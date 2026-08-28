// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

package org.simplegear.peerlinkapp

import android.content.Context

object PeerlinkAccessControl {
    private const val PREFS_NAME = "peerlink_access_control"
    private const val BLOCKED_PEERS_KEY = "blocked_peers"

    fun syncBlockedPeers(context: Context, peerIds: List<String>) {
        val normalized = peerIds
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toSet()
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(BLOCKED_PEERS_KEY, normalized)
            .apply()
    }

    fun isBlocked(context: Context, peerId: String): Boolean {
        val normalized = peerId.trim()
        if (normalized.isEmpty()) {
            return false
        }
        val peers = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getStringSet(BLOCKED_PEERS_KEY, emptySet()) ?: emptySet()
        return peers.contains(normalized)
    }
}
