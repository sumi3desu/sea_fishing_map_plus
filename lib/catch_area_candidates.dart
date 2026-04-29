import 'dart:math' as math;

import 'constants.dart';

typedef CatchAreaLogger = void Function(String message);

/// 実際に釣れた釣り場 [spotId] を基点に、「釣れたエリア」に含める釣り場候補を算出する。
///
/// アルゴリズム概要:
/// - `teibou` 一覧から基点の釣り場を見つけ、その緯度経度を起点に全釣り場との距離を計算する。
/// - この処理は `ambiguousLevel == 1` のときの「釣れたエリア」候補算出として扱う。
/// - 基点から近い `kCatchAreaCandidateSourceCount` 件を取得する。
/// - `kCatchAreaVisibleSpotCount` 件以内ならそのまま使う。
/// - 16 件以上ある場合は外接矩形の縦横比と `spotId % 3` から削る方向を決め、
///   `kCatchAreaVisibleSpotCount` 件になるまで片側から除外する。
/// - 戻り値は `NearbyMapPage` や通知候補生成でそのまま使える `id/name/address/lat/lng/d` を持つマップ配列。
///
/// この関数を通知用 `candidate_spot_ids` と投稿詳細の「釣れたエリア」表示で共通利用することで、
/// 両者の候補釣り場を完全に同じロジックで算出する。
List<Map<String, dynamic>> buildCatchAreaPoints({
  required List<Map<String, dynamic>> rows,
  required int spotId,
  CatchAreaLogger? logger,
}) {
  Map<String, dynamic>? src;
  for (final r in rows) {
    if ((r['spot_id']?.toString() ?? '') == spotId.toString()) {
      src = r;
      break;
    }
  }
  if (src == null) {
    return const <Map<String, dynamic>>[];
  }

  final double sLat = (src['latitude'] as num).toDouble();
  final double sLng = (src['longitude'] as num).toDouble();
  final list =
      rows
          .where((r) {
            final flag =
                r['flag'] is int
                    ? r['flag'] as int
                    : int.tryParse(r['flag']?.toString() ?? '');
            return flag != -2 && flag != -3;
          })
          .map((r) {
            final lat = (r['latitude'] as num).toDouble();
            final lng = (r['longitude'] as num).toDouble();
            final d = _distanceMeters(sLat, sLng, lat, lng);
            return <String, dynamic>{
              'id': int.tryParse(r['spot_id']?.toString() ?? ''),
              'name': (r['spot_name'] ?? '').toString(),
              'address': (r['address'] ?? '').toString(),
              'lat': lat,
              'lng': lng,
              'd': d,
            };
          })
          .toList();
  list.sort((a, b) => (a['d'] as double).compareTo(b['d'] as double));

  final nearby20 = list.take(kCatchAreaCandidateSourceCount).toList();
  if (nearby20.length <= kCatchAreaVisibleSpotCount) {
    logger?.call(
      'ambiguousLevel=1 spotId=$spotId shape=unknown nearby20=${nearby20.length} action=no_cut',
    );
    _logCatchAreaPoints(
      logger,
      label: 'catch_area_final_no_cut',
      points: nearby20,
    );
    return nearby20;
  }
  double minLat = double.infinity;
  double maxLat = -double.infinity;
  double minLng = double.infinity;
  double maxLng = -double.infinity;
  for (final e in nearby20) {
    final lat = (e['lat'] as num).toDouble();
    final lng = (e['lng'] as num).toDouble();
    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
    if (lng < minLng) minLng = lng;
    if (lng > maxLng) maxLng = lng;
  }
  final centerLat = (minLat + maxLat) / 2.0;
  final centerLng = (minLng + maxLng) / 2.0;
  final heightM = _distanceMeters(minLat, centerLng, maxLat, centerLng);
  final widthM = _distanceMeters(centerLat, minLng, centerLat, maxLng);
  final vertical = heightM >= widthM;
  final pattern = (spotId % 3) + 1;
  logger?.call(
    'ambiguousLevel=1 spotId=$spotId shape=${vertical ? 'vertical' : 'horizontal'} pattern=$pattern heightM=${heightM.toStringAsFixed(1)} widthM=${widthM.toStringAsFixed(1)}',
  );
  if (pattern == 3) {
    final removed =
        nearby20.skip(kCatchAreaVisibleSpotCount).map((e) => e['id']).toList();
    logger?.call(
      'ambiguousLevel=1 action=nearest15_keep removedCount=${removed.length} removedIds=$removed',
    );
    final result = nearby20.take(kCatchAreaVisibleSpotCount).toList();
    _logCatchAreaPoints(
      logger,
      label: 'catch_area_final_nearest',
      points: result,
    );
    return result;
  }
  final working = List<Map<String, dynamic>>.from(nearby20);
  int primaryCutCount = 0;
  int fallbackCutCount = 0;
  final removedIds = <dynamic>[];

  int pickIndex(List<Map<String, dynamic>> src, bool primarySide) {
    final indexed = src.asMap().entries.toList();
    indexed.sort((a, b) {
      final av =
          primarySide
              ? _axisValue(a.value, vertical, pattern)
              : _axisValue(a.value, vertical, pattern, opposite: true);
      final bv =
          primarySide
              ? _axisValue(b.value, vertical, pattern)
              : _axisValue(b.value, vertical, pattern, opposite: true);
      final c = av.compareTo(bv);
      if (c != 0) return c;
      final ad = (a.value['d'] as double?) ?? double.infinity;
      final bd = (b.value['d'] as double?) ?? double.infinity;
      return bd.compareTo(ad);
    });
    for (final entry in indexed) {
      if ((entry.value['id'] as int?) != spotId) return entry.key;
    }
    return -1;
  }

  while (working.length > kCatchAreaVisibleSpotCount) {
    int idx = pickIndex(working, true);
    bool usedFallback = false;
    if (idx < 0) {
      idx = pickIndex(working, false);
      usedFallback = true;
    }
    if (idx < 0) break;
    final removed = working.removeAt(idx);
    removedIds.add(removed['id']);
    if (usedFallback) {
      fallbackCutCount++;
    } else {
      primaryCutCount++;
    }
  }
  final primaryAction =
      vertical
          ? (pattern == 1 ? 'top_cut' : 'bottom_cut')
          : (pattern == 1 ? 'right_cut' : 'left_cut');
  final fallbackAction =
      vertical
          ? (pattern == 1 ? 'bottom_cut' : 'top_cut')
          : (pattern == 1 ? 'left_cut' : 'right_cut');
  logger?.call(
    'ambiguousLevel=1 action=$primaryAction count=$primaryCutCount fallbackAction=$fallbackAction fallbackCount=$fallbackCutCount removedIds=$removedIds',
  );
  final result =
      nearby20.where((e) {
        final id = e['id'] as int?;
        if (id != null) {
          return working.any((w) => (w['id'] as int?) == id);
        }
        return working.any((w) {
          final d = _distanceMeters(
            (e['lat'] as num).toDouble(),
            (e['lng'] as num).toDouble(),
            (w['lat'] as num).toDouble(),
            (w['lng'] as num).toDouble(),
          );
          return d < 1.0;
        });
      }).toList();
  _logCatchAreaPoints(logger, label: 'catch_area_final_cut', points: result);
  return result;
}

