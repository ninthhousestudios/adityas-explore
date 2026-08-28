import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:arrow_core/arrow_core.dart' as arrow;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'navigate.dart' if (dart.library.js_interop) 'navigate_web.dart';
import 'file_util.dart';
import 'observability.dart';

import 'astro/being_uncertainty.dart';
import 'astro/chart_calculator.dart';
import 'astro/ephemeris_service.dart';
import 'astro/swe.dart';
import 'package:charts_dart/charts_dart.dart';
import 'chart_reader.dart';
import 'ui/asset_preloader.dart';
import 'ui/birth_form.dart';
import 'ui/boot_error_screen.dart';
import 'ui/chart_wheel.dart';
import 'ui/account_button.dart';
import 'ui/theme.dart';
import 'ui/tokens.dart';
import 'api/chart_service.dart';
import 'export/chart_pdf.dart';
import 'state/auth.dart';
import 'state/backend.dart';

const _sentryDsn =
    'https://0decc8fd44d76a8374d3dc45f055f584@o4511643365933056.ingest.us.sentry.io/4511643403878400';

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options
        ..dsn = _sentryDsn
        ..tracesSampleRate = 0.2
        ..environment = const String.fromEnvironment(
          'SENTRY_ENVIRONMENT',
          defaultValue: 'production',
        );
      // Content-free observability (I19, bug #4): no PII, no request/response
      // bodies, and a beforeSend scrub belt — see observability.dart.
      applyContentFreeSentryPolicy(options);
    },
    appRunner: () {
      WidgetsFlutterBinding.ensureInitialized();
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      runApp(const ProviderScope(child: ExploreApp()));
    },
  );
}

class ExploreApp extends ConsumerStatefulWidget {
  const ExploreApp({
    super.key,
    this.authOptions = const FlutterAuthClientOptions(),
  });

  /// Auth client configuration handed to [Supabase.initialize] during boot.
  ///
  /// Production uses the defaults. Widget tests pass
  /// `autoRefreshToken: false` so gotrue does not start its periodic refresh
  /// ticker, and `detectSessionInUri: false` so no deep-link observer is
  /// attached — both outlive the test and fail it on pending timers.
  final FlutterAuthClientOptions authOptions;

  @override
  ConsumerState<ExploreApp> createState() => _ExploreAppState();
}

class _ExploreAppState extends ConsumerState<ExploreApp> {
  ExploreTheme _theme = ExploreTheme.immersive;
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
  bool _exportingPdf = false;
  int _calcToken = 0;

  List<SavedChartSummary> _savedCharts = [];
  // Bumped on every auth transition (see the authProvider listener in build).
  // _refreshSavedCharts captures it and drops a late list response whose epoch
  // is stale — otherwise an in-flight list for a signed-out/previous user could
  // repopulate or overwrite _savedCharts after an auth change (cross-account
  // leak). Same last-write-wins guard as _calcToken, keyed on auth instead.
  int _authEpoch = 0;
  // The shared authenticated backend client (see state/backend.dart). Read
  // lazily from the provider so chart CRUD and the entitlement fetch use one
  // instance. Safe pre-boot: construction touches no Supabase.instance, only
  // the token closure does (at request time, always post-boot).
  ChartService get _chartService => ref.read(chartServiceProvider);
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();

