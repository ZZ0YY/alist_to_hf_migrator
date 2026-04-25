# Alist-To-HF Migrator

## 项目简介

Alist 到 HuggingFace 的跨平台文件迁移工具。支持 **Windows 桌面端** 和 **Android 手机端**，通过 HuggingFace LFS 大文件直传模式，将 Alist 文件搬运到自托管图床，保留目录结构并获取直链。

## 功能特性

- **Local-First + Cloud-Sync 双轨存储** — 本地 SQLite 优先，云端同步回退
- **HTTP Range 断点续传下载** — 中断后自动从断点继续，不重复下载
- **下载后静态 SHA-256 校验** — 确保文件完整性，损坏自动重试
- **HuggingFace S3 预签名 URL 直传** — 支持单文件 PUT 和分片上传两种模式
- **9 状态任务状态机** — 全生命周期覆盖，状态转换可视化
- **可配置并发数 + 磁盘水位线** — 灵活控制资源占用
- **轮询负载均衡** — 多 HF 渠道自动轮询，避免单点限速
- **图床去重（CHECKING 状态）** — 上传前检查图床是否已存在，避免重复存储
- **智能启动恢复** — 本地优先、云端回退，断电/崩溃后自动恢复未完成任务
- **Windows 系统托盘最小化** — 后台运行不干扰工作
- **Android WakeLock 防休眠** — 迁移过程中保持设备唤醒
- **直链复制 & Markdown 导出** — 一键复制/批量导出图床直链

## 技术栈

| 技术 | 说明 |
|------|------|
| Flutter 3.24+ / Dart 3.0+ | 跨平台 UI 框架 |
| SQLite (sqflite + sqflite_common_ffi) | 本地数据持久化 |
| Dio | HTTP 客户端（断点续传、并发请求） |
| Provider | 状态管理 |
| window_manager | Windows 窗口管理 & 系统托盘 |
| wakelock_plus | Android 防休眠 |

## 项目结构

```
alist_to_hf_migrator/
├── lib/
│   ├── main.dart                    # 应用入口 & 服务容器
│   ├── app.dart                     # MaterialApp & 主题
│   ├── models/                      # 数据模型
│   │   ├── app_config.dart          # 全局配置
│   │   ├── migration_task.dart      # 迁移任务
│   │   ├── task_status.dart         # 状态枚举
│   │   └── alist_file_node.dart     # Alist 文件节点
│   ├── services/
│   │   ├── database/                # SQLite 数据层
│   │   │   ├── database_service.dart
│   │   │   └── tables.dart
│   │   ├── api/                     # API 客户端
│   │   │   ├── alist_api.dart
│   │   │   └── imgbed_api.dart
│   │   ├── engine/                  # 核心引擎
│   │   │   ├── download_engine.dart  # 断点下载
│   │   │   ├── hash_engine.dart      # SHA-256 校验
│   │   │   ├── hf_upload_engine.dart  # HF 直传
│   │   │   └── task_state_machine.dart # 状态机
│   │   ├── scheduler/
│   │   │   └── task_scheduler.dart   # 并发调度
│   │   ├── sync/
│   │   │   └── cloud_sync_service.dart # 云端同步
│   │   └── logging/
│   │       └── log_service.dart
│   ├── ui/
│   │   ├── screens/
│   │   │   ├── home_screen.dart
│   │   │   ├── browser_screen.dart
│   │   │   ├── task_board_screen.dart
│   │   │   └── settings_screen.dart
│   │   └── widgets/
│   │       └── task_card.dart
│   └── utils/
│       ├── path_encoder.dart
│       └── platform_utils.dart
├── android/                         # Android 平台配置
├── windows/                         # Windows 平台配置
├── .github/workflows/               # CI/CD
│   ├── build.yml
│   └── release.yml
├── scripts/                         # 构建脚本
│   ├── build-windows.bat
│   ├── build-android.sh
│   └── build-all.sh
├── pubspec.yaml
└── analysis_options.yaml
```

## 环境要求

### 本地构建

