import 'dart:convert';

/// 应用全局配置 —— 持久化在本地数据库中。
///
/// 包含 Alist 连接信息、图床连接信息、以及全局迁移策略参数。
class AppConfig {
  const AppConfig({
    this.alistBaseUrl = 'http://localhost:5244',
    this.alistUsername = 'admin',
    this.alistPassword = '',
    this.alistToken = '',
    this.imgBedBaseUrl = 'https://your.domain',
    this.imgBedApiToken = '',
    this.syncBasePath = '/migrator_sync',
    this.maxConcurrentTasks = 3,
    this.diskWatermarkGb = 10,
    this.maxRetries = 3,
  });

  // ── Alist ─────────────────────────────────────────────────

  /// Alist 服务地址。
  final String alistBaseUrl;

  /// Alist 用户名。
  final String alistUsername;

  /// Alist 密码。
  final String alistPassword;

  /// Alist 认证令牌（登录后缓存）。
  final String alistToken;

  // ── 图床 (ImageBed) ──────────────────────────────────────

  /// 图床服务基础地址。
  final String imgBedBaseUrl;

  /// 图床 API 令牌。
  final String imgBedApiToken;

  // ── 同步 / 策略 ──────────────────────────────────────────

  /// 云端同步根路径。
  final String syncBasePath;

  /// 最大并行任务数。
  final int maxConcurrentTasks;

  /// 磁盘水位线（GB），低于此值时暂停下载以避免磁盘满。
  final int diskWatermarkGb;

  /// 单个任务最大重试次数。
  final int maxRetries;

  // ══════════════════════════════════════════════════════════
  //  序列化 / 反序列化
  // ══════════════════════════════════════════════════════════

  /// 从数据库 Map（key-value 行）构造。
  factory AppConfig.fromMap(Map<String, dynamic> map) {
    return AppConfig(
      alistBaseUrl: (map['alist_base_url'] as String?) ??
          'http://localhost:5244',
      alistUsername:
          (map['alist_username'] as String?) ?? 'admin',
      alistPassword: (map['alist_password'] as String?) ?? '',
      alistToken: (map['alist_token'] as String?) ?? '',
      imgBedBaseUrl:
          (map['img_bed_base_url'] as String?) ?? 'https://your.domain',
      imgBedApiToken: (map['img_bed_api_token'] as String?) ?? '',
      syncBasePath: (map['sync_base_path'] as String?) ?? '/migrator_sync',
      maxConcurrentTasks:
          (map['max_concurrent_tasks'] as int?) ?? 3,
      diskWatermarkGb: (map['disk_watermark_gb'] as int?) ?? 10,
      maxRetries: (map['max_retries'] as int?) ?? 3,
    );
  }

  /// 序列化为数据库 Map（key-value 行）。
  Map<String, dynamic> toMap() {
    return {
      'alist_base_url': alistBaseUrl,
      'alist_username': alistUsername,
      'alist_password': alistPassword,
      'alist_token': alistToken,
      'img_bed_base_url': imgBedBaseUrl,
      'img_bed_api_token': imgBedApiToken,
      'sync_base_path': syncBasePath,
      'max_concurrent_tasks': maxConcurrentTasks,
      'disk_watermark_gb': diskWatermarkGb,
      'max_retries': maxRetries,
    };
  }

  /// 序列化为 JSON 字符串。
  String toJson() => jsonEncode(toMap());

  /// 从 JSON 字符串构造。
  factory AppConfig.fromJson(String source) {
    return AppConfig.fromMap(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }

  // ══════════════════════════════════════════════════════════
  //  copyWith
  // ══════════════════════════════════════════════════════════

  AppConfig copyWith({
    String? alistBaseUrl,
    String? alistUsername,
    String? alistPassword,
    String? alistToken,
    String? imgBedBaseUrl,
    String? imgBedApiToken,
    String? syncBasePath,
    int? maxConcurrentTasks,
    int? diskWatermarkGb,
    int? maxRetries,
  }) {
    return AppConfig(
      alistBaseUrl: alistBaseUrl ?? this.alistBaseUrl,
      alistUsername: alistUsername ?? this.alistUsername,
      alistPassword: alistPassword ?? this.alistPassword,
      alistToken: alistToken ?? this.alistToken,
      imgBedBaseUrl: imgBedBaseUrl ?? this.imgBedBaseUrl,
      imgBedApiToken: imgBedApiToken ?? this.imgBedApiToken,
      syncBasePath: syncBasePath ?? this.syncBasePath,
      maxConcurrentTasks: maxConcurrentTasks ?? this.maxConcurrentTasks,
      diskWatermarkGb: diskWatermarkGb ?? this.diskWatermarkGb,
      maxRetries: maxRetries ?? this.maxRetries,
    );
  }

  // ══════════════════════════════════════════════════════════
  //  辅助
  // ══════════════════════════════════════════════════════════

  /// Alist 配置是否基本完整（baseUrl 和 password 均非空）。
  bool get isAlistReady =>
      alistBaseUrl.isNotEmpty && alistPassword.isNotEmpty;

  /// Alias for isAlistReady (used by some UI components).
  bool get isAlistConfigured => isAlistReady;

  /// 图床配置是否基本完整（baseUrl 和 apiToken 均非空）。
  bool get isImgBedReady =>
      imgBedBaseUrl.isNotEmpty && imgBedApiToken.isNotEmpty;

  /// Alias for isImgBedReady (used by some UI components).
  bool get isImgBedConfigured => isImgBedReady;

  /// 全部配置是否就绪。
  bool get isFullyReady => isAlistReady && isImgBedReady;

  /// 磁盘水位线字节数。
  int get diskWatermarkBytes => diskWatermarkGb * 1024 * 1024 * 1024;

  @override
  String toString() {
    return 'AppConfig(alistBaseUrl: $alistBaseUrl, '
        'imgBedBaseUrl: $imgBedBaseUrl, '
        'maxConcurrentTasks: $maxConcurrentTasks, '
        'maxRetries: $maxRetries)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppConfig &&
        other.alistBaseUrl == alistBaseUrl &&
        other.alistUsername == alistUsername &&
        other.alistPassword == alistPassword &&
        other.alistToken == alistToken &&
        other.imgBedBaseUrl == imgBedBaseUrl &&
        other.imgBedApiToken == imgBedApiToken &&
        other.syncBasePath == syncBasePath &&
        other.maxConcurrentTasks == maxConcurrentTasks &&
        other.diskWatermarkGb == diskWatermarkGb &&
        other.maxRetries == maxRetries;
  }

  @override
  int get hashCode => Object.hash(
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
      );
}
