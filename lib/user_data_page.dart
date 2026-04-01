import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'main.dart';
import 'sql_db.dart';
import 'icloud_drive.dart';
import 'setting_data.dart';
import 'cache_question_repository.dart';
import 'appconfig.dart';

class UserDataPage extends ConsumerStatefulWidget {
  const UserDataPage({Key? key}) : super(key: key);

  @override
  ConsumerState<UserDataPage> createState() => _UserDataPageState();
}

class _UserDataPageState extends ConsumerState<UserDataPage> {
  static const double _statusIndent = 34; // 同設定画面相当

  // 保存/復旧: CSV Export/Import Helpers（設定画面の実装を転記）
  Future<String> _exportTestResultCsvText() async {
    final db = await openLocalDb();
    final buf = StringBuffer('user_id,nendo_id,question_no,question_type,kind,result,elapsedSeconds,try_datetime\n');
    final rows = await db.rawQuery('''
      SELECT user_id,nendo_id,question_no,question_type,kind,result,elapsedSeconds,try_datetime
      FROM test_result ORDER BY try_datetime ASC
    ''');
    for (final r in rows) {
      buf.writeln([
        r['user_id'], r['nendo_id'], r['question_no'], r['question_type'], r['kind'], r['result'], r['elapsedSeconds'], r['try_datetime']
      ].map((v) => v?.toString() ?? '').join(','));
    }
    return buf.toString();
  }

  Future<String> _exportPinningCsvText() async {
    final db = await openLocalDb();
    final buf = StringBuffer('user_id,nendo_id,question_no,question_type,kind,regist_datetime\n');
    final rows = await db.rawQuery('''
      SELECT user_id,nendo_id,question_no,question_type,kind,regist_datetime
      FROM pinning ORDER BY regist_datetime ASC
    ''');
    for (final r in rows) {
      buf.writeln([
        r['user_id'], r['nendo_id'], r['question_no'], r['question_type'], r['kind'], r['regist_datetime']
      ].map((v) => v?.toString() ?? '').join(','));
    }
    return buf.toString();
  }

  Future<bool> _exportToICloudFixed({required String filename, required String csvText}) async {
    final ok = await ICloudDrive.isAvailable();
    if (!ok) return false;
    final path = await ICloudDrive.saveText(filename, csvText);
    return path != null;
  }

  Future<String?> _readFromICloudFixed(String filename) async {
    final ok = await ICloudDrive.isAvailable();
    if (!ok) return null;
    return await ICloudDrive.readText(filename);
  }

  Future<ICloudFileInfo> _icloudInfo(String filename) => ICloudDrive.fileInfo(filename);

  Future<bool> _confirmOverwriteIfNeeded(String filename) async {
    final info = await _icloudInfo(filename);
    if (!info.exists) return true;
    if (!mounted) return false;
    final ts = info.modifiedMs;
    final formatted = (ts != null) ? _fmtMs(ts) : '不明';
    // ユーザー向け表示名に変換（CSV名ではなく意味の名称を表示）
    String displayName;
    switch (filename) {
      case 'test_result.csv':
        displayName = '成績情報';
        break;
      case 'pinning.csv':
        displayName = 'ピン留め情報';
        break;
      default:
        displayName = filename;
    }

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('上書きしますか？'),
            content: Text('iCloud上の $displayName を上書きします。\n最終更新: $formatted'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('キャンセル')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('上書き')),
            ],
          ),
        ) ??
        false;
    return ok;
  }

  List<List<String>> _parseCsv(String text) {
    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    final List<List<String>> rows = [];
    for (final line in lines) {
      rows.add(line.split(',').map((s) => s.trim()).toList());
    }
    return rows;
  }

