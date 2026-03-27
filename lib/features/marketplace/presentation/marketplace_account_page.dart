import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/errors/ui_error.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/marketplace_service.dart';
import '../../../core/widgets/auth_bottom_sheets.dart';
import '../../../core/widgets/auth_gate_card.dart';
import '../../listings/presentation/account_page.dart';
import '../../listings/presentation/notification_settings_page.dart';
import '../../listings/presentation/privacy_personalization_page.dart';
import '../../listings/presentation/security_center_page.dart';
import 'marketplace_orders_page.dart';
import 'marketplace_seller_dashboard_page.dart';

class MarketplaceAccountPage extends StatefulWidget {
  final MarketplaceAccountSummary? initialSummary;

  const MarketplaceAccountPage({super.key, this.initialSummary});

  @override
  State<MarketplaceAccountPage> createState() => _MarketplaceAccountPageState();
}

class _MarketplaceAccountPageState extends State<MarketplaceAccountPage> {
  static const Duration _firstLoadTimeout = Duration(milliseconds: 4500);

  bool _loadingSummary = true;
  bool _loadingBadge = true;
  String? _summaryError;
  String? _badgeError;
  MarketplaceAccountSummary _summary = const MarketplaceAccountSummary.empty();
  Map<String, dynamic>? _badgeRequest;

  @override
  void initState() {
    super.initState();
    if (widget.initialSummary != null) {
      _summary = widget.initialSummary!;
      _loadingSummary = false;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    if (!AuthService.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loadingSummary = false;
        _loadingBadge = false;
        _summaryError = null;
        _badgeError = null;
        _summary = const MarketplaceAccountSummary.empty();
        _badgeRequest = null;
      });
      return;
    }

    setState(() {
      _loadingSummary =
          !_summary.authenticated &&
          _summary.totalProducts == 0 &&
          _summary.savedCount == 0;
      _loadingBadge = true;
      _summaryError = null;
      _badgeError = null;
    });

