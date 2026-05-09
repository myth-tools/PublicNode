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

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../widgets/vps_bounce.dart';
import 'package:flutter/services.dart';
import '../app/constants.dart';
import '../services/navigation_service.dart';
import '../services/engine_service.dart';
import './vps_notification.dart';
import '../utils/vps_api_utils.dart';

class ProcessTab extends StatefulWidget {
  final String baseUrl;
  final String password;

  const ProcessTab({super.key, required this.baseUrl, required this.password});

  @override
  State<ProcessTab> createState() => _ProcessTabState();
}

class _ProcessTabState extends State<ProcessTab> {
  String _searchQuery = '';
  String _sortBy = 'cpu'; // 'cpu', 'ram', 'pid'

  Future<void> _handleAction(int pid, String name, String action) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SovColors.surface,
        title: Text(
          '${action.toUpperCase()} Program?',
          style: const TextStyle(color: SovColors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to $action $name (ID: $pid)?',
          style: const TextStyle(color: SovColors.textSecondary),
        ),
        actions: [
          VpsBounce(
            onTap: () => Navigator.pop(ctx, false),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('CANCEL'),
            ),
          ),
          VpsBounce(
            onTap: () => Navigator.pop(ctx, true),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                action.toUpperCase(),
                style: TextStyle(
                  color: action == 'kill' ? SovColors.error : SovColors.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final endpoint =
          action == 'kill' ? '/api/procs/kill' : '/api/procs/signal';
      final uri = VpsApiUtils.buildUri(widget.baseUrl, endpoint);

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-PublicNode-Key': widget.password.trim(),
            },
            body: json.encode({
              'pid': pid,
              if (action != 'kill')
                'signal': action == 'suspend' ? 'STOP' : 'CONT',
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (mounted) {
        if (response.statusCode != 200) {
          VpsNotification.error(
            context,
            'Could not $action the program. Please try again.',
            title: 'ACTION_FAILED',
          );
        } else {
          VpsNotification.success(
              context, 'Program $action finished for $name.',
              title: 'DONE');
        }
      }
    } catch (e) {
      if (mounted) VpsNotification.error(context, 'Error: $e');
    }
  }

  List<dynamic> _getFilteredProcs(List<dynamic>? procs) {
    if (procs == null) return [];
    var filtered = procs.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) ||
          p['pid'].toString().contains(_searchQuery);
    }).toList();

