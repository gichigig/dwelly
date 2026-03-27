import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/data/kenya_locations.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/models/marketplace_product.dart';
import '../../../core/services/marketplace_service.dart';

class PostProductPage extends StatefulWidget {
  final MarketplaceProduct? editingProduct;

  const PostProductPage({super.key, this.editingProduct});

  @override
  State<PostProductPage> createState() => _PostProductPageState();
}

class _PostProductPageState extends State<PostProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _phoneController = TextEditingController();

  String _category = 'ELECTRONICS';
  String _condition = 'USED_GOOD';
  String? _county;
  String? _constituency;
  String? _ward;
  bool _showPhone = false;
  String _visibilityScope = 'PUBLIC';
  String? _targetCounty;
  bool _submitting = false;
  List<File> _images = [];

  static const List<String> _categories = [
    'ELECTRONICS',
    'PHONES',
    'FASHION',
    'HOME',
    'BEAUTY',
    'BABY',
    'SPORTS',
    'AUTO',
    'SERVICES',
    'OTHER',
  ];

  static const List<String> _conditions = [
    'NEW',
    'LIKE_NEW',
    'USED_GOOD',
    'USED_FAIR',
  ];

  bool get _isEditing => widget.editingProduct?.id != null;

  @override
  void initState() {
    super.initState();
    final product = widget.editingProduct;
    if (product == null) return;
    _titleController.text = product.title;
    _descriptionController.text = product.description;
    _priceController.text = product.price.toStringAsFixed(0);
    _phoneController.text = product.contactPhone ?? '';
    _category = product.category;
    _condition = product.condition;
    _county = product.county;
    _constituency = product.constituency;
    _ward = product.ward;
    _showPhone = product.showPhone;
    _visibilityScope = product.visibilityScope;
    _targetCounty = product.targetCounty;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 80);
    if (!mounted || files.isEmpty) return;
    final next = [..._images, ...files.map((x) => File(x.path))];
    if (next.length > 6) {
      _showSnack('You can upload up to 6 images');
      return;
    }
    setState(() => _images = next);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_county == null || _constituency == null || _ward == null) {
      _showSnack('Select county, constituency and ward');
      return;
    }
    if (_visibilityScope == 'COUNTY_ONLY' &&
        (_targetCounty == null || _targetCounty!.trim().isEmpty)) {
      _showSnack('Select target county for county-only visibility');
      return;
    }
    if (!_isEditing && _images.isEmpty) {
      _showSnack('Add at least one image');
      return;
    }

    setState(() => _submitting = true);
    try {
      final baseProduct = MarketplaceProduct(
        id: widget.editingProduct?.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        price: double.tryParse(_priceController.text.trim()) ?? 0,
        category: _category,
        condition: _condition,
        county: _county!,
        constituency: _constituency!,
        ward: _ward!,
        showPhone: _showPhone,
        contactPhone: _showPhone && _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
        visibilityScope: _visibilityScope,
        targetCounty: _visibilityScope == 'COUNTY_ONLY'
            ? (_targetCounty ?? _county)
            : null,
        imageUrls: widget.editingProduct?.imageUrls ?? const [],
      );
      if (_isEditing) {
        await MarketplaceService.updateProduct(
          productId: widget.editingProduct!.id!,
          product: baseProduct,
        );
      } else {
        await MarketplaceService.createProduct(
          product: baseProduct,
          images: _images,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showError(
        e,
        fallbackMessage: 'Failed to save product. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(Object error, {required String fallbackMessage}) {
    if (!mounted || isSilentError(error)) return;
    showErrorSnackBar(context, error, fallbackMessage: fallbackMessage);
  }

  @override
  Widget build(BuildContext context) {
    final constituencies = _county != null
        ? (KenyaLocations.constituenciesByCounty[_county] ?? const [])
        : const <String>[];
    final wards = _constituency != null
        ? (KenyaLocations.wardsByConstituency[_constituency] ?? const [])
        : const <String>[];

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Product' : 'Post Product')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => (v == null || v.trim().length < 5)
                    ? 'Enter at least 5 characters'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Description is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price (KES)'),
                validator: (v) {
                  final p = double.tryParse((v ?? '').trim());
                  if (p == null || p <= 0) return 'Enter a valid price';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('post-product-category-$_category'),
                initialValue: _category,
                isExpanded: true,
                items: _categories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('post-product-condition-$_condition'),
                initialValue: _condition,
                isExpanded: true,
                items: _conditions
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _condition = v ?? _condition),
                decoration: const InputDecoration(labelText: 'Condition'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('post-product-county-${_county ?? "none"}'),
                initialValue: _county,
                isExpanded: true,
                items: KenyaLocations.counties
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _county = v;
                    _constituency = null;
                    _ward = null;
                    if (_visibilityScope == 'COUNTY_ONLY') {
                      _targetCounty = v;
                    }
                  });
                },
                decoration: const InputDecoration(labelText: 'County'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'post-product-constituency-${_constituency ?? "none"}',
                ),
                initialValue: _constituency,
                isExpanded: true,
                items: constituencies
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _constituency = v;
                    _ward = null;
                  });
                },
                decoration: const InputDecoration(labelText: 'Constituency'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('post-product-ward-${_ward ?? "none"}'),
                initialValue: _ward,
                isExpanded: true,
                items: wards
                    .map(
                      (w) => DropdownMenuItem(
                        value: w,
                        child: Text(w, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _ward = v),
                decoration: const InputDecoration(labelText: 'Ward'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('post-product-visibility-$_visibilityScope'),
                initialValue: _visibilityScope,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 'PUBLIC',
                    child: Text('Visibility: Public'),
                  ),
                  DropdownMenuItem(
                    value: 'COUNTY_ONLY',
                    child: Text('Visibility: County only'),
                  ),
                ],
                onChanged: (v) {
                  setState(() {
                    _visibilityScope = v ?? 'PUBLIC';
                    if (_visibilityScope == 'COUNTY_ONLY') {
                      _targetCounty = _county;
                    } else {
                      _targetCounty = null;
                    }
                  });
                },
                decoration: const InputDecoration(labelText: 'Visibility'),
              ),
              if (_visibilityScope == 'COUNTY_ONLY') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'post-product-target-county-${_targetCounty ?? _county ?? "none"}',
                  ),
                  initialValue: _targetCounty ?? _county,
                  isExpanded: true,
                  items: KenyaLocations.counties
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _targetCounty = v),
                  decoration: const InputDecoration(labelText: 'Target county'),
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                value: _showPhone,
                contentPadding: EdgeInsets.zero,
                title: const Text('Show my phone to buyers'),
                onChanged: (v) => setState(() => _showPhone = v),
              ),
              if (_showPhone)
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Contact phone'),
                ),
              const SizedBox(height: 12),
              if (!_isEditing) ...[
                OutlinedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _images.isEmpty
                        ? 'Add images (1-6)'
                        : 'Add more images (${_images.length}/6)',
                  ),
                ),
                if (_images.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _images.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                _images[i],
                                width: 90,
                                height: 90,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: InkWell(
                                onTap: () =>
                                    setState(() => _images.removeAt(i)),
                                child: Container(
                                  color: Colors.black54,
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ] else ...[
                if (widget.editingProduct!.imageUrls.isNotEmpty) ...[
                  const Text(
                    'Current images',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 78,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.editingProduct!.imageUrls.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          widget.editingProduct!.imageUrls[i],
                          width: 78,
                          height: 78,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Image updates are done in Realadmin. Mobile edit updates details and status fields.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(
                  _submitting
                      ? (_isEditing ? 'Saving...' : 'Posting...')
                      : (_isEditing ? 'Save Changes' : 'Post Product'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
