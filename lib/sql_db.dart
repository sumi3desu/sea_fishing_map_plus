import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
//import 'package:flutter_riverpod/flutter_riverpod.dart';
//import 'main.dart'; 
import 'test_debug_print.dart';
import 'appconfig.dart';
import 'constants.dart';

Future<void> initialLocalDB(int user_id) async{
  // DB open
  final localDb = await openLocalDb();

  await initialTable(localDb, user_id);

  await matchTheTable(localDb, user_id);

}
/// サーバから version 一覧を取得（適用は行わない）
Future<List<Map<String, dynamic>>> getRemoteVersionList(int userId) async {
  try {
    final uri = Uri.parse('${AppConfig.instance.baseUrl}get_version_list.php');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'userId': userId.toString()},
        )
        .timeout(kHttpTimeout);
    final data = json.decode(resp.body);
    if (resp.statusCode == 200 && data['status'] == 'success') {
      final versions = List.from(data['data']);
      return versions.map<Map<String, dynamic>>((e) => {
        'name': e['name'],
        'version': int.tryParse(e['version'].toString()) ?? -1,
      }).toList();
    }
  } catch (_) {}
  return <Map<String, dynamic>>[];
}

///
/// ローカルDBオープン
///
Future<Database> openLocalDb() async {
  WidgetsFlutterBinding.ensureInitialized();
  final databasesPath = await getDatabasesPath();
  final path = join(databasesPath, 'kakomon_go_takken.db');
  return openDatabase(
    path,
    version: 1,
    // onCreate でもテーブルを作れますが、
    // 既存バージョンの再実行を避けたいなら IF NOT EXISTS
    onCreate: (db, version) async {
    },
  );
}

///
/// 指定のテーブルがローカルに存在するかチェック
///
Future<bool> isExistTable(Database db, String tableName) async {
  final result = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [tableName],
  );
  return result.isNotEmpty;
}


///
/// 指定テーブルのレコード数取得
/// 
Future<int> getCountRows(Database localDb, String tableName) async {

  final count = Sqflite.firstIntValue(
    await localDb.rawQuery(
      'SELECT COUNT(*) FROM $tableName ',
    ),
  )!;
  return count;
}

Future<void> initialVersionItem(Database db, bool initialize, int userId, String name, int version) async {
  // 「glossary」が存在するかをカウント
  final count = Sqflite.firstIntValue(
    await db.rawQuery(
      'SELECT COUNT(*) FROM version WHERE user_id = ? AND name = ?',
      [userId, name],
    ),
  )!;

  if (count == 0) {

    //print("insert to ${name} = ${version}");    
    // 存在しなければ挿入
    await db.insert(
      'version',
      {
        'user_id': userId,
        'name': name,
        'version': version,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  } else {
    //print("update ${name} to version = ${version}");   
    if (!initialize)
    await db.update(
      'version',
      {
        'version': version,
      },
      where: 'user_id = ? AND name = ?',
      whereArgs: [userId, name],
    );

  }
}

Future<int> getVersion(Database db, int userId, String name) async {
  final rows = await db.rawQuery(
    'SELECT version FROM version WHERE user_id = ? AND name = ? LIMIT 1',
    [userId, name],
  );

  if (rows.isNotEmpty) {
    return rows.first['version'] as int;
  } else {
    return -1;
  }
}

Future<void> createVersion(Database db) async {
    // SQLite 用に PRIMARY KEY を含めて一度に定義します。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS version (
        user_id    INTEGER NOT NULL,
        name       TEXT    NOT NULL,
        version    INTEGER NOT NULL,
        PRIMARY KEY (user_id, name)
      )
    ''');
}

Future<void> matchTheTable(Database localDb, int userId) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.instance.baseUrl}get_version_list.php',
      );
  final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          // FIXED: 実ユーザIDでバージョン一覧を取得
          'userId' : userId.toString(),
        },
      );
      final data = json.decode(resp.body);
      if (resp.statusCode == 200 && data['status'] == 'success') {
        final versions = List.from(data['data']);
        final localVersions = await getVersions(localDb, userId);
        for(int i = 0; i < versions.length; i++)
        {
          Map version = versions[i];
          //print('version[${version['name']}]');
          for(int ii = 0; ii < localVersions.length; ii++){
            Map localVersion = localVersions[ii];
            if (version['name'] == localVersion['name']){
              print('name[${version['name']}] version[${version['version']}] localVersion[${localVersion['version']}]');
              int iLocalVersion = localVersion['version'];
              int iVersion = int.parse(version['version']);  
              if ( iLocalVersion < iVersion){
                //print('***update[${version['name']}]');
              } else {
                final cnt = await getCountRows(localDb, version['name']);
                //print('***NO update[${version['name']}] count[${cnt}]');
              }
            }
          }
        }
        print('match end');
      } else {
        print('バージョンの取得に失敗しました: ステータス異常');
      }
    } catch (e) {
      print('バージョンの取得に失敗しました: $e');
    }

}


Future<List<Map<String, Object?>>> getVersions(Database localDb, int userId) async {
  final rows = await localDb.rawQuery(
    'SELECT user_id, name, version '
    'FROM version '
    'WHERE user_id = ?',
    [userId],
  );
  return rows;
}



/// アプリ起動時に呼び出すメソッド
/// userId は将来のレコード挿入時に使う想定ですが、
/// テーブルがなければ必ず作成しておきます。
Future<void> initialTable(Database localDb, int userId) async {
  await createLocalTable(localDb);
  await initialLocalVersion(localDb, userId);

}

Future<void> createLocalTable(Database localDb) async {


  // *** version ***
  bool isExist = await isExistTable(localDb, "version");

  if (!isExist){
    // version テーブル作成
    await createVersion(localDb);
  }

}


Future<void> initialLocalVersion(Database localDb, int userId) async {
  // *** version glossary ***
  await initialVersionItem(localDb, true, userId, 'glossary', 0);

  int ver = await getVersion(localDb, userId, 'glossary');

  //print('glossary versiom[${ver}]');

  // *** version nendo ***
  await initialVersionItem(localDb, true, userId, 'nendo', 0);

  ver = await getVersion(localDb, userId, 'nendo');

  //print('nendo versiom[${ver}]');

  // *** version pinning ***
  await initialVersionItem(localDb, true, userId, 'pinning', 0);

  ver = await getVersion(localDb, userId, 'pinning');

  //print('pinning versiom[${ver}]');

  // *** version question ***
  await initialVersionItem(localDb, true, userId, 'question', 0);

  ver = await getVersion(localDb, userId, 'question');

  //print('question versiom[${ver}]');

  // *** version test_result ***
  await initialVersionItem(localDb, true, userId, 'test_result', 0);

  ver = await getVersion(localDb, userId, 'test_result');

  //print('test_result versiom[${ver}]');

}
