// SPDX-License-Identifier: AGPL-3.0-only
// Telefondan TV uygulaması kurma: Android tarafındaki tvinstall/TvInstallChannel ile konuşan köprü ve hata metinleri.
import 'package:flutter/services.dart';

import 'l10n.dart';

enum TvKind { lg, samsung, android }

extension TvKindText on TvKind {
  String get id => name;

  String get title => switch (this) {
        TvKind.lg => 'LG',
        TvKind.samsung => 'Samsung',
        TvKind.android => 'Android TV / Google TV',
      };
}

TvKind? tvKindOf(String? id) => switch (id) {
      'lg' => TvKind.lg,
      'samsung' => TvKind.samsung,
      'android' => TvKind.android,
      _ => null,
    };

class FoundTv {
  const FoundTv(this.kind, this.host, this.name, this.ready);

  final TvKind kind;
  final String host;
  final String name;

  /// Kurulum portu açık: LG'de geliştirici modu, Android'de hata ayıklama.
  final bool ready;
}

class SavedTv {
  const SavedTv(this.kind, this.host, this.name, this.version);

  final TvKind kind;
  final String host;
  final String name;
  final String? version;
}

class TvCheck {
  const TvCheck(this.ready, this.keyServer, this.hasKey);

  final bool ready;
  final bool keyServer;

  /// LG: bu TV'nin anahtarı kayıtlı, parola yeniden sorulmaz.
  final bool hasKey;
}

class TvInstallResult {
  const TvInstallResult({required this.ok, this.version, this.installed = false, this.launched = false, this.hoursLeft, this.error, this.detail});

  final bool ok;
  final String? version;

  /// false: TV'deki sürüm zaten günceldi, yalnız açıldı.
  final bool installed;
  final bool launched;

  /// LG geliştirici modunun kalan süresi (saat).
  final int? hoursLeft;
  final String? error;
  final String? detail;
}

class TvBridge {
  static const _channel = MethodChannel('gt/tv');
  static const _events = EventChannel('gt/tv/events');

  /// Kurulum aşamaları: connecting, approve, checking, key, `uploading:yüzde`, installing, verifying, launching.
  static Stream<String> get stages => _events.receiveBroadcastStream().map((event) => ((event as Map)['stage'] as String?) ?? '');

  /// Uygulamayla gelen TV paketlerinin sürümleri (marka → sürüm).
  static Future<Map<TvKind, String>> bundled() async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>('bundled') ?? {};
    final result = <TvKind, String>{};
    for (final entry in map.entries) {
      final kind = tvKindOf(entry.key as String?);
      if (kind != null) result[kind] = entry.value as String;
    }
    return result;
  }

  static Future<String?> phoneAddress() => _channel.invokeMethod<String>('phoneAddress');

  static Future<SavedTv?> saved() async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>('saved');
    final kind = tvKindOf(map?['brand'] as String?);
    if (map == null || kind == null) return null;
    return SavedTv(kind, map['host'] as String? ?? '', map['name'] as String? ?? '', map['version'] as String?);
  }

  static Future<void> forget() => _channel.invokeMethod('forget');

  /// Elle yazılan adresi temizler; adres değilse null.
  static Future<String?> normalize(String text) => _channel.invokeMethod<String>('normalize', text);

  static Future<List<FoundTv>> find(TvKind kind) async {
    final list = await _channel.invokeMethod<List<Object?>>('find', kind.id) ?? [];
    return [
      for (final item in list.cast<Map<Object?, Object?>>())
        FoundTv(kind, item['host'] as String, item['name'] as String? ?? kind.title, item['ready'] as bool? ?? false),
    ];
  }

  static Future<TvCheck> check(TvKind kind, String host) async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>('check', {'brand': kind.id, 'host': host}) ?? {};
    return TvCheck(map['ready'] as bool? ?? false, map['keyServer'] as bool? ?? false, map['hasKey'] as bool? ?? false);
  }

  static Future<TvInstallResult> install(TvKind kind, String host, {String name = '', String? passphrase, bool force = false}) async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>(
          'install',
          {'brand': kind.id, 'host': host, 'name': name, 'passphrase': passphrase, 'force': force},
        ) ??
        {};
    return TvInstallResult(
      ok: map['ok'] as bool? ?? false,
      version: map['version'] as String?,
      installed: map['installed'] as bool? ?? false,
      launched: map['launched'] as bool? ?? false,
      hoursLeft: (map['hoursLeft'] as num?)?.toInt(),
      error: map['error'] as String?,
      detail: map['detail'] as String?,
    );
  }

  static Future<void> cancel() => _channel.invokeMethod('cancel');
}

