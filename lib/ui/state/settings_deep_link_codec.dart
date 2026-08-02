class SettingsDeepLinkCodec {
  const SettingsDeepLinkCodec._();

  static bool isInviteUri(Uri uri) {
    if (uri.scheme == 'peerlink' && uri.host == 'invite') {
      return true;
    }
    final isWeb = uri.scheme == 'https' || uri.scheme == 'http';
    if (!isWeb) {
      return false;
    }
    if (uri.pathSegments.contains('invite')) {
      return true;
    }
    final fragmentUri = _fragmentUri(uri);
    return fragmentUri?.pathSegments.contains('invite') == true;
  }

  static bool isAccountPairingUri(Uri uri) {
    if (uri.scheme == 'peerlink' && uri.host == 'pair') {
      return true;
    }
    final isWeb = uri.scheme == 'https' || uri.scheme == 'http';
    if (!isWeb) {
      return false;
    }
    if (uri.pathSegments.contains('pair')) {
      return true;
    }
    final fragmentUri = _fragmentUri(uri);
    return fragmentUri?.pathSegments.contains('pair') == true;
  }

  static bool isServerConfigUri(Uri uri) {
    if (uri.scheme == 'peerlink' && uri.host == 'config') {
      return true;
    }
    final isWeb = uri.scheme == 'https' || uri.scheme == 'http';
    if (!isWeb) {
      return false;
    }
    if (uri.pathSegments.contains('config')) {
      return true;
    }
    final fragmentUri = _fragmentUri(uri);
    return fragmentUri?.pathSegments.contains('config') == true;
  }

  static String? payloadFromUri(Uri uri) {
    final directPayload = uri.queryParameters['payload'];
    if (directPayload?.trim().isNotEmpty == true) {
      return directPayload;
    }
    return _fragmentUri(uri)?.queryParameters['payload'];
  }

  static Uri? _fragmentUri(Uri uri) {
    final fragment = uri.fragment.trim();
    if (fragment.isEmpty) {
      return null;
    }
    if (!fragment.startsWith('/') &&
        !fragment.contains('://') &&
        fragment.contains('=')) {
      return Uri.tryParse('https://peerlink.local/?$fragment');
    }
    final normalized = fragment.startsWith('/')
        ? 'https://peerlink.local$fragment'
        : fragment;
    return Uri.tryParse(normalized);
  }
}
