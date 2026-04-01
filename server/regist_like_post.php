<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

header('Content-Type: application/json');

$ini_info = parse_ini_file(_INI_FILE_PATH_, true);

// 投稿ID
$post_id = $_POST['post_id'] ?? null;

// ユーザID
$user_id = $_POST['user_id'] ?? null;

$action = $_POST['action'] ?? '';
// バリデーション
$post_id = is_numeric($post_id) ? intval($post_id) : 0;
$user_id = is_numeric($user_id) ? intval($user_id) : 0;
if ($action === 'get') {
    if ($post_id <= 0) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'reason' => 'invalid parameters', 'count' => 0]);
        exit;
    }
} else if ($action === 'regist') {
    if ($post_id <= 0 || $user_id <= 0) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'reason' => 'invalid parameters', 'count' => 0]);
        exit;
    }
} else {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'reason' => 'invalid action', 'count' => 0]);
    exit;
}

try {
    $pdo = new PDO(
        $ini_info['database']['dsn'],
        $ini_info['database']['user'],
        $ini_info['database']['password']
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $resAction = $action;
    if ($action === 'regist') {
        // いいねのトグル実装
        // テーブル: post_likes(post_id INT, user_id INT, created_at DATETIME)
        $pdo->beginTransaction();
        $stmt = $pdo->prepare('SELECT 1 FROM post_likes WHERE post_id = ? AND user_id = ? LIMIT 1');
        $stmt->execute([$post_id, $user_id]);
        $exists = ($stmt->fetchColumn() !== false);
        if ($exists) {
            $del = $pdo->prepare('DELETE FROM post_likes WHERE post_id = ? AND user_id = ?');
            $del->execute([$post_id, $user_id]);
            $resAction = 'remove';
        } else {
            $ins = $pdo->prepare('INSERT INTO post_likes (post_id, user_id, created_at) VALUES (?, ?, NOW())');
            $ins->execute([$post_id, $user_id]);
            $resAction = 'insert';
        }
        $cntStmt = $pdo->prepare('SELECT COUNT(*) FROM post_likes WHERE post_id = ?');
        $cntStmt->execute([$post_id]);
        $count = intval($cntStmt->fetchColumn());
        $pdo->commit();
    } else {
        // get: 件数のみ返却
        $stmt = $pdo->prepare('SELECT COUNT(*) FROM post_likes WHERE post_id = ?');
        $stmt->execute([$post_id]);
        $count = intval($stmt->fetchColumn());
        $resAction = 'get';
    }

    http_response_code(200);
    echo json_encode(['status' => 'success', 'reason' => '', 'count' => $count, 'action' => $resAction]);
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        try { $pdo->rollBack(); } catch (Exception $ignored) {}
    }
    http_response_code(500);
    echo json_encode(['status' => 'error', 'reason' => 'DBエラー', 'count' => 0]);
}
