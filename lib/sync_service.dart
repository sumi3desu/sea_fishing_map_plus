import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'appconfig.dart';
import 'sio_database.dart';

class SioSyncService {
  static final SioSyncService _instance = SioSyncService._internal();
  factory SioSyncService() => _instance;
  SioSyncService._internal();

  // 直近の失敗理由（どのエンドポイントで失敗したか等）
  String? lastError;

  // ベースURL（AppConfig の指定をそのまま使用し、末尾のみ正規化）
  final String _base =
      (() {
        var b = AppConfig.instance.baseUrl.trim();
        if (!b.endsWith('/')) b = '$b/';
        return b;
      })();

  Future<void> syncFromServer({int userId = 0}) async {
    try {
      final versions = await _fetchVersionList(userId: userId);
      if (versions == null) return;

      final db = await SioDatabase().database;
      final localVersions = await _getLocalVersions(db, userId: userId);

      for (final item in versions) {
        final name = item['name']?.toString() ?? '';
        final remoteVer = _toInt(item['version']);
        if (name.isEmpty || remoteVer == null) continue;

        final versionName = (name == 'teibou') ? 'spots' : name;
        final localVer = localVersions[versionName] ?? localVersions[name];
        final needsUpdate = (localVer == null) || (localVer != remoteVer);
        if (!needsUpdate) continue;

        if (name == 'spots' || name == 'teibou') {
          final ok = await _syncTeibou(userId: userId);
          if (ok) {
            await _upsertLocalVersion(
              db,
              userId: userId,
              name: 'spots',
              version: remoteVer,
            );
          }
        } else if (name == 'todoufuken') {
          final ok = await _syncTodoufuken(userId: userId);
          if (ok) {
            await _upsertLocalVersion(
              db,
              userId: userId,
              name: name,
              version: remoteVer,
            );
          }
        } else if (name == 'kubun') {
          final ok = await _syncKubun();
          if (ok) {
            await _upsertLocalVersion(
              db,
              userId: userId,
              name: name,
              version: remoteVer,
            );
          }
        }
      }
    } catch (_) {
      // ネットワークや解析エラーは起動を妨げない
    }
  }

