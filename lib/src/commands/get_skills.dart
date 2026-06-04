import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:skills/src/commands/skills_command.dart';
import 'package:skills/src/core/advisory_checker.dart';
import 'package:skills/src/core/git_runner.dart';
import 'package:skills/src/core/package_resolver.dart';
import 'package:skills/src/core/pub_runner.dart';
import 'package:skills/src/core/registry_scanner.dart';
import 'package:skills/src/core/registry_sync.dart';
import 'package:skills/src/core/registry_repos.dart';
import 'package:skills/src/core/skill_installer.dart';
import 'package:skills/src/core/skill_merger.dart';
import 'package:skills/src/core/skill_scanner.dart';
import 'package:skills/src/core/workspace_resolver.dart';
import 'package:skills/src/ide/ide.dart';
import 'package:skills/src/core/dialog_support.dart';
import 'package:skills/src/models/global_config.dart';

import '../models/skill_manifest.dart';

/// Installs skills from package dependencies for [ides].
///
/// Returns `true` on success or `false` otherwise.
Future<bool> getSkills({
  required List<Ide> ides,
  required Logger logger,
  required WorkspaceLayout workspace,
  DialogSupport? dialogSupport,
  GitRunner gitRunner = const GitRunner(),
  String usage = '',
  Set<String>? packageNames,
  List<String> gitRepos = const [],
}) async {
  final ready = await PubRunner.ensureWorkspaceConfigs(workspace);
  if (!ready) {
    throw UsageException('Failed to run pub get.', usage);
  }

  final packages = await PackageResolver.resolveWorkspace(
    workspace,
    packageNames: packageNames,
  );

  if (packageNames != null) {
    if (packages.isEmpty) {
      logger
          .severe('None of the requested packages were found in dependencies.');
      return false;
    }

    final foundNames = packages.map((p) => p.name).toSet();
    final missing = packageNames.difference(foundNames)..remove('all');
    if (missing.isNotEmpty) {
      logger.warning(
          'Warning: The following requested packages were not found in '
          'dependencies: ${missing.join(', ')}');
    }
  }

  final rootPath = workspace.rootPath;
  var manifest = await SkillManifest.loadOrEmptyFromRoot(rootPath);

  for (final repoArg in gitRepos) {
    try {
      final repo = GitRepo.fromArgument(repoArg, isSkillRegistry: false);
      final existing = manifest.registries
          .firstWhereOrNull((r) => r.cloneUrl == repo.cloneUrl);
      if (existing != null) {
        if (existing.isSkillRegistry) {
          if (dialogSupport != null) {
            final options = [
              'Yes, convert to direct skill source (installs all skills)',
              'No, keep as skill registry (only installs skills matching '
                  'dependencies)',
            ];
            final index = await dialogSupport.showSingleSelectDialog(
              options,
              title: 'Repository ${repo.cloneUrl} is currently configured as a '
                  'skill registry.\n'
                  'Do you want to change it to a direct skill source?',
            );
            if (index == 0) {
              manifest = manifest.withoutRegistry(existing).withRegistry(repo);
              logger.info(
                  'Updated registry ${repo.cloneUrl} to be a direct skill '
                  'repo.');
            } else {
              logger.severe(
                  'Aborted: Repository ${repo.cloneUrl} remains a skill registry.');
              continue;
            }
          } else {
            logger.severe(
                'Repository ${repo.cloneUrl} is already configured as a skill registry. '
                'Cannot change to a direct skill source in non-interactive mode.');
            continue;
          }
        }
      } else {
        manifest = manifest.withRegistry(repo);
        logger.info(
            'Added registry ${repo.cloneUrl} to local manifest (bypass package filtering).');
      }
    } on FormatException catch (e) {
      throw UsageException(e.message, usage);
    }
  }

  final globalConfigPath = GlobalConfig.globalPath;
  final globalConfigFile = io.File(globalConfigPath);
  var globalConfig = await GlobalConfig.loadOrEmpty(globalConfigFile);

  final registrySkills = <ScannedSkill>[];
  final registryRepoCommits = <String, String>{};

  if (await gitRunner.isAvailable) {
    final registrySync = RegistrySync(
        repos: [...globalConfig.registries, ...manifest.registries]);
    await registrySync.sync(rootPath, onProgress: logger.info);

    final registryScanner = RegistryScanner();
    registrySkills
      ..addAll(await registryScanner.scan(
        rootPath,
        isGlobal: true,
        repos: globalConfig.registries,
      ))
      ..addAll(await registryScanner.scan(
        rootPath,
        isGlobal: false,
        repos: manifest.registries,
      ));

    for (final repo in registrySync.repos) {
      final repoPath = gitRepoPath(rootPath, repo);
      final commit = await _getGitCommit(repoPath);
      if (commit != null) {
        registryRepoCommits[repo.cloneUrl] = commit;
      }
    }
  } else {
    logger.warning(
      'Warning: git not found. Skipping GitHub registry skills.',
    );
  }

  final advisoryChecker = AdvisoryChecker();
  final advisories = await advisoryChecker.checkAdvisories(
    packages,
    rootPath,
    logger,
    registryRepoCommits: registryRepoCommits,
  );
  if (advisories.isNotEmpty) {
    final buffer = StringBuffer()
      ..writeln('Warning: Found security advisories:');
    for (final entry in advisories.entries) {
      buffer.writeln('  ${entry.key}:');
      for (final summary in entry.value) {
        buffer.writeln('    - $summary');
      }
    }
    logger.warning(buffer.toString());
  }

  final scanner = SkillScanner(logger);
  final dartSkills = await scanner.scan(packages);

  final resolvedPackageNames = packages.map((p) => p.name).toSet();

  final filteredRegistrySkills = <ScannedSkill>[];
  final unfilteredRegistrySkills = <ScannedSkill>[];

  final repoMap = {
    for (final r in [...globalConfig.registries, ...manifest.registries])
      r.cloneUrl: r
  };

  for (final skill in registrySkills) {
    final repo = repoMap[skill.registryUrl];
    if (repo != null && !repo.isSkillRegistry) {
      unfilteredRegistrySkills.add(skill);
    } else {
      filteredRegistrySkills.add(skill);
    }
  }

  var skills = mergeSkills(
    dartSkills: dartSkills,
    registrySkills: filteredRegistrySkills,
    resolvedPackageNames: resolvedPackageNames,
  );

  final packagesWithDartSkills = dartSkills.map((s) => s.packageName).toSet();
  final uniqueUnfiltered = unfilteredRegistrySkills
      .where((s) => !packagesWithDartSkills.contains(s.packageName));
  skills.addAll(uniqueUnfiltered);

  if (skills.isEmpty) {
    logger.info('No skills found in ${packageNames ?? "any"} packages.');
    return false;
  }

  if (packageNames == null) {
    final packagesWithSkills =
        skills.map((skill) => skill.packageName).toSet().toList()..sort();
    if (packagesWithSkills.isNotEmpty) {
      if (dialogSupport != null) {
        final initialSelected =
            Iterable<int>.generate(packagesWithSkills.length).toSet();
        final selectedIndices = await dialogSupport.showMultiSelectDialog(
          packagesWithSkills,
          title: 'Select packages to install skills from:',
          initialSelected: initialSelected,
        );
        if (selectedIndices != null) {
          final selectedPackages =
              selectedIndices.map((i) => packagesWithSkills[i]).toSet();
          skills.removeWhere((s) => !selectedPackages.contains(s.packageName));
        } else {
          logger.info('Installation aborted by user.');
          return false;
        }
      } else {
        logger.info('Available packages with skills:');
        for (final pkg in packagesWithSkills) {
          logger.info('  $pkg');
        }
        logger.info('Rerun with trailing arguments for each package you want '
            'to install skills for, or `all` to install all skills.');
        return false;
      }
    }
  }

  if (skills.isEmpty) {
    logger.info('No skills selected to install.');
    return false;
  }

  final installer = SkillInstaller(dialogSupport);

  for (final ide in ides) {
    final result = await installer.installSkillsForIde(
      ide: ide,
      rootPath: rootPath,
      skills: skills,
      manifest: manifest,
      globalConfig: globalConfig,
    );
    if (result == null) {
      logger.warning('Installation aborted for IDE ${ide.cliName}');
      continue;
    }
    manifest = result.manifest;
    globalConfig = result.globalConfig;
    for (final info in result.installed) {
      logger.info('  [${info.ideName}] Installed ${info.skillName}');
    }
  }

  await globalConfig.save(globalConfigFile);
  await manifest.save(manifestFile(rootPath));

  final ideNames = ides.map((e) => e.cliName).join(', ');
  logger.info('Installed ${skills.length} skill(s) for $ideNames.');

  return true;
}

Future<String?> _getGitCommit(String repoPath) async {
  try {
    final result = await io.Process.run(
      'git',
      ['rev-parse', 'HEAD'],
      workingDirectory: repoPath,
      runInShell: true,
    );
    if (result.exitCode == 0) {
      return (result.stdout as String).trim();
    }
  } catch (e) {
    // Ignore
  }
  return null;
}
