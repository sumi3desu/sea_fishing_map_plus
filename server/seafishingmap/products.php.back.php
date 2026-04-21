<?php
/**
 * 20250923-05: App Store Connect API を使って Subscription の productId を取得し、
 * server/products.json を生成・キャッシュする簡易エンドポイント。
 *
 * 利用方法:
 *  - このファイルを Web 公開ディレクトリに配置し、URL をクライアントから叩く
 *  - 初回/キャッシュTTL切れ/refresh=1 の場合は Apple API に問い合わせて更新
 *  - それ以外は products.json の内容を返す
 *
 * 必要設定（下記の定数をあなたの本番値に置き換えてください）
 */
session_cache_limiter("nocache");
session_start();
include_once("include/define.php");
// 設定ファイル読み込み
$ini_info = parse_ini_file(_INI_FILE_PATH_, true);
$session_pre_key = create_session_key($ini_info['web']['url']);

debug_log("products.php start"); 


const TARGET_BUNDLE_ID = 'jp.bouzer.kakomongo.takken'; // 対象アプリの bundleId（APIの検索キー）

// App Store Connect API 認証情報 ユーザとアクセス -> 統合 -> チームキー
const ASC_ISSUER_ID = '25a4f9c4-eb88-4007-bb24-c4eda0889c69';        // APIのIssuer ID（チーム単位の発行者ID）
const ASC_KEY_ID    = 'F83TPW2N5Z';           // 生成したAPIキーのKey ID
const ASC_PRIVATE_KEY_PEM = <<<PEM
-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQgrt9i5wDjbFkUJZb4
Tf9rrY8timUQ281X9wPw9uzfJzOgCgYIKoZIzj0DAQehRANCAAQ8ytXiLGLOdUqQ
sgMviw0EKzsMX20hSug7zCnjo/4O/ar29uyVhBMc8BCZzu0Bu1N1IcMMG7UsQC4b
JubAbgqi
-----END PRIVATE KEY-----
PEM; // .p8 の中身（PEM）をそのまま埋め込む（本番は環境変数などで安全に管理が推奨）

// 取得範囲（どれか一つでも良いが、少なくとも一つは設定推奨）
const ALLOWED_PRODUCT_PREFIX = 'jp.bouzer.kakomongo.takken.'; // 抽出するproductIdの接頭辞（このprefixだけ許可）
// const APP_ID = '1234567890';  // 任意: 特定アプリIDでAPI結果を絞る場合の例（未使用）
// const SUBSCRIPTION_GROUP_ID = 'abcdef12-3456-7890-abcd-ef1234567890'; // 任意: サブスクグループIDで絞る例（未使用）

// キャッシュ設定
const CACHE_FILE = __DIR__ . '/products.json'; // 生成・再利用するキャッシュファイルのパス
const CACHE_TTL  = 3600; // キャッシュの有効期限（秒）ここでは1時間

header('Content-Type: application/json; charset=utf-8'); // レスポンスをJSONとして返す宣言
// PHP7互換の ends_with
if (!function_exists('str_ends_with_compat')) { // 関数未定義なら互換関数を定義
  function str_ends_with_compat($haystack, $needle) { // 文字列が特定サフィックスで終わるか判定
    if ($needle === '') return true; // 空needleは常にtrue
    $len = strlen($needle); // needle長
    return substr($haystack, -$len) === $needle; // 終端比較
  }
}

if (!function_exists('str_starts_with_compat')) { // starts_withの互換関数が未定義なら
  if (function_exists('str_starts_with')) { // PHP8+の標準があればそれを使う
    // PHP8+ は標準の str_starts_with に委譲
    function str_starts_with_compat($haystack, $needle) {
      return str_starts_with($haystack, $needle); // 標準関数呼び出し
    }
  } else {
    // PHP7 互換実装
    function str_starts_with_compat($haystack, $needle) { // 先頭一致の簡易実装
      if ($needle === '') return true; // 空needleはtrue
      return substr($haystack, 0, strlen($needle)) === $needle; // 先頭比較
    }
  }
}


