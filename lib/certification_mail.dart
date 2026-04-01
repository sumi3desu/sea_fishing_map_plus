import 'dart:async';
import 'dart:convert';
//import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'certification_result.dart';
import 'password_input.dart';
import 'common.dart';
import 'appconfig.dart';
import 'error_message.dart';
// ADDED: UUID 取得（loadUserInfo/getOrInitUserInfo）で使用
import 'main.dart';
// ADDED: 設定画面の再読み込みのために userInfoProvider を無効化
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'constants.dart';

// タイマーの継続時間を定数として定義（単位は秒）
// CHANGED: タイムアウトを 1分 → 3分 に延長
const int kTimerDurationSeconds = 180; // 3分
// 6桁確認コード（前対応済み）
const int kCodeLength = 6; // 確認コード桁数
// ADDED: 再送関連（クールダウン・上限回数）
const int kResendCooldownSec = 45; // 再送クールダウン秒数
const int kMaxResend = 3; // 再送最大回数
// ADDED: 認証ミス上限
const int kMaxAttempts = 5; // 1コードあたりの最大試行回数

// CHANGED: ボタン幅の共通係数（既存: 0.6 → 拡大）
const double kButtonWidthFactor = 0.9; // 画面幅の90% に拡大し文言の折返しを抑制

/// すでに数値が入力されている場合、入力された最新の数字で上書きするフォーマッター
class SingleDigitReplaceFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    // 新たな入力で文字列が2文字以上になった場合、最後の1文字のみを採用
    if (newValue.text.length > 1) {
      final String newText = newValue.text.substring(newValue.text.length - 1);
      return TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
    return newValue;
  }
}

class CertificationMail extends StatefulWidget {
  final String email;
  final String action;
  String authenticationNumber;
  final String? nickName; // 追加: ニックネーム

  CertificationMail({
    Key? key,
    required this.email,
    required this.action,
    required this.authenticationNumber,
    this.nickName,
  }) : super(key: key);

  @override
  _CertificationMailState createState() => _CertificationMailState();
}

class _CertificationMailState extends State<CertificationMail> {
  // タイマー関連
  Timer? _timer;
  int _remainingSeconds = kTimerDurationSeconds; // 初期値は定数から
  String _timeUpMessage = ""; // タイムアップ時のメッセージ

  // 送信状況のメッセージ（指定メール送信時または再送信時に表示する）
  String _sendStatusMessage = "メールアドレス宛に6桁の確認コードを送信しました。";

  // CHANGED: 再送回数は定数で管理（最大 kMaxResend）
  int _resendCount = 0;
  // ADDED: 再送クールダウン残秒
  int _resendCooldown = 0;

  // 各桁の入力用のTextEditingControllerを用意
  final List<TextEditingController> _controllers =
      List.generate(kCodeLength, (_) => TextEditingController());
  // TextField用のFocusNode（カーソル表示用）
  final List<FocusNode> _childFocusNodes = List.generate(kCodeLength, (_) => FocusNode());

  String _errorMessage = '';
  // ADDED: 確認失敗回数とロック状態
  int _attempts = 0;
  bool _locked = false;
  //bool _isVerified = false; // 認証成功かどうか

