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

debug_log("enter_profile.php");

try {
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

    // 入力値取得
    $userId = isset($_POST['user_id']) ? (int)$_POST['user_id'] : 0;
    $type   = isset($_POST['type']) ? trim((string)$_POST['type']) : '';

    if ($userId <= 0) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'invalid user_id'], JSON_UNESCAPED_UNICODE);
        exit;
    }
    if (!in_array($type, ['avatar', 'cover'], true)) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'invalid type'], JSON_UNESCAPED_UNICODE);
        exit;
    }
    if (!isset($_FILES['file']) || !is_uploaded_file($_FILES['file']['tmp_name'])) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'file not uploaded'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    $file      = $_FILES['file'];
    $tmpPath   = $file['tmp_name'];
    $origName  = $file['name'];
    $ext       = strtolower(pathinfo($origName, PATHINFO_EXTENSION));
    if ($ext === '') { $ext = 'png'; }
    // 許可拡張子チェック（最低限）
    $allow = ['png','jpg','jpeg','webp'];
    if (!in_array($ext, $allow, true)) { $ext = 'png'; }

    // 保存先パス（iniのprofile.path配下に user_id ディレクトリを作成）
    $baseProfilePath = isset($ini_info['profile']['path']) ? rtrim($ini_info['profile']['path'], '/'): '';
    if ($baseProfilePath === '') {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => 'profile.path not configured'], JSON_UNESCAPED_UNICODE);
        exit;
    }
    $uploadDir = $baseProfilePath . '/' . $userId;
    if (!is_dir($uploadDir)) {
        if (!mkdir($uploadDir, 0755, true)) {
            http_response_code(500);
            echo json_encode(['status' => 'error', 'message' => 'failed to create directory'], JSON_UNESCAPED_UNICODE);
            exit;
        }
    }

    // 古い同種ファイルを掃除（任意）
    foreach (glob($uploadDir . '/' . $type . '_*.*') as $old) {
        @unlink($old);
    }

    $basename = sprintf('%s_%d.%s', $type, time(), $ext);
    $destPath = $uploadDir . '/' . $basename;

    if (!move_uploaded_file($tmpPath, $destPath)) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => 'failed to save file'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    // 相対パス（profile.path の配下相当）を返却
    $relative = sprintf('%d/%s', $userId, $basename);

    $response = [
        'status' => 'success',
        'type'   => $type,
        'path'   => $relative,
    ];

    echo json_encode($response, JSON_UNESCAPED_UNICODE);

} catch (PDOException $e) {
    // エラー時は HTTPステータスコード 500 を返す
    http_response_code(500);

    $response = [
        'status'  => 'error',
        'message' => '接続失敗: ' . $e->getMessage()
    ];

    echo json_encode($response, JSON_UNESCAPED_UNICODE);
}
?>
