// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'guide_page.dart';
import 'l10n.dart';
import 'main.dart';
import 'tv_install.dart';
import 'ui.dart';

/// TV uygulamasını telefondan kurma sihirbazı: marka → TV'yi bul → geliştirici modu adımları (her ekranda tek iş)
/// → kurulum → TV'de aç. Kurulum Android tarafında yapılır (tvinstall/); bu sayfa yalnız yol gösterir.
class TvInstallPage extends StatefulWidget {
  const TvInstallPage({super.key});

  @override
  State<TvInstallPage> createState() => _TvInstallPageState();
}

enum _Step { brand, samsung, find, guide, install, done }

/// Geliştirici modu adımlarından biri. [check]: adım yapılınca TV'de açılan port (canlı denetim).
class _GuideStep {
  const _GuideStep(this.title, this.body, {this.different, this.check = _Check.none, this.copy});

  final String title;
  final String body;

  /// "Menü farklı görünüyorsa" açıklaması.
  final String? different;
  final _Check check;

  /// Kopyalanabilecek yazı (ör. web adresi).
  final String? copy;
}

enum _Check { none, ready, keyServer }

List<_GuideStep> get _androidSteps => [
      _GuideStep(
        L.t('TV\'de Ayarlar\'ı aç', 'Open Settings on the TV'),
        L.t(
          'TV kumandasındaki dişli (Ayarlar) tuşuna bas. Kumandada yoksa ana ekranın sağ üstündeki dişli simgesini seç.',
          'Press the gear (Settings) button on the TV remote. If your remote does not have one, select the gear icon at the top right of the home screen.',
        ),
        different: L.t(
          'Google TV\'de (yeni Sony, TCL, Philips, Xiaomi modelleri) sağ üstteki profil resmini ya da dişliyi seç, '
              'sonra "Ayarlar"a gir.',
          'On Google TV (newer Sony, TCL, Philips and Xiaomi models), select the profile picture or the gear at the top right, '
              'then open "Settings".',
        ),
      ),
      _GuideStep(
        L.t('"Hakkında" ekranına gir', 'Open the "About" screen'),
        L.t(
          'Android TV: Ayarlar › Cihaz Tercihleri › Hakkında.\nGoogle TV: Ayarlar › Sistem › Hakkında.',
          'Android TV: Settings › Device Preferences › About.\nGoogle TV: Settings › System › About.',
        ),
        different: L.t(
          'Philips: Ayarlar › Android Ayarları › Cihaz Tercihleri › Hakkında.\n'
              'Sony: Ayarlar › Sistem › Hakkında (eski modellerde Cihaz Tercihleri › Hakkında).\n'
              'TCL ve Xiaomi: Ayarlar › Sistem › Hakkında ya da Cihaz Tercihleri › Hakkında.\n'
              'Bulamazsan ayarlarda arama varsa "Hakkında" yaz.',
          'Philips: Settings › Android Settings › Device Preferences › About.\n'
              'Sony: Settings › System › About (on older models Device Preferences › About).\n'
              'TCL and Xiaomi: Settings › System › About or Device Preferences › About.\n'
              'If you cannot find it, type "About" in the settings search, if there is one.',
        ),
      ),
      _GuideStep(
        L.t('Yapı satırına 7 kez bas', 'Press the build line 7 times'),
        L.t(
          'Listenin altındaki "Android TV OS yapısı" satırını seç ve kumandanın Tamam tuşuna art arda 7 kez bas. '
              '"Artık bir geliştiricisiniz" yazısı çıkar.',
          'Select the "Android TV OS build" line at the bottom of the list and press the OK button on the remote 7 times in a row. '
              'A message saying "You are now a developer" appears.',
        ),
        different: L.t(
          'Satırın adı modele göre "Yapı numarası", "Derleme" ya da "Build" olabilir. TV PIN isterse TV\'nin kilit '
              'PIN\'ini gir. "Zaten geliştiricisiniz" yazıyorsa bu adım tamam.',
          'Depending on the model the line may be called "Build number", "Build" or "Android TV OS build". If the TV asks for a PIN, enter the TV\'s lock '
              'PIN. If it says "You are already a developer", this step is done.',
        ),
      ),
      _GuideStep(
        L.t('Geliştirici seçenekleri\'ni aç', 'Open Developer options'),
        L.t(
          'Geri tuşuyla bir ekran geri dön. Android TV\'de Cihaz Tercihleri, Google TV\'de Sistem altında yeni bir '
              '"Geliştirici seçenekleri" satırı belirdi; ona gir.',
          'Go back one screen with the Back button. A new "Developer options" line has appeared under Device Preferences on Android TV, '
              'or under System on Google TV; open it.',
        ),
        different: L.t(
          'Satırı göremiyorsan Ayarlar\'dan tamamen çıkıp yeniden gir. Hâlâ yoksa önceki adımda 7 kez basmayı yinele.',
          'If you cannot see the line, leave Settings completely and open it again. If it is still missing, repeat pressing 7 times in the previous step.',
        ),
      ),
      _GuideStep(
        L.t('"USB hata ayıklama"yı aç', 'Turn on "USB debugging"'),
        L.t(
          'Geliştirici seçenekleri listesinde "USB hata ayıklama"yı bul ve aç; çıkan uyarıda "Tamam"ı seç. Listede '
              '"Ağ üzerinden hata ayıklama" ya da "ADB ağ hata ayıklama" varsa onu da aç.\n\nTV açıldığında burası kendiliğinden yeşile döner.',
          'In the Developer options list find "USB debugging" and turn it on; choose "OK" on the warning that appears. If the list has '
              '"Debugging over network" or "ADB network debugging", turn that on too.\n\nThis turns green by itself once the TV is detected.',
        ),
        different: L.t(
          'Seçeneğin adı "Hata ayıklama (ADB)" ya da İngilizce "USB debugging" olabilir. Yalnız "Kablosuz hata ayıklama" '
              'olup eşleştirme kodu isteyen modeller (ör. Google TV Streamer) telefondan henüz kurulamıyor; bunlarda '
              'Rehber\'deki USB bellek yolunu kullan.',
          'The option may be called "Debugging (ADB)" or "USB debugging". Models that only have "Wireless debugging" '
              'and ask for a pairing code (for example Google TV Streamer) cannot be installed from the phone yet; for those, '
              'use the USB stick method in the Guide.',
        ),
        check: _Check.ready,
      ),
    ];

