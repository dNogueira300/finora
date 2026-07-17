import 'package:drift/drift.dart';
import '../local/database.dart';

class SyncTableSpec {
  SyncTableSpec({
    required this.remoteName,
    required this.dirtyRows,
    required this.markClean,
    required this.applyRemote,
  });
  final String remoteName;
  final Future<List<Map<String, dynamic>>> Function() dirtyRows;
  final Future<void> Function(List<String> ids) markClean;
  final Future<void> Function(Map<String, dynamic> row) applyRemote;
}

String _iso(DateTime d) => d.toUtc().toIso8601String();
DateTime _parse(String s) => DateTime.parse(s).toUtc();
int _int(dynamic v) => (v as num).toInt();
int? _intOrNull(dynamic v) => v == null ? null : (v as num).toInt();

List<SyncTableSpec> buildTableSpecs(AppDatabase db) => [
  SyncTableSpec(
    remoteName: 'accounts',
    dirtyRows: () async {
      final rows = await (db.select(db.accounts)
            ..where((t) => t.isDirty.equals(true))).get();
      return rows.map((r) => {
        'id': r.id, 'name': r.name, 'type': r.type,
        'initial_balance_cents': r.initialBalanceCents,
        'credit_limit_cents': r.creditLimitCents,
        'statement_day': r.statementDay, 'payment_due_day': r.paymentDueDay,
        'last4': r.last4, 'color': r.color, 'is_archived': r.isArchived,
        'updated_at': _iso(r.updatedAt),
        'deleted_at': r.deletedAt == null ? null : _iso(r.deletedAt!),
      }).toList();
    },
    markClean: (ids) => (db.update(db.accounts)
          ..where((t) => t.id.isIn(ids)))
        .write(const AccountsCompanion(isDirty: Value(false))),
    applyRemote: (r) async {
      final remoteUpdated = _parse(r['updated_at']);
      final local = await (db.select(db.accounts)
            ..where((t) => t.id.equals(r['id']))).getSingleOrNull();
      if (local != null && local.isDirty && local.updatedAt.isAfter(remoteUpdated)) {
        return; // gana lo local; se re-empujara
      }
      await db.into(db.accounts).insertOnConflictUpdate(AccountsCompanion(
        id: Value(r['id']), name: Value(r['name']), type: Value(r['type']),
        initialBalanceCents: Value(_int(r['initial_balance_cents'])),
        creditLimitCents: Value(_intOrNull(r['credit_limit_cents'])),
        statementDay: Value(_intOrNull(r['statement_day'])),
        paymentDueDay: Value(_intOrNull(r['payment_due_day'])),
        last4: Value(r['last4'] as String?),
        color: Value(_int(r['color'])),
        isArchived: Value(r['is_archived'] as bool),
        updatedAt: Value(remoteUpdated),
        deletedAt: Value(r['deleted_at'] == null ? null : _parse(r['deleted_at'])),
        isDirty: const Value(false),
      ));
    },
  ),
  SyncTableSpec(
    remoteName: 'categories',
    dirtyRows: () async {
      final rows = await (db.select(db.categories)
            ..where((t) => t.isDirty.equals(true))).get();
      return rows.map((r) => {
        'id': r.id, 'name': r.name, 'icon': r.icon, 'color': r.color,
        'kind': r.kind, 'updated_at': _iso(r.updatedAt),
        'deleted_at': r.deletedAt == null ? null : _iso(r.deletedAt!),
      }).toList();
    },
    markClean: (ids) => (db.update(db.categories)
          ..where((t) => t.id.isIn(ids)))
        .write(const CategoriesCompanion(isDirty: Value(false))),
    applyRemote: (r) async {
      final remoteUpdated = _parse(r['updated_at']);
      final local = await (db.select(db.categories)
            ..where((t) => t.id.equals(r['id']))).getSingleOrNull();
      if (local != null && local.isDirty && local.updatedAt.isAfter(remoteUpdated)) return;
      await db.into(db.categories).insertOnConflictUpdate(CategoriesCompanion(
        id: Value(r['id']), name: Value(r['name']), icon: Value(r['icon']),
        color: Value(_int(r['color'])), kind: Value(r['kind']),
        updatedAt: Value(remoteUpdated),
        deletedAt: Value(r['deleted_at'] == null ? null : _parse(r['deleted_at'])),
        isDirty: const Value(false),
      ));
    },
  ),
  SyncTableSpec(
    remoteName: 'transactions',
    dirtyRows: () async {
      final rows = await (db.select(db.transactions)
            ..where((t) => t.isDirty.equals(true))).get();
      return rows.map((r) => {
        'id': r.id, 'account_id': r.accountId, 'category_id': r.categoryId,
        'kind': r.kind, 'amount_cents': r.amountCents, 'note': r.note,
        'occurred_at': _iso(r.occurredAt), 'updated_at': _iso(r.updatedAt),
        'deleted_at': r.deletedAt == null ? null : _iso(r.deletedAt!),
      }).toList();
    },
    markClean: (ids) => (db.update(db.transactions)
          ..where((t) => t.id.isIn(ids)))
        .write(const TransactionsCompanion(isDirty: Value(false))),
    applyRemote: (r) async {
      final remoteUpdated = _parse(r['updated_at']);
      final local = await (db.select(db.transactions)
            ..where((t) => t.id.equals(r['id']))).getSingleOrNull();
      if (local != null && local.isDirty && local.updatedAt.isAfter(remoteUpdated)) return;
      await db.into(db.transactions).insertOnConflictUpdate(TransactionsCompanion(
        id: Value(r['id']), accountId: Value(r['account_id']),
        categoryId: Value(r['category_id']), kind: Value(r['kind']),
        amountCents: Value(_int(r['amount_cents'])),
        note: Value(r['note'] as String?),
        occurredAt: Value(_parse(r['occurred_at'])),
        updatedAt: Value(remoteUpdated),
        deletedAt: Value(r['deleted_at'] == null ? null : _parse(r['deleted_at'])),
        isDirty: const Value(false),
      ));
    },
  ),
  SyncTableSpec(
    remoteName: 'savings_goals',
    dirtyRows: () async {
      final rows = await (db.select(db.savingsGoals)
            ..where((t) => t.isDirty.equals(true))).get();
      return rows.map((r) => {
        'id': r.id, 'name': r.name, 'target_cents': r.targetCents,
        'saved_cents': r.savedCents,
        'deadline': r.deadline == null ? null : _iso(r.deadline!),
        'color': r.color, 'updated_at': _iso(r.updatedAt),
        'deleted_at': r.deletedAt == null ? null : _iso(r.deletedAt!),
      }).toList();
    },
    markClean: (ids) => (db.update(db.savingsGoals)
          ..where((t) => t.id.isIn(ids)))
        .write(const SavingsGoalsCompanion(isDirty: Value(false))),
    applyRemote: (r) async {
      final remoteUpdated = _parse(r['updated_at']);
      final local = await (db.select(db.savingsGoals)
            ..where((t) => t.id.equals(r['id']))).getSingleOrNull();
      if (local != null && local.isDirty && local.updatedAt.isAfter(remoteUpdated)) return;
      await db.into(db.savingsGoals).insertOnConflictUpdate(SavingsGoalsCompanion(
        id: Value(r['id']), name: Value(r['name']),
        targetCents: Value(_int(r['target_cents'])),
        savedCents: Value(_int(r['saved_cents'])),
        deadline: Value(r['deadline'] == null ? null : _parse(r['deadline'])),
        color: Value(_int(r['color'])),
        updatedAt: Value(remoteUpdated),
        deletedAt: Value(r['deleted_at'] == null ? null : _parse(r['deleted_at'])),
        isDirty: const Value(false),
      ));
    },
  ),
  SyncTableSpec(
    remoteName: 'user_settings',
    dirtyRows: () async {
      final rows = await (db.select(db.userSettings)
            ..where((t) => t.isDirty.equals(true))).get();
      // biometric_enabled es solo local: NO se envia.
      return rows.map((r) => {
        'id': r.id, 'monthly_limit_cents': r.monthlyLimitCents,
        'alert_days_before_due': r.alertDaysBeforeDue,
        'updated_at': _iso(r.updatedAt),
        'deleted_at': r.deletedAt == null ? null : _iso(r.deletedAt!),
      }).toList();
    },
    markClean: (ids) => (db.update(db.userSettings)
          ..where((t) => t.id.isIn(ids)))
        .write(const UserSettingsCompanion(isDirty: Value(false))),
    applyRemote: (r) async {
      final remoteUpdated = _parse(r['updated_at']);
      final local = await (db.select(db.userSettings)
            ..where((t) => t.id.equals(r['id']))).getSingleOrNull();
      if (local != null && local.isDirty && local.updatedAt.isAfter(remoteUpdated)) return;
      await db.into(db.userSettings).insertOnConflictUpdate(UserSettingsCompanion(
        id: Value(r['id']),
        monthlyLimitCents: Value(_intOrNull(r['monthly_limit_cents'])),
        alertDaysBeforeDue: Value(_int(r['alert_days_before_due'])),
        // conservar biometric_enabled local si la fila ya existia
        biometricEnabled: Value(local?.biometricEnabled ?? false),
        updatedAt: Value(remoteUpdated),
        deletedAt: Value(r['deleted_at'] == null ? null : _parse(r['deleted_at'])),
        isDirty: const Value(false),
      ));
    },
  ),
];
