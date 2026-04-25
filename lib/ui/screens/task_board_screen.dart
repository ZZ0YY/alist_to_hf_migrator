import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:clipboard/clipboard.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/migration_task.dart';
import '../../models/task_status.dart';
import '../../services/scheduler/task_scheduler.dart';
import '../../utils/platform_utils.dart';
import '../widgets/task_card.dart';

/// Task board screen showing all migration tasks with real-time status updates.
///
/// Features:
/// - Summary bar with counts (Total, Running, Done, Failed)
/// - Filter tabs (All, Pending, Running, Done, Failed)
/// - Task cards with status, progress, actions
/// - "Start All" / "Pause All" / "Clear Done" / "Export Links" buttons
/// - Swipe to delete with confirmation
/// - Real-time updates via StreamBuilder from TaskScheduler
class TaskBoardScreen extends StatefulWidget {
  final TaskScheduler? scheduler;

  const TaskBoardScreen({super.key, this.scheduler});

  @override
  State<TaskBoardScreen> createState() => _TaskBoardScreenState();
}

class _TaskBoardScreenState extends State<TaskBoardScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  List<MigrationTask> _allTasks = [];

  /// Filter tabs aligned with TaskStatus enum values.
  static const List<_FilterTab> _tabs = [
    _FilterTab(label: 'All', status: null),
    _FilterTab(label: 'Pending', status: TaskStatus.pending),
    _FilterTab(label: 'Running', status: null, statusGroup: 'active'),
    _FilterTab(label: 'Done', status: TaskStatus.done),
    _FilterTab(label: 'Failed', status: TaskStatus.failed),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Get filtered task list based on current tab.
  List<MigrationTask> get _filteredTasks {
    if (_tabController.index == 0) return _allTasks; // All
    final tab = _tabs[_tabController.index];

    if (tab.statusGroup == 'active') {
      return _allTasks.where((t) => t.status.isActive).toList();
    }
    return _allTasks.where((t) => t.status == tab.status).toList();
  }

  /// Count tasks by status group.
  int _countByTab(int tabIndex) {
    if (tabIndex == 0) return _allTasks.length;
    final tab = _tabs[tabIndex];
    if (tab.statusGroup == 'active') {
      return _allTasks.where((t) => t.status.isActive).length;
    }
    return _allTasks.where((t) => t.status == tab.status).length;
  }

  Future<void> _startAll() async {
    final scheduler = widget.scheduler;
    if (scheduler == null) return;

    if (!scheduler.isRunning) {
      final config = await scheduler.db.loadConfig();
      if (config == null) return;
      await scheduler.start(
        maxConcurrent: config.maxConcurrentTasks,
      );
    } else if (scheduler.isPaused) {
      await scheduler.resume();
    }
  }

  Future<void> _pauseAll() async {
    await widget.scheduler?.pause();
  }

  Future<void> _clearDone() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Completed Tasks?'),
        content: const Text('This will remove all DONE tasks from the list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.scheduler?.clearDoneTasks();
    }
  }

  Future<void> _exportLinks() async {
    final links = await widget.scheduler?.exportDoneLinks() ?? '';
    if (links.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No completed links to export')),
      );
      return;
    }
    await FlutterClipboard.copy(links);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Links copied to clipboard'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _retryFailedTasks() async {
    await widget.scheduler?.retryFailedTasks();
  }

  Future<void> _deleteTask(MigrationTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task?'),
        content: Text('Delete "${task.fileName}" from the queue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.scheduler?.deleteTask(task.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Summary bar
        _buildSummaryBar(),

        // Filter tabs
        _buildFilterTabs(),

        // Action buttons
        _buildActionBar(),

        const Divider(height: 1),

        // Task list
        Expanded(child: _buildTaskList()),
      ],
    );
  }

  Widget _buildSummaryBar() {
    final total = _allTasks.length;
    final running =
        _allTasks.where((t) => t.status.isActive).length;
    final done = _allTasks.where((t) => t.status == TaskStatus.done).length;
    final failed =
        _allTasks.where((t) => t.status == TaskStatus.failed).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('Total', total, Colors.grey),
          _buildSummaryItem('Running', running, Colors.blue),
          _buildSummaryItem('Done', done, Colors.green),
          _buildSummaryItem('Failed', failed, Colors.red),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterTabs() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tabs: _tabs.map((tab) {
        final count = _countByTab(_tabs.indexOf(tab));
        return Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tab.label),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 20),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Start All
            _buildSmallButton(
              label: 'Start All',
              icon: Icons.play_arrow,
              color: Colors.green,
              onPressed: _startAll,
            ),
            const SizedBox(width: 6),

            // Pause All
            _buildSmallButton(
              label: 'Pause',
              icon: Icons.pause,
              color: Colors.orange,
              onPressed: _pauseAll,
            ),
            const SizedBox(width: 6),

            // Retry Failed
            _buildSmallButton(
              label: 'Retry Failed',
              icon: Icons.refresh,
              color: Colors.blue,
              onPressed: _retryFailedTasks,
            ),
            const SizedBox(width: 6),

            // Clear Done
            _buildSmallButton(
              label: 'Clear Done',
              icon: Icons.cleaning_services,
              color: Colors.teal,
              onPressed: _clearDone,
            ),
            const SizedBox(width: 6),

            // Export Links
            _buildSmallButton(
              label: 'Export Links',
              icon: Icons.link,
              color: Colors.purple,
              onPressed: _exportLinks,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskList() {
    // StreamBuilder for real-time updates from TaskScheduler
    final stream = widget.scheduler?.taskStream;

    return StreamBuilder<List<MigrationTask>>(
      stream: stream,
      initialData: const [],
      builder: (context, snapshot) {
        // Update all tasks from stream
        if (snapshot.hasData) {
          _allTasks = snapshot.data!;
        }

        final filtered = _filteredTasks;

        if (_allTasks.isEmpty) {
          return _buildEmptyState();
        }

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.filter_list_off, size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4)),
                const SizedBox(height: 16),
                Text(
                  'No tasks match this filter',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final task = filtered[index];
            return Dismissible(
              key: ValueKey(task.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: Colors.red,
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (_) async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Task?'),
                    content: Text('Delete "${task.fileName}"?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style:
                            TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await widget.scheduler?.deleteTask(task.id);
                }
                return confirmed;
              },
              child: TaskCard(
                task: task,
                onRetry: () => widget.scheduler?.retryTask(task.id),
                onCopyLink: () async {
                  if (task.directUrl != null) {
                    await FlutterClipboard.copy(task.directUrl!);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Link copied to clipboard'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                },
                onOpenLink: () async {
                  if (task.directUrl != null) {
                    final uri = Uri.parse(task.directUrl!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  }
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            'No migration tasks yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Go to the Browser tab to select files',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// Filter tab definition.
class _FilterTab {
  final String label;
  final TaskStatus? status;
  final String? statusGroup; // 'active' for running+hashing+downloading+hfUploading

  const _FilterTab({
    required this.label,
    this.status,
    this.statusGroup,
  });
}
