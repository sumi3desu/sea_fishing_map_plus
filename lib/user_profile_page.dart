import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'appconfig.dart';
import 'constants.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key, required this.userId, this.nickName});
  final int userId;
  final String? nickName;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  String? _avatarUrl;
  String? _bgUrl;
  String? _nick;
  bool _loading = true;
  BannerAd? _bannerAd;
  late final TextEditingController _nickController;

  @override
  void initState() {
    super.initState();
    _nick = widget.nickName;
    _nickController = TextEditingController(text: (_nick ?? '').isNotEmpty ? _nick : '');
    _load();
    _loadBanner();
  }

  void _loadBanner() {
    try {
      _bannerAd = BannerAd(
        size: AdSize.banner,
        adUnitId: 'ca-app-pub-3940256099942544/2934735716',
        listener: BannerAdListener(onAdLoaded: (_) => mounted ? setState(() {}) : null, onAdFailedToLoad: (ad, e) => ad.dispose()),
        request: const AdRequest(),
      )..load();
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final uri = Uri.parse('${AppConfig.instance.baseUrl}get_profile_images.php');
      final resp = await http
          .post(uri, body: {'user_id': widget.userId.toString()})
          .timeout(kHttpTimeout);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['status'] == 'success') {
          final String base = '${AppConfig.instance.baseUrl}user_images/';
          final String? avatarRel = data['avatar_path'] as String?;
          final String? coverRel = data['cover_path'] as String?;
          if (avatarRel != null && avatarRel.isNotEmpty) {
            final ts = DateTime.now().millisecondsSinceEpoch;
            _avatarUrl = base + avatarRel + '?ts=$ts';
          }
          if (coverRel != null && coverRel.isNotEmpty) {
            final ts = DateTime.now().millisecondsSinceEpoch;
            _bgUrl = base + coverRel + '?ts=$ts';
          }
          // 将来: ニックネームAPIがあればここで上書き
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _nickController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール'),
        backgroundColor: AppConfig.instance.appBarBackgroundColor,
        foregroundColor: AppConfig.instance.appBarForegroundColor,
        toolbarHeight: 0, // タイトルは本文側に自前で表示（バナーの下）
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_bannerAd != null)
                  Container(
                    alignment: Alignment.center,
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
                // タイトル行（AppBar の代替）
                Container(
                  height: kToolbarHeight,
                  color: AppConfig.instance.appBarBackgroundColor,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                        color: AppConfig.instance.appBarForegroundColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'プロフィール',
                        style: TextStyle(
                          color: AppConfig.instance.appBarForegroundColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                Expanded(
                  child: SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.only(top: 0),
                      children: [
                        // ヘッダー（背景 + 左のプロフィール円）: ProfileEdit と同様の見た目（上下左右16の余白）
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Builder(
                            builder: (context) {
                              final double w = MediaQuery.of(context).size.width;
                              const double phi = 1.61803398875;
                              final double h = w / phi; // 黄金比
                              ImageProvider? bgProvider;
                              if ((_bgUrl ?? '').isNotEmpty) {
                                bgProvider = NetworkImage(_bgUrl!);
                              }
                              ImageProvider? avatarProvider;
                              if ((_avatarUrl ?? '').isNotEmpty) {
                                avatarProvider = NetworkImage(_avatarUrl!);
                              }
                              return Column(
                                children: [
                                  Stack(
                                    children: [
                                      Container(
                                        height: h,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          image: bgProvider != null
                                              ? DecorationImage(image: bgProvider, fit: BoxFit.cover)
                                              : null,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: bgProvider == null
                                            ? Center(
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: const [
                                                    Icon(Icons.image, color: Colors.black54),
                                                    SizedBox(width: 6),
                                                    Text('背景画像（横幅いっぱい）', style: TextStyle(color: Colors.black54)),
                                                  ],
                                                ),
                                              )
                                            : null,
                                      ),
                                      Positioned(
                                        left: 12,
                                        top: h / 2 - 36,
                                        child: CircleAvatar(
                                          radius: 36,
                                          backgroundColor: Colors.white,
                                          foregroundColor: Colors.white,
                                          child: CircleAvatar(
                                            radius: 34,
                                            backgroundColor: Colors.grey.shade300,
                                            backgroundImage: avatarProvider,
                                            child: avatarProvider == null
                                                ? const Icon(Icons.person, color: Colors.white, size: 34)
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ニックネーム', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _nickController,
                                maxLength: 12,
                                enabled: false,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  counterText: '',
                                  hintText: '12文字以内',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text('ユーザーID: ${widget.userId}', style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
