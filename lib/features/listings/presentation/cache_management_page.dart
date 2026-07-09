import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/cache_service.dart' as app_cache;
import '../../../core/services/device_rental_cache_service.dart';

// Top-level function for the background isolate
int _calcDirSize(String dirPath) {
  int total = 0;
  final dir = Directory(dirPath);
  if (dir.existsSync()) {
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += entity.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
  return total;
}

class CacheManagementPage extends StatefulWidget {
  const CacheManagementPage({super.key});

  @override
  State<CacheManagementPage> createState() => _CacheManagementPageState();
}

class _CacheManagementPageState extends State<CacheManagementPage> {
  String _cacheSizeStr = 'Calculating...';
  int _totalCacheBytes = 0;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _calculateCacheSize();
  }

  Future<void> _calculateCacheSize() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final totalSize = await compute(_calcDirSize, tempDir.path);
      
      if (!mounted) return;
      setState(() {
        _totalCacheBytes = totalSize;
        if (totalSize < 1024 * 1024) {
          _cacheSizeStr = '${(totalSize / 1024).toStringAsFixed(1)} KB';
        } else if (totalSize < 1024 * 1024 * 1024) {
          _cacheSizeStr = '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
        } else {
          _cacheSizeStr = '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cacheSizeStr = 'Unknown size';
          _totalCacheBytes = 0;
        });
      }
    }
  }

  Future<void> _clearDeviceCache() async {
    setState(() => _isClearing = true);
    
    await DeviceRentalCacheService.clear();
    app_cache.CacheManager.clearAll();
    ApiService.clearCachedGets();
    await DefaultCacheManager().emptyCache();

    // Aggressively clear the entire temp directory to ensure size drops to 0
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        for (final entity in tempDir.listSync()) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {} // Ignore files currently in use by the OS
        }
      }
    } catch (_) {}

    if (!mounted) return;
    await _calculateCacheSize();
    
    if (!mounted) return;
    setState(() => _isClearing = false);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Device cache cleared.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double maxVisualBytes = 250 * 1024 * 1024;
    double progress = _totalCacheBytes / maxVisualBytes;
    if (progress > 1.0) progress = 1.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage & Cache'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Device Cache Storage',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Offline listings, images, and search history use storage space on your device. Clearing it frees up space but may briefly increase data usage the next time you browse.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5, fontSize: 16),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Used',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        Text(
                          _cacheSizeStr,
                          style: TextStyle(
                            fontSize: 18, 
                            fontWeight: FontWeight.bold,
                            color: progress > 0.8 ? Colors.red : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 16,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progress > 0.8 ? Colors.red : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: FilledButton.icon(
                  onPressed: _isClearing ? null : _clearDeviceCache,
                  icon: _isClearing
                      ? const SizedBox(
                          width: 24, 
                          height: 24, 
                          child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)
                        )
                      : const Icon(Icons.delete_sweep, size: 28, color: Colors.white),
                  label: Text(
                    _isClearing ? 'CLEARING...' : 'CLEAR DEVICE CACHE',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
