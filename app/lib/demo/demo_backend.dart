// In-browser demo backend for the shared web link: the same API the real server offers, answered from memory,
// with sample people, teams and tasks. The workflow rules mirror server/src/workflow/engine.ts; the "AI" is a
// simple keyword reader (the real app uses an LLM). Nothing leaves the browser.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class DemoApi implements HttpClientAdapter {
  DemoApi([DemoBackend? backend]) : backend = backend ?? DemoBackend.seeded();
  final DemoBackend backend;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    Object? body;
    if (o.data is Map || o.data is List) {
      body = o.data;
    } else if (requestStream != null) {
      final bytes = await requestStream.expand((b) => b).toList();
      if (bytes.isNotEmpty) body = jsonDecode(utf8.decode(bytes));
    }
    final uri = Uri.parse(o.uri.toString());
    final auth = '${o.headers['authorization'] ?? ''}';
    final me = auth.startsWith('Bearer demo:') ? auth.substring(12) : null;
    final path = uri.path.replaceFirst(RegExp(r'^.*?/v1'), '');
    final (status, json) = backend.handle(o.method, path, uri.queryParameters, body is Map ? Map<String, dynamic>.from(body) : const {}, me);
    return ResponseBody.fromString(jsonEncode(json), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

class _Err implements Exception {
  _Err(this.status, this.code, this.message);
  final int status;
  final String code, message;
}

const _active = ['Accepted', 'InProgress', 'WaitingInfo', 'WaitingDept', 'Blocked'];
const _finished = ['Closed', 'Rejected', 'Transferred', 'Cancelled'];
const _acceptMin = {'Critical': 15, 'High': 30, 'Medium': 120, 'Low': 240};
const _completeH = {'Critical': 4, 'High': 9, 'Medium': 27, 'Low': 63};
const _order = ['Low', 'Medium', 'High', 'Critical'];

class DemoBackend {
  DemoBackend._();
  final users = <Map<String, dynamic>>[];
  final depts = <Map<String, dynamic>>[];
  final teams = <Map<String, dynamic>>[];
  final threads = <Map<String, dynamic>>[];
  final messages = <Map<String, dynamic>>[];
  final tasks = <Map<String, dynamic>>[];
  final events = <Map<String, dynamic>>[];
  final suggestions = <Map<String, dynamic>>[];
  final notes = <Map<String, dynamic>>[]; // the bell
  final holidays = <Map<String, dynamic>>[
    {'day': '2027-01-26', 'name': 'Republic Day'}, {'day': '2026-12-25', 'name': 'Christmas'},
  ];
  final customers = ['Mehta Traders', 'Shree Ganesh Textiles', 'Sunrise Pharma', 'Om Logistics', 'Patel Agro Foods', 'Kaveri Steel'];
  int _seq = 0, _ticket = 41;
  String _id(String p) => '$p-${++_seq}';
  DateTime now() => DateTime.now().toUtc();

  // ---------------------------------------------------------------- sample data
  factory DemoBackend.seeded() {
    final b = DemoBackend._();
    String dept(String name, List<String> modules) { final id = b._id('D'); b.depts.add({'id': id, 'name': name, 'modules': modules, 'head': null}); return id; }
    final sup = dept('Support', ['Profit NX', 'SQL Installation', 'Licensing', 'Printing', 'Other']);
    final dev = dept('Development', ['Profit NX', 'Ornate', 'Power BI', 'Mobile App', 'Other']);
    final sal = dept('Sales', ['Demo Request', 'Quotation', 'Renewal', 'New License', 'Other']);
    final hr = dept('HR', ['Payroll', 'Leave', 'Attendance', 'Onboarding', 'Other']);
    String team(String d, String name) { final id = b._id('T'); b.teams.add({'id': id, 'dept': d, 'name': name, 'lead': null}); return id; }
    final tSup = team(sup, 'Support'), tPnx = team(dev, 'ProfitNX'), tOrn = team(dev, 'Ornate'), tPbi = team(dev, 'PowerBI'), tSal = team(sal, 'Sales'), tHr = team(hr, 'HR');
    String user(String name, String phone, String? d, String? t, String role) {
      final id = b._id('U');
      b.users.add({'id': id, 'name': name, 'phone': phone, 'dept': d, 'team': t, 'role': role, 'reportsTo': null, 'shift': 0, 'away': false, 'muted': <String>[]});
      return id;
    }
    final supLead = user('Support Lead', '9800000001', sup, tSup, 'dept_head');
    final riya = user('Riya Shah', '9800000002', sup, tSup, 'staff');
    user('Karan Patel', '9800000003', sup, tSup, 'staff');
    final tushar = user('Tushar Parmar', '9800000004', dev, tOrn, 'dept_head');
    final dhaval = user('Dhaval Dalsania', '9800000005', dev, tPnx, 'team_lead');
    final vishwas = user('Vishwas', '9800000006', dev, tPbi, 'team_lead');
    final nisha = user('Nisha Patel', '9800000007', dev, tPbi, 'staff');
    final salesLead = user('Sales Lead', '9800000008', sal, tSal, 'dept_head');
    final priya = user('Priya Nair', '9800000009', sal, tSal, 'staff');
    final kunal = user('Kunal Mehta', '9800000011', dev, tPnx, 'staff');
    final amit = user('Amit Vora', '9800000012', dev, tOrn, 'staff');
    user('Pooja Desai', '9800000013', dev, tOrn, 'staff');
    final hrLead = user('HR Lead', '9800000014', hr, tHr, 'dept_head');
    user('HR Staff', '9800000015', hr, tHr, 'staff');
    b._user(dhaval)['reportsTo'] = tushar;
    b._user(vishwas)['reportsTo'] = dhaval;
    for (final (d, h) in [(sup, supLead), (dev, tushar), (sal, salesLead), (hr, hrLead)]) { b._dept(d)['head'] = h; }
    for (final (t, l) in [(tSup, supLead), (tPnx, dhaval), (tOrn, tushar), (tPbi, vishwas), (tSal, salesLead), (tHr, hrLead)]) { b._team(t)['lead'] = l; }

    // Tasks in every state, sent over the last few days.
    final n = b.now();
    String send(String from, Map<String, dynamic> target, String text, Duration ago, {Map<String, String> overrides = const {}}) {
      final th = b._open(b._user(from), target);
      th['last'] = n.subtract(ago).toIso8601String();
      return b._create(b._user(from), th, {'kind': 'text', 'bodyText': text, 'clientMsgId': 'seed-${b._seq}', 'overrides': overrides}, at: n.subtract(ago))['task']['id'] as String;
    }
    void as(String who, String task, String action, [Map<String, dynamic> body = const {}]) => b._run(b._user(who), b._task(task), action, body);
    final a = send(riya, {'targetType': 'user', 'targetId': dhaval}, 'Urgent - Profit NX login failing for all users at Mehta Traders, Surat. Call 98250 12345, licence PNX-2024-881.', const Duration(hours: 3));
    as(dhaval, a, 'accept');
    final b2 = send(riya, {'targetType': 'team', 'targetId': tPbi}, 'पटेल एग्रो फूड्स, राजकोट: Power BI डैशबोर्ड में मासिक टोटल गलत आ रहा है, कल बोर्ड मीटिंग है, जल्दी देखो।', const Duration(hours: 2));
    send(riya, {'targetType': 'department', 'targetId': dev}, 'Kaveri Steel na Ornate invoice ma GST number print nathi thato, jyare samay male tyare joi lejo.', const Duration(minutes: 40));
    as(nisha, b2, 'accept');
    as(nisha, b2, 'ask_requester', {'question': 'Which month is wrong - October or all of them?'});
    final c = send(priya, {'targetType': 'department', 'targetId': dev}, 'Sunrise Pharma wants the Ornate quotation PDF to show their GST number. Not urgent.', const Duration(days: 2));
    as(amit, c, 'accept');
    as(amit, c, 'complete', {'remarks': 'GST number added to the quotation template.'});
    final d = send(riya, {'targetType': 'department', 'targetId': dev}, 'Mobile app crashes on login for Om Logistics drivers. 99251 77889', const Duration(hours: 26));
    as(kunal, d, 'accept');
    as(kunal, d, 'block', {'reason': 'Waiting for the crash log from Om Logistics'});
    final e = send(priya, {'targetType': 'user', 'targetId': vishwas}, 'Server down at Kaveri Steel Ahmedabad, nobody can bill. Critical!', const Duration(hours: 5));
    as(priya, e, 'escalate', {'level': 'team_lead', 'reason': 'Customer has called three times'});
    final f = send(kunal, {'targetType': 'department', 'targetId': sup}, 'SQL installation needed on the new billing PC at Shree Ganesh Textiles, Surat.', const Duration(days: 4));
    as(riya, f, 'accept');
    as(riya, f, 'complete', {'remarks': 'SQL Server 2022 installed and backed up.'});
    as(kunal, f, 'verify');
    as(kunal, f, 'close', {'resolution': 'Installed and tested with the customer.', 'customerInformed': 'yes'});
    send(amit, {'targetType': 'department', 'targetId': hr}, 'Please update my bank account for salary credit from next month.', const Duration(hours: 1));
    send(riya, {'targetType': 'self'}, 'Call Shree Ganesh Textiles back on Monday about the renewal.', const Duration(minutes: 20));
    b.notes.clear();
    return b;
  }

  // ---------------------------------------------------------------- lookups
  Map<String, dynamic> _user(String? id) => users.firstWhere((u) => u['id'] == id, orElse: () => throw _Err(404, 'NOT_FOUND', 'Person not found.'));
  Map<String, dynamic> _dept(String? id) => depts.firstWhere((d) => d['id'] == id, orElse: () => throw _Err(404, 'NOT_FOUND', 'Department not found.'));
  Map<String, dynamic> _team(String? id) => teams.firstWhere((t) => t['id'] == id, orElse: () => throw _Err(404, 'NOT_FOUND', 'Team not found.'));
  Map<String, dynamic> _task(String? id) => tasks.firstWhere((t) => t['id'] == id, orElse: () => throw _Err(404, 'NOT_FOUND', 'Task not found.'));
  Map<String, dynamic> _thread(String? id) => threads.firstWhere((t) => t['id'] == id, orElse: () => throw _Err(404, 'NOT_FOUND', 'Chat not found.'));
  Map<String, dynamic> _msg(String id) => messages.firstWhere((m) => m['id'] == id);
  String? _name(String? id) => users.where((u) => u['id'] == id).firstOrNull?['name'] as String?;

  List<String> teamsLedBy(Map<String, dynamic> u) {
    if (u['role'] == 'dept_head') return [for (final t in teams) if (t['dept'] == u['dept']) t['id'] as String];
    if (u['role'] != 'team_lead') return [];
    final out = <String>{for (final t in teams) if (t['lead'] == u['id']) t['id'] as String};
    for (final t in teams) {
      final lead = users.where((x) => x['id'] == t['lead']).firstOrNull;
      if (lead != null && lead['reportsTo'] == u['id']) out.addAll(teamsLedBy(lead));
    }
    return out.toList();
  }

  List<String> leadChain(String userId) {
    final u = _user(userId), chain = <String>[];
    final teamLead = teams.where((t) => t['id'] == u['team']).firstOrNull?['lead'] as String?;
    String? next = teamLead != null && teamLead != userId ? teamLead : u['reportsTo'] as String?;
    while (next != null && !chain.contains(next)) { chain.add(next); next = _user(next)['reportsTo'] as String?; }
    final head = _dept(u['dept'])['head'] as String?;
    if (head != null && head != userId && !chain.contains(head)) chain.add(head);
    return chain;
  }

  String roleLabel(Map<String, dynamic> u) {
    final team = teams.where((t) => t['id'] == u['team']).firstOrNull?['name'];
    final dept = depts.where((d) => d['id'] == u['dept']).firstOrNull?['name'];
    return switch (u['role']) { 'admin' => 'Admin', 'dept_head' => '$dept head', 'team_lead' => '${team ?? dept} lead', _ => team != null ? '$team team' : '$dept' };
  }

  bool manages(Map<String, dynamic> me, String userId) {
    final u = _user(userId);
    if (me['role'] == 'dept_head') return me['dept'] == u['dept'];
    return u['team'] != null && teamsLedBy(me).contains(u['team']);
  }

  bool canSee(Map<String, dynamic> me, Map<String, dynamic> th) =>
      th['type'] == 'direct' ? th['a'] == me['id'] || th['b'] == me['id'] : th['type'] == 'self' ? th['requester'] == me['id'] : th['requester'] == me['id'] || th['dept'] == me['dept'];

  // ---------------------------------------------------------------- the "AI" reader (demo only)
  Map<String, dynamic> structure(String text, List<String> modules, Map<String, String> overrides) {
    final low = text.toLowerCase();
    var priority = RegExp(r'critical|server down|nobody can|down for all').hasMatch(low) ? 'Critical'
        : RegExp(r'urgent|asap|today|जल्दी|તાત્કાલિક|jaldi|all users').hasMatch(low) ? 'High'
        : RegExp(r'not urgent|whenever|no rush|next week|कोई जल्दी नहीं|જ્યારે સમય|jyare samay|koi jaldi nahi').hasMatch(low) ? 'Low' : 'Medium';
    String? module = modules.where((m) => m != 'Other' && low.replaceAll(' ', '').contains(m.toLowerCase().replaceAll(' ', ''))).firstOrNull;
    String? customer = customers.where((c) => low.contains(c.toLowerCase())).firstOrNull;
    customer ??= const {'पटेल एग्रो फूड्स': 'पटेल एग्रो फूड्स', 'मेहता ट्रेडर्स': 'मेहता ट्रेडर्स', 'કાવેરી સ્ટીલ': 'કાવેરી સ્ટીલ'}.entries.where((e) => text.contains(e.key)).firstOrNull?.value;
    final digits = RegExp(r'(?:\+?91[\s-]?)?(\d[\d\s-]{8,13}\d)').firstMatch(text)?.group(1)?.replaceAll(RegExp(r'\D'), '');
    final phone = digits != null && digits.length >= 10 ? digits.substring(digits.length - 10) : null;
    final licence = RegExp(r'\b[A-Z]{2,4}-\d[\d-]*\d\b').firstMatch(text)?.group(0);
    const cities = ['Surat', 'Rajkot', 'Ahmedabad', 'Vadodara', 'Pune', 'Mumbai', 'राजकोट', 'सूरत', 'સુરત', 'રાજકોટ'];
    final location = cities.where((c) => text.contains(c)).firstOrNull;
    if (overrides['priority'] != null) priority = overrides['priority']!;
    if (overrides['module'] != null) module = overrides['module'];
    if (overrides['customer'] != null) customer = overrides['customer'];
    final words = text.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(7).join(' ');
    final subject = '${module ?? 'Request'}: ${words.length > 48 ? words.substring(0, 48) : words}';
    return {'subject': subject.length > 60 ? subject.substring(0, 60) : subject, 'module': module ?? 'Other', 'customerName': customer, 'customerPhone': phone,
      'customerLocation': location, 'licenseNo': overrides['license'] ?? licence, 'priority': priority, 'details': text};
  }

  // ---------------------------------------------------------------- threads and messages
  Map<String, dynamic> _open(Map<String, dynamic> me, Map<String, dynamic> body) {
    final type = body['targetType'], target = body['targetId'] as String?;
    if (type == 'self') {
      return threads.where((t) => t['type'] == 'self' && t['requester'] == me['id']).firstOrNull
          ?? (threads..add({'id': _id('TH'), 'type': 'self', 'requester': me['id'], 'dept': null, 'team': null, 'last': null})).last;
    }
    if (type == 'user') {
      if (target == me['id']) throw _Err(400, 'BAD_REQUEST', 'You cannot start a chat with yourself.');
      _user(target);
      final pair = [me['id'] as String, target!]..sort();
      return threads.where((t) => t['type'] == 'direct' && t['a'] == pair[0] && t['b'] == pair[1]).firstOrNull
          ?? (threads..add({'id': _id('TH'), 'type': 'direct', 'a': pair[0], 'b': pair[1], 'last': null})).last;
    }
    final team = type == 'team' ? _team(target) : null;
    final deptId = team?['dept'] ?? _dept(target)['id'];
    return threads.where((t) => t['type'] == 'department' && t['requester'] == me['id'] && t['dept'] == deptId && t['team'] == team?['id']).firstOrNull
        ?? (threads..add({'id': _id('TH'), 'type': 'department', 'requester': me['id'], 'dept': deptId, 'team': team?['id'], 'last': null})).last;
  }

  Map<String, dynamic> _create(Map<String, dynamic> me, Map<String, dynamic> th, Map<String, dynamic> body, {DateTime? at}) {
    final when = at ?? now();
    final dup = messages.where((m) => m['sender'] == me['id'] && m['clientMsgId'] == body['clientMsgId']).firstOrNull;
    if (dup != null) return _item(dup, me['id'] as String);
    final text = (body['bodyText'] as String?)?.trim();
    if (body['kind'] == 'text' && (text == null || text.isEmpty)) throw _Err(400, 'BAD_REQUEST', 'Type a message.');
    if (body['kind'] == 'voice') throw _Err(400, 'BAD_REQUEST', 'Voice notes need the phone app (the browser demo has no microphone).');
    final m = {'id': _id('M'), 'thread': th['id'], 'sender': me['id'], 'clientMsgId': body['clientMsgId'] ?? _id('c'), 'kind': body['kind'] ?? 'text',
      'bodyText': text, 'replyTo': body['replyToTaskId'], 'at': when.toIso8601String()};
    messages.add(m);
    th['last'] = when.toIso8601String();
    if (body['replyToTaskId'] != null) {
      final t = _task(body['replyToTaskId'] as String);
      if (t['status'] == 'WaitingInfo' && _msg(t['message'] as String)['sender'] == me['id']) {
        _set(t, {'status': 'InProgress', 'clock': 'running', 'due': when.add(Duration(hours: _completeH[t['priority']]!)).toIso8601String()});
        _event(t, me['id'] as String, 'answered', {});
      }
      return _item(m, me['id'] as String);
    }
    final parent = body['parentTaskId'] == null ? null : _task(body['parentTaskId'] as String);
    if (parent != null) {
      if (parent['assignee'] != me['id'] || !['Accepted', 'InProgress'].contains(parent['status'])) throw _Err(403, 'FORBIDDEN', 'Only the person working on the task can hand off part of it.');
      if (th['type'] != 'department' || th['dept'] == parent['dept']) throw _Err(400, 'BAD_REQUEST', 'Choose another department.');
    }
    final note = th['type'] == 'self';
    final dept = note ? me['dept'] as String? : th['dept'] as String? ?? _user(th['a'] == me['id'] ? th['b'] : th['a'])['dept'] as String?;
    final overrides = Map<String, String>.from((body['overrides'] as Map?) ?? const {});
    final s = structure(text ?? '', List<String>.from(_dept(dept)['modules'] as List), overrides);
    final ticketNo = parent != null ? '${parent['ticketNo']}/T${tasks.where((x) => x['parent'] == parent['id']).length + 2}' : 'ORN-SS-2627-${(++_ticket).toString().padLeft(5, '0')}';
    final t = {'id': _id('TK'), 'message': m['id'], 'thread': th['id'], 'ticketNo': ticketNo, 'parent': parent?['id'], 'note': note,
      ...s, 'status': 'Open', 'assignee': null, 'tagged': body['taggedUserId'], 'dept': th['dept'], 'team': th['team'], 'aiStatus': 'done',
      'clock': 'not started', 'usedMs': 0, 'due': when.add(Duration(minutes: _acceptMin[s['priority']]!)).toIso8601String(), 'escalation': null,
      'escalatedTo': <String>[], 'reassignAsker': null, 'request': null, 'resolution': null, 'informed': null, 'closedAt': null, 'completedAt': null,
      'created': when.toIso8601String(), 'updated': when.toIso8601String()};
    if (note) t.addAll({'status': 'InProgress', 'assignee': me['id'], 'due': null, 'dept': null});
    tasks.add(t);
    _event(t, me['id'] as String, 'created', {}, at: when);
    if (parent != null) {
      _set(parent, {'status': 'WaitingDept', 'clock': 'paused'});
      _event(parent, me['id'] as String, 'handed_off', {'subject': text});
    }
    if (!note) {
      final to = th['type'] == 'direct' ? [th['a'] == me['id'] ? th['b'] : th['a']]
          : [for (final u in users) if (u['dept'] == th['dept'] && u['id'] != me['id'] && (th['team'] == null || u['team'] == th['team'] || teamsLedBy(u).contains(th['team']))) u['id']];
      _notify(to.cast<String>(), t, '${me['name']} · ${t['subject']}', at: when);
    }
    return _item(m, me['id'] as String);
  }

  void _set(Map<String, dynamic> t, Map<String, dynamic> f) { t.addAll(f); t['updated'] = now().toIso8601String(); }
  void _event(Map<String, dynamic> t, String? by, String type, Map<String, dynamic> payload, {DateTime? at}) =>
      events.add({'task': t['id'], 'by': by, 'type': type, 'payload': payload, 'at': (at ?? now()).toIso8601String()});

  Map<String, dynamic> _messageJson(Map<String, dynamic> m) => {'id': m['id'], 'threadId': m['thread'], 'senderId': m['sender'], 'clientMsgId': m['clientMsgId'],
    'kind': m['kind'], 'bodyText': m['bodyText'], 'attachments': [], 'replyToTaskId': m['replyTo'], 'createdAt': m['at']};

  Map<String, dynamic> _taskJson(Map<String, dynamic> t, String viewer) => {'id': t['id'], 'ticketNo': t['ticketNo'], 'messageId': t['message'], 'threadId': t['thread'],
    'subject': t['subject'], 'module': t['module'], 'customerName': t['customerName'], 'customerPhone': t['customerPhone'],
    'customerLocation': t['customerLocation'], 'licenseNo': t['licenseNo'], 'priority': t['priority'], 'details': t['details'], 'status': t['status'],
    'assigneeId': t['assignee'], 'taggedUserId': t['tagged'], 'departmentId': t['dept'], 'teamId': t['team'], 'aiStatus': t['aiStatus'], 'warnings': [],
    'dueAt': t['due'] == null || t['clock'] == 'paused' || _finished.contains(t['status']) || t['status'] == 'Completed' || t['status'] == 'Verified' ? null : t['due'],
    'clock': {'state': t['clock'], 'usedMs': t['usedMs']}, 'escalationLevel': t['escalation'], 'escalatedTo': t['escalatedTo'],
    'reassignRequestedBy': t['reassignAsker'], 'request': t['request'], 'parentTaskId': t['parent'], 'isNote': t['note'] == true, 'resolution': t['resolution'], 'customerInformed': t['informed'],
    'closedAt': t['closedAt'], 'createdAt': t['created'], 'updatedAt': t['updated'], 'actions': available(_user(viewer), t)};

  Map<String, dynamic> _item(Map<String, dynamic> m, String viewer) {
    final t = tasks.where((x) => x['message'] == m['id']).firstOrNull;
    return {'message': _messageJson(m), 'task': t == null ? null : _taskJson(t, viewer)};
  }

  // ---------------------------------------------------------------- workflow (mirrors server/src/workflow/engine.ts)
  List<String> available(Map<String, dynamic> me, Map<String, dynamic> t) {
    final th = _thread(t['thread'] as String), sender = _msg(t['message'] as String)['sender'];
    if (th['type'] == 'self') {
      if (sender != me['id']) return [];
      return t['status'] != 'Closed' ? ['close', 'edit'] : ['reopen'];
    }
    final requester = sender == me['id'], assignee = t['assignee'] == me['id'], staff = me['role'] == 'staff';
    final myTeams = teamsLedBy(me);
    final head = me['role'] == 'dept_head' && me['dept'] == t['dept'];
    final lead = !requester && (head || (t['assignee'] != null && manages(me, t['assignee'] as String)) || (t['team'] != null && myTeams.contains(t['team'])));
    final recipient = !requester && (th['type'] == 'direct' ? (th['a'] == me['id'] || th['b'] == me['id'])
        : me['dept'] == t['dept'] && (t['team'] == null || me['team'] == t['team'] || myTeams.contains(t['team'])));
    final s = t['status'] as String, out = <String>{};
    if (_finished.contains(s) && s != 'Closed') return [];
    if (lead && t['request'] != null) return ['approve_request', 'refuse_request'];
    if (lead && t['reassignAsker'] != null && _active.contains(s)) return ['reassign', 'keep'];
    if (s == 'Open') {
      if (recipient) out.add('accept');
      if (recipient && t['tagged'] == me['id']) out.add('decline');
      if (recipient && staff && t['request'] == null) out.addAll(['request_reject', 'request_transfer']);
      if (lead) out.addAll(['reassign', 'reject', 'transfer', 'change_priority']);
      if (requester) out.addAll(['cancel', 'change_priority', 'edit']);
    }
    if (_active.contains(s)) {
      if (assignee && s == 'WaitingDept') {
        out.add('change_priority');
      } else if (assignee) {
        if (s == 'Accepted' || s == 'InProgress') out.add('hand_off');
        if (s == 'Accepted') out.add('in_progress');
        out.addAll(['complete', 'change_priority']);
        if (s != 'WaitingInfo') out.add('ask_requester');
        out.add(s == 'Blocked' ? 'unblock' : 'block');
        if (staff) { if (t['reassignAsker'] == null) out.add('ask_reassign'); if (t['request'] == null) out.addAll(['request_reject', 'request_transfer']); }
        else { out.addAll(['reject', 'transfer']); }
      }
      if (lead) out.addAll(['reassign', 'reject', 'transfer', 'change_priority']);
      if (s == 'WaitingDept' && me['role'] == 'dept_head' && me['dept'] == t['dept']) out.add('complete_cancel_subs');
    }
    if (requester) {
      if (s == 'Completed') out.addAll(['verify', 'reopen']);
      if (s == 'Verified') out.addAll(['close', 'reopen']);
      if (s == 'Closed') out.add('reopen');
    }
    if (!_finished.contains(s) && s != 'Completed' && s != 'Verified') {
      if ((requester || assignee || recipient || lead) && t['escalation'] == null) out.add('escalate');
      if (t['escalation'] != null && (t['escalatedTo'] as List).contains(me['id'])) out.add('attend');
    }
    const all = ['accept', 'decline', 'in_progress', 'ask_reassign', 'keep', 'reassign', 'complete', 'verify', 'close', 'reopen', 'ask_requester', 'block',
      'unblock', 'request_reject', 'request_transfer', 'approve_request', 'refuse_request', 'reject', 'transfer', 'escalate', 'attend', 'change_priority', 'cancel',
      'edit', 'hand_off', 'complete_cancel_subs'];
    return all.where(out.contains).toList();
  }

  List<String> _escalationTargets(Map<String, dynamic> t, String want) {
    const levels = ['team_lead', 'dept_head', 'management'];
    final sender = _msg(t['message'] as String)['sender'];
    for (final level in levels.sublist(levels.indexOf(want))) {
      List<String> ids = [];
      if (level == 'team_lead') {
        final lead = t['assignee'] != null ? leadChain(t['assignee'] as String).where((id) => _user(id)['role'] == 'team_lead').firstOrNull
            : teams.where((x) => x['id'] == t['team']).firstOrNull?['lead'] as String?;
        ids = [?lead];
      } else if (level == 'dept_head') {
        ids = [?(_dept(t['dept'] ?? _user(sender)['dept'])['head'] as String?)];
      }
      ids = ids.where((x) => x != sender).toList();
      if (ids.isNotEmpty) return [level, ...ids];
    }
    return [want];
  }

  void _run(Map<String, dynamic> me, Map<String, dynamic> t, String a, Map<String, dynamic> body) {
    if (!available(me, t).contains(a)) throw _Err(403, 'FORBIDDEN', "You can't do that on this task now.");
    String need(String k) { final v = (body[k] as String?)?.trim() ?? ''; if (v.isEmpty) throw _Err(400, 'BAD_REQUEST', 'Add a short reason.'); return v; }
    final n = now();
    final sender = _msg(t['message'] as String)['sender'] as String;
    final note = _thread(t['thread'] as String)['type'] == 'self';
    switch (a) {
      case 'edit':
        final text = (body['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) throw _Err(400, 'BAD_REQUEST', 'Type the message.');
        _msg(t['message'] as String)['bodyText'] = text;
        if (!note) {
          final s = structure(text, List<String>.from(_dept(t['dept'] ?? _user(sender)['dept'])['modules'] as List), const {});
          _set(t, {for (final k in ['subject', 'module', 'customerName', 'customerPhone', 'customerLocation', 'licenseNo', 'priority', 'details']) k: s[k]});
        }
      case 'close' when note:
        _set(t, {'status': 'Closed', 'closedAt': n.toIso8601String()});
      case 'reopen' when note:
        _set(t, {'status': 'InProgress', 'closedAt': null});
      case 'hand_off':
        throw _Err(400, 'BAD_REQUEST', 'Type /subtask in the chat and pick a department.');
      case 'complete_cancel_subs':
        need('remarks');
        for (final s in tasks.where((x) => x['parent'] == t['id'] && !['Completed', 'Verified', ..._finished].contains(x['status']))) {
          _set(s, {'status': 'Cancelled', 'closedAt': n.toIso8601String()});
        }
        _set(t, {'status': 'Completed', 'clock': 'stopped', 'completedAt': n.toIso8601String()});
      case 'accept':
        _set(t, {'status': 'Accepted', 'assignee': me['id'], 'clock': 'running', 'due': n.add(Duration(hours: _completeH[t['priority']]!)).toIso8601String()});
      case 'decline':
        _set(t, {'tagged': null});
      case 'in_progress':
        _set(t, {'status': 'InProgress'});
      case 'ask_reassign':
        need('reason'); _set(t, {'reassignAsker': me['id']});
      case 'keep':
        _set(t, {'reassignAsker': null});
      case 'complete':
        need('remarks'); _set(t, {'status': 'Completed', 'clock': 'stopped', 'completedAt': n.toIso8601String()});
      case 'verify':
        _set(t, {'status': 'Verified'});
      case 'close':
        need('resolution');
        _set(t, {'status': 'Closed', 'closedAt': n.toIso8601String(), 'resolution': body['resolution'], 'informed': body['customerInformed']});
      case 'reopen':
        need('reason');
        _set(t, {'status': 'InProgress', 'clock': 'running', 'closedAt': null, 'resolution': null, 'informed': null, 'due': n.add(Duration(hours: _completeH[t['priority']]!)).toIso8601String()});
      case 'ask_requester':
        need('question'); _set(t, {'status': 'WaitingInfo', 'clock': 'paused'});
      case 'block':
        need('reason'); _set(t, {'status': 'Blocked', 'clock': 'paused'});
      case 'unblock':
        _set(t, {'status': 'InProgress', 'clock': 'running'});
      case 'request_reject' || 'request_transfer':
        need('reason'); _set(t, {'request': {'kind': a == 'request_reject' ? 'reject' : 'transfer', 'by': me['id'], 'reason': body['reason'], 'departmentId': body['departmentId']}});
      case 'refuse_request':
        _set(t, {'request': null});
      case 'approve_request':
        final r = Map<String, dynamic>.from(t['request'] as Map);
        _set(t, {'request': null});
        if (r['kind'] == 'reject') { _set(t, {'status': 'Rejected', 'closedAt': n.toIso8601String(), 'clock': 'stopped'}); }
        else { _transfer(me, t, r['departmentId'] as String, r['reason'] as String); }
      case 'reject':
        need('reason'); _set(t, {'status': 'Rejected', 'closedAt': n.toIso8601String(), 'clock': 'stopped'});
      case 'transfer':
        _transfer(me, t, body['departmentId'] as String, need('reason'));
      case 'escalate':
        need('reason');
        final target = _escalationTargets(t, (body['level'] as String?) ?? 'team_lead');
        if (target.length < 2) throw _Err(400, 'BAD_REQUEST', 'Nobody holds that level yet.');
        _set(t, {'escalation': target.first, 'escalatedTo': target.sublist(1)});
      case 'attend':
        _set(t, {'escalation': null, 'escalatedTo': <String>[]});
      case 'change_priority':
        need('reason');
        final p = body['priority'] as String;
        if (_order.indexOf(p) < _order.indexOf(t['priority'] as String) && me['role'] == 'staff') throw _Err(403, 'FORBIDDEN', 'Only a team lead or department head can lower the priority.');
        _set(t, {'priority': p});
      case 'cancel':
        _set(t, {'status': 'Cancelled', 'closedAt': n.toIso8601String()});
    }
    final type = const {'accept': 'accepted', 'complete': 'completed', 'reject': 'rejected', 'verify': 'verified', 'close': 'closed', 'reopen': 'reopened',
      'ask_requester': 'question', 'block': 'blocked', 'unblock': 'unblocked', 'escalate': 'escalated', 'attend': 'attended', 'cancel': 'cancelled',
      'change_priority': 'priority_changed', 'edit': 'edited', 'decline': 'declined', 'ask_reassign': 'reassign_asked', 'keep': 'reassign_refused',
      'request_reject': 'request', 'request_transfer': 'request', 'refuse_request': 'request_refused', 'transfer': 'transferred', 'in_progress': 'status_changed',
      'complete_cancel_subs': 'subs_cancelled'}[a] ?? a;
    _event(t, me['id'] as String, type, {...Map<String, dynamic>.from(body), if (a == 'in_progress') 'to': 'InProgress'});
    // A sub-task that ended moves its parent on (Ornate).
    if (t['parent'] != null && ['Completed', 'Rejected', 'Cancelled', 'Transferred'].contains(t['status'])) {
      final p = _task(t['parent'] as String);
      _event(p, me['id'] as String, 'subtask_done', {'subject': t['subject']});
      if (p['status'] == 'WaitingDept' && !tasks.any((x) => x['parent'] == p['id'] && !['Completed', 'Verified', ..._finished].contains(x['status']))) {
        _set(p, {'status': 'InProgress', 'clock': 'running'});
      }
    }
    if (!note) {
      final who = sender == me['id'] ? [?t['assignee'] as String?] : [sender];
      _notify(who.where((x) => x != me['id']).toList(), t, '${t['subject']} · ${doneWord(type)} by ${me['name']}');
    }
    if (sender == me['id']) return;
  }

  void _transfer(Map<String, dynamic> me, Map<String, dynamic> t, String deptId, String reason) {
    if (deptId == t['dept']) throw _Err(400, 'BAD_REQUEST', 'Choose a different department.');
    _set(t, {'status': 'Transferred', 'closedAt': now().toIso8601String(), 'clock': 'stopped'});
    final orig = _msg(t['message'] as String);
    final requester = _user(orig['sender'] as String);
    final th = _open(requester, {'targetType': 'department', 'targetId': deptId});
    _create(requester, th, {'kind': 'text', 'bodyText': orig['bodyText'], 'clientMsgId': _id('moved')});
  }

  String doneWord(String type) => type.replaceAll('_', ' ');
  void _notify(List<String> to, Map<String, dynamic> t, String text, {DateTime? at}) {
    for (final u in to.toSet()) {
      notes.add({'id': _id('N'), 'user': u, 'task': t['id'], 'text': text, 'read': false, 'at': (at ?? now()).toIso8601String()});
    }
  }

  // ---------------------------------------------------------------- Ornate lists (mirrors server/src/modules/cases/routes.ts)
  bool _note(Map<String, dynamic> t) => t['note'] == true;
  String _sender(Map<String, dynamic> t) => _msg(t['message'] as String)['sender'] as String;
  bool _recipient(Map<String, dynamic> me, Map<String, dynamic> t) {
    final th = _thread(t['thread'] as String);
    if (_sender(t) == me['id']) return false;
    if (th['type'] == 'direct') return th['a'] == me['id'] || th['b'] == me['id'];
    return th['type'] == 'department' && me['dept'] == t['dept'] && (t['team'] == null || me['team'] == t['team'] || teamsLedBy(me).contains(t['team']));
  }
  bool _leadFor(Map<String, dynamic> me, Map<String, dynamic> t) => (me['role'] == 'dept_head' && me['dept'] == t['dept'])
      || (t['assignee'] != null && manages(me, t['assignee'] as String)) || (t['team'] != null && teamsLedBy(me).contains(t['team']));
  bool _canView(Map<String, dynamic> me, Map<String, dynamic> t) {
    if (_note(t)) return _sender(t) == me['id'];
    if (_sender(t) == me['id'] || t['assignee'] == me['id'] || _leadFor(me, t)) return true;
    final th = _thread(t['thread'] as String);
    if (th['type'] == 'direct' && (th['a'] == me['id'] || th['b'] == me['id'])) return true;
    if (teamsLedBy(me).contains(_user(_sender(t))['team'])) return true;
    return t['status'] == 'Open' && _recipient(me, t);
  }
  bool _inMy(Map<String, dynamic> me, Map<String, dynamic> t) {
    final s = t['status'] as String;
    if (_note(t)) return _sender(t) == me['id'] && s != 'Closed';
    if (t['assignee'] == me['id'] && (_active.contains(s) || s == 'Completed')) return true;
    if (s == 'Open' && _recipient(me, t) && (t['tagged'] == me['id'] || _thread(t['thread'] as String)['type'] == 'direct')) return true;
    if (_leadFor(me, t) && !_finished.contains(s) && (t['request'] != null || t['reassignAsker'] != null || (t['escalatedTo'] as List).contains(me['id']))) return true;
    return _sender(t) == me['id'] && (s == 'Open' || _active.contains(s) || s == 'Completed' || s == 'Verified');
  }
  bool _inQueue(Map<String, dynamic> me, Map<String, dynamic> t) => !_note(t) && t['status'] == 'Open'
      && (_recipient(me, t) || (me['role'] == 'dept_head' && me['dept'] == t['dept']) || (t['team'] != null && teamsLedBy(me).contains(t['team']))) && !_inMy(me, t);
  Map<String, dynamic> _party(Map<String, dynamic> me, Map<String, dynamic> t) {
    if (_note(t)) return {'key': 'self', 'name': 'Private notes', 'sub': 'Only you'};
    String dn(Object? id) => depts.where((d) => d['id'] == id).firstOrNull?['name'] as String? ?? '';
    final s = _sender(t);
    if (s != me['id']) return {'key': 'u:$s', 'name': _name(s), 'sub': dn(_user(s)['dept'])};
    final th = _thread(t['thread'] as String);
    final who = t['assignee'] ?? t['tagged'] ?? (th['type'] == 'direct' ? (th['a'] == me['id'] ? th['b'] : th['a']) : null);
    if (who != null) return {'key': 'u:$who', 'name': _name(who as String), 'sub': dn(_user(who)['dept'])};
    if (t['team'] != null) return {'key': 't:${t['team']}', 'name': '${_team(t['team'])['name']} team', 'sub': dn(t['dept'])};
    return {'key': 'd:${t['dept']}', 'name': '${dn(t['dept'])} Team Leads', 'sub': dn(t['dept'])};
  }
  Map<String, dynamic> _row(Map<String, dynamic> me, Map<String, dynamic> t) {
    final replies = messages.where((m) => m['replyTo'] == t['id']).toList();
    final last = replies.isEmpty ? _msg(t['message'] as String) : replies.last;
    final by = last['sender'] == me['id'] ? 'You' : '${_name(last['sender'] as String)}'.split(' ').first;
    final ev = events.where((e) => e['task'] == t['id'] && !const ['created', 'structured'].contains(e['type'])).lastOrNull;
    final lastOut = ev != null && (ev['at'] as String).compareTo(last['at'] as String) > 0
        ? {'kind': 'event', 'type': ev['type'], 'payload': ev['payload'], 'text': '', 'at': ev['at']}
        : {'kind': 'message', 'text': '$by: ${last['bodyText'] ?? 'Voice message'}', 'mine': last['sender'] == me['id'], 'at': last['at']};
    return {..._item(_msg(t['message'] as String), me['id'] as String), 'party': _party(me, t), 'overdue': !_note(t) && _overdue(t), 'requesterId': _sender(t),
      'last': lastOut};
  }
  Map<String, dynamic> _cases(Map<String, dynamic> me, Map<String, String> q) {
    final tab = q['tab'] ?? 'my', chip = q['chip'] ?? 'All', words = (q['q'] ?? '').toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    const done = ['Verified', 'Closed', 'Rejected', 'Cancelled'];
    final all = tasks.where((t) => _canView(me, t)).toList();
    final finished = chip == 'Verified / Closed';
    final source = finished
        ? (tab == 'my' ? all.where((t) => done.contains(t['status']) && (t['assignee'] == me['id'] || _sender(t) == me['id'])) : all)
        : all.where((t) => tab == 'my' ? _inMy(me, t) : tab == 'queue' ? _inQueue(me, t) : true);
    final list = source.where((t) {
      final s = t['status'] as String;
      final ok = chip == 'All' || finished ? (!finished || done.contains(s))
          : chip == 'Active' ? s == 'Open' || _active.contains(s)
          : chip == 'To Verify' ? s == 'Completed' && _sender(t) == me['id']
          : chip == 'Sent by me' ? _sender(t) == me['id']
          : (!_note(t) && _overdue(t)) || t['escalation'] != null;
      if (!ok) return false;
      if (q['dept'] != null && t['dept'] != q['dept'] && _user(_sender(t))['dept'] != q['dept']) return false;
      if (q['status'] != null && s != q['status']) return false;
      if (q['priority'] != null && t['priority'] != q['priority']) return false;
      if (q['requester'] != null && _sender(t) != q['requester']) return false;
      if (q['owner'] != null && t['assignee'] != q['owner']) return false;
      if (q['type'] != null && (q['type'] == 'Self') != _note(t)) return false;
      if (q['openOnly'] == 'true' && const ['Closed', 'Rejected', 'Cancelled', 'Transferred'].contains(s)) return false;
      final hay = '${t['ticketNo']} ${t['subject']} ${t['details']} ${t['customerName']} ${_name(_sender(t))} ${_name(t['assignee'] as String?)}'.toLowerCase();
      return words.every(hay.contains);
    }).map((t) => _row(me, t)).toList()..sort((a, b) => ('${(b['last'] as Map)['at']}').compareTo('${(a['last'] as Map)['at']}'));
    final lead = me['role'] != 'staff' && tab == 'queue';
    final mine = tasks.where((t) => t['dept'] == me['dept'] && !_note(t));
    return {'items': list, 'grouped': !finished && words.isEmpty,
      'stats': lead ? {'waiting': mine.where((t) => t['status'] == 'Open').length, 'inProgress': mine.where((t) => _active.contains(t['status'])).length,
        'overdue': mine.where(_overdue).length} : null};
  }

  // ---------------------------------------------------------------- HTTP surface
  (int, Object?) handle(String method, String path, Map<String, String> query, Map<String, dynamic> body, String? meId) {
    try {
      if (method == 'POST' && path == '/auth/login') {
        final phone = '${body['phone']}'.replaceAll(RegExp(r'\D'), '');
        final u = users.where((x) => x['phone'] == (phone.length > 10 ? phone.substring(phone.length - 10) : phone)).firstOrNull;
        if (u == null) throw _Err(401, 'UNAUTHORIZED', 'Wrong number or password.');
        return (200, {'accessToken': 'demo:${u['id']}', 'refreshToken': 'demo:${u['id']}', 'user': _public(u)});
      }
      if (path == '/demo/people') return (200, {'people': [for (final u in users) {'phone': u['phone'], 'name': u['name'], 'roleLabel': roleLabel(u)}]});
      if (meId == null || users.every((u) => u['id'] != meId)) throw _Err(401, 'UNAUTHORIZED', 'Sign in again.');
      final me = _user(meId);
      return (200, _route(method, path, query, body, me));
    } on _Err catch (e) {
      return (e.status, {'error': {'code': e.code, 'message': e.message}});
    }
  }

  Map<String, dynamic> _public(Map<String, dynamic> u) => {'id': u['id'], 'name': u['name'], 'role': u['role'], 'departmentId': u['dept']};

  Object? _route(String method, String path, Map<String, String> q, Map<String, dynamic> body, Map<String, dynamic> me) {
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    final id = me['id'] as String;
    switch ((method, seg)) {
      case ('GET', ['me']):
        final mgr = leadChain(id).firstOrNull;
        return {..._public(me), 'roleLabel': roleLabel(me), 'teamName': teams.where((t) => t['id'] == me['team']).firstOrNull?['name'],
          'departmentName': depts.where((d) => d['id'] == me['dept']).firstOrNull?['name'], 'reportingManager': _name(mgr), 'leadsTeams': teamsLedBy(me),
          'away': me['away'], 'shift': me['shift']};
      case ('GET', ['threads']):
        return {'threads': [for (final th in _myThreads(me)) _threadJson(th, me)]};
      case ('POST', ['threads', 'open']):
        return {'thread': _threadJson(_open(me, body), me)};
      case ('GET', ['search']):
        final s = (q['q'] ?? '').toLowerCase();
        return {'results': [
          for (final d in depts) if (d['name'].toString().toLowerCase().contains(s)) {'type': 'department', 'id': d['id'], 'name': d['name'], 'subtitle': 'Department'},
          for (final t in teams) if (s.isNotEmpty && t['name'].toString().toLowerCase().contains(s) && t['name'] != _dept(t['dept'])['name'])
            {'type': 'team', 'id': t['id'], 'name': '${t['name']} team', 'subtitle': _dept(t['dept'])['name']},
          for (final u in users) if (u['id'] != id && u['name'].toString().toLowerCase().contains(s)) {'type': 'user', 'id': u['id'], 'name': u['name'], 'subtitle': _dept(u['dept'])['name']},
        ].take(20).toList()};
      case ('GET', ['threads', final tid, 'messages']):
        final th = _thread(tid);
        if (!canSee(me, th)) throw _Err(403, 'FORBIDDEN', 'You do not have access to this.');
        final ms = messages.where((m) => m['thread'] == tid).toList()..sort((a, b) => (a['at'] as String).compareTo(b['at'] as String));
        return {'items': [for (final m in ms) _item(m, id)], 'nextCursor': null};
      case ('POST', ['threads', final tid, 'messages']):
        final th = _thread(tid);
        if (!canSee(me, th)) throw _Err(403, 'FORBIDDEN', 'You do not have access to this.');
        return _create(me, th, body);
      case ('GET', ['tasks', 'counts']):
        final mine = tasks.where((t) => _pending(me, t)).toList();
        return {'myPending': mine.length, 'overdue': mine.where(_overdue).length,
          'sentByMe': tasks.where((t) => _msg(t['message'] as String)['sender'] == id && !['Closed', 'Rejected', 'Transferred', 'Cancelled', 'Verified'].contains(t['status'])).length};
      case ('GET', ['tasks', 'search']):
        final s = (q['q'] ?? '').toLowerCase();
        final hits = tasks.where((t) => canSee(me, _thread(t['thread'] as String)) && '${t['ticketNo']} ${t['subject']} ${t['customerName']} ${t['details']}'.toLowerCase().contains(s));
        return {'items': [for (final t in hits) _item(_msg(t['message'] as String), id)]};
      case ('GET', ['tasks']):
        final f = q['filter'];
        final list = tasks.where((t) => f == 'sent_by_me'
            ? _msg(t['message'] as String)['sender'] == id && !['Closed', 'Rejected', 'Transferred', 'Cancelled', 'Verified'].contains(t['status'])
            : f == 'overdue' ? _pending(me, t) && _overdue(t) : f == 'closed' ? t['status'] == 'Closed' : _pending(me, t)).toList();
        return {'items': [for (final t in list) _item(_msg(t['message'] as String), id)], 'nextCursor': null};
      case ('GET', ['tasks', final tid, 'history']):
        final t = _task(tid);
        final p = t['parent'] == null ? null : _task(t['parent'] as String);
        return {'events': [for (final e in events.where((e) => e['task'] == tid)) {'type': e['type'], 'by': _name(e['by'] as String?) ?? 'System', 'at': e['at'], 'payload': e['payload']}],
          'files': [], 'ticketNo': t['ticketNo'],
          'replies': [for (final m in messages.where((m) => m['replyTo'] == tid)) _item(m, id)],
          'subTasks': [for (final s in tasks.where((x) => x['parent'] == tid)) {'id': s['id'], 'ticketNo': s['ticketNo'], 'subject': s['subject'], 'status': s['status'], 'threadId': s['thread'], 'department': _dept(s['dept'])['name']}],
          'parent': p == null ? null : {'id': p['id'], 'ticketNo': p['ticketNo'], 'subject': p['subject'], 'status': p['status'], 'threadId': p['thread']}};
      case ('GET', ['cases']):
        return _cases(me, q);
      case ('GET', ['cases', 'counts']):
        final all = tasks.where((t) => _canView(me, t)).toList();
        return {'my': all.where((t) => _inMy(me, t)).length, 'queue': all.where((t) => _inQueue(me, t)).length, 'all': all.length};
      case ('GET', ['cases', final tid]):
        final t = _task(tid);
        if (!_canView(me, t) && !canSee(me, _thread(t['thread'] as String))) throw _Err(403, 'FORBIDDEN', 'You do not have access to this.');
        return _row(me, t);
      case ('GET', ['timeline']):
        final key = q['party'] ?? '';
        final tab = q['tab'];
        bool inTab(Map<String, dynamic> t) => tab == null || const ['Closed', 'Rejected', 'Cancelled', 'Transferred'].contains(t['status'])
            || (tab == 'my' ? _inMy(me, t) : tab == 'queue' ? _inQueue(me, t) : true);
        final mine = tasks.where((t) => _canView(me, t) && _party(me, t)['key'] == key && inTab(t)).toList();
        final ids = mine.map((t) => t['id']).toSet();
        final ms = [...mine.map((t) => _msg(t['message'] as String)), ...messages.where((m) => ids.contains(m['replyTo']))]
          ..sort((a, b) => (a['at'] as String).compareTo(b['at'] as String));
        return {'party': mine.isEmpty ? null : _party(me, mine.first), 'items': [for (final m in ms) _item(m, id)]};
      case ('GET', ['notifications']):
        final mineN = notes.where((n) => n['user'] == id).toList().reversed.toList();
        return {'unread': mineN.where((n) => n['read'] != true).length, 'items': [for (final n in mineN) {'id': n['id'], 'taskId': n['task'],
          'threadId': _task(n['task'] as String)['thread'], 'ticketNo': _task(n['task'] as String)['ticketNo'], 'subject': _task(n['task'] as String)['subject'],
          'text': n['text'], 'read': n['read'] == true, 'at': n['at']}]};
      case ('POST', ['notifications', 'read-all']):
        for (final n in notes.where((n) => n['user'] == id)) { n['read'] = true; }
        return {'ok': true};
      case ('POST', ['notifications', final nid, 'read']):
        notes.firstWhere((n) => n['id'] == nid && n['user'] == id, orElse: () => throw _Err(404, 'NOT_FOUND', 'Not found.'))['read'] = true;
        return {'ok': true};
      case ('GET', ['tasks', final tid]):
        return _item(_msg(_task(tid)['message'] as String), id);
      case ('POST', ['tasks', final tid, 'actions', final a]):
        final t = _task(tid);
        _run(me, t, a, body);
        return {'task': _taskJson(t, id)};
      case ('POST', ['tasks', final tid, 'accept']):
        final t = _task(tid); _run(me, t, 'accept', body); return {'task': _taskJson(t, id)};
      case ('POST', ['tasks', final tid, 'cancel']):
        final t = _task(tid); _run(me, t, 'cancel', body); return {'task': _taskJson(t, id)};
      case ('POST', ['tasks', final tid, 'reassign']):
        final t = _task(tid);
        final target = _user(body['assigneeId'] as String);
        final head = me['role'] == 'dept_head' && me['dept'] == t['dept'];
        if (!head && t['assignee'] != id && !(t['assignee'] != null && manages(me, t['assignee'] as String))) throw _Err(403, 'FORBIDDEN', 'Only the assignee, their team lead or the department head can reassign.');
        if (target['dept'] != t['dept']) throw _Err(400, 'BAD_REQUEST', 'Choose someone in the same department.');
        _set(t, {'assignee': target['id'], 'status': t['status'] == 'Open' ? 'Accepted' : t['status'], 'reassignAsker': null, 'clock': 'running'});
        _event(t, id, 'reassigned', {'to': target['name']});
        return {'task': _taskJson(t, id)};
      case ('GET', ['departments']):
        return {'departments': [for (final d in depts) {'id': d['id'], 'name': d['name']}]};
      case ('GET', ['departments', final did]):
        final d = _dept(did);
        return {'id': d['id'], 'name': d['name'], 'headUserId': d['head'], 'modules': d['modules'],
          'teams': [for (final t in teams) if (t['dept'] == did) {'id': t['id'], 'name': t['name'], 'leadId': t['lead']}],
          'members': [for (final u in users) if (u['dept'] == did) {'id': u['id'], 'name': u['name'], 'role': u['role'], 'roleLabel': roleLabel(u),
            'teamId': u['team'], 'active': _activeCount(u['id'] as String), 'full': _activeCount(u['id'] as String) >= 5, 'away': u['away']}]};
      case ('GET', ['customers']):
        return {'customers': [for (final c in customers) {'id': c, 'name': c}]};
      case ('PUT', ['me', 'away']):
        me['away'] = body['away'] == true; return {'away': me['away']};
      case ('PUT', ['me', 'shift']):
        me['shift'] = body['shift']; return {'shift': me['shift']};
      case ('GET', ['me', 'notifications']):
        return {'kinds': [
          {'id': 'new', 'label': 'New task for you or your team', 'required': true}, {'id': 'accept', 'label': 'Accepted, reassigned, rejected', 'required': true},
          {'id': 'question', 'label': 'Questions and answers', 'required': true}, {'id': 'escalation', 'label': 'Escalations'},
          {'id': 'deadline', 'label': 'Due soon and overdue'}, {'id': 'update', 'label': 'Other updates'},
        ], 'muted': me['muted']};
      case ('PUT', ['me', 'notifications']):
        me['muted'] = List<String>.from(body['muted'] as List); return {'muted': me['muted']};
      case ('GET', ['holidays']):
        return {'holidays': holidays};
      case ('POST', ['holidays']):
        holidays.add({'day': body['day'], 'name': body['name']}); return {'day': body['day']};
      case ('DELETE', ['holidays', final day]):
        holidays.removeWhere((h) => h['day'] == day); return {};
      case ('GET', ['suggestions']):
        final review = me['role'] == 'dept_head' || me['role'] == 'admin';
        return {'canReview': review, 'suggestions': [for (final s in suggestions.reversed) if (review || s['by'] == id) {...s, 'byName': _name(s['by'] as String)}]};
      case ('POST', ['suggestions']):
        suggestions.add({'id': _id('S'), 'by': id, 'text': body['text'], 'status': 'New'}); return {'status': 'New'};
      case ('PUT', ['suggestions', final sid]):
        suggestions.firstWhere((s) => s['id'] == sid)['status'] = body['status']; return {'status': body['status']};
      case ('GET', ['analytics', 'team']):
        return _analytics(me);
      case ('POST', ['devices']) || ('POST', ['auth', 'password']):
        return {};
      case ('POST', ['uploads', 'presign']):
        throw _Err(400, 'BAD_REQUEST', 'Attachments need the phone app (files are not stored in the browser demo).');
    }
    throw _Err(404, 'NOT_FOUND', 'Not found.');
  }

  int _activeCount(String userId) => tasks.where((t) => t['assignee'] == userId && _active.contains(t['status'])).length;
  bool _overdue(Map<String, dynamic> t) => !['Completed', 'Verified', ..._finished].contains(t['status']) && t['clock'] != 'paused' && DateTime.parse(t['due'] as String).isBefore(now());
  bool _pending(Map<String, dynamic> me, Map<String, dynamic> t) {
    if (!['Open', ..._active].contains(t['status']) || _msg(t['message'] as String)['sender'] == me['id']) return false;
    if (t['assignee'] == me['id']) return true;
    if (t['assignee'] != null) return false;
    final th = _thread(t['thread'] as String);
    if (th['type'] == 'direct') return th['a'] == me['id'] || th['b'] == me['id'];
    return t['dept'] == me['dept'] && (t['team'] == null || t['team'] == me['team'] || teamsLedBy(me).contains(t['team']));
  }

  Iterable<Map<String, dynamic>> _myThreads(Map<String, dynamic> me) => threads
      .where((t) => t['a'] == me['id'] || t['b'] == me['id'] || t['requester'] == me['id'] || (t['type'] == 'department' && t['dept'] == me['dept']))
      .toList()..sort((a, b) => ('${b['last']}').compareTo('${a['last']}'));

  Map<String, dynamic> _threadJson(Map<String, dynamic> th, Map<String, dynamic> me) {
    String title, sub;
    if (th['type'] == 'self') {
      title = 'Private notes'; sub = 'Only you';
    } else if (th['type'] == 'direct') {
      final o = _user(th['a'] == me['id'] ? th['b'] : th['a']);
      title = o['name'] as String; sub = _dept(o['dept'])['name'] as String;
    } else if (th['requester'] == me['id']) {
      title = th['team'] != null ? '${_team(th['team'])['name']} team' : _dept(th['dept'])['name'] as String;
      sub = th['team'] != null ? _dept(th['dept'])['name'] as String : 'Department';
    } else {
      title = _name(th['requester'] as String)!;
      sub = 'To ${th['team'] != null ? '${_team(th['team'])['name']} team' : _dept(th['dept'])['name']}';
    }
    final ms = messages.where((m) => m['thread'] == th['id']).toList();
    final last = ms.isEmpty ? null : (ms..sort((a, b) => (a['at'] as String).compareTo(b['at'] as String))).last;
    return {'id': th['id'], 'type': th['type'], 'title': title, 'subtitle': sub, 'departmentId': th['dept'], 'teamId': th['team'], 'requesterId': th['requester'],
      'lastMessage': last == null ? null : {'senderId': last['sender'], 'kind': last['kind'], 'text': last['bodyText'], 'at': last['at']},
      'lastMessageAt': th['last'], 'openTasks': tasks.where((t) => t['thread'] == th['id'] && ['Open', ..._active].contains(t['status'])).length};
  }

  Map<String, dynamic> _analytics(Map<String, dynamic> me) {
    final led = teamsLedBy(me);
    if (led.isEmpty) throw _Err(403, 'FORBIDDEN', 'The Team screen is for team leads and department heads.');
    final head = me['role'] == 'dept_head';
    final mine = tasks.where((t) => t['dept'] == me['dept'] && (head || led.contains(t['team']) || (t['assignee'] != null && led.contains(_user(t['assignee'] as String)['team'])))).toList();
    final done = mine.where((t) => ['Completed', 'Verified', 'Closed'].contains(t['status'])).toList();
    Map<String, dynamic> card(Map<String, dynamic> t) => {'id': t['id'], 'threadId': t['thread'], 'ticketNo': t['ticketNo'], 'subject': t['subject'],
      'status': t['status'], 'priority': t['priority'], 'assignee': _name(t['assignee'] as String?)};
    final open = mine.where((t) => ['Open', ..._active].contains(t['status'])).toList();
    final people = users.where((u) => u['dept'] == me['dept'] && led.contains(u['team'])).toList();
    int count(String type) => events.where((e) => e['type'] == type && mine.any((t) => t['id'] == e['task'])).length;
    return {
      'scope': head ? '${_dept(me['dept'])['name']} department' : led.map((x) => '${_team(x)['name']} team').join(' + '),
      'kpis': {'completed': done.length, 'onTime': done.isEmpty ? null : 1.0, 'overdueNow': open.where(_overdue).length, 'reopened': count('reopen')},
      'attention': {
        'dueSoon': [for (final t in open) if (!_overdue(t) && t['clock'] != 'paused' && DateTime.parse(t['due'] as String).difference(now()).inHours < 2) card(t)],
        'waiting': [for (final t in open) if (t['status'] == 'WaitingInfo' || t['status'] == 'Blocked') {...card(t), 'stuckMs': now().difference(DateTime.parse(t['updated'] as String)).inMilliseconds}],
        'queues': [for (final x in (head ? [for (final t in teams) if (t['dept'] == me['dept']) t['id']] : led))
          if (open.any((t) => t['status'] == 'Open' && (t['team'] == x || (t['team'] == null && head))))
            {'team': _team(x)['name'], 'count': open.where((t) => t['status'] == 'Open' && t['team'] == x).length, 'oldestMs': 0}],
      },
      'thisMonth': {'done': done.length, 'onTime': done.isEmpty ? null : 1.0, 'avgMs': null},
      'lastMonth': {'done': 0, 'onTime': null, 'avgMs': null},
      'byPriority': [for (final p in const ['Critical', 'High', 'Medium', 'Low']) {'priority': p, 'done': done.where((t) => t['priority'] == p).length,
        'onTime': done.any((t) => t['priority'] == p) ? 1.0 : null}],
      'moved': {'reassigned': count('reassigned'), 'declined': count('decline'), 'reopened': count('reopen'), 'transferred': count('transfer'),
        'escalations': [if (count('escalate') > 0) {'level': 'team_lead', 'count': count('escalate')}],
        'stillEscalated': open.where((t) => t['escalation'] != null).length, 'attendedBy': []},
      'people': [for (final u in people) {'id': u['id'], 'name': u['name'], 'roleLabel': roleLabel(u), 'active': _activeCount(u['id'] as String),
        'full': _activeCount(u['id'] as String) >= 5, 'away': u['away'], 'shift': u['shift'], 'done': done.where((t) => t['assignee'] == u['id']).length,
        'onTime': done.any((t) => t['assignee'] == u['id']) ? 1.0 : null, 'avgMs': null, 'movedOff': 0}],
      'teams': head ? [for (final x in teams.where((t) => t['dept'] == me['dept'])) {'team': x['name'],
        'open': open.where((t) => t['team'] == x['id'] || (t['assignee'] != null && _user(t['assignee'] as String)['team'] == x['id'])).length,
        'overdue': open.where((t) => _overdue(t) && (t['team'] == x['id'] || (t['assignee'] != null && _user(t['assignee'] as String)['team'] == x['id']))).length,
        'done': done.where((t) => t['assignee'] != null && _user(t['assignee'] as String)['team'] == x['id']).length, 'onTime': null}] : [],
      'sources': [for (final s in {for (final t in mine) _msg(t['message'] as String)['sender'] as String})
        {'name': _name(s), 'department': _dept(_user(s)['dept'])['name'], 'count': mine.where((t) => _msg(t['message'] as String)['sender'] == s).length, 'sentBack': 0}],
      'customers': [for (final c in {for (final t in mine) if (t['customerName'] != null) t['customerName'] as String})
        {'name': c, 'total': mine.where((t) => t['customerName'] == c).length, 'open': open.where((t) => t['customerName'] == c).length,
          'overdue': open.where((t) => t['customerName'] == c && _overdue(t)).length}],
      'repeats': [],
      'oldest': [for (final t in (open..sort((a, b) => (a['created'] as String).compareTo(b['created'] as String))).take(5))
        {...card(t), 'ageMs': now().difference(DateTime.parse(t['created'] as String)).inMilliseconds}],
    };
  }
}

/// Random enough ids for client message ids in demo seeding.
String demoUuid() => List.generate(32, (_) => Random().nextInt(16).toRadixString(16)).join();
