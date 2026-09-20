// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

package org.simplegear.peerlinkapp

import android.content.Context

/** Small native cache used before the Flutter engine is running for a call. */
object PeerlinkCallerNames {
    private const val prefsName = "peerlink_caller_names"
    private const val namesKey = "names"

    fun sync(context: Context, raw: Map<*, *>) {
        val names = raw.entries.mapNotNull { (rawPeerId, rawName) ->
            val peerId = rawPeerId?.toString()?.trim().orEmpty()
            val name = rawName?.toString()?.trim().orEmpty()
            if (peerId.isEmpty() || name.isEmpty() || name == peerId) null else peerId to name
        }.toMap()
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(namesKey, names.map { "${it.key}\u0000${it.value}" }.toSet())
            .apply()
    }

    fun resolve(context: Context, peerId: String): String? {
        val entries = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getStringSet(namesKey, emptySet()).orEmpty()
        return entries.firstNotNullOfOrNull { entry ->
            val separator = entry.indexOf('\u0000')
            if (separator <= 0 || entry.substring(0, separator) != peerId) null
            else entry.substring(separator + 1).takeIf { it.isNotBlank() }
        }
    }
}
