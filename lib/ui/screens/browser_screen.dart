import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/migration_task.dart';
import '../../models/app_config.dart';
import '../../services/database/database_service.dart';
import '../../services/api/alist_api.dart';
import '../../services/logging/log_service.dart';
import '../../utils/platform_utils.dart';

/// Alist file browser screen with breadcrumb navigation, multi-select,
/// grid/list view toggle, and file type icons.
///
/// Allows users to browse their Alist instance, select files, and
/// add them to the migration queue.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final DatabaseService _db = DatabaseService();
  final AlistApi _alistApi = AlistApi();

  // Navigation
  String _currentPath = '/';
  final List<_BreadcrumbItem> _breadcrumbs = [
    _breadcrumbItem('Root', '/'),
  ];

  // Files
  List<AlistFileItem> _files = [];
  bool _isLoading = true;
  String? _error;
  bool _isGridView = false;

  // Selection
  final Set<String> _selectedPaths = {};

  // Config
  AppConfig? _config;

  @override
  void initState() {
    super.initState();
    _loadConfigAndBrowse();
  }

  Future<void> _loadConfigAndBrowse() async {
    try {
      _config = await _db.loadConfig();
      if (_config != null && _config!.isAlistConfigured) {
        await _alistApi.login(
          _config!.alistBaseUrl,
          _config!.alistUsername,
          _config!.alistPassword,
        );
      }
      await _browsePath('/');
    } catch (e) {
      LogService.instance.error('Failed to initialize browser', e);
      setState(() {
        _isLoading = false;
        _error = 'Failed to connect to Alist. Check settings.';
      });
    }
  }

  Future<void> _browsePath(String path) async {
    if (_config == null || !_config!.isAlistConfigured) {
      setState(() {
        _isLoading = false;
        _error = 'Alist not configured. Go to Settings first.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _selectedPaths.clear();
    });

    try {
      final files = await _alistApi.listFiles(_config!.alistBaseUrl, path);
      // Sort: directories first, then by name
      files.sort((a, b) {
        if (a.isDir && !b.isDir) return -1;
        if (!a.isDir && b.isDir) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      // Update breadcrumbs
      _updateBreadcrumbs(path);

      setState(() {
        _currentPath = path;
        _files = files;
        _isLoading = false;
      });
    } catch (e) {
      LogService.instance.error('Failed to browse $path', e);
      setState(() {
        _isLoading = false;
        _error = 'Failed to load directory: $e';
      });
    }
  }

  void _updateBreadcrumbs(String path) {
    final segments = path == '/' ? [''] : path.split('/').where((s) => s.isNotEmpty).toList();

    _breadcrumbs.clear();
    _breadcrumbs.add(_breadcrumbItem('Root', '/'));

    String cumulativePath = '';
    for (final segment in segments) {
      cumulativePath = '$cumulativePath/$segment';
      _breadcrumbs.add(_breadcrumbItem(segment, cumulativePath));
    }
  }

  _BreadcrumbItem _breadcrumbItem(String label, String path) {
    return _BreadcrumbItem(label: label, path: path);
  }

  void _navigateToPath(String path) {
    _browsePath(path);
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  void _selectAll() {
    setState(() {
      // Select only files (not directories)
      for (final file in _files) {
        if (!file.isDir) {
          _selectedPaths.add('$_currentPath/${file.name}'.replaceAll('//', '/'));
        }
      }
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedPaths.clear();
    });
  }

  Future<void> _addToQueue() async {
    if (_selectedPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No files selected')),
      );
      return;
    }

    final selectedFiles = _files.where((f) {
      final fullPath = '$_currentPath/${f.name}'.replaceAll('//', '/');
      return _selectedPaths.contains(fullPath) && !f.isDir;
    }).toList();

    // Create migration tasks
    final tasks = selectedFiles.map((file) {
      final fullPath = '$_currentPath/${file.name}'.replaceAll('//', '/');
      return MigrationTask(
        id: fullPath.hashCode.toRadixString(36) +
            DateTime.now().millisecondsSinceEpoch.toRadixString(36),
        alistPath: fullPath,
        fileName: file.name,
        fileSize: file.size,
      );
    }).toList();

    try {
      await _db.insertTasks(tasks);
      LogService.instance.info('Added ${tasks.length} files to queue');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${tasks.length} files to migration queue'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _selectedPaths.clear());
      }
    } catch (e) {
      LogService.instance.error('Failed to add tasks', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add tasks: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Breadcrumb navigation
          _buildBreadcrumbs(),
          const Divider(height: 1),

          // Action bar
          _buildActionBar(),
          const Divider(height: 1),

          // File list
          Expanded(child: _buildFileList()),

          // Bottom selection bar
          if (_selectedPaths.isNotEmpty) _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _breadcrumbs.map((crumb) {
            final isLast = crumb == _breadcrumbs.last;
            return Row(
              children: [
                if (crumb != _breadcrumbs.first)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.chevron_right, size: 16),
                  ),
                InkWell(
                  onTap: isLast
                      ? null
                      : () => _navigateToPath(crumb.path),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    child: Text(
                      crumb.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isLast ? FontWeight.bold : FontWeight.normal,
                        color: isLast
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                        decoration: isLast
                            ? TextDecoration.none
                            : TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text(
            '${_files.length} items',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // View toggle
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
            tooltip: _isGridView ? 'List view' : 'Grid view',
            iconSize: 20,
          ),
          // Select All
          TextButton.icon(
            onPressed: _selectAll,
            icon: const Icon(Icons.select_all, size: 16),
            label: const Text('All', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
            ),
          ),
          // Deselect All
          TextButton.icon(
            onPressed: _deselectAll,
            icon: const Icon(Icons.deselect, size: 16),
            label: const Text('None', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _browsePath(_currentPath),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              'Empty directory',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    if (_isGridView) {
      return _buildGridView();
    }
    return _buildListView();
  }

  Widget _buildListView() {
    return RefreshIndicator(
      onRefresh: () => _browsePath(_currentPath),
      child: ListView.builder(
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final file = _files[index];
          final fullPath =
              '$_currentPath/${file.name}'.replaceAll('//', '/');
          final isSelected = _selectedPaths.contains(fullPath);

          return ListTile(
            leading: _buildFileCheckbox(file, fullPath, isSelected),
            title: Text(
              file.name,
              style: TextStyle(
                fontWeight: file.isDir ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: file.isDir
                ? null
                : Text(PlatformUtils.formatFileSize(file.size),
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
            trailing: file.isDir
                ? const Icon(Icons.chevron_right)
                : Icon(_getFileIcon(file.name),
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.7)),
            onLongPress: () => _toggleSelection(fullPath),
            onTap: () {
              if (isSelected) {
                _toggleSelection(fullPath);
              } else if (file.isDir) {
                _browsePath(fullPath);
              } else {
                _toggleSelection(fullPath);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildGridView() {
    return RefreshIndicator(
      onRefresh: () => _browsePath(_currentPath),
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.85,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final file = _files[index];
          final fullPath =
              '$_currentPath/${file.name}'.replaceAll('//', '/');
          final isSelected = _selectedPaths.contains(fullPath);

          return InkWell(
            onTap: () {
              if (isSelected) {
                _toggleSelection(fullPath);
              } else if (file.isDir) {
                _browsePath(fullPath);
              } else {
                _toggleSelection(fullPath);
              }
            },
            onLongPress: () => _toggleSelection(fullPath),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary, width: 2)
                    : null,
                color: isSelected
                    ? Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withOpacity(0.3)
                    : Theme.of(context).colorScheme.surfaceContainerLow,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    file.isDir
                        ? Icons.folder
                        : _getGridFileIconData(file.name),
                    size: 40,
                    color: file.isDir
                        ? Colors.amber
                        : Theme.of(context).colorScheme.primary.withOpacity(0.7),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      file.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  if (!file.isDir)
                    Text(
                      PlatformUtils.formatFileSize(file.size),
                      style: TextStyle(
                        fontSize: 10,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFileCheckbox(AlistFileItem file, String fullPath, bool isSelected) {
    return Checkbox(
      value: isSelected,
      onChanged: (_) => _toggleSelection(fullPath),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_selectedPaths.length} file(s) selected',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Calculate total size
            FutureBuilder<String>(
              future: _calculateSelectedSize(),
              initialData: '',
              builder: (context, snapshot) {
                final sizeStr = snapshot.data ?? '';
                if (sizeStr.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    sizeStr,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                );
              },
            ),
            ElevatedButton.icon(
              onPressed: _addToQueue,
              icon: const Icon(Icons.add_to_queue),
              label: const Text('Add to Queue'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _calculateSelectedSize() async {
    int totalBytes = 0;
    for (final file in _files) {
      final fullPath = '$_currentPath/${file.name}'.replaceAll('//', '/');
      if (_selectedPaths.contains(fullPath) && !file.isDir) {
        totalBytes += file.size;
      }
    }
    return PlatformUtils.formatFileSize(totalBytes);
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'svg':
        return Icons.image;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'flv':
        return Icons.videocam;
      case 'mp3':
      case 'flac':
      case 'wav':
      case 'aac':
      case 'ogg':
        return Icons.audiotrack;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  IconData _getGridFileIconData(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'svg':
        return Icons.image;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'flv':
        return Icons.movie;
      case 'mp3':
      case 'flac':
      case 'wav':
      case 'aac':
      case 'ogg':
        return Icons.music_note;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }
}

/// Simple breadcrumb data class.
class _BreadcrumbItem {
  final String label;
  final String path;
  const _BreadcrumbItem({required this.label, required this.path});
}
