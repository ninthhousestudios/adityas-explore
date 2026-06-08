class ChartData {
  String name;
  DateTime dateTime;
  GeoLocation birthLocation;
  double utcOffsetHours;
  double dstOffsetHours;

  Gender? gender;
  String? notes;
  String? roddenRating;
  List<String>? tags;
  double? julianDay;
  GeoLocation? currentLocation;
  double? currentUtcOffsetHours;
  Map<String, dynamic> extra;

  ChartData({
    required this.name,
    required this.dateTime,
    required this.birthLocation,
    this.utcOffsetHours = 0.0,
    this.dstOffsetHours = 0.0,
    this.gender,
    this.notes,
    this.roddenRating,
    this.tags,
    this.julianDay,
    this.currentLocation,
    this.currentUtcOffsetHours,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  DateTime get utcDateTime => dateTime.subtract(
        Duration(minutes: ((utcOffsetHours + dstOffsetHours) * 60).round()),
      );

  double get decimalHours =>
      dateTime.hour + dateTime.minute / 60.0 + dateTime.second / 3600.0;

  @override
  String toString() =>
      'ChartData($name, ${dateTime.toIso8601String()}, $birthLocation)';
}

enum Gender { male, female, unknown }

class GeoLocation {
  String city;
  String country;
  double latitude;
  double longitude;

  GeoLocation({
    this.city = '',
    this.country = '',
    required this.latitude,
    required this.longitude,
  });

  @override
  String toString() {
    final ns = latitude >= 0 ? 'N' : 'S';
    final ew = longitude >= 0 ? 'E' : 'W';
    return '$city, $country '
        '(${latitude.abs().toStringAsFixed(2)}$ns, '
        '${longitude.abs().toStringAsFixed(2)}$ew)';
  }
}
