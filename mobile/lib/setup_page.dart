// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'bridge.dart';
import 'guide_page.dart';
import 'l10n.dart';
import 'main.dart';
import 'psn.dart';
import 'ui.dart';

/// Kurulum: 1) PSN girişi (hesap kimliği), 2) PS5'i bul ve "Cihaz Eşleştir" koduyla eşleştir.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.setup, required this.onChanged});

  final SetupInfo setup;
  final Future<void> Function() onChanged;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final hostController = TextEditingController();
  final pinController = TextEditingController();
  final pinFocus = FocusNode();
  List<FoundConsole> consoles = [];
  bool searching = false;
  bool searched = false;
  bool pairing = false;
  bool manualHost = false;
  String? error;

  @override
  void initState() {
    super.initState();
    pinFocus.addListener(() => setState(() {}));
    if (widget.setup.hasAccount) search();
  }

  @override
  void didUpdateWidget(SetupPage old) {
    super.didUpdateWidget(old);
    if (widget.setup.hasAccount && !old.setup.hasAccount) search();
  }

  @override
  void dispose() {
    hostController.dispose();
    pinController.dispose();
    pinFocus.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    final accountId = await Navigator.of(context).push<Uint8List>(appleRoute((_) => const PsnLoginPage()));
    if (accountId == null) return;
    await Bridge.setAccountId(accountId);
    await widget.onChanged();
  }

  Future<void> search() async {
    if (searching) return;
    setState(() {
      searching = true;
      error = null;
    });
    final typed = hostController.text.trim();
    final found = await Bridge.discover(hosts: typed.isEmpty ? const [] : [typed]);
    if (!mounted) return;
    setState(() {
      searching = false;
      searched = true;
      consoles = found;
      if (found.length == 1 && hostController.text.trim().isEmpty) hostController.text = found.first.host;
    });
  }

  Future<void> pair() async {
    final host = hostController.text.trim();
    final digits = pinController.text.replaceAll(RegExp(r'\D'), '');
    final pin = int.tryParse(digits);
    if (host.isEmpty) {
      setState(() => error = L.t('Önce PS5\'i seç ya da IP adresini yaz.', 'First pick your PS5 or type its IP address.'));
      return;
    }
    if (pin == null || digits.length != 8) {
      setState(() => error = L.t('PS5 ekranındaki 8 haneli kodu gir.', 'Enter the 8-digit code shown on the PS5 screen.'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      pairing = true;
      error = null;
    });
    final result = await Bridge.register(host, pin);
    if (!mounted) return;
    setState(() {
      pairing = false;
      error = result.ok ? null : (result.detail ?? L.t('Eşleştirme başarısız.', 'Pairing failed.'));
    });
    if (result.ok) await widget.onChanged();
  }

  /// Rehber, o an yapılan adımın bölümü açık gelir: PS5 hazırlığı ya da eşleştirme.
  void showGuide() {
    Navigator.of(context).push(appleRoute<void>((_) => GuideChapterPage(index: widget.setup.hasAccount ? 2 : 1)));
  }

  @override
  Widget build(BuildContext context) {
    final hasAccount = widget.setup.hasAccount;
    final host = hostController.text.trim();
    // Elle yazılmış adres bulunan konsollardan biri değilse alan açık kalır; yoksa yazılan adres gizlenirdi.
    final typedHost = host.isNotEmpty && consoles.every((console) => console.host != host);
    final showHostField = manualHost || typedHost || (searched && !searching && consoles.isEmpty);
    return GlassScaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GtLogo(size: 34, glow: false),
                    SizedBox(width: 14),
                    Text('GameTranslator', style: Txt.headline),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Tooltip(
                    message: L.t('Rehber', 'Guide'),
                    child: Material(
                      color: Tokens.surface,
                      shape: const CircleBorder(side: BorderSide(color: Tokens.border)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: showGuide,
                        child: const SizedBox(width: 42, height: 42, child: Icon(CupertinoIcons.question, size: 20)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(L.t('Kurulum', 'Setup'), textAlign: TextAlign.center, style: Txt.largeTitle),
            const SizedBox(height: 4),
            Text(
              hasAccount ? L.t('PS5 ile bağlantıyı tamamla.', 'Finish connecting to your PS5.') : L.t('Önce PlayStation hesabını bağla.', 'First link your PlayStation account.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tokens.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 22),
            _Stepper(step: hasAccount ? 2 : 1),
            const SizedBox(height: 22),
            _StepCard(
              icon: CupertinoIcons.person_fill,
              title: L.t('PSN ile giriş yap', 'Sign in with PSN'),
              subtitle: L.t('PlayStation Network hesabını bağla.', 'Link your PlayStation Network account.'),
              state: hasAccount ? _StepState.done : _StepState.active,
              doneChild: Row(
                children: [
                  Expanded(
                    child: Notice(icon: CupertinoIcons.checkmark_circle_fill, color: Tokens.success, text: L.t('PSN hesabı bağlandı.', 'PSN account linked.'), compact: true),
                  ),
                  const SizedBox(width: 4),
                  TextButton(onPressed: signIn, child: Text(L.t('Değiştir', 'Change'))),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    L.t(
                      'PS5\'teki ikinci kullanıcının (yan hesabın) PSN hesabıyla giriş yap. Böylece oyunu kendi hesabınla '
                          'oynarken kumandan TV\'den kopmaz.',
                      'Sign in with the PSN account of the second user (side account) on your PS5. That way your controller '
                          'stays connected to the TV while you play on your own account.',
                    ),
                    style: const TextStyle(color: Tokens.textSecondary, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  Notice(
                    icon: CupertinoIcons.lock_fill,
                    text: L.t(
                      'Giriş Sony\'nin kendi sayfasında yapılır. Şifren bu uygulamaya ya da başka bir yere kaydedilmez.',
                      'Sign-in happens on Sony\'s own page. Your password is not saved in this app or anywhere else.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlowButton(onPressed: signIn, icon: CupertinoIcons.arrow_right_circle_fill, label: L.t('PSN ile giriş yap', 'Sign in with PSN')),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _StepCard(
              icon: CupertinoIcons.gamecontroller_fill,
              title: L.t('PS5 ile eşleştir', 'Pair with PS5'),
              subtitle: L.t('Telefonu PS5\'inle eşleştir.', 'Pair the phone with your PS5.'),
              state: hasAccount ? _StepState.active : _StepState.waiting,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Instruction(number: 'a', text: L.t('PS5\'te ikinci kullanıcıya geç.', 'Switch to the second user on the PS5.')),
                  _Instruction(
                    number: 'b',
                    text: L.t(
                      'Ayarlar › Sistem › Uzaktan Oynatma\'da "Uzaktan Oynatmayı Etkinleştir"i aç.',
                      'In Settings › System › Remote Play, turn on "Enable Remote Play".',
                    ),
                  ),
                  _Instruction(
                    number: 'c',
                    text: L.t('"Cihaz Eşleştir"e gir. Ekranda 8 haneli bir kod görünür.', 'Open "Link Device". An 8-digit code appears on the screen.'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: Text(L.t('Bulunan konsol', 'Consoles found'), style: const TextStyle(fontWeight: FontWeight.w600))),
                      TextButton.icon(
                        onPressed: searching ? null : search,
                        icon: searching
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(CupertinoIcons.arrow_clockwise, size: 18),
                        label: Text(searching ? L.t('Aranıyor…', 'Searching…') : L.t('Yenile', 'Refresh')),
                      ),
                    ],
                  ),
                  for (final console in consoles)
                    _ConsoleTile(
                      console: console,
                      selected: hostController.text.trim() == console.host,
                      onTap: () => setState(() => hostController.text = console.host),
                    ),
                  if (searched && !searching && consoles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Notice(
                        icon: CupertinoIcons.wifi_exclamationmark,
                        color: Tokens.warning,
                        text: L.t(
                          'PS5 bulunamadı. Telefon ve PS5 aynı Wi-Fi ağında olmalı. PS5\'in IP adresini aşağıya elle de '
                              'yazabilirsin (PS5\'te Ayarlar › Ağ › Bağlantı Durumu).',
                          'PS5 not found. The phone and the PS5 must be on the same Wi-Fi network. You can also type the '
                              'PS5\'s IP address below (on the PS5: Settings › Network › Connection Status).',
                        ),
                      ),
                    ),
                  if (showHostField)
                    TextField(
                      controller: hostController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: ipAddressFormatters,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: L.t('PS5 IP adresi', 'PS5 IP address'), hintText: '192.168.1.20'),
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                        onPressed: () => setState(() => manualHost = true),
                        child: Text(L.t('IP adresini elle yaz', 'Enter IP address manually')),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text(L.t('Eşleştirme kodu', 'Pairing code'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  _PinBoxes(controller: pinController, focusNode: pinFocus, onChanged: () => setState(() {}), onSubmitted: pair),
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    Notice(icon: CupertinoIcons.exclamationmark_circle_fill, color: Tokens.danger, text: error!),
                  ],
                  const SizedBox(height: 18),
                  GlowButton(onPressed: pairing ? null : pair, busy: pairing, label: pairing ? L.t('Eşleştiriliyor…', 'Pairing…') : L.t('Eşleştir', 'Pair')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// İki adımlı ilerleme çizgisi: tamamlanan adımda tik, sıradakinde numara.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    Widget node(int number) {
      final done = number < step;
      final current = number == step;
      return Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF10233F),
          shape: BoxShape.circle,
          border: Border.all(color: done || current ? Tokens.accentText : Tokens.border, width: 2),
        ),
        child: done
            ? const Icon(CupertinoIcons.checkmark_alt, size: 20, color: Tokens.accentText)
            : Text('$number', style: TextStyle(fontWeight: FontWeight.w800, color: current ? Tokens.accentText : Tokens.textSecondary)),
      );
    }

    Widget label(int number) => Expanded(
          child: Text(
            L.t('Adım $number / 2', 'Step $number / 2'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: number == step ? Tokens.accentText : Tokens.textSecondary,
              fontWeight: number == step ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Çizgi: ulaşılan yere kadar parlak, sonrası sönük.
                Container(height: 8, decoration: BoxDecoration(color: Tokens.border, borderRadius: BorderRadius.circular(4))),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: step == 1 ? 0.25 : 1,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Tokens.accentText,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                Row(children: [Expanded(child: Center(child: node(1))), Expanded(child: Center(child: node(2)))]),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [label(1), label(2)]),
        ],
      ),
    );
  }
}

enum _StepState { waiting, active, done }

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.child,
    this.doneChild,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final _StepState state;
  final Widget child;

  /// Adım tamamlandığında içeriğin yerine görünen kısa özet.
  final Widget? doneChild;

  @override
  Widget build(BuildContext context) {
    final done = state == _StepState.done;
    final active = state == _StepState.active;
    final waiting = state == _StepState.waiting;
    final body = active ? child : (done ? doneChild : null);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: waiting ? 0.5 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: Tokens.glassFill,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: active ? Tokens.accentText.withValues(alpha: 0.8) : Tokens.border, width: active ? 1.4 : 1),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(color: Tokens.surfaceHigh, shape: BoxShape.circle),
                  child: Icon(
                    icon,
                    size: 26,
                    color: active ? Tokens.accentText : Tokens.textPrimary,
                    shadows: active ? [Shadow(color: Tokens.accent.withValues(alpha: 0.9), blurRadius: 14)] : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                      Text(
                        waiting ? L.t('Önce PSN girişini tamamla.', 'First finish the PSN sign-in.') : subtitle,
                        style: const TextStyle(color: Tokens.textSecondary, fontSize: 13.5, height: 1.3),
                      ),
                    ],
                  ),
                ),
                if (done)
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(color: Tokens.success, shape: BoxShape.circle),
                    child: const Icon(CupertinoIcons.checkmark_alt, size: 20, color: Tokens.background),
                  ),
              ],
            ),
            if (body != null) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 14),
              body,
            ],
          ],
        ),
      ),
    );
  }
}

