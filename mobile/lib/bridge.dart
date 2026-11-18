// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:convert';

import 'package:flutter/services.dart';

import 'l10n.dart';
import 'state_hub.dart';

/// Çekirdeğin (Android tarafındaki Engine) arayüze bildirdiği durum.
class EngineState {
  const EngineState({
    this.phase = 'idle',
    this.message = '',
    this.running = false,
    this.tvClients = 0,
    this.serverPort = 0,
    this.localAddress,
    this.lastSource = '',
    this.lastTranslation = '',
    this.lastRead = '',
    this.frames = 0,
    this.frameWidth = 0,
    this.frameHeight = 0,
    this.translated = 0,
    this.packHits = 0,
    this.packGame = '',
    this.nativeAvailable = true,
    this.demo,
    this.autoRegion,
  });

  /// idle, starting, waking, connecting, streaming, reconnecting, stopping, failed
  final String phase;
  final String message;
  final bool running;
  final int tvClients;
  final int serverPort;
  final String? localAddress;
  final String lastSource;
  final String lastTranslation;
  final String lastRead;
  final int frames;
  final int frameWidth;
  final int frameHeight;
  final int translated;

  /// Oyun paketinden gösterilen satır sayısı ve paketin (oynanan oyunun) adı.
  final int packHits;
  final String packGame;
  final bool nativeAvailable;

  /// PS5'siz deneme çalışıyor mu (yalnız iOS; alan yoksa null).
  final bool? demo;

  /// Otomatik bulunan altyazı alanı (top, bottom, left, right; 0–1); bulunmadıysa null.
  final ({double top, double bottom, double left, double right})? autoRegion;

  static ({double top, double bottom, double left, double right})? _parseAuto(Object? raw) {
    if (raw is! Map) return null;
    final top = (raw['top'] as num?)?.toDouble();
    final bottom = (raw['bottom'] as num?)?.toDouble();
    final left = (raw['left'] as num?)?.toDouble();
    final right = (raw['right'] as num?)?.toDouble();
    if (top == null || bottom == null || left == null || right == null) return null;
    return (top: top, bottom: bottom, left: left, right: right);
  }

  factory EngineState.fromMap(Map<Object?, Object?> map) => EngineState(
        phase: map['phase'] as String? ?? 'idle',
        message: map['message'] as String? ?? '',
        running: map['running'] as bool? ?? false,
        tvClients: (map['tvClients'] as num?)?.toInt() ?? 0,
        serverPort: (map['serverPort'] as num?)?.toInt() ?? 0,
        localAddress: map['localAddress'] as String?,
        lastSource: map['lastSource'] as String? ?? '',
        lastTranslation: map['lastTranslation'] as String? ?? '',
        lastRead: map['lastRead'] as String? ?? '',
        frames: (map['frames'] as num?)?.toInt() ?? 0,
        frameWidth: (map['frameWidth'] as num?)?.toInt() ?? 0,
        frameHeight: (map['frameHeight'] as num?)?.toInt() ?? 0,
        translated: (map['translated'] as num?)?.toInt() ?? 0,
        packHits: (map['packHits'] as num?)?.toInt() ?? 0,
        packGame: map['packGame'] as String? ?? '',
        nativeAvailable: map['nativeAvailable'] as bool? ?? true,
        demo: map['demo'] as bool?,
        autoRegion: _parseAuto(map['autoRegion']),
      );
}

/// Altyazı geçmişindeki bir satır.
class HistoryEntry {
  const HistoryEntry({required this.at, required this.source, required this.text, required this.engine});

  final DateTime at;
  final String source;
  final String text;
  final String engine;
}

/// Önceki çalıştırmada olan çökmenin özeti.
class CrashInfo {
  const CrashInfo({required this.at, required this.kind, required this.name, required this.detail});

  final DateTime at;
  final String kind;
  final String name;
  final String detail;
}

/// Ek okuma alanının tek seferlik okuma sonucu.
class ExtraReadResult {
  const ExtraReadResult({this.ok = false, this.source = '', this.text = '', this.error = ''});

