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
import '../widgets/glass_card.dart';
import '../widgets/vps_notification.dart';
import '../widgets/vps_text_field.dart';
import '../widgets/vps_bounce.dart';
import '../services/cloud_service.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../services/engine_service.dart';

class SettingsScreen extends StatefulWidget {
  final bool scrollToDrive;
  const SettingsScreen({super.key, this.scrollToDrive = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _kagUserCtrl = TextEditingController();
  final _kagKeyCtrl = TextEditingController();
  final _hfTokenCtrl = TextEditingController();
  final _kernelSlugCtrl = TextEditingController();
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

  final ScrollController _scrollController = ScrollController();

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
      _kernelSlugCtrl.text = saved['kernelSlug'] ?? '';
      _vpsUserCtrl.text = saved['username'] ?? 'root';
      _topicPrefixCtrl.text = saved['topicPrefix'] ?? 'vps-root';
      _isLoading = false;
    });
    // Initial validation
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
    _vpsUserCtrl.dispose();
    _topicPrefixCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_kagStatus == VpsValidationStatus.invalid ||
        _hfStatus == VpsValidationStatus.invalid) {
      VpsNotification.error(
        context,
        'Please resolve invalid credentials before saving.',
      );
      return;
    }

    await StorageService.saveSettings(
      kaggleUser: _kagUserCtrl.text.trim(),
      kaggleKey: _kagKeyCtrl.text.trim(),
      hfToken: _hfTokenCtrl.text.trim(),
      kernelSlug: _kernelSlugCtrl.text.trim(),
      vpsUser: _vpsUserCtrl.text.trim(),
      topicPrefix: _topicPrefixCtrl.text.trim(),
    );

    // Also notify engine if connected
    if (!mounted) return;

    if (mounted) {
      VpsNotification.success(context, 'PublicNode Settings Saved!');
      Navigator.of(context).pop();
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
                'Your Kaggle account MUST be phone-verified. Go to Kaggle Settings -> Account -> Phone Verification. Without this, the VPS cannot ignite. This is an industry-standard requirement for using Kaggle compute resources.',
              ),
              _guideItem(
                '2. KAGGLE API KEY',
                'Go to Kaggle Settings -> API -> "Create New Token". This downloads kaggle.json. Open it and copy your "username" and "key" into this app. Keep this key safe as it grants access to your Kaggle account.',
              ),
              _guideItem(
                '3. HUGGINGFACE TOKEN',
                'Go to HF Settings -> Access Tokens -> "New Token". Set Name to "PublicNode-Vault" and Type to "WRITE". This allows your VPS to auto-save its entire system state to System Vault repositories.',
              ),
              _guideItem(
                '4. KERNEL SLUG',
                'This is the unique ID for your VPS instance on Kaggle. Use lowercase and hyphens (e.g., my-publicnode-node). The app will automatically create and configure this kernel during the first ignition.',
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('SETTINGS'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: VpsBounce(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back, color: SovColors.textPrimary),
        ),
        actions: [
          VpsBounce(
            onTap: _showGuideDialog,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.help_outline, color: SovColors.accent),
            ),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1B2A), SovColors.background],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Consumer<EngineService>(
                builder: (context, engine, _) => Center(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: SovSpacing.lg,
                      vertical: 80,
                    ),
                    child: GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'KAGGLE INFRASTRUCTURE',
                            style: TextStyle(
                              color: SovColors.accent,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: SovSpacing.md),
                          VpsTextField(
                            controller: _kagUserCtrl,
                            label: 'Kaggle Username',
                            prefixIcon: const Icon(
                              Icons.person_outline,
                              size: 20,
                            ),
                            onChanged: (_) => _validateKaggle(),
                            validationStatus: _kagStatus,
                          ),
                          const SizedBox(height: SovSpacing.md),
                          VpsTextField(
                            controller: _kagKeyCtrl,
                            label: 'Kaggle API Key',
                            isPassword: true,
                            helperText:
                                'Requires phone-verified Kaggle account',
                            prefixIcon: const Icon(
                              Icons.vpn_key_outlined,
                              size: 20,
                            ),
                            onChanged: (_) => _validateKaggle(),
                            validationStatus: _kagStatus,
                            validationMessage: _kagMsg,
                            guidanceText: _kagGuide,
                          ),
                          const SizedBox(height: SovSpacing.xl),
                          const Text(
                            'DATA PERSISTENCE (HuggingFace)',
                            style: TextStyle(
                              color: SovColors.accent,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: SovSpacing.md),
                          VpsTextField(
                            controller: _hfTokenCtrl,
                            label: 'HF Write Token',
                            isPassword: true,
                            helperText:
                                'Requires "Write" permission for data persistence',
                            prefixIcon: const Icon(Icons.security, size: 20),
                            onChanged: (_) => _validateHF(),
                            validationStatus: _hfStatus,
                            validationMessage: _hfMsg,
                            guidanceText: _hfGuide,
                          ),
                          const SizedBox(height: SovSpacing.xl),
                          const SizedBox(height: SovSpacing.xl),
                          const Text(
                            'BACKBONE CONFIGURATION',
                            style: TextStyle(
                              color: SovColors.accent,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: SovSpacing.md),
                          VpsTextField(
                            controller: _kernelSlugCtrl,
                            label: 'Kaggle Kernel Slug',
                            hintText: 'e.g., publicnode-vps-node',
                            prefixIcon: const Icon(Icons.code, size: 20),
                          ),
                          const SizedBox(height: SovSpacing.md),
                          VpsTextField(
                            controller: _vpsUserCtrl,
                            label: 'VPS SSH Username',
                            prefixIcon: const Icon(Icons.terminal, size: 20),
                          ),
                          const SizedBox(height: SovSpacing.md),
                          VpsTextField(
                            controller: _topicPrefixCtrl,
                            label: 'Signal Topic Prefix',
                            prefixIcon: const Icon(Icons.sensors, size: 20),
                            textInputAction: TextInputAction.done,
                            onSubmitted: _save,
                          ),
                          const SizedBox(height: SovSpacing.xxl),
                          const SizedBox(height: SovSpacing.xxl),
                          ElevatedButton(
                            onPressed: _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SovColors.accent,
                              foregroundColor: SovColors.background,
                              padding: const EdgeInsets.all(SovSpacing.md),
                            ),
                            child: const Text('SAVE SETTINGS'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
