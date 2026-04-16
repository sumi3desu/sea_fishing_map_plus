/// Global network timeout for HTTP requests
/// Adjust this value to change all app-wide HTTP timeouts at once.
const Duration kHttpTimeout = Duration(seconds: 20);
const int kPostPageSize = 20; // 投稿一覧の1ページ件数

final String _tosUrl = 'asset://assets/policies/terms_of_use.html';
final String _privacyUrl = 'asset://assets/policies/privacy_policy.html';
 
// ambiguous_plevel=0 釣り場指定
// 
//const int ambiguous_plevel = 0;       // 釣り場指定
const int ambiguous_plevel = 1;    // 近辺釣り場(10個 + 揺らぎ)

//const int ambiguous_method = 1;   // 点スポットから近い順 Top10,その最遠点から近い順 Top10, 重複除外
//const int ambiguous_method = 2;   // 基点スポットから近い順 15件 を取得,その15件を address でグループ化, 各グループ内で基点スポットに近い順に整列,グループ同士は「そのグループ内の最短距離」の昇順で並べ替え

// - 縦長
//      - パターン1: 上からカット、指定釣り場なら下側からカット
//      - パターン2: 下からカット、指定釣り場なら上側からカット
//      - パターン3: 最寄り15件を残す
//  - 横長
//      - パターン1: 右からカット、指定釣り場なら左側からカット
//      - パターン2: 左からカット、指定釣り場なら右側からカット
//      - パターン3: 最寄り15件を残す
const int ambiguous_method = 3;   // 

// const int ambiguous_plevel = 2;    // Block区切り

const int baseMap = 0;                 // open street map
// const int baseMap = 1;              // apple map
// const int baseMap = 2;              // google map


// メッシュサイズ（km）: 例) 30 を指定すると 30km 間隔のグリッド
const int meshSize = 30;

//
// Message
//
final String warningSelectSpot = '「釣果」で投稿を選ぶか「釣り場一覧」で釣り場を選んでください。';
//final String warningCertificationMail = 'メール認証をお願いします。';