  final bool ok;
  final String source;
  final String text;
  final String error;
}

/// Beklemedeki çeviri motoru: neden ("quota", "key", "busy", "connection") ve kalan süre.
class PausedEngine {
  const PausedEngine({required this.engine, required this.seconds, required this.reason});

  final String engine;
  final int seconds;
  final String reason;
}

/// Sistem durumu ekranının verisi; eksik alanlar varsayılanlarla dolar.
class HealthInfo {
  const HealthInfo({
    this.network = false,
    this.phoneAddress = '',
    this.consoleRegistered = false,
    this.consoleHost = '',
    this.consoleState = '',
    this.streamRunning = false,
    this.fps = 0,
    this.lastReadMs = 0,
    this.readerLanguage = '',
    this.stuckRecoveries = 0,
    this.engine = '',
    this.translatorLastOk = true,
    this.translatorLastError = '',
    this.geminiPausedSeconds = 0,
    this.failoverActive = false,
    this.failoverCurrent = '',
    this.failoverPaused = const [],
    this.tvClients = 0,
    this.tvPort = 0,
    this.packsEnabled = false,
    this.packGame = '',
    this.cacheEntries = 0,
  });

  final bool network;
  final String phoneAddress;
  final bool consoleRegistered;
  final String consoleHost;
  final String consoleState;
  final bool streamRunning;
  final double fps;
  final int lastReadMs;
  final String readerLanguage;
  final int stuckRecoveries;
  final String engine;
  final bool translatorLastOk;
  final String translatorLastError;
  final int geminiPausedSeconds;
  final bool failoverActive;
  final String failoverCurrent;

  /// Kota/anahtar yüzünden beklemedeki motorlar (kalan süreyle).
  final List<PausedEngine> failoverPaused;
  final int tvClients;
  final int tvPort;
  final bool packsEnabled;
  final String packGame;
  final int cacheEntries;

  static Map<Object?, Object?> _sub(Object? value) => value is Map ? value.cast<Object?, Object?>() : const <Object?, Object?>{};

