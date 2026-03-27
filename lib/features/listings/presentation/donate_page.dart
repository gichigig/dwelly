import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/mpesa_service.dart';

class DonatePage extends StatefulWidget {
  const DonatePage({super.key});

  @override
  State<DonatePage> createState() => _DonatePageState();
}

class _DonatePageState extends State<DonatePage> {
  int? _selectedAmount;
  final _customAmountController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _showCustomAmount = false;
  bool _isProcessing = false;
  String? _processingMessage;
  StreamSubscription? _statusSubscription;

  static const String mpesaPaybill = '123456'; // Replace with actual paybill
  static const String mpesaAccountNumber = 'DONATE';
  static const String contactEmail = 'donations@dwelly.co.ke';
  static const String contactPhone = '+254 700 000 000';

  final List<int> _suggestedAmounts = [50, 100, 200, 500, 1000, 2000];

  @override
  void dispose() {
    _customAmountController.dispose();
    _phoneController.dispose();
    _statusSubscription?.cancel();
    super.dispose();
  }

  int get _donationAmount {
    if (_showCustomAmount) {
      return int.tryParse(_customAmountController.text) ?? 0;
    }
    return _selectedAmount ?? 0;
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _initiateSTKPush() async {
    final phone = _phoneController.text.trim();
    final amount = _donationAmount;

    // Validate
    if (phone.isEmpty) {
      _showError('Please enter your M-Pesa phone number');
      return;
    }

    if (!MpesaService.isValidPhoneNumber(phone)) {
      _showError('Please enter a valid Safaricom phone number');
      return;
    }

    if (amount < 1) {
      _showError('Please select or enter a donation amount');
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingMessage = 'Initiating payment...';
    });

    // Initiate STK Push
    final result = await MpesaService.initiateSTKPush(
      phoneNumber: phone,
      amount: amount,
    );

    if (!result.success) {
      setState(() {
        _isProcessing = false;
        _processingMessage = null;
      });
      _showError(result.errorMessage ?? 'Failed to initiate payment');
      return;
    }

    setState(() {
      _processingMessage = 'Please enter your M-Pesa PIN...';
    });

    // Show the PIN prompt dialog
    _showPinPromptDialog(result.checkoutRequestId!, amount);
  }

