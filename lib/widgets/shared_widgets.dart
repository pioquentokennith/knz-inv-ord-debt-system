// ─────────────────────────────────────────────────────────────────────────────
// shared_widgets.dart
// Purpose : Reusable UI components shared across all screens in the app.
// Contains: GoldButton, DarkTextField, DarkDropdown, StatCard,
//           OrderStatusBadge, CategoryBadge, StockBadge, DarkIconButton,
//           SectionHeader, KnzFadeIn, showConfirmDialog,
//           KnzToast (animated overlay toast — replaces SnackBar for CRUD feedback)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_constants.dart';
import '../models/order_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// KnzToast — lightweight animated overlay toast (no ScaffoldMessenger needed)
// ─────────────────────────────────────────────────────────────────────────────
// Usage:
//   KnzToast.show(context, 'Product added!', type: KnzToastType.success);
//   KnzToast.show(context, 'Deleted.', type: KnzToastType.error);
//   KnzToast.show(context, 'Stock updated.', type: KnzToastType.info);
//   KnzToast.show(context, 'Check fields.', type: KnzToastType.warning);
// ─────────────────────────────────────────────────────────────────────────────

enum KnzToastType { success, error, warning, info }

class KnzToast {
  KnzToast._();

  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message, {
    KnzToastType type = KnzToastType.success,
    Duration duration = const Duration(seconds: 3),
  }) {
    // Dismiss any existing toast immediately (no stacking)
    _current?.remove();
    _current = null;

    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _KnzToastWidget(
        message: message,
        type: type,
        duration: duration,
        onDismiss: () {
          entry.remove();
          if (_current == entry) _current = null;
        },
      ),
    );

    _current = entry;
    overlay.insert(entry);
  }

  // Convenience shortcuts
  static void success(BuildContext ctx, String msg) =>
      show(ctx, msg, type: KnzToastType.success);
  static void error(BuildContext ctx, String msg) =>
      show(ctx, msg, type: KnzToastType.error);
  static void warning(BuildContext ctx, String msg) =>
      show(ctx, msg, type: KnzToastType.warning);
  static void info(BuildContext ctx, String msg) =>
      show(ctx, msg, type: KnzToastType.info);
}

class _KnzToastWidget extends StatefulWidget {
  final String message;
  final KnzToastType type;
  final Duration duration;
  final VoidCallback onDismiss;

  const _KnzToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_KnzToastWidget> createState() => _KnzToastWidgetState();
}

class _KnzToastWidgetState extends State<_KnzToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _ctrl.forward();

    // Auto-dismiss after [duration]
    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _color {
    switch (widget.type) {
      case KnzToastType.success:
        return AppColors.success;
      case KnzToastType.error:
        return AppColors.error;
      case KnzToastType.warning:
        return AppColors.warning;
      case KnzToastType.info:
        return AppColors.info;
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case KnzToastType.success:
        return Icons.check_circle_rounded;
      case KnzToastType.error:
        return Icons.cancel_rounded;
      case KnzToastType.warning:
        return Icons.warning_rounded;
      case KnzToastType.info:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom:
          MediaQuery.of(context).viewInsets.bottom +
          MediaQuery.of(context).padding.bottom +
          24,
      left: 20,
      right: 20,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: Material(
            color: Colors.transparent,
            child: Semantics(
              button: true,
              label: 'Dismiss notification: ${widget.message}',
              excludeSemantics: true,
              child: InkWell(
                onTap: _dismiss,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _color.withValues(alpha: 0.45),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: _color.withValues(alpha: 0.12),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Colored left accent bar
                      Container(
                        width: 3,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(_icon, color: _color, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.close_rounded,
                        color: AppColors.whiteTertiary,
                        size: 16,
                      ),
                    ],
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

// ─── Animated Confirm Dialog ──────────────────────────────────────────────────
// Replaces the plain AlertDialog with a scale+fade entry animation.
// API identical to old showConfirmDialog — drop-in replacement.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  Color? confirmColor,
  IconData? icon,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
        child: FadeTransition(opacity: anim, child: child),
      );
    },
    pageBuilder: (ctx, _, __) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: confirmColor ?? AppColors.gold, size: 20),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: const TextStyle(
          color: AppColors.whiteSecondary,
          fontSize: 14,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            cancelLabel,
            style: const TextStyle(color: AppColors.whiteTertiary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(
            backgroundColor: (confirmColor ?? AppColors.gold).withValues(
              alpha: 0.12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: confirmColor ?? AppColors.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );
  return result == true;
}

// ─── Fade-in list item animation ──────────────────────────────────────────────
// Wraps any child in a fade+slide-up entrance animation.
// Used on list item builds so cards appear smoothly when the screen loads.
class KnzFadeIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  const KnzFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 280),
  });

  @override
  State<KnzFadeIn> createState() => _KnzFadeInState();
}

