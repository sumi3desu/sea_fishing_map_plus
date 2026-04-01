import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'appconfig.dart';

class InformationPage extends StatefulWidget {
  final String title = '情報'; // 画面タイトル
  final String url = '${AppConfig.instance.baseUrl}disclaimer.html';  // 外部から渡すURL
  InformationPage({super.key});

  @override
  _InformationPageState createState() => _InformationPageState();
}

class _InformationPageState extends State<InformationPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..clearCache() // キャッシュをクリア
      ..loadRequest(Uri.parse(widget.url));  // コンストラクタで渡したURLを使用
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black, //AppConfig.instance.appBarBackgroundColor,
        foregroundColor: Colors.white,//AppConfig.instance.appBarForegroundColor,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
