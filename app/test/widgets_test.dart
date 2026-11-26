import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:taskplus/data/models.dart';
import 'package:taskplus/features/chat/chat_controller.dart';
import 'package:taskplus/features/chat/chat_screen.dart';
import 'package:taskplus/features/composer/composer.dart';
import 'package:taskplus/features/filters/filter_block.dart';
import 'package:taskplus/features/slash/slash.dart';
import 'package:taskplus/features/task_card/task_card.dart';

import 'helpers/fixtures.dart';

void main() {
  group('filter block', () {
    for (final width in [360.0, 412.0]) {
      testWidgets('3 buttons in 2 rows fit $width dp with no overflow', (tester) async {
        await pumpAt(tester, wrap(FilterBlock(onTap: (_) {}, myPending: 128, overdue: 37), width: width), width: width);
        expect(tester.takeException(), isNull);
        for (final f in TaskFilter.values) expect(find.byKey(Key('filter-${f.api}')), findsOneWidget);
        final pending = tester.getRect(find.byKey(const Key('filter-my_pending')));
        final overdue = tester.getRect(find.byKey(const Key('filter-overdue')));
        final closed = tester.getRect(find.byKey(const Key('filter-closed')));
        expect(pending.top, overdue.top); // row 1
        expect(closed.top, greaterThan(pending.bottom)); // row 2
        expect(closed.width, closeTo(pending.width, 1)); // same width
        expect(overdue.right, lessThanOrEqualTo(width));
        expect(find.text('128'), findsOneWidget);
      });
    }
  });

  group('task card', () {
    testWidgets('pending: skeleton, "Structuring…", raw text', (tester) async {
      await pumpAt(tester, wrap(TaskCard(item: ChatItem(message: message(), task: task(ai: 'pending')), directRecipient: true)));
      expect(find.text('Structuring…'), findsOneWidget);
      expect(find.text('Profit NX login failing'), findsOneWidget);
    });

    testWidgets('done: priority, module, subject, fields; Accept for a recipient in the department', (tester) async {
      await pumpAt(tester, wrap(TaskCard(item: ChatItem(message: message(), task: task()), directRecipient: false)));
      for (final s in ['High', 'Profit NX', 'Profit NX Login Failure', 'Mehta Traders', '9825012345', 'PNX-881', 'Login fails for all users.', 'Accept Task']) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.text('Location'), findsNothing); // empty fields are hidden
    });

    testWidgets('needs review: amber chip and the raw text', (tester) async {
      await pumpAt(tester, wrap(TaskCard(item: ChatItem(message: message(), task: task(ai: 'needs_review')), directRecipient: true)));
      expect(find.text('Needs review'), findsOneWidget);
      expect(find.text('Profit NX login failing'), findsOneWidget);
    });

    testWidgets('warnings show ⚠ next to the field; overdue shows in red', (tester) async {
      await pumpAt(tester, wrap(TaskCard(item: ChatItem(message: message(), task: task(warnings: ['customer_phone: not valid'], due: DateTime.utc(2020))), directRecipient: true)));
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
    });

    testWidgets('voice task: play button, length, transcript on request', (tester) async {
      await pumpAt(tester, wrap(TaskCard(item: ChatItem(message: message(kind: 'voice', text: null, transcript: 'Profit NX login band hai'), task: task()), directRecipient: true)));
      expect(find.byTooltip('Play voice note'), findsOneWidget);
      expect(find.text('0:12'), findsOneWidget);
      await tester.tap(find.text('Show transcript'));
      await tester.pump();
      expect(find.text('Profit NX login band hai'), findsOneWidget);
    });
  });

  group('card actions by role', () {
    test('recipient can accept an open task; the sender cannot', () {
      expect(CardActions.of(task(), viewer: me, senderId: 'U-RIYA', directRecipient: false).accept, isTrue);
      expect(CardActions.of(task(), viewer: me, senderId: 'U-ME', directRecipient: false).accept, isFalse);
      expect(CardActions.of(task(dept: null), viewer: me, senderId: 'U-RIYA', directRecipient: false).accept, isFalse);
    });
    test('head or assignee may reassign; only the assignee moves the status', () {
      expect(CardActions.of(task(status: 'Accepted', assignee: 'U-V'), viewer: head, senderId: 'U-RIYA', directRecipient: false).reassign, isTrue);
      expect(CardActions.of(task(status: 'Accepted', assignee: 'U-V'), viewer: me, senderId: 'U-RIYA', directRecipient: false).reassign, isFalse);
      expect(CardActions.of(task(status: 'Accepted', assignee: 'U-ME'), viewer: me, senderId: 'U-RIYA', directRecipient: false).next, ['InProgress', 'Closed']);
      expect(CardActions.of(task(status: 'InProgress', assignee: 'U-ME'), viewer: me, senderId: 'U-RIYA', directRecipient: false).next, ['Closed']);
      expect(CardActions.of(task(status: 'Closed', assignee: 'U-ME'), viewer: me, senderId: 'U-RIYA', directRecipient: false).reassign, isFalse);
    });
  });

  testWidgets('sent bubble shows only my text and the status', (tester) async {
    await pumpAt(tester, wrap(SentBubble(item: ChatItem(message: message(sender: 'U-ME'), task: task(status: 'Accepted')))));
    expect(find.text('Profit NX login failing'), findsOneWidget);
    expect(find.textContaining('Accepted'), findsOneWidget);
    expect(find.text('Mehta Traders'), findsNothing); // the sender never sees the structured card
  });

  group('composer', () {
    testWidgets('"/" opens the menu; /priority becomes a chip and leaves the text', (tester) async {
      Draft? sent;
      await pumpAt(tester, wrap(Composer(threadId: 'T1', departmentId: 'D-DEV', onSend: (d) => sent = d)));
      await tester.enterText(find.byKey(const Key('composer')), 'printer jam /pri');
      await tester.pump();
      expect(find.byKey(const Key('slash-menu')), findsOneWidget);
      await tester.tap(find.text('/priority'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('High'));
      await tester.pumpAndSettle();
      expect(find.text('Priority: High'), findsOneWidget);
      await tester.tap(find.byKey(const Key('send')));
      expect(sent!.bodyText, 'printer jam');
      expect(sent!.overrides, {'priority': 'High'});
    });

    testWidgets('"@" in a department chat tags a member', (tester) async {
      Draft? sent;
      await pumpAt(tester, wrap(Composer(threadId: 'T1', departmentId: 'D-DEV', onSend: (d) => sent = d)));
      await tester.enterText(find.byKey(const Key('composer')), 'check ERP @vis');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vishwas'));
      await tester.pump();
      expect(find.text('@Vishwas'), findsOneWidget);
      await tester.tap(find.byKey(const Key('send')));
      expect(sent!.taggedUserId, 'U-V');
      expect(sent!.bodyText, 'check ERP');
    });

    testWidgets('empty: hold-to-record button instead of send', (tester) async {
      await pumpAt(tester, wrap(Composer(threadId: 'T1', onSend: (_) {})));
      expect(find.byKey(const Key('record')), findsOneWidget);
      expect(find.byKey(const Key('send')), findsNothing);
    });
  });

  group('slash parsing', () {
    test('finds the word being typed and removes it', () {
      final t = ActiveToken.at('hello /pri world', 10, '/')!;
      expect(t.query, 'pri');
      expect(t.removeFrom('hello /pri world'), 'hello world');
      expect(ActiveToken.at('a/b', 3, '/'), isNull); // not at the start of a word
      expect(matchingCommands('l').map((c) => c.name), ['license']);
    });
  });

  group('merging events', () {
    test('keeps the newest task when events arrive out of order or twice', () {
      final older = task(ai: 'pending', updated: DateTime.utc(2026, 11, 26, 9));
      final newer = task(updated: DateTime.utc(2026, 11, 26, 9, 1));
      final items = [ChatItem(message: message(), task: older)];
      final a = ChatMerge.task(ChatMerge.task(items, newer), older); // late duplicate of the old one
      expect(a.single.task!.aiStatus, 'done');
      expect(ChatMerge.upsert(a, ChatItem(message: message(), task: older)).single.task!.aiStatus, 'done');
    });
  });
}
