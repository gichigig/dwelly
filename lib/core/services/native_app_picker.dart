import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class NativeAppPicker {
  static const MethodChannel _channel = MethodChannel('com.ishinadwelly.app/image_picker_apps');

  static Future<List<Map<String, dynamic>>> getApps() async {
    if (!Platform.isAndroid) return [];
    try {
      final List<dynamic> result = await _channel.invokeMethod('getApps');
      return result.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      print('Error fetching native apps: $e');
      return [];
    }
  }

  static Future<List<XFile>> pickFromApp(String packageName, String className) async {
    if (!Platform.isAndroid) return [];
    try {
      final List<dynamic>? filePaths = await _channel.invokeMethod('pickFromApp', {
        'packageName': packageName,
        'className': className,
      });
      if (filePaths != null && filePaths.isNotEmpty) {
        return filePaths.map((path) => XFile(path as String)).toList();
      }
    } catch (e) {
      print('Error picking from native app: $e');
    }
    return [];
  }
}
