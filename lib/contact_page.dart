import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({Key? key}) : super(key: key);

  @override
  _ContactPageState createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  final _formKey = GlobalKey<FormState>();

  String _name = '';
  String _email = '';
  String _message = '';

  // メール送信用のヘルパー関数
  Future<void> _sendEmail() async {
    // 問い合わせ先のメールアドレスを指定してください
    const String emailAddress = 'support@bouzer.jp';

    // メールの件名と本文を設定
    final String subject = 'お問い合わせ';
    final String body =
        '【お問い合わせ内容】\n'
        '名前: $_name\n'
        'メールアドレス: $_email\n'
        '内容:\n$_message';

    // Query パラメータとしてエンコード
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: emailAddress,
      query: _encodeQueryParameters(<String, String>{
        'subject': subject,
        'body': body,
      }),
    );

    // メールクライアントを起動
    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('メールクライアントが起動できませんでした')));
    }
  }

  // query パラメータ用のエンコード関数
  String _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
  }

  // フォーム送信処理
  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState!.save();
      _sendEmail();
      // 送信完了メッセージを Snackbar で表示
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('メール送信のため、メールアプリが起動します')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('お問い合わせ')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // お名前入力フィールド
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'お名前',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'お名前を入力してください';
                  }
                  return null;
                },
                onSaved: (value) => _name = value!.trim(),
              ),
              const SizedBox(height: 16),
              // メールアドレス入力フィールド
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'メールアドレス',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'メールアドレスを入力してください';
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
                    return '有効なメールアドレスを入力してください';
                  }
                  return null;
                },
                onSaved: (value) => _email = value!.trim(),
              ),
              const SizedBox(height: 16),
              // お問い合わせ内容入力フィールド（複数行）
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'お問い合わせ内容',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'お問い合わせ内容を入力してください';
                  }
                  return null;
                },
                onSaved: (value) => _message = value!.trim(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  child: const Text('送信'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
