// ─────────────────────────────────────────────────────────────────────────────
// inventory_screen.dart
// Purpose : Tabular inventory management screen showing all products with stock
//           levels, category badges, and action buttons.
// Function: Local state (_searchCtrl, _filterCategory) controls filtering without
//           triggering AppState rebuilds. AppStateBuilder (FIX 6) scopes rebuilds
//           to the product list only so the header and search bar are unaffected.
//           Renders _ProductCard (mobile) or _ProductRowWide (desktop >= 600px)
//           per product. Supports editing product details, editing stock quantity,
//           and soft-deleting products with confirmation.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/app_state_builder.dart'; // ← FIX 6
import '../models/product_model.dart';
import '../widgets/shared_widgets.dart';
import '../dialogs/product_dialog.dart';
import '../dialogs/edit_stock_dialog.dart';
import '../dialogs/export_dialog.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchCtrl = TextEditingController();
  ProductCategory? _filterCategory;
  // FIX 6: No _state, no addListener, no _onStateChange — removed entirely.

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Filters the product list by search query and/or category selection.
  // Returns a new list — does not mutate the original.
  List<Product> _filtered(List<Product> products) {
    var list = products.toList();
    final q = _searchCtrl.text.toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.description.toLowerCase().contains(q))
          .toList();
    }
    if (_filterCategory != null) {
      list = list.where((p) => p.category == _filterCategory).toList();
    }
    return list;
  }

  // Shows a confirmation dialog then soft-deletes the product (Recycle Bin).
  void _deleteProduct(Product p) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Product',
      message: 'Remove "${p.name}" from inventory? It can be restored from the Recycle Bin.',
      confirmLabel: 'Delete',
      confirmColor: AppColors.error,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirm || !mounted) return;
    await AppState().deleteProduct(p.id);
    if (mounted) KnzToast.error(context, '🗑️ "${p.name}" moved to Recycle Bin.');
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
        children: [
          // ── Header and search bar — local UI, no AppState needed ──────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    color: AppColors.gold, size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Inventory',
                      style: TextStyle(
                          color: AppColors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis),
                ),
                GoldButton(
                  label: '+ Add',
                  width: 90,
                  height: 40,
                  fontSize: 13,
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const ProductDialog(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.download_outlined, color: AppColors.whiteTertiary, size: 22),
                  tooltip: 'Export Inventory',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () => showExportDialog(context, ExportType.inventory),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: AppColors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      hintStyle: const TextStyle(
                          color: AppColors.whiteTertiary, fontSize: 14),
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.whiteTertiary, size: 20),
                      filled: true,
                      fillColor: AppColors.inputFill,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
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
                        borderSide: const BorderSide(color: AppColors.gold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ProductCategory?>(
                        value: _filterCategory,
                        hint: const Text('All\nCategories',
                            style: TextStyle(
                                color: AppColors.whiteTertiary, fontSize: 12)),
                        dropdownColor: AppColors.surfaceElevated,
                        style: const TextStyle(
                            color: AppColors.white, fontSize: 13),
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: AppColors.whiteTertiary),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<ProductCategory?>(
                            value: null,
                            child: Text('All Categories'),
                          ),
                          ...ProductCategory.values.map(
                            (c) => DropdownMenuItem<ProductCategory?>(
                              value: c,
                              child: Text(c.displayName),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _filterCategory = v),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── FIX 6: Only the product list rebuilds on AppState changes ─
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppStateBuilder(
                builder: (context, state) {
                  final filtered = _filtered(state.products);
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(children: [
                                Icon(Icons.list, color: AppColors.gold, size: 18),
                                SizedBox(width: 8),
                                Text('Products',
                                    style: TextStyle(
                                        color: AppColors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16)),
                              ]),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${filtered.length} ITEMS',
                                  style: const TextStyle(
                                      color: AppColors.gold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(color: AppColors.divider, height: 1),
                        Expanded(
                          child: AnimationLimiter(
                            child: ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(color: AppColors.divider, height: 1),
                              itemBuilder: (ctx, i) {
                                final p = filtered[i];
                                final stockPct = p.minStockLevel > 0
                                    ? (p.stockQty / (p.minStockLevel * 3))
                                        .clamp(0.0, 1.0)
                                    : 1.0;
                                return AnimationConfiguration.staggeredList(
                                  position: i,
                                  duration: const Duration(milliseconds: 300),
                                  child: SlideAnimation(
                                    horizontalOffset: 30,
                                    child: KnzFadeIn(
                                      child: isWide
                                          ? _ProductRowWide(
                                              index: i + 1,
                                              product: p,
                                              stockPct: stockPct,
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
                                              onDelete: () => _deleteProduct(p),
                                            )
                                          : _ProductCard(
                                              product: p,
                                              stockPct: stockPct,
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
                                              onDelete: () => _deleteProduct(p),
                                            ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      ),
    );
  }
}

// Mobile card
class _ProductCard extends StatelessWidget {
  final Product product;
  final double stockPct;
  final VoidCallback onEdit;
  final VoidCallback onEditStock;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    required this.stockPct,
    required this.onEdit,
    required this.onEditStock,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: product.imagePath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.file(
                          File(product.imagePath!),
                          fit: BoxFit.cover,
                          cacheWidth: 200,   // PRIORITY 2: limit decoded texture size
                          cacheHeight: 200,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.water_drop_outlined,
                            color: AppColors.gold, size: 22),
                        ),
                      )
                    : const Icon(Icons.water_drop_outlined,
                        color: AppColors.gold, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        style: const TextStyle(
                            color: AppColors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(product.description,
                        style: const TextStyle(
                            color: AppColors.whiteTertiary, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StockBadge(isLowStock: product.isLowStock),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CategoryBadge(label: product.category.shortName),
              const Spacer(),
              const Text('Stock: ',
                  style: TextStyle(
                      color: AppColors.whiteTertiary, fontSize: 12)),
              Text(
                product.stockQty.toString(),
                style: TextStyle(
                    color: product.isLowStock
                        ? AppColors.warning
                        : AppColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: stockPct,
              backgroundColor: AppColors.inputFill,
              valueColor: AlwaysStoppedAnimation(
                product.isLowStock ? AppColors.warning : AppColors.success,
              ),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 2),
          Text('Min stock: ${product.minStockLevel}',
              style: const TextStyle(
                  color: AppColors.whiteTertiary, fontSize: 10)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onEditStock,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    alignment: Alignment.center,
                    child: const Text('Edit Stock',
                        style: TextStyle(color: AppColors.white, fontSize: 12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.gold.withValues(alpha: 0.3)),
                    ),
                    alignment: Alignment.center,
                    child: const Text('Edit',
                        style: TextStyle(color: AppColors.gold, fontSize: 12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DarkIconButton(
                icon: Icons.delete_outline,
                color: AppColors.error,
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Wide/desktop table row
class _ProductRowWide extends StatelessWidget {
  final int index;
  final Product product;
  final double stockPct;
  final VoidCallback onEdit;
  final VoidCallback onEditStock;
  final VoidCallback onDelete;

  const _ProductRowWide({
    required this.index,
    required this.product,
    required this.stockPct,
    required this.onEdit,
    required this.onEditStock,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(index.toString(),
                style: const TextStyle(
                    color: AppColors.whiteTertiary, fontSize: 12)),
          ),
          Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: product.imagePath != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.file(
                      File(product.imagePath!),
                      fit: BoxFit.cover,
                      cacheWidth: 200,   // PRIORITY 2: limit decoded texture size
                      cacheHeight: 200,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.water_drop_outlined,
                        color: AppColors.gold, size: 18),
                    ),
                  )
                : const Icon(Icons.water_drop_outlined,
                    color: AppColors.gold, size: 18),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    style: const TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                Text(product.description,
                    style: const TextStyle(
                        color: AppColors.whiteTertiary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CategoryBadge(label: product.category.shortName),
          const SizedBox(width: 8),
          SizedBox(
            width: 30,
            child: Text(
              product.stockQty.toString(),
              style: TextStyle(
                  color: product.isLowStock
                      ? AppColors.warning
                      : AppColors.success,
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: stockPct,
                    backgroundColor: AppColors.inputFill,
                    valueColor: AlwaysStoppedAnimation(
                      product.isLowStock
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 2),
                Text('Min: ${product.minStockLevel}',
                    style: const TextStyle(
                        color: AppColors.whiteTertiary, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StockBadge(isLowStock: product.isLowStock),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onEditStock,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: const Text('Edit Stock',
                  style: TextStyle(color: AppColors.white, fontSize: 11)),
            ),
          ),
          const SizedBox(width: 6),
          DarkIconButton(
            icon: Icons.delete_outline,
            color: AppColors.error,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}