List<_GuideStep> get _lgSteps => [
      _GuideStep(
        L.t('Ücretsiz LG geliştirici hesabı aç', 'Create a free LG developer account'),
        L.t(
          'Telefonun tarayıcısında aşağıdaki adrese gir, sağ üstten "SIGN IN", sonra "Create Account" ile ücretsiz hesap aç. '
              'E-postanı ve şifreni bir sonraki adımda TV\'de yazacaksın.',
          'In your phone\'s browser go to the address below, tap "SIGN IN" at the top right, then "Create Account" to make a free account. '
              'You will enter your email and password on the TV in the next step.',
        ),
        different: L.t(
          'LG hesabın zaten varsa (ör. LG ThinQ) aynı e-posta ve şifreyle giriş yapabilirsin; bu adımı geç.',
          'If you already have an LG account (for example LG ThinQ), you can sign in with the same email and password; skip this step.',
        ),
        copy: 'https://webostv.developer.lge.com',
      ),
      _GuideStep(
        L.t('TV\'ye "Developer Mode" uygulamasını kur', 'Install the "Developer Mode" app on the TV'),
        L.t(
          'TV\'de LG Content Store\'u (Uygulamalar) aç, arama kutusuna "Developer Mode" yaz ve uygulamayı yükle.',
          'On the TV open the LG Content Store (Apps), type "Developer Mode" in the search box and install the app.',
        ),
        different: L.t(
          'Mağaza açılmıyorsa TV internete bağlı mı kontrol et. Eski modellerde mağazanın adı "LG Store" ya da '
              '"Uygulamalar"dır. Uygulama ekranda İngilizce görünür.',
          'If the store does not open, check that the TV is connected to the internet. On older models the store is called "LG Store" or '
              '"Apps". The app is shown in English.',
        ),
      ),
      _GuideStep(
        L.t('Giriş yap ve "Dev Mode Status"u aç', 'Sign in and turn on "Dev Mode Status"'),
        L.t(
          'Developer Mode uygulamasını aç, LG hesabının e-postası ve şifresiyle giriş yap. "Dev Mode Status" anahtarını aç. '
              'TV kendiliğinden yeniden başlar; açılmasını bekle.\n\nGeliştirici modu açıldığında burası kendiliğinden yeşile döner.',
          'Open the Developer Mode app and sign in with your LG account email and password. Turn on the "Dev Mode Status" switch. '
              'The TV restarts by itself; wait for it to come back.\n\nThis turns green by itself once developer mode is on.',
        ),
        different: L.t(
          '"Dev Mode Status" gri ve seçilemiyorsa önce giriş yapılmamıştır. Giriş "Login failed" diyorsa hesabının '
              'e-postasını doğruladığından emin ol.',
          'If "Dev Mode Status" is grey and cannot be selected, you have not signed in yet. If sign-in says "Login failed", make sure you have verified '
              'your account\'s email.',
        ),
        check: _Check.ready,
      ),
      _GuideStep(
        L.t('"Key Server"ı aç', 'Turn on "Key Server"'),
        L.t(
          'TV açıldıktan sonra Developer Mode uygulamasını yeniden aç ve "Key Server" anahtarını aç. Uygulamayı ekranda bırak; '
              'kapatırsan Key Server da kapanır.\n\nKey Server açıldığında burası kendiliğinden yeşile döner.',
          'After the TV has restarted, open the Developer Mode app again and turn on the "Key Server" switch. Leave the app on screen; '
              'if you close it, Key Server turns off too.\n\nThis turns green by itself once Key Server is on.',
        ),
        different: L.t(
          'Ekranın sol altında 6 karakterlik "Passphrase" görünür; bir sonraki adımda onu yazacaksın.',
          'A 6-character "Passphrase" appears at the bottom left of the screen; you will type it in the next step.',
        ),
        check: _Check.keyServer,
      ),
    ];

class _TvInstallPageState extends State<TvInstallPage> {
  _Step step = _Step.brand;
  TvKind? kind;
  String? host;
  String tvName = '';
  bool force = false;

