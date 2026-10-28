import 'package:bytebox/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('row count', () {
    expect(postRowCount(0, 2), 0);
    expect(postRowCount(5, 1), 5);
    expect(postRowCount(5, 2), 3);
    expect(postRowCount(6, 3), 2);
  });

  for (final (width, cols) in [(411.0, 1), (800.0, 2), (1280.0, 3)]) {
    testWidgets('columns at ${width}dp = $cols', (t) async {
      late int got;
      await t.pumpWidget(MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
        child: Builder(builder: (c) {
          got = postColumns(c);
          return const SizedBox();
        }),
      ));
      expect(got, cols);
    });
  }
}
