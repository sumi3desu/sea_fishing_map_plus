import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class SioDatabase extends ChangeNotifier {
  static final SioDatabase _instance = SioDatabase._internal();
  factory SioDatabase() => _instance;
  SioDatabase._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'sio_db.db');

    return await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateToV2(db);
        }
        if (oldVersion < 3) {
          await _migrateToV3(db);
        }
        if (oldVersion < 4) {
          await _migrateToV4(db);
        }
        if (oldVersion < 5) {
          await _migrateToV5(db);
        }
      },
      onOpen: (db) async {
        // Ensure required tables exist every time the DB opens
        await _ensureTables(db);
      },
    );
  }

  Future _onCreate(Database db, int version) async {
    await _ensureTables(db);
  }

  Future<void> _ensureTables(Database db) async {
    await _migrateLegacyTeibouIfNeeded(db);

    // お気に入りテーブル（既存）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorite_tbl (
        prefecture TEXT NOT NULL,
        point_name TEXT NOT NULL,
        PRIMARY KEY (prefecture, point_name)
      )
    ''');

    // リモートMySQLの構成に合わせたローカルSQLiteテーブル
    await db.execute('''
      CREATE TABLE IF NOT EXISTS spots (
        spot_id INTEGER NOT NULL PRIMARY KEY,
        spot_name TEXT NOT NULL,
        furigana TEXT NOT NULL,
        j_yomi TEXT DEFAULT NULL,
        kubun TEXT NOT NULL,
        address TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        note TEXT NOT NULL
      )
    ''');

    // 互換のため不足カラムを追加（存在すれば無視）
    try {
      await db.execute(
        'ALTER TABLE spots ADD COLUMN flag INTEGER NOT NULL DEFAULT 0',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE spots ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0',
      );
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE spots ADD COLUMN registrant_name TEXT');
    } catch (_) {}
    try {
      // SQLite では DATETIME を TEXT として扱う（サーバは CURRENT_TIMESTAMP）
      await db.execute(
        "ALTER TABLE spots ADD COLUMN create_at TEXT NOT NULL DEFAULT (datetime('now'))",
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE spots ADD COLUMN private INTEGER NOT NULL DEFAULT 0',
      );
    } catch (_) {}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS todoufuken (
        todoufuken_id INTEGER NOT NULL PRIMARY KEY,
        todoufuken_name TEXT NOT NULL,
        chihou_name TEXT
      )
    ''');

    // 区分マスタ（spots.kubun の名称・説明）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kubun (
        id INTEGER NOT NULL PRIMARY KEY,
        kubun_name TEXT NOT NULL,
        note TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS version (
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        version INTEGER NOT NULL,
        PRIMARY KEY(user_id, name)
      )
    ''');

    // 堤防お気に入りテーブル
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorite_teibou (
        spot_id INTEGER NOT NULL PRIMARY KEY,
        created_at INTEGER
      )
    ''');

    // 公開表示用のユーザニックネームキャッシュ
    // user_public_cache は廃止
  }

  // アプリ起動時にテーブルを事前作成したい場合に呼ぶ初期化
  Future<void> initialize() async {
    final db = await database;
    await _ensureTables(db);
  }

  // ============================
  // 堤防お気に入り API
  // ============================
  Future<Set<int>> getFavoriteTeibouIds() async {
    final db = await database;
    final rows = await db.query('favorite_teibou');
    final ids = <int>{};
    for (final r in rows) {
      final v = r['spot_id'];
      if (v is int) ids.add(v);
      if (v is num) ids.add(v.toInt());
    }
    return ids;
  }

  Future<void> addFavoriteTeibou(int portId) async {
    final db = await database;
    await db.insert('favorite_teibou', {
      'spot_id': portId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeFavoriteTeibou(int portId) async {
    final db = await database;
    await db.delete(
      'favorite_teibou',
      where: 'spot_id = ?',
      whereArgs: [portId],
    );
  }

  // バージョン2: 主キー制約の追加（既存テーブルを移行）
  Future<void> _migrateToV2(Database db) async {
    await db.transaction((txn) async {
      // teibou: PRIMARY KEY(port_id)
      final teibouExists = await _tableExists(txn, 'teibou');
      final hasTeibouPk =
          teibouExists && await _hasPrimaryKeyOn(txn, 'teibou', ['port_id']);
      if (!teibouExists) {
        // 旧テーブルがない場合は新規作成のみ
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS teibou (
            port_id INTEGER NOT NULL PRIMARY KEY,
            port_name TEXT NOT NULL,
            furigana TEXT NOT NULL,
            j_yomi TEXT DEFAULT NULL,
            kubun TEXT NOT NULL,
            address TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            note TEXT NOT NULL
          )
        ''');
      } else if (!hasTeibouPk) {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS teibou_new (
            port_id INTEGER NOT NULL PRIMARY KEY,
            port_name TEXT NOT NULL,
            furigana TEXT NOT NULL,
            j_yomi TEXT DEFAULT NULL,
            kubun TEXT NOT NULL,
            address TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            note TEXT NOT NULL
          )
        ''');
        await txn.execute('''
          INSERT OR IGNORE INTO teibou_new (
            port_id, port_name, furigana, j_yomi, kubun, address, latitude, longitude, note
          )
          SELECT port_id, port_name, furigana, j_yomi, kubun, address, latitude, longitude, note FROM teibou
        ''');
        await txn.execute('DROP TABLE IF EXISTS teibou');
        await txn.execute('ALTER TABLE teibou_new RENAME TO teibou');
      }

      // todoufuken: PRIMARY KEY(todoufuken_id)
      final todoufukenExists = await _tableExists(txn, 'todoufuken');
      final hasTodoufukenPk =
          todoufukenExists &&
          await _hasPrimaryKeyOn(txn, 'todoufuken', ['todoufuken_id']);
      if (!todoufukenExists) {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS todoufuken (
            todoufuken_id INTEGER NOT NULL PRIMARY KEY,
            todoufuken_name TEXT NOT NULL
          )
        ''');
      } else if (!hasTodoufukenPk) {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS todoufuken_new (
            todoufuken_id INTEGER NOT NULL PRIMARY KEY,
            todoufuken_name TEXT NOT NULL
          )
        ''');
        await txn.execute('''
          INSERT OR IGNORE INTO todoufuken_new (todoufuken_id, todoufuken_name)
          SELECT todoufuken_id, todoufuken_name FROM todoufuken
        ''');
        await txn.execute('DROP TABLE IF EXISTS todoufuken');
        await txn.execute('ALTER TABLE todoufuken_new RENAME TO todoufuken');
      }

      // version: PRIMARY KEY(user_id, name)
      final versionExists = await _tableExists(txn, 'version');
      final hasVersionPk =
          versionExists &&
          await _hasPrimaryKeyOn(txn, 'version', ['user_id', 'name']);
      if (!versionExists) {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS version (
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            version INTEGER NOT NULL,
            PRIMARY KEY(user_id, name)
          )
        ''');
      } else if (!hasVersionPk) {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS version_new (
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            version INTEGER NOT NULL,
            PRIMARY KEY(user_id, name)
          )
        ''');
        await txn.execute('''
          INSERT OR IGNORE INTO version_new (user_id, name, version)
          SELECT user_id, name, version FROM version
        ''');
        await txn.execute('DROP TABLE IF EXISTS version');
        await txn.execute('ALTER TABLE version_new RENAME TO version');
      }
    });
  }

  Future<bool> _hasPrimaryKeyOn(
    DatabaseExecutor db,
    String table,
    List<String> pkColumns,
  ) async {
    try {
      final rows = await db.rawQuery('PRAGMA table_info($table)');
      if (rows.isEmpty) return false;
      final Map<String, int> pkMap = {
        for (final row in rows) (row['name'] as String): (row['pk'] as int),
      };
      for (final col in pkColumns) {
        if (!(pkMap[col] != null && pkMap[col]! > 0)) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    try {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // バージョン3: todoufuken に chihou_name 列を追加
  Future<void> _migrateToV3(Database db) async {
    await db.transaction((txn) async {
      final hasCol = await _columnExists(txn, 'todoufuken', 'chihou_name');
      if (!hasCol) {
        await txn.execute("ALTER TABLE todoufuken ADD COLUMN chihou_name TEXT");
      }
    });
  }

  // バージョン4: kubun テーブルの追加
  Future<void> _migrateToV4(Database db) async {
    await db.transaction((txn) async {
      final exists = await _tableExists(txn, 'kubun');
      if (!exists) {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS kubun (
            id INTEGER NOT NULL PRIMARY KEY,
            kubun_name TEXT NOT NULL,
            note TEXT
          )
        ''');
      }
    });
  }

  Future<void> _migrateToV5(Database db) async {
    await db.transaction((txn) async {
      await _migrateLegacyTeibouIfNeeded(txn);
      await _migrateFavoriteTeibouSpotIdIfNeeded(txn);
    });
  }

  Future<void> _migrateLegacyTeibouIfNeeded(DatabaseExecutor db) async {
    final hasTeibou = await _tableExists(db, 'teibou');
    if (!hasTeibou) return;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS spots (
        spot_id INTEGER NOT NULL PRIMARY KEY,
        spot_name TEXT NOT NULL,
        furigana TEXT NOT NULL,
        j_yomi TEXT DEFAULT NULL,
        kubun TEXT NOT NULL,
        address TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        note TEXT NOT NULL
      )
    ''');

    final idColumn =
        await _columnExists(db, 'teibou', 'spot_id') ? 'spot_id' : 'port_id';
    final nameColumn =
        await _columnExists(db, 'teibou', 'spot_name')
            ? 'spot_name'
            : 'port_name';
    await db.execute('''
      INSERT OR IGNORE INTO spots (
        spot_id, spot_name, furigana, j_yomi, kubun, address, latitude, longitude, note
      )
      SELECT $idColumn, $nameColumn, furigana, j_yomi, kubun, address, latitude, longitude, note
      FROM teibou
    ''');

    await db.execute('DROP TABLE IF EXISTS teibou');
  }

  Future<void> _migrateFavoriteTeibouSpotIdIfNeeded(DatabaseExecutor db) async {
    final exists = await _tableExists(db, 'favorite_teibou');
    if (!exists) return;
    if (await _columnExists(db, 'favorite_teibou', 'spot_id')) return;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorite_teibou_new (
        spot_id INTEGER NOT NULL PRIMARY KEY,
        created_at INTEGER
      )
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO favorite_teibou_new (spot_id, created_at)
      SELECT port_id, created_at FROM favorite_teibou
    ''');
    await db.execute('DROP TABLE IF EXISTS favorite_teibou');
    await db.execute(
      'ALTER TABLE favorite_teibou_new RENAME TO favorite_teibou',
    );
  }

  Future<bool> _columnExists(
    DatabaseExecutor db,
    String table,
    String column,
  ) async {
    try {
      final rows = await db.rawQuery('PRAGMA table_info($table)');
      for (final row in rows) {
        if ((row['name'] as String).toLowerCase() == column.toLowerCase())
          return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> addFavorite(String prefecture, String pointName) async {
    final db = await database;

    // すでに存在するかチェック
    final result = await db.query(
      'favorite_tbl',
      where: 'prefecture = ? AND point_name = ?',
      whereArgs: [prefecture, pointName],
    );

    if (result.isEmpty) {
      await db.insert('favorite_tbl', {
        'prefecture': prefecture,
        'point_name': pointName,
      });
    } else {}
    int cnt = await countFavorites();
  }

  Future<void> removeFavorite(String prefecture, String pointName) async {
    final db = await database;

    await db.delete(
      'favorite_tbl',
      where: 'prefecture = ? AND point_name = ?',
      whereArgs: [prefecture, pointName],
    );
    int cnt = await countFavorites();
  }

  Future<List<Map<String, String>>> getFavorite() async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query('favorite_tbl');
    int cnt = await countFavorites();
    return maps.map((row) {
      return {
        'prefecture': row['prefecture'] as String,
        'point_name': row['point_name'] as String,
      };
    }).toList();
  }

  Future<int> countFavorites() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM favorite_tbl');
    int count = Sqflite.firstIntValue(result) ?? 0;
    return count;
  }

  // spots と todoufuken を結合し、全釣り場情報を取得
  // MySQL: LEFT(CAST(t.spot_id AS CHAR), 2) = p.todoufuken_id に相当する条件を
  // SQLite では CAST(substr(CAST(t.spot_id AS TEXT),1,2) AS INTEGER) を用いて実現
  Future<List<Map<String, dynamic>>> getAllTeibouWithPrefecture() async {
    final db = await database;
    final sql = '''
      SELECT
        t.spot_id,
        t.spot_name,
        t.furigana,
        t.j_yomi,
        t.kubun,
        t.address,
        t.latitude,
        t.longitude,
        t.flag,
        t.private,
        t.registrant_name,
        t.user_id,
        t.note,
        t.create_at,
        CAST(substr(CAST(t.spot_id AS TEXT), 1, 2) AS INTEGER) AS pref_id_from_port,
        p.todoufuken_id,
        p.todoufuken_name,
        p.chihou_name
      FROM spots AS t
      LEFT JOIN todoufuken AS p
        ON CAST(substr(CAST(t.spot_id AS TEXT), 1, 2) AS INTEGER) = p.todoufuken_id
      WHERE COALESCE(t.flag, 0) NOT IN (-2, -3)
      ORDER BY pref_id_from_port, t.j_yomi
    ''';
    final rows = await db.rawQuery(sql);
    return rows;
  }

  Future<List<Map<String, dynamic>>> getTodoufukenAll() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT todoufuken_id, todoufuken_name, chihou_name FROM todoufuken
    ''');
  }
}
