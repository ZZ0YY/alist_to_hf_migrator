import 'task_status.dart';

/// 迁移任务 —— 对应 Alist → ImageBed 的单文件搬运单元。
///
/// 每一条任务的生命周期由 [TaskStatus] 状态机驱动，
/// 数据库中持久化存储，并可通过 [toCloudJson] 同步至云端。
class MigrationTask {
  MigrationTask({
    required this.id,
    required this.alistPath,
    required this.fileName,
    required this.fileSize,
    required this.status,
    this.downloadedSize = 0,
    this.rawUrl,
    this.sha256,
    this.fileSample,
    this.uploadFolder,
    this.channelName,
    this.fullId,
    this.filePath,
    this.directUrl,
    this.retryCount = 0,
    this.maxRetries = 3,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
    this.tmpLocalPath,
    this.uploadProgress = 0.0,
  });

  // ── 基本标识 ──────────────────────────────────────────────

  /// 唯一标识（UUID v4）。
  final String id;

  /// Alist 中的源路径，如 `/videos/2024/demo.mp4`。
  final String alistPath;

  /// 文件名（从路径中提取的纯文件名）。
  final String fileName;

  /// 文件大小（字节）。
  final int fileSize;

  // ── 状态 ──────────────────────────────────────────────────

  /// 当前状态。
  final TaskStatus status;

  /// 已下载字节数（用于断点续传 / 进度展示）。
  final int downloadedSize;

  /// 错误信息（仅在 [TaskStatus.failed] 时非空）。
  final String? errorMessage;

  /// 已重试次数。
  final int retryCount;

  /// 最大重试次数。
  final int maxRetries;

  // ── 下载阶段 ──────────────────────────────────────────────

  /// Alist 下发的原始下载 URL。
  final String? rawUrl;

  /// 本地临时文件路径。
  final String? tmpLocalPath;

  // ── 校验阶段 ──────────────────────────────────────────────

  /// 文件 SHA‑256 十六进制摘要。
  final String? sha256;

  /// 文件前 512 字节的 Base64 编码采样（用于云端去重 / 识别）。
  final String? fileSample;

  // ── 上传阶段 ──────────────────────────────────────────────

  /// 目标图床上的上传文件夹路径。
  final String? uploadFolder;

  /// HF 频道名称。
  final String? channelName;

  /// getUploadUrl 返回的 fullId。
  final String? fullId;

  /// getUploadUrl 返回的服务端存储路径。
  final String? filePath;

  /// 上传进度（0.0 ~ 1.0），用于 HF 上传阶段 UI 展示。
  final double uploadProgress;

  // ── 完成阶段 ──────────────────────────────────────────────

  /// 完成后获得的直链 URL。
  final String? directUrl;

  // ── 时间戳 ────────────────────────────────────────────────

  /// 任务创建时间。
  final DateTime createdAt;

  /// 最后更新时间。
  final DateTime updatedAt;

  // ══════════════════════════════════════════════════════════
  //  序列化 / 反序列化
  // ══════════════════════════════════════════════════════════