  factory HealthInfo.fromMap(Map<Object?, Object?> map) {
    final console = _sub(map['console']);
    final stream = _sub(map['stream']);
    final reader = _sub(map['reader']);
    final translator = _sub(map['translator']);
    final failover = _sub(translator['failover']);
    final pausedRaw = failover['paused'];
    final tv = _sub(map['tv']);
    final packs = _sub(map['packs']);
    final cache = _sub(map['cache']);
    return HealthInfo(
      network: map['network'] as bool? ?? false,
      phoneAddress: map['phoneAddress'] as String? ?? '',
      consoleRegistered: console['registered'] as bool? ?? false,
      consoleHost: console['host'] as String? ?? '',
      consoleState: console['state'] as String? ?? '',
      streamRunning: stream['running'] as bool? ?? false,
      fps: (stream['fps'] as num?)?.toDouble() ?? 0,
      lastReadMs: (reader['lastReadMs'] as num?)?.toInt() ?? 0,
      readerLanguage: reader['language'] as String? ?? '',
      stuckRecoveries: (reader['stuckRecoveries'] as num?)?.toInt() ?? 0,
      engine: translator['engine'] as String? ?? '',
      translatorLastOk: translator['lastOk'] as bool? ?? true,
      translatorLastError: translator['lastError'] as String? ?? '',
      geminiPausedSeconds: (translator['geminiPausedSeconds'] as num?)?.toInt() ?? 0,
      failoverActive: failover['active'] as bool? ?? false,
      failoverCurrent: failover['current'] as String? ?? '',
      failoverPaused: [
        if (pausedRaw is List)
          for (final item in pausedRaw)
            if (item is Map)
              PausedEngine(
                engine: item['engine'] as String? ?? '',
                seconds: (item['seconds'] as num?)?.toInt() ?? 0,
                reason: item['reason'] as String? ?? '',
              ),
      ],
      tvClients: (tv['clients'] as num?)?.toInt() ?? 0,
      tvPort: (tv['port'] as num?)?.toInt() ?? 0,
      packsEnabled: packs['enabled'] as bool? ?? false,
      packGame: packs['game'] as String? ?? '',
      cacheEntries: (cache['entries'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Kayıtlı PSN hesabı ve eşleştirilmiş PS5.
class SetupInfo {
  const SetupInfo({this.hasAccount = false, this.consoleHost, this.consoleName, this.introSeen = false, this.version = ''});

  final bool hasAccount;
  final String? consoleHost;
  final String? consoleName;
  final bool introSeen;
  final String version;

  bool get hasConsole => consoleHost != null && consoleHost!.isNotEmpty;
  bool get ready => hasAccount && hasConsole;
}

class FoundConsole {
  const FoundConsole(this.host, this.name, this.awake);

  final String host;
  final String name;
  final bool awake;
}

class RegisterResult {
  const RegisterResult(this.ok, this.name, this.detail);

  final bool ok;
  final String? name;
  final String? detail;
}

/// Uygulama ayarları; Android tarafındaki Settings ile aynı alanlar (JSON olarak taşınır).
class AppSettings {
  AppSettings(this.json);

  final Map<String, dynamic> json;

  Map<String, dynamic> get region => (json['region'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get style => (json['style'] as Map).cast<String, dynamic>();

  double regionValue(String edge) => (region[edge] as num).toDouble();
  String get engine => json['engine'] as String? ?? 'google';
  String get targetLanguage => json['targetLanguage'] as String? ?? 'tr';
  String get sourceLanguage => json['sourceLanguage'] as String? ?? 'en';
  String get deepLKey => json['deepLKey'] as String? ?? '';
  String get geminiKey => json['geminiKey'] as String? ?? '';
  String get geminiStyleNote => json['geminiStyleNote'] as String? ?? '';
  bool get engineFailover => json['engineFailover'] as bool? ?? true;
  bool get autoWake => json['autoWake'] as bool? ?? true;
  String get glossary => json['glossary'] as String? ?? '';
  bool get packsEnabled => json['packsEnabled'] as bool? ?? true;
  bool get hideButtonHints => json['hideButtonHints'] as bool? ?? true;
  String get packChoice => json['packChoice'] as String? ?? '';
  String get uiLanguage => json['uiLanguage'] as String? ?? 'auto';
  bool get autoRegion => json['autoRegion'] as bool? ?? false;

  /// Ek okuma alanları (en çok 3): üst, alt, sol, sağ (0–1) ve ad.
  List<Map<String, dynamic>> get extraRegions {
    final raw = json['extraRegions'];
    if (raw is! List) return [];
    return [
      for (final item in raw)
        if (item is Map) item.cast<String, dynamic>(),
    ];
  }

  AppSettings copy() => AppSettings(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
}

/// Android tarafındaki "gt/bridge" ve "gt/events" kanalları.
class Bridge {
  static const _channel = MethodChannel('gt/bridge');
  static const _events = EventChannel('gt/events');

  static final StateHub<EngineState> _hub =
      StateHub<EngineState>((event) => EngineState.fromMap(event as Map<Object?, Object?>));
  static bool _listening = false;

  /// Kanalı uygulama ömrü boyunca tek kez dinler; abonelik hiç iptal edilmez.
  static void _ensureListening() {
    if (_listening) return;
    _listening = true;
    _events.receiveBroadcastStream().listen(_hub.feed, onError: (Object _) {}, cancelOnError: false);
    refreshState();
  }

  /// Paylaşımlı akış: sayfalar kendi aboneliklerini iptal etse de kanal açık kalır.
  static Stream<EngineState> get states {
    _ensureListening();
    return _hub.stream;
  }

  /// Son bilinen durum; henüz olay gelmediyse null.
  static EngineState? get latestState => _hub.latest;

  /// Durumu çekip paylaşımlı dağıtıma verir; hata sessizce geçilir.
  static Future<void> refreshState() async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>('getState');
      if (map != null) _hub.feed(map);
    } catch (_) {}
  }

  static Future<EngineState> state() async =>
      EngineState.fromMap((await _channel.invokeMethod<Map<Object?, Object?>>('getState'))!);

  static Future<SetupInfo> setup() async {
    final map = (await _channel.invokeMethod<Map<Object?, Object?>>('getSetup'))!;
    return SetupInfo(
      hasAccount: map['hasAccount'] as bool? ?? false,
      consoleHost: map['consoleHost'] as String?,
      consoleName: map['consoleName'] as String?,
      introSeen: map['introSeen'] as bool? ?? false,
      version: map['version'] as String? ?? '',
    );
  }

  /// Ayarların uygulamadaki tek ortak kopyası. Bütün ekranlar aynı nesneyi okur ve değiştirir, her kayıt bu nesnenin
  /// tamamını yazar; böylece bir ekranın elindeki eski kopya başka bir ekranın yaptığı değişikliği silemez.
  /// Yerel taraf ayarları kendiliğinden değiştirmez (yalnız setSettings ve resetSettings), bu yüzden bir kez okumak yeter.
  static AppSettings? _settings;

  static Future<AppSettings> settings() async {
    final cached = _settings;
    if (cached != null) return cached;
    final loaded = AppSettings(jsonDecode((await _channel.invokeMethod<String>('getSettings'))!) as Map<String, dynamic>);
    // Aynı anda iki okuma olduysa ilk gelen ortak kopya olur; ikinci de onu döndürür.
    return _settings ??= loaded;
  }

  static Future<void> saveSettings(AppSettings settings) {
    _settings = settings;
    return _channel.invokeMethod('setSettings', jsonEncode(settings.json));
  }

  /// [accountId]: 8 baytlık hesap kimliği.
  static Future<void> setAccountId(Uint8List accountId) => _channel.invokeMethod('setAccountId', base64Encode(accountId));

  static Future<void> setIntroSeen(bool seen) => _channel.invokeMethod('setIntroSeen', seen);
  static Future<void> forgetAccount() => _channel.invokeMethod('forgetAccount');
  static Future<void> forgetConsole() => _channel.invokeMethod('forgetConsole');

  static Future<List<FoundConsole>> discover({List<String> hosts = const [], int timeoutMs = 3000}) async {
    final list = await _channel.invokeMethod<List<Object?>>('discover', {'hosts': hosts, 'timeoutMs': timeoutMs}) ?? [];
    return list.map((item) {
      final map = item as Map<Object?, Object?>;
      return FoundConsole(map['host'] as String, map['name'] as String? ?? 'PS5', map['awake'] as bool? ?? false);
    }).toList();
  }

  static Future<RegisterResult> register(String host, int pin) async {
    final map = (await _channel.invokeMethod<Map<Object?, Object?>>('register', {'host': host, 'pin': pin}))!;
    return RegisterResult(map['ok'] as bool? ?? false, map['name'] as String?, map['detail'] as String?);
  }

  static Future<void> start() => _channel.invokeMethod('start');
  static Future<void> stop() => _channel.invokeMethod('stop');
  static Future<void> testSubtitle() => _channel.invokeMethod('testSubtitle');
  static Future<Uint8List?> snapshot({int width = 960}) => _channel.invokeMethod<Uint8List>('snapshot', width);

  /// Türkçe yaması olan oyunlar (kimlik, başlık, satır sayısı); yalnız iOS.
  static Future<List<({String id, String title, int entries})>> packList() async {
    try {
      final list = await _channel.invokeMethod<List<Object?>>('packList') ?? [];
      return [
        for (final item in list.cast<Map<Object?, Object?>>())
          (id: item['id'] as String, title: item['title'] as String? ?? '', entries: (item['entries'] as num?)?.toInt() ?? 0),
      ];
    } on MissingPluginException {
      return [];
    }
  }

  /// Topluluk yamalarını (GitLab patches/) hemen günceller (yalnız iOS). (başarılı mı, gösterilecek metin)
  static Future<(bool, String)> updatePatches() async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>('updatePatches') ?? {};
      return (map['ok'] as bool? ?? false, map['detail'] as String? ?? '');
    } on MissingPluginException {
      return (false, L.t('Bu telefonda desteklenmiyor.', 'Not supported on this phone.'));
    }
  }

  /// Gemini anahtarını bir deneme çevirisiyle sınar (yalnız iOS). (başarılı mı, gösterilecek metin)
  static Future<(bool, String)> checkGemini(String key) async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>('checkGemini', key) ?? {};
      return (map['ok'] as bool? ?? false, map['detail'] as String? ?? '');
    } on MissingPluginException {
      return (false, L.t('Bu telefonda desteklenmiyor.', 'Not supported on this phone.'));
    }
  }

  /// DeepL anahtarını kota sorgusuyla sınar; çeviri yapmaz, kota harcamaz (yalnız iOS). (başarılı mı, gösterilecek metin)
  static Future<(bool, String)> checkDeepL(String key) async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>('checkDeepL', key) ?? {};
      return (map['ok'] as bool? ?? false, map['detail'] as String? ?? '');
    } on MissingPluginException {
      return (false, L.t('Bu telefonda desteklenmiyor.', 'Not supported on this phone.'));
    }
  }

