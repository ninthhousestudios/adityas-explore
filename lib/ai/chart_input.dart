import 'package:charts_dart/charts_dart.dart';

/// The open chart's civil birth data in the backend's `ChartInput` shape, which
/// mirrors `CalculateRequest` (adityas/ai/35). `date`/`time`/`utc_offset`/
/// `dst_offset` reuse charts_dart's canonical [ChartData.toJson] formatting
/// (`YYYY-MM-DD` / `HH:MM:SS`); `lat`/`lon` are flattened out of the nested
/// `location` object the backend doesn't accept here.
///
/// Used by the durable `/v1/ai` chat path (`SseTurnTransport`, adityas/ai/65)
/// to ground a turn in the open chart's birth data.
Map<String, dynamic> chartInputJson(ChartData chart) {
  final json = chart.toJson();
  return {
    'date': json['date'],
    'time': json['time'],
    'lat': chart.birthLocation.latitude,
    'lon': chart.birthLocation.longitude,
    'utc_offset': json['utc_offset'],
    'dst_offset': json['dst_offset'],
  };
}
