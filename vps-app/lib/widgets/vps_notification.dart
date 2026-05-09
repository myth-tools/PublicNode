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
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/constants.dart';

enum NotificationType { success, error, warning, info, system, processing }

class VpsNotification {
  static final List<_NotificationData> _queue = [];
  static OverlayEntry? _overlayEntry;
  static GlobalKey<AnimatedListState>? _listKey;
  static bool _isOverlayActive = false;

  static void show(
    BuildContext context, {
    required String message,
    NotificationType type = NotificationType.info,
    String? title,
    Duration duration = const Duration(seconds: 6),
    bool sticky = false,
  }) {
    final data = _NotificationData(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      message: message,
      title: title,
      type: type,
      duration: duration,
      sticky: sticky || type == NotificationType.processing,
    );

    if (!_isOverlayActive) {
      // First item: ensure overlay is up
      _queue.insert(0, data);
      _ensureOverlay(context);
    } else {
      // Overlay exists: use AnimatedList for smooth entry
      _queue.insert(0, data);
      _listKey?.currentState?.insertItem(
        0,
        duration: const Duration(milliseconds: 600),
      );
    }

    // Auto-dismiss logic
    if (!data.sticky) {
      Timer(duration, () {
        _dismiss(data.id);
      });
    }
  }

  static void _ensureOverlay(BuildContext context) {
    if (_isOverlayActive) return;

    final overlay = Overlay.of(context);
    _listKey = GlobalKey<AnimatedListState>();

    _overlayEntry = OverlayEntry(
      builder: (context) => _NotificationStack(
        listKey: _listKey!,
        notifications: _queue,
        onDismiss: (id) => _dismiss(id),
      ),
    );

    _isOverlayActive = true;
    overlay.insert(_overlayEntry!);
  }

  static void _dismiss(String id) {
    final index = _queue.indexWhere((n) => n.id == id);
    if (index == -1) return;

    final removedItem = _queue.removeAt(index);

    _listKey?.currentState?.removeItem(
      index,
      (context, animation) => _NotificationWidget(
        data: removedItem,
        animation: animation,
        onDismiss: () {},
        isExiting: true,
      ),
      duration: const Duration(milliseconds: 500),
    );

    if (_queue.isEmpty) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (_queue.isEmpty && _isOverlayActive) {
          _overlayEntry?.remove();
          _overlayEntry = null;
          _isOverlayActive = false;
          _listKey = null;
        }
      });
    }
  }

  static void success(BuildContext context, String message, {String? title}) {
    HapticFeedback.lightImpact();
    show(context,
        message: message,
        title: title,
        type: NotificationType.success,
        duration: const Duration(seconds: 4));
  }

  static void error(BuildContext context, String message, {String? title}) {
    HapticFeedback.heavyImpact();
    show(context,
        message: message,
        title: title,
        type: NotificationType.error,
        duration: const Duration(seconds: 8));
  }

  static void warning(BuildContext context, String message, {String? title}) {
    HapticFeedback.mediumImpact();
    show(context,
        message: message,
        title: title,
        type: NotificationType.warning,
        duration: const Duration(seconds: 6));
  }

  static void info(BuildContext context, String message, {String? title}) {
    show(context,
        message: message,
        title: title,
        type: NotificationType.info,
        duration: const Duration(seconds: 4));
  }

  static void system(BuildContext context, String message, {String? title}) {
    show(context,
        message: message,
        title: title,
        type: NotificationType.system,
        duration: const Duration(seconds: 6));
  }

  static void processing(BuildContext context, String message,
      {String? title}) {
    show(context,
        message: message,
        title: title,
        type: NotificationType.processing,
        sticky: true);
  }

  static void dismissAll() {
    for (int i = _queue.length - 1; i >= 0; i--) {
      _dismiss(_queue[i].id);
    }
  }

  static void dismissProcessing() {
    final idsToRemove = _queue
        .where((n) => n.type == NotificationType.processing)
        .map((n) => n.id)
        .toList();
    for (final id in idsToRemove) {
      _dismiss(id);
    }
  }
}

class _NotificationData {
  final String id;
  final String message;
  final String? title;
  final NotificationType type;
  final Duration duration;
  final bool sticky;

