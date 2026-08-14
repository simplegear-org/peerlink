// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../models/message.dart';
import 'media_viewer_view.dart';

class MediaViewerScreen extends StatefulWidget {
  final List<Message> mediaMessages;
  final int initialIndex;

  const MediaViewerScreen({
    super.key,
    required this.mediaMessages,
    required this.initialIndex,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(
      0,
      widget.mediaMessages.length - 1,
    );
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _evictViewedOriginals();
    _pageController.dispose();
    super.dispose();
  }

  void _evictViewedOriginals() {
    for (final message in widget.mediaMessages) {
      _evictMessageOriginal(message);
    }
  }

  void _evictOriginalsAwayFrom(int index) {
    final keepIndexes = {index - 1, index, index + 1};
    for (var i = 0; i < widget.mediaMessages.length; i++) {
      if (!keepIndexes.contains(i)) {
        _evictMessageOriginal(widget.mediaMessages[i]);
      }
    }
  }

  void _evictMessageOriginal(Message message) {
    final file = message.localFile;
    if (file != null) {
      FileImage(file).evict();
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.mediaMessages[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.fileName ?? message.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.mediaMessages.length > 1)
              Text(
                '${_currentIndex + 1} / ${widget.mediaMessages.length}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.mediaMessages.length,
          onPageChanged: (index) {
            if (!mounted) {
              return;
            }
            _evictOriginalsAwayFrom(index);
            setState(() {
              _currentIndex = index;
            });
          },
          itemBuilder: (context, index) {
            final media = widget.mediaMessages[index];
            if (media.isImage) {
              return MediaImageViewer(message: media);
            }
            if (media.isVideo) {
              return MediaVideoPage(message: media);
            }
            return Center(
              child: Text(
                context.strings.previewUnavailable,
                style: const TextStyle(color: Colors.white70),
              ),
            );
          },
        ),
      ),
    );
  }
}
