// settings_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, File;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException, Clipboard, ClipboardData; // copy CSV
// import 'package:flutter/services.dart'; // 削除: クリップボード未使用のため

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sqflite/sqflite.dart';
import 'package:share_plus/share_plus.dart';
//import 'package:file_picker/file_picker.dart';
import 'icloud_drive.dart';
//import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'setting_data.dart';
import 'cache_question_repository.dart';
import 'user_data_page.dart';

// main.dart で定義した provider 群を使用（settingProvider / userInfoProvider / entitlementVersionProvider）
import 'main.dart';
import 'log_print.dart';
import 'test_debug_print.dart';
import 'new_account_page.dart';
import 'edit_account_page.dart';
import 'html_view_page.dart';
import 'sql_db.dart';
import 'appconfig.dart';
import 'db_rebuild_screen.dart';

// Unify verification endpoint in one place
String kVerifyUrl = '${AppConfig.instance.baseUrl}verify.php';
String kEnterResultUrl = '${AppConfig.instance.baseUrl}enter_result.php';
String kEnterPinUrl = '${AppConfig.instance.baseUrl}enter_pin.php';

typedef YearModeCallback = void Function(String year, int id, int mode, String action);

class SettingsScreen extends ConsumerStatefulWidget {
  final YearModeCallback onYearSelected;

  const SettingsScreen({Key? key, required this.onYearSelected}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with WidgetsBindingObserver {
  static const double _leadingIconSize = 22;
  static const double _leadingGap = 12;
  static const double _statusIndent = _leadingIconSize + _leadingGap; // 34px

  String? _entProductId;
  int? _entExpiresMs;
  String? _entEnvironment;
  bool _busyHeaderRefresh = false;
  bool _busyHeaderRestore = false;
  bool _hasReceiptData = false;

  static const int _clockDriftMs = 30000; // 端末時計猶予
  int _lastHeaderRefreshMs = 0;
  Timer? _autoRefreshTimer;
  bool _resetting = false;

  // use top-level kVerifyUrl

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _restoreSub; // ← 復元イベント購読を追加

  // ───────────── CSV Import/Export Helpers ─────────────
  Future<String> _exportTestResultCsvText() async {
    final db = await openLocalDb();
    // ヘッダ
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

  Future<String> _writeCsvFile(String basename, String csvText) async {
    final dir = await getDatabasesPath();
    final ts = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${ts.year}${two(ts.month)}${two(ts.day)}_${two(ts.hour)}${two(ts.minute)}${two(ts.second)}';
    final path = '$dir/${basename}_$stamp.csv';
    final f = File(path);
    await f.writeAsString(csvText);
    return path;
  }

  Future<void> _shareCsvFile(String basename, String csvText) async {
    // Deprecated path: kept for fallback or Android; on iOS we prefer iCloud container direct save.
    final path = await _writeCsvFile(basename, csvText);
    final xfile = XFile(path, mimeType: 'text/csv', name: path.split('/').last);
    await Share.shareXFiles([xfile], text: '$basename CSV');
  }

  // ───────────── iCloud Container helpers ─────────────
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
    // 表示名（ユーザー向け）へ変換
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

  Future<void> _showCsvTextSheet({required String title, required String csvText, String? savedPath}) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleMedium),
              if (savedPath != null) ...[
                const SizedBox(height: 6),
                Text('保存先: $savedPath', style: Theme.of(ctx).textTheme.bodySmall),
              ],
              const SizedBox(height: 8),
              SizedBox(
                height: 240,
                child: SingleChildScrollView(
                  child: SelectableText(csvText, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: csvText));
                      if (mounted) Navigator.of(ctx).pop();
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSVをコピーしました')));
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('コピー'),
                  ),
                  const SizedBox(width: 8),
                  Text('(外部保存はこのテキストをお使いください)', style: Theme.of(ctx).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<List<String>> _parseCsv(String text) {
    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    final List<List<String>> rows = [];
    for (final line in lines) {
      // 単純CSV（カンマ区切り、ダブルクオート非対応）
      rows.add(line.split(',').map((s) => s.trim()).toList());
    }
    return rows;
  }
/*
  Future<void> _importTestResultFromCsvText(String csv) async {
    final rows = _parseCsv(csv);
    if (rows.isEmpty) return;
    // ヘッダ判定
    int start = 0;
    if (rows.first.isNotEmpty && rows.first[0].toLowerCase().contains('user_id')) start = 1;
    final db = await openLocalDb();
    // 置換インポート: 既存テーブルを再作成
    await db.execute('DROP TABLE IF EXISTS test_result');
    await createTestResult(db);
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

    // サーバにも反映（負荷を下げたい場合はスキップ可能）
    // 成績画面へ即時反映させるためのリフレッシュ通知
    try {
      ref.read(scoreRefreshProvider.notifier).state++;
    } catch (_) {}

    final uid = (await loadUserInfo())?.userId ?? 0;
    if (uid > 0) {
      try {
        for (int i = start; i < rows.length; i++) {
          final r = rows[i];
          if (r.length < 8) continue;
          await http.post(
            Uri.parse(kEnterResultUrl),
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
  Future<void> _importTestResultFromPickedFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final path = file.path;
    if (path == null) return;
    final text = await File(path).readAsString();
    await _importTestResultFromCsvText(text);
  }

  Future<void> _importPinningFromCsvText(String csv) async {
    final rows = _parseCsv(csv);
    if (rows.isEmpty) return;
    int start = 0;
    if (rows.first.isNotEmpty && rows.first[0].toLowerCase().contains('user_id')) start = 1;
    final db = await openLocalDb();
    // 置換インポート: 既存ピンをクリア
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

    // ピン一覧を即座にUIへ反映（Providerを最新DBで更新）
    try {
      await fetchAndStoreQuestionsAndPinning(ref);
    } catch (_) {}

    // 成績画面は test_result 参照だが、将来の拡張に備えて通知
    try {
      ref.read(scoreRefreshProvider.notifier).state++;
    } catch (_) {}

    // サーバにも反映（pin=1 として登録）
    final uid = (await loadUserInfo())?.userId ?? 0;
    if (uid > 0) {
      try {
        for (int i = start; i < rows.length; i++) {
          final r = rows[i];
          if (r.length < 6) continue;
          await http.post(
            Uri.parse(kEnterPinUrl),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'userId': uid.toString(),
              'nendoId': r[1],
              'questionNo': r[2],
              'questionType': r[3],
              'kind': r[4],
              'pin': '1',
            },
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _importPinningFromPickedFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final path = file.path;
    if (path == null) return;
    final text = await File(path).readAsString();
    await _importPinningFromCsvText(text);
  }
*/
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadHeaderFromPrefs();

    // 設定画面でも purchaseStream を購読して、restorePurchases() の restored を拾う
    _restoreSub = _iap.purchaseStream.listen(
      _onPurchasesFromRestore,
      onError: (e) {
        testDebugPrint('[Settings] purchaseStream error: $e');
      },
    );

    // 起動直後にレシート更新＋サーバ再検証を行い、権利状態を自動反映
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshReceiptAndSyncHeader();
    });

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _autoRefreshIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _restoreSub?.cancel();
    super.dispose();
  }