    unawaited(_loadSummary());
    unawaited(_loadBadgeRequest());
  }

  Future<void> _loadSummary() async {
    try {
      final summary = await MarketplaceService.getAccountSummary(
        requestTimeout: _firstLoadTimeout,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loadingSummary = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summaryError = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load account summary.',
        );
        _loadingSummary = false;
      });
    }
  }

  Future<void> _loadBadgeRequest() async {
    try {
      final badge = await MarketplaceService.getMyMarketplaceBadgeRequest(
        requestTimeout: _firstLoadTimeout,
      );
      if (!mounted) return;
      setState(() {
        _badgeRequest = badge;
        _loadingBadge = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _badgeError = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load badge details.',
        );
        _loadingBadge = false;
      });
    }
  }

  Future<void> _requestBadge() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _BadgeApplicationSheet(),
    );
    if (result == true) {
      _showSnack('Badge request submitted');
      _loadData();
    }
  }

  Future<void> _signOut() async {
    await AuthService.logout();
    if (!mounted) return;
    setState(() {});
    _showSnack('Signed out');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: AuthGateCard(
          title: 'Marketplace Account',
          subtitle:
              'Sign in to manage your seller profile, badge, sponsorship, and listings.',
          onSignIn: () => showLoginBottomSheet(
            context,
            onSuccess: () {
              setState(() {});
              _loadData();
            },
          ),
          onCreateAccount: () => showSignupBottomSheet(
            context,
            onSuccess: () {
              setState(() {});
              _loadData();
            },
          ),
        ),
      );
    }

    final user = AuthService.currentUser!;
    final badgeStatus =
        (_badgeRequest?['status'] as String?) ?? _summary.badgeStatus;
    final totalProducts = _summary.totalProducts;
    final activeRequests = _summary.pendingSponsorshipRequests;
    final summaryWarnings = _summary.warnings
        .where((warning) => warning.trim().isNotEmpty)
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          if (_summaryError != null)
            _InlineErrorBanner(message: _summaryError!, onRetry: _loadSummary),
          if (_badgeError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _InlineErrorBanner(
                message: _badgeError!,
                onRetry: _loadBadgeRequest,
              ),
            ),
          if (summaryWarnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _InlineInfoBanner(
                message: summaryWarnings.join(' '),
                onRetry: _loadSummary,
              ),
            ),
          _loadingSummary
              ? const _MarketplaceAccountSummarySkeleton()
              : Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.email,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(label: Text('Products: $totalProducts')),
                            Chip(label: Text('Badge: $badgeStatus')),
                            Chip(
                              label: Text(
                                'Pending sponsorship: $activeRequests',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                if (_loadingBadge)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                ListTile(
                  leading: const Icon(Icons.storefront),
                  title: const Text('Seller Dashboard'),
                  subtitle: const Text('Manage products and status'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MarketplaceSellerDashboardPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('My Orders'),
                  subtitle: const Text('Track checkout and payment status'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MarketplaceOrdersPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.verified),
                  title: const Text('Marketplace Badge'),
                  subtitle: Text(
                    _loadingBadge
                        ? 'Status: loading...'
                        : 'Status: $badgeStatus',
                  ),
                  trailing: badgeStatus == 'NONE' || badgeStatus == 'REJECTED'
                      ? FilledButton.tonal(
                          onPressed: _requestBadge,
                          child: const Text('Apply'),
                        )
                      : null,
                ),
                if (!_loadingBadge &&
                    (badgeStatus == 'PENDING' ||
                        badgeStatus == 'APPROVED')) ...[
                  const Divider(height: 1),
                  _buildDocStatus(
                    'Company Logo',
                    _badgeRequest?['companyLogoUrl'],
                  ),
                  _buildDocStatus(
                    'Company Profile',
                    _badgeRequest?['companyProfilePdfUrl'],
                  ),
                  _buildDocStatus(
                    'Business Permit',
                    _badgeRequest?['businessPermitUrl'],
                  ),
                  _buildDocStatus(
                    'National ID',
                    _badgeRequest?['nationalIdUrl'],
                  ),
                  _buildDocStatus(
                    'KRA Certificate',
                    _badgeRequest?['kraCertUrl'],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Marketplace Notifications'),
                  subtitle: const Text('Shared notification settings'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationSettingsPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.security_outlined),
                  title: const Text('Security & Sign-in'),
                  subtitle: const Text('Shared global security settings'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SecurityCenterPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy & Personalization'),
                  subtitle: const Text('Shared global privacy controls'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPersonalizationPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Open Global Account Settings'),
                  subtitle: const Text('Profile and account details'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountPage()),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  Widget _buildDocStatus(String label, String? url) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(
            url != null && url.isNotEmpty ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: url != null && url.isNotEmpty ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _InlineErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _InlineInfoBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineInfoBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _MarketplaceAccountSummarySkeleton extends StatelessWidget {
  const _MarketplaceAccountSummarySkeleton();

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonBlock(width: 180, height: 18, color: baseColor),
            const SizedBox(height: 8),
            _SkeletonBlock(width: 220, height: 14, color: baseColor),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SkeletonBlock(width: 110, height: 28, color: baseColor),
                _SkeletonBlock(width: 96, height: 28, color: baseColor),
                _SkeletonBlock(width: 160, height: 28, color: baseColor),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _SkeletonBlock({
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Badge Application Bottom Sheet with Document Uploads
// ------------------------------------------------------------------
class _BadgeApplicationSheet extends StatefulWidget {
  const _BadgeApplicationSheet();

  @override
  State<_BadgeApplicationSheet> createState() => _BadgeApplicationSheetState();
}

class _BadgeApplicationSheetState extends State<_BadgeApplicationSheet> {
  final _picker = ImagePicker();
  bool _submitting = false;
  String? _error;

  File? _companyLogo;
  File? _companyProfilePdf;
  File? _businessPermit;
  File? _nationalId;
  File? _kraCert;

  Future<void> _pickImage(ValueChanged<File> onPicked) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked != null) {
      onPicked(File(picked.path));
      setState(() {});
    }
  }

  Future<void> _pickPdf(ValueChanged<File> onPicked) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      onPicked(File(result.files.single.path!));
      setState(() {});
    }
  }

  Future<String?> _uploadIfPresent(File? file) async {
    if (file == null) return null;
    return MarketplaceService.uploadFile(file);
  }

  Future<void> _submit() async {
    // Require at least one document
    if (_companyLogo == null &&
        _companyProfilePdf == null &&
        _businessPermit == null &&
        _nationalId == null &&
        _kraCert == null) {
      setState(() => _error = 'Please upload at least one document');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // Upload all files first
      final results = await Future.wait([
        _uploadIfPresent(_companyLogo),
        _uploadIfPresent(_companyProfilePdf),
        _uploadIfPresent(_businessPermit),
        _uploadIfPresent(_nationalId),
        _uploadIfPresent(_kraCert),
      ]);

      await MarketplaceService.requestMarketplaceBadge(
        companyLogoUrl: results[0],
        companyProfilePdfUrl: results[1],
        businessPermitUrl: results[2],
        nationalIdUrl: results[3],
        kraCertUrl: results[4],
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to submit badge request.',
        );
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ListView(
          controller: scrollController,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Badge Application',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Upload your business documents. These will be reviewed by our team before your seller badge is approved.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            _docTile(
              icon: Icons.photo_camera,
              label: 'Company Logo',
              hint: 'JPG / PNG image',
              file: _companyLogo,
              onPick: () => _pickImage((f) => _companyLogo = f),
            ),
            _docTile(
              icon: Icons.picture_as_pdf,
              label: 'Company Profile (PDF)',
              hint: 'PDF document',
              file: _companyProfilePdf,
              onPick: () => _pickPdf((f) => _companyProfilePdf = f),
            ),
            _docTile(
              icon: Icons.receipt_long,
              label: 'Business Permit',
              hint: 'JPG / PNG image',
              file: _businessPermit,
              onPick: () => _pickImage((f) => _businessPermit = f),
            ),
            _docTile(
              icon: Icons.badge,
              label: 'National ID (Both Sides)',
              hint: 'JPG / PNG scan',
              file: _nationalId,
              onPick: () => _pickImage((f) => _nationalId = f),
            ),
            _docTile(
              icon: Icons.description,
              label: 'KRA Certificate',
              hint: 'JPG / PNG image',
              file: _kraCert,
              onPick: () => _pickImage((f) => _kraCert = f),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(
                _submitting
                    ? 'Uploading & Submitting...'
                    : 'Submit Application',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docTile({
    required IconData icon,
    required String label,
    required String hint,
    required File? file,
    required VoidCallback onPick,
  }) {
    final picked = file != null;
    final subtitle = file?.path.split('/').last ?? hint;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: picked ? Colors.green : null),
        title: Text(label),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: picked
            ? const Icon(Icons.check_circle, color: Colors.green)
            : OutlinedButton(onPressed: onPick, child: const Text('Upload')),
        onTap: onPick,
      ),
    );
  }
}
