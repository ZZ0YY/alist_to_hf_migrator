import 'dart:io';

import 'package:dio/dio.dart';

import '../../models/alist_file_node.dart';
import '../../utils/path_encoder.dart';

// ---------------------------------------------------------------------------
// Data model returned by /api/fs/get
// ---------------------------------------------------------------------------
class AlistFileInfo {
  final String name;
  final int size;
  final bool isDir;
  final String rawUrl;
  final DateTime modified;
  final String provider;

  const AlistFileInfo({
    required this.name,
    required this.size,
    required this.isDir,
    required this.rawUrl,
    required this.modified,
    required this.provider,
  });

  factory AlistFileInfo.fromJson(Map<String, dynamic> json) {
    return AlistFileInfo(
      name: json['name'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      isDir: json['is_dir'] as bool? ?? false,
      rawUrl: json['raw_url'] as String? ?? '',
      modified: _parseDateTime(json['modified'] as String?),
      provider: json['provider'] as String? ?? '',
    );
  }

  static DateTime _parseDateTime(String? value) {
    if (value == null || value.isEmpty) return DateTime.now();
    try {
      return DateTime.parse(value).toUtc();
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Convenience: build an [AlistFileNode] from this info.
  AlistFileNode toFileNode() => AlistFileNode(
        name: name,
        size: size,
        isDir: isDir,
        modified: modified,
        provider: provider,
      );

  @override
  String toString() =>
      'AlistFileInfo(name: $name, size: $size, isDir: $isDir, '
      'rawUrl: $rawUrl, modified: $modified, provider: $provider)';
}

// ---------------------------------------------------------------------------
// Exception thrown when the Alist server returns code != 200
// ---------------------------------------------------------------------------
class AlistApiException implements Exception {
  final int code;
  final String message;

  const AlistApiException(this.code, this.message);

  @override
  String toString() => 'AlistApiException(code: $code, message: $message)';
}

// ---------------------------------------------------------------------------
// API client
// ---------------------------------------------------------------------------
class AlistApi {
  final Dio _dio;
  String? token;

  /// Creates a new [AlistApi] client.
  ///
  /// [baseUrl] should point to the Alist server root, e.g.
  /// `https://alist.example.com` (no trailing slash required).
  AlistApi({required String baseUrl})
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
      onRequest: (options, handler) async {
        if (token != null && token!.isNotEmpty) {
          options.headers['Authorization'] = token!;
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        handler.next(error);
      },
    ));
  }

  // --------------------------------------------------------------------------
  // Internal helpers
  // --------------------------------------------------------------------------
  void _ensureLoggedIn() {
    if (token == null || token!.isEmpty) {
      throw AlistApiException(401, 'Not logged in. Call login() first.');
    }
  }

  /// Checks the standard Alist envelope `{"code":200,"message":"...", "data":...}`.
  /// Returns the `data` field on success.
  dynamic _checkResponse(Response<dynamic> response) {
    final body = response.data;
    final Map<String, dynamic> json;
    if (body is Map<String, dynamic>) {
      json = body;
    } else if (body is String) {
      // Some servers may return JSON as a string – try to decode.
      try {
        json = Map<String, dynamic>.from(
          const JsonDecoder().convert(body) as Map,
        );
      } catch (e) {
        throw AlistApiException(
          -1,
          'Failed to parse response body: $e',
        );
      }
    } else {
      throw AlistApiException(
          -1, 'Unexpected response type: ${body.runtimeType}');
    }

    final code = json['code'] as int? ?? -1;
    final message = json['message'] as String? ?? 'Unknown error';

    if (code != 200) {
      throw AlistApiException(code, message);
    }

    return json['data'];
  }

  /// Wraps a Dio call and translates [DioException] to [AlistApiException].
  Future<T> _safeCall<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on DioException catch (e) {
      final msg = _dioExceptionMessage(e);
      throw AlistApiException(e.response?.statusCode ?? -1, msg);
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
  // Public API methods
  // --------------------------------------------------------------------------

  /// Authenticate with the Alist server and store the token.
  ///
  /// Returns `true` on success. Throws [AlistApiException] on failure.
  Future<bool> login(String username, String password) async {
    return _safeCall(() async {
      final response = await _dio.post(
        '/api/auth/login',
        queryParameters: {
          'username': username,
          'password': password,
        },
      );

      final data = _checkResponse(response) as Map<String, dynamic>;
      token = data['token'] as String?;
      if (token == null || token!.isEmpty) {
        throw AlistApiException(-1, 'Login succeeded but no token returned');
      }
      return true;
    });
  }

  /// List files and folders under [path].
  ///
  /// [page] is 1-indexed. [perPage] = 0 means "return all".
  Future<List<AlistFileNode>> listFiles(
    String path, {
    int page = 1,
    int perPage = 0,
  }) async {
    _ensureLoggedIn();
    return _safeCall(() async {
      final response = await _dio.post(
        '/api/fs/list',
        data: {
          'path': path,
          'page': page,
          'per_page': perPage,
          'password': '',
          'refresh': false,
        },
      );

      final data = _checkResponse(response) as Map<String, dynamic>;
      final content = data['content'] as List<dynamic>? ?? [];
      return content
          .map((item) => AlistFileNode.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  /// Get detailed file/folder info and download URL for a single path.
  ///
  /// The returned [AlistFileInfo.rawUrl] can be used to download the file.
  Future<AlistFileInfo> getFileInfo(String path) async {
    _ensureLoggedIn();
    return _safeCall(() async {
      final response = await _dio.post(
        '/api/fs/get',
        data: {
          'path': path,
          'password': '',
        },
      );

      final data = _checkResponse(response) as Map<String, dynamic>;
      return AlistFileInfo.fromJson(data);
    });
  }

  /// Upload a local file to Alist using the form-upload endpoint.
  ///
  /// [remotePath] is the full remote path including filename, e.g.
  /// `/我的资源/images/photo.jpg`.
  ///
  /// Returns `true` on success.
  Future<bool> uploadFile(String remotePath, File localFile) async {
    _ensureLoggedIn();

    final fileName = PathEncoder.extractFileName(remotePath);
    final fileLength = await localFile.length();
    final encodedPath = PathEncoder.encodeFilePath(remotePath);

    return _safeCall(() async {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          localFile.path,
          filename: fileName,
        ),
      });

      final response = await _dio.put(
        '/api/fs/form',
        data: formData,
        options: Options(
          headers: {
            'Content-Type': 'multipart/form-data',
            'Content-Length': fileLength,
            'File-Path': encodedPath,
          },
        ),
      );

      _checkResponse(response);
      return true;
    });
  }

  /// Create a directory at the given [path] on Alist.
  ///
  /// The path should be the full path of the new directory, e.g.
  /// `/我的资源/newdir`.
  Future<void> mkdir(String path) async {
    _ensureLoggedIn();
    return _safeCall(() async {
      final response = await _dio.post(
        '/api/fs/mkdir',
        data: {
          'path': path,
        },
      );
      _checkResponse(response);
    });
  }

  /// Check whether a file or folder exists at the given [path].
  ///
  /// This lists the parent directory and looks for a matching name.
  /// Returns `true` if found, `false` otherwise.
  Future<bool> fileExists(String path) async {
    _ensureLoggedIn();
    try {
      final parentPath = PathEncoder.extractParentPath(path);
      final targetName = PathEncoder.extractFileName(path);

      final items = await listFiles(parentPath, page: 1, perPage: 0);
      return items.any((node) => node.name == targetName);
    } on AlistApiException {
      // If the parent doesn't exist or listing fails, treat as not-found.
      return false;
    }
  }

  /// Ensure a directory exists on Alist (create if not exists).
  Future<void> ensureDirectory(String path) async {
    if (await fileExists(path)) return;
    await mkdir(path);
  }

  /// Get a direct download URL for a file path.
  /// Returns the raw_url from getFileInfo.
  Future<String> getDirectDownloadUrl(String path) async {
    final info = await getFileInfo(path);
    if (info.rawUrl.isEmpty) {
      throw AlistApiException(-1, 'No download URL available for $path');
    }
    return info.rawUrl;
  }
}
