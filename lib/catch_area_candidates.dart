import 'dart:math' as math;

import 'constants.dart';

typedef CatchAreaLogger = void Function(String message);

/// 実際に釣れた釣り場 [spotId] を基点に、「釣れたエリア」に含める釣り場候補を算出する。
///
/// アルゴリズム概要:
/// - `teibou` 一覧から基点の釣り場を見つけ、その緯度経度を起点に全釣り場との距離を計算する。
/// - 距離の近い順に並べた後、`ambiguous_method` に応じて候補を絞り込む。
/// - `ambiguous_method == 1`
///   - 基点から近い 10 件を取得する。
///   - その 10 件目を新たな基点として、そこから近い 10 件を追加候補として取得する。
///   - 同一 `port_id` は 1 件にまとめ、`port_id` が取れない場合は 50m 未満を同一扱いにして重複除外する。
/// - `ambiguous_method == 2`
///   - 基点から近い 15 件を取得する。
///   - 住所単位でグルーピングし、各グループ内は距離昇順、グループ同士は最短距離昇順で並べる。
/// - `ambiguous_method == 3`
///   - 基点から近い 20 件を取得する。
///   - 20 件以内ならそのまま使う。
///   - 16 件以上ある場合は外接矩形の縦横比と `spotId % 3` から削る方向を決め、15 件になるまで片側から除外する。
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
    if ((r['port_id']?.toString() ?? '') == spotId.toString()) {
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
      rows.map((r) {
        final lat = (r['latitude'] as num).toDouble();
        final lng = (r['longitude'] as num).toDouble();
        final d = _distanceMeters(sLat, sLng, lat, lng);
        return <String, dynamic>{
          'id': int.tryParse(r['port_id']?.toString() ?? ''),
          'name': (r['port_name'] ?? '').toString(),
          'address': (r['address'] ?? '').toString(),
          'lat': lat,
          'lng': lng,
          'd': d,
        };
      }).toList();
  list.sort((a, b) => (a['d'] as double).compareTo(b['d'] as double));

  late final List<Map<String, dynamic>> points;
  if (ambiguous_method == 2) {
    final nearby15 = list.take(15).toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final e in nearby15) {
      final rawAddress = ((e['address'] ?? '') as String).trim();
      final key =
          rawAddress.isNotEmpty
              ? rawAddress
              : '__missing__:${e['id'] ?? e['name'] ?? nearby15.indexOf(e)}';
      groups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(e);
    }
    final orderedGroups =
        groups.values.toList()..sort((a, b) {
          final ad = a
              .map((e) => (e['d'] as double?) ?? double.infinity)
              .reduce((x, y) => x < y ? x : y);
          final bd = b
              .map((e) => (e['d'] as double?) ?? double.infinity)
              .reduce((x, y) => x < y ? x : y);
          return ad.compareTo(bd);
        });
    for (final g in orderedGroups) {
      g.sort(
        (a, b) => ((a['d'] as double?) ?? double.infinity).compareTo(
          (b['d'] as double?) ?? double.infinity,
        ),
      );
    }
    points = orderedGroups.expand((g) => g).toList();
  } else if (ambiguous_method == 3) {
    final nearby20 = list.take(20).toList();
    if (nearby20.length <= 15) {
      logger?.call(
        'ambiguous_method=3 spotId=$spotId shape=unknown nearby20=${nearby20.length} action=no_cut',
      );
      points = nearby20;
    } else {
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
        'ambiguous_method=3 spotId=$spotId shape=${vertical ? 'vertical' : 'horizontal'} pattern=$pattern heightM=${heightM.toStringAsFixed(1)} widthM=${widthM.toStringAsFixed(1)}',
      );
      if (pattern == 3) {
        final removed = nearby20.skip(15).map((e) => e['id']).toList();
        logger?.call(
          'ambiguous_method=3 action=nearest15_keep removedCount=${removed.length} removedIds=$removed',
        );
        points = nearby20.take(15).toList();
      } else {
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

        while (working.length > 15) {
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
          'ambiguous_method=3 action=$primaryAction count=$primaryCutCount fallbackAction=$fallbackAction fallbackCount=$fallbackCutCount removedIds=$removedIds',
        );
        points =
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
      }
    }
  } else {
    final s1 = list.take(10).toList();
    final c10 = s1.isNotEmpty ? s1.last : null;
    List<Map<String, dynamic>> s2 = [];
    if (c10 != null) {
      final cLat = (c10['lat'] as num).toDouble();
      final cLng = (c10['lng'] as num).toDouble();
      final withD =
          rows.map((r) {
            final lat = (r['latitude'] as num).toDouble();
            final lng = (r['longitude'] as num).toDouble();
            final id = int.tryParse(r['port_id']?.toString() ?? '');
            final d = _distanceMeters(cLat, cLng, lat, lng);
            return <String, dynamic>{
              'id': id,
              'name': (r['port_name'] ?? '').toString(),
              'address': (r['address'] ?? '').toString(),
              'lat': lat,
              'lng': lng,
              'd': d,
            };
          }).toList();
      withD.sort((a, b) => (a['d'] as double).compareTo(b['d'] as double));
      s2 = withD.take(10).toList();
    }
    final seenIds = <int>{};
    final combined = <Map<String, dynamic>>[];

    bool addIfUnique(Map<String, dynamic> e) {
      final id = e['id'] as int?;
      if (id != null) {
        if (seenIds.contains(id)) return false;
        seenIds.add(id);
        combined.add(e);
        return true;
      }
      final lat = (e['lat'] as num).toDouble();
      final lng = (e['lng'] as num).toDouble();
      for (final x in combined) {
        final d = _distanceMeters(
          lat,
          lng,
          (x['lat'] as num).toDouble(),
          (x['lng'] as num).toDouble(),
        );
        if (d < 50.0) return false;
      }
      combined.add(e);
      return true;
    }

    for (final e in s1) {
      addIfUnique(e);
    }
    for (final e in s2) {
      addIfUnique(e);
    }
    points = combined;
  }

  return points;
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
