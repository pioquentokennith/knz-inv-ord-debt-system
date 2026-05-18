// ─────────────────────────────────────────────────────────────────────────────
// order_dialog.dart
// Purpose : Dialog for creating a new order with one or more products.
// Function: Provides a product picker dropdown, price input, and quantity field
//           to build a cart. Enforces stock limits when adding items. The cart
//           list supports inline quantity steppers and item removal. On submit,
//           validates that the customer name and cart are not empty, shows a
//           confirmation dialog, generates an order ID, then saves the order
//           via AppState.addOrder(). Displays an error snackbar if saving fails.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../widgets/shared_widgets.dart';

class OrderDialog extends StatefulWidget {
  const OrderDialog({super.key});

  @override
  State<OrderDialog> createState() => _OrderDialogState();
}

class _OrderDialogState extends State<OrderDialog> {
  final _customerCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  OrderStatus _status = OrderStatus.pending;

  // Cart items holding each selected product with its quantity and custom price
  final List<_CartEntry> _cart = [];

  // For the "add item" row
  Product? _pickedProduct;
  final _pickedQtyCtrl = TextEditingController(text: '1');
  final _pickedPriceCtrl = TextEditingController();

  // Product search
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _showSearchResults = false;
  final _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _customerCtrl.dispose();
    _notesCtrl.dispose();
    _pickedQtyCtrl.dispose();
    _pickedPriceCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // Computed total: sum of (customPrice * qty) across all cart entries
  double get _cartTotal =>
      _cart.fold(0, (sum, e) => sum + e.customPrice * e.qty);

  // Validates and adds the currently selected product to the cart.
  // Merges with an existing cart entry if the same product is already in the cart.
  // Enforces stock availability before adding.
  void _addToCart() {
    final product = _pickedProduct;
    if (product == null) return;
    final qty = int.tryParse(_pickedQtyCtrl.text) ?? 1;
    if (qty <= 0) return;
    final price = double.tryParse(_pickedPriceCtrl.text.replaceAll(',', ''));
    if (price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid price')),
      );
      return;
    }

    // Check stock — get current qty already in cart for this product
    final existingIdx = _cart.indexWhere((e) => e.product.id == product.id);
    final alreadyInCart = existingIdx >= 0 ? _cart[existingIdx].qty : 0;
    final totalQty = alreadyInCart + qty;

