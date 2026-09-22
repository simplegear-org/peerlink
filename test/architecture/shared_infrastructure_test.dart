import 'package:test/test.dart';

import 'architecture_test_utils.dart';

void main() {
  test('platform bridge package imports stay behind approved seams', () {
    final imports = dartSourcesUnder(const ['lib'])
        .expand((source) => source.imports())
        .where((import) => _platformPackages.any(import.uri.startsWith));

    final actual = <String, Set<String>>{};
    for (final import in imports) {
      actual.putIfAbsent(import.uri, () => <String>{}).add(import.sourcePath);
    }

    expect(
      actual.map((key, value) => MapEntry(key, value.toList()..sort())),
      equals(_approvedPlatformImports),
      reason:
          'Direct platform/network packages must remain limited to current '
          'bridge/adapter files until explicit seams replace them.',
    );
  });
}

const _platformPackages = [
  'package:firebase_messaging/',
  'package:flutter_secure_storage/',
  'package:flutter_webrtc/',
  'package:http/',
  'package:web_socket_channel/',
];

const _approvedPlatformImports = {
  'package:firebase_messaging/firebase_messaging.dart': [
    'lib/core/firebase/firebase_messaging_service.dart',
    'lib/core/firebase/firebase_push_inbound_service.dart',
    'lib/core/firebase/firebase_push_log_formatter.dart',
    'lib/core/firebase/firebase_push_payload_processor.dart',
    'lib/core/firebase/firebase_push_presentation_handler.dart',
    'lib/core/firebase/firebase_push_token_lifecycle.dart',
    'lib/main.dart',
  ],
  'package:flutter_secure_storage/flutter_secure_storage.dart': [
    'lib/core/runtime/secure_storage_platform_options.dart',
    'lib/core/runtime/secure_storage_wrapper.dart',
  ],
  'package:flutter_webrtc/flutter_webrtc.dart': [
    'lib/core/calls/audio_call_peer.dart',
    'lib/core/calls/call_live_media_stall_detector.dart',
    'lib/core/calls/call_local_audio_outbound_refresher.dart',
    'lib/core/calls/call_local_media_controller.dart',
    'lib/core/calls/call_local_video_track_controller.dart',
    'lib/core/calls/call_media_flow_controller.dart',
    'lib/core/calls/call_media_stats_utils.dart',
    'lib/core/calls/call_media_stream_controller.dart',
    'lib/core/calls/call_models.dart',
    'lib/core/calls/call_negotiation_controller.dart',
    'lib/core/calls/call_peer_binding_helper.dart',
    'lib/core/calls/call_peer_bootstrap_controller.dart',
    'lib/core/calls/call_peer_event_controller.dart',
    'lib/core/calls/call_peer_session_controller.dart',
    'lib/core/calls/call_post_ice_recovery_flow_watch.dart',
    'lib/core/calls/call_remote_control_handler.dart',
    'lib/core/calls/call_remote_receiver_owner.dart',
    'lib/core/calls/call_remote_receiver_owner_native.dart',
    'lib/core/calls/call_service.dart',
    'lib/core/calls/call_signaling_invariants.dart',
    'lib/core/calls/call_state_update_helper.dart',
    'lib/core/calls/call_video_channel_snapshot.dart',
    'lib/core/calls/call_video_controller.dart',
    'lib/core/calls/call_video_quality_controller.dart',
    'lib/core/calls/call_video_state.dart',
    'lib/core/calls/call_video_transceiver_controller.dart',
    'lib/core/transport/webrtc_transport.dart',
    'lib/ui/screens/avatar_capture_screen.dart',
    'lib/ui/screens/call_screen_video_view.dart',
    'lib/ui/screens/call_screen_view.dart',
  ],
  'package:flutter_webrtc/src/native/media_stream_track_impl.dart': [
    'lib/core/calls/call_remote_receiver_owner_native.dart',
  ],
  'package:http/http.dart': [
    'lib/core/relay/http_relay_client.dart',
    'lib/core/relay/relay_http_transport.dart',
    'lib/core/relay/relay_http_types.dart',
  ],
  'package:web_socket_channel/io.dart': [
    'lib/core/signaling/bootstrap_signaling_service.dart',
  ],
  'package:web_socket_channel/web_socket_channel.dart': [
    'lib/core/signaling/bootstrap_signaling_protocol_controller.dart',
    'lib/core/signaling/bootstrap_signaling_runtime_state.dart',
    'lib/core/signaling/bootstrap_signaling_service.dart',
    'lib/core/signaling/bootstrap_signaling_session_controller.dart',
  ],
};
