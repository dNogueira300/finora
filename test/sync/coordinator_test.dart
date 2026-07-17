import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finora/data/sync/sync_providers.dart';

// NOTA: `SyncCoordinator` (y por lo tanto `syncCoordinatorProvider`) tocan
// `Supabase.instance` y plugins de plataforma (`connectivity_plus`) en su
// constructor, asi que no se instancian en este test unitario: requieren un
// entorno con `Supabase.initialize()` y plugins registrados, cubierto por la
// prueba manual (Step 3 del brief), no por la suite automatizada. Esta
// prueba solo verifica lo que es observable sin esas dependencias: el enum
// y el valor por defecto de `syncStatusProvider` en un `ProviderContainer`
// limpio (que nunca crea el coordinador porque nadie lo observa).
void main() {
  test('SyncStatus expone los cuatro valores esperados', () {
    expect(SyncStatus.values, [
      SyncStatus.idle,
      SyncStatus.syncing,
      SyncStatus.offline,
      SyncStatus.error,
    ]);
  });

  test('syncStatusProvider arranca en SyncStatus.idle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(syncStatusProvider), SyncStatus.idle);
  });
}
