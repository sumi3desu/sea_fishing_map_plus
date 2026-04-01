<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

header('Content-Type: application/json; charset=UTF-8');

try {
    $ini_info = parse_ini_file(_INI_FILE_PATH_, true);

    $pdo = new PDO(
        $ini_info['database']['dsn'],
        $ini_info['database']['user'],
        $ini_info['database']['password'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC
        ]
    );

    // 受領パラメータ
    $action   = isset($_POST['action']) ? strtolower(trim((string)$_POST['action'])) : 'insert';
    $userId   = isset($_POST['user_id']) ? (int)$_POST['user_id'] : 0;
    $spotId   = isset($_POST['spot_id']) ? (int)$_POST['spot_id'] : 0;
    $postKind = isset($_POST['post_kind']) ? trim((string)$_POST['post_kind']) : '';
    $exist    = isset($_POST['exist']) ? (int)$_POST['exist'] : 0; // 釣果・その他は0
    $title    = isset($_POST['title']) ? (string)$_POST['title'] : '';
    $detail   = isset($_POST['detail']) ? (string)$_POST['detail'] : '';
    $createAt = isset($_POST['create_at']) ? (string)$_POST['create_at'] : '';
    $postId   = isset($_POST['post_id']) ? (int)$_POST['post_id'] : 0; // update 用

    if ($userId <= 0) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'invalid user_id'], JSON_UNESCAPED_UNICODE);
        exit;
    }
    if ($action !== 'update' && $spotId <= 0) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'invalid spot_id'], JSON_UNESCAPED_UNICODE);
        exit;
    }
    if (mb_strlen($detail) > 1024) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'detail too long'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    // post_kind マッピング（文字列→数値）。定義は必要に応じて調整。
    $kindMap = [
        'catch' => 1,
        'regulation' => 2,
        'parking' => 3,
        'toilet' => 4,
        'bait' => 5,
        'convenience' => 6,
        'other' => 9,
    ];
    if (ctype_digit($postKind)) {
        $kindVal = (int)$postKind;
    } else {
        $kindVal = isset($kindMap[$postKind]) ? $kindMap[$postKind] : 0; // 0=不明
    }
    if ($kindVal === 0) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'invalid post_kind'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    // タイトルのバリデーション
    // 釣果(catch=1) と その他(other=9) は title 必須。
    // 規制/駐車場/トイレ/釣餌/コンビニ は title 任意（未入力可）。
    if ($kindVal === 1 || $kindVal === 9) {
        if ($title === '' || mb_strlen($title) > 32) {
            http_response_code(400);
            echo json_encode(['status' => 'error', 'message' => 'invalid title'], JSON_UNESCAPED_UNICODE);
            exit;
        }
    } else {
        if (mb_strlen($title) > 32) {
            http_response_code(400);
            echo json_encode(['status' => 'error', 'message' => 'title too long'], JSON_UNESCAPED_UNICODE);
            exit;
        }
    }

    $tsForPath = time();
    if ($action === 'update') {
        if ($postId <= 0) {
            http_response_code(400);
            echo json_encode(['status' => 'error', 'message' => 'post_id is required for update'], JSON_UNESCAPED_UNICODE);
            exit;
        }
        // 既存レコード取得
        $stmtSel = $pdo->prepare('SELECT * FROM post WHERE post_id = :post_id');
        $stmtSel->execute([':post_id' => $postId]);
        $row = $stmtSel->fetch();
        if (!$row) {
            http_response_code(404);
            echo json_encode(['status' => 'error', 'message' => 'post not found'], JSON_UNESCAPED_UNICODE);
            exit;
        }
        // spot_id は既存を維持（変更しない）
        $spotId = (int)$row['spot_id'];
        // create_at は既存を維持。画像保存先フォルダ（年/月）算出用に使用
        $tsForPath = strtotime($row['create_at']);
        if ($tsForPath === false) $tsForPath = time();

        // 本体更新（update_at のみ現在時刻に）
        $stmtUp = $pdo->prepare('UPDATE post SET post_kind = :post_kind, exist = :exist, title = :title, detail = :detail, update_at = NOW() WHERE post_id = :post_id');
        $stmtUp->execute([
            ':post_kind' => $kindVal,
            ':exist' => $exist,
            ':title' => $title,
            ':detail' => $detail,
            ':post_id' => $postId,
        ]);
    } else {
        // insert のみ create_at を使用
        $ts = strtotime($createAt);
        if ($ts === false) $ts = time();
        $createAtMysql = date('Y-m-d H:i:s', $ts);
        $tsForPath = $ts;
        // DB登録（post_id は AUTO_INCREMENT 前提）
        $stmt = $pdo->prepare(
            'INSERT INTO post (user_id, spot_id, post_kind, exist, title, detail, create_at)
             VALUES (:user_id, :spot_id, :post_kind, :exist, :title, :detail, :create_at)'
        );
        $stmt->execute([
            ':user_id' => $userId,
            ':spot_id' => $spotId,
            ':post_kind' => $kindVal,
            ':exist' => $exist,
            ':title' => $title,
            ':detail' => $detail,
            ':create_at' => $createAtMysql,
        ]);
        $postId = (int)$pdo->lastInsertId();
    }

    $imageRelative = null;
    $thumbRelative = null;
    $clearImage = (isset($_POST['clear_image']) && (string)$_POST['clear_image'] === '1');
    if (isset($_FILES['file']) && is_uploaded_file($_FILES['file']['tmp_name'])) {
        $file    = $_FILES['file'];
        $tmpPath = $file['tmp_name'];
        $orig    = $file['name'];
        $ext     = strtolower(pathinfo($orig, PATHINFO_EXTENSION));
        $allow   = ['png','jpg','jpeg','webp'];
        if (!in_array($ext, $allow, true)) { $ext = 'webp'; }

        // 保存先決定
        $basePostPath = '';
        if (isset($ini_info['post']['path'])) {
            $basePostPath = rtrim($ini_info['post']['path'], '/');
        } else if (isset($ini_info['profile']['path'])) {
            $basePostPath = rtrim(dirname(rtrim($ini_info['profile']['path'], '/')), '/') . '/post_images';
        }

        if ($basePostPath !== '') {
            $y = date('Y', $tsForPath);
            $m = date('m', $tsForPath);
            $uploadDir = $basePostPath . '/spot/' . $spotId . '/' . $y . '/' . $m . '/' . $postId;
            if (!is_dir($uploadDir)) {
                if (!mkdir($uploadDir, 0755, true)) {
                    // 保存失敗だがDBは成功。エラーにはしない。
                    $uploadDir = '';
                }
            }
            if ($uploadDir !== '') {
                $dest = $uploadDir . '/original.' . $ext;
                if (move_uploaded_file($tmpPath, $dest)) {
                    $imageRelative = 'spot/' . $spotId . '/' . $y . '/' . $m . '/' . $postId . '/original.' . $ext;
                    // サムネイル生成（256x256, 中央クロップ, WebP優先）
                    try {
                        $srcPath = $dest;
                        $thumbPathWebp = $uploadDir . '/thumb_256.webp';
                        // 元画像読み込み（拡張子で分岐）
                        $srcImg = null;
                        if ($ext === 'webp' && function_exists('imagecreatefromwebp')) {
                            $srcImg = @imagecreatefromwebp($srcPath);
                        } elseif (($ext === 'jpg' || $ext === 'jpeg') && function_exists('imagecreatefromjpeg')) {
                            $srcImg = @imagecreatefromjpeg($srcPath);
                        } elseif ($ext === 'png' && function_exists('imagecreatefrompng')) {
                            $srcImg = @imagecreatefrompng($srcPath);
                        } else {
                            // 拡張子不明時は汎用判定
                            if (function_exists('imagecreatefromstring')) {
                                $srcImg = @imagecreatefromstring(file_get_contents($srcPath));
                            }
                        }
                        if ($srcImg) {
                            $w = imagesx($srcImg);
                            $h = imagesy($srcImg);
                            // 中央正方形領域
                            if ($w > 0 && $h > 0) {
                                $size = min($w, $h);
                                $sx = (int)max(0, ($w - $size) / 2);
                                $sy = (int)max(0, ($h - $size) / 2);
                                $crop = imagecreatetruecolor($size, $size);
                                imagecopyresampled($crop, $srcImg, 0, 0, $sx, $sy, $size, $size, $size, $size);
                                // 256x256へ縮小
                                $thumb = imagecreatetruecolor(256, 256);
                                imagecopyresampled($thumb, $crop, 0, 0, 0, 0, 256, 256, $size, $size);
                                // WebP保存（なければJPEG）
                                if (function_exists('imagewebp')) {
                                    if (@imagewebp($thumb, $thumbPathWebp, 85)) {
                                        $thumbRelative = 'spot/' . $spotId . '/' . $y . '/' . $m . '/' . $postId . '/thumb_256.webp';
                                    }
                                } else {
                                    $thumbPathJpg = $uploadDir . '/thumb_256.jpg';
                                    if (@imagejpeg($thumb, $thumbPathJpg, 85)) {
                                        $thumbRelative = 'spot/' . $spotId . '/' . $y . '/' . $m . '/' . $postId . '/thumb_256.jpg';
                                    }
                                }
                                imagedestroy($thumb);
                                imagedestroy($crop);
                            }
                            imagedestroy($srcImg);
                        }
                    } catch (Throwable $t) {
                        // サムネ生成失敗は致命的ではないため無視
                    }
                }
            }
        }
    }

    // 画像有無をDBに反映（has_image, image_path, thumb_path）
    try {
        if ($action === 'update') {
            if ($clearImage) {
                // 既存ファイルの削除（可能なら）
                try {
                    if (!isset($basePostPath)) {
                        $basePostPath = '';
                        if (isset($ini_info['post']['path'])) {
                            $basePostPath = rtrim($ini_info['post']['path'], '/');
                        } else if (isset($ini_info['profile']['path'])) {
                            $basePostPath = rtrim(dirname(rtrim($ini_info['profile']['path'], '/')), '/') . '/post_images';
                        }
                    }
                    // 既存のパスを取得
                    $stmtC = $pdo->prepare('SELECT image_path, thumb_path FROM post WHERE post_id = :post_id');
                    $stmtC->execute([':post_id' => (int)$postId]);
                    $pr = $stmtC->fetch();
                    if ($pr) {
                        if (!empty($pr['image_path']) && $basePostPath !== '') {
                            @unlink($basePostPath . '/' . $pr['image_path']);
                        }
                        if (!empty($pr['thumb_path']) && $basePostPath !== '') {
                            @unlink($basePostPath . '/' . $pr['thumb_path']);
                        }
                    }
                } catch (Throwable $t) {}

                $stmt2 = $pdo->prepare('UPDATE post SET has_image = 0, image_path = NULL, thumb_path = NULL, update_at = NOW() WHERE post_id = :post_id');
                $stmt2->bindValue(':post_id', (int)$postId, PDO::PARAM_INT);
                $stmt2->execute();
            } elseif ($imageRelative !== null || $thumbRelative !== null) {
                $hasImage = 1;
                $stmt2 = $pdo->prepare('UPDATE post SET has_image = :has_image, image_path = :image_path, thumb_path = :thumb_path WHERE post_id = :post_id');
                $stmt2->bindValue(':has_image', $hasImage, PDO::PARAM_INT);
                if ($imageRelative !== null) {
                    $stmt2->bindValue(':image_path', $imageRelative, PDO::PARAM_STR);
                } else {
                    $stmt2->bindValue(':image_path', null, PDO::PARAM_NULL);
                }
                if ($thumbRelative !== null) {
                    $stmt2->bindValue(':thumb_path', $thumbRelative, PDO::PARAM_STR);
                } else {
                    $stmt2->bindValue(':thumb_path', null, PDO::PARAM_NULL);
                }
                $stmt2->bindValue(':post_id', (int)$postId, PDO::PARAM_INT);
                $stmt2->execute();
            }
        } else {
            $hasImage = ($imageRelative !== null) ? 1 : 0;
            $stmt2 = $pdo->prepare('UPDATE post SET has_image = :has_image, image_path = :image_path, thumb_path = :thumb_path WHERE post_id = :post_id');
            $stmt2->bindValue(':has_image', $hasImage, PDO::PARAM_INT);
            if ($imageRelative !== null) {
                $stmt2->bindValue(':image_path', $imageRelative, PDO::PARAM_STR);
            } else {
                $stmt2->bindValue(':image_path', null, PDO::PARAM_NULL);
            }
            if ($thumbRelative !== null) {
                $stmt2->bindValue(':thumb_path', $thumbRelative, PDO::PARAM_STR);
            } else {
                $stmt2->bindValue(':thumb_path', null, PDO::PARAM_NULL);
            }
            $stmt2->bindValue(':post_id', (int)$postId, PDO::PARAM_INT);
            $stmt2->execute();
        }
    } catch (Throwable $t) {
        // サムネ更新失敗は致命的ではないため無視
    }

    echo json_encode([
        'status' => 'success',
        'post_id' => (int)$postId,
        'image_path' => $imageRelative,
        'thumb_path' => $thumbRelative,
        'action' => ($action === 'update') ? 'update' : 'insert',
    ], JSON_UNESCAPED_UNICODE);

} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()], JSON_UNESCAPED_UNICODE);
}
?>
