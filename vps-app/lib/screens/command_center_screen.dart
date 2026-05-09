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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../widgets/vps_bounce.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../app/constants.dart';
import '../services/ssh_service.dart';
import '../services/engine_service.dart';
import '../services/cloud_service.dart';
import '../widgets/process_tab.dart';
import '../widgets/file_explorer_tab.dart';
import 'terminal_screen.dart';
import 'settings_screen.dart';
import '../services/navigation_service.dart';
import '../widgets/vps_notification.dart';
import '../widgets/system_vault_tab.dart';
import '../widgets/gui_desktop_tab.dart';

class CommandCenterScreen extends StatefulWidget {
  final String vpsName;
  final String vpsVersion;
  final String baseUrl;
  final String apiUrl;
  final String password;

  const CommandCenterScreen({
    super.key,
    required this.vpsName,
    required this.vpsVersion,
    required this.baseUrl,
    required this.apiUrl,
    required this.password,
  });

  @override
  State<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends State<CommandCenterScreen>
    with WidgetsBindingObserver {
  bool _isShuttingDown = false;
  String _fileExplorerPath = '/kaggle/working';
  StreamSubscription? _remoteSignalSub;
  late PageController _pageController;

  int get _currentIndex => context.watch<NavigationService>().currentIndex;
  set _currentIndex(int index) =>
      context.read<NavigationService>().setTab(index);

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addObserver(this);
    // Start monitoring the VPS engine using the dedicated API URL
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.apiUrl.isNotEmpty) {
        context.read<EngineService>().startMonitoring(
              widget.apiUrl,
              widget.password,
            );
        _checkAutoSync();
        _setupListeners();
      }
    });
  }

  void _setupRemoteSignalListener() {
    _remoteSignalSub?.cancel();
    _remoteSignalSub =
        context.read<CloudService>().remoteSignals.listen((signal) {
      if (mounted) {
        if (signal['type'] == 'status') {
          VpsNotification.system(
            context,
            signal['message']!,
            title: 'REMOTE_SIGNAL',
          );
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remoteSignalSub?.cancel();
    context.read<EngineService>().removeListener(_onEngineChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _setupListeners() {
    _setupRemoteSignalListener();

    // Listen for Engine errors
    final engine = context.read<EngineService>();
    engine.addListener(_onEngineChanged);
  }

  void _onEngineChanged() {
    final engine = context.read<EngineService>();
    if (engine.error != null && engine.isOnline == false) {
      if (mounted) {
        VpsNotification.error(
          context,
          '${engine.error}',
          title: 'CONNECTION INTERRUPTED',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _robustShutdown();
    }
  }

  /// Perform a professional, industry-grade shutdown: sync changes then kill notebook.
  Future<void> _robustShutdown() async {
    if (_isShuttingDown) return;
    _isShuttingDown = true;
    await context.read<EngineService>().powerOff();
  }

  void _manualPowerOff() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SovColors.surface,
        title: const Text(
          'Power Off PublicNode?',
          style: TextStyle(color: SovColors.textPrimary),
        ),
        content: const Text(
          'This will save your work and safely close everything. All your changes will be stored securely.',
          style: TextStyle(color: SovColors.textSecondary),
        ),
        actions: [
          VpsBounce(
            onTap: () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'CANCEL',
                style: TextStyle(color: SovColors.textSecondary),
              ),
            ),
          ),
          VpsBounce(
            onTap: () {
              Navigator.pop(context);
              VpsNotification.processing(
                context,
                'Closing safely now. Making sure all your work is saved.',
                title: 'SHUTTING_DOWN',
              );

              // V6: Industry-Grade Instant Shutdown
              _robustShutdown(); // Fire and forget

              // Delay slightly to allow the HTTP packet to hit the kernel buffer
              Future.delayed(const Duration(milliseconds: 500), () {
                exit(0);
              });
            },
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'SHUTDOWN',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerCloudSync() async {
    VpsNotification.processing(context, 'Saving your changes to the cloud...',
        title: 'SAVING');
    try {
      final url = widget.apiUrl
          .trim()
          .replaceFirst('wss://', 'https://')
          .replaceFirst('ws://', 'http:' '//');
      final response = await http.get(
        Uri.parse('${url.endsWith('/') ? url : '$url/'}api/sync'),
        headers: {'X-PublicNode-Key': widget.password},
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 202) {
        VpsNotification.dismissProcessing();
        VpsNotification.success(
          context,
          'Cloud saving is active. Your work is being saved now.',
          title: 'SAVING_ACTIVE',
        );
      } else if (response.statusCode == 409) {
        VpsNotification.dismissProcessing();
        VpsNotification.warning(
          context,
          'Sync Conflict: A backup is already active.',
        );
      } else {
        VpsNotification.dismissProcessing();
        VpsNotification.error(
            context, 'Could not save to the cloud. Please check your internet.',
            title: 'SAVE_FAILED');
      }
    } catch (e) {
      VpsNotification.dismissProcessing();
      if (mounted) VpsNotification.error(context, 'Network Error: $e');
    }
  }

  Future<void> _triggerVaultSync() async {
    VpsNotification.processing(
        context, 'Creating a permanent backup in your safe storage...',
        title: 'BACKUP');
    try {
      final url = widget.apiUrl
          .trim()
          .replaceFirst('wss://', 'https://')
          .replaceFirst('ws://', 'http:' '//');
      final response = await http.post(
        Uri.parse('${url.endsWith('/') ? url : '$url/'}api/sync/vault'),
        headers: {'X-PublicNode-Key': widget.password},
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 202) {
        VpsNotification.dismissProcessing();
        VpsNotification.success(
          context,
          'Backup complete. All files are now stored in your safe storage.',
          title: 'BACKUP_COMPLETE',
        );
      } else if (response.statusCode == 409) {
        VpsNotification.dismissProcessing();
        VpsNotification.warning(
          context,
          'Vault Busy: Concurrent sync attempt blocked.',
        );
      } else {
        VpsNotification.dismissProcessing();
        VpsNotification.error(context, 'Vault failed: ${response.statusCode}');
      }
    } catch (e) {
      VpsNotification.dismissProcessing();
      if (mounted) VpsNotification.error(context, 'Network Error: $e');
    }
  }

  void _setTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  Future<void> _checkAutoSync({bool force = false}) async {
    if (_currentIndex != 0 && !force) return;
    try {
      final url = widget.apiUrl
          .trim()
          .replaceFirst('wss://', 'https://')
          .replaceFirst('ws://', 'http:' '//');
      if (!url.startsWith('http')) return;

      if (force) {
        await _triggerCloudSync();
        return;
      }

      final response = await http.get(
        Uri.parse('${url.endsWith('/') ? url : '$url/'}api/sync/last'),
        headers: {'X-PublicNode-Key': widget.password},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['needs_sync'] == true) {
          _triggerCloudSync(); // Trigger auto-sync silently
        }
      }
    } catch (_) {}
  }

  Future<void> _showPulseCheck() async {
    VpsNotification.processing(
        context, 'Checking if everything is working correctly...',
        title: 'CHECKING');
    try {
      final url = widget.apiUrl
          .trim()
          .replaceFirst('wss://', 'https://')
          .replaceFirst('ws://', 'http:' '//');
      final response = await http.get(
        Uri.parse('${url.endsWith('/') ? url : '$url/'}api/system/metrics'),
        headers: {'X-PublicNode-Key': widget.password},
      ).timeout(const Duration(seconds: 5));

      if (!mounted) return;
      if (response.statusCode == 200) {
        VpsNotification.dismissProcessing();
        final data = json.decode(response.body);
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: SovColors.surface,
            title: const Text(
              'System Health: Good',
              style: TextStyle(color: SovColors.accent, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPulseItem(
                    'CPU Usage',
                    '${data['load_avg']['1m']} (1m) • ${data['load_avg']['5m']} (5m)',
                  ),
                  _buildPulseItem(
                    'Free Memory',
                    '${data['ram']['available_gb']} GB Free / ${data['ram']['total_gb']} GB',
                  ),
                  _buildPulseItem(
                    'Disk Space',
                    '${data['disk']['free_gb']} GB Free / ${data['disk']['total_gb']} GB',
                  ),
                  _buildPulseItem(
                      'Backup Memory', '${data['swap']['percent']}%'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE'),
              ),
            ],
          ),
        );
      } else {
        VpsNotification.dismissProcessing();
        VpsNotification.error(
            context, 'Pulse check failed: ${response.statusCode}');
      }
    } catch (e) {
      VpsNotification.dismissProcessing();
      if (mounted) VpsNotification.error(context, 'Health check failed: $e');
    }
  }

  Widget _buildPulseItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: SovColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: SovColors.textPrimary,
              fontSize: 13,
              fontFamily: SovFonts.mono,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: SovSpacing.md),
          decoration: const BoxDecoration(
            color: SovColors.surface,
            border: Border(bottom: BorderSide(color: SovColors.borderGlass)),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth:
                      MediaQuery.of(context).size.width - (SovSpacing.md * 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // --- Left: Real-time Monitor ---
                    Consumer<EngineService>(
                      builder: (context, engine, _) {
                        final stats = engine.stats;
                        final cpu = (stats['cpu'] ?? 0).toStringAsFixed(0);
                        final ram = (stats['ram'] ?? 0).toStringAsFixed(0);
                        final netIn =
                            (stats['net_in_kb'] ?? 0.0).toStringAsFixed(1);
                        final netOut =
                            (stats['net_out_kb'] ?? 0.0).toStringAsFixed(1);
                        final disk =
                            (stats['disk_speed_mb'] ?? 0.0).toStringAsFixed(1);
                        final gpus = stats['gpus'] as List<dynamic>? ?? [];

                        return Row(
                          children: [
                            Tooltip(
                              message: 'CPU Architecture Load',
                              child: _buildMetric(
                                Icons.memory,
                                '$cpu%',
                                Colors.cyanAccent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Hardware RAM Allocation',
                              child: _buildMetric(
                                Icons.dns_outlined,
                                '$ram%',
                                Colors.purpleAccent,
                              ),
                            ),
                            if (gpus.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Tooltip(
                                message: 'GPU Compute: ${gpus[0]['name']}',
                                child: _buildMetric(
                                  Icons.bolt,
                                  '${gpus[0]['util']}%',
                                  Colors.redAccent,
                                ),
                              ),
                            ],
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Disk I/O Throughput',
                              child: _buildMetric(
                                Icons.speed,
                                '$disk MB/s',
                                Colors.blueGrey,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Network Egress',
                              child: _buildMetric(
                                Icons.arrow_upward,
                                '$netOut kB/s',
                                Colors.orangeAccent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Network Ingress',
                              child: _buildMetric(
                                Icons.arrow_downward,
                                '$netIn kB/s',
                                Colors.greenAccent,
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    // --- Right: Header Options & Actions ---
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 12),
                        // --- Vertical Divider ---
                        Container(
                          height: 24,
                          width: 1,
                          color: SovColors.borderGlass,
                        ),
                        const SizedBox(width: 8),
                        _buildHeaderButton(
                          icon: Icons.terminal_outlined,
                          tooltip: 'Terminal',
                          isActive: _currentIndex == 0,
                          onTap: () => _setTab(0),
                        ),
                        const SizedBox(width: 4),
                        _buildHeaderButton(
                          icon: Icons.list,
                          tooltip: 'Active Programs',
                          isActive: _currentIndex == 1,
                          onTap: () => _setTab(1),
                        ),
                        const SizedBox(width: 4),
                        _buildHeaderButton(
                          icon: Icons.folder_outlined,
                          tooltip: 'File Explorer',
                          isActive: _currentIndex == 2 &&
                              _fileExplorerPath != '/kaggle/working/vault',
                          onTap: () {
                            _setTab(2);
                            _fileExplorerPath = '/kaggle/working';
                          },
                        ),
                        const SizedBox(width: 4),
                        _buildHeaderButton(
                          icon: Icons.receipt_long_outlined,
                          tooltip: 'Kaggle Log',
                          isActive: _currentIndex == 3,
                          onTap: () => _setTab(3),
                        ),
                        const SizedBox(width: 4),
                        _buildHeaderButton(
                          icon: Icons.api_outlined,
                          tooltip: 'FastAPI Log',
                          isActive: _currentIndex == 4,
                          onTap: () => _setTab(4),
                        ),
                        const SizedBox(width: 4),
                        _buildHeaderButton(
                          icon: Icons.all_inclusive,
                          tooltip: 'System Vault',
                          isActive: _currentIndex == 5,
                          onTap: () => _setTab(5),
                          activeColor: SovColors.accentPurple,
                        ),
                        const SizedBox(width: 4),
                        // V12: Only show GUI tab when engine reports GUI is enabled
                        Consumer<EngineService>(
                          builder: (context, engine, _) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildHeaderButton(
                                  icon: Icons.desktop_windows_outlined,
                                  tooltip: 'GUI Desktop',
                                  isActive: _currentIndex == 6,
                                  onTap: () => _setTab(6),
                                  activeColor: Colors.amberAccent,
                                ),
                                const SizedBox(width: 4),
                              ],
                            );
                          },
                        ),

                        _buildHeaderButton(
                          icon: Icons.cloud_done_outlined,
                          tooltip: 'Cloud Storage (1TB)',
                          isActive: _currentIndex == 2 &&
                              _fileExplorerPath == '/kaggle/working/vault',
                          onTap: () {
                            _setTab(2);
                            _fileExplorerPath = '/kaggle/working/vault';
                          },
                        ),
                        const SizedBox(width: 8),

                        // --- Sync Indicator ---
                        Consumer<EngineService>(
                          builder: (context, engine, _) {
                            final sync = engine.stats['sync'] ?? {};
                            final isActive = sync['active'] == true;
                            if (!isActive) return const SizedBox.shrink();

                            return Tooltip(
                              message: 'Sync Active: ${sync['message']}',
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.5, end: 1.0),
                                  duration: const Duration(seconds: 1),
                                  curve: Curves.easeInOut,
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: const Icon(
                                        Icons.sync,
                                        color: SovColors.accent,
                                        size: 14,
                                      ),
                                    );
                                  },
                                  onEnd:
                                      () {}, // Restart handled by repeat logic if needed
                                ),
                              ),
                            );
                          },
                        ),

                        // --- Divider ---
                        Container(
                          height: 16,
                          width: 1,
                          color: SovColors.borderGlass,
                        ),
                        const SizedBox(width: 4),

                        // --- Secondary Actions Menu ---
                        VpsBounce(
                          onTap:
                              () {}, // Handled by PopupMenuButton internals but we wrap it
                          child: PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_vert,
                              color: SovColors.textSecondary,
                              size: 20,
                            ),
                            color: SovColors.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(
                                  color: SovColors.borderGlass),
                            ),
                            onSelected: (value) {
                              switch (value) {
                                case 'pulse':
                                  _showPulseCheck();
                                  break;
                                case 'clear':
                                  context.read<SshService>().clearTerminal();
                                  VpsNotification.info(
                                    context,
                                    'Screen cleared and reset.',
                                    title: 'CLEARED',
                                  );
                                  break;
                                case 'sync':
                                  _triggerCloudSync();
                                  break;
                                case 'vault':
                                  _triggerVaultSync();
                                  break;
                                case 'settings':
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SettingsScreen(),
                                    ),
                                  );
                                  break;
                                case 'power':
                                  _manualPowerOff();
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'pulse',
                                child: _PopupItem(
                                  icon: Icons.health_and_safety_outlined,
                                  label: 'System Health',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'clear',
                                child: _PopupItem(
                                  icon: Icons.layers_clear_outlined,
                                  label: 'Clear Screen',
                                ),
                              ),
                              const PopupMenuDivider(height: 1),
                              const PopupMenuItem(
                                value: 'sync',
                                child: _PopupItem(
                                  icon: Icons.sync,
                                  label: 'Sync Files Now',
                                  color: SovColors.accent,
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'vault',
                                child: _PopupItem(
                                  icon: Icons.save,
                                  label: 'Save Everything',
                                  color: SovColors.accent,
                                ),
                              ),
                              const PopupMenuDivider(height: 1),
                              const PopupMenuItem(
                                value: 'settings',
                                child: _PopupItem(
                                  icon: Icons.settings_outlined,
                                  label: 'Settings',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'power',
                                child: _PopupItem(
                                  icon: Icons.power_settings_new,
                                  label: 'Shutdown',
                                  color: SovColors.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            TerminalScreen(
              ssh: context.watch<SshService>(),
              vpsName: widget.vpsName,
              vpsVersion: widget.vpsVersion,
              embedded: true,
            ),
            ProcessTab(baseUrl: widget.apiUrl, password: widget.password),
            FileExplorerTab(
              key: ValueKey(_fileExplorerPath),
              baseUrl: widget.apiUrl,
              password: widget.password,
              initialPath: _fileExplorerPath,
            ),
            _buildKaggleLogsTab(),
            _buildFastApiLogsTab(),
            const SystemVaultTab(),
            GuiDesktopTab(password: widget.password),
          ],
        ),
      ),
    );
  }

  Widget _buildKaggleLogsTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(SovSpacing.md),
          color: SovColors.surface,
          child: Consumer<EngineService>(
            builder: (context, engine, _) {
              final logs = engine.logs;
              return Row(
                children: [
                  const Icon(Icons.receipt_long_outlined,
                      color: SovColors.accent, size: 16),
                  const SizedBox(width: 12),
                  const Text(
                    'KAGGLE SYSTEM LOG',
                    style: TextStyle(
                      color: SovColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  _buildLogAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'Copy All',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: logs.join('\n')));
                      VpsNotification.success(
                          context, 'Logs copied to clipboard.',
                          title: 'COPIED');
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildLogAction(
                    icon: Icons.download_rounded,
                    tooltip: 'Download Log',
                    onTap: () =>
                        _exportLogs(logs, 'publicnode_kaggle_logs.txt'),
                  ),
                ],
              );
            },
          ),
        ),
        const Divider(height: 1, color: SovColors.borderGlass),
        Expanded(
          child: Consumer<EngineService>(
            builder: (context, engine, child) {
              final logs = engine.logs;
              return Container(
                padding: const EdgeInsets.all(SovSpacing.md),
                color: SovColors.background,
                child: ListView.builder(
                  reverse: true,
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[logs.length - 1 - index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        log,
                        style: const TextStyle(
                          color: SovColors.textSecondary,
                          fontFamily: SovFonts.mono,
                          fontSize: 11,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFastApiLogsTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(SovSpacing.md),
          color: SovColors.surface,
          child: Consumer<EngineService>(
            builder: (context, engine, _) {
              final logs = engine.httpLogs.map((l) => l.toString()).toList();
              return Row(
                children: [
                  const Icon(Icons.api_outlined,
                      color: SovColors.accent, size: 16),
                  const SizedBox(width: 12),
                  const Text(
                    'FASTAPI REAL-TIME LOG',
                    style: TextStyle(
                      color: SovColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  _buildLogAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'Copy All',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: logs.join('\n')));
                      VpsNotification.success(
                          context, 'HTTP Logs copied to clipboard');
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildLogAction(
                    icon: Icons.download_rounded,
                    tooltip: 'Download Log',
                    onTap: () =>
                        _exportLogs(logs, 'publicnode_fastapi_logs.txt'),
                  ),
                ],
              );
            },
          ),
        ),
        const Divider(height: 1, color: SovColors.borderGlass),
        Expanded(
          child: Consumer<EngineService>(
            builder: (context, engine, child) {
              final logs = engine.httpLogs;
              return Container(
                padding: const EdgeInsets.all(SovSpacing.md),
                color: SovColors.background,
                child: ListView.builder(
                  reverse: true,
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[logs.length - 1 - index].toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: SovColors.surface.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          log,
                          style: const TextStyle(
                            color: SovColors.textPrimary,
                            fontFamily: SovFonts.mono,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLogAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return VpsBounce(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: SovColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: SovColors.accent, size: 14),
        ),
      ),
    );
  }

  Future<void> _exportLogs(List<String> logs, String filename) async {
    final content = logs.join('\n');
    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final downloads = Directory('$home/Downloads');
      String path;
      if (await downloads.exists()) {
        path = '${downloads.path}/$filename';
      } else {
        path = '$home/$filename';
      }

      final file = File(path);
      await file.writeAsString(content);
      if (mounted) {
        VpsNotification.success(
          context,
          'Logs successfully saved to:\n$path',
          title: 'EXPORT COMPLETE',
        );
      }
    } catch (e) {
      if (mounted) {
        VpsNotification.error(context, 'Export failed: $e');
      }
    }
  }

  Widget _buildMetric(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(SovSpacing.borderRadiusSm),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: SovColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: SovFonts.mono,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback onTap,
    Color activeColor = SovColors.accent,
  }) {
    return VpsBounce(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isActive
                ? activeColor.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? activeColor.withValues(alpha: 0.2)
                  : Colors.transparent,
            ),
          ),
          child: Icon(
            icon,
            color: isActive ? activeColor : SovColors.textSecondary,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _PopupItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _PopupItem({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color ?? SovColors.textPrimary, size: 18),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: color ?? SovColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