  _NotificationData({
    required this.id,
    required this.message,
    this.title,
    required this.type,
    required this.duration,
    required this.sticky,
  });
}

class _NotificationStack extends StatelessWidget {
  final GlobalKey<AnimatedListState> listKey;
  final List<_NotificationData> notifications;
  final Function(String) onDismiss;

  const _NotificationStack({
    required this.listKey,
    required this.notifications,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final rightPadding = MediaQuery.paddingOf(context).right;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;

    return Stack(
      children: [
        Positioned(
          bottom: bottomPadding + (isMobile ? 12 : 24),
          right: rightPadding + (isMobile ? 12 : 24),
          width: isMobile ? 310 : 380,
          child: AnimatedList(
            key: listKey,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            initialItemCount: notifications.length,
            itemBuilder: (context, index, animation) {
              return _NotificationWidget(
                data: notifications[index],
                animation: animation,
                onDismiss: () => onDismiss(notifications[index].id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NotificationWidget extends StatefulWidget {
  final _NotificationData data;
  final Animation<double> animation;
  final VoidCallback onDismiss;
  final bool isExiting;

  const _NotificationWidget({
    required this.data,
    required this.animation,
    required this.onDismiss,
    this.isExiting = false,
  });

  @override
  State<_NotificationWidget> createState() => _NotificationWidgetState();
}

class _NotificationWidgetState extends State<_NotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: widget.data.duration,
    );
    if (!widget.data.sticky && !widget.isExiting) {
      _progressController.forward();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  Color _getColor() {
    switch (widget.data.type) {
      case NotificationType.success:
        return SovColors.success;
      case NotificationType.error:
        return SovColors.error;
      case NotificationType.warning:
        return SovColors.warning;
      case NotificationType.info:
      case NotificationType.processing:
        return SovColors.accent;
      case NotificationType.system:
        return SovColors.accentPurple;
    }
  }

  Widget _getIcon() {
    if (widget.data.type == NotificationType.processing) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(_getColor()),
        ),
      );
    }

    IconData icon;
    switch (widget.data.type) {
      case NotificationType.success:
        icon = Icons.check_circle_rounded;
        break;
      case NotificationType.error:
        icon = Icons.report_problem_rounded;
        break;
      case NotificationType.warning:
        icon = Icons.warning_rounded;
        break;
      case NotificationType.info:
        icon = Icons.info_rounded;
        break;
      case NotificationType.system:
        icon = Icons.terminal_rounded;
        break;
      default:
        icon = Icons.info_rounded;
    }
    return Icon(icon, color: _getColor(), size: 18);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return FadeTransition(
      opacity: widget.animation,
      child: SlideTransition(
        position: widget.animation.drive(
          Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutExpo)),
        ),
        child: SizeTransition(
          sizeFactor: widget.animation,
          axisAlignment: -1.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _getColor().withValues(alpha: 0.15),
                      blurRadius: 20,
                      spreadRadius: -10,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _getColor().withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              isMobile ? 12 : 16,
                              isMobile ? 12 : 14,
                              8,
                              isMobile ? 12 : 14,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _getColor().withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _getColor().withValues(alpha: 0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: _getIcon(),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (widget.data.title != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 4),
                                          child: Text(
                                            widget.data.title!.toUpperCase(),
                                            style: TextStyle(
                                              color: _getColor()
                                                  .withValues(alpha: 0.95),
                                              fontSize: isMobile ? 8 : 9,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 2.2,
                                              fontFamily: SovFonts.mono,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        widget.data.message,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.9),
                                          fontSize: isMobile ? 12 : 13,
                                          height: 1.5,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: SovFonts.ui,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  onPressed: widget.onDismiss,
                                  icon: const Icon(Icons.close_rounded),
                                  color: Colors.white.withValues(alpha: 0.25),
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  splashRadius: 20,
                                ),
                              ],
                            ),
                          ),
                          if (!widget.data.sticky && !widget.isExiting)
                            AnimatedBuilder(
                              animation: _progressController,
                              builder: (context, child) {
                                return Container(
                                  height: 2.5,
                                  width: double.infinity,
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor:
                                        1.0 - _progressController.value,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            _getColor().withValues(alpha: 0.1),
                                            _getColor(),
                                            _getColor().withValues(alpha: 0.8),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
