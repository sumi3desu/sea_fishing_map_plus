<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

$ini_info = parse_ini_file(_INI_FILE_PATH_, true);
$session_pre_key = create_session_key($ini_info['web']['url']);

$refresh_token = isset($_POST['refresh_token']) ? trim((string)$_POST['refresh_token']) : '';

header('Content-Type: application/json');
debug_log(sprintf(
    "restore_user.php refresh_token[%s]",
    ($refresh_token !== '') ? 'set' : 'empty'
));

if ($refresh_token === '') {
    echo json_encode([
        'status' => 'error',
        'reason' => 'refresh_token_required',
        'message' => 'refresh_token is required',
    ]);
    exit;
}

try {
    $pdo = new PDO(
        $ini_info['database']['dsn'],
        $ini_info['database']['user'],
        $ini_info['database']['password']
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    $sql = 'SELECT user_id, uuid, email, created_at, nick_name, reports_blocked, reports_blocked_until, reports_blocked_reason, posts_blocked, posts_blocked_until, posts_blocked_reason, role
              FROM user
             WHERE delete_flg = 0
               AND refresh_token = ?
               AND email <> \'\'
             ORDER BY user_id ASC
             LIMIT 1';
    $stmt = $pdo->prepare($sql);
    $stmt->execute([$refresh_token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        echo json_encode([
            'status' => 'not_found',
            'reason' => 'invalid_refresh_token',
            'message' => 'user not found',
        ]);
        exit;
    }

    $nowJst = new DateTime('now', new DateTimeZone('Asia/Tokyo'));
    $isBlocked = !empty($user['reports_blocked']) && ((int)$user['reports_blocked'] === 1);
    $isTempBlocked = false;
    if (!empty($user['reports_blocked_until'])) {
        try {
            $until = new DateTime($user['reports_blocked_until'], new DateTimeZone('Asia/Tokyo'));
            $isTempBlocked = ($until > $nowJst);
        } catch (Exception $e) {
            $isTempBlocked = false;
        }
    }
    $canReport = !($isBlocked || $isTempBlocked);

    echo json_encode([
        'status' => 'success',
        'userId' => (int)$user['user_id'],
        'email' => (string)$user['email'],
        'uuid' => (string)$user['uuid'],
        'createdAt' => (string)$user['created_at'],
        'nick_name' => $user['nick_name'] ?? null,
        'reports_blocked' => (int)($user['reports_blocked'] ?? 0),
        'reports_blocked_until' => $user['reports_blocked_until'] ?? null,
        'reports_blocked_reason' => $user['reports_blocked_reason'] ?? null,
        'posts_blocked' => (int)($user['posts_blocked'] ?? 0),
        'posts_blocked_until' => $user['posts_blocked_until'] ?? null,
        'posts_blocked_reason' => $user['posts_blocked_reason'] ?? null,
        'can_report' => $canReport,
        'role' => $user['role'] ?? null,
        'refresh_token' => $refresh_token,
        'message' => 'refresh_token から既存ユーザを復元しました',
    ]);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'reason' => 'db_error',
        'message' => '接続失敗: ' . $e->getMessage(),
    ]);
}

?>
