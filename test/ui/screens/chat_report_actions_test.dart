import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/moderation_report_models.dart';
import 'package:peerlink/ui/localization/app_language.dart';
import 'package:peerlink/ui/localization/app_strings.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/ui/screens/chat_report_actions.dart';
import 'package:peerlink/ui/state/chat_controller.dart';

class _FakeChatController implements ChatController {
  String? reportedPeerId;
  String? deletedPeerId;
  String? deletedMessageId;
  ModerationReportReason? reason;
  Message? selectedMessage;
  String? groupId;
  String? blockedPeerId;

  @override
  Future<void> blockAndReportPeer(
    String peerId, {
    required ModerationReportReason reason,
    String? groupId,
  }) async {
    blockedPeerId = peerId;
    this.reason = reason;
    this.groupId = groupId;
  }

  @override
  Future<void> reportPeer({
    required String peerId,
    required ModerationReportReason reason,
    Message? selectedMessage,
    String? groupId,
  }) async {
    reportedPeerId = peerId;
    this.reason = reason;
    this.selectedMessage = selectedMessage;
    this.groupId = groupId;
  }

  @override
  Future<void> deleteMessage(String peerId, String messageId) async {
    deletedPeerId = peerId;
    deletedMessageId = messageId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('reports group message author and hides local message', (
    tester,
  ) async {
    final controller = _FakeChatController();
    final actions = ChatReportActions();
    final chat = Chat(peerId: 'group:1', name: 'Group', isGroup: true);
    BuildContext? hostContext;
    final message = Message(
      id: 'm1',
      peerId: 'group:1',
      text: 'private text',
      senderPeerId: 'bad-peer',
      incoming: true,
      timestamp: DateTime.utc(2026, 8, 24, 12),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: AppLanguage.en.locale,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = hostContext!;
    final reportFuture = actions.reportMessage(
      context: context,
      chat: chat,
      controller: controller,
      message: message,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Harassment'));
    await tester.pumpAndSettle();
    await reportFuture;

    expect(controller.reportedPeerId, 'bad-peer');
    expect(controller.reason, ModerationReportReason.harassment);
    expect(controller.selectedMessage, same(message));
    expect(controller.groupId, 'group:1');
    expect(controller.deletedPeerId, 'group:1');
    expect(controller.deletedMessageId, 'm1');

    final blockFuture = actions.blockAndReportUser(
      context: context,
      peerId: 'bad-peer',
      controller: controller,
      groupId: chat.peerId,
    );
    await tester.pumpAndSettle();
    expect(controller.blockedPeerId, isNull);
    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();
    await blockFuture;
    expect(controller.blockedPeerId, 'bad-peer');
    expect(controller.reason, ModerationReportReason.spam);
    expect(controller.groupId, 'group:1');
  });
}
