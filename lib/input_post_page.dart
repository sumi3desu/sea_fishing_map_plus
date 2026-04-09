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
import 'package:http/http.dart' as http;
import 'dart:io';
import 'appconfig.dart';
import 'dart:convert';
import 'sio_database.dart';
import 'common.dart';
import 'package:flutter/cupertino.dart' show CupertinoSegmentedControl;

class InputPost extends StatefulWidget {
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
  State<InputPost> createState() => _InputPostState();
}

class _InputPostState extends State<InputPost> {
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
  final List<String> _envCategories = const ['規制', '駐車場', 'トイレ', '釣餌', 'コンビニ', 'その他'];
  String? _selectedEnvCategory;

  // 釣果入力
  final TextEditingController _summaryController = TextEditingController();
  final TextEditingController _detailController = TextEditingController();

  // 環境入力
  String? _envAvailability; // 'あり' or 'なし'
  final TextEditingController _envSummaryController = TextEditingController(); // 30桁
  final TextEditingController _envDetailController = TextEditingController(); // 1000桁

  @override
  void initState() {
    super.initState();
    _postType = (widget.initialType == 'env') ? 'env' : 'catch';
    _loadBanner();
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
  }

  void _loadBanner() {
    _bannerAd = BannerAd(
      size: AdSize.banner,
      adUnitId: 'ca-app-pub-3940256099942544/2934735716', // TEST用広告ID（釣り場詳細/一覧/日付と同じ）
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
      final baseName = common.selectedTeibouName.isNotEmpty ? common.selectedTeibouName : common.tidePoint;
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
              final rid = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
              if (rid == sid) { row = r; break; }
            }
          }
        } catch (_) {}
        // 名前一致フォールバック
        row ??= rows.cast<Map<String, dynamic>?>().firstWhere(
          (r) => ((r?['port_name'] ?? '').toString() == baseName),
          orElse: () => null,
        );
        final int? flag = row == null ? null : (row['flag'] is int ? row['flag'] as int : int.tryParse(row['flag']?.toString() ?? ''));
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
      final baseName = common.selectedTeibouName.isNotEmpty ? common.selectedTeibouName : common.tidePoint;
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
              final rid = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
              if (rid == sid) { row = r; break; }
            }
          }
        } catch (_) {}
        row ??= rows.cast<Map<String, dynamic>?>().firstWhere(
          (r) => ((r?['port_name'] ?? '').toString() == baseName),
          orElse: () => null,
        );
        if (row != null) {
          final int? flag = (row['flag'] is int) ? row['flag'] as int : int.tryParse(row['flag']?.toString() ?? '');
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
        final saved = _scrollController.hasClients ? _scrollController.offset : null;
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
        final saved = _scrollController.hasClients ? _scrollController.offset : null;
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
    final s = _postType == 'catch' ? _summaryController.text.trim() : _envSummaryController.text.trim();
    return s.isNotEmpty;
  }

  void _onChangedAny([_]) {
    if (mounted) setState(() {});
  }

  Future<void> _submitPost() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      // 画像圧縮が未完了の場合は待機
      if (_compressing != null && _uploadImage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('画像を処理中です。完了までお待ちください…')),
        );
        final res = await _compressing; // 完了待ち
        if (res != null) _uploadImage = res;
      }

      // パラメータ組み立て
      final prefs = await SharedPreferences.getInstance();
      final spotId = prefs.getInt('selected_teibou_id') ?? 0;
      final now = DateTime.now().toLocal();
      final userInfo = await loadUserInfo() ?? await getOrInitUserInfo();
      final postKind = (_postType == 'catch') ? 'catch' : 'other';
      final title = _postType == 'catch' ? _summaryController.text.trim() : _envSummaryController.text.trim();
      final detail = _postType == 'catch' ? _detailController.text.trim() : _envDetailController.text.trim();
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
      if (status == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('投稿を送信しました')));
        if (mounted) Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('投稿送信に失敗しました (HTTP $status)')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _saveEdit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      // 画像圧縮が未完了の場合は待機
      if (_compressing != null && _uploadImage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('画像を処理中です。完了までお待ちください…')),
        );
        final res = await _compressing; // 完了待ち
        if (res != null) _uploadImage = res;
      }

      final now = DateTime.now().toLocal();
      final userInfo = await loadUserInfo() ?? await getOrInitUserInfo();
      final postKind = (_postType == 'catch') ? 'catch' : 'other';
      final title = _postType == 'catch' ? _summaryController.text.trim() : _envSummaryController.text.trim();
      final detail = _postType == 'catch' ? _detailController.text.trim() : _envDetailController.text.trim();
      final postId = widget.editingPostId ?? 0;
      final spotId = widget.initialSpotId ?? (await SharedPreferences.getInstance()).getInt('selected_teibou_id') ?? 0;
      if (postId <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('投稿IDが不明のため、保存できませんでした')));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('投稿を保存しました')));
        if (mounted) {
          final result = {
            'updated': true,
            'clearedImage': (_clearImage && pathToSend == null),
            if (imagePath != null) 'image_path': imagePath,
            if (thumbPath != null) 'thumb_path': thumbPath,
            'postId': widget.editingPostId,
          };
          Navigator.pop(context, result);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存に失敗しました (HTTP $status)')));
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
        title: const Text('投稿入力'),
        backgroundColor: AppConfig.instance.appBarBackgroundColor,
        foregroundColor: AppConfig.instance.appBarForegroundColor,
        toolbarHeight: 0, // タイトルは本文側に表示（バナーの下）
      ),
      body: SafeArea(
        child: Column(
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
                  '投稿入力',
                  style: TextStyle(
                    color: AppConfig.instance.appBarForegroundColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _submitting
                      ? TextButton.icon(
                          onPressed: null,
                          icon: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppConfig.instance.appBarForegroundColor,
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
                                foregroundColor: AppConfig.instance.appBarForegroundColor,
                                disabledForegroundColor: AppConfig.instance.appBarForegroundColor.withOpacity(0.3),
                              ),
                            )
                          : TextButton.icon(
                              onPressed: _isPostEnabled ? _submitPost : null,
                              icon: const Icon(Icons.send),
                              label: const Text('投稿'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppConfig.instance.appBarForegroundColor,
                                disabledForegroundColor: AppConfig.instance.appBarForegroundColor.withOpacity(0.3),
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
                  style: const TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
          ),
          // 種別切替（釣果/環境）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.white,
            child: Align(
              alignment: Alignment.centerLeft,
              child: CupertinoSegmentedControl<String>(
                groupValue: _postType,
                padding: const EdgeInsets.all(0),
                children: const {
                  'catch': Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Text('釣果')),
                  'env': Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Text('環境')),
                },
                onValueChanged: (val) {
                  setState(() {
                    _postType = (val == 'env') ? 'env' : 'catch';
                    // 入力可否などを即時再評価
                    _onChangedAny('');
                  });
                  // 投稿一覧の選択状態としても反映（起動中は維持）
                  try { Common.instance.setPostListMode(_postType); } catch (_) {}
                },
              ),
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
                      '釣果詳細(1024桁)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _detailController,
                      maxLength: 1024,
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
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Icon(Icons.camera_alt, size: 40, color: Colors.black54),
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
                    const Text('環境概要（一覧に表示される30桁）', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    const Text('環境詳細（1000桁）', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _envDetailController,
                      maxLength: 1000,
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
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Icon(Icons.camera_alt, size: 40, color: Colors.black54),
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
