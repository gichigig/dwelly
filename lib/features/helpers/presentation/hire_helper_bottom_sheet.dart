import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/helpers_repository.dart';

class HireHelperBottomSheet extends ConsumerStatefulWidget {
  final Helper helper;

  const HireHelperBottomSheet({super.key, required this.helper});

  @override
  ConsumerState<HireHelperBottomSheet> createState() => _HireHelperBottomSheetState();
}

class _HireHelperBottomSheetState extends ConsumerState<HireHelperBottomSheet> {
  final _phoneController = TextEditingController();
  final _descController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(helpersRepositoryProvider).hireHelper(
        widget.helper.id,
        _phoneController.text.trim(),
        _descController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment initiated. Please check your phone for the M-Pesa prompt.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding + 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hire ${widget.helper.name}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your payment of KES ${widget.helper.helperPrice.toStringAsFixed(0)} will be held securely in escrow until you approve the job.',
                      style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Job Description',
                hintText: 'What do you need help with?',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Description is required';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'M-Pesa Phone Number',
                hintText: 'e.g. 254712345678',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_android),
              ),
              keyboardType: TextInputType.phone,
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Phone number is required';
                if (!val.startsWith('254') && !val.startsWith('07') && !val.startsWith('01')) {
                  return 'Enter a valid Kenyan number';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _isLoading ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        'Pay KES ${widget.helper.helperPrice.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
