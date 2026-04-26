<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

// 設定ファイル読み込み
$ini_info         = parse_ini_file(_INI_FILE_PATH_, true);
$session_pre_key  = create_session_key($ini_info['web']['url']);

$uuid  = isset($_POST['uuid']) ? trim((string)$_POST['uuid']) : '';
$email = isset($_POST['email']) ? trim((string)$_POST['email']) : '';

header('Content-Type: application/json');
debug_log(sprintf(
    "get_user_info.php uuid[%s] email[%s]",
    $uuid, $email
));

try {
    // PDOインスタンスの生成
    $pdo = new PDO(
        $ini_info['database']['dsn'],
        $ini_info['database']['user'],
        $ini_info['database']['password']
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    // 既存ユーザを検索（どちらの場合もブロック関連カラムを取得）
    $sql = '';
    if ($email === '') {
        $sql = 'SELECT user_id, uuid, email, created_at, nick_name, reports_blocked, reports_blocked_until, reports_blocked_reason, posts_blocked, posts_blocked_until, posts_blocked_reason, role, notif_on_off, delete_flg
                  FROM user
                 WHERE delete_flg = 0
                   AND uuid = ?';
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$uuid]);
        debug_log('sql['.$sql.'] uuid['.$uuid.']');
    } else {
        $sql = 'SELECT user_id, uuid, email, created_at, nick_name, reports_blocked, reports_blocked_until, reports_blocked_reason, posts_blocked, posts_blocked_until, posts_blocked_reason, role, notif_on_off, delete_flg
                  FROM user
                 WHERE delete_flg = 0
                   AND email = ?';
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$email]);
        debug_log('sql['.$sql.'] email['.$email.']');
    }

    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (count($rows) > 0) {
        // 既存ユーザあり → その情報を返す
        $user = $rows[0];
        // can_report を算出
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
        $response = [
            'userId'     => (int)$user['user_id'],
            'email'      => $user['email'],
            'uuid'       => $user['uuid'],
            'status'     => 'success',
            'createdAt'  => $user['created_at'],
            'nick_name'  => $user['nick_name'] ?? null,
            'reports_blocked' => (int)($user['reports_blocked'] ?? 0),
            'reports_blocked_until' => $user['reports_blocked_until'] ?? null,
            'reports_blocked_reason' => $user['reports_blocked_reason'] ?? null,
            'posts_blocked' => (int)($user['posts_blocked'] ?? 0),
            'posts_blocked_until' => $user['posts_blocked_until'] ?? null,
            'posts_blocked_reason' => $user['posts_blocked_reason'] ?? null,
            'can_report' => $canReport,
            'role' => $user['role'],
            'notif_on_off' => isset($user['notif_on_off']) ? (int)$user['notif_on_off'] : 1,
            'message'    => '既存ユーザを取得しました',
        ];
        echo json_encode($response);
        exit;
    }

    // 登録されていないため新規ユーザ登録
    $insertSql = '
        INSERT INTO user (uuid, email, delete_flg, created_at)
             VALUES (?,      ?,     0,         NOW())
    ';
    $insertStmt = $pdo->prepare($insertSql);
    $insertStmt->execute([$uuid, '']);
    $newUserId = $pdo->lastInsertId();
 
    $sql = 'SELECT user_id, uuid, email, created_at, nick_name, reports_blocked, reports_blocked_until, reports_blocked_reason, posts_blocked, posts_blocked_until, posts_blocked_reason, role, notif_on_off, delete_flg
              FROM user
             WHERE delete_flg = 0
               AND user_id = ?';
    $stmt = $pdo->prepare($sql);
    $stmt->execute([$newUserId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (count($rows) > 0) {
        // 既存ユーザあり → その情報を返す
        $user = $rows[0];
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
        $response = [
            'userId'     => (int)$user['user_id'],
            'email'      => $user['email'],
            'uuid'       => $user['uuid'],
            'status'     => 'success',
            'createdAt'  => $user['created_at'],
            'nick_name'  => $user['nick_name'] ?? null,
            'reports_blocked' => (int)($user['reports_blocked'] ?? 0),
            'reports_blocked_until' => $user['reports_blocked_until'] ?? null,
            'reports_blocked_reason' => $user['reports_blocked_reason'] ?? null,
            'posts_blocked' => (int)($user['posts_blocked'] ?? 0),
            'posts_blocked_until' => $user['posts_blocked_until'] ?? null,
            'posts_blocked_reason' => $user['posts_blocked_reason'] ?? null,
            'can_report' => $canReport,
            'role' => $user['role'],
            'notif_on_off' => isset($user['notif_on_off']) ? (int)$user['notif_on_off'] : 1,
            'message'    => '新規ユーザを作成しました',
        ];
    }
    echo json_encode($response);

} catch (PDOException $e) {
    // エラー時は HTTPステータスコード 500 を返す
    http_response_code(500);
    $response = [
        'status'  => 'error',
        'message' => '接続失敗: ' . $e->getMessage()
    ];
    echo json_encode($response);
}