  @override
  void initState() {
    super.initState();
    // CHANGED: 1秒ごとに残り時間と再送クールダウンを更新
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      bool shouldSet = false;
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        shouldSet = true;
      }
      if (_resendCooldown > 0) {
        _resendCooldown--;
        shouldSet = true;
      }
      if (shouldSet) setState(() {});
      if (_remainingSeconds <= 0) {
        setState(() {
          // CHANGED: タイムアップ時に既存の失敗メッセージを消去
          _timeUpMessage = "タイムアップです。";
          _errorMessage = '';
        });
        timer.cancel();
      }
    });

    // 各 _childFocusNodes にリスナーを登録し、フォーカス時にカーソル位置をテキスト末尾に設定する
    for (int i = 0; i < _childFocusNodes.length; i++) {
      _childFocusNodes[i].addListener(() {
        if (_childFocusNodes[i].hasFocus) {
          final text = _controllers[i].text;
          _controllers[i].selection =
              TextSelection.collapsed(offset: text.length);
        }
      });
    }

    // 画面起動後、最初の KeyboardListener にフォーカスをリクエスト
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // CHANGED: 直接 TextField にフォーカスしてキーボードのちらつきを抑制
      _childFocusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _childFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  // ADDED: 全桁入力済みか
  bool _isCodeFilled() => _controllers.every((c) => c.text.length == 1);

  Future<void> _verifyAuthenticationCode() async {
    if (_locked) return; // 上限到達時は何もしない
    final code = _controllers.map((c) => c.text).join();
    if (code == widget.authenticationNumber) {
      if (widget.action == "edit_password") {
        // password
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => PasswordInput(email: widget.email)),
        );
      } else if (widget.action == "edit_mail") {
         try {
          final info = await loadUserInfo() ?? await getOrInitUserInfo();

          final response = await http.post(
            Uri.parse('${AppConfig.instance.baseUrl}user_regist.php'),
            body: {
              'new_mail': widget.email,
              'mail': AppConfig.instance.mail,
              'action': "edit_mail",
              'uuid': info.uuid, // ADDED
             },
          );
          final data = json.decode(response.body);
          if (response.statusCode == 200) {
            if (data['result'] == "OK") {
              // 保持しているメールアドレス更新
              AppConfig.instance.mail = widget.email;
              // ADDED: UserInfo も更新し、Provider を無効化して設定画面に反映
              try {
                final current = await loadUserInfo() ?? await getOrInitUserInfo();
                final updated = UserInfo(
                  userId: current.userId,
                  email: widget.email,
                  uuid: current.uuid,
                  status: current.status,
                  createdAt: current.createdAt,
                  refreshToken: current.refreshToken,
                  nickName: current.nickName,
                );
                await saveUserInfo(updated);
                // Invalidate provider cache to force reload on Settings
                final container = ProviderScope.containerOf(context, listen: false);
                container.invalidate(userInfoProvider);
              } catch (_) {}
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => CertificationResult(action: "edit_mail")),
              );
            } else {
              setState(() {
                _errorMessage = ErrorMessage.instance.exceptionMailRegist(data['reason']);
              });
            }
          } else {
            setState(() {
              _errorMessage = ErrorMessage.instance.exceptionMailRegist(data['reason']);
            });
          }
        } catch (e) {
          setState(() {
            _errorMessage = ErrorMessage.instance.exceptionMailRegist(e);
          });
        }
    
      } else if (widget.action == "new_user") {
        try {
          // ADDED: UUID を付与して登録APIへ送信（takken_ai/user_regist.php）
          final info = await loadUserInfo() ?? await getOrInitUserInfo();
          final response = await http
              .post(
                Uri.parse('${AppConfig.instance.baseUrl}user_regist.php'),
                headers: {
                  'Content-Type': 'application/x-www-form-urlencoded',
                  'Accept': 'application/json, text/plain, */*',
                },
                body: {
                  'mail': widget.email,
                  'uuid': info.uuid, // ADDED
                  'action': "new_user",
                  if ((widget.nickName ?? '').isNotEmpty) 'nick_name': widget.nickName!,
                },
              )
              .timeout(kHttpTimeout);
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['result'] == "OK") {
              // ADDED: リフレッシュトークンをセキュアストレージに保存
              final rt = (data['refresh_token'] is String) ? data['refresh_token'] as String : null;
              try {
                final current = await loadUserInfo() ?? await getOrInitUserInfo();
                // サーバ応答に uuid が含まれていれば優先（再インストール時のUUID再利用）
                final serverUuid = (data['uuid'] is String) ? (data['uuid'] as String) : null;
                final updated = UserInfo(
                  userId: current.userId,
                  email: widget.email,
                  uuid: (serverUuid != null && serverUuid.isNotEmpty) ? serverUuid : current.uuid,
                  status: 'verified',
                  createdAt: current.createdAt,
                  refreshToken: rt ?? current.refreshToken,
                  nickName: widget.nickName ?? current.nickName,
                );
                await saveUserInfo(updated);
                // ADDED: Settings の userInfo を更新させるため invalidate
                final container = ProviderScope.containerOf(context, listen: false);
                container.invalidate(userInfoProvider);
              } catch (_) {}
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => CertificationResult(action: "new_user")),
              );
            } else {
              setState(() {
                _errorMessage = ErrorMessage.instance.exceptionUserRegist(data['reason']);
              });
            }
          } else {
            setState(() {
              _errorMessage = ErrorMessage.instance.exceptionUserRegist(response.statusCode);
            });
          }
        } catch (e) {
          setState(() {
            _errorMessage = ErrorMessage.instance.exceptionUserRegist(e);
          });
        }
      }
      // ADDED: 成功時はカウントをリセット
      setState(() {
        _attempts = 0;
        _locked = false;
      });
    } else {
      // CHANGED: 確認ミス回数を管理し、上限でロック
      // ADDED: 失敗時はいったんキーボードを隠す（エラーメッセージを見せるため）
      FocusScope.of(context).unfocus();
      setState(() {
        _attempts += 1;
        final remains = (kMaxAttempts - _attempts).clamp(0, kMaxAttempts);
        if (_attempts >= kMaxAttempts) {
          _locked = true;
          _errorMessage = '確認に失敗しました。上限に達しました。確認コードを再送してください。';
        } else {
          _errorMessage = '確認に失敗しました。残り$remains回です。';
        }
      });
    }
  }

  /// 確認コード再送ボタンの処理：親側の sendmail メソッドを呼び出す
  void _resendAuthenticationCode() {
    // ADDED: クールダウン中や上限到達時は無効
    if (_resendCooldown > 0) return;
    if (_resendCount >= kMaxResend) return;

    // 新しい確認コードの生成・送信
    widget.authenticationNumber = Common.instance.getRandomNumber();
    Common.instance.sendmail(widget.email, widget.authenticationNumber);

    // 入力をクリアし、先頭にフォーカス
    for (final c in _controllers) c.clear();
    if (_childFocusNodes.isNotEmpty) {
      // CHANGED: KeyboardListener を使わず TextField の FocusNode を直接指定
      _childFocusNodes.first.requestFocus();
    }

    setState(() {
      _sendStatusMessage = "新しい確認コードを送信しました。";
      _resendCount++;
      _resendCooldown = kResendCooldownSec;
      _attempts = 0; // 新コードのためリセット
      _locked = false;
      _errorMessage = '';
    });
  }

  /// タイマー表示用ウィジェット（円状のプログレスと中央の残り時間表示）
  Widget _buildTimerIndicator() {
    final progress = _remainingSeconds / kTimerDurationSeconds;
    final duration = Duration(seconds: _remainingSeconds);
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 100,
          height: 100,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 8,
            backgroundColor: Colors.grey.shade300,
          ),
        ),
        Text(
          "$minutes:$seconds",
          style: const TextStyle(fontSize: 16),
        ),
      ],
    );
  }

  /// 1桁入力用のウィジェットを生成（KeyboardListener を廃止して安定化）
  Widget _buildDigitField(int index) {
    bool isEnabled = _remainingSeconds > 0;
    return Container(
      width: 50,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
          enabled: isEnabled,
          focusNode: _childFocusNodes[index],
          controller: _controllers[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            SingleDigitReplaceFormatter(),
          ],
          decoration: const InputDecoration(
            counterText: '',
            border: OutlineInputBorder(),
          ),
          onTap: () {
            _controllers[index].selection = TextSelection(
              baseOffset: 0,
              extentOffset: _controllers[index].text.length,
            );
          },
          onChanged: (value) {
            if (value.length == 1) {
              if (index < kCodeLength - 1) {
                // CHANGED: 次のフィールドへフォーカス移動（キーボードを保持）
                FocusScope.of(context).nextFocus();
              } else {
                // 最終桁はフォーカス維持（キーボードを閉じない）
              }
            } else if (value.isEmpty) {
              if (index > 0) {
                // CHANGED: 前のフィールドへ戻る
                FocusScope.of(context).previousFocus();
              }
            }
          },
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isTimeUp = _remainingSeconds <= 0;
    // ADDED: 確認ボタンの可否（全桁入力・時間内・未ロック）
    final canVerify = _isCodeFilled() && !isTimeUp && !_locked;
    return Scaffold(
      appBar: AppBar(
        title: const Text("確認コード入力"),
        backgroundColor: AppConfig.instance.appBarBackgroundColor,
        foregroundColor: AppConfig.instance.appBarForegroundColor,
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildTimerIndicator(),
              // タイムアップメッセージ
              const SizedBox(height: 12.0),
              if (_timeUpMessage.isNotEmpty)
                Text(
                  _timeUpMessage,
                  style: const TextStyle(fontSize: 18, color: Colors.red),
                ),

              const SizedBox(height: 12.0),
              // 送信状況のメッセージ（常に表示、再送信時に内容が変わる）
              Text(_sendStatusMessage, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 12.0),
              Text(
                "メールアドレス : ${widget.email}",
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12.0),
              Text("${kTimerDurationSeconds ~/ 60}分以内に確認コードを入力してください。"),
              const SizedBox(height: 20.0),

              // 入力フィールド
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(kCodeLength, (index) => _buildDigitField(index)).toList(),
              ),
              const SizedBox(height: 24.0),
              // 確認ボタン（横幅統一）
              SizedBox(
                // CHANGED: ボタン幅を 60% → 90% に拡大
                width: MediaQuery.of(context).size.width * kButtonWidthFactor,
                child: ElevatedButton(
                  // CHANGED: 条件を厳密化
                  onPressed: canVerify ? _verifyAuthenticationCode : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.instance.buttonBackgroundColor,
                    foregroundColor: AppConfig.instance.buttonForegroundColor,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text("確認"),
                ),
              ),
              const SizedBox(height: 16.0),
              // 確認コード再送ボタン（横幅統一、クールダウン・上限付き）
              SizedBox(
                // CHANGED: ボタン幅を 60% → 90% に拡大
                width: MediaQuery.of(context).size.width * kButtonWidthFactor,
                child: ElevatedButton(
                  // CHANGED: 再送はクールダウン・上限・タイムアップで無効
                  onPressed: (isTimeUp || _resendCount >= kMaxResend || _resendCooldown > 0)
                      ? null
                      : _resendAuthenticationCode,
                  style: ElevatedButton.styleFrom(
                     backgroundColor: AppConfig.instance.buttonBackgroundColor,
                    foregroundColor: AppConfig.instance.buttonForegroundColor,
                   minimumSize: const Size.fromHeight(48),
                  ),
                  // CHANGED: クールダウン/残回数の表示
                  child: Text(
                    _resendCooldown > 0
                        ? "確認コードを再送（再送可能まで: ${_resendCooldown}s）"
                        : "確認コードを再送（残り${(kMaxResend - _resendCount).clamp(0, kMaxResend)}回）",
                  ),
                ),
              ),
              const SizedBox(height: 24.0),
              Text(_errorMessage),
            ],
          ),
        ),
      ),
    );
  }
}
