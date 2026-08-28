import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrowin/app/notification_center.dart';
import 'package:hydrowin/core/theme/hw_colors.dart';

/// Правый оверлей toast (ops dark: surface + status accent).
class SideToastHost extends StatelessWidget {
  const SideToastHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final center = NotificationScope.of(context);
    return Stack(
      children: [
        child,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          right: 12,
          bottom: 12,
          width: 320,
          child: ListenableBuilder(
            listenable: center,
            builder: (context, _) {
              final items = center.toasts;
              if (items.isEmpty) return const SizedBox.shrink();
              return IgnorePointer(
                ignoring: false,
                child: Align(
                  alignment: Alignment.topRight,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final t in items) ...[
                          _ToastCard(
                            item: t,
                            onClose: () => center.dismiss(t.id),
                            onOpen: () {
                              center.dismiss(t.id);
                              context.push('/notifications');
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    required this.item,
    required this.onClose,
    required this.onOpen,
  });

  final SideToastItem item;
  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0.35, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    _auto = Timer(const Duration(seconds: 8), () async {
      if (!mounted) return;
      await _ctrl.reverse();
      if (mounted) widget.onClose();
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  static String _badgeLabel(String headline, bool critical) {
    final h = headline.toLowerCase();
    if (h.contains('обрыв')) return 'ОБРЫВ ЦЕПИ';
    if (h.contains('коротк') || h.contains('кз')) return 'КЗ ПЕТЛИ';
    return critical ? 'КРИТИЧНО' : 'ВНИМАНИЕ';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final critical = widget.item.isCritical;
    final accent = critical ? HwColors.critical : HwColors.warn;
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onOpen,
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.7),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(10),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              critical
                                  ? Icons.warning_amber_rounded
                                  : Icons.info_outline,
                              color: accent,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${widget.item.code} · ${widget.item.name}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.item.headline,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.onSurface.withValues(
                                        alpha: 0.9,
                                      ),
                                      fontSize: 12.5,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _badgeLabel(
                                      widget.item.headline,
                                      critical,
                                    ),
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.close,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              ),
                              onPressed: () async {
                                _auto?.cancel();
                                await _ctrl.reverse();
                                if (mounted) widget.onClose();
                              },
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
      ),
    );
  }
}
