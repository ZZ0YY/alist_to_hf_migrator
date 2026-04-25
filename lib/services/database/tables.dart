/// 数据库表名、列名集中常量定义。
///
/// 所有与 SQL 交互的代码应引用此文件中的常量，
/// 以保证 schema 与代码的一致性并避免拼写错误。
class DbTables {
  DbTables._();

  static const String appConfig = 'app_config';
  static const String taskQueue = 'task_queue';
}

/// `app_config` 表的 key 列可选值。
class ConfigKeys {
  ConfigKeys._();

  static const String alistBaseUrl = 'alist_base_url';
  static const String alistUsername = 'alist_username';
  static const String alistPassword = 'alist_password';
  static const String alistToken = 'alist_token';
  static const String imgBedBaseUrl = 'img_bed_base_url';
  static const String imgBedApiToken = 'img_bed_api_token';
  static const String syncBasePath = 'sync_base_path';
  static const String maxConcurrentTasks = 'max_concurrent_tasks';
  static const String diskWatermarkGb = 'disk_watermark_gb';
  static const String maxRetries = 'max_retries';

  /// 所有配置 key 的列表（便于批量读写）。
  static const List<String> allKeys = [
    alistBaseUrl,
    alistUsername,
    alistPassword,
    alistToken,
    imgBedBaseUrl,
    imgBedApiToken,
    syncBasePath,
    maxConcurrentTasks,
    diskWatermarkGb,
    maxRetries,
  ];
}

/// `task_queue` 表的列名。
class TaskColumns {
  TaskColumns._();

  static const String id = 'id';
  static const String alistPath = 'alist_path';
  static const String fileName = 'file_name';
  static const String fileSize = 'file_size';
  static const String status = 'status';
  static const String downloadedSize = 'downloaded_size';
  static const String rawUrl = 'raw_url';
  static const String sha256 = 'sha256';
  static const String fileSample = 'file_sample';
  static const String uploadFolder = 'upload_folder';
  static const String channelName = 'channel_name';
  static const String fullId = 'full_id';
  static const String filePath = 'file_path';
  static const String directUrl = 'direct_url';
  static const String retryCount = 'retry_count';
  static const String maxRetries = 'max_retries';
  static const String errorMessage = 'error_message';
  static const String createdAt = 'created_at';
  static const String updatedAt = 'updated_at';
  static const String tmpLocalPath = 'tmp_local_path';
}
