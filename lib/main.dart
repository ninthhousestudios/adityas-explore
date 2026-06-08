import 'dart:developer' as dev;

import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as html;

import 'astro/chart_calculator.dart';
import 'astro/ephemeris_service.dart';
import 'astro/swe.dart';
import 'package:charts_dart/charts_dart.dart';
import 'chart_reader.dart';
import 'ui/chart_wheel.dart';
import 'ui/theme.dart';

void main() {
  runApp(const ExploreApp());
}

class ExploreApp extends StatefulWidget {
  const ExploreApp({super.key});

  @override
  State<ExploreApp> createState() => _ExploreAppState();
}

class _ExploreAppState extends State<ExploreApp> {
  bool _useLight = false;
  double _zoom = 1.0;
  bool _booted = false;
  String? _bootError;

  late SharedPreferences _prefs;
  late EphemerisService _ephemerisService;
  late ChartCalculator _calculator;

  ChartData? _chartData;
  arrow.Chart? _chart;
  bool _calculating = false;

  static const _zoomMin = 0.6;
  static const _zoomMax = 1.8;
  static const _zoomStep = 0.1;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final results = await Future.wait([
        initSweEphePath(),
        SharedPreferences.getInstance(),
      ]);
      _prefs = results[1] as SharedPreferences;
      _ephemerisService = await createEphemerisService(currentSweEphePath);
      _calculator = ChartCalculator(_ephemerisService);
      _useLight = _prefs.getBool('useLight') ?? false;
      _zoom = _prefs.getDouble('zoom') ?? 1.0;
      setState(() => _booted = true);
      dev.log('Boot complete', name: 'APP');
    } catch (e, s) {
      dev.log('Boot failed: $e\n$s', name: 'APP');
      setState(() => _bootError = e.toString());
    }
  }

  void _toggleTheme() {
    setState(() => _useLight = !_useLight);
    _prefs.setBool('useLight', _useLight);
  }

  void _zoomIn() {
    if (_zoom >= _zoomMax) return;
    setState(() => _zoom = (_zoom + _zoomStep).clamp(_zoomMin, _zoomMax));
    _prefs.setDouble('zoom', _zoom);
  }

  void _zoomOut() {
    if (_zoom <= _zoomMin) return;
    setState(() => _zoom = (_zoom - _zoomStep).clamp(_zoomMin, _zoomMax));
    _prefs.setDouble('zoom', _zoom);
  }

  Future<void> _openChart() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['toml', 'chtk'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      if (file.bytes == null) {
        debugPrint('No bytes available for ${file.name}');
        return;
      }

      final chartData = ChartReader.read(file.name, file.bytes!);
      debugPrint('Loaded chart: ${chartData.name} (${file.name})');
      debugPrint('  Date: ${chartData.dateTime}');
      debugPrint('  UTC: ${chartData.utcDateTime}');
      debugPrint('  Location: ${chartData.birthLocation}');
      debugPrint('  UTC offset: ${chartData.utcOffsetHours}h');

      setState(() {
        _chartData = chartData;
        _chart = null;
        _calculating = true;
      });

      final chart = await _calculator.calculate(chartData);
      setState(() {
        _chart = chart;
        _calculating = false;
      });
    } catch (e, s) {
      debugPrint('Error opening chart: $e\n$s');
      setState(() => _calculating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bootError != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Boot error: $_bootError')),
        ),
      );
    }

    if (!_booted) {
      return MaterialApp(
        theme: immersiveTheme(),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      title: 'The Adityas — Explore',
      debugShowCheckedModeBanner: false,
      theme: _useLight ? lightTheme() : immersiveTheme(),
      home: _ExplorePage(
        useLight: _useLight,
        onToggleTheme: _toggleTheme,
        zoom: _zoom,
        onZoomIn: _zoomIn,
        onZoomOut: _zoomOut,
        onOpenChart: _openChart,
        chartData: _chartData,
        chart: _chart,
        calculating: _calculating,
      ),
    );
  }
}

class _ExplorePage extends StatelessWidget {
  final bool useLight;
  final VoidCallback onToggleTheme;
  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onOpenChart;
  final ChartData? chartData;
  final arrow.Chart? chart;
  final bool calculating;

  const _ExplorePage({
    required this.useLight,
    required this.onToggleTheme,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onOpenChart,
    required this.chartData,
    required this.chart,
    required this.calculating,
  });

  @override
  Widget build(BuildContext context) {
    final content = Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: TextButton.icon(
            onPressed: () {
              if (kIsWeb) {
                html.window.location.href = '/adityas-live/';
              }
            },
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Home'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
            ),
          ),
        ),
        leadingWidth: 120,
        title: chartData != null ? Text(chartData!.name) : null,
        centerTitle: true,
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onZoomOut,
                icon: const Icon(Icons.remove, size: 18),
                tooltip: 'Zoom out',
                visualDensity: VisualDensity.compact,
              ),
              Text(
                '${(zoom * 100).round()}%',
                style: TextStyle(
                  color: Theme.of(context).appBarTheme.foregroundColor,
                  fontSize: 13,
                ),
              ),
              IconButton(
                onPressed: onZoomIn,
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Zoom in',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          IconButton(
            onPressed: onToggleTheme,
            icon: Icon(useLight ? Icons.dark_mode : Icons.light_mode),
            tooltip: useLight ? 'Immersive theme' : 'Light theme',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            position: PopupMenuPosition.under,
            onSelected: (value) {
              if (value == 'open_chart') onOpenChart();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'open_chart',
                child: Row(
                  children: [
                    Icon(Icons.folder_open, size: 20),
                    SizedBox(width: 12),
                    Text('Open Chart'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(context),
    );

    if (useLight) return content;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/hero-dawn-temple_seed4830.webp',
          fit: BoxFit.cover,
        ),
        content,
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (calculating) {
      return const Center(child: CircularProgressIndicator());
    }

    if (chartData == null) {
      return Center(
        child: Text(
          'Open a chart from the settings menu',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    if (chart == null) {
      return const Center(child: Text('No chart calculated'));
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(zoom),
          ),
          child: ChartWheel(chart: chart!),
        ),
      ),
    );
  }
}
