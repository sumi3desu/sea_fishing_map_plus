import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  static const String entitlementId = 'premium';

  Future<void> initialize() async {
    if (!_listenerRegistered) {
      Purchases.addCustomerInfoUpdateListener(_handleCustomerInfoUpdate);
      _listenerRegistered = true;
    }
    // まずはキャッシュを即時反映（起動直後でもUIで参照できるように）
    await _loadCached();
    // RevenueCatのconfigure完了を待つ（短いタイムアウト）
    await RevenueCatService.waitUntilConfigured(timeout: const Duration(seconds: 5));
    if (!RevenueCatService.isConfigured) {
      state = state.copyWith(isLoading: false, errorMessage: '未初期化（後ほど再取得してください）');
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      if (!RevenueCatService.isConfigured) {
        await RevenueCatService.waitUntilConfigured(timeout: const Duration(seconds: 5));
        if (!RevenueCatService.isConfigured) {
          state = state.copyWith(isLoading: false, errorMessage: '未初期化');
          return;
        }
      }
      final customerInfo = await Purchases.getCustomerInfo();
      final isPremium =
          customerInfo.entitlements.all[entitlementId]?.isActive ?? false;

      state = state.copyWith(
        isLoading: false,
        isPremium: isPremium,
        errorMessage: null,
      );
      // キャッシュ更新
      try { final prefs = await SharedPreferences.getInstance(); await prefs.setBool(_cacheKey, isPremium); } catch (_) {}
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  void _handleCustomerInfoUpdate(CustomerInfo customerInfo) {
    final isPremium =
        customerInfo.entitlements.all[entitlementId]?.isActive ?? false;

    state = state.copyWith(
      isLoading: false,
      isPremium: isPremium,
      errorMessage: null,
    );
  }

  Future<void> restorePurchases() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      if (!RevenueCatService.isConfigured) {
        await RevenueCatService.waitUntilConfigured(timeout: const Duration(seconds: 5));
        if (!RevenueCatService.isConfigured) {
          state = state.copyWith(isLoading: false, errorMessage: '未初期化');
          return;
        }
      }
      final customerInfo = await Purchases.restorePurchases();
      final isPremium =
          customerInfo.entitlements.all[entitlementId]?.isActive ?? false;

      state = state.copyWith(
        isLoading: false,
        isPremium: isPremium,
        errorMessage: null,
      );
      // キャッシュ更新
      try { final prefs = await SharedPreferences.getInstance(); await prefs.setBool(_cacheKey, isPremium); } catch (_) {}
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_cacheKey)) {
        final cached = prefs.getBool(_cacheKey) ?? false;
        state = state.copyWith(isLoading: false, isPremium: cached, errorMessage: null);
      }
    } catch (_) {}
  }
}
