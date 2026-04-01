import 'package:flutter/material.dart';
import 'common.dart';

class SetDatePage extends StatefulWidget {
  SetDatePage({Key? key}) : super(key: key);

  @override
  SetDatePageState createState() => SetDatePageState();
}

class SetDatePageState extends State<SetDatePage> {
  // 基準日（初期状態の選択日）
  DateTime _baseDate = Common.instance.tideDate;
  // 表示中の月（基準日からのオフセットにより算出）
  DateTime _displayedMonth = Common.instance.tideDate;
  // PageView の初期ページインデックス（十分大きな数で中央付近に設定）
  static const int _initialPage = 500;
  late PageController _pageController;
  int _currentPage = _initialPage;

  @override
  void initState() {
    super.initState();
    _displayedMonth = _baseDate;
    _pageController = PageController(initialPage: _initialPage);
    // 初回の潮汐データ取得
    Common.instance.getTide(false, _displayedMonth);
  }

  /// 指定した日付に対して、offset ヶ月後の日付を返す（Dart の DateTime は month が範囲外の場合に補正してくれる）
  DateTime _addMonths(DateTime date, int offset) {
    return DateTime(date.year, date.month + offset, 1);
  }

  /// PageView のページが変わったときのコールバック
  /* 対策 1.
  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
      int monthOffset = _currentPage - _initialPage;
      _displayedMonth = _addMonths(_baseDate, monthOffset);
      //print('月潮汐取得 at _onPageChanged: $_displayedMonth');
      Common.instance.getTide(false, _displayedMonth);
    });
  }
*/
// 例：月切り替え時
Future<void> _onPageChanged(int index) async {
  int monthOffset = index - _initialPage;
  DateTime newMonth = _addMonths(_baseDate, monthOffset);

  // 1) データ取得完了まで待つ
  await Common.instance.getTide(false, newMonth);

  // 2) 完了したら画面更新
  setState(() {
    _currentPage    = index;
    _displayedMonth = newMonth;
  });
}
  /// 矢印ボタンから前の月に移動
  void _goToPreviousMonth() {
    _pageController.previousPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// 矢印ボタンから次の月に移動
  void _goToNextMonth() {
    _pageController.nextPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// 指定された月のカレンダーウィジェットを生成
  Widget _buildCalendarPage(DateTime month) {
    List<Widget> dayWidgets = [];

    // 曜日ヘッダー（Sun～Sat）
    const List<String> daysOfWeek = ['日', '月', '火', '水', '木', '金', '土'];
    for (var day in daysOfWeek) {
      dayWidgets.add(
        Container(
          alignment: Alignment.center,
          child: Text(day, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
    }

    // 今月の初日を取得
    DateTime firstDayOfMonth = DateTime(month.year, month.month, 1);
    // 曜日(weekday)を調整（月曜=1～日曜=7）し、先頭の空セルの数を決定
    int emptyCells = firstDayOfMonth.weekday % 7;
    for (int i = 0; i < emptyCells; i++) {
      dayWidgets.add(Container());
    }

    // 今月の日数を取得
    int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    for (int day = 1; day <= daysInMonth; day++) {
      DateTime currentDate = DateTime(month.year, month.month, day);
      bool isSelected =
          currentDate.year == Common.instance.tideDate.year &&
          currentDate.month == Common.instance.tideDate.month &&
          currentDate.day == Common.instance.tideDate.day;

      // getSio() の戻り値を取得
      String sioValue = Common.instance.getSio(
        currentDate.month,
        currentDate.day,
      );
      // 月齢(0から28)を取得
      int geturei = Common.instance.getGeturei(
        currentDate.month,
        currentDate.day,
      );
      String no = geturei.toString().padLeft(2, '0');
      String fileSmallMoonPath = 'assets/moon/moon_s_$no.jpg';

      dayWidgets.add(
        GestureDetector(
          onTap: () async {
            Common.instance.tideDate = currentDate;
            //print('SetPage onTap ${currentDate.month}/${currentDate.day}');
            setState(() {
              Common.instance.shouldJumpPage = true;
              Common.instance.notify();
            });
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isSelected)
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red, width: 2),
                  ),
                ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    day.toString(),
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                  ),
                  Opacity(
                    opacity: 1.0,
                    child: Image.asset(
                      fileSmallMoonPath,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Text(
                    sioValue,
                    style: TextStyle(
                      fontSize: 12,
                      color: sioValue == '大潮' ? Colors.red : Colors.black,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // GridView のスクロールは PageView に任せるため、内部のスクロールは無効にする
    // available な高さに合わせて childAspectRatio を計算する
    return LayoutBuilder(
      builder: (context, constraints) {
        // 総セル数から必要な行数を計算
        final int totalCells = dayWidgets.length;
        final int rows = (totalCells  / 7).ceil();

        // 1セルあたりの幅／高さを計算
        final double tileWidth  = constraints.maxWidth  / 7;
        final double tileHeight = constraints.maxHeight / rows;
        final double aspectRatio = tileWidth / tileHeight;

        return GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(8.0),
          crossAxisCount: 7,
          childAspectRatio: aspectRatio,
          children: dayWidgets,
        );
      },
    );
  }

  /// 日付の更新処理（オプション）
/*  対策1. 
  void refreshDate() async {
    setState(() {
      _baseDate = Common.instance.tideDate;
      _displayedMonth = _baseDate;
      //print('月潮汐取得 at refresh: $_displayedMonth');
      Common.instance.getTide(false, _displayedMonth);
      _pageController.jumpToPage(_initialPage);
      _currentPage = _initialPage;
    });
  }*/

Future<void> refreshDate() async {
  DateTime newBase  = Common.instance.tideDate;
  DateTime newMonth = DateTime(newBase.year, newBase.month, 1);

  // データ更新を待ってから
  await Common.instance.getTide(false, newMonth);

  setState(() {
    _baseDate      = newBase;
    _displayedMonth= newMonth;
    _currentPage   = _initialPage;
    _pageController.jumpToPage(_initialPage);
  });
}

  @override
  Widget build(BuildContext context) {
    String monthYear =
        "${_displayedMonth.year} / ${_displayedMonth.month.toString().padLeft(2, '0')}";

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.date_range, color: Colors.white),
            SizedBox(width: 8),
            Text('日付'),
          ],
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton(
              onPressed: () {
                // 必要に応じて、本日の日付にジャンプするなどの処理を追加してください
                Common.instance.tideDate = DateTime.now();

                setState(() {
                  _baseDate = Common.instance.tideDate;
                  _displayedMonth = _baseDate;
                  //print('月潮汐取得 at refresh: $_displayedMonth');
                  Common.instance.getTide(false, _displayedMonth);
                  _pageController.jumpToPage(_initialPage);
                  _currentPage = _initialPage;
                  Common.instance.shouldJumpPage = true;
                  Common.instance.notify();
                });
              },
              child: const Text('本日'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade200, // 背景色を指定（例）
                foregroundColor: Colors.black, // テキスト色
                elevation: 2.0, // 影の強さ
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8), // 角丸にする
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 上部ナビゲーション（矢印ボタンと年月表示）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_left),
                onPressed: _goToPreviousMonth,
              ),
              Text(
                monthYear,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_right),
                onPressed: _goToNextMonth,
              ),
            ],
          ),
          // PageView.builder を利用し、スワイプで前後の月へ移動可能とする
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                int monthOffset = index - _initialPage;
                DateTime pageMonth = _addMonths(_baseDate, monthOffset);
                return _buildCalendarPage(pageMonth);
              },
            ),
          ),
        ],
      ),
    );
  }
}
