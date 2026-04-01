
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:sticky_headers/sticky_headers.dart';
import 'package:provider/provider.dart';
import 'sio_info.dart';
import 'common.dart';
import 'location.dart';

class ListPointPage extends StatefulWidget {
  const ListPointPage({super.key});

  @override
  State<ListPointPage> createState() => _ListPointPageState();
}

class _ListPointPageState extends State<ListPointPage> {
  late ScrollController _scrollController;
  bool _showFab = false;

  @override
  void initState() {
    super.initState();

    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);

    // 初期化処理
    init();

    // 初期表示後に選択された行をスクロールする処理
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Common.instance.selectedKey.currentContext != null) {
        Scrollable.ensureVisible(
          Common.instance.selectedKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5,
          curve: Curves.easeInOut,
        );
      }
    });
  }

  // スクロール位置を監視して、一定以上スクロールしたらフローティングボタンを表示
  void _scrollListener() {
    if (_scrollController.offset > 100 && !_showFab) {
      setState(() {
        _showFab = true;
      });
    } else if (_scrollController.offset <= 100 && _showFab) {
      setState(() {
        _showFab = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // グループ化した釣り場一覧ウィジェットの構築
  Widget _buildGroupedList() {
    // 地区ごとにグループ化する
    final Map<String, List<Map<String, String>>> groupedData = {};
    for (var entry in Location.instance.locationData) {
      final String region = entry['region'] as String;
      final String prefecture = entry['prefecture'] as String;
      final List spots = entry['spots'] as List;
      groupedData.putIfAbsent(region, () => []);
      if (spots.isNotEmpty) {
        for (var spot in spots) {
          String name = spot['name'];
          int flag = spot['flag'];
          groupedData[region]!.add({
            'prefecture': prefecture,
            'spot': name,
            'flag': flag.toString(),
          });
        }
      }
    }

    final List<String> regions = groupedData.keys.toList();
    return ListView.builder(
      controller: _scrollController, // ScrollController を設定
      itemCount: regions.length,
      itemBuilder: (context, index) {
        final region = regions[index];
        final rows = groupedData[region]!;
        return StickyHeader(
          header: Container(
            height: 60.0,
            color: Colors.grey.shade300,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Text(
              region,
              style: const TextStyle(color: Colors.black, fontSize: 18),
            ),
          ),
          content: Column(
            children: rows.asMap().entries.map((entry) {
              final idx = entry.key;
              final row = entry.value;
              bool isSelected = row['spot'] == Common.instance.tidePoint;
              return Slidable(
                key: ValueKey('${region}_${row['prefecture']}_${row['spot']}_${row['flag']}_$idx'),
                endActionPane: ActionPane(
                  motion: const DrawerMotion(),
                  extentRatio: 0.4,
                  children: [
                    CustomSlidableAction(
                      onPressed: (context) {
                        if (region == 'お気に入り') {
                          Location.instance.setFavoriteFlag(
                            row['prefecture'].toString(),
                            row['spot'].toString(),
                            0,
                          );
                          Location.instance.removeFavoriteSpot();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('お気に入り解除: [$region] : ${row['spot']}'),
                            ),
                          );
                        } else {
                          Location.instance.setFavoriteFlag(
                            row['prefecture'].toString(),
                            row['spot'].toString(),
                            1,
                          );
                          Location.instance.removeFavoriteSpot();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('お気に入り登録: [$region] : ${row['spot']}'),
                            ),
                          );
                        }
                      },
                      backgroundColor: Colors.amber.shade50,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bookmark,
                            color: Colors.amber,
                            size: 24.0,
                          ),
                        ],
                      ),
                    ),
                    CustomSlidableAction(
                      onPressed: Common.instance.mapKind == MapType.unknown.index
                          ? null
                          : (context) async {
                              String fileName =
                                  Common.instance.getPortFileName(row['spot'].toString());
                              SioInfo sioInfo = SioInfo();
                              await Common.instance.getPortData(fileName, sioInfo);
                              if (Common.instance.mapKind == MapType.googleMaps.index) {
                                Common.instance.openGoogleMaps(sioInfo.lat, sioInfo.lang);
                              } else if (Common.instance.mapKind == MapType.appleMaps.index) {
                                Common.instance.openAppleMaps(sioInfo.lat, sioInfo.lang);
                              }
                            },
                      backgroundColor: Common.instance.mapKind == MapType.unknown.index
                          ? Colors.grey.shade400
                          : Colors.deepOrange.shade100,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.location_pin,
                            color: Common.instance.mapKind == MapType.unknown.index
                                ? Colors.white.withAlpha(64)
                                : Colors.red,
                            size: 28.0,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      Common.instance.tidePoint = row['spot'] as String;
                      Common.instance.shouldJumpPage = true;
                      Common.instance.notify();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.transparent
                          : Colors.transparent,
                      border: isSelected
                          ? Border.all(color: Colors.black, width: 2.0)
                          : Border(
                              bottom: BorderSide(color: Colors.grey.shade300),
                            ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: Text(
                            '${row['prefecture']}',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            row['spot']!,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.red : Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> setAllFavoriteFlag() async {
    List<Map<String, String>> favorites = await Common.instance.sioDb.getFavorite();
    favorites.forEach((row) {
      Location.instance.setFavoriteFlag(
        row['prefecture']!,
        row['point_name']!,
        1,
      );
    });
  }

  Future<void> init() async {
    await setAllFavoriteFlag();
    await Location.instance.addFavorite();
    Common.instance.notify();
  }

  @override
  Widget build(BuildContext context) {
    final common = Provider.of<Common>(context);
    String point = common.tidePoint;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          '一覧 [$point]',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [Expanded(child: _buildGroupedList())],
      ),
      // スクロールして先頭が見えなくなった際に表示するフローティングボタン
  floatingActionButton: _showFab
      ? Padding(
          // 下部の余白をここで調整（例：80ピクセル上げる）
          padding: const EdgeInsets.only(bottom: 40.0),
          child: FloatingActionButton(
              backgroundColor: Colors.grey.shade200,  // ここで色を指定

            onPressed: () {
              _scrollController.animateTo(
                0.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            child: const Icon(Icons.arrow_upward),
          ),
        )
      : null,
  floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
