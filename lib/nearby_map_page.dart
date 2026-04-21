import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'sio_database.dart';
import 'common.dart';
import 'dart:math' as math;

class NearbyMapPage extends StatefulWidget {
  const NearbyMapPage({
    super.key,
    this.points,
    this.centerLat,
    this.centerLng,
    this.centerName,
    this.radiusKm,
    this.highlightId,
  });
  final List<Map<String, dynamic>>? points; // {id?, name, lat, lng}
  final double? centerLat;
  final double? centerLng;
  final String? centerName;
  final double? radiusKm;
  final int? highlightId; // 指定があれば、そのIDを赤マーカーで強調

  @override
  State<NearbyMapPage> createState() => _NearbyMapPageState();
}

class _NearbyMapPageState extends State<NearbyMapPage> {
  final fm.MapController _controller = fm.MapController();
  List<Map<String, dynamic>> _pts = [];
  // 曖昧候補（近辺表示元の候補セット）。外接円はこの集合で算出する
  List<Map<String, dynamic>> _cands = [];
  int? _selectedId;
  bool _shifted = false;
  LatLng? _myPos;
  StreamSubscription<Position>? _posSub;
  bool _blinkOn = true;
  Timer? _blinkTimer;
  // 外接円（全ポイントを含む）
  LatLng? _circleCenter;
  double _circleRadiusM = 0.0;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.highlightId;
    _preparePoints();
    _initLocation();
    _startBlink();
  }

  Future<void> _preparePoints() async {
    if (widget.points != null && widget.points!.isNotEmpty) {
      // points は曖昧候補セット
      _cands = widget.points!;
      // 候補の重心
      double slat = 0.0, slng = 0.0;
      for (final p in _cands) {
        slat += (p['lat'] as num).toDouble();
        slng += (p['lng'] as num).toDouble();
      }
      final cLat = slat / _cands.length;
      final cLng = slng / _cands.length;

      // DBから全堤防を取得し、重心に近い順に最大100件まで取得（候補は重複除外して先頭に）
      final extras = <Map<String, dynamic>>[];
      try {
        final db = await SioDatabase().database;
        final rows = await db.query('teibou');
        // 既存ID集合
        final existingIds = <int>{};
        for (final e in _cands) {
          final id = e['id'] as int?;
          if (id != null) existingIds.add(id);
        }
        final tmp = <Map<String, dynamic>>[];
        for (final r in rows) {
          final id = int.tryParse(r['port_id']?.toString() ?? '');
          final name = (r['port_name'] ?? '').toString();
          final lat = (r['latitude'] as num).toDouble();
          final lng = (r['longitude'] as num).toDouble();
          final d = _dist(cLat, cLng, lat, lng);
          if (id != null && existingIds.contains(id)) continue; // 候補と重複は無視
          // 近接重複も軽く除外
          bool nearDup = false;
          for (final e in _cands) {
            final dl = _dist(
              lat,
              lng,
              (e['lat'] as num).toDouble(),
              (e['lng'] as num).toDouble(),
            );
            if (dl < 50.0) {
              nearDup = true;
              break;
            }
          }
          if (nearDup) continue;
          tmp.add({'id': id, 'name': name, 'lat': lat, 'lng': lng, 'd': d});
        }
        tmp.sort((a, b) => (a['d'] as double).compareTo(b['d'] as double));
        // 必要数だけ追加（合計100件を目標）
        final need = (100 - _cands.length).clamp(0, 100);
        extras.addAll(tmp.take(need));
      } catch (_) {}

      _pts = [..._cands, ...extras];
      _computeCircle();
      if (mounted) setState(() {});
      return;
    }
    // center+radius モード
    if (widget.centerLat != null && widget.centerLng != null) {
      try {
        final db = await SioDatabase().database;
        final rows = await db.query('teibou');
        final clat = widget.centerLat!;
        final clng = widget.centerLng!;
        final radiusM = (widget.radiusKm ?? 30.0) * 1000.0;
        final cand = <Map<String, dynamic>>[];
        for (final r in rows) {
          final id = int.tryParse(r['port_id']?.toString() ?? '');
          final name = (r['port_name'] ?? '').toString();
          final lat = (r['latitude'] as num).toDouble();
          final lng = (r['longitude'] as num).toDouble();
          final d = _dist(clat, clng, lat, lng);
          if (d <= radiusM) {
            cand.add({'id': id, 'name': name, 'lat': lat, 'lng': lng, 'd': d});
          }
        }
        cand.sort((a, b) => (a['d'] as double).compareTo(b['d'] as double));
        _pts = cand.take(100).toList();
      } catch (_) {}
      // 曖昧候補が無い場合は外接円を描画しない
      _circleCenter = null;
      _circleRadiusM = 0.0;
      if (mounted) setState(() {});
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

  void _fitBounds() {
    if (_pts.isEmpty) return;
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in _pts) {
      final lat = (p['lat'] as num).toDouble();
      final lng = (p['lng'] as num).toDouble();
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    final bounds = fm.LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
    final fit = fm.CameraFit.bounds(
      bounds: bounds,
      padding: const EdgeInsets.all(24),
    );
    _controller.fitCamera(fit);
  }

  @override
  Widget build(BuildContext context) {
    final markers = <fm.Marker>[];
    final list = _orderedPts();
    for (int i = 0; i < list.length; i++) {
      final p = list[i];
      markers.add(
        fm.Marker(
          point: LatLng(
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          ),
          width: 160,
          height: 60,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _selectPoint(p),
                child: Container(
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
                  child: Text(
                    (p['name'] ?? '').toString(),
                    style: const TextStyle(fontSize: 11, color: Colors.black),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _selectPoint(p),
                child: Icon(
                  Icons.location_on,
                  color:
                      ((p['id'] ?? -1) == _selectedId)
                          ? Colors.red
                          : Colors.blue,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_myPos != null) {
      markers.add(
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('釣れたエリア'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // タイトル下の説明エリア（AppBarと同じ高さ・白背景）
          Container(
            height: kToolbarHeight,
            width: double.infinity,
            color: Colors.white,
            alignment: Alignment.centerLeft,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'この円内で釣果がありますが、非公開です。\n釣り場をタップすると「釣り場MAP」画面に移動します。',
                style: TextStyle(color: Colors.black87, fontSize: 13),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child:
                (_pts.isEmpty)
                    ? const Center(child: CircularProgressIndicator())
                    : Builder(
                      builder: (context) {
                        fm.MapOptions mapOpts;
                        if (_circleCenter != null && _circleRadiusM > 0) {
                          final screenW = MediaQuery.of(context).size.width;
                          final z = _zoomForCircle(
                            _circleCenter!.latitude,
                            _circleRadiusM,
                            screenW,
                            marginFactor: 1.05,
                          );
                          mapOpts = fm.MapOptions(
                            initialCenter: _circleCenter!,
                            initialZoom: z,
                          );
                        } else {
                          // build-timeに初期カメラを bounds フィットで指定し、初回から確実に描画
                          double minLat = 90,
                              maxLat = -90,
                              minLng = 180,
                              maxLng = -180;
                          for (final p in _pts) {
                            final lat = (p['lat'] as num).toDouble();
                            final lng = (p['lng'] as num).toDouble();
                            if (lat < minLat) minLat = lat;
                            if (lat > maxLat) maxLat = lat;
                            if (lng < minLng) minLng = lng;
                            if (lng > maxLng) maxLng = lng;
                          }
                          final bounds = fm.LatLngBounds(
                            LatLng(minLat, minLng),
                            LatLng(maxLat, maxLng),
                          );
                          mapOpts = fm.MapOptions(
                            initialCameraFit: fm.CameraFit.bounds(
                              bounds: bounds,
                              padding: const EdgeInsets.all(24),
                            ),
                          );
                        }
                        return fm.FlutterMap(
                          mapController: _controller,
                          options: mapOpts,
                          children: [
                            fm.TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'jp.bouzer.seafishingmap',
                              tileProvider: fm.NetworkTileProvider(),
                            ),
                            if (_circleCenter != null && _circleRadiusM > 0)
                              fm.CircleLayer(
                                circles: [
                                  fm.CircleMarker(
                                    point: _circleCenter!,
                                    radius: _circleRadiusM,
                                    useRadiusInMeter: true,
                                    color: Colors.redAccent.withOpacity(0.12),
                                    borderColor: Colors.redAccent.withOpacity(
                                      0.35,
                                    ),
                                    borderStrokeWidth: 2,
                                  ),
                                ],
                              ),
                            fm.MarkerLayer(markers: markers),
                          ],
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  // 外接円内のポイントのみランダム順にして、外側は元順のまま後ろに並べる
  List<Map<String, dynamic>> _orderedPts() {
    if (_circleCenter == null || _circleRadiusM <= 0) {
      return List<Map<String, dynamic>>.from(_pts);
    }
    final inside = <Map<String, dynamic>>[];
    final outside = <Map<String, dynamic>>[];
    for (final p in _pts) {
      final d = _dist(
        _circleCenter!.latitude,
        _circleCenter!.longitude,
        (p['lat'] as num).toDouble(),
        (p['lng'] as num).toDouble(),
      );
      if (d <= _circleRadiusM)
        inside.add(p);
      else
        outside.add(p);
    }
    // 安定したランダム順（候補IDの和をシードに利用）
    int seed = 0;
    final ids = _cands.map((e) => (e['id'] as int?) ?? 0).toList()..sort();
    for (final id in ids) {
      seed = 0x1fffffff & (seed * 131 + id);
    }
    final rnd = math.Random(seed == 0 ? _pts.length : seed);
    for (int i = inside.length - 1; i > 0; i--) {
      final j = rnd.nextInt(i + 1);
      final tmp = inside[i];
      inside[i] = inside[j];
      inside[j] = tmp;
    }
    return [...inside, ...outside];
  }

  double _zoomForCircle(
    double lat,
    double radiusM,
    double screenWidthPx, {
    double marginFactor = 1.05,
  }) {
    // 円の半径が画面半幅の marginFactor 倍で収まるズーム
    final halfWidthMeters = radiusM * marginFactor;
    final worldCircumference = 40075016.68557849; // m
    final metersPerPixel = (halfWidthMeters * 2) / screenWidthPx;
    final cosLat = math.cos(lat * math.pi / 180.0).abs().clamp(0.0001, 1.0);
    final z =
        math.log(worldCircumference * cosLat / (metersPerPixel * 256)) /
        math.log(2);
    return z.clamp(3.0, 19.0);
  }

  void _computeCircle() {
    // 外接円は曖昧候補集合からのみ算出
    if (_cands.isEmpty) {
      _circleCenter = null;
      _circleRadiusM = 0.0;
      return;
    }
    // センターは各ポイントの平均（簡易）
    double slat = 0.0, slng = 0.0;
    for (final p in _cands) {
      slat += (p['lat'] as num).toDouble();
      slng += (p['lng'] as num).toDouble();
    }
    final cLat = slat / _cands.length;
    final cLng = slng / _cands.length;
    _circleCenter = LatLng(cLat, cLng);
    // 半径は中心からの最大距離（5%のマージン）
    double maxM = 0.0;
    for (final p in _cands) {
      final d = _dist(
        cLat,
        cLng,
        (p['lat'] as num).toDouble(),
        (p['lng'] as num).toDouble(),
      );
      if (d > maxM) maxM = d;
    }
    _circleRadiusM = maxM * 1.05;
  }

  void _selectPoint(Map<String, dynamic> p) async {
    final id = p['id'] as int?;
    final name = (p['name'] ?? '').toString();
    final lat = (p['lat'] as num).toDouble();
    final lng = (p['lng'] as num).toDouble();
    setState(() => _selectedId = id);
    try {
      // 近辺選択を現在の詳細に反映（最近傍潮汐ポイントは既存のまま維持）
      await Common.instance.saveSelectedTeibou(
        name,
        Common.instance.tidePoint,
        id: id,
        lat: lat,
        lng: lng,
      );
    } catch (_) {}
    // 曖昧候補(points)モードでは、選択状態を保存して釣り場詳細へ戻す
    if (widget.points != null) {
      Common.instance.shouldJumpPage = true;
      Common.instance.requestNavigateToTidePage();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    // center+radiusモードでは選択を返す（既存の一覧の動作に合わせる）
    if (widget.centerLat != null && widget.centerLng != null) {
      if (!mounted) return;
      Navigator.pop(context, p);
    }
  }

  double _dist(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a =
        (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            (math.sin(dLon / 2) * math.sin(dLon / 2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  @override
  void dispose() {
    try {
      _posSub?.cancel();
    } catch (_) {}
    try {
      _blinkTimer?.cancel();
    } catch (_) {}
    super.dispose();
  }

  void _startBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      setState(() => _blinkOn = !_blinkOn);
    });
  }
}

String _circledNum(int n) {
  const list = ['①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨', '⑩'];
  if (n >= 1 && n <= 10) return list[n - 1];
  return n.toString();
}
