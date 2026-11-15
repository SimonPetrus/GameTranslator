/* SPDX-License-Identifier: AGPL-3.0-only */
/* iOS bağlama kanıtı: libchiaki'nin GameTranslator'da kullanılan işlevlerini (arama, uyandırma, kayıt,
 * oturum) ve PSN/holepunch yolunu (curl, json-c, libevent, miniupnpc) gerçekten çağırır. Amaç
 * çalıştırmak değil; bu dosya iOS arm64 için dinamik kütüphane ve çalıştırılabilir olarak
 * bağlandığında her sembolün statik kütüphanelerden çözüldüğü kanıtlanmış olur.
 * Kullanım biçimi mobile/android/app/src/main/cpp/gt_native.c ile aynıdır. */

#include <chiaki/common.h>
#include <chiaki/discovery.h>
#include <chiaki/log.h>
#include <chiaki/regist.h>
#include <chiaki/session.h>
#include <chiaki/thread.h>
#include <chiaki/time.h>
#include <chiaki/remote/holepunch.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#define GT_EXPORT __attribute__((visibility("default")))

static void gt_log_cb(ChiakiLogLevel level, const char *message, void *user)
{
	(void)level;
	(void)message;
	(void)user;
}

static void gt_discovery_cb(ChiakiDiscoveryHost *host, void *user)
{
	(void)user;
	(void)chiaki_discovery_host_is_ps5(host);
}

static void gt_regist_cb(ChiakiRegistEvent *event, void *user)
{
	(void)event;
	(void)user;
}

static bool gt_pred(void *user)
{
	return *(bool *)user;
}

static void gt_event_cb(ChiakiEvent *event, void *user)
{
	(void)user;
	if(event && event->type == CHIAKI_EVENT_QUIT)
		(void)chiaki_quit_reason_string(event->quit.reason);
}

static bool gt_video_cb(uint8_t *buf, size_t buf_size, int32_t frames_lost, bool frame_recovered, void *user)
{
	(void)buf;
	(void)buf_size;
	(void)frames_lost;
	(void)frame_recovered;
	(void)user;
	return true;
}

/* Arama + uyandırma (cs_discover / cs_wake karşılığı). */
static int gt_probe_discovery(ChiakiLog *log, const char *host)
{
	ChiakiDiscovery discovery;
	if(chiaki_discovery_init(&discovery, log, AF_INET) != CHIAKI_ERR_SUCCESS)
		return -1;
	ChiakiDiscoveryThread thread;
	if(chiaki_discovery_thread_start(&thread, &discovery, gt_discovery_cb, NULL) == CHIAKI_ERR_SUCCESS)
	{
		struct sockaddr_in addr;
		memset(&addr, 0, sizeof(addr));
		addr.sin_family = AF_INET;
		addr.sin_port = htons(CHIAKI_DISCOVERY_PORT_PS5);
		inet_pton(AF_INET, host, &addr.sin_addr);
		char version[] = CHIAKI_DISCOVERY_PROTOCOL_VERSION_PS5;
		ChiakiDiscoveryPacket packet;
		memset(&packet, 0, sizeof(packet));
		packet.cmd = CHIAKI_DISCOVERY_CMD_SRCH;
		packet.protocol_version = version;
		chiaki_discovery_send(&discovery, &packet, (struct sockaddr *)&addr, sizeof(addr));
		(void)chiaki_time_now_monotonic_ms();
		chiaki_discovery_thread_stop(&thread);
	}
	chiaki_discovery_fini(&discovery);
	return (int)chiaki_discovery_wakeup(log, NULL, host, 0, true);
}

