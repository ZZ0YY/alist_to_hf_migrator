import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/migration_task.dart';
import '../database/database_service.dart';

/// Resumable download engine powered by Dio with HTTP Range headers.
///
/// Features:
/// - **Resume support**: Detects existing partial files and sends `Range`
///   headers to continue from where the last download left off.
/// - **Periodic DB sync**: Updates [DatabaseService] every 50 MB or 30 seconds
///   so progress survives app restarts.
/// - **Append mode**: Partial data is always appended to the temp file; the
///   file is never overwritten.
class DownloadEngine {
  final Dio _dio;
  final DatabaseService _db;

  /// How many bytes must be downloaded between periodic DB syncs.
  static const int _syncSizeThreshold = 50 * 1024 * 1024; // 50 MB

  /// Maximum wall-clock time (seconds) between periodic DB syncs.
  static const int _syncTimeThresholdSeconds = 30;

  DownloadEngine(this._dio, this._db);

  /// Download a file with resume support using HTTP Range headers.
  ///
  /// Writes to a local temp file in append mode so existing data is preserved.
  /// Updates `downloadedSize` in the database periodically so progress is
  /// crash-safe.
  ///
  /// [task] must have [MigrationTask.rawUrl] set before calling.
  /// [onProgress] is invoked with `(downloadedBytes, totalBytes)` whenever
  /// new data is written to disk.
  ///
  /// Returns the absolute path to the completed local temp file.
  ///
  /// Throws [DioException] on network errors, [StateError] if `rawUrl` is
  /// empty.
  Future<String> downloadFile(
    MigrationTask task, {
    void Function(int downloaded, int total)? onProgress,
  }) async {
    if (task.rawUrl == null || task.rawUrl!.isEmpty) {
      throw StateError(
        'Cannot download task ${task.id}: rawUrl is not set. '
        'Call AlistApi.getFileInfo() first.',
      );
    }

    // ── 1. Resolve temp directory ────────────────────────────────────────
    final tempDir = await getTemporaryDirectory();
    final tempSubDir = Directory('${tempDir.path}/alist_migrator');
    if (!await tempSubDir.exists()) {
      await tempSubDir.create(recursive: true);
    }
    final localPath = '${tempSubDir.path}/${task.id}';

    // ── 2. Check for partial file ────────────────────────────────────────
    final partialFile = File(localPath);
    int existingSize = 0;

    if (await partialFile.exists()) {
      existingSize = await partialFile.length();
    }

    // ── 3. Open file in append mode ──────────────────────────────────────
    RandomAccessFile raf = await partialFile.open(mode: FileMode.append);

    try {
      // ── 4. Periodic sync tracking ──────────────────────────────────────
      DateTime lastSyncTime = DateTime.now();
      int lastSyncedSize = existingSize;

      // ── 5. Stream download with Range header for resume ────────────────
      final response = await _dio.get<ResponseBody>(
        task.rawUrl!,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          maxRedirects: 5,
          headers: <String, dynamic>{
            if (existingSize > 0) 'Range': 'bytes=$existingSize-',
          },
        ),
      );

      final ResponseBody responseBody = response.data!;

      // ── 6. Determine total file size ───────────────────────────────────
      // If server returned 206 Partial Content, compute total from
      // Content-Range header: "bytes START-END/TOTAL"
      // If server returned 200 OK (doesn't support Range), start from scratch.
      int totalBytes = task.fileSize;

      final statusCode = response.statusCode ?? 200;
      final contentRange = response.headers.value('content-range');

      if (statusCode == 200 && existingSize > 0) {
        // Server ignored the Range header – must start from scratch.
        // Truncate the partial file and reset all counters.
        await raf.truncate(0);
        await raf.setPosition(0);
        existingSize = 0;
        lastSyncedSize = 0;
      }

      if (contentRange != null) {
        // Content-Range format: "bytes 0-999/10000"
        final slashIndex = contentRange.lastIndexOf('/');
        if (slashIndex != -1) {
          final parsed = int.tryParse(contentRange.substring(slashIndex + 1));
          if (parsed != null && parsed > 0) {
            totalBytes = parsed;
          }
        }
      }

      // Fallback: derive total from Content-Length when Content-Range is absent.
      final contentLength = response.headers.value('content-length');
      if (contentLength != null && totalBytes <= 0) {
        final cl = int.parse(contentLength);
        if (statusCode == 206) {
          totalBytes = existingSize + cl;
        } else {
          totalBytes = cl;
        }
      }

      // Last resort: use the task's declared file size.
      if (totalBytes <= 0) {
        totalBytes = task.fileSize;
      }

      int downloadedBytes = existingSize;

      // ── 7. Read stream chunks, write to file, report progress ─────────
      await for (final Uint8List chunk in responseBody.stream) {
        raf.writeFromSync(chunk);
        downloadedBytes += chunk.length;

        // Report progress to caller.
        onProgress?.call(downloadedBytes, totalBytes);

        // ── Periodic DB sync (every 50 MB or 30 seconds) ────────────────
        final now = DateTime.now();
        final bytesSinceSync = downloadedBytes - lastSyncedSize;
        final secondsSinceSync = now.difference(lastSyncTime).inSeconds;

        if (bytesSinceSync >= _syncSizeThreshold ||
            secondsSinceSync >= _syncTimeThresholdSeconds) {
          await _db.updateTaskDownloadProgress(
            task.id,
            downloadedSize: downloadedBytes,
            tmpLocalPath: localPath,
          );
          lastSyncTime = now;
          lastSyncedSize = downloadedBytes;
        }
      }

      // ── 8. Final sync: ensure DB has the exact file size ──────────────
      await raf.close();
      raf = await partialFile.open(mode: FileMode.read);

      final finalFileSize = await raf.length();
      await raf.close();
      raf = await partialFile.open(mode: FileMode.append); // keep open for finally

      await _db.updateTaskDownloadProgress(
        task.id,
        downloadedSize: finalFileSize,
        tmpLocalPath: localPath,
      );

      return localPath;
    } catch (e) {
      // Ensure the file handle is closed on error.
      try {
        await raf.close();
      } catch (_) {
        // Best-effort close; don't mask the original error.
      }
      rethrow;
    } finally {
      try {
        await raf.close();
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }
}