    filtered.sort((a, b) {
      if (_sortBy == 'cpu') {
        return (b['cpu_percent'] ?? 0).compareTo(a['cpu_percent'] ?? 0);
      }
      if (_sortBy == 'ram') {
        return (b['memory_percent'] ?? 0).compareTo(a['memory_percent'] ?? 0);
      }
      return a['pid'].compareTo(b['pid']);
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EngineService>(
      builder: (context, engine, child) {
        if (!engine.isOnline) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  strokeWidth: 2,
                  color: SovColors.accent,
                ),
                SizedBox(height: 16),
                Text(
                  'Loading programs...',
                  style: TextStyle(
                    color: SovColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }

        final filteredProcs = _getFilteredProcs(engine.procs);

        return Column(
          children: [
            // --- Advanced Header & Search ---
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                color: SovColors.surface,
                border: Border(
                  bottom: BorderSide(color: SovColors.borderGlass),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.analytics_outlined,
                        color: SovColors.accent,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'ACTIVE PROGRAMS',
                        style: TextStyle(
                          color: SovColors.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                      const Spacer(),
                      _buildSortChip('CPU', 'cpu'),
                      const SizedBox(width: 8),
                      _buildSortChip('RAM', 'ram'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: const TextStyle(
                      color: SovColors.textPrimary,
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search programs...',
                      hintStyle: TextStyle(
                        color: SovColors.textSecondary.withValues(alpha: 0.5),
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 16,
                        color: SovColors.textSecondary,
                      ),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // --- Process List ---
            Expanded(
              child: ListView.builder(
                itemCount: filteredProcs.length,
                itemBuilder: (context, index) {
                  final proc = filteredProcs[index];
                  return _ProcessTile(
                    proc: proc,
                    onAction: (action) => _handleAction(
                      proc['pid'],
                      proc['name'] ?? 'unknown',
                      action,
                    ),
                    baseUrl: widget.baseUrl,
                    password: widget.password,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSortChip(String label, String value) {
    final isActive = _sortBy == value;
    return VpsBounce(
      onTap: () => setState(() => _sortBy = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? SovColors.accent.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? SovColors.accent : SovColors.borderGlass,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? SovColors.accent : SovColors.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _ProcessTile extends StatelessWidget {
  final dynamic proc;
  final Function(String) onAction;
  final String baseUrl;
  final String password;

  const _ProcessTile({
    required this.proc,
    required this.onAction,
    required this.baseUrl,
    required this.password,
  });

  String _getProcessHelp(Map<String, dynamic> p) {
    final cmd = p['cmdline'];
    if (cmd != null && (cmd is List) && cmd.isNotEmpty) {
      return cmd.join(' ');
    }
    final exe = p['exe'];
    if (exe != null && exe.toString().isNotEmpty) {
      return exe.toString();
    }

    final n = (p['name'] ?? '').toString().toLowerCase();
    if (n.contains('python')) return 'System Engine';
    if (n.contains('sshd')) return 'Remote Login Server';
    if (n.contains('cloudflared')) return 'Secure Tunnel';
    if (n.contains('websocat')) return 'Connection Bridge';
    if (n.contains('htop') || n.contains('top')) return 'Activity Monitor';
    if (n.contains('zsh') || n.contains('bash')) return 'Terminal Session';
    return 'Background Task';
  }

  @override
  Widget build(BuildContext context) {
    final cpu = (proc['cpu_percent'] ?? 0.0).toDouble();
    final ram = (proc['memory_percent'] ?? 0.0).toDouble();

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SovColors.borderGlass)),
      ),
      child: InkWell(
        onSecondaryTapDown: (details) =>
            _showProcessContextMenu(context, details.globalPosition),
        onLongPress: () => _showProcessContextMenu(context, Offset.zero),
        child: VpsBounce(
          onTap: () {}, // Handled by ListTile? No, wrap ListTile properly
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: SizedBox(
              width: 40,
              child: Text(
                '#${proc['pid']}',
                style: const TextStyle(
                  color: SovColors.textSecondary,
                  fontSize: 10,
                  fontFamily: SovFonts.mono,
                ),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    (proc['name'] ?? 'unknown').toString(),
                    style: const TextStyle(
                      color: SovColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _UsageBadge(label: 'CPU', value: cpu, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                _UsageBadge(
                    label: 'RAM', value: ram, color: Colors.purpleAccent),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _getProcessHelp(proc),
                style: TextStyle(
                  color: SovColors.textSecondary.withValues(alpha: 0.6),
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_horiz,
                color: SovColors.textSecondary,
                size: 18,
              ),
              color: SovColors.surface,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'suspend',
                  child: Text('Pause Program'),
                ),
                const PopupMenuItem(
                  value: 'resume',
                  child: Text('Continue Program'),
                ),
                const PopupMenuItem(
                  value: 'kill',
                  child: Text(
                    'Stop Program',
                    style: TextStyle(color: SovColors.error),
                  ),
                ),
              ],
              onSelected: onAction,
            ),
          ),
        ),
      ),
    );
  }

  void _showProcessContextMenu(BuildContext context, Offset position) {
    HapticFeedback.mediumImpact();
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final pid = proc['pid'];

    showMenu<dynamic>(
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
              Icon(Icons.pause, size: 16, color: SovColors.warning),
              SizedBox(width: 12),
              Text('Pause'),
            ],
          ),
          onTap: () => onAction('suspend'),
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.play_arrow, size: 16, color: SovColors.success),
              SizedBox(width: 12),
              Text('Continue'),
            ],
          ),
          onTap: () => onAction('resume'),
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.delete_forever, size: 16, color: SovColors.error),
              SizedBox(width: 12),
              Text('Stop Program'),
            ],
          ),
          onTap: () => onAction('kill'),
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: SovColors.accent),
              SizedBox(width: 12),
              Text('Show Location'),
            ],
          ),
          onTap: () {
            final exe = proc['exe']?.toString();
            if (exe != null && exe.isNotEmpty) {
              final dir = exe.substring(0, exe.lastIndexOf('/'));
              context.read<NavigationService>().openInExplorer(dir);
            } else {
              VpsNotification.warning(
                context,
                'Could not find the location for this program.',
                title: 'NOT_FOUND',
              );
            }
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.copy, size: 16, color: SovColors.accent),
              SizedBox(width: 12),
              Text('Copy PID'),
            ],
          ),
          onTap: () {
            Clipboard.setData(ClipboardData(text: proc['pid'].toString()));
            HapticFeedback.lightImpact();
            VpsNotification.success(
                context, 'Program ID ($pid) copied to clipboard.',
                title: 'COPIED');
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.code, size: 16, color: SovColors.accent),
              SizedBox(width: 12),
              Text('Copy Command'),
            ],
          ),
          onTap: () {
            final cmd = proc['cmdline'];
            if (cmd != null && cmd is List) {
              Clipboard.setData(ClipboardData(text: cmd.join(' ')));
              HapticFeedback.lightImpact();
              VpsNotification.success(
                  context, 'Program details copied to clipboard.',
                  title: 'COPIED');
            }
          },
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
              Text('Program Details'),
            ],
          ),
          onTap: () =>
              _showProcessProperties(context, pid, proc['name'] ?? 'unknown'),
        ),
      ],
    );
  }

  Future<void> _showProcessProperties(
    BuildContext context,
    int pid,
    String name,
  ) async {
    final engine = Provider.of<EngineService>(context, listen: false);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SovColors.surface,
        title: Text(
          'Program: $name (ID $pid)',
          style: const TextStyle(color: SovColors.accent, fontSize: 16),
        ),
        content: FutureBuilder(
          future: _fetchDetailedInfo(engine, pid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 100,
                child: Center(
                  child: CircularProgressIndicator(color: SovColors.accent),
                ),
              );
            }
            if (snapshot.hasError) {
              return Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: SovColors.error),
              );
            }

            final data = snapshot.data as Map<String, dynamic>;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _prop('Program Location', data['exe'] ?? 'N/A'),
                  _prop('Owner', data['username'] ?? 'N/A'),
                  _prop(
                      'Active Tasks', data['num_threads']?.toString() ?? 'N/A'),
                  _prop(
                    'Started At',
                    DateTime.fromMillisecondsSinceEpoch(
                      data['create_time'] * 1000,
                    ).toString(),
                  ),
                  _prop(
                    'Memory Used',
                    '${data['memory_full_info']?['rss'] ?? 0} bytes',
                  ),
                  _prop(
                    'Files in Use',
                    (data['open_files'] as List).length.toString(),
                  ),
                  _prop(
                    'Network Links',
                    (data['connections'] as List).length.toString(),
                  ),
                ],
              ),
            );
          },
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

  Future<Map<String, dynamic>> _fetchDetailedInfo(
    EngineService engine,
    int pid,
  ) async {
    final uri = VpsApiUtils.buildUri(
      baseUrl,
      '/api/procs/info',
      {'pid': pid.toString()},
    );
    final response = await http.get(
      uri,
      headers: {'X-PublicNode-Key': password},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to fetch process info: ${response.statusCode}');
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

class _UsageBadge extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _UsageBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$label ${value.toStringAsFixed(1)}%',
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 40,
          height: 2,
          color: color.withValues(alpha: 0.1),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (value / 100).clamp(0.01, 1.0),
            child: Container(color: color),
          ),
        ),
      ],
    );
  }
}
