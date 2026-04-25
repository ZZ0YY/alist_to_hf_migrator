import 'package:dio/dio.dart';

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// Represents a channel available on the ImgBed instance (e.g. a HuggingFace
/// repo endpoint).
class ImgBedChannel {
  final String name;
  final String type;
  final String id;
  final String status;

  const ImgBedChannel({
    required this.name,
    required this.type,
    required this.id,
    required this.status,
  });

  factory ImgBedChannel.fromJson(Map<String, dynamic> json) {
    return ImgBedChannel(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'ImgBedChannel(name: $name, type: $type, id: $id, status: $status)';
}

/// Represents a single file entry returned by the manage/list endpoint.
class ImgBedFile {
  /// Full file path/name as reported by the API, e.g. `images/photo.jpg`.
  final String name;

  /// Channel label, typically `huggingface` or similar.
  final String channel;

  /// File size in bytes.
  final int fileSize;

  /// MIME type of the file.
  final String mimeType;

  const ImgBedFile({
    required this.name,
    required this.channel,
    required this.fileSize,
    required this.mimeType,
  });

  factory ImgBedFile.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] as Map<String, dynamic>? ?? {};
    return ImgBedFile(
      name: json['name'] as String? ?? '',
      channel: metadata['Channel'] as String? ?? '',
      fileSize: _parseInt(metadata['File-Size']),
      mimeType: metadata['File-Mime'] as String? ?? '',
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  @override
  String toString() =>
      'ImgBedFile(name: $name, channel: $channel, '
      'fileSize: $fileSize, mimeType: $mimeType)';
}

/// Upload action details for S3 presigned PUT requests.
class HFUploadAction {
  /// The presigned URL to PUT the file to.
  final String href;

  /// Headers that must be included in the PUT request.
  ///
  /// For **single** uploads this contains standard HTTP header key-value
  /// pairs (e.g. `{"Content-Type": "image/png"}`).
  ///
  /// For **chunked** uploads the header map also contains keys like
  /// `"00001"`, `"00002"`, … whose values are `Map<String, dynamic>` with
  /// at least a `"url"` key pointing to each chunk's presigned PUT URL.
  /// A separate numeric key (e.g. `"0"`) may contain the chunk size.
  final Map<String, dynamic> header;

  /// Optional chunk size (bytes) when the API indicates chunked upload.
  /// Detected from header keys like `"00001"`.
  final int? chunkSize;

  const HFUploadAction({
    required this.href,
    required this.header,
    this.chunkSize,
  });

  factory HFUploadAction.fromJson(Map<String, dynamic> json) {
    // Keep the header as Map<String, dynamic> to preserve nested structures
    // needed for chunked uploads (where values are Maps with "url" keys).
    final rawHeader = json['header'] as Map<String, dynamic>? ?? {};

    // Detect chunk size from special numeric keys.
    int? detectedChunkSize;
    const chunkKeyPattern = RegExp(r'^\d+$');
    for (final key in rawHeader.keys) {
      if (chunkKeyPattern.hasMatch(key) && key != '0') {
        // Chunk index keys like "00001" have Map values.
        // Skip them here; chunk size may come from key "0" or a dedicated field.
        continue;
      }
    }
    // Check for explicit chunk_size in JSON.
    if (json['chunk_size'] is int) {
      detectedChunkSize = json['chunk_size'] as int;
    }

    return HFUploadAction(
      href: json['href'] as String? ?? '',
      header: Map<String, dynamic>.from(rawHeader),
      chunkSize: detectedChunkSize,
    );
  }

  /// Returns `true` when the header map contains chunk-index keys
  /// (e.g. `"00001"`, `"00002"`), indicating the upload must be split.
  bool get isChunked {
    if (chunkSize != null && chunkSize! > 0) return true;
    const chunkIndexPattern = RegExp(r'^0*\d{1,5}$');
    return header.keys.any((k) =>
        chunkIndexPattern.hasMatch(k) &&
        k != '0' &&
        header[k] is Map);
  }

  @override
  String toString() =>
      'HFUploadAction(href: $href, headerKeys: ${header.keys.toList()}, '
      'chunkSize: $chunkSize, isChunked: $isChunked)';
}

/// Response from the `getUploadUrl` endpoint.
class HFUploadUrlResponse {
  final bool success;
  final String fullId;
  final String filePath;
  final String channelName;
  final String repo;
  final bool needsLfs;
  final bool alreadyExists;
  final String oid;
  final HFUploadAction? uploadAction;

  const HFUploadUrlResponse({
    required this.success,
    required this.fullId,
    required this.filePath,
    required this.channelName,
    required this.repo,
    required this.needsLfs,
    required this.alreadyExists,
    required this.oid,
    this.uploadAction,
  });

  factory HFUploadUrlResponse.fromJson(Map<String, dynamic> json) {
    final action = json['uploadAction'];
    return HFUploadUrlResponse(
      success: json['success'] as bool? ?? false,
      fullId: json['fullId'] as String? ?? '',
      filePath: json['filePath'] as String? ?? '',
      channelName: json['channelName'] as String? ?? '',
      repo: json['repo'] as String? ?? '',
      needsLfs: json['needsLfs'] as bool? ?? false,
      alreadyExists: json['alreadyExists'] as bool? ?? false,
      oid: json['oid'] as String? ?? '',
      uploadAction: action != null
          ? HFUploadAction.fromJson(action as Map<String, dynamic>)
          : null,
    );
  }

  @override
  String toString() =>
      'HFUploadUrlResponse(success: $success, fullId: $fullId, '
      'filePath: $filePath, channelName: $channelName, repo: $repo, '
      'needsLfs: $needsLfs, alreadyExists: $alreadyExists, oid: $oid)';
}

/// Response from the `commitUpload` endpoint.
class HFCommitResponse {
  final bool success;
  final String src;
  final String fileUrl;
  final String fullId;

  const HFCommitResponse({
    required this.success,
    required this.src,
    required this.fileUrl,
    required this.fullId,
  });

  factory HFCommitResponse.fromJson(Map<String, dynamic> json) {
    return HFCommitResponse(
      success: json['success'] as bool? ?? false,
      src: json['src'] as String? ?? '',
      fileUrl: json['fileUrl'] as String? ?? '',
      fullId: json['fullId'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'HFCommitResponse(success: $success, src: $src, '
      'fileUrl: $fileUrl, fullId: $fullId)';
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------
class ImgBedApiException implements Exception {
  final int statusCode;
  final String message;

  const ImgBedApiException(this.statusCode, this.message);

  @override
  String toString() =>
      'ImgBedApiException(statusCode: $statusCode, message: $message)';
}

// ---------------------------------------------------------------------------
// API client
// ---------------------------------------------------------------------------
class ImgBedApi {
  final Dio _dio;

  /// Creates a new [ImgBedApi] client.
  ///
  /// [baseUrl] – root URL of the ImgBed instance, e.g.
  ///   `https://imgbed.example.com` (no trailing slash required).
  /// [apiToken] – bearer token for `Authorization: Bearer <token>`.
  ImgBedApi({required String baseUrl, required String apiToken})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl.endsWith('/')
              ? baseUrl.substring(0, baseUrl.length - 1)
              : baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 120),
          headers: {
            'Accept': 'application/json',
          },
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['Authorization'] = 'Bearer $apiToken';
        handler.next(options);
      },
    ));
  }

  // --------------------------------------------------------------------------
  // Internal
  // --------------------------------------------------------------------------
  Future<T> _safeCall<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on DioException catch (e) {
      final msg = _dioExceptionMessage(e);
      throw ImgBedApiException(e.response?.statusCode ?? -1, msg);
    }
  }