| 依赖 | 版本要求 |
|------|----------|
| Flutter SDK | 3.24.0+ (stable channel) |
| Dart SDK | 3.0.0+ |
| Android SDK | minSdk 21, targetSdk 34 |
| Java | 17（推荐 [Temurin JDK](https://adoptium.net/)） |
| Visual Studio 2022 | C++ 桌面开发工作负载 + Windows 10/11 SDK |

> **提示：** 仅构建 Windows 版本无需安装 Android SDK；仅构建 Android 版本无需安装 Visual Studio。

## 本地构建指南

### 1. 克隆项目

```bash
git clone https://github.com/your-username/alist-to-hf-migrator.git
cd alist-to-hf-migrator
```

### 2. 安装依赖

```bash
flutter pub get
```

### 3. 构建 Windows 版本

```bash
flutter build windows --release
```

构建产物位于 `build/windows/x64/runner/Release/`。

也可以使用脚本：

```cmd
:: Windows CMD / PowerShell
scripts\build-windows.bat
```

### 4. 构建 Android APK

```bash
flutter build apk --release
```

构建产物位于 `build/app/outputs/flutter-apk/app-release.apk`。

也可以使用脚本：

```bash
# Linux / macOS / WSL
bash scripts/build-android.sh
```

### 5. 同时构建两个平台

```bash
bash scripts/build-all.sh
```

所有产物位于 `dist/` 目录。

## GitHub Actions 自动构建

### CI 构建（推送 / PR 自动触发）

向 `main` 分支推送或创建 PR 时，自动构建 Windows 和 Android 版本。

**手动触发：**

1. 进入 GitHub 仓库 → **Actions** → `build`
2. 点击 **"Run workflow"**
3. 可选填 `version` 和 `flutter_version`
4. 产物在 Actions 页面的 **Artifacts** 区域下载

### 发布构建（打 Tag 触发）

```bash
# 创建版本标签
git tag v1.0.0
git push origin v1.0.0
```

自动构建并创建 GitHub Release，附带：

- `alist-to-hf-migrator-v1.0.0-windows-x64.zip`
- `alist-to-hf-migrator-v1.0.0-android.apk`

## 使用指南

### 首次配置

1. 打开 App → **Settings** 标签
2. 填写 Alist 地址、用户名、密码
3. 点击 **"Test Alist"** 验证连接
4. 填写图床地址和 API Token
5. 点击 **"Test ImgBed"** 验证连接
6. 调整并发数、磁盘水位线等参数
7. 点击 **"Save Configuration"** 保存

### 文件迁移

1. 切换到 **Browser** 标签
2. 浏览 Alist 文件目录
3. 点击 / 长按选择文件
4. 点击 **"Add to Queue"** 加入迁移队列
5. 切换到 **Tasks** 标签
6. 点击 **"Start All"** 开始迁移

### 监控进度

- 实时查看每个任务的状态和进度
- 下载 / 上传进度条
- 成功后点击 **"Copy Link"** 复制直链
- 点击 **"Export Links"** 批量导出所有直链

## 状态机

```
PENDING → CHECKING → DOWNLOADING → HASHING → HF_PREPARE → HF_UPLOADING → HF_COMMIT → DONE
    ↓           ↓            ↓           ↓            ↓              ↓             ↓
  (任何错误可重试 → FAILED)
```

各状态说明：

| 状态 | 说明 |
|------|------|
| `PENDING` | 任务已入队，等待调度 |
| `CHECKING` | 查询图床是否已存在（去重） |
| `DOWNLOADING` | 从 Alist 断点续传下载 |
| `HASHING` | SHA-256 完整性校验 |
| `HF_PREPARE` | 申请 HuggingFace 预签名 URL |
| `HF_UPLOADING` | 上传到 HuggingFace S3 |
| `HF_COMMIT` | 提交 LFS Pointer |
| `DONE` | 迁移完成 |
| `FAILED` | 失败（可重试） |

## 绝对红线

> 以下规则在开发中**必须严格遵守**，违反将导致不可预知的 Bug：

- **Alist 表单上传路径必须 URL 编码** — 含中文 / 特殊字符的路径不编码会导致服务端 404
- **HF 分片上传 ETag 双引号必须保留** — 去掉双引号会导致 Commit 阶段 400
- **下载临时文件必须在 `finally` 块中清理** — 异常中断后残留临时文件会占用磁盘空间
- **状态转换前必须先持久化到 DB** — 崩溃恢复依赖 DB 中的最新状态

## 许可证

[MIT License](LICENSE)
