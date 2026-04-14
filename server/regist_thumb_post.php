<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

header('Content-Type: application/json');

$ini_info = parse_ini_file(_INI_FILE_PATH_, true);

// 投稿ID
$post_id = $_POST['post_id'] ?? null;

// ユーザID
$user_id = $_POST['user_id'] ?? null;

$action = $_POST['action'] ?? '';
// up/down 指定（1=thumb up, 0=thumb down）。省略時は 1 とみなす。
$up_down_raw = $_POST['up_down'] ?? '1';
$up_down = ($up_down_raw === '0' || $up_down_raw === 0) ? 0 : 1;
// 低評価理由（up_down=0 のときに主に利用。up のとき送られてきても保存可能）
$reason = isset($_POST['reason']) ? trim($_POST['reason']) : '';
$reason_text = isset($_POST['reason_text']) ? trim($_POST['reason_text']) : '';
// バリデーション
$post_id = is_numeric($post_id) ? intval($post_id) : 0;
$user_id = is_numeric($user_id) ? intval($user_id) : 0;
if ($action === 'get') {
    if ($post_id <= 0) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'reason' => 'invalid parameters', 'count' => 0]);
        exit;
    }
} else if ($action === 'regist') {
    if ($post_id <= 0 || $user_id <= 0) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'reason' => 'invalid parameters', 'count' => 0]);
        exit;
    }
} else {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'reason' => 'invalid action', 'count' => 0]);
    exit;
}

try {
    $pdo = new PDO(
        $ini_info['database']['dsn'],
        $ini_info['database']['user'],
        $ini_info['database']['password']
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $resAction = $action;
    // post_thumb に up_down / reason / reason_text 列が存在することを前提
    // （列が無い環境では明示的に 500 を返す）
    $needCols = ['up_down', 'reason', 'reason_text'];
    foreach ($needCols as $col) {
        $chk = $pdo->prepare("SHOW COLUMNS FROM post_thumb LIKE ?");
        $chk->execute([$col]);
        if ($chk->fetch(PDO::FETCH_ASSOC) === false) {
            http_response_code(500);
            echo json_encode(['status' => 'error', 'reason' => 'server not ready: missing ' . $col . ' column', 'count' => 0]);
            exit;
        }
    }

    if ($action === 'regist') {
        // トグル + 相互排他（同一ユーザ・投稿で up/down は同時に存在しない）
        // テーブル: post_thumb(post_id INT, user_id INT, up_down TINYINT(1), created_at DATETIME)
        $pdo->beginTransaction();
        // 1) 反対側を削除（相互排他）
        $opp = ($up_down === 1) ? 0 : 1;
        $delOpp = $pdo->prepare('DELETE FROM post_thumb WHERE post_id = ? AND user_id = ? AND up_down = ?');
        $delOpp->execute([$post_id, $user_id, $opp]);
        // 2) 同じ側が存在すればトグルで削除、無ければ挿入
        $stmt = $pdo->prepare('SELECT 1 FROM post_thumb WHERE post_id = ? AND user_id = ? AND up_down = ? LIMIT 1');
        $stmt->execute([$post_id, $user_id, $up_down]);
        $exists = ($stmt->fetchColumn() !== false);
        if ($exists) {
            $del = $pdo->prepare('DELETE FROM post_thumb WHERE post_id = ? AND user_id = ? AND up_down = ?');
            $del->execute([$post_id, $user_id, $up_down]);
            $resAction = 'remove';
        } else {
            $ins = $pdo->prepare('INSERT INTO post_thumb (post_id, user_id, up_down, reason, reason_text, created_at) VALUES (?, ?, ?, ?, ?, NOW())');
            $ins->execute([$post_id, $user_id, $up_down, $reason, $reason_text]);
            $resAction = 'insert';
        }
        // 3) 件数取得（上限互換のため count は up の件数を返し、追加で count_down も返却）
        $cntUp = $pdo->prepare('SELECT COUNT(*) FROM post_thumb WHERE post_id = ? AND up_down = 1');
        $cntUp->execute([$post_id]);
        $countUp = intval($cntUp->fetchColumn());
        $cntDown = $pdo->prepare('SELECT COUNT(*) FROM post_thumb WHERE post_id = ? AND up_down = 0');
        $cntDown->execute([$post_id]);
        $countDown = intval($cntDown->fetchColumn());
        $pdo->commit();

        // 自分の現在の状態（1=up, 0=down, -1=none）
        $my = -1;
        try {
            $myStmt = $pdo->prepare('SELECT up_down FROM post_thumb WHERE post_id = ? AND user_id = ? LIMIT 1');
            $myStmt->execute([$post_id, $user_id]);
            $row = $myStmt->fetch(PDO::FETCH_ASSOC);
            if ($row && isset($row['up_down'])) {
                $my = intval($row['up_down']) === 1 ? 1 : 0;
            }
        } catch (Exception $ignored) {}

        http_response_code(200);
        echo json_encode([
            'status' => 'success',
            'reason' => '',
            'count' => $countUp,          // 互換: up の件数
            'count_up' => $countUp,
            'count_down' => $countDown,
            'action' => $resAction,
            'my_up_down' => $my,
        ]);
    } else {
        // get: 件数返却（互換: count は up の件数）
        $cntUp = $pdo->prepare('SELECT COUNT(*) FROM post_thumb WHERE post_id = ? AND up_down = 1');
        $cntUp->execute([$post_id]);
        $countUp = intval($cntUp->fetchColumn());
        $cntDown = $pdo->prepare('SELECT COUNT(*) FROM post_thumb WHERE post_id = ? AND up_down = 0');
        $cntDown->execute([$post_id]);
        $countDown = intval($cntDown->fetchColumn());

        // 自分の現在の状態（user_id があれば判定）
        $my = -1;
        if ($user_id > 0) {
            try {
                $myStmt = $pdo->prepare('SELECT up_down FROM post_thumb WHERE post_id = ? AND user_id = ? LIMIT 1');
                $myStmt->execute([$post_id, $user_id]);
                $row = $myStmt->fetch(PDO::FETCH_ASSOC);
                if ($row && isset($row['up_down'])) {
                    $my = intval($row['up_down']) === 1 ? 1 : 0;
                }
            } catch (Exception $ignored) {}
        }

        http_response_code(200);
        echo json_encode([
            'status' => 'success',
            'reason' => '',
            'count' => $countUp,          // 互換: up の件数
            'count_up' => $countUp,
            'count_down' => $countDown,
            'action' => 'get',
            'my_up_down' => $my,
        ]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        try { $pdo->rollBack(); } catch (Exception $ignored) {}
    }
    http_response_code(500);
    echo json_encode(['status' => 'error', 'reason' => 'DBエラー', 'count' => 0]);
}
