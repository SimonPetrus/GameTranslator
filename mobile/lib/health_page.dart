// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'bridge.dart';
import 'main.dart';
import 'ui.dart';

/// Sistem durumu: ağ, PS5, görüntü, yazı okuma, çeviri, TV ve paketler tek bakışta. Açıkken 2 saniyede bir yenilenir.
class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  HealthInfo? info;
  bool loaded = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    final next = await Bridge.health();
    if (!mounted) return;
    setState(() {
      info = next;
      loaded = true;
    });
  }

  static const engineNames = {'google': 'Google', 'deepl': 'DeepL', 'gemini': 'Gemini', 'mlkit': 'Cihazda'};

  @override
  Widget build(BuildContext context) {
    final h = info;
    return GlassScaffold(
      title: 'Sistem Durumu',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          if (h == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 0),
              child: loaded
                  ? Text('Durum bilgisi alınamadı.', textAlign: TextAlign.center, style: Txt.subhead.copyWith(color: Tokens.textSecondary))
                  : const Center(child: CupertinoActivityIndicator(radius: 14)),
            )
          else ...[
            Group(children: rows(h)),
            const GroupFooter('Yeşil: sorun yok. Kırmızı: ilgilenmek gerekir. Gri: şu an kapalı ya da bekliyor.'),
          ],
        ],
      ),
    );
  }

  List<Widget> rows(HealthInfo h) {
    final streaming = h.streamRunning;
    final consoleState = h.consoleState.isEmpty ? '' : ' · ${h.consoleState}';
    final consoleHost = h.consoleHost.isEmpty ? '' : h.consoleHost;
    final engine = engineNames[h.engine] ?? h.engine;

    final (Color, String) translator;
    if (!h.translatorLastOk) {
      translator = (Tokens.danger, 'Son çeviri başarısız${h.translatorLastError.isEmpty ? '' : ': ${h.translatorLastError}'}');
    } else if (h.geminiPausedSeconds > 0) {
      translator = (Tokens.warning, 'Gemini ${h.geminiPausedSeconds} sn bekliyor; bu sürede Google kullanılır');
    } else {
      translator = (streaming ? Tokens.success : Tokens.gray, 'Sorun yok');
    }

    return [
      _StatusRow(
        color: h.network ? Tokens.success : Tokens.danger,
        title: 'Ağ',
        detail: h.network ? 'İnternet bağlantısı var' : 'Bağlantı yok',
      ),
      _StatusRow(
        color: h.phoneAddress.isEmpty ? Tokens.danger : Tokens.success,
        title: 'Telefon adresi',
        detail: h.phoneAddress.isEmpty ? 'Wi-Fi adresi yok' : h.phoneAddress,
      ),
      _StatusRow(
        color: !h.consoleRegistered ? Tokens.danger : (streaming ? Tokens.success : Tokens.gray),
        title: 'PS5',
        detail: !h.consoleRegistered ? 'Eşleşmemiş' : 'Eşleşti${consoleHost.isEmpty ? '' : ' · $consoleHost'}$consoleState',
      ),
      _StatusRow(
        color: streaming ? Tokens.success : Tokens.gray,
        title: 'Görüntü',
        detail: streaming ? 'Akıyor · ${h.fps.toStringAsFixed(1)} fps' : 'Kapalı',
      ),
      _StatusRow(
        color: !streaming ? Tokens.gray : (h.stuckRecoveries > 0 ? Tokens.warning : Tokens.success),
        title: 'Yazı okuma',
        detail: [
          h.lastReadMs > 0 ? 'Son okuma ${h.lastReadMs} ms' : 'Henüz okuma yok',
          if (h.readerLanguage.isNotEmpty) h.readerLanguage,
          if (h.stuckRecoveries > 0) '${h.stuckRecoveries} toparlanma',
        ].join(' · '),
      ),
      _StatusRow(
        color: translator.$1,
        title: 'Çeviri${engine.isEmpty ? '' : ' · $engine'}',
        detail: translator.$2,
      ),
      _StatusRow(
        color: h.tvClients > 0 ? Tokens.success : (streaming ? Tokens.warning : Tokens.gray),
        title: 'TV',
        detail: '${h.tvClients} TV bağlı${h.tvPort > 0 ? ' · port ${h.tvPort}' : ''}',
      ),
      _StatusRow(
        color: h.packsEnabled ? Tokens.success : Tokens.gray,
        title: 'Oyun paketi',
        detail: !h.packsEnabled ? 'Kapalı' : (h.packGame.isEmpty ? 'Açık · oyun bulunamadı' : h.packGame),
      ),
      _StatusRow(
        color: h.cacheEntries > 0 ? Tokens.success : Tokens.gray,
        title: 'Çeviri hafızası',
        detail: '${h.cacheEntries} kayıt',
      ),
    ];
  }
}

/// Solda renkli durum noktası, ortada başlık ve ayrıntı.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.color, required this.title, required this.detail});

  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Txt.body),
                Text(detail, style: Txt.footnote.copyWith(color: Tokens.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
