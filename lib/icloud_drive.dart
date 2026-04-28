import 'package:flutter/services.dart';

class ICloudDrive {
  static const _channel = MethodChannel('takken_ai2/icloud');

  static Future<bool> isAvailable() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> saveText(String filename, String text) async {
    try {
      final path = await _channel.invokeMethod<String>('saveText', {
        'filename': filename,
        'text': text,
      });
      return path;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> readText(String filename) async {
    try {
      final text = await _channel.invokeMethod<String>('readText', {
        'filename': filename,
      });
      return text;
    } catch (_) {
      return null;
    }
  }

  static Future<ICloudFileInfo> fileInfo(String filename) async {
    try {
      final map = await _channel.invokeMethod<dynamic>('fileInfo', {
        'filename': filename,
      });
      if (map is Map) {
        final exists = (map['exists'] == true);
        final modifiedMs =
            (map['modifiedMs'] is int) ? map['modifiedMs'] as int : null;
        return ICloudFileInfo(exists: exists, modifiedMs: modifiedMs);
      }
    } catch (_) {}
    return ICloudFileInfo(exists: false, modifiedMs: null);
  }
}

class ICloudFileInfo {
  final bool exists;
  final int? modifiedMs;
  ICloudFileInfo({required this.exists, this.modifiedMs});
}
