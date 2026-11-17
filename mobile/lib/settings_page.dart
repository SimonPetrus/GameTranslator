// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';
import 'dart:convert';

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'bridge.dart';
import 'extra_region_page.dart';
import 'health_page.dart';
import 'history_page.dart';
import 'home_page.dart';
import 'intro_page.dart';
import 'main.dart';
import 'tv_install_page.dart';
import 'ui.dart';

/// Ayarlar sekmesi, iOS ayarları düzeninde: çeviri, altyazı bölgesi, TV'deki görünüm, PS5 ve hakkında.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.setup, required this.onSetupChanged, required this.active});

  final SetupInfo setup;
  final Future<void> Function() onSetupChanged;

  /// Sekme ekranda mı? Arkadayken oyun görüntüsü istenmez.
  final bool active;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  static const languages = {
    'tr': 'Türkçe',
    'en': 'İngilizce',
    'de': 'Almanca',
    'fr': 'Fransızca',
    'es': 'İspanyolca',
    'it': 'İtalyanca',
    'pt': 'Portekizce',
    'ru': 'Rusça',
    'ar': 'Arapça',
    'ja': 'Japonca',
    'zh': 'Çince',
    'ko': 'Korece',
    'pl': 'Lehçe',
    'nl': 'Felemenkçe',
    'id': 'Endonezce',
    'hi': 'Hintçe',
    'fa': 'Farsça',
    'uk': 'Ukraynaca',
    'el': 'Yunanca',
    'hu': 'Macarca',
    'ro': 'Romence',
    'cs': 'Çekçe',
    'sv': 'İsveççe',
    'th': 'Tayca',
    'vi': 'Vietnamca',
    'he': 'İbranice',
    'az': 'Azerice',
  };

  static const flags = {
    'tr': '🇹🇷',
    'en': '🇬🇧',
    'de': '🇩🇪',
    'fr': '🇫🇷',
    'es': '🇪🇸',
    'it': '🇮🇹',
    'pt': '🇵🇹',
    'ru': '🇷🇺',
    'ar': '🇸🇦',
    'ja': '🇯🇵',
    'zh': '🇨🇳',
    'ko': '🇰🇷',
    'pl': '🇵🇱',
    'nl': '🇳🇱',
    'id': '🇮🇩',
    'hi': '🇮🇳',
    'fa': '🇮🇷',
    'uk': '🇺🇦',
    'el': '🇬🇷',
    'hu': '🇭🇺',
    'ro': '🇷🇴',
    'cs': '🇨🇿',
    'sv': '🇸🇪',
    'th': '🇹🇭',
    'vi': '🇻🇳',
    'he': '🇮🇱',
    'az': '🇦🇿',
  };

  /// Gemini modelleri (ai-models.json); ilki varsayılandır.
  static const geminiModels = {
    'gemini-3.5-flash-lite': 'Hızlı ve ucuz (önerilen)',
    'gemini-3.6-flash': 'Daha iyi çeviri, biraz yavaş',
  };

  static const placements = {
    'cover': 'Oyunun altyazısını örterek',
    'above': 'Oyunun altyazısının üstünde',
    'below': 'Oyunun altyazısının altında',
    'fixed': 'Ekranın altında sabit',
  };

  static const edges = {'top': 'Üst', 'bottom': 'Alt', 'left': 'Sol', 'right': 'Sağ'};
  static const defaultRegion = {'top': 0.62, 'bottom': 0.97, 'left': 0.14, 'right': 0.86};

  /// Tek dokunuşla bölge seçimleri (Windows'taki Alt/Üst/Tam seçimlerinin genişletilmişi). "Özel" hiçbiriyle eşleşmeyen değerlerdir.
  static const regionPresets = <(String, Map<String, double>)>[
    ('Alt orta (standart)', {'top': 0.62, 'bottom': 0.97, 'left': 0.14, 'right': 0.86}),
    ('Alt yarı', {'top': 0.50, 'bottom': 0.98, 'left': 0.05, 'right': 0.95}),
    ('Geniş alt bant', {'top': 0.70, 'bottom': 0.98, 'left': 0.03, 'right': 0.97}),
    ('Üst bölge', {'top': 0.03, 'bottom': 0.30, 'left': 0.10, 'right': 0.90}),
    ('Tam ekran', {'top': 0.02, 'bottom': 0.98, 'left': 0.02, 'right': 0.98}),
  ];

  /// Geçerli bölgeyle eşleşen hazır seçimin adı; yoksa 'Özel'.
  String matchingPreset(AppSettings s) {
    for (final (name, values) in regionPresets) {
      if (values.entries.every((e) => (s.regionValue(e.key) - e.value).abs() <= 0.006)) return name;
    }
    return 'Özel';
  }

  AppSettings? settings;
  final deepLController = TextEditingController();
  final geminiController = TextEditingController();
  bool checkingGemini = false;
  bool updatingPatches = false;
  (bool, String)? patchesResult;

  /// Bilgisayar sürümündeki "Oyun" seçimi: en üstte Otomatik, altında Türkçe yaması olan oyunlar.
  Future<void> pickGame() async {
    final games = await Bridge.packList();
    if (!mounted) return;
    final options = <String, String>{'': 'Otomatik (oyunu kendisi bulur)'};
    for (final game in games) {
      options[game.id] = '${game.title} · ${game.entries} satır';
    }
    final picked = await showApplePicker(context, title: 'Oyun', options: options, selected: settings?.packChoice ?? '');
    if (picked != null) change((s) => s.json['packChoice'] = picked);
    if (games.isNotEmpty) setState(() => gameTitles = {for (final game in games) game.id: game.title});
  }

  Map<String, String> gameTitles = {};

  /// Paket listesi henüz alınmadıysa kimlikten okunur ad: "mafia-the-old-country" → "Mafia The Old Country".
  static String titleFromId(String id) => id
      .split(RegExp('[-_]'))
      .where((w) => w.isNotEmpty)
      .map((w) => RegExp(r'^(ii|iii|iv|v|vi|vii|viii|ix|x|xi|xii)$').hasMatch(w) ? w.toUpperCase() : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  Future<void> updatePatches() async {
    setState(() {
      updatingPatches = true;
      patchesResult = null;
    });
    final result = await Bridge.updatePatches();
    if (!mounted) return;
    setState(() {
      updatingPatches = false;
      patchesResult = result;
    });
  }
  (bool, String)? geminiResult;

  /// Anahtarı hemen kaydeder ve bir deneme çevirisiyle sınar.
  Future<void> checkGemini() async {
    final current = settings;
    if (current == null) return;
    current.json['geminiKey'] = geminiController.text.trim();
    saveTimer?.cancel();
    setState(() {
      checkingGemini = true;
      geminiResult = null;
    });
    await Bridge.saveSettings(current);
    final result = await Bridge.checkGemini(geminiController.text.trim());
    if (!mounted) return;
    setState(() {
      checkingGemini = false;
      geminiResult = result;
    });
  }
  Uint8List? preview;
  Timer? saveTimer;
  Timer? previewTimer;
  StreamSubscription<EngineState>? stateSubscription;

  /// Önceki çalıştırmadaki çökme (yalnız iOS).
  CrashInfo? crash;

  /// PS5'siz deneme açık mı (yalnız iOS).
  bool demoOn = false;

  /// Altyazı bölgesinde sürgünün ayarladığı kenar.
  String edge = 'top';

  @override
  void initState() {
    super.initState();
    load();
    if (Platform.isIOS) {
      loadIosExtras();
      stateSubscription = Bridge.states.listen((next) {
        final demo = next.demo;
        if (mounted && demo != null && demo != demoOn) setState(() => demoOn = demo);
      });
    }
    // Bölge ayarlanırken oyun görüntüsü güncel kalsın.
    previewTimer = Timer.periodic(const Duration(seconds: 2), (_) => refreshPreview());
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    previewTimer?.cancel();
    stateSubscription?.cancel();
    final current = settings;
    if (current != null) Bridge.saveSettings(current);
    deepLController.dispose();
    geminiController.dispose();
    super.dispose();
  }

  /// iOS'a özgü bilgiler: önceki çökme ve deneme durumu.
  Future<void> loadIosExtras() async {
    final lastCrash = await Bridge.lastCrash();
    bool? demo;
    try {
      demo = (await Bridge.state()).demo;
    } on Object {
      demo = null;
    }
    if (!mounted) return;
    setState(() {
      crash = lastCrash;
      if (demo != null) demoOn = demo;
    });
  }

  Future<void> setDemo(bool on) async {
    setState(() => demoOn = on);
    if (on) {
      await Bridge.demoStart();
    } else {
      await Bridge.demoStop();
    }
  }

  Future<void> resetAll() async {
    final confirmed = await confirmApple(
      context,
      title: 'Bütün ayarlar sıfırlansın mı?',
      message: 'Çeviri, bölge, görünüm ve sözlük ayarları varsayılana döner. '
          'PS5 eşleştirmesi, PSN hesabı ve API anahtarların korunur.',
      action: 'Sıfırla',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    saveTimer?.cancel();
    final fresh = await Bridge.resetSettings();
    if (!mounted) return;
    if (fresh == null) {
      toast(context, 'Ayarlar sıfırlanamadı.');
      return;
    }
    setState(() {
      settings = fresh;
      deepLController.text = fresh.deepLKey;
      geminiController.text = fresh.geminiKey;
    });
    toast(context, 'Ayarlar sıfırlandı.');
  }

  String crashTime(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.day)}.${two(at.month)}.${at.year} ${clockText(at)}';
  }

  void showCrash() {
    final info = crash;
    if (info == null) return;
    final report = '${crashTime(info.at)}\n${info.kind}: ${info.name}\n\n${info.detail}';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (sheet, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            const Text('Önceki çalıştırma çöktü', style: Txt.title2),
            const SizedBox(height: 4),
            Text('${crashTime(info.at)} · ${info.name}', style: Txt.footnote.copyWith(color: Tokens.textSecondary)),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: report));
                    toast(context, 'Çökme bilgisi kopyalandı.');
                  },
                  child: const Text('Kopyala'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(sheet).pop();
                    await Bridge.clearCrash();
                    if (mounted) setState(() => crash = null);
                  },
                  child: const Text('Sil', style: TextStyle(color: Tokens.danger)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              info.detail.isEmpty ? 'Ayrıntı yok.' : info.detail,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Tokens.textSecondary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  /// Ek okuma alanını düzenleme sayfasında açar; kaydedilince ya da silinince ayarlara işler.
  Future<void> editExtra(int index) async {
    final current = settings;
    if (current == null) return;
    final regions = current.extraRegions;
    if (index < 0 || index >= regions.length) return;
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      appleRoute((_) => ExtraRegionPage(initial: regions[index], image: preview)),
    );
    if (result == null) return;
    change((s) {
      final list = s.extraRegions;
      if (index >= list.length) return;
      if (result['delete'] == true) {
        list.removeAt(index);
      } else {
        list[index] = result;
      }
      s.json['extraRegions'] = list;
    });
  }

  Future<void> addExtra() async {
    final current = settings;
    if (current == null || current.extraRegions.length >= 3) return;
    final count = current.extraRegions.length;
    change((s) {
      s.json['extraRegions'] = [
        ...s.extraRegions,
        {'top': 0.05, 'bottom': 0.25, 'left': 0.10, 'right': 0.90, 'name': 'Alan ${count + 1}'},
      ];
    });
    await editExtra(count);
  }

  Future<void> load() async {
    final loaded = await Bridge.settings();
    final image = await Bridge.snapshot(width: 640);
    if (!mounted) return;
    setState(() {
      settings = loaded;
      preview = image;
      deepLController.text = loaded.deepLKey;
      geminiController.text = loaded.geminiKey;
    });
  }

  Future<void> refreshPreview() async {
    if (!mounted || !widget.active) return;
    final image = await Bridge.snapshot(width: 640);
    if (mounted && image != null) setState(() => preview = image);
  }

  /// Değişiklik hemen ekrana yansır; kaydetme sürgü sürüklenirken her adımda değil, kısa bir aradan sonra yapılır.
  void change(void Function(AppSettings) edit) {
    final current = settings;
    if (current == null) return;
    setState(() => edit(current));
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 300), () => Bridge.saveSettings(current));
  }

  Widget _presetChip(String label, {required bool selected, VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Tokens.accent : Tokens.inset,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(label, style: Txt.subhead.copyWith(fontFamily: 'Inter', color: Colors.white, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
        ),
      );

  void setRegion(String edge, double value) => change((s) {
        final region = s.region;
        region[edge] = value;
        // Bölge en az %5 yüksekliğinde ve genişliğinde kalır.
        if (edge == 'top' && region['bottom'] < value + 0.05) region['bottom'] = (value + 0.05).clamp(0.0, 1.0);
        if (edge == 'bottom' && region['top'] > value - 0.05) region['top'] = (value - 0.05).clamp(0.0, 1.0);
        if (edge == 'left' && region['right'] < value + 0.05) region['right'] = (value + 0.05).clamp(0.0, 1.0);
        if (edge == 'right' && region['left'] > value - 0.05) region['left'] = (value - 0.05).clamp(0.0, 1.0);
        s.json['region'] = region;
      });

  void setStyle(String key, Object value) => change((s) {
        final style = s.style;
        style[key] = value;
        s.json['style'] = style;
      });

  /// Oyunun dili: ekran okuma (Vision) yalnız bunları okuyabilir.
  static const sourceCodes = ['en', 'ja', 'zh', 'ko', 'de', 'fr', 'es', 'it', 'pt', 'ru', 'uk', 'ar', 'th', 'vi', 'tr'];

  Future<void> pickLanguage(String key, String title, {Iterable<String>? only}) async {
    final options = only == null ? languages : {for (final code in only) code: languages[code] ?? code};
    final picked = await showApplePicker(context, title: title, options: options, selected: settings?.json[key] as String?, leading: flags);
    if (picked != null) change((s) => s.json[key] = picked);
  }

  Future<void> pickGeminiModel() async {
    final picked = await showApplePicker(context, title: 'Gemini modeli', options: geminiModels, selected: geminiModelId);
    if (picked != null) change((s) => s.json['geminiModel'] = picked);
  }

  String get geminiModelId {
    final id = settings?.json['geminiModel'] as String?;
    return geminiModels.containsKey(id) ? id! : geminiModels.keys.first;
  }

  Future<void> pickPlacement() async {
    final picked = await showApplePicker(context, title: 'Altyazının yeri', options: placements, selected: settings?.style['placement'] as String?);
    if (picked != null) setStyle('placement', picked);
  }

  Future<void> editGlossary() async {
    final current = settings;
    if (current == null) return;
    final text = await Navigator.of(context).push<String>(appleRoute((_) => GlossaryPage(initial: current.glossary)));
    if (text != null) change((s) => s.json['glossary'] = text);
  }

  Future<void> sendTest() async {
    await Bridge.testSubtitle();
    if (mounted) toast(context, 'Deneme altyazısı gönderildi.');
  }

  Future<void> confirmForget({required bool account}) async {
    final confirmed = await confirmApple(
      context,
      title: account ? 'PSN hesabı değiştirilsin mi?' : 'PS5 yeniden eşleştirilsin mi?',
      message: account
          ? 'Kayıtlı hesap ve PS5 eşleştirmesi silinir; kurulumu baştan yaparsın.'
          : 'Kayıtlı eşleştirme silinir; PS5\'teki "Cihaz Eşleştir" koduyla yeniden eşleştirirsin.',
      action: 'Sil ve Devam Et',
      destructive: true,
    );
    if (!confirmed) return;
    await Bridge.stop();
    if (account) {
      await Bridge.forgetAccount();
    } else {
      await Bridge.forgetConsole();
    }
    await widget.onSetupChanged();
  }

  void showIntro() {
    Navigator.of(context).push(appleRoute<void>((context) => IntroPage(replay: true, onDone: () async => Navigator.of(context).pop())));
  }

  Future<void> showLogs() async {
    final lines = await Bridge.logs();
    if (!mounted) return;
    final text = lines.isEmpty ? 'Henüz kayıt yok.' : lines.reversed.join('\n');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (sheet, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Row(
              children: [
                const Expanded(child: Text('Günlük', style: Txt.title2)),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    Navigator.of(sheet).pop();
                    toast(context, 'Günlük kopyalandı.');
                  },
                  child: const Text('Kopyala'),
                ),
              ],
            ),
            Text('Bir sorun olduğunda destek için bu kayıtları paylaşabilirsin.', style: Txt.footnote.copyWith(color: Tokens.textSecondary)),
            const SizedBox(height: 12),
            SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Tokens.textSecondary, height: 1.45)),
          ],
        ),
      ),
    );
  }

  String get glossarySummary {
    final (terms, keep, problem) = GlossaryPage.inspect(settings?.glossary ?? '');
    if (problem != null) return 'Hatalı';
    if (terms + keep == 0) return 'Boş';
    return '${terms + keep} terim';
  }

  @override
  Widget build(BuildContext context) {
    final s = settings;
    if (s == null) return const Center(child: CupertinoActivityIndicator(radius: 14));
    final style = s.style;
    return LargeTitleList(
      title: 'Ayarlar',
      children: [
        if (Platform.isIOS && crash != null) ...[
          Group(
            inset: 60,
            children: [
              Cell(
                icon: CupertinoIcons.exclamationmark_triangle_fill,
                iconColor: Tokens.danger,
                title: 'Önceki çalıştırma çöktü',
                subtitle: '${crashTime(crash!.at)} · ${crash!.name}',
                chevron: true,
                onTap: showCrash,
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        // ---------------------------------------------------------------- Çeviri
        const GroupHeader('ÇEVİRİ'),
        Group(
          inset: 60,
          children: [
            Cell(
              icon: CupertinoIcons.gamecontroller_fill,
              iconColor: Tokens.indigo,
              title: 'Oyunun dili',
              value: '${flags[s.sourceLanguage] ?? ''} ${languages[s.sourceLanguage] ?? s.sourceLanguage}',
              chevron: true,
              onTap: () => pickLanguage('sourceLanguage', 'Oyunun dili', only: sourceCodes),
            ),
            Cell(
              icon: CupertinoIcons.globe,
              iconColor: Tokens.accent,
              title: 'Çeviri dili',
              value: '${flags[s.targetLanguage] ?? ''} ${languages[s.targetLanguage] ?? s.targetLanguage}',
              chevron: true,
              onTap: () => pickLanguage('targetLanguage', 'Çeviri dili'),
            ),
            if (s.sourceLanguage == 'en' && s.targetLanguage == 'tr')
              Cell(
                icon: CupertinoIcons.book_fill,
                iconColor: Tokens.warning,
                title: 'Terim sözlüğü',
                value: glossarySummary,
                chevron: true,
                onTap: editGlossary,
              ),
            if (s.sourceLanguage == 'en' && s.targetLanguage == 'tr')
              Cell(
                icon: CupertinoIcons.cube_box_fill,
                iconColor: Tokens.success,
                title: 'Oyun paketleri',
                subtitle: 'GTA V, RDR2, Elden Ring… satırları hazır Türkçesiyle',
                trailing: CupertinoSwitch(
                  value: s.packsEnabled,
                  activeTrackColor: Tokens.success,
                  onChanged: (value) => change((s) => s.json['packsEnabled'] = value),
                ),
              ),
            if (Platform.isIOS && s.packsEnabled && s.sourceLanguage == 'en' && s.targetLanguage == 'tr')
              Cell(
                icon: CupertinoIcons.gamecontroller_fill,
                iconColor: Tokens.accent,
                title: 'Oyun',
                value: s.packChoice.isEmpty ? 'Otomatik' : (gameTitles[s.packChoice] ?? titleFromId(s.packChoice)),
                chevron: true,
                onTap: pickGame,
              ),
            if (Platform.isIOS && s.packsEnabled && s.sourceLanguage == 'en' && s.targetLanguage == 'tr')
              Cell(
                icon: CupertinoIcons.arrow_down_circle_fill,
                iconColor: Tokens.success,
                title: updatingPatches ? 'Yamalar denetleniyor…' : 'Topluluk yamalarını güncelle',
                subtitle: patchesResult?.$2 ?? 'Yeni ve güncellenen oyun yamalarını indirir (haftada bir kendiliğinden)',
                onTap: updatingPatches ? null : updatePatches,
              ),
            if (Platform.isIOS)
              Cell(
                icon: CupertinoIcons.game_controller_solid,
                iconColor: Tokens.accent,
                title: 'Tuş yazılarını gizle',
                subtitle: 'Altyazının yanındaki "SKIP", "RESUME" gibi düğme yazıları çevrilmez',
                trailing: CupertinoSwitch(
                  value: s.hideButtonHints,
                  activeTrackColor: Tokens.success,
                  onChanged: (value) => change((s) => s.json['hideButtonHints'] = value),
                ),
              ),
          ],
        ),
        if (s.sourceLanguage == 'en' && s.targetLanguage == 'tr')
          const GroupFooter('Oyunun paketinde bulunan satır çeviri motoruna gitmeden paketteki Türkçesiyle gösterilir. '
              'Paketler CouchSubs topluluğundan gelir ve haftada bir yenilenir.'),
        const GroupHeader('ÇEVİRİ MOTORU'),
        Group(
          children: [
            Cell(
              title: 'Google',
              subtitle: 'İnternet ister, anahtar gerekmez. Çoğu oyun için önerilir.',
              checked: s.engine == 'google',
              onTap: () => change((s) => s.json['engine'] = 'google'),
            ),
            Cell(
              title: 'DeepL',
              subtitle: 'Daha doğal cümleler; kendi DeepL API anahtarınla çalışır.',
              checked: s.engine == 'deepl',
              onTap: () => change((s) => s.json['engine'] = 'deepl'),
            ),
            if (s.engine == 'deepl')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: TextField(
                  controller: deepLController,
                  autocorrect: false,
                  decoration: const InputDecoration(hintText: 'DeepL API anahtarı'),
                  onChanged: (value) => change((s) => s.json['deepLKey'] = value.trim()),
                ),
              ),
            // Yapay zekâ çevirisi (bilgisayar sürümündeki gibi); şimdilik yalnız iPhone'da.
            if (Platform.isIOS)
              Cell(
                title: 'Google Gemini',
                subtitle: 'Yapay zekâ ile en doğal Türkçe. Ücretsiz anahtarla çalışır; sınır dolunca bir dakika Google kullanılır.',
                checked: s.engine == 'gemini',
                onTap: () => change((s) => s.json['engine'] = 'gemini'),
              ),
            if (Platform.isIOS && s.engine == 'gemini')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: geminiController,
                      autocorrect: false,
                      obscureText: true,
                      decoration: const InputDecoration(hintText: 'Gemini API anahtarı'),
                      onChanged: (value) => change((s) => s.json['geminiKey'] = value.trim()),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: checkingGemini ? null : checkGemini,
                      child: Text(checkingGemini ? 'Deneniyor…' : 'Kaydet ve dene'),
                    ),
                    if (geminiResult != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          geminiResult!.$2,
                          style: Txt.subhead.copyWith(color: geminiResult!.$1 ? Tokens.success : Tokens.danger),
                        ),
                      ),
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                      onPressed: () => Bridge.openUrl('https://aistudio.google.com/apikey'),
                      child: const Text('Ücretsiz Google Gemini API anahtarı al'),
                    ),
                  ],
                ),
              ),
            if (Platform.isIOS && s.engine == 'gemini')
              Cell(
                title: 'Gemini modeli',
                subtitle: geminiModels[geminiModelId] ?? '',
                chevron: true,
                onTap: pickGeminiModel,
              ),
            Cell(
              title: 'Cihazda',
              subtitle: Platform.isIOS
                  ? 'İnternetsiz çalışır (Apple Çeviri). Önce iPhone\'da Ayarlar › Uygulamalar › Çeviri › İndirilen Diller\'den İngilizce ve Türkçe\'yi indir.'
                  : 'İnternetsiz çalışır; kalitesi daha düşüktür. Dil modeli bir kez iner.',
              checked: s.engine == 'mlkit',
              onTap: () => change((s) => s.json['engine'] = 'mlkit'),
            ),
          ],
        ),
        const GroupFooter('İnternet koparsa çeviri kendiliğinden cihazdaki modele geçer. DeepL anahtarı boşsa ya da çalışmazsa Google kullanılır.'),

        // ---------------------------------------------------------------- Altyazı bölgesi
        const GroupHeader('ALTYAZI BÖLGESİ'),
        Glass(
          clip: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (preview != null) RegionPreview(image: preview!, settings: s, subtitle: 'Örnek altyazı') else _RegionPlaceholder(settings: s),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in [...regionPresets.map((p) => p.$1), 'Özel'])
                      _presetChip(
                        name,
                        selected: matchingPreset(s) == name,
                        onTap: name == 'Özel'
                            ? null
                            : () => change((s) => s.json['region'] = Map<String, dynamic>.from(regionPresets.firstWhere((p) => p.$1 == name).$2)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: CupertinoSlidingSegmentedControl<String>(
                  groupValue: edge,
                  backgroundColor: Tokens.inset,
                  thumbColor: const Color(0xFF636366),
                  children: {
                    for (final entry in edges.entries)
                      entry.key: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Text(entry.value, style: Txt.subhead.copyWith(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w500)),
                      ),
                  },
                  onValueChanged: (value) => setState(() => edge = value ?? edge),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoSlider(
                        value: s.regionValue(edge).clamp(0.0, 1.0),
                        activeColor: Tokens.accent,
                        onChanged: (value) => setRegion(edge, (value * 100).round() / 100),
                      ),
                    ),
                    SizedBox(
                      width: 46,
                      child: Text('%${(s.regionValue(edge) * 100).round()}', textAlign: TextAlign.end, style: Txt.body.copyWith(color: Tokens.textSecondary)),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Cell(title: 'Varsayılana Dön', titleColor: Tokens.accent, onTap: () => change((s) => s.json['region'] = Map<String, dynamic>.from(defaultRegion))),
            ],
          ),
        ),
        const GroupFooter('Mavi çerçeveyi oyunun altyazısının çıktığı yere getir. Çerçeve dar olursa cümlenin başı ya da sonu kesilir.'),
        if (Platform.isIOS) ...[
          const GroupHeader('EK OKUMA ALANLARI'),
          Group(
            children: [
              for (var i = 0; i < s.extraRegions.length; i++)
                Cell(
                  title: s.extraRegions[i]['name'] as String? ?? 'Alan ${i + 1}',
                  subtitle: 'Üst %${(((s.extraRegions[i]['top'] as num?) ?? 0) * 100).round()} · Alt %${(((s.extraRegions[i]['bottom'] as num?) ?? 0) * 100).round()}',
                  chevron: true,
                  onTap: () => editExtra(i),
                ),
              if (s.extraRegions.length < 3) Cell(title: 'Alan ekle', titleColor: Tokens.accent, onTap: addExtra),
            ],
          ),
          const GroupFooter('Görev notu, harita yazısı gibi başka yerdeki yazıları da çevirebilirsin (en çok 3 alan). '
              'Çeviri açıkken ana ekranda her alan için bir düğme çıkar; dokununca o alan bir kez okunur.'),
        ],

        // ---------------------------------------------------------------- TV'de görünüm
        const GroupHeader('TV\'DE GÖRÜNÜM'),
        Group(
          children: [
            _ControlRow(
              title: 'Yazı boyutu',
              child: _Segmented(
                value: '${style['fontSize']}',
                items: const {'36': 'Küçük', '46': 'Orta', '58': 'Büyük', '72': 'Dev'},
                onChanged: (value) => setStyle('fontSize', int.parse(value)),
              ),
            ),
            _ControlRow(
              title: 'Yazı rengi',
              child: _Segmented(
                value: style['textColor'] as String,
                items: const {'white': 'Beyaz', 'yellow': 'Sarı'},
                onChanged: (value) => setStyle('textColor', value),
              ),
            ),
            Cell(
              title: 'Altyazının yeri',
              subtitle: placements[style['placement']] ?? '',
              chevron: true,
              onTap: pickPlacement,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Zemin koyuluğu', style: Txt.body)),
                      Text('%${style['background']}', style: Txt.body.copyWith(color: Tokens.textSecondary)),
                    ],
                  ),
                  CupertinoSlider(
                    value: (style['background'] as num).toDouble().clamp(0, 100),
                    max: 100,
                    divisions: 20,
                    activeColor: Tokens.accent,
                    onChanged: (value) => setStyle('background', value.round()),
                  ),
                ],
              ),
            ),
            if (style['placement'] == 'fixed')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Ekran konumu (alttan yükseklik)', style: Txt.body)),
                      Text('%${(style['bottomPercent'] as num? ?? 7).round()}', style: Txt.body.copyWith(color: Tokens.textSecondary)),
                    ],
                  ),
                  CupertinoSlider(
                    value: (style['bottomPercent'] as num? ?? 7).toDouble().clamp(0, 85),
                    max: 85,
                    divisions: 85,
                    activeColor: Tokens.accent,
                    onChanged: (value) => setStyle('bottomPercent', value.round()),
                  ),
                ],
              ),
            ),
            Cell(
              title: 'Önceki satır da görünsün',
              subtitle: 'Yeni cümlenin üstünde bir önceki cümle soluk kalır',
              trailing: CupertinoSwitch(
                value: style['stackPrevious'] as bool? ?? true,
                activeTrackColor: Tokens.success,
                onChanged: (value) => setStyle('stackPrevious', value),
              ),
            ),
            Cell(
              title: 'Kalın yazı',
              trailing: CupertinoSwitch(value: style['bold'] as bool, activeTrackColor: Tokens.success, onChanged: (value) => setStyle('bold', value)),
            ),
            // Bilgisayar sürümündeki "Konuşmacı adı renkli"; TV uygulaması adı ("ENZO:") ayrı renkte yazar.
            if (Platform.isIOS)
              Cell(
                title: 'Konuşmacı adı renkli',
                subtitle: 'Konuşanın adı (ör. ENZO:) sarı, sarı yazıda açık mavi',
                trailing: CupertinoSwitch(
                  value: style['speakerColor'] as bool? ?? false,
                  activeTrackColor: Tokens.success,
                  onChanged: (value) => setStyle('speakerColor', value),
                ),
              ),
            Cell(title: 'TV\'ye Deneme Altyazısı Gönder', titleColor: Tokens.accent, onTap: sendTest),
            if (Platform.isIOS)
              Cell(
                title: 'PS5\'siz Deneme',
                subtitle: 'Örnek altyazı satırları çevrilip TV\'ye gönderilir; PS5 gerekmez. Kapatana kadar sürer.',
                trailing: CupertinoSwitch(value: demoOn, activeTrackColor: Tokens.success, onChanged: setDemo),
              ),
          ],
        ),

        // ---------------------------------------------------------------- TV uygulaması
        const GroupHeader('TV UYGULAMASI'),
        Group(
          inset: 60,
          children: [
            Cell(
              icon: CupertinoIcons.tv_fill,
              iconColor: Tokens.purple,
              title: 'TV Uygulamasını Kur',
              subtitle: 'LG ve Android TV\'ye telefondan; güncellemek için de',
              chevron: true,
              onTap: () => Navigator.of(context).push(appleRoute<void>((_) => const TvInstallPage())),
            ),
          ],
        ),

        // ---------------------------------------------------------------- PS5
        const GroupHeader('PS5'),
        Group(
          inset: 60,
          children: [
            Cell(
              icon: CupertinoIcons.gamecontroller_fill,
              iconColor: Tokens.gray,
              title: widget.setup.consoleName ?? 'PS5',
              subtitle: widget.setup.consoleHost ?? '',
              trailing: const Pill(text: 'Eşleşti', color: Tokens.success),
            ),
            Cell(
              icon: CupertinoIcons.power,
              iconColor: Tokens.success,
              title: 'Dinlenme modundan uyandır',
              trailing: CupertinoSwitch(
                value: s.autoWake,
                activeTrackColor: Tokens.success,
                onChanged: (value) => change((s) => s.json['autoWake'] = value),
              ),
            ),
          ],
        ),
        const GroupFooter('Çeviri başlarken PS5 dinlenme modundaysa açılır.'),
        const SizedBox(height: 14),
        Group(
          children: [
            Cell(title: 'PS5\'i Yeniden Eşleştir', titleColor: Tokens.accent, onTap: () => confirmForget(account: false)),
            Cell(title: 'PSN Hesabını Değiştir', titleColor: Tokens.danger, onTap: () => confirmForget(account: true)),
          ],
        ),

        if (Platform.isIOS) ...[
          const GroupHeader('TANI'),
          Group(
            inset: 60,
            children: [
              Cell(
                icon: CupertinoIcons.clock_fill,
                iconColor: Tokens.indigo,
                title: 'Altyazı Geçmişi',
                chevron: true,
                onTap: () => Navigator.of(context).push(appleRoute<void>((_) => const HistoryPage())),
              ),
              Cell(
                icon: CupertinoIcons.dot_radiowaves_left_right,
                iconColor: Tokens.success,
                title: 'Sistem Durumu',
                chevron: true,
                onTap: () => Navigator.of(context).push(appleRoute<void>((_) => const HealthPage())),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Group(children: [Cell(title: 'Tüm Ayarları Sıfırla', titleColor: Tokens.danger, onTap: resetAll)]),
          const GroupFooter('PS5 eşleştirmesi, PSN hesabı ve API anahtarların silinmez.'),
        ],

        // ---------------------------------------------------------------- Hakkında
        const GroupHeader('HAKKINDA'),
        Group(
          inset: 60,
          children: [
            Cell(icon: CupertinoIcons.play_circle_fill, iconColor: Tokens.purple, title: 'Tanıtımı Göster', chevron: true, onTap: showIntro),
            Cell(icon: CupertinoIcons.doc_text_fill, iconColor: Tokens.gray, title: 'Günlük', chevron: true, onTap: showLogs),
            Cell(
              icon: CupertinoIcons.info,
              iconColor: Tokens.accent,
              title: 'Sürüm',
              value: widget.setup.version.isEmpty ? '—' : widget.setup.version,
            ),
          ],
        ),
        const GroupFooter(
          'Oyun görüntüsü ve hesap bilgilerin telefonda kalır. Çevrimiçi motor seçiliyse yalnızca okunan altyazı metni çeviri '
          'servisine gönderilir.\n\nGameTranslator açık kaynaklıdır (AGPL-3.0). Sony ya da PlayStation ile bağlantılı değildir.',
        ),
      ],
    );
  }
}

