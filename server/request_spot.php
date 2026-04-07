<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

header('Content-Type: application/json');

$ini_info = parse_ini_file(_INI_FILE_PATH_, true);

// 入力パラメータ取得
$user_id = isset($_POST['user_id']) ? intval($_POST['user_id']) : 0;
$kubun   = isset($_POST['kubun']) ? trim($_POST['kubun']) : '';
$name    = isset($_POST['name']) ? trim($_POST['name']) : '';
$yomi    = isset($_POST['yomi']) ? trim($_POST['yomi']) : '';
$lat     = isset($_POST['lat']) ? floatval($_POST['lat']) : null;
$lng     = isset($_POST['lng']) ? floatval($_POST['lng']) : null;
$address = isset($_POST['address']) ? trim($_POST['address']) : '';
$pref_id = isset($_POST['todoufuken_id']) ? intval($_POST['todoufuken_id']) : 0; // 都道府県コード（必須）
$private = isset($_POST['private']) ? intval($_POST['private']) : 0; // 0:公開,1:非公開
$private = ($private === 1) ? 1 : 0; // 正規化
$flag = isset($_POST['flag']) ? intval($_POST['flag']) : -1; // -1:仮, 1:承認, -2:非承認 等
$port_id_post = isset($_POST['port_id']) ? intval($_POST['port_id']) : 0;

// バリデーション
if ($pref_id <= 0 && $port_id_post <= 0) {
    http_response_code(400);
    echo json_encode(['result' => 'ng', 'reason' => '都道府県が不明です']);
    exit;
}
if ($name === '' || $yomi === '' || $kubun === '' || $lat === null || $lng === null) {
    http_response_code(400);
    echo json_encode(['result' => 'ng', 'reason' => '必須パラメータが不足しています']);
    exit;
}

try {
    $pdo = new PDO(
        $ini_info['database']['dsn'],
        $ini_info['database']['user'],
        $ini_info['database']['password']
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $stmt = null;

    // トランザクション開始
    $pdo->beginTransaction();

    if ($port_id_post > 0) {
        // UPDATE（承認/非承認/編集）
        $up = $pdo->prepare("UPDATE teibou SET 
            port_name=:port_name,
            furigana=:furigana,
            j_yomi=:j_yomi,
            kubun=:kubun,
            address=:address,
            latitude=:lat,
            longitude=:lng,
            note=:note,
            flag=:flag,
            private=:private,
            user_id=:user_id
          WHERE port_id=:port_id");
        $up->execute([
            ':port_name' => $name,
            ':furigana'  => $yomi,
            ':j_yomi'    => $yomi,
            ':kubun'     => $kubun,
            ':address'   => $address,
            ':lat'       => $lat,
            ':lng'       => $lng,
            ':note'      => '',
            ':flag'      => $flag,
            ':private'   => $private,
            ':user_id'   => $user_id,
            ':port_id'   => $port_id_post,
        ]);
        $pdo->commit();
        http_response_code(200);
        echo json_encode(['result' => 'success', 'port_id' => $port_id_post]);
    } else {
        // INSERT（flag は入力があれば優先。通常は -1）
        $min = $pref_id * 100000;
        $max = $min + 99999;
        $q = $pdo->prepare("SELECT port_id FROM teibou WHERE port_id BETWEEN :min AND :max ORDER BY port_id DESC LIMIT 1 FOR UPDATE");
        $q->execute([':min' => $min, ':max' => $max]);
        $row = $q->fetch(PDO::FETCH_ASSOC);
        if ($row && isset($row['port_id'])) {
            $new_port_id = intval($row['port_id']) + 1;
        } else {
            $new_port_id = $min + 1;
        }
        if ($new_port_id > $max) {
            $pdo->rollBack();
            http_response_code(400);
            echo json_encode(['result' => 'ng', 'reason' => '当該都道府県のID上限に達しました']);
            exit;
        }
        $sql = "INSERT INTO teibou (
            port_id, port_name, furigana, j_yomi, kubun, address, latitude, longitude, note, flag, private, user_id
          ) VALUES (
            :port_id, :port_name, :furigana, :j_yomi, :kubun, :address, :lat, :lng, :note, :flag, :private, :user_id
          )";
        $ins = $pdo->prepare($sql);
        $ins->execute([
            ':port_id'   => $new_port_id,
            ':port_name' => $name,
            ':furigana'  => $yomi,
            ':j_yomi'    => $yomi,
            ':kubun'     => $kubun,
            ':address'   => $address,
            ':lat'       => $lat,
            ':lng'       => $lng,
            ':note'      => '',
            ':flag'      => $flag,
            ':private'   => $private,
            ':user_id'   => $user_id,
        ]);
        $pdo->commit();
        http_response_code(200);
        echo json_encode(['result' => 'success', 'port_id' => $new_port_id]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        try { $pdo->rollBack(); } catch (Exception $ex) {}
    }
    http_response_code(500);
    echo json_encode(['result' => 'ng', 'reason' => 'DBエラー: ' . $e->getMessage()]);
}