List<int> buildCatchAreaCandidateSpotIds({
  required List<Map<String, dynamic>> rows,
  required int spotId,
  CatchAreaLogger? logger,
}) {
  final points = buildCatchAreaPoints(
    rows: rows,
    spotId: spotId,
    logger: logger,
  );
  final ids =
      points.map((e) => e['id']).whereType<int>().toSet().toList()..sort();
  if (!ids.contains(spotId)) {
    ids.insert(0, spotId);
  }
  return ids;
}

double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
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

double _axisValue(
  Map<String, dynamic> e,
  bool vertical,
  int pattern, {
  bool opposite = false,
}) {
  final lat = (e['lat'] as num).toDouble();
  final lng = (e['lng'] as num).toDouble();
  if (vertical) {
    final fromTop = pattern == 1;
    final useTop = opposite ? !fromTop : fromTop;
    return useTop ? -lat : lat;
  }
  final fromRight = pattern == 1;
  final useRight = opposite ? !fromRight : fromRight;
  return useRight ? -lng : lng;
}

void _logCatchAreaPoints(
  CatchAreaLogger? logger, {
  required String label,
  required List<Map<String, dynamic>> points,
}) {
  if (logger == null) return;
  logger('ambiguousLevel=1 $label count=${points.length}');
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    final id = p['id'];
    final name = (p['name'] ?? '').toString();
    final lat = (p['lat'] as num?)?.toDouble();
    final lng = (p['lng'] as num?)?.toDouble();
    final d = (p['d'] as num?)?.toDouble();
    logger(
      'ambiguousLevel=1 $label index=$i spot_id=$id spot_name=$name lat=${lat?.toStringAsFixed(6)} lng=${lng?.toStringAsFixed(6)} d_m=${d?.toStringAsFixed(1)}',
    );
  }
}
