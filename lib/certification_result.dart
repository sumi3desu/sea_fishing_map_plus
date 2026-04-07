import 'package:flutter/material.dart';
//import 'login.dart';
// TORIAEZU import 'main_page.dart'; // ADDED: 設定画面に戻るため HomeScreen を参照
import 'appconfig.dart';
import 'main.dart';

class CertificationResult extends StatelessWidget {
  final String action;
 CertificationResult({Key? key, required this.action,
}) : super(key: key);

  @override
  Widget build(BuildContext context) {
      // action の値に応じたタイトルやメッセージを設定
    String appBarTitle;
    String bodyMessage;
    String buttonText;

    switch (action) {
      case "new_user":
        appBarTitle = "アカウント登録結果";
        bodyMessage = "アカウント登録が正常に完了しました。";
        buttonText = "設定へ";
        break;
      case "edit_mail":
        appBarTitle = "メールアドレス変更結果";
        bodyMessage = "メールアドレス変更が正常に完了しました。";
        buttonText = "設定へ";
        break;
      case "edit_password":
        appBarTitle = "パスワード変更結果";
        bodyMessage = "パスワード変更が完了しました。";
        buttonText = "設定へ";
        break;
      default:
        appBarTitle = "認証結果";
        bodyMessage = "操作が正常に完了しました。";
        buttonText = "設定へ";
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        backgroundColor: AppConfig.instance.appBarBackgroundColor,
        foregroundColor: AppConfig.instance.appBarForegroundColor,
        automaticallyImplyLeading: false, // 戻る＜は表示しない
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              bodyMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 64),
                        // 認証ボタン（横幅統一）
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.6,
              child: ElevatedButton(
                onPressed: () {
                  // 最初のメイン画面（MainPage）へ戻る（スタックをクリア）
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MainPage(title: '海釣りMAP+', initialIndex: 3)),
                    (Route<dynamic> route) => false,
                  );
                },
                   style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.instance.buttonBackgroundColor,
                  foregroundColor: AppConfig.instance.buttonForegroundColor,
                    minimumSize: const Size.fromHeight(48),
                  ),
               child: Text(buttonText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
