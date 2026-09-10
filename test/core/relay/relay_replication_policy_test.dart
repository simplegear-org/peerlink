import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/relay/relay_replication_policy.dart';

void main() {
  test('requires one replica for one candidate', () {
    expect(RelayReplicationPolicy.requiredSuccessfulReplicas(1), 1);
  });

  test('requires both replicas for two candidates', () {
    expect(RelayReplicationPolicy.requiredSuccessfulReplicas(2), 2);
  });

  test('caps candidates at three and requires two replicas', () {
    expect(RelayReplicationPolicy.maxCandidates, 3);
    expect(RelayReplicationPolicy.requiredSuccessfulReplicas(3), 2);
    expect(RelayReplicationPolicy.requiredSuccessfulReplicas(10), 2);
  });
}