/* Kayıt (cs_register karşılığı). */
static int gt_probe_regist(ChiakiLog *log, const char *host)
{
	ChiakiMutex mutex;
	ChiakiCond cond;
	bool done = false;
	if(chiaki_mutex_init(&mutex, false) != CHIAKI_ERR_SUCCESS)
		return -1;
	if(chiaki_cond_init(&cond) != CHIAKI_ERR_SUCCESS)
	{
		chiaki_mutex_fini(&mutex);
		return -1;
	}

	ChiakiRegistInfo info;
	memset(&info, 0, sizeof(info));
	info.target = CHIAKI_TARGET_PS5_1;
	info.host = host;
	info.pin = 12345678;

	ChiakiRegist regist;
	ChiakiErrorCode err = chiaki_regist_start(&regist, log, &info, gt_regist_cb, NULL);
	if(err == CHIAKI_ERR_SUCCESS)
	{
		chiaki_mutex_lock(&mutex);
		err = chiaki_cond_timedwait_pred(&cond, &mutex, 1, gt_pred, &done);
		chiaki_mutex_unlock(&mutex);
		chiaki_regist_stop(&regist);
		chiaki_cond_signal(&cond);
		chiaki_regist_fini(&regist);
	}
	(void)chiaki_error_string(err);
	chiaki_cond_fini(&cond);
	chiaki_mutex_fini(&mutex);
	return (int)err;
}

/* Görüntü akışı oturumu (cs_session_start / cs_session_stop karşılığı). */
static int gt_probe_session(ChiakiLog *log, const char *host)
{
	ChiakiConnectInfo info;
	memset(&info, 0, sizeof(info));
	info.ps5 = true;
	info.host = host;
	chiaki_connect_video_profile_preset(&info.video_profile, CHIAKI_VIDEO_RESOLUTION_PRESET_1080p, CHIAKI_VIDEO_FPS_PRESET_30);
	info.video_profile.codec = CHIAKI_CODEC_H264;
	info.video_profile_auto_downgrade = true;
	info.audio_video_disabled = CHIAKI_AUDIO_DISABLED;
	info.packet_loss_max = 0.05;
	info.enable_idr_on_fec_failure = true;

	ChiakiSession session;
	ChiakiErrorCode err = chiaki_session_init(&session, &info, log);
	if(err != CHIAKI_ERR_SUCCESS)
		return (int)err;
	chiaki_session_set_event_cb(&session, gt_event_cb, NULL);
	chiaki_session_set_video_sample_cb(&session, gt_video_cb, NULL);
	err = chiaki_session_start(&session);
	if(err == CHIAKI_ERR_SUCCESS)
	{
		chiaki_session_stop(&session);
		chiaki_session_join(&session);
	}
	chiaki_session_fini(&session);
	return (int)err;
}

/* PSN üzerinden bağlantı yolu: curl (HTTP/WebSocket), json-c, miniupnpc ve libevent buradan bağlanır. */
static int gt_probe_holepunch(ChiakiLog *log)
{
	ChiakiHolepunchSession hp = chiaki_holepunch_session_init("token", log);
	if(!hp)
		return -1;
	ChiakiErrorCode err = chiaki_holepunch_upnp_discover(hp);
	if(err == CHIAKI_ERR_SUCCESS)
		err = chiaki_holepunch_session_create(hp);
	if(err == CHIAKI_ERR_SUCCESS)
		err = chiaki_holepunch_session_punch_hole(hp, CHIAKI_HOLEPUNCH_PORT_TYPE_CTRL);
	chiaki_holepunch_session_fini(hp);

	ChiakiHolepunchDeviceInfo *devices = NULL;
	size_t count = 0;
	if(chiaki_holepunch_list_devices("token", CHIAKI_HOLEPUNCH_CONSOLE_TYPE_PS5, &devices, &count, log) == CHIAKI_ERR_SUCCESS)
		chiaki_holepunch_free_device_list(&devices);
	return (int)err;
}

/* Dışa açık tek giriş noktası: bağlayıcı bütün çağrı ağacını çözmek zorunda kalır. */
GT_EXPORT int gt_ios_linktest_probe(const char *host)
{
	if(chiaki_lib_init() != CHIAKI_ERR_SUCCESS)
		return -1;
	ChiakiLog log;
	chiaki_log_init(&log, CHIAKI_LOG_ERROR, gt_log_cb, NULL);
	int r = gt_probe_discovery(&log, host);
	r |= gt_probe_regist(&log, host);
	r |= gt_probe_session(&log, host);
	r |= gt_probe_holepunch(&log);
	return r;
}

#ifdef GT_LINKTEST_MAIN
int main(int argc, char **argv)
{
	/* Çalıştırılması amaçlanmadı; yine de güvenli: argüman yoksa hiçbir şey yapmaz. */
	if(argc < 2)
		return 0;
	return gt_ios_linktest_probe(argv[1]) == 0 ? 0 : 1;
}
#endif
