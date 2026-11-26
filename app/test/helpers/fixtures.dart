import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:taskplus/core/auth/auth_controller.dart';
import 'package:taskplus/data/models.dart';
import 'package:taskplus/data/providers.dart';

final me = AppUser(id: 'U-ME', name: 'Dhaval Dalsania', role: 'staff', departmentId: 'D-DEV');
final head = AppUser(id: 'U-HEAD', name: 'Tushar Parmar', role: 'dept_head', departmentId: 'D-DEV');
final dev = DepartmentInfo(id: 'D-DEV', name: 'Development', modules: ['Profit NX', 'Ornate', 'Power BI', 'Other'], headUserId: 'U-HEAD', members: [
  Member(id: 'U-ME', name: 'Dhaval Dalsania', role: 'staff'),
  Member(id: 'U-V', name: 'Vishwas', role: 'staff'),
  Member(id: 'U-HEAD', name: 'Tushar Parmar', role: 'dept_head'),
]);

class FakeAuth extends AuthController {
  FakeAuth(this.user);
  final AppUser user;
  @override
  Future<AppUser?> build() async => user;
}

Message message({String sender = 'U-RIYA', String kind = 'text', String? text = 'Profit NX login failing', String? transcript}) => Message(
    id: 'M1', threadId: 'T1', senderId: sender, clientMsgId: 'c1', kind: kind, bodyText: text,
    audioKey: kind == 'voice' ? 'direct/2026/11/a.ogg' : null, audioDurationS: kind == 'voice' ? 12 : null, transcript: transcript,
    createdAt: DateTime.utc(2026, 11, 26, 9));

Task task({String ai = 'done', String status = 'Open', String priority = 'High', String? assignee, String? dept = 'D-DEV',
        List<String> warnings = const [], DateTime? due, DateTime? updated, List<String> actions = const []}) =>
    Task(
      id: 'TK1', messageId: 'M1', threadId: 'T1', priority: priority, status: status, aiStatus: ai,
      dueAt: due ?? DateTime.utc(2099), updatedAt: updated ?? DateTime.utc(2026, 11, 26, 9),
      subject: ai == 'done' ? 'Profit NX Login Failure' : null, module: ai == 'done' ? 'Profit NX' : null,
      customerName: ai == 'done' ? 'Mehta Traders' : null, customerPhone: ai == 'done' ? '9825012345' : null,
      licenseNo: ai == 'done' ? 'PNX-881' : null, details: ai == 'done' ? 'Login fails for all users.' : null,
      assigneeId: assignee, departmentId: dept, warnings: warnings, aiError: ai == 'needs_review' ? 'AI unavailable' : null, actions: actions,
    );

/// A screen inside the app's providers, with a signed-in user and the Development department.
Widget wrap(Widget child, {AppUser? user, double width = 412}) => ProviderScope(
      overrides: [
        authProvider.overrideWith(() => FakeAuth(user ?? me)),
        departmentProvider.overrideWith((ref, id) async => dev),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Scaffold(body: SizedBox(width: width, child: child)),
        ),
      ),
    );

Future<void> pumpAt(WidgetTester tester, Widget w, {double width = 412}) async {
  tester.view.physicalSize = Size(width * 3, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(w);
  await tester.pumpAndSettle();
}
