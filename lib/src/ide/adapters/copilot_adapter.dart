import '../ide.dart';
import 'agent_skills_adapter.dart';

/// GitHub Copilot adapter.
///
/// Installs skills to `.github/skills/<skill-name>/` per
/// [Copilot agent skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills).
class CopilotAdapter extends AgentSkillsAdapter {
  new(String projectPath)
      : super(Ide.copilot.skillsPath(projectPath));
}