    if (totalQty > product.stockQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text(
            'Not enough stock! Only ${product.stockQty - alreadyInCart} left available.',
            style: const TextStyle(color: AppColors.white),
          ),
        ),
      );
      return;
    }

    setState(() {
      if (existingIdx >= 0) {
        _cart[existingIdx] = _CartEntry(
            _cart[existingIdx].product, totalQty, _cart[existingIdx].customPrice);
      } else {
        _cart.add(_CartEntry(product, qty, price));
      }
      _pickedQtyCtrl.text = '1';
      _pickedPriceCtrl.clear();
    });
  }

  // Removes a cart entry by its index in the _cart list
  void _removeFromCart(int index) {
    setState(() => _cart.removeAt(index));
  }

  // Validates the form, shows a confirmation dialog, builds the Order object,
  // assigns a generated order ID, and saves it via AppState.addOrder().
  Future<void> _submit() async {
    final customer = _customerCtrl.text.trim();
    if (customer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer name is required')),
      );
      return;
    }
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one product')),
      );
      return;
    }

    final state = AppState();

    // ── Confirmation prompt ───────────────────────────────────────────────
    final currency2 = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Create Order?',
      message:
          'Create order for $customer with ${_cart.length} item(s) totaling ${currency2.format(_cartTotal)}?',
      confirmLabel: 'Create Order',
    );
    if (!confirmed || !mounted) return;
    // ── END Confirmation ──────────────────────────────────────────────────

    final items = _cart
        .map((e) => OrderItem(
              id: const Uuid().v4(),
              productId: e.product.id,
              productName: e.product.name,
              unitPrice: e.customPrice,
              quantity: e.qty,
            ))
        .toList();

    final orderId = await state.generateOrderId();
    final order = Order(
      id: const Uuid().v4(),
      orderId: orderId,
      customerName: customer,
      items: items,
      totalAmount: _cartTotal,
      status: _status,
      orderDate: DateTime.now(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    // FIX 3: Gamitin ang onError callback para malaman ng user kung failed ang order creation.
    // Dati walang error feedback — nag-pop agad ang dialog kahit failed.
    final success = await state.addOrder(order, onError: (msg) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });
    if (success && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final products = AppState().products;
    _pickedProduct ??= products.isNotEmpty ? products.first : null;
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            const Text(
              '📦 New Order',
              style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 20,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),

            // Customer name
            DarkTextField(
              label: 'CUSTOMER NAME',
              hint: 'Customer full name',
              controller: _customerCtrl,
            ),
            const SizedBox(height: 16),

            // ── Add Item Section ────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ADD PRODUCT TO ORDER',
                      style: AppTextStyles.labelSmall),
                  const SizedBox(height: 10),
                  // ── Product Search Bar ──────────────────────────────
                  Builder(builder: (context) {
                    final allProducts = AppState().products;
                    final filtered = _searchQuery.isEmpty
                        ? allProducts
                        : allProducts
                            .where((p) => p.name
                                .toLowerCase()
                                .contains(_searchQuery.toLowerCase()))
                            .toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search text field
                        TextField(
                          controller: _searchCtrl,
                          focusNode: _searchFocusNode,
                          style: const TextStyle(
                              color: AppColors.white, fontSize: 14),
                          onChanged: (v) => setState(() {
                            _searchQuery = v;
                            _showSearchResults = v.isNotEmpty || _searchFocusNode.hasFocus;
                          }),
                          onTap: () => setState(
                              () => _showSearchResults = true),
                          decoration: InputDecoration(
                            hintText: _pickedProduct != null
                                ? '${_pickedProduct!.name} (${_pickedProduct!.stockQty} left)'
                                : 'Search product...',
                            hintStyle: TextStyle(
                              color: _pickedProduct != null
                                  ? AppColors.white
                                  : AppColors.whiteTertiary,
                              fontSize: 13,
                            ),
                            prefixIcon: const Icon(Icons.search,
                                color: AppColors.whiteTertiary, size: 18),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? GestureDetector(
                                    onTap: () => setState(() {
                                      _searchCtrl.clear();
                                      _searchQuery = '';
                                      _showSearchResults = false;
                                      _searchFocusNode.unfocus();
                                    }),
                                    child: const Icon(Icons.close,
                                        color: AppColors.whiteTertiary,
                                        size: 16),
                                  )
                                : null,
                            filled: true,
                            fillColor: AppColors.surface,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: AppColors.cardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: AppColors.cardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppColors.gold),
                            ),
                          ),
                        ),
                        // Search Results Dropdown
                        if (_showSearchResults) ...[
                          const SizedBox(height: 4),
                          Container(
                            constraints:
                                const BoxConstraints(maxHeight: 200),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: AppColors.cardBorder),
                            ),
                            child: filtered.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text('No products found',
                                        style: TextStyle(
                                            color:
                                                AppColors.whiteTertiary,
                                            fontSize: 13)),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(
                                            color: AppColors.divider,
                                            height: 1),
                                    itemBuilder: (ctx, idx) {
                                      final p = filtered[idx];
                                      final isSelected =
                                          _pickedProduct?.id == p.id;
                                      return GestureDetector(
                                        onTap: () => setState(() {
                                          _pickedProduct = p;
                                          _searchCtrl.clear();
                                          _searchQuery = '';
                                          _showSearchResults = false;
                                          _searchFocusNode.unfocus();
                                        }),
                                        child: Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10),
                                          color: isSelected
                                              ? AppColors.gold
                                                  .withValues(alpha: 0.1)
                                              : Colors.transparent,
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${p.name} (${p.stockQty} left)',
                                                  style: TextStyle(
                                                    color: isSelected
                                                        ? AppColors.gold
                                                        : AppColors.white,
                                                    fontSize: 13,
                                                    fontWeight: isSelected
                                                        ? FontWeight.w600
                                                        : FontWeight
                                                            .normal,
                                                  ),
                                                ),
                                              ),
                                              if (isSelected)
                                                const Icon(Icons.check,
                                                    color: AppColors.gold,
                                                    size: 16),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ],
                    );
                  }),
                  const SizedBox(height: 10),
                  // Price field
                  TextField(
                    controller: _pickedPriceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    style: const TextStyle(color: AppColors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'PRICE (₱)',
                      labelStyle: const TextStyle(
                          color: AppColors.whiteTertiary, fontSize: 12),
                      hintText: 'Enter price...',
                      hintStyle: const TextStyle(
                          color: AppColors.whiteTertiary, fontSize: 13),
                      prefixText: '₱ ',
                      prefixStyle: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
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
                  const SizedBox(height: 10),
                  // Qty + Add button
                  Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _pickedQtyCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style: const TextStyle(
                              color: AppColors.white, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Qty',
                            labelStyle: const TextStyle(
                                color: AppColors.whiteTertiary,
                                fontSize: 12),
                            filled: true,
                            fillColor: AppColors.surface,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: AppColors.cardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: AppColors.cardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppColors.gold),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: _addToCart,
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color:
                                      AppColors.gold.withValues(alpha: 0.4)),
                            ),
                            alignment: Alignment.center,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add,
                                    color: AppColors.gold, size: 18),
                                SizedBox(width: 6),
                                Text('Add to Order',
                                    style: TextStyle(
                                        color: AppColors.gold,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Cart / Order Items ──────────────────────────────────
            if (_cart.isNotEmpty) ...[
              Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.shopping_cart_outlined,
                              color: AppColors.gold, size: 16),
                          const SizedBox(width: 6),
                          Text('${_cart.length} item${_cart.length > 1 ? 's' : ''}',
                              style: const TextStyle(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                    // Items
                    ..._cart.asMap().entries.map((entry) {
                      final i = entry.key;
                      final e = entry.value;
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(e.product.name,
                                          style: const TextStyle(
                                              color: AppColors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                      Text(
                                        '${currency.format(e.customPrice)} × ${e.qty} = ${currency.format(e.customPrice * e.qty)}',
                                        style: const TextStyle(
                                            color: AppColors.whiteTertiary,
                                            fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                // Qty stepper
                                Row(
                                  children: [
                                    _QtyButton(
                                      icon: Icons.remove,
                                      onTap: () {
                                        setState(() {
                                          if (e.qty > 1) {
                                            _cart[i] = _CartEntry(
                                                e.product, e.qty - 1, e.customPrice);
                                          } else {
                                            _cart.removeAt(i);
                                          }
                                        });
                                      },
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Text(e.qty.toString(),
                                          style: const TextStyle(
                                              color: AppColors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14)),
                                    ),
                                    _QtyButton(
                                      icon: Icons.add,
                                      onTap: () {
                                        if (e.qty >= e.product.stockQty) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              backgroundColor: AppColors.error,
                                              content: Text(
                                                'Max stock reached! Only ${e.product.stockQty} available.',
                                                style: const TextStyle(color: AppColors.white),
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        setState(() => _cart[i] =
                                            _CartEntry(e.product, e.qty + 1, e.customPrice));
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _removeFromCart(i),
                                  child: const Icon(Icons.close,
                                      color: AppColors.error, size: 18),
                                ),
                              ],
                            ),
                          ),
                          if (i < _cart.length - 1)
                            const Divider(
                                color: AppColors.divider, height: 1),
                        ],
                      );
                    }),
                    const Divider(color: AppColors.divider, height: 1),
                    // Total
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TOTAL',
                              style: TextStyle(
                                  color: AppColors.whiteTertiary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1)),
                          Text(currency.format(_cartTotal),
                              style: const TextStyle(
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Status dropdown
            DarkDropdown<OrderStatus>(
              label: 'STATUS',
              value: _status,
              items: OrderStatus.values
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.displayName),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _status = v);
              },
            ),
            const SizedBox(height: 14),

            // Notes
            DarkTextField(
              label: 'NOTES (OPTIONAL)',
              hint: 'Any special instructions...',
              controller: _notesCtrl,
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.4)),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GoldButton(
                    label: 'Create Order',
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Helper model for cart entries
class _CartEntry {
  final Product product;
  final int qty;
  final double customPrice;
  _CartEntry(this.product, this.qty, this.customPrice);
}

// Small +/- button
class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Icon(icon, color: AppColors.white, size: 14),
      ),
    );
  }
}