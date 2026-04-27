import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ConsumerStatefulWidget, ConsumerState;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'appconfig.dart';
import 'constants.dart';
import 'catch_area_candidates.dart';
import 'post_detail_page.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'common.dart';
import 'main.dart';
import 'sio_info.dart';
import 'sio.dart';
import 'sio_database.dart';
import 'set_date_page.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as am;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'dart:math' as math;
import 'dart:io' show Platform;
import 'package:latlong2/latlong.dart';
import 'dart:ui' as ui;
import 'package:geolocator/geolocator.dart';
import 'spot_apply_form_page.dart';
import 'package:flutter/cupertino.dart' show CupertinoSegmentedControl;
import 'new_account_page.dart';
import 'providers/premium_state_notifier.dart' as prem;

// 紺（潮汐画面の背景色）
const Color _navyBg = Color(0xFF001F3F);

Future<String?> _buildCatchAreaSpotIdsCsv(int? spotId) async {
  if (spotId == null || spotId <= 0 || ambiguousLevel == 0) return null;
  try {
    final db = await SioDatabase().database;
    final rows = await db.query('teibou');
    final ids = buildCatchAreaCandidateSpotIds(
      rows: rows.cast<Map<String, dynamic>>(),
      spotId: spotId,
    );
    if (ids.isEmpty) return null;
    return ids.join(',');
  } catch (_) {
    return null;
  }
}

class TidePage extends StatefulWidget {
  const TidePage({Key? key}) : super(key: key);

  @override
  State<TidePage> createState() => TidePageState();
}

class TidePageState extends State<TidePage> {
  int _lastStartApplyModeTick = Common.instance.startApplyModeTick;
  int _catchRefreshTick = 0;
  int _envRefreshTick = 0;
  final GlobalKey<_FishingInfoPaneState> _fishingPaneKey =
      GlobalKey<_FishingInfoPaneState>();

  //static bool cacheMoon = false;

  // 60秒ごとに画面更新するタイマー
  late Timer _timer;

  // 月画像ドラッグ状態はローカル共有変数を使用（_SlidingContent内で利用）

  @override
  void initState() {
    super.initState();
    _initData();

    // タイマーをセット（60秒ごとに setState() して画面を更新）
    _timer = Timer.periodic(const Duration(seconds: 60), (Timer timer) {
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    if (Common.instance.preLoadMoonFile == false) {
      Common.instance.preLoadMoonFile = true;
      // すべての29画像を一括でプリロード
      for (String imagePath in Common.instance.lunarPhaseImagePaths) {
        precacheImage(AssetImage('assets/moon/$imagePath'), context);
      }
    }

    final common = Provider.of<Common>(context);
    if (common.shouldJumpPage) {
      await _initData2(common.tideDate);
      common.shouldJumpPage = false;
    }
  }

  Future<void> _initData() async {
    // 初回の潮汐データ取得
    await Common.instance.getTide(true, Common.instance.tideDate);
    setState(() {});
  }

  // ページ切り替え時に、該当の日付の潮汐データを再取得する
  Future<void> _initData2(DateTime newDate) async {
    await Common.instance.getTide(true, newDate);
  }

  void refreshTide(DateTime newDate) {
    _initData2(newDate);
    setState(() {});
  }

  // 外部から釣果リストのみの再読み込みを要求するためのAPI
  void forceReloadCatchList() {
    setState(() {
      _catchRefreshTick++;
    });
  }

  // 外部から投稿一覧シート全体の再読み込みを要求
  void forceReloadPostList() {
    try {
      _fishingPaneKey.currentState?.reloadPostList();
    } catch (_) {}
  }

  bool get isMapTabSelected => true;

  Future<void> showMapTab() async {}

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final common = Provider.of<Common>(context);
    if (common.startApplyModeTick != _lastStartApplyModeTick) {
      _lastStartApplyModeTick = common.startApplyModeTick;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || Common.instance.fishingDiaryMode) return;
        await showMapTab();
        if (!mounted) return;
        await _fishingPaneKey.currentState?.enterApplyMode();
      });
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return _FishingInfoPane(
            key: _fishingPaneKey,
            height: constraints.maxHeight,
          );
        },
      ),
    );
  }
}

class _CatchPostList extends StatefulWidget {
  const _CatchPostList({super.key, required this.refreshTick});
  final int refreshTick;
  @override
  State<_CatchPostList> createState() => _CatchPostListState();
}

class _CatchTab extends StatelessWidget {
  const _CatchTab({super.key, required this.refreshTick});
  final int refreshTick;
  @override
  Widget build(BuildContext context) {
    // 一覧の項目と同じ高さ相当（thumb 56 + padding上下8）
    const double rowHeight = 72;
    return Column(
      children: [
        // 固定の注意テキスト（スクロール対象外）
        SizedBox(
          height: rowHeight,
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  ambiguousLevel != 0 ? 'この釣り場近辺の釣果です。' : 'この釣り場の釣果です。',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
            ),
          ),
        ),
        // スクロール対象
        Expanded(
          child: _CatchPostList(
            key: ValueKey('catch-$refreshTick'),
            refreshTick: refreshTick,
          ),
        ),
      ],
    );
  }
}

