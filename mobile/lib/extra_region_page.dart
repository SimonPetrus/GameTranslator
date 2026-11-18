// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'bridge.dart';
import 'home_page.dart';
import 'l10n.dart';
import 'main.dart';
import 'ui.dart';

/// Ek okuma alanını düzenler: ad ve dört kenar. Kaydedilirse güncel alanı, silinirse `{'delete': true}` döner.
class ExtraRegionPage extends StatefulWidget {
  const ExtraRegionPage({super.key, required this.initial, required this.image});

  final Map<String, dynamic> initial;

  /// Oyun görüntüsü (çeviri kapalıyken null).
  final Uint8List? image;

  @override
  State<ExtraRegionPage> createState() => _ExtraRegionPageState();
}

class _ExtraRegionPageState extends State<ExtraRegionPage> {
  static Map<String, String> get edges => {
        'top': L.t('Üst', 'Top'),
        'bottom': L.t('Alt', 'Bottom'),
        'left': L.t('Sol', 'Left'),
        'right': L.t('Sağ', 'Right'),
      };

  late final Map<String, dynamic> region = Map<String, dynamic>.from(widget.initial);
  late final TextEditingController nameController = TextEditingController(text: widget.initial['name'] as String? ?? '');
  String edge = 'top';

  @override
  void initState() {
    super.initState();
    for (final entry in const {'top': 0.05, 'bottom': 0.25, 'left': 0.10, 'right': 0.90}.entries) {
      region[entry.key] = (region[entry.key] as num?)?.toDouble() ?? entry.value;
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  double value(String key) => (region[key] as num).toDouble();

  void setEdge(String key, double raw) {
    // Kaydederken uygulanan sınırlar: üst ve sol kenar en çok %95, alt ve sağ kenar en az %5.
    final next = key == 'top' || key == 'left' ? raw.clamp(0.0, 0.95) : raw.clamp(0.05, 1.0);
    setState(() {
      region[key] = next;
      // Alan en az %5 yüksekliğinde ve genişliğinde kalır.
      if (key == 'top' && value('bottom') < next + 0.05) region['bottom'] = (next + 0.05).clamp(0.0, 1.0);
      if (key == 'bottom' && value('top') > next - 0.05) region['top'] = (next - 0.05).clamp(0.0, 1.0);
      if (key == 'left' && value('right') < next + 0.05) region['right'] = (next + 0.05).clamp(0.0, 1.0);
      if (key == 'right' && value('left') > next - 0.05) region['left'] = (next - 0.05).clamp(0.0, 1.0);
    });
  }

  void save() {
    final name = nameController.text.trim();
    region['name'] = name.isEmpty ? L.t('Alan', 'Area') : name;
    Navigator.of(context).pop(region);
  }

  Future<void> remove() async {
    final confirmed = await confirmApple(
      context,
      title: L.t('Alan silinsin mi?', 'Delete this area?'),
      message: L.t('Bu ek okuma alanı kaldırılır.', 'This extra reading area is removed.'),
      action: L.t('Sil', 'Delete'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(<String, dynamic>{'delete': true});
  }

  @override
  Widget build(BuildContext context) {
    final preview = AppSettings({'region': region, 'style': <String, dynamic>{}});
    return GlassScaffold(
      title: L.t('Ek Okuma Alanı', 'Extra Reading Area'),
      actions: [
        TextButton(onPressed: save, child: Text(L.t('Kaydet', 'Save'), style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Glass(
            clip: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: nameController,
                maxLength: 24,
                decoration: InputDecoration(hintText: L.t('Alan adı (ör. Görev notu)', 'Area name (e.g. Quest note)'), counterText: ''),
              ),
            ),
          ),
          GroupHeader(L.t('ALAN', 'AREA')),
          Glass(
            clip: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.image != null) RegionPreview(image: widget.image!, settings: preview) else _EmptyPreview(settings: preview),
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
                    onValueChanged: (next) => setState(() => edge = next ?? edge),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoSlider(
                          value: value(edge).clamp(0.0, 1.0),
                          activeColor: Tokens.accent,
                          onChanged: (next) => setEdge(edge, (next * 100).round() / 100),
                        ),
                      ),
                      SizedBox(
                        width: 46,
                        child: Text('%${(value(edge) * 100).round()}', textAlign: TextAlign.end, style: Txt.body.copyWith(color: Tokens.textSecondary)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GroupFooter(L.t('Çeviri açıkken oyun görüntüsü görünür. Ana ekrandaki düğmeye basınca bu alandaki yazı bir kez okunup çevrilir.', 'The game picture is shown while translation is on. Pressing the button on the home screen reads and translates the text in this area once.')),
          const SizedBox(height: 14),
          Group(children: [Cell(title: L.t('Alanı Sil', 'Delete Area'), titleColor: Tokens.danger, onTap: remove)]),
        ],
      ),
    );
  }
}

/// Oyun görüntüsü yokken alan, boş bir ekran üstünde gösterilir.
class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.settings});

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
