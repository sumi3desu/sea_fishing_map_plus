import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:sticky_headers/sticky_headers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'dart:convert';

import 'sio_database.dart';
import 'package:http/http.dart' as http;
import 'appconfig.dart';
import 'constants.dart';
import 'main.dart';
import 'common.dart';
import 'sio_info.dart';
import 'nearby_map_page.dart';
import 'package:geolocator/geolocator.dart';

class ListTeibouPage extends StatefulWidget {
  const ListTeibouPage({super.key});

  @override
  State<ListTeibouPage> createState() => _ListTeibouPageState();
}

class _ListTeibouPageState extends State<ListTeibouPage> {
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  final List<String> _regions = const [
    'お気に入り', '近くの釣場', '北海道', '東北', '関東', '中部', '近畿', '中国', '四国', '九州', '沖縄'
  ];
  int _selectedRegionIndex = 0;
  final Map<String, Set<int>> _regionPrefSet = {};
  final Map<int, String> _prefNameById = {};
  final Map<String, Offset> _pointCoords = {}; // 一覧ポイント名 -> (lat,lng)
  bool _pointsLoading = true;
  Set<int> _favoriteIds = <int>{};
  String? _selectedTeibouName;
  int? _selectedTeibouId;
  final Map<int, GlobalKey> _rowKeys = {};
  // 近くの釣場（検索結果）
  List<Map<String, dynamic>> _nearby = [];
  bool _nearbyLoading = false;
  String? _nearbyError;
  final Map<int, int> _nearbyNumberById = {}; // port_id -> 1..10
  final Map<int, int> _nearbyMetersById = {}; // port_id -> meters from current location
  double? _nearbyUserLat;
  double? _nearbyUserLng;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPointCoords();
    _loadSelection();
    _loadFavorites();
    // DB更新（設定画面での同期完了等）を検知して一覧を再読込
    SioDatabase().addListener(_onDbChanged);
    // 釣場詳細の地図などからの選択変更を反映
    Common.instance.addListener(_onCommonChangedJump);
  }

  void _onDbChanged() {
    if (!mounted) return;
    _load();
    _loadFavorites();
  }

  int _lastCenterTick = 0;
  void _onCommonChangedJump() async {
    if (!mounted) return;
    // 釣場詳細などで選択が更新された場合に、一覧側もスクロール＆選択
    final common = Common.instance;
    // タブ切替直後の再センタリング要求（地域切替は行わずスクロールのみ）
    if (_lastCenterTick != common.listCenterTick) {
      _lastCenterTick = common.listCenterTick;
      // 現在の選択を中央へスクロール
      int? targetId = _selectedTeibouId;
      if (targetId == null && _selectedTeibouName != null) {
        for (final r in _rows) {
          if ((r['port_name'] ?? '').toString() == _selectedTeibouName) {
            targetId = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
            break;
          }
        }
      }
      int attempts = 0;
      void _scrollOnly() {
        if (!mounted) return;
        if (targetId != null) {
          final key = _rowKeys[targetId!];
          final ctx = key?.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: 0.5,
            );
            return;
          }
        }
        attempts++;
        if (attempts < 15) {
          Future.delayed(const Duration(milliseconds: 80), _scrollOnly);
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollOnly());
    }

    if (common.shouldJumpPage) {
      if (_rows.isEmpty || _loading) {
        // データがまだの場合は少し待って再トライ
        Future.delayed(const Duration(milliseconds: 80), _onCommonChangedJump);
        return;
      }
      final selName = Common.instance.selectedTeibouName;
      final sLat = Common.instance.selectedTeibouLat;
      final sLng = Common.instance.selectedTeibouLng;
      int? selId;
      int? prefId;
      String? selResolvedName;
      // 0) 保存済みの選択IDがあれば最優先で採用
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedId = prefs.getInt('selected_teibou_id');
        final savedPref = prefs.getInt('selected_teibou_pref_id');
        if (savedId != null) {
          for (final r in _rows) {
            final rid = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
            if (rid == savedId) {
              selId = rid;
              prefId = savedPref ?? (r['todoufuken_id'] is int
                  ? r['todoufuken_id'] as int
                  : int.tryParse(r['todoufuken_id']?.toString() ?? '') ?? int.tryParse(r['pref_id_from_port']?.toString() ?? ''));
              selResolvedName = (r['port_name'] ?? '').toString();
              break;
            }
          }
        }
        // もしIDで行が見つからなくても、保存済みのprefがあれば地域だけ先に合わせる
        if (selId == null && savedPref != null) {
          prefId = savedPref;
        }
      } catch (_) {}
      // 1) 座標がある場合は最も近い行を採用（名前の重複対策）
      if (selId == null && (sLat != 0.0 || sLng != 0.0)) {
        double best = double.infinity;
        int? bestId;
        int? bestPref;
        String? bestName;
        const double deg2rad = 3.141592653589793 / 180.0;
        final rlat = sLat * deg2rad;
        for (final r in _rows) {
          final dlat = _toDouble(r['latitude']);
          final dlng = _toDouble(r['longitude']);
          if (dlat == null || dlng == null) continue;
          final d = _haversine(sLat, sLng, dlat, dlng, cosLat: rlat);
          if (d < best) {
            best = d;
            bestId = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
            bestPref = r['todoufuken_id'] is int
                ? r['todoufuken_id'] as int
                : int.tryParse(r['todoufuken_id']?.toString() ?? '') ?? int.tryParse(r['pref_id_from_port']?.toString() ?? '');
            bestName = (r['port_name'] ?? '').toString();
          }
        }
        selId = bestId;
        prefId = bestPref;
        selResolvedName = bestName ?? selName;
      }
      // 2) 座標が無ければ名前一致の最初を採用
      if (selId == null) {
        for (final r in _rows) {
          final name = (r['port_name'] ?? '').toString();
          if (name == selName) {
            selId = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
            prefId = r['todoufuken_id'] is int
                ? r['todoufuken_id'] as int
                : int.tryParse(r['todoufuken_id']?.toString() ?? '') ?? int.tryParse(r['pref_id_from_port']?.toString() ?? '');
            selResolvedName = name;
            break;
          }
        }
      }
      String? selRegion;
      if (prefId != null) {
        // 一覧の実データで構成された地域集合から逆引きして整合を取る
        selRegion = _regionNameForPrefId(prefId) ?? _regionByPrefId(prefId);
      }
      setState(() {
        if (selRegion != null) {
          final idx = _regions.indexOf(selRegion!);
          if (idx >= 0) _selectedRegionIndex = idx;
        }
        _selectedTeibouName = selResolvedName ?? selName;
        _selectedTeibouId = selId;
      });
      // ビルド完了を待ってからスクロール。必要なら複数回リトライ
      int attempts = 0;
      void _scroll() {
        if (!mounted) return;
        if (selId != null) {
          final key = _rowKeys[selId!];
          final ctx = key?.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
              alignment: 0.5,
            );
            common.shouldJumpPage = false;
            return;
          }
        }
        if (attempts == 0) {
          // 先に軽く先頭へ寄せてビルドを促す
          try {
            _scrollController.animateTo(
              _scrollController.position.minScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          } catch (_) {}
        }
        attempts++;
        if (attempts < 20) {
          Future.delayed(const Duration(milliseconds: 80), _scroll);
        } else {
          // 最終的にフラグを戻す（次機会に再ジャンプさせない）
          common.shouldJumpPage = false;
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _scroll());
    }
  }

  Future<void> _load() async {
    final db = SioDatabase();
    final rows = await db.getAllTeibouWithPrefecture();
    final prefs = await db.getTodoufukenAll();
    print('teibou rows: ${rows.length}');
    print('todoufuken rows: ${prefs.length}');
    
    final map = <String, Set<int>>{};
    _prefNameById.clear();
    for (final r in prefs) {
      // 地方名の正規化（末尾「地方」除去、複合表記の分岐）
      String chihou = (r['chihou_name'] ?? '').toString().trim();
      final id = r['todoufuken_id'] is int
          ? r['todoufuken_id'] as int
          : int.tryParse(r['todoufuken_id']?.toString() ?? '');
      if (id == null) continue;
      final name = (r['todoufuken_name'] ?? '').toString();
      if (name.isNotEmpty) _prefNameById[id] = name;
      // chihou_name が未提供の場合は都道府県IDから地方を推定
      if (chihou.isEmpty) {
        chihou = _regionByPrefId(id) ?? '';
      }
      if (chihou.endsWith('地方')) {
        chihou = chihou.substring(0, chihou.length - 2);
      }
      if (chihou == '九州・沖縄') {
        chihou = (id == 47) ? '沖縄' : '九州';
      }
      if (!_regions.contains(chihou)) {
        // 未知の表記は無視（フィルタ対象外）
        continue;
      }
      map.putIfAbsent(chihou, () => <int>{}).add(id);
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _regionPrefSet
        ..clear()
        ..addAll(map);
      _loading = false;
    });
    // 初期選択があればスクロール
    if (_selectedTeibouId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final key = _rowKeys[_selectedTeibouId!];
        if (key != null && key.currentContext != null) {
          Scrollable.ensureVisible(
            key.currentContext!,
            duration: const Duration(milliseconds: 300),
            alignment: 0.5,
          );
        }
      });
    }
  }

  // 都道府県IDからアプリのタブ表記の地方名へマッピング
  String? _regionByPrefId(int id) {
    if (id == 1) return '北海道';
    if (id >= 2 && id <= 7) return '東北';
    if (id >= 8 && id <= 14) return '関東';
    if (id >= 15 && id <= 23) return '中部';
    if (id >= 24 && id <= 30) return '近畿';
    if (id >= 31 && id <= 35) return '中国';
    if (id >= 36 && id <= 39) return '四国';
    if (id >= 40 && id <= 46) return '九州';
    if (id == 47) return '沖縄';
    return null;
  }

  // todoufuken テーブル由来の地方集合から逆引きして地方名を返す
  String? _regionNameForPrefId(int pid) {
    for (final entry in _regionPrefSet.entries) {
      if (entry.value.contains(pid)) return entry.key;
    }
    // 見つからない場合のフォールバック
    return _regionByPrefId(pid);
  }

  Future<void> _loadFavorites() async {
    Set<int> ids = <int>{};
    bool fetchedFromRemote = false;
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final resp = await http
          .post(
            Uri.parse('${AppConfig.instance.baseUrl}get_favorites.php'),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json, text/plain, */*',
            },
            body: {
              'user_id': info.userId.toString(),
              //'userId': info.userId.toString(),
            },
          )
          .timeout(kHttpTimeout);
      if (resp.statusCode == 200) {
        fetchedFromRemote = true;
        final dyn = jsonDecode(resp.body);
        List list;
        if (dyn is Map && dyn['data'] != null) {
          list = (dyn['data'] as List);
        } else if (dyn is List) {
          list = dyn;
        } else {
          list = const [];
        }
        for (final e in list) {
          int? id;
          if (e is int) {
            id = e;
          } else if (e is num) {
            id = e.toInt();
          } else if (e is String) {
            id = int.tryParse(e);
          } else if (e is Map) {
            final v = e['spot_id'] ?? e['spotId'] ?? e['port_id'] ?? e['portId'] ?? e['id'];
            if (v is int) id = v;
            else if (v is num) id = v.toInt();
            else if (v is String) id = int.tryParse(v);
          }
          if (id != null) ids.add(id);
        }
      }
    } catch (_) {}

    if (fetchedFromRemote) {
      // リモート取得に成功した場合はローカルDBも同期
      try {
        final existing = await SioDatabase().getFavoriteTeibouIds();
        for (final eid in existing) {
          if (!ids.contains(eid)) {
            await SioDatabase().removeFavoriteTeibou(eid);
          }
        }
        for (final nid in ids) {
          if (!existing.contains(nid)) {
            await SioDatabase().addFavoriteTeibou(nid);
          }
        }
      } catch (_) {}
    } else if (ids.isEmpty) {
      // フォールバック：ローカルDB
      ids = await SioDatabase().getFavoriteTeibouIds();
    }
    if (!mounted) return;
    setState(() {
      _favoriteIds = ids;
    });
  }

  Future<void> _loadSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('selected_teibou_id');
    final name = prefs.getString('selected_teibou_name');
    if (!mounted) return;
    setState(() {
      _selectedTeibouId = id;
      _selectedTeibouName = name;
    });
  }

  Future<void> _saveSelection({int? id, String? name}) async {
    final prefs = await SharedPreferences.getInstance();
    if (id != null) await prefs.setInt('selected_teibou_id', id);
    if (name != null) await prefs.setString('selected_teibou_name', name);
  }

  Future<void> _loadPointCoords() async {
    // Common.portFileData: [pointName, fileName]
    final pairs = Common.instance.portFileData;
    final map = <String, Offset>{};
    for (final row in pairs) {
      if (row.length < 2) continue;
      final name = row[0];
      final file = row[1];
      // 国内(01〜47)のみを対象。海外等(80〜)はアセット未登録のためスキップ
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
        // アセット未登録などで読み込み失敗した場合はスキップ
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

  @override
  void dispose() {
    _scrollController.dispose();
    SioDatabase().removeListener(_onDbChanged);
    try { Common.instance.removeListener(_onCommonChangedJump); } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 地方でフィルタ
    final selectedRegion = _regions[_selectedRegionIndex];
    List<Map<String, dynamic>> filtered;
    if (selectedRegion == 'お気に入り') {
      filtered = _rows.where((r) {
        final id = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
        return id != null && _favoriteIds.contains(id);
      }).toList();
    } else if (selectedRegion == '近くの釣場') {
      filtered = List<Map<String, dynamic>>.from(_nearby); // 検索順（距離昇順）のまま
    } else {
      // todoufuken テーブル由来の地方→都道府県ID集合で厳密にフィルタ
      final allowed = _regionPrefSet[selectedRegion] ?? <int>{};
      filtered = _rows.where((r) {
        int? pid = r['todoufuken_id'] is int
            ? r['todoufuken_id'] as int
            : int.tryParse(r['todoufuken_id']?.toString() ?? '');
        pid ??= int.tryParse(r['pref_id_from_port']?.toString() ?? '');
        return pid != null && allowed.contains(pid);
      }).toList();
    }

    // 既に都道府県ID順、読み順で並んでいる想定（SQLのORDER BY）。
    // 表示のために都道府県ごとにグループ化。
    final List<_PrefGroup> groups = [];
    if (selectedRegion == '近くの釣場') {
      // グループ化せず、検索結果をそのまま一括で表示
      groups.add(_PrefGroup(name: '検索結果', id: null, rows: filtered));
    } else {
      String? currentPref;
      List<Map<String, dynamic>> currentList = [];
      int? currentPrefId;

      for (final r in filtered) {
        String pref = (r['todoufuken_name'] ?? '').toString();
        int? prefId = r['todoufuken_id'] is int
            ? r['todoufuken_id'] as int
            : int.tryParse(r['todoufuken_id']?.toString() ?? '');
        prefId ??= int.tryParse(r['pref_id_from_port']?.toString() ?? '');
        if (pref.isEmpty) {
          // 名称が取れない場合は都道府県IDから名称を復元、なければ地方名(推定)
          if (prefId != null && _prefNameById.containsKey(prefId)) {
            pref = _prefNameById[prefId]!;
          } else {
            final region = prefId != null ? _regionByPrefId(prefId) : null;
            pref = region != null ? '$region（推定）' : '未分類';
          }
        }
        if (currentPref == null) {
          currentPref = pref;
          currentPrefId = prefId;
        }
        if (pref != currentPref) {
          groups.add(_PrefGroup(name: currentPref!, id: currentPrefId, rows: currentList));
          currentPref = pref;
          currentPrefId = prefId;
          currentList = [];
        }
        currentList.add(r);
      }
      if (currentPref != null) {
        groups.add(_PrefGroup(name: currentPref!, id: currentPrefId, rows: currentList));
      }
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.list_alt, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _buildListTitle(),
                style: const TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildRegionTabs(),
          if (selectedRegion == '近くの釣場') ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: _nearbyLoading ? null : _onSearchNearby,
                  icon: const Icon(Icons.search),
                  label: const Text('検索'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
            ),
          ],
          const Divider(height: 1),
          Expanded(
            child: groups.isEmpty
                ? Center(
                    child: Text(
                      selectedRegion == '近くの釣場'
                          ? (_nearbyLoading
                              ? '検索中...'
                              : (_nearbyError ?? '「検索」を押して現在地から近い釣り場を表示'))
                          : 'この地方のデータがありません',
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final g = groups[index];
                      if (selectedRegion == '近くの釣場') {
                        // ヘッダー無しでそのまま並べる（近い順）
                        return Column(children: g.rows.map((row) => _buildRow(row)).toList());
                      } else {
                        return StickyHeader(
                          header: Container(
                            height: 50,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: Alignment.centerLeft,
                            color: Colors.grey.shade300,
                            child: Text(
                              g.name,
                              style: const TextStyle(fontSize: 18, color: Colors.black),
                            ),
                          ),
                          content: Column(
                            children: g.rows.map((row) => _buildRow(row)).toList(),
                          ),
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSearchNearby() async {
    setState(() {
      _nearbyLoading = true;
      _nearbyError = null;
      _nearby = [];
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _nearbyError = '位置情報サービスが無効です';
          _nearbyLoading = false;
        });
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _nearbyError = '位置情報の許可が必要です';
            _nearbyLoading = false;
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _nearbyError = '位置情報の許可が永続的に拒否されています';
          _nearbyLoading = false;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final clat = pos.latitude;
      final clng = pos.longitude;
      _nearbyUserLat = clat;
      _nearbyUserLng = clng;
      // 全堤防から距離計算し、近い順に上位10件
      final List<Map<String, dynamic>> candidates = [];
      final List<double> distances = [];
      final List<int> metersList = [];
      for (final r in _rows) {
        final lat = _toDouble(r['latitude']);
        final lng = _toDouble(r['longitude']);
        if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) continue;
        final d = _haversine(clat, clng, lat, lng);
        final m = _distanceMeters(clat, clng, lat, lng);
        candidates.add(r);
        distances.add(d);
        metersList.add(m);
      }
      // インデックスでソート（距離昇順）
      final idx = List.generate(candidates.length, (i) => i);
      idx.sort((a, b) => distances[a].compareTo(distances[b]));
      final top = idx.take(10).map((i) => candidates[i]).toList();
      // 近さの順位（1..10）を port_id に紐付け
      _nearbyNumberById.clear();
      _nearbyMetersById.clear();
      for (int i = 0; i < top.length; i++) {
        final pid = top[i]['port_id'] is int ? top[i]['port_id'] as int : int.tryParse(top[i]['port_id']?.toString() ?? '');
        if (pid != null) _nearbyNumberById[pid] = i + 1;
        if (pid != null) _nearbyMetersById[pid] = metersList[idx[i]];
      }
      setState(() {
        _nearby = top;
        _nearbyLoading = false;
      });
    } catch (e) {
      setState(() {
        _nearbyError = '検索中にエラーが発生しました';
        _nearbyLoading = false;
      });
    }
  }

  String _buildListTitle() {
    final base = '釣場一覧';
    final spot = _selectedTeibouName ?? '';
    if (spot.isEmpty) return base;
    // 都道府県名の推定
    int pid = Common.instance.selectedTeibouPrefId;
    if (pid == 0) {
      // まずは ID で引く
      if (_selectedTeibouId != null) {
        for (final r in _rows) {
          final rid = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
          if (rid == _selectedTeibouId) {
            pid = r['todoufuken_id'] is int
                ? r['todoufuken_id'] as int
                : int.tryParse(r['todoufuken_id']?.toString() ?? '') ?? int.tryParse(r['pref_id_from_port']?.toString() ?? '') ?? 0;
            break;
          }
        }
      }
      // 次に名前で引く
      if (pid == 0) {
        for (final r in _rows) {
          final n = (r['port_name'] ?? '').toString();
          if (n == spot) {
            pid = r['todoufuken_id'] is int
                ? r['todoufuken_id'] as int
                : int.tryParse(r['todoufuken_id']?.toString() ?? '') ?? int.tryParse(r['pref_id_from_port']?.toString() ?? '') ?? 0;
            break;
          }
        }
      }
    }
    String pref = '';
    if (pid != 0) {
      pref = _prefNameById[pid] ?? '';
    }
    final head = pref.isNotEmpty ? '$pref $spot' : spot;
    return '$base[$head]';
  }

  Widget _buildRegionTabs() {
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: List.generate(_regions.length, (i) {
            final selected = i == _selectedRegionIndex;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: ChoiceChip(
                label: Text(_regions[i]),
                selected: selected,
                onSelected: (v) {
                  if (!v) return;
                  setState(() {
                    _selectedRegionIndex = i;
                  });
                },
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> row) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final prefName = (row['todoufuken_name'] ?? '').toString();
    final int? prefIdRow = row['todoufuken_id'] is int
        ? row['todoufuken_id'] as int
        : int.tryParse(row['todoufuken_id']?.toString() ?? '') ?? int.tryParse(row['pref_id_from_port']?.toString() ?? '');
    final portName = (row['port_name'] ?? '').toString();
    final yomi = (row['j_yomi'] ?? '').toString();
    final portId = row['port_id'] is int ? row['port_id'] as int : int.tryParse(row['port_id']?.toString() ?? '');
    String title = portName;
    // 近くの釣場タブでは順位番号（①〜⑩）を付与
    if (_regions[_selectedRegionIndex] == '近くの釣場' && portId != null) {
      final n = _nearbyNumberById[portId];
      if (n != null) {
        title = '${_circledNum(n)} $title';
      }
    }
    final kubun = (row['kubun'] ?? '').toString();
    final isPort = kubun == '1' || kubun == '2' || kubun == '3' || kubun == '4' || kubun == '特3';
    final lat = _toDouble(row['latitude']);
    final lng = _toDouble(row['longitude']);
    final hasPosition = lat != null && lng != null && (lat != 0.0 || lng != 0.0);
    final isFav = portId != null && _favoriteIds.contains(portId);
    final isSelected = portId != null && _selectedTeibouId == portId;
    String? nearest;
    int? distanceMeters;
    final bool isNearbyTab = (_regions[_selectedRegionIndex] == '近くの釣場');
    if (isNearbyTab) {
      if (portId != null) distanceMeters = _nearbyMetersById[portId];
    } else if (hasPosition && !_pointsLoading && _pointCoords.isNotEmpty) {
      nearest = _nearestPointName(lat!, lng!);
      if (nearest != null) {
        final p = _pointCoords[nearest];
        if (p != null) {
          distanceMeters = _distanceMeters(lat!, lng!, p.dx, p.dy);
        }
      }
    }

    final onOpenMap = () async {
        if (!hasPosition) {
          if (!mounted) return;
          messenger?.showSnackBar(const SnackBar(content: Text('位置情報がありません')));
          return;
        }

        if (Common.instance.mapKind == MapType.googleMaps.index) {
          await Common.instance.openGoogleMaps(lat!, lng!);
        } else if (Common.instance.mapKind == MapType.appleMaps.index) {
          await Common.instance.openAppleMaps(lat!, lng!);
        } else {
          if (!mounted) return;
          messenger?.showSnackBar(const SnackBar(content: Text('設定から地図アプリを選択してください')));
        }
      };

    return Slidable(
      key: ValueKey('teibou_${row['port_id']}'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.40,
        children: [
          CustomSlidableAction(
            onPressed: (c) async {
              if (portId == null) return;
              if (isFav) {
                await SioDatabase().removeFavoriteTeibou(portId);
                _favoriteIds.remove(portId);
                // リモートも削除
                try {
                  final info = await loadUserInfo() ?? await getOrInitUserInfo();
                  final url = '${AppConfig.instance.baseUrl}regist_favorite.php';
                  final resp = await http
                      .post(
                        Uri.parse(url),
                        headers: {
                          'Content-Type': 'application/x-www-form-urlencoded',
                          'Accept': 'application/json, text/plain, */*',
                        },
                        body: {
                          'user_id': info.userId.toString(),
                          'spot_id': portId.toString(),
                          'action': 'delete',
                        },
                      )
                      .timeout(kHttpTimeout);
                  if (resp.statusCode == 200) {
                    messenger?.clearSnackBars();
                    messenger?.showSnackBar(SnackBar(content: Text('お気に入り解除: $portName')));
                  } else {
                    messenger?.clearSnackBars();
                    messenger?.showSnackBar(SnackBar(content: Text('お気に入り解除の同期に失敗しました（${resp.statusCode}）'), duration: const Duration(seconds: 3)));
                  }
                } catch (_) {
                  messenger?.clearSnackBars();
                  messenger?.showSnackBar(const SnackBar(content: Text('お気に入り解除の同期中にエラーが発生しました（ローカル保存済み）'), duration: Duration(seconds: 3)));
                }
              } else {
                await SioDatabase().addFavoriteTeibou(portId);
                _favoriteIds.add(portId);
                // リモートへも登録（失敗は無視）
                try {
                  final info = await loadUserInfo() ?? await getOrInitUserInfo();
                  final uri = Uri.parse('${AppConfig.instance.baseUrl}regist_favorite.php');
                  final primaryUrl = '${AppConfig.instance.baseUrl}regist_favorite.php';
                  final resp = await http
                      .post(
                        Uri.parse(primaryUrl),
                        headers: {
                          'Content-Type': 'application/x-www-form-urlencoded',
                          'Accept': 'application/json, text/plain, */*',
                        },
                        // サーバ側の受け取り名のゆらぎに備えて両形式を同梱
                        body: {
                          'user_id': info.userId.toString(),
                          'spot_id': portId.toString(),
                          'action': 'enter',
                        },
                      )
                      .timeout(kHttpTimeout);
                  if (resp.statusCode == 200) {
                    messenger?.clearSnackBars();
                    messenger?.showSnackBar(SnackBar(content: Text('お気に入り登録: $portName')));
                  } else {
                    messenger?.clearSnackBars();
                    messenger?.showSnackBar(SnackBar(content: Text('お気に入りの同期に失敗しました（${resp.statusCode}）'), duration: const Duration(seconds: 3)));
                  }
                } catch (e) {
                  messenger?.clearSnackBars();
                  messenger?.showSnackBar(const SnackBar(content: Text('お気に入りの同期中にエラーが発生しました（ローカル保存済み）'), duration: Duration(seconds: 3)));
                }
              }
              if (mounted) setState(() {});
            },
            backgroundColor: Colors.amber.shade50,
            child: Icon(
              Icons.bookmark,
              color: isFav ? Colors.amber : Colors.amber.shade300,
              size: 24,
            ),
          ),
          CustomSlidableAction(
            onPressed: (c) async {
              if (!hasPosition) {
                if (!mounted) return;
                messenger?.showSnackBar(const SnackBar(content: Text('位置情報がありません')));
                return;
              }
          // 地図表示
          final bool isNearbyTab = (_regions[_selectedRegionIndex] == '近くの釣場');
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) {
                if (isNearbyTab && _nearby.isNotEmpty) {
                  // 検索した10件をそのまま地図へ（ハイライトは指定釣り場）
                  final pts = _nearby.map((r) {
                    final id = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
                    final name = (r['port_name'] ?? '').toString();
                    final dlat = _toDouble(r['latitude']) ?? 0.0;
                    final dlng = _toDouble(r['longitude']) ?? 0.0;
                    return {'id': id, 'name': name, 'lat': dlat, 'lng': dlng};
                  }).toList();
                  return NearbyMapPage(points: pts, highlightId: portId);
                }
                // 既存の近隣検索マップ（中心＋半径）
                return NearbyMapPage(
                  centerLat: lat!,
                  centerLng: lng!,
                  centerName: portName,
                  radiusKm: 30.0,
                );
              },
            ),
          );
          if (result is Map && result['id'] != null) {
            final selId = (result['id'] is int) ? result['id'] as int : int.tryParse(result['id'].toString());
            final selName = (result['name'] ?? '').toString();
            final selLat = result['lat'] is double ? result['lat'] as double : _toDouble(result['lat']);
            final selLng = result['lng'] is double ? result['lng'] as double : _toDouble(result['lng']);
            if (selId != null) {
              // 選択堤防の地方タブへ切替
              String? selRegion;
              int? pid;
              for (final r in _rows) {
                final rid = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
                if (rid == selId) {
                  pid = r['todoufuken_id'] is int
                      ? r['todoufuken_id'] as int
                      : int.tryParse(r['todoufuken_id']?.toString() ?? '');
                  pid ??= int.tryParse(r['pref_id_from_port']?.toString() ?? '');
                  if (pid != null) {
                    selRegion = _regionNameForPrefId(pid);
                  }
                  break;
                }
              }
              final regionIdx = (selRegion != null) ? _regions.indexOf(selRegion!) : -1;
              setState(() {
                if (regionIdx >= 0) _selectedRegionIndex = regionIdx;
                _selectedTeibouId = selId;
                _selectedTeibouName = selName.isNotEmpty ? selName : _selectedTeibouName;
              });
              // 潮汐ポイント更新（最寄りに切り替え）
              if (selLat != null && selLng != null && !_pointsLoading && _pointCoords.isNotEmpty) {
                final np = _nearestPointName(selLat, selLng);
                if (np != null) {
                  Common.instance.tidePoint = np;
                  Common.instance.savePoint(np);
                  Common.instance.saveSelectedTeibou(_selectedTeibouName ?? selName, np, lat: selLat, lng: selLng, prefId: pid);
                  // 一覧内操作では shouldJumpPage を立てない（他タブ用のジャンプフラグは地図側のみ）
                  Common.instance.notify();
                }
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final key = _rowKeys[selId];
                if (key != null && key.currentContext != null) {
                  Scrollable.ensureVisible(
                    key.currentContext!,
                    duration: const Duration(milliseconds: 300),
                    alignment: 0.5,
                  );
                }
              });
            }
          }
            },
            backgroundColor: hasPosition ? Colors.orange.shade100 : Colors.grey.shade400,
            child: Icon(
              Icons.location_pin,
              color: hasPosition ? Colors.orange : Colors.white.withAlpha(64),
              size: 28,
            ),
          ),
          CustomSlidableAction(
            onPressed: (context) async => await onOpenMap(),
            backgroundColor: hasPosition ? Colors.lightBlue.shade100 : Colors.grey.shade400,
            child: Icon(
              Icons.directions_car,
              color: hasPosition ? Colors.blueAccent : Colors.white.withAlpha(64),
              size: 28,
            ),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTeibouName = portName;
            _selectedTeibouId = portId;
          });
          _saveSelection(id: portId, name: portName);
          if (hasPosition && !_pointsLoading && _pointCoords.isNotEmpty) {
            final np = _nearestPointName(lat!, lng!);
            if (np != null) {
              // 即時にCommonへ反映し、永続化
              Common.instance.tidePoint = np;
              Common.instance.savePoint(np);
              Common.instance.saveSelectedTeibou(portName, np, lat: lat, lng: lng, prefId: prefIdRow);
              // 一覧内での選択では shouldJumpPage は立てない
              Common.instance.notify();
            }
          }
        },
        child: Container(
          key: (portId != null) ? _rowKeys.putIfAbsent(portId, () => GlobalKey()) : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: isSelected
              ? BoxDecoration(
                  color: Colors.transparent,
                  border: Border.all(color: Colors.black, width: 2.0),
                )
              : BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
          child: Row(
            children: [
            SizedBox(
              width: 80,
              child: isPort
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        Icons.anchor,
                        color: Colors.blue.shade600,
                        size: 18,
                      ),
                    )
                  : Text(
                      prefName,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
              const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.red : Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (yomi.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        yomi,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
              const SizedBox(width: 8),
              if (!hasPosition && !isNearbyTab)
                Text(
                  '位置なし',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              if (isNearbyTab)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (hasPosition)
                      Text(
                        '${Common.instance.roundTo5Digits(lat!)} , ${Common.instance.roundTo5Digits(lng!)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      )
                    else
                      Text(
                        '位置なし',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    Text(
                      distanceMeters != null ? '直線距離: ${distanceMeters}m' : '直線距離: -',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                )
              else if (hasPosition)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${Common.instance.roundTo5Digits(lat!)} , ${Common.instance.roundTo5Digits(lng!)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
          ],
        ),
      ),
      ),
    );
  }

  String _circledNum(int n) {
    const list = ['①','②','③','④','⑤','⑥','⑦','⑧','⑨','⑩'];
    if (n >= 1 && n <= 10) return list[n - 1];
    return n.toString();
  }

  String? _nearestPointName(double lat, double lng) {
    double best = double.infinity;
    String? bestName;
    final rlat = lat * 3.141592653589793 / 180.0;
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
    // 距離比較用。地球半径は省略し、相対比較できる値にする
    const double deg2rad = 3.141592653589793 / 180.0;
    final dLat = (lat2 - lat1) * deg2rad;
    final dLon = (lon2 - lon1) * deg2rad;
    final sLat = math.sin(dLat / 2);
    final sLon = math.sin(dLon / 2);
    final a = sLat * sLat + math.cos(lat1 * deg2rad) * math.cos(lat2 * deg2rad) * sLon * sLon;
    return a; // 半径や2*asinは省略（比較のみ）
  }

  int _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000.0; // meters
    const double deg2rad = 3.141592653589793 / 180.0;
    final dLat = (lat2 - lat1) * deg2rad;
    final dLon = (lon2 - lon1) * deg2rad;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * deg2rad) * math.cos(lat2 * deg2rad) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return (R * c).round();
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

class _PrefGroup {
  final String name;
  final int? id;
  final List<Map<String, dynamic>> rows;
  _PrefGroup({required this.name, required this.id, required this.rows});
}
