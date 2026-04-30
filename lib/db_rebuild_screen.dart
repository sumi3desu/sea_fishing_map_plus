import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
//import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'providers/premium_state_notifier.dart' as prem;
import 'sio_database.dart';
import 'sync_service.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'pin_cache_utils.dart';
// import 'cache_question_repository.dart';

class DbRebuildScreen extends ConsumerStatefulWidget {
  const DbRebuildScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DbRebuildScreen> createState() => _DbRebuildScreenState();
}

class _DbRebuildScreenState extends ConsumerState<DbRebuildScreen> {
  BannerAd? _bannerAd;
  bool _loading = false; // 全体ロード中
  bool _fetching = false; // 最新データの確認中
  Map<String, int> _local = {};
  Map<String, int> _remote = {};
  String? _error;
  // 釣り場データを構成するテーブル群
  static const List<String> _fishingTables = ['spots', 'kubun', 'todoufuken'];

  @override
  void initState() {
    super.initState();
    _refreshVersions();
    final isPremium = ref.read(prem.premiumStateProvider).isPremium;
    if (!isPremium) {
      _bannerAd = BannerAd(
        size: AdSize.banner,
        adUnitId: 'ca-app-pub-3940256099942544/2934735716',
        listener: BannerAdListener(
          onAdLoaded: (_) => setState(() {}),
          onAdFailedToLoad: (ad, err) {
            ad.dispose();
          },
        ),
        request: const AdRequest(),
      )..load();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadFishing({required bool force}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      final ok = await SioSyncService().syncFishingData(
        userId: info.userId,
        force: force,
      );
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('釣り場データを更新しました')));
        // 一覧側へ更新を通知
        try {
          SioDatabase().notifyListeners();
        } catch (_) {}
      } else {
        final err = SioSyncService().lastError;
        final msg =
            (!kReleaseMode && (err != null && err.isNotEmpty))
                ? '釣り場データの更新に失敗しました（$err）'
                : '釣り場データの更新に失敗しました';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('釣り場データの更新中にエラーが発生しました')));
    } finally {
      await _refreshVersions();
      if (mounted)
        setState(() {
          _loading = false;
        });
    }
  }

  Future<void> _refreshVersions() async {
    setState(() {
      _fetching = true;
      _error = null;
    });
    final startAt = DateTime.now();
    try {
      final loaded = await loadUserInfo();
      final info = loaded ?? await getOrInitUserInfo();
      // ローカルバージョン取得
      final db = await SioDatabase().database;
      final localRows = await db.query(
        'version',
        where: 'user_id = ?',
        whereArgs: [info.userId],
      );
      final local = <String, int>{
        for (final r in localRows) (r['name'] as String): (r['version'] as int),
      };
      // リモートバージョン取得
      final remoteMap = await SioSyncService().fetchRemoteVersionMap(
        userId: info.userId,
      );
      if (remoteMap.isEmpty) {
        if (!mounted) return;
        setState(() {
          _local = local;
          _remote = {};
          _error = '最新データの確認に失敗しました（機内モードや通信環境をご確認ください）';
        });
        // 画面上部の表示に加えて簡易通知
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('最新データの確認に失敗しました。通信環境をご確認のうえ、再度お試しください。'),
          ),
        );
        return;
      }
      setState(() {
        _local = local;
        _remote = remoteMap;
      });
    } catch (e) {
      setState(() {
        _error = '最新データの確認に失敗しました';
      });
    } finally {
      // 最低2秒は「確認中」を維持してチラつきを抑制
      final minDuration = const Duration(seconds: 2);
      final elapsed = DateTime.now().difference(startAt);
      if (elapsed < minDuration) {
        await Future.delayed(minDuration - elapsed);
      }
      if (mounted)
        setState(() {
          _fetching = false;
        });
    }
  }

  // 表示用ラベル（不要になったが将来拡張に備えて残置）
  String labelFor(String name) => name;

  bool _hasFishingVersionDiff() {
    for (final name in _fishingTables) {
      final remoteVersion = _remote[name];
      if (remoteVersion == null) continue;
      if (_local[name] != remoteVersion) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Consumer(
              builder: (context, ref, _) {
                final isPremium =
                    ref.watch(prem.premiumStateProvider).isPremium;
                if (isPremium || _bannerAd == null)
                  return const SizedBox.shrink();
                return Container(
                  alignment: Alignment.center,
                  width: _bannerAd!.size.width.toDouble(),
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                );
              },
            ),
            Container(
              height: kToolbarHeight,
              color: Colors.black,
              child: Row(
                children: [
                  BackButton(
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        '最新データの更新',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoCard(),
                    const SizedBox(height: 12),
                    _fishingTile(),
                    const SizedBox(height: 16),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: MediaQuery.of(context).size.width * 0.7,
                            child: ElevatedButton(
                              onPressed:
                                  (_loading || _fetching)
                                      ? null
                                      : _refreshVersions,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_fetching)
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    else
                                      const Icon(Icons.refresh),
                                    const SizedBox(width: 8),
                                    Text(_fetching ? '確認中…' : '最新データを確認'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          /*SizedBox(
                    width: MediaQuery.of(context).size.width * 0.7,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('戻る'),
                    ),
                  ),*/
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard() {
    return Card(
      elevation: 0,
      color: Colors.grey.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade400),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Builder(
          builder: (_) {
            if (_error != null) {
              return Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!)),
                ],
              );
            }
            return const Text(
              'サーバ上の最新を確認し、更新があればご案内します。Wi-Fi 環境での実行を推奨します（モバイル回線ではデータ通信料が発生する場合があります）。',
              style: TextStyle(color: Colors.black87),
            );
          },
        ),
      ),
    );
  }

  // 指定データ種別の状態を判定
  ({String text, Color color}) _fishingStatus() {
    // リモートが取れない場合
    final remoteVals = _fishingTables.map((t) => _remote[t] ?? -1).toList();
    if (remoteVals.every((v) => v == -1)) {
      return (text: '通信エラー中', color: Colors.red);
    }
    if (_hasFishingVersionDiff()) {
      return (text: '差異あり', color: Colors.orange);
    }
    return (text: '最新です', color: Colors.green);
  }

  Widget _fishingTile() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade400),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '釣り場データ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  // 状態表示（このカードのバージョン表示の上）
                  Builder(
                    builder: (_) {
                      final st = _fishingStatus();
                      return Row(
                        children: [
                          Icon(
                            st.color == Colors.green
                                ? Icons.check_circle
                                : (st.color == Colors.orange
                                    ? Icons.info_outline
                                    : Icons.warning_amber_rounded),
                            color: st.color,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            st.text,
                            style: TextStyle(
                              color: st.color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  // バージョン番号の表示はユーザーには不要なため非表示
                ],
              ),
            ),
            Builder(
              builder: (_) {
                String label = '更新';
                VoidCallback? onTap;
                if (_loading || _fetching) {
                  onTap = null;
                } else {
                  final remoteVals =
                      _fishingTables.map((t) => _remote[t] ?? -1).toList();
                  if (remoteVals.every((v) => v == -1)) {
                    label = '再試行';
                    onTap = _refreshVersions;
                  } else {
                    if (_hasFishingVersionDiff()) {
                      label = '更新する';
                      onTap = () => _loadFishing(force: false);
                    } else {
                      label = '再取得';
                      onTap = () => _loadFishing(force: true);
                    }
                  }
                }
                return ElevatedButton(onPressed: onTap, child: Text(label));
              },
            ),
          ],
        ),
      ),
    );
  }
}