  // 公開: リモートのバージョン一覧をマップで取得
  Future<Map<String, int>> fetchRemoteVersionMap({required int userId}) async {
    try {
      final list = await _fetchVersionList(userId: userId);
      if (list == null) return {};
      final map = <String, int>{};
      for (final r in list) {
        final n = r['name']?.toString();
        final v = _toInt(r['version']);
        if (n != null && v != null) map[n] = v;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  // 公開: 釣り場データ一括同期（force = true で全取得、false で差分）
  Future<bool> syncFishingData({
    required int userId,
    bool force = false,
  }) async {
    try {
      lastError = null;
      final db = await SioDatabase().database;
      final remote = await fetchRemoteVersionMap(userId: userId);
      // Fallback: バージョン一覧が取得できない場合でも、
      // 初回準備を完了できるように全テーブルの直接同期を試みる
      if (remote.isEmpty) {
        final okKubun = await _syncKubun();
        final okTeibou = await _syncTeibou(userId: userId);
        final okTodou = await _syncTodoufuken(userId: userId);
        if (!okKubun)
          lastError = 'get_kubun.php';
        else if (!okTeibou)
          lastError = 'get_spots.php';
        else if (!okTodou)
          lastError = 'get_todoufuken.php';
        return okKubun && okTeibou && okTodou;
      }
      final local = await _getLocalVersions(db, userId: userId);

      // それぞれのテーブルを更新
      Future<bool> _maybeSync(
        String name,
        Future<bool> Function() action,
      ) async {
        final lv = local[name];
        final rv = remote[name];
        final need = force || lv == null || rv == null || lv != rv;
        if (need) {
          final ok = await action();
          if (ok && rv != null) {
            await _upsertLocalVersion(
              db,
              userId: userId,
              name: name,
              version: rv,
            );
          } else if (!ok) {
            // 同期失敗のエンドポイントを記録
            if (name == 'kubun')
              lastError = 'get_kubun.php';
            else if (name == 'teibou')
              lastError = 'get_spots.php';
            else if (name == 'todoufuken')
              lastError = 'get_todoufuken.php';
          }
          return ok;
        }
        return true;
      }

      final okKubun = await _maybeSync('kubun', _syncKubun);
      final localSpotVersion = local['spots'] ?? local['teibou'];
      final remoteSpotVersion = remote['spots'] ?? remote['teibou'];
      final needSpotSync =
          force ||
          localSpotVersion == null ||
          remoteSpotVersion == null ||
          localSpotVersion != remoteSpotVersion;
      final okTeibou = needSpotSync ? await _syncTeibou(userId: userId) : true;
      if (okTeibou && remoteSpotVersion != null) {
        await _upsertLocalVersion(
          db,
          userId: userId,
          name: 'spots',
          version: remoteSpotVersion,
        );
      } else if (!okTeibou) {
        lastError = 'get_spots.php';
      }
      final okTodou = await _maybeSync(
        'todoufuken',
        () => _syncTodoufuken(userId: userId),
      );
      return okKubun && okTeibou && okTodou;
    } catch (_) {
      lastError = lastError ?? '初期化中に不明なエラー';
      return false;
    }
  }

  Future<Map<String, int>> _getLocalVersions(
    Database db, {
    required int userId,
  }) async {
    try {
      final rows = await db.query(
        'version',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      final map = <String, int>{};
      for (final r in rows) {
        final name = r['name']?.toString();
        final v = r['version'];
        if (name != null && v is int) map[name] = v;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> _upsertLocalVersion(
    Database db, {
    required int userId,
    required String name,
    required int version,
  }) async {
    await db.insert('version', {
      'user_id': userId,
      'name': name,
      'version': version,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>?> _fetchVersionList({
    required int userId,
  }) async {
    final uri = Uri.parse('${_base}get_version_list.php');
    final body = 'userId=${Uri.encodeQueryComponent(userId.toString())}';
    final resp = await _post(
      uri,
      body: body,
      contentType: 'application/x-www-form-urlencoded',
    );
    if (resp == null) return null;
    final map = jsonDecode(resp) as Map<String, dynamic>;
    if (map['status'] == 'success' && map['data'] is List) {
      return (map['data'] as List).cast<Map<String, dynamic>>();
    }
    return null;
  }

  Future<bool> _syncTodoufuken({required int userId}) async {
    final uri = Uri.parse('${_base}get_todoufuken.php');
    final body = 'userId=${Uri.encodeQueryComponent(userId.toString())}';
    final resp = await _post(
      uri,
      body: body,
      contentType: 'application/x-www-form-urlencoded',
    );
    if (resp == null) {
      lastError = lastError ?? 'get_todoufuken.php 通信失敗';
      return false;
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(resp);
    } catch (_) {
      lastError = 'get_todoufuken.php 解析失敗';
      return false;
    }
    List<Map<String, dynamic>> rows;
    try {
      if (decoded is Map<String, dynamic> && decoded['data'] is List) {
        rows = (decoded['data'] as List).cast<Map<String, dynamic>>();
      } else if (decoded is List) {
        rows = decoded.cast<Map<String, dynamic>>();
      } else {
        lastError = 'get_todoufuken.php 形式不正';
        return false;
      }
    } catch (_) {
      lastError = 'get_todoufuken.php 形式不正';
      return false;
    }

    final db = await SioDatabase().database;
    return await db
        .transaction((txn) async {
          await txn.delete('todoufuken');
          final batch = txn.batch();
          for (final r in rows) {
            final id = _toInt(r['todoufuken_id']);
            final name = r['todoufuken_name']?.toString() ?? '';
            final chihou =
                r.containsKey('chihou_name')
                    ? (r['chihou_name']?.toString() ?? '')
                    : '';
            if (id == null || name.isEmpty) continue;
            batch.insert('todoufuken', {
              'todoufuken_id': id,
              'todoufuken_name': name,
              'chihou_name': chihou,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          await batch.commit(noResult: true);
          return true;
        })
        .catchError((_) {
          lastError = 'get_todoufuken.php DB反映失敗';
          return false;
        });
  }

  Future<bool> _syncTeibou({required int userId}) async {
    final uri = Uri.parse('${_base}get_spots.php');
    final body = 'userId=${Uri.encodeQueryComponent(userId.toString())}';
    final resp = await _post(uri, body: body);
    if (resp == null) {
      lastError = 'get_spots.php 通信失敗';
      return false;
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(resp);
    } catch (_) {
      lastError = 'get_spots.php 解析失敗';
      return false;
    }
    List<Map<String, dynamic>> rows;
    try {
      if (decoded is Map<String, dynamic>) {
        if (decoded['data'] is List) {
          rows = (decoded['data'] as List).cast<Map<String, dynamic>>();
        } else if (decoded['spots'] is List) {
          rows = (decoded['spots'] as List).cast<Map<String, dynamic>>();
        } else if (decoded['teibou'] is List) {
          rows = (decoded['teibou'] as List).cast<Map<String, dynamic>>();
        } else {
          lastError = 'get_spots.php 形式不正';
          return false;
        }
      } else if (decoded is List) {
        rows = decoded.cast<Map<String, dynamic>>();
      } else {
        lastError = 'get_spots.php 形式不正';
        return false;
      }
    } catch (_) {
      lastError = 'get_spots.php 形式不正';
      return false;
    }

    final db = await SioDatabase().database;
    return await db
        .transaction((txn) async {
          await txn.delete('spots');

          // todoufuken も併せて更新（重複排除）
          final seenPref = <int>{};
          final todoufukenBatch = txn.batch();

          final teibouBatch = txn.batch();
          for (final r in rows) {
            final spotId = _toInt(r['spot_id']) ?? _toInt(r['port_id']);
            final spotName =
                r['spot_name']?.toString() ?? r['port_name']?.toString() ?? '';
            final furigana = r['furigana']?.toString() ?? '';
            final jYomi =
                (r['j_yomi']?.toString().isEmpty ?? true)
                    ? null
                    : r['j_yomi']?.toString();
            final kubun = r['kubun']?.toString() ?? '';
            final address = r['address']?.toString() ?? '';
            final latitude = _toDouble(r['latitude']);
            final longitude = _toDouble(r['longitude']);
            final note = r['note']?.toString() ?? '';
            final registrantName = r['registrant_name']?.toString();
            final flag = _toInt(r['flag']) ?? 0;
            final priv = _toInt(r['private']) ?? 0;
            final userId = _toInt(r['user_id']) ?? 0;
            final createAt = r['create_at']?.toString();

            if (spotId == null) continue;
            if (flag == -2 || flag == -3) continue;
            final double latIns = latitude ?? 0.0;
            final double lngIns = longitude ?? 0.0;

            final rowMap = <String, Object?>{
              'spot_id': spotId,
              'spot_name': spotName,
              'furigana': furigana,
              'j_yomi': jYomi,
              'kubun': kubun,
              'address': address,
              'latitude': latIns,
              'longitude': lngIns,
              'note': note,
            };
            // 追加カラム（存在する環境では反映）
            rowMap['flag'] = flag;
            rowMap['private'] = priv;
            rowMap['user_id'] = userId;
            if ((registrantName ?? '').isNotEmpty)
              rowMap['registrant_name'] = registrantName;
            if (createAt != null && createAt.isNotEmpty)
              rowMap['create_at'] = createAt;

            teibouBatch.insert(
              'spots',
              rowMap,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

            final prefId = _toInt(r['todoufuken_id']);
            final prefName = r['todoufuken_name']?.toString();
            final chihou =
                r.containsKey('chihou_name')
                    ? r['chihou_name']?.toString()
                    : null;
            if (prefId != null && prefName != null && seenPref.add(prefId)) {
              todoufukenBatch.insert('todoufuken', {
                'todoufuken_id': prefId,
                'todoufuken_name': prefName,
                if (chihou != null) 'chihou_name': chihou,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }

          await teibouBatch.commit(noResult: true);
          await todoufukenBatch.commit(noResult: true);
          return true;
        })
        .catchError((_) {
          lastError = 'get_spots.php DB反映失敗';
          return false;
        });
  }

  Future<bool> _syncKubun() async {
    final uri = Uri.parse('${_base}get_kubun.php');
    final resp = await _get(uri);
    if (resp == null) {
      lastError = lastError ?? 'get_kubun.php 通信失敗';
      return false;
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(resp);
    } catch (_) {
      lastError = 'get_kubun.php 解析失敗';
      return false;
    }
    List<Map<String, dynamic>> rows;
    try {
      if (decoded is Map<String, dynamic> && decoded['data'] is List) {
        rows = (decoded['data'] as List).cast<Map<String, dynamic>>();
      } else if (decoded is List) {
        rows = decoded.cast<Map<String, dynamic>>();
      } else {
        lastError = 'get_kubun.php 形式不正';
        return false;
      }
    } catch (_) {
      lastError = 'get_kubun.php 形式不正';
      return false;
    }

    final db = await SioDatabase().database;
    return await db
        .transaction((txn) async {
          await txn.delete('kubun');
          final batch = txn.batch();
          for (final r in rows) {
            final id = _toInt(r['id']);
            final name = r['kubun_name']?.toString() ?? '';
            final note = r['note']?.toString();
            if (id == null || name.isEmpty) continue;
            batch.insert('kubun', {
              'id': id,
              'kubun_name': name,
              'note': note,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          await batch.commit(noResult: true);
          return true;
        })
        .catchError((_) {
          lastError = 'get_kubun.php DB反映失敗';
          return false;
        });
  }

  // HTTP helpers using dart:io to avoid extra dependencies
  Future<String?> _post(
    Uri uri, {
    required String body,
    String contentType = 'application/x-www-form-urlencoded',
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, contentType);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.add(utf8.encode(body));
      final res = await req.close();
      final ep =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.last : uri.toString();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final respBody = await utf8.decoder.bind(res).join();
        client.close(force: true);
        return respBody;
      }
      // ステータス異常を記録
      lastError = lastError ?? 'POST $ep HTTP ${res.statusCode}';
      client.close(force: true);
      return null;
    } catch (e) {
      final ep =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.last : uri.toString();
      lastError = lastError ?? 'POST $ep 通信例外: $e';
      return null;
    }
  }

  Future<String?> _get(Uri uri) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close();
      final ep =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.last : uri.toString();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final respBody = await utf8.decoder.bind(res).join();
        client.close(force: true);
        return respBody;
      }
      // ステータス異常を記録
      lastError = lastError ?? 'GET $ep HTTP ${res.statusCode}';
      client.close(force: true);
      return null;
    } catch (e) {
      final ep =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.last : uri.toString();
      lastError = lastError ?? 'GET $ep 通信例外: $e';
      return null;
    }
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
