import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:io' show Platform;
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:async';
import 'constants.dart';
import 'appconfig.dart';

class InfoScreen extends StatefulWidget {
  const InfoScreen({Key? key}) : super(key: key);

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _error = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _cancelTimeout();
            if (mounted) {
              setState(() {
                _loading = false;
                _error = false;
              });
            }
          },
          onWebResourceError: (_) {
            _cancelTimeout();
            if (mounted) {
              setState(() {
                _loading = false;
                _error = true;
              });
            }
          },
        ),
      );
    _loadInitialUrl();
  }

  Future<void> _loadInitialUrl() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    _startTimeout();
    try {
      final info = await PackageInfo.fromPlatform();
      final ver = '${info.version}+${info.buildNumber}';
      final platform = Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other');
      final base = Uri.parse('${AppConfig.instance.baseUrl}siowadou_pro_info.php');
      final uri = base.replace(queryParameters: {
        'format': 'html',
        'app': ver,
        'platform': platform,
        // cache-bust to avoid stale content in WebView cache
        'ts': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      await _controller.loadRequest(uri);
    } catch (_) {
      // Fallback: try loading without query params; timeout watcher will handle offline
      await _controller.loadRequest(Uri.parse('${AppConfig.instance.baseUrl}siowadou_pro_info.php?format=html'));
    }
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(kHttpTimeout, () {
      if (!mounted) return;
      if (_loading) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    });
  }

  void _cancelTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  @override
  void dispose() {
    _cancelTimeout();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // タイトル行（AppBar の代替）
        Container(
          height: kToolbarHeight,
          color: Colors.black,
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  '情報',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_loading)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x10FFFFFF),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              if (!_loading && _error)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xF0FFFFFF),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            const Text(
                              '通信ができませんでした。\n機内モードを解除するか、通信環境の良い場所でお試しください。',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _loadInitialUrl,
                              icon: const Icon(Icons.refresh),
                              label: const Text('再試行'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
