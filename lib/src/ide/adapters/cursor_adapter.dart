import '../ide.dart';
import 'agent_skills_adapter.dart';

/// Cursor IDE adapter.
///
/// Installs skills to `.cursor/skills/<pkg>-<skill>/SKILL.md`.
class CursorAdapter extends AgentSkillsAdapter {
  new(String projectPath) : super(Ide.cursor.skillsPath(projectPath));
}
