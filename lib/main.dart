import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:dio/dio.dart';

import 'models/app_config.dart';
import 'models/task_status.dart';
import 'services/database/database_service.dart';
import 'services/api/alist_api.dart';
import 'services/api/imgbed_api.dart';
import 'services/engine/task_state_machine.dart';
import 'services/engine/download_engine.dart';
import 'services/engine/hash_engine.dart';
import 'services/engine/hf_upload_engine.dart';
import 'services/scheduler/task_scheduler.dart';
import 'services/sync/cloud_sync_service.dart';
import 'services/logging/log_service.dart';
import 'utils/platform_utils.dart';
import 'app.dart';

/// Application-level service container for dependency injection.
///
/// Holds all singleton services and provides them to the widget tree
/// via [Provider].
class AppServices {
  final DatabaseService database;
  final AlistApi alistApi;
  final ImgBedApi imgBedApi;
  final TaskStateMachine stateMachine;
  final TaskScheduler scheduler;
  final CloudSyncService cloudSync;
  final LogService log;

  AppServices._({
    required this.database,
    required this.alistApi,
    required this.imgBedApi,
    required this.stateMachine,
    required this.scheduler,
    required this.cloudSync,
    required this.log,
  });

  /// Initialize all services and run the app.
  static Future<void> initializeAndRun() async {
    // Ensure Flutter binding is initialized
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize logging FIRST so all subsequent operations can log
    final log = LogService.instance;
    await log.init();
    log.info('════════════════════════════════════════');
    log.info('  Alist-To-HF Migrator v1.0.0');
    log.info('  Platform: ${PlatformUtils.platformName}');
    log.info('════════════════════════════════════════');

    // ─── Platform-specific setup ───────────────────────────────────
    if (PlatformUtils.isWindows) {
      log.info('Setting up Windows platform...');
      await _setupWindows();
    }

    if (PlatformUtils.isAndroid) {
      log.info('Setting up Android platform...');
      await _setupAndroid();
    }

    // ─── Initialize database ──────────────────────────────────────
    log.info('Initializing database...');
    final database = DatabaseService.instance;
    await database.init();

    // ─── Load config ──────────────────────────────────────────────
    final config = await database.loadConfig() ?? const AppConfig();

    // ─── Initialize API clients ───────────────────────────────────
    log.info('Initializing API clients...');
    final alistApi = AlistApi(baseUrl: config.alistBaseUrl);
    final imgBedApi = ImgBedApi(
      baseUrl: config.imgBedBaseUrl,
      apiToken: config.imgBedApiToken,
    );

    // ─── Login to Alist if configured ──────────────────────────────
    try {
      if (config.isAlistReady) {
        log.info('Logging into Alist: ${config.alistBaseUrl}');
        final success = await alistApi.login(
          config.alistUsername,
          config.alistPassword,
        );
        if (success) {
          log.info('Alist login successful');
        } else {
          log.warning('Alist login failed — check credentials in Settings');
        }
      } else {
        log.info('Alist not configured — go to Settings to set up');
      }
    } catch (e) {
      log.error('Failed to auto-login to Alist', e);
    }

    // ─── Initialize engines ────────────────────────────────────────
    log.info('Initializing engines...');
    final downloadEngine = DownloadEngine(Dio(), database);
    final hashEngine = HashEngine();
    final hfUploadEngine = HFUploadEngine(imgBedApi, Dio());

    // ─── Initialize state machine ─────────────────────────────────
    log.info('Initializing state machine...');
    final stateMachine = TaskStateMachine(
      db: database,
      alistApi: alistApi,
      imgBedApi: imgBedApi,
      downloadEngine: downloadEngine,
      hashEngine: hashEngine,
      hfUploadEngine: hfUploadEngine,
    );

    // ─── Initialize task scheduler ────────────────────────────────
    log.info('Initializing task scheduler...');
    final scheduler = TaskScheduler(database, imgBedApi, stateMachine);
    scheduler.onLog = (msg) => log.info('[Scheduler] $msg');

    // ─── Initialize cloud sync service ────────────────────────────
    log.info('Initializing cloud sync service...');
    final cloudSync = CloudSyncService(database, alistApi);

    // ─── Smart Start: sync local ↔ cloud ──────────────────────────
    try {
      if (config.isAlistReady) {
        log.info('Running SmartStart sync...');
        final tasks = await cloudSync.smartSync(config);
        log.info('SmartStart complete: ${tasks.length} tasks available');

        // Auto-start scheduler if there are pending tasks
        if (tasks.any((t) =>
            t.status == TaskStatus.pending || t.status.isActive)) {
          log.info(
              'Auto-starting scheduler (pending/active tasks found)');
          await scheduler.start(
            maxConcurrent: config.maxConcurrentTasks,
          );
        }
      }
    } catch (e) {
      log.error('SmartStart sync failed (non-fatal)', e);
    }

    // ─── Create service container ──────────────────────────────────
    final services = AppServices._(
      database: database,
      alistApi: alistApi,
      imgBedApi: imgBedApi,
      stateMachine: stateMachine,
      scheduler: scheduler,
      cloudSync: cloudSync,
      log: log,
    );

    // ─── Run the app ───────────────────────────────────────────────
    log.info('Starting app...');
    runApp(
      MultiProvider(
        providers: [
          Provider<AppServices>.value(value: services),
          Provider<DatabaseService>.value(value: database),
          Provider<AlistApi>.value(value: alistApi),
          Provider<ImgBedApi>.value(value: imgBedApi),
          Provider<TaskScheduler>.value(value: scheduler),
          Provider<CloudSyncService>.value(value: cloudSync),
          Provider<LogService>.value(value: log),
        ],
        child: const AlistHfMigratorApp(),
      ),
    );
  }

  /// Windows-specific setup: window sizing, minimize-to-tray, etc.
  static Future<void> _setupWindows() async {
    try {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = const WindowOptions(
        size: Size(1200, 800),
        minimumSize: Size(800, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        title: 'Alist-To-HF Migrator',
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });

      LogService.instance.info('Windows setup complete (1200x800)');
    } catch (e) {
      LogService.instance.error('Windows setup failed', e);
    }
  }

  /// Android-specific setup: wakelock for background transfers.
  static Future<void> _setupAndroid() async {
    try {
      // Enable wakelock to prevent screen from sleeping during transfers
      await WakelockPlus.enable();
      LogService.instance.info('Android wakelock enabled');
    } catch (e) {
      LogService.instance.error('Android setup failed', e);
    }
  }
}

/// App entry point.
void main() {
  AppServices.initializeAndRun();
}
