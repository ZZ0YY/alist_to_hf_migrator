import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../../models/app_config.dart';
import '../../models/migration_task.dart';
import '../../models/task_status.dart';
import 'tables.dart';

/// 单例数据库服务 —— 负责所有本地持久化操作。
///
/// 支持移动端 (Android / iOS) 和桌面端 (macOS / Linux / Windows)：
/// - 移动端：直接使用 `sqflite`。
/// - 桌面端：通过 `sqflite_common_ffi` 提供的 FFI 桥接层运行 SQLite。
///
/// **使用方式：**
/// ```dart
/// await DatabaseService.instance.init();
/// final tasks = await DatabaseService.instance.getAllTasks();
/// await DatabaseService.instance.close();
/// ```
class DatabaseService {
  // ── 单例 ──────────────────────────────────────────────────
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  // ── 内部状态 ──────────────────────────────────────────────
  Database? _db;
  bool _initialized = false;

  /// 数据库是否已初始化。
  bool get isInitialized => _initialized;

  /// 当前数据库版本号。
  static const int _kVersion = 1;

  /// 数据库文件名。
  static const String _kDbFileName = 'alist_to_hf.db';

  // ══════════════════════════════════════════════════════════
  //  初始化 / 生命周期
  // ══════════════════════════════════════════════════════════

