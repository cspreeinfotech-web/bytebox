import 'package:bytebox/theme.dart';
import 'package:bytebox/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme uses Bytebox brand tokens', () {
    final t = AppTheme.dark();
    expect(t.colorScheme.primary, AppColors.primary);
    expect(t.scaffoldBackgroundColor, AppColors.background);
  });

  test('formatters', () {
    expect(formatBytes(16106127360), '15.0 GB');
    expect(formatBytes(0), '0 B');
    expect(durationLabel(7), '1 week');
    expect(durationLabel(30), '1 month');
    expect(durationLabel(180), '6 months');
    expect(durationLabel(365), '1 year');
    expect(formatDuration(125), '2:05');
  });
}