/// Başlığı üstte, denetimi altında olan satır (parçalı seçiciler için).
class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Text(title, style: Txt.body), const SizedBox(height: 10), child],
      ),
    );
  }
}

/// iOS'un kayan parçalı seçicisi.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.items, required this.onChanged});

  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSlidingSegmentedControl<String>(
      groupValue: items.containsKey(value) ? value : null,
      backgroundColor: Tokens.inset,
      thumbColor: const Color(0xFF636366),
      children: {
        for (final entry in items.entries)
          entry.key: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Text(entry.value, style: Txt.subhead.copyWith(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w500)),
          ),
      },
      onValueChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

/// Çeviri kapalıyken oyun görüntüsü yoktur; bölge boş bir ekran üstünde gösterilir.
class _RegionPlaceholder extends StatelessWidget {
  const _RegionPlaceholder({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black)),
            Positioned(
              left: 0,
              right: 0,
              top: 18,
              child: Text('Çeviri açıkken burada oyun görüntüsü görünür.', textAlign: TextAlign.center, style: Txt.footnote.copyWith(color: Tokens.textSecondary)),
            ),
            Positioned(
              left: settings.regionValue('left') * constraints.maxWidth,
              top: settings.regionValue('top') * constraints.maxHeight,
              width: (settings.regionValue('right') - settings.regionValue('left')) * constraints.maxWidth,
              height: (settings.regionValue('bottom') - settings.regionValue('top')) * constraints.maxHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Tokens.accent, width: 1.5),
                  borderRadius: BorderRadius.circular(6),
                  color: Tokens.accent.withValues(alpha: 0.12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Terim sözlüğü düzenleyicisi: bilgisayardaki sözlük dosyalarıyla aynı JSON biçimi.
class GlossaryPage extends StatefulWidget {
  const GlossaryPage({super.key, required this.initial});

  final String initial;

  static const example = '{\n  "terms": {\n    "Leviathan Axe": "Leviathan Baltası"\n  },\n  "keep": ["Kratos", "Atreus"]\n}';

  /// Sözlük metnindeki terim ve korunan ad sayısı; okunamıyorsa üçüncü değer sorunu söyler.
  static (int, int, String?) inspect(String text) {
    if (text.trim().isEmpty) return (0, 0, null);
    try {
      final root = jsonDecode(text);
      if (root is! Map) return (0, 0, 'Sözlük { ... } biçiminde olmalı.');
      final terms = root['terms'] is Map ? (root['terms'] as Map).values.whereType<String>().length : 0;
      final keep = root['keep'] is List ? (root['keep'] as List).whereType<String>().length : 0;
      return (terms, keep, null);
    } on FormatException {
      return (0, 0, 'Yazım hatası var: tırnak, virgül ve parantezleri kontrol et.');
    }
  }

  @override
  State<GlossaryPage> createState() => _GlossaryPageState();
}

class _GlossaryPageState extends State<GlossaryPage> {
  late final controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (terms, keep, problem) = GlossaryPage.inspect(controller.text);
    final empty = controller.text.trim().isEmpty;
    return GlassScaffold(
      title: 'Terim Sözlüğü',
      actions: [
        TextButton(
          onPressed: problem == null ? () => Navigator.of(context).pop(controller.text.trim()) : null,
          child: const Text('Kaydet', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Çevirinin yanlış çevirdiği özel adları ve oyun terimlerini burada sabitleyebilirsin. '
              '"terms" içindeki terimler yazdığın Türkçeyle çevrilir, "keep" içindeki adlar olduğu gibi kalır.',
              style: Txt.subhead.copyWith(color: Tokens.textSecondary),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            minLines: 10,
            maxLines: 22,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.45),
            decoration: InputDecoration(
              hintText: GlossaryPage.example,
              hintMaxLines: 8,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Tokens.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Tokens.border)),
            ),
          ),
          const SizedBox(height: 12),
          if (problem != null)
            Notice(icon: CupertinoIcons.exclamationmark_circle_fill, color: Tokens.danger, text: problem)
          else if (empty)
            Notice(
              icon: CupertinoIcons.wand_stars,
              text: 'Sözlük boş. Bir örnekle başlayıp kendi terimlerinle değiştirebilirsin.',
              action: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                onPressed: () => setState(() => controller.text = GlossaryPage.example),
                child: const Text('Örnek Ekle'),
              ),
            )
          else
            Notice(icon: CupertinoIcons.checkmark_circle_fill, color: Tokens.success, text: '$terms terim, $keep korunan ad okundu.'),
          const GroupFooter(
            'Bilgisayardaki GameTranslator sözlük dosyalarıyla aynı biçimdir; oradaki dosyanın içeriğini buraya yapıştırabilirsin. '
            'Yalnızca İngilizce → Türkçe çeviride kullanılır.',
          ),
        ],
      ),
    );
  }
}
