import 'package:flutter/material.dart';
import 'donate_page.dart';

/// A floating action button for donations with an X to dismiss.
/// When [requireAuth] is true and user is not authenticated,
/// it will show a login prompt instead.
class DonationFab extends StatefulWidget {
  final bool requireAuth;
  final bool isAuthenticated;
  final VoidCallback? onLoginRequired;

  const DonationFab({
    super.key,
    this.requireAuth = false,
    this.isAuthenticated = false,
    this.onLoginRequired,
  });

  @override
  State<DonationFab> createState() => _DonationFabState();
}

class _DonationFabState extends State<DonationFab>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
  }

  void _onDonateTap() {
    if (widget.requireAuth && !widget.isAuthenticated) {
      widget.onLoginRequired?.call();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DonatePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Expanded donate card
        ScaleTransition(
          scale: _scaleAnim,
          alignment: Alignment.bottomRight,
          child: _isExpanded
              ? Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  width: 220,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.favorite,
                                color: Color(0xFF4CAF50),
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Support Dwelly',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Help keep it free for everyone',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        InkWell(
                          onTap: _onDonateTap,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(16),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.phone_android,
                                  color: Color(0xFF4CAF50),
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Donate via M-Pesa',
                                  style: TextStyle(
                                    color: Color(0xFF4CAF50),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // FAB button
        FloatingActionButton(
          heroTag: 'donation_fab',
          onPressed: _toggle,
          backgroundColor:
              _isExpanded ? Colors.grey[700] : const Color(0xFF4CAF50),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isExpanded
                ? const Icon(Icons.close, key: ValueKey('close'), color: Colors.white)
                : const Icon(Icons.favorite, key: ValueKey('heart'), color: Colors.white),
          ),
        ),
      ],
    );
  }
}
