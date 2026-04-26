<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

header('Content-Type: application/json; charset=UTF-8');

function ensureColumn(PDO $pdo, string $table, string $column, string $ddl): void
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) AS cnt
           FROM information_schema.COLUMNS
          WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = :table_name
            AND COLUMN_NAME = :column_name'
    );
    $stmt->execute([
        ':table_name' => $table,
        ':column_name' => $column,
    ]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    $cnt = isset($row['cnt']) ? (int)$row['cnt'] : 0;
    if ($cnt === 0) {
        $pdo->exec($ddl);
    }
}

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

    ensureColumn(
        $pdo,
        'user',
        'x_username',
        "ALTER TABLE user ADD COLUMN x_username VARCHAR(15) DEFAULT NULL"
    );
    ensureColumn(
        $pdo,
        'user',
        'x_public',
        "ALTER TABLE user ADD COLUMN x_public TINYINT(1) NOT NULL DEFAULT 0"
    );
    ensureColumn(
        $pdo,
        'user',
        'instagram_username',
        "ALTER TABLE user ADD COLUMN instagram_username VARCHAR(30) DEFAULT NULL"
    );
    ensureColumn(
        $pdo,
        'user',
        'instagram_public',
        "ALTER TABLE user ADD COLUMN instagram_public TINYINT(1) NOT NULL DEFAULT 0"
    );

    $userId = isset($_POST['user_id']) ? (int)$_POST['user_id'] : 0;
    if ($userId <= 0) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'invalid user_id'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    $stmt = $pdo->prepare(
        'SELECT nick_name, x_username, x_public, instagram_username, instagram_public
           FROM user
          WHERE user_id = :user_id
            AND delete_flg = 0
          LIMIT 1'
    );
    $stmt->execute([':user_id' => $userId]);
    $row = $stmt->fetch();

    if (!$row) {
        http_response_code(404);
        echo json_encode(['status' => 'error', 'message' => 'user not found'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    echo json_encode([
        'status' => 'success',
        'nick_name' => $row['nick_name'] ?? '',
        'x_username' => $row['x_username'] ?? '',
        'x_public' => (int)($row['x_public'] ?? 0),
        'instagram_username' => $row['instagram_username'] ?? '',
        'instagram_public' => (int)($row['instagram_public'] ?? 0),
    ], JSON_UNESCAPED_UNICODE);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage(),
    ], JSON_UNESCAPED_UNICODE);
}
?>
