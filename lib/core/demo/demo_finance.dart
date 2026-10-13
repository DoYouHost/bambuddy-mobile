import 'package:app_util/app_util.dart';

import '../app_context.dart';

/// The demo's billing: three users, their cost centers and one shared ledger, kept
/// as state so what an administrator changes is what the next listing shows.
///
/// It answers with the server's own sentences and status codes
/// (`backend/app/api/routes/finance.py`, `services/finance_budget.py`), since the
/// app words some of the refusals itself.
class DemoFinance {
  /// The signed-in user. The other two exist for an administrator to pick.
  static const userId = 1;

  static final users = <Map<String, dynamic>>[
    {'id': 1, 'username': DemoConfig.username},
    {'id': 2, 'username': 'anna'},
    {'id': 3, 'username': 'leo'},
  ];

  /// Stored as the server stores them: one budget figure of one kind, and the
  /// spend already counted against it. Everything a response carries is derived
  /// in [_summary].
  final List<Map<String, dynamic>> _centers = [
    _center(1, DemoConfig.username, private: true, owner: 1),
    _center(2, 'Workshop', kind: 'monthly', limit: 100),
    // Nearly spent, so a job is refused for what it costs.
    _center(3, 'Maker club', kind: 'total', limit: 5, used: 4.6),
    _center(4, 'Classroom', kind: 'total', limit: 40, used: 12),
    _center(5, 'anna', private: true, owner: 2),
    _center(6, 'leo', private: true, owner: 3),
    _center(7, 'Old lab', active: false),
  ];

  /// `center id -> [{user_id, can_print}]`. The signed-in user may see
  /// Classroom without printing there.
  final Map<int, List<Map<String, dynamic>>> _members = {
    2: [
      {'user_id': 1, 'can_print': true},
      {'user_id': 2, 'can_print': true},
    ],
    3: [
      {'user_id': 1, 'can_print': true},
    ],
    4: [
      {'user_id': 1, 'can_print': false},
      {'user_id': 3, 'can_print': true},
    ],
  };

  int _nextCenterId = 20;
  int _nextTransactionId = 1;

  /// Newest first, as the server lists them. Sixty rows for the signed-in user,
  /// so a second page exists; a few for the others.
  late final List<Map<String, dynamic>> _ledger = _seed();

  static Map<String, dynamic> _center(
    int id,
    String name, {
    bool private = false,
    int? owner,
    bool active = true,
    String kind = 'none',
    double? limit,
    double used = 0,
  }) => {
    'id': id,
    'name': name,
    'is_private': private,
    'owner_user_id': owner,
    'is_active': active,
    'kind': kind,
    'limit': limit,
    'used': used,
  };

  List<Map<String, dynamic>> _seed() {
    const names = ['Bag dispenser', 'Hue dial', 'Gridfinity bin', 'Lamp shade'];
    final rows = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (var n = 0; n < 60; n++) {
      final deposit = n % 15 == 0;
      final partial = !deposit && n % 11 == 5;
      rows.add(
        _row(
          user: 1,
          center: deposit ? null : (n % 3 == 0 ? 2 : 1),
          type: deposit ? 'deposit' : 'print_charge',
          amount: deposit ? 50.0 : -_r1(1.2 + (n % 7) * 0.8),
          description: deposit
              ? 'Top-up'
              : '${names[n % names.length]}'
                    '${partial ? ' [aborted: bed adhesion]' : ''}',
          at: now.subtract(Duration(days: 60 - n)),
        ),
      );
    }
    for (var n = 0; n < 14; n++) {
      rows.add(
        _row(
          user: 2,
          center: n % 2 == 0 ? 2 : 5,
          type: 'print_charge',
          amount: -_r1(2 + (n % 5) * 1.1),
          description: names[(n + 1) % names.length],
          at: now.subtract(Duration(days: 30 - n * 2, hours: 3)),
        ),
      );
    }
    for (var n = 0; n < 6; n++) {
      rows.add(
        _row(
          user: 3,
          center: n.isEven ? 4 : 6,
          type: 'print_charge',
          amount: -_r1(1.5 + n),
          description: names[(n + 2) % names.length],
          at: now.subtract(Duration(days: 20 - n * 3, hours: 5)),
        ),
      );
    }
    rows.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at']));
    return _rebuild(rows);
  }

