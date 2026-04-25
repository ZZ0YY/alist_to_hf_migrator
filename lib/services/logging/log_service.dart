import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

/// Log severity levels.
enum LogLevel { debug, info, warning, error }

/// Simple file-based logging service with singleton access.
///
/// All log output is written both to a rotating log file on disk and
/// to the debug console. Log files are stored under
/// `{appDocumentsDir}/logs/migration_{timestamp}.log`.
class LogService {
  // ─── Singleton ─────────────────────────────────────────────────────
  static LogService? _instance;
  static LogService get instance => _instance ??= LogService._();

  LogService._();

  // ─── State ─────────────────────────────────────────────────────────
  File? _logFile;
  final _buffer = StringBuffer();

  /// Minimum log level to output (default: all).
  LogLevel minLevel = LogLevel.debug;

  /// Optional in-memory ring buffer for the UI log viewer.
  /// Keeps the last [maxUiLogLines] lines.
  final List<String> _uiLogLines = [];
  int maxUiLogLines = 500;

  /// Stream-like callback for UI log display.
  void Function(String line)? onLog;

  // ─── Initialization ────────────────────────────────────────────────

  /// Initialize the log service. Must be called once at app startup.
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/logs');
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }
    final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    _logFile = File('${logDir.path}/migration_$now.log');

    // Write session header
    final header = '═══════════════════════════════════════════════\n'
        '  Alist-To-HF Migrator — Session started\n'
        '  Time: ${DateTime.now().toIso8601String()}\n'
        '═══════════════════════════════════════════════\n';
    _logFile?.writeAsStringSync(header, mode: FileMode.append);
  }

  // ─── Logging API ───────────────────────────────────────────────────

  /// Log a message at the given [level].
  ///
  /// Optional [error] and [stackTrace] are appended for ERROR-level entries.
  void log(LogLevel level, String message, [dynamic error, StackTrace? stackTrace]) {
    // Filter by minimum level
    if (level.index < minLevel.index) return;

    final timestamp = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
    final levelStr = level.name.toUpperCase().padRight(7);
    final line = '[$timestamp] [$levelStr] $message';

    // Build full entry
    _buffer.writeln(line);
    if (error != null) _buffer.writeln('  ERROR: $error');
    if (stackTrace != null) _buffer.writeln('  STACK: $stackTrace');

    // Write to file
    _logFile?.writeAsStringSync(_buffer.toString(), mode: FileMode.append);
    _buffer.clear();

    // Also print to debug console
    // ignore: avoid_print
    print(line);
    if (error != null) {
      // ignore: avoid_print
      print('  ERROR: $error');
    }

    // Feed UI log ring buffer
    _uiLogLines.add(line);
    if (_uiLogLines.length > maxUiLogLines) {
      _uiLogLines.removeAt(0);
    }

    // Notify UI listener
    onLog?.call(line);
  }

  /// Convenience methods for each log level.
  void debug(String msg) => log(LogLevel.debug, msg);
  void info(String msg) => log(LogLevel.info, msg);
  void warning(String msg) => log(LogLevel.warning, msg);
  void error(String msg, [dynamic e, StackTrace? s]) => log(LogLevel.error, msg, e, s);

  // ─── Accessors ─────────────────────────────────────────────────────

  /// The current log file (null if [init] hasn't been called).
  File? get currentLogFile => _logFile;

  /// Directory where log files are stored.
  String get logsDir => _logFile?.parent.path ?? '';

  /// Recent log lines for UI display.
  List<String> get recentLines => List.unmodifiable(_uiLogLines);

  /// Clear the in-memory UI log buffer.
  void clearUiBuffer() {
    _uiLogLines.clear();
  }

  /// Get all log file paths (for export or cleanup).
  Future<List<File>> getLogFiles() async {
    if (logsDir.isEmpty) return [];
    final dir = Directory(logsDir);
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path)); // newest first
  }

  /// Delete log files older than [keepDays] days.
  Future<int> cleanOldLogs({int keepDays = 7}) async {
    final files = await getLogFiles();
    var deleted = 0;
    final cutoff = DateTime.now().subtract(Duration(days: keepDays));
    for (final file in files) {
      final stat = file.statSync();
      if (stat.modified.isBefore(cutoff)) {
        try {
          file.deleteSync();
          deleted++;
        } catch (_) {}
      }
    }
    if (deleted > 0) {
      info('Cleaned $deleted old log files (older than $keepDays days)');
    }
    return deleted;
  }

  /// Flush any buffered log content to disk immediately.
  void flush() {
    if (_buffer.isNotEmpty) {
      _logFile?.writeAsStringSync(_buffer.toString(), mode: FileMode.append);
      _buffer.clear();
    }
  }

  /// Reset singleton (for testing).
  static void reset() {
    _instance?.flush();
    _instance = null;
  }
}