  SavedTv? saved;
  Map<TvKind, String> bundled = {};
  String? phone;

  List<FoundTv> found = [];
  bool searching = false;
  bool searched = false;
  final manualController = TextEditingController();
  String? manualError;

  int guideIndex = 0;
  TvCheck? check;
  Timer? poll;
  bool polling = false;

  final passController = TextEditingController();
  bool installing = false;
  String stage = '';
  TvInstallResult? result;
  StreamSubscription<String>? stages;

  @override
  void initState() {
    super.initState();
    stages = TvBridge.stages.listen((value) {
      if (mounted) setState(() => stage = value);
    });
    () async {
      final values = await Future.wait([TvBridge.saved(), TvBridge.bundled(), TvBridge.phoneAddress()]);
      if (!mounted) return;
      setState(() {
        saved = values[0] as SavedTv?;
        bundled = values[1] as Map<TvKind, String>;
        phone = values[2] as String?;
      });
    }();
  }

  @override
  void dispose() {
    poll?.cancel();
    stages?.cancel();
    if (installing || searching) TvBridge.cancel();
    manualController.dispose();
    passController.dispose();
    super.dispose();
  }

  List<_GuideStep> get guideSteps => switch (kind) {
        TvKind.android => _androidSteps,
        // Anahtarı kayıtlı TV'de Key Server adımı gerekmez.
        TvKind.lg => check?.hasKey == true ? _lgSteps.sublist(0, 3) : _lgSteps,
        _ => const [],
      };

  // ------------------------------------------------------------------------------------------- gezinme

  void go(_Step next) {
    poll?.cancel();
    setState(() {
      step = next;
      if (next != _Step.install) result = null;
    });
    if (next == _Step.find) search();
    if (next == _Step.guide) startPolling();
  }

  void chooseBrand(TvKind value) {
    setState(() {
      kind = value;
      host = null;
      found = [];
      searched = false;
      check = null;
      guideIndex = 0;
      force = false;
    });
    go(value == TvKind.samsung ? _Step.samsung : _Step.find);
  }

  /// Kayıtlı TV'ye doğrudan kurulum (güncelleme ya da yeniden kurulum).
  Future<void> reinstallSaved(SavedTv tv) async {
    setState(() {
      kind = tv.kind;
      host = tv.host;
      tvName = tv.name;
      force = true;
      guideIndex = 0;
    });
    final status = await TvBridge.check(tv.kind, tv.host);
    if (!mounted) return;
    setState(() => check = status);
    if (status.ready && (tv.kind != TvKind.lg || status.hasKey)) {
      go(_Step.install);
      install();
    } else {
      go(_Step.guide);
    }
  }

  void back() {
    switch (step) {
      case _Step.brand:
        Navigator.of(context).pop();
      case _Step.samsung || _Step.find:
        go(_Step.brand);
      case _Step.guide:
        if (guideIndex > 0) {
          setState(() => guideIndex--);
          startPolling();
        } else {
          go(_Step.find);
        }
      case _Step.install:
        if (installing) {
          TvBridge.cancel();
          return;
        }
        setState(() => guideIndex = guideSteps.length - 1);
        go(_Step.guide);
      case _Step.done:
        Navigator.of(context).pop();
    }
  }

  // ------------------------------------------------------------------------------------------- arama

  Future<void> search() async {
    final current = kind;
    if (current == null || searching) return;
    setState(() {
      searching = true;
      manualError = null;
    });
    final list = await TvBridge.find(current);
    if (!mounted || kind != current) return;
    setState(() {
      searching = false;
      searched = true;
      found = list;
    });
  }

  Future<void> useManual() async {
    final address = await TvBridge.normalize(manualController.text);
    if (!mounted) return;
    if (address == null) {
      setState(() => manualError = L.t('Bu bir IP adresine benzemiyor. Örnek: 192.168.1.40', 'This does not look like an IP address. Example: 192.168.1.40'));
      return;
    }
    FocusScope.of(context).unfocus();
    selectTv(address, kind?.title ?? 'TV');
  }

  Future<void> selectTv(String address, String name) async {
    setState(() {
      host = address;
      tvName = name;
      guideIndex = 0;
      manualError = null;
    });
    final status = await TvBridge.check(kind!, address);
    if (!mounted) return;
    setState(() => check = status);
    // Geliştirici modu zaten açıksa adımlar atlanır.
    if (status.ready && (kind == TvKind.android || status.hasKey)) {
      go(_Step.install);
    } else {
      if (status.ready && kind == TvKind.lg) guideIndex = 3; // yalnız Key Server kaldı
      go(_Step.guide);
    }
  }

  // ------------------------------------------------------------------------------------------- canlı denetim

  void startPolling() {
    poll?.cancel();
    final current = guideSteps.elementAtOrNull(guideIndex);
    if (current == null || current.check == _Check.none) return;
    poll = Timer.periodic(const Duration(seconds: 3), (_) => probe());
    probe();
  }

  Future<void> probe() async {
    final current = kind;
    if (polling || current == null) return;
    polling = true;
    try {
      var address = host;
      if (address == null && current == TvKind.android) {
        // TV hata ayıklama açılmadan ağda görünmez: açılınca burada bulunur.
        final list = await TvBridge.find(current);
        if (list.isNotEmpty) {
          address = list.first.host;
          if (mounted) setState(() => host = address);
        }
      }
      if (address == null) return;
      final status = await TvBridge.check(current, address);
      if (mounted) setState(() => check = status);
    } finally {
      polling = false;
    }
  }