  Map<String, dynamic> _row({
    required int user,
    required int? center,
    required String type,
    required double amount,
    required String? description,
    required DateTime at,
  }) => {
    'id': _nextTransactionId++,
    'user_id': user,
    'cost_center_id': center,
    'transaction_type': type,
    'amount': amount,
    'balance_after': 0.0,
    'description': description,
    'created_by_user_id': null,
    'print_run_id': null,
    'print_archive_id': null,
    'print_queue_id': null,
    'created_at': at.toUtc().toIso8601String(),
  };

  /// Every row's `balance_after`, as the server's `repair_wallet_ledger_internal`
  /// works it out: a row on no center, or on the user's own private one, moves that
  /// user's personal wallet; a row on a shared center moves the center's running
  /// balance, whoever it belongs to.
  List<Map<String, dynamic>> _rebuild(List<Map<String, dynamic>> rows) {
    final personal = <int, double>{};
    final shared = <int, double>{};
    for (final row in rows.reversed) {
      final user = row['user_id'] as int;
      final center = _find(row['cost_center_id']);
      final amount = (row['amount'] as num).toDouble();
      final isPersonal =
          center == null ||
          (center['is_private'] == true && center['owner_user_id'] == user);
      final balance = isPersonal
          ? personal[user] = (personal[user] ?? 0) + amount
          : shared[center['id'] as int] =
                (shared[center['id'] as int] ?? 0) + amount;
      row['balance_after'] = _r1(balance);
    }
    return rows;
  }

  bool _isPersonal(Map<String, dynamic> row) {
    final center = _find(row['cost_center_id']);
    return center == null ||
        (center['is_private'] == true &&
            center['owner_user_id'] == row['user_id']);
  }

  static double _r1(double v) => (v * 10).roundToDouble() / 10;

  /// The signed-in user's personal wallet: where their newest personal row left it.
  double get balance => personalBalance(userId);

  double personalBalance(int user) {
    final row = _ledger
        .where((r) => r['user_id'] == user && _isPersonal(r))
        .firstOrNull;
    return row == null ? 0 : (row['balance_after'] as num).toDouble();
  }

  // --- What the app reads ---

  Map<String, dynamic> _summary(
    Map<String, dynamic> c, {
    bool canPrint = true,
  }) {
    final kind = c['kind'] as String;
    final limit = (c['limit'] as num?)?.toDouble();
    final onCenter = _ledger.where((r) => r['cost_center_id'] == c['id']);
    final spent = onCenter.fold<double>(
      0,
      (sum, r) => sum + (r['amount'] as num).toDouble(),
    );
    // The budget counts what the center's rows charged, plus the history the demo
    // keeps no rows for (`used` in the fixture).
    final used =
        (c['used'] as num).toDouble() +
        onCenter.fold<double>(0, (sum, r) {
          final amount = (r['amount'] as num).toDouble();
          return amount < 0 ? sum - amount : sum;
        });
    return {
      'id': c['id'],
      'name': c['name'],
      'is_private': c['is_private'],
      'owner_user_id': c['owner_user_id'],
      'is_active': c['is_active'],
      'total_balance': _r1(spent),
      'total_budget': kind == 'total' ? limit : null,
      'monthly_budget': kind == 'monthly' ? limit : null,
      'budget_mode': kind,
      'budget_limit': limit,
      'budget_used': limit == null ? null : used,
      'budget_available': limit == null
          ? null
          : (limit - used).clamp(0.0, double.infinity),
      'can_print': canPrint,
    };
  }