class _CatchPostListState extends State<_CatchPostList> {
  final List<_PostItem> _items = [];
  final ScrollController _sc = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  bool _isAdmin = false;
  final Map<int, String> _spotNameById = {};
  final Map<int, String> _imgTsByPost = {}; // 編集後のキャッシュバスター
  @override
  void initState() {
    super.initState();
    _initAdminMeta();
    _loadImageTsMap().then((_) => _loadFirst());
    _sc.addListener(() {
      if (_sc.position.pixels >= _sc.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  /*
  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }
*/

  Future<List<_PostItem>> _fetch({required int kind, required int page}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final spotId = prefs.getInt('selected_teibou_id');
      final catchAreaSpotIdsCsv =
          (kind == 1) ? await _buildCatchAreaSpotIdsCsv(spotId) : null;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final uri = Uri.parse(
        '${AppConfig.instance.baseUrl}get_post_list.php?ts=$ts',
      );
      final body = <String, String>{
        'get_kind': kind.toString(),
        'page': page.toString(),
        'page_size': kPostPageSize.toString(),
        'ambiguous_plevel': ambiguousLevel.toString(),
        // キャッシュ回避のためのタイムスタンプ
        'ts': DateTime.now().millisecondsSinceEpoch.toString(),
      };
      if (spotId != null && spotId > 0) body['spot_id'] = spotId.toString();
      if (catchAreaSpotIdsCsv != null && catchAreaSpotIdsCsv.isNotEmpty) {
        body['catch_area_spot_ids'] = catchAreaSpotIdsCsv;
      }
      final resp = await http
          .post(
            uri,
            body: body,
            headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
          )
          .timeout(kHttpTimeout);
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      if (data is Map && data['status'] == 'success') {
        final List rows = (data['rows'] as List?) ?? [];
        final items =
            rows
                .map((e) => _PostItem.fromJson(e as Map<String, dynamic>))
                .toList();
        if (kind == 1) {
          Common.instance.registerKnownCatchPostIds(
            items.map((e) => e.postId).whereType<int>(),
          );
        }
        return items;
      }
      if (data is List) {
        final items =
            data
                .map((e) => _PostItem.fromJson(e as Map<String, dynamic>))
                .toList();
        if (kind == 1) {
          Common.instance.registerKnownCatchPostIds(
            items.map((e) => e.postId).whereType<int>(),
          );
        }
        return items;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadFirst() async {
    if (!mounted || _loading) return;
    setState(() {
      _loading = true;
      _page = 1;
      _hasMore = true;
    });
    var rows = await _fetch(kind: 1, page: 1);
    rows = await _applyAmbiguityFilter(rows);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(rows);
      _hasMore = rows.length >= kPostPageSize;
      _page = 2;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    if (!mounted) return;
    setState(() => _loading = true);
    var rows = await _fetch(kind: 1, page: _page);
    rows = await _applyAmbiguityFilter(rows);
    if (!mounted) return;
    setState(() {
      _items.addAll(_dedupePostItems(rows, existing: _items));
      _hasMore = rows.length >= kPostPageSize;
      _page += 1;
      _loading = false;
    });
  }

  // ambiguousLevel=0 のときは、選択中の釣り場IDに一致する投稿のみを表示
  Future<List<_PostItem>> _applyAmbiguityFilter(List<_PostItem> rows) async {
    if (ambiguousLevel != 0) return rows;
    try {
      final prefs = await SharedPreferences.getInstance();
      final selId = prefs.getInt('selected_teibou_id');
      if (selId == null || selId <= 0) return rows;
      return rows.where((e) => e.spotId == selId).toList();
    } catch (_) {
      return rows;
    }
  }

  static const _kTsStorageKey = 'post_img_ts_map_v1';
  Future<void> _loadImageTsMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kTsStorageKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((k, v) {
        final id = int.tryParse(k);
        final ts = v?.toString();
        if (id != null && ts != null && ts.isNotEmpty) {
          _imgTsByPost[id] = ts;
        }
      });
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveImageTs(int postId, String ts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> map = {};
      final raw = prefs.getString(_kTsStorageKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          map = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      }
      map[postId.toString()] = ts;
      await prefs.setString(_kTsStorageKey, jsonEncode(map));
    } catch (_) {}
  }

  Future<void> _removeImageTs(int postId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> map = {};
      final raw = prefs.getString(_kTsStorageKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          map = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      }
      map.remove(postId.toString());
      await prefs.setString(_kTsStorageKey, jsonEncode(map));
    } catch (_) {}
  }

  String _withTs(String url, int? postId) {
    if (postId != null) {
      final ts = _imgTsByPost[postId];
      if (ts != null && ts.isNotEmpty) {
        final sep = url.contains('?') ? '&' : '?';
        return '$url${sep}ts=$ts';
      }
    }
    return url;
  }

  Future<void> _initAdminMeta() async {
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final isAdmin = ((info.role ?? '').toLowerCase() == 'admin');
      if (!isAdmin) {
        if (mounted) setState(() => _isAdmin = false);
        return;
      }

      final db = await SioDatabase().database;
      var rows = await db.query('teibou');
      if (rows.isEmpty) {
        try {
          rows = await SioDatabase().getAllTeibouWithPrefecture();
        } catch (_) {}
      }
      final spotNames = <int, String>{};
      for (final r in rows) {
        final id = int.tryParse(r['port_id']?.toString() ?? '');
        final name = (r['port_name'] ?? '').toString();
        if (id != null && name.isNotEmpty) spotNames[id] = name;
      }
      if (!mounted) return;
      setState(() {
        _isAdmin = true;
        _spotNameById
          ..clear()
          ..addAll(spotNames);
      });
    } catch (_) {}
  }

  String _adminPostMeta(_PostItem it) {
    if (!_isAdmin) return '';
    final userId = it.userId?.toString() ?? '';
    final spotText =
        it.spotId != null
            ? ((_spotNameById[it.spotId!] ?? '').isNotEmpty
                ? _spotNameById[it.spotId!]!
                : it.spotId!.toString())
            : '';
    final parts = <String>[];
    if (userId.isNotEmpty) parts.add('user_id:$userId');
    if (spotText.isNotEmpty) parts.add('spot:$spotText');
    return parts.join(', ');
  }

  String? _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      DateTime dt;
      if (raw.contains('T')) {
        dt = DateTime.parse(raw).toLocal();
      } else {
        dt = DateTime.parse(raw.replaceFirst(' ', 'T')).toLocal();
      }
      String two(int v) => v.toString().padLeft(2, '0');
      return '${dt.year}/${two(dt.month)}/${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    const double thumb = 56;
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFirst,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('投稿がありません')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: ListView.separated(
        controller: _sc,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final it = _items[i];
          final String? raw = it.thumbUrl ?? it.imageUrl;
          final imgUrl = (raw != null) ? _withTs(raw, it.postId) : null;
          final adminMeta = _adminPostMeta(it);
          return InkWell(
            onTap: () async {
              final String? detailRaw = it.imageUrl ?? it.thumbUrl;
              final String? detailUrl =
                  (detailRaw != null) ? _withTs(detailRaw, it.postId) : null;
              final res = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => PostDetailPage(
                        item: PostDetailItem(
                          userId: it.userId,
                          postId: it.postId,
                          postKind: it.postKind,
                          exist: it.exist,
                          title: it.title,
                          detail: it.detail,
                          imageUrl: detailUrl,
                          nickName: it.nickName,
                          createAt: it.createAt,
                        ),
                      ),
                ),
              );
              if (!mounted) return;
              if (res == true && it.postId != null) {
                final ts = DateTime.now().millisecondsSinceEpoch.toString();
                setState(() {
                  _imgTsByPost[it.postId!] = ts;
                });
                await _saveImageTs(it.postId!, ts);
              } else if (res is Map) {
                final updated = (res['updated'] == true);
                final cleared = (res['clearedImage'] == true);
                final deleted = (res['deleted'] == true);
                final pid =
                    res['postId'] is int
                        ? res['postId'] as int
                        : (res['postId'] is String
                            ? int.tryParse(res['postId'])
                            : null);
                if (deleted && pid != null) {
                  setState(() {
                    _items.removeWhere((e) => e.postId == pid);
                    _imgTsByPost.remove(pid);
                  });
                  await _removeImageTs(pid);
                } else if (updated && cleared && pid != null) {
                  // 投稿は残しつつ、画像だけ消した状態に更新（サムネは非表示）
                  final idx = _items.indexWhere((e) => e.postId == pid);
                  if (idx >= 0) {
                    final old = _items[idx];
                    final updatedItem = _PostItem(
                      postId: old.postId,
                      userId: old.userId,
                      spotId: old.spotId,
                      postKind: old.postKind,
                      exist: old.exist,
                      title: old.title,
                      detail: old.detail,
                      imagePath: null,
                      thumbPath: null,
                      nickName: old.nickName,
                      createAt: old.createAt,
                    );
                    setState(() {
                      _items[idx] = updatedItem;
                    });
                  }
                  // キャッシュバスターも削除
                  setState(() {
                    _imgTsByPost.remove(pid);
                  });
                  await _removeImageTs(pid);
                } else if (updated && pid != null) {
                  final ts = DateTime.now().millisecondsSinceEpoch.toString();
                  // 画像パスが返っていれば項目を更新（画像なし→ありに変わったケース）
                  final ip = (res['image_path']?.toString() ?? '').trim();
                  final tp = (res['thumb_path']?.toString() ?? '').trim();
                  if (ip.isNotEmpty || tp.isNotEmpty) {
                    final idx = _items.indexWhere((e) => e.postId == pid);
                    if (idx >= 0) {
                      final old = _items[idx];
                      final updatedItem = _PostItem(
                        postId: old.postId,
                        userId: old.userId,
                        spotId: old.spotId,
                        postKind: old.postKind,
                        exist: old.exist,
                        title: old.title,
                        detail: old.detail,
                        imagePath: ip.isNotEmpty ? ip : old.imagePath,
                        thumbPath: tp.isNotEmpty ? tp : old.thumbPath,
                        nickName: old.nickName,
                        createAt: old.createAt,
                      );
                      setState(() {
                        _items[idx] = updatedItem;
                      });
                    }
                  }
                  setState(() {
                    _imgTsByPost[pid] = ts;
                  });
                  await _saveImageTs(pid, ts);
                }
              }
            },
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // サムネ枠（空でも固定幅）
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: thumb,
                      height: thumb,
                      child:
                          (imgUrl != null)
                              ? Image.network(imgUrl, fit: BoxFit.cover)
                              : const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      it.title?.isNotEmpty == true ? it.title! : '',
                      style: const TextStyle(fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 150,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          adminMeta.isNotEmpty
                              ? adminMeta
                              : ((it.nickName ?? '').isNotEmpty
                                  ? it.nickName!
                                  : ''),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(it.createAt) ?? '',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EnvPostList extends StatefulWidget {
  const _EnvPostList({
    super.key,
    required this.filterKind,
    required this.refreshTick,
  });
  final int filterKind; // 0=環境すべて, 2/3/4/5/6/9=種別
  final int refreshTick;
  @override
  State<_EnvPostList> createState() => _EnvPostListState();
}

class _EnvPostListState extends State<_EnvPostList> {
  final List<_PostItem> _items = [];
  final ScrollController _sc = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  final Map<int, String> _imgTsByPost = {}; // 編集後のキャッシュバスター
  @override
  void initState() {
    super.initState();
    _loadImageTsMap().then((_) => _loadFirst());
    _sc.addListener(() {
      if (_sc.position.pixels >= _sc.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _EnvPostList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterKind != widget.filterKind ||
        oldWidget.refreshTick != widget.refreshTick) {
      if (mounted) {
        setState(() {
          _items.clear();
          _page = 1;
          _hasMore = true;
          _loading = false;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadMore();
        }
      });
    }
  }

  // 固定エリア（あり/なし件数と比率バー）
  Widget _envSummaryHeader() {
    // 環境すべて(0)では比率ヘッダーは表示しない
    if (widget.filterKind == 0) return const SizedBox.shrink();
    // 「その他」は対象外
    if (widget.filterKind == 9) return const SizedBox.shrink();

    // 一覧の項目と同じ高さ相当（thumb 56 + padding上下8）
    const double rowHeight = 72;
    // 件数集計
    int yes = 0; // あり
    int no = 0; // なし
    for (final it in _items) {
      if (it.exist == 1) {
        yes += 1;
      } else if (it.exist == 0) {
        no += 1;
      }
    }
    final int total = yes + no;

    // ありがたい色の判定
    // 規制(2): あり=赤, なし=青 / それ以外(3,4,5,6): あり=青, なし=赤
    final bool yesIsGood = widget.filterKind != 2;
    final Color good = Colors.blueAccent;
    final Color bad = Colors.redAccent;
    final Color yesColor = yesIsGood ? good : bad;
    final Color noColor = yesIsGood ? bad : good;

    return SizedBox(
      height: rowHeight,
      child: ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 比率バー（あり→なし の順）
              SizedBox(
                height: 16,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double w = constraints.maxWidth;
                    final double yesW = total > 0 ? (w * yes / total) : 0;
                    final double noW = (w - yesW).clamp(0, w);
                    return Stack(
                      children: [
                        // 背景（薄いグレー）
                        Container(
                          width: w,
                          height: 16,
                          color: Colors.grey.shade300,
                        ),
                        // あり（左）
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: Container(width: yesW, color: yesColor),
                        ),
                        // なし（右）
                        Positioned(
                          left: yesW,
                          top: 0,
                          bottom: 0,
                          child: Container(width: noW, color: noColor),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              // 件数表示（左=あり, 右=なし）
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'あり ${yes}件',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'なし ${no}件',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<_PostItem>> _fetch({required int kind, required int page}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final spotId = prefs.getInt('selected_teibou_id');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final uri = Uri.parse(
        '${AppConfig.instance.baseUrl}get_post_list.php?ts=$ts',
      );
      final body = <String, String>{
        'get_kind': kind.toString(),
        'page': page.toString(),
        'page_size': kPostPageSize.toString(),
        'ambiguous_plevel': ambiguousLevel.toString(),
        // キャッシュ回避のためのタイムスタンプ
        'ts': DateTime.now().millisecondsSinceEpoch.toString(),
      };
      if (spotId != null && spotId > 0) body['spot_id'] = spotId.toString();
      final resp = await http
          .post(
            uri,
            body: body,
            headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
          )
          .timeout(kHttpTimeout);
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      if (data is Map && data['status'] == 'success') {
        final List rows = (data['rows'] as List?) ?? [];
        final items =
            rows
                .map((e) => _PostItem.fromJson(e as Map<String, dynamic>))
                .toList();
        if (kind == 1) {
          Common.instance.registerKnownCatchPostIds(
            items.map((e) => e.postId).whereType<int>(),
          );
        }
        return items;
      }
      if (data is List) {
        final items =
            data
                .map((e) => _PostItem.fromJson(e as Map<String, dynamic>))
                .toList();
        if (kind == 1) {
          Common.instance.registerKnownCatchPostIds(
            items.map((e) => e.postId).whereType<int>(),
          );
        }
        return items;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadFirst() async {
    if (!mounted || _loading) return;
    setState(() {
      _loading = true;
      _page = 1;
      _hasMore = true;
    });
    final rows = await _fetch(kind: widget.filterKind, page: 1);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(rows);
      _hasMore = rows.length >= kPostPageSize;
      _page = 2;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    if (!mounted) return;
    setState(() => _loading = true);
    final rows = await _fetch(kind: widget.filterKind, page: _page);
    if (!mounted) return;
    setState(() {
      _items.addAll(_dedupePostItems(rows, existing: _items));
      _hasMore = rows.length >= kPostPageSize;
      _page += 1;
      _loading = false;
    });
  }

  static const _kTsStorageKey = 'post_img_ts_map_v1';
  Future<void> _loadImageTsMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kTsStorageKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((k, v) {
        final id = int.tryParse(k);
        final ts = v?.toString();
        if (id != null && ts != null && ts.isNotEmpty) {
          _imgTsByPost[id] = ts;
        }
      });
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveImageTs(int postId, String ts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> map = {};
      final raw = prefs.getString(_kTsStorageKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          map = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      }
      map[postId.toString()] = ts;
      await prefs.setString(_kTsStorageKey, jsonEncode(map));
    } catch (_) {}
  }

  Future<void> _removeImageTs(int postId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> map = {};
      final raw = prefs.getString(_kTsStorageKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          map = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      }
      map.remove(postId.toString());
      await prefs.setString(_kTsStorageKey, jsonEncode(map));
    } catch (_) {}
  }

  String _withTs(String url, int? postId) {
    if (postId != null) {
      final ts = _imgTsByPost[postId];
      if (ts != null && ts.isNotEmpty) {
        final sep = url.contains('?') ? '&' : '?';
        return '$url${sep}ts=$ts';
      }
    }
    return url;
  }

  String _kindLabel(int kind) {
    switch (kind) {
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
        return '環境';
    }
  }

  @override
  Widget build(BuildContext context) {
    const double thumbW = 56;
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFirst,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('投稿がありません')),
          ],
        ),
      );
    }
    // 固定の要約ヘッダー + スクロール一覧
    return Column(
      children: [
        _envSummaryHeader(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadFirst,
            child: ListView.separated(
              controller: _sc,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _items.length + (_hasMore ? 1 : 0),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i >= _items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final it = _items[i];
                final String? raw = it.thumbUrl ?? it.imageUrl;
                final imgUrl = (raw != null) ? _withTs(raw, it.postId) : null;
                // 有無表示は行わない（釣果と同様のレイアウト）
                return InkWell(
                  onTap: () async {
                    final String? detailRaw = it.imageUrl ?? it.thumbUrl;
                    final String? detailUrl =
                        (detailRaw != null)
                            ? _withTs(detailRaw, it.postId)
                            : null;
                    final res = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => PostDetailPage(
                              item: PostDetailItem(
                                userId: it.userId,
                                postId: it.postId,
                                postKind: it.postKind,
                                exist: it.exist,
                                title: it.title,
                                detail: it.detail,
                                imageUrl: detailUrl,
                                nickName: it.nickName,
                                createAt: it.createAt,
                              ),
                            ),
                      ),
                    );
                    if (!mounted) return;
                    if (res == true && it.postId != null) {
                      final ts =
                          DateTime.now().millisecondsSinceEpoch.toString();
                      setState(() {
                        _imgTsByPost[it.postId!] = ts;
                      });
                      await _saveImageTs(it.postId!, ts);
                    } else if (res is Map) {
                      final updated = (res['updated'] == true);
                      final cleared = (res['clearedImage'] == true);
                      final deleted = (res['deleted'] == true);
                      final pid =
                          res['postId'] is int
                              ? res['postId'] as int
                              : (res['postId'] is String
                                  ? int.tryParse(res['postId'])
                                  : null);
                      if (deleted && pid != null) {
                        setState(() {
                          _items.removeWhere((e) => e.postId == pid);
                          _imgTsByPost.remove(pid);
                        });
                        await _removeImageTs(pid);
                      } else if (updated && cleared && pid != null) {
                        // 画像は外すが投稿行は残す
                        final idx = _items.indexWhere((e) => e.postId == pid);
                        if (idx >= 0) {
                          final old = _items[idx];
                          final updatedItem = _PostItem(
                            postId: old.postId,
                            userId: old.userId,
                            spotId: old.spotId,
                            postKind: old.postKind,
                            exist: old.exist,
                            title: old.title,
                            detail: old.detail,
                            imagePath: null,
                            thumbPath: null,
                            nickName: old.nickName,
                            createAt: old.createAt,
                          );
                          setState(() {
                            _items[idx] = updatedItem;
                          });
                        }
                        setState(() {
                          _imgTsByPost.remove(pid);
                        });
                        await _removeImageTs(pid);
                      } else if (updated && pid != null) {
                        final ts =
                            DateTime.now().millisecondsSinceEpoch.toString();
                        final ip = (res['image_path']?.toString() ?? '').trim();
                        final tp = (res['thumb_path']?.toString() ?? '').trim();
                        if (ip.isNotEmpty || tp.isNotEmpty) {
                          final idx = _items.indexWhere((e) => e.postId == pid);
                          if (idx >= 0) {
                            final old = _items[idx];
                            final updatedItem = _PostItem(
                              postId: old.postId,
                              userId: old.userId,
                              spotId: old.spotId,
                              postKind: old.postKind,
                              exist: old.exist,
                              title: old.title,
                              detail: old.detail,
                              imagePath: ip.isNotEmpty ? ip : old.imagePath,
                              thumbPath: tp.isNotEmpty ? tp : old.thumbPath,
                              nickName: old.nickName,
                              createAt: old.createAt,
                            );
                            setState(() {
                              _items[idx] = updatedItem;
                            });
                          }
                        }
                        setState(() {
                          _imgTsByPost[pid] = ts;
                        });
                        await _saveImageTs(pid, ts);
                      }
                    }
                  },
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: thumbW,
                            height: thumbW,
                            child:
                                (imgUrl != null)
                                    ? Image.network(imgUrl, fit: BoxFit.cover)
                                    : const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            it.title?.isNotEmpty == true ? it.title! : '',
                            style: const TextStyle(fontSize: 15),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              (it.nickName ?? '').isNotEmpty
                                  ? it.nickName!
                                  : '',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDate(it.createAt) ?? '',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  String? _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      DateTime dt;
      if (raw.contains('T')) {
        dt = DateTime.parse(raw).toLocal();
      } else {
        dt = DateTime.parse(raw.replaceFirst(' ', 'T')).toLocal();
      }
      String two(int v) => v.toString().padLeft(2, '0');
      return '${dt.year}/${two(dt.month)}/${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return raw;
    }
  }
}

class _PostItem {
  final int? postId;
  final int? userId;
  final int? spotId;
  final int? postKind;
  final int? exist;
  final String? title;
  final String? detail;
  final String? imagePath;
  final String? thumbPath;
  final String? nickName;
  final String? createAt;

  _PostItem({
    this.postId,
    this.userId,
    this.spotId,
    this.postKind,
    this.exist,
    this.title,
    this.detail,
    this.imagePath,
    this.thumbPath,
    this.nickName,
    this.createAt,
  });

  String? get imageUrl {
    if (thumbPath == null && imagePath == null) return null;
    final rel = imagePath ?? thumbPath!;
    if (rel.startsWith('http')) return rel;
    return '${AppConfig.instance.baseUrl}post_images/' + rel;
  }

  String? get thumbUrl {
    if (thumbPath == null) return null;
    final rel = thumbPath!;
    if (rel.startsWith('http')) return rel;
    return '${AppConfig.instance.baseUrl}post_images/' + rel;
  }

  factory _PostItem.fromJson(Map<String, dynamic> j) {
    int? toInt(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '');
    String? s(dynamic v) => v?.toString();
    return _PostItem(
      postId: toInt(j['post_id']),
      userId: toInt(j['user_id']),
      spotId: toInt(j['spot_id']),
      postKind: toInt(j['post_kind']),
      exist: toInt(j['exist']),
      title: s(j['title']),
      detail: s(j['detail']),
      imagePath: s(j['image_path']),
      thumbPath: s(j['thumb_path']),
      nickName: s(j['nick_name']) ?? s(j['nickname']) ?? s(j['nickName']),
      createAt: s(j['create_at']),
    );
  }
}

class _EnvTabbedList extends StatelessWidget {
  const _EnvTabbedList({super.key, required this.refreshTick});
  final int refreshTick;
  @override
  Widget build(BuildContext context) {
    // タブは廃止し、釣果と同様にヘッダー + 一覧（環境すべて）を表示
    const double rowHeight = 72;
    return Column(
      children: [
        const SizedBox(
          height: rowHeight,
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '規制、駐車場、トイレなどの状況などです',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _EnvPostList(
            key: ValueKey('env-$refreshTick'),
            filterKind: 0,
            refreshTick: refreshTick,
          ),
        ),
      ],
    );
  }
}

class _FishingInfoPane extends StatefulWidget {
  const _FishingInfoPane({Key? key, required this.height}) : super(key: key);
  final double height;

  @override
  State<_FishingInfoPane> createState() => _FishingInfoPaneState();
}

class _FishingInfoPaneState extends State<_FishingInfoPane> {
  final List<fm.Marker> _markers = [];
  final Set<am.Annotation> _appleAnnotations = <am.Annotation>{};
  final Set<gm.Marker> _gmMarkers = <gm.Marker>{};
  final Set<gm.Polyline> _gmPolylines = <gm.Polyline>{};
  final Set<gm.Circle> _gmCircles = <gm.Circle>{};
  LatLng? _center;
  double? _lastLat;
  double? _lastLng;
  String _lastName = '';
  final fm.MapController _mapController = fm.MapController();
  double _currentZoom = 12.0;
  // 近隣潮汐ポイント座標（ポイント名 -> (lat,lng)）
  final Map<String, Offset> _pointCoords = {};
  bool _pointsLoading = true;

  // 現在地表示（ブリンク）
  LatLng? _myPos;
  bool _blinkOn = true;
  Timer? _blinkTimer;
  StreamSubscription<Position>? _posSub;
  // ドラッガブルシートのサイズ制御
  late DraggableScrollableController _sheetController;
  final GlobalKey _sheetActuatorKey = GlobalKey();
  int _sheetEpoch = 0; // シート完全再生成用
  double _lastSheetSize = 0.25; // 直近のシートサイズ（可視時）
  int _sheetReloadTick = 0; // 投稿一覧シートの再構築用トリガ
  Set<int> _favoriteIds = <int>{};
  Set<int> _myCatchSpotIds = <int>{};
  Set<int> _myOwnedSpotIds = <int>{};
  int? _latestMyCatchSpotId;
  int? _latestMyOwnedSpotId;
  bool _showApplyModeGuide = false;
  bool _hideApplyModeGuideCheckbox = false;
  double? _applyGuideLeft;
  double? _applyGuideTop;
  bool _lastFishingDiaryMode = Common.instance.fishingDiaryMode;
  int _lastAmbiguousLevel = ambiguousLevel;
  // 潮汐オーバーレイ表示とスワイプ用
  bool _showTideOverlay = false;
  late PageController _tidePageController;
  DateTime _tideBaseDate = Common.instance.tideDate;
  final GlobalKey<NavigatorState> _tideNavKey = GlobalKey<NavigatorState>();
  late final _TideNavObserver _tideNavObserver;
  gm.GoogleMapController? _gmController;
  // 長押しによる「釣り場登録」用ポイント
  LatLng? _applyPoint; // FlutterMap 用
  gm.LatLng? _gmApplyPoint; // GoogleMap 用
  bool _applyMode = false; // 「釣り場申請」ボタン押下後の指定モード
  bool _isSatellite = false; // Google Maps 用 衛星表示トグル

  Future<bool> _ensureEmailVerified({
    bool returnToInputPost = false,
    String? authPurposeLabel,
  }) async {
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      if (info.email.trim().isNotEmpty) return true;
    } catch (_) {}
    if (!mounted) return false;
    final res = await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => NewAccountPage(
              returnToInputPost: returnToInputPost,
              authPurposeLabel: authPurposeLabel,
            ),
      ),
    );
    return res == true;
  }

  void reloadPostList() {
    if (mounted)
      setState(() {
        _sheetReloadTick++;
      });
  }

  void _showModeInfoDialog() {
    final isApply = _applyMode;
    final title = isApply ? '釣り場登録モードとは' : '閲覧モードとは';
    final String msg =
        isApply
            ? '地図上で登録したい場所を長押ししてください。\nピンが表示されたら「釣り場登録」をタップしてください。\n申請中のピンを申請者本人がタップすると入力項目の修正ができます。\n\n「釣り場登録中...」ボタンをタップすると「閲覧モード」に遷移します。'
            : '地図上の釣り場をタップして選びながら、釣果や環境の投稿をボトムシートの「投稿一覧」で閲覧するモードです。\n\n長押しするとその近辺の釣り場が新たにピン表示されます。';
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (_) => AlertDialog(
            titlePadding: EdgeInsets.zero,
            title: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
              child: Container(
                color: _navyBg,
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 22,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            content: Text(msg),
          ),
    );
  }

  Future<String> _currentSpotDisplay() async {
    final spotName =
        Common.instance.selectedTeibouName.isNotEmpty
            ? Common.instance.selectedTeibouName
            : Common.instance.tidePoint;
    String display = spotName;
    try {
      final rows = await _visibleTeibouRows();
      Map<String, dynamic>? row;
      try {
        final prefs = await SharedPreferences.getInstance();
        final sid = prefs.getInt('selected_teibou_id');
        if (sid != null && sid > 0) {
          for (final r in rows) {
            final rid =
                r['port_id'] is int
                    ? r['port_id'] as int
                    : int.tryParse(r['port_id']?.toString() ?? '');
            if (rid == sid) {
              row = r;
              break;
            }
          }
        }
      } catch (_) {}
      row ??= rows.cast<Map<String, dynamic>?>().firstWhere(
        (r) => ((r?['port_name'] ?? '').toString() == spotName),
        orElse: () => null,
      );
      final int? flag =
          row == null
              ? null
              : (row['flag'] is int
                  ? row['flag'] as int
                  : int.tryParse(row['flag']?.toString() ?? ''));
      if (flag == -1) display = '$spotName (申請中)';
    } catch (_) {}
    return display;
  }

  bool _shouldHideOtherPendingSpotRow(Map<String, dynamic> row, int userId) {
    final int? flag =
        row['flag'] is int
            ? row['flag'] as int
            : int.tryParse(row['flag']?.toString() ?? '');
    if (flag == -3) return true;
    if (flag != -1) return false;
    final int? ownerId =
        row['user_id'] is int
            ? row['user_id'] as int
            : int.tryParse(row['user_id']?.toString() ?? '');
    if (userId <= 0) return true;
    return ownerId == null || ownerId != userId;
  }

  Set<int> get _myDiarySpotIds => <int>{..._myCatchSpotIds, ..._myOwnedSpotIds};

  Future<bool> _shouldShowApplyModeGuide() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('hide_apply_mode_guide') ?? false);
  }

  Future<void> _saveHideApplyModeGuide(bool hide) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_apply_mode_guide', hide);
  }

  Future<List<Map<String, dynamic>>> _visibleTeibouRows() async {
    final rows = await SioDatabase().getAllTeibouWithPrefecture();
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final uid = info.userId;
      return rows
          .where((r) => !_shouldHideOtherPendingSpotRow(r, uid))
          .toList();
    } catch (_) {
      return rows.where((r) => !_shouldHideOtherPendingSpotRow(r, 0)).toList();
    }
  }

  Future<void> _onViewLongPress(double llat, double llng) async {
    if (Common.instance.fishingDiaryMode) return;
    try {
      final rows = await _visibleTeibouRows();
      double best = double.infinity;
      Map<String, dynamic>? bestRow;
      const double d2r = 3.141592653589793 / 180.0;
      final rlat = llat * d2r;
      for (final r in rows) {
        final int? flag =
            r['flag'] is int
                ? r['flag'] as int
                : int.tryParse(r['flag']?.toString() ?? '');
        if (flag == -2 || flag == -3) continue; // 非承認/取り下げは除外
        final dlat = _toDouble(r['latitude']);
        final dlng = _toDouble(r['longitude']);
        if (dlat == null || dlng == null) continue;
        final d = _haversine(llat, llng, dlat, dlng, cosLat: rlat);
        if (d < best) {
          best = d;
          bestRow = r;
        }
      }
      if (bestRow == null) return;
      final nlat = _toDouble(bestRow['latitude']) ?? llat;
      final nlng = _toDouble(bestRow['longitude']) ?? llng;
      final name = (bestRow['port_name'] ?? '').toString();
      // 選択状態は更新（最寄りを選択）し、地図の表示位置・スケールは変更せず近辺ピンのみ再構成
      try {
        String? np;
        if (!_pointsLoading && _pointCoords.isNotEmpty) {
          np = _nearestPointName(nlat, nlng);
        }
        final int? prefId =
            bestRow['todoufuken_id'] is int
                ? bestRow['todoufuken_id'] as int
                : int.tryParse(bestRow['todoufuken_id']?.toString() ?? '') ??
                    int.tryParse(
                      bestRow['pref_id_from_port']?.toString() ?? '',
                    );
        final int? portId =
            bestRow['port_id'] is int
                ? bestRow['port_id'] as int
                : int.tryParse(bestRow['port_id']?.toString() ?? '');
        await Common.instance.saveSelectedTeibou(
          name,
          np ?? (Common.instance.tidePoint),
          id: portId,
          lat: nlat,
          lng: nlng,
          prefId: prefId,
        );
      } catch (_) {}
      // 地図の表示位置は変更せず、ピンのみ再構成（最寄りを赤ピン）
      await _loadMarkers(
        centerName: name,
        lat: nlat,
        lng: nlng,
        radiusKm: kNearbyMapSearchRadiusKm,
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<bool> _openSpotApplyEdit({
    required Map<String, dynamic> row,
    required double lat,
    required double lng,
    required String name,
    required int? portId,
    String? buttonMode,
  }) async {
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final bool isAdmin = ((info.role ?? '').toLowerCase() == 'admin');
      final int? owner =
          row['user_id'] is int
              ? row['user_id'] as int
              : int.tryParse(row['user_id']?.toString() ?? '');
      if (!(isAdmin || (owner != null && owner == info.userId))) return false;
      final prefName = (row['todoufuken_name'] ?? '').toString();
      if (!mounted) return true;
      final res = await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => SpotApplyFormPage(
                lat: lat,
                lng: lng,
                editMode: true,
                initialKind: (row['kubun'] ?? '').toString(),
                initialName: name,
                initialYomi:
                    (row['j_yomi'] ?? row['furigana'] ?? '').toString(),
                initialAddress: (row['address'] ?? '').toString(),
                initialPrefName: prefName,
                initialPrivate:
                    (row['private'] is int)
                        ? row['private'] as int
                        : int.tryParse(row['private']?.toString() ?? '0'),
                initialPortId: portId,
                applicantUserId: owner,
                canModerate: isAdmin,
                buttonMode: buttonMode,
              ),
        ),
      );
      if (res == true && mounted) {
        setState(() {
          _applyMode = false;
          _applyPoint = null;
          _gmApplyPoint = null;
          try {
            _gmMarkers.removeWhere((m) => m.markerId.value == 'apply');
          } catch (_) {}
        });
        return true;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _selectSpot({
    required String name,
    required double lat,
    required double lng,
    required int? portId,
    required int? prefId,
    required double radiusKm,
  }) async {
    String? np;
    if (!_pointsLoading && _pointCoords.isNotEmpty) {
      np = _nearestPointName(lat, lng);
    }
    if (np != null) {
      Common.instance.tidePoint = np;
      await Common.instance.savePoint(np);
    }
    await Common.instance.saveSelectedTeibou(
      name,
      np ?? (Common.instance.tidePoint),
      id: portId,
      lat: lat,
      lng: lng,
      prefId: prefId,
    );
    Common.instance.shouldJumpPage = true;
    Common.instance.notify();
    await _loadMarkers(
      centerName: name,
      lat: lat,
      lng: lng,
      radiusKm: radiusKm,
    );
    if (mounted) {
      setState(() {
        _sheetReloadTick++;
      });
    }
    if (_safeSheetSize() <= 0.01) {
      _recreateSheet(show: true);
    } else {
      _ensureSheetVisible(ifHiddenOnly: true);
    }
  }

  Future<void> _handleSpotTap({
    required bool isSelected,
    required bool isPending,
    required Map<String, dynamic> row,
    required String name,
    required double lat,
    required double lng,
    required int? portId,
    required int? prefId,
    required double radiusKm,
  }) async {
    if (!isSelected) {
      await _selectSpot(
        name: name,
        lat: lat,
        lng: lng,
        portId: portId,
        prefId: prefId,
        radiusKm: radiusKm,
      );
      return;
    }
    if (_applyMode && isPending) {
      final handled = await _openSpotApplyEdit(
        row: row,
        lat: lat,
        lng: lng,
        name: name,
        portId: portId,
      );
      if (handled) {
        if (mounted) {
          _lastLat = null;
          _lastLng = null;
          _lastName = '';
          await _prepare();
        }
        return;
      }
    }
    await _showCurrentSpotInfoDialog();
    if (mounted) {
      _lastLat = null;
      _lastLng = null;
      _lastName = '';
      await _prepare();
    }
  }

  int? _rowPrefId(Map<String, dynamic>? row) {
    if (row == null) return null;
    return row['todoufuken_id'] is int
        ? row['todoufuken_id'] as int
        : int.tryParse(row['todoufuken_id']?.toString() ?? '') ??
            int.tryParse(row['pref_id_from_port']?.toString() ?? '');
  }

  @override
  void initState() {
    super.initState();
    _sheetController = DraggableScrollableController();
    _tidePageController = PageController(initialPage: 1000);
    _tideNavObserver = _TideNavObserver(() {
      if (mounted) setState(() {});
    });
    _prepare();
    _loadPointCoords();
    // Common の変更（堤防選択など）を監視して地図を更新
    Common.instance.addListener(_onCommonChanged);
    _initLocation();
    _startBlink();
    // 初期表示時、シートを下部に表示（隠れている場合に備えて）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureSheetVisible();
    });
    _loadFavorites();
    _loadMyCatchSpotIds();
  }

  void _onCommonChanged() {
    if (Common.instance.fishingDiaryMode && _applyMode) {
      setState(() {
        _applyMode = false;
        _applyPoint = null;
        _gmApplyPoint = null;
        try {
          _gmMarkers.removeWhere((m) => m.markerId.value == 'apply');
        } catch (_) {}
      });
    }
    // 堤防選択が変わった可能性があるため再準備
    _prepare();
    // 再表示や選択変更時、非表示ならシートを下部に出す
    final current = _safeSheetSize();
    if (current <= 0.01) {
      _recreateSheet(show: true);
    } else {
      _ensureSheetVisible(ifHiddenOnly: true);
    }
    // シートの内容（投稿一覧）を再取得するために再構築
    if (mounted)
      setState(() {
        _sheetReloadTick++;
      });
  }

  Future<void> _prepare() async {
    final diaryMode = Common.instance.fishingDiaryMode;
    if (diaryMode) {
      await _ensureDiarySelectedSpotIfNeeded();
    }
    final name = Common.instance.selectedTeibouName;
    final lat = Common.instance.selectedTeibouLat;
    final lng = Common.instance.selectedTeibouLng;
    final diaryModeChanged = _lastFishingDiaryMode != diaryMode;
    final ambiguousChanged = _lastAmbiguousLevel != ambiguousLevel;
    double useLat = lat;
    double useLng = lng;
    String useName = name;
    // 追加フォールバック: 緯度経度が未保存だが名前やIDが保存されている場合、DBから取得して補完
    if ((useLat == 0.0 && useLng == 0.0) && useName.isNotEmpty) {
      try {
        final rows = await _visibleTeibouRows();
        Map<String, dynamic>? hit;
        try {
          final prefs = await SharedPreferences.getInstance();
          final sid = prefs.getInt('selected_teibou_id');
          if (sid != null && sid > 0) {
            for (final r in rows) {
              final rid =
                  r['port_id'] is int
                      ? r['port_id'] as int
                      : int.tryParse(r['port_id']?.toString() ?? '');
              if (rid == sid) {
                hit = r;
                break;
              }
            }
          }
        } catch (_) {}
        hit ??= rows.cast<Map<String, dynamic>?>().firstWhere(
          (r) => ((r?['port_name'] ?? '').toString() == useName),
          orElse: () => null,
        );
        if (hit != null) {
          final dlat = _toDouble(hit['latitude']);
          final dlng = _toDouble(hit['longitude']);
          if (dlat != null && dlng != null && !(dlat == 0.0 && dlng == 0.0)) {
            useLat = dlat;
            useLng = dlng;
            useName = (hit['port_name'] ?? useName).toString();
            // 保存して次回以降に活かす
            try {
              await Common.instance.saveSelectedTeibou(
                useName,
                Common.instance.selectedTeibouNearestPoint,
                lat: useLat,
                lng: useLng,
                id:
                    hit['port_id'] is int
                        ? hit['port_id'] as int
                        : int.tryParse(hit['port_id']?.toString() ?? ''),
                prefId:
                    hit['todoufuken_id'] is int
                        ? hit['todoufuken_id'] as int
                        : int.tryParse(
                              hit['todoufuken_id']?.toString() ?? '',
                            ) ??
                            int.tryParse(
                              hit['pref_id_from_port']?.toString() ?? '',
                            ),
              );
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    if (useLat != 0.0 || useLng != 0.0) {
      // 変更検知（緯度経度 or 名前）
      if (_lastLat != useLat ||
          _lastLng != useLng ||
          _lastName != useName ||
          diaryModeChanged ||
          ambiguousChanged) {
        _center = LatLng(useLat, useLng);
        _lastLat = useLat;
        _lastLng = useLng;
        _lastName = useName;
        _lastFishingDiaryMode = diaryMode;
        _lastAmbiguousLevel = ambiguousLevel;
        await _loadMarkers(
          centerName: useName,
          lat: useLat,
          lng: useLng,
          radiusKm: kNearbyMapSearchRadiusKm,
        );
        // マップの中心も即時移動（シートの占有に合わせて上寄せ）
        if (mounted && _center != null) {
          final viewport = diaryMode ? await _buildDiaryViewport() : null;
          final displayCenter = _center!;
          final displayRadiusKm =
              viewport?.radiusKm ?? kNearbyMapSearchRadiusKm;
          final z =
              (diaryMode && !diaryModeChanged)
                  ? _currentZoom
                  : diaryMode
                  ? _zoomForRadius(displayRadiusKm)
                  : _zoomForRadius(30.0) + 1.0;
          final adjusted = _computeCenteredForSheet(displayCenter, z);
          setState(() {
            _center = adjusted;
          });
          try {
            _mapController.move(adjusted, z);
          } catch (_) {}
          try {
            if (baseMap == 2) {
              _gmController?.moveCamera(
                gm.CameraUpdate.newLatLngZoom(
                  gm.LatLng(adjusted.latitude, adjusted.longitude),
                  z,
                ),
              );
            }
          } catch (_) {}
        }
      }
    } else {
      // フォールバック: 現在の潮汐ポイントの緯度経度があればそれを使用
      final fallbackLat = Common.instance.gSioInfo.lat;
      final fallbackLng = Common.instance.gSioInfo.lang;
      final fallbackName =
          Common.instance.gSioInfo.portName.isNotEmpty
              ? Common.instance.gSioInfo.portName
              : (Common.instance.selectedTeibouName.isNotEmpty
                  ? Common.instance.selectedTeibouName
                  : '');
      if ((fallbackLat != 0.0 || fallbackLng != 0.0)) {
        if (_lastLat != fallbackLat ||
            _lastLng != fallbackLng ||
            _lastName != fallbackName ||
            diaryModeChanged ||
            ambiguousChanged) {
          _center = LatLng(fallbackLat, fallbackLng);
          _lastLat = fallbackLat;
          _lastLng = fallbackLng;
          _lastName = fallbackName;
          _lastFishingDiaryMode = diaryMode;
          _lastAmbiguousLevel = ambiguousLevel;
          await _loadMarkers(
            centerName: fallbackName,
            lat: fallbackLat,
            lng: fallbackLng,
            radiusKm: kNearbyMapSearchRadiusKm,
          );
          if (mounted && _center != null) {
            final viewport = diaryMode ? await _buildDiaryViewport() : null;
            final displayCenter = _center!;
            final displayRadiusKm =
                viewport?.radiusKm ?? kNearbyMapSearchRadiusKm;
            final z =
                (diaryMode && !diaryModeChanged)
                    ? _currentZoom
                    : diaryMode
                    ? _zoomForRadius(displayRadiusKm)
                    : _zoomForRadius(30.0) + 1.0;
            final adjusted = _computeCenteredForSheet(displayCenter, z);
            setState(() {
              _center = adjusted;
            });
            try {
              _mapController.move(adjusted, z);
            } catch (_) {}
            try {
              if (baseMap == 2) {
                _gmController?.moveCamera(
                  gm.CameraUpdate.newLatLngZoom(
                    gm.LatLng(adjusted.latitude, adjusted.longitude),
                    z,
                  ),
                );
              }
            } catch (_) {}
          }
        }
      } else {
        // どちらも未設定ならプレースホルダ
        _center = null;
        setState(() {});
      }
    }
  }

  Future<bool> enterApplyMode() async {
    if (_applyMode) return true;
    final verified = await _ensureEmailVerified(authPurposeLabel: '釣り場登録');
    if (!verified) return false;
    final shouldShowGuide = await _shouldShowApplyModeGuide();
    final bool newMode = true;
    setState(() {
      _applyMode = newMode;
      _applyPoint = null;
      _gmApplyPoint = null;
      _hideApplyModeGuideCheckbox = false;
      _showApplyModeGuide = shouldShowGuide;
      _applyGuideLeft = null;
      _applyGuideTop = null;
      try {
        _gmMarkers.removeWhere((m) => m.markerId.value == 'apply');
      } catch (_) {}
    });
    _lastLat = null;
    _lastLng = null;
    _lastName = '';
    await _prepare();
    return true;
  }

  Future<bool> exitApplyMode() async {
    if (!_applyMode) return true;
    setState(() {
      _applyMode = false;
      _applyPoint = null;
      _gmApplyPoint = null;
      _showApplyModeGuide = false;
      _hideApplyModeGuideCheckbox = false;
      _applyGuideLeft = null;
      _applyGuideTop = null;
      try {
        _gmMarkers.removeWhere((m) => m.markerId.value == 'apply');
      } catch (_) {}
    });
    _lastLat = null;
    _lastLng = null;
    _lastName = '';
    await _prepare();
    return true;
  }

  Future<bool> toggleApplyMode() async {
    if (_applyMode) {
      return exitApplyMode();
    }
    return enterApplyMode();
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) setState(() => _myPos = LatLng(pos.latitude, pos.longitude));

      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((p) {
        if (!mounted) return;
        setState(() => _myPos = LatLng(p.latitude, p.longitude));
      });
    } catch (_) {}
  }

  void _startBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      setState(() => _blinkOn = !_blinkOn);
    });
  }

  Future<void> _loadMarkers({
    required String centerName,
    required double lat,
    required double lng,
    required double radiusKm,
  }) async {
    _markers.clear();
    _appleAnnotations.clear();
    _gmMarkers.clear();
    _gmPolylines.clear();
    _gmCircles.clear();
    final rows = await _visibleTeibouRows();
    var center = LatLng(lat, lng);
    double maxDkm = 0.0; // 外接円半径計算用
    // 中心マーカー（お気に入りなら拡大＆太字）
    int? centerPortId;
    bool centerPending = false;
    bool centerRejected = false;
    String cn = centerName;
    Map<String, dynamic>? centerRow;
    // 1) 選択済みID優先
    try {
      final prefs = await SharedPreferences.getInstance();
      final sid = prefs.getInt('selected_teibou_id');
      if (sid != null && sid > 0) {
        for (final r in rows) {
          final rid =
              r['port_id'] is int
                  ? r['port_id'] as int
                  : int.tryParse(r['port_id']?.toString() ?? '');
          if (rid == sid) {
            centerRow = r;
            break;
          }
        }
      }
    } catch (_) {}
    // 2) 座標一致（厳密 or 近傍）
    if (centerRow == null) {
      const eps = 1e-8;
      for (final r in rows) {
        final dlat0 = _toDouble(r['latitude']);
        final dlng0 = _toDouble(r['longitude']);
        if (dlat0 == null || dlng0 == null) continue;
        if ((dlat0 - lat).abs() < eps && (dlng0 - lng).abs() < eps) {
          centerRow = r;
          break;
        }
      }
    }
    // 3) 名前一致のうち、中心に最も近い行
    if (centerRow == null) {
      double best = double.infinity;
      Map<String, dynamic>? bestRow;
      for (final r in rows) {
        final name = (r['port_name'] ?? '').toString();
        if (name != centerName) continue;
        final dlat0 = _toDouble(r['latitude']);
        final dlng0 = _toDouble(r['longitude']);
        if (dlat0 == null || dlng0 == null) continue;
        final d = _distanceKm(lat, lng, dlat0, dlng0);
        if (d < best) {
          best = d;
          bestRow = r;
        }
      }
      centerRow = bestRow;
    }
    if (centerRow != null) {
      centerPortId =
          centerRow['port_id'] is int
              ? centerRow['port_id'] as int
              : int.tryParse(centerRow['port_id']?.toString() ?? '');
      final int? flag =
          centerRow['flag'] is int
              ? centerRow['flag'] as int
              : int.tryParse(centerRow['flag']?.toString() ?? '');
      centerPending = (flag == -1);
      centerRejected = (flag == -2 || flag == -3);
      final dlat1 = _toDouble(centerRow['latitude']);
      final dlng1 = _toDouble(centerRow['longitude']);
      if (dlat1 != null && dlng1 != null) {
        center = LatLng(dlat1, dlng1);
      }
      cn = (centerRow['port_name'] ?? cn).toString();
    }
    if (centerRow == null && rows.isNotEmpty) {
      double best = double.infinity;
      Map<String, dynamic>? bestRow;
      const double d2r = 3.141592653589793 / 180.0;
      final rlat = lat * d2r;
      for (final r in rows) {
        final dlat0 = _toDouble(r['latitude']);
        final dlng0 = _toDouble(r['longitude']);
        if (dlat0 == null || dlng0 == null) continue;
        final d = _haversine(lat, lng, dlat0, dlng0, cosLat: rlat);
        if (d < best) {
          best = d;
          bestRow = r;
        }
      }
      if (bestRow != null) {
        centerRow = bestRow;
        centerPortId =
            bestRow['port_id'] is int
                ? bestRow['port_id'] as int
                : int.tryParse(bestRow['port_id']?.toString() ?? '');
        final dlat1 = _toDouble(bestRow['latitude']);
        final dlng1 = _toDouble(bestRow['longitude']);
        if (dlat1 != null && dlng1 != null) {
          center = LatLng(dlat1, dlng1);
        }
        cn = (bestRow['port_name'] ?? cn).toString();
        final int? f =
            bestRow['flag'] is int
                ? bestRow['flag'] as int
                : int.tryParse(bestRow['flag']?.toString() ?? '');
        centerPending = (f == -1);
        centerRejected = (f == -2 || f == -3);
        try {
          String? np;
          if (!_pointsLoading && _pointCoords.isNotEmpty) {
            np = _nearestPointName(center.latitude, center.longitude);
          }
          final int? prefId =
              bestRow['todoufuken_id'] is int
                  ? bestRow['todoufuken_id'] as int
                  : int.tryParse(bestRow['todoufuken_id']?.toString() ?? '') ??
                      int.tryParse(
                        bestRow['pref_id_from_port']?.toString() ?? '',
                      );
          await Common.instance.saveSelectedTeibou(
            cn,
            np ?? (Common.instance.tidePoint),
            id: centerPortId,
            lat: center.latitude,
            lng: center.longitude,
            prefId: prefId,
          );
        } catch (_) {}
      }
    }
    // フォールバック: 厳密一致で見つからなかった場合、選択IDや名前から再判定
    if (!centerPending && !centerRejected) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final sid = prefs.getInt('selected_teibou_id');
        Map<String, dynamic>? rr;
        if (sid != null && sid > 0) {
          for (final r in rows) {
            final rid =
                r['port_id'] is int
                    ? r['port_id'] as int
                    : int.tryParse(r['port_id']?.toString() ?? '');
            if (rid == sid) {
              rr = r;
              break;
            }
          }
        }
        rr ??= rows.cast<Map<String, dynamic>?>().firstWhere(
          (r) => (r?['port_name'] ?? '').toString() == centerName,
          orElse: () => null,
        );
        if (rr != null) {
          final int? f =
              rr['flag'] is int
                  ? rr['flag'] as int
                  : int.tryParse(rr['flag']?.toString() ?? '');
          centerPending = (f == -1);
          centerRejected = (f == -2 || f == -3);
          centerPortId ??=
              rr['port_id'] is int
                  ? rr['port_id'] as int
                  : int.tryParse(rr['port_id']?.toString() ?? '');
          if (!centerRejected) {
            final dlat1 = _toDouble(rr['latitude']);
            final dlng1 = _toDouble(rr['longitude']);
            if (dlat1 != null && dlng1 != null) {
              center = LatLng(dlat1, dlng1);
            }
            cn = (rr['port_name'] ?? cn).toString();
          }
        }
      } catch (_) {}
    }
    // 非承認が現在選択中なら、最寄りの別スポットへフォールバック
    if (centerRejected) {
      double best = double.infinity;
      Map<String, dynamic>? bestRow;
      const double d2r = 3.141592653589793 / 180.0;
      final rlat = lat * d2r;
      for (final r in rows) {
        final int? flag =
            r['flag'] is int
                ? r['flag'] as int
                : int.tryParse(r['flag']?.toString() ?? '');
        if (flag == -2 || flag == -3) continue;
        final dlat0 = _toDouble(r['latitude']);
        final dlng0 = _toDouble(r['longitude']);
        if (dlat0 == null || dlng0 == null) continue;
        final a = _haversine(lat, lng, dlat0, dlng0, cosLat: rlat);
        if (a < best) {
          best = a;
          bestRow = r;
        }
      }
      if (bestRow != null) {
        final nlat = _toDouble(bestRow['latitude']) ?? lat;
        final nlng = _toDouble(bestRow['longitude']) ?? lng;
        cn = (bestRow['port_name'] ?? '').toString();
        center = LatLng(nlat, nlng);
        centerPortId =
            bestRow['port_id'] is int
                ? bestRow['port_id'] as int
                : int.tryParse(bestRow['port_id']?.toString() ?? '');
        final int? f2 =
            bestRow['flag'] is int
                ? bestRow['flag'] as int
                : int.tryParse(bestRow['flag']?.toString() ?? '');
        centerPending = (f2 == -1);
        centerRejected = false;
        try {
          String? np;
          if (!_pointsLoading && _pointCoords.isNotEmpty) {
            np = _nearestPointName(nlat, nlng);
          }
          final int? prefId =
              bestRow['todoufuken_id'] is int
                  ? bestRow['todoufuken_id'] as int
                  : int.tryParse(bestRow['todoufuken_id']?.toString() ?? '') ??
                      int.tryParse(
                        bestRow['pref_id_from_port']?.toString() ?? '',
                      );
          await Common.instance.saveSelectedTeibou(
            cn,
            np ?? (Common.instance.tidePoint),
            id: centerPortId,
            lat: nlat,
            lng: nlng,
            prefId: prefId,
          );
          Common.instance.shouldJumpPage = true;
          Common.instance.notify();
        } catch (_) {}
      }
    }
    final bool isCenterFav =
        centerPortId != null && _favoriteIds.contains(centerPortId);
    final bool diaryMode = Common.instance.fishingDiaryMode;
    final bool showCenterMarker =
        !centerRejected &&
        (!diaryMode ||
            (centerPortId != null && _myDiarySpotIds.contains(centerPortId)));
    // AppleMap 中心注釈
    if (showCenterMarker) {
      _appleAnnotations.add(
        am.Annotation(
          annotationId: am.AnnotationId('c'),
          position: am.LatLng(center.latitude, center.longitude),
        ),
      );
    }
    // GoogleMap 中心マーカー（後でzIndex高めで追加）

    for (final r in rows) {
      final dlat = _toDouble(r['latitude']);
      final dlng = _toDouble(r['longitude']);
      final name = (r['port_name'] ?? '').toString();
      final int? flag =
          r['flag'] is int
              ? r['flag'] as int
              : int.tryParse(r['flag']?.toString() ?? '');
      final bool isPending = flag == -1;
      // 非承認/取り下げは非表示
      if (flag == -2 || flag == -3) {
        continue;
      }
      final displayName = isPending ? '$name (申請中)' : name;
      final int? prefId =
          r['todoufuken_id'] is int
              ? r['todoufuken_id'] as int
              : int.tryParse(r['todoufuken_id']?.toString() ?? '') ??
                  int.tryParse(r['pref_id_from_port']?.toString() ?? '');
      final int? portId =
          r['port_id'] is int
              ? r['port_id'] as int
              : int.tryParse(r['port_id']?.toString() ?? '');
      if (dlat == null || dlng == null) continue;
      final bool isSameAsCenter =
          (centerPortId != null && portId == centerPortId) ||
          ((dlat - center.latitude).abs() < 1e-8 &&
              (dlng - center.longitude).abs() < 1e-8);
      if (diaryMode &&
          !(portId != null &&
              _myDiarySpotIds.contains(portId) &&
              !isSameAsCenter)) {
        continue;
      }
      final d = _distanceKm(lat, lng, dlat, dlng);
      if (diaryMode || (d <= radiusKm && !isSameAsCenter)) {
        if (d > maxDkm) maxDkm = d;
        final bool isFav = portId != null && _favoriteIds.contains(portId);
        final bool hasMyCatch =
            portId != null && _myCatchSpotIds.contains(portId);
        _markers.add(
          fm.Marker(
            width: 220,
            height: isFav ? 76 : 60,
            point: LatLng(dlat, dlng),
            child: GestureDetector(
              onTap: () async {
                await _handleSpotTap(
                  isSelected: isSameAsCenter,
                  isPending: isPending,
                  row: r,
                  name: name,
                  lat: dlat,
                  lng: dlng,
                  portId: portId,
                  prefId: prefId,
                  radiusKm: radiusKm,
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ラベル上、ピン下
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 2,
                          offset: Offset(1, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasMyCatch) ...[
                          _buildMyCatchBadge(),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.black,
                              fontWeight:
                                  isFav ? FontWeight.bold : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.location_pin,
                    color:
                        (flag != null && flag != 0)
                            ? Colors.green
                            : Colors.blueAccent,
                    size: isFav ? 42 : 28,
                  ),
                ],
              ),
            ),
          ),
        );
        // AppleMap 近隣注釈（非承認はここに来ない）
        _appleAnnotations.add(
          am.Annotation(
            annotationId: am.AnnotationId('n${portId ?? name}'),
            position: am.LatLng(dlat, dlng),
          ),
        );
        // GoogleMap 近隣マーカー（住所/状態をスニペット表示）
        _gmMarkers.add(
          gm.Marker(
            markerId: gm.MarkerId('n${portId ?? name}'),
            position: gm.LatLng(dlat, dlng),
            consumeTapEvents: true,
            infoWindow: gm.InfoWindow(
              title: displayName,
              snippet: () {
                String _flagText(int? f) {
                  switch (f) {
                    case 0:
                      return '運営登録済み';
                    case -1:
                      return 'ユーザ申請中';
                    case -2:
                      return 'ユーザ申請非承認';
                    case -3:
                      return 'ユーザ申請取り下げ';
                    case 1:
                      return 'ユーザ登録承認済み';
                    default:
                      return '';
                  }
                }

                String _shortAddress(String s) {
                  final t = s.trim();
                  if (t.isEmpty) return t;
                  final parts = t.split(RegExp(r'\s+'));
                  return parts.length >= 2
                      ? '${parts[0]} ${parts[1]}'
                      : parts[0];
                }

                final addr = _shortAddress((r['address'] ?? '').toString());
                final st = _flagText(flag);
                final latlng =
                    '緯度: ${dlat.toStringAsFixed(5)}, 経度: ${dlng.toStringAsFixed(5)}';
                final addrLine = '住所: ' + (addr.isNotEmpty ? addr : '不明');
                final stLine = '状態: ' + (st.isNotEmpty ? st : '不明');
                return '$latlng\n$addrLine\n$stLine';
              }(),
            ),
            icon:
                (flag != null && flag != 0)
                    ? gm.BitmapDescriptor.defaultMarkerWithHue(
                      gm.BitmapDescriptor.hueGreen,
                    )
                    : gm.BitmapDescriptor.defaultMarker,
            onTap: () async {
              await _handleSpotTap(
                isSelected: isSameAsCenter,
                isPending: isPending,
                row: r,
                name: name,
                lat: dlat,
                lng: dlng,
                portId: portId,
                prefId: prefId,
                radiusKm: radiusKm,
              );
            },
            zIndex: 0,
          ),
        );
      }
    }

    // 中心マーカーを最後に追加（最前面に表示）
    if (!centerRejected)
      _markers.add(
        fm.Marker(
          width: 200,
          height: isCenterFav ? 84 : 64,
          point: center,
          child: GestureDetector(
            onTap: () async {
              await _handleSpotTap(
                isSelected: true,
                isPending: centerPending,
                row: centerRow ?? <String, dynamic>{},
                name: centerName,
                lat: center.latitude,
                lng: center.longitude,
                portId: centerPortId,
                prefId: _rowPrefId(centerRow),
                radiusKm: kNearbyMapSearchRadiusKm,
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 2),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (centerPortId != null &&
                          _myCatchSpotIds.contains(centerPortId)) ...[
                        _buildMyCatchBadge(),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          centerPending ? '$cn (申請中)' : cn,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: isCenterFav ? 48 : 32,
                ),
              ],
            ),
          ),
        ),
      );

    // GoogleMap 中心マーカー（zIndexを高めに）
    if (showCenterMarker)
      _gmMarkers.add(
        gm.Marker(
          markerId: const gm.MarkerId('c'),
          position: gm.LatLng(center.latitude, center.longitude),
          consumeTapEvents: true,
          infoWindow: gm.InfoWindow(
            title: centerPending ? '$cn (申請中)' : cn,
            snippet: '中心',
          ),
          onTap: () async {
            await _handleSpotTap(
              isSelected: true,
              isPending: centerPending,
              row: centerRow ?? <String, dynamic>{},
              name: centerName,
              lat: center.latitude,
              lng: center.longitude,
              portId: centerPortId,
              prefId: _rowPrefId(centerRow),
              radiusKm: kNearbyMapSearchRadiusKm,
            );
          },
          zIndex: 1000,
        ),
      );

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child:
          _center == null
              ? const ColoredBox(color: Colors.black)
              : Stack(
                children: [
                  if (Platform.isIOS && baseMap == 1)
                    am.AppleMap(
                      initialCameraPosition: am.CameraPosition(
                        target: am.LatLng(
                          _center!.latitude,
                          _center!.longitude,
                        ),
                        zoom: 12,
                      ),
                      annotations: _appleAnnotations,
                    )
                  else if (baseMap == 2)
                    gm.GoogleMap(
                      initialCameraPosition: gm.CameraPosition(
                        target: gm.LatLng(
                          _center!.latitude,
                          _center!.longitude,
                        ),
                        zoom: 12,
                      ),
                      mapType:
                          _isSatellite ? gm.MapType.hybrid : gm.MapType.normal,
                      onMapCreated: (c) => _gmController = c,
                      onLongPress: (pos) async {
                        if (!_applyMode) {
                          if (Common.instance.fishingDiaryMode) return;
                          // 閲覧モード: 半径30km以内の釣り場を表示し、最寄りを選択
                          await _onViewLongPress(pos.latitude, pos.longitude);
                          return;
                        }
                        // 長押しで申請用ピンを設置
                        setState(() {
                          _gmApplyPoint = pos;
                          // 既存の 'apply' マーカーを除去してから追加
                          _gmMarkers.removeWhere(
                            (m) => m.markerId.value == 'apply',
                          );
                          _gmMarkers.add(
                            gm.Marker(
                              markerId: const gm.MarkerId('apply'),
                              position: pos,
                              infoWindow: gm.InfoWindow(
                                title: '釣り場登録',
                                onTap: () {
                                  _openApplyForm(pos.latitude, pos.longitude);
                                },
                              ),
                              onTap: () {
                                // タップでインフォウィンドウを表示
                                try {
                                  _gmController?.showMarkerInfoWindow(
                                    const gm.MarkerId('apply'),
                                  );
                                } catch (_) {}
                              },
                            ),
                          );
                        });
                        // 可能なら情報ウィンドウを即表示
                        try {
                          _gmController?.showMarkerInfoWindow(
                            const gm.MarkerId('apply'),
                          );
                        } catch (_) {}
                      },
                      onCameraMove: (pos) {
                        if (!mounted) return;
                        setState(() {
                          _center = LatLng(
                            pos.target.latitude,
                            pos.target.longitude,
                          );
                          _currentZoom = pos.zoom;
                        });
                      },
                      markers: _gmMarkers,
                      polylines: _gmPolylines,
                      circles: _gmCircles,
                      myLocationEnabled: _myPos != null,
                      myLocationButtonEnabled: true,
                      compassEnabled: true,
                      zoomControlsEnabled: false,
                    )
                  else
                    fm.FlutterMap(
                      options: fm.MapOptions(
                        initialCenter: _center!,
                        // 半径30km相当より1段ズームイン（約2倍拡大）
                        initialZoom: _zoomForRadius(30.0) + 1.0,
                        interactionOptions: const fm.InteractionOptions(
                          flags: fm.InteractiveFlag.all,
                        ),
                        onLongPress: (tapPosition, latlng) async {
                          if (!_applyMode) {
                            if (Common.instance.fishingDiaryMode) return;
                            // 閲覧モード: 半径30km以内の釣り場を表示し、最寄りを選択
                            await _onViewLongPress(
                              latlng.latitude,
                              latlng.longitude,
                            );
                            return;
                          }
                          // 長押しで申請用ピンを設置
                          setState(() {
                            _applyPoint = latlng;
                          });
                        },
                        onPositionChanged: (pos, hasGesture) {
                          if (!mounted) return;
                          setState(() {
                            if (pos.center != null) {
                              _center = pos.center;
                            }
                            if (pos.zoom != null) {
                              _currentZoom = pos.zoom!;
                            }
                          });
                        },
                      ),
                      mapController: _mapController,
                      children: [
                        fm.TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'jp.bouzer.seafishingmap',
                          tileProvider: fm.NetworkTileProvider(),
                        ),
                        fm.MarkerLayer(markers: _buildAllMarkers()),
                        const fm.RichAttributionWidget(
                          attributions: [
                            fm.TextSourceAttribution(
                              '© OpenStreetMap contributors',
                            ),
                          ],
                        ),
                      ],
                    ),
                  // 地図上部に白背景のパネルを配置（釣果 / お気に入り / 経路表示）
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildTopOverlayPanel(context),
                  ),
                  // 釣り場名の上部オーバーレイは廃止（選択ピン上のラベルで代替）
                  // 左上（同じY位置）にモード表示バッジ
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _showModeInfoDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 2),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _applyMode
                                  ? Icons.edit_location_alt
                                  : Icons.remove_red_eye,
                              size: 16,
                              color: Colors.black87,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _applyMode ? '釣り場登録モード' : '閲覧モード',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_applyMode) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () async {
                                  await exitApplyMode();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.black26),
                                  ),
                                  child: const Text(
                                    'キャンセル',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.black54,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_applyMode && _showApplyModeGuide)
                    Positioned.fill(child: _buildApplyModeGuideOverlay()),
                  // 下から引っ張り出すボトムシート（投稿一覧などを想定）
                  if (!_applyMode)
                    Builder(
                      key: _sheetActuatorKey,
                      builder:
                          (context) => DraggableScrollableActuator(
                            child: KeyedSubtree(
                              key: ValueKey('epoch-$_sheetEpoch'),
                              child: _buildDraggableBottomSheet(),
                            ),
                          ),
                    ),
                  if (_showTideOverlay)
                    Positioned.fill(child: _buildTideOverlay()),
                ],
              ),
    );
  }

  Widget _buildDraggableBottomSheet() {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.25, // 初期は少しだけ見せる（広めに）
      minChildSize: 0.0, // 非表示まで下げられる
      maxChildSize: 0.92, // 上部に余白を残す
      snap: true,
      snapAnimationDuration: const Duration(milliseconds: 200),
      // 下方向(0.0)へのスナップは使わず、上方向の段階にだけスナップ
      snapSizes: const [0.25, 0.5, 0.9],
      builder: (context, controller) {
        // シートサイズの変化を監視して記録
        try {
          _sheetController.removeListener(_onSheetChanged);
        } catch (_) {}
        _sheetController.addListener(_onSheetChanged);
        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            elevation: 8,
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: _BottomSheetCatchList(
              key: ValueKey('sheet-${_sheetReloadTick}'),
              extController: controller,
            ),
          ),
        );
      },
    );
  }

  Widget _buildApplyModeGuideCard() {
    return Material(
      elevation: 8,
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              color: _navyBg,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: const Row(
                children: [
                  Icon(Icons.lightbulb_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    '釣り場登録モードとは',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '新しく登録したい釣り場の位置を地図上で長押ししてください。長押しすれば何度でも修正できます。\n'
                    'その位置でよければ「釣り場登録」ピンをタップして釣り場の情報を入力してください。',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          value: _hideApplyModeGuideCheckbox,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('今後表示しない'),
                          onChanged: (v) {
                            setState(() {
                              _hideApplyModeGuideCheckbox = v ?? false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          await _saveHideApplyModeGuide(
                            _hideApplyModeGuideCheckbox,
                          );
                          if (!mounted) return;
                          setState(() {
                            _showApplyModeGuide = false;
                          });
                        },
                        child: const Text('了解'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApplyModeGuideOverlay() {
    return IgnorePointer(
      ignoring: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double cardWidth = math.min(constraints.maxWidth - 24, 420);
          final double minLeft = 12;
          final double maxLeft = math.max(
            12,
            constraints.maxWidth - cardWidth - 12,
          );
          final double defaultTop = math.max(80, constraints.maxHeight - 300);
          final double minTop = 72;
          final double maxTop = math.max(120, constraints.maxHeight - 120);
          final double left = (_applyGuideLeft ?? 12).clamp(minLeft, maxLeft);
          final double top = (_applyGuideTop ?? defaultTop).clamp(
            minTop,
            maxTop,
          );
          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: cardWidth,
                child: _buildDraggableApplyModeGuideCard(
                  maxLeft: maxLeft,
                  minLeft: minLeft,
                  minTop: minTop,
                  maxTop: maxTop,
                  currentLeft: left,
                  currentTop: top,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDraggableApplyModeGuideCard({
    required double minLeft,
    required double maxLeft,
    required double minTop,
    required double maxTop,
    required double currentLeft,
    required double currentTop,
  }) {
    return Material(
      elevation: 8,
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                if (_applyGuideLeft == null || _applyGuideTop == null) {
                  setState(() {
                    _applyGuideLeft = currentLeft;
                    _applyGuideTop = currentTop;
                  });
                }
              },
              onPanUpdate: (details) {
                setState(() {
                  _applyGuideLeft = ((_applyGuideLeft ?? currentLeft) +
                          details.delta.dx)
                      .clamp(minLeft, maxLeft);
                  _applyGuideTop = ((_applyGuideTop ?? currentTop) +
                          details.delta.dy)
                      .clamp(minTop, maxTop);
                });
              },
              child: Container(
                width: double.infinity,
                color: _navyBg,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: const Row(
                  children: [
                    Icon(
                      Icons.lightbulb_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '釣り場登録モードとは',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.open_with, color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '新しく登録したい釣り場の位置を地図上で長押ししてください。長押しすれば何度でも修正できます。\n'
                    'その位置でよければ「釣り場登録」ピンをタップして釣り場の情報を入力してください。',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          value: _hideApplyModeGuideCheckbox,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('今後表示しない'),
                          onChanged: (v) {
                            setState(() {
                              _hideApplyModeGuideCheckbox = v ?? false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          await _saveHideApplyModeGuide(
                            _hideApplyModeGuideCheckbox,
                          );
                          if (!mounted) return;
                          setState(() {
                            _showApplyModeGuide = false;
                          });
                        },
                        child: const Text('了解'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _ensureSheetVisible({bool ifHiddenOnly = false}) {
    try {
      final current = _sheetController.size;
      if (!ifHiddenOnly || current <= 0.01) {
        _sheetController.animateTo(
          0.25,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {}
    // フォールバック: Actuatorで初期サイズにリセット
    try {
      final ctx = _sheetActuatorKey.currentContext;
      if (ctx != null && _safeSheetSize() <= 0.01) {
        DraggableScrollableActuator.reset(ctx);
      }
    } catch (_) {}
  }

  void _recreateSheet({bool show = false}) {
    // コントローラを作り直して初期サイズに戻す
    _sheetController = DraggableScrollableController();
    if (mounted)
      setState(() {
        _sheetEpoch++;
      });
    if (show) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureSheetVisible(),
      );
    }
  }

  void _onSheetChanged() {
    try {
      final s = _sheetController.size;
      if (s > 0.01) _lastSheetSize = s;
    } catch (_) {}
  }

  double _safeSheetSize() {
    try {
      return _sheetController.size;
    } catch (_) {
      return 0.0;
    }
  }

  Widget _buildTideOverlay() {
    const double headerH = 48;
    final bool canPop = _tideNavKey.currentState?.canPop() ?? false;
    return SafeArea(
      top: false,
      bottom: true,
      child: Material(
        color: Colors.white,
        child: Column(
          children: [
            SizedBox(
              height: headerH,
              child: Row(
                children: [
                  if (canPop)
                    BackButton(
                      onPressed: () => _tideNavKey.currentState?.maybePop(),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _showTideOverlay = false),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    canPop ? '日付' : '潮汐',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Navigator(
                key: _tideNavKey,
                observers: [_tideNavObserver],
                onGenerateRoute: (settings) {
                  return MaterialPageRoute(
                    builder:
                        (_) => _TideHomePage(
                          controller: _tidePageController,
                          baseDate: _tideBaseDate,
                        ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopOverlayPanel(BuildContext context) {
    Widget item({
      required Widget icon,
      required String label,
      required VoidCallback? onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 6.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (baseMap != 2) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          item(
            icon: Icon(
              _isSatellite ? Icons.satellite_alt : Icons.satellite_alt_outlined,
              color: Colors.black87,
            ),
            label: '衛星表示',
            onTap:
                () => setState(() {
                  _isSatellite = !_isSatellite;
                }),
          ),
        ],
      ),
    );
  }

  Future<void> _onToggleFavorite(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final prefs = await SharedPreferences.getInstance();
      int? portId = prefs.getInt('selected_teibou_id');
      String portName = Common.instance.selectedTeibouName;
      if ((portId == null || portId <= 0) && portName.isNotEmpty) {
        // 名前から検索して補完
        try {
          final rows = await SioDatabase().getAllTeibouWithPrefecture();
          for (final r in rows) {
            final n = (r['port_name'] ?? '').toString();
            if (n == portName) {
              portId =
                  r['port_id'] is int
                      ? r['port_id'] as int
                      : int.tryParse(r['port_id']?.toString() ?? '');
              break;
            }
          }
        } catch (_) {}
      }
      if (portId == null || portId <= 0) {
        messenger?.showSnackBar(const SnackBar(content: Text('釣り場情報が見つかりません')));
        return;
      }
      // 現在の登録状態を判定
      final favs = await SioDatabase().getFavoriteTeibouIds();
      final isFav = favs.contains(portId);
      if (!isFav) {
        final verified = await _ensureEmailVerified(authPurposeLabel: 'お気に入り');
        if (!verified) return;
      }
      if (isFav) {
        await SioDatabase().removeFavoriteTeibou(portId);
      } else {
        await SioDatabase().addFavoriteTeibou(portId);
      }
      // リモート同期（失敗は通知して継続）
      try {
        final info = await loadUserInfo() ?? await getOrInitUserInfo();
        final url = '${AppConfig.instance.baseUrl}regist_favorite.php';
        final resp = await http
            .post(
              Uri.parse(url),
              headers: const {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json, text/plain, */*',
              },
              body: {
                'user_id': info.userId.toString(),
                'spot_id': portId.toString(),
                'action': isFav ? 'delete' : 'enter',
              },
            )
            .timeout(kHttpTimeout);
        if (resp.statusCode != 200) {
          messenger?.showSnackBar(
            SnackBar(
              content: Text(
                isFav
                    ? 'お気に入り解除の同期に失敗しました（${resp.statusCode}）'
                    : 'お気に入りの同期に失敗しました（${resp.statusCode}）',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          messenger?.showSnackBar(
            SnackBar(
              content: Text(
                isFav ? 'お気に入り解除: $portName' : 'お気に入り登録: $portName',
              ),
            ),
          );
        }
      } catch (_) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              isFav
                  ? 'お気に入り解除の同期中にエラーが発生しました（ローカル保存済み）'
                  : 'お気に入りの同期中にエラーが発生しました（ローカル保存済み）',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      // 再読込して反映（マーカー拡大/太字を即座に反映）
      await _loadFavorites();
      try {
        final name =
            (_lastName.isNotEmpty)
                ? _lastName
                : Common.instance.selectedTeibouName;
        final lat = (_lastLat ?? Common.instance.selectedTeibouLat);
        final lng = (_lastLng ?? Common.instance.selectedTeibouLng);
        if ((lat != 0.0 || lng != 0.0) && name.isNotEmpty) {
          await _loadMarkers(
            centerName: name,
            lat: lat,
            lng: lng,
            radiusKm: kNearbyMapSearchRadiusKm,
          );
        } else if (_center != null) {
          await _loadMarkers(
            centerName: name,
            lat: _center!.latitude,
            lng: _center!.longitude,
            radiusKm: kNearbyMapSearchRadiusKm,
          );
        }
      } catch (_) {}
      if (mounted) setState(() {});
    } catch (_) {
      messenger?.showSnackBar(const SnackBar(content: Text('お気に入りの更新に失敗しました')));
    }
  }

  Future<void> _onOpenRoute(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final lat = Common.instance.selectedTeibouLat;
    final lng = Common.instance.selectedTeibouLng;
    if (lat == 0.0 && lng == 0.0) {
      // フォールバック: gSioInfo
      final fl = Common.instance.gSioInfo.lat;
      final fg = Common.instance.gSioInfo.lang;
      if (fl == 0.0 && fg == 0.0) {
        messenger?.showSnackBar(const SnackBar(content: Text('位置情報がありません')));
        return;
      }
      if (Common.instance.mapKind == MapType.googleMaps.index) {
        await Common.instance.openGoogleMaps(fl, fg);
      } else if (Common.instance.mapKind == MapType.appleMaps.index) {
        await Common.instance.openAppleMaps(fl, fg);
      } else {
        messenger?.showSnackBar(
          const SnackBar(content: Text('設定から地図アプリを選択してください')),
        );
      }
      return;
    }

    if (Common.instance.mapKind == MapType.googleMaps.index) {
      await Common.instance.openGoogleMaps(lat, lng);
    } else if (Common.instance.mapKind == MapType.appleMaps.index) {
      await Common.instance.openAppleMaps(lat, lng);
    } else {
      messenger?.showSnackBar(
        const SnackBar(content: Text('設定から地図アプリを選択してください')),
      );
    }
  }

  Future<void> _loadPointCoords() async {
    // Common.portFileData: [pointName, fileName]
    final pairs = Common.instance.portFileData;
    final map = <String, Offset>{};
    for (final row in pairs) {
      if (row.length < 2) continue;
      final name = row[0];
      final file = row[1];
      if (file is String && file.length >= 2) {
        final prefix = file.substring(0, 2);
        final n = int.tryParse(prefix);
        if (n == null || n < 1 || n > 47) {
          continue;
        }
      }
      final info = SioInfo();
      try {
        final ok = await Common.instance.getPortData(file, info);
        if (!ok) continue;
        map[name] = Offset(info.lat, info.lang);
      } catch (_) {
        continue;
      }
    }
    if (!mounted) return;
    setState(() {
      _pointCoords
        ..clear()
        ..addAll(map);
      _pointsLoading = false;
    });
  }

  String? _nearestPointName(double lat, double lng) {
    double best = double.infinity;
    String? bestName;
    const double deg2rad = 3.141592653589793 / 180.0;
    final rlat = lat * deg2rad;
    for (final e in _pointCoords.entries) {
      final p = e.value;
      final d = _haversine(lat, lng, p.dx, p.dy, cosLat: rlat);
      if (d < best) {
        best = d;
        bestName = e.key;
      }
    }
    return bestName;
  }

  double _haversine(
    double lat1,
    double lon1,
    double lat2,
    double lon2, {
    double? cosLat,
  }) {
    const double deg2rad = 3.141592653589793 / 180.0;
    final dLat = (lat2 - lat1) * deg2rad;
    final dLon = (lon2 - lon1) * deg2rad;
    final sLat = math.sin(dLat / 2);
    final sLon = math.sin(dLon / 2);
    final a =
        sLat * sLat +
        math.cos(lat1 * deg2rad) * math.cos(lat2 * deg2rad) * sLon * sLon;
    return a;
  }

  List<fm.Marker> _buildAllMarkers() {
    final list = <fm.Marker>[];
    // 申請ピン（FlutterMap）
    if (_applyPoint != null) {
      list.add(
        fm.Marker(
          width: 200,
          height: 64,
          point: _applyPoint!,
          child: GestureDetector(
            onTap:
                () => _openApplyForm(
                  _applyPoint!.latitude,
                  _applyPoint!.longitude,
                ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 2,
                        offset: Offset(1, 1),
                      ),
                    ],
                  ),
                  child: const Text(
                    '釣り場登録',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.location_on, color: Colors.purple, size: 28),
              ],
            ),
          ),
        ),
      );
    }
    list.addAll(_markers);
    if (_myPos != null) {
      list.add(
        fm.Marker(
          width: 36,
          height: 36,
          point: _myPos!,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 350),
            opacity: _blinkOn ? 1.0 : 0.2,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 4,
                    offset: Offset(1, 1),
                  ),
                ],
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ),
      );
    }
    return list;
  }

  void _openApplyForm(double lat, double lng) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SpotApplyFormPage(lat: lat, lng: lng)),
    ).then((res) {
      if (!mounted) return;
      if (res == true) {
        setState(() {
          _applyMode = false;
          _applyPoint = null;
          _gmApplyPoint = null;
          try {
            _gmMarkers.removeWhere((m) => m.markerId.value == 'apply');
          } catch (_) {}
        });
      }
    });
  }

  @override
  void dispose() {
    Common.instance.removeListener(_onCommonChanged);
    _blinkTimer?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371.0; // km
    const double d2r = math.pi / 180.0;
    final dLat = (lat2 - lat1) * d2r;
    final dLon = (lon2 - lon1) * d2r;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * d2r) *
            math.cos(lat2 * d2r) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _zoomForRadius(double radiusKm) {
    if (radiusKm <= 5) return 13.5;
    if (radiusKm <= 10) return 12.5;
    if (radiusKm <= 20) return 11.5;
    if (radiusKm <= 30) return 11.0;
    if (radiusKm <= 50) return 10.5;
    if (radiusKm <= 100) return 9.5;
    if (radiusKm <= 200) return 8.5;
    if (radiusKm <= 400) return 7.5;
    if (radiusKm <= 800) return 6.5;
    if (radiusKm <= 1600) return 5.5;
    if (radiusKm <= 3200) return 4.5;
    return 3.5;
  }

  String? _kubunLabelLocal(String kubun) {
    final v = kubun.trim();
    final lv = v.toLowerCase();
    switch (lv) {
      case '1':
        return '地域港';
      case '2':
        return '拠点港';
      case '3':
        return '主要港';
      case '4':
        return '特殊港';
      case 'gyoko':
        return '漁港';
      case 'iso':
        return '磯';
      case 'kako':
        return '河口';
      case 'surf':
        return 'サーフ';
      case 'teibo':
        return '堤防';
      case 'teibou':
        return '堤防';
      default:
        if (v == '特3') return '最重要港';
        return null;
    }
  }

  Future<void> _showCurrentSpotInfoDialog() async {
    try {
      final spotName =
          Common.instance.selectedTeibouName.isNotEmpty
              ? Common.instance.selectedTeibouName
              : Common.instance.tidePoint;
      final rows = await _visibleTeibouRows();
      Map<String, dynamic>? row;
      // 1) ID優先（保存済みの selected_teibou_id）
      try {
        final prefs = await SharedPreferences.getInstance();
        final sid = prefs.getInt('selected_teibou_id');
        if (sid != null && sid > 0) {
          for (final r in rows) {
            final rid =
                r['port_id'] is int
                    ? r['port_id'] as int
                    : int.tryParse(r['port_id']?.toString() ?? '');
            if (rid == sid) {
              row = r;
              break;
            }
          }
        }
      } catch (_) {}
      // 2) 見つからなければ名前一致
      if (row == null) {
        for (final r in rows) {
          final n = (r['port_name'] ?? '').toString();
          if (n == spotName) {
            row = r;
            break;
          }
        }
      }
      // 見つからない場合は、現在の選択座標に最も近い行を採用
      final double selLat =
          Common.instance.selectedTeibouLat != 0.0
              ? Common.instance.selectedTeibouLat
              : (_center?.latitude ?? 0.0);
      final double selLng =
          Common.instance.selectedTeibouLng != 0.0
              ? Common.instance.selectedTeibouLng
              : (_center?.longitude ?? 0.0);
      if (row == null && (selLat != 0.0 || selLng != 0.0)) {
        double best = double.infinity;
        Map<String, dynamic>? bestRow;
        for (final r in rows) {
          final dlat0 = _toDouble(r['latitude']);
          final dlng0 = _toDouble(r['longitude']);
          if (dlat0 == null || dlng0 == null) continue;
          final d = _distanceKm(selLat, selLng, dlat0, dlng0);
          if (d < best) {
            best = d;
            bestRow = r;
          }
        }
        if (bestRow != null) row = bestRow;
      }
      String prefName = '';
      if (row != null) {
        prefName = (row['todoufuken_name'] ?? '').toString();
        if (prefName.isEmpty) {
          final pid =
              row['todoufuken_id'] is int
                  ? row['todoufuken_id'] as int
                  : int.tryParse(row['todoufuken_id']?.toString() ?? '');
          if (pid != null && pid > 0) {
            final prefs = await SioDatabase().getTodoufukenAll();
            for (final p in prefs) {
              final id =
                  p['todoufuken_id'] is int
                      ? p['todoufuken_id'] as int
                      : int.tryParse(p['todoufuken_id']?.toString() ?? '');
              if (id == pid) {
                prefName = (p['todoufuken_name'] ?? '').toString();
                break;
              }
            }
          }
        }
      }
      final lat =
          Common.instance.selectedTeibouLat != 0.0
              ? Common.instance.selectedTeibouLat
              : _center?.latitude ?? 0.0;
      final lng =
          Common.instance.selectedTeibouLng != 0.0
              ? Common.instance.selectedTeibouLng
              : _center?.longitude ?? 0.0;
      final kubun = (((row != null) ? row['kubun'] : '') ?? '').toString();
      final kubunLabel = _kubunLabelLocal(kubun) ?? '';
      final yomi =
          (((row != null) ? (row['j_yomi'] ?? row['furigana']) : '') ?? '')
              .toString();
      final address = (((row != null) ? row['address'] : '') ?? '').toString();
      String _shortAddress(String s) {
        final t = s.trim();
        if (t.isEmpty) return t;
        final parts = t.split(RegExp(r'\s+'));
        return parts.length >= 2 ? '${parts[0]} ${parts[1]}' : parts[0];
      }

      final addressShort = _shortAddress(address);
      final int? flag =
          (row != null)
              ? (row['flag'] is int
                  ? row['flag'] as int
                  : int.tryParse(row['flag']?.toString() ?? ''))
              : null;
      String _flagText(int? f) {
        switch (f) {
          case 0:
            return '運営登録済み';
          case -1:
            return 'ユーザ申請中';
          case -2:
            return 'ユーザ申請非承認';
          case -3:
            return 'ユーザ申請取り下げ';
          case 1:
            return 'ユーザ登録承認済み';
          default:
            return '';
        }
      }

      final statusText = _flagText(flag);
      final me = await loadUserInfo();
      final bool isAdmin = ((me?.role ?? '').toLowerCase() == 'admin');
      final dynamic _uidRaw = (row != null) ? row['user_id'] : null;
      final int? currentPortId =
          row == null
              ? null
              : (row['port_id'] is int
                  ? row['port_id'] as int
                  : int.tryParse(row['port_id']?.toString() ?? ''));
      final int? ownerId =
          (_uidRaw is int)
              ? _uidRaw
              : int.tryParse((_uidRaw?.toString() ?? ''));
      final bool canEditPending =
          flag == -1 &&
          ((ownerId != null && me != null && ownerId == me.userId) || isAdmin);
      String? nick;
      try {
        if (ownerId != null) {
          if (me != null && ownerId == me.userId) {
            nick = me.nickName ?? '';
          } else {
            // サーバJOIN値（registrant_name）があれば優先
            final rn =
                ((row != null)
                        ? (row['registrant_name']?.toString() ?? '')
                        : '')
                    .trim();
            if (rn.isNotEmpty) nick = rn; // 投稿と同様: 追加問い合わせは行わない
          }
        }
      } catch (_) {}

      if (!mounted) return;
      final pageContext = context;
      showDialog(
        context: context,
        barrierDismissible: true,
        builder:
            (_) => AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              contentPadding: EdgeInsets.zero,
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                      child: Container(
                        color: const Color(0xFF1E90FF),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(
                                  pageContext,
                                  rootNavigator: true,
                                ).pop();
                                Future.microtask(
                                  () => Navigator.of(pageContext).push(
                                    MaterialPageRoute(
                                      builder:
                                          (_) => const _TideStandalonePage(),
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0D47A1),
                                foregroundColor: Colors.white,
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                              icon: const Icon(Icons.waves, size: 18),
                              label: const Text(
                                '潮汐',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                (() {
                                  final base = spotName;
                                  return (flag == -1) ? '$base (申請中)' : base;
                                })(),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (yomi.isNotEmpty) ...[
                            _infoRow('よみがな', yomi),
                            const SizedBox(height: 6),
                          ],
                          _infoRow('都道府県', prefName),
                          const SizedBox(height: 6),
                          _infoRow('種別', kubunLabel),
                          const SizedBox(height: 6),
                          _infoRow(
                            '緯度経度',
                            '${lat.toStringAsFixed(5)} , ${lng.toStringAsFixed(5)}',
                          ),
                          const SizedBox(height: 6),
                          _infoRow('住所', addressShort),
                          const SizedBox(height: 6),
                          _infoRow('状態', statusText),
                          const SizedBox(height: 6),
                          _infoRow(
                            '登録者',
                            (ownerId != null)
                                ? '${(nick ?? '').isNotEmpty ? nick : '−'}($ownerId)'
                                : '−',
                          ),
                          const SizedBox(height: 12),
                          if (canEditPending)
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F8FF),
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Table(
                                border: TableBorder(
                                  horizontalInside: BorderSide(
                                    color: Colors.grey.shade400,
                                  ),
                                  verticalInside: BorderSide(
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                                children: [
                                  TableRow(
                                    children: [
                                      _spotActionTile(
                                        onPressed: () {
                                          Navigator.of(
                                            pageContext,
                                            rootNavigator: true,
                                          ).pop();
                                          Future.microtask(
                                            () => _openSpotApplyEdit(
                                              row: row ?? <String, dynamic>{},
                                              lat: lat,
                                              lng: lng,
                                              name: spotName,
                                              portId: currentPortId,
                                              buttonMode: 'confirmOnly',
                                            ),
                                          );
                                        },
                                        icon: Icons.edit_note,
                                        label: '申請編集',
                                      ),
                                      _spotActionTile(
                                        onPressed: () {
                                          Navigator.of(
                                            pageContext,
                                            rootNavigator: true,
                                          ).pop();
                                          Future.microtask(
                                            () => _openSpotApplyEdit(
                                              row: row ?? <String, dynamic>{},
                                              lat: lat,
                                              lng: lng,
                                              name: spotName,
                                              portId: currentPortId,
                                              buttonMode: 'withdrawOnly',
                                            ),
                                          );
                                        },
                                        icon: Icons.remove_circle_outline,
                                        label: '申請取り下げ',
                                      ),
                                    ],
                                  ),
                                  TableRow(
                                    children: [
                                      _spotActionTile(
                                        onPressed: () {
                                          Navigator.of(
                                            pageContext,
                                            rootNavigator: true,
                                          ).pop();
                                          Future.microtask(
                                            () =>
                                                _onToggleFavorite(pageContext),
                                          );
                                        },
                                        icon: Icons.bookmark_border,
                                        label: 'お気に入り',
                                      ),
                                      _spotActionTile(
                                        onPressed: () {
                                          Navigator.of(
                                            pageContext,
                                            rootNavigator: true,
                                          ).pop();
                                          Future.microtask(
                                            () => _onOpenRoute(pageContext),
                                          );
                                        },
                                        icon: Icons.directions_car,
                                        label: '経路表示',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F8FF),
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Table(
                                border: TableBorder(
                                  verticalInside: BorderSide(
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                                children: [
                                  TableRow(
                                    children: [
                                      _spotActionTile(
                                        onPressed: () {
                                          Navigator.of(
                                            pageContext,
                                            rootNavigator: true,
                                          ).pop();
                                          Future.microtask(
                                            () =>
                                                _onToggleFavorite(pageContext),
                                          );
                                        },
                                        icon: Icons.bookmark_border,
                                        label: 'お気に入り',
                                      ),
                                      _spotActionTile(
                                        onPressed: () {
                                          Navigator.of(
                                            pageContext,
                                            rootNavigator: true,
                                          ).pop();
                                          Future.microtask(
                                            () => _onOpenRoute(pageContext),
                                          );
                                        },
                                        icon: Icons.directions_car,
                                        label: '経路表示',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      );
    } catch (_) {}
  }

  Widget _infoRow(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$k:',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(v.isNotEmpty ? v : '−')),
      ],
    );
  }

  Widget _spotActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  Widget _spotActionTile({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) {
    return InkWell(
      onTap: onPressed,
      child: SizedBox(
        height: 56,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.black87),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // スクロール補正量（論理px）: 投稿一覧シートと上部オーバーレイを考慮
  double _scrollDeltaForSheet(double zoom) {
    final s = _safeSheetSize().clamp(0.0, 0.95);
    if (s <= 0.01) return 0.0;
    final H = widget.height;
    const double kTopOverlay = 60.0;
    final sheetH = H * s;
    // 中央へ寄せるために必要なスクロール（画面座標系, 下方向=正）
    // GoogleMap.scrollBy は y>0 で地図を下にスクロール＝見えるコンテンツが上へ移動。
    // マーカーを下げたい（中央へ持ってきたい）場合は y を負方向に与える。
    double delta = (sheetH - kTopOverlay) / 2.0; // 余分な加算なし
    if (delta < 0) delta = 0;
    final visibleH = (H - sheetH).clamp(0.0, H);
    final maxDelta = visibleH * 0.50; // 安全上限（可視の半分）
    if (delta > maxDelta) delta = maxDelta;
    return -delta; // 上方向スクロール（マーカーを下げる）
  }

  Future<void> _loadFavorites() async {
    try {
      final ids = await SioDatabase().getFavoriteTeibouIds();
      if (mounted)
        setState(() {
          _favoriteIds = ids;
        });
    } catch (_) {}
  }

  Future<void> _loadMyCatchSpotIds() async {
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final resp = await http
          .post(
            Uri.parse('${AppConfig.instance.baseUrl}get_my_spot_list.php'),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json, text/plain, */*',
            },
            body: {'user_id': info.userId.toString()},
          )
          .timeout(kHttpTimeout);
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body);
      final rows =
          (data is Map && data['status'] == 'success' && data['rows'] is List)
              ? (data['rows'] as List)
              : (data is List ? data : const []);
      final ids = <int>{};
      int? latestSpotId;
      final ownedIds = <int>{};
      int? latestOwnedSpotId;
      for (final e in rows) {
        if (e is! Map) continue;
        final id =
            e['spot_id'] is int
                ? e['spot_id'] as int
                : int.tryParse(e['spot_id']?.toString() ?? '');
        if (id != null && id > 0) {
          ids.add(id);
          latestSpotId ??= id;
        }
      }
      try {
        final localRows = await SioDatabase().getAllTeibouWithPrefecture();
        for (final r in localRows) {
          final ownerId =
              r['user_id'] is int
                  ? r['user_id'] as int
                  : int.tryParse(r['user_id']?.toString() ?? '');
          final id =
              r['port_id'] is int
                  ? r['port_id'] as int
                  : int.tryParse(r['port_id']?.toString() ?? '');
          final flag =
              r['flag'] is int
                  ? r['flag'] as int
                  : int.tryParse(r['flag']?.toString() ?? '');
          if (ownerId == info.userId &&
              id != null &&
              id > 0 &&
              flag != -2 &&
              flag != -3) {
            ownedIds.add(id);
            latestOwnedSpotId ??= id;
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _myCatchSpotIds = ids;
        _myOwnedSpotIds = ownedIds;
        _latestMyCatchSpotId = latestSpotId;
        _latestMyOwnedSpotId = latestOwnedSpotId;
      });
      if (Common.instance.fishingDiaryMode) {
        _lastLat = null;
        _lastLng = null;
        _lastName = '';
        _prepare();
      }
    } catch (_) {}
  }

  Future<void> _ensureDiarySelectedSpotIfNeeded() async {
    if (_myDiarySpotIds.isEmpty) return;
    int? selectedId;
    try {
      final prefs = await SharedPreferences.getInstance();
      selectedId = prefs.getInt('selected_teibou_id');
    } catch (_) {}
    if (selectedId != null && _myDiarySpotIds.contains(selectedId)) return;
    final fallbackId = _latestMyCatchSpotId ?? _latestMyOwnedSpotId;
    if (fallbackId == null || fallbackId <= 0) return;
    try {
      final rows = await _visibleTeibouRows();
      Map<String, dynamic>? hit;
      for (final r in rows) {
        final rid =
            r['port_id'] is int
                ? r['port_id'] as int
                : int.tryParse(r['port_id']?.toString() ?? '');
        if (rid == fallbackId) {
          hit = r;
          break;
        }
      }
      if (hit == null) return;
      final dlat = _toDouble(hit['latitude']);
      final dlng = _toDouble(hit['longitude']);
      if (dlat == null || dlng == null) return;
      String? np;
      if (!_pointsLoading && _pointCoords.isNotEmpty) {
        np = _nearestPointName(dlat, dlng);
      }
      final prefId =
          hit['todoufuken_id'] is int
              ? hit['todoufuken_id'] as int
              : int.tryParse(hit['todoufuken_id']?.toString() ?? '') ??
                  int.tryParse(hit['pref_id_from_port']?.toString() ?? '');
      await Common.instance.saveSelectedTeibou(
        (hit['port_name'] ?? '').toString(),
        np ?? Common.instance.tidePoint,
        id: fallbackId,
        lat: dlat,
        lng: dlng,
        prefId: prefId,
      );
    } catch (_) {}
  }

  Future<_DiaryViewport?> _buildDiaryViewport() async {
    if (_myDiarySpotIds.isEmpty) return null;
    try {
      final rows = await _visibleTeibouRows();
      final points = <LatLng>[];
      for (final r in rows) {
        final int? flag =
            r['flag'] is int
                ? r['flag'] as int
                : int.tryParse(r['flag']?.toString() ?? '');
        if (flag == -2 || flag == -3) continue;
        final int? portId =
            r['port_id'] is int
                ? r['port_id'] as int
                : int.tryParse(r['port_id']?.toString() ?? '');
        if (portId == null || !_myDiarySpotIds.contains(portId)) continue;
        final dlat = _toDouble(r['latitude']);
        final dlng = _toDouble(r['longitude']);
        if (dlat == null || dlng == null) continue;
        points.add(LatLng(dlat, dlng));
      }
      if (points.isEmpty) return null;

      double minLat = points.first.latitude;
      double maxLat = points.first.latitude;
      double minLng = points.first.longitude;
      double maxLng = points.first.longitude;
      for (final p in points.skip(1)) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }

      final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
      double radiusKm = 5.0;
      for (final p in points) {
        final d = _distanceKm(
          center.latitude,
          center.longitude,
          p.latitude,
          p.longitude,
        );
        if (d > radiusKm) radiusKm = d;
      }
      return _DiaryViewport(center: center, radiusKm: radiusKm * 1.15);
    } catch (_) {
      return null;
    }
  }

  Widget _buildMyCatchBadge() {
    return Container(
      width: 16,
      height: 16,
      decoration: const BoxDecoration(
        color: Color(0xFFFFB74D),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 11),
    );
  }

  // 現在のボトムシートサイズと上部オーバーレイに応じて、
  // マーカーが可視領域の中央に来るよう中心を調整
  LatLng _computeCenteredForSheet(LatLng marker, double zoom) {
    final s = _safeSheetSize().clamp(0.0, 0.95); // 0..1 のシート占有率
    if (s <= 0.01) return marker; // 非表示なら通常通り
    final H = widget.height; // 地図ウィジェットの高さ（論理px）
    const double kTopOverlay = 60.0; // 上部メニューの高さ
    final double worldPx = 256.0 * math.pow(2.0, zoom).toDouble();

    double latToPixelY(double lat) {
      final rad = lat * math.pi / 180.0;
      final mercN = math.log(math.tan(math.pi / 4.0 + rad / 2.0));
      final normY = (1 - (mercN / math.pi)) / 2.0; // 0..1
      return normY * worldPx;
    }

    double pixelYToLat(double py) {
      final normY = (py / worldPx);
      final mercN = (1 - 2 * normY) * math.pi;
      final lat =
          (2 * math.atan(math.exp(mercN)) - math.pi / 2.0) * 180.0 / math.pi;
      return lat;
    }

    final pMarker = latToPixelY(marker.latitude);
    // 可視領域中心へ寄せるための縦方向オフセット（論理px）
    final sheetH = H * s;
    // 可視領域中央（上部オーバーレイと下部シートを考慮）へ寄せるための中心ピクセルY補正
    double delta = (sheetH - kTopOverlay) / 2.0;
    if (delta < 0) delta = 0; // 過補正しない
    final visibleH = (H - sheetH).clamp(0.0, H);
    final maxDelta = visibleH * 0.50; // 安全上限
    if (delta > maxDelta) delta = maxDelta;
    // 理論式: centerY = pMarker - (desiredScreenY - H/2)
    // desiredScreenY = topOverlay + (visibleH - topOverlay)/2
    // => centerY = pMarker + (sheetH - topOverlay)/2 (= pMarker + delta)
    final desiredCenterPy = pMarker + delta;
    final centerLat = pixelYToLat(desiredCenterPy);
    return LatLng(centerLat, marker.longitude);
  }

  Set<am.Annotation> _buildAppleAnnotations() {
    final set = <am.Annotation>{};
    int idx = 0;
    // 中心と近隣のポイントを簡易的に再構築（_markersからの復元が難しいため、中心のみ確実に追加）
    if (_center != null) {
      set.add(
        am.Annotation(
          annotationId: am.AnnotationId('c'),
          position: am.LatLng(_center!.latitude, _center!.longitude),
        ),
      );
      idx++;
    }
    // 近隣はDBから半径30kmで再取得して簡易注釈
    try {
      final rows = _visibleTeibouRows();
      rows.then((list) {
        if (!mounted || _center == null) return;
        final lat = _center!.latitude;
        final lng = _center!.longitude;
        for (final r in list) {
          final dlat = _toDouble(r['latitude']);
          final dlng = _toDouble(r['longitude']);
          if (dlat == null || dlng == null) continue;
          final d = _distanceKm(lat, lng, dlat, dlng);
          if (d <= 30 && !(dlat == lat && dlng == lng)) {
            final name = (r['port_name'] ?? '').toString();
            set.add(
              am.Annotation(
                annotationId: am.AnnotationId('n${idx++}'),
                position: am.LatLng(dlat, dlng),
              ),
            );
          }
        }
        // 再描画
        if (mounted) setState(() {});
      });
    } catch (_) {}
    return set;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

class _DiaryViewport {
  const _DiaryViewport({required this.center, required this.radiusKm});

  final LatLng center;
  final double radiusKm;
}

class _BottomSheetCatchList extends StatefulWidget {
  const _BottomSheetCatchList({Key? key, required this.extController})
    : super(key: key);
  final ScrollController extController;
  @override
  State<_BottomSheetCatchList> createState() => _BottomSheetCatchListState();
}

class _BottomSheetCatchListState extends State<_BottomSheetCatchList> {
  final List<_PostItem> _items = [];
  final ScrollController _listController = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  String _mode = 'catch'; // 'catch' or 'env'
  String _lastCommonMode = 'catch';
  bool _lastFishingDiaryMode = Common.instance.fishingDiaryMode;
  int _lastAmbiguousLevel = ambiguousLevel;
  int? _myUserId;
  int? _selectedSpotId;
  bool _isAdmin = false;
  final Map<int, String> _spotNameById = {};

  @override
  void initState() {
    super.initState();
    // 直前の選択状態を復元（起動中のみ保持）
    try {
      _mode = Common.instance.postListMode;
    } catch (_) {}
    _lastCommonMode = _mode;
    try {
      Common.instance.addListener(_onCommonModeChanged);
    } catch (_) {}
    _loadMyUserId();
    _loadFirst();
    _listController.addListener(_onScroll);
  }

  Future<void> _loadMyUserId() async {
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final prefs = await SharedPreferences.getInstance();
      final isAdmin = ((info.role ?? '').toLowerCase() == 'admin');
      var spotNames = <int, String>{};
      if (isAdmin) {
        try {
          spotNames = await _loadSpotNamesById();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _myUserId = info.userId;
        _selectedSpotId = prefs.getInt('selected_teibou_id');
        _isAdmin = isAdmin;
        _spotNameById
          ..clear()
          ..addAll(spotNames);
      });
    } catch (_) {}
  }

  Future<Map<int, String>> _loadSpotNamesById() async {
    final db = await SioDatabase().database;
    var rows = await db.query('teibou');
    if (rows.isEmpty) {
      try {
        rows = await SioDatabase().getAllTeibouWithPrefecture();
      } catch (_) {}
    }
    final spotNames = <int, String>{};
    for (final r in rows) {
      final id = int.tryParse(r['port_id']?.toString() ?? '');
      final name = (r['port_name'] ?? '').toString();
      if (id != null && name.isNotEmpty) spotNames[id] = name;
    }
    return spotNames;
  }

  String _adminPostMeta(_PostItem it) {
    if (!_isAdmin || _mode != 'catch') return '';
    final userId = it.userId?.toString() ?? '';
    final spotText =
        it.spotId != null
            ? ((_spotNameById[it.spotId!] ?? '').isNotEmpty
                ? _spotNameById[it.spotId!]!
                : it.spotId!.toString())
            : '';
    final parts = <String>[];
    if (userId.isNotEmpty) parts.add('user_id:$userId');
    if (spotText.isNotEmpty) parts.add('spot:$spotText');
    return parts.join(', ');
  }

  @override
  void dispose() {
    _listController.removeListener(_onScroll);
    _listController.dispose();
    try {
      Common.instance.removeListener(_onCommonModeChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onCommonModeChanged() {
    final cm = Common.instance.postListMode;
    final diaryEnabled = Common.instance.fishingDiaryMode;
    final ambiguousChanged = _lastAmbiguousLevel != ambiguousLevel;
    final modeChanged = cm != _lastCommonMode;
    final diaryChanged = diaryEnabled != _lastFishingDiaryMode;
    if (!modeChanged && !diaryChanged && !ambiguousChanged) return;
    _lastCommonMode = cm;
    _lastFishingDiaryMode = diaryEnabled;
    _lastAmbiguousLevel = ambiguousLevel;
    if (mounted) {
      setState(() {
        _mode = cm;
        _items.clear();
        _page = 1;
        _hasMore = true;
        _loading = false;
      });
      _loadFirst();
    }
  }

  void _onScroll() {
    if (!_hasMore || _loading) return;
    if (_listController.position.pixels >=
        _listController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<List<_PostItem>> _fetch({required int page, required int kind}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final spotId = prefs.getInt('selected_teibou_id');
      final catchAreaSpotIdsCsv =
          (kind == 1) ? await _buildCatchAreaSpotIdsCsv(spotId) : null;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final uri = Uri.parse(
        '${AppConfig.instance.baseUrl}get_post_list.php?ts=$ts',
      );
      final body = <String, String>{
        'get_kind': kind.toString(),
        'page': page.toString(),
        'page_size': kPostPageSize.toString(),
        'ambiguous_plevel': ambiguousLevel.toString(),
        'ts': ts.toString(),
      };
      if (spotId != null && spotId > 0) body['spot_id'] = spotId.toString();
      if (catchAreaSpotIdsCsv != null && catchAreaSpotIdsCsv.isNotEmpty) {
        body['catch_area_spot_ids'] = catchAreaSpotIdsCsv;
      }
      if (Common.instance.fishingDiaryMode) {
        final uid =
            _myUserId ??
            (await loadUserInfo() ?? await getOrInitUserInfo()).userId;
        _myUserId ??= uid;
        if (uid > 0) body['user_id'] = uid.toString();
      }
      final resp = await http
          .post(
            uri,
            body: body,
            headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
          )
          .timeout(kHttpTimeout);
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      if (data is Map && data['status'] == 'success') {
        final List rows = (data['rows'] as List?) ?? [];
        return rows
            .map((e) => _PostItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (data is List) {
        return data
            .map((e) => _PostItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadFirst() async {
    if (!mounted || _loading) return;
    setState(() {
      _loading = true;
      _page = 1;
      _hasMore = true;
    });
    final kind = (_mode == 'catch') ? 1 : 0;
    var rows = await _fetch(page: 1, kind: kind);
    rows = await _applyAmbiguityFilter(rows);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(rows);
      _hasMore = rows.length >= kPostPageSize;
      _page = 2;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    if (!mounted) return;
    setState(() => _loading = true);
    final kind = (_mode == 'catch') ? 1 : 0;
    var rows = await _fetch(page: _page, kind: kind);
    rows = await _applyAmbiguityFilter(rows);
    if (!mounted) return;
    setState(() {
      _items.addAll(_dedupePostItems(rows, existing: _items));
      _hasMore = rows.length >= kPostPageSize;
      _page += 1;
      _loading = false;
    });
  }

  Future<List<_PostItem>> _applyAmbiguityFilter(List<_PostItem> rows) async {
    if (ambiguousLevel != 0) return rows;
    try {
      final prefs = await SharedPreferences.getInstance();
      final selId = prefs.getInt('selected_teibou_id');
      if (selId == null || selId <= 0) return rows;
      return rows.where((e) => e.spotId == selId).toList();
    } catch (_) {
      return rows;
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = _items.length + (_hasMore ? 1 : 0);
    return CustomScrollView(
      controller: widget.extController,
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _PostListHeader(
            mode: _mode,
            onModeChanged: (val) {
              setState(() {
                _mode = val;
                try {
                  Common.instance.setPostListMode(val);
                } catch (_) {}
                _items.clear();
                _page = 1;
                _hasMore = true;
                _loading = false;
              });
              _loadFirst();
            },
          ),
        ),
        SliverFillRemaining(
          child: ListView.builder(
            controller: _listController,
            padding: const EdgeInsets.only(bottom: 72),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (index >= _items.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final it = _items[index];
              final thumb = it.thumbUrl ?? it.imageUrl;
              final adminMeta = _adminPostMeta(it);
              final isMineAtCurrentSpot =
                  _myUserId != null &&
                  _selectedSpotId != null &&
                  it.userId == _myUserId &&
                  it.spotId == _selectedSpotId;
              return Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color:
                              isMineAtCurrentSpot
                                  ? const Color(0xFFFFB74D)
                                  : const Color(0xFFBDBDBD),
                          width: 8,
                        ),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.only(
                        left: 12,
                        right: 16,
                      ),
                      leading:
                          (thumb != null)
                              ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  thumb,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                ),
                              )
                              : const Icon(
                                Icons.image,
                                size: 40,
                                color: Colors.black38,
                              ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              it.title?.isNotEmpty == true
                                  ? it.title!
                                  : (it.nickName ?? '投稿'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (adminMeta.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                adminMeta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          Expanded(
                            child:
                                it.detail?.isNotEmpty == true
                                    ? Text(
                                      it.detail!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                    : const SizedBox.shrink(),
                          ),
                          if ((it.createAt ?? '').isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              it.createAt!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                            ),
                          ],
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (_) => PostDetailPage(
                                  item: PostDetailItem(
                                    userId: it.userId,
                                    postId: it.postId,
                                    postKind: it.postKind,
                                    exist: it.exist,
                                    title: it.title,
                                    detail: it.detail,
                                    imageUrl: it.imageUrl ?? it.thumbUrl,
                                    nickName: it.nickName,
                                    createAt: it.createAt,
                                    spotId: it.spotId,
                                  ),
                                ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PostListHeader extends StatelessWidget {
  const _PostListHeader({
    Key? key,
    required this.mode,
    required this.onModeChanged,
  }) : super(key: key);

  final String mode;
  final ValueChanged<String> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 60,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Center(
                  child: Text(
                    '投稿一覧',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 0),
                    child: CupertinoSegmentedControl<String>(
                      groupValue: mode,
                      padding: const EdgeInsets.all(0),
                      children: const {
                        'catch': Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Text('釣果'),
                        ),
                        'env': Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Text('環境'),
                        ),
                      },
                      onValueChanged: onModeChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

List<_PostItem> _dedupePostItems(
  List<_PostItem> incoming, {
  List<_PostItem> existing = const [],
}) {
  final seen = <int>{};
  for (final item in existing) {
    final postId = item.postId;
    if (postId != null && postId > 0) {
      seen.add(postId);
    }
  }
  final unique = <_PostItem>[];
  for (final item in incoming) {
    final postId = item.postId;
    if (postId == null || postId <= 0) {
      unique.add(item);
      continue;
    }
    if (seen.add(postId)) {
      unique.add(item);
    }
  }
  return unique;
}

class _TideNavObserver extends NavigatorObserver {
  final VoidCallback onChanged;
  _TideNavObserver(this.onChanged);
  @override
  void didPush(Route route, Route? previousRoute) {
    onChanged();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    onChanged();
  }
}

class _TideHomePage extends StatelessWidget {
  const _TideHomePage({
    Key? key,
    required this.controller,
    required this.baseDate,
  }) : super(key: key);
  final PageController controller;
  final DateTime baseDate;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight; // オーバーレイ内部での有効高さ
        return PageView.builder(
          controller: controller,
          onPageChanged: (int index) async {
            final newDate = baseDate.add(Duration(days: index - 1000));
            Common.instance.tideDate = newDate;
            try {
              await Common.instance.getTide(true, newDate);
            } catch (_) {}
          },
          itemBuilder: (context, index) {
            final pageDate = baseDate.add(Duration(days: index - 1000));
            return _SlidingContent(
              key: ValueKey('tide-$pageDate'),
              tidePoint: Common.instance.tidePoint,
              teibouName: Common.instance.selectedTeibouName,
              nearestPoint: Common.instance.selectedTeibouNearestPoint,
              tideDate: pageDate,
              availableHeight: height,
            );
          },
        );
      },
    );
  }
}

class _AppleMapsPanel extends StatelessWidget {
  const _AppleMapsPanel({required this.center, required this.onOpen});
  final LatLng center;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black12,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map, size: 56, color: Colors.black45),
                const SizedBox(height: 12),
                const Text(
                  'Apple Maps を使用します',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Text(
                  '(${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)})',
                  style: const TextStyle(color: Colors.black45, fontSize: 12),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Apple Maps で開く'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// 地図上部の「潮汐」アクションから開く簡易ページ
class _TideStandalonePage extends ConsumerStatefulWidget {
  const _TideStandalonePage({Key? key}) : super(key: key);

  @override
  ConsumerState<_TideStandalonePage> createState() =>
      _TideStandalonePageState();
}

class _TideStandalonePageState extends ConsumerState<_TideStandalonePage> {
  static const int _standaloneInitialPage = 1000;
  BannerAd? _bannerAd;
  late final PageController _pageController;
  late DateTime _baseDate;
  bool _syncingDate = false;

  @override
  void initState() {
    super.initState();
    _baseDate = Common.instance.tideDate;
    _pageController = PageController(initialPage: _standaloneInitialPage);
  }

  void _loadBanner() {
    _bannerAd?.dispose();
    _bannerAd = BannerAd(
      size: AdSize.banner,
      adUnitId: 'ca-app-pub-3940256099942544/2934735716',
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
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final common = Provider.of<Common>(context);
    final premiumState = ref.watch(prem.premiumStateProvider);
    final isPremium = premiumState.isPremium;
    if (!premiumState.isLoading && !isPremium && _bannerAd == null) {
      _loadBanner();
    }
    if (!_syncingDate && common.shouldJumpPage) {
      final targetDate = common.tideDate;
      _syncingDate = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _baseDate = targetDate;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_standaloneInitialPage);
        }
        common.shouldJumpPage = false;
        _syncingDate = false;
        setState(() {});
      });
    }
    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        child:
            premiumState.isLoading
                ? Column(
                  children: [
                    Container(
                      height: kToolbarHeight,
                      width: double.infinity,
                      color: Colors.black,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            left: 4,
                            child: IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                          const Text(
                            '潮汐',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                )
                : Column(
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
                      width: double.infinity,
                      color: Colors.black,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            left: 4,
                            child: IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                          const Text(
                            '潮汐',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _TideHomePage(
                        controller: _pageController,
                        baseDate: _baseDate,
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}

// 月画像はドラッグ不可に戻す（プロフィール用トリミングのみドラッグ対応）

/// _SlidingContent は各ページの中身を表示するウィジェット
class _SlidingContent extends StatelessWidget {
  const _SlidingContent({
    super.key,
    required this.tideDate,
    required this.tidePoint,
    required this.availableHeight,
    this.teibouName,
    this.nearestPoint,
  });

  final String tidePoint;
  final DateTime tideDate;
  final double availableHeight;
  final String? teibouName;
  final String? nearestPoint;

  Future<Map<String, dynamic>> _getSelectedTeibouMeta() async {
    try {
      final name = teibouName ?? '';
      if (name.isEmpty) return {'yomi': '', 'isPort': false, 'flag': null};
      final rows = await SioDatabase().getAllTeibouWithPrefecture();
      Map<String, dynamic>? hit;
      try {
        final prefs = await SharedPreferences.getInstance();
        final sid = prefs.getInt('selected_teibou_id');
        if (sid != null && sid > 0) {
          for (final r in rows) {
            final rid =
                r['port_id'] is int
                    ? r['port_id'] as int
                    : int.tryParse(r['port_id']?.toString() ?? '');
            if (rid == sid) {
              hit = r;
              break;
            }
          }
        }
      } catch (_) {}
      hit ??= rows.cast<Map<String, dynamic>?>().firstWhere(
        (r) => ((r?['port_name'] ?? '').toString() == name),
        orElse: () => null,
      );
      if (hit != null) {
        final kubun = (hit['kubun'] ?? '').toString();
        final k = kubun.trim();
        final isPort =
            k == '1' ||
            k == '2' ||
            k == '3' ||
            k == '4' ||
            k == '特3' ||
            k == 'gyoko';
        String yomi = (hit['j_yomi'] ?? '').toString();
        if (yomi.isEmpty) yomi = (hit['furigana'] ?? '').toString();
        int? flag;
        try {
          flag =
              hit['flag'] is int
                  ? hit['flag'] as int
                  : int.tryParse(hit['flag']?.toString() ?? '');
        } catch (_) {}
        return {'yomi': yomi, 'isPort': isPort, 'flag': flag};
      }
    } catch (_) {}
    return {'yomi': '', 'isPort': false, 'flag': null};
  }

  Widget _valueBox(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 6.0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14.0, color: Colors.black),
      ),
    );
  }

  Widget _rightDate(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.date_range, size: 16),
              label: const Text('日付変更', style: TextStyle(fontSize: 13)),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder:
                        (_) => SetDatePage(showBanner: true, showHeader: true),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            child: SizedBox(
              width: double.infinity,
              child: _valueBox(Sio.instance.dispTideDate),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rightHigh() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            child: Text(
              '満潮',
              style: TextStyle(fontSize: 14, color: Colors.white),
              textAlign: TextAlign.left,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            child: Row(
              children: [
                Expanded(child: _valueBox(Sio.instance.highTideTime1)),
                const SizedBox(width: 2.0),
                Expanded(child: _valueBox(Sio.instance.highTideTime2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rightLow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            child: Text(
              '干潮',
              style: TextStyle(fontSize: 14, color: Colors.white),
              textAlign: TextAlign.left,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            child: Row(
              children: [
                Expanded(child: _valueBox(Sio.instance.lowTideTime1)),
                const SizedBox(width: 2.0),
                Expanded(child: _valueBox(Sio.instance.lowTideTime2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rightSun() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            child: Row(
              children: const [
                Expanded(
                  child: Text(
                    '日出',
                    style: TextStyle(fontSize: 14, color: Colors.white),
                    textAlign: TextAlign.left,
                  ),
                ),
                SizedBox(width: 2.0),
                Expanded(
                  child: Text(
                    '日没',
                    style: TextStyle(fontSize: 14, color: Colors.white),
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            child: Row(
              children: [
                Expanded(child: _valueBox(Sio.instance.sunRiseTime)),
                const SizedBox(width: 2.0),
                Expanded(child: _valueBox(Sio.instance.sunSetTime)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 受け取った availableHeight をそのまま使用（タブは上位で差し引き済み）
    // 上段(情報パネル)は45%、中央に5%の隙間、下段(グラフ)は45%、最下部に5%の余白
    double topHeight = availableHeight * 0.45; // 約45%
    double gapHeight = availableHeight * 0.05; // 約5%
    double graphHeight = availableHeight * 0.45; // 約45%
    double bottomGapHeight =
        availableHeight - topHeight - gapHeight - graphHeight; // 約5%
    return Column(
      children: [
        // 上部：メインコンテンツ（釣り場情報、画像、日付など）
        SizedBox(
          height: topHeight,
          child: Row(
            children: [
              // 左側：釣り場情報エリア
              Expanded(
                flex: 1,
                child: Container(
                  color: _navyBg,
                  child: Column(
                    children: [
                      // 1) 堤防名 + アイコン + 読み（1/3）
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: FutureBuilder<Map<String, dynamic>>(
                            future: _getSelectedTeibouMeta(),
                            builder: (context, snapshot) {
                              final name =
                                  (teibouName != null && teibouName!.isNotEmpty)
                                      ? teibouName!
                                      : tidePoint;
                              final meta = snapshot.data;
                              final isPort =
                                  (meta != null && meta['isPort'] == true);
                              final yomi =
                                  (meta != null && meta['yomi'] is String)
                                      ? meta['yomi'] as String
                                      : '';
                              final isPending =
                                  (meta != null &&
                                      (meta['flag'] == -1 ||
                                          meta['flag'] == '-1'));
                              final displayName =
                                  isPending ? '$name (申請中)' : name;
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isPort)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: Icon(
                                            Icons.anchor,
                                            color: Colors.blue.shade600,
                                            size: 18,
                                          ),
                                        ),
                                      Flexible(
                                        child: Text(
                                          displayName,
                                          style: const TextStyle(
                                            fontSize: 22,
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (yomi.isNotEmpty)
                                    const SizedBox(height: 4),
                                  if (yomi.isNotEmpty)
                                    Text(
                                      yomi,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.white70,
                                      ),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      // 2) 月画像（1/3）
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final iAge = Common.instance.getMitikake(
                                Common.instance.gSioInfo.age,
                                Common.instance.gSioInfo.ilum,
                              );
                              final no = iAge.toString().padLeft(2, '0');
                              final pngPath = 'assets/moon/moon_$no.png';
                              // マスク半径（CustomPainter と同値）
                              const double maskRadius = 32;
                              final Offset center = Offset(
                                constraints.maxWidth / 2,
                                constraints.maxHeight / 2,
                              );

                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  Center(
                                    child: Image.asset(
                                      pngPath,
                                      fit: BoxFit.contain,
                                      width: constraints.maxWidth,
                                      height: constraints.maxHeight,
                                    ),
                                  ),
                                  // 円形くり抜きの白マスク
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: CircularMaskPainter(
                                        radius: maskRadius,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      // 3) 潮名 + 潮汐ポイント（1/3）
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                Sio.instance.sioName,
                                style: const TextStyle(
                                  fontSize: 24,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tidePoint,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 右側：日付・潮汐情報入力エリア
              Expanded(
                flex: 1,
                child: Container(
                  color: _navyBg,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // 小さい画面（または非常に狭い高さ）の場合はスクロール可能に切替
                      // 目安: 各スロット ~56px 程度 × 4 = ~224px
                      if (constraints.maxHeight < 240) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            children: [
                              _rightDate(context),
                              _rightHigh(),
                              _rightLow(),
                              _rightSun(),
                            ],
                          ),
                        );
                      }
                      // 各(満潮/干潮/日出)は高さの 1/4.5、残りを日付に割り当て
                      final totalH = constraints.maxHeight;
                      final slotH = totalH / 4.5; // 各1枠（バランス調整）
                      final dateH = totalH - slotH * 3; // 余りを日付へ
                      return Column(
                        children: [
                          SizedBox(height: dateH, child: _rightDate(context)),
                          SizedBox(height: slotH, child: _rightHigh()),
                          SizedBox(height: slotH, child: _rightLow()),
                          SizedBox(height: slotH, child: _rightSun()),
                        ],
                      );
                    },
                  ),
                ),
              ),
              /*
                      // 日付
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                              child: Text(
                                '日付',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                                textAlign: TextAlign.left,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 6.0),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(4.0),
                                ),
                                child: Text(
                                  Sio.instance.dispTideDate,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16.0),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 満潮情報
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                              child: Text(
                                '満潮',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                                textAlign: TextAlign.left,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 6.0),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(color: Colors.grey),
                                        borderRadius: BorderRadius.circular(
                                          4.0,
                                        ),
                                      ),
                                      child: Text(
                                        Sio.instance.highTideTime1,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 16.0),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2.0),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 6.0),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(color: Colors.grey),
                                        borderRadius: BorderRadius.circular(
                                          4.0,
                                        ),
                                      ),
                                      child: Text(
                                        Sio.instance.highTideTime2,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 16.0),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 干潮情報
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                              child: Text(
                                '干潮',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                                textAlign: TextAlign.left,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 6.0),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(color: Colors.grey),
                                        borderRadius: BorderRadius.circular(
                                          4.0,
                                        ),
                                      ),
                                      child: Text(
                                        Sio.instance.lowTideTime1,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 16.0),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2.0),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 6.0),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(color: Colors.grey),
                                        borderRadius: BorderRadius.circular(
                                          4.0,
                                        ),
                                      ),
                                      child: Text(
                                        Sio.instance.lowTideTime2,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 16.0),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 日出・日没情報
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                              child: Row(
                                children: const [
                                  Expanded(
                                    child: Text(
                                      '日出',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.black,
                                      ),
                                      textAlign: TextAlign.left,
                                    ),
                                  ),
                                  SizedBox(width: 2.0),
                                  Expanded(
                                    child: Text(
                                      '日没',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.black,
                                      ),
                                      textAlign: TextAlign.left,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 6.0),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(color: Colors.grey),
                                        borderRadius: BorderRadius.circular(
                                          4.0,
                                        ),
                                      ),
                                      child: Text(
                                        Sio.instance.sunRiseTime,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 16.0),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2.0),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 6.0),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(color: Colors.grey),
                                        borderRadius: BorderRadius.circular(
                                          4.0,
                                        ),
                                      ),
                                      child: Text(
                                        Sio.instance.sunSetTime,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 16.0),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),*/
            ],
          ),
        ),
        // 上下の間に5%の隙間（背景は濃紺）
        if (gapHeight > 0) Container(height: gapHeight, color: _navyBg),
        // 下部領域：潮汐グラフエリア（45%）
        SizedBox(
          height: graphHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: DrawTide(),
                  child: SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
        if (bottomGapHeight > 0)
          Container(height: bottomGapHeight, color: _navyBg),
      ],
    );
  }
}

// (削除) 釣り場環境 > 投稿一覧 タブは不要となったため実装も削除

class CircularMaskPainter extends CustomPainter {
  final double radius;
  CircularMaskPainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // 濃紺で塗りつぶし、中心円だけ透明にする
    final bgPaint = Paint()..color = _navyBg;
    // Draw on a separate layer so BlendMode.clear creates a transparent hole
    canvas.saveLayer(rect, bgPaint);
    // Fill entire area with white
    canvas.drawRect(rect, bgPaint);
    // Clear a centered circle of given radius
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, radius, clearPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CircularMaskPainter oldDelegate) =>
      oldDelegate.radius != radius;
}

/// DrawTide は下部領域に潮汐グラフを描画する CustomPainter の例です
class DrawTide extends CustomPainter {
  static const double leftMargin = 20;
  // 元の隙間に戻す（上マージン）
  static const double topMargin = 15;
  static const double rightMargin = 5;
  static const double bottomMargin = 10;

  @override
  void paint(Canvas canvas, Size size) {
    double width = size.width;
    double height = size.height;

    // 潮高の最大値を算出
    double maxWaveTide = Common.instance.oneDaySioInfo.dayTide[0].tide;
    for (int i = 0; i < SioInfo.sample_cnt; i++) {
      if (maxWaveTide < Common.instance.oneDaySioInfo.dayTide[i].tide) {
        maxWaveTide = Common.instance.oneDaySioInfo.dayTide[i].tide;
      }
    }

    // 潮高の最小値を算出
    double minWaveTide = Common.instance.oneDaySioInfo.dayTide[0].tide;
    for (int i = 0; i < SioInfo.sample_cnt; i++) {
      if (minWaveTide > Common.instance.oneDaySioInfo.dayTide[i].tide) {
        minWaveTide = Common.instance.oneDaySioInfo.dayTide[i].tide;
      }
    }
    double rate = 50.0;

    int iMaxWave = (maxWaveTide / rate).toInt();
    double maxWave = (iMaxWave + 2) * rate;
    int iMinWave = (minWaveTide / rate).toInt();
    double minWave = (iMinWave - 1) * rate;

    // 全体の背景を濃紺で塗りつぶす
    final paint1 =
        Paint()
          ..color = _navyBg
          ..style = PaintingStyle.fill;
    final outRect = Rect.fromLTWH(0.0, 0.0, width, height);
    canvas.drawRect(outRect, paint1);

    // 潮汐グラフの描画領域（内側の白い部分）
    final paint2 =
        Paint()
          ..color = const Color.fromRGBO(0xff, 0xff, 0xff, 1.0)
          ..style = PaintingStyle.fill;
    final rectTide = Rect.fromLTWH(
      leftMargin,
      topMargin,
      width - leftMargin - rightMargin,
      height - topMargin - bottomMargin,
    );
    canvas.drawRect(rectTide, paint2);

    // 日の出前と日の入り後を灰色で表現（最寄りポイント基準）
    double sunriseTime =
        Common.instance.oneDaySioInfo.pSunRise.hh * 60.0 +
        Common.instance.oneDaySioInfo.pSunRise.mm;
    double sunriseDot =
        sunriseTime * (width - leftMargin - rightMargin) / (24.0 * 60.0);
    final paint3 =
        Paint()
          ..color = const Color.fromRGBO(0xC0, 0xC0, 0xC0, 0.5) // light gray
          ..style = PaintingStyle.fill;
    final rectLeft = Rect.fromLTWH(
      leftMargin,
      topMargin,
      sunriseDot,
      height - topMargin - bottomMargin,
    );
    canvas.drawRect(rectLeft, paint3);

    double sunsetTime =
        Common.instance.oneDaySioInfo.pSunSet.hh * 60.0 +
        Common.instance.oneDaySioInfo.pSunSet.mm;
    double sunsetDot =
        sunsetTime * (width - leftMargin - rightMargin) / (24.0 * 60.0);
    final paint4 =
        Paint()
          ..color = const Color.fromRGBO(0xC0, 0xC0, 0xC0, 0.5) // light gray
          ..style = PaintingStyle.fill;
    final rectRight = Rect.fromLTWH(
      leftMargin + sunsetDot,
      topMargin,
      width - leftMargin - rightMargin - sunsetDot,
      height - topMargin - bottomMargin,
    );
    canvas.drawRect(rectRight, paint4);

    // 赤い日出・日入ラインなし（天文計算は漁港座標で行い、灰色帯のみ最寄の基準で表示）

    // 外枠（白い領域）の黒い境界線
    final strokePaint =
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke;
    canvas.drawRect(rectTide, strokePaint);

    // 横線（潮位目盛り）を描く
    double lineCount = (maxWave - minWave) / rate;
    int iCount = lineCount.toInt();
    double dotRate = rectTide.size.height / lineCount;
    double x1 = rectTide.left;
    double x2 = rectTide.left + rectTide.width;

    for (int i = 0; i <= iCount; i++) {
      double y = rectTide.top + dotRate * i;
      double curHeight = maxWave - rate * i;
      int iCurHeight = curHeight.toInt();
      String heightStr = '$iCurHeight ';

      final strRect = Rect.fromLTWH(x1 - leftMargin, y - 2, leftMargin, 10);

      TextSpan span = const TextSpan(
        // 目盛（左側・潮位）の文字色を白に
        style: TextStyle(fontSize: 10.0, color: Colors.white),
      );
      span = TextSpan(text: heightStr, style: span.style);

      TextPainter tp = TextPainter(
        text: span,
        textAlign: TextAlign.right,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      );
      tp.layout(minWidth: 0, maxWidth: leftMargin);
      Offset textOffset = Offset(
        strRect.left + strRect.width - tp.width,
        strRect.top,
      );
      tp.paint(canvas, textOffset);

      if (i != 0 && i != iCount) {
        Paint linePaint =
            Paint()
              ..color = const Color.fromRGBO(179, 179, 179, 1.0)
              ..style = PaintingStyle.fill;
        Rect lineRect = Rect.fromLTWH(x1, y, x2 - x1, 1);
        canvas.drawRect(lineRect, linePaint);
      }
    }

    // 縦線（時間目盛り）を描く
    double dotTime = rectTide.width / 48.0;
    iCount = 48;
    double y1Pos = rectTide.top;
    double y2Pos = rectTide.top + rectTide.height;

    for (int i = 0; i <= iCount; i++) {
      double x = rectTide.left + dotTime * i;
      double curTime = i / 2.0;
      int iCurTime = curTime.toInt();
      String timeStr = iCurTime.toString().padLeft(2, '0');

      if (i % 4 == 0) {
        Rect strRect = Rect.fromLTWH(x - 15, y1Pos - topMargin, leftMargin, 10);
        TextSpan span = const TextSpan(
          // 目盛（上部・時間）の文字色を白に
          style: TextStyle(fontSize: 10.0, color: Colors.white),
        );
        span = TextSpan(text: timeStr, style: span.style);
        TextPainter tp = TextPainter(
          text: span,
          textAlign: TextAlign.right,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        );
        tp.layout(minWidth: 0, maxWidth: leftMargin);
        Offset textOffset = Offset(
          strRect.left + strRect.width - tp.width,
          strRect.top,
        );
        tp.paint(canvas, textOffset);
      }

      if (i != 0 && i != iCount) {
        Paint linePaint = Paint()..strokeWidth = 1.0;
        if (i % 2 == 0) {
          linePaint.color = Color.fromRGBO(
            (0.3 * 255).toInt(),
            (0.3 * 255).toInt(),
            (0.3 * 255).toInt(),
            1.0,
          );
        } else {
          linePaint.color = Color.fromRGBO(
            (0.7 * 255).toInt(),
            (0.7 * 255).toInt(),
            (0.7 * 255).toInt(),
            1.0,
          );
        }
        canvas.drawLine(Offset(x, y1Pos), Offset(x, y2Pos), linePaint);
      }
    }

    // 本日の潮汐がある場合、現在時刻位置に太い赤線を描画する
    DateTime now = DateTime.now();
    if (Common.instance.tideDate.year == now.year &&
        Common.instance.tideDate.month == now.month &&
        Common.instance.tideDate.day == now.day) {
      double nowMin = (now.hour * 60 + now.minute).toDouble();
      double nowX = nowMin * (width - leftMargin - rightMargin) / (24.0 * 60.0);
      Paint nowLinePaint = Paint()..strokeWidth = 2.0;
      nowLinePaint.color = const Color.fromRGBO(255, 0, 0, 1.0);
      canvas.drawLine(
        Offset(nowX + rectTide.left, y1Pos),
        Offset(nowX + rectTide.left, y2Pos),
        nowLinePaint,
      );
    }

    // 潮汐グラフの本体（漁港座標で計算済みの青線）
    drawWave(canvas, rectTide, maxWave, minWave);

    // 日出・日没の位置に、グラフ下部へ時刻(例: 06:15 / 18:43)を表示 + 目印ライン
    try {
      const double fontSize = 11.0;

      String two(int v) => v.toString().padLeft(2, '0');
      final srHraw = Common.instance.oneDaySioInfo.pSunRise.hh;
      final srMraw = Common.instance.oneDaySioInfo.pSunRise.mm;
      final ssHraw = Common.instance.oneDaySioInfo.pSunSet.hh;
      final ssMraw = Common.instance.oneDaySioInfo.pSunSet.mm;

      // timePrint と同じ丸めルールで時刻を整数化
      int roundHour(double h, double m) {
        final x = h + m / 60.0; // hours with fraction
        int hour = x.floor();
        int minute = ((x - hour) * 60).round();
        if (minute == 60) {
          hour += 1;
        }
        return hour;
      }

      int roundMinute(double h, double m) {
        final x = h + m / 60.0;
        int hour = x.floor();
        int minute = ((x - hour) * 60).round();
        if (minute == 60) {
          minute = 0;
        }
        return minute;
      }

      final int srH = roundHour(srHraw, srMraw);
      final int srM = roundMinute(srHraw, srMraw);
      final int ssH = roundHour(ssHraw, ssMraw);
      final int ssM = roundMinute(ssHraw, ssMraw);

      final double sunriseMinutes = (srH * 60 + srM).toDouble();
      final double sunsetMinutes = (ssH * 60 + ssM).toDouble();

      final double sunriseX =
          rectTide.left +
          sunriseMinutes * (width - leftMargin - rightMargin) / (24.0 * 60.0);
      final double sunsetX =
          rectTide.left +
          sunsetMinutes * (width - leftMargin - rightMargin) / (24.0 * 60.0);

      // ラベルは白背景＋影で、満潮/干潮と同様の見た目に
      final TextStyle textStyle = const TextStyle(
        fontSize: fontSize,
        color: Colors.black,
      );
      final String srText = '${two(srH)}:${two(srM)}';
      final String ssText = '${two(ssH)}:${two(ssM)}';
      final TextPainter srTp = TextPainter(
        text: TextSpan(text: srText, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final TextPainter ssTp = TextPainter(
        text: TextSpan(text: ssText, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      // x がはみ出さないようにクランプ
      double clampX(double x, double w) {
        final double minX = rectTide.left;
        final double maxX = rectTide.right - w;
        return x.clamp(minX, maxX);
      }

      // ラベル用の矩形サイズと配置（少し上に移動）
      const double rectH = 16.0;
      const double padX = 6.0;
      final double baseY = rectTide.bottom - 20.0; // 以前より少し上に配置

      // 影・背景のペイント
      final Paint shadowPaint =
          Paint()
            ..color = Colors.black.withAlpha(128)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      final Paint bgPaint = Paint()..color = Colors.white;
      final Paint tickPaint =
          Paint()
            ..color = Colors.redAccent
            ..strokeWidth = 1.2;

      // 日出ラベル
      final double srRectW = srTp.width + padX * 2;
      final double srLeft = clampX(sunriseX - srRectW / 2, srRectW);
      final Rect srRect = Rect.fromLTWH(srLeft, baseY, srRectW, rectH);
      canvas.drawRect(srRect.shift(const Offset(2, 2)), shadowPaint);
      canvas.drawRect(srRect, bgPaint);
      final Offset srTextOffset = Offset(
        srRect.left + (srRect.width - srTp.width) / 2,
        srRect.top + (rectH - srTp.height) / 2 - 1,
      );
      srTp.paint(canvas, srTextOffset);
      // 目印の縦線（下辺付近）
      canvas.drawLine(
        Offset(sunriseX, rectTide.bottom - 8),
        Offset(sunriseX, rectTide.bottom),
        tickPaint,
      );

      // 日没ラベル
      final double ssRectW = ssTp.width + padX * 2;
      final double ssLeft = clampX(sunsetX - ssRectW / 2, ssRectW);
      final Rect ssRect = Rect.fromLTWH(ssLeft, baseY, ssRectW, rectH);
      canvas.drawRect(ssRect.shift(const Offset(2, 2)), shadowPaint);
      canvas.drawRect(ssRect, bgPaint);
      final Offset ssTextOffset = Offset(
        ssRect.left + (ssRect.width - ssTp.width) / 2,
        ssRect.top + (rectH - ssTp.height) / 2 - 1,
      );
      ssTp.paint(canvas, ssTextOffset);
      canvas.drawLine(
        Offset(sunsetX, rectTide.bottom - 8),
        Offset(sunsetX, rectTide.bottom),
        tickPaint,
      );
    } catch (_) {}

    // グラフ上部に当日付(曜日)を表示（12時の位置＝グラフ中央にセンタリング）
    try {
      final d = Common.instance.tideDate;
      String two(int v) => v.toString().padLeft(2, '0');
      const wdays = ['月', '火', '水', '木', '金', '土', '日'];
      final w = wdays[(d.weekday + 6) % 7]; // DateTime: Mon=1..Sun=7
      final dateStr = '${two(d.month)}/${two(d.day)} ($w)';
      final TextPainter dtp = TextPainter(
        text: TextSpan(
          text: dateStr,
          style: TextStyle(
            fontSize: 20,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(minWidth: 0, maxWidth: rectTide.width);
      // 少し上側に余白を設けつつ、12:00（中央）にセンタリング
      final double x12 = rectTide.left + rectTide.width / 2;
      final double yTop = rectTide.top + 5; // 上部余白を半分に
      final Offset dateOffset = Offset(x12 - dtp.width / 2, yTop);
      // 半透明の白背景で視認性を確保
      final Rect bg = Rect.fromLTWH(
        dateOffset.dx - 8,
        yTop - 4,
        dtp.width + 16,
        dtp.height + 8,
      );
      final Paint bgPaint = Paint()..color = const Color(0x99FFFFFF);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bg, const Radius.circular(8)),
        bgPaint,
      );
      dtp.paint(canvas, dateOffset);
    } catch (_) {}
  }

  void drawWave(Canvas canvas, Rect rectTide, double maxWave, double minWave) {
    double x1 = rectTide.left;
    double x2 = rectTide.left + rectTide.width;
    double width = x2 - x1;
    double y1 = rectTide.top;
    double y2 = rectTide.top + rectTide.height;
    double height = y2 - y1;

    double wx1 = 24.0 * 60.0;
    double wx2 = 0;
    double wy1 = maxWave - minWave;
    double wy2 = 0;

    List<double> x = List.filled(SioInfo.sample_cnt, 0.0);
    List<double> y = List.filled(SioInfo.sample_cnt, 0.0);

    for (int i = 0; i < SioInfo.sample_cnt; i++) {
      wx2 =
          Common.instance.oneDaySioInfo.dayTide[i].hh * 60.0 +
          Common.instance.oneDaySioInfo.dayTide[i].mm;
      x[i] = wx2 * width / wx1;
      wy2 = maxWave - Common.instance.oneDaySioInfo.dayTide[i].tide;
      y[i] = y1 + wy2 * height / wy1;
    }

    Paint paint2 =
        Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.fill;

    // ピークマークは波線・塗りつぶしの後に描画する

    final paint =
        Paint()
          ..color = Colors.blue
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke;

    final path = ui.Path();
    Offset firstp = getXY(0, width, height, maxWave, minWave);
    path.moveTo(firstp.dx, firstp.dy);
    for (int i = 0; i < SioInfo.sample_cnt - 1; i++) {
      final p0 =
          i == 0
              ? getXY(i, width, height, maxWave, minWave)
              : getXY(i - 1, width, height, maxWave, minWave);
      final p1 = getXY(i, width, height, maxWave, minWave);
      final p2 = getXY(i + 1, width, height, maxWave, minWave);
      final p3 =
          (i + 2 < SioInfo.sample_cnt)
              ? getXY(i + 2, width, height, maxWave, minWave)
              : p2;

      final cp1 = p1 + (p2 - p0) / 6;
      final cp2 = p2 - (p3 - p1) / 6;

      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    // 曲線下部を半透明の水色で塗りつぶす
    final lastp = getXY(
      SioInfo.sample_cnt - 1,
      width,
      height,
      maxWave,
      minWave,
    );
    final fillPath =
        ui.Path.from(path)
          ..lineTo(lastp.dx, rectTide.bottom)
          ..lineTo(firstp.dx, rectTide.bottom)
          ..close();
    final fillPaint =
        Paint()
          ..color = const Color.fromRGBO(64, 164, 223, 0.5)
          ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // 波線（ストローク）
    canvas.drawPath(path, paint);

    // ピークマーク
    for (int i = 0; i < Common.instance.oneDaySioInfo.peakTideCnt; i++) {
      drawPeakMark(canvas, paint2, i, width, height, maxWave, minWave);
    }
  }

  // 代替の赤線描画・補助関数は不要（漁港座標の計算結果を青線に統一）

  Offset getXY(
    int idx,
    double dwidth,
    double dHeight,
    double dMaxWave,
    double dMinWave,
  ) {
    double xx =
        Common.instance.oneDaySioInfo.dayTide[idx].hh * 60 +
        Common.instance.oneDaySioInfo.dayTide[idx].mm;
    double x = (dwidth) * xx / (24.0 * 60.0) + leftMargin;
    double wheight = dMaxWave - dMinWave;
    double yy = Common.instance.oneDaySioInfo.dayTide[idx].tide - dMinWave;
    double yyy = dHeight * yy / wheight;
    double y = topMargin + dHeight - yyy;
    return Offset(x, y);
  }

  void drawPeakMark(
    Canvas canvas,
    Paint paint,
    int idx,
    double dwidth,
    double dHeight,
    double dMaxWave,
    double dMinWave,
  ) {
    SioPoint sp = Common.instance.oneDaySioInfo.peakTide[idx];
    double xx = sp.hh * 60 + sp.mm;
    double x = (dwidth) * xx / (24.0 * 60.0) + leftMargin;
    double wheight = dMaxWave - dMinWave;
    double yy = sp.tide - dMinWave;
    double yyy = dHeight * yy / wheight;
    double y = topMargin + dHeight - yyy;
    Offset point = Offset(x, y);
    canvas.drawCircle(point, 4, paint);

    if (sp.flag == 1) {
      y = y - 24.0;
    } else {
      y = y + 10.0;
    }
    x = x - 20.0;
    if (x < leftMargin + 10) {
      x = leftMargin + 10;
    }
    if (x > (dwidth - 30)) {
      x = x - 30.0;
    }
    Rect strRect = Rect.fromLTWH(x, y, 50, 15);
    String siotime =
        '${sp.hh.toInt().toString().padLeft(2, '0')}:${sp.mm.toInt().toString().padLeft(2, '0')}';
    final shadowPaint =
        Paint()
          ..color = Colors.black.withAlpha(128)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawRect(strRect.shift(const Offset(2, 2)), shadowPaint);
    final textBackPaint = Paint()..color = Colors.white;
    canvas.drawRect(strRect, textBackPaint);
    TextSpan span = TextSpan(
      text: siotime,
      style: const TextStyle(fontSize: 12.0, color: Colors.black),
    );
    TextPainter tp = TextPainter(
      text: span,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    tp.layout(minWidth: 0, maxWidth: dwidth);
    Offset textOffset = Offset(x + leftMargin - 14, strRect.top + 1.0);
    tp.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
