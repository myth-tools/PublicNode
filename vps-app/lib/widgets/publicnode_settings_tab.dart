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
import '../app/constants.dart';
import '../services/storage_service.dart';
import 'vps_notification.dart';
import 'vps_text_field.dart';
import '../services/cloud_service.dart';
import 'package:provider/provider.dart';
import 'dart:async';

class PublicNodeSettingsTab extends StatefulWidget {
  const PublicNodeSettingsTab({super.key});

  @override
  State<PublicNodeSettingsTab> createState() => _PublicNodeSettingsTabState();
}

class _PublicNodeSettingsTabState extends State<PublicNodeSettingsTab> {
  final _kagUserCtrl = TextEditingController();
  final _kagKeyCtrl = TextEditingController();
  final _hfTokenCtrl = TextEditingController();
  final _kernelSlugCtrl = TextEditingController();
  final _vaultSlugCtrl = TextEditingController();
  final _vpsUserCtrl = TextEditingController(text: 'root');
  final _topicPrefixCtrl = TextEditingController();

  bool _isLoading = true;

  // Validation State
  VpsValidationStatus _kagStatus = VpsValidationStatus.none;
  String? _kagMsg;
  String? _kagGuide;

  VpsValidationStatus _hfStatus = VpsValidationStatus.none;
  String? _hfMsg;
  String? _hfGuide;

