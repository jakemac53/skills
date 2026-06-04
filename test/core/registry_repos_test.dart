import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:skills/src/core/registry_repos.dart';
import 'package:skills/src/models/skill_manifest.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    Logger.root.onRecord.listen((r) => printOnFailure(r.toString()));
  });

  group('GitRepo', () {
    test('pathSegment encodes cloneUrl', () {
      const repo = GitRepo(
        cloneUrl: 'https://github.com/flutter/skills.git',
      );
      expect(repo.pathSegment,
          equals(Uri.encodeComponent('https://github.com/flutter/skills.git')));
    });

    test('cloneUrl is the provided URL', () {
      const repo = GitRepo(
        cloneUrl: 'https://example.com/repo.git',
      );
      expect(
        repo.cloneUrl,
        equals('https://example.com/repo.git'),
      );
    });
  });

  group('GitRepo.fromArgument', () {
    test('parses github shorthand', () {
      final repo = GitRepo.fromArgument('flutter/skills');
      expect(repo.cloneUrl, equals('https://github.com/flutter/skills.git'));
    });

    test('parses full HTTPS Git URI', () {
      final repo = GitRepo.fromArgument('https://example.com/repo.git');
      expect(repo.cloneUrl, equals('https://example.com/repo.git'));
    });

    test('parses SSH Git URI', () {
      final repo = GitRepo.fromArgument('git@github.com:flutter/skills.git');
      expect(repo.cloneUrl, equals('git@github.com:flutter/skills.git'));
    });

    test('throws FormatException for invalid shorthand', () {
      expect(() => GitRepo.fromArgument('a/b/c'), throwsFormatException);
    });

    test('throws FormatException for invalid URI', () {
      expect(
          () => GitRepo.fromArgument('http://foo:bar'), throwsFormatException);
    });

    test('supports isSkillRegistry parameter', () {
      final repo =
          GitRepo.fromArgument('flutter/skills', isSkillRegistry: false);
      expect(repo.isSkillRegistry, isFalse);
    });
  });

  group('registryReposPath / gitRepoPath', () {
    test('registryReposPath includes .dart_tool/skills/repos', () {
      final path = registryReposPath('/project');
      expect(path, contains(p.join(SkillManifest.cacheDirPath, 'repos')));
    });

    test('gitRepoPath includes host, owner and repo', () {
      const repo = GitRepo(
        cloneUrl: 'https://github.com/flutter/skills.git',
      );
      final path = gitRepoPath('/project', repo);
      expect(
        path,
        contains(p.join(SkillManifest.cacheDirPath, 'repos',
            Uri.encodeComponent(repo.cloneUrl))),
      );
    });
  });
}
