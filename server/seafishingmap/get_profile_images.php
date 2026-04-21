<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");

// 設定ファイル読み込み
$ini_info = parse_ini_file(_INI_FILE_PATH_, true);

header('Content-Type: application/json; charset=UTF-8');

try {
    $userId = isset($_POST['user_id']) ? (int)$_POST['user_id'] : 0;
    if ($userId <= 0) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'invalid user_id'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    $baseProfilePath = isset($ini_info['profile']['path']) ? rtrim($ini_info['profile']['path'], '/') : '';
    if ($baseProfilePath === '') {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => 'profile.path not configured'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    $dir = $baseProfilePath . '/' . $userId;
    $avatarRel = null;
    $coverRel  = null;

    if (is_dir($dir)) {
        // 最新の avatar_*, cover_* を探す（更新日時で最大のもの）
        $avatarFiles = glob($dir . '/avatar_*.*');
        $coverFiles  = glob($dir . '/cover_*.*');

        $latest = function(array $files) {
            $latestFile = null;
            $latestTime = -1;
            foreach ($files as $f) {
                $t = @filemtime($f);
                if ($t !== false && $t > $latestTime) {
                    $latestTime = $t;
                    $latestFile = $f;
                }
            }
            return $latestFile;
        };

        $avatar = $latest($avatarFiles);
        $cover  = $latest($coverFiles);

        if ($avatar && is_file($avatar)) {
            $avatarRel = $userId . '/' . basename($avatar);
        }
        if ($cover && is_file($cover)) {
            $coverRel  = $userId . '/' . basename($cover);
        }
    }

    echo json_encode([
        'status' => 'success',
        'avatar_path' => $avatarRel,
        'cover_path' => $coverRel,
    ], JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()], JSON_UNESCAPED_UNICODE);
}
?>

