/// Global network timeout for HTTP requests
/// Adjust this value to change all app-wide HTTP timeouts at once.
const Duration kHttpTimeout = Duration(seconds: 20);

const int kPostPageSize = 20; // 「釣果」の「ギャラリー」と「一覧」の1ページ件数

const double kScrollableContentBottomPadding = 96.0; // 一覧系スクロール末尾の見切れ防止余白

const double kNearbyMapSearchRadiusKm = 30.0; // 近辺の釣り場表示で使う検索半径

// 「投稿詳細」の「釣れたエリア」で半径 30km 以内の釣り場で地図全体に表示する最大件数
const int kNearbyMapMaxMarkerCount = 100;

const int kCatchAreaCandidateSourceCount = 15; // 「投稿詳細」の「釣れたエリア」で候補算出の起点にする近傍件数

const int kCatchAreaVisibleSpotCount = 10; // 「投稿詳細」の「釣れたエリア」で円内候補として残す件数

//final String _tosUrl = 'asset://assets/policies/terms_of_use.html';
//final String _privacyUrl = 'asset://assets/policies/privacy_policy.html';

// 投稿の釣り場表示モード。
//
// ambiguousLevel = 0:
// - 明示表示。
// - 投稿一覧の取得対象は選択中の spot_id 1件のみ。
// - 投稿詳細では実際の spot_id をそのまま扱う。
//
// ambiguousLevel = 1:
// - 曖昧表示。
// - PHP の get_post_list.php に渡すパラメータ名は互換のため 'ambiguous_plevel' のまま。
// - 投稿一覧取得では、以下の条件をすべて満たす釣果取得時だけ、選択中 spot_id 1件ではなく
//   buildCatchAreaCandidateSpotIds() で算出した候補釣り場集合を対象にする。
//   - get_kind == 1
//   - spot_id > 0
//   - ambiguous_plevel != 0
//   - user_id <= 0
// - 上記条件を満たさない場合は ambiguousLevel = 1 でも spot_id 1件のみ取得する。
//   例: 釣果以外、spot_id 未指定、user_id 指定あり（釣り日記モード）など。
// - 投稿詳細の「釣れたエリア」候補算出は一覧取得とは別ロジックで、基点から近い
//   kCatchAreaCandidateSourceCount 件を起点に、最大 kCatchAreaVisibleSpotCount 件まで表示候補を残す。
// - 候補算出の件数ルール:
//   - 近傍候補が kCatchAreaVisibleSpotCount 件以下なら、その件数をそのまま採用する。
//   - それを超える場合は kCatchAreaCandidateSourceCount 件を取得したうえで
//     kCatchAreaVisibleSpotCount 件になるまで削る。
// - kCatchAreaVisibleSpotCount 件へ絞る方式:
//   - 縦長
//     - パターン1: 上からカット、指定釣り場なら下側からカット
//     - パターン2: 下からカット、指定釣り場なら上側からカット
//     - パターン3: 最寄り kCatchAreaVisibleSpotCount 件を残す
//   - 横長
//     - パターン1: 右からカット、指定釣り場なら左側からカット
//     - パターン2: 左からカット、指定釣り場なら右側からカット
//     - パターン3: 最寄り kCatchAreaVisibleSpotCount 件を残す
const int kDefaultAmbiguousLevel = 1;
int ambiguousLevel = kDefaultAmbiguousLevel; // 近辺釣り場

const int baseMap = 0; // open street map
// const int baseMap = 1;              // apple map
// const int baseMap = 2;              // google map

//
// Message
//
final String warningSelectSpot = '釣り場MAPに移動します。\n＋を押して投稿、釣り場の登録を選んでください。';
//final String warningCertificationMail = 'メール認証をお願いします。';
