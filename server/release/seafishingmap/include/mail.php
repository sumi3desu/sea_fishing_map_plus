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


function build_mail_body($body_lines, $body_params)
{
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
          // no-op
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
  return $body;
}

function send_custom_mail($mail_config, $user_name, $user_mail, $subject, $body_lines, $body_params)
{
  log_put("send_custom_mail[".$user_mail."]");

  $reason = "";
  try {
    //SMTP送信
    $smtp_server = $mail_config['smtp_server'];
    $port_no = $mail_config['port_no'];
    $smtp_auth_user = $mail_config['smtp_auth_user'];
    $smtp_auth_password = $mail_config['smtp_auth_password'];
    $from_mail_addr = $mail_config['from_mail_addr'];
    $from_mail_addr_name = $mail_config['from_mail_addr_name'];

    $body = build_mail_body($body_lines, $body_params);

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

    // 2026/4/11 [
    $mailer->Sender = $from_mail_addr;
    $mailer->addReplyTo($from_mail_addr, $from_mail_addr_name);
    // ]

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

function send_simple_text_mail(
  $mail_config,
  $user_mail,
  $subject,
  $body,
  $reply_to = '',
  $from_override = '',
  $from_name_override = ''
)
{
  log_put("send_simple_text_mail[".$user_mail."]");
  $reason = "";
  try {
    $smtp_server = $mail_config['smtp_server'];
    $port_no = $mail_config['port_no'];
    $smtp_auth_user = $mail_config['smtp_auth_user'];
    $smtp_auth_password = $mail_config['smtp_auth_password'];
    $from_mail_addr = ($from_override !== '') ? $from_override : $mail_config['from_mail_addr'];
    $from_mail_addr_name = ($from_name_override !== '') ? $from_name_override : $mail_config['from_mail_addr_name'];

    $mailer = new PHPMailer();
    $mailer->isSMTP();
    $mailer->Host = $smtp_server;
    $mailer->CharSet = 'UTF-8';
    $mailer->SMTPAuth = true;
    $mailer->Username = $smtp_auth_user;
    $mailer->Password = $smtp_auth_password;
    $mailer->SMTPSecure = 'ssl';
    $mailer->Port = $port_no;

    $mailer->setFrom($from_mail_addr, $from_mail_addr_name);
    $mailer->Sender = $from_mail_addr;
    if ($reply_to !== '') {
      $mailer->addReplyTo($reply_to, $reply_to);
    }
    $mailer->Subject = $subject;
    $mailer->isHTML(false);
    $mailer->Body = $body;
    $mailer->addAddress($user_mail);

    if (!$mailer->send()) {
      $reason = $mailer->ErrorInfo;
      log_put("MAIL simple send ERROR[".$reason."]");
    } else {
      log_put("MAIL simple send OK !");
    }
  } catch (phpmailerException $e) {
    $reason = $e->errorMessage();
    log_put("MAIL simple send ERROR[".$reason."]");
  } catch (Exception $e) {
    $reason = $e->getMessage();
    log_put("MAIL simple send ERROR[".$reason."]");
  }

  if ($reason !== '') {
    return $reason;
  }
  return $reason;
}

// $subject：件名（日本語OK）
// $body_lines：本文(行配列)
// body_params : パラメータの名前と値の配列
function send_mail($ini_info, $user_name, $user_mail, $body_params)
{
  $subject = $ini_info['mail']['subject'];
  $body_lines  = $ini_info['mail']['mail_body'];
  return send_custom_mail(
    $ini_info['mail'],
    $user_name,
    $user_mail,
    $subject,
    $body_lines,
    $body_params
  );
}


?>
