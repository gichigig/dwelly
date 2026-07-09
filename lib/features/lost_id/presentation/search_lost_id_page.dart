import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/id_scanner_service.dart';
import '../../../core/services/google_ad_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/widgets/auth_bottom_sheets.dart';

/// Page for searching for a lost ID
class SearchLostIdPage extends StatefulWidget {
  final String? initialIdType;

  const SearchLostIdPage({super.key, this.initialIdType});

  @override
  State<SearchLostIdPage> createState() => _SearchLostIdPageState();
}

class _SearchLostIdPageState extends State<SearchLostIdPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _schoolController = TextEditingController();

  static const String _nationalIdType = 'NATIONAL_ID';
  static const String _schoolIdType = 'SCHOOL_ID';
  final List<String> _idTypes = [_nationalIdType, _schoolIdType];
  String _selectedIdType = _nationalIdType;
  
  bool _isSearching = false;
  SearchLostIdResponse? _searchResult;
  String? _errorMessage;
  bool _agreedToPolicy = false;
  
  @override
  void initState() {
    super.initState();
    _applyInitialIdType();
  }

  void _applyInitialIdType() {
    final initial = widget.initialIdType;
    if (initial != null && _idTypes.contains(initial)) {
      _selectedIdType = initial;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idNumberController.dispose();
    _schoolController.dispose();
    super.dispose();
  }
  
  Future<void> _callNumber(String phone) async {
    final uri = Uri.parse('tel:${phone.trim()}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open dialer on this device')),
      );
    }
  }

  void _copyNumber(String phone, String label) {
    Clipboard.setData(ClipboardData(text: phone.trim()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label copied to clipboard')),
      );
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    String cleanPhone = phone.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '+254${cleanPhone.substring(1)}';
    } else if (cleanPhone.startsWith('254')) {
      cleanPhone = '+$cleanPhone';
    }
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp not installed')),
      );
    }
  }

  Future<void> _searchLostId() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (!_agreedToPolicy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please check the box to agree to the Safety & Data Handling Policy.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    setState(() {
      _isSearching = true;
      _searchResult = null;
      _errorMessage = null;
    });
    
    try {
      final response = await IdScannerService.searchLostId(
        fullName: _nameController.text.trim(),
        idNumber: _idNumberController.text.trim(),
        idType: _selectedIdType,
        schoolName: _selectedIdType == _schoolIdType
            ? _schoolController.text.trim()
            : null,
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
    if (!AuthService.isLoggedIn) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          title: const Text('Find My Lost ID'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text(
                  'Authentication Required',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'To protect user privacy and prevent spam, you must be logged in to search the Lost IDs database.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    showLoginBottomSheet(
                      context,
                      onSuccess: () => setState(() {}),
                    );
                  },
                  icon: const Icon(Icons.login),
                  label: const Text('Login or Create Account'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
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
              
              // Name input
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Name (as on ID)',
                  hintText: 'e.g., JOHN or JOHN DOE',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ID Type
              DropdownButtonFormField<String>(
                value: _selectedIdType,
                items: _idTypes
                    .map(
                      (type) => DropdownMenuItem<String>(
                        value: type,
                        child: Text(
                          type == _schoolIdType
                              ? 'School ID'
                              : 'National ID',
                        ),
                      ),
                    )
                    .toList(),
                decoration: InputDecoration(
                  labelText: 'ID Type',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedIdType = value;
                  });
                },
              ),
              const SizedBox(height: 16),

              if (_selectedIdType == _schoolIdType) ...[
                TextFormField(
                  controller: _schoolController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'School Name *',
                    hintText: 'e.g., Nairobi School',
                    prefixIcon: const Icon(Icons.school_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (_selectedIdType != _schoolIdType) return null;
                    if (value == null || value.trim().isEmpty) {
                      return 'School name is required for School ID';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],
              
              // ID Number input
              TextFormField(
                controller: _idNumberController,
                keyboardType: _selectedIdType == _schoolIdType
                    ? TextInputType.text
                    : TextInputType.number,
                inputFormatters:
                    _selectedIdType == _schoolIdType
                        ? []
                        : [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(8),
                          ],
                decoration: InputDecoration(
                  labelText: _selectedIdType == _schoolIdType
                      ? 'School ID Number'
                      : 'National ID Number',
                  hintText: _selectedIdType == _schoolIdType
                      ? 'e.g., ADM-12345'
                      : 'e.g., 12345678',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your ID number';
                  }
                  if (_selectedIdType == _schoolIdType) {
                    if (value.trim().length < 3) {
                      return 'Enter a valid school ID number';
                    }
                  } else if (value.trim().length < 7) {
                    return 'ID number must be 7-8 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              
              // Safety & Data Handling Policy Card
              Container(
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined, color: Colors.amber.shade900, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Safety & Data Handling Policy',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '• Data Handling Before Match: Your search query is securely encrypted and compared against our found database without exposing your personal identity to the public.\n'
                      '• Data Handling After Match: If your ID is found, the finder\'s contact or collection location is disclosed only to you. Your search inquiry is then purged.\n'
                      '• Data Deletion Schedule: All unmatched records and alert watchlists are automatically deleted from our servers after 7 days of inactivity or immediately upon a confirmed match.\n'
                      '• Manual Deletion: You can manually delete any found ID record at any time by clicking the red "Delete This Record" button displayed at the bottom of the result card when your ID is found.\n'
                      '• How to Verify Deletion: To check manually and confirm that your ID record has been completely erased from our servers, simply search for your ID Number on this page. If the result returns "Not Found", the record and all associated contact details have been permanently deleted.\n'
                      '• Important Safety Advice: If a finder leaves a personal phone number, NEVER meet in a private, secluded, or unfamiliar location. Always arrange to meet in a busy public place (e.g., bank, shopping mall, or police station) or urge them to leave the ID at a secure facility like a police station or security desk. Beware of anyone demanding money or luring you to unsafe areas!',
                      style: TextStyle(fontSize: 12.5, color: Colors.amber.shade900, height: 1.4),
                    ),
                    const Divider(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: _agreedToPolicy,
                            activeColor: Colors.amber.shade900,
                            onChanged: (val) {
                              setState(() {
                                _agreedToPolicy = val ?? false;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _agreedToPolicy = !_agreedToPolicy;
                              });
                            },
                            child: Text(
                              'I agree to the Data Handling Policy and understand the safety advice when meeting finders.',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
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
              const SizedBox(height: 32),
              const Center(child: GoogleAdMediumRectangleWidget()),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showRegisterAlertAlert() {
    final name = _nameController.text.trim();
    final idNumber = _idNumberController.text.trim();
    
    showDialog(
      context: context,
      builder: (context) {
        return _RegisterAlertDialog(
          idNumber: idNumber,
          fullName: name,
        );
      },
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
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.phone, color: Colors.green, size: 24),
                        const SizedBox(width: 8),
                        SelectableText(
                          result.finderPhone ?? 'N/A',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                    if (result.finderPhone != null && result.finderPhone!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _callNumber(result.finderPhone!),
                            icon: const Icon(Icons.call, size: 18),
                            label: const Text('Call Direct'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _copyNumber(result.finderPhone!, 'Phone number'),
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('Copy'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.green.shade700,
                              side: BorderSide(color: Colors.green.shade700),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (result.finderWhatsApp != null && result.finderWhatsApp!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _openWhatsApp(result.finderWhatsApp!),
                                icon: Icon(Icons.open_in_new, size: 20, color: Colors.green.shade700),
                                tooltip: 'Chat on WhatsApp',
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                              ),
                              IconButton(
                                onPressed: () => _copyNumber(result.finderWhatsApp!, 'WhatsApp number'),
                                icon: Icon(Icons.copy, size: 18, color: Colors.green.shade700),
                                tooltip: 'Copy WhatsApp',
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                              ),
                            ],
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
                          Flexible(
                            child: Text(
                              'Found at: ${result.foundLocation}',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
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
              
              if (result.foundIdId != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _confirmDelete(result.foundIdId!),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Delete This Record', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Privacy Guarantee: Your ID data is securely encrypted at rest. '
                'This record will be automatically removed after 7 days to protect your privacy.',
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
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showRegisterAlertAlert,
                icon: const Icon(Icons.notifications_active),
                label: const Text('Notify Me When Found'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
  
  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Record?'),
        content: const Text(
            'Are you sure you want to delete this ID record from our system? '
            'This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _deleteRecord(id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRecord(int id) async {
    setState(() {
      _isSearching = true;
    });
    try {
      await IdScannerService.deleteFoundId(id);
      setState(() {
        _isSearching = false;
        _searchResult = null;
        _errorMessage = 'Record deleted successfully.';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ID record has been securely deleted.')),
        );
      }
    } catch (e) {
      setState(() {
        _isSearching = false;
        _errorMessage = 'Failed to delete: $e';
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _RegisterAlertDialog extends StatefulWidget {
  final String idNumber;
  final String fullName;

  const _RegisterAlertDialog({
    required this.idNumber,
    required this.fullName,
  });

  @override
  State<_RegisterAlertDialog> createState() => _RegisterAlertDialogState();
}

class _RegisterAlertDialogState extends State<_RegisterAlertDialog> {
  final _phoneController = TextEditingController();
  bool _whatsappEnabled = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submitAlert() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final whatsappNum = _whatsappEnabled ? _phoneController.text.trim() : null;
      if (_whatsappEnabled && (whatsappNum == null || whatsappNum.isEmpty)) {
        throw Exception('Please enter your WhatsApp phone number.');
      }

      await IdScannerService.createLostIdAlert(
        idNumber: widget.idNumber,
        fullName: widget.fullName,
        whatsappAlertsEnabled: _whatsappEnabled,
        whatsappNumber: whatsappNum,
      );

      if (mounted) {
        Navigator.pop(context, true); // Return success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Watchlist alert registered! We will notify you when found.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.add_alert, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          const Text('Notify Me When Found'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Register this ID card on your watchlist. When a finder registers a matching ID, you will receive an instant notification.',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            Text(
              'Name: ${widget.fullName}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'ID Number: ${widget.idNumber}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Divider(),
            SwitchListTile(
              title: const Text('WhatsApp Notifications'),
              subtitle: const Text('Receive a message when your ID is found'),
              value: _whatsappEnabled,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) {
                setState(() {
                  _whatsappEnabled = val;
                });
              },
            ),
            if (_whatsappEnabled) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'WhatsApp Phone Number',
                  hintText: 'e.g., +254700000000',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submitAlert,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Notify Me'),
        ),
      ],
    );
  }
}
