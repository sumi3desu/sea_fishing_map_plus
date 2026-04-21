<?php
// Simple report receiver (trimmed fields): stores CSV log and emails the report.
// Path assumptions: placed under takken_ai2/server on production host.

mb_internal_encoding('UTF-8');

function h($s) { return htmlspecialchars($s ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }

// Basic spam honeypot
if (!empty($_POST['website'])) {
  http_response_code(200);
  echo '<!DOCTYPE html><meta charset="utf-8"><p>OK</p>'; // silently accept
  exit;
}

// Collect fields (trimmed)
// Use JST time for both record timestamp and monthly CSV filename
$nowJst = new DateTime('now', new DateTimeZone('Asia/Tokyo'));
$category = isset($_POST['category']) ? trim((string)$_POST['category']) : '';
$title = isset($_POST['title']) ? trim((string)$_POST['title']) : '';
$details = isset($_POST['details']) ? trim((string)$_POST['details']) : '';
$contact = isset($_POST['contact']) ? trim((string)$_POST['contact']) : '';

// Validate required
if ($title === '' || $details === '' || $category === '') {
  http_response_code(400);
  ?>
  <!DOCTYPE html>
  <html lang="ja">
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>入力エラー</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    body { font-family: 'Roboto', -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans JP', Helvetica, Arial, sans-serif; margin: 0; }
    main { padding: 20px; max-width: 760px; margin: 0 auto; }
    .card { border:1px solid #ddd; border-radius:12px; padding:16px; margin-top: 16px; }
    a.btn { display:inline-block; padding:10px 16px; border-radius:8px; background:#1769aa; color:#fff; text-decoration:none; }
    header { padding: 16px 20px; border-bottom: 1px solid #ddd; font-weight: 600; }
    .err { color: #b00020; }
  </style>
  <header>入力エラー</header>
  <main>
    <div class="card">
      <p class="err">件名、詳細、種別は必須です。前の画面に戻って入力を確認してください。</p>
      <p><a class="btn" href="app://close">設定のその他に戻る</a></p>
    </div>
  </main>
  </html>
  <?php
  exit;
}

$fields = [
  'user_id' => $_POST['uid'] ?? '',
  'app' => $_POST['app'] ?? '',
  'platform' => $_POST['platform'] ?? '',
  'from' => $_POST['from'] ?? '',
  'category' => $category,
  'title' => $title,
  'contact' => $contact,
  'details' => $details,
  'created_at' => $nowJst->format('Y-m-d H:i:s'),
  'ip' => $_SERVER['REMOTE_ADDR'] ?? '',
  'ua' => $_SERVER['HTTP_USER_AGENT'] ?? '',
];

// Check user-level block before rate limit (requires DB access on production host)
// If include files are not available (e.g., local dev), this block is skipped gracefully.
try {
  if (!empty($_POST['uid'])) {
    @include_once(__DIR__ . '/include/define.php');
    @include_once(__DIR__ . '/include/db.php');
    if (defined('_INI_FILE_PATH_')) {
      $ini_info = @parse_ini_file(_INI_FILE_PATH_, true);
      if ($ini_info && isset($ini_info['database']['dsn'])) {
        $pdo = new PDO($ini_info['database']['dsn'], $ini_info['database']['user'], $ini_info['database']['password']);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $st = $pdo->prepare('SELECT reports_blocked, reports_blocked_until FROM `user` WHERE user_id = ? LIMIT 1');
        $st->execute([$_POST['uid']]);
        $u = $st->fetch(PDO::FETCH_ASSOC);
        if ($u) {
          $blocked = !empty($u['reports_blocked']) && intval($u['reports_blocked']) === 1;
          $tempBlocked = false;
          if (!empty($u['reports_blocked_until'])) {
            try {
              $until = new DateTime($u['reports_blocked_until'], new DateTimeZone('Asia/Tokyo'));
              $tempBlocked = ($until > $nowJst);
            } catch (Exception $e) { $tempBlocked = false; }
          }
          if ($blocked || $tempBlocked) {
            http_response_code(403);
            ?>
            <!DOCTYPE html>
            <html lang="ja">
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>送信制限</title>
            <link rel="preconnect" href="https://fonts.googleapis.com">
            <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
            <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
            <style>
              body { font-family: 'Roboto', -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans JP', Helvetica, Arial, sans-serif; margin: 0; }
              main { padding: 20px; max-width: 760px; margin: 0 auto; }
              .card { border:1px solid #ddd; border-radius:12px; padding:16px; margin-top: 16px; }
              a.btn { display:inline-block; padding:10px 16px; border-radius:8px; background:#1769aa; color:#fff; text-decoration:none; }
              header { padding: 16px 20px; border-bottom: 1px solid #ddd; font-weight: 600; }
              .err { color:#b00020; }
            </style>
            <header>送信制限</header>
            <main>
              <div class="card">
                <p class="err">
                  <?php if ($blocked) { echo '報告の送信は停止中です。不適切な利用が確認されました。'; }
                        elseif ($tempBlocked) { echo '報告の送信は一時停止中です。不適切な利用が確認されました。'; } ?>
                </p>
                <p><a class="btn" href="app://close">設定のその他に戻る</a></p>
              </div>
            </main>
            </html>
            <?php
            exit;
          }
        }
      }
    }
  }
} catch (Exception $e) {
  // ignore and continue (fail-open to keep basic reporting functional if DB unavailable)
}

// Daily rate limit (JST): max 10 submissions per user_id (no IP fallback)
$rateDir = __DIR__ . '/rate_limits';
if (!is_dir($rateDir)) { @mkdir($rateDir, 0777, true); }
$rateKey = isset($_POST['uid']) ? trim((string)$_POST['uid']) : '';
if ($rateKey === '') {
  http_response_code(400);
  ?>
  <!DOCTYPE html>
  <html lang="ja">
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>送信エラー</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    body { font-family: 'Roboto', -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans JP', Helvetica, Arial, sans-serif; margin: 0; }
    main { padding: 20px; max-width: 760px; margin: 0 auto; }
    .card { border:1px solid #ddd; border-radius:12px; padding:16px; margin-top: 16px; }
    a.btn { display:inline-block; padding:10px 16px; border-radius:8px; background:#1769aa; color:#fff; text-decoration:none; }
    header { padding: 16px 20px; border-bottom: 1px solid #ddd; font-weight: 600; }
    .err { color:#b00020; }
  </style>
  <header>送信エラー</header>
  <main>
    <div class="card">
      <p class="err">ユーザーIDが確認できないため送信できません。設定画面から再度お試しください。</p>
      <p><a class="btn" href="app://close">設定のその他に戻る</a></p>
    </div>
  </main>
  </html>
  <?php
  exit;
}
$bucket = $nowJst->format('Ymd');
$rateFile = $rateDir . '/' . $bucket . '_' . sha1($rateKey) . '.txt';
$count = 0;
if (is_file($rateFile)) {
  $raw = @file_get_contents($rateFile);
  if ($raw !== false) { $count = max(0, (int)$raw); }
}
if ($count >= 10) {
  http_response_code(429);
  ?>
  <!DOCTYPE html>
  <html lang="ja">
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>送信制限</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    body { font-family: 'Roboto', -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans JP', Helvetica, Arial, sans-serif; margin: 0; }
    main { padding: 20px; max-width: 760px; margin: 0 auto; }
    .card { border:1px solid #ddd; border-radius:12px; padding:16px; margin-top: 16px; }
    a.btn { display:inline-block; padding:10px 16px; border-radius:8px; background:#1769aa; color:#fff; text-decoration:none; }
    header { padding: 16px 20px; border-bottom: 1px solid #ddd; font-weight: 600; }
    .err { color:#b00020; }
  </style>
  <header>送信制限</header>
  <main>
    <div class="card">
      <p class="err">1日10回までの報告しかできません。本日の上限に達しました。</p>
      <p><a class="btn" href="app://close">設定のその他に戻る</a></p>
    </div>
  </main>
  </html>
  <?php
  exit;
}
@file_put_contents($rateFile, (string)($count + 1), LOCK_EX);

// Append to CSV log (monthly: CSV/report_logs_yyyymm.csv in JST)
$csvDir = __DIR__ . '/CSV';
if (!is_dir($csvDir)) { @mkdir($csvDir, 0777, true); }
$csvFile = $csvDir . '/report_logs_' . $nowJst->format('Ym') . '.csv';
$isNew = !file_exists($csvFile);
$fp = fopen($csvFile, 'a');
if ($fp) {
  if ($isNew) {
    fputcsv($fp, array_keys($fields));
  }
  fputcsv($fp, $fields);
  fclose($fp);
}

// Optional email (best-effort)
$to = 'contact@bouzer.jp';
$subject = '【潮はどう? Pro 報告】' . ($fields['category'] ?: '内容修正') . ' ' . ($fields['title'] ?: '');
$body = "以下の内容で報告が届きました。\n\n" .
  "種別: {$fields['category']}\n" .
  "件名: {$fields['title']}\n" .
  "詳細:\n{$fields['details']}\n\n" .
  "連絡先: {$fields['contact']}\n\n" .
  "メタ: user_id={$fields['user_id']} app={$fields['app']} platform={$fields['platform']} from={$fields['from']}\n" .
  "環境: ip={$fields['ip']} ua={$fields['ua']}\n" .
  "受付時刻(UTC): {$fields['created_at']}\n";

// Set From/Reply-To headers. Note: Return-Path is controlled by envelope sender (-f option) not header.
$from = 'contact@bouzer.jp';
$headers = [];
$headers[] = 'MIME-Version: 1.0';
$headers[] = 'Content-Type: text/plain; charset=UTF-8';
$headers[] = 'From: ' . $from;
$headers[] = 'Reply-To: ' . ($fields['contact'] ?: $from);
$headers[] = 'X-Mailer: PHP/' . phpversion();
$headersStr = implode("\r\n", $headers);

// Use envelope sender to set Return-Path for SPF alignment (hosting may restrict this)
$params = '-f ' . escapeshellarg($from);
@mail($to, $subject, $body, $headersStr, $params);

// Persist into DB (best-effort) after mail attempt
try {
  // Load DB ini if available
  if (!defined('_INI_FILE_PATH_')) {
    @include_once(__DIR__ . '/include/define.php');
  }
  if (defined('_INI_FILE_PATH_')) {
    $ini_info2 = @parse_ini_file(_INI_FILE_PATH_, true);
    if ($ini_info2 && isset($ini_info2['database']['dsn'])) {
      $pdo2 = new PDO($ini_info2['database']['dsn'], $ini_info2['database']['user'], $ini_info2['database']['password']);
      $pdo2->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
      $sql2 = 'INSERT INTO report_issues (category, title, details, contact_email, post_id, user_id, app_version, platform, from_source, ip_address, user_agent, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())';
      $st2 = $pdo2->prepare($sql2);
      $pidInt = (isset($_POST['post_id']) && ctype_digit((string)$_POST['post_id'])) ? intval($_POST['post_id']) : null;
      $uidInt = (isset($_POST['uid']) && ctype_digit((string)$_POST['uid'])) ? intval($_POST['uid']) : null;
      $st2->execute([
        $fields['category'],
        $fields['title'],
        $fields['details'],
        ($fields['contact'] !== '' ? $fields['contact'] : null),
        $pidInt,
        $uidInt,
        ($fields['app'] !== '' ? $fields['app'] : null),
        ($fields['platform'] !== '' ? $fields['platform'] : null),
        ($fields['from'] !== '' ? $fields['from'] : null),
        ($fields['ip'] !== '' ? $fields['ip'] : null),
        ($fields['ua'] !== '' ? $fields['ua'] : null),
      ]);
    }
  }
} catch (Exception $e) {
  // ignore DB errors (do not disturb thank-you page)
}

// Thank you page
?>
<!DOCTYPE html>
<html lang="ja">
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>送信完了</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
<style>
  body { font-family: 'Roboto', -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans JP', Helvetica, Arial, sans-serif; margin: 0; }
  main { padding: 20px; max-width: 760px; margin: 0 auto; }
  .card { border:1px solid #ddd; border-radius:12px; padding:16px; margin-top: 16px; }
  a.btn { display:inline-block; padding:10px 16px; border-radius:8px; background:#1769aa; color:#fff; text-decoration:none; }
  .muted { color:#666; font-size: 0.95rem; }
  .kv { color:#333; }
  .kv b { display:inline-block; min-width: 9em; }
  .kv + .kv { margin-top: 6px; }
  .top { margin-top:12px; }
  header { padding: 16px 20px; border-bottom: 1px solid #ddd; font-weight: 600; }
  .ok { color: #1769aa; }
  .section { margin-top: 12px; }
  .small { font-size: 0.9rem; }
  pre { white-space: pre-wrap; background:#f8f8f8; padding:12px; border-radius:8px; }
</style>
<header>送信完了</header>
<main>
  <div class="card">
    <p class="ok">ご報告ありがとうございました。内容を確認し、必要に応じて対応いたします。</p>
    <p class="muted small">控えとして受付情報の一部を表示します。</p>
    <div class="section">
      <div class="kv"><b>種別</b> <?php echo h($fields['category']); ?></div>
      <div class="kv"><b>件名</b> <?php echo h($fields['title']); ?></div>
      <div class="kv"><b>連絡先</b> <?php echo h($fields['contact']); ?></div>
    </div>
    <div class="section">
      <div class="kv"><b>受付(JST)</b> <?php echo h($fields['created_at']); ?></div>
    </div>
<!--    <div class="top">
      <a class="btn" href="report_issue.html">続けて報告する</a>
    </div>-->
  </div>
</main>
</html>