  /// `GET /finance/cost-centers/mine`: active, and either the user's own private
  /// one or one they are a member of — private first, then by name.
  List<Map<String, dynamic>> mine() {
    final out = <Map<String, dynamic>>[];
    for (final c in _centers) {
      if (c['is_active'] != true) continue;
      final member = (_members[c['id']] ?? const [])
          .where((m) => m['user_id'] == userId)
          .firstOrNull;
      final own = c['is_private'] == true && c['owner_user_id'] == userId;
      if (!own && member == null) continue;
      out.add(_summary(c, canPrint: own || member?['can_print'] == true));
    }
    return out..sort((a, b) {
      final byPrivate = (b['is_private'] == true ? 1 : 0).compareTo(
        a['is_private'] == true ? 1 : 0,
      );
      return byPrivate != 0
          ? byPrivate
          : (a['name'] as String).toLowerCase().compareTo(
              (b['name'] as String).toLowerCase(),
            );
    });
  }

  /// `validate_print_budget` for [costCenterId] and a job of [cost]: null when it
  /// passes, else the refusal.
  DemoResult? budgetRefusal(Object? costCenterId, double cost) {
    if (costCenterId == null) {
      return _refuse(400, 'Cost center is required when billing is enabled');
    }
    final center = _find(costCenterId);
    if (center == null) return _refuse(404, 'Cost center not found');
    if (center['is_active'] != true) {
      return _refuse(400, 'Cost center is inactive');
    }
    final mine = this.mine().where((c) => c['id'] == costCenterId).firstOrNull;
    if (mine == null || mine['can_print'] != true) {
      return _refuse(403, 'You cannot print with this cost center');
    }
    final available = (mine['budget_available'] as num?)?.toDouble();
    if (available != null && cost > available) {
      return _refuse(
        400,
        'Estimated print cost exceeds available cost center budget '
        '(${cost.toStringAsFixed(2)} > ${available.toStringAsFixed(2)})',
      );
    }
    return null;
  }

  Map<String, dynamic>? _find(Object? id) =>
      _centers.where((c) => c['id'] == id).firstOrNull;

  // --- The routes ---

  /// Everything under `/finance/`, [s] being the path segments after it.
  DemoResult route(
    String method,
    List<String> s,
    Map<String, String> query,
    Map<String, dynamic> body,
  ) {
    DemoResult ok(Object? b) => (status: 200, body: b);
    final head = s.firstOrNull;
    int? idAt(int i) => s.length > i ? int.tryParse(s[i]) : null;

    if (head == 'me' && s.length == 2 && method == 'GET') {
      if (s[1] == 'balance') {
        return ok({
          'user_id': userId,
          'balance': balance,
          'currency': 'USD',
          'updated_at': _ledger.first['created_at'],
        });
      }
      if (s[1] == 'transactions') {
        return ok(_page(query, userId: userId));
      }
    }
    if (head == 'rebuild-balance-ledger' && method == 'POST') {
      _rebuild(_ledger);
      return ok({
        'status': 'success',
        'transactions_rebuilt': _ledger.length,
        'message': 'Rebuilt ${_ledger.length} wallet ledger values',
      });
    }
    if (head == 'transactions') return _transactions(method, s, query, body);
    if (head == 'users' && s.length == 3 && method == 'POST') {
      return _adjust(idAt(1), deposit: s[2] == 'deposit', body: body);
    }
    if (head == 'cost-centers') return _centersRoute(method, s, query, body);
    return (status: 404, body: {'detail': 'Not Found'});
  }

  Map<String, dynamic> _page(Map<String, String> query, {int? userId}) {
    final limit = int.tryParse(query['limit'] ?? '') ?? 50;
    final offset = int.tryParse(query['offset'] ?? '') ?? 0;
    final rows = [
      for (final r in _ledger)
        if (userId == null || r['user_id'] == userId) r,
    ];
    return {
      'items': rows.skip(offset).take(limit).toList(),
      'total': rows.length,
      'limit': limit,
      'offset': offset,
    };
  }

