import 'package:charts_dart/charts_dart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigate.dart' if (dart.library.js_interop) '../navigate_web.dart';

enum TimePrecision { exact, rough, unknown }

class BirthForm extends StatefulWidget {
  final void Function(ChartData chartData) onSubmit;
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
  // ignore: unused_field — scaffolded for future chart logic (exact/rough/unknown time)
  final TimePrecision _timePrecision = TimePrecision.exact;

  bool _advancedExpanded = false;
  bool _chartSaved = false;

  // Location search state — deferred until API is wired
  bool _searching = false;
  String? _searchError;

  bool get _hasTimezone =>
      _tzController.text.isNotEmpty &&
      double.tryParse(_tzController.text) != null;

  bool get _hasDst => double.tryParse(_dstController.text) != null;

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      _birthDate != null &&
      _birthTime != null &&
      _hasTimezone &&
      _hasDst;

  bool get _canSave =>
      _canSubmit &&
      _latController.text.isNotEmpty &&
      double.tryParse(_latController.text) != null &&
      _lonController.text.isNotEmpty &&
      double.tryParse(_lonController.text) != null;

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
    final time = _birthTime!;
    final localDateTime = DateTime(
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
    );
  }

  void _submit() {
    if (!_canSubmit) return;
    widget.onSubmit(_buildChartData());
  }

  Future<void> _saveChart() async {
    if (!_canSave) return;

    final chartData = _buildChartData();
    final toml = TomlChartFormat.encode(chartData);
    final bytes = Uint8List.fromList(toml.codeUnits);
    final safeName = chartData.name.replaceAll(RegExp(r'[^\w\-.]'), '_');

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save chart',
      fileName: '$safeName.toml',
      bytes: bytes,
    );

    if (result != null && mounted) {
      setState(() => _chartSaved = true);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _chartSaved = false);
      });
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
      });
    }
  }

  void _onDateTextChanged(String value) {
    final parsed = _tryParseDate(value);
    if (parsed != null) {
      setState(() => _birthDate = parsed);
    }
  }

  void _onTimeTextChanged(String value) {
    final parsed = _tryParseTime(value);
    if (parsed != null) {
      setState(() => _birthTime = parsed);
    }
  }

  DateTime? _tryParseDate(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return null;

    // Try M/d/yyyy (US format from date picker)
    final slashParts = cleaned.split('/');
    if (slashParts.length == 3) {
      final m = int.tryParse(slashParts[0]);
      final d = int.tryParse(slashParts[1]);
      final y = int.tryParse(slashParts[2]);
      if (m != null && d != null && y != null) {
        return DateTime(y, m, d);
      }
    }

    // Try yyyy-MM-dd (ISO)
    final isoParsed = DateTime.tryParse(cleaned);
    if (isoParsed != null) return isoParsed;

    return null;
  }

  TimeOfDay? _tryParseTime(String text) {
    final cleaned = text.trim().toUpperCase();
    if (cleaned.isEmpty) return null;

    // Try "H:MM AM/PM" format (MaterialLocalizations default)
    final amPm = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$');
    final match = amPm.firstMatch(cleaned);
    if (match != null) {
      var hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final period = match.group(3)!;
      if (period == 'AM' && hour == 12) hour = 0;
      if (period == 'PM' && hour != 12) hour += 12;
      if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
        return TimeOfDay(hour: hour, minute: minute);
      }
    }

    // Try 24h "HH:MM"
    final h24 = RegExp(r'^(\d{1,2}):(\d{2})$');
    final h24Match = h24.firstMatch(cleaned);
    if (h24Match != null) {
      final hour = int.parse(h24Match.group(1)!);
      final minute = int.parse(h24Match.group(2)!);
      if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
        return TimeOfDay(hour: hour, minute: minute);
      }
    }

    return null;
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

  Future<void> _searchLocation() async {
    final query = _locationQueryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _searchError = null;
    });

    // TODO: Wire to api.84beings.com/v1/places/autocomplete
    // For now, show a placeholder message.
    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      setState(() {
        _searching = false;
        _searchError =
            'Location search is not yet available. '
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
              padding: const EdgeInsets.all(32),
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
                    label: 'Date of Birth',
                    color: color,
                    hint: 'M/D/YYYY',
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
                  _buildTextField(
                    controller: _timeController,
                    label: 'Time of Birth',
                    color: color,
                    hint: 'H:MM AM/PM',
                    onChanged: _onTimeTextChanged,
                    suffix: IconButton(
                      onPressed: _pickTime,
                      icon: Icon(
                        Icons.access_time,
                        size: 18,
                        color: mutedColor,
                      ),
                      tooltip: 'Pick time',
                    ),
                  ),
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
                        !_searching
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
                        label: 'Latitude',
                        color: color,
                        hint: 'e.g. 48.8566',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _lonController,
                        label: 'Longitude',
                        color: color,
                        hint: 'e.g. 2.3522',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: (_) => setState(() {}),
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
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _dstController,
                        label: 'DST Offset',
                        color: color,
                        hint: 'e.g. 1.0 or 0',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: (_) => setState(() {}),
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
                const SizedBox(height: 2),
                _buildLink(
                  'timeanddate.com/worldclock',
                  'https://www.timeanddate.com/worldclock/',
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
