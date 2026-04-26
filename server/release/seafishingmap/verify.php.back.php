<?php
/**
 * verify.php
 * Flutter から送られてくる iOS レシートを Apple に照会して、
 * サブスクが有効かどうか（isActive）と有効期限（expiresDateMs）を返す最小実装。
 *
 * 期待する入力(JSON):
 *   {
 *     "productId": "jp.bouzer.kakomongo.takken.month",
 *     "receiptData": "<Base64のレシート文字列>",
 *     "appUserId": "任意"   // 無くてもOK
 *   }
 *
 * 返却(JSON):
 *   {
 *     "isActive": true|false,
 *     "expiresDateMs": 1735689600000,   // 無ければ省略
 *     "environment": "Sandbox|Production",
 *     "reason": "任意の補足(デバッグ用)" // 失敗時など
 *   }
 */
session_cache_limiter("nocache");
session_start();
include_once("include/define.php");
// 設定ファイル読み込み
$ini_info = parse_ini_file(_INI_FILE_PATH_, true);
$session_pre_key = create_session_key($ini_info['web']['url']);

// ======= 必ず自分の値に置き換えてください！ =======
const APP_SHARED_SECRET     = 'c0043af80ff44cd4b05ad1008fe4c6fe';
const EXPECTED_BUNDLE_ID    = 'jp.bouzer.kakomongo.takken'; // あなたのBundle ID
// 対象の ProductId を絞りたい場合（複数可）。
// 20250923-03: サーバ側変更なし運用のため、リストを空にし接頭辞で制限する方式に対応
const ALLOWED_PRODUCT_IDS   = [];
// 20250923-03: 許可する productId の接頭辞（空文字なら制限なし）
const ALLOWED_PRODUCT_PREFIX = 'jp.bouzer.kakomongo.takken.';

// ─────────────────────────────────────────────────────────
// 停止日ルール（B）: 新規のみ禁止・既存継続は許容
// - 対象 productId ごとに「この日時以降の初回購入」は無効として扱う
// - 既存加入者（初回購入 < 停止日時）は従来通り expires で判定
// - 日時は UTC ミリ秒
// 例）「今以降は新規禁止」にするなら、下の NOW_MS を使う
$NOW_MS = (int)floor(microtime(true) * 1000);
$STOP_RULES = [
  'jp.bouzer.kakomongo.takken.3month' => $NOW_MS,
  'jp.bouzer.kakomongo.takken.6month' => $NOW_MS,
  'jp.bouzer.kakomongo.takken.year'    => $NOW_MS,
];
// ─────────────────────────────────────────────────────────
// ================================================

header('Content-Type: application/json; charset=utf-8');
// （必要ならCORS）header('Access-Control-Allow-Origin: https://your.app.domain');

$raw = file_get_contents('php://input');
$req = json_decode($raw, true);
if (!is_array($req)) {
  http_response_code(400);
  echo json_encode(['isActive' => false, 'reason' => 'bad_json']);
  exit;
}

$productId   = $req['productId']   ?? null; // 20250923-01: 複数プラン対応。nullでも受け付ける
$receiptData = $req['receiptData'] ?? null;
$appUserId   = $req['appUserId']   ?? null; // 任意
debug_log("verify.php start productId[".$productId."] appUserId[".$appUserId."]");

// 20250923-01: productId は省略可。レシートのみで判定できるようにする。
if (!$receiptData) {
  http_response_code(400);
  echo json_encode(['isActive' => false, 'reason' => 'missing_receipt']);

  debug_log("verify.php missing_receipt");

  exit;
}
// 20250923-03: 許可リストがある場合は優先、無ければ接頭辞で弾く
if ($productId !== null && !empty(ALLOWED_PRODUCT_IDS) && !in_array($productId, ALLOWED_PRODUCT_IDS, true)) {
  http_response_code(400);
  echo json_encode(['isActive' => false, 'reason' => 'product_not_allowed']);
  debug_log("verify.php product_not_allowed");
  exit;
}
if ($productId !== null && empty(ALLOWED_PRODUCT_IDS) && !empty(ALLOWED_PRODUCT_PREFIX)) {
  if (strpos($productId, ALLOWED_PRODUCT_PREFIX) !== 0) {
    http_response_code(400);
    echo json_encode(['isActive' => false, 'reason' => 'product_prefix_not_allowed']);
    debug_log("verify.php product_prefix_not_allowed");
    exit;
  }
}

// Apple エンドポイント
$URL_PROD    = 'https://buy.itunes.apple.com/verifyReceipt';
$URL_SANDBOX = 'https://sandbox.itunes.apple.com/verifyReceipt';

