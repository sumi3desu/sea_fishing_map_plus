import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class RevenueCatService {
  static const String iosApiKey = 'appl_ZmEnPhqcvOPcWXaiCCHiPAnGxxd';

  static bool _configured = false;
  static Completer<void>? _readyCompleter;
  static String? _currentAppUserId;

  static Future<void> configure({required String appUserId}) async {
    await Purchases.setLogLevel(kReleaseMode ? LogLevel.info : LogLevel.debug);

    if (_configured) {
      if (_currentAppUserId == appUserId) {
        _readyCompleter ??= Completer<void>()..complete();
        return;
      }
      try {
        await Purchases.logIn(appUserId);
        _currentAppUserId = appUserId;
        if (_readyCompleter == null || _readyCompleter!.isCompleted) {
          _readyCompleter = Completer<void>();
        }
        _readyCompleter!.complete();
        return;
      } catch (e) {
        if (_readyCompleter == null || _readyCompleter!.isCompleted) {
          _readyCompleter = Completer<void>();
        }
        _readyCompleter!.completeError(e);
        rethrow;
      }
    }

    final configuration = PurchasesConfiguration(iosApiKey)
      ..appUserID = appUserId;

    try {
      await Purchases.configure(configuration);
      _configured = true;
      _currentAppUserId = appUserId;
      if (_readyCompleter == null || _readyCompleter!.isCompleted) {
        _readyCompleter = Completer<void>();
      }
      _readyCompleter!.complete();
    } catch (e) {
      // 失敗時も後続に通知
      if (_readyCompleter == null || _readyCompleter!.isCompleted) {
        _readyCompleter = Completer<void>();
      }
      _readyCompleter!.completeError(e);
      rethrow;
    }
  }

  static bool get isConfigured => _configured;

  // 他所から安全に待機するためのユーティリティ（タイムアウト指定可能）
  static Future<void> waitUntilConfigured({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_configured) return;
    _readyCompleter ??= Completer<void>();
    try {
      await _readyCompleter!.future.timeout(timeout);
    } catch (_) {
      // タイムアウトの場合は以降の Purchases 呼び出しを避ける判断材料として使う
    }
  }
}
