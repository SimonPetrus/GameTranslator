// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gametranslator_mobile/state_hub.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late StateHub<int> hub;

  setUp(() {
    hub = StateHub<int>((raw) => raw as int);
  });

  test('both listeners receive the same event', () async {
    final a = <int>[];
    final b = <int>[];
    final subA = hub.stream.listen(a.add);
    final subB = hub.stream.listen(b.add);
    hub.feed(1);
    hub.feed(2);
    await settle();
    expect(a, [1, 2]);
    expect(b, [1, 2]);
    await subA.cancel();
    await subB.cancel();
  });

  test('cancelling one listener keeps the other receiving', () async {
    final a = <int>[];
    final b = <int>[];
    final subA = hub.stream.listen(a.add);
    final subB = hub.stream.listen(b.add);
    hub.feed(1);
    await settle();
    await subA.cancel();
    hub.feed(2);
    await settle();
    expect(a, [1]);
    expect(b, [1, 2]);
    await subB.cancel();
    // Hepsi iptal olduktan sonra da dağıtım çalışır; yeni abone son değeri alır.
    hub.feed(3);
    final c = <int>[];
    final subC = hub.stream.listen(c.add);
    await settle();
    expect(c, [3]);
    await subC.cancel();
  });

  test('late listener gets the latest value asynchronously', () async {
    hub.feed(7);
    hub.feed(8);
    final got = <int>[];
    final sub = hub.stream.listen(got.add);
    expect(got, isEmpty);
    await settle();
    expect(got, [8]);
    hub.feed(9);
    await settle();
    expect(got, [8, 9]);
    await sub.cancel();
  });

  test('live event right after listen is not overwritten by older latest', () async {
    hub.feed(1);
    final got = <int>[];
    final sub = hub.stream.listen(got.add);
    hub.feed(2);
    await settle();
    expect(got, [2]);
    await sub.cancel();
  });

  test('a malformed event is dropped and the stream survives', () async {
    final got = <int>[];
    final sub = hub.stream.listen(got.add);
    hub.feed(1);
    hub.feed('bozuk');
    hub.feed(null);
    hub.feed(2);
    await settle();
    expect(got, [1, 2]);
    expect(hub.latest, 2);
    await sub.cancel();
  });

  test('reset clears the latest value', () async {
    hub.feed(5);
    hub.reset();
    expect(hub.latest, isNull);
  });
}
