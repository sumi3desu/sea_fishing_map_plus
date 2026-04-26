<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

header('Content-Type: application/json');

$ini_info = parse_ini_file(_INI_FILE_PATH_, true);

// ★ user_id はセッション（または認証トークン）から取得
$user_id = $_POST['user_id'] ?? null;

// spot_id だけをクライアントから受ける
$spot_id = $_POST['spot_id'] ?? null;

$action = $_POST['action'] ?? null;

if ($action === null){
    $action = 'enter';
}

if ($user_id === null || $spot_id === null || !ctype_digit((string)$spot_id)) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'reason' => 'invalid params']);
    exit;
}

try {
    $pdo = new PDO(
        $ini_info['database']['dsn'],
        $ini_info['database']['user'],
        $ini_info['database']['password']
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $stmt = null;
    if ($action == 'enter'){

        $stmt = $pdo->prepare(
            "INSERT INTO favorites (user_id, spot_id, created_at, updated_at)
             VALUES (:user_id, :spot_id, NOW(), NOW())
            ON DUPLICATE KEY UPDATE
                updated_at = NOW()"
        );
    } else if ($action == 'delete'){
        $stmt = $pdo->prepare("DELETE FROM favorites WHERE user_id=:user_id AND spot_id=:spot_id");
    }
    $stmt->execute([
        ':user_id' => (int)$user_id,
        ':spot_id' => (int)$spot_id,
    ]);

    http_response_code(200);
    echo json_encode(['status' => 'success', 'reason' => '']);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'reason' => 'DB設定失敗']);
}
