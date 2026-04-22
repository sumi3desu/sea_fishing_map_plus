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
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );

    // 入力
    $getKind = isset($_POST['get_kind']) ? trim((string)$_POST['get_kind']) : (isset($_GET['get_kind']) ? trim((string)$_GET['get_kind']) : '1');
    $spotId  = isset($_POST['spot_id']) ? (int)$_POST['spot_id'] : (isset($_GET['spot_id']) ? (int)$_GET['spot_id'] : 0);
    $limit   = isset($_POST['limit']) ? (int)$_POST['limit'] : (isset($_GET['limit']) ? (int)$_GET['limit'] : 100);
    if ($limit <= 0 || $limit > 500) $limit = 100;
    $page    = isset($_POST['page']) ? (int)$_POST['page'] : (isset($_GET['page']) ? (int)$_GET['page'] : 0);
    $pageSz  = isset($_POST['page_size']) ? (int)$_POST['page_size'] : (isset($_GET['page_size']) ? (int)$_GET['page_size'] : 0);
    if ($pageSz <= 0) $pageSz = 0; // 未指定時は従来のlimitを使用
    $userId  = isset($_POST['user_id']) ? (int)$_POST['user_id'] : (isset($_GET['user_id']) ? (int)$_GET['user_id'] : 0);
    // 0: 指定スポットのみ / 1: 釣果は近隣10スポット。未指定は従来互換で1。
    $ambiguousPlevel = isset($_POST['ambiguous_plevel']) ? (int)$_POST['ambiguous_plevel'] : (isset($_GET['ambiguous_plevel']) ? (int)$_GET['ambiguous_plevel'] : 1);

    // WHERE 句の組み立て
    $where = [];
    $params = [];
    $where[] = 'p.is_deleted = 0';

    // get_kind の意味:
    //  1 -> 釣果 (post_kind = 1)
    //  0 -> 釣果以外 (post_kind <> 1)
    //  その他の数値 -> 該当 post_kind のみ
    if (ctype_digit($getKind)) {
        $k = (int)$getKind;
        if ($k === 1) {
            // 釣果: 近隣10スポット（指定があれば）を対象
            $where[] = 'p.post_kind = 1';
        } else if ($k === 0) {
            $where[] = 'p.post_kind <> 1';
        } else {
            $where[] = 'p.post_kind = :post_kind';
            $params[':post_kind'] = $k;
        }
    } else {
        // 不正値は釣果として扱う
        $k = 1;
        $where[] = 'p.post_kind = 1';
    }

    if ($userId > 0) {
        $where[] = 'p.user_id = :user_id';
        $params[':user_id'] = $userId;
    }

    // スポット指定時の処理
    $useNear = false;
    $nearIds = [];
    if ($spotId > 0) {
        // get_kind=1 かつ ambiguous_plevel != 0 のときだけ近隣10スポット。
        // ただし user_id 指定時（釣り日記など）は指定スポットのみ取得する。
        // ambiguous_plevel=0 や釣果以外も指定スポットのみ取得する。
        if (isset($k) && $k === 1 && $ambiguousPlevel !== 0 && $userId <= 0) {
            try {
                // 基点座標
                $stmt0 = $pdo->prepare('SELECT latitude, longitude FROM teibou WHERE port_id = :sid LIMIT 1');
                $stmt0->execute([':sid' => $spotId]);
                $row0 = $stmt0->fetch();
                if ($row0 && isset($row0['latitude']) && isset($row0['longitude'])) {
                    $lat = (float)$row0['latitude'];
                    $lng = (float)$row0['longitude'];
                    // 近距離のスポットを取得（ハバーサイン近似）
                    $sqlNear = 'SELECT port_id,
                                   (6371 * acos( cos(radians(:lat)) * cos(radians(latitude)) * cos(radians(longitude) - radians(:lng)) + sin(radians(:lat)) * sin(radians(latitude)) )) AS dist
                                FROM teibou
                                ORDER BY dist ASC
                                LIMIT 10';
                    $stmtN = $pdo->prepare($sqlNear);
                    $stmtN->execute([':lat' => $lat, ':lng' => $lng]);
                    $rowsN = $stmtN->fetchAll();
                    foreach ($rowsN as $r) {
                        $pid = (int)$r['port_id'];
                        if ($pid > 0) $nearIds[] = $pid;
                    }
                    if (count($nearIds) > 0) {
                        $useNear = true;
                    }
                }
            } catch (Throwable $t) {
                $useNear = false;
            }
        }
        if ($useNear && count($nearIds) > 0) {
            // IN 句を構築
            $inPh = [];
            foreach ($nearIds as $i => $val) {
                $ph = ':nid'.$i;
                $inPh[] = $ph;
                $params[$ph] = (int)$val;
            }
            $where[] = 'p.spot_id IN ('.implode(',', $inPh).')';
        } else {
            $where[] = 'p.spot_id = :spot_id';
            $params[':spot_id'] = $spotId;
        }
    }

    $whereSql = '';
    if (!empty($where)) {
        $whereSql = 'WHERE ' . implode(' AND ', $where);
    }

    if ($page > 0 && $pageSz > 0) {
        $offset = max(0, ($page - 1) * $pageSz);
        $sql = "SELECT p.post_id, p.user_id, p.spot_id, p.post_kind, p.exist, p.title, p.detail, p.create_at, p.image_path, p.thumb_path,
                       u.nick_name AS nick_name
                FROM post p
                LEFT JOIN user u ON u.user_id = p.user_id
                $whereSql
                ORDER BY p.create_at DESC, p.post_id DESC
                LIMIT :offset, :limit";
    } else {
        $sql = "SELECT p.post_id, p.user_id, p.spot_id, p.post_kind, p.exist, p.title, p.detail, p.create_at, p.image_path, p.thumb_path,
                       u.nick_name AS nick_name
                FROM post p
                LEFT JOIN user u ON u.user_id = p.user_id
                $whereSql
                ORDER BY p.create_at DESC, p.post_id DESC
                LIMIT :limit";
    }
    $stmt = $pdo->prepare($sql);
    foreach ($params as $k => $v) {
        $stmt->bindValue($k, $v, is_int($v) ? PDO::PARAM_INT : PDO::PARAM_STR);
    }
    if ($page > 0 && $pageSz > 0) {
        $stmt->bindValue(':offset', (int)max(0, ($page - 1) * $pageSz), PDO::PARAM_INT);
        $stmt->bindValue(':limit', (int)$pageSz, PDO::PARAM_INT);
    } else {
        $stmt->bindValue(':limit', (int)$limit, PDO::PARAM_INT);
    }
    $stmt->execute();
    $rows = $stmt->fetchAll();

    echo json_encode(['status' => 'success', 'rows' => $rows], JSON_UNESCAPED_UNICODE);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()], JSON_UNESCAPED_UNICODE);
}
?>