// 簡易ヘルパ
function b64url($s) { // Base64URL（=/-を-_に、末尾=除去）に変換するヘルパ
  return rtrim(strtr(base64_encode($s), '+/', '-_'), '='); // JWTのセグメント生成で使用
}

/**
 * DER 署名を JOSE 署名（R||S 各32バイト）に変換
 */
function der_to_jose($der, $partLength = 32) { // OpenSSLのDER署名をJOSE形式(生R||S)へ変換
  $pos = 0; // パース位置
  if (ord($der[$pos++]) !== 0x30) throw new Exception('Invalid DER: SEQUENCE'); // SEQUENCEタグ確認

  // 長さ（短/長フォーマット対応）
  $lenByte = ord($der[$pos++]); // 長さの先頭バイト
  if ($lenByte & 0x80) { // 長さが多バイト表現の場合
    $numBytes = $lenByte & 0x7F; // 何バイトで長さを表すか
    $seqLen = 0; // 全体長初期化
    for ($i = 0; $i < $numBytes; $i++) { // 指定バイト数読み取り
      $seqLen = ($seqLen << 8) | ord($der[$pos++]); // 長さ値を組み立て
    }
  } else {
    $seqLen = $lenByte; // 単一バイトの長さ
  }

  if (ord($der[$pos++]) !== 0x02) throw new Exception('Invalid DER: INTEGER R'); // RのINTEGERタグ確認
  $rLen = ord($der[$pos++]); // Rの長さ
  $r = substr($der, $pos, $rLen); $pos += $rLen; // R値抽出

  if (ord($der[$pos++]) !== 0x02) throw new Exception('Invalid DER: INTEGER S'); // SのINTEGERタグ確認
  $sLen = ord($der[$pos++]); // Sの長さ
  $s = substr($der, $pos, $sLen); // S値抽出

  $r = ltrim($r, "\x00"); // 先頭の0パディングを除去
  $s = ltrim($s, "\x00"); // 同上
  $r = str_pad($r, $partLength, "\x00", STR_PAD_LEFT); // 固定長(32B)に左パディング
  $s = str_pad($s, $partLength, "\x00", STR_PAD_LEFT); // 同上
  return $r . $s; // 連結してJOSE署名(R||S 64B)を返す
}

function asc_jwt() { // App Store Connect API用のJWTを生成
  $header = ['alg' => 'ES256', 'kid' => ASC_KEY_ID, 'typ' => 'JWT']; // JWTヘッダ（ES256、kid=Key ID）
  $now    = time(); // 現在時刻（UNIX）
  $claims = [ // JWTペイロード（クレーム）
    'iss' => ASC_ISSUER_ID, // Issuer ID（チーム）
    'iat' => $now,          // 発行時刻
    'exp' => $now + 20 * 60, // 有効期限（20分）
    'aud' => 'appstoreconnect-v1', // 受信者（固定）
  ];

  $head = b64url(json_encode($header, JSON_UNESCAPED_SLASHES)); // ヘッダJSONをBase64URL化
  $payl = b64url(json_encode($claims, JSON_UNESCAPED_SLASHES)); // クレームをBase64URL化
  $input = $head . '.' . $payl; // 署名対象「header.payload」

  $pkey = openssl_pkey_get_private(ASC_PRIVATE_KEY_PEM); // PEMから秘密鍵ハンドル取得
  if (!$pkey) throw new Exception('Invalid private key'); // 取得失敗なら例外

  if (!openssl_sign($input, $derSig, $pkey, OPENSSL_ALGO_SHA256)) { // ES256で署名（DER形式で返る）
    throw new Exception('Sign fail'); // 署名失敗で例外
  }
  // ★ DER -> JOSE へ変換（R||S 64バイト）
  $joseSig = der_to_jose($derSig, 32); // DER署名をR||S生配列へ変換

  return $input . '.' . b64url($joseSig); // 「header.payload.signature」を返す
}

