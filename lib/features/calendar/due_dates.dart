/// Proxima ocurrencia del dia `dueDay` del mes a partir de `from` (ambos
/// "naive", sin zona horaria: quien llama decide que hora usar como "hoy",
/// ver `toLima` en `core/dates.dart`). Si `dueDay` ya paso este mes, salta al
/// mes siguiente. Maneja meses cortos: si `dueDay` no existe en el mes
/// candidato (p. ej. 31 en junio) se ajusta al ultimo dia de ese mes.
DateTime nextDueDate(int dueDay, DateTime from) {
  DateTime candidate = _clampToMonth(from.year, from.month, dueDay);
  if (!candidate.isBefore(DateTime(from.year, from.month, from.day))) {
    return candidate;
  }
  final next = DateTime(from.year, from.month + 1, 1);
  return _clampToMonth(next.year, next.month, dueDay);
}

DateTime _clampToMonth(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > lastDay ? lastDay : day);
}
