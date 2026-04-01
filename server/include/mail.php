<?php
//パスは自分がPHPMailerをインストールした場所で
require 'PHPMailer/src/PHPMailer.php';
require 'PHPMailer/src/SMTP.php';
require 'PHPMailer/src/POP3.php';
require 'PHPMailer/src/Exception.php';
require 'PHPMailer/src/OAuth.php';
require 'PHPMailer/language/phpmailer.lang-ja.php';

//公式通り
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;


// $to：TOメールアドレス(,セパレータで複数定義可能)
// $cc：CCメールアドレス(,セパレータで複数定義可能)
// $bcc：BCCメールアドレス(,セパレータで複数定義可能)
// $subject：件名（日本語OK）
// $body_lines：本文(行配列)
// body_params : パラメータの名前と値の配列
function send_mail($ini_info, $user_name, $user_mail, $body_params)
{
    log_put("send_mail[".$user_mail."]");

  $reason = "";

  $subject = $ini_info['mail']['subject'];
  $body_lines  = $ini_info['mail']['mail_body'];
  try {
    //SMTP送信
    $smtp_server = $ini_info['mail']['smtp_server'];
    $port_no = $ini_info['mail']['port_no'];
    $smtp_auth_user = $ini_info['mail']['smtp_auth_user'];
    $smtp_auth_password = $ini_info['mail']['smtp_auth_password'];
    $from_mail_addr = $ini_info['mail']['from_mail_addr'];
    $from_mail_addr_name = $ini_info['mail']['from_mail_addr_name'];
      
    $body = "";
    for($i = 0; $i < count($body_lines); $i++){
      $row_use = false;
      $isIncludeKey = false;
      foreach ($body_params as $key => $value){
        // 行にキーが含まれていてかつ値がない場合はこの行は無効にする
        if (strstr($body_lines[$i], $key)){
          // キーあり !
          $isIncludeKey = true;
          if ($value === ''){
            //						$row_use = false;
            //						break;
          } else {
            $row_use = true;
            break;
          }
        }
      }
      if ($row_use == true || $isIncludeKey == false){
        $body = $body.$body_lines[$i]."\r\n";
      }
    }
    foreach ($body_params as $key => $value){
      log_put("mail key[".$key."] value[".$value."]");
      $body = str_replace($key, $value, $body);
    }
    // 追加メタ: post_id が与えられている場合は本文末尾に追記（report_issue 等で利用）
    if (isset($body_params['post_id']) && trim((string)$body_params['post_id']) !== '') {
      $body .= "\r\npost_id=" . trim((string)$body_params['post_id']) . "\r\n";
    }
    log_put("body[".$body."]");

    log_put("MAIL send start...");

    //SMTPの設定
    $mailer = new PHPMailer();//インスタンス生成
    $mailer->isSMTP();//SMTPを作成
    $mailer->Host = $smtp_server;//SMTPサーバ
    $mailer->CharSet = 'UTF-8';//UTF-8で送信
    $mailer->SMTPAuth = true;//SMTP認証を有効
    $mailer->Username = $smtp_auth_user; // ユーザー名
    $mailer->Password = $smtp_auth_password; // パスワード
    $mailer->SMTPSecure = 'ssl';// 465=ssl / 587=tls（iniのport_noに合わせてください）
    $mailer->Port = $port_no;

    // デバッグ出力をログへ（必要時のみ有効化したい場合はコメントアウト解除）
    // $mailer->SMTPDebug = 2; // 2=詳細
    // $mailer->Debugoutput = function($str, $level) { log_put('[SMTP]['.$level.'] '.$str); };

    //メール本体
    $message = $body;  // メール本文（テキスト）
    // 差出人
    $mailer->setFrom($from_mail_addr, $from_mail_addr_name);
    // 件名/本文（UTF-8のままセット）
    $mailer->Subject = $subject;
    $mailer->isHTML(false); // プレーンテキスト
    $mailer->Body = $message;
    $mailer->addAddress($user_mail);

    // 送信（戻り値をチェック）
    if (!$mailer->send()) {
      $reason = $mailer->ErrorInfo;
      log_put("MAIL send ERROR[".$reason."]");
    } else {
      log_put("MAIL send OK !");
    }

  } catch (phpmailerException $e) {
    $reason = $e->errorMessage(); //Pretty error messages from PHPMailer
    log_put("MAIL send ERROR[".$reason."]");
  } catch (Exception $e) {
    $reason = $e->getMessage(); //Boring error messages from anything else!
    log_put("MAIL send ERROR[".$reason."]");
  }

  return $reason;
}


?>
