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
$user_password = isset($_POST['password']) ? trim($_POST['password']) : null;

// 現状プロバイダはPHP7.3.33だがPASSWORD_ARGON2IDは使えないためSHA-256使用
$hash = "";
if ($user_password != "" || $user_password != null){
    $hash = hash('sha256', $user_password);
}

log_put("php version[".phpversion()."] mai[".$mail."] hash[".$hash."]");

$action = isset($_POST['action']) ? trim($_POST['action']) : null;

try {
    // PDOインスタンスの生成
    $pdo = new PDO($ini_info['database']['dsn'], $ini_info['database']['user'], $ini_info['database']['password']);

    // エラーモードを例外モードに設定
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    if ($action == "new_user")
    {
        // メールアドレスがすでに登録されているか確認
        $stmt = $pdo->prepare("INSERT INTO user (mail, hash) values (?, ?);");
        $stmt->execute([$mail, $hash]);

    } else if ($action == "edit_password")
    {
        // 指定メールアドレスのパスワード更新
        $stmt = $pdo->prepare("UPDATE user SET hash = ? where mail = ?;");
        $stmt->execute([$hash, $mail]);
    } else if ($action == "edit_mail"){
        // 指定メールアドレスのメールアドレスを更新
        $stmt = $pdo->prepare("UPDATE user SET mail = ? where mail = ?;");
        $stmt->execute([$new_mail, $mail]);      
    }
    // 成功時のレスポンス
    echo json_encode([
        "mail" => $mail,
        "result" => "OK",
        "reason" => ""
    ]);
} catch (PDOException $e) {
    echo json_encode([
        "mail" => $mail,
        "result" => "NG",
        "reason" => "データベース接続に失敗しました[".$e->getMessage()."]"
    ]);

}

?>
