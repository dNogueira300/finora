import 'package:flutter_test/flutter_test.dart';
import 'package:finora/services/notifications_service.dart';

void main() {
  test('recordatorio N dias antes a las 9am', () {
    expect(reminderDateTime(DateTime(2026, 7, 15), 3), DateTime(2026, 7, 12, 9));
  });
}
