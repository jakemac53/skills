import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:io/io.dart';
import 'package:skills/src/commands/options.dart';
import 'package:skills/src/core/stdin.dart';
import 'package:skills/src/ide/ide.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../utils/test_utils.dart';

void main() {
  group('resolveIdes', () {
    late String projectPath;

    setUp(() async {
      await d.dir('project').create();
      projectPath = d.path('project');
    });

    test('returns IDE when specified via --ide', () async {
      final parser = ArgParser()..addOption('ide');
      final argResults = parser.parse(['--ide', 'cursor']);

      final ides = await resolveIdes(
        argResults: argResults,
        projectPath: projectPath,
      );

      expect(ides, equals([Ide.cursor]));
    });

    test('returns detected IDEs when auto-detection succeeds', () async {
      await d.dir('project', [
        d.dir('.cursor'),
      ]).create();

      final ides = await resolveIdes(
        argResults: null,
        projectPath: projectPath,
      );

      expect(ides, equals([Ide.cursor]));
    });

    test(
        'shows dialog and returns selected IDE when auto-detection fails and terminal available',
        () async {
      await IOOverrides.runZoned(() async {
        await withSharedStdin(
          SharedStdIn(Stream.fromIterable([downArrowKey, spaceKey, enterKey])),
          () async {
            final ides = await resolveIdes(
              argResults: null,
              projectPath: projectPath,
            );

            expect(ides, equals([Ide.values[1]]));
          },
        );
      },
          stdout: () => DummyStdout(hasTerminal: true),
          stdin: () => DummyStdin(hasTerminal: true));
    });

    test(
        'throws UsageException when auto-detection fails and no stdout terminal',
        () async {
      await IOOverrides.runZoned(() async {
        expect(
          () => resolveIdes(
            argResults: null,
            projectPath: projectPath,
          ),
          throwsA(isA<UsageException>()),
        );
      },
          stdout: () => DummyStdout(hasTerminal: false),
          stdin: () => DummyStdin(hasTerminal: true));
    });

    test(
        'throws UsageException when auto-detection fails and no stdin terminal',
        () async {
      await IOOverrides.runZoned(() async {
        expect(
          () => resolveIdes(
            argResults: null,
            projectPath: projectPath,
          ),
          throwsA(isA<UsageException>()),
        );
      },
          stdin: () => DummyStdin(hasTerminal: false),
          stdout: () => DummyStdout(hasTerminal: true));
    });

    test('throws UsageException when user selects nothing in dialog', () async {
      await IOOverrides.runZoned(() async {
        await withSharedStdin(
          SharedStdIn(Stream.fromIterable([enterKey])),
          () async {
            expect(
              () => resolveIdes(
                argResults: null,
                projectPath: projectPath,
              ),
              throwsA(isA<UsageException>()),
            );
          },
        );
      },
          stdout: () => DummyStdout(hasTerminal: true),
          stdin: () => DummyStdin(hasTerminal: true));
    });
  });
}