  static String _dioExceptionMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timed out';
      case DioExceptionType.sendTimeout:
        return 'Send timed out';
      case DioExceptionType.receiveTimeout:
        return 'Receive timed out';
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        final body = e.response?.data;
        return 'Bad response (status $status): $body';
      case DioExceptionType.cancel:
        return 'Request was cancelled';
      case DioExceptionType.connectionError:
        return 'Connection error: ${e.message}';
      case DioExceptionType.badCertificate:
        return 'Bad SSL certificate';
      case DioExceptionType.unknown:
      default:
        return 'Network error: ${e.message ?? e.type.toString()}';
    }
  }

  // --------------------------------------------------------------------------
  // Public methods
  // --------------------------------------------------------------------------

  /// Retrieve the list of available channels (HuggingFace repos configured
  /// on the ImgBed instance).
  ///
  /// GET `/api/channels`
  Future<List<ImgBedChannel>> getChannels() async {
    return _safeCall(() async {
      final response = await _dio.get<List<dynamic>>('/api/channels');
      final body = response.data;
      if (body == null) return [];
      return body
          .map((item) =>
              ImgBedChannel.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  /// List files managed by the ImgBed instance.
  ///
  /// GET `/api/manage/list`
  ///
  /// [dir]      – directory prefix to filter by.
  /// [search]   – search term to match against file names.
  Future<List<ImgBedFile>> listFiles({
    String dir = '',
    String search = '',
  }) async {
    return _safeCall(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/manage/list',
        queryParameters: {
          'dir': dir,
          'search': search,
          'count': 100,
          'start': 0,
          'channel': 'HuggingFace',
        },
      );

      final body = response.data;
      if (body == null) return [];

      final files = body['files'] as List<dynamic>? ?? [];
      return files
          .map((item) =>
              ImgBedFile.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  /// Check whether a file with the given [fileName] exists in [dir].
  ///
  /// Uses [listFiles] with a search filter.
  Future<bool> checkFileExists(String fileName, String dir) async {
    try {
      final files = await listFiles(dir: dir, search: fileName);
      // The API search is a substring match; verify exact name match.
      return files.any((f) => f.name == fileName || f.name.endsWith('/$fileName'));
    } on ImgBedApiException {
      return false;
    }
  }

  /// Obtain a presigned S3 upload URL for a HuggingFace LFS file.
  ///
  /// POST `/upload/huggingface/getUploadUrl`
  Future<HFUploadUrlResponse> getHFUploadUrl({
    required String fileName,
    required String fileType,
    required int fileSize,
    required String sha256,
    String? fileSample,
    required String channelName,
    String uploadNameType = 'origin',
    String? uploadFolder,
  }) async {
    return _safeCall(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/upload/huggingface/getUploadUrl',
        data: {
          'fileName': fileName,
          'fileType': fileType,
          'fileSize': fileSize,
          'sha256': sha256,
          if (fileSample != null) 'fileSample': fileSample,
          'channelName': channelName,
          'uploadNameType': uploadNameType,
          if (uploadFolder != null) 'uploadFolder': uploadFolder,
        },
      );

      final body = response.data;
      if (body == null) {
        throw ImgBedApiException(-1, 'Empty response from getUploadUrl');
      }
      return HFUploadUrlResponse.fromJson(body);
    });
  }

  /// Commit / finalize an upload after the S3 PUT has completed.
  ///
  /// POST `/upload/huggingface/commitUpload`
  Future<HFCommitResponse> commitHFUpload({
    required String fullId,
    required String filePath,
    required String sha256,
    required int fileSize,
    required String fileName,
    required String fileType,
    required String channelName,
  }) async {
    return _safeCall(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/upload/huggingface/commitUpload',
        data: {
          'fullId': fullId,
          'filePath': filePath,
          'sha256': sha256,
          'fileSize': fileSize,
          'fileName': fileName,
          'fileType': fileType,
          'channelName': channelName,
        },
      );

      final body = response.data;
      if (body == null) {
        throw ImgBedApiException(-1, 'Empty response from commitUpload');
      }
      return HFCommitResponse.fromJson(body);
    });
  }
}
