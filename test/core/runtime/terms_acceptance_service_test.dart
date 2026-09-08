import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/core/runtime/terms_acceptance_service.dart';

void main() {
  late StorageService storage;
  late TermsAcceptanceService service;

  setUp(() async {
    await StorageService.resetForTesting();
    storage = StorageService();
    await storage.initForTesting(
      rootDirectory: Directory.systemTemp.createTempSync(
        'peerlink-terms-test-',
      ),
    );
    service = TermsAcceptanceService.forStorage(storage);
  });

  test('requires acceptance by default', () {
    expect(service.isCurrentVersionAccepted, isFalse);
    expect(service.state.accepted, isFalse);
    expect(service.state.version, isNull);
    expect(service.state.acceptedAt, isNull);
  });

  test('stores accepted flag version and timestamp', () async {
    final acceptedAt = DateTime.utc(2026, 8, 24, 10, 30);

    await service.acceptCurrentVersion(acceptedAt: acceptedAt);

    final state = service.state;
    expect(service.isCurrentVersionAccepted, isTrue);
    expect(state.accepted, isTrue);
    expect(state.version, TermsAcceptanceService.currentTermsVersion);
    expect(state.acceptedAt, acceptedAt);
  });

  test('requires reacceptance when stored version is stale', () async {
    final settings = storage.getSettings();
    await settings.put(TermsAcceptanceService.termsAcceptedKey, true);
    await settings.put(TermsAcceptanceService.termsVersionKey, '2026-08-24');
    await settings.put(
      TermsAcceptanceService.termsAcceptedAtKey,
      DateTime.utc(2026, 1, 1).toIso8601String(),
    );

    expect(service.state.accepted, isTrue);
    expect(service.isCurrentVersionAccepted, isFalse);
  });
}
