import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/premium_state_notifier.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'services/revenuecat_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'appconfig.dart';
import 'package:flutter/services.dart';

class PremiumPage extends ConsumerStatefulWidget {
  const PremiumPage({super.key});

  @override
  ConsumerState<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends ConsumerState<PremiumPage> {
  bool _inited = false;
  bool _purchasing = false;
  BannerAd? _bannerAd;
  String? _activeProductId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted && !_inited) {
        _inited = true;
        try {
          await ref.read(premiumStateProvider.notifier).initialize();
        } catch (_) {}
        await _loadActiveProductId();
      }
    });
    _loadBanner();
  }

  void _loadBanner() {
    try {
      final isPremium = ref.read(premiumStateProvider).isPremium;
      if (isPremium) return;
      _bannerAd = BannerAd(
        size: AdSize.banner,
        adUnitId: 'ca-app-pub-3940256099942544/2934735716', // TEST用広告ID
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (mounted) setState(() {});
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
          },
        ),
        request: const AdRequest(),
      )..load();
    } catch (_) {}
  }

  Future<void> _purchasePackage(Package pkg) async {
    if (_purchasing) return;
    setState(() => _purchasing = true);
    try {
      await Purchases.purchasePackage(pkg);
      await ref.read(premiumStateProvider.notifier).refresh();
      await _loadActiveProductId();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('購入が完了しました')));
    } on PlatformException catch (e) {
      // RevenueCat のエラーコードを判定
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (!mounted) return;
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('購入はキャンセルされました。')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('購入エラー: $code')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('購入エラー: $e')));
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _loadActiveProductId() async {
    try {
      final info = await Purchases.getCustomerInfo();
      final ent =
          info.entitlements.active.values.isNotEmpty
              ? info.entitlements.active.values.first
              : null;
      if (!mounted) return;
      setState(() {
        _activeProductId = ent?.productIdentifier;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Widget _statusTag(bool isPurchased) {
    final Color purchasedColor = Colors.indigo.shade900;
    final Color border = isPurchased ? purchasedColor : Colors.grey.shade500;
    final Color bg =
        isPurchased
            ? purchasedColor.withOpacity(0.08)
            : Colors.grey.withOpacity(0.06);
    final String label = isPurchased ? '購入済み' : '未購入';
    final TextStyle style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: isPurchased ? purchasedColor : Colors.black87,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(label, style: style),
    );
  }

  Widget _priceTag(bool purchasing, String priceLabel) {
    if (purchasing) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.shade300),
      ),
      child: Text(
        priceLabel,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(premiumStateProvider);
    final notifier = ref.read(premiumStateProvider.notifier);
    final status = st.isLoading ? '読み込み中' : (st.isPremium ? '購入済み' : '未購入');

    return Scaffold(
      appBar: AppBar(
        title: const Text('プレミアム'),
        backgroundColor: AppConfig.instance.appBarBackgroundColor,
        foregroundColor: AppConfig.instance.appBarForegroundColor,
        toolbarHeight: 0, // タイトルは本文側に自前で表示（バナーの下）
      ),
      body: Column(
        children: [
          if (!st.isPremium && _bannerAd != null)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
          // タイトル行（AppBar の代替）
          Container(
            height: kToolbarHeight,
            color: AppConfig.instance.appBarBackgroundColor,
            child: Row(
              children: [
                BackButton(
                  color: AppConfig.instance.appBarForegroundColor,
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 4),
                Text(
                  'プレミアム',
                  style: TextStyle(
                    color: AppConfig.instance.appBarForegroundColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'プレミアム状態: ' +
                          (st.isPremium
                              ? '購入済み'
                              : (st.isLoading ? '読み込み中' : '未購入')),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if ((st.errorMessage ?? '').isNotEmpty)
                      Text(
                        'エラー: ${st.errorMessage}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    const Text(
                      '提供中のプラン',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    FutureBuilder<Offerings>(
                      future: Purchases.getOfferings(),
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snap.hasError || snap.data == null) {
                          return const Text('プランの取得に失敗しました');
                        }
                        final offerings = snap.data!;
                        final packages = <Package>[];
                        if (offerings.current != null)
                          packages.addAll(offerings.current!.availablePackages);
                        for (final o in offerings.all.values) {
                          for (final p in o.availablePackages) {
                            if (!packages.any(
                              (e) => e.identifier == p.identifier,
                            ))
                              packages.add(p);
                          }
                        }
                        if (packages.isEmpty)
                          return const Text('現在、提供中のプランはありません');
                        return Column(
                          children:
                              packages.map((p) {
                                final sp = p.storeProduct;
                                final bool isPurchased =
                                    (_activeProductId != null &&
                                        _activeProductId == sp.identifier);
                                return Card(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap:
                                        _purchasing
                                            ? null
                                            : () => _purchasePackage(p),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // 1行目: タイトル
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons
                                                    .workspace_premium_outlined,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  sp.title,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          // 2行目: 説明
                                          Text(
                                            sp.description,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              color: Colors.black87,
                                              height: 1.25,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 8),
                                          // 3行目: 左ラベル(購入状態) / 右ラベル(価格)
                                          Row(
                                            children: [
                                              _statusTag(isPurchased),
                                              const Spacer(),
                                              _priceTag(
                                                _purchasing,
                                                '${sp.priceString} で購入',
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
          // 下部固定ボタン群
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed:
                        st.isLoading
                            ? null
                            : () async {
                              await notifier.refresh();
                              final err =
                                  ref.read(premiumStateProvider).errorMessage;
                              if ((err ?? '').isNotEmpty && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('再取得エラー: $err')),
                                );
                              }
                            },
                    icon: const Icon(Icons.refresh),
                    label: const Text('購入情報を再取得'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed:
                        st.isLoading
                            ? null
                            : () async {
                              await notifier.restorePurchases();
                              final s = ref.read(premiumStateProvider);
                              if ((s.errorMessage ?? '').isNotEmpty &&
                                  context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('復元エラー: ${s.errorMessage}'),
                                  ),
                                );
                              } else if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('復元が完了しました')),
                                );
                              }
                            },
                    icon: const Icon(Icons.settings_backup_restore),
                    label: const Text('購入情報を再取得 / 復元'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final uri =
                          Platform.isIOS
                              ? Uri.parse(
                                'https://apps.apple.com/account/subscriptions',
                              )
                              : Uri.parse(
                                'https://play.google.com/store/account/subscriptions',
                              );
                      final ok = await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('サブスク管理ページを開けませんでした')),
                        );
                      }
                    },
                    icon: const Icon(Icons.manage_accounts),
                    label: const Text('プレミアムの閲覧/解約/変更'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _resolveActiveTitle() async {
    try {
      if (!RevenueCatService.isConfigured) {
        await RevenueCatService.waitUntilConfigured(
          timeout: const Duration(seconds: 5),
        );
        if (!RevenueCatService.isConfigured) return '購入済み';
      }
      final info = await Purchases.getCustomerInfo();
      final ent =
          info.entitlements.active.values.isNotEmpty
              ? info.entitlements.active.values.first
              : null;
      final pid = ent?.productIdentifier ?? '';
      if (pid.isEmpty) return '購入済み';
      try {
        final offerings = await Purchases.getOfferings();
        final pkgs = <Package>[];
        if (offerings.current != null)
          pkgs.addAll(offerings.current!.availablePackages);
        for (final o in offerings.all.values) {
          for (final p in o.availablePackages) {
            if (!pkgs.any((e) => e.identifier == p.identifier)) pkgs.add(p);
          }
        }
        for (final p in pkgs) {
          if (p.storeProduct.identifier == pid) {
            final title = p.storeProduct.title;
            return title.isNotEmpty ? '購入済み（$title）' : '購入済み';
          }
        }
      } catch (_) {}
      final lpid = pid.toLowerCase();
      if (lpid.contains('month')) return '購入済み（月額）';
      if (lpid.contains('year')) return '購入済み（年額）';
      return '購入済み（$pid）';
    } catch (_) {
      return '購入済み';
    }
  }
}
