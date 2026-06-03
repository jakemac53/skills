import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/commands/get_command.dart';
import 'package:skills/src/commands/skills_command_runner.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/core/registry_repos.dart';
import 'package:skills/src/models/global_config.dart';
import 'package:skills/src/models/skill_manifest.dart';
import '../fake_dialog_support.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('GetCommand with registry', () {
    test(
      'when git is unavailable then only Dart skills are installed and warning is printed',
      () async {
        // Use a test-owned temp dir (pass to create()) so we do not use test_descriptor's
        // global sandbox; then run the command with --directory so we never change process cwd.
        final testRootPath = p.join(
          Directory.systemTemp.path,
          'skills_get_test_${DateTime.now().millisecondsSinceEpoch}',
        );
        Directory(testRootPath).createSync();
        addTearDown(() async {
          await Directory(testRootPath).delete(recursive: true);
        });

        // dep_with_skills is sibling of project, so from project/.dart_tool we need ../../dep_with_skills
        final depRelative = p.join('..', '..', 'dep_with_skills');

        await d.dir('dep_with_skills', [
          d.dir('lib', [d.file('dep.dart', '')]),
          d.dir('skills', [
            d.dir('dep_with_skills-code-gen', [
              d.file('SKILL.md', '---\nname: dep_with_skills-code-gen\n---\n'),
            ]),
          ]),
        ]).create(testRootPath);

        await d.dir('project', [
          d.file('pubspec.yaml', '''
name: test_app
environment:
  sdk: ^3.0.0
'''),
          d.dir('.dart_tool', [
            d.file(
              'package_config.json',
              jsonEncode({
                'configVersion': 2,
                'packages': [
                  {'name': 'test_app', 'rootUri': '../', 'packageUri': 'lib/'},
                  {
                    'name': 'dep_with_skills',
                    'rootUri': depRelative,
                    'packageUri': 'lib/',
                  },
                ],
              }),
            ),
          ]),
          d.dir('.cursor', [d.dir('skills')]),
        ]).create(testRootPath);

        final projectPath = p.join(testRootPath, 'project');

        final getCommand = GetCommand(
          dialogSupport: FakeDialogSupport()..multiSelectResult = {0},
          gitRunner: GitRunner(isAvailableOverride: _gitUnavailable),
        );
        final runner = SkillsCommandRunner('skills', 'Test')
          ..addCommand(getCommand);

        await runner
            .run(['get', '--directory', projectPath, '--ide', 'cursor']);

        final skillDir = Directory(
          p.join(projectPath, '.cursor', 'skills', 'dep_with_skills-code-gen'),
        );
        expect(await skillDir.exists(), isTrue);
        final manifestFile = File(SkillManifest.pathIn(projectPath));
        expect(await manifestFile.exists(), isTrue);
      },
    );

    test(
        'when installing from global registry then adds back-link to global '
        'config', () async {
      final mockRegistry = d.dir('mock_registry', [
        d.dir('skills', [
          d.dir('pkg-skill', [
            d.file('SKILL.md', '---\nname: pkg-skill\n---\n'),
          ]),
        ]),
      ]);
      await mockRegistry.create();
      final registryPath = mockRegistry.io.path;

      // Initialize git repo
      await Process.run('git', ['init'], workingDirectory: registryPath);
      await Process.run('git', ['config', 'user.name', 'Test'],
          workingDirectory: registryPath);
      await Process.run('git', ['config', 'user.email', 'test@example.com'],
          workingDirectory: registryPath);
      await Process.run('git', ['add', '.'], workingDirectory: registryPath);
      await Process.run('git', ['commit', '-m', 'initial'],
          workingDirectory: registryPath);

      final project = d.dir('project', [
        d.file('pubspec.yaml', '''
name: test_app
environment:
  sdk: ^3.0.0
'''),
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {'name': 'test_app', 'rootUri': '../', 'packageUri': 'lib/'},
                {'name': 'pkg', 'rootUri': '../../pkg', 'packageUri': 'lib/'},
              ],
            }),
          ),
        ]),
        d.dir('.cursor', [d.dir('skills')]),
      ]);
      await project.create();
      final projectPath = project.io.path;

      final globalConfigPath = d.file('global_config.json').io.path;
      GlobalConfig.globalPathOverride = globalConfigPath;
      addTearDown(() => GlobalConfig.globalPathOverride = null);

      var globalConfig = const GlobalConfig();
      globalConfig = globalConfig.withRegistry(GitRepo(cloneUrl: registryPath));
      await globalConfig.save(File(globalConfigPath));

      final getCommand = GetCommand(
        dialogSupport: FakeDialogSupport()..multiSelectResult = {0},
      );

      final runner = SkillsCommandRunner('skills', 'Test')
        ..addCommand(getCommand);

      await runner.run(['--directory', projectPath, 'get', '--ide', 'cursor']);

      await d.dir(projectPath, [d.dir('.cursor/skills/pkg-skill')]).validate();

      final updatedGlobalConfig =
          await GlobalConfig.loadOrEmpty(File(globalConfigPath));
      final repo = updatedGlobalConfig.registries
          .firstWhere((r) => r.cloneUrl == registryPath);
      expect(repo.installs, isNotEmpty);
      expect(repo.installs.first, contains('pkg-skill'));
    });

    test(
        'when installing with --git option then adds registry to manifest and '
        'installs skills', () async {
      final mockRegistry = d.dir('mock_registry', [
        d.dir('skills', [
          d.dir('pkg-skill', [
            d.file('SKILL.md', '---\nname: pkg-skill\n---\n'),
          ]),
        ]),
      ]);
      await mockRegistry.create();
      final registryPath = mockRegistry.io.path;

      // Initialize git repo
      await Process.run('git', ['init'], workingDirectory: registryPath);
      await Process.run('git', ['config', 'user.name', 'Test'],
          workingDirectory: registryPath);
      await Process.run('git', ['config', 'user.email', 'test@example.com'],
          workingDirectory: registryPath);
      await Process.run('git', ['add', '.'], workingDirectory: registryPath);
      await Process.run('git', ['commit', '-m', 'initial'],
          workingDirectory: registryPath);

      final project = d.dir('project', [
        d.file('pubspec.yaml', '''
name: test_app
environment:
  sdk: ^3.0.0
'''),
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {'name': 'test_app', 'rootUri': '../', 'packageUri': 'lib/'},
              ],
            }),
          ),
        ]),
        d.dir('.cursor', [d.dir('skills')]),
      ]);
      await project.create();
      final projectPath = project.io.path;

      final getCommand = GetCommand(
        dialogSupport: FakeDialogSupport()..multiSelectResult = {0},
      );

      final runner = SkillsCommandRunner('skills', 'Test')
        ..addCommand(getCommand);

      // Use file:// URI for local path to avoid shorthand parser
      final registryUri = Uri.file(registryPath).toString();

      await runner.run([
        '--directory',
        projectPath,
        'get',
        '--ide',
        'cursor',
        '--git',
        registryUri,
      ]);

      await d.dir(projectPath, [d.dir('.cursor/skills/pkg-skill')]).validate();

      final manifestFile = File(SkillManifest.pathIn(projectPath));
      expect(await manifestFile.exists(), isTrue);
      final manifest = await SkillManifest.load(manifestFile);
      expect(manifest, isNotNull);
      expect(
        manifest!.registries.any((r) => r.cloneUrl == registryUri),
        isTrue,
      );
    });

    test(
        'when repo is already a registry and user confirms conversion, then '
        'converts to direct repo and installs skills', () async {
      final mockRegistry = d.dir('mock_registry', [
        d.dir('skills', [
          d.dir('pkg-skill', [
            d.file('SKILL.md', '---\nname: pkg-skill\n---\n'),
          ]),
        ]),
      ]);
      await mockRegistry.create();
      final registryPath = mockRegistry.io.path;

      // Initialize git repo
      await Process.run('git', ['init'], workingDirectory: registryPath);
      await Process.run('git', ['config', 'user.name', 'Test'],
          workingDirectory: registryPath);
      await Process.run('git', ['config', 'user.email', 'test@example.com'],
          workingDirectory: registryPath);
      await Process.run('git', ['add', '.'], workingDirectory: registryPath);
      await Process.run('git', ['commit', '-m', 'initial'],
          workingDirectory: registryPath);

      final registryUri = Uri.file(registryPath).toString();

      final project = d.dir('project', [
        d.file('pubspec.yaml', '''
name: test_app
environment:
  sdk: ^3.0.0
'''),
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {'name': 'test_app', 'rootUri': '../', 'packageUri': 'lib/'},
              ],
            }),
          ),
        ]),
        d.dir('.cursor', [d.dir('skills')]),
        d.dir('.config', [
          d.dir('dart_skills', [
            d.file(
              'skills_config.json',
              jsonEncode({
                'version': SkillManifest.currentVersion,
                'registries': [
                  {'cloneUrl': registryUri, 'isSkillRegistry': true}
                ]
              }),
            ),
          ]),
        ]),
      ]);
      await project.create();
      final projectPath = project.io.path;

      final getCommand = GetCommand(
        dialogSupport: FakeDialogSupport()
          ..multiSelectResult = {0}
          ..singleSelectResult = 0,
      );

      final runner = SkillsCommandRunner('skills', 'Test')
        ..addCommand(getCommand);

      await runner.run([
        '--directory',
        projectPath,
        'get',
        '--ide',
        'cursor',
        '--git',
        registryUri,
      ]);

      await d.dir(projectPath, [d.dir('.cursor/skills/pkg-skill')]).validate();

      final manifestFile = File(SkillManifest.pathIn(projectPath));
      final manifest = await SkillManifest.load(manifestFile);
      expect(manifest, isNotNull);
      final repo =
          manifest!.registries.firstWhere((r) => r.cloneUrl == registryUri);
      expect(repo.isSkillRegistry, isFalse);
    });

    test(
        'when repo is already a registry and user declines conversion, then '
        'skips it and does not install', () async {
      final mockRegistry = d.dir('mock_registry', [
        d.dir('skills', [
          d.dir('pkg-skill', [
            d.file('SKILL.md', '---\nname: pkg-skill\n---\n'),
          ]),
        ]),
      ]);
      await mockRegistry.create();
      final registryPath = mockRegistry.io.path;

      // Initialize git repo
      await Process.run('git', ['init'], workingDirectory: registryPath);
      await Process.run('git', ['config', 'user.name', 'Test'],
          workingDirectory: registryPath);
      await Process.run('git', ['config', 'user.email', 'test@example.com'],
          workingDirectory: registryPath);
      await Process.run('git', ['add', '.'], workingDirectory: registryPath);
      await Process.run('git', ['commit', '-m', 'initial'],
          workingDirectory: registryPath);

      final registryUri = Uri.file(registryPath).toString();

      final project = d.dir('project', [
        d.file('pubspec.yaml', '''
name: test_app
environment:
  sdk: ^3.0.0
'''),
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {'name': 'test_app', 'rootUri': '../', 'packageUri': 'lib/'},
              ],
            }),
          ),
        ]),
        d.dir('.cursor', [d.dir('skills')]),
        d.dir('.config', [
          d.dir('dart_skills', [
            d.file(
              'skills_config.json',
              jsonEncode({
                'version': SkillManifest.currentVersion,
                'registries': [
                  {'cloneUrl': registryUri, 'isSkillRegistry': true}
                ]
              }),
            ),
          ]),
        ]),
      ]);
      await project.create();
      final projectPath = project.io.path;

      final getCommand = GetCommand(
        dialogSupport: FakeDialogSupport()
          ..multiSelectResult = {0}
          ..singleSelectResult = 1,
      );

      final runner = SkillsCommandRunner('skills', 'Test')
        ..addCommand(getCommand);

      await runner.run([
        '--directory',
        projectPath,
        'get',
        '--ide',
        'cursor',
        '--git',
        registryUri,
      ]);

      await d.dir(projectPath, [
        d.nothing('.cursor/skills/pkg-skill'),
      ]).validate();

      final manifestFile = File(SkillManifest.pathIn(projectPath));
      final manifest = await SkillManifest.load(manifestFile);
      expect(manifest, isNotNull);
      final repo =
          manifest!.registries.firstWhere((r) => r.cloneUrl == registryUri);
      expect(repo.isSkillRegistry, isTrue);
    });

    test('when repo is already a registry and no dialog support, then skips',
        () async {
      final mockRegistry = d.dir('mock_registry', [
        d.dir('skills', [
          d.dir('pkg-skill', [
            d.file('SKILL.md', '---\nname: pkg-skill\n---\n'),
          ]),
        ]),
      ]);
      await mockRegistry.create();
      final registryPath = mockRegistry.io.path;

      // Initialize git repo
      await Process.run('git', ['init'], workingDirectory: registryPath);
      await Process.run('git', ['config', 'user.name', 'Test'],
          workingDirectory: registryPath);
      await Process.run('git', ['config', 'user.email', 'test@example.com'],
          workingDirectory: registryPath);
      await Process.run('git', ['add', '.'], workingDirectory: registryPath);
      await Process.run('git', ['commit', '-m', 'initial'],
          workingDirectory: registryPath);

      final registryUri = Uri.file(registryPath).toString();

      final project = d.dir('project', [
        d.file('pubspec.yaml', '''
name: test_app
environment:
  sdk: ^3.0.0
'''),
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {'name': 'test_app', 'rootUri': '../', 'packageUri': 'lib/'},
              ],
            }),
          ),
        ]),
        d.dir('.cursor', [d.dir('skills')]),
        d.dir('.config', [
          d.dir('dart_skills', [
            d.file(
              'skills_config.json',
              jsonEncode({
                'version': SkillManifest.currentVersion,
                'registries': [
                  {'cloneUrl': registryUri, 'isSkillRegistry': true}
                ]
              }),
            ),
          ]),
        ]),
      ]);
      await project.create();
      final projectPath = project.io.path;

      final getCommand = GetCommand(
        dialogSupport: null,
      );

      final runner = SkillsCommandRunner('skills', 'Test')
        ..addCommand(getCommand);

      await runner.run([
        '--directory',
        projectPath,
        'get',
        '--ide',
        'cursor',
        '--git',
        registryUri,
      ]);

      await d.dir(projectPath, [
        d.nothing('.cursor/skills/pkg-skill'),
      ]).validate();

      final manifestFile = File(SkillManifest.pathIn(projectPath));
      final manifest = await SkillManifest.load(manifestFile);
      expect(manifest, isNotNull);
      final repo =
          manifest!.registries.firstWhere((r) => r.cloneUrl == registryUri);
      expect(repo.isSkillRegistry, isTrue);
    });

    test(
        'when one repo is already a registry and user declines conversion, '
        'it skips it but still installs from other git repos', () async {
      final mockRegistry1 = d.dir('mock_registry1', [
        d.dir('skills', [
          d.dir('pkg1-skill', [
            d.file('SKILL.md', '---\nname: pkg1-skill\n---\n'),
          ]),
        ]),
      ]);
      await mockRegistry1.create();
      final registryPath1 = mockRegistry1.io.path;
      await _initGitRepo(registryPath1);
      final registryUri1 = Uri.file(registryPath1).toString();

      final mockRegistry2 = d.dir('mock_registry2', [
        d.dir('skills', [
          d.dir('pkg2-skill', [
            d.file('SKILL.md', '---\nname: pkg2-skill\n---\n'),
          ]),
        ]),
      ]);
      await mockRegistry2.create();
      final registryPath2 = mockRegistry2.io.path;
      await _initGitRepo(registryPath2);
      final registryUri2 = Uri.file(registryPath2).toString();

      final project = d.dir('project', [
        d.file('pubspec.yaml', '''
name: test_app
environment:
  sdk: ^3.0.0
'''),
        d.dir('.dart_tool', [
          d.file(
            'package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {'name': 'test_app', 'rootUri': '../', 'packageUri': 'lib/'},
              ],
            }),
          ),
        ]),
        d.dir('.cursor', [d.dir('skills')]),
        d.dir('.config', [
          d.dir('dart_skills', [
            d.file(
              'skills_config.json',
              jsonEncode({
                'version': SkillManifest.currentVersion,
                'registries': [
                  {'cloneUrl': registryUri1, 'isSkillRegistry': true}
                ]
              }),
            ),
          ]),
        ]),
      ]);
      await project.create();
      final projectPath = project.io.path;

      final getCommand = GetCommand(
        dialogSupport: FakeDialogSupport()
          ..multiSelectResult = {0}
          ..singleSelectResult = 1,
      );

      final runner = SkillsCommandRunner('skills', 'Test')
        ..addCommand(getCommand);

      await runner.run([
        '--directory',
        projectPath,
        'get',
        '--ide',
        'cursor',
        '--git',
        registryUri1,
        '--git',
        registryUri2,
      ]);

      await d.dir(projectPath, [
        d.nothing('.cursor/skills/pkg1-skill'),
        d.dir('.cursor/skills/pkg2-skill'),
      ]).validate();

      final manifestFile = File(SkillManifest.pathIn(projectPath));
      final manifest = await SkillManifest.load(manifestFile);
      expect(manifest, isNotNull);
      final repo1 =
          manifest!.registries.firstWhere((r) => r.cloneUrl == registryUri1);
      expect(repo1.isSkillRegistry, isTrue);
      final repo2 =
          manifest.registries.firstWhere((r) => r.cloneUrl == registryUri2);
      expect(repo2.isSkillRegistry, isFalse);
    });
  });
}

Future<bool> _gitUnavailable() async => false;

Future<void> _initGitRepo(String path) async {
  await Process.run('git', ['init'], workingDirectory: path);
  await Process.run('git', ['config', 'user.name', 'Test'],
      workingDirectory: path);
  await Process.run('git', ['config', 'user.email', 'test@example.com'],
      workingDirectory: path);
  await Process.run('git', ['add', '.'], workingDirectory: path);
  await Process.run('git', ['commit', '-m', 'initial'], workingDirectory: path);
}
