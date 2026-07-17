import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finora/features/auth/lock_screen.dart';

void main() {
  test('la app arranca bloqueada y se desbloquea', () {
    final container = ProviderContainer();
    expect(container.read(appLockedProvider), true);
    container.read(appLockedProvider.notifier).state = false;
    expect(container.read(appLockedProvider), false);
  });
}
