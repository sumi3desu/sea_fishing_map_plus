import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/premium_state_notifier.dart' as prem;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'constants.dart';
//import 'dart:io';
import 'profile_edit_page.dart';
import 'user_profile_page.dart';
import 'sio_database.dart';
import 'nearby_map_page.dart';
import 'input_post_page.dart';
import 'new_account_page.dart';
import 'appconfig.dart';
import 'html_view_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'log_print.dart';
//import 'dart:io' show Platform;
import 'main.dart';
//import 'constants.dart';
import 'common.dart';
import 'catch_area_candidates.dart';

class PostDetailPage extends ConsumerStatefulWidget {
  const PostDetailPage({super.key, required this.item});
  final PostDetailItem item;

  @override
  ConsumerState<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends ConsumerState<PostDetailPage> {
  BannerAd? _bannerAd;
  String? _displayNick;
  String? _avatarUrl;
  bool _triedServerAvatar = false;
  bool _liking = false;
  int? _likeCount;
  int? _downCount; // 低評価件数
  int? _myUpDown; // 1=thumb up, 0=thumb down, null/その他=未投票
  bool _disliking = false; // 低評価送信中
  bool _canEdit = false;
  bool _isMine = false;
  String _cacheTs = '';
  bool _updated = false; // 編集で更新されたか（戻り値用）
  bool _imageCleared = false; // 編集で画像を外したか
  String? _overrideImageUrl; // 編集結果で受け取った新しい画像URL
  String? _newImagePath; // 編集結果で受け取った相対 image_path
  String? _newThumbPath; // 編集結果で受け取った相対 thumb_path
  String? _currentTitle;
  String? _currentDetail;

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.item.title;
    _currentDetail = widget.item.detail;
    _loadBanner();
    _fetchAvatarIfAny();
    _loadLikeCount();
    _prepareEditPermission();
  }

