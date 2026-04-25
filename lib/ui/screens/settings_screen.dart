import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_config.dart';
import '../../services/database/database_service.dart';
import '../../services/api/alist_api.dart';
import '../../services/api/imgbed_api.dart';
import '../../services/sync/cloud_sync_service.dart';
import '../../services/logging/log_service.dart';

/// Settings screen with form fields for all configuration options.
///
/// Includes Alist credentials, Image Bed config, sync settings,
/// concurrency limits, and action buttons for testing connections,
/// cloud sync, and clearing tasks.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _imgBedUrlController = TextEditingController();
  final _imgBedTokenController = TextEditingController();
  final _syncPathController = TextEditingController();

  double _maxConcurrent = 3;
  double _diskWatermark = 5;
  double _maxRetries = 3;

  bool _isLoading = true;
  bool _isSaving = false;
  String _statusMessage = '';
  bool _statusIsError = false;

  late final DatabaseService _db;
  late final AlistApi _alistApi;
  late final ImgBedApi _imgBedApi;

  @override
  void initState() {
    super.initState();
    _db = DatabaseService();
    _alistApi = AlistApi();
    _imgBedApi = ImgBedApi();
    _loadConfig();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _imgBedUrlController.dispose();
    _imgBedTokenController.dispose();
    _syncPathController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _db.loadConfig();
      if (config == null) {
        setState(() => _isLoading = false);
        return;
      }
      _urlController.text = config.alistBaseUrl;
      _usernameController.text = config.alistUsername;
      _passwordController.text = config.alistPassword;
      _imgBedUrlController.text = config.imgBedBaseUrl;
      _imgBedTokenController.text = config.imgBedApiToken;
      _syncPathController.text = config.syncBasePath;
      _maxConcurrent = (config.maxConcurrentTasks).toDouble();
      _diskWatermark = (config.diskWatermarkGb).toDouble();
      _maxRetries = (config.maxRetries).toDouble();
      setState(() => _isLoading = false);
    } catch (e) {
      LogService.instance.error('Failed to load config', e);
      setState(() {
        _isLoading = false;
        _statusMessage = 'Failed to load config: $e';
        _statusIsError = true;
      });
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _statusMessage = '';
    });

    try {
      final config = AppConfig(
        alistBaseUrl: _urlController.text.trim(),
        alistUsername: _usernameController.text.trim(),
        alistPassword: _passwordController.text.trim(),
        imgBedBaseUrl: _imgBedUrlController.text.trim(),
        imgBedApiToken: _imgBedTokenController.text.trim(),
        syncBasePath: _syncPathController.text.trim(),
        maxConcurrentTasks: _maxConcurrent.round(),
        diskWatermarkGb: _diskWatermark.round(),
        maxRetries: _maxRetries.round(),
      );

      await _db.saveConfig(config);
      LogService.instance.info('Config saved successfully');

      setState(() {
        _isSaving = false;
        _statusMessage = '✅ Configuration saved successfully';
        _statusIsError = false;
      });
    } catch (e) {
      LogService.instance.error('Failed to save config', e);
      setState(() {
        _isSaving = false;
        _statusMessage = '❌ Failed to save: $e';
        _statusIsError = true;
      });
    }
  }

  Future<void> _testAlistConnection() async {
    _setStatus('Testing Alist connection...', false);
    final baseUrl = _urlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (baseUrl.isEmpty || username.isEmpty || password.isEmpty) {
      _setStatus('Please enter Alist URL, username, and password', true);
      return;
    }
    try {
      final api = AlistApi(baseUrl: baseUrl);
      final success = await api.login(username, password);
      if (success) {
        _setStatus('✅ Alist connection successful', false);
      } else {
        _setStatus('❌ Alist login failed', true);
      }
    } catch (e) {
      _setStatus('❌ Alist error: $e', true);
    }
  }

  Future<void> _testImgBedConnection() async {
    _setStatus('Testing Image Bed connection...', false);
    final baseUrl = _imgBedUrlController.text.trim();
    final token = _imgBedTokenController.text.trim();
    if (baseUrl.isEmpty || token.isEmpty) {
      _setStatus('Please enter Image Bed URL and Token', true);
      return;
    }
    try {
      final api = ImgBedApi(baseUrl: baseUrl, apiToken: token);
      await api.getChannels();
      _setStatus('✅ Image Bed connection successful', false);
    } catch (e) {
      _setStatus('❌ Image Bed error: $e', true);
    }
  }

  Future<void> _pushConfigToCloud() async {
    _setStatus('Pushing config to cloud...', false);
    try {
      await _saveConfig();
      final config = await _db.loadConfig();
      if (config == null) {
        _setStatus('❌ No config found to push', true);
        return;
      }
      final syncService = CloudSyncService(_db, _alistApi);
      await syncService.pushToCloud(config);
      _setStatus('✅ Config pushed to cloud', false);
    } catch (e) {
      _setStatus('❌ Push failed: $e', true);
    }
  }

  Future<void> _pullConfigFromCloud() async {
    _setStatus('Pulling config from cloud...', false);
    try {
      final config = AppConfig(
        alistBaseUrl: _urlController.text.trim(),
        alistUsername: _usernameController.text.trim(),
        alistPassword: _passwordController.text.trim(),
        syncBasePath: _syncPathController.text.trim(),
      );
      final syncService = CloudSyncService(_db, _alistApi);
      final tasks = await syncService.pullFromCloud(config);
      _setStatus('✅ Pulled ${tasks.length} tasks from cloud', false);
    } catch (e) {
      _setStatus('❌ Pull failed: $e', true);
    }
  }

  Future<void> _clearAllTasks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Tasks?'),
        content: const Text(
            'This will permanently delete ALL tasks from the local database. '
            'This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _db.clearAllTasks();
        _setStatus('🗑️ All tasks cleared', false);
      } catch (e) {
        _setStatus('❌ Failed to clear tasks: $e', true);
      }
    }
  }

  void _setStatus(String message, bool isError) {
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ─── Alist Configuration ──────────────────────────────────
            _buildSectionHeader('Alist Configuration'),
            _buildTextField(
              controller: _urlController,
              label: 'Alist Base URL',
              hint: 'https://alist.example.com',
              prefixIcon: Icons.dns,
              validator: (v) =>
                  v?.trim().isEmpty ? 'Required' : null,
            ),
            _buildTextField(
              controller: _usernameController,
              label: 'Alist Username',
              prefixIcon: Icons.person,
              validator: (v) =>
                  v?.trim().isEmpty ? 'Required' : null,
            ),
            _buildTextField(
              controller: _passwordController,
              label: 'Alist Password',
              prefixIcon: Icons.lock,
              obscureText: true,
              validator: (v) =>
                  v?.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 8),

            // ─── Image Bed Configuration ──────────────────────────────
            _buildSectionHeader('Image Bed Configuration'),
            _buildTextField(
              controller: _imgBedUrlController,
              label: 'Image Bed Base URL',
              hint: 'https://imgbed.example.com',
              prefixIcon: Icons.cloud_upload,
            ),
            _buildTextField(
              controller: _imgBedTokenController,
              label: 'Image Bed API Token',
              prefixIcon: Icons.vpn_key,
              obscureText: true,
            ),
            const SizedBox(height: 8),

            // ─── Sync Settings ────────────────────────────────────────
            _buildSectionHeader('Sync Settings'),
            _buildTextField(
              controller: _syncPathController,
              label: 'Sync Base Path',
              hint: '/migration_sync',
              prefixIcon: Icons.sync,
            ),
            const SizedBox(height: 8),

            // ─── Performance Settings ─────────────────────────────────
            _buildSectionHeader('Performance Settings'),
            _buildSliderRow(
              label: 'Max Concurrent Tasks',
              value: _maxConcurrent,
              min: 1,
              max: 10,
              divisions: 9,
              onChanged: (v) => setState(() => _maxConcurrent = v),
              valueLabel: _maxConcurrent.round().toString(),
            ),
            _buildSliderRow(
              label: 'Disk Watermark (GB)',
              value: _diskWatermark,
              min: 1,
              max: 50,
              divisions: 49,
              onChanged: (v) => setState(() => _diskWatermark = v),
              valueLabel: _diskWatermark.round().toString(),
            ),
            _buildSliderRow(
              label: 'Max Retries',
              value: _maxRetries,
              min: 1,
              max: 10,
              divisions: 9,
              onChanged: (v) => setState(() => _maxRetries = v),
              valueLabel: _maxRetries.round().toString(),
            ),
            const SizedBox(height: 16),

            // ─── Status Message ───────────────────────────────────────
            if (_statusMessage.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _statusIsError
                      ? Colors.red.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _statusIsError ? Colors.red : Colors.green,
                  ),
                ),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: _statusIsError ? Colors.red : Colors.green.shade700,
                    fontSize: 13,
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // ─── Action Buttons ──────────────────────────────────────
            // Save
            _buildActionButton(
              label: _isSaving ? 'Saving...' : 'Save Configuration',
              icon: Icons.save,
              onPressed: _isSaving ? null : _saveConfig,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 8),

            // Test Connections
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    label: 'Test Alist',
                    icon: Icons.wifi_find,
                    onPressed: _testAlistConnection,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    label: 'Test ImgBed',
                    icon: Icons.cloud_done,
                    onPressed: _testImgBedConnection,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Cloud Sync
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    label: 'Push to Cloud',
                    icon: Icons.cloud_upload,
                    onPressed: _pushConfigToCloud,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    label: 'Pull from Cloud',
                    icon: Icons.cloud_download,
                    onPressed: _pullConfigFromCloud,
                    color: Colors.teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Clear All
            _buildActionButton(
              label: 'Clear All Tasks',
              icon: Icons.delete_forever,
              onPressed: _clearAllTasks,
              color: Colors.red,
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─── Helper widgets ───────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? prefixIcon,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
          border: const OutlineInputBorder(),
          filled: true,
        ),
        validator: validator,
        textInputAction: TextInputAction.next,
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueLabel,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              valueLabel,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
