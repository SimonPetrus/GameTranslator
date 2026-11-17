// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'bridge.dart';
import 'guide_page.dart';
import 'history_page.dart';
import 'l10n.dart';
import 'main.dart';
import 'settings_page.dart';
import 'tv_install_page.dart';
import 'ui.dart';

/// Ana ekran: altta yüzen cam sekme çubuğu ve üç sekme (Çeviri, Rehber, Ayarlar).
/// Çeviri sekmesi: başlat/durdur, PS5 · telefon · TV durumu, canlı önizleme ve son çeviri.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.setup, required this.onSetupChanged});

  final SetupInfo setup;
  final Future<void> Function() onSetupChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  static List<(IconData, IconData, String)> get tabs => [
        (CupertinoIcons.captions_bubble, CupertinoIcons.captions_bubble_fill, L.t('Çeviri', 'Translate')),
        (CupertinoIcons.book, CupertinoIcons.book_fill, L.t('Rehber', 'Guide')),
        (CupertinoIcons.gear_alt, CupertinoIcons.gear_alt_fill, L.t('Ayarlar', 'Settings')),
      ];

  int tab = 0;
  EngineState state = const EngineState();
  AppSettings? settings;
  StreamSubscription<EngineState>? subscription;
  Timer? previewTimer;
  Uint8List? preview;
  late final AnimationController pulse;

  /// Görüntü akarken TV'nin bağlanmasının beklenmeye başladığı an; TV bağlıyken ya da çeviri kapalıyken null.
  DateTime? tvWaitingSince;

  /// TV uygulaması telefonu genelde birkaç saniyede bulur; bu kadar beklendiyse bir sorun vardır.
  static const tvWaitLimit = Duration(seconds: 25);

  bool get tvStuck => tvWaitingSince != null && DateTime.now().difference(tvWaitingSince!) > tvWaitLimit;

  @override
  void initState() {
    super.initState();
    pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
    subscription = Bridge.states.listen((next) {
      if (!mounted) return;
      setState(() {
        state = next;
        final waiting = next.phase == 'streaming' && next.tvClients == 0;
        tvWaitingSince = waiting ? (tvWaitingSince ?? DateTime.now()) : null;
      });
    });
    loadSettings();
    // Önizleme yalnız görüntü akarken yenilenir. Aynı sayaç, TV bekleme süresi dolunca uyarının değişmesini sağlar.
    previewTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      refreshPreview();
      if (mounted && tvWaitingSince != null) setState(() {});
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    previewTimer?.cancel();
    pulse.dispose();
    super.dispose();
  }

  bool get active => state.running || (state.phase != 'idle' && state.phase != 'failed');
  bool get streaming => state.phase == 'streaming';

  Future<void> loadSettings() async {
    final loaded = await Bridge.settings();
    if (mounted) setState(() => settings = loaded);
  }

  /// Başlıktaki küre düğmesi (yalnız iOS): dili Türkçe ile İngilizce arasında değiştirir ve ayara yazar.
  /// Ayarlar sekmesiyle aynı ortak ayar nesnesi değiştirilir; o sekmenin bekleyen değişiklikleri de korunur.
  Future<void> toggleLanguage() async {
    final next = L.en ? 'tr' : 'en';
    L.apply(next);
    try {
      final shared = await Bridge.settings();
      shared.json['uiLanguage'] = next;
      await Bridge.saveSettings(shared);
      if (mounted) setState(() => settings = shared);
    } catch (_) {
      // Ayar yazılamadı: dil bu oturumda değişmiş kalır.
    }
  }

  Future<void> refreshPreview() async {
    if (!streaming || tab != 0) return;
    final image = await Bridge.snapshot(width: 640);
    if (mounted && image != null) setState(() => preview = image);
  }

  /// Sekme değişir; Çeviri'ye dönülünce bölge çerçevesi güncel ayarlarla çizilsin diye ayarlar yeniden okunur.
  void selectTab(int index) {
    setState(() => tab = index);
    if (index == 0) loadSettings();
  }

  Future<void> toggle() async {
    if (active) {
      await Bridge.stop();
    } else {
      await Bridge.start();
    }
  }

  Future<void> sendTest() async {
    await Bridge.testSubtitle();
    if (!mounted) return;
    toast(
      context,
      state.tvClients > 0
          ? L.t('Deneme altyazısı TV\'ye gönderildi.', 'Test subtitle sent to the TV.')
          : L.t('TV bağlı değil. Önce TV\'de GameTranslator\'ı aç.', 'The TV is not connected. Open GameTranslator on the TV first.'),
    );
  }

  /// Şu an okunan ek alanın sırası (yoksa null).
  int? readingExtra;

  /// Ek okuma alanını bir kez okutur ve sonucu küçük bir pencerede gösterir (yalnız iOS).
  Future<void> readExtraArea(int index) async {
    if (readingExtra != null) return;
    setState(() => readingExtra = index);
    final result = await Bridge.readExtra(index);
    if (!mounted) return;
    setState(() => readingExtra = null);
    final failed = !result.ok || result.text.isEmpty;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (failed)
              Text(
                result.error.isEmpty ? L.t('Bu alanda okunacak yazı bulunamadı.', 'No text to read in this area.') : result.error,
                style: Txt.subhead.copyWith(color: Tokens.danger),
              )
            else ...[
              Text(
                result.text,
                textDirection: isRtlText(result.text) ? TextDirection.rtl : TextDirection.ltr,
                textAlign: isRtlText(result.text) ? TextAlign.right : TextAlign.left,
                style: Txt.title3.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(result.source.replaceAll('\n', ' '), style: Txt.subhead.copyWith(color: Tokens.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }

  (String, String, Color) get headline => switch (state.phase) {
        'streaming' => (
            L.t('Çeviri açık', 'Translation on'),
            L.t('Ekranı kapatabilirsin; çeviri arka planda sürer.', 'You can lock the screen; translation keeps running in the background.'),
            Tokens.success
          ),
        'starting' => (L.t('Başlatılıyor…', 'Starting…'), L.t('Birkaç saniye sürer.', 'This takes a few seconds.'), Tokens.warning),
        'connecting' => (
            L.t('PS5\'e bağlanılıyor…', 'Connecting to the PS5…'),
            L.t('PS5 açık ve aynı Wi-Fi\'de olmalı.', 'The PS5 must be on and on the same Wi-Fi.'),
            Tokens.warning
          ),
        'waking' => (
            L.t('PS5 uyandırılıyor…', 'Waking the PS5…'),
            L.t('Dinlenme modundan çıkması bir dakikayı bulabilir.', 'Leaving rest mode can take up to a minute.'),
            Tokens.warning
          ),
        'reconnecting' => (
            L.t('Yeniden bağlanılıyor…', 'Reconnecting…'),
            L.t('Bağlantı koptu, tekrar deneniyor.', 'The connection dropped; trying again.'),
            Tokens.warning
          ),
        'stopping' => (L.t('Durduruluyor…', 'Stopping…'), '', Tokens.textSecondary),
        'failed' => (L.t('Başlatılamadı', 'Could not start'), L.t('Yeniden denemek için dokun.', 'Tap to try again.'), Tokens.danger),
        _ => (L.t('Çeviri kapalı', 'Translation off'), L.t('Başlatmak için dokun.', 'Tap to start.'), Tokens.textSecondary),
      };

  List<FlowNode> get nodes {
    final connecting = const {'starting', 'connecting', 'waking', 'reconnecting'}.contains(state.phase);
    final address = state.localAddress;
    final tvOn = state.tvClients > 0;
    return [
      FlowNode(
        icon: CupertinoIcons.gamecontroller_fill,
        label: 'PS5',
        detail: streaming
            ? L.t('Bağlı', 'Connected')
            : switch (state.phase) {
                'waking' => L.t('Uyanıyor', 'Waking'),
                'starting' || 'connecting' || 'reconnecting' => L.t('Bağlanıyor', 'Connecting'),
                _ => L.t('Eşleşti', 'Paired'),
              },
        color: streaming ? Tokens.success : (connecting ? Tokens.warning : Tokens.textSecondary),
        busy: connecting,
      ),
      FlowNode(
        icon: CupertinoIcons.device_phone_portrait,
        label: L.t('Telefon', 'Phone'),
        detail: address == null ? L.t('Wi-Fi yok', 'No Wi-Fi') : (streaming ? L.t('Çeviriyor', 'Translating') : L.t('Hazır', 'Ready')),
        color: address == null ? Tokens.danger : (streaming ? Tokens.accent : Tokens.textSecondary),
      ),
      FlowNode(
        icon: CupertinoIcons.tv_fill,
        label: 'TV',
        detail: tvOn ? L.t('Bağlı', 'Connected') : (active ? L.t('Bekleniyor', 'Waiting') : L.t('Bağlı değil', 'Not connected')),
        color: tvOn ? Tokens.success : (active ? Tokens.warning : Tokens.textSecondary),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        const GlassBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              IndexedStack(
                index: tab,
                children: [
                  translateTab(),
                  const GuideTab(),
                  SettingsTab(setup: widget.setup, onSetupChanged: widget.onSetupChanged, active: tab == 2),
                ],
              ),
              // Klavye açıkken sekme çubuğu gizlenir: yazılan kutunun (ör. API anahtarı) üstünü örtüyordu.
              if (MediaQuery.viewInsetsOf(context).bottom == 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottom + 12,
                  child: Center(child: GlassTabBar(items: tabs, index: tab, onTap: selectTab)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget translateTab() {
    final (title, hint, color) = headline;
    final failed = state.phase == 'failed';
    final tvOn = state.tvClients > 0;
    return LargeTitleList(
      title: 'GameTranslator',
      // Dil düğmesi yalnız iOS'ta; Android'de başlık bu paketten önceki gibi yalnız logodur.
      trailing: Platform.isIOS
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassIconButton(
                  icon: CupertinoIcons.globe,
                  size: 34,
                  tooltip: L.t('Uygulama dili', 'App language'),
                  onTap: toggleLanguage,
                ),
                const SizedBox(width: 8),
                const GtLogo(size: 34, glow: false),
              ],
            )
          : const GtLogo(size: 38, glow: false),
      children: [
        const SizedBox(height: 22),
        Center(
          child: _PowerButton(
            phase: state.phase,
            active: active,
            color: color,
            pulse: pulse,
            onTap: state.nativeAvailable && state.phase != 'stopping' ? toggle : null,
          ),
        ),
        const SizedBox(height: 22),
        Text(title, textAlign: TextAlign.center, style: Txt.title1),
        const SizedBox(height: 4),
        Text(
          failed && state.message.isNotEmpty ? state.message : hint,
          textAlign: TextAlign.center,
          style: Txt.subhead.copyWith(color: failed ? Tokens.danger : Tokens.textSecondary),
        ),
        const SizedBox(height: 26),
        FlowRow(nodes: nodes),
        if (!state.nativeAvailable) ...[
          const SizedBox(height: 12),
          Notice(
            icon: CupertinoIcons.exclamationmark_circle_fill,
            color: Tokens.danger,
            title: L.t('Bu telefon desteklenmiyor', 'This phone is not supported'),
            text: L.t('Remote Play kütüphanesi bu cihazda yüklenemedi.', 'The Remote Play library could not be loaded on this device.'),
          ),
        ],
        if (state.localAddress == null) ...[
          const SizedBox(height: 12),
          Notice(
            icon: CupertinoIcons.wifi_slash,
            color: Tokens.danger,
            title: L.t('Wi-Fi bağlantısı yok', 'No Wi-Fi connection'),
            text: L.t('Telefon, PS5 ve TV ile aynı Wi-Fi ağına bağlı olmalı.', 'The phone must be on the same Wi-Fi network as the PS5 and the TV.'),
          ),
        ],
        if (streaming && !tvOn && !tvStuck) ...[
          const SizedBox(height: 12),
          Notice(
            icon: CupertinoIcons.tv,
            color: Tokens.warning,
            title: L.t('TV\'de GameTranslator\'ı aç', 'Open GameTranslator on the TV'),
            text: L.t(
              'TV uygulaması telefonu ağda kendisi bulur; açtıktan sonra bağlanması birkaç saniye sürer.',
              'The TV app finds the phone on the network by itself; it takes a few seconds to connect after you open it.',
            ),
          ),
        ],
        if (streaming && !tvOn && tvStuck) ...[
          const SizedBox(height: 12),
          Notice(
            icon: CupertinoIcons.exclamationmark_triangle_fill,
            color: Tokens.warning,
            title: L.t('TV hâlâ bağlanmadı', 'The TV still has not connected'),
            text: L.t(
              'TV uygulaması daha önce bilgisayara bağlandıysa eski adreste takılı kalmış olabilir. '
                  'TV\'de uygulamanın verilerini bir kez temizlemek bunu düzeltir.',
              'If the TV app was connected to a computer before, it may be stuck on the old address. '
                  'Clearing the app\'s data on the TV once fixes this.',
            ),
            action: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
              onPressed: () => Navigator.of(context).push(appleRoute<void>((_) => const TvHelpPage())),
              child: Text(L.t('Adım adım göster', 'Show step by step'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
        if (active) ...[
          GroupHeader(L.t('CANLI', 'LIVE')),
          _LiveCard(state: state, preview: streaming ? preview : null, settings: settings),
          if (Platform.isIOS && streaming && (settings?.extraRegions.isNotEmpty ?? false)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < settings!.extraRegions.length; i++)
                  OutlinedButton.icon(
                    onPressed: readingExtra == null ? () => readExtraArea(i) : null,
                    icon: readingExtra == i
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(CupertinoIcons.crop, size: 16),
                    label: Text(settings!.extraRegions[i]['name'] as String? ?? L.t('Alan ${i + 1}', 'Area ${i + 1}')),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Group(
            inset: 60,
            children: [
              if (Platform.isIOS)
                Cell(
                  icon: CupertinoIcons.clock_fill,
                  iconColor: Tokens.indigo,
                  title: L.t('Altyazı geçmişi', 'Subtitle history'),
                  chevron: true,
                  onTap: () => Navigator.of(context).push(appleRoute<void>((_) => const HistoryPage())),
                ),
              Cell(icon: CupertinoIcons.captions_bubble_fill, iconColor: Tokens.indigo, title: L.t('TV\'ye deneme altyazısı gönder', 'Send a test subtitle to the TV'), onTap: sendTest),
              Cell(icon: CupertinoIcons.crop, iconColor: Tokens.teal, title: L.t('Altyazı bölgesini ayarla', 'Adjust subtitle area'), chevron: true, onTap: () => selectTab(2)),
            ],
          ),
        ] else ...[
          GroupHeader(L.t('NASIL KULLANILIR', 'HOW TO USE')),
          Group(
            inset: 60,
            children: [
              _HowStep(number: 1, text: L.t('Oyunda altyazıları aç.', 'Turn on subtitles in the game.')),
              _HowStep(number: 2, text: L.t('Yukarıdaki düğmeyle çeviriyi başlat.', 'Start translation with the button above.')),
              _HowStep(number: 3, text: L.t('TV\'de GameTranslator\'ı aç; çeviri oyunun üstünde görünür.', 'Open GameTranslator on the TV; the translation appears over the game.')),
              Cell(
                icon: CupertinoIcons.tv_fill,
                iconColor: Tokens.purple,
                title: L.t('TV uygulamasını kur', 'Install the TV app'),
                subtitle: L.t('TV\'nde GameTranslator yoksa', 'If your TV does not have GameTranslator'),
                chevron: true,
                onTap: () => Navigator.of(context).push(appleRoute<void>((_) => const TvInstallPage())),
              ),
              Cell(icon: CupertinoIcons.book_fill, iconColor: Tokens.warning, title: L.t('Ayrıntılı rehber', 'Detailed guide'), chevron: true, onTap: () => selectTab(1)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Ortadaki büyük başlat/durdur düğmesi: cam bir halkanın içinde, sol üstten ışık alan küre.
class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.phase, required this.active, required this.color, required this.pulse, required this.onTap});

  final String phase;
  final bool active;
  final Color color;
  final Animation<double> pulse;
  final VoidCallback? onTap;

  static const double outer = 172;
  static const double inner = 144;

  @override
  Widget build(BuildContext context) {
    final streaming = phase == 'streaming';
    final busy = active && !streaming;
    final idle = !active;
    final tone = idle ? (phase == 'failed' ? Tokens.danger : Tokens.accent) : color;
    return Semantics(
      button: true,
      label: active ? L.t('Çeviriyi durdur', 'Stop translation') : L.t('Çeviriyi başlat', 'Start translation'),
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, child) {
          // Kapalıyken ve çeviri açıkken ışık yavaşça nefes alır; bağlanırken sabit kalır.
          final t = busy ? 0.3 : Curves.easeInOut.transform(pulse.value);
          return Container(
            width: outer,
            height: outer,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: Tokens.glassFill,
              border: Border.all(color: Tokens.border, width: 0.8),
              boxShadow: [BoxShadow(color: tone.withValues(alpha: 0.20 + 0.16 * t), blurRadius: 40 + 24 * t, spreadRadius: 2 + 4 * t)],
            ),
            child: child,
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (busy) SizedBox(width: outer - 4, height: outer - 4, child: CircularProgressIndicator(strokeWidth: 2.5, color: color)),
            Material(
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              color: Colors.transparent,
              child: Ink(
                width: inner,
                height: inner,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: idle
                      ? const RadialGradient(
                          center: Alignment(-0.45, -0.55),
                          radius: 1.15,
                          colors: [Color(0xFF7CC0FF), Color(0xFF0A84FF), Color(0xFF0060DF)],
                          stops: [0, 0.48, 1],
                        )
                      : RadialGradient(
                          center: const Alignment(-0.45, -0.55),
                          radius: 1.15,
                          colors: [const Color(0x59FFFFFF), tone.withValues(alpha: streaming ? 0.30 : 0.12)],
                        ),
                  border: idle ? null : Border.all(color: tone.withValues(alpha: busy ? 0.3 : 0.9), width: 2),
                ),
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: Icon(
                    active ? CupertinoIcons.stop_fill : CupertinoIcons.play_fill,
                    size: active ? 46 : 54,
                    color: Colors.white.withValues(alpha: busy ? 0.6 : 1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Nasıl kullanılır" listesindeki numaralı satır.
class _HowStep extends StatelessWidget {
  const _HowStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Tokens.surfaceHigh, borderRadius: BorderRadius.circular(7.2)),
            child: Text('$number', style: Txt.subhead.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: Txt.callout)),
        ],
      ),
    );
  }
}

/// Çeviri açıkken: oyun görüntüsü, altyazı bölgesi ve son çeviri.
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.state, required this.preview, required this.settings});

  final EngineState state;
  final Uint8List? preview;
  final AppSettings? settings;

  @override
  Widget build(BuildContext context) {
    final hasTranslation = state.lastTranslation.isNotEmpty;
    final streaming = state.phase == 'streaming';
    return Glass(
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (preview != null)
            RegionPreview(image: preview!, settings: settings, subtitle: hasTranslation ? state.lastTranslation : null, autoRegion: state.autoRegion)
          else
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CupertinoActivityIndicator(radius: 12),
                    const SizedBox(height: 12),
                    Text(streaming ? L.t('Önizleme hazırlanıyor…', 'Preparing preview…') : L.t('PS5 görüntüsü bekleniyor…', 'Waiting for the PS5 picture…'), style: Txt.footnote.copyWith(color: Tokens.textSecondary)),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(L.t('Son çeviri', 'Latest translation'), style: Txt.headline)),
                    if (streaming) Pill(text: L.t('${state.translated} satır', '${state.translated} lines'), color: Tokens.accent),
                  ],
                ),
                const SizedBox(height: 8),
                if (hasTranslation) ...[
                  Text(
                    state.lastTranslation,
                    textDirection: isRtlText(state.lastTranslation) ? TextDirection.rtl : TextDirection.ltr,
                    textAlign: isRtlText(state.lastTranslation) ? TextAlign.right : TextAlign.left,
                    style: Txt.title3.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(state.lastSource.replaceAll('\n', ' '), style: Txt.subhead.copyWith(color: Tokens.textSecondary)),
                  if (state.packHits > 0 && state.packGame.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(L.t('${state.packGame} paketi kullanılıyor · ${state.packHits} satır paketten', 'Using the ${state.packGame} pack · ${state.packHits} lines from the pack'),
                        style: Txt.footnote.copyWith(color: Tokens.success)),
                  ],
                ] else
                  Text(L.t('Oyunda altyazı çıkınca çevirisi burada ve TV\'de görünür.', 'When a subtitle appears in the game, its translation shows here and on the TV.'), style: Txt.subhead.copyWith(color: Tokens.textSecondary)),
                if (streaming) ...[
                  const SizedBox(height: 14),
                  // Bölge doğru yerde mi ve yazı okunuyor mu, buradan anlaşılır.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Tokens.inset, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L.t('ÇERÇEVEDE OKUNAN', 'READ IN THE FRAME'), style: Txt.caption.copyWith(color: Tokens.textSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                        const SizedBox(height: 3),
                        Text(
                          state.lastRead.isEmpty ? L.t('Şu an yazı yok.', 'No text right now.') : state.lastRead.replaceAll('\n', ' '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.footnote.copyWith(fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Oyun görüntüsü, üstünde altyazının arandığı bölgenin çerçevesi ve (verildiyse) TV'deki gibi çeviri.
class RegionPreview extends StatelessWidget {
  const RegionPreview({super.key, required this.image, required this.settings, this.subtitle, this.autoRegion});

  final Uint8List image;
  final AppSettings? settings;
  final String? subtitle;

  /// Otomatik bulunan altyazı alanı (0–1); yoksa null.
  final ({double top, double bottom, double left, double right})? autoRegion;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final auto = autoRegion;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(image, fit: BoxFit.fill, gaplessPlayback: true),
            if (s != null)
              Positioned(
                left: s.regionValue('left') * constraints.maxWidth,
                top: s.regionValue('top') * constraints.maxHeight,
                width: (s.regionValue('right') - s.regionValue('left')) * constraints.maxWidth,
                height: (s.regionValue('bottom') - s.regionValue('top')) * constraints.maxHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Tokens.accent, width: 1.5),
                    borderRadius: BorderRadius.circular(6),
                    color: Tokens.accent.withValues(alpha: 0.10),
                  ),
                ),
              ),
            if (auto != null) ..._autoBand(auto, constraints.maxWidth, constraints.maxHeight),
            if (subtitle != null) _subtitle(s, constraints.maxHeight),
          ],
        ),
      ),
    );
  }

  /// Otomatik bulunan altyazı bandı: yeşil çerçeve ve "Otomatik" etiketi (elle çizilen mavi çerçeveden ayrışır).
  List<Widget> _autoBand(({double top, double bottom, double left, double right}) a, double width, double height) {
    final top = a.top.clamp(0.0, 1.0).toDouble() * height;
    final bottom = a.bottom.clamp(0.0, 1.0).toDouble() * height;
    final left = a.left.clamp(0.0, 1.0).toDouble() * width;
    final right = a.right.clamp(0.0, 1.0).toDouble() * width;
    if (right <= left || bottom <= top) return const [];
    return [
      Positioned(
        left: left,
        top: top,
        width: right - left,
        height: bottom - top,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Tokens.success, width: 1.5),
            borderRadius: BorderRadius.circular(6),
            color: Tokens.success.withValues(alpha: 0.12),
          ),
        ),
      ),
      Positioned(
        left: left,
        top: (top - 15).clamp(0.0, height).toDouble(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: Tokens.success, borderRadius: BorderRadius.circular(4)),
          child: Text(L.t('Otomatik', 'Auto'), style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }

  /// TV'deki görünümün yaklaşık hâli: renk, kalınlık, boyut (1080p TV'ye göre ölçekli), zemin ve yer.
  Widget _subtitle(AppSettings? s, double height) {
    final style = s?.style ?? const <String, dynamic>{};
    final fontSize = ((style['fontSize'] as num?) ?? 46).toDouble() / 1080 * height;
    final color = style['textColor'] == 'yellow' ? const Color(0xFFFFE600) : Colors.white;
    final placement = style['placement'] as String? ?? 'cover';
    final alpha = placement == 'cover' ? 0.92 : ((style['background'] as num?) ?? 72).toDouble().clamp(0, 100) / 100;
    final bottomPercent = ((style['bottomPercent'] as num?) ?? 7).toDouble().clamp(0, 85) / 100;
    var bottom = bottomPercent * height;
    if (s != null && placement != 'fixed') {
      final top = s.regionValue('top');
      final regionBottom = s.regionValue('bottom');
      if (placement == 'cover') bottom = ((1 - regionBottom) * height).clamp(0.0, height);
      if (placement == 'above') bottom = ((1 - top) * height).clamp(0.0, height);
      if (placement == 'below') bottom = ((1 - regionBottom) * height - fontSize * 2.6).clamp(0.0, height);
    }
    return Positioned(
      left: 12,
      right: 12,
      bottom: bottom,
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: fontSize * 0.2),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: alpha), borderRadius: BorderRadius.circular(6)),
          child: Text(
            subtitle!,
            textDirection: isRtlText(subtitle!) ? TextDirection.rtl : TextDirection.ltr,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: fontSize.clamp(8.0, 28.0),
              fontWeight: style['bold'] == false ? FontWeight.w600 : FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}
