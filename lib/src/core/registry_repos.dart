import 'package:path/path.dart' as p;

import '../models/skill_manifest.dart';

/// How skill directories are organized inside a registry repo's `skills/` folder.
enum RegistrySkillLayout {
  /// Skills are directly under `skills/`; each dir name is `<package>-<suffix>`
  /// (e.g. `skills/shadcn_ui-buttons`).
  flat,

  /// Skills are grouped by package: `skills/<package>/<skill-dir>/`
  /// (e.g. `skills/riverpod/riverpod-get-started`).
  groupedByPackage,
}

/// A registry repository with a clone URL.
/// A Git repository that contains skills.
///
/// Can be a skill registry (contains skills for multiple packages, only installs
/// skills matching package dependencies) or a direct skill source (installs all
/// skills).
class GitRepo {
  final String cloneUrl;

  /// Absolute paths where this repo is installed.
  final List<String> installs;

  /// Whether this repo is a skill registry.
  ///
  /// Skill registries only install skills matching package dependencies.
  /// If false, all skills from the repo are installed.
  final bool isSkillRegistry;

  const GitRepo({
    required this.cloneUrl,
    this.installs = const [],
    this.isSkillRegistry = true,
  });

  GitRepo copyWith({
    String? cloneUrl,
    List<String>? installs,
    bool? isSkillRegistry,
  }) {
    return GitRepo(
      cloneUrl: cloneUrl ?? this.cloneUrl,
      installs: installs ?? this.installs,
      isSkillRegistry: isSkillRegistry ?? this.isSkillRegistry,
    );
  }

  factory GitRepo.fromJson(Map<String, dynamic> json) {
    final installs = (json['installs'] as List<dynamic>?)?.cast<String>() ?? [];
    final cloneUrl = json['cloneUrl'] as String;
    final isSkillRegistry = json['isSkillRegistry'] as bool? ??
        json['packageFilter'] as bool? ?? // Fallback for backward compatibility
        true;
    return GitRepo(
      cloneUrl: cloneUrl,
      installs: installs,
      isSkillRegistry: isSkillRegistry,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cloneUrl': cloneUrl,
      'installs': installs,
      'isSkillRegistry': isSkillRegistry,
    };
  }

  /// Returns a copy with a new install location added.
  GitRepo withInstall(String location) {
    if (installs.contains(location)) return this;
    return GitRepo(
      cloneUrl: cloneUrl,
      installs: [...installs, location],
      isSkillRegistry: isSkillRegistry,
    );
  }

  /// Parses a registry argument into a [GitRepo].
  ///
  /// Supports `owner/repo` shorthand for GitHub, or full Git URIs.
  /// Throws [FormatException] if the format is invalid.
  static GitRepo parse(String arg) {
    if (arg.contains('/') && !arg.contains(':') && !arg.contains('@')) {
      final parts = arg.split('/');
      if (parts.length != 2) {
        throw FormatException(
          'Invalid repo format: $arg. Expected <owner>/<repo> or a Git URI.',
        );
      }
      final url = 'https://github.com/${parts[0]}/${parts[1]}.git';
      return GitRepo(cloneUrl: url);
    } else {
      return GitRepo(cloneUrl: arg);
    }
  }

  /// The path segment for this repo under [reposDir].
  String get pathSegment => Uri.encodeComponent(cloneUrl);
}

/// Returns the absolute path to the repos root under [rootPath]:
/// `<rootPath>/.dart_tool/skills/repos`.
String registryReposPath(String rootPath) {
  return p.join(rootPath, SkillManifest.cacheDirPath, 'repos');
}

/// Returns the absolute path where [repo] should be cloned under [rootPath]:
/// `<rootPath>/.dart_tool/skills/repos/<owner>/<name>`.
String gitRepoPath(String rootPath, GitRepo repo) {
  return p.join(registryReposPath(rootPath), repo.pathSegment);
}
