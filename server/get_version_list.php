<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

// 設定ファイル読み込み
$ini_info = parse_ini_file(_INI_FILE_PATH_, true);
$session_pre_key = create_session_key($ini_info['web']['url']);

$userId = $_POST['userId'];

// JSONレスポンスで返すためのヘッダー設定
header('Content-Type: application/json');

debug_log("get_version_list.php userId[".$userId."]");

try {
    // PDOインスタンスの生成
    $pdo = new PDO($ini_info['database']['dsn'], $ini_info['database']['user'], $ini_info['database']['password']);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    // 全単語帳取得
    //$sql = "SELECT * FROM version where user_id = ?;";
    $sql = "SELECT * FROM version;";

    $stmt = $pdo->prepare($sql);
    $stmt->execute([$userId]);
    
    // 結果を連想配列で取得
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    // 成功時のレスポンス
    $response = array(
        'status' => 'success',
        'data'   => $rows
    );
    echo json_encode($response);
    
} catch (PDOException $e) {
    // エラー時は HTTPステータスコード 500 を返す
    http_response_code(500);
    $response = array(
        'status'  => 'error',
        'message' => '接続失敗: ' . $e->getMessage()
    );
    echo json_encode($response);
}
?>
