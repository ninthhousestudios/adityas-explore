double dateTimeToJdUt(DateTime dt) {
  const jdEpoch = 2440587.5;
  const msPerDay = 86400000.0;
  return jdEpoch + dt.toUtc().millisecondsSinceEpoch / msPerDay;
}

DateTime jdUtToDateTime(double jd) {
  const jdEpoch = 2440587.5;
  const msPerDay = 86400000.0;
  final ms = ((jd - jdEpoch) * msPerDay).round();
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}
