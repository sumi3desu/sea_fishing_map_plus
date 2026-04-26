<?php
session_cache_limiter("nocache");
session_start();

/*
|--------------------------------------------------------------------------
| 出力形式判定（json / html）
|--------------------------------------------------------------------------
*/
$format = 'json';

if (isset($_GET['format'])) {
    $format = strtolower($_GET['format']);
} else {
    $qs = isset($_SERVER['QUERY_STRING']) ? $_SERVER['QUERY_STRING'] : '';
    if ($qs && preg_match('/(?:^|&)(?:format|fmt|f)=html(?:&|$)/i', $qs)) {
        $format = 'html';
    } else {
        $accept = isset($_SERVER['HTTP_ACCEPT']) ? $_SERVER['HTTP_ACCEPT'] : '';
        if (strpos($accept, 'text/html') !== false) {
            $format = 'html';
        }
    }
}

/*
|--------------------------------------------------------------------------
| 共通ヘッダ
|--------------------------------------------------------------------------
*/
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Vary: Accept');
header('X-Resolved-Format: ' . $format);

if ($format === 'html') {
    header('Content-Type: text/html; charset=utf-8');
} else {
    header('Content-Type: application/json; charset=utf-8');
}

/*
|--------------------------------------------------------------------------
| OPTIONS 対応
|--------------------------------------------------------------------------
*/
if (isset($_SERVER['REQUEST_METHOD']) && $_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

/*
|--------------------------------------------------------------------------
| エラー設定
|--------------------------------------------------------------------------
*/
error_reporting(E_ALL);
ini_set('display_errors', '0');

/*
|--------------------------------------------------------------------------
| お知らせデータ
|--------------------------------------------------------------------------
*/
$notices = array(
    array(
        'id' => '2026-1-X',
        'title' => '「法のミカタ! FP編」リリース予定',
        'date' => '2026年1月X日',
        'body' => "ファイナンシャルプランナー関連の主要な法令をまとめて閲覧(横断検索)できます。",
        'type' => 'release',
        'priority' => 'normal',
    ),
    array(
        'id' => '2026-1-14',
        'title' => '「法のミカタ! 行政書士編」リリース',
        'date' => '2026年1月14日',
        'body' => "行政書士関連の主要な法令をまとめて閲覧(横断検索)できます。",
        'type' => 'release',
        'priority' => 'normal',
    ),
    array(
        'id' => '2026-1-5',
        'title' => '「法のミカタ! 宅建士編」リリース',
        'date' => '2026年1月5日',
        'body' => "宅建士試験で扱われる主要な法令をまとめて閲覧(横断検索)できます。",
        'type' => 'release',
        'priority' => 'normal',
    ),
    array(
        'id' => '2026-1-5',
        'title' => '「過去問GO! 宅建士編」リリース',
        'date' => '2026年1月5日',
        'body' => "過去問GO! 宅建士編は、宅建士試験の過去問を解きながら、自分の苦手分野を把握するための学習アプリです。",
        'type' => 'release',
        'priority' => 'normal',
    ),
≈);

/*
|--------------------------------------------------------------------------
| JSON 出力用ペイロード
|--------------------------------------------------------------------------
*/
$jsonFlags = 0;
if (defined('JSON_UNESCAPED_UNICODE')) $jsonFlags |= JSON_UNESCAPED_UNICODE;
if (defined('JSON_UNESCAPED_SLASHES')) $jsonFlags |= JSON_UNESCAPED_SLASHES;

$payload = array(
    'version' => '1.0',
    'updated_at' => date('c'),
    'notices' => $notices,
);

/*
|--------------------------------------------------------------------------
| HTML 出力
|--------------------------------------------------------------------------
*/
if ($format === 'html') {

    function h($s) {
        return htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
    }

    echo '<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>お知らせ</title>
<style>
body {
  font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
  line-height: 1.6;
  margin: 16px;
  color: #222;
}
.notice {
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  padding: 12px 14px;
  margin: 10px 0;
  background: #fff;
}
.title {
  font-weight: 600;
  margin: 0 0 4px;
}
.meta {
  color: #6b7280;
  font-size: 12px;
  margin-bottom: 6px;
}
.body {
  white-space: pre-wrap; /* ← 改行はこれで効く */
  margin: 0;
}
.badge {
  display: inline-block;
  font-size: 11px;
  padding: 2px 6px;
  border-radius: 9999px;
  margin-left: 6px;
  background: #eef2ff;
  color: #3730a3;
}
</style>
</head>
<body>

<h2 style="margin:0 0 12px">お知らせ</h2>';

    foreach ($notices as $n) {
        echo '<article class="notice">';
        echo '<h3 class="title">' . h($n['title']) . '</h3>';
        echo '<div class="meta">' . h($n['date']);

        if (!empty($n['type'])) {
            echo ' <span class="badge">' . h($n['type']) . '</span>';
        }
        if (!empty($n['priority']) && $n['priority'] !== 'normal') {
            echo ' <span class="badge">' . h($n['priority']) . '</span>';
        }

        echo '</div>';
        echo '<p class="body">' . h($n['body']) . '</p>';
        echo '</article>';
    }

    echo '</body></html>';

} else {
    /*
    |--------------------------------------------------------------------------
    | JSON 出力
    |--------------------------------------------------------------------------
    */
    echo json_encode($payload, $jsonFlags);
}

exit;
