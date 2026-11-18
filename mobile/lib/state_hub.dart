// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';

/// Tek kaynaktan gelen olayları birden çok dinleyiciye dağıtır ve son değeri saklar.
/// Dinleyici iptali kaynağı etkilemez; geç abone olan, varsa son değeri eşzamansız alır.
class StateHub<T> {
  StateHub(this._parse);

  final T Function(Object? raw) _parse;
  final StreamController<T> _live = StreamController<T>.broadcast(sync: true);
  T? _latest;

  /// En son alınan değer; henüz olay gelmediyse null.
  T? get latest => _latest;

  /// Ham olayı ayrıştırıp dağıtır. Ayrıştırma hatası yalnız o olayı düşürür.
  void feed(Object? raw) {
    final T value;
    try {
      value = _parse(raw);
    } catch (_) {
      return;
    }
    _latest = value;
    _live.add(value);
  }

  /// Önce (varsa) son değer, sonra canlı olaylar. Teslim her zaman `listen` çağrısından sonradır.
  Stream<T> get stream => Stream<T>.multi((controller) {
        var gotLive = false;
        final sub = _live.stream.listen((value) {
          gotLive = true;
          controller.add(value);
        });
        controller.onCancel = sub.cancel;
        scheduleMicrotask(() {
          final last = _latest;
          if (!gotLive && last != null && !controller.isClosed) controller.add(last);
        });
      }, isBroadcast: true);

  /// Yalnız testler için.
  void reset() => _latest = null;
}
