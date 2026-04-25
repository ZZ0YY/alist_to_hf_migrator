import 'dart:io';

import 'package:dio/dio.dart';

import '../../models/migration_task.dart';
import '../../models/task_status.dart';
import '../api/alist_api.dart';
import '../api/imgbed_api.dart';
import '../database/database_service.dart';
import 'download_engine.dart';
import 'hash_engine.dart';
import 'hf_upload_engine.dart';

/// Orchestrates the complete lifecycle of a single migration task.
///
/// The state machine drives a [MigrationTask] through these states:
///
/// ```
/// PENDING
///   └─► DOWNLOADING ──► HASHING ──► CHECKING ──► HF_PREPARE ──► HF_UPLOADING ──► HF_COMMIT ──► DONE
///         │              │            │              │               │               │
///         ▼              ▼            ▼              ▼               ▼               ▼
///       (any error → retry or FAILED)
/// ```
///
/// Key design decisions:
/// - **Crash recovery**: State is written to DB *before* executing each
///   phase action. If the app crashes, the scheduler can resume from the
///   last persisted state.
/// - **Retry logic**: On failure, [retryCount] is incremented. The scheduler
///   will re-invoke [executeTask] for tasks with retryCount < maxRetries.
///   After max retries the task is permanently FAILED.
/// - **Cancellation**: Accepts a [shouldCancel] callback that is polled
///   between each state transition.
/// - **Temp file cleanup**: [_safeDeleteTempFile] is invoked in both the
///   success and failure paths.
class TaskStateMachine {
  final DatabaseService _db;
  final AlistApi _alistApi;
  final ImgBedApi _imgBedApi;
  final DownloadEngine _downloadEngine;
  final HashEngine _hashEngine;
  final HFUploadEngine _hfUploadEngine;

  /// Maximum number of download retry attempts before the download phase
  /// is considered failed (separate from the overall task retryCount).
  static const int _maxDownloadAttempts = 3;

  /// Called whenever the task is updated (status change, progress, etc.).
  void Function(MigrationTask task)? onTaskUpdated;

  /// Called with progress updates during downloading and uploading.
  void Function(MigrationTask task)? onProgress;

