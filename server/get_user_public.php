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
        $ini_info['database']['password']
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    $uid = isset($_POST['user_id']) ? intval($_POST['user_id']) : 0;
    if ($uid <= 0) {
        echo json_encode(['status' => 'error', 'reason' => 'invalid user_id']);
        exit;
    }

    $sql = 'SELECT nick_name FROM user WHERE user_id = ? AND delete_flg = 0 LIMIT 1';
    $stmt = $pdo->prepare($sql);
    $stmt->execute([$uid]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($row) {
        $nick = isset($row['nick_name']) ? (string)$row['nick_name'] : '';
        echo json_encode(['status' => 'success', 'nick_name' => $nick]);
    } else {
        echo json_encode(['status' => 'error', 'reason' => 'not found']);
    }
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'reason' => 'DB error']);
}

