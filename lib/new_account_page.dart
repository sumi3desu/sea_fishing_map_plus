//import 'dart:convert';
import 'package:flutter/material.dart';
//import 'package:http/http.dart' as http;
//import 'dart:math';
import 'certification_mail.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/premium_state_notifier.dart' as prem;
import 'common.dart';
import 'error_message.dart';
import 'appconfig.dart';
import 'main.dart';
import 'log_print.dart';

class NewAccountPage extends ConsumerStatefulWidget {
  const NewAccountPage({
    super.key,
    this.returnToInputPost = false,
    this.initialEmail,
    this.recoveryMode = false,
    this.authPurposeLabel,
  });
  final bool returnToInputPost;
  final String? initialEmail;
  final bool recoveryMode;
  final String? authPurposeLabel;

  @override
  _NewAccountPageState createState() => _NewAccountPageState();
}

class _NewAccountPageState extends ConsumerState<NewAccountPage> {
  BannerAd? _bannerAd;
  // メール入力のコントローラー（パスワード入力は廃止）
  final TextEditingController _mailaddressController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();

  // 表示するエラーメッセージ
  String? _errorMessage;

  // 画面下に数秒間エラーを表示するスナックバー
  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _mailaddressController.text = widget.initialEmail?.trim() ?? '';
  }

  String _purposeLeadText() {
    switch (widget.authPurposeLabel?.trim()) {
      case '投稿':
        return '「投稿」するためにはアカウント登録を行なってください。';
      case 'お気に入り':
        return '「お気に入り」の登録をするためにはアカウント登録を行なってください。';
      case '釣り日記':
        return '「釣り日記」状態にするためにはアカウント登録を行なってください。';
      case '釣り場登録':
        return '「釣り場登録」をするためにはアカウント登録を行なってください。';
      case '低評価':
        return '「低評価」をするためにはアカウント登録を行なってください。';
      default:
        return 'アカウントを登録すると、機種変更やアプリの再インストール時にお気に入り(釣り場)の引き継ぎができます。';
    }
  }

  String _topCardMessage() {
    if (widget.recoveryMode) {
      return '以前利用していたメールアドレスで確認コード認証を行うと、以前のアカウントへ戻せます。';
    }
    final label = widget.authPurposeLabel?.trim() ?? '';
    if (label.isNotEmpty) {
      return '${_purposeLeadText()}\nメールアドレスとニックネームを入力し、届いたメールの認証コードを入力してください。';
    }
    return _purposeLeadText();
  }

  String _subMessage() {
    if (widget.recoveryMode) {
      return '同じメールアドレスで認証すると、以前のユーザIDを優先して復元します。';
    }
    switch (widget.authPurposeLabel?.trim()) {
      case '投稿':
        return 'この画面でアカウント登録を行うと、そのまま「投稿」の操作へ戻れます。';
      case 'お気に入り':
        return 'この画面でアカウント登録を行うと、そのまま「お気に入り」の登録へ戻れます。';
      case '釣り日記':
        return 'この画面でアカウント登録を行うと、そのまま「釣り日記」状態へ切り替えられます。';
      case '釣り場登録':
        return 'この画面でアカウント登録を行うと、そのまま「釣り場登録」の操作へ戻れます。';
      case '低評価':
        return 'この画面でアカウント登録を行うと、そのまま「低評価」の操作へ戻れます。';
      default:
        return 'アカウントの登録を行うことで機種変更時にもお気に入り(釣り場)の引き継ぎができます。';
    }
  }

  // 「登録」ボタン押下時の処理
  Future<void> _register() async {
    setState(() {
      _errorMessage = null;
    });

    String email = _mailaddressController.text.trim();
    String nickname = _nicknameController.text.trim();
    if (nickname.length > 12) nickname = nickname.substring(0, 12);

    // メールアドレス入力空チェック
    if (email.isEmpty) {
      final msg = ErrorMessage.instance.pleaseInputMailAddress;
      setState(() {
        // "メールアドレスを入力してください。"
        _errorMessage = msg;
      });
      _showErrorSnack(msg);
      return;
    }
    // メール形式チェック
    if (!Common.instance.isValidEmail(email)) {
      final msg = ErrorMessage.instance.pleaseInputValidMailAddress;
      setState(() {
        //  = "有効なメールアドレスを入力してください。"
        _errorMessage = msg;
      });
      _showErrorSnack(msg);
      return;
    }

    // パスワード入力・検証は廃止

    // 全てのチェックをパスした場合、登録処理を実行
    logPrint("Registration successful for email: $email");

    try {
      // CheckRegistUser でサーバーにチェックを依頼（UUID 同送）
      // user_info_kakomongo_key から UUID を取得（未生成なら生成）
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final responseData = await Common.instance.checkRegistUser(
        email,
        info.uuid,
      );
      // サーバーからの返答 ['result']
      // unregist: 未登録
      // registed: すでに同一メールアドレスユーザあり
      // temporary: 仮登録状態ユーザあり
      // error: 入力情報不正　(無効なメールアドレス形式、パスワード不正)

      // サーバーの戻り値は環境により表記ゆれの可能性があるため網羅的に判定
      final result = (responseData['result'] ?? '').toString().toLowerCase();
      final reasonText = (responseData['reason'] ?? '').toString();
      // 既登録（機種変想定）や仮登録、未登録のいずれでも確認コード送信を許可
      final proceedValues = {
        'unregisted', // 既存コード想定
        'unregist', // 表記ゆれ
        'unregistered', // 英語正書法
        'temporary', // 仮登録は確認コード入力へ誘導
        'registed', // 既登録（機種変想定）でも確認コード送付して本人確認
        'registered', // 英語表記ゆれ
      };
      final shouldProceed =
          proceedValues.contains(result) || reasonText.contains('機種変');

      if (shouldProceed) {
        // 既存ユーザ・仮登録の場合はサーバから正規のUUIDを取得して保存（再インストール対策）
        if (result == 'registed' ||
            result == 'registered' ||
            result == 'temporary' ||
            result == 'not_match_uuid' ||
            reasonText.contains('機種変')) {
          try {
            final server = await getUserInfoFromServerByEmail(email);
            if (server != null) {
              final current = await loadUserInfo() ?? await getOrInitUserInfo();
              final merged = current.copyWith(
                userId: server.userId != 0 ? server.userId : current.userId,
                email: email,
                uuid: server.uuid.isNotEmpty ? server.uuid : current.uuid,
                status:
                    server.status.isNotEmpty ? server.status : current.status,
                createdAt:
                    server.createdAt.isNotEmpty
                        ? server.createdAt
                        : current.createdAt,
                nickName: current.nickName,
                reportsBlocked: server.reportsBlocked,
                reportsBlockedUntil: server.reportsBlockedUntil,
                reportsBlockedReason: server.reportsBlockedReason,
                postsBlocked: server.postsBlocked,
                postsBlockedUntil: server.postsBlockedUntil,
                postsBlockedReason: server.postsBlockedReason,
                role: server.role ?? current.role,
                canReport: server.canReport,
                photoUrl: server.photoUrl ?? current.photoUrl,
                photoVersion: server.photoVersion ?? current.photoVersion,
                clearReportsBlockedUntil: server.reportsBlockedUntil == null,
                clearReportsBlockedReason: server.reportsBlockedReason == null,
                clearPostsBlockedUntil: server.postsBlockedUntil == null,
                clearPostsBlockedReason: server.postsBlockedReason == null,
              );
              await saveUserInfo(merged);
            }
          } catch (_) {}
        }
        // 確認コード取得
        String authenticationNumber = Common.instance.getRandomNumber();

        final responseMailData = await Common.instance.sendmail(
          email,
          authenticationNumber,
        );
        if (responseMailData['result'] == "OK") {
          // 次の6桁入力画面に遷移
          if (!mounted) return; // 非マウント時は遷移しない
          final res = await Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => CertificationMail(
                    email: email,
                    action: "new_user",
                    authenticationNumber: authenticationNumber,
                    nickName: nickname,
                    returnToInputPost: widget.returnToInputPost,
                  ),
            ),
          );
          // 認証結果から true が返ってきたら、この画面を閉じて元の投稿入力へ戻る
          if (res == true && mounted) {
            Navigator.pop(context, true);
            return;
          }
        } else {
          final msg = responseMailData['reason'];
          setState(() {
            _errorMessage = msg;
          });
          _showErrorSnack(msg);
        }
      } else {
        // 返された配列の内容をダイアログで表示
        /*showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text("登録結果"),
              content: Text(
                "メール: ${responseData['mail']}\n"
                "結果: ${responseData['result']}\n"
                "理由: ${responseData['reason']}"
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              ],
            );
          },
        );
        */
        final msg =
            responseData['reason'] ?? '登録できませんでした（${responseData['result']}）';
        setState(() {
          _errorMessage = msg;
        });
        _showErrorSnack(msg);
      }
    } catch (e) {
      final msg = ErrorMessage.instance.exceptionCheckMail(e);
      setState(() {
        // "メールアドレスチェック処理でエラーが発生しました。[$e]"
        _errorMessage = msg;
      });
      _showErrorSnack(msg);
    }
  }

  @override
  void dispose() {
    _mailaddressController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.read(prem.premiumStateProvider).isPremium;
    if (!isPremium) {
      _bannerAd ??= BannerAd(
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Consumer(
              builder: (context, ref, _) {
                final isPremium =
                    ref.watch(prem.premiumStateProvider).isPremium;
                if (isPremium || _bannerAd == null)
                  return const SizedBox.shrink();
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
                        widget.recoveryMode ? 'アカウント復元' : 'アカウント設定',
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  // キーボード表示時にもスクロールできるように
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 64.0),
                      // 上部インフォカード（iボタンの代替表示）
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade400),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: Text(
                            _topCardMessage(),
                            style: const TextStyle(fontSize: 13, height: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      // メール入力
                      TextField(
                        controller: _mailaddressController,
                        decoration: const InputDecoration(
                          labelText: "メールアドレス",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      // パスワード入力は廃止
                      const SizedBox(height: 12.0),
                      // 補足文（確認コード送信案内）
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'このメールアドレス宛に6桁の確認コードを送信します。',
                          style: TextStyle(
                            fontSize: 13.0,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ),
                      // ADDED: アカウント登録の案内文（メール入力と次へボタンの間に表示）
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _subMessage(),
                          style: const TextStyle(
                            fontSize: 13.0,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      // ニックネーム
                      TextField(
                        controller: _nicknameController,
                        maxLength: 12,
                        decoration: const InputDecoration(
                          labelText: 'ニックネーム',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '本名など個人情報は入力しないでください（投稿時に表示されます）',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20.0),
                      // 登録ボタン（横幅半分）
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.6,
                        child: ElevatedButton(
                          onPressed: () async {
                            // 送信直前にニックネームをトリム＆12桁に丸め
                            var nn = _nicknameController.text.trim();
                            if (nn.length > 12) nn = nn.substring(0, 12);
                            _nicknameController.text = nn;
                            await _register();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                AppConfig.instance.buttonBackgroundColor,
                            foregroundColor:
                                AppConfig.instance.buttonForegroundColor,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text("次へ（確認コードを送信）"),
                        ),
                      ),
                      const SizedBox(height: 16.0),

                      // 戻るボタン（横幅半分）
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.6,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                AppConfig.instance.buttonBackgroundColor,
                            foregroundColor:
                                AppConfig.instance.buttonForegroundColor,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text("戻る"),
                        ),
                      ),
                      // エラーメッセージ表示
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 24.0),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 16.0,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
