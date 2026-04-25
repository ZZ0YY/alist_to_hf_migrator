import 'dart:async';
import '../../models/migration_task.dart';
import '../../models/task_status.dart';
import '../../models/app_config.dart';
import '../database/database_service.dart';
import '../api/imgbed_api.dart';
import '../engine/task_state_machine.dart';
import '../logging/log_service.dart';
import '../../utils/platform_utils.dart';

/// Task scheduler with concurrent task execution and round-robin channel selection.
///
/// Manages a pool of concurrent tasks (configurable, default 3). Periodically
/// polls the local DB for PENDING tasks and dispatches them through the
/// [TaskStateMachine]. Emits real-time task list updates via [taskStream].
class TaskScheduler {
  final DatabaseService _db;
  final ImgBedApi _imgBedApi;
  final TaskStateMachine _stateMachine;

  int _maxConcurrent = 3;
  int _runningCount = 0;
  final Set<String> _runningTaskIds = {};
  Timer? _scheduleTimer;
  int _channelRoundRobinIndex = 0;
  List<String> _availableChannels = [];
  bool _isRunning = false;
  bool _isPaused = false;

  /// Stream controller for UI updates — broadcasts the full task list
  /// whenever any task changes state.
  final _taskStreamController = StreamController<List<MigrationTask>>.broadcast();
  Stream<List<MigrationTask>> get taskStream => _taskStreamController.stream;

  /// Optional log callback for UI log display.
  void Function(String message)? onLog;

  TaskScheduler(this._db, this._imgBedApi, this._stateMachine);

  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  int get runningCount => _runningCount;
  int get maxConcurrent => _maxConcurrent;

  /// Expose the database service for UI access (e.g. reading config).
  DatabaseService get db => _db;

