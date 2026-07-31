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
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/money.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../models/payment_method_model.dart';
import '../models/reseller_model.dart';
import '../widgets/shared_widgets.dart';
import '../screens/main_shell.dart';

class OrderDialog extends StatefulWidget {
  const OrderDialog({super.key});

  @override
  State<OrderDialog> createState() => _OrderDialogState();
}

class _OrderDialogState extends State<OrderDialog> {
  final _customerCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  OrderStatus _status = OrderStatus.pending;

  // ── v6: Payment method ──────────────────────────────────────────────────
  PaymentMethod _paymentMethod = PaymentMethod.cashOnDelivery;
  final _paymentRefCtrl = TextEditingController();

  // ── v6: Reseller discount ───────────────────────────────────────────────
  Reseller? _selectedReseller; // null = no reseller discount

  // ── v7: Interest for Utang orders (optional) ────────────────────────────
  String _interestType = 'none'; // 'none' | 'daily' | 'monthly'
  final _interestCtrl = TextEditingController(text: '0');

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
    _paymentRefCtrl.dispose();
    _pickedQtyCtrl.dispose();
    _pickedPriceCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _interestCtrl.dispose();
    super.dispose();
  }

  // Computed total: sum of (customPrice * qty) across all cart entries
  Money get _cartTotal =>
      _cart.fold(Money.zero, (sum, e) => sum + e.customPrice * e.qty);

  // Discounted total when a reseller is selected (fixed ₱ deduction per item)
  Money get _discountedCartTotal {
    if (_selectedReseller == null) return _cartTotal;
    final deduction = _selectedReseller!.deductionPerItem;
    // Sum: (customPrice - deduction) × qty, clamped so price never goes below 0
    return _cart.fold(
      Money.zero,
      (sum, e) =>
          sum +
          (e.customPrice - deduction).max(Money.zero).min(e.customPrice) *
              e.qty,
    );
  }

  Money get _deductionPerItem =>
      _selectedReseller?.deductionPerItem ?? Money.zero;

  // Validates and adds the currently selected product to the cart.
  // Merges with an existing cart entry if the same product is already in the cart.
  // Enforces stock availability before adding.
  void _addToCart() {
    final product = _pickedProduct;
    if (product == null) return;
    final qty = int.tryParse(_pickedQtyCtrl.text) ?? 1;
    if (qty <= 0) return;

    final srp = product.price;
    final deduction =
        Money.tryParse(_pickedPriceCtrl.text.replaceAll(',', '')) ?? Money.zero;
    if (deduction < 0) {
      KnzToast.warning(context, 'Discount cannot be negative.');
      return;
    }
    if (deduction > srp) {
      KnzToast.error(
        context,
        'Discount (₱${deduction.toStringAsFixed(2)}) cannot exceed SRP (₱${srp.toStringAsFixed(2)})',
      );
      return;
    }
    final finalPrice = srp - deduction;

    final existingIdx = _cart.indexWhere((e) => e.product.id == product.id);
    final alreadyInCart = existingIdx >= 0 ? _cart[existingIdx].qty : 0;
    final totalQty = alreadyInCart + qty;

    if (totalQty > product.stockQty) {
      KnzToast.error(
        context,
        'Not enough stock! Only ${product.stockQty - alreadyInCart} left available.',
      );
      return;
    }

    setState(() {
      if (existingIdx >= 0) {
        _cart[existingIdx] = _CartEntry(
          _cart[existingIdx].product,
          totalQty,
          _cart[existingIdx].srp,
          _cart[existingIdx].customPrice,
        );
      } else {
        _cart.add(_CartEntry(product, qty, srp, finalPrice));
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
      KnzToast.warning(context, 'Customer name is required.');
      return;
    }
    if (_cart.isEmpty) {
      KnzToast.warning(context, 'Add at least one product to continue.');
      return;
    }

    final state = AppState();

    // ── Confirmation prompt ───────────────────────────────────────────────
    final displayTotal = _selectedReseller != null
        ? _discountedCartTotal
        : _cartTotal;
    final resellerNote = _selectedReseller != null
        ? ' (after −₱${_deductionPerItem.toStringAsFixed(0)}/item discount)'
        : '';
    final interestNote =
        _paymentMethod == PaymentMethod.utang &&
            _interestType != 'none' &&
            (Money.tryParse(_interestCtrl.text.trim()) ?? Money.zero).isPositive
        ? '\nInterest: ${_interestCtrl.text.trim()}% $_interestType'
        : '';
    final confirmed = await showConfirmDialog(
      context,
      title: 'Create Order?',
      message:
          'Create order for $customer with ${_cart.length} item(s) totaling ${displayTotal.format()}$resellerNote?$interestNote',
      confirmLabel: 'Create Order',
    );
    if (!confirmed || !mounted) return;
    // ── END Confirmation ──────────────────────────────────────────────────

    // For reseller orders: apply the fixed deduction to unitPrice so that
    //   item.unitPrice = srp - deductionPerItem (e.g. 220 - 50 = 170)  ← net selling price
    //   item.srpPrice  = srp (e.g. 220)                                 ← catalog price
    // This ensures itemDiscountAmount = (srpPrice - unitPrice) * qty is always correct.
    // The discount field is hidden for resellers so e.customPrice == e.srp (no manual discount).
    final resellerDeduction = _selectedReseller?.deductionPerItem ?? Money.zero;
    final items = _cart
        .map(
          (e) => OrderItem(
            id: const Uuid().v4(),
            productId: e.product.id,
            productName: e.product.name,
            unitPrice: resellerDeduction > 0
                ? (e.srp - resellerDeduction).max(Money.zero).min(e.srp)
                : e.customPrice, // non-reseller: use manually entered discounted price
            srpPrice: e.srp, // always original catalog price
            quantity: e.qty,
          ),
        )
        .toList();

    // The readable KNZ number is allocated by SQLite inside the create
    // transaction. This placeholder is never persisted.
    const orderId = 'PENDING';
    // If payment method is Utang, force status to utang so it auto-creates a debt record
    final effectiveStatus = _paymentMethod == PaymentMethod.utang
        ? OrderStatus.utang
        : _status;
    // Customer-pay total is authoritative; SRP remains separately available on
    // the order and line items for discount and receipt reference.
    final savedTotal = displayTotal;
    final savedDiscountedTotal = _selectedReseller != null
        ? _discountedCartTotal
        : null;
    final order = Order(
      id: const Uuid().v4(),
      orderId: orderId,
      customerName: customer,
      items: items,
      totalAmount: savedTotal,
      srpTotal: _cartTotal,
      status: effectiveStatus,
      orderDate: DateTime.now(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      // v6 fields
      paymentMethod: _paymentMethod,
      paymentReference: _paymentRefCtrl.text.trim().isEmpty
          ? null
          : _paymentRefCtrl.text.trim(),
      isReseller: _selectedReseller != null,
      deductionPerItem: _deductionPerItem,
      discountedTotal: savedDiscountedTotal,
    );

    final success = await state.addOrder(
      order,
      onError: (msg) {
        if (mounted) KnzToast.error(context, msg);
      },
      interestRateBasisPoints: _paymentMethod == PaymentMethod.utang
          ? (Money.tryParse(_interestCtrl.text.trim()) ?? Money.zero).centavos
          : 0,
      interestType: _paymentMethod == PaymentMethod.utang
          ? _interestType
          : 'none',
    );
    if (success && mounted) {
      Navigator.pop(context);
      KnzToast.success(context, '✅ Order created for $customer.');
      if (_paymentMethod == PaymentMethod.utang) {
        final shell = context.findAncestorStateOfType<MainShellState>();
        shell?.navigateTo(NavItem.utang);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = AppState().products;
    if (_pickedProduct == null && products.isNotEmpty) {
      _pickedProduct = products.first;
      // Deduction field starts empty — SRP is shown as a locked display
    }
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
                fontWeight: FontWeight.w700,
              ),
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
                  const Text(
                    'ADD PRODUCT TO ORDER',
                    style: AppTextStyles.labelSmall,
                  ),
                  const SizedBox(height: 10),
                  // ── Product Search Bar ──────────────────────────────
                  Builder(
                    builder: (context) {
                      final allProducts = AppState().products;
                      final filtered = _searchQuery.isEmpty
                          ? allProducts
                          : allProducts
                                .where(
                                  (p) => p.name.toLowerCase().contains(
                                    _searchQuery.toLowerCase(),
                                  ),
                                )
                                .toList();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Search text field
                          TextField(
                            controller: _searchCtrl,
                            focusNode: _searchFocusNode,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 14,
                            ),
                            onChanged: (v) => setState(() {
                              _searchQuery = v;
                              _showSearchResults =
                                  v.isNotEmpty || _searchFocusNode.hasFocus;
                            }),
                            onTap: () =>
                                setState(() => _showSearchResults = true),
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
                              prefixIcon: const Icon(
                                Icons.search,
                                color: AppColors.whiteTertiary,
                                size: 18,
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? GestureDetector(
                                      onTap: () => setState(() {
                                        _searchCtrl.clear();
                                        _searchQuery = '';
                                        _showSearchResults = false;
                                        _searchFocusNode.unfocus();
                                      }),
                                      child: const Icon(
                                        Icons.close,
                                        color: AppColors.whiteTertiary,
                                        size: 16,
                                      ),
                                    )
                                  : null,
                              filled: true,
                              fillColor: AppColors.surface,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.cardBorder,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.cardBorder,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.gold,
                                ),
                              ),
                            ),
                          ),
                          // Search Results Dropdown
                          if (_showSearchResults) ...[
                            const SizedBox(height: 4),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 200),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.cardBorder),
                              ),
                              child: filtered.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Text(
                                        'No products found',
                                        style: TextStyle(
                                          color: AppColors.whiteTertiary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: filtered.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(
                                            color: AppColors.divider,
                                            height: 1,
                                          ),
                                      itemBuilder: (ctx, idx) {
                                        final p = filtered[idx];
                                        final isSelected =
                                            _pickedProduct?.id == p.id;
                                        return GestureDetector(
                                          onTap: () => setState(() {
                                            _pickedProduct = p;
                                            // Clear deduction when switching products
                                            _pickedPriceCtrl.clear();
                                            _searchCtrl.clear();
                                            _searchQuery = '';
                                            _showSearchResults = false;
                                            _searchFocusNode.unfocus();
                                          }),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            color: isSelected
                                                ? AppColors.gold.withValues(
                                                    alpha: 0.1,
                                                  )
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
                                                          : FontWeight.normal,
                                                    ),
                                                  ),
                                                ),
                                                if (isSelected)
                                                  const Icon(
                                                    Icons.check,
                                                    color: AppColors.gold,
                                                    size: 16,
                                                  ),
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
                    },
                  ),
                  const SizedBox(height: 10),
                  // ── SRP (read-only) ────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'SRP',
                          style: TextStyle(
                            color: AppColors.whiteTertiary,
                            fontSize: 11,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _pickedProduct != null
                              ? '₱${_pickedProduct!.price.toStringAsFixed(2)}'
                              : '₱0.00',
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.lock_outline,
                          color: AppColors.whiteTertiary,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Fixed',
                          style: TextStyle(
                            color: AppColors.whiteTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── Discount deduction — hidden when a reseller is selected ──
                  // Resellers get a fixed peso deduction applied at cart level;
                  // showing a manual discount field at the same time causes
                  // confusion and potential double-discount data entry.
                  if (_selectedReseller == null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          '−',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _pickedPriceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'),
                              ),
                            ],
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 14,
                            ),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'DISCOUNT (OPTIONAL)',
                              labelStyle: const TextStyle(
                                color: AppColors.whiteTertiary,
                                fontSize: 12,
                              ),
                              hintText: '0',
                              hintStyle: const TextStyle(
                                color: AppColors.whiteTertiary,
                                fontSize: 13,
                              ),
                              prefixText: '₱ ',
                              prefixStyle: const TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                              filled: true,
                              fillColor: AppColors.surface,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.cardBorder,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.cardBorder,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.gold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Live final price preview
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Builder(
                              builder: (_) {
                                final srp = _pickedProduct?.price ?? Money.zero;
                                final deduct =
                                    Money.tryParse(_pickedPriceCtrl.text) ??
                                    Money.zero;
                                final sell = (srp - deduct)
                                    .max(Money.zero)
                                    .min(srp);
                                final hasDeduct =
                                    deduct > 0 && _pickedProduct != null;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (hasDeduct) ...[
                                      Text(
                                        '₱${srp.toStringAsFixed(2)} − ₱${deduct.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: AppColors.whiteTertiary,
                                          fontSize: 10,
                                        ),
                                      ),
                                      const Text(
                                        '=',
                                        style: TextStyle(
                                          color: AppColors.whiteTertiary,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                    const Text(
                                      'SELLING PRICE',
                                      style: TextStyle(
                                        color: AppColors.whiteTertiary,
                                        fontSize: 10,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    Text(
                                      _pickedProduct == null
                                          ? '₱0.00'
                                          : '₱${sell.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: hasDeduct
                                            ? AppColors.success
                                            : AppColors.gold,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ), // end of discount Row
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
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Qty',
                            labelStyle: const TextStyle(
                              color: AppColors.whiteTertiary,
                              fontSize: 12,
                            ),
                            filled: true,
                            fillColor: AppColors.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: AppColors.cardBorder,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: AppColors.cardBorder,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: AppColors.gold,
                              ),
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
                                color: AppColors.gold.withValues(alpha: 0.4),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add,
                                  color: AppColors.gold,
                                  size: 18,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Add to Order',
                                  style: TextStyle(
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
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
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.shopping_cart_outlined,
                            color: AppColors.gold,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_cart.length} item${_cart.length > 1 ? 's' : ''}',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
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
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.product.name,
                                        style: const TextStyle(
                                          color: AppColors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (e.srp != e.customPrice) ...[
                                        // Show SRP and deduction when discounted
                                        Row(
                                          children: [
                                            Text(
                                              'SRP ${e.srp.format()}',
                                              style: const TextStyle(
                                                color: AppColors.whiteTertiary,
                                                fontSize: 10,
                                                decoration:
                                                    TextDecoration.lineThrough,
                                              ),
                                            ),
                                            const Text(
                                              ' − ',
                                              style: TextStyle(
                                                color: AppColors.error,
                                                fontSize: 10,
                                              ),
                                            ),
                                            Text(
                                              (e.srp - e.customPrice).format(),
                                              style: const TextStyle(
                                                color: AppColors.error,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      Text(
                                        '${e.customPrice.format()} × ${e.qty} = ${(e.customPrice * e.qty).format()}',
                                        style: const TextStyle(
                                          color: AppColors.whiteTertiary,
                                          fontSize: 11,
                                        ),
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
                                              e.product,
                                              e.qty - 1,
                                              e.srp,
                                              e.customPrice,
                                            );
                                          } else {
                                            _cart.removeAt(i);
                                          }
                                        });
                                      },
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Text(
                                        e.qty.toString(),
                                        style: const TextStyle(
                                          color: AppColors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    _QtyButton(
                                      icon: Icons.add,
                                      onTap: () {
                                        if (e.qty >= e.product.stockQty) {
                                          KnzToast.warning(
                                            context,
                                            'Max stock reached! Only ${e.product.stockQty} available.',
                                          );
                                          return;
                                        }
                                        setState(
                                          () => _cart[i] = _CartEntry(
                                            e.product,
                                            e.qty + 1,
                                            e.srp,
                                            e.customPrice,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _removeFromCart(i),
                                  child: const Icon(
                                    Icons.close,
                                    color: AppColors.error,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (i < _cart.length - 1)
                            const Divider(color: AppColors.divider, height: 1),
                        ],
                      );
                    }),
                    const Divider(color: AppColors.divider, height: 1),
                    // Total
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TOTAL',
                            style: TextStyle(
                              color: AppColors.whiteTertiary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            _cartTotal.format(),
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
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
              items: const [OrderStatus.pending]
                  .map(
                    (s) =>
                        DropdownMenuItem(value: s, child: Text(s.displayName)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _status = v);
              },
            ),
            const SizedBox(height: 14),

            // ── v6: Reseller discount ──────────────────────────────────────
            ListenableBuilder(
              listenable: AppState(),
              builder: (context, _) {
                final resellers = AppState().resellers;
                if (resellers.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RESELLER DISCOUNT',
                      style: TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Reseller?>(
                          isExpanded: true,
                          value: _selectedReseller,
                          dropdownColor: AppColors.surfaceElevated,
                          style: const TextStyle(color: AppColors.white),
                          hint: const Text(
                            'No discount (regular order)',
                            style: TextStyle(color: AppColors.whiteTertiary),
                          ),
                          items: [
                            const DropdownMenuItem<Reseller?>(
                              value: null,
                              child: Text(
                                'No discount (regular order)',
                                style: TextStyle(
                                  color: AppColors.whiteSecondary,
                                ),
                              ),
                            ),
                            ...resellers.map(
                              (r) => DropdownMenuItem<Reseller?>(
                                value: r,
                                child: Text(
                                  r.label,
                                  style: const TextStyle(color: AppColors.gold),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (r) => setState(() {
                            _selectedReseller = r;
                            // Clear any manual discount when a reseller is
                            // selected — the field is now hidden and its
                            // value would otherwise silently affect pricing.
                            _pickedPriceCtrl.clear();
                          }),
                        ),
                      ),
                    ),
                    if (_selectedReseller != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'SRP:  ${_cartTotal.format()}',
                              style: const TextStyle(
                                color: AppColors.whiteSecondary,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'NET: ${_discountedCartTotal.format()}',
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                  ],
                );
              },
            ),

            // ── v6: Payment method ─────────────────────────────────────────
            const Text(
              'PAYMENT METHOD',
              style: TextStyle(
                color: AppColors.whiteTertiary,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<PaymentMethod>(
                  isExpanded: true,
                  value: _paymentMethod,
                  dropdownColor: AppColors.surfaceElevated,
                  style: const TextStyle(color: AppColors.white),
                  items: PaymentMethod.values
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Row(
                            children: [
                              Icon(m.icon, color: AppColors.gold, size: 18),
                              const SizedBox(width: 8),
                              Text(m.displayName),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _paymentMethod = v;
                        if (!v.requiresReference) {
                          _paymentRefCtrl.clear();
                        }
                        if (v != PaymentMethod.utang) {
                          _interestType = 'none';
                          _interestCtrl.text = '0';
                        }
                      });
                    }
                  },
                ),
              ),
            ),
            if (_paymentMethod.requiresReference) ...[
              const SizedBox(height: 10),
              DarkTextField(
                label: 'REFERENCE NUMBER',
                hint: _paymentMethod.referenceHint,
                controller: _paymentRefCtrl,
              ),
            ],

            // ── v7: Interest section — only visible for Utang orders ─────
            if (_paymentMethod == PaymentMethod.utang) ...[
              const SizedBox(height: 14),
              const Divider(color: AppColors.cardBorder),
              const SizedBox(height: 10),
              const Text(
                'INTEREST (OPTIONAL)',
                style: TextStyle(
                  color: AppColors.whiteTertiary,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final type in ['none', 'daily', 'monthly'])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _interestType = type),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _interestType == type
                                ? AppColors.warning.withValues(alpha: 0.15)
                                : AppColors.inputFill,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _interestType == type
                                  ? AppColors.warning
                                  : AppColors.cardBorder,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            type == 'none'
                                ? 'None'
                                : type[0].toUpperCase() + type.substring(1),
                            style: TextStyle(
                              color: _interestType == type
                                  ? AppColors.warning
                                  : AppColors.whiteTertiary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (_interestType != 'none') ...[
                const SizedBox(height: 12),
                const Text(
                  'RATE (%)',
                  style: TextStyle(
                    color: AppColors.whiteTertiary,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _interestCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    hintText: '2.0',
                    hintStyle: const TextStyle(color: AppColors.whiteTertiary),
                    suffixText: '%  $_interestType',
                    suffixStyle: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: AppColors.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: AppColors.warning,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _interestType == 'daily'
                      ? 'Accrued = balance × rate% × days unpaid'
                      : 'Accrued = balance × rate% × (days/30)',
                  style: const TextStyle(
                    color: AppColors.whiteTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
              const SizedBox(height: 4),
            ],

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
                          color: AppColors.error.withValues(alpha: 0.4),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GoldButton(label: 'Create Order', onPressed: _submit),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Helper model for cart entries — stores both the original SRP and the actual selling price
class _CartEntry {
  final Product product;
  final int qty;
  final Money srp; // Original catalog price (locked, never changes)
  final Money customPrice; // Actual selling price (srp - deduction)
  _CartEntry(this.product, this.qty, this.srp, this.customPrice);
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
