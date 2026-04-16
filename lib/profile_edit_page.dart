import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'appconfig.dart';
import 'constants.dart';
import 'main.dart';
import 'avatar_crop_page.dart';
import 'package:flutter/cupertino.dart';
import 'background_crop_page.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/premium_state_notifier.dart' as prem;

class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final TextEditingController _nickController = TextEditingController();
  bool _saving = false;
  bool _isEditing = false;
  bool _dirty = false;
  String _initialNick = '';
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage;
  XFile? _pickedBgImage;
  String? _remotePhotoUrl;
  String? _bgRemoteUrl; // サーバー上の背景画像URL
  String? _bgLocalPath; // 端末保存用の背景画像パス
  BannerAd? _bannerAd;

  @override
  void initState() {
    super.initState();
    _load();
    final isPremium = ref.read(prem.premiumStateProvider).isPremium;
    if (!isPremium) {
      _loadBanner();
    }
  }

  Future<void> _load() async {
    try {
      // 優先: セキュアストレージの UserInfo.nickName
      final info = await loadUserInfo();
      String nn = info?.nickName ?? '';
      _remotePhotoUrl = info?.photoUrl;
      // フォールバック: 旧保存領域（SharedPreferences）
      if (nn.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        nn = prefs.getString('profile_nick_name') ?? '';
      }
      // 背景画像のローカルパス
      try {
        final prefs = await SharedPreferences.getInstance();
        _bgLocalPath = prefs.getString('profile_bg_path');
      } catch (_) {}
      _nickController.text = nn;
      _initialNick = _nickController.text;
      setState(() {});
      // サーバーに保存されている最新のプロフィール画像/背景画像の取得
      await _fetchRemoteImages();
    } catch (_) {}
  }

  void _loadBanner() {
    _bannerAd = BannerAd(
      size: AdSize.banner,
      adUnitId: 'ca-app-pub-3940256099942544/2934735716', // TEST用広告ID
      //　adUnitId: 'ca-app-pub-9290857735881347/1643363507', // 本番広告ID（main.dartと同一）
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

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _fetchRemoteImages() async {
    try {
      final info = await loadUserInfo();
      if (info == null || info.userId <= 0) return;
      final uri = Uri.parse(
        '${AppConfig.instance.baseUrl}get_profile_images.php',
      );
      final resp = await http
          .post(uri, body: {'user_id': info.userId.toString()})
          .timeout(kHttpTimeout);
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if ((data['status'] as String?) != 'success') return;
      final String base = '${AppConfig.instance.baseUrl}user_images/';
      final String? avatarRel = data['avatar_path'] as String?;
      final String? coverRel = data['cover_path'] as String?;
      if (!mounted) return;
      setState(() {
        if (avatarRel != null && avatarRel.isNotEmpty) {
          _remotePhotoUrl = base + avatarRel;
        }
        if (coverRel != null && coverRel.isNotEmpty) {
          _bgRemoteUrl = base + coverRel;
        }
      });
    } catch (_) {
      // 取得失敗時は無視（オフライン等）
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (x != null) {
        if (!mounted) return;
        final croppedPath = await Navigator.push<String?>(
          context,
          MaterialPageRoute(builder: (_) => AvatarCropPage(imageFile: x)),
        );
        if (croppedPath != null) {
          setState(() => _pickedImage = XFile(croppedPath));
          // 編集完了タイミングで即アップロード（avatar）
          _uploadProfileFile(croppedPath, kind: 'avatar');
          _dirty = true;
        }
      }
    } catch (_) {}
  }

  Future<void> _pickFromCamera() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (x != null) {
        if (!mounted) return;
        final croppedPath = await Navigator.push<String?>(
          context,
          MaterialPageRoute(builder: (_) => AvatarCropPage(imageFile: x)),
        );
        if (croppedPath != null) {
          setState(() => _pickedImage = XFile(croppedPath));
          // 編集完了タイミングで即アップロード（avatar）
          _uploadProfileFile(croppedPath, kind: 'avatar');
          _dirty = true;
        }
      }
    } catch (_) {}
  }

  Future<void> _showAvatarActionSheet() async {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    if (isIOS) {
      await showCupertinoModalPopup(
        context: context,
        builder:
            (ctx) => CupertinoActionSheet(
              title: const Text('登録方法（プロフィール画像）'),
              actions: [
                CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pickFromCamera();
                  },
                  child: const Text('写真を撮る'),
                ),
                CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pickFromGallery();
                  },
                  child: const Text('ギャラリーから写真を選択する'),
                ),
              ],
              cancelButton: CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル'),
              ),
            ),
      );
    } else {
      await showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return SafeArea(
            child: Wrap(
              children: [
                const ListTile(title: Text('登録方法（プロフィール画像）')),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('写真を撮る'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickFromCamera();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('ギャラリーから写真を選択する'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickFromGallery();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('キャンセル'),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Future<void> _pickBgFromGallery() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 92,
      );
      if (x != null) {
        if (!mounted) return;
        final croppedPath = await Navigator.push<String?>(
          context,
          MaterialPageRoute(builder: (_) => BackgroundCropPage(imageFile: x)),
        );
        if (croppedPath != null) {
          setState(() => _pickedBgImage = XFile(croppedPath));
          // 編集完了タイミングで即アップロード（cover）
          _uploadProfileFile(croppedPath, kind: 'cover');
          _dirty = true;
        }
      }
    } catch (_) {}
  }

  Future<void> _pickBgFromCamera() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 92,
      );
      if (x != null) {
        if (!mounted) return;
        final croppedPath = await Navigator.push<String?>(
          context,
          MaterialPageRoute(builder: (_) => BackgroundCropPage(imageFile: x)),
        );
        if (croppedPath != null) {
          setState(() => _pickedBgImage = XFile(croppedPath));
          // 編集完了タイミングで即アップロード（cover）
          _uploadProfileFile(croppedPath, kind: 'cover');
          _dirty = true;
        }
      }
    } catch (_) {}
  }

  Future<void> _uploadProfileFile(
    String localPath, {
    required String kind,
  }) async {
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final uri = Uri.parse('${AppConfig.instance.baseUrl}enter_profile.php');
      final req =
          http.MultipartRequest('POST', uri)
            ..fields['user_id'] = info.userId.toString()
            ..fields['type'] = kind;
      final file = await http.MultipartFile.fromPath('file', localPath);
      req.files.add(file);
      final resp = await req.send();
      // Optionally read response; keep silent on failure to not block UI
      await resp.stream.drain();
    } catch (_) {
      // 無視（通信失敗は致命的でない）
    }
  }

  Future<void> _showBgActionSheet() async {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    if (isIOS) {
      await showCupertinoModalPopup(
        context: context,
        builder:
            (ctx) => CupertinoActionSheet(
              title: const Text('登録方法(背景画像)'),
              actions: [
                CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pickBgFromCamera();
                  },
                  child: const Text('写真を撮る'),
                ),
                CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pickBgFromGallery();
                  },
                  child: const Text('ギャラリーから写真を選択する'),
                ),
              ],
              cancelButton: CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(ctx),
                isDefaultAction: false,
                isDestructiveAction: false,
                child: const Text('キャンセル'),
              ),
            ),
      );
    } else {
      await showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return SafeArea(
            child: Wrap(
              children: [
                const ListTile(title: Text('登録方法(背景画像)')),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('写真を撮る'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickBgFromCamera();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('ギャラリーから写真を選択する'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickBgFromGallery();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('キャンセル'),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  void _enterEdit() {
    setState(() {
      _isEditing = true;
      _dirty = false;
      _initialNick = _nickController.text;
    });
  }

  bool _hasUnsavedChanges() {
    if (_pickedImage != null) return true;
    if (_pickedBgImage != null) return true;
    if (_nickController.text.trim() != _initialNick.trim()) return true;
    return _dirty;
  }

  Future<bool> _confirmDiscard() async {
    return await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('変更を破棄しますか？'),
                content: const Text('保存されていない変更があります。破棄してよろしいですか？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('続ける'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('破棄'),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<void> _cancelEdit() async {
    if (_hasUnsavedChanges()) {
      final discard = await _confirmDiscard();
      if (!discard) return;
    }
    setState(() {
      _isEditing = false;
      _dirty = false;
      _nickController.text = _initialNick;
      _pickedImage = null;
      _pickedBgImage = null;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      var nn = _nickController.text.trim();
      if (nn.length > 12) nn = nn.substring(0, 12);
      // 1) ローカル保存（表示用途のフォールバック）
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_nick_name', nn);
      // 2) サーバへ反映（ニックネーム）
      try {
        final info = await loadUserInfo() ?? await getOrInitUserInfo();
        await http
            .post(
              Uri.parse('${AppConfig.instance.baseUrl}user_regist.php'),
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json, text/plain, */*',
              },
              body: {
                'uuid': info.uuid,
                'user_id': info.userId.toString(),
                'nick_name': nn,
                'action': 'update_nick',
              },
            )
            .timeout(kHttpTimeout);
      } catch (_) {}
      // 2b) プロフィール画像（サーバ連携は後回し）: ローカルに保存し、UserInfoにfile://URLで保持
      String? newPhotoUrl;
      int? newPhotoVer;
      if (_pickedImage != null) {
        try {
          final info = await loadUserInfo() ?? await getOrInitUserInfo();
          final dir = await getApplicationDocumentsDirectory();
          final fname = 'user_${info.userId}_profile.webp';
          final destPath = p.join(dir.path, fname);
          await File(_pickedImage!.path).copy(destPath);
          newPhotoUrl = 'file://$destPath';
        } catch (_) {}
      }
      // 2c) 背景画像（ローカル保存）
      if (_pickedBgImage != null) {
        try {
          final info = await loadUserInfo() ?? await getOrInitUserInfo();
          final dir = await getApplicationDocumentsDirectory();
          final fname = 'user_${info.userId}_bg.webp';
          final destPath = p.join(dir.path, fname);
          await File(_pickedBgImage!.path).copy(destPath);
          _bgLocalPath = destPath;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('profile_bg_path', destPath);
        } catch (_) {}
      }

      // 2d) サーバに反映された最新のアバターURLを取得して photoUrl をサーバURLへ統一
      String? remoteAvatarUrl;
      try {
        final info = await loadUserInfo() ?? await getOrInitUserInfo();
        final uri = Uri.parse(
          '${AppConfig.instance.baseUrl}get_profile_images.php',
        );
        final resp = await http
            .post(uri, body: {'user_id': info.userId.toString()})
            .timeout(kHttpTimeout);
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          if ((data['status'] as String?) == 'success') {
            final String base = '${AppConfig.instance.baseUrl}user_images/';
            final String? avatarRel = data['avatar_path'] as String?;
            if (avatarRel != null && avatarRel.isNotEmpty) {
              remoteAvatarUrl = base + avatarRel;
            }
          }
        }
      } catch (_) {}

      // 3) UserInfo にも反映（サーバURLを優先。なければローカルfile://、それもなければ現状維持）
      try {
        final current = await loadUserInfo() ?? await getOrInitUserInfo();
        final updated = UserInfo(
          userId: current.userId,
          email: current.email,
          uuid: current.uuid,
          status: current.status,
          createdAt: current.createdAt,
          refreshToken: current.refreshToken,
          nickName: nn,
          photoUrl: remoteAvatarUrl ?? newPhotoUrl ?? current.photoUrl,
          photoVersion: newPhotoVer ?? current.photoVersion,
        );
        await saveUserInfo(updated);
        _remotePhotoUrl = updated.photoUrl;
      } catch (_) {}
      if (!mounted) return;
      Navigator.pop(context, nn);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存中にエラーが発生しました')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isEditing && _hasUnsavedChanges()) {
          return await _confirmDiscard();
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'プロフィールの編集' : 'プロフィール'),
          backgroundColor: AppConfig.instance.appBarBackgroundColor,
          foregroundColor: AppConfig.instance.appBarForegroundColor,
          toolbarHeight: 0, // タイトルはボディ側に自前で表示（バナーの下）
        ),
        body: Column(
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
            // タイトル行（AppBar の代替）
            Container(
              height: kToolbarHeight,
              color: AppConfig.instance.appBarBackgroundColor,
              child: Row(
                children: [
                  // 左側: 編集中は「キャンセル」、それ以外は戻るボタン
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child:
                        _isEditing
                            ? TextButton.icon(
                              onPressed: _saving ? null : _cancelEdit,
                              icon: const Icon(Icons.close),
                              label: const Text('キャンセル'),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    AppConfig.instance.appBarForegroundColor,
                              ),
                            )
                            : BackButton(
                              color: AppConfig.instance.appBarForegroundColor,
                              onPressed: () => Navigator.pop(context),
                            ),
                  ),
                  // 中央タイトル
                  Expanded(
                    child: Text(
                      _isEditing ? 'プロフィールの編集' : 'プロフィール',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        color: AppConfig.instance.appBarForegroundColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // 右側アクション: 編集 or 保存
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child:
                        _isEditing
                            ? TextButton.icon(
                              onPressed: _saving ? null : _save,
                              icon:
                                  _saving
                                      ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.check),
                              label: Text(_saving ? '保存中…' : '保存'),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    AppConfig.instance.appBarForegroundColor,
                              ),
                            )
                            : TextButton.icon(
                              onPressed: _enterEdit,
                              icon: const Icon(Icons.edit),
                              label: const Text('編集'),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    AppConfig.instance.appBarForegroundColor,
                              ),
                            ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 背景画像プレビュー（黄金比: 高さ = 幅 / φ）
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final w = MediaQuery.of(context).size.width;
                        const phi = 1.61803398875;
                        final h = w / phi; // 黄金比
                        final ImageProvider? bgProvider =
                            _pickedBgImage != null
                                ? FileImage(File(_pickedBgImage!.path))
                                : (_bgRemoteUrl != null &&
                                    _bgRemoteUrl!.isNotEmpty)
                                ? NetworkImage(_bgRemoteUrl!)
                                : (_bgLocalPath != null &&
                                    _bgLocalPath!.isNotEmpty)
                                ? FileImage(File(_bgLocalPath!))
                                : null;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: double.infinity,
                                  height: h,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade300,
                                    image:
                                        bgProvider != null
                                            ? DecorationImage(
                                              image: bgProvider,
                                              fit: BoxFit.cover,
                                            )
                                            : null,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child:
                                      bgProvider == null
                                          ? Center(
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: const [
                                                Icon(
                                                  Icons.image,
                                                  color: Colors.black54,
                                                ),
                                                SizedBox(width: 6),
                                                Text(
                                                  '背景画像（横幅いっぱい）',
                                                  style: TextStyle(
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                          : null,
                                ),
                                // 背景画像編集ボタン（背景左上、半透明50%）
                                if (_isEditing)
                                  Positioned(
                                    left: 12,
                                    top: 8,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.black
                                            .withOpacity(0.3),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: _showBgActionSheet,
                                      icon: const Icon(Icons.edit),
                                      label: const Text(
                                        '背景画像編集',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                // プロフィール円画像を背景上にオーバーレイ（縁の中心が背景高さの1/2になるよう位置決め）
                                Positioned(
                                  left: 12,
                                  top:
                                      h / 2 -
                                      36, // 外側円(radius:36)の中心がちょうど中点になるように調整
                                  child: CircleAvatar(
                                    radius: 36,
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.white,
                                    child: CircleAvatar(
                                      radius: 34,
                                      backgroundColor: Colors.grey.shade300,
                                      backgroundImage:
                                          _pickedImage != null
                                              ? FileImage(
                                                    File(_pickedImage!.path),
                                                  )
                                                  as ImageProvider
                                              : (_remotePhotoUrl != null &&
                                                  _remotePhotoUrl!.isNotEmpty)
                                              ? (_remotePhotoUrl!.startsWith(
                                                    'http',
                                                  )
                                                  ? NetworkImage(
                                                    _remotePhotoUrl!,
                                                  )
                                                  : (_remotePhotoUrl!
                                                          .startsWith('file://')
                                                      ? FileImage(
                                                        File(
                                                          Uri.parse(
                                                            _remotePhotoUrl!,
                                                          ).toFilePath(),
                                                        ),
                                                      )
                                                      : FileImage(
                                                        File(_remotePhotoUrl!),
                                                      )))
                                              : null,
                                      child:
                                          (_pickedImage == null &&
                                                  (_remotePhotoUrl == null ||
                                                      _remotePhotoUrl!.isEmpty))
                                              ? const Icon(
                                                Icons.person,
                                                color: Colors.white,
                                                size: 34,
                                              )
                                              : null,
                                    ),
                                  ),
                                ),
                                // プロフィール画像編集ボタン（円の直下、半透明50%）
                                if (_isEditing)
                                  Positioned(
                                    left: 12,
                                    top: h / 2 - 36 + 72 + 8, // 円の下に少し余白
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.black
                                            .withOpacity(0.3),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: _showAvatarActionSheet,
                                      icon: const Icon(Icons.edit),
                                      label: const Text(
                                        'プロフィール画像編集',
                                        style: TextStyle(fontSize: 12),
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
                    const SizedBox(height: 16),
                    const Text(
                      'ニックネーム',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nickController,
                      maxLength: 12,
                      enabled: _isEditing,
                      readOnly: !_isEditing,
                      onChanged: (_) => _dirty = true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        counterText: '',
                        hintText: '12文字以内',
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 注意書き（ニックネームの直下に配置）
                    const Text(
                      '本名など個人情報は入力しないでください（投稿時に表示されます）',
                      style: TextStyle(fontSize: 12.5, color: Colors.black87),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
