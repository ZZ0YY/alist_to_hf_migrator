/// 任务状态枚举 —— 对应迁移任务状态机中的全部节点。
///
/// 状态流转：
///   PENDING → CHECKING → DOWNLOADING → HASHING → HF_PREPARE → HF_UPLOADING → HF_COMMIT → DONE
///   （任何非终态 → FAILED）
enum TaskStatus {
  pending('PENDING'),
  checking('CHECKING'),
  downloading('DOWNLOADING'),
  hashing('HASHING'),
  hfPrepare('HF_PREPARE'),
  hfUploading('HF_UPLOADING'),
  hfCommit('HF_COMMIT'),
  done('DONE'),
  failed('FAILED');

  const TaskStatus(this.value);

  /// 序列化时使用的字符串标识。
  final String value;

  /// 是否为终态（不可再流转）。
  bool get isTerminal {
    switch (this) {
      case TaskStatus.done:
      case TaskStatus.failed:
        return true;
      default:
        return false;
    }
  }

  /// 是否为活跃状态（正在进行中）。
  bool get isActive {
    switch (this) {
      case TaskStatus.checking:
      case TaskStatus.downloading:
      case TaskStatus.hashing:
      case TaskStatus.hfPrepare:
      case TaskStatus.hfUploading:
      case TaskStatus.hfCommit:
        return true;
      default:
        return false;
    }
  }

  /// 是否可以重试。
  ///
  /// 当任务处于 DOWNLOADING / HASHING / HF_PREPARE / HF_UPLOADING / HF_COMMIT
  /// 时若因网络等原因失败，可从当前阶段重新开始。
  bool get isRetryable {
    switch (this) {
      case TaskStatus.downloading:
      case TaskStatus.hashing:
      case TaskStatus.hfPrepare:
      case TaskStatus.hfUploading:
      case TaskStatus.hfCommit:
        return true;
      default:
        return false;
    }
  }

  /// 中文显示名称。
  String get displayName {
    switch (this) {
      case TaskStatus.pending:
        return '等待中';
      case TaskStatus.checking:
        return '检查中';
      case TaskStatus.downloading:
        return '下载中';
      case TaskStatus.hashing:
        return '校验中';
      case TaskStatus.hfPrepare:
        return '准备上传';
      case TaskStatus.hfUploading:
        return '上传中';
      case TaskStatus.hfCommit:
        return '提交中';
      case TaskStatus.done:
        return '已完成';
      case TaskStatus.failed:
        return '失败';
    }
  }

  /// 从字符串解析 [TaskStatus]。
  ///
  /// 如果 [value] 不匹配任何已知状态，则默认返回 [TaskStatus.pending]。
  static TaskStatus fromString(String value) {
    return TaskStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => TaskStatus.pending,
    );
  }
}
