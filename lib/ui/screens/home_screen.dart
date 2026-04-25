import 'package:flutter/material.dart';
import '../../models/migration_task.dart';
import '../../models/task_status.dart';
import '../screens/browser_screen.dart';
import '../screens/task_board_screen.dart';
import '../screens/settings_screen.dart';
import '../../services/scheduler/task_scheduler.dart';

/// Main home screen with bottom navigation bar (3 tabs).
///
/// Tab 1: Browser — Alist file browser for selecting files to migrate.
/// Tab 2: Tasks — Task board/kanban showing all migration tasks.
/// Tab 3: Settings — App configuration (URLs, credentials, limits).
class HomeScreen extends StatefulWidget {
  final TaskScheduler? scheduler;

  const HomeScreen({super.key, this.scheduler});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Alist-To-HF Migrator',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 1,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Browser
          const BrowserScreen(),
          // Tab 1: Tasks
          TaskBoardScreen(scheduler: widget.scheduler),
          // Tab 2: Settings
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return StreamBuilder<List<MigrationTask>>(
      stream: widget.scheduler?.taskStream,
      initialData: const [],
      builder: (context, snapshot) {
        // Count running tasks for badge
        final tasks = snapshot.data ?? [];
        final runningCount = tasks.where((t) => t.status.isActive).length;

        return NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          height: 65,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.folder_open_outlined),
              selectedIcon: Icon(Icons.folder_open),
              label: 'Browser',
            ),
            NavigationDestination(
              icon: _buildBadgeIcon(
                icon: const Icon(Icons.list_alt_outlined),
                count: runningCount,
              ),
              selectedIcon: _buildBadgeIcon(
                icon: const Icon(Icons.list_alt),
                count: runningCount,
                isSelected: true,
              ),
              label: 'Tasks',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        );
      },
    );
  }

  /// Build an icon with an optional count badge.
  Widget _buildBadgeIcon({
    required Icon icon,
    required int count,
    bool isSelected = false,
  }) {
    if (count <= 0) return icon;
    return Badge(
      label: Text('$count'),
      child: icon,
    );
  }
}
