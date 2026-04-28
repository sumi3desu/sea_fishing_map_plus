import 'package:flutter/material.dart';
import 'appconfig.dart';
import 'constants.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'post_detail_page.dart';
import 'sio_database.dart';
import 'sync_service.dart';
import 'main.dart';
import 'common.dart';
import 'log_print.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'new_account_page.dart';

class FishingResultGrid extends StatefulWidget {
  const FishingResultGrid({super.key});

  @override
  State<FishingResultGrid> createState() => _FishingResultGridState();
}

class _FishingResultGridState extends State<FishingResultGrid>
    with SingleTickerProviderStateMixin {
  final List<_PostGridItem> _items = [];
  final List<_PostGridItem> _listItems = [];
  final ScrollController _sc = ScrollController();
  final ScrollController _listSc = ScrollController();
  bool _loading = false;
  bool _listLoading = false;
  bool _hasMore = true;
  bool _listHasMore = true;
  int _page = 1;
  int _listPage = 1;
  final Map<int, String> _prefNameById = {};
  final Map<int, String> _spotNameById = {};
  bool _isAdmin = false;
  int? _myUserId;
  bool _metaReady = false; // 都道府県/釣り場名とadminの準備完了
  final Map<int, String> _imgTsByPost = {}; // キャッシュバスター（編集後の差し替え用）
  bool _lastFishingDiaryMode = Common.instance.fishingDiaryMode;
  int _lastAmbiguousLevel = ambiguousLevel;
  int _lastPostFeedReloadTick = Common.instance.postFeedReloadTick;
  int _lastCatchNotificationTick = Common.instance.catchNotificationTick;
  int? _lastCatchNotificationPostId =
      Common.instance.latestCatchNotificationPostId;
  String _lastCatchNotificationTitle =
      Common.instance.latestCatchNotificationTitle;
  String _lastCatchNotificationBody =
      Common.instance.latestCatchNotificationBody;
  late final TabController _tabController;

  Future<bool> _ensureEmailVerified() async {
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      if (info.email.trim().isNotEmpty) return true;
    } catch (_) {}
    if (!mounted) return false;
    final res = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NewAccountPage(authPurposeLabel: '釣り日記'),
      ),
    );
    return res == true;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Common.instance.setFishingResultTabIndex(_tabController.index);
    refreshForegroundNotificationPresentationOptions();
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      Common.instance.setFishingResultTabIndex(_tabController.index);
      refreshForegroundNotificationPresentationOptions();
      if (_tabController.index != 1) {
        Common.instance.clearCatchNotification();
      }
    });
    _initMeta();
    _loadImageTsMap();
    Common.instance.addListener(_onCommonChanged);
    _loadFirst();
    _loadListFirst();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Common.instance.latestCatchNotificationPostId != null) {
        _tabController.animateTo(1);
      }
    });
    _sc.addListener(() {
      if (_sc.position.pixels >= _sc.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
    _listSc.addListener(() {
      if (_listSc.position.pixels >= _listSc.position.maxScrollExtent - 200) {
        _loadListMore();
      }
    });
  }

  Future<void> _initMeta() async {
    await _ensurePrefMap();
    await _checkAdmin();
    await _loadMyUserId();
    if (mounted) setState(() => _metaReady = true);
  }

  Future<void> _loadMyUserId() async {
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      if (!mounted) return;
      setState(() => _myUserId = info.userId);
    } catch (_) {}
  }

  void _onCommonChanged() {
    final enabled = Common.instance.fishingDiaryMode;
    final diaryModeChanged = _lastFishingDiaryMode != enabled;
    final ambiguousChanged = _lastAmbiguousLevel != ambiguousLevel;
    final postFeedChanged =
        _lastPostFeedReloadTick != Common.instance.postFeedReloadTick;
    final catchNotificationChanged =
        _lastCatchNotificationTick != Common.instance.catchNotificationTick;
    final currentNotificationPostId =
        Common.instance.latestCatchNotificationPostId;
    final currentNotificationTitle =
        Common.instance.latestCatchNotificationTitle;
    final currentNotificationBody = Common.instance.latestCatchNotificationBody;
    final catchNotificationStateChanged =
        _lastCatchNotificationPostId != currentNotificationPostId ||
        _lastCatchNotificationTitle != currentNotificationTitle ||
        _lastCatchNotificationBody != currentNotificationBody;
    if (catchNotificationStateChanged) {
      _lastCatchNotificationPostId = currentNotificationPostId;
      _lastCatchNotificationTitle = currentNotificationTitle;
      _lastCatchNotificationBody = currentNotificationBody;
    }
    if (catchNotificationChanged) {
      _lastCatchNotificationTick = Common.instance.catchNotificationTick;
      if (Common.instance.latestCatchNotificationPostId != null) {
        _tabController.animateTo(1);
        if (_listItems.isEmpty) {
          _loadListFirst();
        } else {
          _refreshListPreserveItems();
        }
      }
    }
    if (_lastFishingDiaryMode == enabled &&
        !ambiguousChanged &&
        !postFeedChanged &&
        !catchNotificationChanged &&
        !catchNotificationStateChanged) {
      return;
    }
    if (!ambiguousChanged &&
        !postFeedChanged &&
        !catchNotificationChanged &&
        catchNotificationStateChanged) {
      if (mounted) {
        setState(() {});
      }
      return;
    }
    _lastFishingDiaryMode = enabled;
    _lastAmbiguousLevel = ambiguousLevel;
    _lastPostFeedReloadTick = Common.instance.postFeedReloadTick;
    logPrint(
      'FishingResultGrid reload trigger diaryMode=$enabled ambiguous=$ambiguousLevel feedTick=${Common.instance.postFeedReloadTick}',
    );
    _loadFirst();
    if (diaryModeChanged || _listItems.isEmpty) {
      _loadListFirst();
    } else {
      _refreshListPreserveItems();
    }
  }

  @override
  void dispose() {
    Common.instance.setFishingResultTabIndex(0);
    refreshForegroundNotificationPresentationOptions();
    Common.instance.removeListener(_onCommonChanged);
    _tabController.dispose();
    _sc.dispose();
    _listSc.dispose();
    super.dispose();
  }

  Future<_FetchResult> _fetch({
    required int page,
    required bool imageOnly,
  }) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final uri = Uri.parse(
        '${AppConfig.instance.baseUrl}get_post_list.php?ts=$ts',
      );
      final body = <String, String>{
        'get_kind': '1', // 釣果
        'page': page.toString(),
        'page_size': kPostPageSize.toString(),
        'ambiguous_plevel': ambiguousLevel.toString(),
        'catch_list_image_only': imageOnly ? '1' : '0',
        'ts': ts.toString(),
      };
      if (Common.instance.fishingDiaryMode) {
        final uid =
            _myUserId ??
            (await loadUserInfo() ?? await getOrInitUserInfo()).userId;
        _myUserId ??= uid;
        if (uid > 0) body['user_id'] = uid.toString();
      }
      logPrint(
        'FishingResultGrid fetch page=$page imageOnly=$imageOnly diaryMode=${Common.instance.fishingDiaryMode} body=${body.entries.map((e) => '${e.key}=${e.value}').join('&')}',
      );
      final resp = await http
          .post(
            uri,
            body: body,
            headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
          )
          .timeout(kHttpTimeout);
      if (resp.statusCode != 200) {
        return const _FetchResult(items: [], rawCount: 0);
      }
      final data = jsonDecode(resp.body);
      List rows;
      if (data is Map && data['status'] == 'success') {
        rows = (data['rows'] as List?) ?? [];
      } else if (data is List) {
        rows = data;
      } else {
        return const _FetchResult(items: [], rawCount: 0);
      }
      final list =
          rows
              .map(
                (e) => _PostGridItem.fromJson(
                  e as Map<String, dynamic>,
                  AppConfig.instance.baseUrl,
                ),
              )
              .toList();
      final sampleItems = list
          .take(5)
          .map(
            (e) =>
                '${e.postId?.toString() ?? 'null'}:u${e.userId?.toString() ?? 'null'}',
          )
          .join(',');
      final uniqueUserIds = list.map((e) => e.userId).whereType<int>().toSet();
      Common.instance.registerKnownCatchPostIds(
        list.map((e) => e.postId).whereType<int>(),
      );
      logPrint(
        'FishingResultGrid fetch result page=$page count=${list.length} uniqueUserIds=${uniqueUserIds.length} sampleItems=[$sampleItems]',
      );
      if (!imageOnly) {
        return _FetchResult(items: list, rawCount: list.length);
      }
      return _FetchResult(
        items: list.where((e) => (e.thumbUrl ?? e.imageUrl) != null).toList(),
        rawCount: list.length,
      );
    } catch (_) {
      logPrint('FishingResultGrid fetch failed page=$page');
      return const _FetchResult(items: [], rawCount: 0);
    }
  }

  Future<void> _loadFirst() async {
    if (!mounted) return;
    logPrint(
      'FishingResultGrid loadFirst diaryMode=${Common.instance.fishingDiaryMode} ambiguous=$ambiguousLevel',
    );
    setState(() {
      _items.clear();
      _page = 1;
      _hasMore = true;
      _loading = false;
    });
    await _loadMore();
  }

  Future<void> _loadListFirst() async {
    if (!mounted) return;
    logPrint(
      'FishingResultGrid loadListFirst diaryMode=${Common.instance.fishingDiaryMode} ambiguous=$ambiguousLevel',
    );
    setState(() {
      _listItems.clear();
      _listPage = 1;
      _listHasMore = true;
      _listLoading = false;
    });
    await _loadListMore();
  }

  Future<void> _refreshListPreserveItems() async {
    if (!mounted) return;
    final currentItems = List<_PostGridItem>.from(_listItems);
    final currentHasMore = _listHasMore;
    final currentPage = _listPage;
    logPrint(
      'FishingResultGrid refreshListPreserveItems currentCount=${currentItems.length} currentPage=$currentPage',
    );
    setState(() => _listLoading = true);
    final result = await _fetch(page: 1, imageOnly: false);
    if (!mounted) return;
    final merged = <_PostGridItem>[];
    merged.addAll(_dedupePostGridItems(result.items, existing: merged));
    merged.addAll(_dedupePostGridItems(currentItems, existing: merged));
    setState(() {
      _listItems
        ..clear()
        ..addAll(merged);
      _listHasMore = currentHasMore || result.rawCount >= kPostPageSize;
      _listPage = currentPage < 2 ? 2 : currentPage;
      _listLoading = false;
    });
    _scrollToLatestCatchNotificationIfNeeded();
    logPrint(
      'FishingResultGrid refreshListPreserveItems end itemCount=${_listItems.length} nextPage=$_listPage hasMore=$_listHasMore',
    );
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    if (!mounted) return;
    logPrint('FishingResultGrid loadMore start page=$_page');
    setState(() => _loading = true);
    final result = await _fetch(page: _page, imageOnly: true);
    if (!mounted) return;
    setState(() {
      _items.addAll(_dedupePostGridItems(result.items, existing: _items));
      _hasMore = result.rawCount >= kPostPageSize;
      _page += 1;
      _loading = false;
    });
    logPrint(
      'FishingResultGrid loadMore end nextPage=$_page hasMore=$_hasMore itemCount=${_items.length} rawCount=${result.rawCount}',
    );
  }

  Future<void> _loadListMore() async {
    if (_listLoading || !_listHasMore) return;
    if (!mounted) return;
    logPrint('FishingResultGrid loadListMore start page=$_listPage');
    setState(() => _listLoading = true);
    final result = await _fetch(page: _listPage, imageOnly: false);
    if (!mounted) return;
    setState(() {
      _listItems.addAll(
        _dedupePostGridItems(result.items, existing: _listItems),
      );
      _listHasMore = result.rawCount >= kPostPageSize;
      _listPage += 1;
      _listLoading = false;
    });
    _scrollToLatestCatchNotificationIfNeeded();
    logPrint(
      'FishingResultGrid loadListMore end nextPage=$_listPage hasMore=$_listHasMore itemCount=${_listItems.length} rawCount=${result.rawCount}',
    );
  }

  List<_PostGridItem> _dedupePostGridItems(
    List<_PostGridItem> incoming, {
    List<_PostGridItem> existing = const [],
  }) {
    final seen = <int>{};
    for (final item in existing) {
      final postId = item.postId;
      if (postId != null && postId > 0) {
        seen.add(postId);
      }
    }
    final unique = <_PostGridItem>[];
    for (final item in incoming) {
      final postId = item.postId;
      if (postId == null || postId <= 0) {
        unique.add(item);
        continue;
      }
      if (seen.add(postId)) {
        unique.add(item);
      }
    }
    return unique;
  }

  void _scrollToLatestCatchNotificationIfNeeded() {
    final targetPostId = Common.instance.latestCatchNotificationPostId;
    if (targetPostId == null) return;
    final idx = _listItems.indexWhere((e) => e.postId == targetPostId);
    if (idx < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_listSc.hasClients) return;
      final offset = (idx * 73.0).clamp(0.0, _listSc.position.maxScrollExtent);
      _listSc.animateTo(
        offset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _maybeLoadMoreFromScroll(ScrollMetrics metrics) {
    if (metrics.extentAfter < 300 && !_loading && _hasMore) {
      logPrint(
        'FishingResultGrid scroll trigger extentAfter=${metrics.extentAfter.toStringAsFixed(1)} page=$_page hasMore=$_hasMore',
      );
      _loadMore();
    }
  }

  void _maybeLoadListMoreFromScroll(ScrollMetrics metrics) {
    if (metrics.extentAfter < 300 && !_listLoading && _listHasMore) {
      logPrint(
        'FishingResultGrid list scroll trigger extentAfter=${metrics.extentAfter.toStringAsFixed(1)} page=$_listPage hasMore=$_listHasMore',
      );
      _loadListMore();
    }
  }

  Future<void> _ensurePrefMap() async {
    try {
      final db = await SioDatabase().database;
      var rows = await db.query('todoufuken');
      // 釣り場名のためのテーブルもチェック
      var teibou = await db.query('spots');
      // 初回起動などで未同期の場合はサーバーと同期してから再取得
      if (rows.isEmpty || teibou.isEmpty) {
        try {
          final info = await loadUserInfo();
          final uid = info?.userId ?? 0;
          await SioSyncService().syncFishingData(userId: uid, force: true);
        } catch (_) {}
        rows = await db.query('todoufuken');
        teibou = await db.query('spots');
      }
      for (final r in rows) {
        final idVal = r['todoufuken_id'];
        final nameVal = r['todoufuken_name'];
        final id =
            (idVal is int) ? idVal : int.tryParse(idVal?.toString() ?? '');
        final name = nameVal?.toString();
        if (id != null && name != null && name.isNotEmpty) {
          _prefNameById[id] = name;
        }
      }
      // 釣り場名（spot_id -> spot_name）も用意
      if (teibou.isEmpty) {
        try {
          teibou = await SioDatabase().getAllTeibouWithPrefecture();
        } catch (_) {}
      }
      for (final r in teibou) {
        final id = int.tryParse(r['spot_id']?.toString() ?? '');
        final name = (r['spot_name'] ?? '').toString();
        if (id != null && name.isNotEmpty) _spotNameById[id] = name;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _checkAdmin() async {
    try {
      final info = await loadUserInfo();
      if (info != null) {
        var role = (info.role ?? '').toLowerCase();
        if (role != 'admin') {
          try {
            final refreshed = await getUserInfoFromServer(
              uuid: info.uuid,
              email: null,
            );
            role = (refreshed.role ?? role).toLowerCase();
            // 保存しておく（他画面でも反映）
            final updated = info.copyWith(
              userId: refreshed.userId,
              email: refreshed.email,
              uuid: info.uuid,
              status: refreshed.status,
              createdAt: refreshed.createdAt,
              nickName: refreshed.nickName ?? info.nickName,
              reportsBlocked: refreshed.reportsBlocked,
              reportsBlockedUntil: refreshed.reportsBlockedUntil,
              reportsBlockedReason: refreshed.reportsBlockedReason,
              postsBlocked: refreshed.postsBlocked,
              postsBlockedUntil: refreshed.postsBlockedUntil,
              postsBlockedReason: refreshed.postsBlockedReason,
              role: role,
              canReport: refreshed.canReport,
              clearReportsBlockedUntil: refreshed.reportsBlockedUntil == null,
              clearReportsBlockedReason: refreshed.reportsBlockedReason == null,
              clearPostsBlockedUntil: refreshed.postsBlockedUntil == null,
              clearPostsBlockedReason: refreshed.postsBlockedReason == null,
            );
            await saveUserInfo(updated);
          } catch (_) {}
        }
        if (role == 'admin' && mounted) setState(() => _isAdmin = true);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('釣果'),
        backgroundColor: AppConfig.instance.appBarBackgroundColor,
        foregroundColor: AppConfig.instance.appBarForegroundColor,
        toolbarHeight: 0,
      ),
      body: Column(
        children: [
          Container(
            height: kToolbarHeight,
            color: AppConfig.instance.appBarBackgroundColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '🐟',
                          style: TextStyle(
                            fontSize: 20,
                            color: AppConfig.instance.appBarForegroundColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '釣果',
                          style: TextStyle(
                            color: AppConfig.instance.appBarForegroundColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilterChip(
                      showCheckmark: false,
                      selected: Common.instance.fishingDiaryMode,
                      onSelected: (v) async {
                        if (v) {
                          final verified = await _ensureEmailVerified();
                          if (!verified) return;
                          if (!mounted) return;
                          final ok = await Common.instance
                              .confirmEnableFishingDiary(context);
                          if (!ok) return;
                        }
                        await Common.instance.setFishingDiaryMode(v);
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(
                        horizontal: -2.5,
                        vertical: -2,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      avatarBoxConstraints: const BoxConstraints.tightFor(
                        width: 18,
                        height: 18,
                      ),
                      avatar: Icon(
                        Icons.menu_book,
                        size: 14,
                        color:
                            Common.instance.fishingDiaryMode
                                ? Colors.white
                                : Colors.black87,
                      ),
                      label: Text(
                        '釣り日記',
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              Common.instance.fishingDiaryMode
                                  ? Colors.white
                                  : Colors.black87,
                        ),
                      ),
                      backgroundColor: Colors.white,
                      selectedColor: const Color(0xFFFFB74D),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child:
                !_metaReady
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                      children: [
                        Container(
                          color: Colors.white,
                          child: TabBar(
                            controller: _tabController,
                            tabs: [
                              Tab(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.photo_library_outlined,
                                      size: 18,
                                    ),
                                    SizedBox(width: 6),
                                    Text('ギャラリー'),
                                  ],
                                ),
                              ),
                              Tab(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.view_list_outlined, size: 18),
                                    SizedBox(width: 6),
                                    Text('一覧'),
                                  ],
                                ),
                              ),
                            ],
                            labelColor: Colors.black87,
                            indicatorColor: Colors.black87,
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              RefreshIndicator(
                                onRefresh: _loadFirst,
                                child: _buildGalleryTab(context),
                              ),
                              RefreshIndicator(
                                onRefresh: _loadListFirst,
                                child: _buildListTab(context),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryTab(BuildContext context) {
    if (_items.isEmpty && !_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: kScrollableContentBottomPadding),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('釣果が取得できませんでした。下に引っ張って更新してください。')),
        ],
      );
    }
    final width = MediaQuery.of(context).size.width;
    const double pad = 8;
    const double gap = 4;
    final double cell = (width - pad * 2 - gap * 2) / 3.0;
    final groups = <_MosaicGroup>[];
    int i = 0;
    int prev = 0;
    int? forceNext;
    final rng = math.Random(_items.length + _page);
    while (i < _items.length) {
      final remain = _items.length - i;
      int pattern;
      if (i == 0) {
        pattern = (remain >= 3) ? 2 : 4;
      } else if (forceNext != null) {
        pattern = forceNext!;
        forceNext = null;
      } else {
        final viable = <int>[];
        if (remain >= 3) {
          viable.addAll([2, 3, 4]);
        } else {
          viable.addAll([4]);
        }
        final candidates = viable.where((p) => p != prev).toList();
        if (candidates.isEmpty) {
          pattern = 4;
        } else {
          pattern = candidates[rng.nextInt(candidates.length)];
          if ((pattern == 2 || pattern == 3) && remain < 3) {
            pattern = 4;
          }
        }
      }
      final need = math.min(3, remain);
      final slice = _items.sublist(i, i + need);
      groups.add(_MosaicGroup(pattern: pattern, items: slice));
      i += need;
      if ((pattern == 2 || pattern == 3) && i < _items.length) {
        forceNext = 4;
        prev = 4;
      } else {
        prev = pattern;
      }
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _maybeLoadMoreFromScroll(notification.metrics);
        return false;
      },
      child: ListView.builder(
        controller: _sc,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          pad,
          pad,
          pad,
          kScrollableContentBottomPadding,
        ),
        itemCount: groups.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, gi) {
          if (gi >= groups.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final g = groups[gi];
          return _buildGroup(g, cell, gap);
        },
      ),
    );
  }

  Widget _buildListTab(BuildContext context) {
    final notificationPostId = Common.instance.latestCatchNotificationPostId;
    if (_listItems.isEmpty && !_listLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: kScrollableContentBottomPadding),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('釣果が取得できませんでした。下に引っ張って更新してください。')),
        ],
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _maybeLoadListMoreFromScroll(notification.metrics);
        return false;
      },
      child: ListView.builder(
        controller: _listSc,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: kScrollableContentBottomPadding),
        itemCount:
            _listItems.length +
            (_listHasMore ? 1 : 0) +
            (notificationPostId != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (notificationPostId != null && index == 0) {
            return InkWell(
              onTap: () => Common.instance.clearCatchNotification(),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFB9D2FF)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notifications_active,
                      color: Color(0xFF1565C0),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Common
                                    .instance
                                    .latestCatchNotificationTitle
                                    .isNotEmpty
                                ? Common.instance.latestCatchNotificationTitle
                                : '新しい釣果通知',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (Common
                              .instance
                              .latestCatchNotificationBody
                              .isNotEmpty)
                            Text(
                              Common.instance.latestCatchNotificationBody,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final listIndex = index - (notificationPostId != null ? 1 : 0);
          if (listIndex >= _listItems.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final it = _listItems[listIndex];
          final thumb = it.thumbUrl ?? it.imageUrl;
          final isMine = _myUserId != null && it.userId == _myUserId;
          final adminMeta = _adminPostMeta(it);
          final isNotified =
              notificationPostId != null && it.postId == notificationPostId;
          return Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: isNotified ? const Color(0xFFFFF7CC) : null,
                  border: Border(
                    left: BorderSide(
                      color:
                          isMine
                              ? const Color(0xFFFFB74D)
                              : const Color(0xFFBDBDBD),
                      width: 8,
                    ),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.only(left: 12, right: 16),
                  leading:
                      (thumb != null)
                          ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              _withTs(thumb, it.postId),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                          )
                          : const Icon(
                            Icons.image,
                            size: 40,
                            color: Colors.black38,
                          ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          it.title?.isNotEmpty == true
                              ? it.title!
                              : (it.nickName ?? '投稿'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (adminMeta.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            adminMeta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Row(
                    children: [
                      Expanded(
                        child:
                            it.detail?.isNotEmpty == true
                                ? Text(
                                  it.detail!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                                : const SizedBox.shrink(),
                      ),
                      if ((it.createAt ?? '').isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          it.createAt!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ],
                  ),
                  onTap: () async {
                    Common.instance.clearCatchNotification();
                    final String? detailRaw = it.imageUrl ?? it.thumbUrl;
                    final String? detailUrl =
                        (detailRaw != null)
                            ? _withTs(detailRaw, it.postId)
                            : null;
                    final updated = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => PostDetailPage(
                              item: PostDetailItem(
                                userId: it.userId,
                                postId: it.postId,
                                postKind: it.postKind,
                                exist: it.exist,
                                title: it.title,
                                detail: it.detail,
                                imageUrl: detailUrl,
                                nickName: it.nickName,
                                createAt: it.createAt,
                                spotId: it.spotId,
                                showNearbyButton: true,
                              ),
                            ),
                      ),
                    );
                    if (!mounted) return;
                    if (updated == true && it.postId != null) {
                      final ts =
                          DateTime.now().millisecondsSinceEpoch.toString();
                      setState(() {
                        _imgTsByPost[it.postId!] = ts;
                      });
                      _saveImageTs(it.postId!, ts);
                    } else if (updated is Map) {
                      final u = (updated['updated'] == true);
                      final cleared = (updated['clearedImage'] == true);
                      final deleted = (updated['deleted'] == true);
                      final pid =
                          updated['postId'] is int
                              ? updated['postId'] as int
                              : (updated['postId'] is String
                                  ? int.tryParse(updated['postId'])
                                  : null);
                      if (deleted && pid != null) {
                        setState(() {
                          _listItems.removeWhere((e) => e.postId == pid);
                          _items.removeWhere((e) => e.postId == pid);
                          _imgTsByPost.remove(pid);
                        });
                        _removeImageTs(pid);
                        return;
                      }
                      if (u && cleared && pid != null) {
                        setState(() {
                          _items.removeWhere((e) => e.postId == pid);
                          _imgTsByPost.remove(pid);
                        });
                        _removeImageTs(pid);
                      } else if (u && pid != null) {
                        final ts =
                            DateTime.now().millisecondsSinceEpoch.toString();
                        setState(() {
                          _imgTsByPost[pid] = ts;
                        });
                        _saveImageTs(pid, ts);
                      }
                    }
                  },
                ),
              ),
              const Divider(height: 1),
            ],
          );
        },
      ),
    );
  }
}

class _PostGridItem {
  final int? postId;
  final int? userId;
  final int? spotId;
  final int? postKind;
  final int? exist;
  final String? title;
  final String? detail;
  final String? imagePath;
  final String? thumbPath;
  final String? nickName;
  final String? createAt;
  final String baseUrl;
  _PostGridItem({
    this.postId,
    this.userId,
    this.spotId,
    this.postKind,
    this.exist,
    this.title,
    this.detail,
    this.imagePath,
    this.thumbPath,
    this.nickName,
    this.createAt,
    required this.baseUrl,
  });
  String? get imageUrl {
    if (imagePath == null) return null;
    final rel = imagePath!;
    if (rel.startsWith('http')) return rel;
    return baseUrl + 'post_images/' + rel;
  }

  String? get thumbUrl {
    if (thumbPath == null) return null;
    final rel = thumbPath!;
    if (rel.startsWith('http')) return rel;
    return baseUrl + 'post_images/' + rel;
  }

  factory _PostGridItem.fromJson(Map<String, dynamic> j, String baseUrl) {
    int? toInt(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '');
    String? s(dynamic v) => v?.toString();
    return _PostGridItem(
      postId: toInt(j['post_id']),
      userId: toInt(j['user_id']),
      spotId: toInt(j['spot_id']),
      postKind: toInt(j['post_kind']),
      exist: toInt(j['exist']),
      title: s(j['title']),
      detail: s(j['detail']),
      imagePath: s(j['image_path']),
      thumbPath: s(j['thumb_path']),
      nickName: s(j['nick_name']) ?? s(j['nickname']) ?? s(j['nickName']),
      createAt: s(j['create_at']),
      baseUrl: baseUrl,
    );
  }
}

class _MosaicGroup {
  final int pattern; // 2..4
  final List<_PostGridItem> items;
  _MosaicGroup({required this.pattern, required this.items});
}

class _FetchResult {
  final List<_PostGridItem> items;
  final int rawCount;
  const _FetchResult({required this.items, required this.rawCount});
}

extension _MosaicBuilders on _FishingResultGridState {
  static const _kTsStorageKey = 'post_img_ts_map_v1';

  Future<void> _loadImageTsMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kTsStorageKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((k, v) {
        final id = int.tryParse(k);
        final ts = v?.toString();
        if (id != null && ts != null && ts.isNotEmpty) {
          _imgTsByPost[id] = ts;
        }
      });
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveImageTs(int postId, String ts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 既存マップを読み取り
      Map<String, dynamic> map = {};
      final raw = prefs.getString(_kTsStorageKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          map = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      }
      map[postId.toString()] = ts;
      await prefs.setString(_kTsStorageKey, jsonEncode(map));
    } catch (_) {}
  }

  Future<void> _removeImageTs(int postId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> map = {};
      final raw = prefs.getString(_kTsStorageKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          map = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      }
      map.remove(postId.toString());
      await prefs.setString(_kTsStorageKey, jsonEncode(map));
    } catch (_) {}
  }

  String _withTs(String url, int? postId) {
    if (postId != null) {
      final ts = _imgTsByPost[postId];
      if (ts != null && ts.isNotEmpty) {
        final sep = url.contains('?') ? '&' : '?';
        return '$url${sep}ts=$ts';
      }
    }
    return url;
  }

  String _adminPostMeta(_PostGridItem it) {
    if (!_isAdmin) return '';
    final userId = it.userId?.toString() ?? '';
    final spotText =
        it.spotId != null
            ? ((_spotNameById[it.spotId!] ?? '').isNotEmpty
                ? _spotNameById[it.spotId!]!
                : it.spotId!.toString())
            : '';
    final parts = <String>[];
    if (userId.isNotEmpty) parts.add('user_id:$userId');
    if (spotText.isNotEmpty) parts.add('spot:$spotText');
    return parts.join(', ');
  }

  Widget _buildTile(
    _PostGridItem it,
    double left,
    double top,
    double w,
    double h,
  ) {
    final String? rawUrl = it.thumbUrl ?? it.imageUrl;
    final url = (rawUrl != null) ? _withTs(rawUrl, it.postId) : null;
    String topLabel = '';
    if (it.spotId != null) {
      final s = it.spotId!.toString();
      if (s.length >= 2) {
        final pid = int.tryParse(s.substring(0, 2));
        if (pid != null && _prefNameById.containsKey(pid))
          topLabel = _prefNameById[pid]!;
      }
    }
    final bottomLabel = it.nickName ?? '';
    final isMine = _myUserId != null && it.userId == _myUserId;
    final bool canShowSpotName = (ambiguousLevel == 0) || _isAdmin;
    final String? spotName =
        (it.spotId != null) ? _spotNameById[it.spotId] : null;
    final String combinedTopLabel = () {
      String s = '';
      if (topLabel.isNotEmpty) s = topLabel;
      if (canShowSpotName && spotName != null && spotName.isNotEmpty) {
        s = s.isEmpty ? spotName! : '$s $spotName';
      }
      return s;
    }();
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: InkWell(
        onTap: () async {
          final String? detailUrlRaw = it.imageUrl ?? it.thumbUrl;
          final String? detailUrl =
              (detailUrlRaw != null) ? _withTs(detailUrlRaw, it.postId) : null;
          final updated = await Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => PostDetailPage(
                    item: PostDetailItem(
                      userId: it.userId,
                      postId: it.postId,
                      postKind: it.postKind,
                      exist: it.exist,
                      title: it.title,
                      detail: it.detail,
                      imageUrl: detailUrl,
                      nickName: it.nickName,
                      createAt: it.createAt,
                      spotId: it.spotId,
                      showNearbyButton: true,
                    ),
                  ),
            ),
          );
          if (!mounted) return;
          if (updated == true && it.postId != null) {
            final ts = DateTime.now().millisecondsSinceEpoch.toString();
            setState(() {
              _imgTsByPost[it.postId!] = ts;
            });
            _saveImageTs(it.postId!, ts);
          } else if (updated is Map) {
            final u = (updated['updated'] == true);
            final cleared = (updated['clearedImage'] == true);
            final deleted = (updated['deleted'] == true);
            final pid =
                updated['postId'] is int
                    ? updated['postId'] as int
                    : (updated['postId'] is String
                        ? int.tryParse(updated['postId'])
                        : null);
            if (deleted && pid != null) {
              setState(() {
                _items.removeWhere((e) => e.postId == pid);
                _imgTsByPost.remove(pid);
              });
              _removeImageTs(pid);
              return;
            }
            if (u && cleared && pid != null) {
              // 画像が消された場合はグリッドからも項目を外す
              setState(() {
                _items.removeWhere((e) => e.postId == pid);
                _imgTsByPost.remove(pid);
              });
              // 永続側からも削除
              _removeImageTs(pid);
            } else if (u && pid != null) {
              final ts = DateTime.now().millisecondsSinceEpoch.toString();
              setState(() {
                _imgTsByPost[pid] = ts;
              });
              _saveImageTs(pid, ts);
            }
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              url != null
                  ? Image.network(url, fit: BoxFit.cover)
                  : const ColoredBox(color: Colors.black12),
              // 上部ラベル行（都道府県 + 釣り場名を半角スペース区切りで1つのラベルに）
              if (isMine)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB74D),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
              if (combinedTopLabel.isNotEmpty)
                Positioned(
                  top: 4,
                  left: isMine ? 44 : 4,
                  right: 4,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        combinedTopLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              if (bottomLabel.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 6,
                    ),
                    color: Colors.black45,
                    child: Text(
                      bottomLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroup(_MosaicGroup g, double cell, double gap) {
    final tiles = <Widget>[];
    double height;
    switch (g.pattern) {
      case 2:
        height = cell * 2 + gap;
        tiles.add(_buildTile(g.items[0], 0, 0, cell * 2 + gap, height));
        tiles.add(
          _buildTile(
            g.items.length > 1 ? g.items[1] : g.items[0],
            cell * 2 + gap * 2,
            0,
            cell,
            cell,
          ),
        );
        if (g.items.length > 2) {
          tiles.add(
            _buildTile(g.items[2], cell * 2 + gap * 2, cell + gap, cell, cell),
          );
        }
        break;
      case 3:
        height = cell * 2 + gap;
        tiles.add(_buildTile(g.items[0], 0, 0, cell, cell));
        tiles.add(
          _buildTile(
            g.items.length > 1 ? g.items[1] : g.items[0],
            0,
            cell + gap,
            cell,
            cell,
          ),
        );
        tiles.add(
          _buildTile(
            g.items.length > 2 ? g.items[2] : g.items[0],
            cell + gap,
            0,
            cell * 2 + gap,
            height,
          ),
        );
        break;
      default:
        height = cell;
        for (var i = 0; i < g.items.length; i++) {
          final x = i * (cell + gap);
          tiles.add(_buildTile(g.items[i], x, 0, cell, cell));
        }
    }
    final totalWidth = cell * 3 + gap * 2;
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: SizedBox(
        width: totalWidth,
        height: height,
        child: Stack(children: tiles),
      ),
    );
  }
}
