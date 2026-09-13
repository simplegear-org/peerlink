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

  test('resolves website short-invite fallback scheme', () {
    expect(
      AppDeepLinkCoordinator.resolveShortInviteUri(
        Uri.parse(
          'peerlink://invite?url=https%3A%2F%2Fsimplegear.org%2Fi%2Fabcdefghijklmnopqrstuv',
        ),
      ),
      Uri.parse('https://simplegear.org/i/abcdefghijklmnopqrstuv'),
    );
  });
}
