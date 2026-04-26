<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

header('Content-Type: application/json; charset=UTF-8');

try {
    $ini_info = parse_ini_file(_INI_FILE_PATH_, true);
    $pdo = new PDO(
        $ini_info['database']['dsn'],
        $ini_info['database']['user'],
        $ini_info['database']['password'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );

    $userId = isset($_POST['user_id']) ? (int)$_POST['user_id'] : 0;
    $notifOnOff = isset($_POST['notif_on_off']) ? (int)$_POST['notif_on_off'] : 1;
    $notifOnOff = ($notifOnOff !== 0) ? 1 : 0;

    if ($userId <= 0) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'invalid user_id'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    $stmt = $pdo->prepare(
        'UPDATE user
            SET notif_on_off = :notif_on_off
          WHERE user_id = :user_id
            AND delete_flg = 0'
    );
    $stmt->execute([
        ':notif_on_off' => $notifOnOff,
        ':user_id' => $userId,
    ]);

    echo json_encode([
        'status' => 'success',
        'notif_on_off' => $notifOnOff,
    ], JSON_UNESCAPED_UNICODE);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage(),
    ], JSON_UNESCAPED_UNICODE);
}
?>
