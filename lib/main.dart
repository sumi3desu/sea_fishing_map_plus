import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // ADDED: セキュアストレージ用
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as fp; // alias to avoid Riverpod name clash
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http; // ADDED: 自動ログイン用
import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'setting_page.dart';
import 'FishingResultGrid.dart';
//import 'info_page.dart';
import 'info_screen.dart';
// import 'set_date_page.dart'; // 日付タブは廃止（Tide ページ内のボタンから遷移）
import 'tide_page.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'common.dart';
import 'list_teibou_page.dart';
import 'test_debug_print.dart';
import 'setting_data.dart';
import 'cache_question.dart';
import 'sio_database.dart';
import 'sync_service.dart';
import 'appconfig.dart';
import 'constants.dart';
import 'html_view_page.dart';
import 'sql_db.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'db_rebuild_screen.dart';
import 'input_post_page.dart';

/// 初回データのダウンロードをユーザーに確認してから実行する共通関数
Future<void> confirmAndDownloadInitialData({
  required BuildContext context,
  required Future<bool> Function() runDownload,
  FutureOr<void> Function()? onSuccess,
}) async {
  final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('初回データの準備'),
          content: const Text(
            'アプリの利用に必要な初回データをダウンロードします。\nWi‑Fi 環境での実行を推奨します。実行しますか？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('実行'),
            ),
          ],
        ),
      ) ??
      false;

  if (!proceed) return;

  final ok = await runDownload();
  if (ok) {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('初回データの準備が完了しました')),
      );
    } catch (_) {}
    if (onSuccess != null) {
      await onSuccess();
    }
  } else {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('初回データの準備に失敗しました')),
      );
    } catch (_) {}
  }
}