  Future<void> _onResetAllTapped() async {
    if (_resetting) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('データ完全初期化'),
            content: const Text(
                '端末内のデータ（成績／ピン留め）をすべて削除します。\n'
                'この操作は取り消せません。よろしいですか？'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('キャンセル')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('実行')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() => _resetting = true);
    try {
      // 1) アカウントは削除しない（Keychainは保持）

      // 2) SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        // 初回起動相当の既定値も保存しておく（年/科目/モード/順序/ピン）
        await prefs.setBool('buzzerOn', true);
        await prefs.setInt('mode', 4);
        await prefs.setInt('outputOrder', 1);
        await prefs.setInt('yearId', 0);
        await prefs.setInt('subjectIndex', 0);
        await prefs.setBool('pinOnly', false);
        // 成績期間の初期値
        await prefs.setString('selectedPeriod', '直近30日');
      } catch (_) {}

      // 3) ローカルDB（sqflite）
      try {
        final dir = await getDatabasesPath();
        final dbPath = '$dir/kakomon_go_takken.db';
        await deleteDatabase(dbPath);
      } catch (_) {}

      // 4) 即時に再設定（通常起動時相当）
      try {
        final info = await getOrInitUserInfo();
        await saveUserInfo(info);
        await initialLocalDB(info.userId);
        // ランダム順などのキャッシュ（question_cache）も明示的にクリア
        await CacheQuestionRepository.deleteAll();
      } catch (_) {}

      // 5) Providerをリフレッシュ（設定/キャッシュ/一覧/成績）
      try {
        // 設定は既定値に戻す
        ref.read(settingProvider.notifier).state = SettingData(
          buzzerOn: true,
          mode: 4,
          outputOrder: 1,
          yearId: 0,
          subjectIndex: 0,
          pinOnly: false,
        );
        // キャッシュクリア→一覧更新（メモリ側）
        ref.read(cacheQuestionProvider.notifier).state = [];
        ref.read(hasFetchedQuestionsProvider.notifier).state = false;
        //await fetchAndStoreQuestionsAndPinning(ref);
        ref.read(hasFetchedQuestionsProvider.notifier).state = true;
        // 成績の再計算
        ref.read(scoreRefreshProvider.notifier).state++;
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('初期化と再設定が完了しました')),
      );
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshReceiptAndSyncHeader();
    }
  }

  void _autoRefreshIfNeeded() {
    if (!mounted) return;
    final expires = _entExpiresMs;
    if (expires == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sinceLast = now - _lastHeaderRefreshMs;
    if (_busyHeaderRefresh || _busyHeaderRestore) return;

    if (!_isActive(expires)) {
      if (sinceLast > 3000) _refreshReceiptAndSyncHeader();
      return;
    }

    final msUntilExpiry = expires - (now + _clockDriftMs);
    if (msUntilExpiry <= 10000 && sinceLast > 3000) {
      _refreshReceiptAndSyncHeader();
    }
  }

  bool _isActive(int? expiresMs) {
    if (expiresMs == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now + _clockDriftMs) < expiresMs;
  }

  Future<void> _loadHeaderFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final exp = prefs.getInt('expiresDateMs');
    final pid = prefs.getString('currentProductId');
    final receipt = prefs.getString('lastReceiptData');
    if (!mounted) return;
    setState(() {
      _entExpiresMs = exp;
      _entProductId = pid;
      _hasReceiptData = (receipt != null && receipt.isNotEmpty);
    });
  }

  Future<void> _refreshReceiptAndSyncHeader() async {
    if (_busyHeaderRefresh) return;
    _lastHeaderRefreshMs = DateTime.now().millisecondsSinceEpoch;
    setState(() => _busyHeaderRefresh = true);
    try {
      if (Platform.isIOS) {
        try {
          final add = _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
          final dyn = add as dynamic;
          // まずは refreshReceipt を呼ばずに検証データだけ取得
          String receiptBase64 = '';
          try {
            final ver = await dyn.refreshPurchaseVerificationData();
            receiptBase64 = (ver.serverVerificationData as String?)
                    ?.replaceAll('\n', '')
                    .replaceAll('\r', '')
                    .trim() ??
                '';
          } catch (_) {}
          // 空なら refreshReceipt を一度だけ試す（ユーザー操作起点なので許容）
          if (receiptBase64.isEmpty) {
            try {
              await dyn.refreshReceipt();
              final ver2 = await dyn.refreshPurchaseVerificationData();
              receiptBase64 = (ver2.serverVerificationData as String?)
                      ?.replaceAll('\n', '')
                      .replaceAll('\r', '')
                      .trim() ??
                  '';
            } catch (_) {}
          }
          if (receiptBase64.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('lastReceiptData', receiptBase64);
            if (mounted) setState(() => _hasReceiptData = true);
            // productId の補完
            final lastPid = prefs.getString('lastProductId');
            final currPid = prefs.getString('currentProductId');
            if (lastPid == null && currPid != null) {
              await prefs.setString('lastProductId', currPid);
            }
          }
        } catch (_) {}
      }
      await _reverifyFromSavedReceipt();
    } finally {
      if (mounted) setState(() => _busyHeaderRefresh = false);
    }
  }

  Future<void> _restoreAndSyncHeader() async {
    if (_busyHeaderRestore) return;
    setState(() => _busyHeaderRestore = true);
    try {
      if (Platform.isIOS) {
        try {
          final add =
              _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
          final dyn = add as dynamic;
          // まずは検証データだけ取得
          String receiptBase64 = '';
          try {
            final ver = await dyn.refreshPurchaseVerificationData();
            receiptBase64 = (ver.serverVerificationData as String?)
                    ?.replaceAll('\n', '')
                    .replaceAll('\r', '')
                    .trim() ??
                '';
          } catch (_) {}
          // 空なら refreshReceipt を一度だけ試す
          if (receiptBase64.isEmpty) {
            try {
              await dyn.refreshReceipt();
              final ver2 = await dyn.refreshPurchaseVerificationData();
              receiptBase64 = (ver2.serverVerificationData as String?)
                      ?.replaceAll('\n', '')
                      .replaceAll('\r', '')
                      .trim() ??
                  '';
            } catch (_) {}
          }
          if (receiptBase64.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('lastReceiptData', receiptBase64);
            if (mounted) setState(() => _hasReceiptData = true);
            final lastPid = prefs.getString('lastProductId');
            final currPid = prefs.getString('currentProductId');
            if (lastPid == null && currPid != null) {
              await prefs.setString('lastProductId', currPid);
            }
          }
        } catch (_) {}
      }
      // ここで復元を呼ぶと、restored イベントが purchaseStream に流れてくる → _onPurchasesFromRestore で処理
      await _iap.restorePurchases();

      // レシートのみで検証できるケースもあるので最後に再検証も実行
      await _reverifyFromSavedReceipt();

      if (mounted) {
        final envLabel = _entEnvironment ?? '不明';
        final when = _formatExpiry(_entExpiresMs) ?? 'なし';
        final msg = '購入情報を最新に更新しました（環境=$envLabel / 期限=$when）';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('購入情報の再取得に失敗しました')));
      }
    } finally {
      if (mounted) setState(() => _busyHeaderRestore = false);
    }
  }

  // ← 復元イベント（restorePurchases の結果）をここで処理する
  Future<void> _onPurchasesFromRestore(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        try {
          await _verifyAndSaveFromPurchaseDetails(p);
        } catch (e) {
          testDebugPrint('[Settings] verify error: $e');
        } finally {
          try {
            if (p.pendingCompletePurchase) {
              await _iap.completePurchase(p);
            }
          } catch (_) {}
        }
      }
    }
  }

  // purchase.details から verificationData を保存→サーバ検証→expiresDateMs/currentProductId を保存
  Future<void> _verifyAndSaveFromPurchaseDetails(PurchaseDetails p) async {
    final token = p.verificationData.serverVerificationData
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .trim();

    if (token.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastReceiptData', token);
    await prefs.setString('lastProductId', p.productID);

    final resp = await http.post(
      Uri.parse(kVerifyUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'productId': p.productID, 'receiptData': token}),
    );

    if (resp.statusCode != 200) return;

    final jsonResp = json.decode(resp.body) as Map<String, dynamic>;
    final isActive = jsonResp['isActive'] == true;
    final expiresMs =
        (jsonResp['expiresDateMs'] is num) ? (jsonResp['expiresDateMs'] as num).toInt() : null;
    final serverPid =
        (jsonResp['productId'] is String) ? jsonResp['productId'] as String : null;
    final env = (jsonResp['environment'] is String) ? jsonResp['environment'] as String : null;
    final autoRenew = (jsonResp['autoRenewStatus'] is String)
        ? jsonResp['autoRenewStatus'] as String
        : null; // '1' or '0'
    final reason = (jsonResp['reason'] is String) ? jsonResp['reason'] as String : null;

    if (isActive) {
      if (expiresMs != null) {
        await prefs.setInt('expiresDateMs', expiresMs);
        // 最終既知の有効期限も更新（起動直後の楽観的判定で使用）
        await prefs.setInt('lastExpiresDateMs', expiresMs);
      }
      if (serverPid != null) await prefs.setString('currentProductId', serverPid);
      if (mounted) {
        setState(() {
          _entExpiresMs = expiresMs ?? _entExpiresMs;
          _entProductId = serverPid ?? _entProductId;
          _entEnvironment = env ?? _entEnvironment;
        });
      }
      // Home に再描画を促す
      try {
        ref.read(entitlementVersionProvider.notifier).state++;
      } catch (_) {}
      // 復元操作中であれば、環境と有効期限を軽く表示
      if (mounted && _busyHeaderRestore) {
        final when = _formatExpiry(expiresMs);
        final labelEnv = env ?? '不明';
        final msg = '復元結果: 環境=$labelEnv / 期限=${when ?? 'なし'}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }

      // ログ出力: 購入/復元（expires_at が unknown の場合はログしない）
      if (expiresMs != null) {
        final purchasedMs = int.tryParse(p.transactionDate ?? '') ?? 0;
        final purchasedAt = _fmtMs(purchasedMs);
        final expiresAt = _fmtMs(expiresMs);
        final autoLabel = (autoRenew == '1') ? 'ON' : (autoRenew == '0') ? 'OFF' : 'unknown';
        logPrint('purchase_or_restore product_id=${serverPid ?? p.productID} purchased_at=$purchasedAt expires_at=$expiresAt auto_renew_status=$autoLabel env=${env ?? 'unknown'}');
      }
    } else {
      // 明確に無効ならクリア。ただし直前の期限は lastExpiresDateMs に退避
      final prevExp = prefs.getInt('expiresDateMs');
      if (prevExp != null) {
        await prefs.setInt('lastExpiresDateMs', prevExp);
      } else if (expiresMs != null) {
        await prefs.setInt('lastExpiresDateMs', expiresMs);
      }
      await prefs.remove('expiresDateMs');
      await prefs.remove('currentProductId');
      // last* は残しておく（必要に応じて後続で再検証）
      if (mounted) {
        setState(() {
          _entExpiresMs = null;
          _entProductId = null;
          _entEnvironment = env ?? _entEnvironment;
        });
      }
      try {
        ref.read(entitlementVersionProvider.notifier).state++;
      } catch (_) {}
      if (mounted && _busyHeaderRestore) {
        final labelEnv = env ?? '不明';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('復元結果: 環境=$labelEnv / 未購入')));
      }

      // ログ出力: 検証失敗や未購入（理由があれば付与）
      final purchasedMs = int.tryParse(p.transactionDate ?? '') ?? 0;
      final purchasedAt = _fmtMs(purchasedMs);
      final r = reason ?? 'unknown';
      logPrint('verification_inactive product_id=${serverPid ?? p.productID} purchased_at=$purchasedAt reason=$r env=${env ?? 'unknown'}');
    }
  }

  // lastReceiptData / lastProductId → サーバ再検証 → Prefs + UI 反映
  Future<void> _reverifyFromSavedReceipt() async {
    final prefs = await SharedPreferences.getInstance();
    final receipt = prefs.getString('lastReceiptData');
    String? productId = prefs.getString('lastProductId');
    productId ??= prefs.getString('currentProductId');
    if (receipt == null) {
      await _loadHeaderFromPrefs();
      return;
    }

    final resp = await http.post(
      Uri.parse(kVerifyUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'productId': productId, 'receiptData': receipt}),
    );

    if (resp.statusCode == 200) {
      final jsonResp = json.decode(resp.body) as Map<String, dynamic>;
      final isActive = jsonResp['isActive'] == true;
      final expiresMs =
          (jsonResp['expiresDateMs'] is num) ? (jsonResp['expiresDateMs'] as num).toInt() : null;
      final serverPid =
          (jsonResp['productId'] is String) ? jsonResp['productId'] as String : null;
      final env =
          (jsonResp['environment'] is String) ? jsonResp['environment'] as String : null;
      final autoRenew = (jsonResp['autoRenewStatus'] is String)
          ? jsonResp['autoRenewStatus'] as String
          : null; // '1' or '0'
      final reason = (jsonResp['reason'] is String) ? jsonResp['reason'] as String : null;

      final prevExpires = prefs.getInt('expiresDateMs');
      final prevPid = prefs.getString('currentProductId');

      int? nextExpires = prevExpires;
      if (expiresMs != null) {
        nextExpires = expiresMs;
        await prefs.setInt('expiresDateMs', nextExpires);
        // 最終既知の期限も更新
        await prefs.setInt('lastExpiresDateMs', nextExpires);
      }

      String? nextPid = serverPid ?? prevPid;
      if (!isActive) {
        // Log the moment entitlement becomes inactive (expired)
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final expForLog = expiresMs ?? prevExpires;
        if (prevPid != null && expForLog != null && expForLog <= nowMs) {
          logPrint('expired product_id=$prevPid expires_at=${_fmtMs(expForLog)}');
        }
        // クリア前に直前の期限を退避
        final prevExpForLast = prefs.getInt('expiresDateMs');
        if (prevExpForLast != null) {
          await prefs.setInt('lastExpiresDateMs', prevExpForLast);
        } else if (expiresMs != null) {
          await prefs.setInt('lastExpiresDateMs', expiresMs);
        }
        await prefs.remove('currentProductId');
        await prefs.remove('expiresDateMs');
        nextPid = null;
        nextExpires = null;
      } else if (serverPid != null) {
        await prefs.setString('currentProductId', serverPid);
      }

      // auto_renew_status 変更検知
      final prevAuto = prefs.getString('autoRenewStatus');
      if (autoRenew != null) {
        await prefs.setString('autoRenewStatus', autoRenew);
      } else {
        await prefs.remove('autoRenewStatus');
      }

      // プラン変更検知
      final prevPidForLog = prevPid;

      if (!mounted) return;
      setState(() {
        _entExpiresMs = nextExpires;
        _entProductId = nextPid;
        _entEnvironment = env;
      });
      try {
        ref.read(entitlementVersionProvider.notifier).state++;
      } catch (_) {}

      // ログ: 更新/期限変更/失効/自動更新変更/プラン変更/グレース/キャンセル
      final expiresAt = _fmtMs(nextExpires);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (prevExpires != null && nextExpires != null && nextExpires > prevExpires) {
        if (nextPid != null) {
          logPrint('renewed product_id=$nextPid expires_at=$expiresAt');
        }
      }
      if (prevExpires != null && nextExpires != null && nextExpires <= nowMs) {
        if (prevPidForLog != null) {
          logPrint('expired product_id=$prevPidForLog expires_at=${_fmtMs(nextExpires)}');
        }
      }
      if (prevAuto != autoRenew && autoRenew != null) {
        final label = (autoRenew == '1') ? 'ON' : 'OFF';
        final pidForAuto = nextPid ?? prevPidForLog;
        if (pidForAuto != null) {
          logPrint('auto_renew_status_changed product_id=$pidForAuto new_status=$label');
        }
      }
      if (prevPidForLog != null && nextPid != null && prevPidForLog != nextPid) {
        logPrint('plan_changed from=$prevPidForLog to=$nextPid');
      }
      if (reason == 'grace_period') {
        final pidForGrace = nextPid ?? prevPidForLog;
        if (pidForGrace != null) {
          // サーバ応答に具体的な期限が無いので unknown とする
          logPrint('grace_period product_id=$pidForGrace grace_period_until=unknown');
        }
      }
      if (reason == 'cancelled') {
        final pidForCancel = nextPid ?? prevPidForLog;
        if (pidForCancel != null) {
          logPrint('refunded_or_cancelled product_id=$pidForCancel cancel_reason=cancelled');
        }
      }
    } else {
      await _loadHeaderFromPrefs();
    }
  }

  Future<void> _openManageSubscriptions() async {
    final uri = Platform.isIOS
        ? Uri.parse('https://apps.apple.com/account/subscriptions')
        : Uri.parse('https://play.google.com/store/account/subscriptions');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('サブスク管理ページを開けませんでした')));
    }
  }

  String _currentPlanLabel() {
    final active = _isActive(_entExpiresMs);
    final now = DateTime.now().millisecondsSinceEpoch;
    final recentlyRefreshed = (now - _lastHeaderRefreshMs) < 2500;
    final hasEntitlementHint = (_entProductId != null) && _hasReceiptData;

    if (!active) {
      final isVerifying =
          _busyHeaderRestore || ((_busyHeaderRefresh || recentlyRefreshed) && hasEntitlementHint);
      if (isVerifying) return '現在の状態 : 確認中';
      return '現在の状態 : 未購入';
    }

    final pid = _entProductId;
    String suffix = '';
    if (pid != null) {
      if (pid.endsWith('.year')) {
        suffix = '（年額）';
      } else if (pid.endsWith('.6month')) {
        suffix = '（6ヶ月）';
      } else if (pid.endsWith('.3month')) {
        suffix = '（3ヶ月）';
      } else if (pid.endsWith('.month')) {
        suffix = '（月額）';
      }
    }
    return '現在の状態 : 購入済みプラン $suffix';
  }

  // 共通: ms(UTC epoch) → 'YYYY/MM/DD HH/MM/SS'（null/0は 'unknown'）
  String _fmtMs(int? ms) {
    if (ms == null || ms <= 0) return 'unknown';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year.toString().padLeft(4, '0')}/${two(dt.month)}/${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Row(
      children: [
        const Icon(Icons.arrow_right, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
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

  Widget _actionRow({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool enabled = true,
    bool showSpinner = false,
    Widget? trailing,
    bool showChevron = false,
  }) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    final effectiveStyle =
        enabled ? textStyle : textStyle?.copyWith(color: Theme.of(context).disabledColor);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: _leadingIconSize,
              height: _leadingIconSize,
              child: Center(
                child: showSpinner
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icon, size: _leadingIconSize),
              ),
            ),
            const SizedBox(width: _leadingGap),
            Expanded(child: Text(label, style: effectiveStyle)),
            if (trailing != null) trailing,
            if (showChevron) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: Colors.grey.shade600),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final setting = ref.watch(settingProvider);
    final buzzerOn = setting.buzzerOn;

    final active = _isActive(_entExpiresMs);

    if (!active && !_busyHeaderRefresh) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastHeaderRefreshMs > 3000) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _refreshReceiptAndSyncHeader();
        });
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('設定'), toolbarHeight: 0),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 第一の「ユーザデータ」セクションは下段へ統合のため削除
          const SizedBox(height: 24),
          _sectionTitle(context, 'アカウント'),
          const SizedBox(height: 12),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    //const Icon(Icons.verified_user, size: _leadingIconSize),
                    const SizedBox(width: _leadingGap),
                    Expanded(
                  child: ref.watch(userInfoProvider).when(
                        loading: () => const Text('アカウント登録状態 : 読み込み中'),
                        error: (_, __) => const Text('アカウント登録状態 : 未'),
                        data: (userInfo) {
                          final email = userInfo?.email ?? '';
                          final statusText = email.isNotEmpty ? 'メール登録済み［$email］' : '未';
                          return Text('アカウント登録状態 : $statusText');
                        },
                      ),
                ),
                  ],
                ),
                // ユーザIDの表示（必要に応じてサポート連絡時などに参照）
                Padding(
                  padding: const EdgeInsets.only(left: _leadingGap, top: 2),
                  child: ref.watch(userInfoProvider).when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (userInfo) {
                          final uid = userInfo?.userId;
                          if (uid == null || uid <= 0) return const SizedBox.shrink();
                          return Text('ユーザID: $uid', style: Theme.of(context).textTheme.bodySmall);
                        },
                      ),
                ),
                const SizedBox(height: 6),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(left: 0),
                  child: Builder(
                    builder: (context) {
                      final asyncUser = ref.watch(userInfoProvider);
                      final isRegistered = ref.watch(isEmailRegisteredProvider);
                      final user = asyncUser.valueOrNull;
                      final currentEmail = user?.email ?? '';
                      final accountLabel = isRegistered ? 'アカウントの編集' : 'アカウントの登録';
                      final accountIcon = isRegistered ? Icons.manage_accounts : Icons.person_add_alt_1;
                      return _actionRow(
                        icon: accountIcon,
                        label: accountLabel,
                        onTap: () {
                          if (isRegistered) {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => EditAccountPage(currentEmail: currentEmail)),
                            );
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const NewAccountPage()),
                            );
                          }
                        },
                        enabled: true,
                        showChevron: true,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          _sectionTitle(context, '効果音'),
          const SizedBox(height: 12),
          _sectionCard(
            child: Row(
              children: [
                Icon(buzzerOn ? Icons.volume_up : Icons.volume_off, size: _leadingIconSize),
                const SizedBox(width: _leadingGap),
                Expanded(
                  child: Text('解答時の効果音を鳴らす', style: Theme.of(context).textTheme.bodyMedium),
                ),
                Switch(
                  value: buzzerOn,
                  onChanged: (v) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('buzzerOn', v);
                    ref.read(settingProvider.notifier).update((s) => s.copyWith(buzzerOn: v));
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          _sectionTitle(context, 'プレミアム'),
          const SizedBox(height: 12),

          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    //const Icon(Icons.monetization_on, size: _leadingIconSize),
                    const SizedBox(width: _leadingGap),
                    Expanded(
                      child: Text(
                        _currentPlanLabel(),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                if (active && _entExpiresMs != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: _statusIndent),
                    child: Text('有効期限: ${_formatExpiry(_entExpiresMs)}',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ],
                if (_entEnvironment != null && _entEnvironment != 'Production') ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: _statusIndent),
                    child: Text('環境: Sandbox', style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ],

                const SizedBox(height: 12),
                const Divider(height: 1),

                Padding(
                  padding: const EdgeInsets.only(left: 0),
                  child: _actionRow(
                    icon: Icons.workspace_premium_outlined,
                    label: active ? 'プレミアムの表示' : 'プレミアムの購入',
                    onTap: () {
                      Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const PaywallPage()))
                          .then((_) => _refreshReceiptAndSyncHeader());
                    },
                    showChevron: true,
                  ),
                ),

                // Restore button moved to Premium page bottom section.
              ],
            ),
          ),

          const SizedBox(height: 8),
          // ── 問題（メンテナンス） ──
          const SizedBox(height: 24),
          _sectionTitle(context, 'データの更新'),
          const SizedBox(height: 12),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _actionRow(
                  icon: Icons.storage,
                  label: '最新データの更新',
                  showChevron: true,
                  onTap: () async {
                    await Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const DbRebuildScreen()));
                    // 戻ってきたら問題・ピンのプロバイダを最新化
                    //try { await fetchAndStoreQuestionsAndPinning(ref); } catch (_) {}
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(left: _statusIndent, top: 6),
                  child: Text(
                    '用語集や法令データを最新に更新します。\n'
                    'Wi-Fi 環境での実行を推奨します（モバイル回線ではデータ通信料が発生する場合があります）。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                // const Divider(height: 16),
                // 参照関連法令の取得元は現状ローカル固定（UIスイッチは非表示）
              ],
            ),
          ),

          // ── メンテナンス ──
          const SizedBox(height: 24),
          _sectionTitle(context, 'ユーザデータ'),
          const SizedBox(height: 12),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ユーザ情報の保存/復旧（iCloud）
                // アンカーのみを表示（詳細は別画面へ移動）
                _actionRow(
                  icon: Icons.cloud_sync,
                  label: 'ユーザデータの保存/復旧/初期化',
                  showChevron: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UserDataPage()),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _sectionTitle(context, '法的情報'),
          const SizedBox(height: 12),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _actionRow(
                  icon: Icons.description_outlined,
                  label: '利用規約',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HtmlViewPage(
                          title: '利用規約',
                          url: '${AppConfig.instance.baseUrl}terms_of_use.html',
                        ),
                      ),
                    );
                  },
                  showChevron: true,
                ),
                const Divider(height: 1),
                _actionRow(
                  icon: Icons.privacy_tip_outlined,
                  label: 'プライバシーポリシー',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HtmlViewPage(
                          title: 'プライバシーポリシー',
                          url: '${AppConfig.instance.baseUrl}privacy_policy.html',
                        ),
                      ),
                    );
                  },
                  showChevron: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────
