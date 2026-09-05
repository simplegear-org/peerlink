import 'package:peerlink/app/deep_links/app_deep_link_coordinator.dart';
import 'package:test/test.dart';

void main() {
  test('extractDeepLinkCandidate keeps direct uri', () {
    expect(
      AppDeepLinkCoordinator.extractDeepLinkCandidate(
        'peerlink://invite?payload=abc',
      ),
      'peerlink://invite?payload=abc',
    );
  });

  test('extractDeepLinkCandidate extracts uri from shared text', () {
    expect(
      AppDeepLinkCoordinator.extractDeepLinkCandidate(
        'Open this: https://simplegear.org/invite?payload=abc.',
      ),
      'https://simplegear.org/invite?payload=abc',
    );
  });
}
