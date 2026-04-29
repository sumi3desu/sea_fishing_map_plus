import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:ui' as ui;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'appconfig.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/premium_state_notifier.dart' as prem;
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'sio_database.dart';
import 'common.dart';
import 'new_account_page.dart';
import 'catch_area_candidates.dart';

class InputPost extends ConsumerStatefulWidget {
  const InputPost({
    super.key,
    required this.initialType,
    this.editMode = false,
    this.initialSummary,
    this.initialDetail,
    this.initialImageUrl,
    this.editingPostId,
    this.initialSpotId,
  });
  // 'catch' or 'env'
  final String initialType;
  // 編集モード（投稿ではなく保存ボタンを表示）
  final bool editMode;
  // 事前入力（編集モード用）
  final String? initialSummary;
  final String? initialDetail;
  final String? initialImageUrl;
  final int? editingPostId;
  final int? initialSpotId; // 編集モードでのスポットID（フォルダ構成に利用）

  @override
  ConsumerState<InputPost> createState() => _InputPostState();
}

class _InputPostState extends ConsumerState<InputPost> {
  BannerAd? _bannerAd;
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage; // 表示用（選択直後の元画像を表示し続ける）
  XFile? _uploadImage; // 送信用（圧縮後のWebPを保持）
  String? _networkImageUrl; // 編集モード時の既存画像URLプレビュー
  bool _clearImage = false; // 画像取り消し（編集で画像を外したいとき）
  final ScrollController _scrollController = ScrollController();
  Future<XFile?>? _compressing; // 進行中の圧縮（あれば待機に使用）
  bool _submitting = false;

  // 投稿種別（画面遷移元で決定）
  // 'catch' = 釣果, 'env' = 釣り場環境
  late String _postType;

  // 釣り場環境の投稿項目（単一選択）
  final List<String> _envCategories = const [
    '規制',
    '駐車場',
    'トイレ',
    '釣餌',
    'コンビニ',
    'その他',
  ];
  String? _selectedEnvCategory;

  // 釣果入力
  final TextEditingController _summaryController = TextEditingController();
  final TextEditingController _detailController = TextEditingController();

  // 環境入力
  String? _envAvailability; // 'あり' or 'なし'
  final TextEditingController _envSummaryController =
      TextEditingController(); // 30桁
  final TextEditingController _envDetailController =
      TextEditingController(); // 1000桁
  bool _emailVerified = false;

  String get _screenTitle {
    if (widget.editMode) return '投稿を編集';
    return _postType == 'catch' ? '釣果を投稿' : '環境を投稿';
  }