function asc_get($path, $params = []) { // 単発GET（1ページ分）を実行するヘルパ
  $url = 'https://api.appstoreconnect.apple.com' . $path; // ベースURL結合
  if (!empty($params)) {
    $url .= '?' . http_build_query($params); // クエリ付与
  }
  $ch = curl_init($url); // cURL初期化
  curl_setopt_array($ch, [ // 各種オプション設定
    CURLOPT_RETURNTRANSFER => true, // 文字列で返す
    CURLOPT_HTTPHEADER => [
      'Authorization: Bearer ' . asc_jwt(), // 認証ヘッダ（JWT）
      'Accept: application/json', // JSONを要求
    ],
    CURLOPT_TIMEOUT => 20, // タイムアウト（秒）
  ]);
  $res = curl_exec($ch); // リクエスト実行
  $err = curl_error($ch); // エラー文字列取得
  $code = curl_getinfo($ch, CURLINFO_HTTP_CODE); // HTTPステータス
  curl_close($ch); // ハンドル解放
  if ($res === false) throw new Exception('curl error: ' . $err); // ネットワーク等の失敗
  if ($code < 200 || $code >= 300) throw new Exception('HTTP ' . $code + ': ' . $res); // 非2xxなら例外
  return json_decode($res, true); // JSONデコードして返す（連想配列）
}
// 汎用：ページネーション対応 GET
function asc_get_all($path, $params = []) { // ページネーションを追跡して全件取得するヘルパ
  $out = []; // 収集配列
  $url = 'https://api.appstoreconnect.apple.com' . $path; // 初期URL
  if (!empty($params)) $url .= '?' . http_build_query($params); // クエリ付与

  while ($url) { // nextリンクがある限りループ
    $ch = curl_init($url); // cURL初期化
    curl_setopt_array($ch, [
      CURLOPT_RETURNTRANSFER => true,
      CURLOPT_HTTPHEADER => [
        'Authorization: Bearer ' . asc_jwt(), // 毎回JWTを生成・付与
        'Accept: application/json',
      ],
      CURLOPT_TIMEOUT => 20,
    ]);
    $res  = curl_exec($ch); // 実行
    $err  = curl_error($ch); // エラー取得
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE); // ステータス取得
    curl_close($ch); // ハンドル解放
    if ($res === false) throw new Exception('curl error: ' . $err); // cURL失敗時
    if ($code < 200 || $code >= 300) throw new Exception('HTTP ' . $code . ': ' . $res); // HTTPエラー

    $json = json_decode($res, true); // JSONデコード
    if (!empty($json['data'])) {
      $out = array_merge($out, $json['data']); // data配列を結合
    }
    // ページネーション：links.next があれば追跡
    $url = isset($json['links']['next']) ? $json['links']['next'] : null; // 次ページURLを更新
  }
  return $out; // 全件配列を返す
}

// 1) bundleId → appId を取得
function get_app_id_by_bundle_id($bundleId) { // bundleIdに対応するAppのIDを取得
  $data = asc_get_all('/v1/apps', [ 'filter[bundleId]' => $bundleId, 'limit' => 50 ]); // appsをbundleIdでフィルタ
  foreach ($data as $item) { // 該当データを走査
    if (($item['attributes']['bundleId'] ?? null) === $bundleId) { // bundleId一致を確認
      return $item['id']; // 一致したAppのidを返す
    }
  }
  throw new Exception('app not found for bundleId=' . $bundleId); // 見つからない場合は例外
}

