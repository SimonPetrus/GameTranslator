// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'bridge.dart';
import 'l10n.dart';
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

  static Map<String, String> get engineNames => {'google': 'Google', 'deepl': 'DeepL', 'gemini': 'Gemini', 'mlkit': L.t('Cihazda', 'On device')};

  @override
  Widget build(BuildContext context) {
    final h = info;
    return GlassScaffold(
      title: L.t('Sistem Durumu', 'System Status'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          if (h == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 0),
              child: loaded
                  ? Text(L.t('Durum bilgisi alınamadı.', 'Status information is unavailable.'), textAlign: TextAlign.center, style: Txt.subhead.copyWith(color: Tokens.textSecondary))
                  : const Center(child: CupertinoActivityIndicator(radius: 14)),
            )
          else ...[
            Group(children: rows(h)),
            GroupFooter(L.t('Yeşil: sorun yok. Kırmızı: ilgilenmek gerekir. Gri: şu an kapalı ya da bekliyor.', 'Green: no problem. Red: needs attention. Gray: off or waiting right now.')),
          ],
        ],
      ),
    );
  }

  /// "DeepL: kota dolu, 27 dk sonra yeniden denenecek" gibi tek satır.
  String _pausedLine(PausedEngine p) {
    final name = engineNames[p.engine] ?? p.engine;
    final minutes = (p.seconds / 60).ceil();
    final trWait = p.seconds >= 60 ? '$minutes dk' : '${p.seconds} sn';
    final enWait = p.seconds >= 60 ? '$minutes min' : '${p.seconds} s';
    switch (p.reason) {
      case 'quota':
        return L.t('$name: kota dolu, $trWait sonra yeniden denenecek', '$name: quota is full, retrying in $enWait');
      case 'connection':
        return L.t('$name: bağlantı sorunu, $trWait sonra yeniden denenecek', '$name: connection problem, retrying in $enWait');
      case 'key':
        return L.t('$name: anahtar reddedildi, $trWait sonra yeniden denenecek', '$name: key was rejected, retrying in $enWait');
      default:
        return L.t('$name: çok istek, $trWait sonra yeniden denenecek', '$name: too many requests, retrying in $enWait');
    }
  }

  List<Widget> rows(HealthInfo h) {
    final streaming = h.streamRunning;
    final consoleState = h.consoleState.isEmpty ? '' : ' · ${h.consoleState}';
    final consoleHost = h.consoleHost.isEmpty ? '' : h.consoleHost;
    final engine = engineNames[h.engine] ?? h.engine;

    final (Color, String) translator;
    if (!h.translatorLastOk) {
      translator = (Tokens.danger, '${L.t('Son çeviri başarısız', 'Last translation failed')}${h.translatorLastError.isEmpty ? '' : ': ${h.translatorLastError}'}');
    } else if (h.failoverActive) {
      final lines = [for (final p in h.failoverPaused) _pausedLine(p)];
      final current = engineNames[h.failoverCurrent] ?? h.failoverCurrent;
      lines.add(L.t('Şu an çeviren: ${current.isEmpty ? 'Google' : current}', 'Currently translating: ${current.isEmpty ? 'Google' : current}'));
      translator = (h.failoverPaused.isNotEmpty ? Tokens.warning : (streaming ? Tokens.success : Tokens.gray), lines.join('\n'));
    } else if (h.geminiPausedSeconds > 0) {
      translator = (Tokens.warning, L.t('Gemini ${h.geminiPausedSeconds} sn bekliyor; bu sürede Google kullanılır', 'Gemini is paused for ${h.geminiPausedSeconds} s; Google is used meanwhile'));
    } else {
      translator = (streaming ? Tokens.success : Tokens.gray, L.t('Sorun yok', 'No problem'));
    }

    return [
      _StatusRow(
        color: h.network ? Tokens.success : Tokens.danger,
        title: L.t('Ağ', 'Network'),
        detail: h.network ? L.t('İnternet bağlantısı var', 'Internet connection available') : L.t('Bağlantı yok', 'No connection'),
      ),
      _StatusRow(
        color: h.phoneAddress.isEmpty ? Tokens.danger : Tokens.success,
        title: L.t('Telefon adresi', 'Phone address'),
        detail: h.phoneAddress.isEmpty ? L.t('Wi-Fi adresi yok', 'No Wi-Fi address') : h.phoneAddress,
      ),
      _StatusRow(
        color: !h.consoleRegistered ? Tokens.danger : (streaming ? Tokens.success : Tokens.gray),
        title: 'PS5',
        detail: !h.consoleRegistered ? L.t('Eşleşmemiş', 'Not paired') : '${L.t('Eşleşti', 'Paired')}${consoleHost.isEmpty ? '' : ' · $consoleHost'}$consoleState',
      ),
      _StatusRow(
        color: streaming ? Tokens.success : Tokens.gray,
        title: L.t('Görüntü', 'Video'),
        detail: streaming ? L.t('Akıyor · ${h.fps.toStringAsFixed(1)} fps', 'Streaming · ${h.fps.toStringAsFixed(1)} fps') : L.t('Kapalı', 'Off'),
      ),
      _StatusRow(
        color: !streaming ? Tokens.gray : (h.stuckRecoveries > 0 ? Tokens.warning : Tokens.success),
        title: L.t('Yazı okuma', 'Text reading'),
        detail: [
          h.lastReadMs > 0 ? L.t('Son okuma ${h.lastReadMs} ms', 'Last read ${h.lastReadMs} ms') : L.t('Henüz okuma yok', 'No reads yet'),
          if (h.readerLanguage.isNotEmpty) h.readerLanguage,
          if (h.stuckRecoveries > 0) L.t('${h.stuckRecoveries} toparlanma', '${h.stuckRecoveries} recoveries'),
        ].join(' · '),
      ),
      _StatusRow(
        color: translator.$1,
        title: '${L.t('Çeviri', 'Translation')}${engine.isEmpty ? '' : ' · $engine'}',
        detail: translator.$2,
      ),
      _StatusRow(
        color: h.tvClients > 0 ? Tokens.success : (streaming ? Tokens.warning : Tokens.gray),
        title: 'TV',
        detail: '${L.t('${h.tvClients} TV bağlı', '${h.tvClients} TV connected')}${h.tvPort > 0 ? ' · port ${h.tvPort}' : ''}',
      ),
      _StatusRow(
        color: h.packsEnabled ? Tokens.success : Tokens.gray,
        title: L.t('Oyun paketi', 'Game pack'),
        detail: !h.packsEnabled ? L.t('Kapalı', 'Off') : (h.packGame.isEmpty ? L.t('Açık · oyun bulunamadı', 'On · no game found') : h.packGame),
      ),
      _StatusRow(
        color: h.cacheEntries > 0 ? Tokens.success : Tokens.gray,
        title: L.t('Çeviri hafızası', 'Translation memory'),
        detail: L.t('${h.cacheEntries} kayıt', '${h.cacheEntries} entries'),
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
