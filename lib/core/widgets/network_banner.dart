import 'package:flutter/material.dart';
import '../services/network_service.dart';

class NetworkBanner extends StatelessWidget {
  final Widget child;

  const NetworkBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: child),
        ValueListenableBuilder<NetworkStatus>(
          valueListenable: NetworkService.instance.status,
          builder: (context, status, _) {
            final isOffline = status == NetworkStatus.offline;
            final isSlow = status == NetworkStatus.slow;
            final isBackOnline = status == NetworkStatus.backOnline;
            final showBanner = isOffline || isSlow || isBackOnline;

            Color bannerColor = Colors.orange.shade700;
            IconData bannerIcon = Icons.network_check;
            String bannerText = 'Slow Internet Connection';

            if (isOffline) {
              bannerColor = Colors.red.shade600;
              bannerIcon = Icons.wifi_off;
              bannerText = 'No Internet Connection';
            } else if (isBackOnline) {
              bannerColor = Colors.green.shade600;
              bannerIcon = Icons.check_circle;
              bannerText = 'Back Online';
            }

            return AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: showBanner
                  ? Material(
                      color: bannerColor,
                      child: SafeArea(
                        top: false,
                        child: Container(
                          width: double.infinity,
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
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            );
          },
        ),
      ],
    );
  }
}
