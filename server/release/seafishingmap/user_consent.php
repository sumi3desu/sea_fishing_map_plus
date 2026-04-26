<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

header('Content-Type: application/json');

$uuid = isset($_POST['uuid']) ? trim($_POST['uuid']) : '';
$version = isset($_POST['version_agreed']) ? trim($_POST['version_agreed']) : '';
$agreedAt = isset($_POST['agreed_at']) ? trim($_POST['agreed_at']) : '';

if ($uuid === '' || $version === '') {
  echo json_encode(['result' => 'NG', 'reason' => 'invalid_parameters']);
  exit;
}

try {
  $ini = parse_ini_file(_INI_FILE_PATH_, true);
  $pdo = new PDO($ini['database']['dsn'], $ini['database']['user'], $ini['database']['password']);
  $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

  // consent_agreed_at は ISO8601 で来る想定。DBは DATETIME として保存。
  // パースに失敗したら現在UTCにする。
  $dt = $agreedAt;
  if ($dt === '') {
    $dt = gmdate('Y-m-d H:i:s');
  } else {
    // ざっくり UTC 文字列を DATETIME に整形
    $ts = strtotime($agreedAt);
    if ($ts === false) $ts = time();
    $dt = gmdate('Y-m-d H:i:s', $ts);
  }

  // 前提: user テーブルに consent_version_agreed / consent_agreed_at カラムが存在
  // なければ ALTER で追加してください（下記参照）。
  $sql = "UPDATE `user` SET consent_version_agreed = ?, consent_agreed_at = ? WHERE uuid = ?";
  $st = $pdo->prepare($sql);
  $st->execute([$version, $dt, $uuid]);

  echo json_encode(['result' => 'OK']);
} catch (PDOException $e) {
  echo json_encode(['result' => 'NG', 'reason' => 'db_error']);
}

/*
-- 推奨カラム追加（MySQL例） --
ALTER TABLE `user`
  ADD COLUMN `consent_version_agreed` VARCHAR(32) NOT NULL DEFAULT '' AFTER `refresh_token`,
  ADD COLUMN `consent_agreed_at` DATETIME NULL AFTER `consent_version_agreed`;

-- 任意で履歴テーブル
CREATE TABLE IF NOT EXISTS `user_consent_log` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `uuid` VARCHAR(64) NOT NULL,
  `version` VARCHAR(32) NOT NULL,
  `agreed_at` DATETIME NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_uuid` (`uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
*/

?>