  /// Start the scheduler.
  ///
  /// [maxConcurrent] controls the number of parallel task executions.
  /// [channels] optionally provides a pre-loaded list of HF channel names.
  Future<void> start({int maxConcurrent = 3, List<String>? channels}) async {
    if (_isRunning) {
      LogService.instance.warning('Scheduler already running');
      return;
    }

    _maxConcurrent = maxConcurrent;
    _isRunning = true;
    _isPaused = false;

    // Wire up state machine callbacks
    _stateMachine.onProgress = (task) {
      onLog?.call('  ${task.fileName}: ${(task.downloadProgress * 100).toStringAsFixed(1)}%');
    };

    LogService.instance.info('Scheduler started (maxConcurrent=$maxConcurrent)');

    // Load available HF channels
    if (channels != null && channels.isNotEmpty) {
      _availableChannels = channels;
    } else {
      await loadChannels();
    }
    LogService.instance
        .info('Available HF channels: ${_availableChannels.join(", ")}');

    // Start the periodic scheduling loop (every 1 second)
    _scheduleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused) {
        _schedule();
      }
    });

    // Emit initial state
    await _emitTaskUpdate();
  }

  /// Stop the scheduler gracefully.
  ///
  /// Waits for running tasks to complete their current step, then stops
  /// accepting new tasks. Running tasks are marked as PAUSED.
  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;
    _scheduleTimer?.cancel();
    _scheduleTimer = null;

    LogService.instance.info('Scheduler stopping, pausing ${_runningCount} running tasks');

    // Pause all currently running tasks
    for (final taskId in _runningTaskIds.toList()) {
      final task = await _db.getTask(taskId);
      if (task != null && !task.status.isTerminal) {
        final updated = task.copyWith(
          status: TaskStatus.paused,
          updatedAt: DateTime.now(),
        );
        await _db.updateTask(updated);
      }
    }
    _runningTaskIds.clear();
    _runningCount = 0;

    await _emitTaskUpdate();
    LogService.instance.info('Scheduler stopped');
  }

  /// Pause the scheduler without stopping it.
  /// Running tasks will finish their current step, but no new tasks are dispatched.
  Future<void> pause() async {
    _isPaused = true;
    LogService.instance.info('Scheduler paused');
  }

  /// Resume the scheduler after pause.
  Future<void> resume() async {
    _isPaused = false;
    LogService.instance.info('Scheduler resumed');
  }

  /// Main scheduling loop — runs periodically.
  ///
  /// Checks disk watermark, running count, and dispatches the next
  /// PENDING task if capacity is available.
  void _schedule() async {
    if (!_isRunning || _isPaused) return;
    if (_runningCount >= _maxConcurrent) return;

    // Check if there are any pending tasks
    final pendingTasks = await _db.getTasksByStatus(TaskStatus.pending);
    if (pendingTasks.isEmpty) return;

    // Check disk watermark
    final diskOk = await _checkDiskWatermark(5); // default 5GB check
    if (!diskOk) {
      onLog?.call('⚠️ Disk space low — waiting before starting new tasks');
      return;
    }

    // Find a task not already running
    for (final task in pendingTasks) {
      if (_runningTaskIds.contains(task.id)) continue;

      // We have capacity and a task — dispatch it
      await _executeTask(task);
      break; // Re-evaluate on next tick to respect concurrency limit
    }
  }

  /// Execute a single task through the state machine.
  Future<void> _executeTask(MigrationTask task) async {
    _runningTaskIds.add(task.id);
    _runningCount++;
    onLog?.call('▶ Starting: ${task.fileName}');

    try {
      // Select next HF channel
      final channel = _selectChannel();

      // Execute through state machine (returns void)
      await _stateMachine.executeTask(task, channel);

      // Re-read task from DB to get final status
      final updatedTask = await _db.getTask(task.id);
      if (updatedTask != null) {
        if (updatedTask.status == TaskStatus.done) {
          onLog?.call(
              '✅ Done: ${updatedTask.fileName} → ${updatedTask.directUrl}');
        } else if (updatedTask.status == TaskStatus.failed) {
          onLog?.call(
              '❌ Failed: ${updatedTask.fileName} — ${updatedTask.errorMessage}');
        }
      }
    } catch (e) {
      LogService.instance.error('Unexpected error executing task ${task.id}', e);
      onLog?.call('❌ Error: ${task.fileName} — $e');
    } finally {
      _runningTaskIds.remove(task.id);
      _runningCount--;
      await _emitTaskUpdate();
    }
  }

  /// Select next HF channel using round-robin load balancing.
  String _selectChannel() {
    if (_availableChannels.isEmpty) {
      throw StateError('No HF channels available');
    }
    final channel =
        _availableChannels[_channelRoundRobinIndex % _availableChannels.length];
    _channelRoundRobinIndex++;
    return channel;
  }

  /// Load available HF channels from image bed API.
  ///
  /// Filters for channels of type `huggingface` with `active` status.
  Future<void> loadChannels() async {
    try {
      final channels = await _imgBedApi.getChannels();
      _availableChannels = channels
          .where(
              (c) => c.type.toLowerCase() == 'huggingface' && c.status == 'active')
          .map((c) => c.name)
          .toList();

      if (_availableChannels.isEmpty) {
        LogService.instance
            .warning('No active HF channels found in image bed');
      }
    } catch (e) {
      LogService.instance.error('Failed to load HF channels', e);
    }
  }

  /// Retry all failed tasks that haven't exceeded their max retries.
  Future<void> retryFailedTasks() async {
    final failedTasks = await _db.getTasksByStatus(TaskStatus.failed);
    var retriedCount = 0;

    for (final task in failedTasks) {
      if (task.retryCount >= task.maxRetries) continue;

      // Reset to PENDING for re-scheduling
      final updated = task.copyWith(
        status: TaskStatus.pending,
        retryCount: task.retryCount + 1,
        errorMessage: null,
        downloadedSize: 0,
        updatedAt: DateTime.now(),
      );
      await _db.updateTask(updated);
      retriedCount++;
    }

    if (retriedCount > 0) {
      onLog?.call('🔄 Queued $retriedCount failed tasks for retry');
      LogService.instance.info('Retried $retriedCount failed tasks');
      await _emitTaskUpdate();
    }
  }

  /// Retry a specific failed task by ID.
  Future<void> retryTask(String taskId) async {
    final task = await _db.getTask(taskId);
    if (task == null) {
      LogService.instance.warning('Cannot retry: task $taskId not found');
      return;
    }
    if (task.status != TaskStatus.failed) {
      LogService.instance
          .warning('Cannot retry: task ${task.fileName} is not failed');
      return;
    }
    if (task.retryCount >= task.maxRetries) {
      LogService.instance
          .warning('Cannot retry: task ${task.fileName} max retries reached');
      return;
    }

    final updated = task.copyWith(
      status: TaskStatus.pending,
      retryCount: task.retryCount + 1,
      errorMessage: null,
      downloadedSize: 0,
      updatedAt: DateTime.now(),
    );
    await _db.updateTask(updated);
    onLog?.call('🔄 Queued for retry: ${task.fileName} (attempt ${updated.retryCount})');
    await _emitTaskUpdate();
  }

  /// Add new tasks to the queue.
  Future<void> addTasks(List<MigrationTask> tasks) async {
    for (final task in tasks) {
      await _db.insertTask(task);
    }
    onLog?.call('📋 Added ${tasks.length} tasks to queue');
    LogService.instance.info('Added ${tasks.length} tasks to queue');
    await _emitTaskUpdate();
  }

  /// Clear all completed (DONE) tasks from the DB.
  Future<void> clearDoneTasks() async {
    final doneTasks = await _db.getTasksByStatus(TaskStatus.done);
    for (final task in doneTasks) {
      await _db.deleteTask(task.id);
    }
    if (doneTasks.isNotEmpty) {
      onLog?.call('🗑️ Cleared ${doneTasks.length} completed tasks');
      LogService.instance.info('Cleared ${doneTasks.length} done tasks');
      await _emitTaskUpdate();
    }
  }

  /// Broadcast current task list to UI.
  Future<void> _emitTaskUpdate() async {
    try {
      final tasks = await _db.getAllTasks();
      if (!_taskStreamController.isClosed) {
        _taskStreamController.add(tasks);
      }
    } catch (e) {
      LogService.instance.error('Failed to emit task update', e);
    }
  }

  /// Check available disk space against a watermark.
  ///
  /// Returns `true` if at least [requiredGb] GB of free space is available.
  Future<bool> _checkDiskWatermark(int requiredGb) async {
    try {
      final freeGb = await PlatformUtils.getFreeDiskSpaceGb();
      final ok = freeGb >= requiredGb;
      if (!ok) {
        LogService.instance.warning(
            'Disk space low: ${freeGb.toStringAsFixed(1)} GB free, need $requiredGb GB');
      }
      return ok;
    } catch (e) {
      LogService.instance.warning('Could not check disk space: $e — assuming OK');
      return true; // Fail-open: don't block on disk check failure
    }
  }

  /// Delete a task by ID.
  Future<void> deleteTask(String taskId) async {
    await _db.deleteTask(taskId);
    onLog?.call('🗑️ Deleted task: $taskId');
    await _emitTaskUpdate();
  }

  /// Export all completed task direct links as a text list.
  Future<String> exportDoneLinks() async {
    final doneTasks = await _db.getTasksByStatus(TaskStatus.done);
    final links = doneTasks
        .where((t) => t.directUrl != null && t.directUrl!.isNotEmpty)
        .map((t) => '${t.directUrl}\t${t.fileName}')
        .join('\n');
    return links;
  }

  /// Update configuration (e.g., max concurrent).
  Future<void> updateConfig(AppConfig config) async {
    _maxConcurrent = config.maxConcurrentTasks;
    LogService.instance.info(
        'Scheduler config updated: maxConcurrent=$_maxConcurrent');
  }

  /// Dispose resources.
  void dispose() {
    _scheduleTimer?.cancel();
    _taskStreamController.close();
  }
}
