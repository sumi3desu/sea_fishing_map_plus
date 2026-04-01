import 'package:flutter/material.dart';

class DisclaimerPage extends StatefulWidget {
  const DisclaimerPage({Key? key}) : super(key: key);

  @override
  _DisclaimerPageState createState() => _DisclaimerPageState();
}

class _DisclaimerPageState extends State<DisclaimerPage> {
  bool _isChecked = false;

  @override
  Widget build(BuildContext context) {
    const String disclaimerText = '''
【免責事項】

航海の用に供する公式の潮汐の推算は、航海等における混乱を防ぐため、各国の水路機関が責任を持って行うことになっており、海上保安庁海洋情報部で毎年刊行している「潮汐表」が公式の潮汐推算値です。
従って、本プログラムを使用した計算は、正確性、完全性、有用性について保証するものではなく「潮汐表」の代替物にはなりません。
航海には必ず海上保安庁海洋情報部発行の「潮汐表」を使用してください。

本アプリケーションの使用により生じた直接的または間接的な損害について、当社は一切の責任を負いません。

利用者ご自身の責任においてご利用ください。
''';

    return Scaffold(
      appBar: AppBar(
        title: const Text('情報'),
        backgroundColor: Colors.black, //AppConfig.instance.appBarBackgroundColor,
        foregroundColor: Colors.white,//AppConfig.instance.appBarForegroundColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 免責事項の文章をスクロール可能な領域に配置
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  disclaimerText,
                  style: const TextStyle(fontSize: 16.0),
                ),
              ),
            ),
            // チェックボックスとラベル
            Row(
              children: [
                Checkbox(
                  value: _isChecked,
                  onChanged: (bool? value) {
                    setState(() {
                      _isChecked = value ?? false;
                    });
                  },
                ),
                const Expanded(
                  child: Text(
                    '上記内容に同意します。',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            // 確認ボタン（チェック済みの場合のみ有効）
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isChecked
                    ? () {
                      }
                    : null,
                child: const Text('確認'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
