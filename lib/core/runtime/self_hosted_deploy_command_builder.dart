import 'dart:convert';

class SelfHostedDeployCommandBuilder {
  final String bootstrapScriptUrl;
  final String deployRepoUrl;
  final String deployBranch;
  final String deployDirName;
  final String deploySuccessMarker;

  const SelfHostedDeployCommandBuilder({
    required this.bootstrapScriptUrl,
    required this.deployRepoUrl,
    required this.deployBranch,
    required this.deployDirName,
    required this.deploySuccessMarker,
  });

  String buildDeployCommand({
    required String publicHost,
    required String turnUser,
    required String turnPassword,
    required String loginPassword,
  }) {
    final escapedPublicHost = shellEscape(publicHost);
    final escapedTurnUser = shellEscape(turnUser);
    final escapedTurnPassword = shellEscape(turnPassword);
    final escapedLoginPassword = shellEscape(loginPassword);
    final escapedScriptUrl = shellEscape(bootstrapScriptUrl);
    final escapedRepoUrl = shellEscape(deployRepoUrl);
    final escapedBranch = shellEscape(deployBranch);
    final escapedDirName = shellEscape(deployDirName);

    final script = [
      'set -euo pipefail',
      'if command -v sudo >/dev/null 2>&1; then',
      '  sudo_password=$escapedLoginPassword',
      '  sudo -S -p \'\' -v <<< "\$sudo_password"',
      '  unset sudo_password',
      'fi',
      'export PUBLIC_HOST=$escapedPublicHost',
      'export TURN_USER=$escapedTurnUser',
      'export TURN_PASSWORD=$escapedTurnPassword',
      'if [ -e $escapedDirName ]; then rm -rf $escapedDirName || true; fi',
      'if [ -e $escapedDirName ] && command -v sudo >/dev/null 2>&1; then sudo rm -rf $escapedDirName || true; fi',
      'if [ -e $escapedDirName ]; then echo "cleanup failed for $escapedDirName"; exit 1; fi',
      'rm -f get-docker.sh || true',
      'bootstrap_script="\$(mktemp)"',
      'trap \'rm -f "\$bootstrap_script"\' EXIT',
      'if command -v wget >/dev/null 2>&1; then',
      '  wget -qO "\$bootstrap_script" $escapedScriptUrl',
      'elif command -v curl >/dev/null 2>&1; then',
      '  curl -fsSL $escapedScriptUrl -o "\$bootstrap_script"',
      'else',
      '  echo "Neither wget nor curl is installed on the server" >&2',
      '  exit 127',
      'fi',
      'bash "\$bootstrap_script" $escapedRepoUrl $escapedBranch $escapedDirName',
      'echo $deploySuccessMarker',
    ].join('\n');

    return "bash -lc ${shellEscape(script)}";
  }

  static String lastLines(String text, {int maxLines = 6}) {
    final lines = const LineSplitter()
        .convert(text)
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return '';
    }
    final start = lines.length > maxLines ? lines.length - maxLines : 0;
    return lines.sublist(start).join('\n');
  }

  static String shellEscape(String value) {
    if (value.isEmpty) {
      return "''";
    }
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }
}
