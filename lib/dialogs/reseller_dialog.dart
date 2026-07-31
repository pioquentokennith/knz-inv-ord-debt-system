// ─────────────────────────────────────────────────────────────────────────────
// reseller_dialog.dart — Add / Edit reseller form dialog
// Purpose : Collects reseller name, contact, and fixed peso deduction per item.
//           Used by ResellersScreen for both adding a new reseller and editing
//           an existing one. Validates that deduction is non-negative.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/money.dart';
import '../models/reseller_model.dart';
import '../widgets/shared_widgets.dart';

class ResellerDialog extends StatefulWidget {
  final Reseller? existing; // null = add mode; non-null = edit mode

  const ResellerDialog({super.key, this.existing});

  @override
  State<ResellerDialog> createState() => _ResellerDialogState();
}

class _ResellerDialogState extends State<ResellerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();

  bool _isSaving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _nameCtrl.text = widget.existing!.name;
      _contactCtrl.text = widget.existing!.contact ?? '';
      _discountCtrl.text = widget.existing!.deductionPerItem.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    final state = AppState();
    final discount = Money.tryParse(_discountCtrl.text.trim());
    if (discount == null || discount.isNegative) {
      KnzToast.warning(context, 'Enter a valid non-negative deduction.');
      return;
    }
    final name = _nameCtrl.text.trim();
    final contact = _contactCtrl.text.trim();
    setState(() => _isSaving = true);

    try {
      if (_isEdit) {
        final updated = widget.existing!.copyWith(
          name: name,
          contact: contact.isEmpty ? null : contact,
          deductionPerItem: discount,
        );
        await state.updateReseller(updated);
        if (mounted) {
          Navigator.of(context).pop();
          KnzToast.success(context, '✏️ Reseller "$name" updated.');
        }
      } else {
        final reseller = Reseller(
          id: const Uuid().v4(),
          name: name,
          contact: contact.isEmpty ? null : contact,
          deductionPerItem: discount,
          userId: state.activeUser,
          createdAt: DateTime.now(),
        );
        await state.addReseller(reseller);
        if (mounted) {
          Navigator.of(context).pop();
          KnzToast.success(context, '✅ Reseller "$name" added.');
        }
      }
    } catch (_) {
      if (mounted) {
        KnzToast.error(
          context,
          'The reseller could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                children: [
                  const Icon(
                    Icons.people_outline,
                    color: AppColors.gold,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isEdit ? 'Edit Reseller' : 'Add Reseller',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Name ────────────────────────────────────────────────────
              _field(
                controller: _nameCtrl,
                label: 'Reseller Name',
                hint: 'e.g. Maria Santos',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),

              // ── Contact ─────────────────────────────────────────────────
              _field(
                controller: _contactCtrl,
                label: 'Contact (optional)',
                hint: 'Phone / address',
              ),
              const SizedBox(height: 12),

              // ── Discount Amount ──────────────────────────────────────────────
              _field(
                controller: _discountCtrl,
                label: 'Discount per Product (₱)',
                hint: 'e.g. 20',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                prefix: const Text(
                  '−₱',
                  style: TextStyle(color: AppColors.gold, fontSize: 16),
                ),
                validator: (v) {
                  final val = Money.tryParse(v ?? '');
                  if (val == null) return 'Enter a valid amount';
                  if (val.isNegative) return 'Cannot be negative';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // ── Actions ─────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.whiteTertiary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(_isEdit ? 'Save Changes' : 'Add Reseller'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    Widget? suffix,
    Widget? prefix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.whiteSecondary, fontSize: 12),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.whiteTertiary),
            prefixIcon: prefix != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: prefix,
                  )
                : null,
            prefixIconConstraints: const BoxConstraints(minWidth: 0),
            suffixIcon: suffix != null
                ? Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: suffix,
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(minWidth: 0),
            filled: true,
            fillColor: AppColors.surfaceElevated,
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
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }
}