  bool stepDone(_GuideStep s) => switch (s.check) {
        _Check.none => false,
        _Check.ready => check?.ready == true,
        _Check.keyServer => check?.keyServer == true,
      };

  void nextGuide() {
    if (guideIndex + 1 < guideSteps.length) {
      setState(() => guideIndex++);
      startPolling();
    } else {
      go(_Step.install);
    }
  }

  // ------------------------------------------------------------------------------------------- kurulum

  bool get needsPassphrase => kind == TvKind.lg && check?.hasKey != true;

  Future<void> install() async {
    final current = kind;
    final address = host;
    if (current == null || address == null || installing) return;
    final pass = passController.text.trim();
    if (current == TvKind.lg && needsPassphrase && pass.isEmpty) {
      setState(() => result = TvInstallResult(ok: false, error: 'WRONG_PASSPHRASE', detail: L.t('parola boş', 'passphrase is empty')));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      installing = true;
      result = null;
      stage = 'connecting';
    });
    final outcome = await TvBridge.install(current, address, name: tvName, passphrase: needsPassphrase ? pass : null, force: force);
    if (!mounted) return;
    setState(() {
      installing = false;
      result = outcome;
      if (outcome.ok) step = _Step.done;
      // Kayıtlı anahtar geçmediyse parola yeniden sorulur.
      if (outcome.error == 'KEY_REFUSED' || outcome.error == 'WRONG_PASSPHRASE') check = TvCheck(check?.ready ?? false, check?.keyServer ?? false, false);
    });
    if (outcome.ok) TvBridge.saved().then((value) => mounted ? setState(() => saved = value) : null);
  }

  // ------------------------------------------------------------------------------------------- görünüm

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: step == _Step.brand || step == _Step.done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: GlassScaffold(
        title: L.t('TV Uygulamasını Kur', 'Install the TV App'),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey('$step-$guideIndex'),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: switch (step) {
                _Step.brand => brandView(),
                _Step.samsung => samsungView(),
                _Step.find => findView(),
                _Step.guide => guideView(),
                _Step.install => installView(),
                _Step.done => doneView(),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget progress(int index, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: i <= index ? Tokens.accent : Tokens.surfaceHigh,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(L.t('ADIM ${index + 1} / 4', 'STEP ${index + 1} / 4'), style: Txt.footnote.copyWith(color: Tokens.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(title, style: Txt.title2),
          ],
        ),
      );

  // ----- 1. marka

  List<Widget> brandView() {
    final tv = saved;
    return [
      progress(0, L.t('TV\'nin markası ne?', 'What brand is your TV?')),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Text(
            L.t(
              'Altyazıyı TV\'de gösteren GameTranslator uygulamasını telefondan TV\'ne kuracağız. Telefon ve TV aynı Wi-Fi '
                  'ağında olsun.',
              'We will install the GameTranslator app that shows the subtitles on your TV, from your phone. The phone and TV must be on '
                  'the same Wi-Fi network.',
            ),
            style: Txt.subhead.copyWith(color: Tokens.textSecondary)),
      ),
      if (tv != null) ...[
        GroupHeader(L.t('KAYITLI TV', 'SAVED TV')),
        Group(
          inset: 60,
          children: [
            Cell(
              icon: CupertinoIcons.tv_fill,
              iconColor: Tokens.success,
              title: tv.name.isEmpty ? tv.kind.title : tv.name,
              subtitle: L.t('${tv.host} · TV\'de ${tv.version ?? '?'} · telefonda ${bundled[tv.kind] ?? '?'}', '${tv.host} · on TV ${tv.version ?? '?'} · on phone ${bundled[tv.kind] ?? '?'}'),
              trailing: tv.version != null && bundled[tv.kind] != null && _newer(bundled[tv.kind]!, tv.version!)
                  ? Pill(text: L.t('Güncelleme var', 'Update available'), color: Tokens.warning)
                  : null,
            ),
            Cell(
              title: tv.version != null && bundled[tv.kind] != null && _newer(bundled[tv.kind]!, tv.version!) ? L.t('Güncelle', 'Update') : L.t('Yeniden kur', 'Reinstall'),
              titleColor: Tokens.accent,
              onTap: () => reinstallSaved(tv),
            ),
          ],
        ),
      ],
      GroupHeader(L.t('MARKA', 'BRAND')),
      Group(
        inset: 60,
        children: [
          Cell(
            icon: CupertinoIcons.tv,
            iconColor: Tokens.success,
            title: 'Android TV / Google TV',
            subtitle: L.t('TCL, Sony, Philips, Xiaomi, Vestel, Arçelik, Beko, Grundig… Ana ekranda Google Play ya da "Google TV" yazar.', 'TCL, Sony, Philips, Xiaomi, Vestel, Arçelik, Beko, Grundig… The home screen says Google Play or "Google TV".'),
            chevron: true,
            onTap: () => chooseBrand(TvKind.android),
          ),
          Cell(
            icon: CupertinoIcons.tv,
            iconColor: Tokens.danger,
            title: 'LG',
            subtitle: L.t('webOS. Ana ekranda "LG Content Store" ve alt şeritte renkli uygulama kartları bulunur.', 'webOS. The home screen has "LG Content Store" and colorful app cards in the bottom strip.'),
            chevron: true,
            onTap: () => chooseBrand(TvKind.lg),
          ),
          Cell(
            icon: CupertinoIcons.tv,
            iconColor: Tokens.accent,
            title: 'Samsung',
            subtitle: L.t('Tizen, 2019 ve sonrası. Ana ekranda "Samsung TV Plus" ve "Smart Hub" bulunur.', 'Tizen, 2019 and later. The home screen has "Samsung TV Plus" and "Smart Hub".'),
            chevron: true,
            onTap: () => chooseBrand(TvKind.samsung),
          ),
        ],
      ),
      GroupFooter(L.t(
        'Emin değil misin? TV\'nin Ayarlar › Destek (ya da Hakkında) ekranında model ve işletim sistemi yazar. '
            'Vestel/Arçelik/Beko/Grundig\'in Linux modelleri, Philips Saphi ve Titan OS desteklenmiyor.',
        'Not sure? The model and operating system are listed in the TV\'s Settings › Support (or About) screen. '
            'Linux models of Vestel/Arçelik/Beko/Grundig, Philips Saphi and Titan OS are not supported.',
      )),
    ];
  }

  // ----- Samsung: şimdilik bilgisayardan

  List<Widget> samsungView() => [
        progress(0, L.t('Samsung: bilgisayardan kur', 'Samsung: install from a computer')),
        Notice(
          icon: CupertinoIcons.desktopcomputer,
          color: Tokens.warning,
          title: L.t('Samsung TV\'ye kurulum şimdilik bilgisayardan', 'For now, Samsung TVs are set up from a computer'),
          text: L.t(
            'Samsung, uygulamanın her TV için Samsung hesabıyla ayrıca imzalanmasını istiyor. Telefondan kurulum henüz hazır '
                'değil; bilgisayardaki GameTranslator bunu kendisi yapar. Kurulum bir kez yapılır, sonra bilgisayar gerekmez.',
            'Samsung requires the app to be signed separately for each TV with a Samsung account. Installing from the phone is not ready '
                'yet; GameTranslator on the computer does this itself. Setup is done once, after that the computer is not needed.',
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          icon: CupertinoIcons.list_number,
          title: L.t('Kısaca adımlar', 'Steps in brief'),
          children: [
            _Numbered(1, L.t('TV\'de Uygulamalar ekranını aç, kumandayla 1 2 3 4 5 tuşlarına bas.', 'On the TV open the Apps screen and press 1 2 3 4 5 on the remote.')),
            _Numbered(2, L.t('"Developer mode"u "On" yap, "Host PC IP" alanına BİLGİSAYARIN adresini yaz, OK\'e bas.', 'Set "Developer mode" to "On", enter your COMPUTER\'s address in the "Host PC IP" field and press OK.')),
            _Numbered(3, L.t('TV\'yi güç tuşunu basılı tutarak tam kapatıp aç.', 'Fully turn the TV off by holding the power button, then turn it on again.')),
            _Numbered(4, L.t('Bilgisayarda GameTranslator\'ın TV adımında Samsung TV\'ni seç ve açılan sayfada Samsung hesabınla giriş yap.', 'In the TV step of GameTranslator on the computer, pick your Samsung TV and sign in with your Samsung account on the page that opens.')),
          ],
        ),
        const SizedBox(height: 16),
        GlowButton(
          icon: CupertinoIcons.book_fill,
          label: L.t('Rehberde ayrıntılı göster', 'Show details in the Guide'),
          onPressed: () => Navigator.of(context).push(appleRoute<void>((_) => const GuideChapterPage(index: 3))),
        ),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => go(_Step.brand), child: Text(L.t('Başka marka seç', 'Choose another brand'))),
      ];

  // ----- 2. TV'yi bul

  List<Widget> findView() {
    final current = kind!;
    final android = current == TvKind.android;
    final phoneHint = phone == null
        ? ''
        : L.t('Telefonun adresi $phone; TV\'ninki ilk üç bölümde aynı olmalı.', 'The phone\'s address is $phone; the TV\'s should match it in the first three parts.');
    return [
      progress(1, L.t('TV\'ni bul', 'Find your TV')),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        child: Text(
          android
              ? L.t(
                  'Ağda hata ayıklaması açık Android TV\'ler aranıyor. Hata ayıklamayı henüz açmadıysan TV burada görünmez; '
                      'sorun değil, "Adımları göster" ile devam et.',
                  'Searching for Android TVs with debugging turned on in the network. If you have not turned on debugging yet, the TV will not appear here; '
                      'that is fine, continue with "Show steps".',
                )
              : L.t('Telefonla aynı ağdaki LG TV\'ler aranıyor. TV açık olsun.', 'Searching for LG TVs on the same network as the phone. Keep the TV on.'),
          style: Txt.subhead.copyWith(color: Tokens.textSecondary),
        ),
      ),
      GroupHeader(searching ? L.t('ARANIYOR…', 'SEARCHING…') : L.t('BULUNAN TV\'LER', 'TVS FOUND')),
      Group(
        inset: 60,
        children: [
          if (searching)
            Cell(title: L.t('Ağ taranıyor, birkaç saniye sürer…', 'Scanning the network, this takes a few seconds…'), trailing: const CupertinoActivityIndicator())
          else if (found.isEmpty)
            Cell(title: searched ? L.t('TV bulunamadı', 'No TV found') : L.t('Henüz aranmadı', 'Not searched yet'), subtitle: searched ? L.t('Yenile\'ye dokun ya da adresi elle yaz.', 'Tap Refresh or type the address manually.') : null),
          for (final tv in found)
            Cell(
              icon: CupertinoIcons.tv_fill,
              iconColor: tv.ready ? Tokens.success : Tokens.gray,
              title: tv.name,
              subtitle: tv.host,
              trailing: tv.ready ? Pill(text: L.t('Hazır', 'Ready'), color: Tokens.success) : null,
              chevron: true,
              onTap: () => selectTv(tv.host, tv.name),
            ),
          Cell(title: L.t('Yenile', 'Refresh'), titleColor: Tokens.accent, onTap: searching ? null : search),
        ],
      ),
      GroupHeader(L.t('ADRESİ ELLE YAZ', 'ENTER ADDRESS MANUALLY')),
      Glass(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: manualController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: ipAddressFormatters,
              decoration: InputDecoration(hintText: L.t('ör. 192.168.1.40', 'e.g. 192.168.1.40'), errorText: manualError),
              onSubmitted: (_) => useManual(),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: useManual, child: Text(L.t('Bu adresi kullan', 'Use this address'))),
          ],
        ),
      ),
      GroupFooter(android
          ? '${L.t('TV\'nin adresi: Ayarlar › Ağ ve İnternet › bağlı olduğun Wi-Fi ağının adı (Google TV: Ayarlar › Ağ ve İnternet). ', 'The TV\'s address: Settings › Network & Internet › the name of the Wi-Fi network you are connected to (Google TV: Settings › Network & Internet). ')}$phoneHint'
          : '${L.t('TV\'nin adresi: Ayarlar › Genel › Ağ › Wi-Fi Bağlantısı › Gelişmiş Wi-Fi Ayarları (modele göre Ayarlar › Ağ). ', 'The TV\'s address: Settings › General › Network › Wi-Fi Connection › Advanced Wi-Fi Settings (Settings › Network on some models). ')}$phoneHint'),
      if (android) ...[
        const SizedBox(height: 16),
        GlowButton(
          label: L.t('Adımları göster', 'Show steps'),
          icon: CupertinoIcons.list_number,
          onPressed: () {
            setState(() => guideIndex = 0);
            go(_Step.guide);
          },
        ),
      ],
    ];
  }

  // ----- 3. geliştirici modu

  List<Widget> guideView() {
    final steps = guideSteps;
    final index = guideIndex.clamp(0, steps.length - 1);
    final s = steps[index];
    final done = stepDone(s);
    final waiting = s.check != _Check.none && !done;
    return [
      progress(2, kind == TvKind.android ? L.t('Hata ayıklamayı aç', 'Turn on debugging') : L.t('Geliştirici modunu aç', 'Turn on developer mode')),
      Glass(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: done ? Tokens.success : Tokens.accent, shape: BoxShape.circle),
                  child: done
                      ? const Icon(CupertinoIcons.checkmark_alt, size: 20, color: Colors.white)
                      : Text('${index + 1}', style: Txt.headline.copyWith(color: Colors.white)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(s.title, style: Txt.title3)),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Text(L.t('${index + 1}. adım, toplam ${steps.length}', 'Step ${index + 1} of ${steps.length}'), style: Txt.footnote.copyWith(color: Tokens.textSecondary)),
            ),
            const SizedBox(height: 14),
            Text(s.body, style: Txt.callout),
            if (s.copy != null) ...[
              const SizedBox(height: 12),
              Glass(
                radius: 14,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: SelectableText(s.copy!, style: Txt.subhead.copyWith(fontWeight: FontWeight.w600))),
                    IconButton(
                      tooltip: L.t('Kopyala', 'Copy'),
                      icon: const Icon(CupertinoIcons.doc_on_clipboard, color: Tokens.accent),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: s.copy!));
                        toast(context, L.t('Adres kopyalandı', 'Address copied'));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      if (s.check != _Check.none) ...[
        const SizedBox(height: 12),
        done
            ? Notice(
                icon: CupertinoIcons.checkmark_circle_fill,
                color: Tokens.success,
                compact: true,
                text: s.check == _Check.keyServer ? L.t('Key Server açık. Devam edebilirsin.', 'Key Server is on. You can continue.') : L.t('TV hazır. Devam edebilirsin.', 'The TV is ready. You can continue.'),
              )
            : Glass(
                radius: 18,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    const CupertinoActivityIndicator(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        host == null ? L.t('TV ağda aranıyor…', 'Looking for the TV on the network…') : L.t('TV bekleniyor ($host)…', 'Waiting for the TV ($host)…'),
                        style: Txt.subhead.copyWith(color: Tokens.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
      ],
      if (s.different != null) ...[
        const SizedBox(height: 12),
        _Expandable(title: L.t('Menü farklı görünüyorsa', 'If your menu looks different'), text: s.different!),
      ],
      const SizedBox(height: 18),
      GlowButton(
        label: waiting ? L.t('Bunu yaptım', 'I did this') : (index + 1 < steps.length ? L.t('Bunu yaptım', 'I did this') : L.t('Kuruluma geç', 'Go to installation')),
        icon: CupertinoIcons.checkmark_alt,
        // Canlı denetimde TV henüz görünmüyorsa yine de geçilebilir: bazı ağlar denetimi engeller, kurulum kendisi dener.
        onPressed: (s.check == _Check.ready && host == null && waiting) ? null : nextGuide,
      ),
      if (s.check == _Check.ready && host == null && waiting)
        GroupFooter(L.t('TV ağda görünene kadar bekleniyor. Görünmüyorsa geri dönüp TV\'nin adresini elle yaz.', 'Waiting until the TV shows up on the network. If it does not, go back and type the TV\'s address manually.')),
    ];
  }

  // ----- 4. kurulum

  List<Widget> installView() {
    final current = kind!;
    final failure = result != null && !result!.ok ? result : null;
    final text = failure == null ? null : tvErrorText(failure.error, current);
    return [
      progress(3, L.t('Kur', 'Install')),
      Group(
        inset: 60,
        children: [
          Cell(icon: CupertinoIcons.tv_fill, iconColor: Tokens.purple, title: tvName.isEmpty ? current.title : tvName, subtitle: host),
          Cell(icon: CupertinoIcons.cube_box_fill, iconColor: Tokens.indigo, title: L.t('Kurulacak sürüm', 'Version to install'), value: bundled[current] ?? '?'),
        ],
      ),
      if (current == TvKind.lg && needsPassphrase) ...[
        GroupHeader(L.t('TV EKRANINDAKİ PAROLA', 'PASSPHRASE ON THE TV SCREEN')),
        Glass(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: passController,
                enabled: !installing,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                maxLength: 10,
                style: Txt.title2.copyWith(letterSpacing: 6),
                textAlign: TextAlign.center,
                decoration: InputDecoration(hintText: L.t('ör. 2FEEB2', 'e.g. 2FEEB2'), counterText: ''),
                onSubmitted: (_) => install(),
              ),
            ],
          ),
        ),
        GroupFooter(L.t(
          'Developer Mode uygulamasında Key Server açıkken ekranın sol altında "Passphrase" olarak görünen 6 karakter. '
              'Yalnız bu ilk kurulumda sorulur.',
          'The 6 characters shown as "Passphrase" at the bottom left of the screen in the Developer Mode app while Key Server is on. '
              'It is only asked for during this first installation.',
        )),
      ],
      if (current == TvKind.android && !installing && failure == null)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Notice(
            icon: CupertinoIcons.hand_raised_fill,
            title: L.t('TV\'de bir soru çıkacak', 'A question will appear on the TV'),
            text: L.t(
              '"USB hata ayıklamaya izin verilsin mi?" sorusunda "Bu bilgisayardan her zaman izin ver"i işaretle ve "İzin ver"i seç. '
                  'Soru yalnız ilk kurulumda çıkar.',
              'When the TV asks "Allow USB debugging?", tick "Always allow from this computer" and choose "Allow". '
                  'The question only appears during the first installation.',
            ),
          ),
        ),
      if (installing) ...[
        const SizedBox(height: 14),
        Glass(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const CupertinoActivityIndicator(),
                  const SizedBox(width: 12),
                  Expanded(child: Text(tvStageText(stage), style: Txt.headline)),
                ],
              ),
              if (stage.startsWith('uploading:')) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: (int.tryParse(stage.substring(10)) ?? 0) / 100, borderRadius: BorderRadius.circular(4)),
              ],
            ],
          ),
        ),
        if (stage == 'approve') ...[
          const SizedBox(height: 12),
          Notice(
            icon: CupertinoIcons.tv,
            color: Tokens.warning,
            title: L.t('Şimdi TV\'ye bak', 'Look at the TV now'),
            text: L.t(
              'TV "USB hata ayıklamaya izin verilsin mi?" diye soruyor. "Bu bilgisayardan her zaman izin ver"i işaretle ve '
                  '"İzin ver"i seç. Kurulum sonra kendiliğinden sürer.',
              'The TV is asking "Allow USB debugging?". Tick "Always allow from this computer" and '
                  'choose "Allow". The installation then continues by itself.',
            ),
          ),
        ],
        const SizedBox(height: 10),
        GroupFooter(L.t('Telefonun ekranını açık tut. Kurulum genellikle bir dakikadan kısa sürer.', 'Keep the phone screen on. Installation usually takes less than a minute.')),
      ],
      if (failure != null) ...[
        const SizedBox(height: 14),
        Notice(icon: CupertinoIcons.exclamationmark_triangle_fill, color: Tokens.danger, title: text!.title, text: text.fix),
        if ((failure.detail ?? '').isNotEmpty && failure.error != 'CANCELLED') ...[
          const SizedBox(height: 10),
          _Expandable(title: L.t('TV\'nin söylediği', 'What the TV said'), text: failure.detail!),
        ],
      ],
      const SizedBox(height: 18),
      if (installing)
        OutlinedButton(onPressed: TvBridge.cancel, child: Text(L.t('Durdur', 'Stop')))
      else ...[
        GlowButton(
          icon: failure == null ? CupertinoIcons.arrow_down_circle_fill : CupertinoIcons.arrow_clockwise,
          label: failure == null ? L.t('TV\'ye kur', 'Install on TV') : L.t('Tekrar dene', 'Try again'),
          onPressed: install,
        ),
        if (failure != null) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () {
              setState(() => guideIndex = failure.error == 'KEY_SERVER_OFF' ? guideSteps.length - 1 : 0);
              go(_Step.guide);
            },
            child: Text(L.t('Adımlara dön', 'Back to the steps')),
          ),
        ],
      ],
    ];
  }

  // ----- 5. tamam

  List<Widget> doneView() {
    final r = result!;
    final leftText = r.hoursLeft == null ? '' : L.t('Kalan süre: ${r.hoursLeft} saat. ', 'Time left: ${r.hoursLeft} hours. ');
    return [
      const SizedBox(height: 24),
      const Center(child: Icon(CupertinoIcons.checkmark_seal_fill, size: 84, color: Tokens.success)),
      const SizedBox(height: 16),
      Center(child: Text(r.installed ? L.t('TV uygulaması kuruldu', 'TV app installed') : L.t('TV uygulaması zaten güncel', 'TV app is already up to date'), style: Txt.title2, textAlign: TextAlign.center)),
      const SizedBox(height: 6),
      Center(child: Text(L.t('Sürüm ${r.version ?? '?'}', 'Version ${r.version ?? '?'}'), style: Txt.subhead.copyWith(color: Tokens.textSecondary))),
      const SizedBox(height: 22),
      Notice(
        icon: CupertinoIcons.tv_fill,
        color: r.launched ? Tokens.success : Tokens.accent,
        title: r.launched ? L.t('TV\'de GameTranslator açıldı', 'GameTranslator opened on the TV') : L.t('TV\'de GameTranslator\'ı aç', 'Open GameTranslator on the TV'),
        text: r.launched
            ? L.t('Çeviriyi telefonda başlattığında TV uygulaması telefonu ağda kendisi bulur.', 'When you start the translation on the phone, the TV app finds the phone on the network by itself.')
            : L.t('TV\'nin uygulamalar listesinde GameTranslator\'ı bul ve aç. Çeviriyi başlattığında telefonu kendisi bulur.', 'Find GameTranslator in the TV\'s apps list and open it. When you start the translation, it finds the phone by itself.'),
      ),
      if (kind == TvKind.lg) ...[
        const SizedBox(height: 12),
        Notice(
          icon: CupertinoIcons.clock_fill,
          color: Tokens.warning,
          title: L.t('LG geliştirici modu süresi', 'LG developer mode time'),
          text: leftText +
              L.t(
                'Süre dolarsa TV uygulaması silinir. Uzun süre '
                    'kullanmayacaksan TV\'deki Developer Mode uygulamasında "EXTEND"e bas; bu sayfadan yeniden kurmak da süreyi uzatır.',
                'If the time runs out, the TV app is removed. If you will not use it for a long time, press '
                    '"EXTEND" in the Developer Mode app on the TV; installing again from this page also extends the time.',
              ),
        ),
      ],
      if (kind == TvKind.android) ...[
        const SizedBox(height: 12),
        Notice(
          icon: CupertinoIcons.info_circle_fill,
          text: L.t(
            'İstersen artık TV\'de USB hata ayıklamayı kapatabilirsin. Yeni bir sürümü kurmak için yeniden açman gerekir.',
            'You can now turn off USB debugging on the TV if you like. You will need to turn it on again to install a newer version.',
          ),
        ),
      ],
      const SizedBox(height: 22),
      GlowButton(label: L.t('Bitti', 'Done'), onPressed: () => Navigator.of(context).pop()),
    ];
  }
}