  Future<void> _sendLike() async {
    if (_liking) return;
    final pid = widget.item.postId;
    if (pid == null || pid <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('投稿IDが不明のため、送信できませんでした')));
      return;
    }
    setState(() => _liking = true);
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final uri = Uri.parse(
        '${AppConfig.instance.baseUrl}regist_thumb_post.php',
      );
      final resp = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json, text/plain, */*',
            },
            body: {
              'post_id': pid.toString(),
              'user_id': info.userId.toString(),
              'action': 'regist',
              'up_down': '1',
            },
          )
          .timeout(kHttpTimeout);
      if (!mounted) return;
      if (resp.statusCode == 200) {
        String snackMsg = '「いいね」を送信しました';
        try {
          final data = jsonDecode(resp.body);
          final status =
              (data is Map) ? (data['status']?.toString() ?? '') : '';
          if (status == 'success' && data is Map) {
            int? cu;
            int? cd;
            try {
              final cUp = data['count_up'] ?? data['count'];
              if (cUp is int)
                cu = cUp;
              else if (cUp is String)
                cu = int.tryParse(cUp);
            } catch (_) {}
            try {
              final cDown = data['count_down'];
              if (cDown is int)
                cd = cDown;
              else if (cDown is String)
                cd = int.tryParse(cDown);
            } catch (_) {}
            if (mounted) {
              setState(() {
                _likeCount = (cu != null && cu > 0) ? cu : null;
                _downCount = (cd != null && cd > 0) ? cd : null;
                final my = data['my_up_down'];
                if (my is int)
                  _myUpDown = my;
                else if (my is String)
                  _myUpDown = int.tryParse(my);
              });
            }
            final act = (data['action']?.toString() ?? '').toLowerCase();
            if (act == 'remove')
              snackMsg = '「いいね」を解除しました';
            else if (act == 'insert')
              snackMsg = '「いいね」を送信しました';
          } else if (data is Map) {
            final reason = (data['reason']?.toString() ?? '送信に失敗しました');
            snackMsg = reason;
          }
        } catch (_) {}
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(snackMsg)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信に失敗しました（${resp.statusCode}）')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('送信中にエラーが発生しました')));
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _openConfirmRequest() async {
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();

      // 事前に当日送信数を確認し、上限なら画面遷移せずに通知
      try {
        final checkUri = Uri.parse(
          '${AppConfig.instance.baseUrl}get_issues_count.php',
        ).replace(
          queryParameters: {
            'user_id': info.userId.toString(),
            'ts': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        );
        final chk = await http.get(checkUri).timeout(kHttpTimeout);
        if (mounted && chk.statusCode == 200) {
          final j = jsonDecode(chk.body);
          final status = (j is Map) ? (j['status']?.toString() ?? '') : '';
          final reason = (j is Map) ? (j['reason']?.toString() ?? '') : '';
          final count =
              (j is Map)
                  ? int.tryParse(j['count']?.toString() ?? '') ?? -1
                  : -1;
          final limit =
              (j is Map)
                  ? int.tryParse(j['limit']?.toString() ?? '') ?? 10
                  : 10;
          if (status == 'error' || (count >= 0 && count >= limit)) {
            final msg =
                reason.isNotEmpty ? reason : '1日10回までの報告しかできません。本日の上限に達しました。';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                duration: const Duration(seconds: 4),
              ),
            );
            return; // 遷移しない
          }
        }
      } catch (_) {
        // 取得失敗時はブロックせず続行（遷移を優先）
      }
      final pinfo = await PackageInfo.fromPlatform();
      final ver = '${pinfo.version}+${pinfo.buildNumber}';
      final platform =
          Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other');
      final base = Uri.parse('${AppConfig.instance.baseUrl}report_issue.php');
      final qp = {
        'uid': info.userId.toString(),
        'app': ver,
        'platform': platform,
        'from': 'post_detail',
        'ts': DateTime.now().millisecondsSinceEpoch.toString(),
      };
      final url = base.replace(queryParameters: qp).toString();
      final pid = widget.item.postId;
      final title = (pid != null && pid > 0) ? '投稿ID=${pid}の確認のお願い' : '確認のお願い';
      if (!mounted) return;
      final post = <String, String>{
        'category': 'confirm',
        'title': title,
        'post_id': pid.toString(),
      };
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => HtmlViewPage(
                title: '要望・記載ミスなどの報告',
                url: url,
                postParams: post,
              ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('報告ページを開けませんでした')));
    }
  }

  Future<void> _onTapThumbDown() async {
    try {
      final pid = widget.item.postId;
      if (pid == null || pid <= 0) return;
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      // 未認証なら他導線と同様にメール認証へ進める
      if ((info.email).trim().isEmpty) {
        if (!mounted) return;
        final res = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const NewAccountPage(authPurposeLabel: '低評価'),
          ),
        );
        if (res != true) return;
      }
      final latest = await loadUserInfo() ?? await getOrInitUserInfo();
      // 既に低評価済みならダイアログなしで解除。未低評価の場合のみ理由入力を求める
      Map<String, String>? reasonData;
      if (_myUpDown == 0) {
        reasonData = null; // 解除のため理由不要
      } else {
        reasonData = await _promptThumbDownReason();
        if (reasonData == null) return; // キャンセル
      }
      if (_disliking) return;
      setState(() => _disliking = true);
      final reason = reasonData?['reason'] ?? '';
      final reasonText = reasonData?['reason_text'] ?? '';

      final uri = Uri.parse(
        '${AppConfig.instance.baseUrl}regist_thumb_post.php',
      );
      final resp = await http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json, text/plain, */*',
            },
            body: {
              'post_id': pid.toString(),
              'user_id': latest.userId.toString(),
              'action': 'regist',
              'up_down': '0',
              'reason': reason,
              'reason_text': reasonText,
            },
          )
          .timeout(kHttpTimeout);
      if (!mounted) return;
      if (resp.statusCode == 200) {
        String snackMsg = '低評価を送信しました';
        try {
          final data = jsonDecode(resp.body);
          final status =
              (data is Map) ? (data['status']?.toString() ?? '') : '';
          if (status == 'success' && data is Map) {
            int? cu;
            int? cd;
            try {
              final cUp = data['count_up'] ?? data['count'];
              if (cUp is int)
                cu = cUp;
              else if (cUp is String)
                cu = int.tryParse(cUp);
            } catch (_) {}
            try {
              final cDown = data['count_down'];
              if (cDown is int)
                cd = cDown;
              else if (cDown is String)
                cd = int.tryParse(cDown);
            } catch (_) {}
            if (mounted)
              setState(() {
                _likeCount = (cu != null && cu > 0) ? cu : null;
                _downCount = (cd != null && cd > 0) ? cd : null;
                final my = data['my_up_down'];
                if (my is int)
                  _myUpDown = my;
                else if (my is String)
                  _myUpDown = int.tryParse(my);
              });
            final act = (data['action']?.toString() ?? '').toLowerCase();
            if (act == 'remove')
              snackMsg = '低評価を解除しました';
            else if (act == 'insert')
              snackMsg = '低評価を送信しました';
          } else if (data is Map) {
            final reason = (data['reason']?.toString() ?? '送信に失敗しました');
            snackMsg = reason;
          }
        } catch (_) {}
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(snackMsg)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信に失敗しました（${resp.statusCode}）')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('送信中にエラーが発生しました')));
    } finally {
      if (mounted) setState(() => _disliking = false);
    }
  }

  Future<Map<String, String>?> _promptThumbDownReason() async {
    final reasons = <String>[
      '不適切な内容',
      '誤った釣り場情報',
      '虚偽の投稿',
      '広告・宣伝',
      'スパム・いたずら',
      '釣り禁止エリアの可能性',
      'その他',
    ];
    String? selected;
    final controller = TextEditingController();
    return showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final canSend = (selected != null && selected!.isNotEmpty);
            return AlertDialog(
              title: const Text('低評価の理由'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...reasons.map(
                      (r) => RadioListTile<String>(
                        title: Text(r),
                        value: r,
                        groupValue: selected,
                        onChanged: (v) => setStateDialog(() => selected = v),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('補足説明（200桁まで）'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: controller,
                      maxLines: 3,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: '任意で入力してください',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed:
                      canSend
                          ? () {
                            final text = controller.text.trim();
                            Navigator.of(
                              ctx,
                            ).pop({'reason': selected!, 'reason_text': text});
                          }
                          : null,
                  child: const Text('送信'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _loadBanner() {
    final isPremium = ref.read(prem.premiumStateProvider).isPremium;
    if (isPremium) return;
    _bannerAd = BannerAd(
      size: AdSize.banner,
      adUnitId: 'ca-app-pub-3940256099942544/2934735716',
      listener: BannerAdListener(
        onAdLoaded: (_) => mounted ? setState(() {}) : null,
        onAdFailedToLoad: (ad, e) => ad.dispose(),
      ),
      request: const AdRequest(),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _openNearbyMap() async {
    try {
      final sid = widget.item.spotId;
      if (sid == null || sid <= 0) return;
      final db = await SioDatabase().database;
      final rows = await db.query('teibou');
      Map<String, dynamic>? src;
      for (final r in rows) {
        if ((r['port_id']?.toString() ?? '') == sid.toString()) {
          src = r;
          break;
        }
      }
      if (src == null) return;
      final double sLat = (src['latitude'] as num).toDouble();
      final double sLng = (src['longitude'] as num).toDouble();
      final String spotName = (src['port_name'] ?? '').toString();
      final int? prefId =
          src['todoufuken_id'] is int
              ? src['todoufuken_id'] as int
              : int.tryParse(src['todoufuken_id']?.toString() ?? '') ??
                  int.tryParse(src['pref_id_from_port']?.toString() ?? '');
      if (_isMine) {
        await Common.instance.saveSelectedTeibou(
          spotName,
          Common.instance.tidePoint,
          id: sid,
          lat: sLat,
          lng: sLng,
          prefId: prefId,
        );
        Common.instance.shouldJumpPage = true;
        Common.instance.requestNavigateToTidePage();
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }
      final points = buildCatchAreaPoints(
        rows: rows.cast<Map<String, dynamic>>(),
        spotId: sid,
        logger: logPrint,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NearbyMapPage(points: points)),
      );
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prepareNickName();
  }

  Future<void> _prepareEditPermission() async {
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final me =
          (widget.item.userId != null) && (info.userId == widget.item.userId);
      final isAdmin = ((info.role ?? '').toLowerCase() == 'admin');
      if (mounted) {
        setState(() {
          _isMine = me;
          _canEdit = me || isAdmin;
        });
      }
    } catch (_) {}
  }

  void _openEdit() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder:
                (_) => InputPost(
                  initialType: 'catch',
                  editMode: true,
                  initialSummary: widget.item.title,
                  initialDetail: widget.item.detail,
                  initialImageUrl:
                      (widget.item.imageUrl != null)
                          ? _withTs(widget.item.imageUrl!)
                          : null,
                  editingPostId: widget.item.postId,
                  initialSpotId: widget.item.spotId,
                ),
          ),
        )
        .then((res) {
          if (!mounted) return;
          if (res == true) {
            setState(() {
              _cacheTs = DateTime.now().millisecondsSinceEpoch.toString();
              _updated = true;
            });
          } else if (res is Map) {
            final updated = (res['updated'] == true);
            final cleared = (res['clearedImage'] == true);
            if (updated) {
              setState(() {
                _updated = true;
                _currentTitle = res['title']?.toString() ?? _currentTitle;
                _currentDetail = res['detail']?.toString() ?? _currentDetail;
                if (cleared) {
                  _imageCleared = true;
                  _overrideImageUrl = null;
                  _newImagePath = null;
                  _newThumbPath = null;
                } else {
                  _cacheTs = DateTime.now().millisecondsSinceEpoch.toString();
                  final ip = (res['image_path']?.toString() ?? '').trim();
                  final tp = (res['thumb_path']?.toString() ?? '').trim();
                  _newImagePath = ip.isNotEmpty ? ip : null;
                  _newThumbPath = tp.isNotEmpty ? tp : null;
                  final rel = ip.isNotEmpty ? ip : (tp.isNotEmpty ? tp : '');
                  if (rel.isNotEmpty) {
                    _overrideImageUrl =
                        AppConfig.instance.baseUrl + 'post_images/' + rel;
                  }
                }
              });
            }
          }
        });
  }

  void _openDelete() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder:
                (_) => _DeletePostPage(
                  item: widget.item,
                  currentTitle: _currentTitle ?? widget.item.title ?? '',
                  currentDetail: _currentDetail ?? widget.item.detail ?? '',
                ),
          ),
        )
        .then((res) {
          if (!mounted) return;
          if (res is Map && res['deleted'] == true) {
            Navigator.pop(context, res);
          }
        });
  }

  Future<void> _prepareNickName() async {
    // まずはサーバから受け取ったニックネームがあれば優先
    final initial = (widget.item.nickName ?? '').trim();
    if (initial.isNotEmpty) {
      setState(() => _displayNick = initial);
      return;
    }
    // 自分の投稿ならローカルのUserInfoから補完
    try {
      final info = await loadUserInfo();
      if (info != null &&
          widget.item.userId != null &&
          info.userId == widget.item.userId) {
        final localNick = (info.nickName ?? '').trim();
        if (localNick.isNotEmpty && mounted)
          setState(() => _displayNick = localNick);
      }
    } catch (_) {}
  }

  Future<void> _fetchAvatarIfAny() async {
    try {
      final uid = widget.item.userId;
      // 自分自身の投稿でローカルに photoUrl があれば優先
      try {
        final info = await loadUserInfo();
        if (info != null) {
          final localPhoto = (info.photoUrl ?? '').trim();
          final localNick = (info.nickName ?? '').trim();
          final itemNick = (widget.item.nickName ?? '').trim();
          // 1) userId が一致（ローカルファイルの存在チェック付き）
          if (uid != null &&
              uid > 0 &&
              info.userId == uid &&
              localPhoto.isNotEmpty) {
            if (localPhoto.startsWith('http')) {
              if (mounted) setState(() => _avatarUrl = localPhoto);
              return;
            } else {
              try {
                final p =
                    localPhoto.startsWith('file://')
                        ? Uri.parse(localPhoto).toFilePath()
                        : localPhoto;
                final f = File(p);
                final exists = await f.exists();
                final len = exists ? await f.length() : 0;
                debugPrint('[avatar] local exists=$exists size=$len path=$p');
                if (exists && len > 0) {
                  if (mounted) setState(() => _avatarUrl = localPhoto);
                  return;
                }
              } catch (e) {
                debugPrint('[avatar] local check error: $e');
              }
            }
          }
          // 2) userId が未設定でも、ニックネーム一致なら採用
          if ((uid == null || uid <= 0) &&
              localPhoto.isNotEmpty &&
              localNick.isNotEmpty &&
              localNick == itemNick) {
            if (localPhoto.startsWith('http')) {
              if (mounted) setState(() => _avatarUrl = localPhoto);
              return;
            } else {
              try {
                final p =
                    localPhoto.startsWith('file://')
                        ? Uri.parse(localPhoto).toFilePath()
                        : localPhoto;
                final f = File(p);
                final exists = await f.exists();
                final len = exists ? await f.length() : 0;
                debugPrint(
                  '[avatar] local(nick) exists=$exists size=$len path=$p',
                );
                if (exists && len > 0) {
                  if (mounted) setState(() => _avatarUrl = localPhoto);
                  return;
                }
              } catch (e) {
                debugPrint('[avatar] local(nick) check error: $e');
              }
            }
          }
        }
      } catch (_) {}
      if (uid == null || uid <= 0) return;

      // サーバから対象ユーザのプロフィール画像パスを取得
      final uri = Uri.parse(
        '${AppConfig.instance.baseUrl}get_profile_images.php',
      );
      final resp = await http
          .post(uri, body: {'user_id': uid.toString()})
          .timeout(kHttpTimeout);
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body);
      if (data is Map && data['status'] == 'success') {
        final String? rel = data['avatar_path'] as String?;
        if (rel != null && rel.isNotEmpty) {
          final String url = '${AppConfig.instance.baseUrl}user_images/' + rel;
          if (mounted) setState(() => _avatarUrl = url);
        }
      }
    } catch (_) {}
  }

  Future<void> _fallbackToServerAvatar() async {
    if (_triedServerAvatar) return;
    _triedServerAvatar = true;
    try {
      final uid = widget.item.userId;
      if (uid == null || uid <= 0) return;
      final uri = Uri.parse(
        '${AppConfig.instance.baseUrl}get_profile_images.php',
      );
      final resp = await http
          .post(uri, body: {'user_id': uid.toString()})
          .timeout(kHttpTimeout);
      debugPrint('[avatar] fallback status=${resp.statusCode}');
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body);
      debugPrint('[avatar] fallback body=$data');
      if (data is Map && data['status'] == 'success') {
        final String? rel = data['avatar_path'] as String?;
        if (rel != null && rel.isNotEmpty) {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final String url =
              '${AppConfig.instance.baseUrl}user_images/' + rel + '?ts=$ts';
          if (mounted) setState(() => _avatarUrl = url);
        }
      }
    } catch (e) {
      debugPrint('[avatar] fallback error: $e');
    }
  }

  Future<void> _loadLikeCount() async {
    try {
      final pid = widget.item.postId;
      if (pid == null || pid <= 0) return;
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final uri = Uri.parse(
        '${AppConfig.instance.baseUrl}regist_thumb_post.php',
      );
      final resp = await http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json, text/plain, */*',
            },
            body: {
              'post_id': pid.toString(),
              'user_id': info.userId.toString(),
              'action': 'get',
            },
          )
          .timeout(kHttpTimeout);
      if (!mounted) return;
      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(resp.body);
          if (data is Map && (data['status']?.toString() ?? '') == 'success') {
            int? cu;
            int? cd;
            try {
              final cUp = data['count_up'] ?? data['count'];
              if (cUp is int)
                cu = cUp;
              else if (cUp is String)
                cu = int.tryParse(cUp);
            } catch (_) {}
            try {
              final cDown = data['count_down'];
              if (cDown is int)
                cd = cDown;
              else if (cDown is String)
                cd = int.tryParse(cDown);
            } catch (_) {}
            if (mounted)
              setState(() {
                _likeCount = (cu != null && cu > 0) ? cu : null;
                _downCount = (cd != null && cd > 0) ? cd : null;
                final my = data['my_up_down'];
                if (my is int)
                  _myUpDown = my;
                else if (my is String)
                  _myUpDown = int.tryParse(my);
              });
          } else {
            final reason =
                (data is Map)
                    ? (data['reason']?.toString() ?? '件数の取得に失敗しました')
                    : '件数の取得に失敗しました';
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(reason)));
          }
        } catch (_) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('件数の解析に失敗しました')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('件数の取得に失敗しました（HTTP ${resp.statusCode}）')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('件数の取得エラー: $e')));
    }
  }

  String _kindLabel(int? kind) {
    switch (kind) {
      case 1:
        return '釣果';
      case 2:
        return '規制';
      case 3:
        return '駐車場';
      case 4:
        return 'トイレ';
      case 5:
        return '釣餌';
      case 6:
        return 'コンビニ';
      case 9:
        return 'その他';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final isEnv = (it.postKind ?? 1) != 1;
    String? dateLabel;
    if ((it.createAt ?? '').isNotEmpty) {
      // 'YYYY-MM-DD HH:MM:SS' または ISO8601 を想定
      try {
        final raw = it.createAt!;
        DateTime dt;
        if (raw.contains('T')) {
          dt = DateTime.parse(raw).toLocal();
        } else {
          // MySQL DATETIME をパース
          dt = DateTime.parse(raw.replaceFirst(' ', 'T')).toLocal();
        }
        String two(int v) => v.toString().padLeft(2, '0');
        dateLabel =
            '${dt.year}/${two(dt.month)}/${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
      } catch (_) {
        dateLabel = it.createAt;
      }
    }
    return WillPopScope(
      onWillPop: () async {
        final map = {
          'updated': _updated,
          'clearedImage': _imageCleared,
          'postId': widget.item.postId,
          'deleted': false,
        };
        if (_newImagePath != null) map['image_path'] = _newImagePath;
        if (_newThumbPath != null) map['thumb_path'] = _newThumbPath;
        Navigator.pop(context, map);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('投稿詳細'),
          backgroundColor: AppConfig.instance.appBarBackgroundColor,
          foregroundColor: AppConfig.instance.appBarForegroundColor,
          toolbarHeight: 0,
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
              Container(
                height: kToolbarHeight,
                color: AppConfig.instance.appBarBackgroundColor,
                child: Row(
                  children: [
                    BackButton(
                      color: AppConfig.instance.appBarForegroundColor,
                      onPressed: () {
                        final map = {
                          'updated': _updated,
                          'clearedImage': _imageCleared,
                          'postId': widget.item.postId,
                          'deleted': false,
                        };
                        if (_newImagePath != null)
                          map['image_path'] = _newImagePath;
                        if (_newThumbPath != null)
                          map['thumb_path'] = _newThumbPath;
                        Navigator.pop(context, map);
                      },
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text(
                        '投稿詳細',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (widget.item.showNearbyButton &&
                        (widget.item.spotId ?? 0) > 0 &&
                        ambiguous_plevel != 0)
                      TextButton.icon(
                        onPressed: _openNearbyMap,
                        icon: const Icon(Icons.map),
                        label: Text(_canEdit ? '釣れた場所' : '釣れたエリア'),
                        style: TextButton.styleFrom(
                          foregroundColor:
                              AppConfig.instance.appBarForegroundColor,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
              if (_canEdit)
                Container(
                  height: 44,
                  width: double.infinity,
                  color: const Color(0xFF0D47A1),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: _openEdit,
                        icon: const Icon(Icons.edit),
                        label: const Text('編集'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _openDelete,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('削除'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ニックネーム + 日時（最上段）
                      if ((_displayNick ?? '').isNotEmpty ||
                          (dateLabel ?? '').isNotEmpty ||
                          ((_avatarUrl ?? '').isNotEmpty)) ...[
                        Row(
                          children: [
                            if ((_avatarUrl ?? '').isNotEmpty) ...[
                              Builder(
                                builder: (context) {
                                  ImageProvider? provider;
                                  final url = _avatarUrl!;
                                  try {
                                    if (url.startsWith('http')) {
                                      final buster =
                                          url.contains('?') ? '&' : '?';
                                      provider = NetworkImage(
                                        '$url${buster}ts=${DateTime.now().millisecondsSinceEpoch}',
                                      );
                                    } else {
                                      final p =
                                          url.startsWith('file://')
                                              ? Uri.parse(url).toFilePath()
                                              : url;
                                      final f = File(p);
                                      final exists = f.existsSync();
                                      debugPrint(
                                        '[avatar] build file exists=$exists path=$p',
                                      );
                                      provider = exists ? FileImage(f) : null;
                                      if (!exists) {
                                        // ローカルが無ければサーバーフォールバック
                                        _fallbackToServerAvatar();
                                      }
                                    }
                                  } catch (e) {
                                    debugPrint(
                                      '[avatar] provider build error: $e',
                                    );
                                  }
                                  return Row(
                                    children: [
                                      InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () async {
                                          final uid = widget.item.userId;
                                          final me = await loadUserInfo();
                                          if (uid != null &&
                                              me != null &&
                                              uid == me.userId) {
                                            if (!mounted) return;
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder:
                                                    (_) =>
                                                        const ProfileEditPage(),
                                              ),
                                            );
                                          } else if (uid != null && uid > 0) {
                                            if (!mounted) return;
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder:
                                                    (_) => UserProfilePage(
                                                      userId: uid,
                                                      nickName: _displayNick,
                                                    ),
                                              ),
                                            );
                                          }
                                        },
                                        child: CircleAvatar(
                                          radius: 20,
                                          backgroundColor: Colors.grey.shade300,
                                          backgroundImage: provider,
                                          onBackgroundImageError: (e, st) {
                                            debugPrint(
                                              'avatar decode error: $e',
                                            );
                                            _fallbackToServerAvatar();
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                  );
                                },
                              ),
                            ] else if ((_displayNick ?? '').isNotEmpty) ...[
                              const Icon(
                                Icons.person,
                                size: 20,
                                color: Colors.black54,
                              ),
                              const SizedBox(width: 6),
                            ],
                            if ((_displayNick ?? '').isNotEmpty)
                              Text(
                                _displayNick!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                            if (it.postId != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                'ID：${it.postId}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                            if (((_displayNick ?? '').isNotEmpty ||
                                    (_avatarUrl ?? '').isNotEmpty) &&
                                (dateLabel ?? '').isNotEmpty)
                              const SizedBox(width: 12),
                            if ((dateLabel ?? '').isNotEmpty) ...[
                              const Icon(
                                Icons.schedule,
                                size: 16,
                                color: Colors.black54,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                dateLabel!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],

                      if (isEnv) ...[
                        Text(
                          _kindLabel(it.postKind),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (it.postKind != 9)
                          Text(
                            (it.exist == 1) ? 'あり' : 'なし',
                            style: const TextStyle(fontSize: 14),
                          ),
                        const SizedBox(height: 8),
                      ],
                      if ((_currentTitle ?? '').isNotEmpty) ...[
                        Text(
                          _currentTitle!,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if ((_currentDetail ?? '').isNotEmpty) ...[
                        Text(
                          _currentDetail!,
                          style: const TextStyle(fontSize: 15, height: 1.6),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (!_imageCleared)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Builder(
                            builder: (_) {
                              final raw = _overrideImageUrl ?? it.imageUrl;
                              if (raw == null || raw.isEmpty)
                                return const SizedBox.shrink();
                              return Image.network(
                                _withTs(raw),
                                fit: BoxFit.fitWidth,
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 16),
                      const Divider(height: 24),
                      // フィードバックセクション（1行・左右分割・フラット）
                      Material(
                        color: Colors.transparent,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(12),
                                    bottomLeft: Radius.circular(12),
                                  ),
                                  onTap: _sendLike,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.thumb_up,
                                          color: Colors.blue,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _likeCount != null
                                              ? _likeCount.toString()
                                              : '',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 40,
                                child: VerticalDivider(
                                  width: 1,
                                  thickness: 1,
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                  onTap: _onTapThumbDown,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.thumb_down,
                                          color: Colors.redAccent,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _downCount != null
                                              ? _downCount.toString()
                                              : '',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _CacheBuster on _PostDetailPageState {
  String _withTs(String url) {
    if (_updated && _cacheTs.isNotEmpty) {
      final sep = url.contains('?') ? '&' : '?';
      return '$url${sep}ts=${_cacheTs}';
    }
    return url;
  }
}

class PostDetailItem {
  final int? userId;
  final int? postId;
  final int? postKind;
  final int? exist;
  final String? title;
  final String? detail;
  final String? imageUrl;
  final String? nickName;
  final String? createAt;
  final int? spotId;
  final bool showNearbyButton; // 釣果グリッドから来た場合に true
  PostDetailItem({
    this.userId,
    this.postId,
    this.postKind,
    this.exist,
    this.title,
    this.detail,
    this.imageUrl,
    this.nickName,
    this.createAt,
    this.spotId,
    this.showNearbyButton = false,
  });
}

class _DeletePostPage extends ConsumerStatefulWidget {
  const _DeletePostPage({
    required this.item,
    required this.currentTitle,
    required this.currentDetail,
  });

  final PostDetailItem item;
  final String currentTitle;
  final String currentDetail;

  @override
  ConsumerState<_DeletePostPage> createState() => _DeletePostPageState();
}

class _DeletePostPageState extends ConsumerState<_DeletePostPage> {
  final TextEditingController _reasonController = TextEditingController();
  BannerAd? _bannerAd;
  bool _submitting = false;
  String? _reasonError;

  String _withDeleteTs(String url) {
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}ts=${DateTime.now().millisecondsSinceEpoch}';
  }

  void _ensureBannerLoaded(bool isPremium) {
    if (isPremium || _bannerAd != null) return;
    _bannerAd = BannerAd(
      size: AdSize.banner,
      adUnitId:
          Platform.isIOS
              ? 'ca-app-pub-3940256099942544/2934735716'
              : 'ca-app-pub-3940256099942544/6300978111',
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
          if (mounted) setState(() {});
        },
        onAdLoaded: (_) {
          if (mounted) setState(() {});
        },
      ),
      request: const AdRequest(),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() {
        _reasonError = '削除理由を入力してください';
      });
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            content: const Text('削除してよろしいですか'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('はい'),
              ),
            ],
          ),
    );
    if (ok != true) return;
    setState(() {
      _submitting = true;
      _reasonError = null;
    });
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final uri = Uri.parse('${AppConfig.instance.baseUrl}post.php');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'action': 'delete',
              'post_id': (widget.item.postId ?? 0).toString(),
              'user_id': info.userId.toString(),
              'delete_reason': reason,
            },
          )
          .timeout(kHttpTimeout);
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['status']?.toString() == 'success') {
          Navigator.pop(context, {
            'deleted': true,
            'postId': widget.item.postId,
          });
          return;
        }
        final message =
            (data is Map ? data['message']?.toString() : null) ?? '削除に失敗しました';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除に失敗しました（HTTP ${resp.statusCode}）')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final premiumState = ref.watch(prem.premiumStateProvider);
    if (premiumState.isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('投稿の削除'),
          backgroundColor: AppConfig.instance.appBarBackgroundColor,
          foregroundColor: AppConfig.instance.appBarForegroundColor,
          toolbarHeight: 0,
        ),
        body: const SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }
    final isPremium = premiumState.isPremium;
    _ensureBannerLoaded(isPremium);
    return Scaffold(
      appBar: AppBar(
        title: const Text('投稿の削除'),
        backgroundColor: AppConfig.instance.appBarBackgroundColor,
        foregroundColor: AppConfig.instance.appBarForegroundColor,
        toolbarHeight: 0,
      ),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (!isPremium && _bannerAd != null)
                  Container(
                    alignment: Alignment.center,
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
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
                      const Expanded(
                        child: Text(
                          '投稿の削除',
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextButton.icon(
                          onPressed: _submitting ? null : _delete,
                          icon:
                              _submitting
                                  ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color:
                                          AppConfig
                                              .instance
                                              .appBarForegroundColor,
                                    ),
                                  )
                                  : const Icon(Icons.delete_outline),
                          label: const Text('削除'),
                          style: TextButton.styleFrom(
                            foregroundColor:
                                AppConfig.instance.appBarForegroundColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '削除理由',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reasonController,
                      maxLength: 255,
                      minLines: 3,
                      maxLines: 5,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: '削除理由を入力してください',
                        errorText: _reasonError,
                      ),
                      onChanged: (_) {
                        if (_reasonError != null) {
                          setState(() {
                            _reasonError = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '概要',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: TextEditingController(
                        text: widget.currentTitle,
                      ),
                      readOnly: true,
                      maxLength: 32,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '詳細',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: TextEditingController(
                        text: widget.currentDetail,
                      ),
                      readOnly: true,
                      minLines: 4,
                      maxLines: 8,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if ((widget.item.imageUrl ?? '').isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        '画像',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _withDeleteTs(widget.item.imageUrl!),
                          fit: BoxFit.fitWidth,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
