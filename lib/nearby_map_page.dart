import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'sio_database.dart';
import 'common.dart';
import 'dart:math' as math;

class NearbyMapPage extends StatefulWidget {
  const NearbyMapPage({super.key, this.points, this.centerLat, this.centerLng, this.centerName, this.radiusKm, this.highlightId});
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
  int? _selectedId;
  bool _shifted = false;
  LatLng? _myPos;
  StreamSubscription<Position>? _posSub;
  bool _blinkOn = true;
  Timer? _blinkTimer;

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
      _pts = widget.points!;
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
        _pts = cand.take(10).toList();
      } catch (_) {}
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
    final bounds = fm.LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
    final fit = fm.CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(24));
    _controller.fitCamera(fit);
  }

  @override
  Widget build(BuildContext context) {
    final markers = <fm.Marker>[];
    for (int i = 0; i < _pts.length; i++) {
      final p = _pts[i];
      final idxText = _circledNum(i + 1);
      markers.add(
        fm.Marker(
              point: LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
              width: 160,
              height: 60,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _selectPoint(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        '$idxText ${(p['name'] ?? '').toString()}',
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _selectPoint(p),
                    child: Icon(
                      Icons.location_on,
                      color: ((p['id'] ?? -1) == _selectedId) ? Colors.red : Colors.blue,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ));
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
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(1, 1))],
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('近辺の釣り場'), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: (_pts.isEmpty)
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (context) {
              // build-timeに初期カメラを bounds フィットで指定し、初回から確実に描画
              double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
              for (final p in _pts) {
                final lat = (p['lat'] as num).toDouble();
                final lng = (p['lng'] as num).toDouble();
                if (lat < minLat) minLat = lat;
                if (lat > maxLat) maxLat = lat;
                if (lng < minLng) minLng = lng;
                if (lng > maxLng) maxLng = lng;
              }
              // Expand bounds by 1.5x around center for a wider view
              final cLat = (minLat + maxLat) / 2.0;
              final cLng = (minLng + maxLng) / 2.0;
              double halfLat = (maxLat - minLat) / 2.0 * 1.5;
              double halfLng = (maxLng - minLng) / 2.0 * 1.5;
              if (halfLat == 0) halfLat = 0.005; // minimal span
              if (halfLng == 0) halfLng = 0.005;
              final expMinLat = (cLat - halfLat).clamp(-90.0, 90.0);
              final expMaxLat = (cLat + halfLat).clamp(-90.0, 90.0);
              final expMinLng = (cLng - halfLng).clamp(-180.0, 180.0);
              final expMaxLng = (cLng + halfLng).clamp(-180.0, 180.0);
              final bounds = fm.LatLngBounds(LatLng(expMinLat, expMinLng), LatLng(expMaxLat, expMaxLng));
              final fit = fm.CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(24));
              // 中心を少しオフセットする（全点が見えたうえで中心推測を外すため）
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_shifted) return;
                _shifted = true;
                final cLat = (expMinLat + expMaxLat) / 2.0;
                final cLng = (expMinLng + expMaxLng) / 2.0;
                final halfLat = (expMaxLat - expMinLat) / 2.0;
                final halfLng = (expMaxLng - expMinLng) / 2.0;
                final rnd = math.Random(_pts.length);
                final theta = rnd.nextDouble() * 2 * math.pi;
                final dLat = halfLat * 0.2 * math.sin(theta);
                final dLng = halfLng * 0.2 * math.cos(theta);
                final tgt = LatLng((cLat + dLat).clamp(-90.0, 90.0), (cLng + dLng).clamp(-180.0, 180.0));
                // ズームはそのまま、中心をずらす
                _controller.move(tgt, _controller.camera.zoom);
              });
              return fm.FlutterMap(
                mapController: _controller,
                options: fm.MapOptions(initialCameraFit: fit),
                children: [
                  fm.TileLayer(
                    urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'jp.bouzer.siowadou',
                    tileProvider: fm.NetworkTileProvider(),
                  ),
                  fm.MarkerLayer(markers: markers),
                ],
              );
            }),
    );
  }

  void _selectPoint(Map<String, dynamic> p) async {
    final id = p['id'] as int?;
    final name = (p['name'] ?? '').toString();
    final lat = (p['lat'] as num).toDouble();
    final lng = (p['lng'] as num).toDouble();
    setState(() => _selectedId = id);
    try {
      // 近辺選択を現在の詳細に反映（最近傍潮汐ポイントは既存のまま維持）
      await Common.instance.saveSelectedTeibou(name, Common.instance.tidePoint, id: id, lat: lat, lng: lng);
    } catch (_) {}
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
        (math.sin(dLat / 2) * math.sin(dLat / 2)) + math.cos(lat1 * math.pi / 180.0) * math.cos(lat2 * math.pi / 180.0) * (math.sin(dLon / 2) * math.sin(dLon / 2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  @override
  void dispose() {
    try { _posSub?.cancel(); } catch (_) {}
    try { _blinkTimer?.cancel(); } catch (_) {}
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
  const list = ['①','②','③','④','⑤','⑥','⑦','⑧','⑨','⑩'];
  if (n >= 1 && n <= 10) return list[n - 1];
  return n.toString();
}
