<?php
declare(strict_types=1);

session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

header('Content-Type: application/json; charset=UTF-8');

function base64UrlEncode(string $data): string
{
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function getAccessTokenFromServiceAccount(string $serviceAccountPath): string
{
    if (!file_exists($serviceAccountPath)) {
        throw new RuntimeException('サービスアカウントJSONが見つかりません: ' . $serviceAccountPath);
    }

    $json = json_decode((string)file_get_contents($serviceAccountPath), true);
    if (!$json || empty($json['client_email']) || empty($json['private_key'])) {
        throw new RuntimeException('サービスアカウントJSONの内容が不正です。');
    }

    $now = time();
    $header = ['alg' => 'RS256', 'typ' => 'JWT'];
    $claimSet = [
        'iss'   => $json['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud'   => 'https://oauth2.googleapis.com/token',
        'iat'   => $now,
        'exp'   => $now + 3600,
    ];

    $unsignedJwt =
        base64UrlEncode(json_encode($header, JSON_UNESCAPED_SLASHES)) . '.' .
        base64UrlEncode(json_encode($claimSet, JSON_UNESCAPED_SLASHES));

    $privateKey = openssl_pkey_get_private($json['private_key']);
    if (!$privateKey) {
        throw new RuntimeException('秘密鍵の読み込みに失敗しました。');
    }

    $signature = '';
    $signed = openssl_sign($unsignedJwt, $signature, $privateKey, 'sha256WithRSAEncryption');
    openssl_free_key($privateKey);
    if (!$signed) {
        throw new RuntimeException('JWT署名に失敗しました。');
    }

    $jwt = $unsignedJwt . '.' . base64UrlEncode($signature);
    $postFields = http_build_query([
        'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion'  => $jwt,
    ]);

    $ch = curl_init('https://oauth2.googleapis.com/token');
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => ['Content-Type: application/x-www-form-urlencoded'],
        CURLOPT_POSTFIELDS => $postFields,
        CURLOPT_TIMEOUT => 30,
    ]);
    $result = curl_exec($ch);
    if ($result === false) {
        $error = curl_error($ch);
        curl_close($ch);
        throw new RuntimeException('アクセストークン取得 cURL エラー: ' . $error);
    }
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    $decoded = json_decode($result, true);
    if ($httpCode !== 200 || empty($decoded['access_token'])) {
        throw new RuntimeException('アクセストークン取得失敗: ' . $result);
    }

    return (string)$decoded['access_token'];
}

function sendFcmMessage(
    string $projectId,
    string $serviceAccountPath,
    string $deviceToken,
    string $title,
    string $body,
    array $data = []
): array {
    $accessToken = getAccessTokenFromServiceAccount($serviceAccountPath);
    $url = "https://fcm.googleapis.com/v1/projects/{$projectId}/messages:send";
    $catchNotificationGroupKey = 'catch_updates';

    $payload = [
        'message' => [
            'token' => $deviceToken,
            'notification' => [
                'title' => $title,
                'body'  => $body,
            ],
            'data' => array_map('strval', $data),
            'android' => [
                'collapse_key' => $catchNotificationGroupKey,
                'notification' => [
                    'tag' => $catchNotificationGroupKey,
                ],
            ],
            'apns' => [
                'headers' => [
                    'apns-priority' => '10',
                    'apns-collapse-id' => $catchNotificationGroupKey,
                ],
                'payload' => [
                    'aps' => [
                        'sound' => 'default',
                        'thread-id' => $catchNotificationGroupKey,
                    ],
                ],
            ],
        ],
    ];

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $accessToken,
            'Content-Type: application/json; charset=UTF-8',
        ],
        CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE),
        CURLOPT_TIMEOUT => 30,
    ]);

    $result = curl_exec($ch);
    if ($result === false) {
        $error = curl_error($ch);
        curl_close($ch);
        throw new RuntimeException('FCM送信 cURL エラー: ' . $error);
    }

    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    return [
        'http_code' => $httpCode,
        'body' => json_decode($result, true),
        'raw' => $result,
    ];
}

function markJobDone(PDO $pdo, int $jobId): void
{
    $stmt = $pdo->prepare(
        "UPDATE notification_jobs
         SET status = 'done',
             locked_at = NULL,
             updated_at = NOW()
         WHERE id = :id"
    );
    $stmt->execute([':id' => $jobId]);
}

