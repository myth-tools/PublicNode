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

/// Connect Screen — glassmorphic login/connection interface.
/// Reads default values from the YAML config. Provides "Remember Password"
/// toggle and animated connection state transitions.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yaml/yaml.dart';
import 'dart:io' show File;

import '../widgets/vps_bounce.dart';

import '../app/constants.dart';
import '../models/connection.dart' as model;
import '../services/ssh_service.dart';
import '../services/storage_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/status_indicator.dart';
import 'command_center_screen.dart';
import 'settings_screen.dart';
import '../services/cloud_service.dart';
import '../services/engine_service.dart';
import '../app/notebook_template.dart';
import '../widgets/vps_notification.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with SingleTickerProviderStateMixin {
  final _urlController = TextEditingController();
  final _userController = TextEditingController(text: 'root');
  final _passController = TextEditingController();
  bool _rememberPassword = false;
  bool _isLoading = false;
  String? _apiUrl;

  // Config values loaded from YAML
  String _vpsName = 'PublicNode';
  String _vpsVersion = '0.1.0';
  String _creator = '';
  String _topicPrefix = 'vps-root';
  String _kernelSlug = 'publicnode-vps-engine';
  String _kagUser = '';
  final bool _isSyncing = false;
  StreamSubscription? _remoteSignalSub;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
    _loadSavedCredentials();
    _loadConfig();
  }

  /// Load configuration from vps-config.yaml (reads from repo root — desktop only).
  Future<void> _loadConfig() async {
    // Skip file-based config on mobile (files don't exist on Android/iOS)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) return;

    try {
      // Try loading from filesystem relative to executable
      String? yamlContent;

      // Check common relative paths
      final candidates = [
        '../pyproject.toml', // Check project root first
        '../../pyproject.toml',
        '../vps-config.yaml', // vps-app/ -> Vps/
        '../../vps-config.yaml', // build output
        'vps-config.yaml', // same directory
        'pyproject.toml',
      ];

      for (final path in candidates) {
        final file = File(path);
        if (await file.exists()) {
          yamlContent = await file.readAsString();
          break;
        }
      }

      if (yamlContent != null) {
        final yaml = loadYaml(yamlContent);
        if (yaml is YamlMap) {
          setState(() {
            // Version from pyproject.toml or vps-config.yaml
            if (yaml.containsKey('project')) {
              _vpsVersion =
                  yaml['project']?['version']?.toString() ?? _vpsVersion;
            } else if (yaml.containsKey('engine')) {
              _vpsVersion =
                  yaml['engine']?['version']?.toString() ?? _vpsVersion;
            }

            _vpsName = yaml['identity']?['vps_name']?.toString() ?? _vpsName;
            _creator =
                yaml['identity']?['kaggle_username']?.toString() ?? _creator;
            _topicPrefix =
                yaml['signal']?['topic_prefix']?.toString() ?? _topicPrefix;
            _kernelSlug =
                yaml['identity']?['kernel_slug']?.toString() ?? _kernelSlug;
          });
        }
      }
    } catch (_) {
      // Config not found — use defaults, which is fine
    }
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final saved = await StorageService.loadConnection();
      setState(() {
        _urlController.text = ''; // Keep empty until fresh boot
        _userController.text = saved['username'] ?? 'root';
        _passController.text = ''; // Keep empty until fresh boot
        _rememberPassword = saved['remember'] == 'true';

        // Load cloud identity for syncing
        if (saved['kagUser']?.isNotEmpty == true) {
          _kagUser = saved['kagUser']!;
        }
        if (saved['topicPrefix']?.isNotEmpty == true) {
          _topicPrefix = saved['topicPrefix']!;
        }
        if (saved['kernelSlug']?.isNotEmpty == true) {
          _kernelSlug = saved['kernelSlug']!;
        }
      });
      // V6: Proactive Identity Check
      _runIdentityCheck();
    } catch (_) {
      // First launch or storage error — ignore
    }
  }

  bool _isIdentityValid = false;
  String? _identityError;
  bool _checkingIdentity = false;

  Future<void> _runIdentityCheck() async {
    final cloud = context.read<CloudService>();
    await cloud.loadIdentity();
    if (cloud.username.isEmpty || cloud.apiKey.isEmpty) {
      setState(() {
        _isIdentityValid = false;
        _identityError = 'Kaggle Credentials Missing';
      });
      return;
    }

    setState(() {
      _checkingIdentity = true;
      _identityError = null;
    });

    try {
      final result = await cloud.validateKaggle(cloud.username, cloud.apiKey);
      if (mounted) {
        setState(() {
          _isIdentityValid = result['valid'] == true;
          _identityError = result['valid'] == true ? null : result['message'];
          _checkingIdentity = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isIdentityValid = false;
          _identityError = 'Verification Failed';
          _checkingIdentity = false;
        });
      }
    }
  }

  Future<void> _igniteCloud() async {
    final cloud = context.read<CloudService>();
    try {
      // Final sanity check
      if (!_isIdentityValid) {
        await _runIdentityCheck();
        if (!_isIdentityValid) {
          if (mounted) {
            VpsNotification.error(
              context,
              'Account check failed. Please check your Kaggle keys in Settings.',
            );
          }
          return;
        }
      }

      if (!mounted) return;

      // New: Ask for Headless vs GUI
      final bool? guiEnabled = await _showIgnitionModeDialog();
      if (guiEnabled == null) return; // User cancelled

      if (!mounted) return;
      VpsNotification.info(context, 'Starting Cloud Computer...');
      await cloud.loadIdentity(); // Ensure cached identity is fresh
      cloud.reset();
      await cloud.igniteVps(
        kernelSlug: _kernelSlug,
        notebookContent: vpsNotebookTemplate,
        guiEnabled: guiEnabled,
      );

      _remoteSignalSub?.cancel();
      _remoteSignalSub = cloud.remoteSignals.listen((signal) {
        if (mounted) {
          VpsNotification.system(
            context,
            signal['message']!,
            title: 'ENGINE_STATUS',
          );
        }
      });

      // Auto-start sync loop after ignition
      _startAutoSync();
    } catch (e) {
      if (mounted) {
        VpsNotification.error(context, 'Start-up Failed: $e');
      }
    }
  }

  Future<bool?> _showIgnitionModeDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SovColors.surface,
        title: const Text(
          'SELECT ENVIRONMENT MODE',
          style: TextStyle(
            color: SovColors.accent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModeOption(
              context,
              title: 'HEADLESS (STABLE)',
              subtitle: 'Terminal only. Minimal RAM overhead.',
              icon: Icons.terminal_outlined,
              value: false,
            ),
            const SizedBox(height: 12),
            _buildModeOption(
              context,
              title: 'DESKTOP (BETA)',
              subtitle: 'XFCE Premium Desktop + Terminal. ~200MB RAM.',
              icon: Icons.desktop_windows_outlined,
              value: true,
              isRecommended: false,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: SovColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    bool isRecommended = false,
  }) {
    return VpsBounce(
      onTap: () => Navigator.pop(context, value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isRecommended ? SovColors.accent : SovColors.borderGlass,
            width: isRecommended ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: SovColors.accent, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: SovColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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
    );
  }

  void _startAutoSync() {
    int attempts = 0;
    const maxAttempts = 80; // 80 × 15s = 20 minutes max wait
    final cloud = context.read<CloudService>();

    // Poll ntfy every 15s for session-tagged signals until WS URL arrives
    Future.doWhile(() async {
      try {
        if (!mounted) return false;
        if (cloud.state == CloudState.error || cloud.state == CloudState.idle) {
          return false;
        }

        attempts++;
        if (attempts > maxAttempts) {
          if (mounted) {
            VpsNotification.warning(
              context,
              'Cloud boot sequence exceeded expected timeout threshold.',
              title: 'BOOT_TIMEOUT',
            );
            cloud.reset();
          }
          return false;
        }

        // Grace period: skip kernel status checks for first 5 attempts (~75s).
        // Kaggle kernels are always 'queued' during early initialization.
        if (attempts > 5 && attempts % 2 == 0) {
          final status = await cloud.getKernelStatus(
            cloud.username,
            cloud.apiKey,
            cloud.kernelSlug,
          );

          // 'unknown' = network error, transient — keep polling
          // 'cancel' = definitive user-cancelled stop
          // 'error' / 'failed' = definitive crash
          if (status == 'cancel') {
            if (mounted) {
              VpsNotification.error(
                context,
                'The PublicNode engine was stopped by the user or an external system.',
                title: 'ENGINE_STOPPED',
              );
              cloud.reset();
            }
            return false;
          } else if (status == 'error' || status == 'failed') {
            // Fetch logs IMMEDIATELY on failure — no more tolerance
            final logs = await cloud.fetchKernelLogs(
              cloud.username,
              cloud.apiKey,
              cloud.kernelSlug,
            );
            if (mounted) {
              cloud.updateBootStatus('❌ ENGINE ERROR DETECTED');
              // Add last few lines of logs to the UI for diagnostics
              final logLines = logs.split('\n');
              final lastLogs = logLines.length > 50
                  ? logLines.sublist(logLines.length - 50)
                  : logLines;
              for (var line in lastLogs) {
                if (line.trim().isNotEmpty) {
                  cloud.updateBootStatus('> $line');
                }
              }
              VpsNotification.error(
                context,
                'System execution failed. A critical error was detected in the remote environment.',
                title: 'ENGINE_SYSTEM_ERROR',
              );
            }
            return false;
          }
        }

        // Fetch session-strict signals from ntfy
        final signals = await cloud.fetchCloudSignals();
        if (!mounted) return false;

        final wsUrl = signals['wsUrl'] ?? '';
        final apiUrl = signals['apiUrl'] ?? '';
        final password = signals['password'] ?? '';

        final guiUrl = signals['guiUrl'] ?? '';

        if (wsUrl.isNotEmpty && password.isNotEmpty) {
          // Both arrived — populate fields and auto-connect
          setState(() {
            _urlController.text = wsUrl;
            _passController.text = password;
            _apiUrl = apiUrl.isNotEmpty ? apiUrl : wsUrl;
            if (guiUrl.isNotEmpty) {
              context.read<EngineService>().setGuiUrl(guiUrl);
            }
          });
          VpsNotification.success(
            context,
            'Connection established. Signing in...',
            title: 'CONNECTION_READY',
          );
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) _connect();
          return false; // Stop polling
        } else if (wsUrl.isNotEmpty) {
          setState(() => _urlController.text = wsUrl);
          // Password not yet received — keep polling
        }

        await Future.delayed(const Duration(seconds: 15));
        return true;
      } catch (e) {
        debugPrint('Polling error: $e');
        // On error, wait and try again unless state changed
        await Future.delayed(const Duration(seconds: 15));
        return mounted &&
            cloud.state != CloudState.error &&
            cloud.state != CloudState.idle;
      }
    });
  }

  Future<void> _connect() async {
    if (_urlController.text.trim().isEmpty ||
        _passController.text.trim().isEmpty) {
      VpsNotification.warning(
        context,
        'Waiting for cloud session to be ready...',
      );
      return;
    }

    setState(() => _isLoading = true);

    final ssh = context.read<SshService>();
    final info = model.ConnectionInfo(
      label: _vpsName,
      wsUrl: _urlController.text.trim(),
      sshHost: _urlController.text.trim(),
      sshPort: 2222,
      username: _userController.text.trim(),
      password: _passController.text,
      rememberPassword: _rememberPassword,
    );

    // Save credentials if requested
    await StorageService.saveConnection(
      wsUrl: info.wsUrl,
      sshHost: info.sshHost,
      sshPort: info.sshPort,
      username: info.username,
      password: info.password,
      remember: _rememberPassword,
    );

    await ssh.connect(info);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (ssh.isConnected) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CommandCenterScreen(
            vpsName: _vpsName,
            vpsVersion: _vpsVersion,
            baseUrl: _urlController.text,
            apiUrl: (_apiUrl != null && _apiUrl!.isNotEmpty)
                ? _apiUrl!
                : _urlController.text,
            password: _passController.text,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    _remoteSignalSub?.cancel();
    super.dispose();
  }

  void _showLiveLogs() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SovColors.surface,
          title: const Text(
            'Live Engine Monitor',
            style: TextStyle(color: SovColors.accent),
          ),
          content: Container(
            width: double.maxFinite,
            height: 400,
            decoration: BoxDecoration(
              color: SovColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SovColors.borderGlass),
            ),
            child: Consumer<CloudService>(
              builder: (context, cloud, child) {
                final logs = cloud.bootLogs.reversed.toList();
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '> ${logs[index]}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: SovColors.textSecondary,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'CLOSE',
                style: TextStyle(color: SovColors.accent),
              ),
            ),
          ],
        );
      },
    );
  }

  void _powerOff() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SovColors.surface,
        title: const Text(
          'Power Off VPS?',
          style: TextStyle(color: SovColors.textPrimary),
        ),
        content: const Text(
          'This will perform a final sync and terminate the remote notebook. All unsaved system changes may be lost.',
          style: TextStyle(color: SovColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: SovColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              VpsNotification.warning(context, 'Sending Power Off Signal...');
              context.read<CloudService>().sendControlSignal('KILL');
            },
            child: const Text(
              'POWER OFF',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudService>();
    final ssh = context.watch<SshService>();
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 600;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          _BlinkingMonitorIcon(
            isBlinking: _isSyncing ||
                context.watch<CloudService>().state == CloudState.checking ||
                context.watch<CloudService>().state == CloudState.igniting ||
                context.watch<CloudService>().state == CloudState.booting,
            onPressed: _showLiveLogs,
          ),
          IconButton(
            icon: const Icon(Icons.power_settings_new, color: Colors.redAccent),
            tooltip: 'Power Off Notebook',
            onPressed: _powerOff,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: SovColors.accent),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
              _loadSavedCredentials();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.5,
            colors: [Color(0xFF0D1B2A), SovColors.background],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? screenWidth * 0.2 : SovSpacing.lg,
              vertical: SovSpacing.xxl,
            ),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // --- Logo / Title ---
                  _buildPulsingLogo(),
                  const SizedBox(height: SovSpacing.md),
                  Text(
                    _vpsName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: SovColors.textPrimary,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: SovSpacing.xxl),

                  // --- System Identity Grid (Industrial) ---
                  _buildSystemIdentity(),
                  const SizedBox(height: SovSpacing.sm),

                  // V6: Proactive Identity Status Chip
                  GestureDetector(
                    onTap: _runIdentityCheck,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isIdentityValid
                            ? Colors.greenAccent.withValues(alpha: 0.1)
                            : SovColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isIdentityValid
                              ? Colors.greenAccent.withValues(alpha: 0.3)
                              : SovColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_checkingIdentity)
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: SovColors.textSecondary,
                              ),
                            )
                          else
                            Icon(
                              _isIdentityValid
                                  ? Icons.verified_user_outlined
                                  : Icons.gpp_bad_outlined,
                              size: 12,
                              color: _isIdentityValid
                                  ? Colors.greenAccent
                                  : SovColors.error,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            _checkingIdentity
                                ? 'CHECKING ACCOUNT...'
                                : (_isIdentityValid
                                    ? 'ACCOUNT VERIFIED'
                                    : (_identityError ??
                                        'ACCOUNT NOT VERIFIED')),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              fontFamily: SovFonts.mono,
                              color: _isIdentityValid
                                  ? Colors.greenAccent
                                  : SovColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: SovSpacing.lg),

                  GlassCard(
                    hasTechnicalGrid: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // --- Card Header Telemetry ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'STARTED_AT: ${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}',
                              style: TextStyle(
                                fontSize: 7,
                                fontFamily: SovFonts.mono,
                                color: SovColors.accent.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: SovSpacing.md),
                        // Status indicator
                        if (ssh.state != model.ConnectionState.disconnected)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: SovSpacing.md,
                            ),
                            child: Center(
                              child: StatusIndicator(
                                state: ssh.state,
                                message: ssh.statusMessage,
                              ),
                            ),
                          ),

                        // SSH Error message
                        if (ssh.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: SovSpacing.md,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(SovSpacing.sm),
                              decoration: BoxDecoration(
                                color: SovColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                  SovSpacing.borderRadiusSm,
                                ),
                                border: Border.all(
                                  color: SovColors.error.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                ssh.errorMessage!,
                                style: const TextStyle(
                                  color: SovColors.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),

                        // Cloud Error message
                        if (cloud.errorMessage != null &&
                            cloud.state == CloudState.error)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: SovSpacing.md,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(SovSpacing.sm),
                              decoration: BoxDecoration(
                                color: SovColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                  SovSpacing.borderRadiusSm,
                                ),
                                border: Border.all(
                                  color: SovColors.error.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                'ENGINE ERROR: ${cloud.errorMessage!}',
                                style: const TextStyle(
                                  color: SovColors.error,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                        // Connection details are now managed automatically after ignition
                        const SizedBox(height: SovSpacing.lg),

                        const SizedBox(height: SovSpacing.lg),

                        // Master Ignition / Connect Button
                        Consumer<CloudService>(
                          builder: (context, cloud, _) {
                            final isIgniting =
                                cloud.state == CloudState.igniting ||
                                    cloud.state == CloudState.booting;

                            return Column(
                              children: [
                                if (!isIgniting) ...[
                                  const Text(
                                    'CONNECTION STATUS: OFFLINE',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontFamily: SovFonts.mono,
                                      color: SovColors.textSecondary,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (isIgniting)
                                  _buildPowerfulProgressBar(cloud),
                                Container(
                                  width: double.infinity,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: SovColors.accent
                                            .withValues(alpha: 0.3),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: VpsBounce(
                                    onTap: (_isLoading || isIgniting)
                                        ? null
                                        : () async {
                                            _urlController.clear();
                                            _passController.clear();
                                            _igniteCloud();
                                          },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: LinearGradient(
                                          colors: (_isLoading || isIgniting)
                                              ? [
                                                  SovColors.surface,
                                                  SovColors.surface
                                                ]
                                              : [
                                                  SovColors.accent,
                                                  SovColors.accentPurple
                                                ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: SovColors.background,
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  isIgniting
                                                      ? Icons.speed
                                                      : Icons.bolt,
                                                  color: isIgniting
                                                      ? SovColors.textPrimary
                                                      : SovColors.background,
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  isIgniting
                                                      ? 'SYSTEM BOOTING...'
                                                      : 'START CLOUD SYSTEM',
                                                  style: TextStyle(
                                                    color: isIgniting
                                                        ? SovColors.textPrimary
                                                        : SovColors.background,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 1.5,
                                                    shadows: isIgniting
                                                        ? [
                                                            Shadow(
                                                              color: SovColors
                                                                  .accent
                                                                  .withValues(
                                                                      alpha:
                                                                          0.5),
                                                              blurRadius: 10,
                                                            )
                                                          ]
                                                        : null,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                                if (isIgniting)
                                  VpsBounce(
                                    onTap: () => cloud.reset(),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          vertical: 8, horizontal: 16),
                                      child: Text(
                                        'CANCEL STARTING',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: SovColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SovSpacing.lg),

                  // --- Footer ---
                  Text(
                    'PROTOCOL: SSH-QUIC-V3 • TLS 1.3 • AES-256-GCM',
                    style: TextStyle(
                      color: SovColors.textSecondary.withValues(alpha: 0.4),
                      fontSize: 8,
                      fontFamily: SovFonts.mono,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'SSH over ${_isMobile ? "WebSocket" : "TCP"} • Cloudflare Edge Network',
                    style: const TextStyle(
                      color: SovColors.textSecondary,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Widget _buildPulsingLogo() {
    return Container(
      padding: const EdgeInsets.all(SovSpacing.md),
      decoration: BoxDecoration(
        color: SovColors.accent.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: SovColors.accent.withValues(alpha: 0.2),
            blurRadius: 15,
            spreadRadius: 5,
          ),
        ],
        border: Border.all(
          color: SovColors.accent.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: const Text(
        '◢◤',
        style: TextStyle(
          fontSize: 40,
          color: SovColors.accent,
          fontWeight: FontWeight.w900,
          letterSpacing: -4,
        ),
      ),
    );
  }

  Widget _buildSystemIdentity() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildIdentityCell(
                'ACCOUNT',
                _kagUser.isEmpty ? 'ANONYMOUS' : _kagUser,
                Icons.person_outline,
              ),
            ),
            const SizedBox(width: SovSpacing.md),
            Expanded(
              child: _buildIdentityCell(
                'CONNECTION',
                _topicPrefix,
                Icons.sensors,
              ),
            ),
          ],
        ),
        const SizedBox(height: SovSpacing.md),
        Row(
          children: [
            Expanded(
              child: _buildIdentityCell(
                'SYSTEM',
                'LINUX-X64(Ubuntu22.04)',
                Icons.memory,
              ),
            ),
            const SizedBox(width: SovSpacing.md),
            Expanded(
              child: _buildIdentityCell(
                'VERSION',
                _vpsVersion,
                Icons.terminal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdentityCell(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SovSpacing.md,
        vertical: SovSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: SovColors.borderGlass),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: SovColors.accent.withValues(alpha: 0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    color: SovColors.textSecondary.withValues(alpha: 0.5),
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  value.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: SovColors.textPrimary,
                    fontFamily: SovFonts.mono,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPowerfulProgressBar(CloudService cloud) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final currentWidth = availableWidth * cloud.smoothProgress;

        return Column(
          children: [
            // --- Mission Control Telemetry Row (Compact) ---
            _buildTelemetryRow(cloud),
            const SizedBox(height: 16),

            // --- Enhanced Progress Bar (Animated, but Real) ---
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(
                    height: 12,
                    width: double.infinity,
                    color: SovColors.accent.withValues(alpha: 0.05),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.linear,
                    height: 12,
                    width: currentWidth,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [SovColors.accent, Color(0xFF00E5FF)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: SovColors.accent.withValues(alpha: 0.4),
                          blurRadius: 15,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // --- Live Kernel Status ---
            Row(
              children: [
                _BlinkingMonitorIcon(isBlinking: true, onPressed: () {}),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (cloud.statusMessage ?? 'Waiting for system...')
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: SovColors.accent,
                          fontFamily: SovFonts.mono,
                          letterSpacing: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        cloud.currentTaskDescription,
                        style: TextStyle(
                          fontSize: 9,
                          color: SovColors.textSecondary.withValues(alpha: 0.7),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(cloud.smoothProgress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: SovColors.accent,
                    fontFamily: SovFonts.mono,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // --- Verification Sequence & Live Stream ---
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildVerificationList(cloud)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _buildLiveLogStream(cloud)),
              ],
            ),

            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildLiveLogStream(CloudService cloud) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'LIVE SYSTEM FEED',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: SovColors.textSecondary,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          height: 140,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: SovColors.borderGlass),
          ),
          child: ListView.builder(
            itemCount: cloud.recentLogs.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  cloud.recentLogs[index],
                  style: TextStyle(
                    fontSize: 8,
                    color: SovColors.accent.withValues(alpha: 0.6),
                    fontFamily: SovFonts.mono,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetryRow(CloudService cloud) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _TelemetryChip(
          label: 'SIGNALS',
          value: '${cloud.signalsReceived}',
          icon: Icons.sensors,
        ),
        _TelemetryChip(
          label: 'STEPS',
          value: '${cloud.milestonesCount}',
          icon: Icons.verified,
        ),
        _TelemetryChip(
          label: 'TIME',
          value: cloud.elapsedText,
          icon: Icons.timer,
        ),
        _TelemetryChip(
          label: 'REMAINING',
          value: cloud.etaText,
          icon: Icons.update,
          isAccent: true,
        ),
      ],
    );
  }

  Widget _buildVerificationList(CloudService cloud) {
    // Industrial Grade: Use actual milestones from CloudService
    final milestones = cloud.allMilestones;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CHECKING SYSTEM',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: SovColors.textSecondary,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        ...milestones.map((m) {
          final isDone = m.reached;
          final isActive = cloud.currentTaskDescription == m.description;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  isDone
                      ? Icons.check_circle
                      : (isActive
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off),
                  size: 14,
                  color: isDone
                      ? Colors.greenAccent
                      : (isActive
                          ? SovColors.accent
                          : SovColors.textSecondary.withValues(alpha: 0.3)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    m.displayName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: isDone
                          ? SovColors.textPrimary
                          : (isActive
                              ? SovColors.accent
                              : SovColors.textSecondary.withValues(
                                  alpha: 0.5,
                                )),
                      fontFamily: SovFonts.mono,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: SovColors.accent,
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _TelemetryChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isAccent;

  const _TelemetryChip({
    required this.label,
    required this.value,
    required this.icon,
    this.isAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SovColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isAccent
              ? SovColors.accent.withValues(alpha: 0.3)
              : SovColors.borderGlass,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isAccent ? SovColors.accent : SovColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: const TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.w700,
              color: SovColors.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: isAccent ? SovColors.accent : SovColors.textPrimary,
              fontFamily: SovFonts.mono,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerOverlay extends StatefulWidget {
  @override
  State<_ShimmerOverlay> createState() => _ShimmerOverlayState();
}

class _ShimmerOverlayState extends State<_ShimmerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0.2),
                Colors.white.withValues(alpha: 0),
              ],
              stops: [
                _controller.value - 0.3,
                _controller.value,
                _controller.value + 0.3,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A high-performance blinking icon that doesn't trigger parent rebuilds.
class _BlinkingMonitorIcon extends StatefulWidget {
  final bool isBlinking;
  final VoidCallback onPressed;

  const _BlinkingMonitorIcon({
    required this.isBlinking,
    required this.onPressed,
  });

  @override
  State<_BlinkingMonitorIcon> createState() => _BlinkingMonitorIconState();
}

class _BlinkingMonitorIconState extends State<_BlinkingMonitorIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.isBlinking) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_BlinkingMonitorIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isBlinking && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isBlinking && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.isBlinking
          ? _controller.drive(CurveTween(curve: Curves.easeInOut))
          : const AlwaysStoppedAnimation(1.0),
      child: VpsBounce(
        onTap: widget.onPressed,
        child: IconButton(
          icon:
              const Icon(Icons.receipt_long_outlined, color: SovColors.accent),
          tooltip: 'Live Monitor',
          onPressed: widget.onPressed,
        ),
      ),
    );
  }
}
