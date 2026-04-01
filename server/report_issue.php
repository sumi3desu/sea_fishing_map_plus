<?php
// Cache disable headers for WebView reliability
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('Expires: 0');

// HTMLエスケープ
function h($s) { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }

// 種別の正規化: 英語コード/日本語いずれの入力にも対応
function normalize_category($val) {
  $m = mb_strtolower(trim((string)$val), 'UTF-8');
  if ($m === '') return '';
  $map = [
    'request' => '要望',
    'mistake' => '記載ミス',
    'confirm' => '確認のお願い',
    'other'   => 'その他',
  ];
  if (isset($map[$m])) return $map[$m];
  // 日本語そのまま
  $allowed = ['要望','記載ミス','確認のお願い','その他'];
  if (in_array($val, $allowed, true)) return $val;
  return '';
}

// POSTで category / kind / title が指定された場合は固定（変更不可）
$lockedCategory = '';
// NOTE: category を唯一の入力パラメータとしてサポート。kind は無視します。
if (isset($_POST['category'])) $lockedCategory = normalize_category($_POST['category']);
$hasCategoryLock = ($lockedCategory !== '');
$lockedTitle = isset($_POST['title']) ? (string)$_POST['title'] : '';
$lockedPostId = isset($_POST['post_id']) ? (string)$_POST['post_id'] : '';
$hasTitleLock = ($lockedTitle !== '');
?>
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, interactive-widget=resizes-content" />
  <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate" />
  <meta http-equiv="Pragma" content="no-cache" />
  <meta http-equiv="Expires" content="0" />
  <title>要望・記載ミスなどの報告</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    html, body { height: 100%; }
    main { min-height: 100dvh; }
    @supports not (height: 1dvh) { main { min-height: 100vh; } }
    :root { --fg:#222; --muted:#666; --line:#ddd; --primary:#1769aa; --bg:#fff; --kb:0px; }
    html { font-size: 18px; -webkit-text-size-adjust: 100%; }
    body { font-family: 'Roboto', -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans JP', Helvetica, Arial, sans-serif; color:var(--fg); background:var(--bg); margin:0; }
    header { padding:16px 20px; border-bottom:1px solid var(--line); font-weight:600; font-size:1.2rem; }
    main { padding: 16px 20px calc(24px + var(--kb)); max-width: 760px; margin: 0 auto; }
    .desc { color: var(--muted); font-size: 0.95rem; line-height: 1.6; margin-bottom: 16px; }
    form { border:1px solid var(--line); border-radius:12px; padding:16px; background:#fafafa; }
    .row { display:flex; gap:16px; flex-wrap:wrap; }
    .field { flex: 1 1 260px; margin: 8px 0; }
    label { display:block; font-size:0.95rem; margin-bottom:6px; color:#333; font-weight:600; }
    input[type="text"], input[type="email"], select, textarea { width:100%; box-sizing:border-box; border:1px solid var(--line); border-radius:8px; padding:10px; font-size:1rem; background:#fff; }
    textarea { min-height: 140px; resize: vertical; line-height: 1.6; overflow: auto; }
    /* 視認性向上: ロック（disabled）の select でも濃い文字色で表示 */
    select:disabled { color:#222; background:#f5f5f5; opacity:1; }
    .readonly-box { background:#f5f5f5; color:#222; }
    .hint { font-size: 0.9rem; color: var(--muted); margin-top: 4px; }
    .actions { margin-top: 12px; display:flex; align-items:center; gap:12px; }
    button { appearance:none; border:none; padding:10px 16px; border-radius:8px; font-weight:600; cursor:pointer; font-size:0.95rem; }
    .primary { background: var(--primary); color:#fff; }
    .ghost { background: transparent; color: var(--primary); }
    .note { font-size: 0.9rem; color: var(--muted); margin-top: 12px; }
    .banner { border:1px solid #f0c36d; background:#fff8e1; color:#8a6d3b; padding:12px 16px; border-radius:8px; margin: 0 0 12px; }
    /* 常に下側に余白を持たせて上方向へのスクロール余地を確保 */
    #focusSpacer { height: 35dvh; transition: height .12s ease; }
    @supports not (height: 1dvh) {
      #focusSpacer { height: 280px; }
    }
    /* 下部スペーサでスクロール余地を確保（他の自動スクロールは行わない） */
  </style>
  <script>
    function getParam(name) {
      const url = new URL(window.location.href);
      return url.searchParams.get(name) || '';
    }
    function setIfExists(id, value) {
      const el = document.getElementById(id);
      if (el) el.value = value;
    }
    function onLoadPrefill() {
      // Prefill from query
      const from = getParam('from') || 'info';
      setIfExists('uid', getParam('uid'));
      setIfExists('app', getParam('app'));
      setIfExists('platform', getParam('platform'));
      setIfExists('from', from);
      // Show anti-abuse notice when launched from settings
      if (from === 'settings') {
        const b = document.getElementById('limitBanner');
        if (b) b.hidden = false;
      }
      // Locking is handled server-side only when POSTed.
      // 追加: 詳細欄フォーカス時に動的に高さを拡張（iOS WKWebView 向けの保険）
      let detailsResizeTimer = null;
      try {
        const details = document.getElementById('details');
        const spacer = document.getElementById('focusSpacer');
        const setBaseSpacer = () => {
          if (!spacer) return;
          try {
            let base = 280;
            if (window.visualViewport) {
              base = Math.max(280, Math.floor(window.visualViewport.height * 0.35));
            } else {
              base = Math.max(280, Math.floor(window.innerHeight * 0.35));
            }
            spacer.style.height = base + 'px';
          } catch (_) {}
        };
        const expandDetails = () => {};
        const autoResize = () => {};
        const collapseDetails = () => {
          if (!details) return;
          details.style.minHeight = '';
          details.style.height = '';
          if (detailsResizeTimer) { clearInterval(detailsResizeTimer); detailsResizeTimer = null; }
          setBaseSpacer();
        };
        if (details) {
          details.addEventListener('focus', () => {
            // ここでは何もしない（スペーサのみで調整）
          });
          details.addEventListener('blur', () => { collapseDetails(); });
        }
      } catch (_) {}
      // 初期の基準スペーサ設定
      try {
        const spacer = document.getElementById('focusSpacer');
        if (spacer) {
          let base = 280;
          if (window.visualViewport) {
            base = Math.max(280, Math.floor(window.visualViewport.height * 0.35));
          } else {
            base = Math.max(280, Math.floor(window.innerHeight * 0.35));
          }
          spacer.style.height = base + 'px';
        }
      } catch (_) {}
    }
    // 自動スクロール/自動リサイズは撤去。下部スペーサのみで余地を確保します。
  </script>
</head>
<body onload="onLoadPrefill()">
  <header></header>
  <main>
    <!-- <div id="limitBanner" class="banner" hidden>1日10回までの報告しかできません</div> -->
    <form method="post" action="submit_report.php">
      <!-- Hidden metadata populated from query -->
      <input type="hidden" id="uid" name="uid" />
      <input type="hidden" id="app" name="app" />
      <input type="hidden" id="platform" name="platform" />
      <input type="hidden" id="from" name="from" />
      <?php if ($lockedPostId !== ''): ?>
        <input type="hidden" id="post_id" name="post_id" value="<?php echo h($lockedPostId); ?>" />
      <?php endif; ?>

      <!-- Honeypot (spam protection) -->
      <div style="position:absolute; left:-9999px" aria-hidden="true">
        <label>Leave blank</label>
        <input type="text" name="website" tabindex="-1" autocomplete="off" />
      </div>

      <div class="row">
        <div class="field">
          <label for="category">種別</label>
          <?php if ($hasCategoryLock): ?>
            <!-- ロック時は読み取り専用のテキストボックス表示（見た目をタイトルに合わせる） -->
            <input type="text" id="category_display" class="readonly-box" value="<?php echo h($lockedCategory); ?>" readonly />
            <input type="hidden" name="category" value="<?php echo h($lockedCategory); ?>" />
          <?php else: ?>
            <select id="category" name="category" required>
              <option value="要望" <?php echo ($lockedCategory==='要望')?'selected':''; ?>>要望</option>
              <option value="記載ミス" <?php echo ($lockedCategory==='記載ミス')?'selected':''; ?>>記載ミス</option>
              <option value="確認のお願い" <?php echo ($lockedCategory==='確認のお願い')?'selected':''; ?>>確認のお願い</option>
              <option value="その他" <?php echo ($lockedCategory==='その他')?'selected':''; ?>>その他</option>
            </select>
          <?php endif; ?>
        </div>
        <div class="field">
          <label for="title">件名</label>
          <input type="text" id="title" name="title" required placeholder="要望・記載ミス等の件名" value="<?php echo h($lockedTitle); ?>" <?php echo $hasTitleLock ? 'readonly style="background:#f5f5f5"' : ''; ?> />
        </div>
      </div>
      <div class="row">
        <div class="field">
          <label for="contact">連絡先メール（任意）</label>
          <input type="email" id="contact" name="contact" placeholder="返信が必要な場合のみ" />
        </div>
      </div>

      <div class="field">
        <label for="details">詳細</label>
        <textarea id="details" name="details" required placeholder="要望の内容、記載ミスの内容、正しいと思われる内容を具体的にご記入ください"></textarea>
      </div>
      <div class="actions">
        <button type="submit" class="primary">送信する</button>
        <button type="reset" class="ghost">リセット</button>
      </div>

      <p class="note">送信内容は品質改善・不具合修正の目的で利用します。個人情報の取り扱いはプライバシーポリシーに従います。</p>
      <div id="focusSpacer"></div>
    </form>
  </main>
</body>
</html>