function markJobFailed(PDO $pdo, int $jobId): void
{
    $stmt = $pdo->prepare(
        "UPDATE notification_jobs
         SET status = 'failed',
             retry_count = retry_count + 1,
             locked_at = NULL,
             updated_at = NOW()
         WHERE id = :id"
    );
    $stmt->execute([':id' => $jobId]);
}

function insertNotificationSendError(
    PDO $pdo,
    ?int $jobId,
    int $userId,
    ?string $fcmToken,
    ?string $errorCode,
    string $errorMessage
): void {
    $stmt = $pdo->prepare(
        "INSERT INTO notification_send_errors (
            job_id,
            user_id,
            fcm_token,
            error_code,
            error_message
         ) VALUES (
            :job_id,
            :user_id,
            :fcm_token,
            :error_code,
            :error_message
         )"
    );
    if ($jobId === null) {
        $stmt->bindValue(':job_id', null, PDO::PARAM_NULL);
    } else {
        $stmt->bindValue(':job_id', $jobId, PDO::PARAM_INT);
    }
    $stmt->bindValue(':user_id', $userId, PDO::PARAM_INT);
    if ($fcmToken === null || $fcmToken === '') {
        $stmt->bindValue(':fcm_token', null, PDO::PARAM_NULL);
    } else {
        $stmt->bindValue(':fcm_token', $fcmToken, PDO::PARAM_STR);
    }
    if ($errorCode === null || $errorCode === '') {
        $stmt->bindValue(':error_code', null, PDO::PARAM_NULL);
    } else {
        $stmt->bindValue(':error_code', $errorCode, PDO::PARAM_STR);
    }
    $stmt->bindValue(':error_message', $errorMessage, PDO::PARAM_STR);
    $stmt->execute();
}

