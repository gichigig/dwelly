import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';

class HouseSearchHelpPage extends StatefulWidget {
  final VoidCallback? onNavigateToInbox;

  const HouseSearchHelpPage({super.key, this.onNavigateToInbox});

  static const pendingRequestKey = 'house_search_helper_request_pending_v1';

  @override
  State<HouseSearchHelpPage> createState() => _HouseSearchHelpPageState();
}

class _HouseSearchHelpPageState extends State<HouseSearchHelpPage> {
  final _formKey = GlobalKey<FormState>();
  final _locationController = TextEditingController();
  final _budgetController = TextEditingController();
  final _notesController = TextEditingController();
  String _homeType = 'Bedsitter';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _locationController.dispose();
    _budgetController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(HouseSearchHelpPage.pendingRequestKey, true);
    await prefs.setString(
      'house_search_helper_request_summary_v1',
      '$_homeType around ${_locationController.text.trim()}',
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Request saved. A helper conversation will appear in Inbox.',
        ),
      ),
    );
    widget.onNavigateToInbox?.call();
    Navigator.of(context).maybePop();
  }

  void _openInbox() {
    widget.onNavigateToInbox?.call();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Hire a house search helper')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.support_agent, color: colorScheme.primary),
                      const SizedBox(height: 10),
                      Text(
                        'Tell us what you need. Your helper will continue the search with you in Inbox.',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _homeType,
                  decoration: const InputDecoration(labelText: 'Home type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'Bedsitter',
                      child: Text('Bedsitter'),
                    ),
                    DropdownMenuItem(
                      value: 'Single room',
                      child: Text('Single room'),
                    ),
                    DropdownMenuItem(value: 'Studio', child: Text('Studio')),
                    DropdownMenuItem(
                      value: 'Apartment',
                      child: Text('Apartment'),
                    ),
                    DropdownMenuItem(value: 'House', child: Text('House')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _homeType = value);
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: 'Preferred area',
                    hintText: 'Kilimani, South B, Juja...',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter the area you want help searching.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _budgetController,
                  decoration: const InputDecoration(
                    labelText: 'Monthly budget',
                    hintText: 'KES 15,000',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter your budget.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Move-in date, must-haves, commute, security...',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: DwellyOrbitingLoader(),
                          )
                        : const Icon(Icons.send),
                    label: Text(_isSubmitting ? 'Sending' : 'Send request'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openInbox,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Open Inbox'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