// Apple へ送るペイロード
$payload = [
  'receipt-data'             => $receiptData,
  'password'                 => APP_SHARED_SECRET,
  'exclude-old-transactions' => true,
];

// cURL で POST
function post_json($url, $data) {
  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST           => true,
    CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
    CURLOPT_POSTFIELDS     => json_encode($data),
    CURLOPT_TIMEOUT        => 15,
  ]);
  $res = curl_exec($ch);
  $err = curl_error($ch);
  $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
  curl_close($ch);
  if ($res === false) {
    return [null, $code, $err];
  }
  return [json_decode($res, true), $code, null];
}

// まず本番に投げる → 21007（Sandbox）ならサンドボックスへ投げ直し
list($result, $http, $cerr) = post_json($URL_PROD, $payload);
if ($result === null) {
  http_response_code(502);
  echo json_encode(['isActive' => false, 'reason' => 'curl_error_prod: ' . $cerr]);
  debug_log("verify.php curl_error_prod");
  exit;
}
if (isset($result['status']) && $result['status'] == 21007) {
  list($result, $http, $cerr) = post_json($URL_SANDBOX, $payload);
  if ($result === null) {
    http_response_code(502);
    echo json_encode(['isActive' => false, 'reason' => 'curl_error_sandbox: ' . $cerr]);
    debug_log("verify.php curl_error_sandbox");
    exit;
  }
}

// ステータスチェック
$status = $result['status'] ?? -1;
$environment = $result['environment'] ?? null; // 20250923: env を明示
if ($status !== 0) {
  // 21002: receipt不正 / 21003: 認証失敗 など
  echo json_encode([
    'isActive' => false,
    'reason'   => 'apple_status_' . $status,
    'environment' => $environment
  ]);
  debug_log("verify.php 21002,21003,,,");
  exit;
}

// レシート本体
$receipt = $result['receipt'] ?? null;
if (!$receipt) {
  echo json_encode(['isActive' => false, 'reason' => 'no_receipt', 'environment' => $result['environment'] ?? null]);
  debug_log("verify.php NG receipt");
  exit;
}

// バンドルID一致を確認（不一致なら拒否推奨）
if (!empty(EXPECTED_BUNDLE_ID) && ($receipt['bundle_id'] ?? '') !== EXPECTED_BUNDLE_ID) {
  echo json_encode(['isActive' => false, 'reason' => 'bundle_mismatch', 'environment' => $result['environment'] ?? null]);
  debug_log("verify.php bundle_mismatch");
  exit;
}

// サブスク（自動更新）情報は latest_receipt_info に入る
// 20250923: グレース期間/課金リトライも考慮するため、pending_renewal_info も参照
$latestList = $result['latest_receipt_info'] ?? [];
$pendingList = $result['pending_renewal_info'] ?? [];

// 自動更新サブスク以外（非消耗/消耗）の場合、receipt['in_app'] に取引が入るため、保険で併合
if (empty($latestList) && !empty($receipt['in_app'])) {
  $latestList = $receipt['in_app'];
}

// 対象 productId に絞る（20250923-01/03: 指定が無い/ヒットしない場合は許可リスト・接頭辞でフォールバック）
$filtered = [];
if ($productId !== null) {
  $filtered = array_values(array_filter($latestList, function($x) use ($productId) {
    return isset($x['product_id']) && $x['product_id'] === $productId;
  }));
}
if (empty($filtered)) {
  $allowedSet = ALLOWED_PRODUCT_IDS;
  if (!empty($allowedSet)) {
    $filtered = array_values(array_filter($latestList, function($x) use ($allowedSet) {
      return isset($x['product_id']) && in_array($x['product_id'], $allowedSet, true);
    }));
  } else if (!empty(ALLOWED_PRODUCT_PREFIX)) {
    $filtered = array_values(array_filter($latestList, function($x) {
      return isset($x['product_id']) && strpos($x['product_id'], ALLOWED_PRODUCT_PREFIX) === 0;
    }));
  } else {
    $filtered = $latestList;
  }
}
if (empty($filtered)) {
  echo json_encode([
    'isActive' => false,
    'reason'   => 'no_transactions_for_product',
    'environment' => $environment
  ]);
  debug_log("verify.php no_transactions_for_product");
  exit;
}

// 期限が最も新しいものを採用
usort($filtered, function($a, $b) {
  $ams = intval($a['expires_date_ms'] ?? 0);
  $bms = intval($b['expires_date_ms'] ?? 0);
  return $bms <=> $ams;
});
$latest = $filtered[0];

// 返金/取り消しの確認
$isCancelled = !empty($latest['cancellation_date_ms']);

