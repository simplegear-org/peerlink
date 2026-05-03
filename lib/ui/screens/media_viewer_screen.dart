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
    _pageController.dispose();
    super.dispose();
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
