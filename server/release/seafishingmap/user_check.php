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

// POSTデータを受け取る
//   mail: メールアドレス
//   password: パスワード
// メールとパスワードのバリデーションチェックはサーバーで行うことでスマホアプリ再リリース防ぐ
$mail = isset($_POST['mail']) ? trim($_POST['mail']) : null;
$uuid = isset($_POST['uuid']) ? trim($_POST['uuid']) : null;

// バリデーション（最低限）
if (!$mail) {
    echo json_encode([
      "mail" => $mail,
      "hashcode" => "",
      "result" => "error",
      "reason" => "メールアドレスが未入力です。"
    ]);
    exit;
}
// バリデーション（最低限）
if (!$uuid) {
    echo json_encode([
      "mail" => $mail,
      "hashcode" => "",
      "result" => "error",
      "reason" => "UUIDが未入力です。"
    ]);
    exit;
}

// メールアドレスのフォーマットチェック
if (!filter_var($mail, FILTER_VALIDATE_EMAIL)) {
    echo json_encode([
      "mail" => $mail,
      "hashcode" => "",
      "result" => "error",
      "reason" => "無効なメールアドレス形式です。"
    ]);
    exit;
}

try {
    // PDOインスタンスの生成
    $pdo = new PDO($ini_info['database']['dsn'], $ini_info['database']['user'], $ini_info['database']['password']);

    // エラーモードを例外モードに設定
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    // メールアドレスがすでに登録されているか確認
    $sql = "SELECT * FROM user WHERE email = ?";
    $stmt = $pdo->prepare($sql);
    $stmt->execute([$mail]);
    
    // 1行ずつ取得して処理
    $exist = false;
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        // メール登録済み
        $exist = true;
        if ($uuid == $row['uuid']){
          echo json_encode([
              "mail" => $mail,
              "hashcode" => "",
              "result" => "registed",
              "reason" => "このメールアドレスはすでに登録状態です。"
          ]);
        } else {
          echo json_encode([
              "mail" => $mail,
              "hashcode" => "",
              "result" => "not_match_uuid",
              "reason" => "機種変の可能性があります。"
          ]);

        }
        break;
    }

    if ($exist == false) {
        // 成功時のレスポンス
        echo json_encode([
          "mail" => $mail,
          "result" => "unregisted",
          "reason" => "このメールアドレスは登録されていません。"
        ]);
    }
    
} catch (PDOException $e) {
    //echo "データベース接続に失敗しました: " . $e->getMessage();
    // エラー時は HTTPステータスコード 500 を返す
    http_response_code(500);
    echo json_encode([
      "mail" => $mail,
      "hashcode" => "",
      "result" => "error",
      "reason" => "データベース接続に失敗しました。[".$e->getMessage()."]"
    ]);

}

?>