/// ここから：ペイウォール（変更なし：購読は従来通り）
/// ─────────────────────────────────────────────────────────

enum _PlanState { currentActive, other }

class PaywallPage extends ConsumerStatefulWidget {
  const PaywallPage({super.key});
  @override
  ConsumerState<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends ConsumerState<PaywallPage> {
  final InAppPurchase iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  List<ProductDetails> _products = [];
  String? _error;
  bool _loading = true;

  // use top-level kVerifyUrl
  static String _productsListUrl = '${AppConfig.instance.baseUrl}products.php';

  bool _verifying = false;
  final Set<String> _processingPurchaseIds = {};
  final Map<String, int> _latestTsByProduct = {};

  int? _expiresDateMs;
  String? _currentProductId;
  String? _environment;
  // 購入中フラグ（多重起動・連打対策）
  bool _purchasing = false;
  Timer? _purchasingTimeout;

  bool _busyRestore = false; // 下段の「購入情報を再取得 / 復元」ボタンの状態

  Timer? _autoRefreshTimer;
  int _lastRefreshMs = 0;
  static const int _clockDriftMs = 30000;

  bool get _isPremiumActive =>
      _expiresDateMs != null && DateTime.now().millisecondsSinceEpoch < _expiresDateMs!;

  @override
  void initState() {
    super.initState();

    _sub = iap.purchaseStream.listen(
      _onPurchases,
      onError: (e) {
        if (mounted) {
          setState(() {
            _error = e.toString();
            _purchasing = false;
          });
        }
      },
    );

    _initProducts();
    _loadEntitlement();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final info = await PackageInfo.fromPlatform();
      testDebugPrint('bundle/app id = ${info.packageName}');
      if (Platform.isIOS) {
        try {
          final iosAdd = iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
          final dyn = iosAdd as dynamic;
          try {
            await dyn.refreshReceipt();
          } catch (_) {
            try {
              await dyn.refreshPurchaseVerificationData();
            } catch (_) {}
          }
        } catch (_) {}
      }
      await _syncEntitlementFromSavedReceipt();
      // 自動復元は行わない（購入開始との競合でシート表示が遅延するのを避ける）
      // 復元はユーザー操作（「購入情報を再取得 / 復元」）で実施
    });

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _autoRefreshIfNeeded();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _autoRefreshTimer?.cancel();
    _purchasingTimeout?.cancel();
    super.dispose();
  }

  Future<void> _openManageSubscriptions() async {
    final uri = Platform.isIOS
        ? Uri.parse('https://apps.apple.com/account/subscriptions')
        : Uri.parse('https://play.google.com/store/account/subscriptions');

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('サブスク管理ページを開けませんでした')));
      }
    }
  }

  void _showManageInfo() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('プレミアムの閲覧 / 解約 / 変更 とは？',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: 10),
              Text(
                'プレミアムの内容を確認したり、解約やプラン変更を行うための画面を開きます。\n'
                'iOS: 設定 ＞ [ユーザ名]（Apple ID）＞ サブスクリプション\n'
                '※購入は Apple ID アカウントに紐づきます。',
                style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.5),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRestoreInfo() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Text(
            '・アプリ起動時に自動で購入状態を同期します。\n'
            '・反映されない場合や Apple ID 切替・機種変更直後は「購入情報を再取得 / 復元」を実行してください。\n'
            '・復元ではストアの購入履歴を再取得し、未完了の購入があれば整理します。\n'
            '（同一Apple ID のみ復元可能）\n',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        );
      },
    );
  }

  Future<void> _restorePurchasesAndSync() async {
    if (_busyRestore) return;
    setState(() => _busyRestore = true);
    try {
      if (Platform.isIOS) {
        try {
          final add = iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
          final dyn = add as dynamic;
          String receiptBase64 = '';
          try {
            final ver = await dyn.refreshPurchaseVerificationData();
            receiptBase64 = (ver.serverVerificationData as String?)
                    ?.replaceAll('\n', '')
                    .replaceAll('\r', '')
                    .trim() ??
                '';
          } catch (_) {}
          if (receiptBase64.isEmpty) {
            try {
              await dyn.refreshReceipt();
              final ver2 = await dyn.refreshPurchaseVerificationData();
              receiptBase64 = (ver2.serverVerificationData as String?)
                      ?.replaceAll('\n', '')
                      .replaceAll('\r', '')
                      .trim() ??
                  '';
            } catch (_) {}
          }
          if (receiptBase64.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('lastReceiptData', receiptBase64);
            // productId 補完
            final lastPid = prefs.getString('lastProductId');
            final currPid = prefs.getString('currentProductId');
            if (lastPid == null && currPid != null) {
              await prefs.setString('lastProductId', currPid);
            }
          }
        } catch (_) {}
      }
      await iap.restorePurchases();
      await _syncEntitlementFromSavedReceipt();

      if (mounted) {
        final envLabel = _environment ?? '不明';
        final when = _formatExpiry(_expiresDateMs) ?? 'なし';
        final msg = '購入情報を最新に更新しました（環境=$envLabel / 期限=$when）';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('購入情報の再取得に失敗しました')));
      }
    } finally {
      if (mounted) setState(() => _busyRestore = false);
    }
  }

  Future<void> _loadEntitlement() async {
    final prefs = await SharedPreferences.getInstance();
    final expMs = prefs.getInt('expiresDateMs');
    setState(() {
      _expiresDateMs = expMs;
      _currentProductId = prefs.getString('currentProductId');
    });
  }

  Future<void> _saveEntitlement(
    bool active, {
    int? expiresMs,
    String? productId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (expiresMs != null) {
      await prefs.setInt('expiresDateMs', expiresMs);
      // 最終既知の期限も更新
      await prefs.setInt('lastExpiresDateMs', expiresMs);
    } else {
      // クリアする場合は直前の値を lastExpiresDateMs に退避
      final prev = prefs.getInt('expiresDateMs');
      if (prev != null) {
        await prefs.setInt('lastExpiresDateMs', prev);
      }
      await prefs.remove('expiresDateMs');
    }
    if (productId != null) {
      await prefs.setString('currentProductId', productId);
    } else {
      await prefs.remove('currentProductId');
    }
    if (!mounted) return;
    setState(() {
      _expiresDateMs = expiresMs ?? _expiresDateMs;
      _currentProductId = productId ?? _currentProductId;
    });
    try {
      ref.read(entitlementVersionProvider.notifier).state++;
    } catch (_) {}
  }

  Future<List<String>> _fetchProductIds() async {
    try {
      final resp =
          await http.get(Uri.parse(_productsListUrl)).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        if (decoded is List) {
          final fromServer =
              decoded.whereType<String>().where((e) => e.trim().isNotEmpty).toList();
          if (fromServer.isNotEmpty) return fromServer;
        }
      }
    } catch (_) {}
    return [
      'jp.bouzer.kakomongo.takken.month',
      'jp.bouzer.kakomongo.takken.3month',
      'jp.bouzer.kakomongo.takken.6month',
      'jp.bouzer.kakomongo.takken.year',
    ];
  }

  Future<void> _initProducts() async {
    try {
      final available = await iap.isAvailable();
      if (!available) {
        setState(() {
          _error = 'Store not available';
          _loading = false;
        });
        return;
      }
      final ids = await _fetchProductIds();
      final response = await iap.queryProductDetails(ids.toSet());
      if (response.error != null) {
        setState(() {
          _error = response.error?.message ?? '商品情報の取得に失敗しました';
          _loading = false;
        });
        return;
      }
      if (response.productDetails.isEmpty) {
        setState(() {
          _error = '商品が見つかりませんでした';
          _loading = false;
        });
        return;
      }
      final index = {for (var i = 0; i < ids.length; i++) ids[i]: i};
      final sorted = [...response.productDetails]
        ..sort((a, b) => (index[a.id] ?? 1 << 30).compareTo(index[b.id] ?? 1 << 30));
      setState(() {
        _products = sorted;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _buy(ProductDetails product) async {
    if (_isPremiumActive) {
      _showSnack('購入中のプランがあります。変更はサブスクリプション管理から行ってください。');
      return;
    }
    if (_verifying || _purchasing) return;
    final purchaseParam = PurchaseParam(productDetails: product);
    setState(() => _purchasing = true);
    _purchasingTimeout?.cancel();
    _purchasingTimeout = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      // 念のためタイムアウトで復帰（イベント未到達の保険）
      setState(() => _purchasing = false);
    });
    try {
      iap.buyNonConsumable(purchaseParam: purchaseParam);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _purchasing = false);
      if (e.code == 'storekit_duplicate_product_object') {
        _showSnack('未完了の購入手続きが残っています。復元して整理します…');
        try {
          await iap.restorePurchases();
        } catch (_) {}
        _showSnack('前の購入を完了/整理後、もう一度お試しください');
      } else {
        _showSnack('購入の開始に失敗しました');
      }
    } catch (_) {
      if (mounted) setState(() => _purchasing = false);
      _showSnack('購入の開始に失敗しました');
    }
  }

  // 共通: ms(UTC epoch) → 'YYYY/MM/DD HH/MM/SS'（null/0は 'unknown'）
  String _fmtMs(int? ms) {
    if (ms == null || ms <= 0) return 'unknown';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year.toString().padLeft(4, '0')}/${two(dt.month)}/${two(dt.day)} '
        '${two(dt.hour)}/${two(dt.minute)}/${two(dt.second)}';
  }

  Future<_VerifyResult> _verifyOnServer(PurchaseDetails p) async {
    final receiptBase64 =
        p.verificationData.serverVerificationData.replaceAll('\n', '').replaceAll('\r', '').trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastReceiptData', receiptBase64);
    await prefs.setString('lastProductId', p.productID);

    final resp = await http.post(
      Uri.parse(kVerifyUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'productId': p.productID,
        'receiptData': receiptBase64,
      }),
    );

    if (resp.statusCode != 200) {
      return const _VerifyResult(active: false);
    }

    final jsonResp = json.decode(resp.body) as Map<String, dynamic>;
    return _VerifyResult(
      active: jsonResp['isActive'] == true,
      expiresDateMs:
          (jsonResp['expiresDateMs'] is num) ? (jsonResp['expiresDateMs'] as num).toInt() : null,
      productId: (jsonResp['productId'] is String) ? jsonResp['productId'] as String : null,
      environment: (jsonResp['environment'] is String) ? jsonResp['environment'] as String : null,
    );
  }

  Future<void> _syncEntitlementFromSavedReceipt({bool silent = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final receipt = prefs.getString('lastReceiptData');
      String? productId = prefs.getString('lastProductId');
      productId ??= prefs.getString('currentProductId');
      if (receipt == null) return;

      if (!silent && mounted) setState(() => _verifying = true);
      final resp = await http.post(
        Uri.parse(kVerifyUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'productId': productId, 'receiptData': receipt}),
      );

      if (resp.statusCode == 200) {
        final jsonResp = json.decode(resp.body) as Map<String, dynamic>;
        await _saveEntitlement(
          jsonResp['isActive'] == true,
          expiresMs: (jsonResp['expiresDateMs'] is num)
              ? (jsonResp['expiresDateMs'] as num).toInt()
              : null,
          productId: (jsonResp['productId'] is String) ? jsonResp['productId'] as String : null,
        );
        final env = jsonResp['environment'];
        if (env is String && mounted) setState(() => _environment = env);
      }
    } catch (_) {
    } finally {
      if (!silent && mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _refreshReceiptAndSync({bool silent = false}) async {
    _lastRefreshMs = DateTime.now().millisecondsSinceEpoch;
    if (Platform.isIOS) {
      try {
        final iosAdd = iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
        final dyn = iosAdd as dynamic;
        try {
          await dyn.refreshReceipt();
        } catch (_) {}
        try {
          final ver = await dyn.refreshPurchaseVerificationData();
          final receiptBase64 = (ver.serverVerificationData as String?)
                  ?.replaceAll('\n', '')
                  .replaceAll('\r', '')
                  .trim() ??
              '';
          if (receiptBase64.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('lastReceiptData', receiptBase64);
            final lastPid = prefs.getString('lastProductId');
            final currPid = prefs.getString('currentProductId');
            if (lastPid == null && currPid != null) {
              await prefs.setString('lastProductId', currPid);
            }
          }
        } catch (_) {}
      } catch (_) {}
    }
    await _syncEntitlementFromSavedReceipt(silent: silent);
  }

  void _autoRefreshIfNeeded() {
    if (!mounted) return;
    final exp = _expiresDateMs;
    if (exp == null) return;
    if (_verifying) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sinceLast = now - _lastRefreshMs;
    if (sinceLast <= 3000) return;
    final active = (now + _clockDriftMs) < exp;
    if (!active) return; // 非アクティブ時は自動同期しない
    final msUntilExpiry = exp - (now + _clockDriftMs);
    if (msUntilExpiry <= 10000) {
      _refreshReceiptAndSync(silent: true); // サイレント再検証（UIを「確認中…」にしない）
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    if (!mounted) return;
    for (final purchase in purchases) {
      final ts = int.tryParse(purchase.transactionDate ?? '') ?? 0;
      final prev = _latestTsByProduct[purchase.productID] ?? 0;
      if (ts < prev) continue;
      _latestTsByProduct[purchase.productID] = ts;

      final pid = purchase.purchaseID ?? '${purchase.hashCode}';
      if (_processingPurchaseIds.contains(pid)) continue;
      _processingPurchaseIds.add(pid);

      try {
        if (purchase.status == PurchaseStatus.pending) {
          if (mounted) setState(() => _purchasing = true);
        }
        if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
          final result = await _verifyOnServer(purchase);
          if (result.active) {
            await _saveEntitlement(true, expiresMs: result.expiresDateMs, productId: result.productId);
            final when = _formatExpiry(result.expiresDateMs);
            if (when != null) _showSnack('プランが有効になりました（期限: $when）');
            // ログ: 購入/更新
            if (result.expiresDateMs != null) {
              final purchasedMs = int.tryParse(purchase.transactionDate ?? '') ?? 0;
              final purchasedAt = _fmtMs(purchasedMs);
              final expiresAt = _fmtMs(result.expiresDateMs);
              logPrint('purchased product_id=${result.productId ?? purchase.productID} purchased_at=$purchasedAt expires_at=$expiresAt');
            }
          } else {
            await _saveEntitlement(false, expiresMs: result.expiresDateMs);
            _showSnack('購入は確認できませんでした');
            final purchasedMs = int.tryParse(purchase.transactionDate ?? '') ?? 0;
            final purchasedAt = _fmtMs(purchasedMs);
            logPrint('purchase_failed product_id=${result.productId ?? purchase.productID} purchased_at=$purchasedAt');
          }
          if (mounted) {
            _purchasingTimeout?.cancel();
            setState(() => _purchasing = false);
          }
        }
        if (purchase.status == PurchaseStatus.error) {
          if (mounted) {
            _purchasingTimeout?.cancel();
            setState(() => _purchasing = false);
          }
        }
      } finally {
        try {
          if (purchase.pendingCompletePurchase) {
            await iap.completePurchase(purchase);
          }
        } catch (_) {}
        _processingPurchaseIds.remove(pid);
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  _PlanState _planStateFor(String productId) {
    if (_isPremiumActive) {
      if (_currentProductId == null) return _PlanState.currentActive; // 確認中
      if (_currentProductId == productId) return _PlanState.currentActive;
    }
    return _PlanState.other;
  }

  bool _canPurchase(String productId) {
    if (_verifying || _purchasing) return false;
    return !_isPremiumActive;
  }

  Widget _planCard(ProductDetails p) {
    final state = _planStateFor(p.id);
    final isCurrent = state == _PlanState.currentActive;
    final enabled = _canPurchase(p.id);

    Color border;
    Color bg;
    String badgeText;
    String buttonText;

    switch (state) {
      case _PlanState.currentActive:
        border = Colors.green;
        bg = Colors.green.withOpacity(0.08);
        badgeText = '現在のプラン';
        buttonText = '購入済み（${p.price}）';
        break;
      case _PlanState.other:
        border = Colors.grey.shade500;
        bg = Colors.grey.withOpacity(0.05);
        badgeText = _isPremiumActive ? '他プラン' : '未購入';
        buttonText = _isPremiumActive ? '購入不可（${p.price}）' : '${p.price} で購入';
        break;
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border, width: 1),
      ),
      color: bg,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(p.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.25)),
            if (isCurrent && _expiresDateMs != null) ...[
              const SizedBox(height: 6),
              Text('有効期限: ${_formatExpiry(_expiresDateMs)}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.black87)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: border.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: border),
                  ),
                  child: Text(badgeText, style: TextStyle(fontSize: 10.5, color: border, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 120),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), minimumSize: const Size(0, 36)),
                    onPressed: enabled ? () => _buy(p) : null,
                    child: Text(_verifying ? '確認中…' : (_purchasing ? '処理中…' : buttonText), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('プレミアム')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('エラー: $_error'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _loading = true;
                    });
                    _initProducts();
                  },
                  child: const Text('再試行'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_products.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('プレミアム')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('商品情報が読み込めませんでした。しばらくしてから再度お試しください。'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _loading = true);
                    _initProducts();
                  },
                  child: const Text('再読み込み'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('プレミアム')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 説明カード（設定画面のiボタンの内容をこちらで表示）
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade400),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Text(
                  _isPremiumActive
                      ? '・プレミアム購入で広告は非表示になります。\n'
                        '・現在プレミアム購入ずみです。\n'
                        '・プレミアムは自動更新のサブスクリプションです。\n'
                        '・購入はお使いの Apple ID に紐づきます。'
                      : '・プレミアム購入で広告は非表示になります。\n'
                        '・料金プランを選んで購入してください。\n'
                        '・プレミアムは自動更新のサブスクリプションです。\n'
                        '・購入はお使いの Apple ID に紐づきます。',
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _products.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _planCard(_products[i]),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busyRestore ? null : _restorePurchasesAndSync,
                    icon: _busyRestore
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync),
                    label: Text(_busyRestore ? '更新中…' : '購入情報を再取得 / 復元'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '説明',
                  onPressed: _showRestoreInfo,
                  icon: const Icon(Icons.info_outline),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _verifying ? null : _openManageSubscriptions,
                    icon: const Icon(Icons.subscriptions_outlined),
                    label: const Text('プレミアムの閲覧 / 解約 / 変更'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '説明',
                  onPressed: _showManageInfo,
                  icon: const Icon(Icons.info_outline),
                ),
              ],
            ),
            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }
}

class _VerifyResult {
  final bool active;
  final int? expiresDateMs;
  final String? productId;
  final String? environment;
  const _VerifyResult({
    required this.active,
    this.expiresDateMs,
    this.productId,
    this.environment,
  });
}

String? _formatExpiry(int? ms) {
  if (ms == null) return null;
  final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}/${two(dt.month)}/${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}
