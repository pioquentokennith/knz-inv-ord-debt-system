// ─────────────────────────────────────────────────────────────────────────────
// products_screen.dart
// Purpose : Product catalogue grid showing all products as visual cards.
// Function: Uses AppStateBuilder (FIX 6) to scope rebuilds to the grid only.
//           Renders a 2-column grid (or 1 column if screen width < 400px) of
//           _ProductCard widgets. Each card shows the product image, name, category,
//           price, stock badge, stock progress bar, and action buttons (Edit Stock,
//           Edit, Delete). Cards have a hover elevation animation via MouseRegion
//           for desktop users.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/app_state_builder.dart'; // ← FIX 6
import '../models/product_model.dart';
import '../widgets/shared_widgets.dart';
import '../dialogs/product_dialog.dart';
import '../dialogs/edit_stock_dialog.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  // FIX 6: No _state, no addListener, no _onStateChange — removed entirely.

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppColors.gold, size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Product Catalogue',
                      style: TextStyle(
                          color: AppColors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  GoldButton(
                    label: '+ Add',
                    width: 100,
                    height: 40,
                    fontSize: 13,
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const ProductDialog(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── FIX 6: Only the grid rebuilds on AppState changes ──────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AppStateBuilder(
                  builder: (context, state) {
                    final products = state.products;
                    return AnimationLimiter(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount =
                              constraints.maxWidth < 400 ? 1 : 2;
                          return GridView.builder(
                            padding: const EdgeInsets.only(bottom: 16),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              mainAxisExtent: 380,
                            ),
                            itemCount: products.length,
                            itemBuilder: (ctx, i) {
                              final p = products[i];
                              final stockPct = p.minStockLevel > 0
                                  ? (p.stockQty / (p.minStockLevel * 3))
                                      .clamp(0.0, 1.0)
                                  : 1.0;
                              return AnimationConfiguration.staggeredGrid(
                                position: i,
                                duration: const Duration(milliseconds: 400),
                                columnCount: crossAxisCount,
                                child: ScaleAnimation(
                                  child: FadeInAnimation(
                                    child: _ProductCard(
                                      product: p,
                                      stockPct: stockPct,
                                      currency: currency,
                                      onEdit: () => showDialog(
                                        context: context,
                                        builder: (_) =>
                                            ProductDialog(existing: p),
                                      ),
                                      onEditStock: () => showDialog(
                                        context: context,
                                        builder: (_) =>
                                            EditStockDialog(product: p),
                                      ),
                                      onDelete: () async {
                                        await AppState().deleteProduct(p.id);
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// Product catalogue card with a hover elevation effect for desktop users.
// Displays the product image, name, category, price, stock badge, progress bar,
// and action buttons (Edit Stock, Edit, Delete).
class _ProductCard extends StatefulWidget {
  final Product product;
  final double stockPct;
  final NumberFormat currency;
  final VoidCallback onEdit;
  final VoidCallback onEditStock;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    required this.stockPct,
    required this.currency,
    required this.onEdit,
    required this.onEditStock,
    required this.onDelete,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverCtrl;
  late Animation<double> _elevation;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _elevation = Tween<double>(begin: 0, end: 8).animate(
      CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _hoverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;

    return MouseRegion(
      onEnter: (_) => _hoverCtrl.forward(),
      onExit: (_) => _hoverCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _elevation,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: p.isLowStock
                  ? AppColors.warning.withValues(alpha: 0.4)
                  : AppColors.cardBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold
                    .withValues(alpha: 0.05 * _elevation.value / 8),
                blurRadius: _elevation.value * 2,
                spreadRadius: _elevation.value * 0.5,
              ),
            ],
          ),
          // FIX 5: ClipRRect — pigilan ang image/content na lumabas sa border radius
          // Ito ang nagiging dahilan ng black+yellow stripe
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: child,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Image — responsive height based on screen width ──────
            LayoutBuilder(
              builder: (context, constraints) {
                final imgHeight = constraints.maxWidth * 0.55;
                return SizedBox(
                  height: imgHeight,
                  child: ColoredBox(
                    color: AppColors.inputFill,
                    child: p.imagePath != null
                        ? Image.file(
                            File(p.imagePath!),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.water_drop_outlined,
                                  color: AppColors.gold, size: 32),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.water_drop_outlined,
                                color: AppColors.gold, size: 32),
                          ),
                  ),
                );
              },
            ),

            // Separator — 1px lang, hindi "stripe"
            Container(height: 1, color: AppColors.cardBorder),

            // ── Content (Expanded — punan ang natirang espasyo) ────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.category.displayName,
                      style: const TextStyle(
                          color: AppColors.whiteTertiary, fontSize: 10),
                    ),

                    const SizedBox(height: 8),

                    // Price + Badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.currency.format(p.price),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 4),
                        StockBadge(isLowStock: p.isLowStock),
                      ],
                    ),

                    // Spacer — itutulak ang stock + buttons sa baba
                    const Spacer(),

                    // Stock count
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Stock:',
                            style: TextStyle(
                                color: AppColors.whiteTertiary,
                                fontSize: 10)),
                        Text(
                          p.stockQty.toString(),
                          style: TextStyle(
                            color: p.isLowStock
                                ? AppColors.warning
                                : AppColors.success,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: widget.stockPct,
                        backgroundColor: AppColors.inputFill,
                        valueColor: AlwaysStoppedAnimation(p.isLowStock
                            ? AppColors.warning
                            : AppColors.success),
                        minHeight: 4,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: widget.onEditStock,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(6),
                                border:
                                    Border.all(color: AppColors.cardBorder),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'Edit Stock',
                                style: TextStyle(
                                    color: AppColors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        DarkIconButton(
                          icon: Icons.edit_outlined,
                          color: AppColors.gold,
                          onPressed: widget.onEdit,
                        ),
                        const SizedBox(width: 4),
                        DarkIconButton(
                          icon: Icons.delete_outline,
                          color: AppColors.error,
                          onPressed: widget.onDelete,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
