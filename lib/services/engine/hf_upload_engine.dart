import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/migration_task.dart';
import '../api/imgbed_api.dart';

/// HuggingFace direct upload engine implementing the 3-step HF LFS protocol.
///
/// Step 1 – **getUploadUrl**: Obtain a pre-signed S3 URL from the image bed.
/// Step 2 – **uploadToS3**: Upload the file (single PUT or chunked multipart).
/// Step 3 – **commitUpload**: Notify the image bed that the upload is complete.
///
/// The engine handles both small files (single PUT) and large files that
/// require chunked multipart upload. For chunked uploads it tracks ETags
/// per chunk and issues a merge request after all parts are uploaded.
class HFUploadEngine {
  final ImgBedApi _imgBedApi;
  final Dio _dio;

  HFUploadEngine(this._imgBedApi, this._dio);

  // ─────────────────────────────────────────────────────────────────────────
  // Step 1: Obtain upload URL
  // ─────────────────────────────────────────────────────────────────────────

  /// Request a pre-signed upload URL from the image bed service.
  ///
  /// The returned [HFUploadUrlResponse] may indicate that the file already
  /// exists ([HFUploadUrlResponse.alreadyExists]), in which case steps 2
  /// and 3 can be skipped.
  Future<HFUploadUrlResponse> getUploadUrl(
    MigrationTask task,
    String channelName,
  ) async {
    return await _imgBedApi.getHFUploadUrl(
      fileName: task.fileName,
      fileType: _guessMimeType(task.fileName),
      fileSize: task.fileSize,
      sha256: task.sha256!,
      fileSample: task.fileSample!,
      channelName: channelName,
      uploadNameType: 'origin',
      uploadFolder: task.uploadFolder,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 2: Upload file to S3
  // ─────────────────────────────────────────────────────────────────────────

  /// Upload the local file to HuggingFace S3 storage.
  ///
  /// Supports two modes:
  ///
  /// **Single PUT** – When [HFUploadAction.isChunked] is false, performs a
  /// single PUT request to [HFUploadAction.href] with the provided headers.
  ///
  /// **Chunked upload** – When chunk indicators are present, splits the file
  /// into chunks of [HFUploadAction.chunkSize] bytes, PUTs each chunk to the
  /// URL embedded in its header entry, collects the ETag from each response
  /// (keeping the surrounding double-quotes!), and then POSTs a merge request.
  ///
  /// [onProgress] receives `(bytesUploaded, totalBytes)` as chunks complete.
  Future<void> uploadToS3(
    String localFilePath,
    HFUploadUrlResponse uploadInfo, {
    void Function(int uploaded, int total)? onProgress,
  }) async {
    final action = uploadInfo.uploadAction;
    if (action == null) {
      throw StateError(
        'No upload action provided. The server may indicate the file '
        'already exists (alreadyExists=${uploadInfo.alreadyExists}).',
      );
    }

    if (action.isChunked) {
      await _uploadChunked(localFilePath, action, onProgress: onProgress);
    } else {
      await _uploadSingle(localFilePath, action, onProgress: onProgress);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 3: Commit upload
  // ─────────────────────────────────────────────────────────────────────────

  /// Notify the image bed that the S3 upload is complete.
  ///
  /// Returns the public URL of the uploaded file.
  Future<HFCommitResponse> commitUpload(
    MigrationTask task,
    HFUploadUrlResponse uploadInfo,
    String channelName,
  ) async {
    return await _imgBedApi.commitHFUpload(
      fullId: uploadInfo.fullId,
      filePath: uploadInfo.filePath,
      sha256: task.sha256!,
      fileSize: task.fileSize,
      fileName: task.fileName,
      fileType: _guessMimeType(task.fileName),
      channelName: channelName,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Single PUT upload – send the entire file in one request.
  Future<void> _uploadSingle(
    String localFilePath,
    HFUploadAction action, {
    void Function(int uploaded, int total)? onProgress,
  }) async {
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found for upload', localFilePath);
    }

    final fileLength = await file.length();

    // Build headers from the action, excluding chunk-index keys.
    final headers = _extractStandardHeaders(action.header);
    headers['Content-Length'] = fileLength.toString();

    await _dio.put(
      action.href,
      data: file.openRead(),
      options: Options(
        headers: headers,
        sendTimeout: const Duration(minutes: 60),
        receiveTimeout: const Duration(minutes: 60),
      ),
      onSendProgress: (sent, total) {
        onProgress?.call(sent, total);
      },
    );
  }

  /// Chunked multipart upload.
  ///
  /// Each chunk is PUT to its own URL extracted from [HFUploadAction.header].
  /// The key format is a zero-padded 5-digit index (e.g. "00001").
  /// The value for each key is a Map with:
  ///   - `"url"`: the pre-signed PUT URL for that chunk
  ///   - Other headers to include in the request
  ///
  /// After all chunks are uploaded, a POST merge request is sent to
  /// [HFUploadAction.href].
  Future<void> _uploadChunked(
    String localFilePath,
    HFUploadAction action, {
    void Function(int uploaded, int total)? onProgress,
  }) async {
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found for upload', localFilePath);
    }

    final fileLength = await file.length();
    final chunkSize = action.chunkSize ?? 5 * 1024 * 1024; // Default 5 MB

    // ── Extract ordered chunk entries from header ────────────────────────
    final chunkEntries = <MapEntry<int, Map<String, dynamic>>>[];
    final chunkPattern = RegExp(r'^0*(\d+)$');

    for (final entry in action.header.entries) {
      final match = chunkPattern.firstMatch(entry.key);
      if (match != null) {
        final index = int.parse(match.group(1)!);
        // The value should be a Map containing at least a "url" key.
        if (entry.value is Map<String, dynamic>) {
          chunkEntries.add(MapEntry(index, entry.value as Map<String, dynamic>));
        } else if (entry.value is Map) {
          chunkEntries.add(MapEntry(
            index,
            Map<String, dynamic>.from(entry.value as Map),
          ));
        }
      }
    }

    // Sort by chunk index (ascending).
    chunkEntries.sort((a, b) => a.key.compareTo(b.key));

    if (chunkEntries.isEmpty) {
      throw StateError(
        'Chunked upload requested but no chunk entries found in headers. '
        'Expected keys like "00001", "00002", etc.',
      );
    }

    // ── Upload each chunk ────────────────────────────────────────────────
    final etags = <Map<String, dynamic>>[];
    int totalUploaded = 0;

    for (int i = 0; i < chunkEntries.length; i++) {
      final chunkIndex = chunkEntries[i].key;
      final chunkMeta = chunkEntries[i].value;
      final chunkUrl = chunkMeta['url'] as String? ?? chunkMeta['href'] as String?;

      if (chunkUrl == null || chunkUrl.isEmpty) {
        throw StateError(
          'Chunk $chunkIndex is missing "url" in its header metadata.',
        );
      }

      // Calculate byte range for this chunk.
      final start = chunkIndex * chunkSize;
      final end = (start + chunkSize > fileLength) ? fileLength : start + chunkSize;
      final thisChunkSize = end - start;

      // Read the chunk bytes from the file.
      final raf = await file.open(mode: FileMode.read);
      try {
        await raf.setPosition(start);
        final chunkBytes = await raf.read(thisChunkSize);
        await raf.close();

        // Build headers for this chunk (exclude structural keys).
        final chunkHeaders = <String, dynamic>{};
        for (final h in chunkMeta.entries) {
          if (h.key != 'url' && h.key != 'href') {
            chunkHeaders[h.key] = h.value;
          }
        }
        chunkHeaders['Content-Length'] = thisChunkSize.toString();

        // PUT the chunk.
        final response = await _dio.put<dynamic>(
          chunkUrl,
          data: Stream.fromIterable([Uint8List.fromList(chunkBytes)]),
          options: Options(
            headers: chunkHeaders,
            sendTimeout: const Duration(minutes: 30),
            receiveTimeout: const Duration(minutes: 30),
            responseType: ResponseType.plain,
          ),
        );

        // ── CRITICAL: Extract ETag, keeping the surrounding quotes ───────
        final etag = response.headers.value('etag');
        if (etag == null || etag.isEmpty) {
          throw StateError(
            'Chunk $chunkIndex upload succeeded but server did not return '
            'an ETag header. Cannot complete merge.',
          );
        }

        // Part numbers in the merge API are 1-based.
        etags.add({
          'partNumber': chunkIndex + 1,
          'etag': etag, // Keep the double quotes, e.g. '"abc123"'
        });
      } catch (e) {
        try {
          await raf.close();
        } catch (_) {}
        rethrow;
      }

      totalUploaded = end;
      onProgress?.call(totalUploaded, fileLength);
    }

    // ── Merge: POST parts list to the merge endpoint ─────────────────────
    await _dio.post<dynamic>(
      action.href,
      data: jsonEncode({
        'oid': '', // OID is not needed for merge in this API variant
        'parts': etags,
      }),
      options: Options(
        headers: {
          'Content-Type': 'application/vnd.git-lfs+json',
        },
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
  }

  /// Extract standard HTTP headers from an [HFUploadAction.header] map.
  ///
  /// Filters out keys that look like chunk indices (5-digit numbers).
  Map<String, dynamic> _extractStandardHeaders(Map<String, dynamic> header) {
    final result = <String, dynamic>{};
    final chunkPattern = RegExp(r'^\d{5}$');

    for (final entry in header.entries) {
      if (!chunkPattern.hasMatch(entry.key) &&
          entry.key.toLowerCase() != 'chunk_size') {
        result[entry.key] = entry.value;
      }
    }

    return result;
  }

  /// Simple extension-based MIME type guesser.
  ///
  /// Falls back to `application/octet-stream` for unknown extensions.
  String _guessMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    const mimeMap = <String, String>{
      // Images
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'bmp': 'image/bmp',
      'svg': 'image/svg+xml',
      'ico': 'image/x-icon',
      'tiff': 'image/tiff',
      'tif': 'image/tiff',
      // Videos
      'mp4': 'video/mp4',
      'mkv': 'video/x-matroska',
      'avi': 'video/avi',
      'mov': 'video/quicktime',
      'wmv': 'video/x-ms-wmv',
      'flv': 'video/x-flv',
      'webm': 'video/webm',
      'm4v': 'video/mp4',
      // Audio
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'flac': 'audio/flac',
      'ogg': 'audio/ogg',
      'aac': 'audio/aac',
      'm4a': 'audio/mp4',
      'wma': 'audio/x-ms-wma',
      // Documents
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      // Archives
      'zip': 'application/zip',
      'rar': 'application/vnd.rar',
      '7z': 'application/x-7z-compressed',
      'tar': 'application/x-tar',
      'gz': 'application/gzip',
      'bz2': 'application/x-bzip2',
      // Text / Code
      'txt': 'text/plain',
      'json': 'application/json',
      'xml': 'text/xml',
      'csv': 'text/csv',
      'yaml': 'text/yaml',
      'yml': 'text/yaml',
      'md': 'text/markdown',
      'html': 'text/html',
      'htm': 'text/html',
      'css': 'text/css',
      'js': 'application/javascript',
      'ts': 'application/typescript',
      'py': 'text/x-python',
      'sh': 'application/x-sh',
      // Models / Data
      'safetensors': 'application/octet-stream',
      'bin': 'application/octet-stream',
      'pt': 'application/octet-stream',
      'pth': 'application/octet-stream',
      'onnx': 'application/octet-stream',
      'h5': 'application/octet-stream',
      'parquet': 'application/octet-stream',
      'arrow': 'application/octet-stream',
      'npy': 'application/octet-stream',
      'npz': 'application/octet-stream',
    };
    return mimeMap[ext] ?? 'application/octet-stream';
  }
}
