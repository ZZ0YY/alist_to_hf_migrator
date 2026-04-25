import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/migration_task.dart';
import '../../models/app_config.dart';
import '../database/database_service.dart';
import '../api/alist_api.dart';
import '../logging/log_service.dart';

/// Cloud sync service that serializes/deserializes task state between
/// local DB and Alist cloud storage.
///
/// Uses Alist's file upload API to store a JSON snapshot of all tasks
/// at `{syncBasePath}/tasks.json`. This enables cross-device sync so
/// that reinstalling on a new phone can restore task state from the cloud.
class CloudSyncService {
  final DatabaseService _db;
  final AlistApi _alistApi;

  CloudSyncService(this._db, this._alistApi);

  // ─── Push ──────────────────────────────────────────────────────────

  /// Push local tasks to cloud via Alist form upload.
  ///
  /// Serializes all tasks as JSON array and uploads to `syncBasePath/tasks.json`.
  Future<void> pushToCloud(AppConfig config) async {
    final syncBasePath = config.syncBasePath;

    try {
      // 1. Ensure the sync directory exists on Alist
      await _alistApi.ensureDirectory(syncBasePath);
      LogService.instance.info('Ensured sync directory: $syncBasePath');

      // 2. Get all tasks from local DB
      final tasks = await _db.getAllTasks();

      // 3. Serialize to JSON (use toCloudJson() — excludes tmpLocalPath)
      final jsonArray = tasks.map((t) => t.toCloudJson()).toList();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonArray);

      // 4. Write JSON to a temp file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, 'tasks_sync.json'));
      await tempFile.writeAsString(jsonString);
      LogService.instance
          .info('Serialized ${tasks.length} tasks to temp file (${tempFile.lengthSync()} bytes)');

      // 5. Upload to Alist via _alistApi.uploadFile()
      final remotePath = '$syncBasePath/tasks.json';
      final success =
          await _alistApi.uploadFile(remotePath, tempFile);

      if (success) {
        LogService.instance.info('Successfully pushed ${tasks.length} tasks to cloud');
      } else {
        LogService.instance.error('Failed to push tasks to cloud');
      }

      // 6. Clean up temp file
      try {
        await tempFile.delete();
      } catch (_) {
        // Best effort cleanup
      }
    } catch (e, st) {
      LogService.instance.error('Error pushing to cloud', e, st);
      rethrow;
    }
  }

  // ─── Pull ──────────────────────────────────────────────────────────

  /// Pull tasks from cloud.
  ///
  /// Downloads `tasks.json` from Alist, parses, and returns the list.
  /// Used when local DB is empty (e.g. cloud phone reinstall scenario).
  /// The **caller** handles DB insertion to allow deduplication.
  Future<List<MigrationTask>> pullFromCloud(AppConfig config) async {
    final syncBasePath = config.syncBasePath;

    try {
      // 1. Get file info to obtain the raw download URL
      final remotePath = '$syncBasePath/tasks.json';
      final fileInfo = await _alistApi.getFileInfo(remotePath);

      if (fileInfo.rawUrl.isEmpty) {
        LogService.instance
            .warning('No download URL available for $remotePath');
        return [];
      }

      final downloadUrl = fileInfo.rawUrl;
      LogService.instance.info('Got cloud download URL: $downloadUrl');

      // 2. Download the file using a fresh Dio instance
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ));

      final tempDir = await getTemporaryDirectory();
      final localPath = p.join(tempDir.path, 'tasks_cloud.json');
      await dio.download(downloadUrl, localPath);

      // 3. Read and parse JSON array
      final file = File(localPath);
      final contents = await file.readAsString();
      final List<dynamic> jsonArray = json.decode(contents) as List<dynamic>;

      // 4. Convert each item to MigrationTask using fromCloudJson()
      final tasks = jsonArray
          .map((item) =>
              MigrationTask.fromCloudJson(item as Map<String, dynamic>))
          .toList();

      LogService.instance.info('Pulled ${tasks.length} tasks from cloud');

      // 5. Clean up temp file
      try {
        await file.delete();
      } catch (_) {}

      // 6. Return the list (caller handles DB insertion)
      return tasks;
    } catch (e, st) {
      LogService.instance.error('Error pulling from cloud', e, st);
      return [];
    }
  }

  // ─── Single-task push ─────────────────────────────────────────────

  /// Push a single task status update to cloud (for strong sync).
  ///
  /// Called at strong sync points: PENDING → HASHING, DOWNLOADING → HF_UPLOADING,
  /// DONE, and FAILED. Re-uploads the full `tasks.json` for simplicity
  /// (Alist does not support partial file patch).
  Future<void> pushTaskUpdate(AppConfig config, MigrationTask task) async {
    try {
      // Ensure the task is up-to-date in local DB first
      await _db.updateTask(task);

      // Re-upload the full tasks.json
      await pushToCloud(config);
      LogService.instance
          .debug('Pushed task update for ${task.fileName} (${task.status.value})');
    } catch (e) {
      // Don't block the task pipeline on sync failure
      LogService.instance.error('Failed to push task update for ${task.id}', e);
    }
  }

  // ─── Log sync ──────────────────────────────────────────────────────

  /// Sync log file to cloud.
  ///
  /// Uploads the given log file to `{syncBasePath}/logs/` with a
  /// date-based filename like `migration_20240101_120000.log`.
  Future<void> pushLogToCloud(AppConfig config, File logFile) async {
    final syncBasePath = config.syncBasePath;

    try {
      if (!logFile.existsSync()) {
        LogService.instance
            .warning('Log file does not exist: ${logFile.path}');
        return;
      }

      // Ensure logs directory exists on Alist
      final logsDir = '$syncBasePath/logs';
      await _alistApi.ensureDirectory(logsDir);

      // Build date-based filename
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'migration_$now.log';
      final remotePath = '$logsDir/$fileName';

      // Upload
      final success =
          await _alistApi.uploadFile(remotePath, logFile);
      if (success) {
        LogService.instance.info('Pushed log to cloud: $remotePath');
      } else {
        LogService.instance.warning('Failed to push log to cloud');
      }
    } catch (e) {
      LogService.instance.error('Error pushing log to cloud', e);
    }
  }

  // ─── Smart start sync ─────────────────────────────────────────────

  /// Smart-start sync: decide whether to push local or pull from cloud.
  ///
  /// Returns the list of tasks to use (local or cloud-restored).
  /// - If local DB has tasks → use local, push to cloud
  /// - If local DB is empty → pull from cloud
  /// - If both empty → return empty list
  Future<List<MigrationTask>> smartSync(AppConfig config) async {
    final localTasks = await _db.getAllTasks();

    if (localTasks.isNotEmpty) {
      // Local DB has data — push to cloud as source of truth
      LogService.instance.info(
          'SmartSync: ${localTasks.length} local tasks found, pushing to cloud');
      try {
        await pushToCloud(config);
      } catch (e) {
        LogService.instance
            .warning('SmartSync: push to cloud failed (non-fatal): $e');
      }
      return localTasks;
    }

    // Local DB is empty — try pulling from cloud
    LogService.instance.info('SmartSync: local DB empty, pulling from cloud');
    final cloudTasks = await pullFromCloud(config);

    if (cloudTasks.isNotEmpty) {
      // Insert cloud tasks into local DB one by one
      for (final task in cloudTasks) {
        await _db.insertTask(task);
      }
      LogService.instance.info(
          'SmartSync: restored ${cloudTasks.length} tasks from cloud');
    } else {
      LogService.instance
          .info('SmartSync: no tasks found locally or on cloud');
    }

    return cloudTasks;
  }
}