class _KnzFadeInState extends State<KnzFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ─── Gold Gradient Button ──────────────────────────────────────────────────
class GoldButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final double? width;
  final double height;
  final double fontSize;

  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.width,
    this.height = 52,
    this.fontSize = 14,
  });

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          onTapDown: enabled ? (_) => _ctrl.forward() : null,
          onTapUp: enabled ? (_) => _ctrl.reverse() : null,
          onTapCancel: enabled ? () => _ctrl.reverse() : null,
          borderRadius: BorderRadius.circular(8),
          canRequestFocus: enabled,
          child: AnimatedBuilder(
            animation: _scale,
            builder: (_, child) =>
                Transform.scale(scale: _scale.value, child: child),
            child: Ink(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                gradient: enabled ? AppColors.goldGradient : null,
                color: enabled ? null : AppColors.whiteTertiary,
                borderRadius: BorderRadius.circular(8),
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.background,
                    letterSpacing: 1.5,
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

// ─── Dark Input Field ──────────────────────────────────────────────────────
class DarkTextField extends StatelessWidget {
  final String hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? label;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final IconData? prefixIcon;

  const DarkTextField({
    super.key,
    required this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.label,
    this.maxLines = 1,
    this.inputFormatters,
    this.onChanged,
    this.prefixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: AppTextStyles.labelSmall),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLines: maxLines,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          style: const TextStyle(color: AppColors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppColors.whiteTertiary,
              fontSize: 14,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: AppColors.whiteTertiary, size: 18)
                : null,
            filled: true,
            fillColor: AppColors.inputFill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Dark Dropdown ─────────────────────────────────────────────────────────
class DarkDropdown<T> extends StatelessWidget {
  final String? label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const DarkDropdown({
    super.key,
    this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: AppTextStyles.labelSmall),
          const SizedBox(height: 6),
        ],
        Container(
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              dropdownColor: AppColors.surfaceElevated,
              style: const TextStyle(color: AppColors.white, fontSize: 14),
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: AppColors.whiteTertiary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Stat Card ─────────────────────────────────────────────────────────────
class StatCard extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final String? subtitle;
  final Color subtitleColor;

  const StatCard({
    super.key,
    required this.emoji,
    required this.value,
    required this.label,
    this.subtitle,
    this.subtitleColor = AppColors.success,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(12)),
        border: Border(top: BorderSide(color: AppColors.gold, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppTextStyles.cardTitle),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.cardLabel,
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 11, color: subtitleColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Order Status Badge ────────────────────────────────────────────────────
class OrderStatusBadge extends StatelessWidget {
  final OrderStatus status;

  const OrderStatusBadge({super.key, required this.status});

  Color get _color => status.color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.displayName.toUpperCase(),
        style: TextStyle(
          color: _color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ─── Category Badge ────────────────────────────────────────────────────────
class CategoryBadge extends StatelessWidget {
  final String label;

  const CategoryBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.info,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─── Stock Badge ───────────────────────────────────────────────────────────
class StockBadge extends StatelessWidget {
  final bool isLowStock;

  const StockBadge({super.key, required this.isLowStock});

  @override
  Widget build(BuildContext context) {
    final color = isLowStock ? AppColors.warning : AppColors.success;
    final label = isLowStock ? 'LOW STOCK' : 'IN STOCK';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─── Dark Icon Button ──────────────────────────────────────────────────────
class DarkIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final String? semanticLabel;

  const DarkIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color = AppColors.whiteTertiary,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final label = semanticLabel ?? 'Action';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: color, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppColors.cardBorder),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section Header ────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.sectionHeader,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              trailing!,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