class _Instruction extends StatelessWidget {
  const _Instruction({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Tokens.surfaceHigh, shape: BoxShape.circle),
            child: Text(number, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.1)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(text, style: const TextStyle(height: 1.35)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsoleTile extends StatelessWidget {
  const _ConsoleTile({required this.console, required this.selected, required this.onTap});

  final FoundConsole console;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? Tokens.accentSoft : Tokens.inset,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? Tokens.accentText : Tokens.border, width: selected ? 1.8 : 1),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: selected ? Tokens.accentText : Tokens.textSecondary, width: 1.8),
                    ),
                    child: selected
                        ? Container(width: 10, height: 10, decoration: const BoxDecoration(color: Tokens.accentText, shape: BoxShape.circle))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: console.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          TextSpan(text: '  ·  ${console.host}  ·  ', style: const TextStyle(color: Tokens.textSecondary)),
                          TextSpan(
                            text: console.awake ? L.t('açık', 'on') : L.t('dinlenmede', 'rest mode'),
                            style: TextStyle(color: console.awake ? Tokens.success : Tokens.warning, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sekiz kutuluk kod girişi. Yazıyı görünmez bir metin alanı tutar; kutular yalnızca gösterir.
class _PinBoxes extends StatelessWidget {
  const _PinBoxes({required this.controller, required this.focusNode, required this.onChanged, required this.onSubmitted});

  static const length = 8;

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final text = controller.text;
    return Stack(
      children: [
        Row(
          children: [
            for (var i = 0; i < length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Builder(builder: (context) {
                  final current = focusNode.hasFocus && i == (text.length < length ? text.length : length - 1);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Tokens.inset,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: current ? Tokens.accentText : Tokens.border, width: current ? 1.8 : 1),
                    ),
                    child: Text(
                      i < text.length ? text[i] : '',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                  );
                }),
              ),
            ],
          ],
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.number,
              showCursor: false,
              enableInteractiveSelection: false,
              autocorrect: false,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(length)],
              decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
              onChanged: (_) => onChanged(),
              onSubmitted: (_) => onSubmitted(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Sony'nin giriş sayfası; giriş bitince yönlendirmedeki kod hesap kimliğine çevrilip döndürülür.
class PsnLoginPage extends StatefulWidget {
  const PsnLoginPage({super.key});

  @override
  State<PsnLoginPage> createState() => _PsnLoginPageState();
}

class _PsnLoginPageState extends State<PsnLoginPage> {
  late final WebViewController controller;
  bool exchanging = false;
  int progress = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
        onNavigationRequest: (request) {
          if (!PsnAccount.isRedirect(request.url)) return NavigationDecision.navigate;
          finish(request.url);
          return NavigationDecision.prevent;
        },
        // Bazı WebView sürümleri sunucu yönlendirmesini onNavigationRequest'e sormaz; adres değişiminden de yakalanır.
        onPageStarted: (url) {
          if (PsnAccount.isRedirect(url)) finish(url);
        },
        onUrlChange: (change) {
          final url = change.url;
          if (url != null && PsnAccount.isRedirect(url)) finish(url);
        },
      ))
      ..loadRequest(PsnAccount.authorizeUrl);
  }

  Future<void> finish(String redirect) async {
    if (exchanging) return;
    final code = PsnAccount.codeFromRedirect(redirect);
    if (code == null || code.isEmpty) {
      setState(() => error = PsnAccount.errorFromRedirect(redirect) ?? L.t('Giriş tamamlanmadı.', 'Sign-in was not completed.'));
      return;
    }
    setState(() {
      exchanging = true;
      error = null;
    });
    try {
      final accountId = await PsnAccount.accountId(code);
      if (mounted) Navigator.of(context).pop(accountId);
    } on PsnException catch (failure) {
      if (mounted) {
        setState(() {
          exchanging = false;
          error = failure.message;
        });
      }
    }
  }

  /// Chiaki gibi araçlardan alınmış hesap kimliğini (base64, 8 bayt) elle girmek için.
  Future<void> enterManually() async {
    final input = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t('Hesap kimliğini elle gir', 'Enter account ID manually')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L.t(
                'Giriş sayfası açılmıyorsa, Chiaki gibi araçlardan aldığın PSN hesap kimliğini buraya yapıştırabilirsin.',
                'If the sign-in page does not open, you can paste a PSN account ID you obtained elsewhere here.',
              ),
              style: const TextStyle(color: Tokens.textSecondary, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(controller: input, autocorrect: false, decoration: InputDecoration(hintText: L.t('Base64 hesap kimliği', 'Base64 account ID'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(L.t('Vazgeç', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, input.text.trim()), child: Text(L.t('Tamam', 'OK'))),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    try {
      final bytes = base64Decode(text);
      if (bytes.length != 8) throw const FormatException();
      Navigator.of(context).pop(Uint8List.fromList(bytes));
    } on FormatException {
      setState(() => error = L.t('Hesap kimliği 8 baytlık base64 olmalı.', 'The account ID must be 8 bytes in base64.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassScaffold.navBar(
        context,
        L.t('PSN Girişi', 'PSN Sign-in'),
        actions: [
          PopupMenuButton<String>(
            color: Tokens.sheet,
            onSelected: (value) => value == 'manual' ? enterManually() : controller.loadRequest(PsnAccount.authorizeUrl),
            itemBuilder: (context) => [
              PopupMenuItem(value: 'reload', child: Text(L.t('Sayfayı yeniden yükle', 'Reload page'))),
              PopupMenuItem(value: 'manual', child: Text(L.t('Hesap kimliğini elle gir', 'Enter account ID manually'))),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: progress < 100 && !exchanging
              ? LinearProgressIndicator(value: progress / 100, minHeight: 2, backgroundColor: Colors.transparent)
              : const SizedBox(height: 2),
        ),
      ),
      body: Column(
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Notice(icon: CupertinoIcons.exclamationmark_circle_fill, color: Tokens.danger, text: error!),
            ),
          Expanded(
            child: exchanging
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(L.t('Hesap bağlanıyor…', 'Linking account…'), style: const TextStyle(color: Tokens.textSecondary)),
                      ],
                    ),
                  )
                : WebViewWidget(controller: controller),
          ),
        ],
      ),
    );
  }
}
