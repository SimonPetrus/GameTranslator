// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'bridge.dart';
import 'l10n.dart';
import 'main.dart';
import 'ui.dart';

/// "HH:mm:ss" biçiminde saat.
String clockText(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

/// Altyazı geçmişi: en yeni satır üstte; çeviri, altında özgün metin, saat ve çeviri motoru.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HistoryEntry> entries = const [];
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
    final list = await Bridge.history();
    if (!mounted) return;
    setState(() {
      entries = list;
      loaded = true;
    });
  }

  Future<void> clear() async {
    final confirmed = await confirmApple(
      context,
      title: L.t('Geçmiş temizlensin mi?', 'Clear the history?'),
      message: L.t('Kayıtlı bütün altyazı satırları silinir.', 'All saved subtitle lines are deleted.'),
      action: L.t('Temizle', 'Clear'),
      destructive: true,
    );
    if (!confirmed) return;
    await Bridge.clearHistory();
    await refresh();
  }

  void copyAll() {
    final buffer = StringBuffer();
    for (final entry in entries) {
      buffer
        ..writeln(clockText(entry.at))
        ..writeln(entry.source.replaceAll('\n', ' '))
        ..writeln(entry.text.replaceAll('\n', ' '))
        ..writeln();
    }
    Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    toast(context, L.t('Geçmiş kopyalandı.', 'History copied.'));
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      title: L.t('Altyazı Geçmişi', 'Subtitle History'),
      actions: [
        TextButton(onPressed: entries.isEmpty ? null : copyAll, child: Text(L.t('Kopyala', 'Copy'))),
        TextButton(
          onPressed: entries.isEmpty ? null : clear,
          child: Text(L.t('Temizle', 'Clear'), style: TextStyle(color: entries.isEmpty ? null : Tokens.danger)),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            if (!loaded)
              const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CupertinoActivityIndicator(radius: 14)))
            else if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 0),
                child: Text(
                  L.t(
                    'Henüz çevrilmiş altyazı yok. Çeviri açıkken ya da deneme çalışırken satırlar burada birikir.',
                    'No translated subtitles yet. Lines collect here while translation or the trial is running.',
                  ),
                  textAlign: TextAlign.center,
                  style: Txt.subhead.copyWith(color: Tokens.textSecondary),
                ),
              )
            else
              for (final entry in entries) ...[
                _HistoryTile(entry: entry),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final translationRtl = isRtlText(entry.text);
    final sourceRtl = isRtlText(entry.source);
    return Glass(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(clockText(entry.at), style: Txt.caption.copyWith(color: Tokens.textSecondary)),
              const Spacer(),
              if (entry.engine.isNotEmpty) Pill(text: entry.engine, color: Tokens.accent),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entry.text,
            textDirection: translationRtl ? TextDirection.rtl : TextDirection.ltr,
            textAlign: translationRtl ? TextAlign.right : TextAlign.left,
            style: Txt.callout.copyWith(fontWeight: FontWeight.w500),
          ),
          if (entry.source.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              entry.source.replaceAll('\n', ' '),
              textDirection: sourceRtl ? TextDirection.rtl : TextDirection.ltr,
              textAlign: sourceRtl ? TextAlign.right : TextAlign.left,
              style: Txt.footnote.copyWith(color: Tokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
