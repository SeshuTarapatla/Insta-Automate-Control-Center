import 'dart:io';

import 'agent_config.dart';

class AgentToken {
  static Future<String?> read() async {
    final file = File(AgentConfig.tokenPath);
    if (!await file.exists()) return null;
    final token = (await file.readAsString()).trim();
    return token.isEmpty ? null : token;
  }
}