  Timer? _kagTimer;
  Timer? _hfTimer;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final saved = await StorageService.loadConnection();
    setState(() {
      _kagUserCtrl.text = saved['kagUser'] ?? '';
      _kagKeyCtrl.text = saved['kagKey'] ?? '';
      _hfTokenCtrl.text = saved['hfToken'] ?? '';
      _kernelSlugCtrl.text = saved['kernelSlug'] ?? 'publicnode-vps-engine';
      _vaultSlugCtrl.text = saved['vaultSlug'] ?? 'vps-storage';
      _topicPrefixCtrl.text = saved['topicPrefix'] ?? 'vps-root';
      _vpsUserCtrl.text = saved['username'] ?? 'root';
      _isLoading = false;
    });
    _validateKaggle();
    _validateHF();
  }

  void _validateKaggle() {
    if (_kagUserCtrl.text.isEmpty || _kagKeyCtrl.text.isEmpty) {
      setState(() {
        _kagStatus = VpsValidationStatus.none;
        _kagMsg = null;
        _kagGuide = null;
      });
      return;
    }

    _kagTimer?.cancel();
    _kagTimer = Timer(const Duration(milliseconds: 600), () async {
      final user = _kagUserCtrl.text.trim();
      final key = _kagKeyCtrl.text.trim();

      if (user.isEmpty || key.isEmpty) return;

      setState(() => _kagStatus = VpsValidationStatus.loading);
      final result = await context.read<CloudService>().validateKaggle(
            user,
            key,
          );
      if (mounted) {
        setState(() {
          _kagStatus = result['valid']
              ? VpsValidationStatus.valid
              : VpsValidationStatus.invalid;
          _kagMsg = result['message'];
          _kagGuide = result['guide'];
        });
      }
    });
  }

  void _validateHF() {
    if (_hfTokenCtrl.text.isEmpty) {
      setState(() {
        _hfStatus = VpsValidationStatus.none;
        _hfMsg = null;
        _hfGuide = null;
      });
      return;
    }

    _hfTimer?.cancel();
    _hfTimer = Timer(const Duration(milliseconds: 600), () async {
      final token = _hfTokenCtrl.text.trim();
      if (token.isEmpty) return;

      setState(() => _hfStatus = VpsValidationStatus.loading);
      final result = await context.read<CloudService>().validateHuggingFace(
            token,
          );
      if (mounted) {
        setState(() {
          _hfStatus = result['valid']
              ? VpsValidationStatus.valid
              : VpsValidationStatus.invalid;
          _hfMsg = result['message'];
          _hfGuide = result['guide'];
        });
      }
    });
  }

  @override
  void dispose() {
    _kagTimer?.cancel();
    _hfTimer?.cancel();
    _kagUserCtrl.dispose();
    _kagKeyCtrl.dispose();
    _hfTokenCtrl.dispose();
    _kernelSlugCtrl.dispose();
    _vaultSlugCtrl.dispose();
    _vpsUserCtrl.dispose();
    _topicPrefixCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_kagStatus == VpsValidationStatus.invalid ||
        _hfStatus == VpsValidationStatus.invalid) {
      VpsNotification.error(
        context,
        'Please fix your login info before saving.',
        title: 'LOGIN_ERROR',
      );
      return;
    }
    await StorageService.saveSettings(
      kaggleUser: _kagUserCtrl.text.trim(),
      kaggleKey: _kagKeyCtrl.text.trim(),
      hfToken: _hfTokenCtrl.text.trim(),
      kernelSlug: _kernelSlugCtrl.text.trim(),
      vaultSlug: _vaultSlugCtrl.text.trim(),
      vpsUser: _vpsUserCtrl.text.trim(),
      topicPrefix: _topicPrefixCtrl.text.trim(),
    );

    // Also notify engine if connected
    if (!mounted) return;

    if (mounted) {
      VpsNotification.success(context, 'Settings saved successfully.',
          title: 'SAVED');
    }
  }

  void _showGuideDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SovColors.surface,
        title: const Text(
          'PUBLICNODE SETUP GUIDE',
          style: TextStyle(
            color: SovColors.accent,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _guideItem(
                '1. KAGGLE ACCOUNT',
                'Your Kaggle account MUST be verified with a phone number. Without this, the system won\'t start.',
              ),
              _guideItem(
                '2. KAGGLE API KEY',
                'Get this from Kaggle Settings. It allows the app to manage your remote computer.',
              ),
              _guideItem(
                '3. HUGGINGFACE TOKEN',
                'This allows the system to automatically save your work so you don\'t lose anything.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'GOT IT',
              style: TextStyle(color: SovColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideItem(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
          const SizedBox(height: 4),
          Text(
            desc,
            style: const TextStyle(
              color: SovColors.textSecondary,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: SovColors.accent),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(SovSpacing.md),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('KAGGLE SETUP'),
            IconButton(
              icon: const Icon(
                Icons.help_outline,
                color: SovColors.accent,
                size: 18,
              ),
              onPressed: _showGuideDialog,
              tooltip: 'Show Setup Guide',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        _buildTextField(
          _kagUserCtrl,
          'Username',
          Icons.person_outline,
          onChanged: (_) => _validateKaggle(),
          status: _kagStatus,
        ),
        _buildTextField(
          _kagKeyCtrl,
          'API Key',
          Icons.vpn_key_outlined,
          isPassword: true,
          helper: 'Your Kaggle account must be verified with a phone number',
          onChanged: (_) => _validateKaggle(),
          status: _kagStatus,
          msg: _kagMsg,
          guide: _kagGuide,
        ),
        _buildTextField(
          _kernelSlugCtrl,
          'Engine ID',
          Icons.code,
          helper: 'e.g., my-vps-node',
        ),
        const SizedBox(height: SovSpacing.lg),
        _buildSectionHeader('BACKUP STORAGE (HF)'),
        _buildTextField(
          _hfTokenCtrl,
          'Write Token',
          Icons.security,
          isPassword: true,
          helper: 'Requires permission to save files',
          onChanged: (_) => _validateHF(),
          status: _hfStatus,
          msg: _hfMsg,
          guide: _hfGuide,
        ),
        _buildTextField(
          _vaultSlugCtrl,
          'Storage ID',
          Icons.folder_shared_outlined,
        ),
        const SizedBox(height: SovSpacing.lg),
        _buildSectionHeader('CONNECTION CHANNELS'),
        _buildTextField(
          _vpsUserCtrl,
          'VPS SSH Username',
          Icons.terminal,
        ),
        const SizedBox(height: SovSpacing.md),
        _buildTextField(
          _topicPrefixCtrl,
          'Connection Name Prefix',
          Icons.sensors,
          isLast: true,
        ),
        const SizedBox(height: SovSpacing.lg),
        const SizedBox(height: SovSpacing.xl),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: SovColors.accent,
            foregroundColor: SovColors.background,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'SAVE SETTINGS',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: SovSpacing.xl),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: SovColors.accent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isPassword = false,
    String? helper,
    bool isLast = false,
    ValueChanged<String>? onChanged,
    VpsValidationStatus status = VpsValidationStatus.none,
    String? msg,
    String? guide,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: VpsTextField(
        controller: controller,
        label: label,
        isPassword: isPassword,
        helperText: helper,
        prefixIcon: Icon(icon, size: 18, color: SovColors.textSecondary),
        textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
        onSubmitted: isLast ? _save : null,
        onChanged: onChanged,
        validationStatus: status,
        validationMessage: msg,
        guidanceText: guide,
      ),
    );
  }
}
