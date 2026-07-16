import 'package:flutter_test/flutter_test.dart';
import 'package:finora/core/money.dart';

void main() {
  test('formatea centavos a soles', () {
    expect(formatMoney(123456), 'S/ 1,234.56');
    expect(formatMoney(0), 'S/ 0.00');
    expect(formatMoney(-5000), '-S/ 50.00');
  });
  test('parsea texto de usuario a centavos', () {
    expect(parseMoney('1234.56'), 123456);
    expect(parseMoney('1,234.56'), 123456);
    expect(parseMoney('50'), 5000);
    expect(parseMoney('abc'), null);
  });
}
