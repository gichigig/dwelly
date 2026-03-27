import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/id_scanner_service.dart';

/// Page for searching for a lost ID
class SearchLostIdPage extends StatefulWidget {
  const SearchLostIdPage({super.key});

  @override
  State<SearchLostIdPage> createState() => _SearchLostIdPageState();
}

class _SearchLostIdPageState extends State<SearchLostIdPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _idNumberController = TextEditingController();
  
  bool _isSearching = false;
  SearchLostIdResponse? _searchResult;
  String? _errorMessage;
  
  @override
  void dispose() {
    _nameController.dispose();
    _idNumberController.dispose();
    super.dispose();
  }
  
  Future<void> _searchLostId() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isSearching = true;
      _searchResult = null;
      _errorMessage = null;
    });
    
    try {
      final response = await IdScannerService.searchLostId(
        fullName: _nameController.text.trim(),
        idNumber: _idNumberController.text.trim(),
      );
      
      setState(() {
        _isSearching = false;
        _searchResult = response;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _errorMessage = 'Search failed: $e';
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find My Lost ID'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Instructions
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.search, color: Colors.orange.shade700, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        'Lost your ID?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.orange.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Enter your details below to check if someone has found and registered your ID.',
                        style: TextStyle(color: Colors.orange.shade600, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Full Name input
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Full Name (as on ID)',
                  hintText: 'e.g., JOHN DOE MWANGI',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your full name';
                  }
                  if (value.trim().split(' ').length < 2) {
                    return 'Enter at least first and last name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // ID Number input
              TextFormField(
                controller: _idNumberController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: InputDecoration(
                  labelText: 'ID Number',
                  hintText: 'e.g., 12345678',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your ID number';
                  }
                  if (value.trim().length < 7) {
                    return 'ID number must be 7-8 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              
              // Search button
              FilledButton.icon(
                onPressed: _isSearching ? null : _searchLostId,
                icon: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_isSearching ? 'Searching...' : 'Search'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              
              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              // Search result
              if (_searchResult != null) ...[
                const SizedBox(height: 24),
                _buildSearchResult(_searchResult!),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildSearchResult(SearchLostIdResponse result) {
    if (result.found) {
      return Card(
        color: Colors.green.shade50,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.celebration, color: Colors.green, size: 48),
              const SizedBox(height: 12),
              Text(
                'Great News!',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                result.message,
                style: TextStyle(color: Colors.green.shade600),
                textAlign: TextAlign.center,
              ),
              const Divider(height: 32),
              
              // Finder's contact
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Contact the finder:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.phone, color: Colors.green),
                        const SizedBox(width: 8),
                        SelectableText(
                          result.finderPhone ?? 'N/A',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (result.finderWhatsApp != null && result.finderWhatsApp!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat, color: Colors.green.shade600),
                          const SizedBox(width: 8),
                          SelectableText(
                            'WhatsApp: ${result.finderWhatsApp}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (result.collectionPlace != null && result.collectionPlace!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.place, color: Colors.blue.shade700, size: 20),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Collect from: ${result.collectionPlace}',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (result.foundLocation != null && result.foundLocation!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_on, color: Colors.grey.shade600, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            'Found at: ${result.foundLocation}',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ],
                    if (result.foundAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Registered on: ${_formatDate(result.foundAt!)}',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              Text(
                'Note: This record will be automatically removed after 7 days.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    } else {
      return Card(
        color: Colors.grey.shade100,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.search_off, color: Colors.grey.shade400, size: 48),
              const SizedBox(height: 12),
              Text(
                'Not Found',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                result.message,
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Check back later - someone may find and register your ID.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
  }
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
