<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

$ini_info = parse_ini_file(_INI_FILE_PATH_, true);
$session_pre_key = create_session_key($ini_info['web']['url']);

$user_id = isset($_POST['user_id']) ? (int)$_POST['user_id'] : 0;
$fcm_token = isset($_POST['fcm_token']) ? trim((string)$_POST['fcm_token']) : '';

header('Content-Type: application/json');
debug_log(sprintf(
    "update_fcm_token.php user_id[%d] token[%s]",
    $user_id,
    ($fcm_token !== '') ? 'set' : 'empty'
));

if ($fcm_token === '') {
    echo json_encode([
        'status' => 'error',
        'reason' => 'fcm_token_required',
        'message' => 'fcm_token is required',
    ]);
    exit;
}

if ($user_id <= 0) {
    echo json_encode([
        'status' => 'error',
        'reason' => 'user_id_required',
        'message' => 'user_id is required',
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

    $sql = 'UPDATE user
               SET fcm_token = :fcm_token,
                   fcm_token_updated_at = NOW()
             WHERE delete_flg = 0
               AND user_id = :user_id';
    $stmt = $pdo->prepare($sql);
    $stmt->execute([
        ':fcm_token' => $fcm_token,
        ':user_id' => $user_id,
    ]);

    echo json_encode([
        'status' => 'success',
        'message' => 'FCM token updated',
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
