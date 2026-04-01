<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

// 設定ファイル読み込み
$ini_info = parse_ini_file(_INI_FILE_PATH_, true);
$session_pre_key = create_session_key($ini_info['web']['url']);

// JSONレスポンスで返すためのヘッダー設定
header('Content-Type: application/json; charset=UTF-8');

debug_log("get_teibou.php");

// ==============================
// 半角カナ → 全角ひらがな 変換関数
// ==============================
function kanaToHiragana($str) {
    if ($str === null || $str === '') {
        return $str;
    }

    // 半角カナ → 全角カナ
    // K: カタカナ化, V: 濁点・半濁点を結合
    $str = mb_convert_kana($str, 'KV', 'UTF-8');

    // カタカナ → ひらがな
    // H: ひらがな化, c: 全角化
    $str = mb_convert_kana($str, 'Hc', 'UTF-8');

    return $str;
}

try {
    // PDOインスタンスの生成
    $pdo = new PDO(
        $ini_info['database']['dsn'],
        $ini_info['database']['user'],
        $ini_info['database']['password'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC
            //PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4"
        ]
    );

    // ==============================
    // j_yomi が空のレコードを自動補完
    // ==============================
    $selectForUpdate = $pdo->prepare("
        SELECT port_id, furigana
        FROM teibou
        WHERE j_yomi IS NULL OR j_yomi = ''
    ");
    $selectForUpdate->execute();

    $updateStmt = $pdo->prepare("
        UPDATE teibou
        SET j_yomi = :j_yomi
        WHERE port_id = :port_id
    ");

    while ($row = $selectForUpdate->fetch()) {
        $hiragana = kanaToHiragana($row['furigana']);

        $updateStmt->execute([
            ':j_yomi'  => $hiragana,
            ':port_id'=> $row['port_id']
        ]);
    }

    // ==============================
    // データ取得
    // ==============================
    $sql = "
        SELECT * FROM teibou AS t INNER JOIN todoufuken AS p ON LEFT(CAST(t.port_id AS CHAR), 2) = p.todoufuken_id ORDER BY p.todoufuken_id, t.j_yomi;
    ";

    $stmt = $pdo->prepare($sql);
    $stmt->execute();

    $rows = $stmt->fetchAll();

    // 成功時のレスポンス
    $response = [
        'status' => 'success',
        'count'  => count($rows),
        'data'   => $rows
    ];

    echo json_encode($response, JSON_UNESCAPED_UNICODE);

} catch (PDOException $e) {
    // エラー時は HTTPステータスコード 500 を返す
    http_response_code(500);

    $response = [
        'status'  => 'error',
        'message' => '接続失敗: ' . $e->getMessage()
    ];

    echo json_encode($response, JSON_UNESCAPED_UNICODE);
}
?>