  DemoResult _transactions(
    String method,
    List<String> s,
    Map<String, String> query,
    Map<String, dynamic> body,
  ) {
    if (s.length == 1 && method == 'GET') {
      return (
        status: 200,
        body: _page(query, userId: int.tryParse(query['user_id'] ?? '')),
      );
    }
    if (s.length == 2 && s[1] == 'manual' && method == 'POST') {
      final user = body['user_id'];
      final center = body['cost_center_id'];
      if (!users.any((u) => u['id'] == user)) {
        return _refuse(404, 'User not found');
      }
      if (_find(center) == null) return _refuse(404, 'Cost center not found');
      final given = (body['amount'] as num?)?.toDouble() ?? 0;
      if (given <= 0) return _refuse(422, 'Amount must be greater than zero');
      final amount = -given;
      final row = _row(
        user: user as int,
        center: center as int,
        type: 'manual_adjustment',
        amount: amount,
        description: (body['description'] as String?) ?? 'Manual print charge',
        at: DateTime.now(),
      );
      _insert(row);
      return (status: 200, body: row);
    }
    final id = s.length == 2 ? int.tryParse(s[1]) : null;
    final row = _ledger.where((r) => r['id'] == id).firstOrNull;
    if (row == null) return _refuse(404, 'Transaction not found');
    if (method == 'DELETE') {
      _ledger.remove(row);
      _rebuild(_ledger);
      return (status: 200, body: {'status': 'success'});
    }
    if (method == 'PATCH') {
      if (body['user_id'] != null) {
        if (!users.any((u) => u['id'] == body['user_id'])) {
          return _refuse(404, 'User not found');
        }
        row['user_id'] = body['user_id'];
      }
      if (body.containsKey('cost_center_id')) {
        if (body['cost_center_id'] != null &&
            _find(body['cost_center_id']) == null) {
          return _refuse(404, 'Cost center not found');
        }
        row['cost_center_id'] = body['cost_center_id'];
      }
      if (body['amount'] != null) row['amount'] = body['amount'];
      if (body['description'] != null) {
        final text = body['description'] as String;
        row['description'] = text.endsWith('(Admin edit)')
            ? text
            : '$text (Admin edit)';
      }
      _rebuild(_ledger);
      return (status: 200, body: row);
    }
    return (status: 404, body: {'detail': 'Not Found'});
  }

  void _insert(Map<String, dynamic> row) {
    _ledger.insert(0, row);
    _ledger.sort(
      (a, b) => (b['created_at'] as String).compareTo(a['created_at']),
    );
    _rebuild(_ledger);
  }

  DemoResult _adjust(
    int? user, {
    required bool deposit,
    required Map<String, dynamic> body,
  }) {
    if (!users.any((u) => u['id'] == user)) {
      return _refuse(404, 'User not found');
    }
    final amount = (body['amount'] as num?)?.toDouble() ?? 0;
    if (amount <= 0) return _refuse(422, 'Amount must be greater than zero');
    final center = body['cost_center_id'];
    if (center != null && _find(center) == null) {
      return _refuse(404, 'Cost center not found');
    }
    final row = _row(
      user: user!,
      center: center as int?,
      type: deposit ? 'deposit' : 'withdraw',
      amount: deposit ? amount : -amount,
      description: body['description'] as String?,
      at: DateTime.now(),
    );
    _insert(row);
    return (
      status: 200,
      body: {
        'transaction': row,
        'balance': {'user_id': user, 'balance': personalBalance(user)},
      },
    );
  }

