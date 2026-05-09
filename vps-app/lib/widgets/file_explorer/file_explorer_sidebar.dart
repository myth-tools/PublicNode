// PublicNode VPS
// Copyright (C) 2026 mohammadhasanulislam

import 'package:flutter/material.dart';
import '../../app/constants.dart';
import '../vps_bounce.dart';

class FileExplorerSidebar extends StatelessWidget {
  final String currentPath;
  final bool isHomeExpanded;
  final Function(String) onNavigate;
  final VoidCallback onToggleHome;
  final bool collapsed;
  final VoidCallback? onClose;

  const FileExplorerSidebar({
    super.key,
    required this.currentPath,
    required this.isHomeExpanded,
    required this.onNavigate,
    required this.onToggleHome,
    this.collapsed = false,
    this.onClose,
  });

  static const List<Map<String, String>> homeSubFolders = [
    {
      'name': 'Documents',
      'path': '/kaggle/working/Documents',
      'icon': 'description',
    },
    {
      'name': 'Downloads',
      'path': '/kaggle/working/Downloads',
      'icon': 'download',
    },
    {'name': 'Pictures', 'path': '/kaggle/working/Pictures', 'icon': 'image'},
    {'name': 'Projects', 'path': '/kaggle/working/Projects', 'icon': 'code'},
    {'name': 'Music', 'path': '/kaggle/working/Music', 'icon': 'music_note'},
    {'name': 'Videos', 'path': '/kaggle/working/Videos', 'icon': 'movie'},
  ];

  IconData _getSidebarIcon(String iconName) {
    switch (iconName) {
      case 'storage':
        return Icons.storage;
      case 'home':
        return Icons.home_rounded;
      case 'description':
        return Icons.description_outlined;
      case 'download':
        return Icons.file_download_outlined;
      case 'image':
        return Icons.image_outlined;
      case 'code':
        return Icons.code_rounded;
      case 'music_note':
        return Icons.music_note_outlined;
      case 'movie':
        return Icons.movie_outlined;
      case 'delete_sweep':
        return Icons.delete_sweep_outlined;
      case 'cloud_done':
        return Icons.cloud_done_outlined;
      default:
        return Icons.folder;
    }
  }

  Widget _buildSidebarItem(
    String name,
    String path,
    String icon, {
    double indent = 12,
  }) {
    final isActive = currentPath == path;
    return Padding(
      padding: EdgeInsets.only(
        left: collapsed ? 4 : indent,
        right: collapsed ? 4 : 12,
        top: 1,
        bottom: 1,
      ),
      child: VpsBounce(
        onTap: () => onNavigate(path),
        child: Tooltip(
          message: collapsed ? name : '',
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? SovColors.accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(SovSpacing.borderRadiusSm),
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  _getSidebarIcon(icon),
                  color: isActive ? SovColors.accent : SovColors.textSecondary,
                  size: 16,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color:
                            isActive ? SovColors.accent : SovColors.textPrimary,
                        fontSize: 12,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandableHome() {
    final isHomeActive = currentPath == '/kaggle/working';

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: collapsed ? 4 : 12,
            right: collapsed ? 4 : 12,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(SovSpacing.borderRadiusSm),
            onTap: () => onNavigate('/kaggle/working'),
            child: Tooltip(
              message: collapsed ? 'Home' : '',
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 0 : 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isHomeActive
                      ? SovColors.accent.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(SovSpacing.borderRadiusSm),
                ),
                child: Row(
                  mainAxisAlignment: collapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Icon(
                      _getSidebarIcon('home'),
                      color: isHomeActive
                          ? SovColors.accent
                          : SovColors.textSecondary,
                      size: 18,
                    ),
                    if (!collapsed) ...[
                      const SizedBox(width: 12),
                      const Text(
                        'Home',
                        style: TextStyle(
                          color: SovColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: onToggleHome,
                        child: Icon(
                          isHomeExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          color: SovColors.textSecondary,
                          size: 16,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isHomeExpanded && !collapsed)
          ...homeSubFolders.map(
            (sub) => _buildSidebarItem(
              sub['name']!,
              sub['path']!,
              sub['icon']!,
              indent: 32,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: collapsed ? 56 : 240,
      decoration: const BoxDecoration(
        color: SovColors.surface,
        border: Border(right: BorderSide(color: SovColors.borderGlass)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
          if (onClose != null && !collapsed)
            Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: SovColors.textSecondary),
                  onPressed: onClose,
                ),
              ),
            ),
          if (!collapsed)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'QUICK ACCESS',
                style: TextStyle(
                  color: SovColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          _buildSidebarItem('Root System', '/', 'storage'),
          _buildSidebarItem('Temp', '/tmp', 'delete_sweep'),
          const SizedBox(height: 16),
          if (!collapsed)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'CLOUD STORAGE',
                style: TextStyle(
                  color: SovColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          _buildSidebarItem('System Vault (Persistent)',
              '/kaggle/working/vault', 'cloud_done'),
          const SizedBox(height: 16),
          if (!collapsed)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'PLACES',
                style: TextStyle(
                  color: SovColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          _buildExpandableHome(),
        ],
      ),
    );
  }
}
