import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/premium_state_notifier.dart' as prem;
import 'appconfig.dart';

class InformationPage extends StatefulWidget {
  final String title = '情報'; // 画面タイトル
  final String url =
      '${AppConfig.instance.baseUrl}disclaimer.html'; // 外部から渡すURL
  InformationPage({super.key});

  @override
  _InformationPageState createState() => _InformationPageState();
}

class _InformationPageState extends State<InformationPage> {
  late final WebViewController _controller;
  BannerAd? _bannerAd;

  @override
  void initState() {
    super.initState();
    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..clearCache() // キャッシュをクリア
          ..loadRequest(Uri.parse(widget.url)); // コンストラクタで渡したURLを使用
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Consumer(
              builder: (context, ref, _) {
                final isPremium =
                    ref.watch(prem.premiumStateProvider).isPremium;
                if (isPremium) return const SizedBox.shrink();
                if (_bannerAd == null) {
                  _bannerAd = BannerAd(
                    size: AdSize.banner,
                    adUnitId: 'ca-app-pub-3940256099942544/2934735716',
                    listener: BannerAdListener(
                      onAdLoaded: (_) => setState(() {}),
                      onAdFailedToLoad: (ad, err) {
                        ad.dispose();
                      },
                    ),
                    request: const AdRequest(),
                  )..load();
                }
                if (_bannerAd == null) return const SizedBox.shrink();
                return Container(
                  alignment: Alignment.center,
                  width: _bannerAd!.size.width.toDouble(),
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                );
              },
            ),
            Container(
              height: kToolbarHeight,
              color: Colors.black,
              child: Row(
                children: [
                  BackButton(
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
    );
  }
}