// 2) appId → subscriptionGroups 列挙
function list_subscription_group_ids($appId) { // Appに紐づくサブスクグループID一覧を取得
  $groups = asc_get_all('/v1/apps/' . $appId . '/subscriptionGroups', [ 'limit' => 200 ]); // グループ一覧取得
  $ids = []; // ID格納
  foreach ($groups as $g) {
    if (isset($g['id'])) $ids[] = $g['id']; // 各グループのidを取り出す
  }
  return $ids; // ID配列を返す
}
// === Appのサブスク productId を取得（ユニーク & ソートで返す）===
function fetch_subscription_product_ids_for_app($bundleId) { // 指定bundleIdのApp配下で販売中のproductId一覧を返す
  // 1) bundleId -> appId
  $appId = get_app_id_by_bundle_id($bundleId); // まずApp IDを特定

  // 2) appId -> subscriptionGroupIds
  $groupIds = list_subscription_group_ids($appId); // Appに紐づくサブスクグループIDを取得
  if (empty($groupIds)) return []; // グループが無ければ空配列

  // 3) 各グループから subscriptions を集めて productId を抽出
  $set = []; // ユニーク化用（連想配列でset化）

  foreach ($groupIds as $gid) { // 各グループごとに
    try {
      $subs = asc_get_all("/v1/subscriptionGroups/{$gid}/subscriptions", ['limit' => 200]); // グループ配下のサブスク一覧
    } catch (Throwable $e) {
      // グループ単位の失敗はスキップして続行（ログしたければここで error_log）
      continue; // 一部失敗しても全体は続行
    }

    if (empty($subs) || !is_array($subs)) continue; // 該当なしなら次へ

    foreach ($subs as $s) { // 各サブスク項目を走査
      $attrs = isset($s['attributes']) && is_array($s['attributes']) ? $s['attributes'] : null; // attributes取得
      if (!$attrs) continue; // 無ければスキップ

      $pid = isset($attrs['productId']) ? trim((string)$attrs['productId']) : ''; // productId取り出し
      if ($pid === '') continue; // 空ならスキップ

      // Apple 側「配信から削除」等の状態は除外（サブスクでは state が付与されない場合あり）
      $state = isset($attrs['state']) ? (string)$attrs['state'] : null;
      $excludeStates = ['DEVELOPER_REMOVED_FROM_SALE', 'REMOVED_FROM_SALE', 'INACTIVE', 'DEPRECATED'];
      if ($state !== null && in_array($state, $excludeStates, true)) {
        // debug_log("products.php exclude by state pid=".$pid." state=".$state);
        continue;
      }

      // プレフィックスでフィルタ（空なら全許可）
      if (ALLOWED_PRODUCT_PREFIX === '' || str_starts_with_compat($pid, ALLOWED_PRODUCT_PREFIX)) {
        $set[$pid] = true; // 許可されたproductIdをsetに追加（ユニーク化）
      }
    }
  }

  // 4) ユニーク化 + ソートして返す
  $ids = array_keys($set); // setのキー（productId）を配列化
  //sort($ids, SORT_STRING); // デフォルトの辞書順ソートは不使用（下で手動優先順位ソート）

  // 希望の順序で並べ替え
  $priority = [
    '.month'  => 1, // 月額を最優先
    '.3month' => 2, // 3ヶ月
    '.6month' => 3, // 6ヶ月
    '.year'   => 4, // 年額
  ];

  usort($ids, function($a, $b) use ($priority) { // サフィックス優先度でソート
    $wa = 999; $wb = 999; // デフォルトは低優先度
    foreach ($priority as $suffix => $rank) { // 定義した優先順位を適用
      if (str_ends_with_compat($a, $suffix)) $wa = $rank; // aの優先度
      if (str_ends_with_compat($b, $suffix)) $wb = $rank; // bの優先度
    }
    if ($wa === $wb) return strcmp($a, $b); // 同順位なら名前順で安定化
    return $wa <=> $wb; // 低いrankが先
  });

  return $ids; // ソート済みのproductId配列を返す
}

// verify.php の STOP_RULES に記載されている productId を抽出して返す（UIから非表示にするため）
function extract_stopped_product_ids_from_verify() {
  $f = __DIR__ . '/verify.php';
  $out = [];
  if (!file_exists($f)) return $out;
  $src = @file_get_contents($f);
  if ($src === false || $src === '') return $out;
  // 配列キー 'productId' => ... を抽出
  if (preg_match_all("/'([a-zA-Z0-9_\.]+)'\s*=>/", $src, $m)) {
    foreach ($m[1] as $pid) {
      // 接頭辞一致でサブスクのみ採用
      if (ALLOWED_PRODUCT_PREFIX === '' || str_starts_with_compat($pid, ALLOWED_PRODUCT_PREFIX)) {
        $out[$pid] = true;
      }
    }
  }
  return array_keys($out);
}

