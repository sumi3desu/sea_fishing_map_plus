<?php
session_cache_limiter("nocache");
session_start();

include_once("include/define.php");
include_once("include/db.php");

header('Content-Type: application/json; charset=UTF-8');

function ensureColumn(PDO $pdo, string $table, string $column, string $ddl): void
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) AS cnt
           FROM information_schema.COLUMNS
          WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = :table_name
            AND COLUMN_NAME = :column_name'
    );
    $stmt->execute([
        ':table_name' => $table,
        ':column_name' => $column,
    ]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    $cnt = isset($row['cnt']) ? (int)$row['cnt'] : 0;
    if ($cnt === 0) {
        $pdo->exec($ddl);
    }
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

    $userId = isset($_POST['user_id']) ? (int)$_POST['user_id'] : 0;
    $entitlementId = isset($_POST['entitlement_id']) ? trim((string)$_POST['entitlement_id']) : 'premium';
    $isActive = isset($_POST['is_active']) ? (int)$_POST['is_active'] : 0;
    $productId = isset($_POST['product_id']) ? trim((string)$_POST['product_id']) : '';
    $expiresAt = isset($_POST['expires_at']) ? trim((string)$_POST['expires_at']) : '';
    $willRenew = isset($_POST['will_renew']) ? (int)$_POST['will_renew'] : 0;
    $payloadJson = isset($_POST['payload_json']) ? trim((string)$_POST['payload_json']) : '';

    if ($userId <= 0) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'invalid user_id'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    if ($entitlementId === '') {
        $entitlementId = 'premium';
    }

    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS subscription_status (
            user_id INT NOT NULL,
            entitlement_id VARCHAR(64) NOT NULL,
            is_active TINYINT(1) NOT NULL DEFAULT 0,
            product_id VARCHAR(191) DEFAULT NULL,
            expires_at DATETIME DEFAULT NULL,
            will_renew TINYINT(1) NOT NULL DEFAULT 0,
            latest_payload_json LONGTEXT DEFAULT NULL,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id, entitlement_id),
            KEY idx_subscription_status_product_id (product_id),
            KEY idx_subscription_status_updated_at (updated_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );

    ensureColumn(
        $pdo,
        'user',
        'subscription_active',
        "ALTER TABLE user ADD COLUMN subscription_active TINYINT(1) NOT NULL DEFAULT 0"
    );
    ensureColumn(
        $pdo,
        'user',
        'subscription_product_id',
        "ALTER TABLE user ADD COLUMN subscription_product_id VARCHAR(191) DEFAULT NULL"
    );
    ensureColumn(
        $pdo,
        'user',
        'subscription_expires_at',
        "ALTER TABLE user ADD COLUMN subscription_expires_at DATETIME DEFAULT NULL"
    );
    ensureColumn(
        $pdo,
        'user',
        'subscription_will_renew',
        "ALTER TABLE user ADD COLUMN subscription_will_renew TINYINT(1) NOT NULL DEFAULT 0"
    );
    ensureColumn(
        $pdo,
        'user',
        'subscription_updated_at',
        "ALTER TABLE user ADD COLUMN subscription_updated_at DATETIME DEFAULT NULL"
    );

    $expiresAtValue = null;
    if ($expiresAt !== '') {
        try {
            $dt = new DateTime($expiresAt);
            $dt->setTimezone(new DateTimeZone('Asia/Tokyo'));
            $expiresAtValue = $dt->format('Y-m-d H:i:s');
        } catch (Throwable $t) {
            $expiresAtValue = null;
        }
    }

    $sql = "INSERT INTO subscription_status (
                user_id,
                entitlement_id,
                is_active,
                product_id,
                expires_at,
                will_renew,
                latest_payload_json,
                updated_at
            ) VALUES (
                :user_id,
                :entitlement_id,
                :is_active,
                :product_id,
                :expires_at,
                :will_renew,
                :latest_payload_json,
                NOW()
            )
            ON DUPLICATE KEY UPDATE
                is_active = VALUES(is_active),
                product_id = VALUES(product_id),
                expires_at = VALUES(expires_at),
                will_renew = VALUES(will_renew),
                latest_payload_json = VALUES(latest_payload_json),
                updated_at = NOW()";
    $stmt = $pdo->prepare($sql);
    $stmt->execute([
        ':user_id' => $userId,
        ':entitlement_id' => $entitlementId,
        ':is_active' => ($isActive !== 0) ? 1 : 0,
        ':product_id' => ($productId !== '') ? $productId : null,
        ':expires_at' => $expiresAtValue,
        ':will_renew' => ($willRenew !== 0) ? 1 : 0,
        ':latest_payload_json' => ($payloadJson !== '') ? $payloadJson : null,
    ]);

    $stmt2 = $pdo->prepare(
        "UPDATE user
            SET subscription_active = :subscription_active,
                subscription_product_id = :subscription_product_id,
                subscription_expires_at = :subscription_expires_at,
                subscription_will_renew = :subscription_will_renew,
                subscription_updated_at = NOW()
          WHERE user_id = :user_id"
    );
    $stmt2->execute([
        ':subscription_active' => ($isActive !== 0) ? 1 : 0,
        ':subscription_product_id' => ($productId !== '') ? $productId : null,
        ':subscription_expires_at' => $expiresAtValue,
        ':subscription_will_renew' => ($willRenew !== 0) ? 1 : 0,
        ':user_id' => $userId,
    ]);

    echo json_encode([
        'status' => 'success',
        'user_id' => $userId,
        'entitlement_id' => $entitlementId,
    ], JSON_UNESCAPED_UNICODE);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage(),
    ], JSON_UNESCAPED_UNICODE);
}
?>
