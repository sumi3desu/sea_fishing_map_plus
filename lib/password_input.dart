import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'certification_result.dart';
import 'common.dart';
import 'error_message.dart';
import 'appconfig.dart';
// ADDED: UUID を取得するために main.dart を参照
import 'main.dart';

class PasswordInput extends StatefulWidget {
  final String email;
  const PasswordInput({Key? key, required this.email}) : super(key: key);

  @override
  _PasswordInputState createState() => _PasswordInputState();
}

class _PasswordInputState extends State<PasswordInput> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // 表示するエラーメッセージ
  String? _errorMessage;

  // サーバーにユーザー登録を依頼する処理
  Future<Map<String, dynamic>> RegistPassword(
    String email,
    String password,
  ) async {
    // ADDED: UUID を user_info から取得
    final info = await loadUserInfo() ?? await getOrInitUserInfo();
    final response = await http.post(
      Uri.parse('${AppConfig.instance.baseUrl}spark_regist.php'),
      body: {
        'mail': email,
        'password': password,
        // ADDED: uuid を追加
        'uuid': info.uuid,
        'action': 'edit_password',
      },
    );

    if (response.statusCode == 200) {
      // サーバー側で JSON エンコードされた配列を返す前提
      return json.decode(response.body);
    } else if (response.statusCode == 500) {
      throw Exception(json.decode(response.body)['reason']);
    } else {
      throw Exception(
        'Failed to register user. Status code: ${response.statusCode}',
      );
    }
  }

  // 「登録」ボタン押下時の処理
  Future<void> _resetpassword() async {
    setState(() {
      _errorMessage = null;
    });

    String password = _passwordController.text;
    String confirmPassword = _confirmPasswordController.text;

    // パスワードが未入力の場合
    if (password.isEmpty) {
      setState(() {
        // "パスワードを入力してください。"
        _errorMessage = ErrorMessage.instance.pleaseInputPassword;
      });
      return;
    }
    // パスワード確認が未入力の場合
    if (confirmPassword.isEmpty) {
      setState(() {
        // "パスワード確認を入力してください。"
        _errorMessage = ErrorMessage.instance.pleaseInputConfirmPassword;
      });
      return;
    }
    // パスワードとパスワード確認が一致しているか
    if (password != confirmPassword) {
      setState(() {
        // "パスワードが一致していません。"
        _errorMessage = ErrorMessage.instance.notMatchPassword;
      });
      return;
    }

    // パスワードが推奨パターンに沿っているか
    if (!Common.instance.isValidPassword(password)) {
      setState(() {
        // "パスワードは8文字以上で、大文字・小文字・数字・特殊文字(@\$!%*?&)を各1文字以上含む必要があります。"
        _errorMessage = ErrorMessage.instance.pleaseInputValidPassword;
      });
      return;
    }

    try {
      // パスワード更新
      final responseData = await RegistPassword(widget.email, password);
      // サーバーからの返答 ['result']
      // unregist: 未登録
      // registed: すでに同一メールアドレスユーザあり
      // error: 入力情報不正　(無効なメールアドレス形式、パスワード不正)

      if (responseData['result'] == "OK") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => CertificationResult(action: "edit_password"),
          ),
        );
      } else {
        setState(() {
          _errorMessage = responseData['reason'];
        });
      }
    } catch (e) {
      setState(() {
        // "登録処理でエラーが発生しました。[$e]"
        _errorMessage = ErrorMessage.instance.exceptionPasswordRegist(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("新パスワード設定"),
        backgroundColor: AppConfig.instance.appBarBackgroundColor,
        foregroundColor: AppConfig.instance.appBarForegroundColor,
        automaticallyImplyLeading: false, // 戻る＜は表示しない
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "新しく設定するパスワードを入力して下さい。",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32.0),
            // パスワード入力
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: "パスワード",
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16.0),
            // パスワード確認入力
            TextField(
              controller: _confirmPasswordController,
              decoration: const InputDecoration(
                labelText: "パスワード確認",
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 32.0),
            const Text(
              "※ パスワードは8文字以上で、大文字・小文字・数字・特殊文字を各1文字以上含む必要があります",
              style: TextStyle(fontSize: 12.0, color: Colors.grey),
            ),
            const SizedBox(height: 64.0),

            // 登録ボタン（横幅半分）
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.6,
              child: ElevatedButton(
                onPressed: _resetpassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.instance.buttonBackgroundColor,
                  foregroundColor: AppConfig.instance.buttonForegroundColor,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text("設　定"),
              ),
            ),
            // エラーメッセージ表示
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 16.0),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
