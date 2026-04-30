<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

// 設定ファイル読み込み
$ini_info = parse_ini_file(_INI_FILE_PATH_, true);
$session_pre_key = create_session_key($ini_info['web']['url']);
// JSONレスポンスで返すためのヘッダー設定
header('Content-Type: application/json');

// POSTデータ(mail, password, number を受け取る
$mail = isset($_POST['mail']) ? trim($_POST['mail']) : null;
$new_mail = isset($_POST['new_mail']) ? trim($_POST['new_mail']) : null;
//$user_password = isset($_POST['password']) ? trim($_POST['password']) : null;
$uuid = isset($_POST['uuid']) ? trim($_POST['uuid']) : null;
$nick_name = isset($_POST['nick_name']) ? trim($_POST['nick_name']) : null;

// 現状プロバイダはPHP7.3.33だがPASSWORD_ARGON2IDは使えないためSHA-256使用
/*$hash = "";
if ($user_password != "" || $user_password != null){
    $hash = hash('sha256', $user_password);
}

log_put("php version[".phpversion()."] mai[".$mail."] hash[".$hash."]");
*/

$action = isset($_POST['action']) ? trim($_POST['action']) : null;
log_put("user_regist.php start php version[".phpversion()."] mai[".$mail."] action[".$action."] uuid[".$uuid."]");

try {
    // PDOインスタンスの生成
    $pdo = new PDO($ini_info['database']['dsn'], $ini_info['database']['user'], $ini_info['database']['password']);

    // エラーモードを例外モードに設定
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    // 返却用（必要な場合のみ生成）
    $refresh_token = null;
    $response_user_id = 0;
    $response_uuid = $uuid;

    if ($action == "new_user")
    {
        // ADDED: 端末用のリフレッシュトークンを発行（hex64 = 256bit）
        $refresh_token = bin2hex(random_bytes(32));

        $pdo->beginTransaction();
        try {
            // 同一メールが既存登録済みの場合は、そのユーザを優先して採用する。
            $sel = $pdo->prepare("SELECT user_id, uuid, nick_name FROM `user` WHERE delete_flg = 0 AND email = ? ORDER BY user_id ASC LIMIT 1 FOR UPDATE;");
            $sel->execute([$mail]);
            $existing = $sel->fetch(PDO::FETCH_ASSOC);

            if ($existing) {
                $response_user_id = isset($existing['user_id']) ? (int)$existing['user_id'] : 0;
                $response_uuid = isset($existing['uuid']) ? trim((string)$existing['uuid']) : $uuid;
                $save_nick_name = ($nick_name !== null && $nick_name !== '') ? $nick_name : ($existing['nick_name'] ?? '');

                $stmt = $pdo->prepare("UPDATE `user` SET email = ?, nick_name = ?, refresh_token = ? WHERE user_id = ?;");
                $stmt->execute([$mail, $save_nick_name, $refresh_token, $response_user_id]);
            } else {
                // 該当メールが無ければ、現在の uuid 行へ登録する。
                $stmt = $pdo->prepare("UPDATE `user` SET email = ?, nick_name = ?, refresh_token = ? WHERE uuid = ?;");
                $stmt->execute([$mail, $nick_name, $refresh_token, $uuid]);

                $sel = $pdo->prepare("SELECT user_id, uuid FROM `user` WHERE delete_flg = 0 AND uuid = ? ORDER BY user_id ASC LIMIT 1;");
                $sel->execute([$uuid]);
                $current = $sel->fetch(PDO::FETCH_ASSOC);
                if ($current) {
                    $response_user_id = isset($current['user_id']) ? (int)$current['user_id'] : 0;
                    $response_uuid = isset($current['uuid']) ? trim((string)$current['uuid']) : $uuid;
                }
            }

            $pdo->commit();
        } catch (Exception $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $e;
        }
    }
    else if ($action == "delete_mail")
    {
        // ADDED: メールアドレスとリフレッシュトークンを無効化（空文字にリセット）
        $stmt = $pdo->prepare("UPDATE `user` SET email = '', refresh_token = '' WHERE uuid = ?;");
        $stmt->execute([$uuid]);
        $mail = '';
        $refresh_token = null;
    }
    else if ($action == "edit_mail")
    {
        // ADDED: メールアドレス変更（uuid をキーに new_mail を設定）。refresh_token は維持。
        if ($new_mail === null || $new_mail === '') {
            throw new PDOException('invalid_new_mail');
        }
        $stmt = $pdo->prepare("UPDATE `user` SET email = ? WHERE uuid = ?;");
        $stmt->execute([$new_mail, $uuid]);
        $mail = $new_mail;
    }
    /*else if ($action == "edit_password")
    {
        // 指定メールアドレスのパスワード更新
        $stmt = $pdo->prepare("UPDATE user SET hash = ? where mail = ?;");
        $stmt->execute([$hash, $mail]);
    } else if ($action == "edit_mail"){
        // 指定メールアドレスのメールアドレスを更新
        $stmt = $pdo->prepare("UPDATE user SET mail = ? where mail = ?;");
        $stmt->execute([$new_mail, $mail]);      
    }
        */
    log_put("user_regist.php end OK");
    // 成功時のレスポンス（リフレッシュトークンを含む）
    echo json_encode([
        "mail" => $mail,
        "result" => "OK",
        "reason" => "",
        // ADDED: リフレッシュトークン（new_user 時のみ発行）
        "refresh_token" => $refresh_token,
        "user_id" => $response_user_id,
        "uuid" => $response_uuid,
    ]);
} catch (PDOException $e) {
    log_put("user_regist.php end NG");
    echo json_encode([
        "mail" => $mail,
        "result" => "NG",
        "reason" => "データベース接続に失敗しました[".$e->getMessage()."]"
    ]);

}

?>
