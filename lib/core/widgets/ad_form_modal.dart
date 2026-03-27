import 'package:flutter/material.dart';
import '../models/advertisement.dart';
import '../services/ad_service.dart';

/// Modal bottom sheet for displaying and submitting ad forms
class AdFormModal extends StatefulWidget {
  final Advertisement ad;
  final AdService adService;
  final VoidCallback? onSuccess;
  final VoidCallback? onCancel;

  const AdFormModal({
    super.key,
    required this.ad,
    required this.adService,
    this.onSuccess,
    this.onCancel,
  });

  /// Show the form modal
  static Future<void> show(
    BuildContext context, {
    required Advertisement ad,
    required AdService adService,
    VoidCallback? onSuccess,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AdFormModal(
        ad: ad,
        adService: adService,
        onSuccess: onSuccess,
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  @override
  State<AdFormModal> createState() => _AdFormModalState();
}

class _AdFormModalState extends State<AdFormModal> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _formData = {};
  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  AdFormSchema? get _schema => widget.ad.formSchema;

  @override
  void initState() {
    super.initState();
    // Initialize form data with empty values
    if (_schema != null) {
      for (final field in _schema!.fields) {
        if (field.type == 'checkbox') {
          _formData[field.id] = false;
        } else {
          _formData[field.id] = '';
        }
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() {
      _submitting = true;
      _error = null;
    });

    // Extract name, email, phone if present
    String? name;
    String? email;
    String? phone;
    
    for (final field in _schema?.fields ?? <AdFormField>[]) {
      if (field.type == 'email') {
        email = _formData[field.id] as String?;
      } else if (field.type == 'phone') {
        phone = _formData[field.id] as String?;
      } else if (field.label.toLowerCase().contains('name') && 
                 field.type == 'text' && name == null) {
        name = _formData[field.id] as String?;
      }
    }

    final success = await widget.adService.submitForm(
      widget.ad.id,
      _formData,
      name: name,
      email: email,
      phone: phone,
    );

    if (mounted) {
      setState(() => _submitting = false);
      
      if (success) {
        setState(() => _submitted = true);
        widget.onSuccess?.call();
      } else {
        setState(() => _error = 'Failed to submit. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: _submitted ? _buildSuccessView() : _buildFormView(bottomPadding),
    );
  }

  Widget _buildSuccessView() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            _schema?.successMessage ?? 'Thank you for your submission!',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormView(double bottomPadding) {
    if (_schema == null || _schema!.fields.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Form not available'),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _schema?.title ?? widget.ad.formTitle ?? 'Fill out this form',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.ad.advertiserName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        
        // Form
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 16 + bottomPadding,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._schema!.fields.map((field) => _buildField(field)),
                  
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  
                  const SizedBox(height: 8),
                  
                  ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _schema?.submitButtonText ?? 
                            widget.ad.formSubmitButtonText ?? 
                            'Submit',
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField(AdFormField field) {
    Widget fieldWidget;

    switch (field.type) {
      case 'text':
        fieldWidget = TextFormField(
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
            border: const OutlineInputBorder(),
          ),
          validator: field.required
              ? (value) => value?.isEmpty == true ? 'This field is required' : null
              : null,
          onSaved: (value) => _formData[field.id] = value ?? '',
        );
        break;

      case 'email':
        fieldWidget = TextFormField(
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder ?? 'email@example.com',
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (field.required && (value?.isEmpty ?? true)) {
              return 'This field is required';
            }
            if (value?.isNotEmpty == true && 
                !RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value!)) {
              return 'Enter a valid email';
            }
            return null;
          },
          onSaved: (value) => _formData[field.id] = value ?? '',
        );
        break;

      case 'phone':
        fieldWidget = TextFormField(
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder ?? '+254 700 000 000',
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.phone,
          validator: field.required
              ? (value) => value?.isEmpty == true ? 'This field is required' : null
              : null,
          onSaved: (value) => _formData[field.id] = value ?? '',
        );
        break;

      case 'textarea':
        fieldWidget = TextFormField(
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 4,
          validator: field.required
              ? (value) => value?.isEmpty == true ? 'This field is required' : null
              : null,
          onSaved: (value) => _formData[field.id] = value ?? '',
        );
        break;

      case 'dropdown':
        fieldWidget = DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: field.label,
            border: const OutlineInputBorder(),
          ),
          items: (field.options ?? []).map((opt) => DropdownMenuItem(
            value: opt,
            child: Text(opt),
          )).toList(),
          validator: field.required
              ? (value) => value == null ? 'Please select an option' : null
              : null,
          onChanged: (value) => _formData[field.id] = value ?? '',
          onSaved: (value) => _formData[field.id] = value ?? '',
        );
        break;

      case 'checkbox':
        fieldWidget = FormField<bool>(
          initialValue: _formData[field.id] as bool? ?? false,
          validator: field.required
              ? (value) => value != true ? 'This field is required' : null
              : null,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                value: state.value ?? false,
                onChanged: (value) {
                  state.didChange(value);
                  _formData[field.id] = value ?? false;
                },
                title: Text(field.label),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    state.errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        );
        break;

      default:
        fieldWidget = TextFormField(
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
            border: const OutlineInputBorder(),
          ),
          onSaved: (value) => _formData[field.id] = value ?? '',
        );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: fieldWidget,
    );
  }
}
