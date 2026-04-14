import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as r; // Riverpod for account section
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io' show Platform, File;

import 'new_account_page.dart';
import 'edit_account_page.dart';
import 'main.dart'; // userInfoProvider / isEmailRegisteredProvider
import 'common.dart';
import 'location.dart';
import 'db_rebuild_screen.dart';
import 'profile_edit_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'html_view_page.dart';
import 'appconfig.dart';
import 'constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'providers/premium_state_notifier.dart' as prem;
import 'premium_page.dart';
import 'services/revenuecat_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class SettingPage extends StatefulWidget {
  SettingPage({super.key});

  @override
  _SettingPageState createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  // カテゴリーBの選択状態を保持する変数（0, 1, 2 のいずれか）
  //int _selectedRadio = 0;
  Enum smartPhoneType = SmartPhoneType.iPhone;
  static const double _leadingIconSize = 22;
  static const double _leadingGap = 12;
  static const double _statusIndent = _leadingIconSize + _leadingGap; // 34px
  String _nickname = '';
  bool _didInitPremium = false;

  void waitGetMapKind() async {
    Common.instance.mapKind = await Common.instance.loadMapKind();
  }

  void initState() {
    super.initState();
    smartPhoneType = Common.instance.getSmartPhoneType();
    waitGetMapKind();
    // ローカルが未登録の場合はサーバから最新の登録状態を取得して反映
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRefreshUserInfoFromServer());
    _loadNickname();
  }

  Future<void> _maybeRefreshUserInfoFromServer() async {
    try {
      final local = await loadUserInfo() ?? await getOrInitUserInfo();
      // いつでもサーバの最新値を取得（UIをブロックしない範囲で）
      final remote = await getUserInfoFromServer(uuid: local.uuid, email: null);
      bool needsSave = false;
      final merged = UserInfo(
        userId: remote.userId != 0 ? remote.userId : local.userId,
        email: (remote.email).isNotEmpty ? remote.email : local.email,
        uuid: local.uuid,
        status: (remote.status).isNotEmpty ? remote.status : local.status,
        createdAt: (remote.createdAt).isNotEmpty ? remote.createdAt : local.createdAt,
        refreshToken: local.refreshToken,
        nickName: (remote.nickName ?? '').isNotEmpty ? remote.nickName : local.nickName,
      );
      if (merged.email != local.email || merged.nickName != local.nickName) {
        needsSave = true;
      }
      if (needsSave) {
        await saveUserInfo(merged);
        if (!mounted) return;
        // 設定画面の表示項目（ニックネーム含む）を更新
        final container = r.ProviderScope.containerOf(context, listen: false);
        container.invalidate(userInfoProvider);
        await _loadNickname();
      }
    } catch (_) {}
  }

  Future<void> _loadNickname() async {
    try {
      // 優先: セキュアストレージの UserInfo
      final info = await loadUserInfo();
      String nn = info?.nickName ?? '';
      if (nn.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        nn = prefs.getString('profile_nick_name') ?? '';
      }
      setState(() => _nickname = nn);
    } catch (_) {}
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Row(
      children: [
        const Icon(Icons.arrow_right, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _sectionCard({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(14, 12, 14, 12)}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade400),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }

  Widget _premiumStatusCard(r.WidgetRef ref) {
    final st = ref.watch(prem.premiumStateProvider);
    Widget content;
    if (st.isLoading) {
      content = const ListTile(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8),
        title: Text('現在の状態: 読み込み中'),
      );
    } else if (!st.isPremium) {
      content = const ListTile(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8),
        title: Text('現在の状態: 未購入'),
      );
    } else {
      content = FutureBuilder<String>(
        future: _resolveActiveProductTitle(),
        builder: (context, snap) {
          final t = snap.data ?? '購入済み';
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text('現在の状態: $t'),
          );
        },
      );
    }
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          if ((st.errorMessage ?? '').isNotEmpty)
            const SizedBox(height: 4),
          if ((st.errorMessage ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('エラー: ${st.errorMessage}', style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  Future<String> _resolveActiveProductTitle() async {
    try {
      // RevenueCat 構成が完了していない場合は安全にフォールバック
      if (!RevenueCatService.isConfigured) {
        await RevenueCatService.waitUntilConfigured(timeout: const Duration(seconds: 5));
        if (!RevenueCatService.isConfigured) return '購入済み';
      }
      final info = await Purchases.getCustomerInfo();
      final ent = info.entitlements.active.values.isNotEmpty
          ? info.entitlements.active.values.first
          : null;
      final pid = ent?.productIdentifier ?? '';
      if (pid.isEmpty) return '購入済み';
      // Offeringsからタイトル解決
      try {
        final offerings = await Purchases.getOfferings();
        final pkgs = <Package>[];
        if (offerings.current != null) pkgs.addAll(offerings.current!.availablePackages);
        for (final o in offerings.all.values) {
          for (final p in o.availablePackages) {
            if (!pkgs.any((e) => e.identifier == p.identifier)) pkgs.add(p);
          }
        }
        for (final p in pkgs) {
          if (p.storeProduct.identifier == pid) {
            final title = p.storeProduct.title;
            return title.isNotEmpty ? title : '購入済み';
          }
        }
      } catch (_) {}
      // フォールバック（IDから推測）
      final lpid = pid.toLowerCase();
      if (lpid.contains('month')) return '購入済み（月額）';
      if (lpid.contains('year')) return '購入済み（年額）';
      return '購入済み（$pid）';
    } catch (_) {
      return '購入済み';
    }
  }
  // 報告フォームをWebViewで開く（uid/app/platformを付与）
  Future<void> _openReportForm() async {
    try {
      // 事前に送信可否をチェックし、不可ならトーストを出して遷移しない
      final user = await loadUserInfo();

      // reports_blocked / reports_blocked_until / can_report のいずれかでブロック判定
      bool isBlocked = false;
      String msg = '現在、報告の送信は停止中です。';
      String? until = user?.reportsBlockedUntil;

      if (user != null) {
        // 恒久ブロック
        if (user.reportsBlocked == 1) {
          isBlocked = true;
        } else {
          // 一時ブロック期限が未来かを確認（JSTフォーマット想定: 'YYYY-MM-DD HH:mm:ss'）
          if (until != null && until.isNotEmpty) {
            try {
              final dt = DateTime.parse(until.replaceAll('/', '-'));
              if (dt.isAfter(DateTime.now())) {
                isBlocked = true;
              }
            } catch (_) {}
          }
        }

        // サーバー計算の can_report も尊重（古いクライアントでもブロックできるように）
        if (!isBlocked && user.canReport == false) {
          isBlocked = true;
        }

        // ブロック時のメッセージ整形（期限があれば表示）
        if (isBlocked && until != null && until.isNotEmpty) {
          try {
            final dt = DateTime.parse(until.replaceAll('/', '-'));
            final y = dt.year.toString().padLeft(4, '0');
            final m = dt.month.toString().padLeft(2, '0');
            final d = dt.day.toString().padLeft(2, '0');
            msg = '報告の送信は $y/$m/$d まで一時停止中です。';
          } catch (_) {}
        }
      }

      if (isBlocked) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
        );
        return;
      }

      // 当日送信数の上限チェック（サーバ問い合わせ）
      try {
        final uid = user?.userId ?? 0;
        if (uid > 0) {
          final checkUri = Uri.parse('${AppConfig.instance.baseUrl}get_issues_count.php').replace(
            queryParameters: {
              'user_id': uid.toString(),
              'ts': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          );
          final resp = await http.get(checkUri).timeout(kHttpTimeout);
          if (mounted && resp.statusCode == 200) {
            final j = jsonDecode(resp.body);
            final status = (j is Map) ? (j['status']?.toString() ?? '') : '';
            final reason = (j is Map) ? (j['reason']?.toString() ?? '') : '';
            final count = (j is Map) ? int.tryParse(j['count']?.toString() ?? '') ?? -1 : -1;
            final limit = (j is Map) ? int.tryParse(j['limit']?.toString() ?? '') ?? 10 : 10;
            if (status == 'error' || (count >= 0 && count >= limit)) {
              final txt = reason.isNotEmpty ? reason : '1日10回までの報告しかできません。本日の上限に達しました。';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(txt), duration: const Duration(seconds: 4)),
              );
              return; // 遷移しない
            }
          }
        }
      } catch (_) {
        // 失敗時は遷移をブロックしない
      }

      final info = await PackageInfo.fromPlatform();
      final ver = '${info.version}+${info.buildNumber}';
      final uid = user?.userId ?? 0;
      final platform = Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other');
      final uri = Uri.parse('${AppConfig.instance.baseUrl}report_issue.php').replace(queryParameters: {
        'uid': uid.toString(),
        'app': ver,
        'platform': platform,
        'from': 'settings',
        // cache-bust to avoid stale content in WebView cache
        'ts': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HtmlViewPage(title: '要望・記載ミスなどの報告', url: uri.toString()),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('報告ページを開けませんでした')));
    }
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool enabled = true,
    bool showSpinner = false,
    Widget? trailing,
    bool showChevron = false,
  }) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    final effectiveStyle =
        enabled ? textStyle : textStyle?.copyWith(color: Theme.of(context).disabledColor);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: _leadingIconSize,
              height: _leadingIconSize,
              child: Center(
                child: showSpinner
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icon, size: _leadingIconSize),
              ),
            ),
            const SizedBox(width: _leadingGap),
            Expanded(child: Text(label, style: effectiveStyle)),
            if (trailing != null) trailing,
            if (showChevron) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: Colors.grey.shade600),
            ],
          ],
        ),
      ),
    );
  }

  Widget _premiumNavCard() {
    return _sectionCard(
      child: _actionRow(
        icon: Icons.workspace_premium_outlined,
        label: 'プレミアム設定',
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumPage()));
        },
        showChevron: true,
      ),
    );
  }

  Widget _premiumCombinedCard(r.WidgetRef ref) {
    // 統合カード（上: 現在の状態, 下: プレミアム設定, Dividerで区切る）
    final st = ref.watch(prem.premiumStateProvider);
    Widget statusRow;
    if (st.isLoading) {
      statusRow = const ListTile(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8),
        title: Text('プレミアム状態: 読み込み中'),
      );
    } else if (!st.isPremium) {
      statusRow = const ListTile(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8),
        title: Text('プレミアム状態: 未購入'),
      );
    } else {
      statusRow = FutureBuilder<String>(
        future: _resolveActiveProductTitle(),
        builder: (context, snap) {
          final t = snap.data ?? '購入済み';
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text('プレミアム状態: $t'),
          );
        },
      );
    }
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          statusRow,
          const Divider(height: 1),
          _actionRow(
            icon: Icons.workspace_premium_outlined,
            label: 'プレミアム設定',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumPage()));
            },
            showChevron: true,
          ),
        ],
      ),
    );
  }

  @override

  String maskEmail(String email) {
  final parts = email.split('@');
  if (parts.length != 2) return email; // 不正形式はそのまま

  final name = parts[0];
  final domain = parts[1];

  if (name.length <= 2) {
    return '${name[0]}*@$domain';
  }

  final masked =
      name.substring(0, 2) + '*' * (name.length - 2);

  return '$masked@$domain';
  }

  int _selectedTabIndex = 0;
  final List<String> _tabs = const ['アカウント', '設定', 'その他', 'メンテナンス'];

  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.settings, color: Colors.white),
            SizedBox(width: 8),
            Text("設定"),
          ],
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildScrollableTabs(),
          const Divider(height: 1),
          Expanded(child: _buildTabContent()),
        ],
      ),
    );
  }

  Widget _buildScrollableTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_tabs.length, (i) {
            final selected = i == _selectedTabIndex;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: ChoiceChip(
                label: Text(_tabs[i]),
                selected: selected,
                onSelected: (v) {
                  if (!v) return;
                  setState(() => _selectedTabIndex = i);
                },
                selectedColor: Colors.grey.shade200,
                backgroundColor: Colors.white,
                labelStyle: TextStyle(color: Colors.grey.shade800),
                shape: StadiumBorder(side: BorderSide(color: Colors.grey.shade400)),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildAccountTab(context);
      case 1:
        return _buildSettingsTab(context);
      case 2:
        return _buildOthersTab(context);
      case 3:
      default:
        return _buildMaintenanceTab(context);
    }
  }

  // ---- Tabs ----
  Widget _buildAccountTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 初回にプレミアム状態を取得（設定画面表示時）
        r.Consumer(builder: (context, ref, _) {
          if (!_didInitPremium) {
            _didInitPremium = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              try { await ref.read(prem.premiumStateProvider.notifier).initialize(); } catch (_) {}
            });
          }
          return const SizedBox.shrink();
        }),

        _sectionTitle(context, 'アカウント'),
        const SizedBox(height: 12),
        r.Consumer(builder: (context, ref, _) {
          return _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(width: _leadingGap),
                    Expanded(
                      child: ref.watch(userInfoProvider).when(
                            loading: () => const Text('アカウント登録状態 : 読み込み中'),
                            error: (_, __) => const Text('アカウント登録状態 : 未'),
                            data: (userInfo) {
                              final email = userInfo?.email ?? '';
                              final statusText = email.isNotEmpty ? 'メール登録済み［${maskEmail(email)}］' : '未';
                              return Text('アカウント登録状態 : $statusText');
                            },
                          ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: _leadingGap, top: 2),
                  child: ref.watch(userInfoProvider).when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (userInfo) {
                          final uid = userInfo?.userId;
                          if (uid == null || uid <= 0) return const SizedBox.shrink();
                          return Text('ユーザID: $uid', style: Theme.of(context).textTheme.bodySmall);
                        },
                      ),
                ),
                const SizedBox(height: 6),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(left: 0),
                  child: Builder(
                    builder: (context) {
                      final asyncUser = r.ProviderScope.containerOf(context).read(userInfoProvider);
                      final isRegistered = r.ProviderScope.containerOf(context).read(isEmailRegisteredProvider);
                      // read() は同期値。ボタン押下時の画面遷移のみに使用
                      final currentEmail = asyncUser.valueOrNull?.email ?? '';
                      final accountLabel = 'アカウント設定';
                      final accountIcon = Icons.manage_accounts;
                      return _actionRow(
                        icon: accountIcon,
                        label: accountLabel,
                        onTap: () {
                          if (isRegistered) {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => EditAccountPage(currentEmail: currentEmail)),
                            );
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const NewAccountPage()),
                            );
                          }
                        },
                        enabled: true,
                        showChevron: true,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 24),
          _sectionTitle(context, 'プレミアム'),
          const SizedBox(height: 12),
          r.Consumer(builder: (context, ref, _) => _premiumCombinedCard(ref)),

        const SizedBox(height: 24),
        _sectionTitle(context, 'プロフィール'),
        const SizedBox(height: 12),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(width: _leadingGap),
                  const Text('ニックネーム:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (_nickname.isEmpty) ? '未設定' : _nickname,
                      textAlign: TextAlign.left,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.only(left: 0),
                child: _actionRow(
                  icon: Icons.account_circle_outlined,
                  label: 'プロフィール',
                  showChevron: true,
                  onTap: () async {
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileEditPage()),
                    );
                    if (result is String) {
                      setState(() => _nickname = result);
                    } else {
                      await _loadNickname();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTab(BuildContext context) {
    final common = Provider.of<Common>(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle(context, '地図(経路)'),
        const SizedBox(height: 8),
        _sectionCard(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Column(
            children: [
              if (!(smartPhoneType == SmartPhoneType.android || smartPhoneType == SmartPhoneType.unknown))
                RadioListTile<int>(
                  title: const Text("Apple Maps"),
                  value: MapType.appleMaps.index,
                  groupValue: common.mapKind,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  onChanged: (int? value) {
                    setState(() { Common.instance.mapKind = value!; });
                  },
                ),
              if (smartPhoneType != SmartPhoneType.unknown)
                RadioListTile<int>(
                  title: const Text("Google Maps"),
                  value: MapType.googleMaps.index,
                  groupValue: common.mapKind,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  onChanged: (int? value) {
                    setState(() { Common.instance.mapKind = value!; });
                  },
                ),
              // 「地図表示しない」は選択肢から削除
            ],
          ),
        ),

        const SizedBox(height: 24),
        _sectionTitle(context, 'データの更新'),
        const SizedBox(height: 12),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _actionRow(
                icon: Icons.storage,
                label: '最新データの更新',
                showChevron: true,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DbRebuildScreen()),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.only(left: _statusIndent, top: 6),
                child: Text(
                  '用語集や法令データを最新に更新します。\nWi-Fi 環境での実行を推奨します（モバイル回線ではデータ通信料が発生する場合があります）。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOthersTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle(context, 'お問い合わせ'),
        const SizedBox(height: 12),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _actionRow(
                icon: Icons.report_gmailerrorred_outlined,
                label: '要望・記載ミスなどの報告',
                onTap: () { _openReportForm(); },
                showChevron: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        _sectionTitle(context, '情報'),
        const SizedBox(height: 12),
        _sectionCard(
          child: _actionRow(
            icon: Icons.info_outline,
            label: '情報',
            showChevron: true,
            onTap: () async {
              try {
                final info = await PackageInfo.fromPlatform();
                final ver = '${info.version}+${info.buildNumber}';
                final platform = Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other');
                final base = Uri.parse('${AppConfig.instance.baseUrl}siowadou_pro_info.php');
                final uri = base.replace(queryParameters: {
                  'format': 'html',
                  'app': ver,
                  'platform': platform,
                  'ts': DateTime.now().millisecondsSinceEpoch.toString(),
                });
                if (!mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => HtmlViewPage(title: '情報', url: uri.toString())),
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('情報ページを開けませんでした')));
              }
            },
          ),
        ),

        const SizedBox(height: 24),
        _sectionTitle(context, 'ご利用にあたって'),
        const SizedBox(height: 12),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _actionRow(
                icon: Icons.description_outlined,
                label: '利用規約',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const HtmlViewPage(title: '利用規約', url: 'asset://assets/policies/terms_of_use.html'),
                    ),
                  );
                },
                showChevron: true,
              ),
              const Divider(height: 1),
              _actionRow(
                icon: Icons.privacy_tip_outlined,
                label: 'プライバシーポリシー',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const HtmlViewPage(title: 'プライバシーポリシー', url: 'asset://assets/policies/privacy_policy.html'),
                    ),
                  );
                },
                showChevron: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMaintenanceTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle(context, '初期化'),
        const SizedBox(height: 12),
        _sectionCard(
          child: ListTile(
            title: const Text("お気に入り削除", style: TextStyle(color: Colors.black)),
            leading: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.delete, color: Colors.black),
            ),
            onTap: () async {
              final result = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text("確認"),
                    content: const Text("お気に入り削除してもよろしいですか？"),
                    actions: [
                      TextButton(child: const Text("キャンセル"), onPressed: () { Navigator.of(context).pop(false); }),
                      TextButton(child: const Text("OK"), onPressed: () { Navigator.of(context).pop(true); }),
                    ],
                  );
                },
              );
              if (result == true) {
                await Common.instance.sioDb.removeAll();
                Location.instance.resetFlag();
                Location.instance.removeFavoriteSpot();
              }
            },
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          child: ListTile(
            title: const Text("ユーザをリセット（UUID再発行）", style: TextStyle(color: Colors.black)),
            leading: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.restart_alt, color: Colors.black),
            ),
            subtitle: const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '現在のユーザ情報（UUID）を初期化し、新しいユーザとして再登録します。\n必要なら事前にユーザデータの保存をご利用ください。',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ),
            onTap: () async {
              final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('確認'),
                      content: const Text('ユーザ情報（UUID）を初期化して新しいユーザを作成します。よろしいですか？'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
                      ],
                    ),
                  ) ?? false;
              if (!ok) return;
              try {
                const storage = FlutterSecureStorage();
                await storage.delete(key: userInfoKey);
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove(userInfoKey);
                await prefs.remove('profile_nick_name');
                await prefs.remove('profile_bg_path');
                final newInfo = await getOrInitUserInfo();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('新しいユーザを作成しました（ID: ${newInfo.userId}）')),
                );
                setState(() {});
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('ユーザリセットに失敗しました: $e')),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}