void main() async {
  // ネイティブのスプラッシュを表示し続け、初回フレーム描画を遅らせる
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.deferFirstFrame();
  // Google AdMob 初期化
  MobileAds.instance.initialize();
  // 画面の向きを縦方向に固定
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ユーザ情報初期化（UUID発行＋サーバ問い合わせ）
  final userInfo = await getOrInitUserInfo();

  // ローカルDB初期化
  await SioDatabase().initialize();

  // サーバーと同期（同意済みの場合のみ。失敗しても続行）
  try {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('consent_version_agreed');
    final t = v?.trim() ?? '';
    final consented = t.isNotEmpty && t.toLowerCase() != 'null' && t != '0';
    if (consented) {
      await SioSyncService().syncFromServer(userId: userInfo.userId);
    }
  } catch (_) {}

  // 共通状態の初期化
  await Common.instance.loadSelectedTeibou();
  if (Common.instance.selectedTeibouNearestPoint.isNotEmpty) {
    Common.instance.tidePoint = Common.instance.selectedTeibouNearestPoint;
    await Common.instance
        .savePoint(Common.instance.selectedTeibouNearestPoint);
  }
  await Common.instance.setupNearestByLocationIfUnset();

  // Riverpod の SharedPreferences を注入
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: fp.ChangeNotifierProvider<Common>(
        create: (_) => Common.instance,
        child: const MyApp(),
      ),
    ),
  );

  // 1.5秒後に初回フレームの描画を許可（= ネイティブスプラッシュを消す）
  Future.delayed(const Duration(milliseconds: 1000), () {
    try { binding.allowFirstFrame(); } catch (_) {}
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  void _initMapKind() async {
    Common.instance.mapKind = await Common.instance.loadMapKind();
  }

  @override
  Widget build(BuildContext context) {
    final common = fp.Provider.of<Common>(context);
    _initMapKind();
    return MaterialApp(
      title: 'siowadou?',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainPage(title: '海釣りMAP+'),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // 1.5秒後にメイン画面へ遷移
    Future.delayed(const Duration(milliseconds: 1000), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainPage(title: '海釣りMAP+')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: Image.asset(
            'assets/splash_logo.png',
            fit: BoxFit.contain,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}

// SharedPreferencesの保存キー
const String userInfoKey = 'user_info_siowadou_pro_key';
/// 質問一覧を保持する StateProvider
final questionsProvider = StateProvider<List<Map<String, dynamic>>>((ref) => []);
/// PIN問題 StateProvider
final pinningsProvider = StateProvider<List<Map<String, dynamic>>>((ref) => []);

/// ScoreScreen の再フェッチトリガー
final scoreRefreshProvider = StateProvider<int>((ref) => 0);
/// Fetch済みフラグ StateProvider
final hasFetchedQuestionsProvider = StateProvider<bool>((ref) => false);
/// Settings/Paywall が更新時にインクリメントし、HomeScreen の再描画を促す
final entitlementVersionProvider = StateProvider<int>((ref) => 0); 

/// shared_preferences の Provider
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(); // runApp で override されます
});

/// メール登録済みフラグ Provider（UserInfo の email が非空なら true）
final isEmailRegisteredProvider = Provider<bool>((ref) {
  final asyncUser = ref.watch(userInfoProvider);
  return asyncUser.maybeWhen(
    data: (u) => (u?.email ?? '').isNotEmpty,
    orElse: () => false,
  );
});

/// キャッシュリスト StateProvider
final cacheQuestionProvider = StateProvider<List<CacheQuestion>>((ref) => []);
/*
class UserInfo {
  final int userId; // メール認証済みユーザID
  final String email; // メールアドレス
  final String uuid; // UUID
  final String status; // ステータス（例: 'verified' / 'unverified'など）
  final String createdAt; // 作成日時 (ISO8601文字列)
  final String? refreshToken; // ADDED: 端末用リフレッシュトークン
  final String? nickName; // ADDED: ニックネーム（サーバ col: nick_name）

  UserInfo({
    required this.userId,
    required this.email,
    required this.uuid,
    required this.status,
    required this.createdAt,
    this.refreshToken,
    this.nickName,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) => UserInfo(
        userId: json['userId'] as int,
        email: json['email'] as String,
        uuid: json['uuid'] as String,
        status: json['status'] as String,
        createdAt: json['created_at'] as String,
        refreshToken: json['refresh_token'] as String?,
        nickName: (json['nick_name'] ?? json['nickName']) as String?,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'email': email,
        'uuid': uuid,
        'status': status,
        'created_at': createdAt,
        if (refreshToken != null) 'refresh_token': refreshToken,
        if (nickName != null) 'nick_name': nickName,
      };
}
*/
class UserInfo {
  final int userId; // メール認証済みユーザID
  final String email; // メールアドレス
  final String uuid; // UUID
  final String status; // ステータス（例: 'verified' / 'unverified'など）
  final String createdAt; // 作成日時 (ISO8601文字列)
  final String? refreshToken; // ADDED: 端末用リフレッシュトークン
  // ADDED: ニックネーム（サーバ col: nick_name）
  final String? nickName;
  // ADDED: 報告ブロック関連
  final int reportsBlocked; // 1=恒久ブロック, 0=なし
  final String? reportsBlockedUntil; // 一時ブロック解除日時 (JST 文字列 or null)
  final String? reportsBlockedReason; // 理由メモ
  final String? role; // 権限(user,admin)
  final bool canReport; // 送信可否（サーバ算出）
  // プロフィール画像
  final String? photoUrl;
  final int? photoVersion;

  UserInfo({
    required this.userId,
    required this.email,
    required this.uuid,
    required this.status,
    required this.createdAt,
    this.refreshToken,
    this.nickName,
    this.reportsBlocked = 0,
    this.reportsBlockedUntil,
    this.reportsBlockedReason,
    this.role,
    this.canReport = true,
    this.photoUrl,
    this.photoVersion,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) => UserInfo(
        userId: json['userId'] as int,
        email: json['email'] as String,
        uuid: json['uuid'] as String,
        status: json['status'] as String,
        createdAt: json['created_at'] as String,
        refreshToken: json['refresh_token'] as String?,
        nickName: (json['nick_name'] ?? json['nickName']) as String?,
        reportsBlocked: (json['reports_blocked'] is int)
            ? json['reports_blocked'] as int
            : ((json['reports_blocked'] is bool)
                ? ((json['reports_blocked'] as bool) ? 1 : 0)
                : (json['reports_blocked'] is String)
                    ? int.tryParse(json['reports_blocked'] as String) ?? 0
                    : 0),
        reportsBlockedUntil: json['reports_blocked_until'] as String?,
        reportsBlockedReason: json['reports_blocked_reason'] as String?,
        role: json['role'] as String?,
        canReport: (json['can_report'] is bool)
            ? json['can_report'] as bool
            : (json['can_report'] is int)
                ? ((json['can_report'] as int) != 0)
                : true,
        photoUrl: (json['profile_image_url'] ?? json['photo_url']) as String?,
        photoVersion: (json['profile_image_version'] is int)
            ? json['profile_image_version'] as int
            : (json['photo_version'] is int)
                ? json['photo_version'] as int
                : null,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'email': email,
        'uuid': uuid,
        'status': status,
        'created_at': createdAt,
        if (refreshToken != null) 'refresh_token': refreshToken,
        if (nickName != null) 'nick_name': nickName,
        'reports_blocked': reportsBlocked,
        if (reportsBlockedUntil != null) 'reports_blocked_until': reportsBlockedUntil,
        if (reportsBlockedReason != null) 'reports_blocked_reason': reportsBlockedReason,
        if (role != null) 'role': role,
        'can_report': canReport,
        if (photoUrl != null) 'profile_image_url': photoUrl,
        if (photoVersion != null) 'profile_image_version': photoVersion,
      };
}


/// UserInfo をセキュアストレージに保存する
Future<void> saveUserInfo(UserInfo info) async {
  await _secure.write(key: userInfoKey, value: jsonEncode(info.toJson()));
}

/// ユーザ情報を非同期に読み込むプロバイダ
final userInfoProvider = FutureProvider<UserInfo?>((ref) async {
  return await loadUserInfo();
});
/// サーバーから UserInfo を取得／新規作成
Future<UserInfo> getUserInfoFromServer({
  required String uuid,
  String? email,
}) async {
  final uri = Uri.parse('${AppConfig.instance.baseUrl}get_user_info.php');
  final body = <String, String>{'uuid': uuid};
  if (email != null) {
    body['email'] = email;
  }

  try {
    final resp = await http.post(uri, body: body);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;

    if (resp.statusCode == 200 && data['status'] == 'success') {
      return UserInfo(
        userId: data['userId'] as int,
        email: data['email'] as String,
        uuid: data['uuid'] as String,
        status: data['status'] as String,
        createdAt: data['createdAt'] as String,
        nickName: (data['nick_name'] ?? data['nickName']) as String?,
        role: (data['role'] as String?)
      );
    } else {
      throw Exception('get_user_info.php が失敗しました: ${data['status']}');
    }
  } catch (e) {
    testDebugPrint('ユーザー情報取得エラー: $e');
    rethrow;
  }
}

/// メールアドレスから UserInfo を取得（UUID 不明時の救済）
Future<UserInfo?> getUserInfoFromServerByEmail(String email) async {
  try {
    final ui = await getUserInfoFromServer(uuid: '', email: email);
    return ui;
  } catch (_) {
    return null;
  }
}

/// 設定情報 StateProvider
final settingProvider = StateProvider<SettingData>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return SettingData(
    buzzerOn: prefs.getBool('buzzerOn') ?? true,
    mode: prefs.getInt('mode') ?? 4,
    outputOrder: prefs.getInt('outputOrder') ?? 1,
    yearId: prefs.getInt('yearId') ?? 202400,
    subjectIndex: prefs.getInt('subjectIndex') ?? 0,
    pinOnly: prefs.getBool('pinOnly') ?? false,
  );
});


/// UserInfo が保存されていなければ初期化し、サーバー問い合わせも含めて生成・保存する
Future<UserInfo> getOrInitUserInfo() async {
  // 1) すでに保存済みならそのまま返す（セキュアストレージ優先）
  final existing = await loadUserInfo();
  if (existing != null) return existing;

  // 2) UUID を新規発行（ユーザ情報に格納して保存）
  final uuid = const Uuid().v4();

  // 3) サーバー問い合わせ
  UserInfo info;
  try {
    final serverData = await getUserInfoFromServer(uuid: uuid, email: null);
    info = UserInfo(
      userId: serverData.userId,
      email: serverData.email,
      uuid: uuid,
      status: serverData.status,
      createdAt: serverData.createdAt,
      nickName: serverData.nickName,
    );
  } catch (_) {
    // オフライン等で取得できない場合はローカル用に暫定作成し、後で上書きされる前提で続行
    info = UserInfo(
      userId: 0,
      email: '',
      uuid: uuid,
      status: 'local',
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  // 4) セキュアストレージに保存
  await saveUserInfo(info);

  return info;
}

// ADDED: セキュアストレージ（Keychain/Keystore）
final _secure = const FlutterSecureStorage();

/// UserInfo をセキュアストレージから読み出し。
/// 旧バージョンのデータ（SharedPreferences）があれば移行する。
Future<UserInfo?> loadUserInfo() async {
  // セキュアストレージ優先
  final secured = await _secure.read(key: userInfoKey);
  if (secured != null && secured.isNotEmpty) {
    try {
      final Map<String, dynamic> data = jsonDecode(secured);
      return UserInfo.fromJson(data);
    } catch (_) {}
  }
  // SharedPreferences からの移行
  final prefs = await SharedPreferences.getInstance();
  final legacy = prefs.getString(userInfoKey);
  if (legacy != null && legacy.isNotEmpty) {
    try {
      await _secure.write(key: userInfoKey, value: legacy);
      final Map<String, dynamic> data = jsonDecode(legacy);
      return UserInfo.fromJson(data);
    } catch (_) {}
  }
  return null;
}


class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.title, this.initialIndex = 0});

  final String title;
  final int initialIndex;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  static const double _postFabDiameter = 61.0;
  BannerAd? _bannerAd;
  // 規約・プライバシーポリシー同意ダイアログ制御
  bool _consentDialogShown = false;
  bool _agreeAll = false;
  final String _tosUrl = 'asset://assets/policies/terms_of_use.html';
  final String _privacyUrl = 'asset://assets/policies/privacy_policy.html';
   // 初回起動で同意未完了の場合、同意後にデータ警告を出すための保留フラグ
  bool _noDataCheckPending = false;

  // タブのインデックス（0: 釣果、1: 釣り場一覧、2: 釣り場詳細、3: 日付、4: 設定、5: 情報）
  int _selectedIndex = 0;

  // TidePage の GlobalKey を作成
  final GlobalKey<TidePageState> tidePageKey = GlobalKey<TidePageState>();
  // 日付タブは廃止（Tide ページ内のボタンから遷移）
  int _lastNavigateToTideTick = 0;

  void _onItemTapped(int index) {
    // 中央の「投稿」アイテムは FAB と同じ動作に割り当てる
    if (index == 2) {
      _onPressCreatePost();
      return;
    }
    // 下部ナビのインデックスをページインデックスに変換
    final int pageIndex = index > 2 ? index - 1 : index;
    setState(() {
      _selectedIndex = pageIndex;
    });
    // 釣り場詳細(TidePage) が選択された場合だけ TidePage の refreshTide() を呼び出す
    if (pageIndex == 2) {
      tidePageKey.currentState?.refreshTide(Common.instance.tideDate);
      // 釣り場一覧タブが選択されたときにDB更新を通知して再読込を促す
    } else if (pageIndex == 1) {
      try { SioDatabase().notifyListeners(); } catch (_) {}
      try { Common.instance.requestListCentering(); } catch (_) {}
    }
  }

  @override
  void initState() {
    super.initState();
    // 初期タブを外部指定で切り替え可能にする
    _selectedIndex = widget.initialIndex;
    _loadBanner();
    // 日付タブは廃止（Tide ページ内の「日付変更」ボタンから遷移）
    // 共通状態からの「釣り場詳細へ遷移」要求に反応
    try {
      Common.instance.addListener(_onCommonNavigateRequest);
    } catch (_) {}
    // 初回起動時に同意ダイアログを検討して表示
    _maybeShowConsentDialog();
    // 起動時にユーザ情報(特に role)を最新化して保存（各画面の表示整合性のため）
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshUserRole());
    // すでに同意済みで初回データが未準備なら、確認なしで自動実行
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        final consented = await _hasPolicyConsent();
        if (consented && await _isInitialDataMissing()) {
          await _confirmAndDownloadInitialData();
        }
      } catch (_) {}
    });
  }

  Future<void> _refreshUserRole() async {
    try {
      final info = await getOrInitUserInfo();
      try {
        final refreshed = await getUserInfoFromServer(uuid: info.uuid);
        await saveUserInfo(refreshed);
      } catch (_) {}
    } catch (_) {}
  }

  @override
  void dispose() {
    try { Common.instance.removeListener(_onCommonNavigateRequest); } catch (_) {}
    _bannerAd?.dispose();
    super.dispose();
  }

  void _onCommonNavigateRequest() {
    final common = Common.instance;
    if (common.navigateToTideTick != _lastNavigateToTideTick) {
      _lastNavigateToTideTick = common.navigateToTideTick;
      if (!mounted) return;
      setState(() {
        _selectedIndex = 2; // 釣り場詳細タブ
      });
      // 遷移直後に潮汐の再読込も実施
      try { tidePageKey.currentState?.refreshTide(Common.instance.tideDate); } catch (_) {}
      // 釣果リストも強制再読み込み（選択釣り場の変更を確実に反映）
      try { tidePageKey.currentState?.forceReloadCatchList(); } catch (_) {}
    }
  }
    // 初回準備が完了しているか（堤防テーブルが揃っているか）
  Future<bool> _isInitialDataMissing() async {
    try {
      // SioDatabase 側の実テーブルから判定（legacy DB ではなく）
      final sdb = await SioDatabase().database;
      int tb = 0, tdfk = 0, k = 0;
      try {
        tb = sqflite.Sqflite.firstIntValue(await sdb.rawQuery('SELECT COUNT(*) FROM teibou')) ?? 0;
      } catch (_) {}
      try {
        tdfk = sqflite.Sqflite.firstIntValue(await sdb.rawQuery('SELECT COUNT(*) FROM todoufuken')) ?? 0;
      } catch (_) {}
      try {
        k = sqflite.Sqflite.firstIntValue(await sdb.rawQuery('SELECT COUNT(*) FROM kubun')) ?? 0;
      } catch (_) {}
      return (tb == 0 || tdfk == 0 || k == 0);
    } catch (_) {
      return true; // 取得失敗時は未整備扱い
    }
  }

  // 同意ダイアログを必要に応じて表示
  void _maybeShowConsentDialog() {
    if (_consentDialogShown) return;
    // フレーム後に非同期で判定してから表示
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (await _hasPolicyConsent()) return;
      if (_consentDialogShown) return;
      _consentDialogShown = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) {
          bool localAgree = _agreeAll;
          final titleTextStyle = Theme.of(ctx).textTheme.titleLarge;
          final scaledTitleStyle = (titleTextStyle ?? const TextStyle()).copyWith(
            fontSize: (titleTextStyle?.fontSize ?? 20) * 0.8,
          );
          return WillPopScope(
            onWillPop: () async => false,
            child: StatefulBuilder(
              builder: (context, setStateDialog) {
                void setAgree(bool v) {
                  if (mounted) setState(() => _agreeAll = v);
                  setStateDialog(() => localAgree = v);
                }
                return AlertDialog(
                  title: Text('利用規約・プライバシーポリシーへの同意', style: scaledTitleStyle),
                  content: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('サービスのご利用には、以下への同意が必要です。'),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              value: localAgree,
                              onChanged: (v) => setAgree(v ?? false),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(color: Colors.black, fontSize: 14),
                                  children: [
                                    TextSpan(
                                      text: '利用規約',
                                      style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                                      recognizer: (TapGestureRecognizer()..onTap = () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => HtmlViewPage(title: '利用規約', url: _tosUrl)),
                                        );
                                      }),
                                    ),
                                    const TextSpan(text: ' と '),
                                    TextSpan(
                                      text: 'プライバシーポリシー',
                                      style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                                      recognizer: (TapGestureRecognizer()..onTap = () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => HtmlViewPage(title: 'プライバシーポリシー', url: _privacyUrl)),
                                        );
                                      }),
                                    ),
                                    const TextSpan(text: ' に同意します'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    ElevatedButton(
                      onPressed: localAgree
                          ? () {
                              _saveConsentAndProceed(() async {
                                if (!mounted) return;
                                Navigator.of(context, rootNavigator: true).pop();
                                _consentDialogShown = false;
                                // 同意直後に初回データダウンロードの案内を実施（必要時）
                                _noDataCheckPending = false; // 旧警告フローはクリア
                                try {
                                  if (await _isInitialDataMissing()) {
                                    await _confirmAndDownloadInitialData();
                                  }
                                } catch (_) {}
                              });
                            }
                          : null,
                      child: const Text('同意して続行'),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    });
  }
  Future<void> _saveConsentAndProceed(FutureOr<void> Function() proceed) async {
    // チェック未ONならスナックバーで通知
    if (!_agreeAll) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('利用規約・プライバシーポリシーに同意してください。')),
        );
      }
      return;
    }
    final latest = 'local-${DateTime.now().toUtc().toIso8601String()}';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('consent_version_agreed', latest);
      // サーバ側にも簡易送信（失敗しても無視）
      try {
        final info = await loadUserInfo() ?? await getOrInitUserInfo();
        await http.post(
          Uri.parse('${AppConfig.instance.baseUrl}user_consent.php'),
          body: {
            'uuid': info.uuid,
            'version_agreed': latest,
            'agreed_at': DateTime.now().toUtc().toIso8601String(),
          },
        ).timeout(kHttpTimeout);
      } catch (_) {}
    } catch (_) {}
    await proceed();
  }
  // 規約・プライバシーポリシーへの同意が済んでいるかを確認
  Future<bool> _hasPolicyConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString('consent_version_agreed');
      final t = v?.trim() ?? '';
      // 未同意判定: 空/null/'0'/'null'
      final firstConsent = (t.isEmpty || t.toLowerCase() == 'null' || t == '0');
      return !firstConsent;
    } catch (_) {
      return false;
    }
  }

  // 初回データダウンロード確認ダイアログ → 実行（共通化ラッパー）
  Future<void> _confirmAndDownloadInitialData() async {
    if (!mounted) return;
    // ユーザー確認なしで即実行
    final ok = await _runInitialDataDownload();
    try {
      if (!mounted) return;
      final err = SioSyncService().lastError;
      final msg = ok
          ? '初回データの準備が完了しました'
          : (!kReleaseMode && (err != null && err.isNotEmpty)
              ? '初回データの準備に失敗しました（$err）'
              : '初回データの準備に失敗しました');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {}
  }

  // 実際のデータダウンロード処理（プログレス表示を含む）
  Future<bool> _runInitialDataDownload() async {
    if (!mounted) return false;
    // 進行ダイアログ
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          width: 64,
          height: 64,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );
    bool success = false;
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final legacyDb = await openLocalDb();
      await initialTable(legacyDb, info.userId); // 既存ローカルテーブル群の作成（別DB）

      // 初回データ（堤防・都道府県・区分）を明示的に同期（SioDatabase 側）
      final ok = await SioSyncService().syncFishingData(userId: info.userId, force: true);
      if (ok) {
        try {
          final sdb = await SioDatabase().database;
          int tb = 0, tdfk = 0, kb = 0;
          tb = sqflite.Sqflite.firstIntValue(await sdb.rawQuery('SELECT COUNT(*) FROM teibou')) ?? 0;
          tdfk = sqflite.Sqflite.firstIntValue(await sdb.rawQuery('SELECT COUNT(*) FROM todoufuken')) ?? 0;
          kb = sqflite.Sqflite.firstIntValue(await sdb.rawQuery('SELECT COUNT(*) FROM kubun')) ?? 0;
          success = (tb > 0 && tdfk > 0 && kb > 0);
          if (!success) {
            final details = 'teibou=$tb todoufuken=$tdfk kubun=$kb';
            if ((SioSyncService().lastError ?? '').isEmpty) {
              SioSyncService().lastError = 'データ不足（$details）';
            } else {
              // 既にAPI由来のエラーがある場合は補足として追記
              SioSyncService().lastError = '${SioSyncService().lastError} / データ不足（$details）';
            }
          }
        } catch (_) {
          if ((SioSyncService().lastError ?? '').isEmpty) {
            SioSyncService().lastError = '件数確認に失敗';
          }
          success = false;
        }
      } else {
        if ((SioSyncService().lastError ?? '').isEmpty) {
          SioSyncService().lastError = '同期処理に失敗';
        }
        success = false;
      }
    } catch (_) {
      if ((SioSyncService().lastError ?? '').isEmpty) {
        SioSyncService().lastError = '初期化中に例外発生';
      }
      success = false;
    }
    // プログレスを閉じる（以降で画面遷移の可能性があるため先に閉じる）
    if (mounted) {
      try { Navigator.of(context, rootNavigator: true).pop(); } catch (_) {}
    }

    // 成功時、一覧などへDB更新を通知
    if (success) {
      try { SioDatabase().notifyListeners(); } catch (_) {}
    }

    // 失敗時は画面遷移せず、エラーを通知してそのまま戻る
    if (!success && mounted) {
      try {
        final err = SioSyncService().lastError;
        final msg = (!kReleaseMode && (err != null && err.isNotEmpty))
            ? '初回データの準備に失敗しました（$err）'
            : '初回データの準備に失敗しました。通信環境をご確認のうえ、後ほどお試しください。';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      } catch (_) {}
    }
    return success;
  }


  void _loadBanner() {
    _bannerAd = BannerAd(
      size: AdSize.banner,
      adUnitId: 'ca-app-pub-3940256099942544/2934735716', // TEST用広告ID
      //adUnitId: 'ca-app-pub-9290857735881347/1643363507',  // 本番広告ID
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {});
        },
        onAdFailedToLoad: (ad, error) {
          print('Ad failed to load: ${error.code} ${error.message}');
          ad.dispose();
          // エラーハンドリング（例：ログ出力）
        },
      ),
      request: const AdRequest(),
    )..load();
  }

  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final common = fp.Provider.of<Common>(context);
    /// メインコンテンツは各タブごとに作成（IndexedStack により各状態が保持される）
    final List<Widget> pages = [
      const FishingResultGrid(),
      const ListTeibouPage(),
      TidePage(key: tidePageKey),
      SettingPage(),
    ];
    return Scaffold(
      extendBody: true,
      // AppBar は使用しないのでコメントアウトまたは削除します
      // appBar: AppBar(
      //   title: Text(widget.title),
      //   backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      // ),
      body: Stack(
        children: [
          // 本文は SafeArea (bottom: false) で保護し、ナビの分だけ下に余白を確保
          SafeArea(
            top: true,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: kBottomNavigationBarHeight),
              child: Column(
                children: [
                  if (_bannerAd != null)
                    Container(
                      alignment: Alignment.center,
                      width: _bannerAd!.size.width.toDouble(),
                      height: _bannerAd!.size.height.toDouble(),
                      child: AdWidget(ad: _bannerAd!),
                    ),
                // タブ2(釣り場詳細)のとき、広告の下に AppBar と同等のタイトルを表示（黒背景/白文字）
                if (_selectedIndex == 2)
                  SizedBox(
                    height: kToolbarHeight,
                    width: double.infinity,
                    child: FutureBuilder<String>(
                  future: () async {
                    final spotName = common.selectedTeibouName.isNotEmpty ? common.selectedTeibouName : common.tidePoint;
                    String prefName = '';
                    try {
                      int pid = common.selectedTeibouPrefId;
                      if (pid == 0) {
                        // まずは選択済みport_idで引く（同名別県の誤参照防止）
                        try {
                          final prefs = await SharedPreferences.getInstance();
                          final sid = prefs.getInt('selected_teibou_id');
                          if (sid != null && sid > 0) {
                            final rows = await SioDatabase().getAllTeibouWithPrefecture();
                            for (final r in rows) {
                              final rid = r['port_id'] is int ? r['port_id'] as int : int.tryParse(r['port_id']?.toString() ?? '');
                              if (rid == sid) {
                                pid = r['todoufuken_id'] is int
                                    ? r['todoufuken_id'] as int
                                    : int.tryParse(r['todoufuken_id']?.toString() ?? '') ?? int.tryParse(r['pref_id_from_port']?.toString() ?? '') ?? 0;
                                break;
                              }
                            }
                          }
                        } catch (_) {}
                        // port_id で取得できなかった場合のみ、名前一致でフォールバック
                        if (pid == 0 && common.selectedTeibouName.isNotEmpty) {
                          final rows = await SioDatabase().getAllTeibouWithPrefecture();
                          for (final r in rows) {
                            final n = (r['port_name'] ?? '').toString();
                            if (n == common.selectedTeibouName) {
                              pid = r['todoufuken_id'] is int
                                  ? r['todoufuken_id'] as int
                                  : int.tryParse(r['todoufuken_id']?.toString() ?? '') ?? int.tryParse(r['pref_id_from_port']?.toString() ?? '') ?? 0;
                              break;
                            }
                          }
                        }
                      }
                      if (pid != 0) {
                        final prefs = await SioDatabase().getTodoufukenAll();
                        for (final r in prefs) {
                          final id = r['todoufuken_id'] is int ? r['todoufuken_id'] as int : int.tryParse(r['todoufuken_id']?.toString() ?? '');
                          if (id == pid) {
                            prefName = (r['todoufuken_name'] ?? '').toString();
                            break;
                          }
                        }
                      }
                    } catch (_) {}
                    return '釣り場詳細[' + (prefName.isNotEmpty ? '$prefName ' : '') + spotName + ']';
                  }(),
                  builder: (context, snap) {
                    return AppBar(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      centerTitle: true,
                      elevation: 0,
                      automaticallyImplyLeading: false,
                      title: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.place, color: Colors.white),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '釣り場詳細',
                              style: TextStyle(color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
                // 釣り場詳細のタイトル直下のアクションバーは廃止（地図上部へ移設）
                Expanded(
                  child: IndexedStack(index: _selectedIndex, children: pages),
                ),
                ],
              ),
            ),
          ),
          // ボトムナビゲーション（オーバーレイ）
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              bottom: false,
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                elevation: 0,
                currentIndex: _navIndexFromPageIndex(_selectedIndex),
                onTap: _onItemTapped,
                items: <BottomNavigationBarItem>[
                  const BottomNavigationBarItem(icon: Text('🐟', style: TextStyle(fontSize: 20)), label: '釣果'),
                  const BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: '釣り場一覧'),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.add_circle, color: Colors.transparent),
                    label: '',
                  ),
                  const BottomNavigationBarItem(icon: Icon(Icons.place), label: '釣り場詳細'),
                  const BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設定'),
                ],
              ),
            ),
          ),
          // 中央の＋ボタン（オーバーレイ固定・ナビの手前）
            Positioned(
              left: 0,
              right: 0,
            // 現在の位置から約5px下げる（= 半重なりをわずかに深く）
            bottom: (kBottomNavigationBarHeight - (_postFabDiameter / 2)) + 30,
            child: Center(child: _buildPostFab(context)),
          ),
        ],
      ),
    );
  }

  int _navIndexFromPageIndex(int pageIndex) {
    if (pageIndex <= 1) return pageIndex; // 0:釣果, 1:一覧
    if (pageIndex == 2) return 3;         // 釣り場詳細はナビの3番目
    return 4;                              // 設定はナビの4番目
  }

  Widget _buildPostFab(BuildContext context) {
    return RawMaterialButton(
      onPressed: _onPressCreatePost,
      elevation: 0,
      highlightElevation: 0,
      disabledElevation: 0,
      constraints: const BoxConstraints.tightFor(width: _postFabDiameter, height: _postFabDiameter),
      shape: const CircleBorder(),
      fillColor: const Color(0xFF1E90FF),
      child: const Icon(Icons.add, color: Colors.white, size: 26),
    );
  }

  Future<void> _onPressCreatePost() async {
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      if (!(info.canReport)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('現在は投稿できません')));
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    String initType = 'catch';
    try {
      final mode = Common.instance.postListMode;
      initType = (mode == 'env') ? 'env' : 'catch';
    } catch (_) {}
    final res = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InputPost(initialType: initType)),
    );
    if (res == true) {
      // 投稿成功時、TidePage の投稿一覧を再読込
      try { tidePageKey.currentState?.forceReloadPostList(); } catch (_) {}
    }
  }
}

class _DetailTopAction extends StatelessWidget {
  final IconData icon;
  final String label;
  const _DetailTopAction({Key? key, required this.icon, required this.label}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.black87),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
