import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'navigate.dart' if (dart.library.js_interop) 'navigate_web.dart';
import 'file_util.dart' if (dart.library.js_interop) 'file_util_web.dart';

import 'astro/being_uncertainty.dart';
import 'astro/chart_calculator.dart';
import 'astro/ephemeris_service.dart';
import 'astro/swe.dart';
import 'package:charts_dart/charts_dart.dart';
import 'chart_reader.dart';
import 'ui/asset_preloader.dart';
import 'ui/birth_form.dart';
import 'ui/chart_wheel.dart';
import 'ui/account_button.dart';
import 'ui/theme.dart';
import 'api/chart_service.dart';

const _sentryDsn =
    'https://cc5b1def15a852176a16cded3ecfc029@o4511643365933056.ingest.us.sentry.io/4511643385331716';

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      options.tracesSampleRate = 0.2;
      options.environment = const String.fromEnvironment(
        'SENTRY_ENVIRONMENT',
        defaultValue: 'production',
      );
    },
    appRunner: () {
      WidgetsFlutterBinding.ensureInitialized();
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      runApp(const ExploreApp());
    },
  );
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
  bool _waitlistSigned = false;

  late SharedPreferences _prefs;
  late EphemerisService _ephemerisService;
  late ChartCalculator _calculator;

  ChartData? _chartData;
  arrow.Chart? _chart;
  BeingUncertainty? _uncertainty;
  bool _calculating = false;
  int _calcToken = 0;

  User? _user;
  List<SavedChartSummary> _savedCharts = [];
  StreamSubscription<AuthState>? _authSub;
  final ChartService _chartService = ChartService();

  static const _zoomMin = 0.6;
  static const _zoomMax = 1.8;
  static const _zoomStep = 0.1;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await Supabase.initialize(
        url: 'https://brkrnuucfdzuligvttol.supabase.co',
        publishableKey: 'sb_publishable_0G0m4eJ_w5SjhgzDOyvbMg_hJGWQIWZ',
      );
      final results = await Future.wait([
        initSweEphePath(),
        SharedPreferences.getInstance(),
      ]);
      _prefs = results[1] as SharedPreferences;
      _ephemerisService = await createEphemerisService(currentSweEphePath);
      _calculator = ChartCalculator(_ephemerisService);
      _useLight = _prefs.getBool('useLight') ?? false;
      _zoom = _prefs.getDouble('zoom') ?? 1.0;
      _waitlistSigned = _prefs.getBool('waitlist_signed') ?? false;
      _user = Supabase.instance.client.auth.currentUser;
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (!mounted) return;
        final user = data.session?.user;
        setState(() => _user = user);
        if (user != null) {
          _refreshSavedCharts();
        } else {
          setState(() => _savedCharts = []);
        }
      });
      if (_user != null) unawaited(_refreshSavedCharts());

      if (!mounted) return;
      setState(() => _booted = true);
      dev.log('Boot complete', name: 'APP');
      unawaited(AssetPreloader.precacheStaticAssets(context));

      final chartParam = Uri.base.queryParameters['chart'];
      if (chartParam != null && _user != null) {
        unawaited(_loadSavedChart(chartParam));
      }
    } catch (e, s) {
      dev.log('Boot failed: $e\n$s', name: 'APP');
      await Sentry.captureException(e, stackTrace: s);
      setState(() => _bootError = e.toString());
    }
  }

  void _toggleTheme() {
    setState(() => _useLight = !_useLight);
    _prefs.setBool('useLight', _useLight);
  }

  void _onWaitlistSigned() {
    setState(() => _waitlistSigned = true);
    _prefs.setBool('waitlist_signed', true);
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

  void _newChart() {
    setState(() {
      _chartData = null;
      _chart = null;
      _uncertainty = null;
      _calculating = false;
    });
  }

  Future<void> _refreshSavedCharts() async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return;
    try {
      final charts = await _chartService.list(token);
      if (!mounted) return;
      setState(() => _savedCharts = charts);
    } catch (e) {
      debugPrint('Error fetching saved charts: $e');
    }
  }

  Future<void> _saveChartToServer() async {
    final chartData = _chartData;
    if (chartData == null) return;
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return;

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _SaveChartDialog(initialName: chartData.name),
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      final toml = TomlChartFormat.encode(chartData);
      await _chartService.create(token, name.trim(), toml);
      await _refreshSavedCharts();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Chart "$name" saved')));
      }
    } on ChartApiException catch (e) {
      if (mounted) {
        final msg = e.statusCode == 409
            ? 'Chart limit reached (25). Delete a chart from your account to save more.'
            : 'Error: ${e.message}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _loadSavedChart(String chartId) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return;

    try {
      final toml = await _chartService.fetchToml(token, chartId);
      final chartData = TomlChartFormat.parseString(toml);
      final timeUncertainty = roddenToUncertainty(
        chartData.roddenRating,
        chartData.dateTime.hour,
      );
      await _submitChart(chartData, timeUncertainty);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading chart: $e')));
      }
    }
  }

  Future<void> _saveChart() async {
    final chartData = _chartData;
    if (chartData == null) return;

    final toml = TomlChartFormat.encode(chartData);
    final bytes = Uint8List.fromList(utf8.encode(toml));
    final safeName = chartData.name.replaceAll(RegExp(r'[^\w\-.]'), '_');
    await saveFileBytes('$safeName.toml', bytes);
  }

  Future<void> _submitChart(
    ChartData chartData,
    TimeUncertainty timeUncertainty,
  ) async {
    final token = ++_calcToken;
    try {
      setState(() {
        _chartData = chartData;
        _chart = null;
        _uncertainty = null;
        _calculating = true;
      });

      final chart = await _calculator.calculate(chartData);
      if (!mounted || token != _calcToken) return;
      unawaited(AssetPreloader.precacheChartAssets(context, chart));
      final uncertainty = await computeBeingUncertainty(
        calculator: _calculator,
        chartData: chartData,
        primaryChart: chart,
        uncertainty: timeUncertainty,
      );
      if (!mounted || token != _calcToken) return;
      unawaited(
        AssetPreloader.precacheChartAssets(
          context,
          chart,
          uncertainty: uncertainty,
        ),
      );
      setState(() {
        _chart = chart;
        _uncertainty = uncertainty;
        _calculating = false;
      });
    } catch (e, s) {
      debugPrint('Error calculating chart: $e\n$s');
      if (!mounted || token != _calcToken) return;
      setState(() => _calculating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _openChart() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['toml', 'chtk', 'jhd'],
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

      final timeUncertainty = roddenToUncertainty(
        chartData.roddenRating,
        chartData.dateTime.hour,
      );

      setState(() {
        _chartData = chartData;
        _chart = null;
        _uncertainty = null;
        _calculating = true;
      });

      final chart = await _calculator.calculate(chartData);
      if (!mounted) return;
      unawaited(AssetPreloader.precacheChartAssets(context, chart));
      final uncertainty = await computeBeingUncertainty(
        calculator: _calculator,
        chartData: chartData,
        primaryChart: chart,
        uncertainty: timeUncertainty,
      );
      if (!mounted) return;
      unawaited(
        AssetPreloader.precacheChartAssets(
          context,
          chart,
          uncertainty: uncertainty,
        ),
      );
      setState(() {
        _chart = chart;
        _uncertainty = uncertainty;
        _calculating = false;
      });
    } catch (e, s) {
      debugPrint('Error opening chart: $e\n$s');
      setState(() => _calculating = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bootError != null) {
      return MaterialApp(
        home: Scaffold(body: Center(child: Text('Boot error: $_bootError'))),
      );
    }

    if (!_booted) {
      return MaterialApp(
        theme: immersiveTheme(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      title: 'The Adityas — Explore',
      debugShowCheckedModeBanner: false,
      theme: _useLight ? lightTheme() : immersiveTheme(),
      navigatorObservers: [SentryNavigatorObserver()],
      home: _ExplorePage(
        useLight: _useLight,
        onToggleTheme: _toggleTheme,
        zoom: _zoom,
        onZoomIn: _zoomIn,
        onZoomOut: _zoomOut,
        onOpenChart: _openChart,
        onNewChart: _newChart,
        onSaveChart: _saveChart,
        onSubmitChart: _submitChart,
        chartData: _chartData,
        chart: _chart,
        uncertainty: _uncertainty,
        calculating: _calculating,
        waitlistSigned: _waitlistSigned,
        onWaitlistSigned: _onWaitlistSigned,
        isLoggedIn: _user != null,
        savedCharts: _savedCharts,
        onSaveChartToServer: _saveChartToServer,
        onLoadSavedChart: _loadSavedChart,
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
  final VoidCallback onNewChart;
  final VoidCallback onSaveChart;
  final void Function(ChartData, TimeUncertainty) onSubmitChart;
  final ChartData? chartData;
  final arrow.Chart? chart;
  final BeingUncertainty? uncertainty;
  final bool calculating;
  final bool waitlistSigned;
  final VoidCallback onWaitlistSigned;
  final bool isLoggedIn;
  final List<SavedChartSummary> savedCharts;
  final VoidCallback onSaveChartToServer;
  final void Function(String chartId) onLoadSavedChart;

  const _ExplorePage({
    required this.useLight,
    required this.onToggleTheme,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onOpenChart,
    required this.onNewChart,
    required this.onSaveChart,
    required this.onSubmitChart,
    required this.chartData,
    required this.chart,
    required this.uncertainty,
    required this.calculating,
    required this.waitlistSigned,
    required this.onWaitlistSigned,
    required this.isLoggedIn,
    required this.savedCharts,
    required this.onSaveChartToServer,
    required this.onLoadSavedChart,
  });

  List<Widget> _buildSettingsMenuChildren(BuildContext context) => [
    if (isLoggedIn && chartData != null)
      MenuItemButton(
        onPressed: savedCharts.length >= 25 ? null : onSaveChartToServer,
        leadingIcon: const Icon(Icons.save, size: 20),
        child: Text(
          savedCharts.length >= 25
              ? 'Save Chart (limit reached)'
              : 'Save Chart',
        ),
      ),
    if (isLoggedIn)
      SubmenuButton(
        menuChildren: [
          if (savedCharts.isEmpty)
            const MenuItemButton(
              onPressed: null,
              leadingIcon: Icon(Icons.info_outline, size: 18),
              child: Text('No saved charts'),
            ),
          for (final chart in savedCharts)
            MenuItemButton(
              onPressed: () => onLoadSavedChart(chart.id),
              child: Text(chart.name),
            ),
        ],
        leadingIcon: const Icon(Icons.folder, size: 20),
        child: const Text('My Charts'),
      ),
    if (chartData != null)
      MenuItemButton(
        onPressed: onSaveChart,
        leadingIcon: const Icon(Icons.save_alt, size: 20),
        child: const Text('Download chart file'),
      ),
    MenuItemButton(
      onPressed: onOpenChart,
      leadingIcon: const Icon(Icons.folder_open, size: 20),
      child: const Text('Open Chart'),
    ),
    MenuItemButton(
      onPressed: () => _showAbout(context),
      leadingIcon: const Icon(Icons.info_outline, size: 20),
      child: const Text('About'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final fgColor = Theme.of(context).appBarTheme.foregroundColor;

    final content = Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: TextButton.icon(
            onPressed: () => navigateToUrl('/'),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Home'),
            style: TextButton.styleFrom(foregroundColor: fgColor),
          ),
        ),
        leadingWidth: 120,
        title: chartData != null ? Text(chartData!.name) : null,
        centerTitle: true,
        actions: isMobile
            ? [
                MenuAnchor(
                  builder: (context, controller, child) => IconButton(
                    icon: const Icon(Icons.menu),
                    tooltip: 'Menu',
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                  menuChildren: [
                    MenuItemButton(
                      onPressed: onToggleTheme,
                      leadingIcon: Icon(
                        useLight ? Icons.dark_mode : Icons.light_mode,
                        size: 20,
                      ),
                      child: Text(useLight ? 'Immersive theme' : 'Light theme'),
                    ),
                    if (chartData != null)
                      MenuItemButton(
                        onPressed: onNewChart,
                        leadingIcon: const Icon(Icons.add, size: 20),
                        child: const Text('New Chart'),
                      ),
                    ..._buildSettingsMenuChildren(context),
                  ],
                ),
                const AccountButton(),
              ]
            : [
                if (chartData != null)
                  TextButton.icon(
                    onPressed: onNewChart,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Chart'),
                    style: TextButton.styleFrom(foregroundColor: fgColor),
                  ),
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
                      style: TextStyle(color: fgColor, fontSize: 13),
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
                MenuAnchor(
                  builder: (context, controller, child) => IconButton(
                    icon: const Icon(Icons.settings),
                    tooltip: 'Settings',
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                  menuChildren: _buildSettingsMenuChildren(context),
                ),
                const AccountButton(),
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

  void _showAbout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black;
    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);

    showDialog(
      context: context,
      builder: (context) => Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    Text(
                      'About',
                      style: TextStyle(
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(Icons.close, color: color, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'This is free-as-in-freedom software, licensed under the AGPL-3.0.',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  'https://github.com/ninthhousestudios/adityas-explore',
                  style: TextStyle(
                    color: isDark ? const Color(0xFFD4A855) : Colors.blue[800],
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (calculating) {
      return const Center(child: CircularProgressIndicator());
    }

    if (chartData == null) {
      return BirthForm(onSubmit: onSubmitChart, onOpenChart: onOpenChart);
    }

    if (chart == null) {
      return const Center(child: Text('No chart calculated'));
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(zoom)),
          child: ChartWheel(
            chart: chart!,
            uncertainty: uncertainty,
            waitlistSigned: waitlistSigned,
            onWaitlistSigned: onWaitlistSigned,
          ),
        ),
      ),
    );
  }
}

class _SaveChartDialog extends StatefulWidget {
  final String initialName;

  const _SaveChartDialog({required this.initialName});

  @override
  State<_SaveChartDialog> createState() => _SaveChartDialogState();
}

class _SaveChartDialogState extends State<_SaveChartDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black;
    final cardBg = isDark ? const Color(0xF0151015) : const Color(0xF0F5F1EA);

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Save Chart',
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                autofocus: true,
                style: TextStyle(color: color),
                decoration: InputDecoration(
                  labelText: 'Chart name',
                  labelStyle: TextStyle(color: color.withValues(alpha: 0.7)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: isDark
                          ? const Color(0xFFD4A853)
                          : const Color(0xFF8B6F37),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.of(context).pop(value.trim());
                  }
                },
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: color.withValues(alpha: 0.7)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      final name = _controller.text.trim();
                      if (name.isNotEmpty) {
                        Navigator.of(context).pop(name);
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark
                          ? const Color(0xFFD4A853)
                          : const Color(0xFF8B6F37),
                      foregroundColor: isDark ? Colors.black : Colors.white,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
