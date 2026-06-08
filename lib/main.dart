import 'dart:developer' as dev;

import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'astro/chart_calculator.dart';
import 'astro/ephemeris_service.dart';
import 'astro/swe.dart';
import 'chart_io/chart_data.dart';
import 'chart_io/chart_reader.dart';
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
  bool _booted = false;
  String? _bootError;

  late SharedPreferences _prefs;
  late EphemerisService _ephemerisService;
  late ChartCalculator _calculator;

  ChartData? _chartData;
  arrow.Chart? _chart;
  bool _calculating = false;

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
      debugPrint('Loaded chart: ${chartData.name}');
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
      theme: _useLight ? lightTheme() : immersiveTheme(),
      home: _ExplorePage(
        useLight: _useLight,
        onToggleTheme: _toggleTheme,
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
  final VoidCallback onOpenChart;
  final ChartData? chartData;
  final arrow.Chart? chart;
  final bool calculating;

  const _ExplorePage({
    required this.useLight,
    required this.onToggleTheme,
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
              // TODO: navigate to theadityas.com
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
          IconButton(
            onPressed: onToggleTheme,
            icon: Icon(useLight ? Icons.dark_mode : Icons.light_mode),
            tooltip: useLight ? 'Immersive theme' : 'Light theme',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
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
        child: ChartWheel(chart: chart!),
      ),
    );
  }
}
