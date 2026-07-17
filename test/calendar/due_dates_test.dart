// test/calendar/due_dates_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:finora/features/calendar/due_dates.dart';

void main() {
  test('proxima fecha en el mismo mes si aun no pasa', () {
    expect(nextDueDate(20, DateTime(2026, 7, 10)), DateTime(2026, 7, 20));
  });
  test('salta al mes siguiente si ya paso', () {
    expect(nextDueDate(5, DateTime(2026, 7, 10)), DateTime(2026, 8, 5));
  });
  test('ajusta meses cortos', () {
    expect(nextDueDate(31, DateTime(2026, 6, 1)), DateTime(2026, 6, 30));
    expect(nextDueDate(30, DateTime(2026, 2, 1)), DateTime(2026, 2, 28));
  });
}
