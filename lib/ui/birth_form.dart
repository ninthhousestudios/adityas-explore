import 'dart:convert';

import 'package:charts_dart/charts_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/places_service.dart';
import '../astro/being_uncertainty.dart'
    show TimeUncertainty, ExactTime, PeriodTime, UnknownTime;
import '../file_util.dart' if (dart.library.js_interop) '../file_util_web.dart';
import '../navigate.dart' if (dart.library.js_interop) '../navigate_web.dart';

enum TimePrecision { exact, general, unknown }

enum BirthPeriod {
  morning(
    label: 'Morning',
    range: '6:00 AM – 12:00 PM',
    hour: 9,
    startHour: 6,
    endHour: 12,
  ),
  afternoon(
    label: 'Afternoon',
    range: '12:00 PM – 6:00 PM',
    hour: 15,
    startHour: 12,
    endHour: 18,
  ),
  evening(
    label: 'Evening',
    range: '6:00 PM – 12:00 AM',
    hour: 21,
    startHour: 18,
    endHour: 0,
  ),
  night(
    label: 'Night',
    range: '12:00 AM – 6:00 AM',
    hour: 3,
    startHour: 0,
    endHour: 6,
  );

  const BirthPeriod({
    required this.label,
    required this.range,
    required this.hour,
    required this.startHour,
    required this.endHour,
  });

  final String label;
  final String range;
  final int hour;
  final int startHour;
  final int endHour;

  TimeOfDay get midpoint => TimeOfDay(hour: hour, minute: 0);

  static BirthPeriod fromHour(int hour) {
    if (hour >= 6 && hour < 12) return morning;
    if (hour >= 12 && hour < 18) return afternoon;
    if (hour >= 18) return evening;
    return night;
  }
}

class BirthForm extends StatefulWidget {
  final void Function(ChartData chartData, TimeUncertainty uncertainty)
  onSubmit;
  final VoidCallback onOpenChart;

  const BirthForm({
    super.key,
    required this.onSubmit,
    required this.onOpenChart,
  });

  @override
  State<BirthForm> createState() => _BirthFormState();
}

class _BirthFormState extends State<BirthForm> {
  final _nameController = TextEditingController();
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  final _locationQueryController = TextEditingController();

  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  final _tzController = TextEditingController();
  final _dstController = TextEditingController(text: '0.0');

  DateTime? _birthDate;
  TimeOfDay? _birthTime;
  TimePrecision _timePrecision = TimePrecision.exact;
  BirthPeriod? _selectedPeriod;

  TimeOfDay? get _effectiveBirthTime => switch (_timePrecision) {
    TimePrecision.exact => _birthTime,
    TimePrecision.general => _selectedPeriod?.midpoint,
    TimePrecision.unknown => const TimeOfDay(hour: 12, minute: 0),
  };

  bool _advancedExpanded = false;
  bool _chartSaved = false;

  final _placesService = PlacesService();
  List<PlaceAutocompleteResult> _searchResults = [];
  bool _searching = false;
  bool _resolving = false;
  String? _searchError;

  String? _dateError;
  String? _timeError;
  String? _latError;
  String? _lonError;
  String? _tzError;
  String? _dstError;

  bool get _hasTimezone {
    final text = _tzController.text.trim();
    if (text.isEmpty) return false;
    final v = double.tryParse(text);
    return v != null && v >= -12 && v <= 14;
  }

  bool get _hasDst {
    final text = _dstController.text.trim();
    final v = double.tryParse(text);
    return v != null;
  }

  bool get _hasValidLat {
    final text = _latController.text.trim();
    if (text.isEmpty) return false;
    final v = double.tryParse(text);
    return v != null && v >= -90 && v <= 90;
  }

  bool get _hasValidLon {
    final text = _lonController.text.trim();
    if (text.isEmpty) return false;
    final v = double.tryParse(text);
    return v != null && v >= -180 && v <= 180;
  }

  bool get _canSubmit =>
      _birthDate != null &&
      _effectiveBirthTime != null &&
      _dateError == null &&
      (_timePrecision != TimePrecision.exact || _timeError == null) &&
      _hasTimezone &&
      _hasDst &&
      _tzError == null &&
      _dstError == null;

  bool get _canSave =>
      _canSubmit &&
      _hasValidLat &&
      _hasValidLon &&
      _latError == null &&
      _lonError == null;

  @override
  void dispose() {
    _nameController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _locationQueryController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _tzController.dispose();
    _dstController.dispose();
    super.dispose();
  }