  /// 初始化数据库。
  ///
  /// 必须在使用任何其他方法之前调用。在桌面端会自动完成 FFI 初始化。
  /// 重复调用不会重新打开数据库。
  Future<void> init() async {
    if (_initialized && _db != null) return;

    _ensureDesktopFfi();

    final dbPath = await _resolveDbPath();
    final fullPath = p.join(dbPath, _kDbFileName);

    debugPrint('[DatabaseService] Opening database: $fullPath');

    _db = await openDatabase(
      fullPath,
      version: _kVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    _initialized = true;
    debugPrint('[DatabaseService] Database initialized (v$_kVersion)');
  }

  /// 关闭数据库连接。
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
      _initialized = false;
      debugPrint('[DatabaseService] Database closed');
    }
  }

  // ══════════════════════════════════════════════════════════
  //  AppConfig CRUD
  // ══════════════════════════════════════════════════════════

  /// 保存 [AppConfig] 到数据库。
  ///
  /// 采用 `INSERT OR REPLACE` 策略，每个字段作为一行 key-value 存储。
  Future<void> saveConfig(AppConfig config) async {
    _ensureOpen();
    final map = config.toMap();

    final batch = _db!.batch();
    for (final entry in map.entries) {
      batch.execute(
        'INSERT OR REPLACE INTO ${DbTables.appConfig} (key, value) VALUES (?, ?)',
        [entry.key, entry.value.toString()],
      );
    }
    await batch.commit(noResult: true);

    debugPrint('[DatabaseService] Config saved (${map.length} keys)');
  }

  /// 从数据库加载 [AppConfig]。
  ///
  /// 如果数据库中没有任何配置记录则返回 `null`。
  Future<AppConfig?> loadConfig() async {
    _ensureOpen();

    final rows = await _db!.query(
      DbTables.appConfig,
      columns: ['key', 'value'],
    );

    if (rows.isEmpty) return null;

    final Map<String, dynamic> map = {};
    for (final row in rows) {
      final key = row['key'] as String;
      final value = row['value'] as String;
      map[key] = value;
    }

    // 将整数字段从 String 还原为 int
    _restoreIntField(map, ConfigKeys.maxConcurrentTasks);
    _restoreIntField(map, ConfigKeys.diskWatermarkGb);
    _restoreIntField(map, ConfigKeys.maxRetries);

    debugPrint('[DatabaseService] Config loaded (${map.length} keys)');
    return AppConfig.fromMap(map);
  }

  // ══════════════════════════════════════════════════════════
  //  MigrationTask CRUD
  // ══════════════════════════════════════════════════════════

  /// 插入一条新任务。
  ///
  /// 使用 `ConflictAlgorithm.replace` —— 若已存在同 ID 记录则覆盖。
  Future<void> insertTask(MigrationTask task) async {
    _ensureOpen();

    await _db!.insert(
      DbTables.taskQueue,
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    debugPrint('[DatabaseService] Task inserted: ${task.id}');
  }

  /// 更新一条已有任务（根据 ID 匹配）。
  Future<void> updateTask(MigrationTask task) async {
    _ensureOpen();

    final count = await _db!.update(
      DbTables.taskQueue,
      task.toMap(),
      where: '${TaskColumns.id} = ?',
      whereArgs: [task.id],
    );

    if (count == 0) {
      debugPrint(
        '[DatabaseService] ⚠ updateTask: no row matched for id=${task.id}',
      );
    }
  }

  /// 根据 ID 获取单条任务。
  ///
  /// 不存在时返回 `null`。
  Future<MigrationTask?> getTask(String id) async {
    _ensureOpen();

    final rows = await _db!.query(
      DbTables.taskQueue,
      where: '${TaskColumns.id} = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return MigrationTask.fromMap(rows.first);
  }

  /// 获取全部任务（按创建时间倒序）。
  Future<List<MigrationTask>> getAllTasks() async {
    _ensureOpen();

    final rows = await _db!.query(
      DbTables.taskQueue,
      orderBy: '${TaskColumns.createdAt} DESC',
    );

    return rows.map((row) => MigrationTask.fromMap(row)).toList();
  }

  /// 按状态筛选任务。
  Future<List<MigrationTask>> getTasksByStatus(TaskStatus status) async {
    _ensureOpen();

    final rows = await _db!.query(
      DbTables.taskQueue,
      where: '${TaskColumns.status} = ?',
      whereArgs: [status.value],
      orderBy: '${TaskColumns.createdAt} DESC',
    );

    return rows.map((row) => MigrationTask.fromMap(row)).toList();
  }

  /// 获取所有待处理和进行中的任务。
  ///
  /// 包含 [TaskStatus.pending] 以及所有活跃状态
  /// （CHECKING、DOWNLOADING、HASHING、HF_PREPARE、HF_UPLOADING、HF_COMMIT）。
  Future<List<MigrationTask>> getPendingAndActiveTasks() async {
    _ensureOpen();

    const activeStatuses = [
      'PENDING',
      'CHECKING',
      'DOWNLOADING',
      'HASHING',
      'HF_PREPARE',
      'HF_UPLOADING',
      'HF_COMMIT',
    ];

    final placeholders = List.filled(activeStatuses.length, '?').join(',');

    final rows = await _db!.query(
      DbTables.taskQueue,
      where: '${TaskColumns.status} IN ($placeholders)',
      whereArgs: activeStatuses,
      orderBy: '${TaskColumns.createdAt} ASC',
    );

    return rows.map((row) => MigrationTask.fromMap(row)).toList();
  }

  /// 删除一条任务。
  Future<void> deleteTask(String id) async {
    _ensureOpen();

    await _db!.delete(
      DbTables.taskQueue,
      where: '${TaskColumns.id} = ?',
      whereArgs: [id],
    );

    debugPrint('[DatabaseService] Task deleted: $id');
  }

  /// 统计指定状态的任务数量。
  Future<int> getTaskCountByStatus(TaskStatus status) async {
    _ensureOpen();

    final result = await _db!.rawQuery(
      'SELECT COUNT(*) AS cnt FROM ${DbTables.taskQueue} '
      'WHERE ${TaskColumns.status} = ?',
      [status.value],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 局部更新下载进度（高效，仅修改两列）。
  ///
  /// 由 [DownloadEngine] 在下载过程中周期性调用，
  /// 避免每次序列化完整的 [MigrationTask] 对象。
  Future<void> updateTaskDownloadProgress(
    String taskId, {
    required int downloadedSize,
    required String tmpLocalPath,
  }) async {
    _ensureOpen();

    await _db!.update(
      DbTables.taskQueue,
      {
        TaskColumns.downloadedSize: downloadedSize,
        TaskColumns.tmpLocalPath: tmpLocalPath,
        TaskColumns.updatedAt: DateTime.now().toIso8601String(),
      },
      where: '${TaskColumns.id} = ?',
      whereArgs: [taskId],
    );
  }

  /// 批量插入任务（用于云端恢复场景）。
  Future<void> insertTasks(List<MigrationTask> tasks) async {
    _ensureOpen();
    final batch = _db!.batch();
    for (final task in tasks) {
      batch.insert(
        DbTables.taskQueue,
        task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    debugPrint('[DatabaseService] Batch inserted ${tasks.length} tasks');
  }

  /// 清空全部任务（用于重置）。
  ///
  /// 将直接 DELETE 表中所有行，请谨慎使用。
  Future<void> clearAllTasks() async {
    _ensureOpen();

    await _db!.delete(DbTables.taskQueue);
    debugPrint('[DatabaseService] All tasks cleared');
  }

  // ══════════════════════════════════════════════════════════
  //  内部方法
  // ══════════════════════════════════════════════════════════

  /// 桌面端 FFI 初始化（仅桌面端执行一次）。
  ///
  /// 在桌面端调用 `sqfliteFfiInit()` 并将全局 `databaseFactory`
  /// 替换为 FFI 版本，后续 `openDatabase` 调用将自动走 FFI 路径。
  void _ensureDesktopFfi() {
    if (kIsWeb) return;

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      try {
        ffi.sqfliteFfiInit();
        databaseFactory = ffi.databaseFactoryFfi;
        debugPrint('[DatabaseService] Desktop FFI initialized');
      } catch (e) {
        debugPrint('[DatabaseService] ⚠ Failed to init FFI: $e');
      }
    }
  }

  /// 解析数据库文件存储目录路径。
  ///
  /// - 移动端 (Android / iOS)：使用 [getApplicationDocumentsDirectory]。
  /// - 桌面端 (macOS / Linux / Windows)：使用 [getApplicationSupportDirectory]。
  Future<String> _resolveDbPath() async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Web platform is not supported by the local database service.',
      );
    }

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final dir = await getApplicationSupportDirectory();
      return dir.path;
    }

    // Android / iOS
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  /// 首次建表回调。
  Future<void> _onCreate(Database db, int version) async {
    await db.execute(_kCreateAppConfigTable);
    await db.execute(_kCreateTaskQueueTable);

    // 创建索引以加速按状态查询
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_task_status '
      'ON ${DbTables.taskQueue} (${TaskColumns.status})',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_task_created '
      'ON ${DbTables.taskQueue} (${TaskColumns.createdAt})',
    );

    debugPrint('[DatabaseService] Tables created (v$version)');
  }

  /// 数据库升级回调。
  ///
  /// 当前仅 v1，后续版本可在此处增加 migration 逻辑。
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint(
      '[DatabaseService] Upgrading DB from v$oldVersion to v$newVersion',
    );

    for (int v = oldVersion + 1; v <= newVersion; v++) {
      await _migrate(db, v);
    }
  }

  /// 逐版本迁移（扩展点）。
  ///
  /// 当前 v1 为初始版本，无需迁移。
  /// 后续新增版本时在此添加 case 分支：
  /// ```dart
  /// switch (targetVersion) {
  ///   case 2:
  ///     await db.execute('ALTER TABLE ...');
  ///     break;
  /// }
  /// ```
  Future<void> _migrate(Database db, int targetVersion) async {
    // v1 → 初始版本，无需迁移
  }

  /// 确保数据库已打开，否则抛出 [StateError]。
  void _ensureOpen() {
    if (!_initialized || _db == null) {
      throw StateError(
        'DatabaseService is not initialized. Call init() first.',
      );
    }
  }

  /// 将 Map 中指定 key 的 String 值还原为 int（`AppConfig.fromMap` 需要 int）。
  void _restoreIntField(Map<String, dynamic> map, String key) {
    if (map.containsKey(key)) {
      map[key] = int.tryParse(map[key] as String) ?? 0;
    }
  }
}

