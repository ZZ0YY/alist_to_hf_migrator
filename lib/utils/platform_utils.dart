import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Platform detection and filesystem utilities.
///
/// Provides a unified API for platform-specific operations like
/// temp directory resolution, disk space queries, and size formatting
/// across Windows, Linux, macOS, and Android.
class PlatformUtils {
  // ─── Platform detection ────────────────────────────────────────────

  /// Whether the current platform is Windows.
  static bool get isWindows => Platform.isWindows;

  /// Whether the current platform is Android.
  static bool get isAndroid => Platform.isAndroid;

  /// Whether the current platform is iOS.
  static bool get isIOS => Platform.isIOS;

  /// Whether the current platform is Linux.
  static bool get isLinux => Platform.isLinux;

  /// Whether the current platform is macOS.
  static bool get isMacOS => Platform.isMacOS;

  /// Whether the current platform is a desktop OS (Windows, Linux, macOS).
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Whether the current platform is a mobile OS (Android, iOS).
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// Human-readable platform name.
  static String get platformName {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Unknown';
  }

  // ─── Temp directory ────────────────────────────────────────────────

  /// Get the temp directory for downloads.
  ///
  /// On desktop: `{appSupportDir}/temp_downloads`
  /// On mobile: `{systemTempDir}/alist_hf_migrator`
  static Future<String> getTempDir() async {
    if (isDesktop) {
      final dir = await getApplicationSupportDirectory();
      final tempDir = Directory(p.join(dir.path, 'temp_downloads'));
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }
      return tempDir.path;
    } else {
      final tempDir = await getTemporaryDirectory();
      final appTempDir = Directory(p.join(tempDir.path, 'alist_hf_migrator'));
      if (!appTempDir.existsSync()) {
        appTempDir.createSync(recursive: true);
      }
      return appTempDir.path;
    }
  }

  // ─── Disk space ────────────────────────────────────────────────────

  /// Get free disk space in GB for the temp/download directory.
  ///
  /// - **Windows**: Uses `wmic logicaldisk get freespace`
  /// - **Linux/macOS**: Uses `df` command
  /// - **Android**: Falls back to available storage via `statvfs` or
  ///   returns a generous default (Android doesn't expose a simple API
  ///   without a plugin).
  static Future<double> getFreeDiskSpaceGb() async {
    try {
      if (isWindows) {
        return await _getFreeDiskSpaceWindows();
      } else if (isLinux || isMacOS) {
        return await _getFreeDiskSpaceUnix();
      } else if (isAndroid) {
        return await _getFreeDiskSpaceAndroid();
      } else {
        // iOS or unknown — return a generous default
        return 100.0;
      }
    } catch (e) {
      // Fail-open: don't block on disk check failure
      return 100.0;
    }
  }

  /// Windows: parse `wmic` output.
  static Future<double> _getFreeDiskSpaceWindows() async {
    final process = await Process.run(
      'wmic',
      ['logicaldisk', 'get', 'freespace'],
      runInShell: true,
    );
    final lines = (process.stdout as String).split('\n');
    // First line is header, remaining lines have values (bytes)
    int totalFreeBytes = 0;
    for (final line in lines.skip(1)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final bytes = int.tryParse(trimmed);
      if (bytes != null) totalFreeBytes += bytes;
    }
    return totalFreeBytes / (1024 * 1024 * 1024);
  }

  /// Linux/macOS: parse `df` output.
  static Future<double> _getFreeDiskSpaceUnix() async {
    final process = await Process.run('df', ['--output=avail', '/']);
    final lines = (process.stdout as String).split('\n');
    // First line is header, second is value in 1K blocks
    for (final line in lines.skip(1)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final kb = int.tryParse(trimmed);
      if (kb != null) return kb / (1024 * 1024); // KB → GB
    }
    return 100.0;
  }

  /// Android: use /proc/meminfo-style approach or StatFs via jni.
  /// For simplicity, we try to read from the temp directory's disk.
  static Future<double> _getFreeDiskSpaceAndroid() async {
    try {
      // Try df which works on Android's Linux kernel
      final process = await Process.run('df', ['-k', '/data']);
      final lines = (process.stdout as String).split('\n');
      for (final line in lines.skip(1)) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final avail = int.tryParse(parts[3]);
          if (avail != null) return avail / (1024 * 1024); // KB → GB
        }
      }
    } catch (_) {}
    return 50.0; // Conservative default for Android
  }

  // ─── Formatting ────────────────────────────────────────────────────

  /// Format a byte count as a human-readable string.
  ///
  /// Examples: `"1.2 KB"`, `"3.45 MB"`, `"10.00 GB"`
  static String formatFileSize(int bytes) {
    if (bytes < 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes < 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
  }

  /// Format a transfer speed as a human-readable string.
  ///
  /// Example: `"1.2 MB/s"`
  static String formatSpeed(double bytesPerSecond) {
    return '${formatFileSize(bytesPerSecond.toInt())}/s';
  }

  /// Get a file extension icon name for use in the UI.
  ///
  /// Returns a Material icon name based on the file extension.
  static String getFileIcon(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      // Images
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.webp':
      case '.bmp':
      case '.svg':
        return 'image';
      // Videos
      case '.mp4':
      case '.mkv':
      case '.avi':
      case '.mov':
      case '.wmv':
      case '.flv':
        return 'videocam';
      // Audio
      case '.mp3':
      case '.flac':
      case '.wav':
      case '.aac':
      case '.ogg':
        return 'audiotrack';
      // Documents
      case '.pdf':
        return 'picture_as_pdf';
      case '.doc':
      case '.docx':
        return 'description';
      case '.xls':
      case '.xlsx':
        return 'table_chart';
      case '.ppt':
      case '.pptx':
        return 'slideshow';
      // Archives
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
        return 'folder_zip';
      // Code
      case '.js':
      case '.ts':
      case '.dart':
      case '.py':
      case '.java':
      case '.cpp':
      case '.c':
      case '.h':
        return 'code';
      // Text
      case '.txt':
      case '.md':
      case '.log':
        return 'article';
      // Default
      default:
        return 'insert_drive_file';
    }
  }

  /// Sanitize a file name to remove problematic characters.
  static String sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
