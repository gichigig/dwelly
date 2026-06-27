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
      _hideTimer = Timer(const Duration(seconds: 2), () {
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

            Color bannerColor = Colors.orange.shade700.withOpacity(0.85);
            IconData bannerIcon = Icons.network_check;
            String bannerText = 'Slow Internet Connection';

            if (isOffline) {
              bannerColor = Colors.red.shade600.withOpacity(0.85);
              bannerIcon = Icons.wifi_off;
              bannerText = 'No Internet Connection';
            } else if (isBackOnline) {
              bannerColor = Colors.green.shade600.withOpacity(0.85);
              bannerIcon = Icons.check_circle;
              bannerText = 'Back Online';
            }

            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _isVisible
                    ? Material(
                        color: Colors.transparent,
                        child: Container(
                          width: double.infinity,
                          color: bannerColor,
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    bannerIcon,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    bannerText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity, height: 0),
              ),
            );
          },
        ),
      ],
    );
  }
}

