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

  // ベースURL（AppConfig の指定をそのまま使用し、末尾のみ正規化）
  final String _base = (() {
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

        final localVer = localVersions[name];
        final needsUpdate = (localVer == null) || (localVer != remoteVer);
        if (!needsUpdate) continue;

        if (name == 'teibou') {
          final ok = await _syncTeibou();
          if (ok) {
            await _upsertLocalVersion(db, userId: userId, name: name, version: remoteVer);
          }
        } else if (name == 'todoufuken') {
          final ok = await _syncTodoufuken(userId: userId);
          if (ok) {
            await _upsertLocalVersion(db, userId: userId, name: name, version: remoteVer);
          }
        } else if (name == 'kubun') {
          final ok = await _syncKubun();
          if (ok) {
            await _upsertLocalVersion(db, userId: userId, name: name, version: remoteVer);
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
  Future<bool> syncFishingData({required int userId, bool force = false}) async {
    try {
      final db = await SioDatabase().database;
      final remote = await fetchRemoteVersionMap(userId: userId);
      if (remote.isEmpty) return false;
      final local = await _getLocalVersions(db, userId: userId);

      // それぞれのテーブルを更新
      Future<bool> _maybeSync(String name, Future<bool> Function() action) async {
        final lv = local[name];
        final rv = remote[name];
        final need = force || lv == null || rv == null || lv != rv;
        if (need) {
          final ok = await action();
          if (ok && rv != null) {
            await _upsertLocalVersion(db, userId: userId, name: name, version: rv);
          }
          return ok;
        }
        return true;
      }

      final okKubun = await _maybeSync('kubun', _syncKubun);
      final okTeibou = await _maybeSync('teibou', _syncTeibou);
      final okTodou = await _maybeSync('todoufuken', () => _syncTodoufuken(userId: userId));
      return okKubun && okTeibou && okTodou;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, int>> _getLocalVersions(Database db, {required int userId}) async {
    try {
      final rows = await db.query('version', where: 'user_id = ?', whereArgs: [userId]);
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

  Future<void> _upsertLocalVersion(Database db, {required int userId, required String name, required int version}) async {
    await db.insert(
      'version',
      {'user_id': userId, 'name': name, 'version': version},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>?> _fetchVersionList({required int userId}) async {
    final uri = Uri.parse('${_base}get_version_list.php');
    final body = 'userId=${Uri.encodeQueryComponent(userId.toString())}';
    final resp = await _post(uri, body: body, contentType: 'application/x-www-form-urlencoded');
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
    final resp = await _post(uri, body: body, contentType: 'application/x-www-form-urlencoded');
    if (resp == null) return false;
    final map = jsonDecode(resp) as Map<String, dynamic>;
    if (map['status'] != 'success' || map['data'] is! List) return false;
    final rows = (map['data'] as List).cast<Map<String, dynamic>>();

    final db = await SioDatabase().database;
    return await db.transaction((txn) async {
      await txn.delete('todoufuken');
      final batch = txn.batch();
      for (final r in rows) {
        final id = _toInt(r['todoufuken_id']);
        final name = r['todoufuken_name']?.toString() ?? '';
        final chihou = r.containsKey('chihou_name') ? (r['chihou_name']?.toString() ?? '') : '';
        if (id == null || name.isEmpty) continue;
        batch.insert(
          'todoufuken',
          {
            'todoufuken_id': id,
            'todoufuken_name': name,
            'chihou_name': chihou,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      return true;
    }).catchError((_) => false);
  }

  Future<bool> _syncTeibou() async {
    final uri = Uri.parse('${_base}get_teibou.php');
    final resp = await _get(uri);
    if (resp == null) return false;
    final map = jsonDecode(resp) as Map<String, dynamic>;
    if (map['status'] != 'success' || map['data'] is! List) return false;
    final rows = (map['data'] as List).cast<Map<String, dynamic>>();

    final db = await SioDatabase().database;
    return await db.transaction((txn) async {
      await txn.delete('teibou');

      // todoufuken も併せて更新（重複排除）
      final seenPref = <int>{};
      final todoufukenBatch = txn.batch();

      final teibouBatch = txn.batch();
      for (final r in rows) {
        final portId = _toInt(r['port_id']);
        final portName = r['port_name']?.toString() ?? '';
        final furigana = r['furigana']?.toString() ?? '';
        final jYomi = (r['j_yomi']?.toString().isEmpty ?? true) ? null : r['j_yomi']?.toString();
        final kubun = r['kubun']?.toString() ?? '';
        final address = r['address']?.toString() ?? '';
        final latitude = _toDouble(r['latitude']);
        final longitude = _toDouble(r['longitude']);
        final note = r['note']?.toString() ?? '';

        if (portId == null) continue;
        final double latIns = latitude ?? 0.0;
        final double lngIns = longitude ?? 0.0;

        teibouBatch.insert(
          'teibou',
          {
            'port_id': portId,
            'port_name': portName,
            'furigana': furigana,
            'j_yomi': jYomi,
            'kubun': kubun,
            'address': address,
            'latitude': latIns,
            'longitude': lngIns,
            'note': note,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        final prefId = _toInt(r['todoufuken_id']);
        final prefName = r['todoufuken_name']?.toString();
        final chihou = r.containsKey('chihou_name') ? r['chihou_name']?.toString() : null;
        if (prefId != null && prefName != null && seenPref.add(prefId)) {
          todoufukenBatch.insert(
            'todoufuken',
            {
              'todoufuken_id': prefId,
              'todoufuken_name': prefName,
              if (chihou != null) 'chihou_name': chihou,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      await teibouBatch.commit(noResult: true);
      await todoufukenBatch.commit(noResult: true);
      return true;
    }).catchError((_) => false);
  }

  Future<bool> _syncKubun() async {
    final uri = Uri.parse('${_base}get_kubun.php');
    final resp = await _get(uri);
    if (resp == null) return false;
    final map = jsonDecode(resp) as Map<String, dynamic>;
    if (map['status'] != 'success' || map['data'] is! List) return false;
    final rows = (map['data'] as List).cast<Map<String, dynamic>>();

    final db = await SioDatabase().database;
    return await db.transaction((txn) async {
      await txn.delete('kubun');
      final batch = txn.batch();
      for (final r in rows) {
        final id = _toInt(r['id']);
        final name = r['kubun_name']?.toString() ?? '';
        final note = r['note']?.toString();
        if (id == null || name.isEmpty) continue;
        batch.insert(
          'kubun',
          {
            'id': id,
            'kubun_name': name,
            'note': note,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      return true;
    }).catchError((_) => false);
  }

  // HTTP helpers using dart:io to avoid extra dependencies
  Future<String?> _post(Uri uri, {required String body, String contentType = 'application/x-www-form-urlencoded'}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, contentType);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.add(utf8.encode(body));
      final res = await req.close();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final respBody = await utf8.decoder.bind(res).join();
        client.close(force: true);
        return respBody;
      }
      client.close(force: true);
      return null;
    } catch (_) {
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
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final respBody = await utf8.decoder.bind(res).join();
        client.close(force: true);
        return respBody;
      }
      client.close(force: true);
      return null;
    } catch (_) {
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
