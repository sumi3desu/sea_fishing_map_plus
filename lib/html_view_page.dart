import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'appconfig.dart';

class HtmlViewPage extends StatefulWidget {
  final String title; // 画面タイトル
  final String url; // 外部から渡すURL（POST時もactionに使用）
  final Map<String, String>? postParams; // POSTで送る場合のフォームデータ（指定時は自動submit）
  const HtmlViewPage({
    super.key,
    required this.title,
    required this.url,
    this.postParams,
  });

  @override
  _HtmlViewPageState createState() => _HtmlViewPageState();
}

class _HtmlViewPageState extends State<HtmlViewPage> {
  late final WebViewController _controller;
  bool _isMounted = false;
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (url) {
                _currentUrl = url;
              },
              onUrlChange: (change) {
                _currentUrl = change.url;
              },
            ),
          )
          ..clearCache(); // キャッシュをクリア

    // asset://assets/... の場合はアセットを読み込む
    if (widget.url.startsWith('asset://assets/')) {
      final assetPath = widget.url.replaceFirst('asset://', '');
      // WebViewController に用意されたアセット読み込みを使用
      _controller.loadFlutterAsset(assetPath);
    } else if (widget.postParams != null && widget.postParams!.isNotEmpty) {
      // POST パラメータが指定された場合は、自己送信フォームで POST するHTMLを生成して読み込む
      final sb = StringBuffer();
      sb.writeln(
        '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"/></head>',
      );
      sb.writeln('<body onload="document.forms[0].submit()">');
      sb.writeln('<form method="POST" action="${widget.url}">');
      widget.postParams!.forEach((k, v) {
        final key = _htmlEscape(k);
        final val = _htmlEscape(v);
        sb.writeln('<input type="hidden" name="$key" value="$val"/>');
      });
      sb.writeln('<noscript><button type="submit">続行</button></noscript>');
      sb.writeln('</form></body></html>');
      _controller.loadHtmlString(sb.toString());
    } else {
      _controller.loadRequest(Uri.parse(widget.url));
    }
  }

  @override
  void dispose() {
    _isMounted = false;
    super.dispose();
  }

  Future<void> _handleBack() async {
    try {
      final isComplete =
          (_currentUrl != null && _currentUrl!.contains('submit_report.php'));
      if (isComplete) {
        if (_isMounted) Navigator.of(context).maybePop();
        return;
      }
      final can = await _controller.canGoBack();
      if (can) {
        await _controller.goBack();
      } else {
        if (_isMounted) Navigator.of(context).maybePop();
      }
    } catch (_) {
      if (_isMounted) Navigator.of(context).maybePop();
    }
  }

  String _htmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        try {
          final isComplete =
              (_currentUrl != null &&
                  _currentUrl!.contains('submit_report.php'));
          if (isComplete) return true; // pop screen
          if (await _controller.canGoBack()) {
            await _controller.goBack();
            return false;
          }
        } catch (_) {}
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: AppConfig.instance.appBarBackgroundColor,
          foregroundColor: AppConfig.instance.appBarForegroundColor,
          leading: BackButton(onPressed: _handleBack),
        ),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