// ══════════════════════════════════════════════════════════
//  SQL DDL
// ══════════════════════════════════════════════════════════

const String _kCreateAppConfigTable = '''
CREATE TABLE IF NOT EXISTS ${DbTables.appConfig} (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''';

const String _kCreateTaskQueueTable = '''
CREATE TABLE IF NOT EXISTS ${DbTables.taskQueue} (
  ${TaskColumns.id} TEXT PRIMARY KEY,
  ${TaskColumns.alistPath} TEXT NOT NULL,
  ${TaskColumns.fileName} TEXT NOT NULL,
  ${TaskColumns.fileSize} INTEGER NOT NULL DEFAULT 0,
  ${TaskColumns.status} TEXT NOT NULL DEFAULT 'PENDING',
  ${TaskColumns.downloadedSize} INTEGER NOT NULL DEFAULT 0,
  ${TaskColumns.rawUrl} TEXT,
  ${TaskColumns.sha256} TEXT,
  ${TaskColumns.fileSample} TEXT,
  ${TaskColumns.uploadFolder} TEXT,
  ${TaskColumns.channelName} TEXT,
  ${TaskColumns.fullId} TEXT,
  ${TaskColumns.filePath} TEXT,
  ${TaskColumns.directUrl} TEXT,
  ${TaskColumns.retryCount} INTEGER NOT NULL DEFAULT 0,
  ${TaskColumns.maxRetries} INTEGER NOT NULL DEFAULT 3,
  ${TaskColumns.errorMessage} TEXT,
  ${TaskColumns.createdAt} TEXT NOT NULL,
  ${TaskColumns.updatedAt} TEXT NOT NULL,
  ${TaskColumns.tmpLocalPath} TEXT
);
''';
