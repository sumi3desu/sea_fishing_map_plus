import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'common.dart';

class SpotRegistrationMapPage extends StatefulWidget {
  const SpotRegistrationMapPage({super.key, this.initialCenter, this.initialZoom});

  final LatLng? initialCenter;
  final double? initialZoom;

  @override
  State<SpotRegistrationMapPage> createState() => _SpotRegistrationMapPageState();
}

class _SpotRegistrationMapPageState extends State<SpotRegistrationMapPage> {
  gm.GoogleMapController? _gmController;
  gm.MapType _mapType = gm.MapType.hybrid; // 位置特定に有利な初期値
  gm.LatLng? _center;
  double _zoom = 14;
  gm.LatLng? _selected;
  bool _locPermChecked = false;
  bool _locEnabled = false;

  @override
  void initState() {
    super.initState();
    // 初期中心: 渡し値 -> 選択済み堤防 -> gSioInfo -> 日本中心
    final init = widget.initialCenter ?? _defaultCenterFromCommon();
    _center = gm.LatLng(init.latitude, init.longitude);
    _zoom = (widget.initialZoom ?? 14).toDouble();
    _initLocation();
  }

  LatLng _defaultCenterFromCommon() {
    final lat = (Common.instance.selectedTeibouLat != 0.0)
        ? Common.instance.selectedTeibouLat
        : (Common.instance.gSioInfo.lat != 0.0 ? Common.instance.gSioInfo.lat : 35.681236);
    final lng = (Common.instance.selectedTeibouLng != 0.0)
        ? Common.instance.selectedTeibouLng
        : (Common.instance.gSioInfo.lang != 0.0 ? Common.instance.gSioInfo.lang : 139.767125);
    return LatLng(lat, lng);
  }

  Future<void> _initLocation() async {
    try {
      _locEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      _locPermChecked = permission != LocationPermission.denied && permission != LocationPermission.deniedForever;
      if (_locEnabled && _locPermChecked) {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        if (mounted && _gmController != null) {
          _gmController!.animateCamera(
            gm.CameraUpdate.newLatLngZoom(gm.LatLng(pos.latitude, pos.longitude), 16),
          );
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final markers = <gm.Marker>{};
    if (_selected != null) {
      markers.add(
        gm.Marker(
          markerId: const gm.MarkerId('sel'),
          position: _selected!,
          infoWindow: const gm.InfoWindow(title: '選択位置'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('釣り場の位置を選択'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: _mapType == gm.MapType.hybrid ? '標準表示' : '衛星表示',
            onPressed: () => setState(() {
              _mapType = _mapType == gm.MapType.hybrid ? gm.MapType.normal : gm.MapType.hybrid;
            }),
            icon: Icon(_mapType == gm.MapType.hybrid ? Icons.layers : Icons.satellite_alt),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_center != null)
            gm.GoogleMap(
              initialCameraPosition: gm.CameraPosition(target: _center!, zoom: _zoom),
              onMapCreated: (c) => _gmController = c,
              mapType: _mapType,
              myLocationEnabled: _locEnabled && _locPermChecked,
              myLocationButtonEnabled: true,
              compassEnabled: true,
              zoomControlsEnabled: false,
              markers: markers,
              onTap: (p) => setState(() => _selected = p),
              onLongPress: (p) => setState(() => _selected = p),
              onCameraMove: (pos) {
                _center = pos.target;
                _zoom = pos.zoom;
              },
            ),
          // 下部インフォと決定ボタン
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selected != null
                                ? '緯度: ${_selected!.latitude.toStringAsFixed(6)} / 経度: ${_selected!.longitude.toStringAsFixed(6)}'
                                : '地図をタップして位置を選択',
                            style: const TextStyle(fontSize: 13, color: Colors.black87),
                          ),
                          const SizedBox(height: 4),
                          Text('表示: ${_mapType == gm.MapType.hybrid ? '衛星' : '標準'} / ズーム: ${_zoom.toStringAsFixed(1)}',
                              style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('キャンセル'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _selected == null
                          ? null
                          : () {
                              Navigator.pop(context, {
                                'lat': _selected!.latitude,
                                'lng': _selected!.longitude,
                                'zoom': _zoom,
                              });
                            },
                      child: const Text('この位置を選択'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: (_gmController != null)
          ? FloatingActionButton.small(
              heroTag: 'recenter',
              onPressed: () async {
                // 選択中マーカーがあればそこへ、無ければ現在地 or 初期中心へ
                final target = _selected ?? _center ?? gm.LatLng(35.681236, 139.767125);
                await _gmController!.animateCamera(gm.CameraUpdate.newLatLngZoom(target, _zoom));
              },
              child: const Icon(Icons.my_location),
            )
          : null,
    );
  }
}

