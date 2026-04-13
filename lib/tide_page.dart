import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'appconfig.dart';
import 'constants.dart';
import 'post_detail_page.dart';
import 'input_post_page.dart';
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
import 'dart:io' show Platform;
import 'constants.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:geolocator/geolocator.dart';
import 'spot_apply_form_page.dart';
import 'package:flutter/cupertino.dart' show CupertinoSegmentedControl;

// 紺（潮汐画面の背景色）
const Color _navyBg = Color(0xFF001F3F);

class TidePage extends StatefulWidget {
  const TidePage({Key? key}) : super(key: key);

  @override
  State<TidePage> createState() => TidePageState();
}

class TidePageState extends State<TidePage> {
  // PageView 用のコントローラー。初期ページは 1000 とする（十分大きい数）
  late final PageController _pageController;
  // 基準となる日付（最初に読み込んだ tideDate を保持）
  late DateTime _baseDate;
  static const int initialPage = 1000;
  int _catchRefreshTick = 0;
  int _envRefreshTick = 0;
  final GlobalKey<_FishingInfoPaneState> _fishingPaneKey = GlobalKey<_FishingInfoPaneState>();

  //static bool cacheMoon = false;

  // 60秒ごとに画面更新するタイマー
  late Timer _timer;

  // 月画像ドラッグ状態はローカル共有変数を使用（_SlidingContent内で利用）

  @override
  void initState() {
    super.initState();
    // 基準日付を設定。通常、Common.instance.tideDate に初期値が入っている前提
    _baseDate = Common.instance.tideDate;
    _pageController = PageController(initialPage: initialPage);

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
    //print('TidePage> Provider');
    if (common.shouldJumpPage) {
      /*print(
        'TidePage> Provider=${common.tideDate.year}/${common.tideDate.month}/${common.tideDate.day}',
      );*/
      _baseDate = common.tideDate;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(initialPage);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_pageController.hasClients) {
            _pageController.jumpToPage(initialPage);
          }
        });
      }

      await _initData2(_baseDate);
      common.shouldJumpPage = false;
    }
  }


  Future<void> _initData() async {
    // 初回の潮汐データ取得（_baseDate を使う）
    await Common.instance.getTide(true, _baseDate);
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
    setState(() { _catchRefreshTick++; });
  }

  // 外部から投稿一覧シート全体の再読み込みを要求
  void forceReloadPostList() {
    try { _fishingPaneKey.currentState?.reloadPostList(); } catch (_) {}
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final common = Provider.of<Common>(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final totalHeight = constraints.maxHeight;
          const double tabBarHeight = kTextTabBarHeight; // 48
          final double contentHeight = (totalHeight - tabBarHeight).clamp(0, totalHeight);

          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                // タブバー（白背景、左にアイコン+テキスト）
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {},
                  onHorizontalDragUpdate: (_) {},
                  onHorizontalDragEnd: (_) {},
                  child: Container(
                    color: Colors.white,
                    child: const TabBar(
                      indicatorColor: Colors.black,
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.black54,
                      tabs: [
                        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.map), SizedBox(width: 6), Text('地図')])),
                        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.waves), SizedBox(width: 6), Text('潮汐')])),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      // 地図（全面表示）
                      _FishingInfoPane(key: _fishingPaneKey, height: contentHeight),
                      // 潮汐（スワイプ可能）
                      _TideTab(height: contentHeight),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TideTab extends StatefulWidget {
  const _TideTab({Key? key, required this.height}) : super(key: key);
  final double height;
  @override
  State<_TideTab> createState() => _TideTabState();
}