/// Hatanın sade dilde açıklaması ve çözümü (Windows'taki TvAppCard.Message ile aynı durumlar).
({String title, String fix}) tvErrorText(String? error, TvKind kind) {
  final android = kind == TvKind.android;
  return switch (error) {
    'UNREACHABLE' => android
        ? (
            title: L.t('TV yanıt vermedi', 'The TV did not respond'),
            fix: L.t(
              'TV açık mı ve telefonla aynı Wi-Fi ağında mı? Geliştirici seçeneklerinde "USB hata ayıklama" açık olmalı. '
                  'Bazı TV\'lerde bu ayar TV yeniden başlayınca kapanır; açıp yeniden dene.',
              'Is the TV on and on the same Wi-Fi network as your phone? "USB debugging" must be enabled in Developer options. '
                  'On some TVs this setting turns off when the TV restarts; turn it on again and retry.',
            ),
          )
        : (
            title: L.t('TV yanıt vermedi', 'The TV did not respond'),
            fix: L.t(
              'TV açık mı ve telefonla aynı Wi-Fi ağında mı? Developer Mode uygulamasında "Dev Mode Status" açık olmalı; '
                  'açtıktan sonra TV yeniden başlar, açılmasını bekle.',
              'Is the TV on and on the same Wi-Fi network as your phone? "Dev Mode Status" must be on in the Developer Mode app; '
                  'the TV restarts after you turn it on, so wait for it to come back.',
            ),
          ),
    'KEY_SERVER_OFF' => (
        title: L.t('Key Server kapalı', 'Key Server is off'),
        fix: L.t(
          'TV\'de Developer Mode uygulamasını aç, "Key Server"ı aç ve uygulamayı ekranda bırak. Sonra yeniden dene.',
          'Open the Developer Mode app on the TV, turn on "Key Server" and leave the app on screen. Then retry.',
        ),
      ),
    'WRONG_PASSPHRASE' => (
        title: L.t('Parola doğru değil', 'Wrong passphrase'),
        fix: L.t(
          'TV ekranında Developer Mode uygulamasının sol altındaki 6 karakterlik "Passphrase"i yeniden yaz. '
              '0 (sıfır) ile O harfi, 1 ile I harfi karışabilir.',
          'Type the 6-character "Passphrase" shown at the bottom left of the Developer Mode app on the TV again. '
              'The digit 0 and the letter O, or the digit 1 and the letter I, are easy to mix up.',
        ),
      ),
    'KEY_REFUSED' => (
        title: L.t('TV anahtarı kabul etmedi', 'The TV rejected the key'),
        fix: L.t(
          'Geliştirici modu kapatılıp açıldıysa TV yeni bir anahtar üretir. Key Server\'ı açıp parolayı yeniden yaz.',
          'If Developer Mode was turned off and on, the TV generates a new key. Turn on Key Server and enter the passphrase again.',
        ),
      ),
    'NOT_APPROVED' => (
        title: L.t('TV\'de izin verilmedi', 'Not allowed on the TV'),
        fix: L.t(
          'Yeniden dene. TV\'de "USB hata ayıklamaya izin verilsin mi?" sorusu çıkınca "Bu bilgisayardan her zaman izin ver"i '
              'işaretleyip "İzin ver"i seç. Soru TV ekranında yaklaşık bir buçuk dakika bekler.',
          'Retry. When the TV asks "Allow USB debugging?", tick "Always allow from this computer" '
              'and choose "Allow". The prompt stays on the TV screen for about a minute and a half.',
        ),
      ),
    'NOT_ENOUGH_SPACE' => (
        title: L.t('TV\'de yer kalmamış', 'The TV is out of space'),
        fix: L.t(
          'TV\'den kullanmadığın bir uygulamayı kaldır ve yeniden dene.',
          'Remove an app you do not use from the TV and retry.',
        ),
      ),
    'CONNECTION_LOST' => (
        title: L.t('Bağlantı koptu', 'Connection lost'),
        fix: L.t(
          'Kurulum sırasında TV ile bağlantı kesildi. Telefonun ekranı açık ve Wi-Fi\'ye bağlı kalsın; yeniden dene.',
          'The connection to the TV dropped during installation. Keep your phone screen on and connected to Wi-Fi, then retry.',
        ),
      ),
    'TOO_OLD' => (
        title: L.t('Bu TV çok eski', 'This TV is too old'),
        fix: L.t(
          'GameTranslator TV uygulaması bu TV\'nin yazılımında çalışmıyor.',
          'The GameTranslator TV app does not work on this TV\'s software.',
        ),
      ),
    'PACKAGE_MISSING' => (
        title: L.t('TV paketi bulunamadı', 'TV package not found'),
        fix: L.t(
          'Bu telefon uygulamasının içinde TV paketi yok. Uygulamanın son sürümünü kur.',
          'This phone app does not include the TV package. Install the latest version of the app.',
        ),
      ),
    'CANCELLED' => (
        title: L.t('Kurulum durduruldu', 'Installation stopped'),
        fix: L.t('Hazır olduğunda yeniden başlatabilirsin.', 'You can start it again when you are ready.'),
      ),
    _ => (
        title: L.t('TV uygulaması kurulamadı', 'Could not install the TV app'),
        fix: L.t(
          'Yeniden dene. TV\'yi kapatıp açmak yarım kalan kurulumların çoğunu düzeltir. Yine olmazsa aşağıdaki "TV\'nin söylediği" '
              'yazısıyla birlikte bize bildir.',
          'Retry. Turning the TV off and on fixes most interrupted installs. If it still fails, report it to us '
              'together with the "What the TV said" text below.',
        ),
      ),
  };
}

/// Kurulum aşamasının adı.
String tvStageText(String stage) {
  if (stage.startsWith('uploading:')) {
    final percent = stage.substring(10);
    return L.t('Uygulama TV\'ye gönderiliyor… %$percent', 'Sending the app to the TV… $percent%');
  }
  return switch (stage) {
    'connecting' => L.t('TV\'ye bağlanılıyor…', 'Connecting to the TV…'),
    'approve' => L.t('TV\'de izin bekleniyor…', 'Waiting for approval on the TV…'),
    'checking' => L.t('TV\'deki sürüme bakılıyor…', 'Checking the version on the TV…'),
    'key' => L.t('TV\'den anahtar alınıyor…', 'Getting the key from the TV…'),
    'installing' => L.t('TV\'ye kuruluyor…', 'Installing on the TV…'),
    'verifying' => L.t('Kurulum doğrulanıyor…', 'Verifying the installation…'),
    'launching' => L.t('TV\'de açılıyor…', 'Opening on the TV…'),
    _ => L.t('Hazırlanıyor…', 'Preparing…'),
  };
}
