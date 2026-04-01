class SunPoint {
  // 時
  double hh = 0.0;
  // 分
  double mm = 0.0;

  SunPoint({required this.hh, required this.mm});
}

class SioPoint {
  // 満潮=1, 干潮=0
  int flag = 0;
  // 潮高
  double tide = 0.0;
  // 時
  double hh = 0.0;
  // 分
  double mm = 0.0;
}

class SioInfo {
  static final int sample_cnt = 73;
  // 入力
  int inYear = 0;
  int inMonth = 0;
  int inDay = 0;

  // 出力
  int weekday = 0;
  String portName = "";
  //String ido = "";      // 緯度（文字列）
  //String keido = "";    // 経度（文字列）
  double lat = 0.0;
  double lang = 0.0;

  String sio = ""; // 潮（文字列）

  // 平均水面、月齢、月輝面
  double average = 0.0;
  double age = 0.0;
  double ilum = 0.0;

  // 日出
  String sunrise = "";
  SunPoint pSunRise = SunPoint(hh: 0.0, mm: 0.0);

  // 日没
  String sunset = "";
  SunPoint pSunSet = SunPoint(hh: 0.0, mm: 0.0);

  // 月出、月入
  String moonOut = "";
  String moonIn = "";

  // 潮汐1日情報（最大73件）
  List<SioPoint> dayTide = List.generate(sample_cnt, (_) => SioPoint());
  int dayTideCnt = 0;

  // 満潮、干潮（最大4件）
  List<SioPoint> peakTide = List.generate(4, (_) => SioPoint());
  int peakTideCnt = 0;

  SioInfo();
}

class SioSummaryDayInfo {
  // flag
  int flag = 0;

  // 年
  int year = 0;
  // 月
  int month = 0;
  // 日
  int day = 0;
  // 曜日
  int weekday = 0;

  // 月齢
  double age = 0.0;
  int age2 = 0;

  // 月輝面
  double ilum = 0.0;

  // 潮
  String sio = "";
}

class SioMonthInfo {
  // 入力
  int inYear = 0;
  int inMonth = 0;

  // 指定月の日数
  int daycnt = 0;

  // １ヶ月分の潮
  final List<SioSummaryDayInfo> sioSummaryDayInfo = List.generate(
    31,
    (index) => SioSummaryDayInfo(),
  );
}

class Sio3MonthInfo {
  int infoCnt = 0;
  final List<SioSummaryDayInfo> sioSummaryDayInfo = List.generate(
    31 * 3,
    (index) => SioSummaryDayInfo(),
  );
}