  @override
  void initState() {
    super.initState();
    // ドラフトがあれば種別を上書き
    final draftType = widget.editMode ? null : Common.instance.draftType;
    _postType =
        (draftType != null)
            ? draftType
            : ((widget.initialType == 'env') ? 'env' : 'catch');
    _loadBanner();
    // メール認証状態を取得
    (() async {
      try {
        final info = await loadUserInfo() ?? await getOrInitUserInfo();
        if (mounted)
          setState(() => _emailVerified = (info.email.trim().isNotEmpty));
      } catch (_) {}
    })();
    // 編集モードの事前入力
    if (widget.editMode) {
      if (_postType == 'catch') {
        _summaryController.text = widget.initialSummary ?? '';
        _detailController.text = widget.initialDetail ?? '';
      } else {
        _envSummaryController.text = widget.initialSummary ?? '';
        _envDetailController.text = widget.initialDetail ?? '';
      }
      final url = (widget.initialImageUrl ?? '').trim();
      if (url.isNotEmpty) {
        _networkImageUrl = url;
      }
    }
    // ドラフトの内容を復元
    _restoreDraftIfAny();
    // 認証後に自動投稿が要求されている場合は試行
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _tryAutoSubmitAfterAuth(),
    );
  }

  void _loadBanner() {
    final isPremium = ref.read(prem.premiumStateProvider).isPremium;
    if (isPremium) return;
    _bannerAd = BannerAd(
      size: AdSize.banner,
      adUnitId:
          'ca-app-pub-3940256099942544/2934735716', // TEST用広告ID（釣り場詳細/一覧/日付と同じ）
      // adUnitId: 'ca-app-pub-9290857735881347/1643363507', // 本番広告ID
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
    _summaryController.dispose();
    _detailController.dispose();
    _envSummaryController.dispose();
    _envDetailController.dispose();
    super.dispose();
  }

  Future<String> _spotDisplayText() async {
    try {
      final common = Common.instance;
      final baseName =
          common.selectedTeibouName.isNotEmpty
              ? common.selectedTeibouName
              : common.tidePoint;
      String display = baseName;
      try {
        final rows = await SioDatabase().getAllTeibouWithPrefecture();
        Map<String, dynamic>? row;
        // ID優先（selected_teibou_id）
        try {
          final prefs = await SharedPreferences.getInstance();
          final sid = prefs.getInt('selected_teibou_id');
          if (sid != null && sid > 0) {
            for (final r in rows) {
              final rid =
                  r['spot_id'] is int
                      ? r['spot_id'] as int
                      : int.tryParse(r['spot_id']?.toString() ?? '');
              if (rid == sid) {
                row = r;
                break;
              }
            }
          }
        } catch (_) {}
        // 名前一致フォールバック
        row ??= rows.cast<Map<String, dynamic>?>().firstWhere(
          (r) => ((r?['spot_name'] ?? '').toString() == baseName),
          orElse: () => null,
        );
        final int? flag =
            row == null
                ? null
                : (row['flag'] is int
                    ? row['flag'] as int
                    : int.tryParse(row['flag']?.toString() ?? ''));
        if (flag == -1) display = '$baseName (申請中)';
      } catch (_) {}
      return display;
    } catch (_) {
      return '';
    }
  }

  // 画面見出し用の整形済みテキスト
  Future<String> _spotTitleText() async {
    try {
      final common = Common.instance;
      final baseName =
          common.selectedTeibouName.isNotEmpty
              ? common.selectedTeibouName
              : common.tidePoint;
      String name = baseName;
      String yomi = '';
      try {
        final rows = await SioDatabase().getAllTeibouWithPrefecture();
        Map<String, dynamic>? row;
        try {
          final prefs = await SharedPreferences.getInstance();
          final sid = prefs.getInt('selected_teibou_id');
          if (sid != null && sid > 0) {
            for (final r in rows) {
              final rid =
                  r['spot_id'] is int
                      ? r['spot_id'] as int
                      : int.tryParse(r['spot_id']?.toString() ?? '');
              if (rid == sid) {
                row = r;
                break;
              }
            }
          }
        } catch (_) {}
        row ??= rows.cast<Map<String, dynamic>?>().firstWhere(
          (r) => ((r?['spot_name'] ?? '').toString() == baseName),
          orElse: () => null,
        );
        if (row != null) {
          final int? flag =
              (row['flag'] is int)
                  ? row['flag'] as int
                  : int.tryParse(row['flag']?.toString() ?? '');
          if (flag == -1) name = '$baseName (申請中)';
          yomi = ((row['j_yomi'] ?? row['furigana']) ?? '').toString();
        }
      } catch (_) {}
      // タイトル形式: 釣り場名 : 名称 (ふりがな)
      final suffix = yomi.trim().isNotEmpty ? ' ($yomi)' : '';
      return '釣り場名 : $name$suffix';
    } catch (_) {
      return '釣り場名 : ';
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery);
      if (x != null && mounted) {
        _networkImageUrl = null; // ネットワーク画像プレビューはクリア
        _clearImage = false; // 新規選択で取り消し解除
        // 先に即時プレビュー → バックグラウンドで圧縮後に差し替え
        final saved =
            _scrollController.hasClients ? _scrollController.offset : null;
        setState(() => _pickedImage = x);
        if (saved != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollController.hasClients) return;
            final max = _scrollController.position.maxScrollExtent;
            final target = saved.clamp(0.0, max);
            _scrollController.jumpTo(target);
          });
        }
        _compressing = _compressToWebP(x);
        // ignore: unawaited_futures
        _compressing!.then((compressed) {
          if (!mounted) return;
          if (compressed != null) {
            // プレビューはそのまま、送信用にのみ保持
            _uploadImage = compressed;
          }
          _compressing = null;
        });
      }
    } catch (_) {}
  }

  Future<void> _pickFromCamera() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.camera);
      if (x != null && mounted) {
        _networkImageUrl = null; // ネットワーク画像プレビューはクリア
        _clearImage = false; // 新規選択で取り消し解除
        // 先に即時プレビュー → バックグラウンドで圧縮後に差し替え
        final saved =
            _scrollController.hasClients ? _scrollController.offset : null;
        setState(() => _pickedImage = x);
        if (saved != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollController.hasClients) return;
            final max = _scrollController.position.maxScrollExtent;
            final target = saved.clamp(0.0, max);
            _scrollController.jumpTo(target);
          });
        }
        _compressing = _compressToWebP(x);
        // ignore: unawaited_futures
        _compressing!.then((compressed) {
          if (!mounted) return;
          if (compressed != null) {
            _uploadImage = compressed;
          }
          _compressing = null;
        });
      }
    } catch (_) {}
  }

  bool get _isPostEnabled {
    // 釣果/環境ともに概略があれば投稿可能
    final s =
        _postType == 'catch'
            ? _summaryController.text.trim()
            : _envSummaryController.text.trim();
    return s.isNotEmpty;
  }

  void _onChangedAny([_]) {
    if (mounted) setState(() {});
  }

  void _restoreDraftIfAny() {
    if (widget.editMode) return;
    final c = Common.instance;
    if (c.draftType == null) return;
    if (c.draftType == 'catch') {
      _summaryController.text = c.draftSummary ?? _summaryController.text;
      _detailController.text = c.draftDetail ?? _detailController.text;
    } else {
      _envSummaryController.text =
          c.draftEnvSummary ?? _envSummaryController.text;
      _envDetailController.text = c.draftEnvDetail ?? _envDetailController.text;
    }
    final p = (c.draftImagePath ?? '').trim();
    if (p.isNotEmpty) {
      try {
        _pickedImage = XFile(p);
      } catch (_) {}
    }
  }

  Future<void> _tryAutoSubmitAfterAuth() async {
    final c = Common.instance;
    if (!c.draftAutoSubmit) return;
    // 認証済みか確認
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final verified = (info.email.trim().isNotEmpty);
      if (!verified) return;
    } catch (_) {
      return;
    }
    // 投稿可否を再評価
    _onChangedAny('');
    if (!_isPostEnabled) return;
    // フラグを下げてから投稿（多重送信防止）
    c.draftAutoSubmit = false;
    await _submitPost();
  }

  Future<void> _submitPost() async {
    if (_submitting) return;
    // 未認証の場合はアカウント登録フローへ
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      if ((info.email).trim().isEmpty) {
        if (!mounted) return;
        // 送信前のドラフトを保存して自動投稿を指示
        Common.instance.savePostDraft(
          type: _postType,
          summary: _summaryController.text.trim(),
          detail: _detailController.text.trim(),
          envSummary: _envSummaryController.text.trim(),
          envDetail: _envDetailController.text.trim(),
          imagePath: _uploadImage?.path ?? _pickedImage?.path,
          autoSubmit: true,
        );
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => const NewAccountPage(
                  returnToInputPost: true,
                  authPurposeLabel: '投稿',
                ),
          ),
        );
        // 登録画面から戻ったら自動投稿を試行
        await _tryAutoSubmitAfterAuth();
        return;
      }
    } catch (_) {}
    try {
      final latest = await _loadLatestUserInfoForPosting();
      final blockedMessage = _resolvePostBlockedMessage(latest);
      if (blockedMessage != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(blockedMessage)));
        return;
      }
    } catch (_) {}
    setState(() => _submitting = true);
    try {
      // 画像圧縮が未完了の場合は待機
      if (_compressing != null && _uploadImage == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('画像を処理中です。完了までお待ちください…')));
        final res = await _compressing; // 完了待ち
        if (res != null) _uploadImage = res;
      }

      // パラメータ組み立て
      final prefs = await SharedPreferences.getInstance();
      final spotId = prefs.getInt('selected_teibou_id') ?? 0;
      final now = DateTime.now().toLocal();
      final userInfo = await loadUserInfo() ?? await getOrInitUserInfo();
      final postKind = (_postType == 'catch') ? 'catch' : 'other';
      final title =
          _postType == 'catch'
              ? _summaryController.text.trim()
              : _envSummaryController.text.trim();
      final detail =
          _postType == 'catch'
              ? _detailController.text.trim()
              : _envDetailController.text.trim();
      final map = <String, String>{
        'spot_id': spotId.toString(),
        'user_id': userInfo.userId.toString(),
        'post_kind': postKind,
        'title': title,
        'detail': detail,
        'create_at': _formatMySqlDate(now),
        'action': 'insert',
      };
      // exist は常に 0（任意）
      map['exist'] = '0';
      if (_postType == 'catch') {
        final candidateSpotIds = await _buildCandidateSpotIds(spotId);
        map['candidate_spot_ids'] = jsonEncode({
          'candidate_spot_ids': candidateSpotIds,
        });
      }

      final pathToSend = _uploadImage?.path ?? _pickedImage?.path;

      // Multipartで post.php へ送信
      final uri = Uri.parse('${AppConfig.instance.baseUrl}post.php');
      final req = http.MultipartRequest('POST', uri)..fields.addAll(map);
      if (pathToSend != null) {
        final file = await http.MultipartFile.fromPath('file', pathToSend);
        req.files.add(file);
      }
      final resp = await req.send();
      final status = resp.statusCode;
      final httpResp = await http.Response.fromStream(resp);
      if (status == 200) {
        try {
          Common.instance.clearPostDraft();
        } catch (_) {}
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('投稿を送信しました')));
        if (mounted) Navigator.pop(context, true);
      } else {
        String message = '投稿送信に失敗しました (HTTP $status)';
        try {
          final j = jsonDecode(httpResp.body);
          final serverMessage =
              (j is Map) ? (j['message']?.toString() ?? '') : '';
          if (serverMessage.isNotEmpty) {
            message = serverMessage;
          }
        } catch (_) {}
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<UserInfo> _loadLatestUserInfoForPosting() async {
    final local = await loadUserInfo() ?? await getOrInitUserInfo();
    try {
      final remote = await getUserInfoFromServer(uuid: local.uuid, email: null);
      final merged = local.copyWith(
        userId: remote.userId != 0 ? remote.userId : local.userId,
        email: remote.email.isNotEmpty ? remote.email : local.email,
        uuid: remote.uuid.isNotEmpty ? remote.uuid : local.uuid,
        status: remote.status.isNotEmpty ? remote.status : local.status,
        createdAt:
            remote.createdAt.isNotEmpty ? remote.createdAt : local.createdAt,
        nickName: remote.nickName ?? local.nickName,
        reportsBlocked: remote.reportsBlocked,
        reportsBlockedUntil: remote.reportsBlockedUntil,
        reportsBlockedReason: remote.reportsBlockedReason,
        postsBlocked: remote.postsBlocked,
        postsBlockedUntil: remote.postsBlockedUntil,
        postsBlockedReason: remote.postsBlockedReason,
        role: remote.role ?? local.role,
        canReport: remote.canReport,
        photoUrl: remote.photoUrl ?? local.photoUrl,
        photoVersion: remote.photoVersion ?? local.photoVersion,
        clearReportsBlockedUntil: remote.reportsBlockedUntil == null,
        clearReportsBlockedReason: remote.reportsBlockedReason == null,
        clearPostsBlockedUntil: remote.postsBlockedUntil == null,
        clearPostsBlockedReason: remote.postsBlockedReason == null,
      );
      await saveUserInfo(merged);
      return merged;
    } catch (_) {
      return local;
    }
  }

  String? _resolvePostBlockedMessage(UserInfo info) {
    if (info.postsBlocked == 1) {
      return '投稿の送信は停止中です。不適切な利用が確認されました。';
    }
    final until = info.postsBlockedUntil?.trim() ?? '';
    final lower = until.toLowerCase();
    if (until.isEmpty ||
        lower == 'null' ||
        lower == '0' ||
        until == '0000-00-00 00:00:00') {
      return null;
    }
    try {
      final dt = DateTime.parse(until.replaceFirst(' ', 'T')).toLocal();
      if (!dt.isAfter(DateTime.now())) return null;
    } catch (_) {
      return null;
    }
    return '投稿の送信は一時停止中です。不適切な利用が確認されました。';
  }

  Future<void> _saveEdit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      // 画像圧縮が未完了の場合は待機
      if (_compressing != null && _uploadImage == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('画像を処理中です。完了までお待ちください…')));
        final res = await _compressing; // 完了待ち
        if (res != null) _uploadImage = res;
      }

      final now = DateTime.now().toLocal();
      final userInfo = await loadUserInfo() ?? await getOrInitUserInfo();
      final postKind = (_postType == 'catch') ? 'catch' : 'other';
      final title =
          _postType == 'catch'
              ? _summaryController.text.trim()
              : _envSummaryController.text.trim();
      final detail =
          _postType == 'catch'
              ? _detailController.text.trim()
              : _envDetailController.text.trim();
      final postId = widget.editingPostId ?? 0;
      final spotId =
          widget.initialSpotId ??
          (await SharedPreferences.getInstance()).getInt(
            'selected_teibou_id',
          ) ??
          0;
      if (postId <= 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('投稿IDが不明のため、保存できませんでした')));
        return;
      }

      final map = <String, String>{
        'post_id': postId.toString(),
        'spot_id': spotId.toString(),
        'user_id': userInfo.userId.toString(),
        'post_kind': postKind,
        'title': title,
        'detail': detail,
        'action': 'update',
      };
      final pathToSend = _uploadImage?.path; // 新規選択がある場合のみ送信
      if (pathToSend == null && _clearImage) {
        map['clear_image'] = '1';
      }
      final uri = Uri.parse('${AppConfig.instance.baseUrl}post.php');
      final req = http.MultipartRequest('POST', uri)..fields.addAll(map);
      if (pathToSend != null) {
        final file = await http.MultipartFile.fromPath('file', pathToSend);
        req.files.add(file);
      }
      final streamed = await req.send();
      final status = streamed.statusCode;
      final httpResp = await http.Response.fromStream(streamed);
      if (status == 200) {
        String? imagePath;
        String? thumbPath;
        try {
          final j = jsonDecode(httpResp.body);
          if (j is Map) {
            imagePath = j['image_path']?.toString();
            thumbPath = j['thumb_path']?.toString();
          }
        } catch (_) {}
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('投稿を保存しました')));
        if (mounted) {
          final result = {
            'updated': true,
            'title': title,
            'detail': detail,
            'clearedImage': (_clearImage && pathToSend == null),
            if (imagePath != null) 'image_path': imagePath,
            if (thumbPath != null) 'thumb_path': thumbPath,
            'postId': widget.editingPostId,
          };
          Navigator.pop(context, result);
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存に失敗しました (HTTP $status)')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _resolvePostKind() => 'other';

  String _formatMySqlDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Future<List<int>> _buildCandidateSpotIds(int spotId) async {
    try {
      final db = await SioDatabase().database;
      final rows = await db.query(
        'spots',
        where: 'flag NOT IN (?, ?)',
        whereArgs: [-2, -3],
      );
      return buildCatchAreaCandidateSpotIds(
        rows: rows.cast<Map<String, dynamic>>(),
        spotId: spotId,
      );
    } catch (_) {
      return <int>[spotId];
    }
  }

  Future<void> _showImageActionSheet() async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                title: Text('登録内容（${_postType == 'catch' ? '釣果' : '環境'}）'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('写真を撮る'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('ギャラリーから写真を選択する'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickFromGallery();
                },
              ),
              if (_pickedImage != null || (_networkImageUrl ?? '').isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.backspace),
                  title: const Text('画像を取り消す'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _pickedImage = null;
                      _uploadImage = null;
                      _networkImageUrl = null;
                      _clearImage = true;
                    });
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

  // 画像をWebP(品質85)へ変換し、長辺2048pxに縮小
  Future<XFile?> _compressToWebP(XFile original) async {
    try {
      final bytes = await File(original.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      final longSide = w > h ? w : h;
      int targetW = w;
      int targetH = h;
      if (longSide > 2048) {
        final ratio = 2048 / longSide;
        targetW = (w * ratio).round();
        targetH = (h * ratio).round();
      }

      final dir = await getTemporaryDirectory();
      final outPath = p.join(
        dir.path,
        'post_${DateTime.now().millisecondsSinceEpoch}.webp',
      );

      final outFile = await FlutterImageCompress.compressAndGetFile(
        original.path,
        outPath,
        minWidth: targetW,
        minHeight: targetH,
        quality: 85,
        format: CompressFormat.webp,
      );
      if (outFile == null) return null;
      return XFile(outFile.path);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_screenTitle),
        backgroundColor: AppConfig.instance.appBarBackgroundColor,
        foregroundColor: AppConfig.instance.appBarForegroundColor,
        toolbarHeight: 0, // タイトルは本文側に表示（バナーの下）
      ),
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
                    _screenTitle,
                    style: TextStyle(
                      color: AppConfig.instance.appBarForegroundColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child:
                        _submitting
                            ? TextButton.icon(
                              onPressed: null,
                              icon: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color:
                                      AppConfig.instance.appBarForegroundColor,
                                ),
                              ),
                              label: const Text('投稿中…'),
                            )
                            : (widget.editMode
                                ? TextButton.icon(
                                  onPressed: _isPostEnabled ? _saveEdit : null,
                                  icon: const Icon(Icons.save),
                                  label: const Text('保存'),
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        AppConfig
                                            .instance
                                            .appBarForegroundColor,
                                    disabledForegroundColor: AppConfig
                                        .instance
                                        .appBarForegroundColor
                                        .withOpacity(0.3),
                                  ),
                                )
                                : TextButton.icon(
                                  onPressed:
                                      _isPostEnabled ? _submitPost : null,
                                  icon: const Icon(Icons.edit_note),
                                  label: const Text('投稿'),
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        AppConfig
                                            .instance
                                            .appBarForegroundColor,
                                    disabledForegroundColor: AppConfig
                                        .instance
                                        .appBarForegroundColor
                                        .withOpacity(0.3),
                                  ),
                                )),
                  ),
                ],
              ),
            ),
            // 釣り場名表示（白背景のエリア）
            Container(
              height: kToolbarHeight,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              child: FutureBuilder<String>(
                future: _spotTitleText(),
                builder: (context, snap) {
                  final txt = (snap.data ?? '').trim();
                  return Text(
                    txt.isNotEmpty ? txt : '（釣り場未選択）',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
            ),
            // 投稿種別に応じた説明文 + 認証の注意
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.editMode
                        ? '釣果の投稿を編集してください。'
                        : _postType == 'catch'
                        ? '釣果の投稿を入力してください。'
                        : '釣り場の規制/駐車場/トイレなどについての投稿を入力してください。',
                  ),
                  if (_postType == 'catch')
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_rounded,
                            color: Colors.orange,
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '釣果は周辺の釣り場のいずれかとして表示されます。\n'
                              '※自分の投稿は正確な場所で確認できます。',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!_emailVerified)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        '※ 投稿するにはメール認証が必要です。',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 画面本体
            Expanded(
              child: SingleChildScrollView(
                key: const PageStorageKey('input_post_scroll'),
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    if (_postType == 'catch') ...[
                      const Text(
                        '釣果概要（一覧に表示される32桁）',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _summaryController,
                        maxLength: 32,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '例）アジ20cm前後を10匹',
                          counterText: '',
                        ),
                        onChanged: _onChangedAny,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '釣果詳細(500桁)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _detailController,
                        maxLength: 500,
                        minLines: 4,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'サイズ、時間帯、仕掛け、場所の状況など詳しく記載してください',
                        ),
                        onChanged: _onChangedAny,
                      ),
                      const SizedBox(height: 16),
                      // 画像エリア（タップで選択、幅いっぱい・アスペクト比維持で全体表示）
                      InkWell(
                        onTap: _showImageActionSheet,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (_pickedImage == null) {
                              if ((_networkImageUrl ?? '').isNotEmpty) {
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    _networkImageUrl!,
                                    width: constraints.maxWidth,
                                    fit: BoxFit.fitWidth,
                                  ),
                                );
                              }
                              return Container(
                                width: double.infinity,
                                height: 180,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  border: Border.all(
                                    color: Colors.grey.shade400,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.camera_alt,
                                    size: 40,
                                    color: Colors.black54,
                                  ),
                                ),
                              );
                            }
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(_pickedImage!.path),
                                width: constraints.maxWidth,
                                fit: BoxFit.fitWidth,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (_postType == 'env') ...[
                      const Text(
                        '環境概要（一覧に表示される30桁）',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _envSummaryController,
                        maxLength: 30,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '例）駐車場、トイレなどの状況',
                          counterText: '',
                        ),
                        onChanged: _onChangedAny,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '環境詳細（500桁）',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _envDetailController,
                        maxLength: 500,
                        minLines: 4,
                        maxLines: 10,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '駐車場、トイレなどの状況や注意点を詳しく記載してください',
                        ),
                        onChanged: _onChangedAny,
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: _showImageActionSheet,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (_pickedImage == null) {
                              return Container(
                                width: double.infinity,
                                height: 180,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  border: Border.all(
                                    color: Colors.grey.shade400,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.camera_alt,
                                    size: 40,
                                    color: Colors.black54,
                                  ),
                                ),
                              );
                            }
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(_pickedImage!.path),
                                width: constraints.maxWidth,
                                fit: BoxFit.fitWidth,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
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
