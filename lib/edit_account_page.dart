import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appconfig.dart';
import 'common.dart';
import 'error_message.dart';
import 'certification_mail.dart';
import 'main.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'providers/premium_state_notifier.dart' as prem;

class EditAccountPage extends ConsumerStatefulWidget {
  final String currentEmail;
  const EditAccountPage({super.key, required this.currentEmail});

  @override
  ConsumerState<EditAccountPage> createState() => _EditAccountPageState();
}

class _EditAccountPageState extends ConsumerState<EditAccountPage> {
  final TextEditingController _newEmailController = TextEditingController();
  bool _sending = false;
  String? _error;
  BannerAd? _bannerAd;

  @override
  void initState() {
    super.initState();
    _newEmailController.text = '';
    _loadBanner();
  }

  @override
  void dispose() {
    _newEmailController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBanner() {
    final isPremium = ref.read(prem.premiumStateProvider).isPremium;
    if (isPremium) return;
    _bannerAd = BannerAd(
      size: AdSize.banner,
      adUnitId: 'ca-app-pub-3940256099942544/2934735716', // TEST用広告ID
      // adUnitId: 'ca-app-pub-9290857735881347/1643363507', // 本番広告ID（main.dartと同一）
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() {});
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
      request: const AdRequest(),
    )..load();
  }

  Future<void> _sendVerification() async {
    setState(() {
      _error = null;
    });

    final newEmail = _newEmailController.text.trim();
    if (newEmail.isEmpty) {
      setState(() => _error = ErrorMessage.instance.pleaseInputMailAddress);
      return;
    }
    if (!Common.instance.isValidEmail(newEmail)) {
      setState(
        () => _error = ErrorMessage.instance.pleaseInputValidMailAddress,
      );
      return;
    }

    setState(() => _sending = true);
    try {
      // 6桁コード生成して送信
      final code = Common.instance.getRandomNumber();
      final resp = await Common.instance.sendmail(newEmail, code);
      if (resp['result'] == 'OK') {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CertificationMail(
                  email: newEmail,
                  action: 'edit_mail',
                  authenticationNumber: code,
                ),
          ),
        );
      } else {
        setState(() => _error = resp['reason']?.toString() ?? 'メール送信に失敗しました');
      }
    } catch (e) {
      setState(() => _error = ErrorMessage.instance.exceptionMailRegist(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteEmail() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('アカウント登録を解除しますか？'),
            content: const Text(
              'メールアドレスの登録を解除します。\n'
              'メールアドレスの登録を解除しても直ちにはお気に入り(釣り場)は削除されません。\n'
              '但し機種変更やアプリの再インストール時にお気に入り(釣り場)の引き継ぎができなくなります。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('解除'),
              ),
            ],
          ),
    );
    if (ok != true) return;

    setState(() => _sending = true);
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final resp = await http.post(
        Uri.parse('${AppConfig.instance.baseUrl}user_regist.php'),
        body: {
          'uuid': info.uuid,
          'action': 'delete_mail', // サーバ側で実装されている前提
        },
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is Map && data['result'] == 'OK') {
          // ローカルも未登録に降格
          final updated = UserInfo(
            userId: info.userId,
            email: '',
            uuid: info.uuid,
            status: info.status,
            createdAt: info.createdAt,
            refreshToken: null,
          );
          await saveUserInfo(updated);
          // 設定画面へ反映
          ref.invalidate(userInfoProvider);
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('アカウント登録を解除しました')));
          Navigator.pop(context);
        } else {
          setState(() => _error = data['reason']?.toString() ?? '削除に失敗しました');
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('サーバーエラー: ${resp.statusCode}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('削除時にエラーが発生しました'),
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('アカウント設定'),
        backgroundColor: AppConfig.instance.appBarBackgroundColor,
        foregroundColor: AppConfig.instance.appBarForegroundColor,
        toolbarHeight: 0, // タイトルはボディ側に自前で表示（バナーの下）
      ),
      body: Column(
        children: [
          Builder(
            builder: (context) {
              final isPremium = ref.watch(prem.premiumStateProvider).isPremium;
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
          // タイトル行（AppBar の代替）
          Container(
            height: kToolbarHeight,
            color: AppConfig.instance.appBarBackgroundColor,
            child: Row(
              children: [
                BackButton(
                  color: AppConfig.instance.appBarForegroundColor,
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    'アカウント設定',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      color: AppConfig.instance.appBarForegroundColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 上部インフォカード（iボタンの代替表示）
                  _sectionCard(
                    child: const Text(
                      'メールアドレスの変更やアカウントを削除することができます',
                      style: TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle(context, 'メールアドレス変更'),
                  const SizedBox(height: 12),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '現在のメールアドレス',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.currentEmail.isEmpty
                                ? '未登録'
                                : widget.currentEmail,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '新しいメールアドレス',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _newEmailController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'example@example.com',
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _sending ? null : _sendVerification,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  AppConfig.instance.buttonBackgroundColor,
                              foregroundColor:
                                  AppConfig.instance.buttonForegroundColor,
                              minimumSize: const Size.fromHeight(44),
                            ),
                            child: Text(_sending ? '送信中…' : '確認コードを送信'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  _sectionTitle(context, 'アカウント登録解除'),
                  const SizedBox(height: 12),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _sending ? null : _deleteEmail,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(44),
                            ),
                            child: Text(_sending ? '処理中…' : 'アカウント登録を解除'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '登録を解除すると、機種変更やアプリの再インストール時にお気に入り(釣り場)の引き継ぎができなくなります。',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Row(
      children: [
        const Icon(Icons.arrow_right, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade400),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: child,
      ),
    );
  }
}