  /// Adresi tarayıcıda açar (yalnız iOS'ta; Android'de false döner).
  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', url) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Altyazı geçmişi, yeniden eskiye (yalnız iOS; başka yerde boş liste).
  static Future<List<HistoryEntry>> history() async {
    try {
      final list = await _channel.invokeMethod<List<Object?>>('history') ?? [];
      return [
        for (final item in list)
          if (item is Map)
            HistoryEntry(
              at: DateTime.fromMillisecondsSinceEpoch((item['at'] as num?)?.toInt() ?? 0),
              source: item['source'] as String? ?? '',
              text: item['text'] as String? ?? '',
              engine: item['engine'] as String? ?? '',
            ),
      ];
    } on MissingPluginException {
      return [];
    } on PlatformException {
      return [];
    }
  }

  static Future<void> clearHistory() async {
    try {
      await _channel.invokeMethod<void>('clearHistory');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// Bütün ayarları varsayılana döndürür; yeni ayarları döner (yalnız iOS, olmazsa null).
  static Future<AppSettings?> resetSettings() async {
    try {
      final text = await _channel.invokeMethod<String>('resetSettings');
      if (text == null) return null;
      return _settings = AppSettings(jsonDecode(text) as Map<String, dynamic>);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Önceki çalıştırmadaki çökme; yoksa null (yalnız iOS).
  static Future<CrashInfo?> lastCrash() async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>('lastCrash');
      if (map == null) return null;
      return CrashInfo(
        at: DateTime.fromMillisecondsSinceEpoch((map['at'] as num?)?.toInt() ?? 0),
        kind: map['kind'] as String? ?? '',
        name: map['name'] as String? ?? '',
        detail: map['detail'] as String? ?? '',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<void> clearCrash() async {
    try {
      await _channel.invokeMethod<void>('clearCrash');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// Sistem durumu (yalnız iOS; olmazsa null).
  static Future<HealthInfo?> health() async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>('health');
      if (map == null) return null;
      return HealthInfo.fromMap(map);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// PS5'siz deneme: örnek satırlar çevrilip TV'ye gönderilir (yalnız iOS).
  static Future<void> demoStart() async {
    try {
      await _channel.invokeMethod<void>('demoStart');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<void> demoStop() async {
    try {
      await _channel.invokeMethod<void>('demoStop');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// [index]. ek okuma alanını bir kez okuyup çevirir (yalnız iOS).
  static Future<ExtraReadResult> readExtra(int index) async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>('readExtra', index) ?? {};
      return ExtraReadResult(
        ok: map['ok'] as bool? ?? false,
        source: map['source'] as String? ?? '',
        text: map['text'] as String? ?? '',
        error: map['error'] as String? ?? '',
      );
    } on MissingPluginException {
      return ExtraReadResult(error: L.t('Bu telefonda desteklenmiyor.', 'Not supported on this phone.'));
    } on PlatformException {
      return ExtraReadResult(error: L.t('Okunamadı.', 'Could not read.'));
    }
  }

  static Future<List<String>> logs() async =>
      (await _channel.invokeMethod<List<Object?>>('logs') ?? []).cast<String>();
}
