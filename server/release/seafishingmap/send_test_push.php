<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

/**
 * Base64 URL-safe encode
 */
function base64UrlEncode(string $data): string
{
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

/**
 * サービスアカウントJSONから OAuth 2.0 アクセストークンを取得
 */
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

    $header = [
        'alg' => 'RS256',
        'typ' => 'JWT',
    ];

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
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/x-www-form-urlencoded',
        ],
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

    return $decoded['access_token'];
}

/**
 * FCM HTTP v1 API で単一端末へ通知送信
 */
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

    $payload = [
        'message' => [
            'token' => $deviceToken,
            'notification' => [
                'title' => $title,
                'body'  => $body,
            ],
            'data' => array_map('strval', $data),
            'apns' => [
                'headers' => [
                    'apns-priority' => '10',
                ],
                'payload' => [
                    'aps' => [
                        'sound' => 'default',
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

try {
    // FirebaseプロジェクトID
    $projectId = 'seafishingmap-4f77f';

    // release/api/send_test_push.php から見て、release の兄弟 secure を参照
    //$serviceAccountPath = dirname(__DIR__, 2) . '/secure/firebase-service-account.json';
  //$serviceAccountPath = dirname(__DIR__, 2) . '/home/users/0/babyblue.jp-bouzer/web/secure/seafishingmap-4f77f-firebase-adminsdk-fbsvc-e3159a8bd1.json';
    $serviceAccountPath = dirname(__DIR__, 2) . '/secure/seafishingmap-4f77f-firebase-adminsdk-fbsvc-e3159a8bd1.json';

    // テスト対象のiPhoneのFCMトークン
    //$deviceToken = 'ここにFCMトークンを貼る';
    //$deviceToken = 'dP8MwJ8trkPViLZhujQn6-:APA91bHIWywCvw3XfGXkNMydG7MceL6M1zgbuBsfoxzlyyQUweFfP0CuOW83-DqqiHroiH83aVeb6iePshVgCSMsbtx153zo1z7anl9yhqttptuZg-S0Nno';
  //$deviceToken = 'fmHUG1AURUcatRopEcUIeM:APA91bECTUGXm9Q1WwmYgQpoJAXtanujLYF0MEHs5SO0wbGqjwZLyjwWm9Yr3WlQFBofXHFGWlgERv5o4sdxWqT9KQpI0EL6sR3zlWAp7ruI36mtbzqZoSY';
    $deviceToken = 'd2NirO1Xf0ZtuzvJRhdOJg:APA91bH-wGOqJscDv2dPgcY82PfvJVEVea-NxyGxSYZjqsXr0RIN2Bh8DgT3DNytuDQNI_9U_bNmXn0Hns0w7XbhcwljKs-JBvnlpbEagZl7zLstF32-TpU';

$title = 'FCMテスト1';
    $body  = 'PHPから送信しました。';

    $data = [
        'type' => 'test',
        'screen' => 'home',
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
    http_response_code($response['http_code'] ?? 500);
    echo json_encode([
        'ok' => false,
        'message' => 'FCM送信に失敗しました。',
        'result' => $response,
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    exit;
}

    echo json_encode([
        'ok' => true,
        'message' => '送信処理を実行しました。',
        'result' => $response,
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);

} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'ok' => false,
        'message' => $e->getMessage(),
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
}