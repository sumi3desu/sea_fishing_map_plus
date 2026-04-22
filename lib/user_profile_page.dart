import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import 'appconfig.dart';
import 'constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/premium_state_notifier.dart' as prem;

class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({super.key, required this.userId, this.nickName});
  final int userId;
  final String? nickName;

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  String? _avatarUrl;
  String? _bgUrl;
  String? _nick;
  String _xUsername = '';
  String _instagramUsername = '';
  bool _xPublic = false;
  bool _instagramPublic = false;
  bool _loading = true;
  BannerAd? _bannerAd;
  late final TextEditingController _nickController;

  @override
  void initState() {
    super.initState();
    _nick = widget.nickName;
    _nickController = TextEditingController(
      text: (_nick ?? '').isNotEmpty ? _nick : '',
    );
    _load();
    final isPremium = ref.read(prem.premiumStateProvider).isPremium;
    if (!isPremium) {
      _loadBanner();
    }
  }

  void _loadBanner() {
    try {
      _bannerAd = BannerAd(
        size: AdSize.banner,
        adUnitId: 'ca-app-pub-3940256099942544/2934735716',
        listener: BannerAdListener(
          onAdLoaded: (_) => mounted ? setState(() {}) : null,
          onAdFailedToLoad: (ad, e) => ad.dispose(),
        ),
        request: const AdRequest(),
      )..load();
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final uri = Uri.parse(
        '${AppConfig.instance.baseUrl}get_profile_images.php',
      );
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
            _avatarUrl = '$base$avatarRel?ts=$ts';
          }
          if (coverRel != null && coverRel.isNotEmpty) {
            final ts = DateTime.now().millisecondsSinceEpoch;
            _bgUrl = '$base$coverRel?ts=$ts';
          }
        }
      }
    } catch (_) {}
    try {
      final uri = Uri.parse(
        '${AppConfig.instance.baseUrl}get_profile_fields.php',
      );
      final resp = await http
          .post(uri, body: {'user_id': widget.userId.toString()})
          .timeout(kHttpTimeout);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['status'] == 'success') {
          _nick = (data['nick_name']?.toString() ?? '').trim();
          _nickController.text = _nick ?? '';
          _xUsername = (data['x_username']?.toString() ?? '').trim();
          _instagramUsername =
              (data['instagram_username']?.toString() ?? '').trim();
          _xPublic =
              (data['x_public']?.toString() == '1' || data['x_public'] == true);
          _instagramPublic =
              (data['instagram_public']?.toString() == '1' ||
                  data['instagram_public'] == true);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openExternalUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('URLを開けませんでした')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('URLを開けませんでした')));
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _nickController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール'),
        backgroundColor: AppConfig.instance.appBarBackgroundColor,
        foregroundColor: AppConfig.instance.appBarForegroundColor,
        toolbarHeight: 0, // タイトルは本文側に自前で表示（バナーの下）
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      final isPremium =
                          ref.watch(prem.premiumStateProvider).isPremium;
                      if (isPremium || _bannerAd == null) {
                        return const SizedBox.shrink();
                      }
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
                                final double w =
                                    MediaQuery.of(context).size.width;
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
                                            image:
                                                bgProvider != null
                                                    ? DecorationImage(
                                                      image: bgProvider,
                                                      fit: BoxFit.cover,
                                                    )
                                                    : null,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child:
                                              bgProvider == null
                                                  ? Center(
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: const [
                                                        Icon(
                                                          Icons.image,
                                                          color: Colors.black54,
                                                        ),
                                                        SizedBox(width: 6),
                                                        Text(
                                                          '背景画像（横幅いっぱい）',
                                                          style: TextStyle(
                                                            color:
                                                                Colors.black54,
                                                          ),
                                                        ),
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
                                              backgroundColor:
                                                  Colors.grey.shade300,
                                              backgroundImage: avatarProvider,
                                              child:
                                                  avatarProvider == null
                                                      ? const Icon(
                                                        Icons.person,
                                                        color: Colors.white,
                                                        size: 34,
                                                      )
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
                                _sectionTitle('ニックネーム'),
                                const SizedBox(height: 12),
                                _sectionCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
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
                                      Text(
                                        'ユーザーID: ${widget.userId}',
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _sectionTitle('SNS'),
                                const SizedBox(height: 12),
                                _sectionCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildSocialFieldReadOnly(
                                        label: 'X ユーザネーム',
                                        value: _xPublic ? _xUsername : '',
                                        isPublic: _xPublic,
                                        hintText: _xPublic ? '1から15文字' : '',
                                        icon: _buildSocialIcon(
                                          label: 'X',
                                          onTap: () {
                                            if (!_xPublic ||
                                                _xUsername.isEmpty) {
                                              return;
                                            }
                                            _openExternalUrl(
                                              'https://x.com/$_xUsername',
                                            );
                                          },
                                          enabled:
                                              _xPublic && _xUsername.isNotEmpty,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Divider(height: 1),
                                      const SizedBox(height: 16),
                                      _buildSocialFieldReadOnly(
                                        label: 'Instagram ユーザネーム',
                                        value:
                                            _instagramPublic
                                                ? _instagramUsername
                                                : '',
                                        isPublic: _instagramPublic,
                                        hintText:
                                            _instagramPublic ? '1から30文字' : '',
                                        icon: _buildSocialIcon(
                                          icon: Icons.camera_alt_outlined,
                                          onTap: () {
                                            if (!_instagramPublic ||
                                                _instagramUsername.isEmpty) {
                                              return;
                                            }
                                            _openExternalUrl(
                                              'https://www.instagram.com/$_instagramUsername/',
                                            );
                                          },
                                          enabled:
                                              _instagramPublic &&
                                              _instagramUsername.isNotEmpty,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        const Text('▶︎', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

  Widget _buildSocialFieldReadOnly({
    required String label,
    required String value,
    required bool isPublic,
    required String hintText,
    required Widget icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: IgnorePointer(
            child: CupertinoSlidingSegmentedControl<bool>(
              groupValue: isPublic,
              children: const {
                false: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('非公開'),
                ),
                true: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('公開'),
                ),
              },
              onValueChanged: (_) {},
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 4), child: icon),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: TextEditingController(text: value),
                maxLength: label.startsWith('X') ? 15 : 30,
                enabled: false,
                readOnly: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  counterText: '',
                  hintText: hintText,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSocialIcon({
    IconData? icon,
    String? label,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    final color =
        enabled ? AppConfig.instance.appBarBackgroundColor : Colors.grey;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child:
            icon != null
                ? Icon(icon, color: color, size: 20)
                : Text(
                  label ?? '',
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
      ),
    );
  }
}