// 3) groupId ごとに subscriptions を取得し productId を集める
// （↑上で実装済みのためコメントとして残しているだけ）


/*
function fetch_subscription_product_ids() {
  // 20250923-05: シンプル化のため subscriptions を直接取得。
  // 必要に応じて app / subscriptionGroup でのフィルタを追加してください。
  $params = [ 'limit' => 200 ];
  // 例: アプリやグループで絞りたい場合（必要に応じて有効化）
  // $params['filter[app]'] = APP_ID;
  // $params['filter[subscriptionGroup]'] = SUBSCRIPTION_GROUP_ID;
  $data = asc_get('/v1/subscriptions', $params);
  $list = [];
  if (!empty($data['data']) && is_array($data['data'])) {
    foreach ($data['data'] as $item) {
      $pid = $item['attributes']['productId'] ?? null;
      if (is_string($pid) && $pid !== '') {
        if (ALLOWED_PRODUCT_PREFIX === '' || str_starts_with($pid, ALLOWED_PRODUCT_PREFIX)) {
          $list[$pid] = true; // set
        }
      }
    }
  }
  // TODO: ページネーション対応（next がある場合は追跡）。必要になったら実装してください。
  return array_keys($list);
}
*/

try { // 例外捕捉開始（以降で失敗時に500を返す）
  // https://www.bouzer.jp/takken_ai/products.php?refresh=1
  $refresh = isset($_GET['refresh']) && $_GET['refresh'] == '1'; // クエリ?refresh=1なら強制更新
  $useCache = false; // キャッシュ使用フラグ初期化
  if (!$refresh && file_exists(CACHE_FILE)) { // 更新要求がなくキャッシュが存在
    $age = time() - filemtime(CACHE_FILE); // キャッシュの経過秒数を算出
    if ($age < CACHE_TTL) {
      readfile(CACHE_FILE); // 有効期限内ならキャッシュをそのまま返す
      debug_log("products.php use cache");
      exit;
    }
  }

  //$ids = fetch_subscription_product_ids(); // 旧: 直接subscriptionsから取得（未使用）
  $ids = fetch_subscription_product_ids_for_app(TARGET_BUNDLE_ID); // 推奨: App→Group→Subscriptions経由でproductId一覧取得
  $before = $ids;

  // verify.php の STOP_RULES を参照して UI から非表示にする（販売停止に連動）
  try {
    $stopped = extract_stopped_product_ids_from_verify();
    if (!empty($stopped)) {
      $ids = array_values(array_filter($ids, function($id) use ($stopped) {
        return !in_array($id, $stopped, true);
      }));
    }
  } catch (Throwable $e) {
    // 無視（ログだけ必要ならここで）
  }

  if (empty($ids)) { // 取得できなかった場合
    // フォールバック：キャッシュがあればそれを返す
    if (file_exists(CACHE_FILE)) { // 以前のキャッシュがあれば
      readfile(CACHE_FILE); // それを返す
      debug_log("products.php return cache file"); 
      exit; // 終了
    }
    // 最後の手段：空
    $default = ['jp.bouzer.kakomongo.takken.month'];
    debug_log("products.php fallback default month");
    echo json_encode($default, JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE);
    exit; // 終了
  }
  // ソートして保存
  // sort($ids); // 既に上でusort済みのため不要
  if (file_put_contents(CACHE_FILE, json_encode($ids, JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE)) === false) { // JSONを書き出し
    http_response_code(500); // 書き込み失敗→HTTP 500
    debug_log("products.php error:failed_to_write_cache"); 
    echo json_encode(['error' => 'failed_to_write_cache']); // エラーJSON
    exit; // 終了
  }
  debug_log("products.php normal end"); 
  echo json_encode($ids, JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE); // 取得したproductId配列をJSON出力
} catch (Throwable $e) { // いずれかで例外が投げられた場合
  http_response_code(500); // HTTP 500に設定
  debug_log("products.php error:[".$e->getMessage()."]"); 
  echo json_encode(['error' => $e->getMessage()]); // エラー内容をJSONで返す
}