  ChartData _buildChartData() {
    final date = _birthDate!;
    final time = _effectiveBirthTime!;
    // Use DateTime.utc to prevent dateTimeToJdUt's .toUtc() from
    // applying the system timezone a second time on top of our manual offset.
    final localDateTime = DateTime.utc(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    final lat = double.tryParse(_latController.text) ?? 0.0;
    final lon = double.tryParse(_lonController.text) ?? 0.0;
    final utcOffset = double.parse(_tzController.text);
    final dstOffset = double.tryParse(_dstController.text) ?? 0.0;

    return ChartData(
      name: _nameController.text.trim(),
      dateTime: localDateTime,
      birthLocation: GeoLocation(
        city: _locationQueryController.text.trim(),
        latitude: lat,
        longitude: lon,
      ),
      utcOffsetHours: utcOffset,
      dstOffsetHours: dstOffset,
      roddenRating: switch (_timePrecision) {
        TimePrecision.exact => 'A',
        TimePrecision.general => 'C',
        TimePrecision.unknown => 'X',
      },
    );
  }

  void _submit() {
    if (!_canSubmit) return;
    final uncertainty = switch (_timePrecision) {
      TimePrecision.exact => const ExactTime(),
      TimePrecision.general => PeriodTime(
        startHour: _selectedPeriod!.startHour,
        endHour: _selectedPeriod!.endHour,
      ),
      TimePrecision.unknown => const UnknownTime(),
    };
    widget.onSubmit(_buildChartData(), uncertainty);
  }

  Future<void> _saveChart() async {
    if (!_canSave) return;

    try {
      final chartData = _buildChartData();
      final toml = TomlChartFormat.encode(chartData);
      final bytes = Uint8List.fromList(utf8.encode(toml));
      final safeName = chartData.name.replaceAll(RegExp(r'[^\w\-.]'), '_');

      final saved = await saveFileBytes('$safeName.toml', bytes);

      if (saved && mounted) {
        setState(() => _chartSaved = true);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _chartSaved = false);
        });
      }
    } catch (e, s) {
      debugPrint('Error saving chart: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? now,
      firstDate: DateTime(1800),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _dateController.text = _formatDate(picked);
        _dateError = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _birthTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _birthTime = picked;
        _timeController.text = picked.format(context);
        _timeError = null;
      });
    }
  }

  void _onDateTextChanged(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) {
      setState(() {
        _birthDate = null;
        _dateError = null;
      });
      return;
    }

    final result = _tryParseDate(cleaned);
    setState(() {
      _birthDate = result.date;
      _dateError = result.error;
    });
  }

  void _onTimeTextChanged(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) {
      setState(() {
        _birthTime = null;
        _timeError = null;
      });
      return;
    }

    final result = _tryParseTime(cleaned);
    setState(() {
      _birthTime = result.time;
      _timeError = result.error;
    });
  }

  ({DateTime? date, String? error}) _tryParseDate(String text) {
    int? m, d, y;

    // Try M/D/YYYY or M-D-YYYY
    final parts = text.split(RegExp(r'[/\-]'));
    if (parts.length == 3) {
      final a = int.tryParse(parts[0]);
      final b = int.tryParse(parts[1]);
      final c = int.tryParse(parts[2]);
      if (a != null && b != null && c != null) {
        if (a > 31) {
          // yyyy-MM-dd
          y = a;
          m = b;
          d = c;
        } else {
          // MM/DD/YYYY
          m = a;
          d = b;
          y = c;
        }
      }
    }

    // Try ISO fallback
    if (y == null) {
      final iso = DateTime.tryParse(text);
      if (iso != null) return (date: iso, error: null);
      return (date: null, error: 'Use MM/DD/YYYY or YYYY-MM-DD');
    }

    if (m! < 1 || m > 12) return (date: null, error: 'Month must be 1–12');
    if (d! < 1 || d > 31) return (date: null, error: 'Day must be 1–31');
    if (y < 1) return (date: null, error: 'Invalid year');

    // Validate the day is real for this month/year
    final candidate = DateTime(y, m, d);
    if (candidate.month != m || candidate.day != d) {
      return (date: null, error: 'Invalid date for this month');
    }

    return (date: candidate, error: null);
  }

  ({TimeOfDay? time, String? error}) _tryParseTime(String text) {
    final cleaned = text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();

    // Try "H:MM[:SS] AM/PM"
    final amPm = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)$');
    final match = amPm.firstMatch(cleaned);
    if (match != null) {
      var hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final period = match.group(4)!;
      if (hour < 1 || hour > 12) {
        return (time: null, error: 'Hour must be 1–12 with AM/PM');
      }
      if (minute > 59) return (time: null, error: 'Minutes must be 0–59');
      if (period == 'AM' && hour == 12) hour = 0;
      if (period == 'PM' && hour != 12) hour += 12;
      return (time: TimeOfDay(hour: hour, minute: minute), error: null);
    }

    // Try 24h "HH:MM[:SS]"
    final h24 = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$');
    final h24Match = h24.firstMatch(cleaned);
    if (h24Match != null) {
      final hour = int.parse(h24Match.group(1)!);
      final minute = int.parse(h24Match.group(2)!);
      if (hour > 23) return (time: null, error: 'Hour must be 0–23');
      if (minute > 59) return (time: null, error: 'Minutes must be 0–59');
      // Ambiguous: 1:00–12:59 without AM/PM
      if (hour >= 1 && hour <= 12) {
        return (time: null, error: 'Please specify AM or PM');
      }
      return (time: TimeOfDay(hour: hour, minute: minute), error: null);
    }

    return (time: null, error: 'Use HH:MM AM/PM or 24h HH:MM');
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

  void _validateLat(String v) {
    final text = v.trim();
    setState(() {
      if (text.isEmpty) {
        _latError = null;
      } else {
        final val = double.tryParse(text);
        if (val == null) {
          _latError = 'Must be a number';
        } else if (val < -90 || val > 90) {
          _latError = 'Must be −90 to 90';
        } else {
          _latError = null;
        }
      }
    });
  }

  void _validateLon(String v) {
    final text = v.trim();
    setState(() {
      if (text.isEmpty) {
        _lonError = null;
      } else {
        final val = double.tryParse(text);
        if (val == null) {
          _lonError = 'Must be a number';
        } else if (val < -180 || val > 180) {
          _lonError = 'Must be −180 to 180';
        } else {
          _lonError = null;
        }
      }
    });
  }

  void _validateTz(String v) {
    final text = v.trim();
    setState(() {
      if (text.isEmpty) {
        _tzError = null;
      } else {
        final val = double.tryParse(text);
        if (val == null) {
          _tzError = 'Must be a number';
        } else if (val < -12 || val > 14) {
          _tzError = 'Must be −12 to +14';
        } else {
          _tzError = null;
        }
      }
    });
  }

  void _validateDst(String v) {
    final text = v.trim();
    setState(() {
      if (text.isEmpty) {
        _dstError = null;
      } else {
        final val = double.tryParse(text);
        if (val == null) {
          _dstError = 'Must be a number';
        } else {
          _dstError = null;
        }
      }
    });
  }

  Future<void> _searchLocation() async {
    final query = _locationQueryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _searchError = null;
      _searchResults = [];
    });

    try {
      final results = await _placesService.autocomplete(query);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchResults = results;
        if (results.isEmpty) {
          _searchError = 'No results found. Try a different search term.';
        }
      });
    } on PlacesApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError =
            'Could not reach the server. '
            'Please enter coordinates and timezone manually below.';
        if (!_advancedExpanded) _advancedExpanded = true;
      });
    }
  }

  int? _birthDateAsUnixSeconds() {
    if (_birthDate == null || _effectiveBirthTime == null) return null;
    final d = _birthDate!;
    final t = _effectiveBirthTime!;
    return DateTime.utc(
          d.year,
          d.month,
          d.day,
          t.hour,
          t.minute,
        ).millisecondsSinceEpoch ~/
        1000;
  }

  Future<void> _resolvePlace(PlaceAutocompleteResult place) async {
    final snapshotDate = _birthDate;
    final snapshotTime = _birthTime;
    final timestamp = _birthDateAsUnixSeconds();

    setState(() {
      _resolving = true;
      _searchError = null;
      _searchResults = [];
      _locationQueryController.text = place.description;
    });

    try {
      final result = await _placesService.resolve(
        place.placeId,
        timestamp: timestamp,
      );
      if (!mounted) return;
      if (_birthDate != snapshotDate || _birthTime != snapshotTime) return;
      setState(() {
        _resolving = false;
        _latController.text = result.lat.toString();
        _lonController.text = result.lon.toString();
        _tzController.text = result.utcOffsetHours.toString();
        _dstController.text = result.dstOffsetHours.toString();
        _locationQueryController.text = result.formattedAddress;
        _latError = null;
        _lonError = null;
        _tzError = null;
        _dstError = null;
        if (_advancedExpanded) _advancedExpanded = false;
      });
    } on PlacesApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _searchError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _searchError =
            'Could not resolve location. '
            'Please enter coordinates and timezone manually below.';
        if (!_advancedExpanded) _advancedExpanded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black;
    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);
    final mutedColor = color.withValues(alpha: 0.5);
    final accentColor = isDark
        ? const Color(0xFFD4A853)
        : const Color(0xFF8B6F37);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width < 600 ? 16 : 32,
                vertical: 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildOpenChartRow(color, mutedColor),
                  const SizedBox(height: 24),
                  _buildTextField(
                    controller: _nameController,
                    label: 'Name',
                    color: color,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _dateController,
                    label: 'Date of Birth (MM/DD/YYYY)',
                    color: color,
                    errorText: _dateError,
                    onChanged: _onDateTextChanged,
                    suffix: IconButton(
                      onPressed: _pickDate,
                      icon: Icon(
                        Icons.calendar_today,
                        size: 18,
                        color: mutedColor,
                      ),
                      tooltip: 'Pick date',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildTimeCertaintySection(color, mutedColor),
                  const SizedBox(height: 16),
                  _buildLocationField(color, mutedColor),
                  if (_searchError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _searchError!,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (_searchResults.isNotEmpty)
                    _buildSearchResults(color, mutedColor, accentColor),
                  if (_resolving) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: mutedColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Looking up coordinates…',
                          style: TextStyle(color: mutedColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  _buildAdvancedSection(color, mutedColor, accentColor),
                  const SizedBox(height: 28),
                  _buildActions(color, accentColor),
                  if (_chartSaved) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Chart Saved',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildFooter(mutedColor, accentColor),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOpenChartRow(Color color, Color mutedColor) {
    return Align(
      alignment: Alignment.centerRight,
      child: InkWell(
        onTap: widget.onOpenChart,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open, size: 16, color: mutedColor),
              const SizedBox(width: 6),
              Text(
                'Open chart from file',
                style: TextStyle(color: mutedColor, fontSize: 13),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Reads .chtk, .jhd, and .toml format charts.',
                child: Icon(Icons.info_outline, size: 14, color: mutedColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required Color color,
    String? hint,
    String? errorText,
    Widget? suffix,
    void Function(String)? onChanged,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      keyboardType: keyboardType,
      style: TextStyle(color: color, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        errorStyle: const TextStyle(fontSize: 11),
        labelStyle: TextStyle(color: color.withValues(alpha: 0.6)),
        hintStyle: TextStyle(color: color.withValues(alpha: 0.3), fontSize: 14),
        suffixIcon: suffix,
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: color.withValues(alpha: 0.2)),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }

  Widget _buildTimeCertaintySection(Color color, Color mutedColor) {
    const options = [
      (TimePrecision.exact, 'I know the exact time'),
      (TimePrecision.general, 'I know the general time of day'),
      (TimePrecision.unknown, "I don't know the time"),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How accurate is your birth time?',
          style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 12),
        ),
        const SizedBox(height: 4),
        ...options.map(
          (opt) => _buildRadio<TimePrecision>(
            value: opt.$1,
            groupValue: _timePrecision,
            label: opt.$2,
            color: color,
            onChanged: (v) {
              setState(() {
                _timePrecision = v;
                if (v != TimePrecision.exact) _timeError = null;
                if (v != TimePrecision.general) _selectedPeriod = null;
              });
            },
          ),
        ),
        if (_timePrecision == TimePrecision.exact) ...[
          const SizedBox(height: 8),
          _buildTextField(
            controller: _timeController,
            label: 'Time of Birth (HH:MM AM/PM)',
            color: color,
            errorText: _timeError,
            onChanged: _onTimeTextChanged,
            suffix: IconButton(
              onPressed: _pickTime,
              icon: Icon(Icons.access_time, size: 18, color: mutedColor),
              tooltip: 'Pick time',
            ),
          ),
        ],
        if (_timePrecision == TimePrecision.general) ...[
          const SizedBox(height: 8),
          ...BirthPeriod.values.map(
            (period) => _buildRadio<BirthPeriod>(
              value: period,
              groupValue: _selectedPeriod,
              label: '${period.label} (${period.range})',
              color: color,
              onChanged: (v) => setState(() => _selectedPeriod = v),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRadio<T>({
    required T value,
    required T? groupValue,
    required String label,
    required Color color,
    required ValueChanged<T> onChanged,
  }) {
    final selected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected
                  ? color.withValues(alpha: 0.8)
                  : color.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: selected ? 0.8 : 0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationField(Color color, Color mutedColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _locationQueryController,
                label: 'Birth Location',
                color: color,
                hint: 'City or place name',
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 36,
              child: TextButton(
                onPressed:
                    _locationQueryController.text.trim().isNotEmpty &&
                        !_searching &&
                        !_resolving &&
                        _birthDate != null &&
                        _effectiveBirthTime != null &&
                        _dateError == null
                    ? _searchLocation
                    : null,
                style: TextButton.styleFrom(
                  foregroundColor: color.withValues(alpha: 0.8),
                  side: BorderSide(color: color.withValues(alpha: 0.2)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: _searching
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: mutedColor,
                        ),
                      )
                    : const Text('Search', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Powered by Google',
          style: TextStyle(color: mutedColor, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildSearchResults(Color color, Color mutedColor, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 200),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _searchResults.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: color.withValues(alpha: 0.1)),
          itemBuilder: (context, index) {
            final result = _searchResults[index];
            return InkWell(
              onTap: () => _resolvePlace(result),
              borderRadius: BorderRadius.circular(index == 0 ? 8 : 0),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  result.description,
                  style: TextStyle(color: color, fontSize: 13),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAdvancedSection(
    Color color,
    Color mutedColor,
    Color accentColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _advancedExpanded = !_advancedExpanded),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _advancedExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: mutedColor,
                ),
                const SizedBox(width: 4),
                Text(
                  'Advanced: enter timezone and/or location manually',
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _advancedExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _latController,
                        label: 'Latitude (N+, S−)',
                        color: color,
                        hint: 'e.g. 48.8566',
                        errorText: _latError,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: (v) => _validateLat(v),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _lonController,
                        label: 'Longitude (E+, W−)',
                        color: color,
                        hint: 'e.g. 2.3522',
                        errorText: _lonError,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: (v) => _validateLon(v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _tzController,
                        label: 'UTC Offset',
                        color: color,
                        hint: 'e.g. 5.5 or -8',
                        errorText: _tzError,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: (v) => _validateTz(v),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _dstController,
                        label: 'DST Offset',
                        color: color,
                        hint: 'e.g. 1.0 or 0',
                        errorText: _dstError,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: (v) => _validateDst(v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_hasTimezone || !_hasDst)
                  Text(
                    'Timezone and DST offset are required to calculate beings.',
                    style: TextStyle(color: accentColor, fontSize: 12),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Look up your timezone:',
                  style: TextStyle(color: mutedColor, fontSize: 11),
                ),
                const SizedBox(height: 4),
                _buildLink(
                  'timeanddate.com/worldclock/converter',
                  'https://www.timeanddate.com/worldclock/converter.html',
                  mutedColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLink(String label, String url, Color color) {
    return InkWell(
      onTap: () => navigateToUrl(url),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          decoration: TextDecoration.underline,
          decorationColor: color,
        ),
      ),
    );
  }

  Widget _buildActions(Color color, Color accentColor) {
    return Row(
      children: [
        const Spacer(),
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: _canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: accentColor.withValues(alpha: 0.3),
                disabledForegroundColor: Colors.white54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              child: const Text('Meet my Beings'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _canSave ? _saveChart : null,
            icon: Icon(
              Icons.save_alt,
              size: 16,
              color: _canSave
                  ? color.withValues(alpha: 0.7)
                  : color.withValues(alpha: 0.2),
            ),
            label: Text(
              'Save',
              style: TextStyle(
                fontSize: 13,
                color: _canSave
                    ? color.withValues(alpha: 0.7)
                    : color.withValues(alpha: 0.2),
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: _canSave
                    ? color.withValues(alpha: 0.3)
                    : color.withValues(alpha: 0.1),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildFooter(Color mutedColor, Color accentColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Tooltip(
          message: 'Save chart to a .toml file',
          child: Text('', style: TextStyle(color: mutedColor, fontSize: 10)),
        ),
        InkWell(
          onTap: () => navigateToUrl('https://ninthhouse.studio/oacf.html'),
          child: Text(
            'OACF format spec',
            style: TextStyle(
              color: accentColor.withValues(alpha: 0.6),
              fontSize: 10,
              decoration: TextDecoration.underline,
              decorationColor: accentColor.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }
}
