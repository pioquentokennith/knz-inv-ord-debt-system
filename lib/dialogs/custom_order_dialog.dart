// ─────────────────────────────────────────────────────────────────────────────
// custom_order_dialog.dart — Add / Edit custom perfume agreement dialog
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/custom_order_model.dart';
import '../widgets/shared_widgets.dart';

class CustomOrderDialog extends StatefulWidget {
  final CustomOrder? existing; // null = add mode

  const CustomOrderDialog({super.key, this.existing});

  @override
  State<CustomOrderDialog> createState() => _CustomOrderDialogState();
}

class _CustomOrderDialogState extends State<CustomOrderDialog> {
  final _formKey       = GlobalKey<FormState>();
  final _nameCtrl      = TextEditingController();
  final _contactCtrl   = TextEditingController();
  final _specsCtrl     = TextEditingController();
  final _priceCtrl     = TextEditingController();
  final _depositCtrl   = TextEditingController(text: '0');
  final _termsCtrl     = TextEditingController();
  DateTime _deliveryDate = DateTime.now().add(const Duration(days: 7));
  bool _isSaving = false;

  final _dateFmt = DateFormat('MMM dd, yyyy');
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final e = widget.existing!;
      _nameCtrl.text    = e.customerName;
      _contactCtrl.text = e.contact ?? '';
      _specsCtrl.text   = e.fragranceSpecs;
      _priceCtrl.text   = e.agreedPrice.toStringAsFixed(2);
      _depositCtrl.text = e.depositPaid.toStringAsFixed(2);
      _termsCtrl.text   = e.terms ?? '';
      _deliveryDate     = e.deliveryDate;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _contactCtrl.dispose(); _specsCtrl.dispose();
    _priceCtrl.dispose(); _depositCtrl.dispose(); _termsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDeliveryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.gold),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _deliveryDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final state   = AppState();
    final price   = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    final deposit = double.tryParse(_depositCtrl.text.trim()) ?? 0;

    if (_isEdit) {
      final customerName = _nameCtrl.text.trim();
      final updated = widget.existing!.copyWith(
        customerName:   customerName,
        contact:        _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim(),
        fragranceSpecs: _specsCtrl.text.trim(),
        agreedPrice:    price,
        depositPaid:    deposit,
        deliveryDate:   _deliveryDate,
        terms:          _termsCtrl.text.trim().isEmpty ? null : _termsCtrl.text.trim(),
      );
      await state.updateCustomOrder(updated);
      if (mounted) {
        Navigator.of(context).pop();
        KnzToast.success(context, '✏️ Custom order for "$customerName" updated.');
      }
    } else {
      final customerName = _nameCtrl.text.trim();
      final order = CustomOrder(
        id:             const Uuid().v4(),
        customerName:   customerName,
        contact:        _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim(),
        fragranceSpecs: _specsCtrl.text.trim(),
        agreedPrice:    price,
        depositPaid:    deposit,
        deliveryDate:   _deliveryDate,
        terms:          _termsCtrl.text.trim().isEmpty ? null : _termsCtrl.text.trim(),
        userId:         state.activeUser,
        createdAt:      DateTime.now(),
      );
      await state.addCustomOrder(order);
      if (mounted) {
        Navigator.of(context).pop();
        KnzToast.success(context, '✅ Custom order for "$customerName" created.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                const Icon(Icons.draw_outlined, color: AppColors.gold, size: 20),
                const SizedBox(width: 8),
                Text(_isEdit ? 'Edit Agreement' : 'New Custom Order',
                    style: const TextStyle(color: AppColors.white,
                        fontSize: 17, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 20),

              // Customer name
              _field(_nameCtrl, 'Customer Name', 'Full name',
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              const SizedBox(height: 12),

              // Contact (optional)
              _field(_contactCtrl, 'Contact (optional)', 'Phone / address'),
              const SizedBox(height: 12),

              // Fragrance specs
              _field(_specsCtrl, 'Fragrance Specifications',
                  'Describe the custom scent (notes, intensity, bottle type…)',
                  maxLines: 3,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              const SizedBox(height: 12),

              // Price row
              Row(children: [
                Expanded(child: _field(_priceCtrl, 'Agreed Price (₱)', '0.00',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    if (n == null || n <= 0) return 'Enter price';
                    return null;
                  })),
                const SizedBox(width: 10),
                Expanded(child: _field(_depositCtrl, 'Deposit Paid (₱)', '0.00',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    if (n == null || n < 0) return 'Enter deposit';
                    return null;
                  })),
              ]),
              const SizedBox(height: 12),

              // Delivery date picker
              const Text('DELIVERY DATE',
                  style: TextStyle(color: AppColors.whiteTertiary,
                      fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickDeliveryDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined,
                        color: AppColors.gold, size: 16),
                    const SizedBox(width: 10),
                    Text(_dateFmt.format(_deliveryDate),
                        style: const TextStyle(color: AppColors.white, fontSize: 14)),
                    const Spacer(),
                    const Icon(Icons.edit_outlined,
                        color: AppColors.whiteTertiary, size: 14),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              // Terms (optional)
              _field(_termsCtrl, 'Terms & Conditions (optional)',
                  'e.g. No refund after production starts…', maxLines: 3),
              const SizedBox(height: 24),

              // Action buttons
              Row(children: [
                Expanded(child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel',
                      style: TextStyle(color: AppColors.whiteTertiary)),
                )),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Text(_isEdit ? 'Save Changes' : 'Create Agreement'),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.whiteTertiary,
          fontSize: 11, letterSpacing: 1.2)),
      const SizedBox(height: 4),
      TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        style: const TextStyle(color: AppColors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.whiteTertiary),
          filled: true,
          fillColor: AppColors.surfaceElevated,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.cardBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.cardBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.gold, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error)),
        ),
      ),
    ]);
  }
}