  /// 从数据库 Map 构造。
  factory MigrationTask.fromMap(Map<String, dynamic> map) {
    return MigrationTask(
      id: map['id'] as String,
      alistPath: map['alist_path'] as String,
      fileName: map['file_name'] as String,
      fileSize: (map['file_size'] as int?) ?? 0,
      status: TaskStatus.fromString(map['status'] as String? ?? 'PENDING'),
      downloadedSize: (map['downloaded_size'] as int?) ?? 0,
      rawUrl: map['raw_url'] as String?,
      sha256: map['sha256'] as String?,
      fileSample: map['file_sample'] as String?,
      uploadFolder: map['upload_folder'] as String?,
      channelName: map['channel_name'] as String?,
      fullId: map['full_id'] as String?,
      filePath: map['file_path'] as String?,
      directUrl: map['direct_url'] as String?,
      retryCount: (map['retry_count'] as int?) ?? 0,
      maxRetries: (map['max_retries'] as int?) ?? 3,
      errorMessage: map['error_message'] as String?,
      createdAt: _parseDateTime(map['created_at']),
      updatedAt: _parseDateTime(map['updated_at']),
      tmpLocalPath: map['tmp_local_path'] as String?,
      uploadProgress: (map['upload_progress'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// 序列化为数据库 Map。
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'alist_path': alistPath,
      'file_name': fileName,
      'file_size': fileSize,
      'status': status.value,
      'downloaded_size': downloadedSize,
      'raw_url': rawUrl,
      'sha256': sha256,
      'file_sample': fileSample,
      'upload_folder': uploadFolder,
      'channel_name': channelName,
      'full_id': fullId,
      'file_path': filePath,
      'direct_url': directUrl,
      'retry_count': retryCount,
      'max_retries': maxRetries,
      'error_message': errorMessage,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'tmp_local_path': tmpLocalPath,
      'upload_progress': uploadProgress,
    };
  }

  /// 序列化为云端 JSON（排除本地临时路径等敏感/冗余字段）。
  Map<String, dynamic> toCloudJson() {
    return {
      'id': id,
      'alist_path': alistPath,
      'file_name': fileName,
      'file_size': fileSize,
      'status': status.value,
      'downloaded_size': downloadedSize,
      'raw_url': rawUrl,
      'sha256': sha256,
      'file_sample': fileSample,
      'upload_folder': uploadFolder,
      'channel_name': channelName,
      'full_id': fullId,
      'file_path': filePath,
      'direct_url': directUrl,
      'retry_count': retryCount,
      'max_retries': maxRetries,
      'error_message': errorMessage,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// 从云端 JSON 构造。
  factory MigrationTask.fromCloudJson(Map<String, dynamic> json) {
    return MigrationTask(
      id: json['id'] as String,
      alistPath: json['alist_path'] as String,
      fileName: json['file_name'] as String,
      fileSize: (json['file_size'] as int?) ?? 0,
      status: TaskStatus.fromString(json['status'] as String? ?? 'PENDING'),
      downloadedSize: (json['downloaded_size'] as int?) ?? 0,
      rawUrl: json['raw_url'] as String?,
      sha256: json['sha256'] as String?,
      fileSample: json['file_sample'] as String?,
      uploadFolder: json['upload_folder'] as String?,
      channelName: json['channel_name'] as String?,
      fullId: json['full_id'] as String?,
      filePath: json['file_path'] as String?,
      directUrl: json['direct_url'] as String?,
      retryCount: (json['retry_count'] as int?) ?? 0,
      maxRetries: (json['max_retries'] as int?) ?? 3,
      errorMessage: json['error_message'] as String?,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  copyWith
  // ══════════════════════════════════════════════════════════

  /// Sentinel object used to distinguish "explicitly set to null"
  /// from "not provided" in [copyWith].
  static const _sentinel = _Sentinel();

  MigrationTask copyWith({
    String? id,
    String? alistPath,
    String? fileName,
    int? fileSize,
    TaskStatus? status,
    int? downloadedSize,
    String? rawUrl,
    String? sha256,
    String? fileSample,
    String? uploadFolder,
    String? channelName,
    String? fullId,
    String? filePath,
    String? directUrl,
    int? retryCount,
    int? maxRetries,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? tmpLocalPath,
    double? uploadProgress,
    // 使用 sentinel 标记可空字段的显式清除
    Object? clearRawUrl = _sentinel,
    Object? clearSha256 = _sentinel,
    Object? clearFileSample = _sentinel,
    Object? clearUploadFolder = _sentinel,
    Object? clearChannelName = _sentinel,
    Object? clearFullId = _sentinel,
    Object? clearFilePath = _sentinel,
    Object? clearDirectUrl = _sentinel,
    Object? clearErrorMessage = _sentinel,
    Object? clearTmpLocalPath = _sentinel,
  }) {
    return MigrationTask(
      id: id ?? this.id,
      alistPath: alistPath ?? this.alistPath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      status: status ?? this.status,
      downloadedSize: downloadedSize ?? this.downloadedSize,
      rawUrl: clearRawUrl != _sentinel ? null : (rawUrl ?? this.rawUrl),
      sha256: clearSha256 != _sentinel ? null : (sha256 ?? this.sha256),
      fileSample:
          clearFileSample != _sentinel ? null : (fileSample ?? this.fileSample),
      uploadFolder:
          clearUploadFolder != _sentinel ? null : (uploadFolder ?? this.uploadFolder),
      channelName:
          clearChannelName != _sentinel ? null : (channelName ?? this.channelName),
      fullId: clearFullId != _sentinel ? null : (fullId ?? this.fullId),
      filePath: clearFilePath != _sentinel ? null : (filePath ?? this.filePath),
      directUrl: clearDirectUrl != _sentinel ? null : (directUrl ?? this.directUrl),
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      errorMessage:
          clearErrorMessage != _sentinel ? null : (errorMessage ?? this.errorMessage),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tmpLocalPath:
          clearTmpLocalPath != _sentinel ? null : (tmpLocalPath ?? this.tmpLocalPath),
      uploadProgress: uploadProgress ?? this.uploadProgress,
    );
  }

  // ══════════════════════════════════════════════════════════
  //  辅助
  // ══════════════════════════════════════════════════════════

  /// 下载进度（0.0 ~ 1.0），若 fileSize 为 0 则返回 0.0。
  double get downloadProgress {
    if (fileSize <= 0) return 0.0;
    return (downloadedSize / fileSize).clamp(0.0, 1.0);
  }

  /// 是否还能重试。
  bool get canRetry => retryCount < maxRetries && status.isRetryable;

  @override
  String toString() {
    return 'MigrationTask(id: $id, fileName: $fileName, '
        'status: ${status.value}, progress: $downloadedSize/$fileSize)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MigrationTask && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  // ── 私有工具 ──────────────────────────────────────────────

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}

/// Sentinel class for nullable field handling in [MigrationTask.copyWith].
class _Sentinel {
  const _Sentinel();
}
