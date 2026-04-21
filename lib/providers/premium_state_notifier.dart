import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../appconfig.dart';
import '../services/revenuecat_service.dart';

final premiumStateProvider =
    StateNotifierProvider<PremiumStateNotifier, PremiumState>(
      (ref) => PremiumStateNotifier(),
    );

class PremiumState {
  final bool isLoading;
  final bool isPremium;
  final String? errorMessage;

  const PremiumState({
    required this.isLoading,
    required this.isPremium,
    this.errorMessage,
  });

  factory PremiumState.initial() {
    return const PremiumState(
      isLoading: true,
      isPremium: false,
      errorMessage: null,
    );
  }

  PremiumState copyWith({
    bool? isLoading,
    bool? isPremium,
    String? errorMessage,
  }) {
    return PremiumState(
      isLoading: isLoading ?? this.isLoading,
      isPremium: isPremium ?? this.isPremium,
      errorMessage: errorMessage,
    );
  }
}

class PremiumStateNotifier extends StateNotifier<PremiumState> {
  PremiumStateNotifier() : super(PremiumState.initial());
  static const String _cacheKey = 'premium_is_premium';

  bool _listenerRegistered = false;
  String? _lastSyncedSignature;

  static const String entitlementId = 'premium';

  Future<void> initialize() async {
    if (!_listenerRegistered) {
      Purchases.addCustomerInfoUpdateListener(_handleCustomerInfoUpdate);
      _listenerRegistered = true;
    }
    // まずはキャッシュを即時反映（起動直後でもUIで参照できるように）
    await _loadCached();
    // RevenueCatのconfigure完了を待つ（短いタイムアウト）
    await RevenueCatService.waitUntilConfigured(
      timeout: const Duration(seconds: 5),
    );
    if (!RevenueCatService.isConfigured) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '未初期化（後ほど再取得してください）',
      );
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      if (!RevenueCatService.isConfigured) {
        await RevenueCatService.waitUntilConfigured(
          timeout: const Duration(seconds: 5),
        );
        if (!RevenueCatService.isConfigured) {
          state = state.copyWith(isLoading: false, errorMessage: '未初期化');
          return;
        }
      }
      final customerInfo = await Purchases.getCustomerInfo();
      await _applyCustomerInfo(customerInfo);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void _handleCustomerInfoUpdate(CustomerInfo customerInfo) {
    unawaited(_applyCustomerInfo(customerInfo));
  }

  Future<void> restorePurchases() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      if (!RevenueCatService.isConfigured) {
        await RevenueCatService.waitUntilConfigured(
          timeout: const Duration(seconds: 5),
        );
        if (!RevenueCatService.isConfigured) {
          state = state.copyWith(isLoading: false, errorMessage: '未初期化');
          return;
        }
      }
      final customerInfo = await Purchases.restorePurchases();
      await _applyCustomerInfo(customerInfo);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_cacheKey)) {
        final cached = prefs.getBool(_cacheKey) ?? false;
        state = state.copyWith(
          isLoading: false,
          isPremium: cached,
          errorMessage: null,
        );
      }
    } catch (_) {}
  }

  Future<void> _applyCustomerInfo(CustomerInfo customerInfo) async {
    final ent = _resolveEntitlement(customerInfo);
    final isPremium = ent?.isActive ?? false;

    state = state.copyWith(
      isLoading: false,
      isPremium: isPremium,
      errorMessage: null,
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cacheKey, isPremium);
    } catch (_) {}

    try {
      await _syncSubscriptionStatus(customerInfo, ent);
    } catch (_) {}
  }

  EntitlementInfo? _resolveEntitlement(CustomerInfo customerInfo) {
    final direct = customerInfo.entitlements.all[entitlementId];
    if (direct != null) return direct;
    if (customerInfo.entitlements.active.values.isNotEmpty) {
      return customerInfo.entitlements.active.values.first;
    }
    return null;
  }

  Future<void> _syncSubscriptionStatus(
    CustomerInfo customerInfo,
    EntitlementInfo? ent,
  ) async {
    final userId = int.tryParse(customerInfo.originalAppUserId);
    if (userId == null || userId <= 0) return;

    final isActive = ent?.isActive == true;
    final productId = ent?.productIdentifier ?? '';
    final expiresAt = ent?.expirationDate ?? '';
    final willRenew = ent?.willRenew == true;
    final signature = [
      userId,
      ent?.identifier ?? entitlementId,
      isActive ? 1 : 0,
      productId,
      expiresAt,
      willRenew ? 1 : 0,
    ].join('|');
    if (_lastSyncedSignature == signature) return;

    final payload = jsonEncode({
      'originalAppUserId': customerInfo.originalAppUserId,
      'requestDate': customerInfo.requestDate,
      'activeSubscriptions': customerInfo.activeSubscriptions,
      'allPurchasedProductIdentifiers':
          customerInfo.allPurchasedProductIdentifiers,
      'entitlement':
          ent == null
              ? null
              : {
                'identifier': ent.identifier,
                'isActive': ent.isActive,
                'willRenew': ent.willRenew,
                'productIdentifier': ent.productIdentifier,
                'expirationDate': ent.expirationDate,
              },
    });

    final uri = Uri.parse(
      '${AppConfig.instance.baseUrl}update_subscription_status.php',
    );
    final response = await http.post(
      uri,
      body: {
        'user_id': userId.toString(),
        'entitlement_id': ent?.identifier ?? entitlementId,
        'is_active': isActive ? '1' : '0',
        'product_id': productId,
        'expires_at': expiresAt,
        'will_renew': willRenew ? '1' : '0',
        'payload_json': payload,
      },
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      _lastSyncedSignature = signature;
    }
  }
}
