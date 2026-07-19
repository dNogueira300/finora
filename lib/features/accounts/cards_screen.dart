import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/finora_colors.dart';
import '../../core/finora_tokens.dart';
import '../../core/finora_widgets.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import 'edit_account_sheet.dart';

final _activeAccountsProvider = StreamProvider.autoDispose<List<Account>>((ref) {
  return ref.watch(databaseProvider).accountsDao.watchActive();
});

/// `watchActive()` solo re-emite cuando cambia la tabla `accounts`: una
/// transaccion nueva contra una cuenta no dispara por si sola un recalculo
/// de saldo/uso de linea de credito (misma limitacion documentada en
/// `dashboard_screen.dart` para `monthTotalsProvider`/`totalBalanceProvider`).
/// Se observa este stream unicamente como "trigger" para que `CardsScreen`
/// reconstruya sus `FutureBuilder` de `balanceCents` cuando se registra un
/// gasto o un pago.
final _recentTxnsProvider = StreamProvider.autoDispose<List<Txn>>((ref) {
  return ref.watch(databaseProvider).transactionsDao.watchRecent(50);
});

/// Ultima pagina del carrusel de tarjetas, guardada FUERA del `State` de
/// `CardsScreen`. Al cambiar de pestaña con `context.go`, el `ShellRoute`
/// reemplaza su hijo y `_CardsScreenState` se destruye por completo (no es
/// un simple rebuild): un `PageController` creado en el `State` vuelve a
/// nacer en la pagina 0 al reconstruirse. Este provider NO es `autoDispose`
/// para que sobreviva ese desmontaje mientras el usuario esta en otra
/// pestaña y se recupere al volver a `/cards`.
final _carouselPageProvider = StateProvider<int>((_) => 0);

/// Pantalla "Mis Tarjetas" (referencia Stitch "Mis Tarjetas Premium"):
/// carrusel de tarjetas visuales para cuentas `credit`/`debit` (con barra de
/// uso de linea para `credit`) y lista de cuentas `cash`/`wallet` con su
/// saldo. FAB abre `EditAccountSheet` para crear una cuenta nueva; long-press
/// sobre una cuenta abre el menu Editar/Archivar/Eliminar.
class CardsScreen extends ConsumerStatefulWidget {
  const CardsScreen({super.key});

