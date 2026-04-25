import 'package:flutter/material.dart';
import '../../models/migration_task.dart';
import '../../models/task_status.dart';
import '../../utils/platform_utils.dart';

/// A reusable task card widget.
///
/// Displays a [MigrationTask] in a styled [Card] with:
/// - File name and path
/// - Color-coded status chip
/// - Linear progress indicator (for active tasks)
/// - File size display
/// - Retry count badge (if > 0)
/// - Error message (if FAILED)
/// - Direct link with copy/open buttons (if DONE)
/// - Retry button (if FAILED and retryable)
class TaskCard extends StatelessWidget {
  final MigrationTask task;
  final VoidCallback? onRetry;
  final VoidCallback? onCopyLink;
  final VoidCallback? onOpenLink;

  const TaskCard({
    super.key,
    required this.task,
    this.onRetry,
    this.onCopyLink,
    this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: _getBorderSide(theme),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: File name + Status chip
            _buildHeaderRow(theme),
            const SizedBox(height: 4),

            // Row 2: File path (truncated)
            _buildFilePath(theme),
            const SizedBox(height: 6),

            // Row 3: Progress bar (for active tasks)
            if (task.status.isActive) ...[
              _buildProgressBar(theme),
              const SizedBox(height: 6),
            ],

            // Row 4: Metadata (size, retry count)
            _buildMetadataRow(theme),
            const SizedBox(height: 4),

            // Row 5: Error message (if failed)
            if (task.status == TaskStatus.failed && task.errorMessage != null)
              _buildErrorMessage(theme),

            // Row 6: Action buttons
            const SizedBox(height: 6),
            _buildActionButtons(theme),
          ],
        ),
      ),
    );
  }

  // ─── Sub-widgets ───────────────────────────────────────────────────

  Widget _buildHeaderRow(ThemeData theme) {
    return Row(
      children: [
        // File icon
        Icon(
          _getStatusIcon(),
          size: 20,
          color: _getStatusColor(),
        ),
        const SizedBox(width: 8),

        // File name (truncated)
        Expanded(
          child: Text(
            task.fileName,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),

        // Status chip
        _buildStatusChip(theme),

        // Retry badge
        if (task.retryCount > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange, width: 0.5),
            ),
            child: Text(
              'Retry ${task.retryCount}/${task.maxRetries}',
              style: TextStyle(
                fontSize: 10,
                color: Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFilePath(ThemeData theme) {
    return Text(
      task.alistPath,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  Widget _buildProgressBar(ThemeData theme) {
    final color = _getStatusColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: task.uploadProgress,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 2),
        Text(
          '${(task.uploadProgress * 100).toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataRow(ThemeData theme) {
    return Row(
      children: [
        Icon(Icons.description_outlined,
            size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          PlatformUtils.formatFileSize(task.fileSize),
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (task.channelName != null) ...[
          const SizedBox(width: 12),
          Icon(Icons.cloud_outlined,
              size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            task.channelName,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const Spacer(),
        Text(
          _formatRelativeTime(task.updatedAt),
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              task.errorMessage!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.red.shade700,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Retry button (if FAILED and retryable)
        if (task.status == TaskStatus.failed &&
            task.retryCount < task.maxRetries)
          _buildSmallButton(
            icon: Icons.refresh,
            label: 'Retry',
            color: Colors.orange,
            onPressed: onRetry,
          ),

        // Copy link button (if DONE)
        if (task.status == TaskStatus.done && task.directUrl != null) ...[
          _buildSmallButton(
            icon: Icons.copy,
            label: 'Copy Link',
            color: Colors.blue,
            onPressed: onCopyLink,
          ),
          const SizedBox(width: 6),
          _buildSmallButton(
            icon: Icons.open_in_new,
            label: 'Open',
            color: Colors.green,
            onPressed: onOpenLink,
          ),
        ],
      ],
    );
  }

  Widget _buildSmallButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    final (color, bgColor) = _getStatusColors();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _getStatusLabel(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  BorderSide _getBorderSide(ThemeData theme) {
    switch (task.status) {
      case TaskStatus.failed:
        return BorderSide(color: Colors.red.withOpacity(0.5), width: 1);
      case TaskStatus.done:
        return BorderSide(color: Colors.green.withOpacity(0.5), width: 1);
      case TaskStatus.downloading:
      case TaskStatus.hfUploading:
      case TaskStatus.hashing:
        return BorderSide(color: Colors.blue.withOpacity(0.5), width: 1);
      default:
        return BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.5), width: 0.5);
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  IconData _getStatusIcon() {
    switch (task.status) {
      case TaskStatus.pending:
        return Icons.schedule;
      case TaskStatus.hashing:
        return Icons.fingerprint;
      case TaskStatus.downloading:
        return Icons.download;
      case TaskStatus.hfUploading:
        return Icons.cloud_upload;
      case TaskStatus.done:
        return Icons.check_circle;
      case TaskStatus.failed:
        return Icons.error;
      case TaskStatus.paused:
        return Icons.pause_circle;
      case TaskStatus.cancelled:
        return Icons.cancel;
    }
  }

  Color _getStatusColor() {
    switch (task.status) {
      case TaskStatus.pending:
        return Colors.grey;
      case TaskStatus.hashing:
        return Colors.purple;
      case TaskStatus.downloading:
        return Colors.blue;
      case TaskStatus.hfUploading:
        return Colors.indigo;
      case TaskStatus.done:
        return Colors.green;
      case TaskStatus.failed:
        return Colors.red;
      case TaskStatus.paused:
        return Colors.orange;
      case TaskStatus.cancelled:
        return Colors.grey;
    }
  }

  (Color fg, Color bg) _getStatusColors() {
    switch (task.status) {
      case TaskStatus.pending:
        return (Colors.grey.shade700, Colors.grey.shade100);
      case TaskStatus.hashing:
        return (Colors.purple.shade700, Colors.purple.shade50);
      case TaskStatus.downloading:
        return (Colors.blue.shade700, Colors.blue.shade50);
      case TaskStatus.hfUploading:
        return (Colors.indigo.shade700, Colors.indigo.shade50);
      case TaskStatus.done:
        return (Colors.green.shade700, Colors.green.shade50);
      case TaskStatus.failed:
        return (Colors.red.shade700, Colors.red.shade50);
      case TaskStatus.paused:
        return (Colors.orange.shade700, Colors.orange.shade50);
      case TaskStatus.cancelled:
        return (Colors.grey.shade700, Colors.grey.shade100);
    }
  }

  String _getStatusLabel() {
    switch (task.status) {
      case TaskStatus.pending:
        return 'PENDING';
      case TaskStatus.hashing:
        return 'HASHING';
      case TaskStatus.downloading:
        return 'DOWNLOADING';
      case TaskStatus.hfUploading:
        return 'UPLOADING';
      case TaskStatus.done:
        return 'DONE';
      case TaskStatus.failed:
        return 'FAILED';
      case TaskStatus.paused:
        return 'PAUSED';
      case TaskStatus.cancelled:
        return 'CANCELLED';
    }
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
