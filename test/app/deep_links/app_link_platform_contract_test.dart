import 'dart:io';

import 'package:test/test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('Android declares verified short-invite App Link and forwards it', () {
    final manifest = source('android/app/src/main/AndroidManifest.xml');
    final activity = source(
      'android/app/src/main/kotlin/org/simplegear/peerlinkapp/MainActivity.kt',
    );

    expect(manifest, contains('android:autoVerify="true"'));
    expect(manifest, contains('android:host="simplegear.org"'));
    expect(manifest, contains('android:pathPrefix="/i"'));
    expect(manifest, contains('android:scheme="peerlink" android:host="call"'));
    expect(activity, contains('it == "i"'));
    expect(activity, contains('eventSink?.success(link)'));
    expect(activity, contains('pendingLink = link'));
  });

  test('iOS declares and forwards short-invite Universal Links', () {
    final entitlements = source('ios/Runner/Runner.entitlements');
    final delegate = source('ios/Runner/AppDelegate.swift');

    expect(entitlements, contains('applinks:simplegear.org'));
    expect(delegate, contains('url.pathComponents.contains("i")'));
    expect(delegate, contains('continue userActivity: NSUserActivity'));
    expect(delegate, contains('DeepLinkChannel.shared.handle(url: url)'));
    expect(delegate, contains('pendingLink = link'));
  });
}
