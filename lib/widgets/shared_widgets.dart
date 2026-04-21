// ─────────────────────────────────────────────────────────────────────────────
// shared_widgets.dart
// Purpose : Reusable UI components shared across all screens in the app.
// Contains: GoldButton, DarkTextField, DarkDropdown, StatCard,
//           OrderStatusBadge, CategoryBadge, StockBadge, DarkIconButton,
//           SectionHeader, and showConfirmDialog helper.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_constants.dart';
import '../models/order_model.dart';

// ─── Gold Gradient Button ──────────────────────────────────────────────────
// Purpose : A primary call-to-action button with a gold gradient background.
// Function: Animates a subtle scale-down (96%) on tap using AnimationController
//           to give tactile press feedback, then fires the onPressed callback.
class GoldButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
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
  // Animation controller that drives the press-scale effect
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    // Short 100ms duration for a snappy press response
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    // Scale from 1.0 (normal) to 0.96 (slightly smaller) when tapped
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),   // Shrink on finger down
      onTapUp: (_) {
        _ctrl.reverse();                    // Restore on finger up
        widget.onPressed();                // Fire the callback
      },
      onTapCancel: () => _ctrl.reverse(), // Restore if tap is cancelled
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: AppColors.goldGradient,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
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
    );
  }
}

// ─── Dark Input Field ──────────────────────────────────────────────────────
// Purpose : A consistently styled text input for dark-themed forms.
// Function: Wraps Flutter's TextField with the app's dark color palette,
//           optional label, prefix icon, obscure text, and formatter support.
//           Highlights border in gold when focused.
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
        // Render label text above the input field if provided
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
                color: AppColors.whiteTertiary, fontSize: 14),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: AppColors.whiteTertiary, size: 18)
                : null,
            filled: true,
            fillColor: AppColors.inputFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            // Gold border appears when the field is focused
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppColors.gold, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Dark Dropdown ─────────────────────────────────────────────────────────
// Purpose : A generic dropdown selector that matches the app's dark theme.
// Function: Accepts any type T, renders a styled DropdownButton inside a
//           dark container, and calls onChanged when the user picks an option.
//           Supports an optional label rendered above the dropdown.
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
        // Render label text above the dropdown if provided
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
              icon: const Icon(Icons.keyboard_arrow_down,
                  color: AppColors.whiteTertiary),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Stat Card ─────────────────────────────────────────────────────────────
// Purpose : A summary metric card displayed on the Overview and Analytics screens.
// Function: Shows an emoji icon, a large value (number or currency), a label,
//           and an optional subtitle with a configurable color. Has a gold
//           top border accent for visual emphasis.
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
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(12)),
        // Gold top border acts as a visual accent line
        border: Border(top: BorderSide(color: AppColors.gold, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          // FittedBox scales down the value text if it overflows the card width
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppTextStyles.cardTitle),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: AppTextStyles.cardLabel,
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.ellipsis),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                style: TextStyle(fontSize: 11, color: subtitleColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

// ─── Order Status Badge ────────────────────────────────────────────────────
// Purpose : A colored pill badge showing the current status of an order.
// Function: Reads the color from OrderStatusExtension (single source of truth)
//           to avoid duplication. Renders a semi-transparent background with
//           a border and uppercase status text.
class OrderStatusBadge extends StatelessWidget {
  final OrderStatus status;

  const OrderStatusBadge({super.key, required this.status});

  // Delegates color resolution to the extension on OrderStatus
  // so there is only one place where status colors are defined
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
// Purpose : A small informational badge showing a product's category.
// Function: Renders the category label with a blue (info) color scheme
//           on a semi-transparent background with a matching border.
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
        border:
            Border.all(color: AppColors.info.withValues(alpha: 0.3)),
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
// Purpose : A badge that visually indicates whether a product's stock is low.
// Function: Shows "LOW STOCK" in warning yellow or "IN STOCK" in success green
//           based on the isLowStock flag passed from the product model.
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
// Purpose : A square 36x36 icon-only button styled for the dark theme.
// Function: Wraps an icon in a GestureDetector with a dark elevated background
//           and border. Used for quick actions (edit, delete, etc.) in list rows.
class DarkIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;

  const DarkIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color = AppColors.whiteTertiary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

// ─── Section Header ────────────────────────────────────────────────────────
// Purpose : A row header used to label sections within a screen.
// Function: Shows a title on the left and an optional pill badge (e.g., item count)
//           on the right. The title truncates with ellipsis if it overflows.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(title,
              style: AppTextStyles.sectionHeader,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          // Gold pill badge showing a count or status on the right side
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

// ── Reusable confirmation dialog helper ──────────────────────────────────────
// Purpose : Shows a modal AlertDialog asking the user to confirm or cancel an action.
// Function: Displays a title, message, and two buttons (cancel + confirm).
//           Returns true if the user confirmed, false or null if they cancelled.
//           Used before destructive or irreversible actions (delete, update, etc.).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel  = 'Cancel',
  Color? confirmColor,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(title,
          style: const TextStyle(
              color: AppColors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16)),
      content: Text(message,
          style: const TextStyle(
              color: AppColors.whiteSecondary, fontSize: 14)),
      actions: [
        // Cancel button — dismisses dialog and returns false
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelLabel,
              style: const TextStyle(color: AppColors.whiteTertiary)),
        ),
        // Confirm button — dismisses dialog and returns true
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel,
              style: TextStyle(
                  color: confirmColor ?? AppColors.gold,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return result == true;
}
