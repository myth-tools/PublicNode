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
import 'package:provider/provider.dart';
import '../services/engine_service.dart';
import '../app/constants.dart';

class MonitorTab extends StatelessWidget {
  const MonitorTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<EngineService>(
      builder: (context, engine, child) {
        if (!engine.isOnline) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.cloud_off,
                  color: SovColors.textSecondary,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  engine.error ?? 'Connecting to Engine Telemetry...',
                  style: const TextStyle(color: SovColors.textSecondary),
                ),
              ],
            ),
          );
        }

        final stats = engine.stats;
        final cpu = (stats['cpu'] ?? 0.0).toDouble();
        final ram = (stats['ram'] ?? 0.0).toDouble();
        final netIn = (stats['net_in_kb'] ?? 0.0).toDouble();
        final netOut = (stats['net_out_kb'] ?? 0.0).toDouble();
        final diskSpeed = (stats['disk_speed_mb'] ?? 0.0).toDouble();
        final cpuFreq =
            stats['stats']?['cpu_freq'] ?? 0; // Handled via sysinfo or stats

        // GPU Logic (Industrial Grade)
        final List<dynamic> gpus = stats['gpus'] ?? [];

        return ListView(
          padding: const EdgeInsets.all(SovSpacing.md),
          children: [
            _buildMetricCard(
              'CPU Performance',
              '${cpu.toStringAsFixed(1)}%',
              cpu / 100,
              Icons.speed,
              Colors.cyanAccent,
              subtitle: cpuFreq > 0 ? '$cpuFreq MHz Nominal' : null,
            ),
            _buildMetricCard(
              'Memory Capacity',
              '${ram.toStringAsFixed(1)}%',
              ram / 100,
              Icons.memory,
              Colors.purpleAccent,
            ),
            _buildMetricCard(
              'Disk Throughput',
              '${diskSpeed.toStringAsFixed(1)} MB/s',
              null,
              Icons.storage,
              Colors.amberAccent,
            ),
            _buildMetricCard(
              'Network Traffic',
              'RX: ${netIn.toStringAsFixed(1)} KB/s\nTX: ${netOut.toStringAsFixed(1)} KB/s',
              null,
              Icons.lan,
              Colors.greenAccent,
            ),
            if (gpus.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'GPU ACCELERATION',
                  style: TextStyle(
                    color: SovColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              ...gpus.map(
                (g) => _buildMetricCard(
                  g['name'] ?? 'NVIDIA GPU',
                  '${g['util']}% Core',
                  g['util'] / 100.0,
                  Icons.memory_outlined,
                  Colors.greenAccent,
                  subtitle: 'VRAM: ${g['used']}MB / ${g['total']}MB',
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    double? progress,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: SovSpacing.md),
      padding: const EdgeInsets.all(SovSpacing.md),
      decoration: BoxDecoration(
        color: SovColors.surface,
        borderRadius: BorderRadius.circular(SovSpacing.borderRadius),
        border: Border.all(color: SovColors.borderGlass),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: SovColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.7),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: SovColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: SovFonts.mono,
                ),
                textAlign: TextAlign.right,
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: color.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
