import 'database.dart';

/// IDs fijos y deterministicos para las 10 categorias por defecto (fix de
/// duplicados multi-dispositivo, ver nota de `seedDefaultCategories` mas
/// abajo). Generados una sola vez con `Uuid().v4()` y fijados aqui como
/// constantes: NUNCA deben cambiar de valor ni de orden — cambiar el id de
/// una categoria ya sembrada en produccion crearia una fila nueva (duplicada)
/// en vez de actualizar la existente.
const _idComida = '1436f568-89a0-428d-ad04-df12122e2d2e';
const _idPasajes = 'fdd8d632-7d6a-4c14-bdc7-244c7271b3c9';
const _idServicios = '40e9d264-1012-49f7-b32d-186040caad3e';
const _idCompras = '5276fd82-f50a-479d-a5e3-52e6dc65a029';
const _idSalud = '81243eed-e14d-4f73-bc45-48aa6f6fe8ea';
const _idEducacion = '17106421-faf8-4d78-b39c-b1d1f5a444b7';
const _idOcio = 'abf27f07-c408-42f4-a944-e2fd103d1444';
const _idPagoTarjeta = '508757aa-fbe2-4996-a43c-b8b759fd5077';
const _idSueldo = 'd9f5130a-36ab-4f38-997a-0f738ba6626f';
const _idOtrosIngresos = 'dfcbdc60-f6c4-40bd-b0df-aedbf10a3dfb';

/// Siembra las 10 categorias por defecto SOLO si la tabla local esta vacia
/// (`countAll() == 0`). Belt-and-suspenders contra duplicados en un segundo
/// dispositivo/reinstalacion (ver `SyncCoordinator` en `sync_providers.dart`,
/// que ahora hace el primer `pull()` ANTES de llamar a esta funcion):
///
/// 1. IDs fijos (arriba) en vez de `Uuid().v4()` por instalacion: si dos
///    dispositivos llegan a sembrar de forma concurrente (p. ej. el primer
///    `pull()` de uno de los dos falla por falta de red), ambos escriben la
///    MISMA fila por id para cada categoria. El `upsert`/LWW de
///    `sync_engine.dart` converge a una sola fila por categoria al
///    sincronizar, en vez de terminar con 20 filas (10 duplicadas por
///    nombre).
/// 2. El guard `countAll() > 0`: como `SyncCoordinator` ahora intenta un
///    `pull()` antes de sembrar, un segundo dispositivo que SI tuvo red para
///    ese pull ya habra recibido las 10 categorias del primero y esta
///    funcion no hace nada.
Future<void> seedDefaultCategories(AppDatabase db) async {
  if (await db.categoriesDao.countAll() > 0) return;
  final now = DateTime.now().toUtc();
  const defaults = [
    (_idComida, 'Comida', 'restaurant', 0xFFEF4444, 'expense'),
    (_idPasajes, 'Pasajes', 'directions_bus', 0xFFF59E0B, 'expense'),
    (_idServicios, 'Servicios', 'receipt_long', 0xFF3B82F6, 'expense'),
    (_idCompras, 'Compras', 'shopping_bag', 0xFF8B5CF6, 'expense'),
    (_idSalud, 'Salud', 'favorite', 0xFFEC4899, 'expense'),
    (_idEducacion, 'Educación', 'school', 0xFF14B8A6, 'expense'),
    (_idOcio, 'Ocio', 'sports_esports', 0xFF6366F1, 'expense'),
    (_idPagoTarjeta, 'Pago de tarjeta', 'credit_score', 0xFF1E3A8A, 'income'),
    (_idSueldo, 'Sueldo', 'payments', 0xFF22C55E, 'income'),
    (_idOtrosIngresos, 'Otros ingresos', 'add_circle', 0xFF16A34A, 'income'),
  ];
  for (final (id, name, icon, color, kind) in defaults) {
    await db.categoriesDao.upsert(CategoriesCompanion.insert(
      id: id,
      name: name,
      icon: icon,
      color: color,
      kind: kind,
      updatedAt: now,
    ));
  }
}
