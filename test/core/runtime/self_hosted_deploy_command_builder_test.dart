import 'package:peerlink/core/runtime/self_hosted_deploy_command_builder.dart';
import 'package:test/test.dart';

void main() {
  test('shellEscape quotes empty and single quotes safely', () {
    expect(SelfHostedDeployCommandBuilder.shellEscape(''), "''");
    expect(
      SelfHostedDeployCommandBuilder.shellEscape("host'one"),
      "'host'\"'\"'one'",
    );
  });

  test('buildDeployCommand includes escaped inputs and success marker', () {
    const builder = SelfHostedDeployCommandBuilder(
      bootstrapScriptUrl: 'https://example.test/bootstrap.sh',
      deployRepoUrl: 'https://example.test/repo.git',
      deployBranch: 'main',
      deployDirName: 'peerlink_servers',
      deploySuccessMarker: '__OK__',
    );

    final command = builder.buildDeployCommand(
      publicHost: "host'one",
      turnUser: 'peerlink',
      turnPassword: 'pass',
      loginPassword: 'sudo-pass',
    );

    expect(command, startsWith('bash -lc '));
    expect(command, contains('__OK__'));
    expect(command, contains('host'));
    expect(command, contains('one'));
  });

  test('lastLines returns non-empty tail only', () {
    expect(
      SelfHostedDeployCommandBuilder.lastLines('a\n\n b \nc\nd', maxLines: 2),
      'c\nd',
    );
  });
}
