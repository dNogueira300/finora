import 'package:intl/intl.dart';

final _fmt = NumberFormat.currency(locale: 'en_US', symbol: 'S/ ', decimalDigits: 2);

String formatMoney(int cents) {
  final s = _fmt.format(cents.abs() / 100);
  return cents < 0 ? '-$s' : s;
}

int? parseMoney(String input) {
  final clean = input.replaceAll(',', '').trim();
  final value = double.tryParse(clean);
  if (value == null) return null;
  return (value * 100).round();
}
