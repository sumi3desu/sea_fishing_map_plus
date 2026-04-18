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

    $userId = isset($_POST['user_id']) ? (int)$_POST['user_id'] : (isset($_GET['user_id']) ? (int)$_GET['user_id'] : 0);
    if ($userId <= 0) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'user_id is required'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    $sql = "SELECT
                p.spot_id,
                MAX(p.create_at) AS last_catch_at,
                COUNT(*) AS catch_count
            FROM post p
            WHERE p.user_id = :user_id
              AND p.post_kind = 1
              AND p.spot_id IS NOT NULL
              AND p.spot_id > 0
            GROUP BY p.spot_id
            ORDER BY last_catch_at DESC, p.spot_id DESC";
    $stmt = $pdo->prepare($sql);
    $stmt->bindValue(':user_id', $userId, PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll();

    echo json_encode(['status' => 'success', 'rows' => $rows], JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()], JSON_UNESCAPED_UNICODE);
}
?>
