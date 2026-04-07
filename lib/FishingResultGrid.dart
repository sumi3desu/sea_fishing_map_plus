import 'package:flutter/material.dart';
import 'appconfig.dart';
import 'constants.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'post_detail_page.dart';
import 'sio_database.dart';
import 'sync_service.dart';
import 'main.dart';
import 'common.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class FishingResultGrid extends StatefulWidget {
  const FishingResultGrid({super.key});

  @override
  State<FishingResultGrid> createState() => _FishingResultGridState();
}

class _FishingResultGridState extends State<FishingResultGrid> {
  final List<_PostGridItem> _items = [];
  final ScrollController _sc = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  final Map<int, String> _prefNameById = {};
  final Map<int, String> _spotNameById = {};
  bool _isAdmin = false;
  bool _metaReady = false; // 都道府県/釣場名とadminの準備完了
  final Map<int, String> _imgTsByPost = {}; // キャッシュバスター（編集後の差し替え用）

  @override
  void initState() {
    super.initState();
    _initMeta();
    _loadImageTsMap();
    _loadFirst();
    _sc.addListener(() {
      if (_sc.position.pixels >= _sc.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  Future<void> _initMeta() async {
    await _ensurePrefMap();
    await _checkAdmin();
    if (mounted) setState(() => _metaReady = true);
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  Future<List<_PostGridItem>> _fetch({required int page}) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final uri = Uri.parse('${AppConfig.instance.baseUrl}get_post_list.php?ts=$ts');
      final body = <String, String>{
        'get_kind': '1', // 釣果
        'page': page.toString(),
        'page_size': kPostPageSize.toString(),
        'ts': ts.toString(),
      };
      final resp = await http
          .post(uri, body: body, headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'})
          .timeout(kHttpTimeout);
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      List rows;
      if (data is Map && data['status'] == 'success') {
        rows = (data['rows'] as List?) ?? [];
      } else if (data is List) {
        rows = data;
      } else {
        return [];
      }
      final list = rows.map((e) => _PostGridItem.fromJson(e as Map<String, dynamic>, AppConfig.instance.baseUrl)).toList();
      // 画像ありのみ
      return list.where((e) => (e.thumbUrl ?? e.imageUrl) != null).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadFirst() async {
    if (!mounted) return;
    setState(() {
      _items.clear();
      _page = 1;
      _hasMore = true;
      _loading = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    if (!mounted) return;
    setState(() => _loading = true);
    final rows = await _fetch(page: _page);
    if (!mounted) return;
    setState(() {
      _items.addAll(rows);
      _hasMore = rows.length >= kPostPageSize;
      _page += 1;
      _loading = false;
    });
  }

  Future<void> _ensurePrefMap() async {
    try {
      final db = await SioDatabase().database;
      var rows = await db.query('todoufuken');
      // 釣り場名のためのテーブルもチェック
      var teibou = await db.query('teibou');
      // 初回起動などで未同期の場合はサーバーと同期してから再取得
      if (rows.isEmpty || teibou.isEmpty) {
        try {
          final info = await loadUserInfo();
          final uid = info?.userId ?? 0;
          await SioSyncService().syncFishingData(userId: uid, force: true);
        } catch (_) {}
        rows = await db.query('todoufuken');
        teibou = await db.query('teibou');
      }
      for (final r in rows) {
        final idVal = r['todoufuken_id'];
        final nameVal = r['todoufuken_name'];
        final id = (idVal is int) ? idVal : int.tryParse(idVal?.toString() ?? '');
        final name = nameVal?.toString();
        if (id != null && name != null && name.isNotEmpty) {
          _prefNameById[id] = name;
        }
      }
      // 釣り場名（port_id -> port_name）も用意
      if (teibou.isEmpty) {
        try {
          teibou = await SioDatabase().getAllTeibouWithPrefecture();
        } catch (_) {}
      }
      for (final r in teibou) {
        final id = int.tryParse(r['port_id']?.toString() ?? '');
        final name = (r['port_name'] ?? '').toString();
        if (id != null && name.isNotEmpty) _spotNameById[id] = name;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _checkAdmin() async {
    try {
      final info = await loadUserInfo();
      if (info != null) {
        var role = (info.role ?? '').toLowerCase();
        if (role != 'admin') {
          try {
            final refreshed = await getUserInfoFromServer(uuid: info.uuid, email: null);
            role = (refreshed.role ?? role).toLowerCase();
            // 保存しておく（他画面でも反映）
            final updated = UserInfo(
              userId: refreshed.userId,
              email: refreshed.email,
              uuid: info.uuid,
              status: refreshed.status,
              createdAt: refreshed.createdAt,
              refreshToken: info.refreshToken,
              nickName: refreshed.nickName ?? info.nickName,
              reportsBlocked: info.reportsBlocked,
              reportsBlockedUntil: info.reportsBlockedUntil,
              reportsBlockedReason: info.reportsBlockedReason,
              role: role,
              canReport: info.canReport,
              photoUrl: info.photoUrl,
              photoVersion: info.photoVersion,
            );
            await saveUserInfo(updated);
          } catch (_) {}
        }
        if (role == 'admin' && mounted) setState(() => _isAdmin = true);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('釣果'),
        backgroundColor: AppConfig.instance.appBarBackgroundColor,
        foregroundColor: AppConfig.instance.appBarForegroundColor,
        toolbarHeight: 0,
      ),
      body: Column(
        children: [
          Container(
            height: kToolbarHeight,
            color: AppConfig.instance.appBarBackgroundColor,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🐟', style: TextStyle(fontSize: 20, color: AppConfig.instance.appBarForegroundColor)),
                  const SizedBox(width: 8),
                  Text(
                    '釣果',
                    style: TextStyle(
                      color: AppConfig.instance.appBarForegroundColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadFirst,
              child: !_metaReady
                  ? const Center(child: CircularProgressIndicator())
                  : Builder(builder: (context) {
                final width = MediaQuery.of(context).size.width;
                const double pad = 8;
                const double gap = 4;
                final double cell = (width - pad * 2 - gap * 2) / 3.0;
                // グループ分割（パターン2..4のみを使用。同一パターンは連続回避）
                final groups = <_MosaicGroup>[];
                int i = 0;
                int prev = 0;
                int? forceNext; // 2/3 の後は 4 を強制
                final rng = math.Random(_items.length + _page);
                while (i < _items.length) {
                  final remain = _items.length - i;
                  int pattern;
                  // 最初のグループはパターン2（大1枚＋右に小2枚の縦並び）。残数不足なら4にフォールバック。
                  if (i == 0) {
                    pattern = (remain >= 3) ? 2 : 4;
                  } else if (forceNext != null) {
                    pattern = forceNext!;
                    forceNext = null;
                  } else {
                    // 2,3は3件必要。4は1..3件。
                    final viable = <int>[];
                    if (remain >= 3) {
                      viable.addAll([2, 3, 4]);
                    } else {
                      viable.addAll([4]);
                    }
                    // 直前パターン除外
                    final candidates = viable.where((p) => p != prev).toList();
                    if (candidates.isEmpty) {
                      // どうしても連続回避できない場合は成立するものを選択
                      pattern = 4;
                    } else {
                      pattern = candidates[rng.nextInt(candidates.length)];
                      // 2/3は残数が3件必要。残数不足なら4にフォールバック
                      if ((pattern == 2 || pattern == 3) && remain < 3) {
                        pattern = 4;
                      }
                    }
                  }
                  final need = math.min(3, remain);
                  final slice = _items.sublist(i, i + need);
                  groups.add(_MosaicGroup(pattern: pattern, items: slice));
                  i += need;
                  if ((pattern == 2 || pattern == 3) && i < _items.length) {
                    forceNext = 4; // 次は横3個
                    prev = 4; // 連続回避の基準も4に設定
                  } else {
                    prev = pattern;
                  }
                }
                return ListView.builder(
                  controller: _sc,
                  padding: const EdgeInsets.all(pad),
                  itemCount: groups.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, gi) {
                    if (gi >= groups.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final g = groups[gi];
                    return _buildGroup(g, cell, gap);
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostGridItem {
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
  final String baseUrl;
  _PostGridItem({
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
    required this.baseUrl,
  });
  String? get imageUrl {
    if (imagePath == null) return null;
    final rel = imagePath!;
    if (rel.startsWith('http')) return rel;
    return baseUrl + 'post_images/' + rel;
  }
  String? get thumbUrl {
    if (thumbPath == null) return null;
    final rel = thumbPath!;
    if (rel.startsWith('http')) return rel;
    return baseUrl + 'post_images/' + rel;
  }
  factory _PostGridItem.fromJson(Map<String, dynamic> j, String baseUrl) {
    int? toInt(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '');
    String? s(dynamic v) => v?.toString();
    return _PostGridItem(
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
      baseUrl: baseUrl,
    );
  }
}

class _MosaicGroup {
  final int pattern; // 2..4
  final List<_PostGridItem> items;
  _MosaicGroup({required this.pattern, required this.items});
}

extension _MosaicBuilders on _FishingResultGridState {
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
      // 既存マップを読み取り
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
  Widget _buildTile(_PostGridItem it, double left, double top, double w, double h) {
    final String? rawUrl = it.thumbUrl ?? it.imageUrl;
    final url = (rawUrl != null) ? _withTs(rawUrl, it.postId) : null;
    String topLabel = '';
    if (it.spotId != null) {
      final s = it.spotId!.toString();
      if (s.length >= 2) {
        final pid = int.tryParse(s.substring(0, 2));
        if (pid != null && _prefNameById.containsKey(pid)) topLabel = _prefNameById[pid]!;
      }
    }
    final bottomLabel = it.nickName ?? '';
    final bool canShowSpotName = (ambiguous_plevel == 0) || _isAdmin;
    final String? spotName = (it.spotId != null) ? _spotNameById[it.spotId] : null;
    final String combinedTopLabel = () {
      String s = '';
      if (topLabel.isNotEmpty) s = topLabel;
      if (canShowSpotName && spotName != null && spotName.isNotEmpty) {
        s = s.isEmpty ? spotName! : '$s $spotName';
      }
      return s;
    }();
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: InkWell(
        onTap: () async {
          if (ambiguous_plevel == 0 && it.spotId != null) {
            // 釣り場が曖昧でない場合、該当スポットを選択して釣場詳細へ
            final ok = await Common.instance.selectTeibouById(it.spotId!);
            if (ok) {
              if (!mounted) return;
              Common.instance.requestNavigateToTidePage();
              return;
            }
            // もし失敗した場合は従来の詳細表示にフォールバック
          }
          final String? detailUrlRaw = it.imageUrl ?? it.thumbUrl;
          final String? detailUrl = (detailUrlRaw != null) ? _withTs(detailUrlRaw, it.postId) : null;
          final updated = await Navigator.push(
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
                  spotId: it.spotId,
                  showNearbyButton: true,
                ),
              ),
            ),
          );
          if (!mounted) return;
          if (updated == true && it.postId != null) {
            final ts = DateTime.now().millisecondsSinceEpoch.toString();
            setState(() {
              _imgTsByPost[it.postId!] = ts;
            });
            _saveImageTs(it.postId!, ts);
          } else if (updated is Map) {
            final u = (updated['updated'] == true);
            final cleared = (updated['clearedImage'] == true);
            final pid = updated['postId'] is int ? updated['postId'] as int : (updated['postId'] is String ? int.tryParse(updated['postId']) : null);
            if (u && cleared && pid != null) {
              // 画像が消された場合はグリッドからも項目を外す
              setState(() {
                _items.removeWhere((e) => e.postId == pid);
                _imgTsByPost.remove(pid);
              });
              // 永続側からも削除
              _removeImageTs(pid);
            } else if (u && pid != null) {
              final ts = DateTime.now().millisecondsSinceEpoch.toString();
              setState(() { _imgTsByPost[pid] = ts; });
              _saveImageTs(pid, ts);
            }
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              url != null ? Image.network(url, fit: BoxFit.cover) : const ColoredBox(color: Colors.black12),
              // 上部ラベル行（都道府県 + 釣り場名を半角スペース区切りで1つのラベルに）
              if (combinedTopLabel.isNotEmpty)
                Positioned(
                  top: 4,
                  left: 4,
                  right: 4,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        combinedTopLabel,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              if (bottomLabel.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                    color: Colors.black45,
                    child: Text(bottomLabel, style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroup(_MosaicGroup g, double cell, double gap) {
    final tiles = <Widget>[];
    double height;
    switch (g.pattern) {
      case 2:
        height = cell * 2 + gap;
        tiles.add(_buildTile(g.items[0], 0, 0, cell * 2 + gap, height));
        tiles.add(_buildTile(g.items.length > 1 ? g.items[1] : g.items[0], cell * 2 + gap * 2, 0, cell, cell));
        if (g.items.length > 2) {
          tiles.add(_buildTile(g.items[2], cell * 2 + gap * 2, cell + gap, cell, cell));
        }
        break;
      case 3:
        height = cell * 2 + gap;
        tiles.add(_buildTile(g.items[0], 0, 0, cell, cell));
        tiles.add(_buildTile(g.items.length > 1 ? g.items[1] : g.items[0], 0, cell + gap, cell, cell));
        tiles.add(_buildTile(g.items.length > 2 ? g.items[2] : g.items[0], cell + gap, 0, cell * 2 + gap, height));
        break;
      default:
        height = cell;
        for (var i = 0; i < g.items.length; i++) {
          final x = i * (cell + gap);
          tiles.add(_buildTile(g.items[i], x, 0, cell, cell));
        }
    }
    final totalWidth = cell * 3 + gap * 2;
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: SizedBox(
        width: totalWidth,
        height: height,
        child: Stack(children: tiles),
      ),
    );
  }
}
