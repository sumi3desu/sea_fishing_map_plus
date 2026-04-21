<?php
session_cache_limiter("nocache");

//セッション開始
session_start();

include_once("include/define.php");
include_once("include/db.php");
include_once("include/mail.php");

// 設定ファイル読み込み
$ini_info = parse_ini_file(_INI_FILE_PATH_, true);
$session_pre_key = create_session_key($ini_info['web']['url']);

log_put('****** send_number.php start');

//mail
//authenticationNumber

// POSTデータ(mail, authenticationNumber を受け取る
$mail = isset($_POST['mail']) ? trim($_POST['mail']) : null;
$authenticationNumber = isset($_POST['authenticationNumber']) ? trim($_POST['authenticationNumber']) : null;
log_put('mail['.$mail.']');
log_put('authenticationNumber['.$authenticationNumber.']');


try {
    $body_params['$authenticationNumber$'] = $authenticationNumber;
    
    $user_name = "新規ユーザ";
    $reason = send_mail($ini_info, $user_name, $mail, $body_params);

    log_put('reason['.$reason.']');
    if ($reason == "")
    {
        // 成功時のレスポンス
        echo json_encode([
            "mail" => $mail,
            "result" => "OK",
            "reason" => ""
        ]);

    } else {
        echo json_encode([
            "mail" => $mail,
            "result" => "NG",
            "reason" => "メール送信[".$mail."]に失敗しました[".$reason."]"
        ]);

    }

} catch(Exception $e){
    echo json_encode([
     "mail" => $mail,
     "result" => "NG",
     "reason" => "メール送信[".$mail."]に失敗しました[".$e->getMessage()."]"
    ]);
}

?>