// 有効期限
$expiresMs = isset($latest['expires_date_ms']) ? intval($latest['expires_date_ms']) : null;
$nowMs     = intval(microtime(true) * 1000);

// 20250923: pending_renewal_info からグレース期間/自動更新状態を取得
$graceMs = null;
$autoRenewStatus = null; // '1' or '0'
foreach ($pendingList as $p) {
  // auto_renew_product_id または product_id が一致する行を採用
  $pid1 = $p['product_id'] ?? null;
  $pid2 = $p['auto_renew_product_id'] ?? null;
  if ($pid1 === $productId || $pid2 === $productId) {
    if (!empty($p['grace_period_expires_date_ms'])) {
      $graceMs = intval($p['grace_period_expires_date_ms']);
    }
    if (isset($p['auto_renew_status'])) {
      $autoRenewStatus = (string)$p['auto_renew_status'];
    }
    break;
  }
}

// isActive 判定（Sandboxでは厳格に expires を優先。Production でのみグレースを考慮）

// original_transaction_id を取得（安定キー）
// - サブスクの初回購入時に付与され、その後も変化しない識別子。
// - 端末変更や復元でも同じ値のため、ユーザー権利の冪等な突き合わせに利用できます。
$originalTransactionId = isset($latest['original_transaction_id'])
  ? (string)$latest['original_transaction_id']
  : null;

// ここでは「取得のみ」。必要に応じてDB保存や監査ログに利用してください。
// 例) saveEntitlement($appUserId, $originalTransactionId, $expiresMs, $isActive);

$isActive = (!$isCancelled) && ($expiresMs !== null) && ($expiresMs > $nowMs);
if (!$isActive && $environment === 'Production') {
  if ($graceMs !== null && $graceMs > $nowMs) {
    $isActive = true;
  }
}

// 任意：ここで DB に original_transaction_id をユーザー(appUserId)に紐付けて保存すると安全
// $origTid = $latest['original_transaction_id'] ?? null;
// saveEntitlement($appUserId, $origTid, $expiresMs, $isActive);

// 20250923-02: 応答に採用 productId を含めて、どのプランか判別できるようにする
$currentProductId = isset($latest['product_id']) ? (string)$latest['product_id'] : null;

// 20250923: 追加情報（originalTransactionId, autoRenewStatus）を返却
$resp = [
  'isActive'       => $isActive,
  'expiresDateMs'  => $expiresMs,
  'environment'    => $environment,
  'originalTransactionId' => $originalTransactionId,
  // 20250923-02: 現在判定に用いた productId
  'productId'      => $currentProductId,
];
// 停止日ルール（B）の適用
// - 初回購入日時 original_purchase_date_ms を取得（無ければ同一 original_transaction_id の最古 purchase_date_ms を採用）
if ($currentProductId !== null && isset($STOP_RULES[$currentProductId])) {
  $stopFrom = (int)$STOP_RULES[$currentProductId];
  $origMs = null;
  if (!empty($latest['original_purchase_date_ms'])) {
    $origMs = (int)$latest['original_purchase_date_ms'];
  } else if ($originalTransactionId !== null) {
    // フォールバック: 同一 original_transaction_id の中で最古の purchase_date_ms
    $minMs = null;
    foreach ($latestList as $row) {
      if (($row['original_transaction_id'] ?? null) === $originalTransactionId) {
        $pms = isset($row['purchase_date_ms']) ? (int)$row['purchase_date_ms'] : null;
        if ($pms !== null) {
          if ($minMs === null || $pms < $minMs) $minMs = $pms;
        }
      }
    }
    if ($minMs !== null) $origMs = $minMs;
  }
  if ($origMs !== null && $origMs >= $stopFrom) {
    // 停止日時以降に初回購入された新規は、たとえ有効期限内でも権利を付与しない
    $isActive = false;
    $resp['isActive'] = false;
    $resp['reason'] = 'stopped_new_sales';
  }
}

if ($autoRenewStatus !== null) {
  $resp['autoRenewStatus'] = $autoRenewStatus;
}
if ($isCancelled) {
  $resp['reason'] = 'cancelled';
}
if ($graceMs !== null && $graceMs > $nowMs) {
  $resp['reason'] = ($resp['reason'] ?? 'grace_period');
}
debug_log("verify.php end isActive[".$isActive."] expiresDateMs[".$expiresDateMs."] environment[".$environment."] originalTransactionId[".$envoriginalTransactionIdironment."] currentProductId[".$currentProductId."] autoRenewStatus[".$autoRenewStatus."] reason[".$reason."]");

echo json_encode($resp);