  @override
  ConsumerState<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends ConsumerState<CardsScreen> {
  // Creado una unica vez por instancia de `_CardsScreenState` (no en
  // `build`): `CardsScreen` reconstruye su arbol cada vez que
  // `_activeAccountsProvider`/`_recentTxnsProvider` emiten (p. ej. al
  // registrar cualquier transaccion mientras la pantalla esta montada). Un
  // `PageController` nuevo en cada `build` reiniciaria el carrusel a la
  // primera pagina en cada rebuild, deshaciendo el swipe del usuario.
  //
  // Es nullable (en vez de `late final`) porque su `initialPage` depende de
  // `cardAccounts.length`, que solo se conoce dentro de `build` una vez que
  // `_activeAccountsProvider` tiene datos; se crea perezosamente la primera
  // vez que se conoce ese conteo y se reutiliza en los rebuilds siguientes.
  PageController? _pageController;

  /// Se lee (no se observa) `_carouselPageProvider` al construir el
  /// controlador: cambiar de pestaña destruye esta instancia de `State`
  /// (y con ella `_pageController`), asi que la pagina debe sobrevivir en
  /// un provider no-autoDispose para que el carrusel no vuelva a la
  /// primera tarjeta al regresar a `/cards`. Se acota contra `cardCount`
  /// por si se eliminaron tarjetas mientras el usuario estaba en otra
  /// pestaña: un `initialPage` fuera de rango no debe romper el carrusel.
  PageController _controllerFor(int cardCount) {
    final stored = ref.read(_carouselPageProvider);
    final initialPage = stored.clamp(0, cardCount - 1);
    return _pageController ??= PageController(viewportFraction: .9, initialPage: initialPage);
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(_activeAccountsProvider);
    // Solo se usa como trigger de invalidacion (ver nota del provider).
    ref.watch(_recentTxnsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis tarjetas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Calendario de vencimientos',
            onPressed: () => context.push('/calendar'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'cards-new-account-fab',
        onPressed: () => _openEditSheet(context),
        backgroundColor: FinoraColors.primary,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        label: const Text(
          '+ Nueva cuenta',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: accountsAsync.when(
          data: (accounts) {
            if (accounts.isEmpty) {
              return const _EmptyState();
            }
            final cardAccounts =
                accounts.where((a) => a.type == 'credit' || a.type == 'debit').toList();
            final walletAccounts =
                accounts.where((a) => a.type == 'cash' || a.type == 'wallet').toList();
            // Se observa la pagina actual para pintar los dots del carrusel.
            // No recrea el `PageController` (esta cacheado en `_pageController`):
            // solo reconstruye el arbol y los dots reflejan el swipe.
            final currentPage = ref.watch(_carouselPageProvider);
            return ListView(
              padding: const EdgeInsets.all(FinoraTokens.s16),
              children: [
                if (cardAccounts.isNotEmpty) ...[
                  const SectionHeader('Tarjetas'),
                  const SizedBox(height: FinoraTokens.s12),
                  SizedBox(
                    height: 190,
                    child: PageView(
                      controller: _controllerFor(cardAccounts.length),
                      onPageChanged: (i) =>
                          ref.read(_carouselPageProvider.notifier).state = i,
                      children: [
                        for (final a in cardAccounts)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: _AccountCard(
                              account: a,
                              onLongPress: () => showAccountMenu(context, ref, a),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (cardAccounts.length > 1) ...[
                    const SizedBox(height: FinoraTokens.s12),
                    _PageDots(
                      count: cardAccounts.length,
                      active: currentPage.clamp(0, cardAccounts.length - 1),
                    ),
                  ],
                  const SizedBox(height: FinoraTokens.s24),
                ],
                if (walletAccounts.isNotEmpty) ...[
                  const SectionHeader('Efectivo y billeteras'),
                  const SizedBox(height: FinoraTokens.s12),
                  for (final a in walletAccounts)
                    _WalletTile(
                      account: a,
                      onLongPress: () => showAccountMenu(context, ref, a),
                    ),
                ],
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('No se pudo cargar: $e')),
        ),
      ),
    );
  }
}

Future<void> _openEditSheet(BuildContext context, {Account? account}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EditAccountSheet(account: account),
  );
}

/// Menu de acciones de una cuenta (Editar/Archivar/Eliminar), abierto con
/// long-press. Publica (sin `_`) para poder invocarla directamente desde los
/// tests de widget sin depender de gestos de long-press.
Future<void> showAccountMenu(BuildContext context, WidgetRef ref, Account account) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Editar'),
            onTap: () => Navigator.of(ctx).pop('edit'),
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Archivar'),
            onTap: () => Navigator.of(ctx).pop('archive'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: FinoraColors.expense),
            title: const Text('Eliminar', style: TextStyle(color: FinoraColors.expense)),
            onTap: () => Navigator.of(ctx).pop('delete'),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;
  final db = ref.read(databaseProvider);
  switch (action) {
    case 'edit':
      await _openEditSheet(context, account: account);
    case 'archive':
      // `AccountsDao.upsert` hace `insertOnConflictUpdate`, que valida como si
      // fuera un INSERT nuevo: las columnas NOT NULL sin default (`name`,
      // `type`) deben venir presentes aunque la fila ya exista. Se reenvian
      // todos los campos actuales de `account` y solo se cambia `isArchived`.
      await db.accountsDao.upsert(AccountsCompanion.insert(
        id: account.id,
        name: account.name,
        type: account.type,
        initialBalanceCents: Value(account.initialBalanceCents),
        creditLimitCents: Value(account.creditLimitCents),
        statementDay: Value(account.statementDay),
        paymentDueDay: Value(account.paymentDueDay),
        last4: Value(account.last4),
        color: Value(account.color),
        isArchived: const Value(true),
        updatedAt: DateTime.now().toUtc(),
      ));
    case 'delete':
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Eliminar cuenta'),
          content: Text('¿Eliminar "${account.name}"? Esta acción no se puede deshacer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Eliminar', style: TextStyle(color: FinoraColors.expense)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await db.accountsDao.softDelete(account.id);
      }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Aún no tienes cuentas.\nToca "Nueva cuenta" para crear la primera.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: FinoraColors.textSecondary),
        ),
      ),
    );
  }
}

/// Tarjeta visual de una cuenta `credit`/`debit`: degradado con
/// `account.color`, nombre, `**** {last4}` y tipo. Para `credit` agrega la
/// barra de uso de linea (ambar > 70%, rojo > 90%) y "Disponible: S/ X".
class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.account, required this.onLongPress});
  final Account account;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [Color(account.color), Color(account.color).withValues(alpha: .7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    account.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.contactless, color: Colors.white70),
              ],
            ),
            const SizedBox(height: FinoraTokens.s8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: FinoraTokens.s8, vertical: FinoraTokens.s4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .2),
                borderRadius: BorderRadius.circular(FinoraTokens.rPill),
              ),
              child: Text(
                accountTypeLabel(account.type),
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            const Spacer(),
            Text(
              '****  ****  ****  ${account.last4 ?? '----'}',
              style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 2),
            ),
            const SizedBox(height: FinoraTokens.s12),
            FutureBuilder<int>(
              future: db.accountsDao.balanceCents(account.id),
              builder: (context, snapshot) {
                final cents = snapshot.data;
                if (account.type != 'credit') {
                  return Text('Saldo: ${formatMoney(cents ?? 0)}',
                      style: const TextStyle(color: Colors.white, fontSize: 13));
                }
                final limit = account.creditLimitCents ?? 0;
                final usado = cents ?? 0;
                final ratio = limit > 0 ? (usado / limit).clamp(0.0, 1.0) : 0.0;
                final barColor = ratio > 0.9
                    ? FinoraColors.expense
                    : (ratio > 0.7 ? FinoraColors.warning : Colors.white);
                // Fix visual minor T16: si lo usado es negativo (un pago dejo la
                // linea "a favor"), el disponible no puede exceder el limite; se
                // acota en pantalla sin tocar el valor calculado/persistido.
                final disponible = usado < 0 ? limit : limit - usado;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation(barColor),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Disponible: ${formatMoney(disponible)}',
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Indicador de pagina del carrusel: un punto por tarjeta. El activo es una
/// pildora alargada primary (16x6); los inactivos, un circulo con borde (6x6).
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: FinoraTokens.dFast,
            curve: FinoraTokens.curve,
            margin: const EdgeInsets.symmetric(horizontal: FinoraTokens.s4),
            width: i == active ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == active ? FinoraColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(FinoraTokens.rPill),
              border: i == active ? null : Border.all(color: FinoraColors.border),
            ),
          ),
      ],
    );
  }
}

/// Fila de lista para una cuenta `cash`/`wallet` con su saldo actual.
class _WalletTile extends ConsumerWidget {
  const _WalletTile({required this.account, required this.onLongPress});
  final Account account;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return GestureDetector(
      onLongPress: onLongPress,
      child: Card(
        margin: const EdgeInsets.only(bottom: FinoraTokens.s12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FinoraTokens.rInput)),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(account.color),
              borderRadius: BorderRadius.circular(FinoraTokens.rInput),
            ),
            child: Icon(
              account.type == 'wallet' ? Icons.account_balance_wallet : Icons.payments,
              color: Colors.white,
              size: 20,
            ),
          ),
          title: Text(account.name),
          subtitle: Text(accountTypeLabel(account.type)),
          trailing: FutureBuilder<int>(
            future: db.accountsDao.balanceCents(account.id),
            builder: (context, snapshot) => Text(
              formatMoney(snapshot.data ?? 0),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