class _TideTabState extends State<_TideTab> {
  late final PageController _controller;
  late DateTime _baseDate;
  @override
  void initState() {
    super.initState();
    _baseDate = Common.instance.tideDate;
    _controller = PageController(initialPage: 1000);
  }
  @override
  Widget build(BuildContext context) {
    // 日付変更画面などからの外部更新（shouldJumpPage）にのみ反応して基準日付を更新
    final shouldJump = Provider.of<Common>(context).shouldJumpPage;
    if (shouldJump) {
      final cur = Common.instance.tideDate;
      if (cur.year != _baseDate.year || cur.month != _baseDate.month || cur.day != _baseDate.day) {
        _baseDate = cur;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_controller.hasClients) {
            _controller.jumpToPage(1000);
          }
        });
      }
    }
    return _TideHomePage(controller: _controller, baseDate: _baseDate);
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
          child: const ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  ambiguous_plevel != 0 ? 'この釣り場近辺の釣果です。' : 'この釣り場の釣果です。',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
            ),
          ),
        ),
        // スクロール対象
        Expanded(child: _CatchPostList(key: ValueKey('catch-$refreshTick'), refreshTick: refreshTick)),
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
      final ts = DateTime.now().millisecondsSinceEpoch;
      final uri = Uri.parse('${AppConfig.instance.baseUrl}get_post_list.php?ts=$ts');
      final body = <String, String>{
        'get_kind': kind.toString(),
        'page': page.toString(),
        'page_size': kPostPageSize.toString(),
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
        return rows.map((e) => _PostItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      if (data is List) {
        return data.map((e) => _PostItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadFirst() async {
    if (!mounted || _loading) return;
    setState(() { _loading = true; _page = 1; _hasMore = true; });
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
      _items.addAll(rows);
      _hasMore = rows.length >= kPostPageSize;
      _page += 1;
      _loading = false;
    });
  }

  // ambiguous_plevel=0 のときは、選択中の釣り場IDに一致する投稿のみを表示
  Future<List<_PostItem>> _applyAmbiguityFilter(List<_PostItem> rows) async {
    if (ambiguous_plevel != 0) return rows;
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
        try { map = jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
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
        try { map = jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
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
            return InkWell(
              onTap: () async {
                final String? detailRaw = it.imageUrl ?? it.thumbUrl;
                final String? detailUrl = (detailRaw != null) ? _withTs(detailRaw, it.postId) : null;
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostDetailPage(
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
                  setState(() { _imgTsByPost[it.postId!] = ts; });
                  await _saveImageTs(it.postId!, ts);
                } else if (res is Map) {
                  final updated = (res['updated'] == true);
                  final cleared = (res['clearedImage'] == true);
                  final pid = res['postId'] is int ? res['postId'] as int : (res['postId'] is String ? int.tryParse(res['postId']) : null);
                  if (updated && cleared && pid != null) {
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
                      setState(() { _items[idx] = updatedItem; });
                    }
                    // キャッシュバスターも削除
                    setState(() { _imgTsByPost.remove(pid); });
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
                        setState(() { _items[idx] = updatedItem; });
                      }
                    }
                    setState(() { _imgTsByPost[pid] = ts; });
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
                        child: (imgUrl != null)
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
                          (it.nickName ?? '').isNotEmpty ? it.nickName! : '',
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(it.createAt) ?? '',
                          style: const TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ],
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
  const _EnvPostList({super.key, required this.filterKind, required this.refreshTick});
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
    if (oldWidget.filterKind != widget.filterKind || oldWidget.refreshTick != widget.refreshTick) {
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
    int no = 0;  // なし
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
                        Container(width: w, height: 16, color: Colors.grey.shade300),
                        // あり（左）
                        Positioned(left: 0, top: 0, bottom: 0, child: Container(width: yesW, color: yesColor)),
                        // なし（右）
                        Positioned(left: yesW, top: 0, bottom: 0, child: Container(width: noW, color: noColor)),
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
                      child: Text('あり ${yes}件', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text('なし ${no}件', style: const TextStyle(fontSize: 13, color: Colors.black87)),
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
      final uri = Uri.parse('${AppConfig.instance.baseUrl}get_post_list.php?ts=$ts');
      final body = <String, String>{
        'get_kind': kind.toString(),
        'page': page.toString(),
        'page_size': kPostPageSize.toString(),
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
        return rows.map((e) => _PostItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      if (data is List) {
        return data.map((e) => _PostItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadFirst() async {
    if (!mounted || _loading) return;
    setState(() { _loading = true; _page = 1; _hasMore = true; });
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
      _items.addAll(rows);
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
        try { map = jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
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
        try { map = jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
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
                      final String? detailUrl = (detailRaw != null) ? _withTs(detailRaw, it.postId) : null;
                      final res = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PostDetailPage(
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
                        setState(() { _imgTsByPost[it.postId!] = ts; });
                        await _saveImageTs(it.postId!, ts);
                      } else if (res is Map) {
                        final updated = (res['updated'] == true);
                        final cleared = (res['clearedImage'] == true);
                        final pid = res['postId'] is int ? res['postId'] as int : (res['postId'] is String ? int.tryParse(res['postId']) : null);
                        if (updated && cleared && pid != null) {
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
                            setState(() { _items[idx] = updatedItem; });
                          }
                          setState(() { _imgTsByPost.remove(pid); });
                          await _removeImageTs(pid);
                        } else if (updated && pid != null) {
                          final ts = DateTime.now().millisecondsSinceEpoch.toString();
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
                              setState(() { _items[idx] = updatedItem; });
                            }
                          }
                          setState(() { _imgTsByPost[pid] = ts; });
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: thumbW,
                            height: thumbW,
                        child: (imgUrl != null)
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
                              (it.nickName ?? '').isNotEmpty ? it.nickName! : '',
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDate(it.createAt) ?? '',
                              style: const TextStyle(fontSize: 11, color: Colors.black54),
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
                child: Text('規制、駐車場、トイレなどの状況などです',
                    style: TextStyle(fontSize: 13, color: Colors.black87)),
              ),
            ),
          ),
        ),
        Expanded(child: _EnvPostList(key: ValueKey('env-$refreshTick'), filterKind: 0, refreshTick: refreshTick)),
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
  // 潮汐オーバーレイ表示とスワイプ用
  bool _showTideOverlay = false;
  late PageController _tidePageController;
  DateTime _tideBaseDate = Common.instance.tideDate;
  final GlobalKey<NavigatorState> _tideNavKey = GlobalKey<NavigatorState>();
  late final _TideNavObserver _tideNavObserver;
  gm.GoogleMapController? _gmController;
  // 長押しによる「釣り場登録」用ポイント
  LatLng? _applyPoint;           // FlutterMap 用
  gm.LatLng? _gmApplyPoint;      // GoogleMap 用
  bool _applyMode = false;       // 「釣り場申請」ボタン押下後の指定モード
  bool _isSatellite = false; // Google Maps 用 衛星表示トグル

  void reloadPostList() {
    if (mounted) setState(() { _sheetReloadTick++; });
  }

  void _showModeInfoDialog() {
    final isApply = _applyMode;
    final String msg = isApply
        ? '地図上で登録したい場所を長押ししてください。\nピンが表示されたら「釣り場登録」をタップしてください。\n申請中のピンを申請者本人がタップすると入力項目の修正ができます。\n\n「釣り場登録中...」ボタンをタップすると「閲覧モード」に遷移します。'
        : '地図上の釣り場をタップして選びながら、釣果や環境の投稿を閲覧するモードです。\n\n長押しするとその近辺の釣り場がピン表示されます。\n\n「釣り場登録」ボタンをタップすると釣り場を登録する「釣り場登録モード」に遷移します。';
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        content: Text(msg),
      ),
    );
  }

  Future<String> _currentSpotDisplay() async {
    final spotName = Common.instance.selectedTeibouName.isNotEmpty
        ? Common.instance.selectedTeibouName
        : Common.instance.tidePoint;
    String display = spotName;
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
        (r) => ((r?['port_name'] ?? '').toString() == spotName),
        orElse: () => null,
      );
      final int? flag = row == null
          ? null
          : (row['flag'] is int ? row['flag'] as int : int.tryParse(row['flag']?.toString() ?? ''));
      if (flag == -1) display = '$spotName (申請中)';
    } catch (_) {}
    return display;
  }

  Future<void> _onViewLongPress(double llat, double llng) async {
    try {
      final rows = await SioDatabase().getAllTeibouWithPrefecture();
      double best = double.infinity;
      Map<String, dynamic>? bestRow;
      const double d2r = 3.141592653589793 / 180.0;
      final rlat = llat * d2r;
      for (final r in rows) {
        final int? flag = r['flag'] is int ? r['flag'] as int : int.tryParse(r['flag']?.toString() ?? '');
        if (flag == -2) continue; // 非承認は除外
        final dlat = _toDouble(r['latitude']);
        final dlng = _toDouble(r['longitude']);
        if (dlat == null || dlng == null) continue;
        final d = _haversine(llat, llng, dlat, dlng, cosLat: rlat);
        if (d < best) { best = d; bestRow = r; }
      }
      if (bestRow == null) return;
      final nlat = _toDouble(bestRow['latitude']) ?? llat;
      final nlng = _toDouble(bestRow['longitude']) ?? llng;
      final name = (bestRow['port_name'] ?? '').toString();
      // 選択状態は更新（最寄りを選択）し、地図の表示位置・スケールは変更せず近辺ピンのみ再構成
      try {
        String? np;
        if (!_pointsLoading && _pointCoords.isNotEmpty) { np = _nearestPointName(nlat, nlng); }
        final int? prefId = bestRow['todoufuken_id'] is int
            ? bestRow['todoufuken_id'] as int
            : int.tryParse(bestRow['todoufuken_id']?.toString() ?? '') ?? int.tryParse(bestRow['pref_id_from_port']?.toString() ?? '');
        final int? portId = bestRow['port_id'] is int ? bestRow['port_id'] as int : int.tryParse(bestRow['port_id']?.toString() ?? '');
        await Common.instance.saveSelectedTeibou(name, np ?? (Common.instance.tidePoint), id: portId, lat: nlat, lng: nlng, prefId: prefId);
      } catch (_) {}
      // 地図の表示位置は変更せず、ピンのみ再構成（最寄りを赤ピン）
      await _loadMarkers(centerName: name, lat: nlat, lng: nlng, radiusKm: 30.0);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _sheetController = DraggableScrollableController();
    _tidePageController = PageController(initialPage: 1000);
    _tideNavObserver = _TideNavObserver(() { if (mounted) setState(() {}); });
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
  }

  void _onCommonChanged() {
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
    if (mounted) setState(() { _sheetReloadTick++; });
  }

  Future<void> _prepare() async {
    final name = Common.instance.selectedTeibouName;
    final lat = Common.instance.selectedTeibouLat;
    final lng = Common.instance.selectedTeibouLng;
    double useLat = lat;
    double useLng = lng;
    String useName = name;
    // 追加フォールバック: 緯度経度が未保存だが名前やIDが保存されている場合、DBから取得して補完
    if ((useLat == 0.0 && useLng == 0.0) && useName.isNotEmpty) {
      try {
        final rows = await SioDatabase().getAllTeibouWithPrefecture();
        Map<String, dynamic>? hit;
        try {
          final prefs = await SharedPreferences.getInstance();
          final sid = prefs.getInt('selected_teibou_id');
          if (sid != null && sid > 0) {
            for (final r in rows) {
              final rid = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
              if (rid == sid) { hit = r; break; }
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
                id: hit['port_id'] is int ? hit['port_id'] as int : int.tryParse(hit['port_id']?.toString() ?? ''),
                prefId: hit['todoufuken_id'] is int
                    ? hit['todoufuken_id'] as int
                    : int.tryParse(hit['todoufuken_id']?.toString() ?? '') ?? int.tryParse(hit['pref_id_from_port']?.toString() ?? ''),
              );
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    if (useLat != 0.0 || useLng != 0.0) {
      // 変更検知（緯度経度 or 名前）
      if (_lastLat != useLat || _lastLng != useLng || _lastName != useName) {
        _center = LatLng(useLat, useLng);
        _lastLat = useLat;
        _lastLng = useLng;
        _lastName = useName;
        await _loadMarkers(centerName: useName, lat: useLat, lng: useLng, radiusKm: 30.0);
        // マップの中心も即時移動（シートの占有に合わせて上寄せ）
        if (mounted && _center != null) {
          final z = _zoomForRadius(30.0) + 1.0;
          final adjusted = _computeCenteredForSheet(_center!, z);
          setState(() { _center = adjusted; });
          try { _mapController.move(adjusted, z); } catch (_) {}
          try { if (baseMap == 2) { _gmController?.moveCamera(gm.CameraUpdate.newLatLngZoom(gm.LatLng(adjusted.latitude, adjusted.longitude), z)); } } catch (_) {}
        }
      }
    } else {
      // フォールバック: 現在の潮汐ポイントの緯度経度があればそれを使用
      final fallbackLat = Common.instance.gSioInfo.lat;
      final fallbackLng = Common.instance.gSioInfo.lang;
      final fallbackName = Common.instance.gSioInfo.portName.isNotEmpty
          ? Common.instance.gSioInfo.portName
          : (Common.instance.selectedTeibouName.isNotEmpty
              ? Common.instance.selectedTeibouName
              : '');
      if ((fallbackLat != 0.0 || fallbackLng != 0.0)) {
        if (_lastLat != fallbackLat || _lastLng != fallbackLng || _lastName != fallbackName) {
          _center = LatLng(fallbackLat, fallbackLng);
          _lastLat = fallbackLat;
          _lastLng = fallbackLng;
          _lastName = fallbackName;
          await _loadMarkers(centerName: fallbackName, lat: fallbackLat, lng: fallbackLng, radiusKm: 30.0);
          if (mounted && _center != null) {
            final z = _zoomForRadius(30.0) + 1.0;
            final adjusted = _computeCenteredForSheet(_center!, z);
            setState(() { _center = adjusted; });
            try { _mapController.move(adjusted, z); } catch (_) {}
            try { if (baseMap == 2) { _gmController?.moveCamera(gm.CameraUpdate.newLatLngZoom(gm.LatLng(adjusted.latitude, adjusted.longitude), z)); } } catch (_) {}
          }
        }
      } else {
        // どちらも未設定ならプレースホルダ
        _center = null;
        setState(() {});
      }
    }
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

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() => _myPos = LatLng(pos.latitude, pos.longitude));

      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
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

  Future<void> _loadMarkers({required String centerName, required double lat, required double lng, required double radiusKm}) async {
    _markers.clear();
    _appleAnnotations.clear();
    _gmMarkers.clear();
    _gmPolylines.clear();
    _gmCircles.clear();
    final rows = await SioDatabase().getAllTeibouWithPrefecture();
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
          final rid = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
          if (rid == sid) { centerRow = r; break; }
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
        if ((dlat0 - lat).abs() < eps && (dlng0 - lng).abs() < eps) { centerRow = r; break; }
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
        if (d < best) { best = d; bestRow = r; }
      }
      centerRow = bestRow;
    }
    if (centerRow != null) {
      centerPortId = centerRow['port_id'] is int ? centerRow['port_id'] as int : int.tryParse(centerRow['port_id']?.toString() ?? '');
      final int? flag = centerRow['flag'] is int ? centerRow['flag'] as int : int.tryParse(centerRow['flag']?.toString() ?? '');
      centerPending = (flag == -1);
      centerRejected = (flag == -2);
      final dlat1 = _toDouble(centerRow['latitude']);
      final dlng1 = _toDouble(centerRow['longitude']);
      if (dlat1 != null && dlng1 != null) {
        center = LatLng(dlat1, dlng1);
      }
      cn = (centerRow['port_name'] ?? cn).toString();
    }
    // フォールバック: 厳密一致で見つからなかった場合、選択IDや名前から再判定
    if (!centerPending && !centerRejected) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final sid = prefs.getInt('selected_teibou_id');
        Map<String, dynamic>? rr;
        if (sid != null && sid > 0) {
          for (final r in rows) {
            final rid = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
            if (rid == sid) { rr = r; break; }
          }
        }
        rr ??= rows.cast<Map<String, dynamic>?>().firstWhere(
          (r) => (r?['port_name'] ?? '').toString() == centerName,
          orElse: () => null,
        );
        if (rr != null) {
          final int? f = rr['flag'] is int ? rr['flag'] as int : int.tryParse(rr['flag']?.toString() ?? '');
          centerPending = (f == -1);
          centerRejected = (f == -2);
          centerPortId ??= rr['port_id'] is int ? rr['port_id'] as int : int.tryParse(rr['port_id']?.toString() ?? '');
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
        final int? flag = r['flag'] is int ? r['flag'] as int : int.tryParse(r['flag']?.toString() ?? '');
        if (flag == -2) continue;
        final dlat0 = _toDouble(r['latitude']);
        final dlng0 = _toDouble(r['longitude']);
        if (dlat0 == null || dlng0 == null) continue;
        final a = _haversine(lat, lng, dlat0, dlng0, cosLat: rlat);
        if (a < best) { best = a; bestRow = r; }
      }
      if (bestRow != null) {
        final nlat = _toDouble(bestRow['latitude']) ?? lat;
        final nlng = _toDouble(bestRow['longitude']) ?? lng;
        cn = (bestRow['port_name'] ?? '').toString();
        center = LatLng(nlat, nlng);
        centerPortId = bestRow['port_id'] is int ? bestRow['port_id'] as int : int.tryParse(bestRow['port_id']?.toString() ?? '');
        final int? f2 = bestRow['flag'] is int ? bestRow['flag'] as int : int.tryParse(bestRow['flag']?.toString() ?? '');
        centerPending = (f2 == -1);
        centerRejected = false;
        try {
          String? np;
          if (!_pointsLoading && _pointCoords.isNotEmpty) { np = _nearestPointName(nlat, nlng); }
          final int? prefId = bestRow['todoufuken_id'] is int
              ? bestRow['todoufuken_id'] as int
              : int.tryParse(bestRow['todoufuken_id']?.toString() ?? '') ?? int.tryParse(bestRow['pref_id_from_port']?.toString() ?? '');
          await Common.instance.saveSelectedTeibou(cn, np ?? (Common.instance.tidePoint), id: centerPortId, lat: nlat, lng: nlng, prefId: prefId);
          Common.instance.shouldJumpPage = true;
          Common.instance.notify();
        } catch (_) {}
      }
    }
    final bool isCenterFav = centerPortId != null && _favoriteIds.contains(centerPortId);
    // AppleMap 中心注釈
    if (!centerRejected) {
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
      final int? flag = r['flag'] is int ? r['flag'] as int : int.tryParse(r['flag']?.toString() ?? '');
      final bool isPending = flag == -1;
      // 非承認は非表示
      if (flag == -2) {
        continue;
      }
      final displayName = isPending ? '$name (申請中)' : name;
      final int? prefId = r['todoufuken_id'] is int
          ? r['todoufuken_id'] as int
          : int.tryParse(r['todoufuken_id']?.toString() ?? '') ?? int.tryParse(r['pref_id_from_port']?.toString() ?? '');
      final int? portId = r['port_id'] is int
          ? r['port_id'] as int
          : int.tryParse(r['port_id']?.toString() ?? '');
      if (dlat == null || dlng == null) continue;
      final d = _distanceKm(lat, lng, dlat, dlng);
      if (d <= radiusKm && !(dlat == lat && dlng == lng)) {
        if (d > maxDkm) maxDkm = d;
        final bool isFav = portId != null && _favoriteIds.contains(portId);
        _markers.add(
          fm.Marker(
            width: 220,
            height: isFav ? 76 : 60,
            point: LatLng(dlat, dlng),
            child: GestureDetector(
              onTap: () async {
                // 申請中ピンを編集（申請者本人 or 管理者）
                if (_applyMode && isPending) {
                  try {
                    final info = await loadUserInfo() ?? await getOrInitUserInfo();
                    final bool isAdmin = ((info.role ?? '').toLowerCase() == 'admin');
                    final int? owner = r['user_id'] is int ? r['user_id'] as int : int.tryParse(r['user_id']?.toString() ?? '');
                    if (isAdmin || (owner != null && owner == info.userId)) {
                      final prefName = (r['todoufuken_name'] ?? '').toString();
                      if (!mounted) return;
                      final res = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SpotApplyFormPage(
                            lat: dlat,
                            lng: dlng,
                            editMode: true,
                            initialKind: (r['kubun'] ?? '').toString(),
                            initialName: name,
                            initialYomi: (r['j_yomi'] ?? r['furigana'] ?? '').toString(),
                            initialAddress: (r['address'] ?? '').toString(),
                            initialPrefName: prefName,
                            initialPrivate: (r['private'] is int) ? r['private'] as int : int.tryParse(r['private']?.toString() ?? '0'),
                            initialPortId: portId,
                            canModerate: isAdmin,
                          ),
                        ),
                      );
                      if (res == true && mounted) {
                        setState(() {
                          _applyMode = false;
                          _applyPoint = null;
                          _gmApplyPoint = null;
                          try { _gmMarkers.removeWhere((m) => m.markerId.value == 'apply'); } catch (_) {}
                        });
                      }
                      return;
                    }
                  } catch (_) {}
                }
                // 近隣ポイントへ選択切替（一覧と同じ挙動）
                String? np;
                if (!_pointsLoading && _pointCoords.isNotEmpty) {
                  np = _nearestPointName(dlat, dlng);
                }
                if (np != null) {
                  Common.instance.tidePoint = np;
                  await Common.instance.savePoint(np);
                }
                await Common.instance.saveSelectedTeibou(
                  name,
                  np ?? (Common.instance.tidePoint),
                  id: portId,
                  lat: dlat,
                  lng: dlng,
                  prefId: prefId,
                );
                Common.instance.shouldJumpPage = true;
                Common.instance.notify();
                // カメラ移動は _onCommonChanged からの _prepare() に委ねる（重複移動を避ける）
                // マーカーを再構築
                await _loadMarkers(centerName: name, lat: dlat, lng: dlng, radiusKm: radiusKm);
                // 投稿一覧リロード。シートが非表示なら再表示、表示中はサイズ維持
                if (mounted) setState(() { _sheetReloadTick++; });
                if (_safeSheetSize() <= 0.01) {
                  _recreateSheet(show: true);
                } else {
                  _ensureSheetVisible(ifHiddenOnly: true);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ラベル上、ピン下
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1))],
                    ),
                    child: Text(
                      displayName,
                      style: TextStyle(fontSize: 10, color: Colors.black, fontWeight: isFav ? FontWeight.bold : FontWeight.normal),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  Icon(
                    Icons.location_pin,
                    color: (flag != null && flag != 0) ? Colors.green : Colors.blueAccent,
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
                    case 1:
                      return 'ユーザ登録承認ずみ';
                    default:
                      return '';
                  }
                }
                String _shortAddress(String s) {
                  final t = s.trim();
                  if (t.isEmpty) return t;
                  final parts = t.split(RegExp(r'\s+'));
                  return parts.length >= 2 ? '${parts[0]} ${parts[1]}' : parts[0];
                }
                final addr = _shortAddress((r['address'] ?? '').toString());
                final st = _flagText(flag);
                final latlng = '緯度: ${dlat.toStringAsFixed(5)}, 経度: ${dlng.toStringAsFixed(5)}';
                final addrLine = '住所: ' + (addr.isNotEmpty ? addr : '不明');
                final stLine = '状態: ' + (st.isNotEmpty ? st : '不明');
                return '$latlng\n$addrLine\n$stLine';
              }(),
            ),
            icon: (flag != null && flag != 0)
                ? gm.BitmapDescriptor.defaultMarkerWithHue(gm.BitmapDescriptor.hueGreen)
                : gm.BitmapDescriptor.defaultMarker,
            onTap: () async {
              if (_applyMode && isPending) {
                try {
                  final info = await loadUserInfo() ?? await getOrInitUserInfo();
                  final bool isAdmin = ((info.role ?? '').toLowerCase() == 'admin');
                  final int? owner = r['user_id'] is int ? r['user_id'] as int : int.tryParse(r['user_id']?.toString() ?? '');
                  if (isAdmin || (owner != null && owner == info.userId)) {
                    final prefName = (r['todoufuken_name'] ?? '').toString();
                    if (!mounted) return;
                    final res = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SpotApplyFormPage(
                          lat: dlat,
                          lng: dlng,
                          editMode: true,
                          initialKind: (r['kubun'] ?? '').toString(),
                          initialName: name,
                          initialYomi: (r['j_yomi'] ?? r['furigana'] ?? '').toString(),
                          initialAddress: (r['address'] ?? '').toString(),
                          initialPrefName: prefName,
                          initialPrivate: (r['private'] is int) ? r['private'] as int : int.tryParse(r['private']?.toString() ?? '0'),
                          initialPortId: portId,
                          canModerate: isAdmin,
                        ),
                      ),
                    );
                    if (res == true && mounted) {
                      setState(() {
                        _applyMode = false;
                        _applyPoint = null;
                        _gmApplyPoint = null;
                        try { _gmMarkers.removeWhere((m) => m.markerId.value == 'apply'); } catch (_) {}
                      });
                      try { await _loadMarkers(centerName: name, lat: dlat, lng: dlng, radiusKm: radiusKm); } catch (_) {}
                      if (mounted) setState(() {});
                    }
                    return;
                  }
                } catch (_) {}
              }
              // 近隣ポイントへ選択切替
              String? np;
              if (!_pointsLoading && _pointCoords.isNotEmpty) {
                np = _nearestPointName(dlat, dlng);
              }
              if (np != null) {
                Common.instance.tidePoint = np;
                await Common.instance.savePoint(np);
              }
              await Common.instance.saveSelectedTeibou(
                name,
                np ?? (Common.instance.tidePoint),
                id: portId,
                lat: dlat,
                lng: dlng,
                prefId: prefId,
              );
              Common.instance.shouldJumpPage = true;
              Common.instance.notify();
              // カメラ移動は _onCommonChanged からの _prepare() に委ねる（重複移動を避ける）
              // マーカー再構築
              await _loadMarkers(centerName: name, lat: dlat, lng: dlng, radiusKm: radiusKm);
              if (mounted) setState(() { _sheetReloadTick++; });
              if (_safeSheetSize() <= 0.01) {
                _recreateSheet(show: true);
              } else {
                _ensureSheetVisible(ifHiddenOnly: true);
              }
            },
            zIndex: 0,
          ),
        );
      }
    }

    // 中心マーカーを最後に追加（最前面に表示）
    if (!centerRejected) _markers.add(
      fm.Marker(
        width: 200,
        height: isCenterFav ? 84 : 64,
        point: center,
        child: GestureDetector(
          onTap: () async {
            if (_applyMode && centerPending) {
              try {
                final info = await loadUserInfo() ?? await getOrInitUserInfo();
                final bool isAdmin = ((info.role ?? '').toLowerCase() == 'admin');
                // 対応する行を検索（port_id 最優先）
                Map<String, dynamic>? cr;
                if (centerPortId != null) {
                  for (final r in rows) {
                    final rid = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
                    if (rid == centerPortId) { cr = r; break; }
                  }
                }
                if (cr == null) {
                  for (final r in rows) {
                    final n = (r['port_name'] ?? '').toString();
                    final dlat0 = _toDouble(r['latitude']);
                    final dlng0 = _toDouble(r['longitude']);
                    if (dlat0 == null || dlng0 == null) continue;
                    if ((n == centerName) || ((dlat0 - lat).abs() < 1e-8 && (dlng0 - lng).abs() < 1e-8)) { cr = r; break; }
                  }
                }
                final int? owner = cr == null ? null : (cr['user_id'] is int ? cr['user_id'] as int : int.tryParse(cr['user_id']?.toString() ?? ''));
                if (isAdmin || (owner != null && owner == info.userId)) {
                  final prefName = cr == null ? '' : (cr['todoufuken_name'] ?? '').toString();
                  if (!mounted) return;
                  final res = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SpotApplyFormPage(
                        lat: center.latitude,
                        lng: center.longitude,
                        editMode: true,
                        initialKind: cr == null ? '' : (cr['kubun'] ?? '').toString(),
                        initialName: centerName,
                        initialYomi: cr == null ? '' : (cr['j_yomi'] ?? cr['furigana'] ?? '').toString(),
                        initialAddress: cr == null ? '' : (cr['address'] ?? '').toString(),
                        initialPrefName: prefName,
                        initialPrivate: cr == null ? 0 : ((cr['private'] is int) ? cr['private'] as int : int.tryParse(cr['private']?.toString() ?? '0') ?? 0),
                        initialPortId: cr == null ? null : (cr['port_id'] is int ? cr['port_id'] as int : int.tryParse(cr['port_id']?.toString() ?? '')),
                        canModerate: isAdmin,
                      ),
                    ),
                  );
                    if (res == true && mounted) {
                      setState(() {
                        _applyMode = false;
                        _applyPoint = null;
                        _gmApplyPoint = null;
                        try { _gmMarkers.removeWhere((m) => m.markerId.value == 'apply'); } catch (_) {}
                      });
                      try { await _loadMarkers(centerName: centerName, lat: center.latitude, lng: center.longitude, radiusKm: 30.0); } catch (_) {}
                      if (mounted) setState(() {});
                    }
                  return;
                }
              } catch (_) {}
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _showCurrentSpotInfoDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                  ),
                  child: Text(
                    centerPending ? '$cn (申請中)' : cn,
                    style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
              Icon(Icons.location_pin, color: Colors.red, size: isCenterFav ? 48 : 32),
            ],
          ),
        ),
      ),
    );

    // GoogleMap 中心マーカー（zIndexを高めに）
    if (!centerRejected) _gmMarkers.add(
      gm.Marker(
        markerId: const gm.MarkerId('c'),
        position: gm.LatLng(center.latitude, center.longitude),
        infoWindow: gm.InfoWindow(title: centerPending ? '$cn (申請中)' : cn, snippet: '中心'),
        onTap: () async {
          if (_applyMode && centerPending) {
            try {
              final info = await loadUserInfo() ?? await getOrInitUserInfo();
              final bool isAdmin = ((info.role ?? '').toLowerCase() == 'admin');
              // port_id 最優先で検索
              Map<String, dynamic>? cr;
              if (centerPortId != null) {
                for (final r in rows) {
                  final rid = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
                  if (rid == centerPortId) { cr = r; break; }
                }
              }
              if (cr == null) {
                for (final r in rows) {
                  final n = (r['port_name'] ?? '').toString();
                  final dlat0 = _toDouble(r['latitude']);
                  final dlng0 = _toDouble(r['longitude']);
                  if (dlat0 == null || dlng0 == null) continue;
                  if ((n == centerName) || ((dlat0 - lat).abs() < 1e-8 && (dlng0 - lng).abs() < 1e-8)) { cr = r; break; }
                }
              }
              final int? owner = cr == null ? null : (cr['user_id'] is int ? cr['user_id'] as int : int.tryParse(cr['user_id']?.toString() ?? ''));
              if (isAdmin || (owner != null && owner == info.userId)) {
                final prefName = cr == null ? '' : (cr['todoufuken_name'] ?? '').toString();
                if (!mounted) return;
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SpotApplyFormPage(
                      lat: center.latitude,
                      lng: center.longitude,
                      editMode: true,
                      initialKind: cr == null ? '' : (cr['kubun'] ?? '').toString(),
                      initialName: centerName,
                      initialYomi: cr == null ? '' : (cr['j_yomi'] ?? cr['furigana'] ?? '').toString(),
                      initialAddress: cr == null ? '' : (cr['address'] ?? '').toString(),
                      initialPrefName: prefName,
                      initialPrivate: cr == null ? 0 : ((cr['private'] is int) ? cr['private'] as int : int.tryParse(cr['private']?.toString() ?? '0') ?? 0),
                      initialPortId: cr == null ? null : (cr['port_id'] is int ? cr['port_id'] as int : int.tryParse(cr['port_id']?.toString() ?? '')),
                      canModerate: isAdmin,
                    ),
                  ),
                );
                if (res == true && mounted) {
                  setState(() {
                    _applyMode = false;
                    _applyPoint = null;
                    _gmApplyPoint = null;
                    try { _gmMarkers.removeWhere((m) => m.markerId.value == 'apply'); } catch (_) {}
                  });
                }
                return;
              }
            } catch (_) {}
          }
        },
        zIndex: 1000,
      ),
    );

    // GoogleMap: 外接円（候補範囲） - 曖昧表示のときのみ
    if (_center != null && maxDkm > 0 && ambiguous_plevel == 2) {
      _gmCircles.add(
        gm.Circle(
          circleId: const gm.CircleId('enclosing'),
          center: gm.LatLng(_center!.latitude, _center!.longitude),
          radius: maxDkm * 1000.0,
          strokeColor: Colors.redAccent.withOpacity(0.35),
          strokeWidth: 2,
          fillColor: Colors.redAccent.withOpacity(0.12),
        ),
      );
    }

    // GoogleMap: メッシュ（ambiguous_plevel == 2 のとき）
    if (ambiguous_plevel == 2) {
      _gmPolylines.clear();
      for (final pl in _buildMeshPolylines()) {
        final pts = pl.points.map((p) => gm.LatLng(p.latitude, p.longitude)).toList();
        _gmPolylines.add(gm.Polyline(
          polylineId: gm.PolylineId('mesh-${_gmPolylines.length}'),
          points: pts,
          color: Colors.black.withOpacity(0.2),
          width: 1,
        ));
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: _center == null
          ? const ColoredBox(color: Colors.black)
          : Stack(
              children: [
                if (Platform.isIOS && baseMap == 1)
                  am.AppleMap(
                    initialCameraPosition: am.CameraPosition(
                      target: am.LatLng(_center!.latitude, _center!.longitude),
                      zoom: 12,
                    ),
                    annotations: _appleAnnotations,
                  )
                else if (baseMap == 2)
                  gm.GoogleMap(
                    initialCameraPosition: gm.CameraPosition(
                      target: gm.LatLng(_center!.latitude, _center!.longitude),
                      zoom: 12,
                    ),
                    mapType: _isSatellite ? gm.MapType.hybrid : gm.MapType.normal,
                    onMapCreated: (c) => _gmController = c,
                    onLongPress: (pos) async {
                      if (!_applyMode) {
                        // 閲覧モード: 半径30km以内の釣り場を表示し、最寄りを選択
                        await _onViewLongPress(pos.latitude, pos.longitude);
                        return;
                      }
                      // 長押しで申請用ピンを設置
                      setState(() {
                        _gmApplyPoint = pos;
                        // 既存の 'apply' マーカーを除去してから追加
                        _gmMarkers.removeWhere((m) => m.markerId.value == 'apply');
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
                              try { _gmController?.showMarkerInfoWindow(const gm.MarkerId('apply')); } catch (_) {}
                            },
                          ),
                        );
                      });
                      // 可能なら情報ウィンドウを即表示
                      try { _gmController?.showMarkerInfoWindow(const gm.MarkerId('apply')); } catch (_) {}
                      // 案内表示
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      messenger?.showSnackBar(
                        const SnackBar(
                          content: Text('この位置でよければ「釣り場登録」をタップしてください。'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    },
                    onCameraMove: (pos) {
                      if (!mounted) return;
                      setState(() {
                        _center = LatLng(pos.target.latitude, pos.target.longitude);
                        _currentZoom = pos.zoom;
                      });
                      // メッシュはズーム・中心に応じて動的だが、簡易に再計算
                      if (ambiguous_plevel == 2) {
                        _gmPolylines.clear();
                        for (final pl in _buildMeshPolylines()) {
                          final pts = pl.points.map((p) => gm.LatLng(p.latitude, p.longitude)).toList();
                          _gmPolylines.add(gm.Polyline(
                            polylineId: gm.PolylineId('mesh-${_gmPolylines.length}-${DateTime.now().millisecondsSinceEpoch}'),
                            points: pts,
                            color: Colors.black.withOpacity(0.2),
                            width: 1,
                          ));
                        }
                        if (mounted) setState(() {});
                      }
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
                      interactionOptions: const fm.InteractionOptions(flags: fm.InteractiveFlag.all),
                      onLongPress: (tapPosition, latlng) async {
                        if (!_applyMode) {
                          // 閲覧モード: 半径30km以内の釣り場を表示し、最寄りを選択
                          await _onViewLongPress(latlng.latitude, latlng.longitude);
                          return;
                        }
                        // 長押しで申請用ピンを設置
                        setState(() {
                          _applyPoint = latlng;
                        });
                        final messenger = ScaffoldMessenger.maybeOf(context);
                        messenger?.showSnackBar(
                          const SnackBar(
                            content: Text('この位置でよければ「釣り場登録」をタップしてください。'),
                            duration: Duration(seconds: 3),
                          ),
                        );
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
                        urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c'],
                        userAgentPackageName: 'jp.bouzer.siowadou',
                        tileProvider: fm.NetworkTileProvider(),
                      ),
                      if (ambiguous_plevel == 2)
                        fm.PolylineLayer(polylines: _buildMeshPolylines()),
                      if (ambiguous_plevel == 2)
                        fm.MarkerLayer(markers: _buildGridCenterMarkers()),
                      fm.MarkerLayer(markers: _buildAllMarkers()),
                      const fm.RichAttributionWidget(
                        attributions: [
                          fm.TextSourceAttribution('© OpenStreetMap contributors'),
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
                if (ambiguous_plevel == 2 && _center != null)
                  // 画面中央に現在のグリッド識別子 (X, Y) を表示
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: true,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: Builder(
                            builder: (_) {
                              final g = Common.grid10kmXY(_center!.latitude, _center!.longitude);
                              return Text(
                                'X=${g.x}, Y=${g.y}',
                                style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w600),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                // 釣り場名の上部オーバーレイは廃止（選択ピン上のラベルで代替）
                // 左上（同じY位置）にモード表示バッジ
                Positioned(
                  top: 70,
                  right: 8,
                  child: GestureDetector(
                    onTap: _showModeInfoDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_applyMode ? Icons.edit_location_alt : Icons.remove_red_eye,
                              size: 16, color: Colors.black87),
                          const SizedBox(width: 6),
                          Text(
                            _applyMode ? '釣り場登録モード' : '閲覧モード',
                            style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.info_outline, size: 16, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                ),
                // 下から引っ張り出すボトムシート（投稿一覧などを想定）
                Builder(
                  key: _sheetActuatorKey,
                  builder: (context) => DraggableScrollableActuator(
                    child: KeyedSubtree(
                      key: ValueKey('epoch-$_sheetEpoch'),
                      child: _buildDraggableBottomSheet(),
                    ),
                  ),
                ),
                if (_showTideOverlay) Positioned.fill(child: _buildTideOverlay()),
              ],
            ),
    );
  }

  Widget _buildDraggableBottomSheet() {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.25, // 初期は少しだけ見せる（広めに）
      minChildSize: 0.0,      // 非表示まで下げられる
      maxChildSize: 0.92,     // 上部に余白を残す
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
            child: _BottomSheetCatchList(key: ValueKey('sheet-${_sheetReloadTick}'), extController: controller),
          ),
        );
      },
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
    if (mounted) setState(() { _sheetEpoch++; });
    if (show) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSheetVisible());
    }
  }

  void _onSheetChanged() {
    try {
      final s = _sheetController.size;
      if (s > 0.01) _lastSheetSize = s;
    } catch (_) {}
  }

  double _safeSheetSize() {
    try { return _sheetController.size; } catch (_) { return 0.0; }
  }

  List<fm.Polyline> _buildMeshPolylines() {
    if (_center == null) return const <fm.Polyline>[];
    // Web Mercator メートル座標で 10km グリッドを固定生成
    const double R = 6378137.0; // Web Mercator 半径（m）
    final double gridM = meshSize.toDouble() * 1000.0; // 可変メッシュ（km -> m）

    // 中心のメルカトル座標
    final _M xy = _projectToMercator(_center!.latitude, _center!.longitude);

    // ズームに応じた描画範囲（半径km）
    double radiusKm;
    if (_currentZoom >= 14) radiusKm = 12;
    else if (_currentZoom >= 13) radiusKm = 20;
    else if (_currentZoom >= 12) radiusKm = 35;
    else if (_currentZoom >= 11) radiusKm = 60;
    else radiusKm = 100;
    final double rangeM = radiusKm * 1000.0;

    // 表示領域（概算）
    final double xMin = xy.x - rangeM;
    final double xMax = xy.x + rangeM;
    final double yMin = (xy.y - rangeM).clamp(-math.pi * R, math.pi * R);
    final double yMax = (xy.y + rangeM).clamp(-math.pi * R, math.pi * R);

    // グリッド開始点（原点 0 を基準に 10km きざみ）
    final double startX = (xMin / gridM).floorToDouble() * gridM;
    final double startY = (yMin / gridM).floorToDouble() * gridM;

    const int segs = 16; // 線分近似の分割数
    final lines = <fm.Polyline>[];

    // 垂直線 x = const
    for (double x = startX; x <= xMax + 1e-6; x += gridM) {
      final pts = <LatLng>[];
      for (int i = 0; i <= segs; i++) {
        final double t = i / segs;
        final double y = yMin + (yMax - yMin) * t;
        final latlng = _unprojectFromMercator(x, y);
        pts.add(latlng);
      }
      lines.add(fm.Polyline(points: pts, color: Colors.black.withOpacity(0.20), strokeWidth: 1.0));
    }

    // 水平線 y = const
    for (double y = startY; y <= yMax + 1e-6; y += gridM) {
      final pts = <LatLng>[];
      for (int i = 0; i <= segs; i++) {
        final double t = i / segs;
        final double x = xMin + (xMax - xMin) * t;
        final latlng = _unprojectFromMercator(x, y);
        pts.add(latlng);
      }
      lines.add(fm.Polyline(points: pts, color: Colors.black.withOpacity(0.20), strokeWidth: 1.0));
    }

    return lines;
  }

  List<fm.Marker> _buildGridCenterMarkers() {
    if (_center == null) return const <fm.Marker>[];
    // 低ズームでは密集しすぎるため非表示
    if (_currentZoom < 11) return const <fm.Marker>[];

    const double R = 6378137.0; // Web Mercator 半径
    final double gridM = meshSize.toDouble() * 1000.0; // 可変メッシュ（km -> m）
    final _M xy = _projectToMercator(_center!.latitude, _center!.longitude);

    double radiusKm;
    if (_currentZoom >= 14) radiusKm = 12;
    else if (_currentZoom >= 13) radiusKm = 20;
    else if (_currentZoom >= 12) radiusKm = 35;
    else radiusKm = 60;
    final double rangeM = radiusKm * 1000.0;

    final double xMin = xy.x - rangeM;
    final double xMax = xy.x + rangeM;
    final double yMin = (xy.y - rangeM).clamp(-math.pi * R, math.pi * R);
    final double yMax = (xy.y + rangeM).clamp(-math.pi * R, math.pi * R);

    final double startX = (xMin / gridM).floorToDouble() * gridM;
    final double startY = (yMin / gridM).floorToDouble() * gridM;

    final markers = <fm.Marker>[];
    for (double x = startX; x <= xMax + 1e-6; x += gridM) {
      for (double y = startY; y <= yMax + 1e-6; y += gridM) {
        final double cx = x + gridM / 2.0;
        final double cy = y + gridM / 2.0;
        if (cx < xMin || cx > xMax || cy < yMin || cy > yMax) continue;
        final LatLng ll = _unprojectFromMercator(cx, cy);
        final g = Common.grid10kmXY(ll.latitude, ll.longitude);
        markers.add(
          fm.Marker(
            width: 140,
            height: 30,
            point: ll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.90),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'X=${g.x}, Y=${g.y}',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  // Web Mercator <-> LatLng 変換
  _M _projectToMercator(double lat, double lon) {
    const double R = 6378137.0;
    final double x = R * (lon * math.pi / 180.0);
    final double y = R * math.log(math.tan(math.pi / 4.0 + (lat * math.pi / 180.0) / 2.0));
    return _M(x, y);
  }

  LatLng _unprojectFromMercator(double x, double y) {
    const double R = 6378137.0;
    final double lon = (x / R) * 180.0 / math.pi;
    final double lat = (2.0 * math.atan(math.exp(y / R)) - math.pi / 2.0) * 180.0 / math.pi;
    return LatLng(lat, lon);
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
                IconButton(
                  icon: Icon(canPop ? Icons.arrow_back : Icons.close),
                  onPressed: () {
                    if (canPop) {
                      _tideNavKey.currentState?.maybePop();
                    } else {
                      setState(() => _showTideOverlay = false);
                    }
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  canPop ? '日付' : '潮汐',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(
            child: Navigator(
              key: _tideNavKey,
              observers: [_tideNavObserver],
              onGenerateRoute: (settings) {
                return MaterialPageRoute(builder: (_) => _TideHomePage(controller: _tidePageController, baseDate: _tideBaseDate));
              },
            ),
          ),
        ],
      ),
    ));
  }


  Widget _buildTopOverlayPanel(BuildContext context) {
    Widget item({required Widget icon, required String label, required VoidCallback? onTap}) {
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
                style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // お気に入り：ブックマーク
          item(
            icon: const Icon(Icons.bookmark_border, color: Colors.black87),
            label: 'お気に入り',
            onTap: () => _onToggleFavorite(context),
          ),
          // 釣り場申請：長押し案内
          item(
            icon: Icon(Icons.add_location_alt, color: _applyMode ? Colors.deepPurple : Colors.black87),
            label: _applyMode ? '釣り場登録中...' : '釣り場登録',
            onTap: () {
              // 先に新しいモードを決定してから setState に渡す
              final bool newMode = !_applyMode;
              setState(() {
                _applyMode = newMode;
                if (!newMode) {
                  // 申請モード解除時は申請ピンを消す
                  _applyPoint = null;
                  _gmApplyPoint = null;
                  try { _gmMarkers.removeWhere((m) => m.markerId.value == 'apply'); } catch (_) {}
                }
              });
/*
              if (newMode) {
                final messenger = ScaffoldMessenger.maybeOf(context);
                messenger?.showSnackBar(
                  const SnackBar(
                    content: Text('新規釣り場申請したいポイントを長押ししてください'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
*/

            },
          ),
          // 経路表示：車
          item(
            icon: const Icon(Icons.directions_car, color: Colors.black87),
            label: '経路表示',
            onTap: () => _onOpenRoute(context),
          ),
          // 衛星表示（Google Maps のみ表示）
          if (baseMap == 2)
            item(
              icon: Icon(
                _isSatellite ? Icons.satellite_alt : Icons.satellite_alt_outlined,
                color: Colors.black87,
              ),
              label: '衛星表示',
              onTap: () => setState(() {
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
              portId = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
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
          messenger?.showSnackBar(SnackBar(content: Text(isFav ? 'お気に入り解除の同期に失敗しました（${resp.statusCode}）' : 'お気に入りの同期に失敗しました（${resp.statusCode}）'), duration: const Duration(seconds: 3)));
        } else {
          messenger?.showSnackBar(SnackBar(content: Text(isFav ? 'お気に入り解除: $portName' : 'お気に入り登録: $portName')));
        }
      } catch (_) {
        messenger?.showSnackBar(SnackBar(content: Text(isFav ? 'お気に入り解除の同期中にエラーが発生しました（ローカル保存済み）' : 'お気に入りの同期中にエラーが発生しました（ローカル保存済み）'), duration: const Duration(seconds: 3)));
      }
      // 再読込して反映（マーカー拡大/太字を即座に反映）
      await _loadFavorites();
      try {
        final name = (_lastName.isNotEmpty) ? _lastName : Common.instance.selectedTeibouName;
        final lat = (_lastLat ?? Common.instance.selectedTeibouLat);
        final lng = (_lastLng ?? Common.instance.selectedTeibouLng);
        if ((lat != 0.0 || lng != 0.0) && name.isNotEmpty) {
          await _loadMarkers(centerName: name, lat: lat, lng: lng, radiusKm: 30.0);
        } else if (_center != null) {
          await _loadMarkers(centerName: name, lat: _center!.latitude, lng: _center!.longitude, radiusKm: 30.0);
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
        messenger?.showSnackBar(const SnackBar(content: Text('設定から地図アプリを選択してください')));
      }
      return;
    }

    if (Common.instance.mapKind == MapType.googleMaps.index) {
      await Common.instance.openGoogleMaps(lat, lng);
    } else if (Common.instance.mapKind == MapType.appleMaps.index) {
      await Common.instance.openAppleMaps(lat, lng);
    } else {
      messenger?.showSnackBar(const SnackBar(content: Text('設定から地図アプリを選択してください')));
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

  double _haversine(double lat1, double lon1, double lat2, double lon2, {double? cosLat}) {
    const double deg2rad = 3.141592653589793 / 180.0;
    final dLat = (lat2 - lat1) * deg2rad;
    final dLon = (lon2 - lon1) * deg2rad;
    final sLat = math.sin(dLat / 2);
    final sLon = math.sin(dLon / 2);
    final a = sLat * sLat + math.cos(lat1 * deg2rad) * math.cos(lat2 * deg2rad) * sLon * sLon;
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
            onTap: () => _openApplyForm(_applyPoint!.latitude, _applyPoint!.longitude),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1))],
                ),
                child: const Text(
                  '釣り場登録',
                  style: TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.w600),
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
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(1, 1))],
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
          try { _gmMarkers.removeWhere((m) => m.markerId.value == 'apply'); } catch (_) {}
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
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * d2r) * math.cos(lat2 * d2r) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _zoomForRadius(double radiusKm) {
    if (radiusKm <= 5) return 13.5;
    if (radiusKm <= 10) return 12.5;
    if (radiusKm <= 20) return 11.5;
    if (radiusKm <= 30) return 11.0;
    if (radiusKm <= 50) return 10.5;
    return 10.0;
  }

  String? _kubunLabelLocal(String kubun) {
    final v = kubun.trim();
    final lv = v.toLowerCase();
    switch (lv) {
      case '1': return '地域港';
      case '2': return '拠点港';
      case '3': return '主要港';
      case '4': return '特殊港';
      case 'gyoko': return '漁港';
      case 'iso': return '磯';
      case 'kako': return '河口';
      case 'surf': return 'サーフ';
      case 'teibo': return '堤防';
      case 'teibou': return '堤防';
      default:
        if (v == '特3') return '最重要港';
        return null;
    }
  }

  Future<void> _showCurrentSpotInfoDialog() async {
    try {
      final spotName = Common.instance.selectedTeibouName.isNotEmpty ? Common.instance.selectedTeibouName : Common.instance.tidePoint;
      final rows = await SioDatabase().getAllTeibouWithPrefecture();
      Map<String, dynamic>? row;
      // 1) ID優先（保存済みの selected_teibou_id）
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
      // 2) 見つからなければ名前一致
      if (row == null) {
        for (final r in rows) {
          final n = (r['port_name'] ?? '').toString();
          if (n == spotName) { row = r; break; }
        }
      }
      // 見つからない場合は、現在の選択座標に最も近い行を採用
      final double selLat = Common.instance.selectedTeibouLat != 0.0 ? Common.instance.selectedTeibouLat : (_center?.latitude ?? 0.0);
      final double selLng = Common.instance.selectedTeibouLng != 0.0 ? Common.instance.selectedTeibouLng : (_center?.longitude ?? 0.0);
      if (row == null && (selLat != 0.0 || selLng != 0.0)) {
        double best = double.infinity;
        Map<String, dynamic>? bestRow;
        for (final r in rows) {
          final dlat0 = _toDouble(r['latitude']);
          final dlng0 = _toDouble(r['longitude']);
          if (dlat0 == null || dlng0 == null) continue;
          final d = _distanceKm(selLat, selLng, dlat0, dlng0);
          if (d < best) { best = d; bestRow = r; }
        }
        if (bestRow != null) row = bestRow;
      }
      String prefName = '';
      if (row != null) {
        prefName = (row['todoufuken_name'] ?? '').toString();
        if (prefName.isEmpty) {
          final pid = row['todoufuken_id'] is int ? row['todoufuken_id'] as int : int.tryParse(row['todoufuken_id']?.toString() ?? '');
          if (pid != null && pid > 0) {
            final prefs = await SioDatabase().getTodoufukenAll();
            for (final p in prefs) {
              final id = p['todoufuken_id'] is int ? p['todoufuken_id'] as int : int.tryParse(p['todoufuken_id']?.toString() ?? '');
              if (id == pid) { prefName = (p['todoufuken_name'] ?? '').toString(); break; }
            }
          }
        }
      }
      final lat = Common.instance.selectedTeibouLat != 0.0 ? Common.instance.selectedTeibouLat : _center?.latitude ?? 0.0;
      final lng = Common.instance.selectedTeibouLng != 0.0 ? Common.instance.selectedTeibouLng : _center?.longitude ?? 0.0;
      final kubun = (((row != null) ? row['kubun'] : '') ?? '').toString();
      final kubunLabel = _kubunLabelLocal(kubun) ?? '';
      final yomi = (((row != null) ? (row['j_yomi'] ?? row['furigana']) : '') ?? '').toString();
      final address = (((row != null) ? row['address'] : '') ?? '').toString();
      String _shortAddress(String s) {
        final t = s.trim();
        if (t.isEmpty) return t;
        final parts = t.split(RegExp(r'\s+'));
        return parts.length >= 2 ? '${parts[0]} ${parts[1]}' : parts[0];
      }
      final addressShort = _shortAddress(address);
      final int? flag = (row != null)
          ? (row['flag'] is int ? row['flag'] as int : int.tryParse(row['flag']?.toString() ?? ''))
          : null;
      String _flagText(int? f) {
        switch (f) {
          case 0:
            return '運営登録済み';
          case -1:
            return 'ユーザ申請中';
          case -2:
            return 'ユーザ申請非承認';
          case 1:
            return 'ユーザ登録承認ずみ';
          default:
            return '';
        }
      }
      final statusText = _flagText(flag);
      final dynamic _uidRaw = (row != null) ? row['user_id'] : null;
      final int? ownerId = (_uidRaw is int) ? _uidRaw : int.tryParse((_uidRaw?.toString() ?? ''));
      String? nick;
      try {
        if (ownerId != null) {
          final me = await loadUserInfo();
          if (me != null && ownerId == me.userId) {
            nick = me.nickName ?? '';
          } else {
            // サーバJOIN値（registrant_name）があれば優先
            final rn = ((row != null) ? (row['registrant_name']?.toString() ?? '') : '').trim();
            if (rn.isNotEmpty) nick = rn; // 投稿と同様: 追加問い合わせは行わない
          }
        }
      } catch (_) {}

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('都道府県', prefName),
              const SizedBox(height: 6),
              _infoRow(
                '釣り場名',
                (() {
                  final base = yomi.isNotEmpty ? '$spotName（$yomi）' : spotName;
                  return (flag == -1) ? '$base (申請中)' : base;
                })(),
              ),
              const SizedBox(height: 6),
              _infoRow('種別', kubunLabel),
              const SizedBox(height: 6),
              _infoRow('緯度経度', '${lat.toStringAsFixed(5)} , ${lng.toStringAsFixed(5)}'),
              const SizedBox(height: 6),
              _infoRow('住所', addressShort),
              const SizedBox(height: 6),
              _infoRow('状態', statusText),
              const SizedBox(height: 6),
              _infoRow('登録者', (ownerId != null) ? '${(nick ?? '').isNotEmpty ? nick : '−'}($ownerId)' : '−'),
            ],
          ),
        ),
      );
    } catch (_) {}
  }

  Widget _infoRow(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 80, child: Text('$k:', style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(width: 6),
        Expanded(child: Text(v.isNotEmpty ? v : '−')),
      ],
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
      if (mounted) setState(() { _favoriteIds = ids; });
    } catch (_) {}
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
      final lat = (2 * math.atan(math.exp(mercN)) - math.pi / 2.0) * 180.0 / math.pi;
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
      set.add(am.Annotation(
        annotationId: am.AnnotationId('c'),
        position: am.LatLng(_center!.latitude, _center!.longitude),
      ));
      idx++;
    }
    // 近隣はDBから半径30kmで再取得して簡易注釈
    try {
      final rows = SioDatabase().getAllTeibouWithPrefecture();
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
            set.add(am.Annotation(
              annotationId: am.AnnotationId('n${idx++}'),
              position: am.LatLng(dlat, dlng),
            ));
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

class _BottomSheetCatchList extends StatefulWidget {
  const _BottomSheetCatchList({Key? key, required this.extController}) : super(key: key);
  final ScrollController extController;
  @override
  State<_BottomSheetCatchList> createState() => _BottomSheetCatchListState();
}

class _BottomSheetCatchListState extends State<_BottomSheetCatchList> {
  final List<_PostItem> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  String _mode = 'catch'; // 'catch' or 'env'
  String _lastCommonMode = 'catch';

  @override
  void initState() {
    super.initState();
    // 直前の選択状態を復元（起動中のみ保持）
    try { _mode = Common.instance.postListMode; } catch (_) {}
    _lastCommonMode = _mode;
    try { Common.instance.addListener(_onCommonModeChanged); } catch (_) {}
    _loadFirst();
    widget.extController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.extController.removeListener(_onScroll);
    try { Common.instance.removeListener(_onCommonModeChanged); } catch (_) {}
    super.dispose();
  }

  void _onCommonModeChanged() {
    final cm = Common.instance.postListMode;
    if (cm != _lastCommonMode) {
      _lastCommonMode = cm;
      if (mounted && _mode != cm) {
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
  }

  void _onScroll() {
    if (!_hasMore || _loading) return;
    if (widget.extController.position.pixels >= widget.extController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<List<_PostItem>> _fetch({required int page, required int kind}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final spotId = prefs.getInt('selected_teibou_id');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final uri = Uri.parse('${AppConfig.instance.baseUrl}get_post_list.php?ts=$ts');
      final body = <String, String>{
        'get_kind': kind.toString(),
        'page': page.toString(),
        'page_size': kPostPageSize.toString(),
        'ts': ts.toString(),
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
        return rows.map((e) => _PostItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      if (data is List) {
        return data.map((e) => _PostItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadFirst() async {
    if (!mounted || _loading) return;
    setState(() { _loading = true; _page = 1; _hasMore = true; });
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
      _items.addAll(rows);
      _hasMore = rows.length >= kPostPageSize;
      _page += 1;
      _loading = false;
    });
  }

  Future<List<_PostItem>> _applyAmbiguityFilter(List<_PostItem> rows) async {
    if (ambiguous_plevel != 0) return rows;
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
    final bool isCatch = _mode == 'catch';
    final totalCount = 1 /*header*/ + _items.length + (_hasMore ? 1 : 0);
    return ListView.builder(
      controller: widget.extController,
      padding: EdgeInsets.zero,
      itemCount: totalCount,
      itemBuilder: (context, index) {
        // 0: ヘッダー（グラブハンドル＋タイトル）
        if (index == 0) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 60,
                height: 6,
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // 左端: ＋ 投稿 ボタン（アイコンなし、全角プラス）
                    OutlinedButton(
                      onPressed: () async {
                        final posted = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InputPost(initialType: _mode == 'catch' ? 'catch' : 'env'),
                          ),
                        );
                        if (posted == true) {
                          if (!mounted) return;
                          setState(() {
                            _items.clear();
                            _page = 1;
                            _hasMore = true;
                            _loading = false;
                          });
                          await _loadFirst();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      child: const Text('＋ 投稿', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    // 中央: 投稿一覧（中央寄せ）
                    const Expanded(
                      child: Center(
                        child: Text('投稿一覧', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    // 右端: セグメント（釣果/環境）を右寄せで
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: CupertinoSegmentedControl<String>(
                          groupValue: _mode,
                          padding: const EdgeInsets.all(0),
                          children: const {
                            'catch': Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('釣果')),
                            'env': Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('環境')),
                          },
                          onValueChanged: (val) {
                            setState(() {
                              _mode = val;
                              // 現在の選択をアプリ起動中は維持
                              try { Common.instance.setPostListMode(val); } catch (_) {}
                              // モード切替時は一覧をリセットして再取得
                              _items.clear();
                              _page = 1;
                              _hasMore = true;
                              _loading = false;
                            });
                            _loadFirst();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
            ],
          );
        }
        final listIndex = index - 1;
        if (listIndex >= _items.length) {
          // ローディングフッター
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final it = _items[listIndex];
        final thumb = it.thumbUrl ?? it.imageUrl;
        return Column(
          children: [
            ListTile(
              leading: (thumb != null)
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(thumb, width: 48, height: 48, fit: BoxFit.cover))
                  : const Icon(Icons.image, size: 40, color: Colors.black38),
              title: Text(it.title?.isNotEmpty == true ? it.title! : (it.nickName ?? '投稿'), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(it.detail?.isNotEmpty == true ? it.detail! : (it.createAt ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PostDetailPage(
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
                      showNearbyButton: true,
                    ),
                  ),
                ));
              },
            ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }
}

class _TideNavObserver extends NavigatorObserver {
  final VoidCallback onChanged;
  _TideNavObserver(this.onChanged);
  @override
  void didPush(Route route, Route? previousRoute) { onChanged(); }
  @override
  void didPop(Route route, Route? previousRoute) { onChanged(); }
}

class _TideHomePage extends StatelessWidget {
  const _TideHomePage({Key? key, required this.controller, required this.baseDate}) : super(key: key);
  final PageController controller;
  final DateTime baseDate;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight; // オーバーレイ内部での有効高さ
      return PageView.builder(
        controller: controller,
        onPageChanged: (int index) async {
          final newDate = baseDate.add(Duration(days: index - 1000));
          Common.instance.tideDate = newDate;
          try { await Common.instance.getTide(true, newDate); } catch (_) {}
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
    });
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
                const Text('Apple Maps を使用します', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                Text('(${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)})', style: const TextStyle(color: Colors.black45, fontSize: 12)),
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
class _TideStandalonePage extends StatelessWidget {
  const _TideStandalonePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('潮汐'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;
          return _SlidingContent(
            key: ValueKey('tide-standalone-${Common.instance.tideDate.toIso8601String()}'),
            tidePoint: Common.instance.tidePoint,
            teibouName: Common.instance.selectedTeibouName,
            nearestPoint: Common.instance.selectedTeibouNearestPoint,
            tideDate: Common.instance.tideDate,
            availableHeight: h,
          );
        },
      ),
    );
  }
}

class _M {
  final double x;
  final double y;
  const _M(this.x, this.y);
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
            final rid = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
            if (rid == sid) { hit = r; break; }
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
        final isPort = k == '1' || k == '2' || k == '3' || k == '4' || k == '特3' || k == 'gyoko';
        String yomi = (hit['j_yomi'] ?? '').toString();
        if (yomi.isEmpty) yomi = (hit['furigana'] ?? '').toString();
        int? flag;
        try { flag = hit['flag'] is int ? hit['flag'] as int : int.tryParse(hit['flag']?.toString() ?? ''); } catch (_) {}
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.date_range, size: 16),
              label: const Text('日付変更', style: TextStyle(fontSize: 13)),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => SetDatePage(showBanner: true, showHeader: true)),
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            child: SizedBox(width: double.infinity, child: _valueBox(Sio.instance.dispTideDate)),
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
            child: Text('満潮', style: TextStyle(fontSize: 14, color: Colors.white), textAlign: TextAlign.left),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            child: Row(children: [
              Expanded(child: _valueBox(Sio.instance.highTideTime1)),
              const SizedBox(width: 2.0),
              Expanded(child: _valueBox(Sio.instance.highTideTime2)),
            ]),
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
            child: Text('干潮', style: TextStyle(fontSize: 14, color: Colors.white), textAlign: TextAlign.left),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            child: Row(children: [
              Expanded(child: _valueBox(Sio.instance.lowTideTime1)),
              const SizedBox(width: 2.0),
              Expanded(child: _valueBox(Sio.instance.lowTideTime2)),
            ]),
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
            child: Row(children: const [
              Expanded(child: Text('日出', style: TextStyle(fontSize: 14, color: Colors.white), textAlign: TextAlign.left)),
              SizedBox(width: 2.0),
              Expanded(child: Text('日没', style: TextStyle(fontSize: 14, color: Colors.white), textAlign: TextAlign.left)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            child: Row(children: [
              Expanded(child: _valueBox(Sio.instance.sunRiseTime)),
              const SizedBox(width: 2.0),
              Expanded(child: _valueBox(Sio.instance.sunSetTime)),
            ]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 受け取った availableHeight をそのまま使用（タブは上位で差し引き済み）
    // 上段(情報パネル)は画面高の50%、中央に5%の隙間、下段(グラフ)は45%
    double topHeight = availableHeight * 0.50; // 約50%
    double gapHeight = availableHeight * 0.05; // 約5%
    double graphHeight = availableHeight - topHeight - gapHeight; // 残り（約45%）
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: FutureBuilder<Map<String, dynamic>>(
                            future: _getSelectedTeibouMeta(),
                            builder: (context, snapshot) {
                              final name = (teibouName != null && teibouName!.isNotEmpty) ? teibouName! : tidePoint;
                              final meta = snapshot.data;
                              final isPort = (meta != null && meta['isPort'] == true);
                              final yomi = (meta != null && meta['yomi'] is String) ? meta['yomi'] as String : '';
                              final isPending = (meta != null && (meta['flag'] == -1 || meta['flag'] == '-1'));
                              final displayName = isPending ? '$name (申請中)' : name;
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isPort)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: Icon(Icons.anchor, color: Colors.blue.shade600, size: 18),
                                        ),
                                      Flexible(
                                        child: Text(
                                          displayName,
                                          style: const TextStyle(fontSize: 22, color: Colors.white),
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (yomi.isNotEmpty) const SizedBox(height: 4),
                                  if (yomi.isNotEmpty)
                                    Text(
                                      yomi,
                                      style: const TextStyle(fontSize: 13, color: Colors.white70),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                              final Offset center = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);

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
                                      painter: CircularMaskPainter(radius: maskRadius),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                Sio.instance.sioName,
                                style: const TextStyle(fontSize: 24, color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tidePoint,
                                style: const TextStyle(fontSize: 13, color: Colors.white70),
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
        if (gapHeight > 0)
          Container(
            height: gapHeight,
            color: _navyBg,
          ),
        // 下部領域：潮汐グラフエリア（45%）
        SizedBox(
          height: graphHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: DrawTide(), child: SizedBox.shrink()),
              ),
            ],
          ),
        ),
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
  bool shouldRepaint(covariant CircularMaskPainter oldDelegate) => oldDelegate.radius != radius;
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

      final double sunriseX = rectTide.left +
          sunriseMinutes * (width - leftMargin - rightMargin) / (24.0 * 60.0);
      final double sunsetX = rectTide.left +
          sunsetMinutes * (width - leftMargin - rightMargin) / (24.0 * 60.0);

      // ラベルは白背景＋影で、満潮/干潮と同様の見た目に
      final TextStyle textStyle = const TextStyle(fontSize: fontSize, color: Colors.black);
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
      final Paint shadowPaint = Paint()
        ..color = Colors.black.withAlpha(128)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      final Paint bgPaint = Paint()..color = Colors.white;
      final Paint tickPaint = Paint()
        ..color = Colors.redAccent
        ..strokeWidth = 1.2;

      // 日出ラベル
      final double srRectW = srTp.width + padX * 2;
      final double srLeft = clampX(sunriseX - srRectW / 2, srRectW);
      final Rect srRect = Rect.fromLTWH(srLeft, baseY, srRectW, rectH);
      canvas.drawRect(srRect.shift(const Offset(2, 2)), shadowPaint);
      canvas.drawRect(srRect, bgPaint);
      final Offset srTextOffset = Offset(srRect.left + (srRect.width - srTp.width) / 2, srRect.top + (rectH - srTp.height) / 2 - 1);
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
      final Offset ssTextOffset = Offset(ssRect.left + (ssRect.width - ssTp.width) / 2, ssRect.top + (rectH - ssTp.height) / 2 - 1);
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
      const wdays = ['月','火','水','木','金','土','日'];
      final w = wdays[(d.weekday + 6) % 7]; // DateTime: Mon=1..Sun=7
      final dateStr = '${two(d.month)}/${two(d.day)} ($w)';
      final TextPainter dtp = TextPainter(
        text: TextSpan(
          text: dateStr,
          style: TextStyle(fontSize: 20, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(minWidth: 0, maxWidth: rectTide.width);
      // 少し上側に余白を設けつつ、12:00（中央）にセンタリング
      final double x12 = rectTide.left + rectTide.width / 2;
      final double yTop = rectTide.top + 5; // 上部余白を半分に
      final Offset dateOffset = Offset(x12 - dtp.width / 2, yTop);
      // 半透明の白背景で視認性を確保
      final Rect bg = Rect.fromLTWH(dateOffset.dx - 8, yTop - 4, dtp.width + 16, dtp.height + 8);
      final Paint bgPaint = Paint()..color = const Color(0x99FFFFFF);
      canvas.drawRRect(RRect.fromRectAndRadius(bg, const Radius.circular(8)), bgPaint);
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
    final lastp = getXY(SioInfo.sample_cnt - 1, width, height, maxWave, minWave);
    final fillPath = ui.Path.from(path)
      ..lineTo(lastp.dx, rectTide.bottom)
      ..lineTo(firstp.dx, rectTide.bottom)
      ..close();
    final fillPaint = Paint()
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
