/// Alist 文件/目录节点 —— 对应 `/api/fs/list` 返回的 `data.content[]` 条目。
///
/// 仅包含展示与筛选所需的基本字段；完整字段可按需扩展。
class AlistFileNode {
  const AlistFileNode({
    required this.name,
    required this.size,
    required this.isDir,
    required this.modified,
    required this.provider,
  });

  /// 文件 / 目录名称。
  final String name;

  /// 文件大小（字节）。目录时通常为 0 或 -1。
  final int size;

  /// 是否为目录。
  final bool isDir;

  /// 最后修改时间。
  final DateTime modified;

  /// 存储提供者名称（如 `Local`、`AliyundriveOpen`）。
  final String provider;

  // ══════════════════════════════════════════════════════════
  //  构造
  // ══════════════════════════════════════════════════════════

  /// 从 Alist API JSON 构造。
  ///
  /// Alist `/api/fs/list` 返回的每个节点大致如下：
  /// ```json
  /// {
  ///   "name": "video.mp4",
  ///   "size": 104857600,
  ///   "is_dir": false,
  ///   "modified": "2024-06-15T10:30:00Z",
  ///   "provider": "AliyundriveOpen"
  /// }
  /// ```
  factory AlistFileNode.fromJson(Map<String, dynamic> json) {
    return AlistFileNode(
      name: json['name'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      isDir: json['is_dir'] as bool? ?? false,
      modified: _parseDateTime(json['modified']),
      provider: json['provider'] as String? ?? '',
    );
  }

  // ══════════════════════════════════════════════════════════
  //  计算属性
  // ══════════════════════════════════════════════════════════

  /// 文件扩展名（含点号，小写），如 `.mp4`。
  ///
  /// 目录、无扩展名、或以 `.` 开头的隐藏文件返回空字符串。
  String get extension {
    if (isDir) return '';
    if (name.startsWith('.')) {
      // 隐藏文件：`.bashrc` → ''
      final lastDot = name.lastIndexOf('.');
      if (lastDot == 0) return '';
      return name.substring(lastDot).toLowerCase();
    }
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == name.length - 1) return '';
    return name.substring(dotIndex).toLowerCase();
  }

  /// MIME 类型。
  ///
  /// 基于常见扩展名推断；未知类型返回 `application/octet-stream`。
  String get mimeType {
    if (isDir) return 'inode/directory';
    final ext = extension;
    return _mimeMap[ext] ?? 'application/octet-stream';
  }

  /// 格式化文件大小。
  String get formattedSize {
    if (isDir || size < 0) return '-';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // ══════════════════════════════════════════════════════════
  //  辅助
  // ══════════════════════════════════════════════════════════

  @override
  String toString() =>
      'AlistFileNode(name: $name, size: $size, isDir: $isDir, '
      'provider: $provider)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlistFileNode &&
        other.name == name &&
        other.size == size &&
        other.isDir == isDir &&
        other.modified == modified &&
        other.provider == provider;
  }

  @override
  int get hashCode => Object.hash(name, size, isDir, modified, provider);

  // ── 私有工具 ──────────────────────────────────────────────

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }
}

// ══════════════════════════════════════════════════════════════
//  常用 MIME 类型查找表（与 mime 包对齐）
// ══════════════════════════════════════════════════════════════
const Map<String, String> _mimeMap = {
  // ── 图片 ──
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.bmp': 'image/bmp',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.tiff': 'image/tiff',
  '.tif': 'image/tiff',
  '.avif': 'image/avif',
  '.heic': 'image/heic',
  '.heif': 'image/heif',
  // ── 视频 ──
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
  '.mkv': 'video/x-matroska',
  '.avi': 'video/x-msvideo',
  '.mov': 'video/quicktime',
  '.flv': 'video/x-flv',
  '.wmv': 'video/x-ms-wmv',
  '.ts': 'video/mp2t',
  '.m3u8': 'application/vnd.apple.mpegurl',
  // ── 音频 ──
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
  '.flac': 'audio/flac',
  '.aac': 'audio/aac',
  '.ogg': 'audio/ogg',
  '.opus': 'audio/opus',
  '.m4a': 'audio/mp4',
  '.wma': 'audio/x-ms-wma',
  // ── 文档 ──
  '.pdf': 'application/pdf',
  '.doc': 'application/msword',
  '.docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xls': 'application/vnd.ms-excel',
  '.xlsx':
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.ppt': 'application/vnd.ms-powerpoint',
  '.pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  '.txt': 'text/plain',
  '.md': 'text/markdown',
  '.csv': 'text/csv',
  '.rtf': 'application/rtf',
  // ── 压缩 ──
  '.zip': 'application/zip',
  '.rar': 'application/vnd.rar',
  '.7z': 'application/x-7z-compressed',
  '.tar': 'application/x-tar',
  '.gz': 'application/gzip',
  '.bz2': 'application/x-bzip2',
  '.xz': 'application/x-xz',
  // ── 代码 / 脚本 ──
  '.json': 'application/json',
  '.xml': 'application/xml',
  '.yaml': 'application/x-yaml',
  '.yml': 'application/x-yaml',
  '.html': 'text/html',
  '.htm': 'text/html',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.mjs': 'application/javascript',
  '.ts': 'application/typescript',
  '.dart': 'application/dart',
  '.py': 'text/x-python',
  '.java': 'text/x-java-source',
  '.c': 'text/x-c',
  '.cpp': 'text/x-c++',
  '.h': 'text/x-c',
  '.sh': 'application/x-sh',
  '.bat': 'application/x-bat',
  '.sql': 'application/sql',
  // ── 字体 ──
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  // ── APK / 安装包 ──
  '.apk': 'application/vnd.android.package-archive',
  '.dmg': 'application/x-apple-diskimage',
  '.exe': 'application/octet-stream',
  // ── 其他 ──
  '.torrent': 'application/x-bittorrent',
  '.srt': 'text/plain',
  '.ass': 'text/plain',
  '.vtt': 'text/vtt',
  '.log': 'text/plain',
  '.ini': 'text/plain',
  '.conf': 'text/plain',
  '.cfg': 'text/plain',
  '.env': 'text/plain',
};
