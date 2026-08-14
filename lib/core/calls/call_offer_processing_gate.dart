// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'call_signaling_invariants.dart';

class CallOfferProcessingGate {
  String? _activeOfferKey;
  String? _lastCompletedOfferKey;

  Future<bool> runIfAccepted({
    required String offerKey,
    required void Function(String message) log,
    required Future<void> Function() action,
  }) async {
    if (CallSignalingInvariants.isDuplicateOffer(
      offerKey: offerKey,
      activeOfferKey: _activeOfferKey,
      lastCompletedOfferKey: null,
    )) {
      log('offer:skip duplicate in-flight key=$offerKey');
      return false;
    }
    if (CallSignalingInvariants.isDuplicateOffer(
      offerKey: offerKey,
      activeOfferKey: null,
      lastCompletedOfferKey: _lastCompletedOfferKey,
    )) {
      log('offer:skip duplicate completed key=$offerKey');
      return false;
    }

    _activeOfferKey = offerKey;
    try {
      await action();
      _lastCompletedOfferKey = offerKey;
      return true;
    } finally {
      if (_activeOfferKey == offerKey) {
        _activeOfferKey = null;
      }
    }
  }

  void markCompleted(String offerKey) {
    _lastCompletedOfferKey = offerKey;
  }

  void reset() {
    _activeOfferKey = null;
    _lastCompletedOfferKey = null;
  }
}