  DemoResult _centersRoute(
    String method,
    List<String> s,
    Map<String, String> query,
    Map<String, dynamic> body,
  ) {
    DemoResult ok(Object? b) => (status: 200, body: b);
    if (s.length == 2 && s[1] == 'mine' && method == 'GET') return ok(mine());
    if (s.length == 1) {
      if (method == 'GET') {
        final all = query['include_inactive'] == 'true';
        return ok([
          for (final c in _centers)
            if (all || c['is_active'] == true) _summary(c),
        ]);
      }
      if (method == 'POST') {
        final name = (body['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) return _refuse(422, 'Name is required');
        final monthly = (body['monthly_budget'] as num?)?.toDouble();
        final total = (body['total_budget'] as num?)?.toDouble();
        final created = _center(
          _nextCenterId++,
          name,
          kind: monthly != null
              ? 'monthly'
              : (total != null ? 'total' : 'none'),
          limit: monthly ?? total,
        );
        _centers.add(created);
        return ok(_summary(created));
      }
    }
    final id = s.length >= 2 ? int.tryParse(s[1]) : null;
    final center = _find(id);
    if (center == null) return _refuse(404, 'Cost center not found');
    final private = center['is_private'] == true;
    if (s.length == 2) {
      if (method == 'GET') {
        return ok({..._summary(center), 'members': _membersOf(id!)});
      }
      if (method == 'PATCH') {
        if (private) {
          return _refuse(
            400,
            'Private cost centers cannot be deactivated or renamed; set '
            'their budget to 0 to prevent printing',
          );
        }
        if (body['name'] != null) {
          center['name'] = (body['name'] as String).trim();
        }
        if (body['is_active'] != null) center['is_active'] = body['is_active'];
        return ok(_summary(center));
      }
      if (method == 'DELETE') {
        if (private) {
          return _refuse(400, 'Private cost centers cannot be deleted');
        }
        if (_ledger.any((r) => r['cost_center_id'] == id)) {
          return _refuse(
            400,
            'Cost center cannot be deleted while transactions reference it',
          );
        }
        _centers.remove(center);
        _members.remove(id);
        return ok({'status': 'success'});
      }
    }
    if (s.length == 3 && s[2] == 'budgets' && method == 'PATCH') {
      final monthly = (body['monthly_budget'] as num?)?.toDouble();
      final total = (body['total_budget'] as num?)?.toDouble();
      center['kind'] = monthly != null
          ? 'monthly'
          : (total != null ? 'total' : 'none');
      center['limit'] = monthly ?? total;
      return ok(_summary(center));
    }
    if (s.length >= 3 && s[2] == 'members') {
      if (private) {
        return _refuse(
          400,
          'Private cost center memberships cannot be modified',
        );
      }
      final members = _members.putIfAbsent(id!, () => []);
      if (s.length == 3 && method == 'POST') {
        final user = body['user_id'];
        if (!users.any((u) => u['id'] == user)) {
          return _refuse(404, 'User not found');
        }
        final existing = members.where((m) => m['user_id'] == user).firstOrNull;
        if (existing == null) {
          members.add({
            'user_id': user,
            'can_print': body['can_print'] != false,
          });
        } else {
          existing['can_print'] = body['can_print'] != false;
        }
        return ok({
          'id': 1,
          'cost_center_id': id,
          'user_id': user,
          'can_print': body['can_print'] != false,
        });
      }
      if (s.length == 4 && method == 'DELETE') {
        final before = members.length;
        members.removeWhere((m) => m['user_id'] == int.tryParse(s[3]));
        return members.length == before
            ? _refuse(404, 'Membership not found')
            : ok({'status': 'success'});
      }
    }
    return (status: 404, body: {'detail': 'Not Found'});
  }

  List<Map<String, dynamic>> _membersOf(int id) => [
    for (final (i, m) in (_members[id] ?? const []).indexed)
      {
        'id': i + 1,
        'cost_center_id': id,
        ...m,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
  ];

  static DemoResult _refuse(int status, String detail) =>
      (status: status, body: {'detail': detail});
}
