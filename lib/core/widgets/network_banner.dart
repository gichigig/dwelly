import 'dart:async';
import 'package:flutter/material.dart';
import '../services/network_service.dart';

class NetworkBanner extends StatefulWidget {
  final Widget child;

  const NetworkBanner({super.key, required this.child});

  @override
  State<NetworkBanner> createState() => _NetworkBannerState();
}

class _NetworkBannerState extends State<NetworkBanner> {
  bool _isVisible = false;
  Timer? _hideTimer;
  NetworkStatus _lastStatus = NetworkStatus.online;

  @override
  void initState() {
    super.initState();
    NetworkService.instance.status.addListener(_onNetworkStatusChanged);
  }

  @override
  void dispose() {
    NetworkService.instance.status.removeListener(_onNetworkStatusChanged);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onNetworkStatusChanged() {
    final status = NetworkService.instance.status.value;
    if (status == _lastStatus) return;
    _lastStatus = status;

    if (status != NetworkStatus.online) {
      setState(() {
        _isVisible = true;
      });
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) {
          setState(() {
            _isVisible = false;
          });
        }
      });
    } else {
      if (mounted) {
        setState(() {
          _isVisible = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<NetworkStatus>(
          valueListenable: NetworkService.instance.status,
          builder: (context, status, _) {
            final isOffline = status == NetworkStatus.offline;
            final isBackOnline = status == NetworkStatus.backOnline;

            Color iconColor = Colors.orange.shade400;
            IconData bannerIcon = Icons.network_check;
            String bannerText = 'Slow internet connection';

            if (isOffline) {
              iconColor = Colors.red.shade400;
              bannerIcon = Icons.wifi_off;
              bannerText = 'No internet connection';
            } else if (isBackOnline) {
              iconColor = Colors.green.shade400;
              bannerIcon = Icons.check_circle;
              bannerText = 'Back online';
            }

            return Positioned(
              left: 16,
              right: 16,
              top: 12,
              child: SafeArea(
                bottom: false,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  offset: _isVisible ? Offset.zero : const Offset(0, -1.5),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: _isVisible ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: !_isVisible,
                      child: Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFF323232),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 16,
                          ),
                          child: Row(
                            children: [
                              Icon(bannerIcon, color: iconColor, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  bannerText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
