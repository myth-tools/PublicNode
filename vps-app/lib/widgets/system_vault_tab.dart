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
import 'package:provider/provider.dart';
import '../app/constants.dart';
import '../services/engine_service.dart';
import '../widgets/vps_notification.dart';
import '../widgets/vps_bounce.dart';

class SystemVaultTab extends StatefulWidget {
  const SystemVaultTab({super.key});

  @override
  State<SystemVaultTab> createState() => _SystemVaultTabState();
}

class _SystemVaultTabState extends State<SystemVaultTab> {
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic> _status = {};
  List<dynamic> _history = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _fetchData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchData() async {
    final engine = context.read<EngineService>();
    if (!engine.isOnline) return;

    final status = await engine.systemVaultStatus();
    final history = await engine.systemVaultHistory();

    if (mounted) {
      setState(() {
        _status = status;
        _history = history;
        _isLoading = false;

        final syncState = _status['sync'] as Map<String, dynamic>?;
        if (syncState != null) {
          _isSaving = syncState['active'] == true;
        }
      });
    }
  }

  Future<void> _saveSystem() async {
    if (_isSaving) return;

    final engine = context.read<EngineService>();
    setState(() => _isSaving = true);

    final success = await engine.systemSave();

    if (mounted) {
      if (success) {
        VpsNotification.success(
            context, 'System snapshot triggered successfully');
        _fetchData(); // Immediately poll backend for progress
      } else {
        VpsNotification.error(context, 'Failed to trigger system snapshot');
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<EngineService>();
    if (!engine.isOnline) {
      return const Center(
        child: Text(
          'Engine Offline',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: SovColors.accent),
      );
    }

    final isConfigured = _status['configured'] == true;
    final isTokenPresent = _status['hf_token_present'] == true;
    final repoUrl = _status['hf_repo'] ?? 'HuggingFace Hub';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SovColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.security,
                    color: SovColors.accent, size: 28),
              ),
              const SizedBox(width: 16),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'System Vault',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Zero-Touch OS Persistence',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Status Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: SovColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Vault Status',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isConfigured
                            ? Colors.greenAccent.withValues(alpha: 0.1)
                            : Colors.orangeAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isConfigured ? 'SECURED' : 'UNCONFIGURED',
                        style: TextStyle(
                          color: isConfigured
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildInfoRow('Storage Backend', 'HuggingFace Datasets'),
                const SizedBox(height: 8),
                _buildInfoRow('Repository', isConfigured ? repoUrl : 'N/A'),
                const SizedBox(height: 8),
                _buildInfoRow('Snapshot Sync', 'Atomic tar.zst (Rootfs)'),
                if (isConfigured) ...[
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: VpsBounce(
                      onTap: _isSaving ? null : _saveSystem,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [SovColors.accent, Colors.blueAccent],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: SovColors.accent.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: _isSaving
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.backup, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text(
                                    'Create System Snapshot',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  if (_status['sync'] != null &&
                      _status['sync']['active'] == true) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: SovColors.accent,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _status['sync']['message'] ?? 'Syncing...',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_status['sync'] != null &&
                      _status['sync']['error'] != null &&
                      _status['sync']['error'].toString().isNotEmpty &&
                      _status['sync']['active'] == false) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _status['sync']['error'].toString(),
                              style: const TextStyle(
                                  color: Colors.redAccent, fontSize: 13),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                if (!isConfigured || !isTokenPresent) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.orangeAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.orangeAccent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            !isTokenPresent
                                ? 'HF_TOKEN is missing! You must create `.vps_auth/hf.token` with your HuggingFace token and rebuild the engine.'
                                : 'Please configure HF_REPO to enable the System Vault.',
                            style: const TextStyle(
                                color: Colors.orangeAccent, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )
                ]
              ],
            ),
          ),
          const SizedBox(height: 32),

          // History Section
          if (isConfigured) ...[
            const Text(
              'Snapshot History',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (_history.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: SovColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'No snapshots found in repository.',
                  style: TextStyle(color: Colors.white54),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  final commit = _history[index];
                  final timestampInt = commit['timestamp'];
                  final timestamp = timestampInt != null
                      ? DateTime.fromMillisecondsSinceEpoch(timestampInt * 1000)
                          .toString()
                          .split('.')[0]
                      : 'Unknown time';
                  final author = commit['tier'] == 'hf'
                      ? 'System Vault'
                      : 'Kaggle Snapshot';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: SovColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: ListTile(
                      leading:
                          const Icon(Icons.commit, color: SovColors.accent),
                      title: Text(
                        'Snapshot @ $timestamp',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Author: $author',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      trailing: const Icon(Icons.cloud_done,
                          color: Colors.greenAccent, size: 20),
                    ),
                  );
                },
              ),
          ]
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