  void _showPinPromptDialog(String checkoutRequestId, int amount) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _MpesaPinDialog(
        checkoutRequestId: checkoutRequestId,
        amount: amount,
        onComplete: (success, message) {
          Navigator.of(context).pop();
          setState(() {
            _isProcessing = false;
            _processingMessage = null;
          });
          
          if (success) {
            _showSuccessDialog(message);
          } else {
            _showError(message);
          }
        },
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 64),
        title: const Text('Thank You!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 16),
            const Text(
              'Your donation helps keep Dwelly free for everyone. We truly appreciate your support! 💚',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openMpesaApp() async {
    // Try to open M-Pesa app via USSD or intent
    final uri = Uri.parse('tel:*334%23');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _sendEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: contactEmail,
      queryParameters: {
        'subject': 'Large Donation Inquiry - Dwelly',
        'body': 'Hello,\n\nI would like to make a large donation to support Dwelly.\n\nPlease contact me to discuss the details.\n\nThank you!',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _callSupport() async {
    final uri = Uri.parse('tel:$contactPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Dwelly'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withOpacity(0.8),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.favorite,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Help Us Keep Dwelly Free',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your donation helps us maintain servers, improve features, and keep the platform free for everyone.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // M-Pesa STK Push Section (Recommended)
                  _buildSectionCard(
                    context,
                    icon: Icons.flash_on,
                    iconColor: const Color(0xFF4CAF50), // M-Pesa green
                    title: 'Quick Donate (Recommended)',
                    subtitle: 'STK Push - Pay instantly from your phone',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Amount Selection
                        Text(
                          'Select Amount (KES)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ..._suggestedAmounts.map((amount) => _buildAmountChip(amount)),
                            _buildCustomAmountChip(),
                          ],
                        ),

                        if (_showCustomAmount) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _customAmountController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              labelText: 'Enter amount',
                              prefixText: 'KES ',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // Phone Number Input
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'M-Pesa Phone Number',
                            hintText: '07XX XXX XXX',
                            prefixIcon: const Icon(Icons.phone, color: Color(0xFF4CAF50)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            helperText: 'Enter Safaricom number registered with M-Pesa',
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Pay Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: (_isProcessing || _donationAmount < 1) ? null : _initiateSTKPush,
                            icon: _isProcessing 
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send),
                            label: Text(
                              _isProcessing 
                                ? (_processingMessage ?? 'Processing...')
                                : _donationAmount > 0 
                                  ? 'Donate KES $_donationAmount'
                                  : 'Select Amount to Donate',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4CAF50),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[400],
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Info text
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'You\'ll receive an M-Pesa prompt on your phone. Enter your PIN to complete the donation.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Manual M-Pesa Section
                  _buildSectionCard(
                    context,
                    icon: Icons.phone_android,
                    iconColor: const Color(0xFF4CAF50), // M-Pesa green
                    title: 'Manual M-Pesa Payment',
                    subtitle: 'Pay via Paybill',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Paybill Info
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF4CAF50).withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            children: [
                              _buildPaybillRow(
                                'Paybill Number',
                                mpesaPaybill,
                                onCopy: () => _copyToClipboard(mpesaPaybill, 'Paybill number'),
                              ),
                              const Divider(height: 24),
                              _buildPaybillRow(
                                'Account Number',
                                mpesaAccountNumber,
                                onCopy: () => _copyToClipboard(mpesaAccountNumber, 'Account number'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Instructions
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'How to donate manually:',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildInstructionStep('1', 'Go to M-Pesa on your phone'),
                              _buildInstructionStep('2', 'Select "Lipa na M-Pesa"'),
                              _buildInstructionStep('3', 'Select "Pay Bill"'),
                              _buildInstructionStep('4', 'Enter Business Number: $mpesaPaybill'),
                              _buildInstructionStep('5', 'Enter Account Number: $mpesaAccountNumber'),
                              _buildInstructionStep('6', 'Enter Amount and confirm'),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _openMpesaApp,
                            icon: const Icon(Icons.phone_android),
                            label: const Text('Open M-Pesa'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4CAF50),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Large Donations Section
                  _buildSectionCard(
                    context,
                    icon: Icons.diamond_outlined,
                    iconColor: Colors.amber,
                    title: 'Large Donations',
                    subtitle: 'For donations above KES 10,000',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'For larger contributions, please contact our team directly. We can arrange bank transfers, provide receipts, and discuss how your donation will be used.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _sendEmail,
                                icon: const Icon(Icons.email_outlined),
                                label: const Text('Email Us'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _callSupport,
                                icon: const Icon(Icons.phone_outlined),
                                label: const Text('Call Us'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
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

                  // What Donations Support
                  _buildSectionCard(
                    context,
                    icon: Icons.auto_awesome,
                    iconColor: colorScheme.primary,
                    title: 'Your Impact',
                    child: Column(
                      children: [
                        _buildImpactItem(
                          Icons.storage,
                          'Server & Database',
                          'Keep the platform running 24/7',
                        ),
                        _buildImpactItem(
                          Icons.cloud_upload,
                          'Cloud Storage',
                          'Store property images and documents',
                        ),
                        _buildImpactItem(
                          Icons.code,
                          'Development',
                          'Build new features and fix bugs',
                        ),
                        _buildImpactItem(
                          Icons.support_agent,
                          'Support',
                          'Help users and maintain quality',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Thank You Message
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.volunteer_activism,
                          size: 32,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Thank You!',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Every contribution, big or small, helps us continue our mission to make housing search free and accessible for all Kenyans.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildPaybillRow(String label, String value, {VoidCallback? onCopy}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        if (onCopy != null)
          IconButton(
            onPressed: onCopy,
            icon: const Icon(Icons.copy, size: 20),
            tooltip: 'Copy',
          ),
      ],
    );
  }

  Widget _buildAmountChip(int amount) {
    final isSelected = _selectedAmount == amount && !_showCustomAmount;

    return ChoiceChip(
      label: Text('KES $amount'),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedAmount = selected ? amount : null;
          _showCustomAmount = false;
        });
      },
      selectedColor: const Color(0xFF4CAF50).withOpacity(0.2),
      checkmarkColor: const Color(0xFF4CAF50),
    );
  }

  Widget _buildCustomAmountChip() {
    return ChoiceChip(
      label: const Text('Custom'),
      selected: _showCustomAmount,
      onSelected: (selected) {
        setState(() {
          _showCustomAmount = selected;
          _selectedAmount = null;
        });
      },
      selectedColor: const Color(0xFF4CAF50).withOpacity(0.2),
      checkmarkColor: const Color(0xFF4CAF50),
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4CAF50),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImpactItem(IconData icon, String title, String description) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog that shows while waiting for M-Pesa PIN entry
class _MpesaPinDialog extends StatefulWidget {
  final String checkoutRequestId;
  final int amount;
  final Function(bool success, String message) onComplete;

  const _MpesaPinDialog({
    required this.checkoutRequestId,
    required this.amount,
    required this.onComplete,
  });

  @override
  State<_MpesaPinDialog> createState() => _MpesaPinDialogState();
}

class _MpesaPinDialogState extends State<_MpesaPinDialog> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  StreamSubscription? _statusSubscription;
  String _statusMessage = 'Waiting for M-Pesa PIN...';
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _startPolling();
  }

  void _startPolling() {
    _statusSubscription = MpesaService.waitForPayment(widget.checkoutRequestId).listen(
      (status) {
        if (_isCompleted) return;
        
        switch (status.status) {
          case MpesaStatus.completed:
            _isCompleted = true;
            widget.onComplete(true, 'Donation of KES ${widget.amount} received successfully!\nReceipt: ${status.mpesaReceiptNumber}');
            break;
          case MpesaStatus.cancelled:
            _isCompleted = true;
            widget.onComplete(false, 'Payment was cancelled');
            break;
          case MpesaStatus.failed:
            _isCompleted = true;
            widget.onComplete(false, status.resultDesc.isNotEmpty ? status.resultDesc : 'Payment failed. Please try again.');
            break;
          case MpesaStatus.pending:
            // Still waiting
            break;
        }
      },
      onError: (error) {
        if (!_isCompleted) {
          _isCompleted = true;
          widget.onComplete(false, 'An error occurred. Please check your M-Pesa messages.');
        }
      },
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          
          // Animated phone icon
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (_pulseController.value * 0.1),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1 + (_pulseController.value * 0.1)),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.phone_android,
                    size: 48,
                    color: Color(0xFF4CAF50),
                  ),
                ),
              );
            },
          ),
          
          const SizedBox(height: 24),
          
          Text(
            'KES ${widget.amount}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4CAF50),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            'Please check your phone and enter your M-Pesa PIN to complete the donation.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          
          const SizedBox(height: 24),
          
          const LinearProgressIndicator(
            backgroundColor: Color(0xFFE8F5E9),
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
          ),
          
          const SizedBox(height: 16),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _isCompleted = true;
            widget.onComplete(false, 'Payment cancelled');
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
