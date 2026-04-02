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
import 'sio_info.dart';
import 'sio.dart';
import 'sio_database.dart';
import 'set_date_page.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:geolocator/geolocator.dart';

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
            length: 3,
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
                        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.waves), SizedBox(width: 6), Text('潮汐')])),
                        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.map), SizedBox(width: 6), Text('地図')])),
                        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.post_add), SizedBox(width: 6), Text('投稿')])),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      // 潮汐タブ配下のみ左右スワイプ可能
                      PageView.builder(
                        controller: _pageController,
                        onPageChanged: (int index) {
                          DateTime newDate = _baseDate.add(Duration(days: index - 1000));
                          setState(() {
                            common.tideDate = newDate;
                            _initData2(newDate);
                          });
                        },
                        itemBuilder: (context, index) {
                          DateTime pageDate = _baseDate.add(Duration(days: index - 1000));
                          return _SlidingContent(
                            key: ValueKey(pageDate),
                            tidePoint: common.tidePoint,
                            teibouName: Common.instance.selectedTeibouName,
                            nearestPoint: Common.instance.selectedTeibouNearestPoint,
                            tideDate: pageDate,
                            availableHeight: contentHeight,
                          );
                        },
                      ),
                      // 地図（全面表示）
                      _FishingInfoPane(height: contentHeight),
                      // 投稿：内側タブ（釣果 / 釣場環境） + 共通FAB
                      DefaultTabController(
                        length: 2,
                        child: Stack(
                          children: [
                            Column(
                              children: [
                                Container(
                                  color: Colors.white,
                                  child: TabBar(
                                    indicatorColor: Colors.black,
                                    labelColor: Colors.black,
                                    unselectedLabelColor: Colors.black54,
                                    tabs: [
                                      const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Text('🐟', style: TextStyle(fontSize: 20)), SizedBox(width: 6), Text('釣果')])),
                                      Tab(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // 青い看板に白いPの簡易アイコン
                                            Container(
                                              width: 18,
                                              height: 18,
                                              decoration: BoxDecoration(
                                                color: Colors.blue,
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              alignment: Alignment.center,
                                              child: const Text('P', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                                            ),
                                            const SizedBox(width: 4),
                                            const Icon(Icons.wc),
                                            const SizedBox(width: 4),
                                            // 釣り禁止（規制）を示す簡易アイコンに戻す
                                            const Text('🚫', style: TextStyle(fontSize: 16)),
                                            const SizedBox(width: 6),
                                            const Text('環境'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                              child: TabBarView(
                                children: [
                                  _CatchTab(
                                    key: ValueKey('${Common.instance.selectedTeibouName}-${_catchRefreshTick}'),
                                    refreshTick: _catchRefreshTick,
                                  ),
                                  _EnvTabbedList(
                                    key: ValueKey('${Common.instance.selectedTeibouName}-${_envRefreshTick}'),
                                    refreshTick: _envRefreshTick,
                                  ),
                                ],
                              ),
                                ),
                              ],
                            ),
                            Positioned(
                              right: 16,
                              bottom: 16,
                              child: Builder(
                                builder: (context) {
                                  final controller = DefaultTabController.of(context);
                                  if (controller == null) {
                                    return FloatingActionButton.extended(
                                      onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const InputPost(initialType: 'catch')),
                                      ).then((posted) {
                                        if (posted == true) {
                                          setState(() => _catchRefreshTick++);
                                        }
                                      });
                                      },
                                      icon: const Icon(Icons.add),
                                      label: const Text('釣果投稿'),
                                    );
                                  }
                                  return AnimatedBuilder(
                                    animation: controller.animation!,
                                    builder: (context, _) {
                                      final isCatch = controller.index == 0;
                                      return FloatingActionButton.extended(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (_) => InputPost(initialType: isCatch ? 'catch' : 'env')),
                                          ).then((posted) {
                                            if (posted == true) {
                                              setState(() {
                                                if (isCatch) {
                                                  _catchRefreshTick++;
                                                } else {
                                                  _envRefreshTick++;
                                                }
                                              });
                                            }
                                          });
                                        },
                                        icon: const Icon(Icons.add),
                                        label: Text(isCatch ? '釣果投稿' : '環境投稿'),
                                      );
                                    },
                                  );
                                },
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
          child: const ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  ambiguous_point ? 'この釣り場近辺の釣果です。' : 'この釣り場の釣果です。',
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

  // ambiguous_point=false のときは、選択中の釣り場IDに一致する投稿のみを表示
  Future<List<_PostItem>> _applyAmbiguityFilter(List<_PostItem> rows) async {
    if (ambiguous_point) return rows;
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
  const _FishingInfoPane({required this.height});
  final double height;

  @override
  State<_FishingInfoPane> createState() => _FishingInfoPaneState();
}

class _FishingInfoPaneState extends State<_FishingInfoPane> {
  final List<fm.Marker> _markers = [];
  LatLng? _center;
  double? _lastLat;
  double? _lastLng;
  String _lastName = '';
  final fm.MapController _mapController = fm.MapController();
  // 近隣潮汐ポイント座標（ポイント名 -> (lat,lng)）
  final Map<String, Offset> _pointCoords = {};
  bool _pointsLoading = true;

  // 現在地表示（ブリンク）
  LatLng? _myPos;
  bool _blinkOn = true;
  Timer? _blinkTimer;
  StreamSubscription<Position>? _posSub;

  @override
  void initState() {
    super.initState();
    _prepare();
    _loadPointCoords();
    // Common の変更（堤防選択など）を監視して地図を更新
    Common.instance.addListener(_onCommonChanged);
    _initLocation();
    _startBlink();
  }

  void _onCommonChanged() {
    // 堤防選択が変わった可能性があるため再準備
    _prepare();
  }

  Future<void> _prepare() async {
    final name = Common.instance.selectedTeibouName;
    final lat = Common.instance.selectedTeibouLat;
    final lng = Common.instance.selectedTeibouLng;
    if (lat != 0.0 || lng != 0.0) {
      // 変更検知（緯度経度 or 名前）
      if (_lastLat != lat || _lastLng != lng || _lastName != name) {
        _center = LatLng(lat, lng);
        _lastLat = lat;
        _lastLng = lng;
        _lastName = name;
        await _loadMarkers(centerName: name, lat: lat, lng: lng, radiusKm: 30.0);
        // マップの中心も即時移動
        if (mounted && _center != null) {
          try {
            _mapController.move(_center!, _zoomForRadius(30.0) + 1.0);
          } catch (_) {}
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
            try {
              _mapController.move(_center!, _zoomForRadius(30.0) + 1.0);
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
    final rows = await SioDatabase().getAllTeibouWithPrefecture();
    final center = LatLng(lat, lng);
    _markers.add(
      fm.Marker(
        width: 180,
        height: 64,
        point: center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_pin, color: Colors.red, size: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1))],
              ),
              child: Text(
                centerName,
                style: const TextStyle(fontSize: 11, color: Colors.black),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );

    for (final r in rows) {
      final dlat = _toDouble(r['latitude']);
      final dlng = _toDouble(r['longitude']);
      final name = (r['port_name'] ?? '').toString();
      final int? prefId = r['todoufuken_id'] is int
          ? r['todoufuken_id'] as int
          : int.tryParse(r['todoufuken_id']?.toString() ?? '') ?? int.tryParse(r['pref_id_from_port']?.toString() ?? '');
      final int? portId = r['port_id'] is int
          ? r['port_id'] as int
          : int.tryParse(r['port_id']?.toString() ?? '');
      if (dlat == null || dlng == null) continue;
      final d = _distanceKm(lat, lng, dlat, dlng);
      if (d <= radiusKm && !(dlat == lat && dlng == lng)) {
        _markers.add(
          fm.Marker(
            width: 200,
            height: 60,
            point: LatLng(dlat, dlng),
            child: GestureDetector(
              onTap: () async {
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
                // マップも新しい中心へ移動
                setState(() {
                  _center = LatLng(dlat, dlng);
                });
                try { _mapController.move(_center!, _zoomForRadius(30.0) + 1.0); } catch (_) {}
                // マーカーを再構築
                await _loadMarkers(centerName: name, lat: dlat, lng: dlng, radiusKm: radiusKm);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_pin, color: Colors.blueAccent, size: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1))],
                    ),
                    child: Text(
                      '$name (${d.toStringAsFixed(1)}km)',
                      style: const TextStyle(fontSize: 10, color: Colors.black),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
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
          : fm.FlutterMap(
              options: fm.MapOptions(
                initialCenter: _center!,
                // 半径30km相当より1段ズームイン（約2倍拡大）
                initialZoom: _zoomForRadius(30.0) + 1.0,
                interactionOptions: const fm.InteractionOptions(flags: fm.InteractiveFlag.all),
              ),
              mapController: _mapController,
              children: [
                fm.TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'jp.bouzer.siowadou',
                  tileProvider: fm.NetworkTileProvider(),
                ),
                fm.MarkerLayer(markers: _buildAllMarkers()),
                const fm.RichAttributionWidget(
                  attributions: [
                    fm.TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
    );
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

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
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
      if (name.isEmpty) return {'yomi': '', 'isPort': false};
      final rows = await SioDatabase().getAllTeibouWithPrefecture();
      for (final r in rows) {
        final n = (r['port_name'] ?? '').toString();
        if (n == name) {
          final kubun = (r['kubun'] ?? '').toString();
          final isPort = kubun == '1' || kubun == '2' || kubun == '3' || kubun == '4' || kubun == '特3';
          String yomi = (r['j_yomi'] ?? '').toString();
          if (yomi.isEmpty) yomi = (r['furigana'] ?? '').toString();
          return {'yomi': yomi, 'isPort': isPort};
        }
      }
    } catch (_) {}
    return {'yomi': '', 'isPort': false};
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
                  MaterialPageRoute(builder: (_) => SetDatePage()),
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
                                          name,
                                          style: const TextStyle(fontSize: 24, color: Colors.white),
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

// (削除) 釣場環境 > 投稿一覧 タブは不要となったため実装も削除

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
