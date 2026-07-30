import 'dart:io';

/// Dev-only: the agent lives beside this app in the same repo, launched via
/// `uv run`. Once the agent ships as an installed service (Phase 2.5), this
/// becomes a fixed install path instead of a sibling-directory guess.
class AgentConfig {
  static const host = 'localhost';
  static const port = 8787;

  static String get baseUrl => 'http://$host:$port';

  static String get tokenPath {
    final localAppData = Platform.environment['LOCALAPPDATA']!;
    return '$localAppData\\ia-agent\\token';
  }

  static const agentDir = r'D:\Coding\Insta-Automate-Control-Center\agent';
}