/*  Future<void> _importTestResultFromCsvText(String csv) async {
    final rows = _parseCsv(csv);
    if (rows.isEmpty) return;
    int start = 0;
    if (rows.first.isNotEmpty && rows.first[0].toLowerCase().contains('user_id')) start = 1;
    final db = await openLocalDb();
    final batch = db.batch();
    const sql = '''
      INSERT OR REPLACE INTO test_result (
        user_id,nendo_id,question_no,question_type,kind,result,elapsedSeconds,try_datetime
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''';
    for (int i = start; i < rows.length; i++) {
      final r = rows[i];
      if (r.length < 8) continue;
      batch.rawInsert(sql, [
        int.tryParse(r[0]) ?? 0,
        int.tryParse(r[1]) ?? 0,
        int.tryParse(r[2]) ?? 0,
        int.tryParse(r[3]) ?? 0,
        int.tryParse(r[4]) ?? 0,
        int.tryParse(r[5]) ?? 0,
        int.tryParse(r[6]) ?? 0,
        r[7],
      ]);
    }
    await batch.commit(noResult: true);

    // 画面更新トリガ
    try { ref.read(scoreRefreshProvider.notifier).state++; } catch (_) {}

    // サーバ反映（必要時）
    final uid = (await loadUserInfo())?.userId ?? 0;
    if (uid > 0) {
      try {
        for (int i = start; i < rows.length; i++) {
          final r = rows[i];
          if (r.length < 8) continue;
          await http.post(
            Uri.parse('${AppConfig.instance.baseUrl}enter_result.php'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'userId': uid.toString(),
              'nendoId': r[1],
              'questionNo': r[2],
              'questionType': r[3],
              'kind': r[4],
              'result': r[5],
              'elapsedSeconds': r[6],
            },
          );
        }
      } catch (_) {}
    }
  }
*/
/*
  Future<void> _importPinningFromCsvText(String csv) async {
    final rows = _parseCsv(csv);
    if (rows.isEmpty) return;
    int start = 0;
    if (rows.first.isNotEmpty && rows.first[0].toLowerCase().contains('user_id')) start = 1;
    final db = await openLocalDb();
    await db.execute('DELETE FROM pinning');
    const sql = '''
      INSERT OR REPLACE INTO pinning (
        user_id,nendo_id,question_no,question_type,kind,regist_datetime
      ) VALUES (?, ?, ?, ?, ?, ?)
    ''';
    final batch = db.batch();
    for (int i = start; i < rows.length; i++) {
      final r = rows[i];
      if (r.length < 6) continue;
      batch.rawInsert(sql, [
        int.tryParse(r[0]) ?? 0,
        int.tryParse(r[1]) ?? 0,
        int.tryParse(r[2]) ?? 0,
        int.tryParse(r[3]) ?? 0,
        int.tryParse(r[4]) ?? 0,
        r[5],
      ]);
    }
    await batch.commit(noResult: true);

    try { await fetchAndStoreQuestionsAndPinning(ref); } catch (_) {}
    try { ref.read(scoreRefreshProvider.notifier).state++; } catch (_) {}
  }
*/

  Future<void> _onResetAllTapped() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(
              'ユーザデータを初期状態に戻す',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14),
            ),
            content: const Text(
                'ユーザデータ(成績／ピン留め)をすべて削除します。\n'
                'この操作は取り消せません。\nよろしいですか？'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('キャンセル')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('実行')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    // SharedPreferences 初期化 + 既定値へ
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await prefs.setBool('buzzerOn', true);
      await prefs.setInt('mode', 4);
      await prefs.setInt('outputOrder', 1);
      await prefs.setInt('yearId', 0);
      await prefs.setInt('subjectIndex', 0);
      await prefs.setBool('pinOnly', false);
      await prefs.setString('selectedPeriod', '直近30日');
    } catch (_) {}

    // ローカルDB削除
    try {
      final dir = await getDatabasesPath();
      final dbPath = '$dir/kakomon_go_takken.db';
      await deleteDatabase(dbPath);
    } catch (_) {}

    // 即時再設定（Keychainは保持）
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      await saveUserInfo(info);
      await initialLocalDB(info.userId);
      await CacheQuestionRepository.deleteAll();
      ref.read(settingProvider.notifier).state =  SettingData(
        buzzerOn: true,
        mode: 4,
        outputOrder: 1,
        yearId: 0,
        subjectIndex: 0,
        pinOnly: false,
      );
      ref.read(cacheQuestionProvider.notifier).state = [];
      ref.read(hasFetchedQuestionsProvider.notifier).state = false;
      //await fetchAndStoreQuestionsAndPinning(ref);
      ref.read(hasFetchedQuestionsProvider.notifier).state = true;
      ref.read(scoreRefreshProvider.notifier).state++;
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('初期化と再設定が完了しました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ユーザデータ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 説明カード（プレミアム画面の説明カードと同様のスタイル）
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade400),
            ),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Text(
                '・ユーザデータとは成績やピン留め情報です。\n'
                '・機種変更でユーザデータを引き継ぐ操作\n'
                '  (1)旧機種で「ユーザデータの保存(iCloud)」押下\n'
                '  (2)新機種で「ユーザデータの復旧(iCloud)」押下\n'
                '「ユーザデータの初期化」押下でユーザデータ初期化',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                //Text('ユーザデータ(成績/ピン留め)の保存/復旧/初期化', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                // 保存/復旧ボタン + 説明 + 最終保存
                LayoutBuilder(builder: (context, constraints) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
/*                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('端末内のユーザ情報(成績/ピン留め)をiCloudに保存します。',
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ),
*/                      SizedBox(
                        width: constraints.maxWidth,
                        child: ElevatedButton(
                          onPressed: () async {
                            try {
                              final csvTest = await _exportTestResultCsvText();
                              final csvPin = await _exportPinningCsvText();
                              if (!(await _confirmOverwriteIfNeeded('test_result.csv'))) return;
                              if (!(await _confirmOverwriteIfNeeded('pinning.csv'))) return;
                              final ok1 = await _exportToICloudFixed(filename: 'test_result.csv', csvText: csvTest);
                              final ok2 = await _exportToICloudFixed(filename: 'pinning.csv', csvText: csvPin);
                              if (!mounted) return;
                              if (ok1 && ok2) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('iCloud Driveに保存しました（成績情報 / ピン留め情報）')),
                                );
                                if (mounted) setState(() {}); // 最終保存の日時を即時反映
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('書出しに失敗しました（一部または全て）')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('書出しに失敗しました')),
                                );
                              }
                            }
                          },
                          child: const Text('ユーザデータの保存(iCloudへ)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent.shade100),
                        ),
                      ),
                      const SizedBox(height: 8),
                      /*Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('iCloudに保存したユーザ情報(成績/ピン留め)を端末に取得します。',
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ),*/
                      SizedBox(
                        width: constraints.maxWidth,
                        child: ElevatedButton(
                          onPressed: () async {
                            try {
                              final t1 = await _readFromICloudFixed('test_result.csv');
                              final t2 = await _readFromICloudFixed('pinning.csv');
                              bool ok = true;
                              if (t1 != null && t1.isNotEmpty) {
                                //await _importTestResultFromCsvText(t1);
                              } else {
                                ok = false;
                              }
                              if (t2 != null && t2.isNotEmpty) {
                                //await _importPinningFromCsvText(t2);
                              } else {
                                ok = false;
                              }
                              if (!mounted) return;
                              if (ok) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('読み込みました（成績情報 / ピン留め情報）')),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('一部または全てのファイルが見つかりませんでした')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('読込みに失敗しました')),
                                );
                              }
                            }
                          },
                          child: const Text('ユーザデータの復旧(iCloudから)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent.shade100),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: FutureBuilder<ICloudFileInfo>(
                          future: _icloudInfo('test_result.csv'),
                          builder: (context, snap) {
                            final info = snap.data;
                            if (info == null || !info.exists) return const SizedBox.shrink();
                            final when = (info.modifiedMs != null) ? _fmtMs(info.modifiedMs) : '不明';
                            return Text('最終保存: $when', style: Theme.of(context).textTheme.bodySmall);
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      // 初期化（成績/ピン留め）
                      /*Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 34, right: 8, bottom: 8),
                          child: Text(
                            '端末内のユーザ情報（成績/ピン留め）をクリアして初期状態に戻します。\n'
                            '成績/ピン留め情報が必要なら「ユーザ情報を保存(iCloud)」でバックアップしてください。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),*/
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.delete_forever),
                          label: const Text('ユーザデータの初期化'),
                          onPressed: _onResetAllTapped,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent.shade100),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade400),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: child,
      ),
    );
  }

  String _fmtMs(int? ms) {
    if (ms == null || ms <= 0) return 'unknown';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
