class Sio {
  Sio._privateConstructor();

  // 唯一のインスタンスを生成して保持する静的フィールド
  static final Sio _instance = Sio._privateConstructor();

  // グローバルアクセサ
  static Sio get instance => _instance;

  // 潮汐表示日
  String dispTideDate = "";

  // 大潮、中潮、小潮など
  String sioName = "";
  // 日出
  String sunRiseTime = "";
  // 日入
  String sunSetTime = "";

  // 4. 高潮・低潮時刻の初期化
  String highTideTime1 = "";
  String highTideTime2 = "";
  String lowTideTime1 = "";
  String lowTideTime2 = "";
}
