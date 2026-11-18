// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'bridge.dart';
import 'l10n.dart';
import 'main.dart';
import 'ui.dart';

/// Tanı kaydı (yalnız iOS): kullanıcı kaydı başlatır, oyunu oynar, durdurur ve tek .zip dosyasını geliştiriciye gönderir.
/// Kayıtta okunan yazılar, çeviriler, TV'ye gidenler ve küçültülmüş oyun kareleri olur. Açıkken saniyede bir yenilenir.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  DiagnosticsStatus? status;
  bool loaded = false;
  bool busy = false;
  String? sharing;
  Timer? timer;

  /// Sayfa açıkken gözlenen son duruş sayısı; kayıt kendiliğinden durunca uyarı gösterilir.
  int? seenStops;
  String? limitNotice;

  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    final next = await Bridge.diagStatus();
    if (!mounted) return;
    setState(() {
      if (next != null) {
        final before = seenStops;
        if (before != null && next.stops > before && !next.recording) {
          limitNotice = stopReasonText(next.lastStop, next);
        }
        seenStops = next.stops;
      }
      status = next;
      loaded = true;
    });
  }

  /// Sınırların metni: köprüden gelen değerlerden (dakika, MB, kare).
  static int limitMinutes(DiagnosticsStatus s) => (s.maxSeconds / 60).round();
  static int limitMegabytes(DiagnosticsStatus s) => (s.maxBytes / (1024 * 1024)).round();

  /// Kendiliğinden (sınır ya da hata yüzünden) duruşun metni; elle durdurulduysa null.
  static String? stopReasonText(String reason, DiagnosticsStatus s) {
    final minutes = limitMinutes(s);
    final megabytes = limitMegabytes(s);
    final frames = s.maxFrames;
    switch (reason) {
      case 'duration':
        return L.t('Süre sınırı ($minutes dakika) doldu; kayıt kendiliğinden durdu.', 'The time limit ($minutes minutes) was reached; the recording stopped by itself.');
      case 'size':
        return L.t('Boyut sınırı ($megabytes MB) doldu; kayıt kendiliğinden durdu.', 'The size limit ($megabytes MB) was reached; the recording stopped by itself.');
      case 'frames':
        return L.t('Görüntü sınırı ($frames kare) doldu; kayıt kendiliğinden durdu.', 'The image limit ($frames frames) was reached; the recording stopped by itself.');
      case 'failed':
        return L.t('Kayıt dosyası yazılamadı; kayıt durdu.', 'The recording file could not be written; the recording stopped.');
      default:
        return null;
    }
  }

  Future<void> start({bool replaceOldest = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      limitNotice = null;
    });
    final result = await Bridge.diagStart(replaceOldest: replaceOldest);
    if (!mounted) return;
    setState(() => busy = false);
    if (result.ok) {
      await refresh();
      return;
    }
    if (!mounted) return;
    if (result.error == 'full' && !replaceOldest) {
      DiagnosticsSession? oldest;
      for (final session in status?.sessions ?? const <DiagnosticsSession>[]) {
        if (session.id == result.oldest) oldest = session;
      }
      final confirmed = await confirmApple(
        context,
        title: L.t('En eski kayıt silinsin mi?', 'Delete the oldest recording?'),
        message: L.t(
          'Telefonda en çok ${status?.maxSessions ?? 3} kayıt saklanır. Yeni kayıt için en eski kayıt${oldest == null ? '' : ' (${dateText(oldest)})'} silinecek.',
          'At most ${status?.maxSessions ?? 3} recordings are kept on the phone. The oldest recording${oldest == null ? '' : ' (${dateText(oldest)})'} will be deleted for the new one.',
        ),
        action: L.t('Sil ve başlat', 'Delete and start'),
        destructive: true,
      );
      if (confirmed && mounted) await start(replaceOldest: true);
      return;
    }
    toast(context, result.detail.isEmpty ? L.t('Kayıt başlatılamadı.', 'The recording could not be started.') : result.detail);
  }

  Future<void> stop() async {
    if (busy) return;
    setState(() => busy = true);
    await Bridge.diagStop();
    if (!mounted) return;
    setState(() => busy = false);
    await refresh();
  }

  Future<void> share(DiagnosticsSession session) async {
    if (sharing != null) return;
    setState(() => sharing = session.id);
    final (ok, error) = await Bridge.diagShare(session.id);
    if (!mounted) return;
    setState(() => sharing = null);
    if (!ok) toast(context, error.isEmpty ? L.t('Paylaşılamadı.', 'Could not share.') : error);
  }

  Future<void> delete(DiagnosticsSession session) async {
    final confirmed = await confirmApple(
      context,
      title: L.t('Kayıt silinsin mi?', 'Delete the recording?'),
      message: L.t('${dateText(session)} tarihli kayıt telefondan silinir.', 'The recording from ${dateText(session)} is deleted from the phone.'),
      action: L.t('Sil', 'Delete'),
      destructive: true,
    );
    if (!confirmed) return;
    final ok = await Bridge.diagDelete(session.id);
    if (!mounted) return;
    if (!ok) toast(context, L.t('Kayıt silinemedi.', 'The recording could not be deleted.'));
    await refresh();
  }

  static String two(int value) => value.toString().padLeft(2, '0');

  static String dateText(DiagnosticsSession session) {
    final at = session.startedAt;
    if (at == null) return session.id;
    return '${two(at.day)}.${two(at.month)}.${at.year} ${two(at.hour)}:${two(at.minute)}';
  }

  static String durationText(double seconds) {
    final total = seconds.round();
    return '${two(total ~/ 60)}:${two(total % 60)}';
  }

  static String sizeText(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).ceil()} KB';
  }

  String countsText({required double seconds, required int events, required int bytes, required int frames}) => L.t(
        '${durationText(seconds)} · $events olay · ${sizeText(bytes)} · $frames kare',
        '${durationText(seconds)} · $events events · ${sizeText(bytes)} · $frames frames',
      );

  @override
  Widget build(BuildContext context) {
    final s = status;
    return GlassScaffold(
      title: L.t('Tanı Kaydı', 'Diagnostics Recording'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          if (!loaded)
            const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CupertinoActivityIndicator(radius: 14)))
          else if (s == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 0),
              child: Text(L.t('Tanı kaydı bu telefonda yok.', 'Diagnostics recording is not available on this phone.'),
                  textAlign: TextAlign.center, style: Txt.subhead.copyWith(color: Tokens.textSecondary)),
            )
          else ...[
            Group(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: s.recording ? Tokens.danger : Tokens.gray, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.recording ? L.t('Kaydediyor', 'Recording') : L.t('Kapalı', 'Off'), style: Txt.body),
                            if (s.recording)
                              Text(countsText(seconds: s.seconds, events: s.events, bytes: s.bytes, frames: s.frames),
                                  style: Txt.footnote.copyWith(color: Tokens.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GlowButton(
              onPressed: busy ? null : (s.recording ? stop : start),
              busy: busy,
              icon: s.recording ? CupertinoIcons.stop_fill : CupertinoIcons.circle_fill,
              label: s.recording ? L.t('Kaydı durdur', 'Stop recording') : L.t('Kaydı başlat', 'Start recording'),
            ),
            if (limitNotice != null) ...[
              const SizedBox(height: 12),
              Notice(icon: CupertinoIcons.exclamationmark_circle_fill, color: Tokens.warning, text: limitNotice!),
            ],
            GroupFooter(L.t(
              'Kaydı başlat, oyunu oynarken sorunu yaşa, sonra durdur ve dosyayı paylaş. En çok ${limitMinutes(s)} dakika, '
                  '${limitMegabytes(s)} MB ya da ${s.maxFrames} kare; hangisi önce dolarsa kayıt kendiliğinden durur. '
                  'Kayıt çeviri başlamadan da açılabilir.',
              'Start the recording, play until the problem happens, then stop it and share the file. At most ${limitMinutes(s)} minutes, '
                  '${limitMegabytes(s)} MB or ${s.maxFrames} frames; whichever comes first stops the recording by itself. '
                  'You can start it before translation too.',
            )),
            GroupHeader(L.t('KAYITLAR', 'RECORDINGS')),
            if (s.sessions.isEmpty)
              Group(children: [Cell(title: L.t('Henüz kayıt yok', 'No recordings yet'), titleColor: Tokens.textSecondary)])
            else
              Group(children: [for (final session in s.sessions) sessionRow(session)]),
            GroupFooter(L.t(
              'Kayıtta oyun görüntüleri, okunan yazılar ve çeviriler bulunur. API anahtarların ve PSN hesabın kaydedilmez. '
                  'Dosya, sen paylaşmadıkça telefonundan çıkmaz.',
              'The recording contains game images, the text that was read and the translations. Your API keys and PSN account are not recorded. '
                  'The file does not leave your phone unless you share it.',
            )),
          ],
        ],
      ),
    );
  }

  /// Kaydın neden bittiği (elle durdurulduysa boş).
  static String endText(DiagnosticsSession session) {
    if (session.interrupted) return L.t('Yarım kaldı (uygulama kapandı)', 'Incomplete (the app closed)');
    switch (session.reason) {
      case 'duration':
        return L.t('Süre sınırında durdu', 'Stopped at the time limit');
      case 'size':
        return L.t('Boyut sınırında durdu', 'Stopped at the size limit');
      case 'frames':
        return L.t('Kare sınırında durdu', 'Stopped at the frame limit');
      case 'failed':
        return L.t('Hatayla durdu', 'Stopped with an error');
      default:
        return '';
    }
  }

  Widget sessionRow(DiagnosticsSession session) {
    final end = endText(session);
    final notes = <String>[
      if (end.isNotEmpty) end,
      if (session.version.isNotEmpty) 'v${session.version}',
    ];
    final detail = countsText(seconds: session.seconds, events: session.events, bytes: session.bytes, frames: session.frames);
    final sharingThis = sharing == session.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateText(session), style: Txt.body),
                Text(detail, style: Txt.footnote.copyWith(color: Tokens.textSecondary)),
                if (notes.isNotEmpty)
                  Text(notes.join(' · '), style: Txt.footnote.copyWith(color: session.interrupted ? Tokens.warning : Tokens.textSecondary)),
              ],
            ),
          ),
          if (sharingThis)
            const Padding(padding: EdgeInsets.all(12), child: CupertinoActivityIndicator(radius: 10))
          else
            IconButton(
              tooltip: L.t('Paylaş', 'Share'),
              onPressed: sharing == null ? () => share(session) : null,
              icon: const Icon(CupertinoIcons.share, color: Tokens.accent),
            ),
          IconButton(
            tooltip: L.t('Sil', 'Delete'),
            onPressed: sharingThis ? null : () => delete(session),
            icon: const Icon(CupertinoIcons.trash, color: Tokens.danger),
          ),
        ],
      ),
    );
  }
}
