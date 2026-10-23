import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves every `binding.takeScreenshot(name)` to build/screenshots/<name>.png on the host.
Future<void> main() => integrationDriver(
      onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final file = File('build/screenshots/$name.png');
        file.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
        return true;
      },
    );
