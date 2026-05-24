// ─────────────────────────────────────────────────────────────────────────────
// product_dialog.dart
// Purpose : Dialog for adding a new product or editing an existing one.
// Function: In "add" mode, all fields start blank; in "edit" mode, fields are
//           pre-filled from the existing Product object. Supports picking a product
//           image from the camera or gallery, copying it to the app's permanent
//           documents directory (so it survives temp file clears), and storing the
//           local path in the product model. On save, validates the product name,
//           shows a confirmation dialog, then calls AppState.addProduct() or
//           AppState.updateProduct() accordingly.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/product_model.dart';
import '../widgets/shared_widgets.dart';

class ProductDialog extends StatefulWidget {
  final Product? existing;
  const ProductDialog({super.key, this.existing});

  @override
  State<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  final _nameCtrl     = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _priceCtrl    = TextEditingController(text: '0.00');
  final _stockCtrl    = TextEditingController(text: '0');
  final _minStockCtrl = TextEditingController(text: '5');

  ProductCategory _category = ProductCategory.eauDeParfum;
  String? _imagePath;
  // Tracks whether this dialog was opened for editing (true) or adding (false)
  bool _isEditing  = false;
  // Prevents double-submission while an async save is in progress
  bool _isSaving   = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.existing != null;
    if (_isEditing) {
      final p = widget.existing!;
      _nameCtrl.text     = p.name;
      _descCtrl.text     = p.description;
      _priceCtrl.text    = p.price.toStringAsFixed(2);
      _stockCtrl.text    = p.stockQty.toString();
      _minStockCtrl.text = p.minStockLevel.toString();
      _category          = p.category;
      _imagePath         = p.imagePath; // local path only
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _minStockCtrl.dispose();
    super.dispose();
  }

  // Opens a bottom sheet to choose between Camera and Gallery.
  // Copies the selected image to the app's permanent documents directory
  // so it persists across temp file clears. Stores the absolute path.
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: AppColors.gold),
            title: const Text('Take Photo',
                style: TextStyle(color: AppColors.white)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: AppColors.gold),
            title: const Text('Choose from Gallery',
                style: TextStyle(color: AppColors.white)),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );

    if (source == null) return;
    final xfile = await picker.pickImage(source: source, imageQuality: 80);
    if (xfile == null || !mounted) return;

    // I-copy sa permanent local storage ng app — hindi mawawala kahit
    // mag-clear ng temp files
    final appDir  = await getApplicationDocumentsDirectory();
    final imgDir  = Directory('${appDir.path}/product_images');
    if (!await imgDir.exists()) await imgDir.create(recursive: true);

    final fileName      = '${const Uuid().v4()}.jpg';
    final permanentPath = '${imgDir.path}/$fileName';
    await File(xfile.path).copy(permanentPath);

    if (mounted) {
      setState(() => _imagePath = permanentPath);
    }
  }

  // Validates product name, shows a confirmation dialog, then either
  // creates a new Product or updates the existing one via AppState.
  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      KnzToast.warning(context, 'Product name is required.');
      return;
    }

    final price    = double.tryParse(_priceCtrl.text)  ?? 0;
    final stock    = int.tryParse(_stockCtrl.text)      ?? 0;
    final minStock = int.tryParse(_minStockCtrl.text)   ?? 5;

    setState(() => _isSaving = true);

    // ── Confirmation prompt ───────────────────────────────────────────────
    final actionLabel = _isEditing ? 'Save Changes' : 'Add Product';
    final confirmed = await showConfirmDialog(
      context,
      title: _isEditing ? 'Save Changes?' : 'Add Product?',
      message: _isEditing
          ? 'Save changes to "$name"?'
          : 'Add "$name" to inventory?',
      confirmLabel: actionLabel,
      icon: _isEditing ? Icons.edit_rounded : Icons.add_box_rounded,
    );
    if (!confirmed || !mounted) {
      setState(() => _isSaving = false);
      return;
    }
    // ── END Confirmation ──────────────────────────────────────────────────

    try {
      if (_isEditing) {
        final updated = widget.existing!.copyWith(
          name:          name,
          description:   _descCtrl.text.trim(),
          category:      _category,
          price:         price,
          stockQty:      stock,
          minStockLevel: minStock,
          imagePath:     _imagePath,
        );
        await AppState().updateProduct(updated);
        if (mounted) {
          Navigator.pop(context);
          KnzToast.success(context, '✏️ "$name" updated successfully.');
        }
      } else {
        final product = Product(
          id:            const Uuid().v4(),
          name:          name,
          description:   _descCtrl.text.trim(),
          category:      _category,
          price:         price,
          stockQty:      stock,
          minStockLevel: minStock,
          imagePath:     _imagePath,
        );
        await AppState().addProduct(product);
        if (mounted) {
          Navigator.pop(context);
          KnzToast.success(context, '✅ "$name" added to inventory.');
        }
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Loads the product image from the local file system path.
  // Falls back to a placeholder icon if the file is missing or unreadable.
  Widget _buildImagePreview() {
    if (_imagePath != null) {
      final file = File(_imagePath!);
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _noImageWidget(),
      );
    }
    return _noImageWidget();
  }

  Widget _noImageWidget() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.add_photo_alternate_outlined,
          color: AppColors.gold.withValues(alpha: 0.6), size: 40),
      const SizedBox(height: 8),
      const Text('Tap to add product image',
          style: TextStyle(color: AppColors.whiteTertiary, fontSize: 13)),
      const Text('Camera or Gallery',
          style: TextStyle(color: AppColors.whiteTertiary, fontSize: 11)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final hasImage = _imagePath != null;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isEditing ? '✏️ Edit Product' : '✨ ${AppStrings.addNewProduct}',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),

            // ── Image picker ──────────────────────────────────────────────
            GestureDetector(
              onTap: _isSaving ? null : _pickImage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 140,
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasImage
                        ? AppColors.gold.withValues(alpha: 0.5)
                        : AppColors.cardBorder,
                    width: 1.5,
                  ),
                ),
                child: hasImage
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: _buildImagePreview(),
                          ),
                          // Remove button
                          Positioned(
                            top: 8, right: 8,
                            child: GestureDetector(
                              onTap: () => setState(() => _imagePath = null),
                              child: Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(
                                  color: AppColors.error,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      )
                    : _noImageWidget(),
              ),
            ),

            const SizedBox(height: 16),

            DarkTextField(
              label: AppStrings.productName,
              hint: 'e.g., Rose Oud Intense',
              controller: _nameCtrl,
            ),
            const SizedBox(height: 14),
            DarkDropdown<ProductCategory>(
              label: AppStrings.category,
              value: _category,
              items: ProductCategory.values
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c.displayName),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _category = v);
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DarkTextField(
                    label: AppStrings.price,
                    hint: '0.00',
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'))
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DarkTextField(
                    label: AppStrings.stockQty,
                    hint: '0',
                    controller: _stockCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DarkTextField(
                    label: AppStrings.minStockLevel,
                    hint: '5',
                    controller: _minStockCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DarkTextField(
              label: AppStrings.description,
              hint: 'Short description...',
              controller: _descCtrl,
              maxLines: 3,
            ),
            const SizedBox(height: 24),

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
                        AppStrings.cancel,
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
                    label: _isSaving
                        ? 'Saving...'
                        : _isEditing
                            ? 'Save Changes'
                            : AppStrings.addProduct,
                    onPressed: _isSaving ? () {} : _submit,
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