bool _newer(String a, String b) {
  List<int> parts(String v) => v.split(RegExp(r'[.-]')).map((p) => int.tryParse(p) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final l = i < x.length ? x[i] : 0, r = i < y.length ? y[i] : 0;
    if (l != r) return l > r;
  }
  return false;
}

class _Numbered extends StatelessWidget {
  const _Numbered(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Tokens.accentSoft, shape: BoxShape.circle),
              child: Text('$number', style: Txt.footnote.copyWith(fontWeight: FontWeight.w700, color: Tokens.accent)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: Txt.subhead)),
          ],
        ),
      );
}

/// Dokununca açılan ek açıklama.
class _Expandable extends StatefulWidget {
  const _Expandable({required this.title, required this.text});

  final String title;
  final String text;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool open = false;

  @override
  Widget build(BuildContext context) => Glass(
        radius: 18,
        clip: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Cell(
              icon: CupertinoIcons.question_circle_fill,
              iconColor: Tokens.gray,
              title: widget.title,
              trailing: Icon(open ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down, size: 16, color: Tokens.textSecondary),
              onTap: () => setState(() => open = !open),
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: SelectableText(widget.text, style: Txt.subhead.copyWith(color: const Color(0xD9EBEBF5))),
              ),
          ],
        ),
      );
}