  TaskStateMachine({
    required DatabaseService db,
    required AlistApi alistApi,
    required ImgBedApi imgBedApi,
    required DownloadEngine downloadEngine,
    required HashEngine hashEngine,
    required HFUploadEngine hfUploadEngine,
  })  : _db = db,
        _alistApi = alistApi,
        _imgBedApi = imgBedApi,
        _downloadEngine = downloadEngine,
        _hashEngine = hashEngine,
        _hfUploadEngine = hfUploadEngine;

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Main entry point: drive [task] through the complete state machine.
  ///
  /// [channelName] is the image bed channel to upload to.
  /// [shouldCancel] is polled between transitions; return `true` to abort.
  ///
  /// This method is fully async-safe and handles its own error recovery.
  Future<void> executeTask(
    MigrationTask task,
    String channelName, {
    bool Function()? shouldCancel,
  }) async {
    try {
      // ── Guard: don't re-execute terminal tasks ─────────────────────────
      if (task.status.isTerminal) return;

      // ── Guard: cancellation check ──────────────────────────────────────
      if (_checkCancel(shouldCancel)) return;

      // ═════════════════════════════════════════════════════════════════════
      // Phase 0: Resolve raw URL from Alist (if not already resolved)
      // ═════════════════════════════════════════════════════════════════════
      if (task.rawUrl == null || task.rawUrl!.isEmpty) {
        // Persist DOWNLOADING status BEFORE the API call (crash recovery).
        task = await _persistStatus(task, TaskStatus.downloading);
        if (_checkCancel(shouldCancel)) return;

        final info = await _alistApi.getFileInfo(task.alistPath);
        task = task.copyWith(
          rawUrl: info.rawUrl,
          fileSize: info.size > 0 ? info.size : task.fileSize,
        );
        await _updateTask(task);
        _notifyUpdate(task);
      } else {
        // URL already resolved – just set status to downloading.
        task = await _persistStatus(task, TaskStatus.downloading);
      }

      // ═════════════════════════════════════════════════════════════════════
      // Phase 1: Download the file with resume support
      // ═════════════════════════════════════════════════════════════════════
      task = await _downloadWithRetry(task, shouldCancel: shouldCancel);
      if (_checkCancel(shouldCancel)) return;

      // ═════════════════════════════════════════════════════════════════════
      // Phase 2: Compute SHA-256 hash
      // ═════════════════════════════════════════════════════════════════════
      task = await _persistStatus(task, TaskStatus.hashing);
      if (_checkCancel(shouldCancel)) return;

      {
        final hashResult =
            await _hashEngine.computeHash(task.tmpLocalPath!);
        task = task.copyWith(
          sha256: hashResult.sha256,
          fileSample: hashResult.fileSample,
        );
        await _updateTask(task);
        _notifyUpdate(task);
      }

      if (_checkCancel(shouldCancel)) return;

      // ═════════════════════════════════════════════════════════════════════
      // Phase 3: Dedup check – skip upload if file already exists
      // ═════════════════════════════════════════════════════════════════════
      task = await _persistStatus(task, TaskStatus.checking);
      if (_checkCancel(shouldCancel)) return;

      final fileAlreadyExists = await _imgBedApi.checkFileExists(
        task.fileName,
        task.uploadFolder ?? '',
      );

      // ── Fast path: file already exists, skip to DONE ───────────────────
      if (fileAlreadyExists) {
        task = task.copyWith(
          status: TaskStatus.done,
          errorMessage: null,
          uploadProgress: 1.0,
        );
        _safeDeleteTempFile(task.tmpLocalPath);
        task = task.copyWith(tmpLocalPath: null);
        await _updateTask(task);
        _notifyUpdate(task);
        return;
      }

      if (_checkCancel(shouldCancel)) return;

      // ═════════════════════════════════════════════════════════════════════
      // Phase 4: Get pre-signed upload URL from image bed
      // ═════════════════════════════════════════════════════════════════════
      task = await _persistStatus(task, TaskStatus.hfPrepare);
      if (_checkCancel(shouldCancel)) return;

      final uploadInfo = await _hfUploadEngine.getUploadUrl(task, channelName);
      task = task.copyWith(
        fullId: uploadInfo.fullId,
        filePath: uploadInfo.filePath,
      );
      await _updateTask(task);
      _notifyUpdate(task);

      // ── Guard: already exists on HF (server-side dedup) ───────────────
      if (uploadInfo.alreadyExists) {
        task = task.copyWith(
          status: TaskStatus.done,
          errorMessage: null,
          uploadProgress: 1.0,
        );
        _safeDeleteTempFile(task.tmpLocalPath);
        task = task.copyWith(tmpLocalPath: null);
        await _updateTask(task);
        _notifyUpdate(task);
        return;
      }

      // ═════════════════════════════════════════════════════════════════════
      // Phase 5: Upload to S3 (if LFS upload is required)
      // ═════════════════════════════════════════════════════════════════════
      if (uploadInfo.needsLfs && uploadInfo.uploadAction != null) {
        task = await _persistStatus(task, TaskStatus.hfUploading);
        if (_checkCancel(shouldCancel)) return;

        await _hfUploadEngine.uploadToS3(
          task.tmpLocalPath!,
          uploadInfo,
          onProgress: (uploaded, total) {
            final progress = total > 0 ? uploaded / total : 0.0;
            final updated = task.copyWith(uploadProgress: progress);
            onProgress?.call(updated);
          },
        );
      }

      if (_checkCancel(shouldCancel)) return;

      // ═════════════════════════════════════════════════════════════════════
      // Phase 6: Commit the upload
      // ═════════════════════════════════════════════════════════════════════
      task = await _persistStatus(task, TaskStatus.hfCommit);
      if (_checkCancel(shouldCancel)) return;

      final commitResult = await _hfUploadEngine.commitUpload(
        task,
        uploadInfo,
        channelName,
      );
      task = task.copyWith(
        directUrl: commitResult.fileUrl,
        uploadProgress: 1.0,
      );
      await _updateTask(task);
      _notifyUpdate(task);

      // ═════════════════════════════════════════════════════════════════════
      // Phase 7: Success – mark DONE and clean up
      // ═════════════════════════════════════════════════════════════════════
      _safeDeleteTempFile(task.tmpLocalPath);
      task = task.copyWith(
        status: TaskStatus.done,
        errorMessage: null,
        tmpLocalPath: null,
      );
      await _updateTask(task);
      _notifyUpdate(task);
    } catch (e) {
      await _handleFailure(task, e);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // State transition helper
  // ─────────────────────────────────────────────────────────────────────────

  /// Persist [newStatus] to DB and notify listeners.
  ///
  /// This is the key crash-recovery mechanism: the status is written BEFORE
  /// the subsequent operation runs. If the app crashes, the scheduler can
  /// inspect the persisted status and decide whether to retry or skip.
  Future<MigrationTask> _persistStatus(
    MigrationTask task,
    TaskStatus newStatus,
  ) async {
    task = task.copyWith(status: newStatus);
    await _updateTask(task);
    _notifyUpdate(task);
    return task;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Download with retry
  // ─────────────────────────────────────────────────────────────────────────

  /// Download the file with up to [_maxDownloadAttempts] retries.
  ///
  /// Each retry re-invokes [DownloadEngine.downloadFile], which internally
  /// uses HTTP Range headers to resume from the last checkpoint.
  Future<MigrationTask> _downloadWithRetry(
    MigrationTask task, {
    bool Function()? shouldCancel,
  }) async {
    int attempt = 0;

    while (attempt < _maxDownloadAttempts) {
      if (_checkCancel(shouldCancel)) return task;

      attempt++;

      try {
        final localPath = await _downloadEngine.downloadFile(
          task,
          onProgress: (downloaded, total) {
            final updated = task.copyWith(
              downloadedSize: downloaded,
              fileSize: total > 0 ? total : task.fileSize,
            );
            onProgress?.call(updated);
          },
        );

        // Download succeeded – update task with final state.
        final file = File(localPath);
        final fileSize = await file.length();
        task = task.copyWith(
          downloadedSize: fileSize,
          tmpLocalPath: localPath,
        );
        await _updateTask(task);
        _notifyUpdate(task);
        return task;
      } on DioException catch (e) {
        final isLastAttempt = attempt >= _maxDownloadAttempts;

        if (isLastAttempt) {
          throw StateError(
            'Download failed after $_maxDownloadAttempts attempts: ${e.message}',
          );
        }

        // Exponential backoff before retry: 2s, 4s, 6s ...
        final delaySeconds = attempt * 2;
        await Future.delayed(Duration(seconds: delaySeconds));

        // Re-read task from DB to pick up any external changes (e.g.
        // user cancelled while we were sleeping).
        final freshTask = await _db.getTask(task.id);
        if (freshTask != null) {
          task = freshTask;
        }
      }
    }

    // Should not reach here, but just in case.
    throw StateError('Download failed: unexpected loop exit');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Error handling
  // ─────────────────────────────────────────────────────────────────────────

  /// Handle a task failure with retry logic.
  ///
  /// If [task.retryCount] < [task.maxRetries]:
  ///   - **Keep the current status** (so the scheduler retries from the same
  ///     phase). The status is NOT changed to FAILED.
  ///   - Increment [retryCount].
  ///   - Save error message to DB for UI display.
  ///
  /// If retries are exhausted:
  ///   - Set status to [TaskStatus.failed].
  ///   - Store a descriptive error message.
  ///   - Delete the temp file.
  ///   - Save to DB.
  Future<void> _handleFailure(MigrationTask task, dynamic error) async {
    final errorMessage = _formatError(error);

    if (task.retryCount < task.maxRetries) {
      // ── Retriable: increment retry count, keep current status ──────────
      // The scheduler will pick up this task again and call executeTask().
      // Because we keep the status as-is, the state machine will re-enter
      // the appropriate phase (e.g. DOWNLOADING → resumes download).
      task = task.copyWith(
        retryCount: task.retryCount + 1,
        errorMessage: errorMessage,
      );
      await _updateTask(task);
      _notifyUpdate(task);
    } else {
      // ── Fatal: mark as FAILED, clean up temp file ──────────────────────
      _safeDeleteTempFile(task.tmpLocalPath);
      task = task.copyWith(
        status: TaskStatus.failed,
        errorMessage: 'Failed after ${task.maxRetries} retries: $errorMessage',
        tmpLocalPath: null,
      );
      await _updateTask(task);
      _notifyUpdate(task);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Utilities
  // ─────────────────────────────────────────────────────────────────────────

  /// Check the [shouldCancel] callback. Returns `true` if cancelled.
  ///
  /// This is a convenience wrapper that handles null [shouldCancel].
  bool _checkCancel(bool Function()? shouldCancel) {
    return shouldCancel != null && shouldCancel();
  }

  /// Persist the current task state to the database.
  ///
  /// Wraps DB errors so they don't mask the original operation error.
  Future<void> _updateTask(MigrationTask task) async {
    try {
      await _db.updateTask(task);
    } catch (e) {
      // Log but don't throw – DB persistence failures should not crash
      // the state machine (the in-memory state is still valid).
      assert(false, 'Failed to persist task ${task.id} to DB: $e');
    }
  }

  /// Safely notify the UI layer of a task update.
  ///
  /// Never throws – errors in the callback are silently swallowed.
  void _notifyUpdate(MigrationTask task) {
    try {
      onTaskUpdated?.call(task);
    } catch (_) {
      // UI callback errors should not crash the engine.
    }
  }

  /// Delete the temp file at [path]. Never throws.
  ///
  /// If [path] is null, empty, or the file doesn't exist, this is a no-op.
  void _safeDeleteTempFile(String? path) {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Best-effort cleanup. Never throw from this method.
    }
  }

  /// Format an error into a human-readable string.
  String _formatError(dynamic error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final message = error.message ?? 'no message';
      return 'DioException(status=$status): $message';
    } else if (error is StateError) {
      return error.message;
    } else if (error is FileSystemException) {
      return 'FileSystemException: ${error.message} (path: ${error.path})';
    } else {
      return error.toString();
    }
  }
}