function clearUserFcmToken(PDO $pdo, int $userId): void
{
    $stmt = $pdo->prepare(
        "UPDATE user
         SET fcm_token = NULL,
             fcm_token_updated_at = NOW()
         WHERE user_id = :user_id"
    );
    $stmt->execute([':user_id' => $userId]);
}

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

    $projectId = 'seafishingmap-4f77f';
    $serviceAccountPath = dirname(__DIR__, 2) . '/secure/seafishingmap-4f77f-firebase-adminsdk-fbsvc-e3159a8bd1.json';

    $stmt = $pdo->prepare(
        "SELECT *
         FROM notification_jobs
         WHERE available_at <= NOW()
         ORDER BY id ASC"
    );
    $stmt->execute();
    $jobs = $stmt->fetchAll();

    $results = [];

    foreach ($jobs as $job) {
        $jobId = (int)$job['id'];

        $stmtLock = $pdo->prepare(
            "UPDATE notification_jobs
             SET status = 'processing',
                 locked_at = NOW(),
                 updated_at = NOW()
             WHERE id = :id"
        );
        $stmtLock->execute([':id' => $jobId]);
        if ($stmtLock->rowCount() !== 1) {
            continue;
        }

        try {
            $posterUserId = (int)$job['poster_user_id'];
            $postId = (int)$job['post_id'];
            $baseSpotId = (int)$job['base_spot_id'];
            $hasImage = (int)($job['has_image'] ?? 0);
            $deviceToken = null;
            $sendErrorLogged = false;

            $payload = json_decode((string)($job['payload_json'] ?? ''), true);
            $candidateSpotIds = [];
            if (is_array($payload) && isset($payload['candidate_spot_ids']) && is_array($payload['candidate_spot_ids'])) {
                foreach ($payload['candidate_spot_ids'] as $rawId) {
                    $id = (int)$rawId;
                    if ($id > 0) {
                        $candidateSpotIds[$id] = $id;
                    }
                }
            }
            $candidateSpotIds = array_values($candidateSpotIds);
            if (empty($candidateSpotIds)) {
                throw new RuntimeException('candidate_spot_ids が空です。');
            }

            $stmtUser = $pdo->prepare(
                "SELECT user_id, fcm_token, notif_on_off
                 FROM user
                 WHERE user_id = :user_id
                 LIMIT 1"
            );
            $stmtUser->execute([':user_id' => $posterUserId]);
            $user = $stmtUser->fetch();
            if (!$user) {
                throw new RuntimeException('poster_user_id の user が見つかりません。');
            }

            if (isset($user['notif_on_off']) && (int)$user['notif_on_off'] === 0) {
                markJobDone($pdo, $jobId);
                $results[] = [
                    'job_id' => $jobId,
                    'status' => 'skipped',
                    'reason' => 'notif_on_off が OFF です。',
                ];
                continue;
            }

            $deviceToken = trim((string)($user['fcm_token'] ?? ''));
            if ($deviceToken === '') {
                markJobDone($pdo, $jobId);
                $results[] = [
                    'job_id' => $jobId,
                    'status' => 'skipped',
                    'reason' => 'fcm_token が未設定です。',
                ];
                continue;
            }

            $stmtFav = $pdo->prepare(
                "SELECT spot_id
                 FROM favorites
                 WHERE user_id = :user_id"
            );
            $stmtFav->execute([':user_id' => $posterUserId]);
            $favoriteSpotIds = [];
            foreach ($stmtFav->fetchAll() as $fav) {
                $favId = (int)($fav['spot_id'] ?? 0);
                if ($favId > 0) {
                    $favoriteSpotIds[$favId] = $favId;
                }
            }
            $favoriteSpotIds = array_values($favoriteSpotIds);

            $matchedSpotIds = array_values(array_intersect($candidateSpotIds, $favoriteSpotIds));
            if (empty($matchedSpotIds)) {
                markJobDone($pdo, $jobId);
                $results[] = [
                    'job_id' => $jobId,
                    'status' => 'skipped',
                    'reason' => 'candidate_spot_ids と favorites の一致がありません。',
                ];
                continue;
            }

            $title = 'お気に入りの釣り場近辺で釣果がありました';
            $body = '地図で周辺の釣果状況を確認できます';
            $data = [
                'post_id' => $postId,
                'base_spot_id' => $baseSpotId,
                'poster_user_id' => $posterUserId,
                'has_image' => $hasImage,
            ];

            $response = sendFcmMessage(
                $projectId,
                $serviceAccountPath,
                $deviceToken,
                $title,
                $body,
                $data
            );

            if (($response['http_code'] ?? 500) !== 200) {
                $responseBody = is_array($response['body'] ?? null) ? $response['body'] : [];
                $errorCode = null;
                $errorMessage = 'FCM送信失敗';
                if (isset($responseBody['error']) && is_array($responseBody['error'])) {
                    $errorCode = isset($responseBody['error']['status']) ? (string)$responseBody['error']['status'] : null;
                    if (!empty($responseBody['error']['message'])) {
                        $errorMessage = (string)$responseBody['error']['message'];
                    }
                } elseif (!empty($response['raw'])) {
                    $errorMessage = (string)$response['raw'];
                }
                insertNotificationSendError(
                    $pdo,
                    $jobId,
                    $posterUserId,
                    $deviceToken,
                    $errorCode,
                    $errorMessage
                );
                if ($errorCode === 'NOT_FOUND') {
                    clearUserFcmToken($pdo, $posterUserId);
                }
                $sendErrorLogged = true;
                throw new RuntimeException('FCM送信失敗: ' . $errorMessage);
            }

            markJobDone($pdo, $jobId);
                $results[] = [
                    'job_id' => $jobId,
                    'status' => 'done',
                    'matched_spot_ids' => $matchedSpotIds,
                    'data' => $data,
                    'response' => $response,
                ];
        } catch (Throwable $e) {
            if (!$sendErrorLogged && !empty($posterUserId ?? 0)) {
                try {
                    insertNotificationSendError(
                        $pdo,
                        $jobId,
                        (int)$posterUserId,
                        $deviceToken ?? null,
                        null,
                        $e->getMessage()
                    );
                } catch (Throwable $ignored) {
                }
            }
            markJobFailed($pdo, $jobId);
            $results[] = [
                'job_id' => $jobId,
                'status' => 'failed',
                'message' => $e->getMessage(),
            ];
        }
    }

    echo json_encode([
        'ok' => true,
        'processed_count' => count($results),
        'results' => $results,
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'ok' => false,
        'message' => $e->getMessage(),
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
}
?>
