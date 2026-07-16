/// America/Lima es UTC-5 fijo (sin horario de verano).
const _limaOffset = Duration(hours: 5);

/// Convierte un instante UTC a hora de Lima (DateTime "naive" de Perú).
DateTime toLima(DateTime utc) {
  final l = utc.toUtc().subtract(_limaOffset);
  return DateTime(l.year, l.month, l.day, l.hour, l.minute, l.second, l.millisecond);
}

/// Interpreta [lima] como hora de Perú y devuelve el instante UTC.
DateTime limaToUtc(DateTime lima) =>
    DateTime.utc(lima.year, lima.month, lima.day, lima.hour, lima.minute,
        lima.second, lima.millisecond).add(_limaOffset);

/// Límites [desde, hasta) en UTC del mes calendario de Lima que contiene [limaMonth].
(DateTime, DateTime) monthRangeUtc(DateTime limaMonth) => (
      limaToUtc(DateTime(limaMonth.year, limaMonth.month, 1)),
      limaToUtc(DateTime(limaMonth.year, limaMonth.month + 1, 1)),
    );
