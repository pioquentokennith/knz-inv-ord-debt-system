// ─────────────────────────────────────────────────────────────────────────────
// products_screen.dart  (UPDATED)
// Changes:
//   • Search bar     — real-time filter by product name or category
//   • Filter chips   — quick category filter (All + each ProductCategory)
//   • Clickable image → full-screen InteractiveViewer overlay (pinch-to-zoom)
//   • BoxFit.contain  — image no longer cropped inside the card
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/app_state_builder.dart';
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
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  // null = All categories
  ProductCategory? _selectedCategory;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── helpers ──────────────────────────────────────────────────────────────
  List<Product> _applyFilters(List<Product> products) {
    return products.where((p) {
      final q = _searchQuery.toLowerCase();
      final matchSearch = q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.category.displayName.toLowerCase().contains(q);
      final matchCategory =
          _selectedCategory == null || p.category == _selectedCategory;
      return matchSearch && matchCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ─────────────────────────────────────────────
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

            const SizedBox(height: 12),

            // ── Search bar ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(color: AppColors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search products…',
                  hintStyle: const TextStyle(
                      color: AppColors.whiteTertiary, fontSize: 13),
                  prefixIcon: const Icon(Icons.search,
                      color: AppColors.gold, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear,
                              color: AppColors.whiteTertiary, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.inputFill,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: AppColors.gold, width: 1),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── Filter chips ───────────────────────────────────────────
            SizedBox(
              height: 36,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                children: [
                  // "All" chip
                  _FilterChip(
                    label: 'All',
                    selected: _selectedCategory == null,
                    onTap: () => setState(() => _selectedCategory = null),
                  ),
                  const SizedBox(width: 8),
                  // One chip per category
                  ...ProductCategory.values.map((cat) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: cat.displayName,
                        selected: _selectedCategory == cat,
                        onTap: () =>
                            setState(() => _selectedCategory = cat),
                      ),
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Grid (scoped rebuild) ──────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AppStateBuilder(
                  builder: (context, state) {
                    final filtered = _applyFilters(state.products);

                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off,
                                color: AppColors.whiteTertiary, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty ||
                                      _selectedCategory != null
                                  ? 'No products match your filter.'
                                  : 'No products yet.\nTap "+ Add" to get started.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.whiteTertiary,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }

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
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final p = filtered[i];
                              final stockPct = p.minStockLevel > 0
                                  ? (p.stockQty /
                                          (p.minStockLevel * 3))
                                      .clamp(0.0, 1.0)
                                  : 1.0;
                              return AnimationConfiguration.staggeredGrid(
                                position: i,
                                duration:
                                    const Duration(milliseconds: 400),
                                columnCount: crossAxisCount,
                                child: ScaleAnimation(
                                  child: KnzFadeIn(
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
                                        final confirm = await showConfirmDialog(
                                          context,
                                          title: 'Delete Product',
                                          message: 'Remove "${p.name}" from inventory? It can be restored from the Recycle Bin.',
                                          confirmLabel: 'Delete',
                                          confirmColor: AppColors.error,
                                          icon: Icons.delete_outline_rounded,
                                        );
                                        if (!confirm || !context.mounted) return;
                                        await AppState().deleteProduct(p.id);
                                        if (context.mounted) KnzToast.error(context, '🗑️ "${p.name}" moved to Recycle Bin.');
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

// ─────────────────────────────────────────────────────────────────────────────
// _FilterChip — styled category filter button
// ─────────────────────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : AppColors.inputFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : AppColors.white,
            fontSize: 11,
            fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ProductCard — card with clickable image (full-screen overlay on tap)
// ─────────────────────────────────────────────────────────────────────────────
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

  // ── Full-screen image overlay ─────────────────────────────────────────
  void _openFullScreen(BuildContext context, String imagePath) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(anim), child: child),
      ),
      pageBuilder: (ctx, _, __) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // Pinch-to-zoom image
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              // Close button top-right
              Positioned(
                top: MediaQuery.of(ctx).padding.top + 8,
                right: 12,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.gold, width: 1),
                    ),
                    child: const Icon(Icons.close,
                        color: AppColors.white, size: 20),
                  ),
                ),
              ),
              // Product name at bottom
              Positioned(
                bottom: MediaQuery.of(ctx).padding.bottom + 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.product.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: child,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Image — tappable, BoxFit.contain (no crop) ──────────
            LayoutBuilder(
              builder: (context, constraints) {
                final imgHeight = constraints.maxWidth * 0.55;
                return GestureDetector(
                  // Only open full screen when there IS an image
                  onTap: p.imagePath != null
                      ? () => _openFullScreen(context, p.imagePath!)
                      : null,
                  child: SizedBox(
                    height: imgHeight,
                    child: ColoredBox(
                      color: AppColors.inputFill,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          p.imagePath != null
                              ? Image.file(
                                  File(p.imagePath!),
                                  fit: BoxFit.contain, // ← no more crop
                                  width: double.infinity,
                                  cacheWidth: 400,
                                  cacheHeight: 400,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.water_drop_outlined,
                                        color: AppColors.gold, size: 32),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.water_drop_outlined,
                                      color: AppColors.gold, size: 32),
                                ),
                          // Zoom hint badge (only when image exists)
                          if (p.imagePath != null)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.zoom_in,
                                    color: AppColors.white, size: 14),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // Separator
            Container(height: 1, color: AppColors.cardBorder),

            // ── Content ────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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

                    const Spacer(),

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
                                border: Border.all(
                                    color: AppColors.cardBorder),
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