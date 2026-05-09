// PublicNode VPS
// Copyright (C) 2026 mohammadhasanulislam
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../app/constants.dart';
import '../utils/vps_api_utils.dart';
import '../services/navigation_service.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import './vps_notification.dart';
import './vps_progress_overlay.dart';
import './vps_bounce.dart';
import './file_explorer/file_explorer_sidebar.dart';

class FileExplorerTab extends StatefulWidget {
  final String baseUrl;
  final String password;
  final String initialPath;

  const FileExplorerTab({
    super.key,
    required this.baseUrl,
    required this.password,
    this.initialPath = '/kaggle/working',
  });

  @override
  State<FileExplorerTab> createState() => _FileExplorerTabState();
}

class _FileExplorerTabState extends State<FileExplorerTab> {
  late String _currentPath;
  List<dynamic> _files = [];
  bool _loading = false;
  String? _error;
  bool _isHomeExpanded = true;
  final Map<String, List<dynamic>> _pathCache = {}; // Zero-Latency Cache

  // V6: Advanced Clipboard & Selection State
  String? _clipboardPath;
  bool _isCut = false;
  final Set<String> _selectedPaths = {};
  bool _selectionMode = false;
  bool _isSidebarOpen = false;
  bool _isSearchActive = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _fetchFiles();
    _preemptiveFetch(); // Warm up the cache for ultra-smooth navigation
  }

  @override
  void dispose() {
    _pathCache.clear();
    super.dispose();
  }

  Future<void> _preemptiveFetch() async {
    for (var sub in FileExplorerSidebar.homeSubFolders) {
      _fetchFiles(path: sub['path']!, silent: true);
    }
    _fetchFiles(path: '/', silent: true);
    _fetchFiles(path: '/tmp', silent: true);
  }

  Future<void> _fetchFiles({String? path, bool silent = false}) async {
    final targetPath = path ?? _currentPath;

    // Serve from cache if available for instant UI response
    if (_pathCache.containsKey(targetPath) && !silent) {
      setState(() {
        _files = _pathCache[targetPath]!;
        _loading = false;
      });
      // Continue to fetch in background to refresh cache
    }

    if (!silent) {
      setState(() {
        _loading = _pathCache.containsKey(targetPath) ? false : true;
        _error = null;
      });
    }
    try {
      final uri = VpsApiUtils.buildUri(widget.baseUrl, '/api/files/list', {
        'path': targetPath,
      });

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${widget.password}',
          'X-PublicNode-Key': widget.password,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (!mounted) return;
        final data = json.decode(response.body);
        _pathCache[targetPath] = data; // Update cache

        setState(() {
          if (targetPath == _currentPath) {
            _files = data;
          }
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'Error: ${response.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to fetch directory: $e';
        _loading = false;
      });
    }
  }

  Future<void> _triggerHfSync() async {
    VpsNotification.processing(
      context,
      'Zipping your files and saving to backup storage...',
      title: 'BACKING_UP',
    );
    try {
      final url = widget.baseUrl
          .trim()
          .replaceFirst('wss://', 'https://')
          .replaceFirst('ws://', 'http:' '//');
      final response = await http.get(
        Uri.parse(
          '${url.endsWith('/') ? url : '$url/'}api/vault/hf/sync',
        ),
        headers: {'X-PublicNode-Key': widget.password},
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (response.statusCode == 202 || response.statusCode == 200) {
        VpsNotification.dismissProcessing();
        VpsNotification.success(
          context,
          'Your files have been safely backed up.',
          title: 'BACKUP_DONE',
        );
        _fetchFiles(); // Refresh files after sync
      } else {
        VpsNotification.dismissProcessing();
        VpsNotification.error(
          context,
          'Backup failed. Please try again.',
          title: 'BACKUP_FAILED',
        );
      }
    } catch (e) {
      VpsNotification.dismissProcessing();
      if (!mounted) return;
      VpsNotification.error(context, 'Backup failed: $e');
    }
  }

  Future<void> _deleteItem(String path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SovColors.surface,
        title: const Text(
          'Delete Forever?',
          style: TextStyle(color: SovColors.accent),
        ),
        content: Text(
          'Are you sure you want to delete this forever?\n$path',
          style: const TextStyle(color: SovColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: SovColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'DELETE',
              style: TextStyle(color: SovColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // V6: Optimistic UI Update (Industry Grade)
    final originalFiles = List<dynamic>.from(_files);
    setState(() {
      _files.removeWhere((f) => f['path'] == path);
    });

    try {
      final uri = VpsApiUtils.buildUri(widget.baseUrl, '/api/files/delete');
      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${widget.password}',
              'X-PublicNode-Key': widget.password,
              'Content-Type': 'application/json',
            },
            body: json.encode({'path': path}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        if (mounted) {
          setState(() => _files = originalFiles);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Delete failed: ${response.statusCode}',
                style: const TextStyle(color: SovColors.textPrimary),
              ),
              backgroundColor: SovColors.error,
            ),
          );
        }
      } else {
        // Success: already handled optimistically, just refresh cache in background
        _fetchFiles(silent: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _files = originalFiles);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Delete failed: $e',
              style: const TextStyle(color: SovColors.textPrimary),
            ),
            backgroundColor: SovColors.error,
          ),
        );
      }
    }
  }

  void _navigateTo(String path) {
    setState(() => _currentPath = path);
    _fetchFiles();
  }

  String _formatBytes(int bytes) {
    if (bytes < 0) return '--';
    if (bytes == 0) return '0 B'; // Industrial accuracy: 0 bytes is a real size
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatRelativeTime(int timestampSecs) {
    if (timestampSecs <= 0) return '--';
    final date = DateTime.fromMillisecondsSinceEpoch(
      timestampSecs * 1000,
    ).toLocal();
    final now = DateTime.now();
    final diff = now.difference(date);

    // Formatting helper for time
    String timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    // Desktop-class precision logic
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';

    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final fileDate = DateTime(date.year, date.month, date.day);

    if (fileDate == today) return 'Today, $timeStr';
    if (fileDate == yesterday) return 'Yesterday, $timeStr';

    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[date.weekday - 1]}, $timeStr';
    }

    return '${date.day}/${date.month}/${date.year}';
  }

  IconData _getFileIcon(String filename, bool isDir) {
    if (isDir) return Icons.folder;
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
        return Icons.folder_zip_outlined;
      case 'py':
        return Icons.terminal;
      case 'ipynb':
        return Icons.book_outlined;
      case 'txt':
      case 'md':
      case 'json':
      case 'yaml':
      case 'yml':
        return Icons.description_outlined;
      case 'png':
      case 'jpg':
      case 'jpeg':
        return Icons.image_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color _getFileIconColor(String filename, bool isDir) {
    if (isDir) return Colors.blueAccent; // Modern GNOME blue folder
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
        return Colors.orangeAccent;
      case 'py':
      case 'ipynb':
        return Colors.yellowAccent;
      case 'png':
      case 'jpg':
      case 'jpeg':
        return Colors.purpleAccent;
      default:
        return SovColors.textSecondary;
    }
  }

  Widget _buildBreadcrumbs() {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();

    if (isMobile && _isSearchActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          color: SovColors.background,
          border: Border(bottom: BorderSide(color: SovColors.borderGlass)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: SovColors.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: SovColors.borderGlass),
                ),
                child: TextField(
                  autofocus: true,
                  style: const TextStyle(
                      color: SovColors.textPrimary, fontSize: 13),
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: const InputDecoration(
                    hintText: 'Search files...',
                    hintStyle: TextStyle(color: SovColors.textSecondary),
                    prefixIcon:
                        Icon(Icons.search, size: 16, color: SovColors.accent),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, color: SovColors.textSecondary),
              onPressed: () => setState(() {
                _isSearchActive = false;
                _searchQuery = '';
              }),
            ),
          ],
        ),
      );
    }

    List<Widget> children = [
      if (isMobile)
        IconButton(
          icon: const Icon(Icons.menu, color: SovColors.accent, size: 20),
          onPressed: () => setState(() => _isSidebarOpen = true),
        ),
      VpsBounce(
        onTap: () => _navigateTo('/'),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Icon(
            Icons.home_outlined,
            color: SovColors.textSecondary,
            size: 18,
          ),
        ),
      ),
      const Text(' / ', style: TextStyle(color: SovColors.textSecondary)),
    ];

    String builtPath = '';
    for (int i = 0; i < parts.length; i++) {
      builtPath += '/${parts[i]}';
      final isLast = i == parts.length - 1;
      final navPath = builtPath;

      children.add(
        VpsBounce(
          onTap: () => _navigateTo(navPath),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              parts[i],
              style: TextStyle(
                color: isLast ? SovColors.textPrimary : SovColors.textSecondary,
                fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );

      if (!isLast) {
        children.add(
          const Text(' / ', style: TextStyle(color: SovColors.textSecondary)),
        );
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: SovColors.background,
        border: Border(bottom: BorderSide(color: SovColors.borderGlass)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: children),
            ),
          ),
          if (_currentPath.startsWith('/kaggle/working/vault'))
            _iconBtn(Icons.auto_awesome, _triggerHfSync,
                color: SovColors.accent),
          if (_selectionMode) ...[
            _iconBtn(Icons.delete_sweep,
                _selectedPaths.isEmpty ? null : _batchDelete,
                color: SovColors.error),
            _iconBtn(
                Icons.close,
                () => setState(() {
                      _selectionMode = false;
                      _selectedPaths.clear();
                    })),
          ] else ...[
            if (!isMobile) ...[
              _iconBtn(
                  Icons.checklist, () => setState(() => _selectionMode = true)),
              _iconBtn(Icons.create_new_folder_outlined,
                  () => _showCreateDialog(isFolder: true)),
              _iconBtn(Icons.note_add_outlined,
                  () => _showCreateDialog(isFolder: false)),
            ] else
              PopupMenuButton<String>(
                icon: const Icon(Icons.add_circle_outline,
                    color: SovColors.accent, size: 20),
                color: SovColors.surface,
                onSelected: (val) {
                  if (val == 'select') setState(() => _selectionMode = true);
                  if (val == 'folder') _showCreateDialog(isFolder: true);
                  if (val == 'file') _showCreateDialog(isFolder: false);
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                      value: 'select', child: Text('Select Mode')),
                  const PopupMenuItem(
                      value: 'folder', child: Text('New Folder')),
                  const PopupMenuItem(value: 'file', child: Text('New File')),
                ],
              ),
          ],
          _iconBtn(Icons.cloud_download_outlined, _showDownloadDialog),
          _iconBtn(Icons.upload_file_outlined, _uploadFile),
          if (isMobile)
            _iconBtn(Icons.search, () => setState(() => _isSearchActive = true))
          else ...[
            _iconBtn(Icons.refresh, _fetchFiles),
            const SizedBox(width: 8),
            _buildDesktopSearch(),
          ],
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {Color? color}) {
    return VpsBounce(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(
          icon,
          color: color ?? SovColors.textSecondary,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildDesktopSearch() {
    return Container(
      width: 150,
      height: 32,
      decoration: BoxDecoration(
        color: SovColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SovColors.borderGlass),
      ),
      child: TextField(
        style: const TextStyle(color: SovColors.textPrimary, fontSize: 12),
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: const InputDecoration(
          hintText: 'Search...',
          hintStyle: TextStyle(color: SovColors.textSecondary),
          prefixIcon:
              Icon(Icons.search, size: 14, color: SovColors.textSecondary),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.pickFiles(
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final fileName = file.name;
      final bytes = file.bytes;

      if (bytes == null) {
        if (!mounted) return;
        VpsNotification.error(context, 'Could not read file data');
        return;
      }

      // Show Industry-Grade Overlay
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => VpsProgressOverlay(status: 'Uploading $fileName...'),
      );

      try {
        final path = '${_currentPath == '/' ? '' : _currentPath}/$fileName';
        final uri = VpsApiUtils.buildUri(widget.baseUrl, '/api/files/write');

        final response = await http
            .post(
              uri,
              headers: {
                'X-PublicNode-Key': widget.password,
                'Content-Type': 'application/json',
              },
              body: json.encode({
                'path': path,
                'content': base64Encode(bytes),
                'encoding': 'base64',
              }),
            )
            .timeout(const Duration(seconds: 60));

        if (!mounted) return;
        Navigator.pop(context); // Close Overlay

        if (response.statusCode == 200) {
          if (!mounted) return;
          VpsNotification.success(
              context, 'File uploaded successfully. $fileName is now ready.',
              title: 'UPLOAD_DONE');
          _fetchFiles();
        } else {
          if (!mounted) return;
          VpsNotification.error(
            context,
            'Upload failed. Please check the file.',
            title: 'UPLOAD_FAILED',
          );
        }
      } finally {
        if (mounted && Navigator.canPop(context)) {
          // Extra safety to ensure dialog is gone
        }
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        VpsNotification.error(context, 'Upload Error: $e');
      }
    }
  }

  Future<void> _downloadFile(String path, String name) async {
    try {
      // Show Industry-Grade Overlay
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => VpsProgressOverlay(status: 'Downloading $name...'),
      );

      final uri = VpsApiUtils.buildUri(widget.baseUrl, '/api/files/read', {
        'path': path,
        'encoding': 'base64',
      });

      final response = await http.get(
        uri,
        headers: {'X-PublicNode-Key': widget.password},
      ).timeout(const Duration(seconds: 60));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final bytes = base64Decode(data['content']);

        Directory? downloadDir;
        if (Platform.isAndroid) {
          downloadDir = Directory('/storage/emulated/0/Download');
          if (!await downloadDir.exists()) {
            downloadDir = await getExternalStorageDirectory();
          }
        } else {
          downloadDir = await getDownloadsDirectory();
        }

        if (downloadDir == null) {
          if (!mounted) return;
          Navigator.pop(context);
          VpsNotification.error(context, 'Could not find download directory');
          return;
        }

        final localFile = File('${downloadDir.path}/$name');
        await localFile.writeAsBytes(bytes);

        if (!mounted) return;
        Navigator.pop(context); // Close Overlay
        VpsNotification.success(
            context, 'Download complete. File saved to: ${localFile.path}',
            title: 'DOWNLOAD_DONE');
      } else {
        if (!mounted) return;
        Navigator.pop(context);
        VpsNotification.error(
          context,
          'Download Failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        VpsNotification.error(context, 'Download Error: $e');
      }
    }
  }

  Future<void> _archiveAction(String path, String name, bool extract) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VpsProgressOverlay(
        status: extract ? 'Extracting $name...' : 'Zipping $name...',
      ),
    );

    try {
      final endpoint = extract ? '/api/files/extract' : '/api/files/archive';
      final uri = VpsApiUtils.buildUri(widget.baseUrl, endpoint);

      final response = await http
          .post(
            uri,
            headers: {
              'X-PublicNode-Key': widget.password,
              'Content-Type': 'application/json',
            },
            body: json.encode({'path': path}),
          )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;
      Navigator.pop(context); // Close Overlay

      if (response.statusCode == 200) {
        VpsNotification.success(context, 'Zip operation finished.',
            title: 'ZIP_READY');
        _fetchFiles();
      } else {
        VpsNotification.error(
          context,
          'Operation failed. Please check the file.',
          title: 'ERROR',
        );
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        VpsNotification.error(context, 'Operation Error: $e');
      }
    }
  }

  void _showDownloadDialog() {
    final urlController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SovColors.surface,
        title: const Text(
          'Download from Web',
          style: TextStyle(color: SovColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              autofocus: true,
              style: const TextStyle(color: SovColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://example.com/file.zip',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              style: const TextStyle(color: SovColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'File Name',
                hintText: 'file.zip',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = urlController.text.trim();
              final name = nameController.text.trim();
              if (url.isEmpty || name.isEmpty) return;

              Navigator.pop(ctx);
              _performRemoteDownload(url, name);
            },
            child: const Text('DOWNLOAD'),
          ),
        ],
      ),
    );
  }

  Future<void> _pushToVault(String path, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SovColors.surface,
        title: const Text('Confirm Vault Push'),
        content: Text(
            'Are you sure you want to archive "$name" to your private System Vault?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ARCHIVE'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final uri = VpsApiUtils.buildUri(
          widget.baseUrl, '/api/vault/push', {'path': path});
      final response = await http.get(
        uri,
        headers: {'X-PublicNode-Key': widget.password},
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (response.statusCode == 202) {
        VpsNotification.success(context, 'Started saving a backup for $name.',
            title: 'SAVING');
      } else {
        VpsNotification.error(context, 'Push failed: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      VpsNotification.error(context, 'Push error: $e');
    }
  }

  Future<void> _performRemoteDownload(String url, String filename) async {
    VpsNotification.info(context, 'Starting download: $filename');
    try {
      final destPath = '${_currentPath == '/' ? '' : _currentPath}/$filename';
      final uri = VpsApiUtils.buildUri(
        widget.baseUrl,
        '/api/files/remote-download',
        {'url': url, 'dest_path': destPath},
      );

      final response = await http.post(uri, headers: {
        'X-PublicNode-Key': widget.password
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && mounted) {
        VpsNotification.success(context, 'Background download started.',
            title: 'DOWNLOADING');
        _fetchFiles(); // Refresh to see if it appeared (though might take time)
      } else {
        if (mounted) {
          VpsNotification.error(context, 'Failed: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) VpsNotification.error(context, 'Error: $e');
    }
  }

  Widget _buildListHeader() {
    final isMobile = MediaQuery.of(context).size.width < 800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SovColors.borderGlass)),
      ),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: Text(
              'Name',
              style: TextStyle(
                color: SovColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (!isMobile) ...[
            const Expanded(
              flex: 1,
              child: Text(
                'Size',
                style: TextStyle(
                  color: SovColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Expanded(
              flex: 1,
              child: Text(
                'Last Changed',
                style: TextStyle(
                  color: SovColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          const SizedBox(width: 48), // Action column space
        ],
      ),
    );
  }

  Widget _buildFileRow(Map<String, dynamic> file) {
    final bool isDir = file['isDir'] ?? false;
    final String name = file['name'] ?? '';
    final int size = file['size'] ?? 0;
    final int mtime = file['mtime'] ?? 0;
    final int itemCount = file['itemCount'] ?? 0;

    String sizeText;
    if (isDir) {
      if (itemCount == -1) {
        sizeText = 'No Access';
      } else {
        sizeText = '$itemCount ${itemCount == 1 ? 'item' : 'items'}';
      }
    } else {
      sizeText = _formatBytes(size);
    }

    final isSelected = _selectedPaths.contains(file['path']);
    final isPendingCut = _clipboardPath == file['path'] && _isCut;

    final isMobile = MediaQuery.of(context).size.width < 800;

    return VpsBounce(
      onTap: _selectionMode
          ? () => setState(
                () => isSelected
                    ? _selectedPaths.remove(file['path'])
                    : _selectedPaths.add(file['path']),
              )
          : (isDir
              ? () => _navigateTo(
                    '${_currentPath == '/' ? '' : _currentPath}/$name',
                  )
              : null),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showFileContextMenu(details.globalPosition, file),
        onLongPress: () => _showFileContextMenu(Offset.zero, file),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isPendingCut ? 0.4 : 1.0,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: isMobile ? 12 : 10,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? SovColors.accent.withValues(alpha: 0.1)
                  : Colors.transparent,
              border: const Border(
                bottom: BorderSide(color: SovColors.borderGlass, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                if (_selectionMode) ...[
                  Icon(
                    isSelected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color:
                        isSelected ? SovColors.accent : SovColors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Icon(
                        _getFileIcon(name, isDir),
                        color: _getFileIconColor(name, isDir),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: SovColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (isMobile)
                              Text(
                                '$sizeText • ${_formatRelativeTime(mtime)}',
                                style: const TextStyle(
                                  color: SovColors.textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isMobile) ...[
                  Expanded(
                    flex: 1,
                    child: Text(
                      sizeText,
                      style: const TextStyle(
                        color: SovColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      _formatRelativeTime(mtime),
                      style: const TextStyle(
                        color: SovColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                SizedBox(
                  width: 48,
                  height: 48,
                  child: VpsBounce(
                    onTap: () {}, // Handled by gesture detector for position
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) =>
                          _showFileContextMenu(details.globalPosition, file),
                      child: const Icon(
                        Icons.more_vert,
                        color: SovColors.textSecondary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // V6: Cross-Module Navigation Bridge
    final nav = context.watch<NavigationService>();
    if (nav.pendingExplorerPath != null) {
      final path = nav.pendingExplorerPath!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nav.clearExplorerPath();
        _navigateTo(path);
      });
    }

    final filteredFiles = _files.where((f) {
      final name = (f['name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    final isMobile = MediaQuery.of(context).size.width < 800;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
          if (_selectedPaths.length == 1) {
            setState(() {
              _clipboardPath = _selectedPaths.first;
              _isCut = false;
            });
            VpsNotification.info(context, 'Copied to clipboard');
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): () {
          if (_selectedPaths.length == 1) {
            setState(() {
              _clipboardPath = _selectedPaths.first;
              _isCut = true;
            });
            VpsNotification.info(context, 'Cut to clipboard');
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
          if (_clipboardPath != null) {
            _pasteItem(_currentPath);
          }
        },
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (_selectedPaths.isNotEmpty) {
            _batchDelete();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Row(
              children: [
                if (!isMobile)
                  FileExplorerSidebar(
                    currentPath: _currentPath,
                    isHomeExpanded: _isHomeExpanded,
                    onNavigate: _navigateTo,
                    onToggleHome: () =>
                        setState(() => _isHomeExpanded = !_isHomeExpanded),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      _buildBreadcrumbs(),
                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          color: SovColors.error.withValues(alpha: 0.1),
                          width: double.infinity,
                          child: Text(
                            _error!,
                            style: const TextStyle(color: SovColors.error),
                          ),
                        ),
                      _buildListHeader(),
                      Expanded(
                        child: _loading
                            ? _buildSkeletonLoader()
                            : filteredFiles.isEmpty && _error == null
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        TweenAnimationBuilder<double>(
                                          tween: Tween(begin: 0, end: 1),
                                          duration: const Duration(seconds: 1),
                                          curve: Curves.elasticOut,
                                          builder: (context, value, child) {
                                            return Transform.scale(
                                              scale: value,
                                              child: Icon(
                                                _searchQuery.isEmpty
                                                    ? Icons.folder_open_outlined
                                                    : Icons.search_off_outlined,
                                                size: 80,
                                                color: SovColors.accent
                                                    .withValues(alpha: 0.1),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          _searchQuery.isEmpty
                                              ? 'Empty Folder'
                                              : 'No matches found',
                                          style: const TextStyle(
                                              color: SovColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: filteredFiles.length,
                                    itemBuilder: (context, index) =>
                                        _buildFileRow(filteredFiles[index]),
                                  ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Mobile Sidebar Overlay
            if (isMobile && _isSidebarOpen)
              GestureDetector(
                onTap: () => setState(() => _isSidebarOpen = false),
                child: Container(
                  color: Colors.black54,
                ),
              ),
            if (isMobile)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                left: _isSidebarOpen ? 0 : -240,
                top: 0,
                bottom: 0,
                child: FileExplorerSidebar(
                  currentPath: _currentPath,
                  isHomeExpanded: _isHomeExpanded,
                  onNavigate: (path) {
                    _navigateTo(path);
                    setState(() => _isSidebarOpen = false);
                  },
                  onToggleHome: () =>
                      setState(() => _isHomeExpanded = !_isHomeExpanded),
                  onClose: () => setState(() => _isSidebarOpen = false),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showFileContextMenu(Offset position, Map<String, dynamic> file) {
    HapticFeedback.mediumImpact();
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final path = file['path'] ?? '';
    final name = file['name'] ?? '';

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: SovColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.copy, size: 16, color: SovColors.accent),
              SizedBox(width: 12),
              Text('Copy'),
            ],
          ),
          onTap: () => setState(() {
            _clipboardPath = path;
            _isCut = false;
          }),
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.cut, size: 16, color: SovColors.accent),
              SizedBox(width: 12),
              Text('Cut'),
            ],
          ),
          onTap: () => setState(() {
            _clipboardPath = path;
            _isCut = true;
          }),
        ),
        if (_clipboardPath != null)
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.paste, size: 16, color: SovColors.accent),
                SizedBox(width: 12),
                Text('Paste'),
              ],
            ),
            onTap: () => _pasteItem(path),
          ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.terminal, size: 16, color: SovColors.accent),
              SizedBox(width: 12),
              Text('Open in Terminal'),
            ],
          ),
          onTap: () {
            final isDir = file['isDir'] == true;
            context.read<NavigationService>().openInTerminal(
                  isDir ? path : path.substring(0, path.lastIndexOf('/')),
                );
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.shield_outlined,
                  size: 16, color: SovColors.accentPurple),
              SizedBox(width: 12),
              Text('Push to Vault'),
            ],
          ),
          onTap: () => _pushToVault(path, name),
        ),
        if (!file['isDir'])
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.file_download, size: 16, color: SovColors.accent),
                SizedBox(width: 12),
                Text('Save to Device'),
              ],
            ),
            onTap: () => _downloadFile(path, name),
          ),
        if (name.endsWith('.zip') ||
            name.endsWith('.tar') ||
            name.endsWith('.gz') ||
            name.endsWith('.7z'))
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.unarchive, size: 16, color: SovColors.accent),
                SizedBox(width: 12),
                Text('Unzip / Extract'),
              ],
            ),
            onTap: () => _archiveAction(path, name, true),
          )
        else
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.archive, size: 16, color: SovColors.accent),
                SizedBox(width: 12),
                Text('Create Zip File'),
              ],
            ),
            onTap: () => _archiveAction(path, name, false),
          ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.code, size: 16, color: SovColors.accent),
              SizedBox(width: 12),
              Text('Copy for Terminal'),
            ],
          ),
          onTap: () {
            Clipboard.setData(ClipboardData(text: "'$path'"));
            VpsNotification.success(context, 'Path copied to clipboard.',
                title: 'COPIED');
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.link, size: 16, color: SovColors.accent),
              SizedBox(width: 12),
              Text('Copy Full Path'),
            ],
          ),
          onTap: () {
            Clipboard.setData(ClipboardData(text: path));
            VpsNotification.success(context, 'Path copied to clipboard');
          },
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.edit_outlined, size: 16, color: SovColors.accent),
              SizedBox(width: 12),
              Text('Rename'),
            ],
          ),
          onTap: () => _showRenameDialog(path, name),
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: SovColors.error),
              SizedBox(width: 12),
              Text('Delete'),
            ],
          ),
          onTap: () => _deleteItem(path),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: SovColors.textSecondary,
              ),
              SizedBox(width: 12),
              Text('Properties'),
            ],
          ),
          onTap: () => _showPropertiesDialog(path),
        ),
      ],
    );
  }

  Future<void> _pasteItem(String targetPath) async {
    if (_clipboardPath == null) return;
    // If target is a file, paste into its parent directory instead
    final isTargetDir = _files.any(
      (f) => f['path'] == targetPath && f['isDir'] == true,
    );
    final targetDir = isTargetDir
        ? targetPath
        : targetPath.substring(0, targetPath.lastIndexOf('/'));
    final fileName = _clipboardPath!.split('/').last;
    final dest = '$targetDir/$fileName';

    VpsNotification.info(context, _isCut ? 'Moving...' : 'Copying...');
    try {
      final endpoint = _isCut ? '/api/files/rename' : '/api/files/copy';
      final uri = VpsApiUtils.buildUri(widget.baseUrl, endpoint);
      final body = _isCut
          ? {'old_path': _clipboardPath, 'new_path': dest}
          : {'src': _clipboardPath, 'dest': dest};

      final response = await http
          .post(
            uri,
            headers: {
              'X-PublicNode-Key': widget.password,
              'Content-Type': 'application/json',
            },
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        if (mounted) {
          VpsNotification.success(context, 'File moved/copied successfully.',
              title: 'DONE');
        }
        if (_isCut) setState(() => _clipboardPath = null);
        _fetchFiles();
      } else {
        if (mounted) {
          VpsNotification.error(context, 'Failed: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) VpsNotification.error(context, 'Error: $e');
    }
  }

  void _showCreateDialog({required bool isFolder}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SovColors.surface,
        title: Text(isFolder ? 'New Folder' : 'New File'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: SovColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              _createItem(name, isFolder);
            },
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
  }

  Future<void> _createItem(String name, bool isFolder) async {
    try {
      final path = '${_currentPath == '/' ? '' : _currentPath}/$name';

      // V6: Optimistic UI Update
      final originalFiles = List<dynamic>.from(_files);
      setState(() {
        _files.add({
          'name': name,
          'path': path,
          'isDir': isFolder,
          'size': 0,
          'mtime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'itemCount': isFolder ? 0 : null,
        });
        _files.sort((a, b) {
          if (a['isDir'] != b['isDir']) return a['isDir'] ? -1 : 1;
          return a['name'].toString().toLowerCase().compareTo(
                b['name'].toString().toLowerCase(),
              );
        });
      });

      final endpoint = isFolder ? '/api/files/mkdir' : '/api/files/write';
      final uri = VpsApiUtils.buildUri(widget.baseUrl, endpoint);
      final body = isFolder ? {'path': path} : {'path': path, 'content': ''};

      final response = await http
          .post(
            uri,
            headers: {
              'X-PublicNode-Key': widget.password,
              'Content-Type': 'application/json',
            },
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (mounted) {
          VpsNotification.success(context, 'New item created successfully.',
              title: 'CREATED');
        }
        _fetchFiles(silent: true);
      } else {
        if (mounted) {
          setState(() => _files = originalFiles);
          VpsNotification.error(context, 'Failed: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) VpsNotification.error(context, 'Error: $e');
    }
  }

  void _showRenameDialog(String oldPath, String oldName) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SovColors.surface,
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: SovColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty || newName == oldName) {
                Navigator.pop(ctx);
                return;
              }
              Navigator.pop(ctx);
              final newPath =
                  '${oldPath.substring(0, oldPath.lastIndexOf('/'))}/$newName';
              _renameItem(oldPath, newPath);
            },
            child: const Text('RENAME'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameItem(String oldPath, String newPath) async {
    try {
      // V6: Optimistic UI Update
      final originalFiles = List<dynamic>.from(_files);
      setState(() {
        for (var i = 0; i < _files.length; i++) {
          if (_files[i]['path'] == oldPath) {
            _files[i]['path'] = newPath;
            _files[i]['name'] = newPath.split('/').last;
            break;
          }
        }
      });

      final uri = VpsApiUtils.buildUri(widget.baseUrl, '/api/files/rename');
      final response = await http
          .post(
            uri,
            headers: {
              'X-PublicNode-Key': widget.password,
              'Content-Type': 'application/json',
            },
            body: json.encode({'old_path': oldPath, 'new_path': newPath}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (mounted) {
          VpsNotification.success(context, 'Item renamed successfully.',
              title: 'RENAMED');
        }
        _fetchFiles(silent: true);
      } else {
        if (mounted) {
          setState(() => _files = originalFiles);
          VpsNotification.error(context, 'Failed: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) VpsNotification.error(context, 'Error: $e');
    }
  }

  Future<void> _batchDelete() async {
    final count = _selectedPaths.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SovColors.surface,
        title: const Text(
          'Batch Delete',
          style: TextStyle(color: SovColors.error),
        ),
        content: Text(
          'Are you sure you want to permanently delete $count items?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: SovColors.error),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final pathsToRemove = Set<String>.from(_selectedPaths);

    setState(() {
      _files.removeWhere((f) => pathsToRemove.contains(f['path']));
      _selectedPaths.clear();
      _selectionMode = false;
    });

    if (mounted) VpsNotification.info(context, 'Deleting $count items...');

    int successCount = 0;
    for (final path in pathsToRemove) {
      try {
        final uri = VpsApiUtils.buildUri(widget.baseUrl, '/api/files/delete');
        final response = await http
            .post(
              uri,
              headers: {
                'X-PublicNode-Key': widget.password,
                'Content-Type': 'application/json',
              },
              body: json.encode({'path': path}),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) successCount++;
      } catch (e) {
        debugPrint('Batch delete error: $e');
      }
    }

    if (successCount < count) {
      if (mounted) {
        VpsNotification.error(
          context,
          'Deleted $successCount/$count items. Some failed.',
        );
      }
      _fetchFiles(); // Re-sync properly
    } else {
      if (mounted) {
        VpsNotification.success(context, 'Successfully deleted $count item(s).',
            title: 'DELETED');
      }
      _fetchFiles(silent: true);
    }
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      itemCount: 10,
      itemBuilder: (context, index) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: SovColors.borderGlass, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: SovColors.surface,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 150,
                    height: 12,
                    decoration: BoxDecoration(
                      color: SovColors.surface,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 80,
                    height: 8,
                    decoration: BoxDecoration(
                      color: SovColors.surface,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 60,
              height: 10,
              decoration: BoxDecoration(
                color: SovColors.surface,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Future<void> _showPropertiesDialog(String path) async {
    VpsNotification.info(context, 'Retrieving deep properties...');
    try {
      final uri = VpsApiUtils.buildUri(widget.baseUrl, '/api/files/stat', {
        'path': path,
      });
      final response = await http.get(uri, headers: {
        'X-PublicNode-Key': widget.password
      }).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: SovColors.surface,
            title: const Text(
              'Properties',
              style: TextStyle(color: SovColors.accent),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _prop('Path', path),
                  _prop('Type', data['is_dir'] ? 'Directory' : 'File'),
                  _prop('Total Size', _formatBytes(data['size'])),
                  if (data['is_dir']) ...[
                    _prop(
                      'Contains',
                      '${data['file_count']} files, ${data['dir_count']} folders',
                    ),
                  ],
                  const Divider(color: SovColors.borderGlass, height: 24),
                  _prop('Access Rights', data['mode']),
                  _prop('Owner', '${data['owner']} : ${data['group']}'),
                  _prop(
                    'Last Changed',
                    DateTime.fromMillisecondsSinceEpoch(
                      data['mtime'] * 1000,
                    ).toString(),
                  ),
                  _prop(
                    'Last Opened',
                    DateTime.fromMillisecondsSinceEpoch(
                      data['atime'] * 1000,
                    ).toString(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CLOSE'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) VpsNotification.error(context, 'Error: $e');
    }
  }

  Widget _prop(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              k,
              style:
                  const TextStyle(color: SovColors.textSecondary, fontSize: 10),
            ),
            Text(
              v,
              style: const TextStyle(
                color: SovColors.textPrimary,
                fontSize: 12,
                fontFamily: SovFonts.mono,
              ),
            ),
          ],
        ),
      );
}
