import 'package:flutter_test/flutter_test.dart';
import 'package:finora/core/dates.dart';

void main() {
  test('toLima resta 5 horas al UTC', () {
    expect(toLima(DateTime.utc(2026, 7, 16, 3, 0)), DateTime(2026, 7, 15, 22, 0));
  });
  test('limaToUtc suma 5 horas', () {
    expect(limaToUtc(DateTime(2026, 7, 15, 22, 0)), DateTime.utc(2026, 7, 16, 3, 0));
  });
  test('monthRangeUtc devuelve limites del mes de Lima en UTC', () {
    final (from, to) = monthRangeUtc(DateTime(2026, 7, 1));
    expect(from, DateTime.utc(2026, 7, 1, 5, 0));
    expect(to, DateTime.utc(2026, 8, 1, 5, 0));
  });
}
