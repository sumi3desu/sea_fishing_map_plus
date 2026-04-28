<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");
include_once("include/mail.php");

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
$flag = isset($_POST['flag']) ? intval($_POST['flag']) : -1; // -1:申請中, 1:承認, -2:非承認, -3:取り下げ 等
$spot_id_post = isset($_POST['spot_id']) ? intval($_POST['spot_id']) : (isset($_POST['port_id']) ? intval($_POST['port_id']) : 0);
$mail_action = isset($_POST['mail_action']) ? trim((string)$_POST['mail_action']) : '';
$mail_reason = isset($_POST['mail_reason']) ? trim((string)$_POST['mail_reason']) : '';
$actor_user_id = isset($_POST['actor_user_id']) ? intval($_POST['actor_user_id']) : 0;

function spot_kind_label($kubun) {
    switch ($kubun) {
        case 'gyoko': return '漁港';
        case 'teibou': return '堤防';
        case 'surf': return 'サーフ';
        case 'kako': return '河口';
        case 'iso': return '磯';
        default: return $kubun;
    }
}

function spot_mail_template($action) {
    switch ($action) {
        case 'confirm':
            return [
                'subject' => '[海釣りMAP+] 釣り場申請の編集内容について',
                'body_lines' => [
                    '海釣りMAP+ をご利用いただきありがとうございます。',
                    '',
                    'ご申請いただいた釣り場情報について、編集内容のご連絡です。',
                    '',
                    '対象釣り場: $spot_name$',
                    '釣り場種別: $spot_kind$',
                    '住所: $spot_address$',
                    '緯度: $spot_lat$',
                    '経度: $spot_lng$',
                    '',
                    '編集理由:',
                    '$mail_reason$',
                    '',
                    '本メールは送信専用です。',
                ],
            ];
        case 'approve':
            return [
                'subject' => '[海釣りMAP+] 釣り場申請が承認されました',
                'body_lines' => [
                    '海釣りMAP+ をご利用いただきありがとうございます。',
                    '',
                    'ご申請いただいた釣り場が承認されました。',
                    '',
                    '対象釣り場: $spot_name$',
                    '釣り場種別: $spot_kind$',
                    '住所: $spot_address$',
                    '緯度: $spot_lat$',
                    '経度: $spot_lng$',
                    '',
                    'メッセージ:',
                    '$mail_reason$',
                    '',
                    '本メールは送信専用です。',
                ],
            ];
        case 'deny':
            return [
                'subject' => '[海釣りMAP+] 釣り場申請は否認されました',
                'body_lines' => [
                    '海釣りMAP+ をご利用いただきありがとうございます。',
                    '',
                    'ご申請いただいた釣り場は否認されました。',
                    '',
                    '対象釣り場: $spot_name$',
                    '釣り場種別: $spot_kind$',
                    '住所: $spot_address$',
                    '緯度: $spot_lat$',
                    '経度: $spot_lng$',
                    '',
                    '否認理由:',
                    '$mail_reason$',
                    '',
                    '本メールは送信専用です。',
                ],
            ];
        default:
            return null;
    }
}

