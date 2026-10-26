import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('T16: only the six approved files import the process host', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from the repository root');
    final importing = <String>{};
    final importPattern = RegExp(
      "(?:import|export)\\s+'[^']*process_host(?:_io|_stub)?\\.dart'",
    );
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (importPattern.hasMatch(source)) {
        importing.add(entity.path.replaceAll('\\', '/'));
      }
    }

    expect(importing, {
      'lib/kernel/thincoder/thincoder_process_io.dart',
      'lib/kernel/thincoder/thincoder_locator.dart',
      'lib/kernel/thincoder/thincoder_process.dart',
      'lib/platform/process_host.dart',
      'lib/platform/process_host_io.dart',
      'lib/platform/process_host_stub.dart',
    });

    final direct = RegExp(r'\bProcess\.(?:start|run|runSync)\(');
    for (final path in const [
      'lib/kernel/thincoder/thincoder_process_io.dart',
      'lib/kernel/thincoder/thincoder_locator.dart',
      'lib/kernel/thincoder/thincoder_process.dart',
    ]) {
      final violations = [
        for (final line in File(path).readAsLinesSync())
          if (!line.trimLeft().startsWith('//') && direct.hasMatch(line)) line,
      ];
      expect(violations, isEmpty, reason: '$path creates a process directly');
    }
  });
}
