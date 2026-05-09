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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/constants.dart';
import '../services/engine_service.dart';
import 'glass_card.dart';
import 'vps_bounce.dart';
import 'vps_notification.dart';

class GuiDesktopTab extends StatefulWidget {
  final String password;

  const GuiDesktopTab({super.key, required this.password});

  @override
  State<GuiDesktopTab> createState() => _GuiDesktopTabState();
}

class _GuiDesktopTabState extends State<GuiDesktopTab>
    with SingleTickerProviderStateMixin {
  InAppWebViewController? _webViewController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isLoading = true;
  double _loadingProgress = 0.0;
  String? _lastUrl;
  bool? _lastRunningState;

  // Premium Status Telemetry
  String _statusMessage = 'IGNITING BACKBONE...';
  final List<String> _statusCycle = [
    'ESTABLISHING NEURAL LINK...',
    'AUTHENTICATING CLOUD VAULT...',
    'DEPLOYING LOW-LATENCY GUI...',
    'OPTIMIZING HARDWARE ACCELERATION...',
    'FINALIZING DESKTOP STACK...'
  ];
  int _statusIndex = 0;
  Timer? _statusTimer;

  // flutter_inappwebview supports: Android, iOS, macOS, Linux, Web.
  // Windows Desktop requires a fallback to the system browser.
  final bool _isWebViewSupported = Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.6, end: 1.0).animate(_pulseController);

    _statusTimer = Timer.periodic(const Duration(milliseconds: 1800), (timer) {
      if (_isLoading && mounted) {
        setState(() {
          _statusIndex = (_statusIndex + 1) % _statusCycle.length;
          _statusMessage = _statusCycle[_statusIndex];
        });
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _buildKasmUrl(String baseUrl) {
    // Performance-tuned KasmVNC URL parameters:
    // autoconnect  — no click-to-connect prompt
    // resize=scale — desktop scales to the frame size
    // quality=9    — high quality without crushing bandwidth
    // compress=4   — balanced compression
    // encrypt=0    — Cloudflare HTTPS already provides the TLS layer
    return '$baseUrl/?autoconnect=true'
        '&webrtc=true'
        '&reconnect=true'
        '&reconnect_delay=2000'
        '&quality=9'
        '&compression=4'
        '&resize=remote'
        '&control_bar=hidden'
        '&cursor=none'
        '&show_dot=false'
        '&logging=warn';
  }

  void _loadUrl(String baseUrl) {
    final url = _buildKasmUrl(baseUrl);
    if (_lastUrl == url) return;
    _lastUrl = url;
    if (mounted) setState(() => _isLoading = true);
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(url)),
    );
  }

  void _handleStatusChange(BuildContext context, bool isRunning) {
    if (_lastRunningState == isRunning) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isRunning) {
        VpsNotification.processing(context, 'Igniting GUI Stack...',
            title: 'BOOTING');
      } else if (_lastRunningState == true) {
        VpsNotification.warning(context, 'GUI Stack was terminated.',
            title: 'OFFLINE');
      }
      _lastRunningState = isRunning;
    });
  }

  Future<void> _launchInBrowser(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      VpsNotification.error(context, 'Could not open system browser.',
          title: 'LAUNCH FAILED');
    }
  }

  // ──────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<EngineService>(
      builder: (context, engine, _) {
        // Headless mode — show premium upgrade screen
        if (!engine.guiEnabled) return _buildDisabledState();

        _handleStatusChange(context, engine.guiRunning);

        // GUI enabled but not yet running — booting spinner
        if (!engine.guiRunning || engine.guiUrl == null) {
          return _buildBootingState();
        }

        // GUI running — load URL on supported platforms
        if (_isWebViewSupported) {
          _loadUrl(engine.guiUrl!);
        }

        return Column(
          children: [
            _buildGuiHeader(engine),
            const Divider(height: 1, color: SovColors.borderGlass),
            Expanded(
              child: _isWebViewSupported
                  ? _buildWebView(engine.guiUrl!)
                  : _buildDesktopFallback(engine.guiUrl!),
            ),
          ],
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────
  // WEBVIEW (Android / iOS / macOS)
  // ──────────────────────────────────────────────────────────────

  Widget _buildWebView(String baseUrl) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(_buildKasmUrl(baseUrl)),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            transparentBackground: true, // Use app theme color
            isInspectable: false,
            hardwareAcceleration: true,
            disableLongPressContextMenuOnLinks: true,
            userAgent:
                'Mozilla/5.0 (Linux; PublicNode) AppleWebKit/537.36 Chrome/124 Safari/537.36',
          ),
          onReceivedServerTrustAuthRequest: (controller, challenge) async {
            return ServerTrustAuthResponse(
                action: ServerTrustAuthResponseAction.PROCEED);
          },
          onWebViewCreated: (controller) {
            _webViewController = controller;
          },
          onLoadStart: (controller, url) {
            // Inject CSS to hide KasmVNC branding IMMEDIATELY
            controller.injectCSSCode(source: """
              #loading-screen, #loading-logo, .loading-logo, #kasm-logo, #status-text { 
                display: none !important; 
                opacity: 0 !important;
                visibility: hidden !important;
              }
              body { background-color: #0A0A0A !important; }
            """);
            if (mounted) {
              setState(() {
                _isLoading = true;
                _loadingProgress = 0.0;
              });
            }
          },
          onLoadStop: (controller, url) async {
            // Scrub branding elements from DOM
            await controller.evaluateJavascript(source: """
              document.querySelectorAll('#loading-screen, #loading-logo, .loading-logo, #kasm-logo').forEach(el => el.remove());
            """);
            if (mounted) {
              setState(() => _isLoading = false);
              VpsNotification.success(context, 'GUI Desktop is Online',
                  title: 'STABILIZED');
            }
          },
          onProgressChanged: (controller, progress) {
            if (mounted) {
              setState(() => _loadingProgress = progress / 100.0);
              if (progress > 95) setState(() => _isLoading = false);
            }
          },
          onReceivedError: (controller, request, error) {
            if (mounted) {
              VpsNotification.error(
                  context, 'VNC Bridge Error: ${error.description}',
                  title: 'FAILED');
            }
          },
          onConsoleMessage: (controller, consoleMessage) {
            debugPrint(
                '[KasmVNC] ${consoleMessage.messageLevel}: ${consoleMessage.message}');
          },
        ),
        if (_isLoading) _buildPremiumLoader(),
      ],
    );
  }

  Widget _buildPremiumLoader({String? customMessage}) {
    return Container(
      color: SovColors.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: Tween(begin: 0.95, end: 1.05).animate(
                CurvedAnimation(
                    parent: _pulseController, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: SovColors.accent.withValues(alpha: 0.3),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                  gradient: const RadialGradient(
                    colors: [
                      SovColors.accent,
                      Color(0xFF00B0FF),
                    ],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.bolt_rounded,
                    color: Colors.white,
                    size: 50,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              (customMessage ?? _statusMessage).toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SovColors.textPrimary,
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
                fontFamily: SovFonts.mono,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              height: 2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _loadingProgress > 0 ? _loadingProgress : null,
                  backgroundColor: SovColors.surface,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(SovColors.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // DESKTOP FALLBACK (Linux / Windows — no embedded webview)
  // ──────────────────────────────────────────────────────────────

  Widget _buildDesktopFallback(String baseUrl) {
    final url = _buildKasmUrl(baseUrl);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SovSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) => Opacity(
                opacity: _pulseAnimation.value,
                child: child,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: SovColors.accent.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: SovColors.accent.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.open_in_browser_rounded,
                    size: 56, color: SovColors.accent),
              ),
            ),
            const SizedBox(height: SovSpacing.lg),
            const Text(
              'OPEN IN SYSTEM BROWSER',
              style: TextStyle(
                color: SovColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.8,
              ),
            ),
            const SizedBox(height: SovSpacing.sm),
            const Text(
              'Linux Desktop delivers maximum performance via a native browser.\nYour GPU-accelerated Chrome or Firefox provides zero-lag VNC.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: SovColors.textSecondary, height: 1.6, fontSize: 13),
            ),
            const SizedBox(height: SovSpacing.xl),
            // Primary — Launch browser
            VpsBounce(
              onTap: () => _launchInBrowser(url),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [SovColors.accent, Color(0xFF0090CC)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: SovColors.accent.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.rocket_launch_rounded,
                        color: Colors.black, size: 20),
                    SizedBox(width: 12),
                    Text(
                      'LAUNCH GUI DESKTOP',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: SovSpacing.lg),
            // Secondary — copy URL
            VpsBounce(
              onTap: () {
                Clipboard.setData(ClipboardData(text: url));
                VpsNotification.success(context, 'URL copied to clipboard.',
                    title: 'COPIED');
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: SovColors.accent.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(8),
                  color: SovColors.accent.withValues(alpha: 0.06),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.copy_rounded,
                        size: 14, color: SovColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      baseUrl,
                      style: const TextStyle(
                        color: SovColors.textSecondary,
                        fontFamily: SovFonts.mono,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // BOOTING STATE
  // ──────────────────────────────────────────────────────────────

  Widget _buildBootingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Opacity(
              opacity: _pulseAnimation.value,
              child: child,
            ),
            child: const CircularProgressIndicator(color: SovColors.accent),
          ),
          const SizedBox(height: SovSpacing.lg),
          const Text(
            'Starting Desktop Environment...',
            style:
                TextStyle(color: SovColors.textSecondary, letterSpacing: 1.2),
          ),
          const SizedBox(height: SovSpacing.sm),
          Text(
            'X Server → KasmVNC → Cloudflare Tunnel',
            style: TextStyle(
              color: SovColors.textSecondary.withValues(alpha: 0.5),
              fontSize: 11,
              fontFamily: SovFonts.mono,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // HEADLESS / DISABLED STATE
  // ──────────────────────────────────────────────────────────────

  Widget _buildDisabledState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SovSpacing.xl),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                SovColors.accent.withValues(alpha: 0.12),
                SovColors.accentPurple.withValues(alpha: 0.08),
                Colors.transparent,
              ],
            ),
            border: Border.all(
              color: SovColors.accent.withValues(alpha: 0.18),
            ),
          ),
          child: GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(SovSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) => Transform.scale(
                      scale: 0.95 + 0.05 * _pulseAnimation.value,
                      child: child,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amberAccent.withValues(alpha: 0.15),
                            blurRadius: 30,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.workspace_premium_rounded,
                          size: 64, color: Colors.amberAccent),
                    ),
                  ),
                  const SizedBox(height: SovSpacing.lg),
                  const Text(
                    'ULTRA-LOW LATENCY GUI',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(height: SovSpacing.xs),
                  const Text(
                    'HYPER-OS VISUAL INTERFACE',
                    style: TextStyle(
                      color: SovColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: SovSpacing.lg),
                  const Text(
                    'Initialize PublicNode in GUI mode to access the full\nhigh-performance Linux desktop environment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SovColors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: SovSpacing.xl),
                  VpsBounce(
                    onTap: () {
                      VpsNotification.info(
                        context,
                        'Set GUI_ENABLED=true and restart the PublicNode engine.',
                        title: 'INIT REQUIRED',
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 36, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.amberAccent, Color(0xFFFFB300)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amberAccent.withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flash_on_rounded,
                              color: Colors.black87, size: 20),
                          SizedBox(width: 12),
                          Text(
                            'UPGRADE TO GUI MODE',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
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

  // ──────────────────────────────────────────────────────────────
  // GUI HEADER BAR
  // ──────────────────────────────────────────────────────────────

  Widget _buildGuiHeader(EngineService engine) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SovSpacing.md, vertical: SovSpacing.sm),
      color: SovColors.surface,
      child: Row(
        children: [
          _buildStatusPill(engine.guiRunning),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DISPLAY: ${engine.guiDisplay}',
                style: const TextStyle(
                  color: SovColors.textPrimary,
                  fontSize: 10,
                  fontFamily: SovFonts.mono,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'RES: ${engine.guiResolution}',
                style: const TextStyle(
                  color: SovColors.textSecondary,
                  fontSize: 9,
                  fontFamily: SovFonts.mono,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (!_isWebViewSupported && engine.guiUrl != null)
            _buildActionIcon(
              icon: Icons.open_in_new_rounded,
              tooltip: 'Open in System Browser',
              onTap: () => _launchInBrowser(_buildKasmUrl(engine.guiUrl!)),
            ),
          if (_isWebViewSupported) ...[
            _buildActionIcon(
              icon: Icons.refresh_rounded,
              tooltip: 'Reload WebView',
              onTap: () => _webViewController?.reload(),
            ),
            const SizedBox(width: 4),
          ],
          _buildActionIcon(
            icon: Icons.power_settings_new_rounded,
            tooltip: 'Restart GUI Stack',
            onTap: () async {
              VpsNotification.processing(context, 'Rebooting GUI Stack...',
                  title: 'RESTARTING');
              await engine.setGuiEnabled(false);
              await engine.setGuiEnabled(true);
            },
          ),
          const SizedBox(width: 4),
          _buildActionIcon(
            icon: Icons.receipt_long_outlined,
            tooltip: 'View GUI Logs',
            onTap: () async {
              final logs = await engine.fetchGuiLogs();
              _showLogsDialog(logs);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(bool isRunning) {
    final color = isRunning ? SovColors.success : SovColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Opacity(
              opacity: isRunning ? _pulseAnimation.value : 1.0,
              child: child,
            ),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isRunning ? 'ONLINE' : 'OFFLINE',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: SovColors.textSecondary, size: 18),
        ),
      ),
    );
  }

  void _showLogsDialog(List<String> logs) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SovColors.surface,
        title: const Text('GUI STACK LOGS',
            style: TextStyle(color: SovColors.accent, fontSize: 14)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: logs.isEmpty
              ? const Center(
                  child: Text('No logs available.',
                      style: TextStyle(color: SovColors.textSecondary)))
              : ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      logs[index],
                      style: const TextStyle(
                        color: SovColors.textSecondary,
                        fontFamily: SovFonts.mono,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('CLOSE', style: TextStyle(color: SovColors.accent)),
          ),
        ],
      ),
    );
  }
}