// バリデーション
if ($pref_id <= 0 && $spot_id_post <= 0) {
    http_response_code(400);
    echo json_encode(['result' => 'ng', 'reason' => '都道府県が不明です']);
    exit;
}
if ($name === '' || $yomi === '' || $kubun === '' || $lat === null || $lng === null) {
    http_response_code(400);
    echo json_encode(['result' => 'ng', 'reason' => '必須パラメータが不足しています']);
    exit;
}
if ($mail_action !== '' && !in_array($mail_action, ['confirm', 'approve', 'deny'], true)) {
    http_response_code(400);
    echo json_encode(['result' => 'ng', 'reason' => 'mail_action が不正です']);
    exit;
}
if (($mail_action === 'confirm' || $mail_action === 'deny') && $mail_reason === '') {
    http_response_code(400);
    echo json_encode(['result' => 'ng', 'reason' => '理由を入力してください']);
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

    if ($spot_id_post > 0) {
        $sel = $pdo->prepare("SELECT spot_id, user_id FROM spots WHERE spot_id = :spot_id LIMIT 1 FOR UPDATE");
        $sel->execute([':spot_id' => $spot_id_post]);
        $current = $sel->fetch(PDO::FETCH_ASSOC);
        if (!$current) {
            $pdo->rollBack();
            http_response_code(404);
            echo json_encode(['result' => 'ng', 'reason' => '対象の釣り場が見つかりません']);
            exit;
        }
        $owner_user_id = isset($current['user_id']) ? intval($current['user_id']) : 0;
        $save_user_id = ($owner_user_id > 0) ? $owner_user_id : $user_id;

        // UPDATE（承認/非承認/編集）
        $up = $pdo->prepare("UPDATE spots SET 
            spot_name=:spot_name,
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
          WHERE spot_id=:spot_id");
        $up->execute([
            ':spot_name' => $name,
            ':furigana'  => $yomi,
            ':j_yomi'    => $yomi,
            ':kubun'     => $kubun,
            ':address'   => $address,
            ':lat'       => $lat,
            ':lng'       => $lng,
            ':note'      => '',
            ':flag'      => $flag,
            ':private'   => $private,
            ':user_id'   => $save_user_id,
            ':spot_id'   => $spot_id_post,
        ]);

        if ($mail_action !== '') {
            $template = spot_mail_template($mail_action);
            if ($template === null) {
                throw new RuntimeException('メールテンプレートの取得に失敗しました');
            }
            if ($save_user_id <= 0) {
                throw new RuntimeException('申請者のユーザーIDが確認できません');
            }
            $mailSt = $pdo->prepare("SELECT email FROM `user` WHERE user_id = :user_id LIMIT 1");
            $mailSt->execute([':user_id' => $save_user_id]);
            $mailRow = $mailSt->fetch(PDO::FETCH_ASSOC);
            $target_mail = trim((string)($mailRow['email'] ?? ''));
            if ($target_mail === '') {
                throw new RuntimeException('申請者のメールアドレスが確認できません');
            }
            $body_params = [
                '$spot_name$' => $name,
                '$spot_kind$' => spot_kind_label($kubun),
                '$spot_address$' => $address,
                '$spot_lat$' => sprintf('%.6f', $lat),
                '$spot_lng$' => sprintf('%.6f', $lng),
                '$mail_reason$' => $mail_reason,
                '$actor_user_id$' => ($actor_user_id > 0) ? (string)$actor_user_id : '',
            ];
            $mail_body = build_mail_body($template['body_lines'], $body_params);
            $mail_reason_text = send_simple_text_mail(
                $ini_info['mail'],
                $target_mail,
                $template['subject'],
                $mail_body,
                '',
                'noreply@bouzer.jp',
                '海釣りMAP+'
            );
            if ($mail_reason_text !== '') {
                throw new RuntimeException('メール送信に失敗しました[' . $mail_reason_text . ']');
            }
        }

        $pdo->commit();
        http_response_code(200);
        echo json_encode(['result' => 'success', 'spot_id' => $spot_id_post, 'port_id' => $spot_id_post]);
    } else {
        // INSERT（flag は入力があれば優先。通常は -1）
        $min = $pref_id * 100000;
        $max = $min + 99999;
        $q = $pdo->prepare("SELECT spot_id FROM spots WHERE spot_id BETWEEN :min AND :max ORDER BY spot_id DESC LIMIT 1 FOR UPDATE");
        $q->execute([':min' => $min, ':max' => $max]);
        $row = $q->fetch(PDO::FETCH_ASSOC);
        if ($row && isset($row['spot_id'])) {
            $new_spot_id = intval($row['spot_id']) + 1;
        } else {
            $new_spot_id = $min + 1;
        }
        if ($new_spot_id > $max) {
            $pdo->rollBack();
            http_response_code(400);
            echo json_encode(['result' => 'ng', 'reason' => '当該都道府県のID上限に達しました']);
            exit;
        }
        $sql = "INSERT INTO spots (
            spot_id, spot_name, furigana, j_yomi, kubun, address, latitude, longitude, note, flag, private, user_id
          ) VALUES (
            :spot_id, :spot_name, :furigana, :j_yomi, :kubun, :address, :lat, :lng, :note, :flag, :private, :user_id
          )";
        $ins = $pdo->prepare($sql);
        $ins->execute([
            ':spot_id'   => $new_spot_id,
            ':spot_name' => $name,
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
        echo json_encode(['result' => 'success', 'spot_id' => $new_spot_id, 'port_id' => $new_spot_id]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        try { $pdo->rollBack(); } catch (Exception $ex) {}
    }
    http_response_code(500);
    echo json_encode(['result' => 'ng', 'reason' => 'DBエラー: ' . $e->getMessage()]);
} catch (Exception $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        try { $pdo->rollBack(); } catch (Exception $ex) {}
    }
    http_response_code(500);
    echo json_encode(['result' => 'ng', 'reason' => $e->getMessage()]);
}
