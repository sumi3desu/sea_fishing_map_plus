<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

// 設定ファイル読み込み
$ini_info = parse_ini_file(_INI_FILE_PATH_, true);
$session_pre_key = create_session_key($ini_info['web']['url']);

// JSONレスポンスで返すためのヘッダー設定
header('Content-Type: application/json; charset=UTF-8');

debug_log("get_issues_count.php");


try {
    // 入力: user_id を取得（GET/POST/uid を許容）
    $userId = 0;
    if (isset($_GET['user_id'])) $userId = intval($_GET['user_id']);
    else if (isset($_GET['uid'])) $userId = intval($_GET['uid']);
    else if (isset($_POST['user_id'])) $userId = intval($_POST['user_id']);
    else if (isset($_POST['uid'])) $userId = intval($_POST['uid']);

    if ($userId <= 0) {
        http_response_code(400);
        echo json_encode([
            'status' => 'error',
            'reason' => 'user_id is required',
            'count'  => 0,
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    // PDOインスタンスの生成
    $pdo = new PDO(
        $ini_info['database']['dsn'],
        $ini_info['database']['user'],
        $ini_info['database']['password'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC
            //PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4"
        ]
    );

    // 今日の報告数（サーバローカル時刻基準）
    $sql = "SELECT COUNT(*) AS cnt FROM report_issues WHERE user_id = ? AND DATE(created_at) = CURDATE()";

    $stmt = $pdo->prepare($sql);
    $stmt->execute([$userId]);

    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    $count = isset($row['cnt']) ? intval($row['cnt']) : 0;
    $limit = 10;

    if ($count < $limit) {
        // 成功時のレスポンス
        $response = [
            'status' => 'success',
            'reason' => '',
            'count'  => $count,
            'limit'  => $limit,
        ];

        echo json_encode($response, JSON_UNESCAPED_UNICODE);
    } else {
        // 上限時のレスポンス
        $response = [
            'status' => 'error',
            'reason' => '1日10回までの報告しかできません。本日の上限に達しています。',
            'count'  => $count,
            'limit'  => $limit,
        ];

        echo json_encode($response, JSON_UNESCAPED_UNICODE);
    }
} catch (PDOException $e) {
    // エラー時は HTTPステータスコード 500 を返す
    http_response_code(500);

    $response = [
        'status'  => 'error',
        'reason' => '接続失敗: ' . $e->getMessage(),
        'count'  => 0,
    ];

    echo json_encode($response, JSON_UNESCAPED_UNICODE);
}
?>
