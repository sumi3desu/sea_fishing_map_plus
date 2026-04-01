import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

class InfoPage extends StatefulWidget {
  const InfoPage({Key? key}) : super(key: key);

  @override
  _InfoPageState createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  String versionInfo = "";
  Future<void> _launchReviewPage() async {
    // Apple Store のレビュー投稿ページの URL 形式
    final Uri reviewUri = Uri.parse(
      "itms-apps://itunes.apple.com/app/6744795665?action=write-review",
    );
    if (await canLaunchUrl(reviewUri)) {
      await launchUrl(reviewUri);
    } else {
      // URL を開けなかった場合のエラーハンドリング
      debugPrint("Could not launch review page");
    }
  }

  Future<void> getAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    versionInfo = '${info.version} [${info.buildNumber}]';
  }

  void initState() {
    super.initState();
    getAppVersion();
  }

  @override
  Widget build(BuildContext context) {
    const String disclaimerText = '''
航海の用に供する公式の潮汐の推算は、航海等における混乱を防ぐため、各国の水路機関が責任を持って行うことになっており、海上保安庁海洋情報部で毎年刊行している「潮汐表」が公式の潮汐推算値です。
従って、本プログラムを使用した計算は、正確性、完全性、有用性について保証するものではなく「潮汐表」の代替物にはなりません。
航海には必ず海上保安庁海洋情報部発行の「潮汐表」を使用してください。
本アプリケーションの使用により生じた直接的または間接的な損害について、当社は一切の責任を負いません。
利用者ご自身の責任においてご利用ください。''';

    return Scaffold(
      appBar: AppBar(
        title: const Text("情報"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 24),

          // アプリケーションのカテゴリー
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "アプリケーション",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            title: const Text("バージョン"),
            trailing: Text(
              versionInfo,
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.right,
            ),
            onTap: null, // 表示のみ
          ),
          // 「レビューを書く」を追加
          ListTile(
            title: const Text("レビューを書く"),
            trailing: const Icon(Icons.chevron_right),
            onTap: _launchReviewPage,
          ),

          // 免責事項カテゴリー
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "免責事項",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(disclaimerText, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