  static const _zoomMin = 0.6;
  static const _zoomMax = 1.8;
  static const _zoomStep = 0.1;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  void _showSnackBar(String message) {
    _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _boot() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await Supabase.initialize(
        url: 'https://brkrnuucfdzuligvttol.supabase.co',
        publishableKey: 'sb_publishable_0G0m4eJ_w5SjhgzDOyvbMg_hJGWQIWZ',
        authOptions: widget.authOptions,
      );
      final results = await Future.wait([
        initSweEphePath(),
        SharedPreferences.getInstance(),
      ]);
      _prefs = results[1] as SharedPreferences;
      _ephemerisService = await createEphemerisService(currentSweEphePath);
      _calculator = ChartCalculator(_ephemerisService);
      _theme = readThemePreference(_prefs);
      _zoom = _prefs.getDouble('zoom') ?? 1.0;
      _waitlistSigned = _prefs.getBool('waitlist_signed') ?? false;
      final auth = Supabase.instance.client.auth;
      // Validate stored session before the app subscribes (via authProvider) —
      // a stale refresh token causes an uncaught async throw from the SDK's
      // background refresh. This stays boot logic; the ongoing subscription
      // now lives in authProvider.
      if (auth.currentSession != null) {
        try {
          await auth.refreshSession();
        } on AuthApiException catch (e) {
          dev.log('Stale session cleared: ${e.code}', name: 'AUTH');
          await auth.signOut();
        }
      }
      // Initial saved-charts load if already signed in. Later sign-in/sign-out
      // is handled by the ref.listen(authProvider) in build.
      if (auth.currentUser != null) unawaited(_refreshSavedCharts());

      if (!mounted) return;
      setState(() => _booted = true);
      dev.log('Boot complete', name: 'APP');
      unawaited(AssetPreloader.precacheStaticAssets(context));

      final chartParam = Uri.base.queryParameters['chart'];
      if (chartParam != null && auth.currentUser != null) {
        unawaited(_loadSavedChart(chartParam));
      }
    } catch (e, s) {
      dev.log('Boot failed: $e\n$s', name: 'APP');
      await Sentry.captureException(e, stackTrace: s);
      // Report first, then bail if we were disposed — the failure is worth
      // capturing either way, but the await above means dispose can land
      // between it and the setState.
      if (!mounted) return;
      setState(() => _bootError = e.toString());
    }
  }

  void _retryBoot() {
    if (kIsWeb) {
      // On web, initializeWasm is single-flight and caches the *failed*
      // future, so re-running _boot() in-process won't re-fetch the wasm.
      // A hard page reload is the only reliable recovery.
      reloadApp();
      return;
    }
    setState(() {
      _bootError = null;
      _booted = false;
    });
    _boot();
  }

  void _toggleTheme() {
    setState(() {
      _theme = _theme == ExploreTheme.light
          ? ExploreTheme.immersive
          : ExploreTheme.light;
    });
    unawaited(writeThemePreference(_prefs, _theme));
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
    final epoch = _authEpoch;
    try {
      final charts = await _chartService.list();
      if (!mounted || epoch != _authEpoch) return;
      setState(() => _savedCharts = charts);
    } on ChartApiException catch (e) {
      if (e.statusCode == 401 && mounted && epoch == _authEpoch) {
        setState(() => _savedCharts = []);
      }
      debugPrint('Error fetching saved charts: $e');
    } catch (e) {
      debugPrint('Error fetching saved charts: $e');
    }
  }

  Future<void> _saveChartToServer() async {
    final chartData = _chartData;
    if (chartData == null) return;

    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null) return;
    final name = await showDialog<String>(
      context: dialogContext,
      builder: (ctx) => _SaveChartDialog(initialName: chartData.name),
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      final toml = TomlChartFormat.encode(chartData);
      await _chartService.create(name.trim(), toml);
      await _refreshSavedCharts();
      if (mounted) _showSnackBar('Chart "$name" saved');
    } on ChartApiException catch (e) {
      if (mounted) {
        _showSnackBar(
          e.statusCode == 401
              ? 'Session expired — please sign in again'
              : e.statusCode == 409
              ? 'Chart limit reached (25). Delete a chart from your account to save more.'
              : 'Error: ${e.message}',
        );
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error saving chart: $e');
    }
  }

  Future<void> _loadSavedChart(String chartId) async {
    try {
      final toml = await _chartService.fetchToml(chartId);
      final chartData = TomlChartFormat.parseString(toml);
      final timeUncertainty = roddenToUncertainty(
        chartData.roddenRating,
        chartData.dateTime.hour,
      );
      await _submitChart(chartData, timeUncertainty);
    } on ChartApiException catch (e) {
      if (mounted) {
        _showSnackBar(
          e.statusCode == 401
              ? 'Session expired — please sign in again'
              : 'Error loading chart: $e',
        );
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error loading chart: $e');
    }
  }

  Future<void> _saveChart() async {
    final chartData = _chartData;
    if (chartData == null) return;

    final toml = TomlChartFormat.encode(chartData);
    final bytes = Uint8List.fromList(utf8.encode(toml));
    await saveFileBytes('${chartFileStem(chartData.name)}.toml', bytes);
  }

  Future<void> _downloadPdf() async {
    final chart = _chart;
    final chartData = _chartData;
    if (chart == null || _exportingPdf) return;

    setState(() => _exportingPdf = true);
    try {
      final bytes = await buildChartPdf(
        chart: chart,
        chartName: chartData?.name,
        uncertainty: _uncertainty,
      );
      if (!mounted) return;
      await saveFileBytes('${chartFileStem(chartData?.name)}-chart.pdf', bytes);
    } on Exception catch (e) {
      if (mounted) _showSnackBar('Error exporting PDF: $e');
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
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
      _showSnackBar('Error: $e');
    }
  }

  Future<void> _openChart() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['toml', 'chtk', 'jhd'],
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();

      final chartData = ChartReader.read(file.name, bytes);
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
      if (mounted) _showSnackBar('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bootError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: immersiveTheme(),
        home: BootErrorScreen(onRetry: _retryBoot),
      );
    }

    if (!_booted) {
      return MaterialApp(
        theme: immersiveTheme(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    // Single auth reaction: refresh saved charts on sign-in, clear on sign-out.
    // The initial load lives in _boot; this is only read post-boot, so
    // authProvider's `Supabase.instance` access is always valid here.
    ref.listen<User?>(authProvider, (previous, user) {
      // Invalidate any in-flight _refreshSavedCharts from the previous auth
      // state before reacting, so a late list response can't clobber this one.
      _authEpoch++;
      if (user != null) {
        _refreshSavedCharts();
      } else {
        setState(() => _savedCharts = []);
      }
    });

    return MaterialApp(
      title: 'The Adityas — Explore',
      debugShowCheckedModeBanner: false,
      theme: _theme == ExploreTheme.light ? lightTheme() : immersiveTheme(),
      scaffoldMessengerKey: _messengerKey,
      navigatorKey: _navigatorKey,
      navigatorObservers: [SentryNavigatorObserver()],
      home: _ExplorePage(
        useLight: _theme == ExploreTheme.light,
        onToggleTheme: _toggleTheme,
        zoom: _zoom,
        onZoomIn: _zoomIn,
        onZoomOut: _zoomOut,
        onOpenChart: _openChart,
        onNewChart: _newChart,
        onSaveChart: _saveChart,
        onDownloadPdf: _downloadPdf,
        onSubmitChart: _submitChart,
        chartData: _chartData,
        chart: _chart,
        uncertainty: _uncertainty,
        calculating: _calculating,
        waitlistSigned: _waitlistSigned,
        onWaitlistSigned: _onWaitlistSigned,
        hasChart: _chartData != null,
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
  final VoidCallback onDownloadPdf;
  final void Function(ChartData, TimeUncertainty) onSubmitChart;
  final ChartData? chartData;
  final arrow.Chart? chart;
  final BeingUncertainty? uncertainty;
  final bool calculating;
  final bool waitlistSigned;
  final VoidCallback onWaitlistSigned;
  final bool hasChart;
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
    required this.onDownloadPdf,
    required this.onSubmitChart,
    required this.chartData,
    required this.chart,
    required this.uncertainty,
    required this.calculating,
    required this.waitlistSigned,
    required this.onWaitlistSigned,
    required this.hasChart,
    required this.savedCharts,
    required this.onSaveChartToServer,
    required this.onLoadSavedChart,
  });

  Widget _accountButton() => AccountButton(
    hasChart: hasChart,
    savedCharts: savedCharts,
    onSaveChartToServer: onSaveChartToServer,
    onLoadSavedChart: onLoadSavedChart,
  );

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
                PopupMenuButton<String>(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Menu',
                  position: PopupMenuPosition.under,
                  onSelected: (value) {
                    switch (value) {
                      case 'theme':
                        onToggleTheme();
                      case 'new_chart':
                        onNewChart();
                      case 'save_chart':
                        onSaveChart();
                      case 'download_pdf':
                        onDownloadPdf();
                      case 'open_chart':
                        onOpenChart();
                      case 'about':
                        _showAbout(context);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'theme',
                      child: Row(
                        children: [
                          Icon(
                            useLight ? Icons.dark_mode : Icons.light_mode,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(useLight ? 'Immersive theme' : 'Light theme'),
                        ],
                      ),
                    ),
                    if (chartData != null)
                      const PopupMenuItem(
                        value: 'new_chart',
                        child: Row(
                          children: [
                            Icon(Icons.add, size: 20),
                            SizedBox(width: 12),
                            Text('New Chart'),
                          ],
                        ),
                      ),
                    if (chartData != null)
                      const PopupMenuItem(
                        value: 'save_chart',
                        child: Row(
                          children: [
                            Icon(Icons.save_alt, size: 20),
                            SizedBox(width: 12),
                            Text('Download chart file'),
                          ],
                        ),
                      ),
                    if (chart != null)
                      const PopupMenuItem(
                        value: 'download_pdf',
                        child: Row(
                          children: [
                            Icon(Icons.picture_as_pdf, size: 20),
                            SizedBox(width: 12),
                            Text('Download PDF'),
                          ],
                        ),
                      ),
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
                    const PopupMenuItem(
                      value: 'about',
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 20),
                          SizedBox(width: 12),
                          Text('About'),
                        ],
                      ),
                    ),
                  ],
                ),
                _accountButton(),
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
                PopupMenuButton<String>(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings',
                  position: PopupMenuPosition.under,
                  onSelected: (value) {
                    if (value == 'save_chart') onSaveChart();
                    if (value == 'download_pdf') onDownloadPdf();
                    if (value == 'open_chart') onOpenChart();
                    if (value == 'about') _showAbout(context);
                  },
                  itemBuilder: (context) => [
                    if (chartData != null)
                      const PopupMenuItem(
                        value: 'save_chart',
                        child: Row(
                          children: [
                            Icon(Icons.save_alt, size: 20),
                            SizedBox(width: 12),
                            Text('Download chart file'),
                          ],
                        ),
                      ),
                    if (chart != null)
                      const PopupMenuItem(
                        value: 'download_pdf',
                        child: Row(
                          children: [
                            Icon(Icons.picture_as_pdf, size: 20),
                            SizedBox(width: 12),
                            Text('Download PDF'),
                          ],
                        ),
                      ),
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
                    const PopupMenuItem(
                      value: 'about',
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 20),
                          SizedBox(width: 12),
                          Text('About'),
                        ],
                      ),
                    ),
                  ],
                ),
                _accountButton(),
              ],
      ),
      body: _buildBody(context),
    );

    // Keep a constant tree shape across themes. If the light branch returned a
    // bare `content` and the dark branch a `Stack([Image, content])`, toggling
    // the theme would change the child widget type under this element and tear
    // down the whole subtree — including `_ChartWheelState`, resetting its
    // layout mode to Explore and closing the chat box. Holding the Stack shape
    // stable (only the background slot's child swaps) preserves that State.
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: useLight
              ? const _LightCanvas()
              : Image.asset(
                  'assets/images/hero-dawn-temple_seed4830.webp',
                  fit: BoxFit.cover,
                ),
        ),
        content,
      ],
    );
  }

  void _showAbout(BuildContext context) {
    final t = context.tokens;
    final color = t.ink;
    final cardBg = t.cardBg;

    showDialog<void>(
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
                        fontFamily: t.serifFamily,
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
                  style: TextStyle(color: t.gold, fontSize: 13),
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
            chartData: chartData,
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
    final t = context.tokens;
    final color = t.ink;
    final cardBg = t.cardBg;

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
                    borderSide: BorderSide(color: t.gold),
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
                      backgroundColor: t.gold,
                      foregroundColor: t.onGold,
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

/// The light-mode page canvas. Immersive mode fills the background slot with
/// the temple photo; light mode fills it with this — a warm paper field rather
/// than a flat cream slab. The scaffold's cream shows through; this layers a
/// faint grain over it so it reads as paper, not a `#F5F1EA` fill.
class _LightCanvas extends StatelessWidget {
  const _LightCanvas();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/paper-grain.png'),
          repeat: ImageRepeat.repeat,
          opacity: 0.035,
        ),
      ),
    );
  }
}
