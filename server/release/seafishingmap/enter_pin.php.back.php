<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

// 設定ファイル読み込み
$ini_info = parse_ini_file(_INI_FILE_PATH_, true);
$session_pre_key = create_session_key($ini_info['web']['url']);

// key
$userId = $_POST['userId'];
$nendoId    = $_POST['nendoId'];
$questionNo = $_POST['questionNo'];
$questionType = $_POST['questionType'];
$kind = $_POST['kind'];
$pin = $_POST['pin'];
// JSONレスポンスで返すためのヘッダー設定
header('Content-Type: application/json');

debug_log("enter_pin.php start" );

try {
    $pdo = new PDO(
        $ini_info['database']['dsn'],
        $ini_info['database']['user'],
        $ini_info['database']['password']
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    if ($pin == '1'){
        $upsert = $pdo->prepare(
        "INSERT INTO pinning 
         (user_id, nendo_id, question_no, question_type, kind, regist_datetime)
         VALUES (:userid, :nendo, :qno, :qtype, :kd, NOW())
         ON DUPLICATE KEY UPDATE
           user_id  = VALUES(user_id),
           nendo_id  = VALUES(nendo_id),
           question_no  = VALUES(question_no),
           question_type  = VALUES(question_type),
           kind = VALUES(kind),
           regist_datetime = NOW()"
        );

        $pdo->beginTransaction();

        $upsert->execute([
            ':userid' => $userId,
            ':nendo' => $nendoId,
            ':qno'   => $questionNo,
            ':qtype' => $questionType,
            ':kd' => $kind
        ]);

    } else {
        $params = [$userId];
        $params[] = $nendoId;
        $params[] = $questionNo;
        $params[] = $questionType;

        $sql = "DELETE FROM pinning WHERE user_id=? and nendo_id=? and question_no=? and question_type=?";
        $smtp = $pdo->prepare($sql);
        $pdo->beginTransaction();

        $smtp->execute($params);
    }

    $pdo->commit();

    // 成功時のレスポンス
    $response = array(
        'status' => 'success',
        'reason'   => ''
    );

    debug_log("enter_pin.php OK end");

    http_response_code(200);
    echo json_encode($response);
} catch (PDOException $e) {
    // エラー時は HTTPステータスコード 500 を返す
    http_response_code(500);
    $response = array(
        'status'  => 'error',
        'reason' => '接続失敗: ' . $e->getMessage()
    );
    debug_log("enter_pin.php NG end");
    if ($pdo->inTransaction()) $pdo->rollBack();

    http_response_code(500);

    echo json_encode($response);
}
