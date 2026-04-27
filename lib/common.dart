import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'sio_info.dart';
import 'common_class.dart';
import 'lagrange_cal.dart';
import 'sio.dart';
import 'moon_info.dart';
import 'sio_database.dart';
import 'appconfig.dart';
import 'constants.dart';

enum SmartPhoneType { iPhone, android, unknown }

enum MapType { unknown, appleMaps, googleMaps }

class Common extends ChangeNotifier {
  // プライベートコンストラクタ
  Common._privateConstructor();

  // 唯一のインスタンスを生成して保持する静的フィールド
  static final Common _instance = Common._privateConstructor();

  // グローバルアクセサ
  static Common get instance => _instance;

  // 潮汐の表示日
  DateTime _tideDate = DateTime.now();

  DateTime get tideDate => _tideDate;

  set tideDate(DateTime newTideDate) {
    if (tideDate != newTideDate) {
      _tideDate = newTideDate;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  // 潮汐のポイント
  String _tidePoint = "伊東";
  String get tidePoint => _tidePoint;
  set tidePoint(String newPoint) {
    if (_tidePoint != newPoint) {
      _tidePoint = newPoint;
      savePoint(_tidePoint);
      notifyListeners();
    }
  }

  int _mapKind = MapType.appleMaps.index; //openStreetMap.index;
  int get mapKind => _mapKind;
  set mapKind(int newMapKind) {
    if (_mapKind != newMapKind) {
      _mapKind = newMapKind;
      saveMapKind(_mapKind);
      notifyListeners();
    }
  }

  final int unknownIlum = 0;
  final int upIlum = 2;
  final int kagenIlum = 1;
  final int downIlum = -2;
  final int jyougenIlum = -1;

  // 1日潮情報
  SioInfo gSioInfo = SioInfo();

  SioInfo oneDaySioInfo = SioInfo();

  // 2次元配列の初期データ：各要素は [ポイント, ポイント情報ファイル名]
  final List<List<String>> portFileData = const [
    //// 北海道
    ['函館', '01函館'],
    ['吉岡', '01吉岡'],
    ['室蘭', '01室蘭'],
    ['小樽', '01小樽'],
    ['忍路', '01忍路'],
    ['浦河', '01浦河'],
    ['留萌', '01留萌'],
    ['稚内', '01稚内'],
    ['紋別', '01紋別'],
    ['網走', '01網走'],
    ['花咲', '01花咲'],
    ['苫小牧', '01苫小牧'],
    ['釧路', '01釧路'],
    //// 青森県
    ['三厩', '02三厩'],
    ['八戸', '02八戸'],
    ['大湊', '02大湊'],
    ['大畑', '02大畑'],
    ['大間', '02大間'],
    ['小泊', '02小泊'],
    ['小湊', '02小湊'],
    ['尻矢', '02尻矢'],
    ['尻矢崎', '02尻矢崎'],
    ['岩崎', '02岩崎'],
    ['泊', '02泊'],
    ['浅虫', '02浅虫'],
    ['深浦', '02深浦'],
    ['白糠', '02白糠'],
    ['竜飛', '02竜飛'],
    ['竜飛埼', '02竜飛埼'],
    ['茂浦', '02茂浦'],
    ['野辺地', '02野辺地'],
    ['関根浜', '02関根浜'],
    ['青森', '02青森'],
    ['鯵ヶ沢', '02鯵ヶ沢'],
    //// 岩手県
    ['久慈', '03久慈'],
    ['八木', '03八木'],
    ['大船渡', '03大船渡'],
    ['宮古', '03宮古'],
    ['山田', '03山田'],
    ['釜石', '03釜石'],
    //// 宮城県
    ['仙台', '04仙台'],
    ['塩釜仙', '04塩釜仙'],
    ['塩釜港', '04塩釜港'],
    ['女川', '04女川'],
    ['志津川', '04志津川'],
    ['気仙沼', '04気仙沼'],
    ['港橋', '04港橋'],
    ['石巻', '04石巻'],
    ['石浜', '04石浜'],
    ['船越湾', '04船越湾'],
    ['花淵浜', '04花淵浜'],
    ['荻浜', '04荻浜'],
    ['野蒜湾', '04野蒜湾'],
    ['閖上', '04閖上'],
    ['鮎川', '04鮎川'],
    //// 秋田県
    ['岩舘', '05岩舘'],
    ['男鹿', '05男鹿'],
    ['秋田', '05秋田'],
    ['金浦', '05金浦'],
    //// 山形県
    ['加茂', '06加茂'],
    ['由良', '06由良'],
    ['酒田', '06酒田'],
    ['鼠ヶ関', '06鼠ヶ関'],
    //// 福島県
    ['四倉', '07四倉'],
    ['夫沢', '07夫沢'],
    ['富岡', '07富岡'],
    ['小名浜', '07小名浜'],
    ['松川浦', '07松川浦'],
    ['相馬', '07相馬'],
    //// 茨城県
    ['大洗', '08大洗'],
    ['大津', '08大津'],
    ['日立', '08日立'],
    ['那珂湊', '08那珂湊'],
    ['鹿島', '08鹿島'],
    //// 千葉県
    ['一海堡', '12一海堡'],
    ['上総勝', '12上総勝'],
    ['勝浦', '12勝浦'],
    ['千葉灯', '12千葉灯'],
    ['名洗', '12名洗'],
    ['君津', '12君津'],
    ['姉崎', '12姉崎'],
    ['寒川', '12寒川'],
    ['岩井袋', '12岩井袋'],
    ['市原', '12市原'],
    ['市川', '12市川'],
    ['布良', '12布良'],
    ['犬吠崎', '12犬吠崎'],
    ['白浜', '12白浜'],
    ['船橋', '12船橋'],
    ['銚子', '12銚子'],
    ['銚子新', '12銚子新'],
    ['銚子港', '12銚子港'],
    ['館山', '12館山'],
    ['鴨川', '12鴨川'],
    //// 東京都
    ['三宅島', '13三宅島'],
    ['二見', '13二見'],
    ['八重根', '13八重根'],
    ['岡田', '13岡田'],
    ['式根島', '13式根島'],
    ['晴海', '13晴海'],
    ['母島', '13母島'],
    ['波浮', '13波浮'],
    ['父島', '13父島'],
    ['硫黄島', '13硫黄島'],
    ['神津島', '13神津島'],
    ['神湊', '13神湊'],
    ['築地', '13築地'],
    ['羽田', '13羽田'],
    ['芝浦', '13芝浦'],
    ['阿古', '13阿古'],
    ['鳥島', '13鳥島'],
    //// 神奈川県
    ['向ヶ崎', '14向ヶ崎'],
    ['塩浜運', '14塩浜運'],
    ['小田和', '14小田和'],
    ['川崎', '14川崎'],
    ['新宿湾', '14新宿湾'],
    ['新山下', '14新山下'],
    ['新港', '14新港'],
    ['末広', '14末広'],
    ['根岸', '14根岸'],
    ['横浜', '14横浜'],
    ['横浜新', '14横浜新'],
    ['横須賀', '14横須賀'],
    ['江ノ島', '14江ノ島'],
    ['油壷', '14油壷'],
    ['真鶴', '14真鶴'],
    ['走水', '14走水'],
    ['金田湾', '14金田湾'],
    ['長浦', '14長浦'],
    ['間口', '14間口'],
    //// 新潟県
    ['小木', '15小木'],
    ['新潟東', '15新潟東'],
    ['新潟西', '15新潟西'],
    ['柏崎', '15柏崎'],
    ['直江津', '15直江津'],
    ['粟島', '15粟島'],
    ['能生', '15能生'],
    //// 富山県
    ['伏木', '16伏木'],
    ['富山', '16富山'],
    //// 石川県
    ['輪島', '17輪島'],
    ['金沢', '17金沢'],
    //// 福井県
    ['三国', '18三国'],
    ['内浦湾', '18内浦湾'],
    ['小浜', '18小浜'],
    ['敦賀', '18敦賀'],
    ['福井', '18福井'],
    //// 静岡県
    ['三保', '22三保'],
    ['三津', '22三津'],
    ['伊東', '22伊東'],
    ['南伊豆', '22南伊豆'],
    ['妻良', '22妻良'],
    ['宇久須', '22宇久須'],
    ['川奈', '22川奈'],
    ['御前崎', '22御前崎'],
    ['御津', '22御津'],
    ['江ノ浦', '22江ノ浦'],
    ['清水', '22清水'],
    ['焼津', '22焼津'],
    ['田子', '22田子'],
    ['田子浦', '22田子浦'],
    ['白浜', '22白浜'],
    ['相良', '22相良'],
    ['網代', '22網代'],
    ['興津', '22興津'],
    ['舞阪', '22舞阪'],
    //// 愛知県
    ['伊良胡', '23伊良胡'],
    ['名古屋', '23名古屋'],
    ['師崎', '23師崎'],
    ['武豊', '23武豊'],
    ['神島', '23神島'],
    ['蒲郡', '23蒲郡'],
    ['豊橋', '23豊橋'],
    ['赤羽', '23赤羽'],
    ['赤羽根', '23赤羽根'],
    ['鬼崎', '23鬼崎'],
    //// 三重県
    ['五ヵ所', '24五ヵ所'],
    ['四日市', '24四日市'],
    ['尾鷲', '24尾鷲'],
    ['松阪', '24松阪'],
    ['的矢', '24的矢'],
    ['長島', '24長島'],
    ['鳥羽', '24鳥羽'],
    //// 京都府
    ['島崎', '26島崎'],
    ['舞鶴東', '26舞鶴東'],
    ['舞鶴西', '26舞鶴西'],
    //// 大阪府
    ['堺', '27堺'],
    ['大阪', '27大阪'],
    ['岸和田', '27岸和田'],
    ['泉大津', '27泉大津'],
    ['淡輪', '27淡輪'],
    //// 兵庫県
    ['垂水', '28垂水'],
    ['室津', '28室津'],
    ['家島', '28家島'],
    ['尼崎', '28尼崎'],
    ['岩屋', '28岩屋'],
    ['明石', '28明石'],
    ['江井', '28江井'],
    ['江崎', '28江崎'],
    ['洲本', '28洲本'],
    ['由良', '28由良'],
    ['神戸', '28神戸'],
    ['福良', '28福良'],
    ['飾磨', '28飾磨'],
    ['高砂', '28高砂'],
    //// 和歌山県
    ['下津', '30下津'],
    ['串本', '30串本'],
    ['和歌山', '30和歌山'],
    ['沖ノ島', '30沖ノ島'],
    ['浦神', '30浦神'],
    ['海南', '30海南'],
    ['田辺', '30田辺'],
    //// 鳥取県
    ['境', '31境'],
    ['田後', '31田後'],
    //// 島根県
    ['外ノ浦', '32外ノ浦'],
    ['西郷', '32西郷'],
    //// 岡山県
    ['宇野', '33宇野'],
    ['水島', '33水島'],
    ['笠岡', '33笠岡'],
    //// 広島県
    ['厳島', '34厳島'],
    ['呉', '34呉'],
    ['尾道', '34尾道'],
    ['広島', '34広島'],
    ['福山', '34福山'],
    ['竹原', '34竹原'],
    ['糸崎', '34糸崎'],
    //// 山口県
    ['三田尻', '35三田尻'],
    ['上の関', '35上の関'],
    ['下関桟', '35下関桟'],
    ['両源田', '35両源田'],
    ['南風泊', '35南風泊'],
    ['壇ノ浦', '35壇ノ浦'],
    ['大山鼻', '35大山鼻'],
    ['大泊', '35大泊'],
    ['宇部', '35宇部'],
    ['岩国', '35岩国'],
    ['弟子待', '35弟子待'],
    ['徳山', '35徳山'],
    ['東安下', '35東安下'],
    ['沖家室', '35沖家室'],
    ['油谷', '35油谷'],
    ['田の首', '35田の首'],
    ['萩', '35萩'],
    ['長府', '35長府'],
    //// 徳島県
    ['堂ノ浦', '36堂ノ浦'],
    ['小松島', '36小松島'],
    //// 香川県
    ['与島', '37与島'],
    ['佐柳', '37佐柳'],
    ['坂出', '37坂出'],
    ['坂手', '37坂手'],
    ['引田', '37引田'],
    ['男木島', '37男木島'],
    ['粟島', '37粟島'],
    ['青木', '37青木'],
    ['高松', '37高松'],
    //// 愛媛県
    ['三島', '38三島'],
    ['三机', '38三机'],
    ['今治', '38今治'],
    ['八幡浜', '38八幡浜'],
    ['宇和島', '38宇和島'],
    ['小島', '38小島'],
    ['新居浜', '38新居浜'],
    ['日振島', '38日振島'],
    ['松山', '38松山'],
    ['波止浜', '38波止浜'],
    ['興居島', '38興居島'],
    ['菊間', '38菊間'],
    ['西条', '38西条'],
    ['長浜', '38長浜'],
    ['青島', '38青島'],
    ['鼻粟瀬', '38鼻粟瀬'],
    //// 高知県
    ['土佐清', '39土佐清'],
    ['室戸岬', '39室戸岬'],
    ['高知', '39高知'],
    //// 福岡県
    ['三池', '40三池'],
    ['八幡', '40八幡'],
    ['博多船', '40博多船'],
    ['室戸岬', '40室戸岬'],
    ['日明', '40日明'],
    ['旧門司', '40旧門司'],
    ['砂津', '40砂津'],
    ['福岡船', '40福岡船'],
    ['苅田', '40苅田'],
    ['若松', '40若松'],
    ['西海岸', '40西海岸'],
    ['青浜', '40青浜'],
    //// 佐賀県
    ['仮屋', '41仮屋'],
    ['唐津', '41唐津'],
    ['竹崎島', '41竹崎島'],
    //// 長崎県
    ['久根浜', '42久根浜'],
    ['佐世保', '42佐世保'],
    ['佐賀', '42佐賀'],
    ['佐須奈', '42佐須奈'],
    ['厳原', '42厳原'],
    ['口之津', '42口之津'],
    ['巌原', '42巌原'],
    ['志々伎', '42志々伎'],
    ['松ヶ枝', '42松ヶ枝'],
    ['松浦', '42松浦'],
    ['深堀', '42深堀'],
    ['福江', '42福江'],
    ['芦辺', '42芦辺'],
    ['郷ノ浦', '42郷ノ浦'],
    ['青方', '42青方'],
    ['鴨居瀬', '42鴨居瀬'],
    //// 熊本県
    ['三角', '43三角'],
    ['八代', '43八代'],
    ['富岡', '43富岡'],
    ['本渡', '43本渡'],
    ['柳瀬戸', '43柳瀬戸'],
    ['水俣', '43水俣'],
    ['池の浦', '43池の浦'],
    ['熊本', '43熊本'],
    ['牛深', '43牛深'],
    ['袋浦', '43袋浦'],
    ['長洲', '43長洲'],
    //// 大分県
    ['下浦', '44下浦'],
    ['姫島', '44姫島'],
    ['西大分', '44西大分'],
    ['長島', '44長島'],
    ['高田', '44高田'],
    ['鶴崎', '44鶴崎'],
    //// 宮崎県
    ['宮崎', '45宮崎'],
    ['油津', '45油津'],
    ['細島', '45細島'],
    //// 鹿児島県
    ['中之島', '46中之島'],
    ['古仁屋', '46古仁屋'],
    ['名瀬', '46名瀬'],
    ['喜入', '46喜入'],
    ['大泊', '46大泊'],
    ['枕崎', '46枕崎'],
    ['西之表', '46西之表'],
    ['阿久根', '46阿久根'],
    ['鹿児島', '46鹿児島'],
    //// 沖縄県
    ['平良', '47平良'],
    ['波照間', '47波照間'],
    ['石垣', '47石垣'],
    ['石川', '47石川'],
    ['西表島', '47西表島'],
    ['那覇', '47那覇'],
    //// その他
    ['セブ', '80セブ'],
    ['ポナペ', '80ポナペ'],
    ['片岡湾', '80片岡湾'],
    ['ｻｲﾊﾟﾝ', '80ｻｲﾊﾟﾝ'],
  ];
  // 緯度
  double gLat0 = 0.0;
  double gLat = 0.0;

  // 経度
  double gLng0 = 0.0;
  double gLng = 0.0;
  // 角度変換用定数
  double dr = pi / 180.0; // degrees to radians
  double rd = 180.0 / pi; // radians to degrees

  // Zone time
  double gZt = 0.0;
  List<double> gHr = List.filled(40, 0.0);
  List<double> gPl = List.filled(40, 0.0);
  List<int> gNc = List.filled(40, 0);

  List<double> gV = List.filled(40, 0.0);
  List<double> gVl = List.filled(40, 0.0);
  List<double> gU = List.filled(40, 0.0);
  List<double> gF = List.filled(40, 0.0);
  List<double> gAgs = List.filled(40, 0.0);
  List<int> gMonthDay = [31, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  int gLeap = 0; /* Flag of Leap Year        */
  // 閏年の場合には1,その他は0
  List<String> gWeekday = ['日', '月', '火', '水', '木', '金', '土'];

  List<String> gShio = [
    "大潮",
    "中潮",
    "小潮",
    "長潮",
    "若潮",
    "中潮",
    "大潮",
    "中潮",
    "小潮",
    "長潮",
    "若潮",
    "中潮",
    "大潮",
  ];

  //　********************************************
  // 月潮汐
  //　********************************************
  //
  // 指定月
  SioMonthInfo sioMonthInfo = SioMonthInfo();
  // 前月
  SioMonthInfo sioPreMonthInfo = SioMonthInfo();
  // 次月
  SioMonthInfo sioNextMonthInfo = SioMonthInfo();

  // 3ヶ月分潮汐
  Sio3MonthInfo sio3MonthInfo = Sio3MonthInfo();

  SioDatabase sioDb = SioDatabase();

  // 堤防一覧で選択された漁港と、その最寄り潮汐ポイント名
  String selectedTeibouName = '';
  String selectedTeibouNearestPoint = '';
  double selectedTeibouLat = 0.0;
  double selectedTeibouLng = 0.0;
  int selectedTeibouPrefId = 0;
  int listCenterTick = 0; // 釣り場一覧で再センタリングの要求カウンタ
  int teibouReloadTick = 0; // 釣り場一覧の再読込要求カウンタ
  // 釣り場一覧から釣り場詳細タブへのナビゲーション要求カウンタ
  int navigateToTideTick = 0;
  int postFeedReloadTick = 0;
  int startApplyModeTick = 0;
  int navigateToFishingTick = 0;
  int catchNotificationTick = 0;
  final Set<int> _knownCatchPostIds = <int>{};
  int? latestCatchNotificationPostId;
  String latestCatchNotificationTitle = '';
  String latestCatchNotificationBody = '';
  int currentMainPageIndex = 0;
  int fishingResultTabIndex = 0;
  SioInfo oneDaySioInfoAlt = SioInfo();

  // 投稿一覧の表示モード（'catch' or 'env'）。アプリ起動中のみ保持。
  String postListMode = 'catch';
  bool fishingDiaryMode = false;

  void setPostListMode(String mode) {
    final m = (mode == 'env') ? 'env' : 'catch';
    if (postListMode != m) {
      postListMode = m;
      notifyListeners();
    }
  }

  Future<void> loadFishingDiaryMode() async {
    final prefs = await SharedPreferences.getInstance();
    fishingDiaryMode = prefs.getBool('fishing_diary_mode') ?? false;
  }

  Future<void> setFishingDiaryMode(bool enabled) async {
    if (fishingDiaryMode == enabled) return;
    fishingDiaryMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fishing_diary_mode', enabled);
    notifyListeners();
  }

  Future<bool> _shouldShowFishingDiaryIntro() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('hide_fishing_diary_intro') ?? false);
  }

  Future<void> _saveHideFishingDiaryIntro(bool hide) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_fishing_diary_intro', hide);
  }

  Future<bool> confirmEnableFishingDiary(BuildContext context) async {
    if (!await _shouldShowFishingDiaryIntro()) return true;
    if (!context.mounted) return false;
    bool dontShowAgain = false;
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setLocalState) {
              return AlertDialog(
                titlePadding: EdgeInsets.zero,
                title: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                  child: Container(
                    color: const Color(0xFF1E90FF),
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '釣り日記とは',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    const Text('自分が投稿した釣果や、登録した釣り場だけ表示します。'),
                  ],
                ),
                actions: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: CheckboxListTile(
                          value: dontShowAgain,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('今後表示しない'),
                          onChanged: (v) {
                            setLocalState(() {
                              dontShowAgain = v ?? false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop(true);
                        },
                        child: const Text('了解'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
    );
    if (agreed == true) {
      await _saveHideFishingDiaryIntro(dontShowAgain);
      return true;
    }
    return false;
  }

  void requestPostFeedReload() {
    postFeedReloadTick++;
    notifyListeners();
  }

  void showCatchNotification({
    required int postId,
    required String title,
    required String body,
    bool navigateToFishing = true,
  }) {
    latestCatchNotificationPostId = postId;
    latestCatchNotificationTitle = title;
    latestCatchNotificationBody = body;
    catchNotificationTick++;
    if (navigateToFishing) {
      navigateToFishingTick++;
    }
    notifyListeners();
  }

  void setCurrentMainPageIndex(int pageIndex) {
    final normalized = pageIndex < 0 ? 0 : pageIndex;
    if (currentMainPageIndex == normalized) return;
    currentMainPageIndex = normalized;
    notifyListeners();
  }

  void setFishingResultTabIndex(int tabIndex) {
    final normalized = tabIndex == 1 ? 1 : 0;
    if (fishingResultTabIndex == normalized) return;
    fishingResultTabIndex = normalized;
    notifyListeners();
  }

  bool get isViewingFishingList =>
      currentMainPageIndex == 0 && fishingResultTabIndex == 1;

  void clearCatchNotification() {
    if (latestCatchNotificationPostId == null &&
        latestCatchNotificationTitle.isEmpty &&
        latestCatchNotificationBody.isEmpty) {
      return;
    }
    latestCatchNotificationPostId = null;
    latestCatchNotificationTitle = '';
    latestCatchNotificationBody = '';
    notifyListeners();
  }

  bool hasKnownCatchPostId(int postId) => _knownCatchPostIds.contains(postId);

  void registerKnownCatchPostIds(Iterable<int> postIds) {
    var changed = false;
    for (final postId in postIds) {
      if (postId > 0 && _knownCatchPostIds.add(postId)) {
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void requestStartApplyMode() {
    startApplyModeTick++;
    notifyListeners();
  }

  Future<void> loadAmbiguousLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('ambiguousLevel') ?? prefs.getInt('ambiguous_plevel');
    ambiguousLevel = (v == 0) ? 0 : kDefaultAmbiguousLevel;
  }

  Future<void> setAmbiguousLevel(int value) async {
    final normalized = (value == 0) ? 0 : 1;
    if (ambiguousLevel == normalized) return;
    ambiguousLevel = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ambiguousLevel', normalized);
    notifyListeners();
  }

  // ===== 投稿入力のドラフト（メール認証フロー復帰用） =====
  bool draftAutoSubmit = false;
  String? draftType; // 'catch' or 'env'
  String? draftSummary;
  String? draftDetail;
  String? draftEnvSummary;
  String? draftEnvDetail;
  String? draftImagePath;

  void savePostDraft({
    required String type,
    String? summary,
    String? detail,
    String? envSummary,
    String? envDetail,
    String? imagePath,
    bool autoSubmit = false,
  }) {
    draftType = (type == 'env') ? 'env' : 'catch';
    draftSummary = summary;
    draftDetail = detail;
    draftEnvSummary = envSummary;
    draftEnvDetail = envDetail;
    draftImagePath = imagePath;
    draftAutoSubmit = autoSubmit;
  }

  void clearPostDraft() {
    draftAutoSubmit = false;
    draftType = null;
    draftSummary = null;
    draftDetail = null;
    draftEnvSummary = null;
    draftEnvDetail = null;
    draftImagePath = null;
  }

  // ============= 自動「近くの釣り場」検索の起動時リクエスト =============
  bool autoNearbySearchPending = false;
  void requestAutoNearbySearch() {
    autoNearbySearchPending = true;
    notifyListeners();
  }

  Future<void> saveSelectedTeibou(
    String name,
    String nearestPoint, {
    int? id,
    double? lat,
    double? lng,
    int? prefId,
  }) async {
    selectedTeibouName = name;
    selectedTeibouNearestPoint = nearestPoint;
    if (lat != null) selectedTeibouLat = lat;
    if (lng != null) selectedTeibouLng = lng;
    if (prefId != null) selectedTeibouPrefId = prefId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_teibou_name', name);
    await prefs.setString('selected_teibou_nearest_point', nearestPoint);
    if (id != null) await prefs.setInt('selected_teibou_id', id);
    if (lat != null) await prefs.setDouble('selected_teibou_lat', lat);
    if (lng != null) await prefs.setDouble('selected_teibou_lng', lng);
    if (prefId != null) await prefs.setInt('selected_teibou_pref_id', prefId);
  }

  Future<void> loadSelectedTeibou() async {
    final prefs = await SharedPreferences.getInstance();
    selectedTeibouName = prefs.getString('selected_teibou_name') ?? '';
    selectedTeibouNearestPoint =
        prefs.getString('selected_teibou_nearest_point') ?? '';
    selectedTeibouLat = prefs.getDouble('selected_teibou_lat') ?? 0.0;
    selectedTeibouLng = prefs.getDouble('selected_teibou_lng') ?? 0.0;
    selectedTeibouPrefId = prefs.getInt('selected_teibou_pref_id') ?? 0;
  }

  void requestListCentering() {
    listCenterTick++;
    notifyListeners();
  }

  void requestTeibouReload() {
    teibouReloadTick++;
    notifyListeners();
  }

  // 釣り場詳細タブへ遷移要求（BottomNavigation のインデックス切替用）
  void requestNavigateToTidePage() {
    navigateToTideTick++;
    notifyListeners();
  }

  // 投稿などから特定の釣り場IDを選択状態にし、最寄り潮汐ポイントも設定
  Future<bool> selectTeibouById(int portId) async {
    try {
      final db = await sioDb.database;
      final rows = await db.query(
        'teibou',
        where: 'port_id = ?',
        whereArgs: [portId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final r = rows.first;
      final name = (r['port_name'] ?? '').toString();
      final lat =
          (r['latitude'] is num)
              ? (r['latitude'] as num).toDouble()
              : double.tryParse(r['latitude']?.toString() ?? '');
      final lng =
          (r['longitude'] is num)
              ? (r['longitude'] as num).toDouble()
              : double.tryParse(r['longitude']?.toString() ?? '');
      if (lat == null || lng == null) return false;

      // 都道府県IDの特定（拡張テーブルから逆引き）
      int? prefId;
      try {
        final extRows = await SioDatabase().getAllTeibouWithPrefecture();
        for (final er in extRows) {
          final rid =
              er['port_id'] is int
                  ? er['port_id'] as int
                  : int.tryParse(er['port_id']?.toString() ?? '');
          if (rid == portId) {
            prefId =
                er['todoufuken_id'] is int
                    ? er['todoufuken_id'] as int
                    : int.tryParse(er['todoufuken_id']?.toString() ?? '') ??
                        int.tryParse(er['pref_id_from_port']?.toString() ?? '');
            break;
          }
        }
      } catch (_) {}

      // 最寄り潮汐ポイント
      final nearestPoint = await _findNearestTidePoint(lat, lng);
      if (nearestPoint == null) return false;
      tidePoint = nearestPoint;
      await savePoint(nearestPoint);
      await saveSelectedTeibou(
        name,
        nearestPoint,
        id: portId,
        lat: lat,
        lng: lng,
        prefId: prefId,
      );
      notify();
      return true;
    } catch (_) {
      return false;
    }
  }

  // まだ漁港が未設定の場合、現在地から最寄りの堤防＋最寄り潮汐ポイントを自動設定
  Future<void> setupNearestByLocationIfUnset() async {
    if (selectedTeibouName.isNotEmpty ||
        selectedTeibouNearestPoint.isNotEmpty) {
      return; // 既に設定済み
    }
    // 位置サービスと権限チェック
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await _setupFixedDefaultTeibou();
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        await _setupFixedDefaultTeibou();
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      await _setupFixedDefaultTeibou();
      return;
    }

    final Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    final double clat = pos.latitude;
    final double clng = pos.longitude;

    // DBから全堤防を取得して最寄りを探す
    try {
      final rows = await sioDb.getAllTeibouWithPrefecture();
      double best = double.infinity;
      Map<String, dynamic>? bestRow;
      for (final r in rows) {
        final lat = _toDouble(r['latitude']);
        final lng = _toDouble(r['longitude']);
        if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) continue;
        final d = _haversineKm(clat, clng, lat, lng);
        if (d < best) {
          best = d;
          bestRow = r;
        }
      }
      if (bestRow == null) return;
      final name = (bestRow['port_name'] ?? '').toString();
      final bid =
          bestRow['port_id'] is int
              ? bestRow['port_id'] as int
              : int.tryParse(bestRow['port_id']?.toString() ?? '');
      final plat = _toDouble(bestRow['latitude']) ?? 0.0;
      final plng = _toDouble(bestRow['longitude']) ?? 0.0;

      // 最寄りの潮汐ポイント名を算出
      final nearestPoint = await _findNearestTidePoint(plat, plng);
      if (nearestPoint == null) return;

      // 反映
      tidePoint = nearestPoint;
      await savePoint(nearestPoint);
      await saveSelectedTeibou(name, nearestPoint, id: bid);
      shouldJumpPage = true;
      notify();
    } catch (_) {
      // 現在地取得や探索に失敗した場合は固定デフォルトへ
      await _setupFixedDefaultTeibou();
    }
  }

  Future<String?> _findNearestTidePoint(double lat, double lng) async {
    double best = double.infinity;
    String? bestName;
    for (final row in portFileData) {
      if (row.length < 2) continue;
      final name = row[0];
      final file = row[1];
      // 国内(01〜47)のみ対象
      if (file.isEmpty || file.length < 2) continue;
      final prefix = int.tryParse(file.substring(0, 2));
      if (prefix == null || prefix < 1 || prefix > 47) continue;
      final info = SioInfo();
      try {
        final ok = await getPortData(file, info);
        if (!ok) continue;
        final d = _haversineKm(lat, lng, info.lat, info.lang);
        if (d < best) {
          best = d;
          bestName = name;
        }
      } catch (_) {
        continue;
      }
    }
    return bestName;
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371.0; // km
    const double d2r = pi / 180.0;
    final dLat = (lat2 - lat1) * d2r;
    final dLon = (lon2 - lon1) * d2r;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * d2r) * cos(lat2 * d2r) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  // 位置情報が使えない場合の固定デフォルト設定
  Future<void> _setupFixedDefaultTeibou() async {
    try {
      final rows = await sioDb.getAllTeibouWithPrefecture();
      Map<String, dynamic>? pick;

      bool valid(Map<String, dynamic> r) {
        final lat = _toDouble(r['latitude']) ?? 0.0;
        final lng = _toDouble(r['longitude']) ?? 0.0;
        return !(lat == 0.0 && lng == 0.0);
      }

      // 優先1: 静岡県(22)で port_name が「田子漁港」と一致
      for (final r in rows) {
        final pid =
            r['todoufuken_id'] is int
                ? r['todoufuken_id'] as int
                : int.tryParse(r['todoufuken_id']?.toString() ?? '');
        final name = (r['port_name'] ?? '').toString();
        if (pid == 22 && name == '田子漁港' && valid(r)) {
          pick = r;
          break;
        }
      }
      // 優先2: 静岡県(22)で port_name に「田子」を含む
      if (pick == null) {
        for (final r in rows) {
          final pid =
              r['todoufuken_id'] is int
                  ? r['todoufuken_id'] as int
                  : int.tryParse(r['todoufuken_id']?.toString() ?? '');
          final name = (r['port_name'] ?? '').toString();
          if (pid == 22 && name.contains('田子') && valid(r)) {
            pick = r;
            break;
          }
        }
      }
      // 優先3: port_name が「田子漁港」
      if (pick == null) {
        for (final r in rows) {
          final name = (r['port_name'] ?? '').toString();
          if (name == '田子漁港' && valid(r)) {
            pick = r;
            break;
          }
        }
      }
      // 優先4: port_name に「田子」を含む
      if (pick == null) {
        for (final r in rows) {
          final name = (r['port_name'] ?? '').toString();
          if (name.contains('田子') && valid(r)) {
            pick = r;
            break;
          }
        }
      }
      // 最後: 最初の有効な堤防
      if (pick == null) {
        for (final r in rows) {
          if (valid(r)) {
            pick = r;
            break;
          }
        }
      }
      if (pick == null) return;

      final name = (pick['port_name'] ?? '').toString();
      final bid =
          pick['port_id'] is int
              ? pick['port_id'] as int
              : int.tryParse(pick['port_id']?.toString() ?? '');
      final plat = _toDouble(pick['latitude']) ?? 0.0;
      final plng = _toDouble(pick['longitude']) ?? 0.0;
      final nearestPoint = await _findNearestTidePoint(plat, plng);
      if (nearestPoint == null) return;

      tidePoint = nearestPoint;
      await savePoint(nearestPoint);
      await saveSelectedTeibou(name, nearestPoint, id: bid);
      shouldJumpPage = true;
      notify();
    } catch (_) {
      // いずれも失敗なら黙って従来表示
    }
  }

  /*  void setFavoriteFlag(String prefecture, String point_name){
    for (var entry in locationData) {
      String region = entry['region'] as String;
      String prefecture = entry['prefecture'] as String;

      List spots = (entry['spots'] as List?) ?? [];
      for (var spot in spots) {
        String name = spot['name'];
        int flag = spot['flag'];
      }
    }

  }
*/
  bool preLoadMoonFile = false;

  List<String> lunarPhaseImagePaths = [
    "moon_00.png",
    "moon_01.png",
    "moon_02.png",
    "moon_03.png",
    "moon_04.png",
    "moon_05.png",
    "moon_06.png",
    "moon_07.png",
    "moon_08.png",
    "moon_09.png",
    "moon_10.png",
    "moon_11.png",
    "moon_12.png",
    "moon_13.png",
    "moon_14.png",
    "moon_15.png",
    "moon_16.png",
    "moon_17.png",
    "moon_18.png",
    "moon_19.png",
    "moon_20.png",
    "moon_21.png",
    "moon_22.png",
    "moon_23.png",
    "moon_24.png",
    "moon_25.png",
    "moon_26.png",
    "moon_27.png",
    "moon_28.png",
  ];

  bool _shouldJumpPage = false; // 外部更新時のみ true にする
  bool get shouldJumpPage => _shouldJumpPage;
  set shouldJumpPage(bool newShould) {
    if (_shouldJumpPage != newShould) {
      _shouldJumpPage = newShould;
    }
  }

  void notify() {
    notifyListeners();
  }

  void initialize() async {
    mapKind = await loadMapKind();
  }

  //
  // 釣り場保存
  //
  Future<void> savePoint(String point) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('point', point);
  }

  // 読み込み
  Future<String> loadPoint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('point') ?? '伊東';
  }

  //
  // 地図種別保存
  //
  Future<void> saveMapKind(int mapKind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mapKind', mapKind);
  }

  // 読み込み
  Future<int> loadMapKind() async {
    final prefs = await SharedPreferences.getInstance();
    int mapkind = prefs.getInt('mapKind') ?? MapType.appleMaps.index;
    return mapkind;
  }

  Enum getSmartPhoneType() {
    if (Platform.isIOS) {
      return SmartPhoneType.iPhone;
    } else if (Platform.isAndroid) {
      return SmartPhoneType.android;
    } else {
      return SmartPhoneType.unknown;
    }
  }

  //　********************************************
  // メソッド
  // *********************************************
  int getGeturei(int month, int day) {
    //print('getGeturei daycnt[${sioMonthInfo.daycnt}]');
    for (int i = 0; i < sioMonthInfo.daycnt; i++) {
      //print('getGeturei [$i] month[sioMonthInfo.sioSummaryDayInfo[i].month]/day[sioMonthInfo.sioSummaryDayInfo[i].day]');
      if (sioMonthInfo.sioSummaryDayInfo[i].month == month &&
          sioMonthInfo.sioSummaryDayInfo[i].day == day) {
        return sioMonthInfo.sioSummaryDayInfo[i].age2;
      }
    }
    return 0;
  }

  String getSio(int month, int day) {
    for (int i = 0; i < sioMonthInfo.daycnt; i++) {
      if (sioMonthInfo.sioSummaryDayInfo[i].month == month &&
          sioMonthInfo.sioSummaryDayInfo[i].day == day) {
        return sioMonthInfo.sioSummaryDayInfo[i].sio;
      }
    }
    return '';
  }

  int getTuki(int month, int day) {
    for (int i = 0; i < sioMonthInfo.daycnt; i++) {
      if (sioMonthInfo.sioSummaryDayInfo[i].month == month &&
          sioMonthInfo.sioSummaryDayInfo[i].day == day) {
        return sioMonthInfo.sioSummaryDayInfo[i].flag;
      }
    }
    return 0;
  }

  void getTidePoint(
    SioInfo tideInfo,
    List<double> f,
    List<double> hr,
    List<double> vl,
    List<double> ags,
    List<double> pl,
    int peakflag,
  ) {
    int i, j;
    int k;
    //int pos;
    int lag;
    double tc = 0.0;
    //double x1 = 0;
    //double y1 = 0;
    //double x2 = 0;
    //double y2 = 0;
    //double cox;
    double itv;
    double inc;
    double timeVal;
    int hh;
    double mm;
    double level = tideInfo.average;

    if (peakflag != 0) {
      tideInfo.peakTideCnt = 0;
    } else {
      tideInfo.dayTideCnt = 0;
    }

    //pos = 51;
    k = 19;
    itv = 20; // 計算間隔
    inc = (24 * 60 / itv + 1).toDouble(); // 計算回数
    //cox = itv * 0.2;

    // Lagrange関数初期化
    timeVal = -60.0;

    FloatWrapper T = FloatWrapper(timeVal);
    FloatWrapper Y = FloatWrapper(tc);

    lag = LagrangeCalculator.lagrange(T, Y);
    timeVal = T.value; // 更新後の time
    tc = Y.value;

    for (i = -5; i < inc; i++) {
      tc = level;
      for (j = 0; j < 40; j++) {
        tc =
            tc +
            f[j] * hr[j] * cos((vl[j] + ags[j] * i / (60 / itv) - pl[j]) * dr);
      }
      timeVal = 1.0 * itv * i;
      hh = (timeVal / 60).floor(); // ここは floor で整数部分
      mm = timeVal.remainder(60); // Dartでは % は余り（整数の場合）
      // ここでは小数部分として計算する必要があれば調整してください
      if (peakflag != 0) {
        T.value = timeVal;
        Y.value = tc;
        lag = LagrangeCalculator.lagrange(T, Y);
        timeVal = T.value;
        tc = Y.value;

        if (lag == 1) {
          hh = (timeVal / 60).floor();
          mm = timeVal.remainder(60);

          if (hh < 24) {
            if (tideInfo.peakTideCnt < 4) {
              tideInfo.peakTide[tideInfo.peakTideCnt].tide = tc;
              tideInfo.peakTide[tideInfo.peakTideCnt].hh = hh.toDouble();
              tideInfo.peakTide[tideInfo.peakTideCnt].mm = mm;
              tideInfo.peakTideCnt++;
            }
            k = k + 1;
          }
          if (k > 24) k = 24;
        }
      } else {
        if (i == 0 || i > 0) {
          if (tideInfo.dayTideCnt < 73) {
            tideInfo.dayTide[tideInfo.dayTideCnt].tide = tc;
            tideInfo.dayTide[tideInfo.dayTideCnt].hh = hh.toDouble();
            tideInfo.dayTide[tideInfo.dayTideCnt].mm = mm;
            tideInfo.dayTideCnt++;
          }
        }
      }
    }

    if (peakflag != 0) {
      for (int i = 1; i < tideInfo.peakTideCnt; i++) {
        if (tideInfo.peakTide[i - 1].tide < tideInfo.peakTide[i].tide) {
          tideInfo.peakTide[i - 1].flag = 0;
          tideInfo.peakTide[i].flag = 1;
        } else {
          tideInfo.peakTide[i - 1].flag = 1;
          tideInfo.peakTide[i].flag = 0;
        }
      }
    }
  }

  double roundTo5Digits(double value) {
    return double.parse(value.toStringAsFixed(5));
  }

  Future<void> openGoogleMaps(double lat, double lng, {int zoom = 15}) async {
    final double latitude = roundTo5Digits(lat);
    final double longitude = roundTo5Digits(lng);

    // Android は geo: 優先。iOS は comgooglemaps:// を試し、ダメなら https。
    if (Platform.isAndroid) {
      final Uri geoUri = Uri.parse(
        'geo:$latitude,$longitude?q=$latitude,$longitude&z=$zoom',
      );
      final Uri geoUriFallback = Uri.parse(
        'geo:0,0?q=$latitude,$longitude&z=$zoom',
      );
      final Uri webUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude&zoom=$zoom',
      );

      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
        return;
      }
      if (await canLaunchUrl(geoUriFallback)) {
        await launchUrl(geoUriFallback, mode: LaunchMode.externalApplication);
        return;
      }
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    } else if (Platform.isIOS) {
      final Uri appUri = Uri.parse(
        'comgooglemaps://?q=$latitude,$longitude&zoom=$zoom',
      );
      final Uri webUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude&zoom=$zoom',
      );
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
      return;
    } else {
      // 他プラットフォームは https で外部ブラウザ
      final Uri webUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude&zoom=$zoom',
      );
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> openAppleMaps(double lat, double lng /*, String label*/) async {
    final double latitude = roundTo5Digits(lat);
    final double longitude = roundTo5Digits(lng);

    final Uri appleMapsUri = Uri.parse('maps://?q=$latitude,$longitude');
    final Uri fallbackUri = Uri.parse(
      'https://maps.apple.com/?q=$latitude,$longitude',
    );

    if (await canLaunchUrl(appleMapsUri)) {
      await launchUrl(appleMapsUri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
    }
  }

  /// readPort 関数は、filename.TD2 のアセットファイルを読み込み、
  /// 最初の行はカンマ区切りで na に設定し、
  /// 2行目以降は各行をカンマ区切りにして、hr と pl の配列に値を設定する処理を行います。
  Future<List<String>> readPort(
    String filename,
    List<double> hr,
    List<double> pl,
    SioInfo tideInfo,
  ) async {
    // 初期化
    int i = 0;
    // アセットファイルのパスを指定（pubspec.yaml で assets に登録されている前提）
    String path = 'assets/TID/$filename.TD2';

    // アセットファイルの内容を文字列として読み込み（非同期）
    String fileText = "";

    fileText = await rootBundle.loadString(path);

    // 改行コード "\r" で分割（※環境により "\n" などの場合は適宜変更）
    List<String> lineItems = fileText.split('\r');

    List<String> na = [];
    List<String> work = [];
    int setp = 0;
    for (i = 0; i < lineItems.length; i++) {
      // 各行の前後の余分な空白や改行を取り除く
      String text = lineItems[i].trim();
      if (text.isNotEmpty) {
        if (i == 0) {
          // 1行目：釣り場名のリストを取得
          na = text.split(',');
        } else {
          // 2行目以降：カンマ区切りにして work に格納
          work = text.split(',');
          // work[1]、[2]、[4]、[5] から浮動小数点数に変換して hr と pl に設定
          hr[setp] = double.tryParse(work[1]) ?? 0.0;
          pl[setp] = double.tryParse(work[2]) ?? 0.0;
          hr[setp + 1] = double.tryParse(work[4]) ?? 0.0;
          pl[setp + 1] = double.tryParse(work[5]) ?? 0.0;
          setp += 1;
          setp += 1;
        }
      } else {
        break;
      }
    }
    return na;
  }

  Future<bool> getPortData(String fileName, SioInfo sioInfo) async {
    List<String> na = await readPort(fileName, gHr, gPl, sioInfo);
    // 緯度
    gLat0 = double.tryParse(na[1]) ?? 0.0;
    // 経度
    gLng0 = double.tryParse(na[2]) ?? 0.0;
    // 平均水面の高さ
    sioInfo.average = double.tryParse(na[3]) ?? 0.0;

    gLat = dg2dc(gLat0);
    gLng = dg2dc(gLng0);
    // 日本国内（01〜47のファイル）の場合は行政上の標準時（JST=135°）を固定で採用。
    // 経度から標準時子午線を算出すると沖縄（~123°E）がUTC+8相当になり1時間ズレるため。
    double zoneMeridian;
    if (fileName.isNotEmpty && fileName.length >= 2) {
      final prefix = fileName.substring(0, 2);
      final n = int.tryParse(prefix);
      if (n != null && n >= 1 && n <= 47) {
        zoneMeridian = 135.0; // JST
      } else {
        // 海外などは従来の計算（地理的標準時）にフォールバック
        zoneMeridian = (((gLng + 7.5) / 15.0).floor() * 15.0).toDouble();
      }
    } else {
      zoneMeridian = (((gLng + 7.5) / 15.0).floor() * 15.0).toDouble();
    }
    gZt = zoneMeridian;
    sioInfo.lat = gLat;
    sioInfo.lang = gLng;

    return true;
  }

  /// meanLongitudes 関数：年、時差（tz）から4つの値 [s, h, p, n] を返す
  List<double> meanLongitudes(int year, int tz) {
    int ty = year - 2000;
    double s = rnd(211.728 + rnd(129.38471 * ty) + rnd(13.176396 * tz));
    double h = rnd(279.974 + rnd(-0.23871 * ty) + rnd(0.985647 * tz));
    double p = rnd(83.298 + rnd(40.66229 * ty) + rnd(0.111404 * tz));
    double n = rnd(125.071 + rnd(-19.32812 * ty) + rnd(-0.052954 * tz));
    return [s, h, p, n];
  }

  // **************************************************************
  //年初（1月1日）からの経過日数
  //閏年のチェックは行わない
  //M[]の値をそのまま使うだけなのでM[]の内容が間違っていると
  //この関数の値も不正になる
  // ***************************************************************/
  int serialDay(int month, int day, List<int> M) {
    int sday = 0;
    for (int i = 1; i < month; i++) {
      sday += M[i];
    }
    sday = sday + day - 1;
    return sday;
  }

  /// argumentF0 関数：p, n から f0[10] のリストを計算して返す
  List<double> argumentF0(double p, double n) {
    double n1 = cos(n * 1.0 * dr);
    double n2 = cos(rnd(n * 2.0) * dr);
    double n3 = cos(rnd(n * 3.0) * dr);
    List<double> f0 = List.filled(10, 0.0);
    f0[0] = 1.0000 - 0.1300 * n1 + 0.0013 * n2;
    f0[1] = 1.0429 + 0.4135 * n1 - 0.0040 * n2;
    f0[2] = 1.0089 + 0.1871 * n1 - 0.0147 * n2 + 0.0014 * n3;
    f0[3] = 1.0060 + 0.1150 * n1 - 0.0088 * n2 + 0.0006 * n3;
    f0[4] = 1.0129 + 0.1676 * n1 - 0.0170 * n2 + 0.0016 * n3;
    f0[5] = 1.1027 + 0.6504 * n1 + 0.0317 * n2 - 0.0014 * n3;
    f0[6] = 1.0004 - 0.0373 * n1 + 0.0002 * n2;
    f0[7] = 1.0241 + 0.2863 * n1 + 0.0083 * n2 - 0.0015 * n3;

    double cu =
        1.0 -
        0.2505 * cos(p * 2.0 * dr) -
        0.1102 * cos((p * 2.0 - n) * dr) -
        0.0156 * cos((p * 2.0 - n * 2.0) * dr) -
        0.0370 * cos(n * dr);
    double su =
        -0.2505 * sin(p * 2.0 * dr) -
        0.1102 * sin((p * 2.0 - n) * dr) -
        0.0156 * sin((p * 2.0 - n * 2.0) * dr) -
        0.0370 * sin(n * dr);
    double arg = atan2(su, cu) * rd;
    f0[8] = su / sin(arg * dr);

    cu = 2.0 * cos(p * dr) + 0.4 * cos((p - n) * dr);
    su = sin(p * dr) + 0.2 * cos((p - n) * dr);
    arg = atan2(su, cu) * rd;
    f0[9] = cu / cos(arg * dr);

    return f0;
  }

  /// argumentU0 関数：p, n から u0[10] のリストを計算して返す
  List<double> argumentU0(double p, double n) {
    double s1 = sin(n * dr);
    double s2 = sin(rnd(n * 2.0) * dr);
    double s3 = sin(rnd(n * 3.0) * dr);
    List<double> u0 = List.filled(10, 0.0);
    u0[0] = 0.00 * s1 + 0.00 * s2 + 0.00 * s3;
    u0[1] = -23.74 * s1 + 2.68 * s2 - 0.38 * s3;
    u0[2] = 10.80 * s1 - 1.34 * s2 + 0.19 * s3;
    u0[3] = -8.86 * s1 + 0.68 * s2 - 0.07 * s3;
    u0[4] = -12.94 * s1 + 1.34 * s2 - 0.19 * s3;
    u0[5] = -36.68 * s1 + 4.02 * s2 - 0.57 * s3;
    u0[6] = -2.14 * s1;
    u0[7] = -17.74 * s1 + 0.68 * s2 - 0.04 * s3;

    double cu =
        1.0 -
        0.2505 * cos(p * 2.0 * dr) -
        0.1102 * cos((p * 2.0 - n) * dr) -
        0.0156 * cos((p * 2.0 - n * 2.0) * dr) -
        0.0370 * cos(n * dr);
    double su =
        -0.2505 * sin(p * 2.0 * dr) -
        0.1102 * sin((p * 2.0 - n) * dr) -
        0.0156 * sin((p * 2.0 - n * 2.0) * dr) -
        0.0370 * sin(n * dr);
    u0[8] = atan2(su, cu) * rd;

    cu = 2.0 * cos(p * dr) + 0.4 * cos((p - n) * dr);
    su = sin(p * dr) + 0.2 * cos((p - n) * dr);
    u0[9] = atan2(su, cu) * rd;

    return u0;
  }

  /// argumentV1 関数：s, h, p から v[0..19] のリストを返す
  List<double> argumentV1(double s, double h, double p) {
    List<double> v = List.filled(40, 0.0);
    v[0] = (0.0 * s + 1.0 * h + 0.0 * p + 0.0);
    v[1] = (0.0 * s + 2.0 * h + 0.0 * p + 0.0);
    v[2] = (1.0 * s + 0.0 * h - 1.0 * p + 0.0);
    v[3] = (2.0 * s - 2.0 * h + 0.0 * p + 0.0);
    v[4] = (2.0 * s + 0.0 * h + 0.0 * p + 0.0);
    v[5] = (-3.0 * s + 1.0 * h + 1.0 * p + 270.0);
    v[6] = (-3.0 * s + 3.0 * h - 1.0 * p + 270.0);
    v[7] = (-2.0 * s + 1.0 * h + 0.0 * p + 270.0);
    v[8] = (-2.0 * s + 3.0 * h + 0.0 * p - 270.0);
    v[9] = (-1.0 * s + 1.0 * h + 0.0 * p + 90.0);
    v[10] = (0.0 * s - 2.0 * h + 0.0 * p + 192.0);
    v[11] = (0.0 * s - 1.0 * h + 0.0 * p + 270.0);
    v[12] = (0.0 * s + 0.0 * h + 0.0 * p + 180.0);
    v[13] = (0.0 * s + 1.0 * h + 0.0 * p + 90.0);
    v[14] = (0.0 * s + 2.0 * h + 0.0 * p + 168.0);
    v[15] = (0.0 * s + 3.0 * h + 0.0 * p + 90.0);
    v[16] = (1.0 * s + 1.0 * h - 1.0 * p + 90.0);
    v[17] = (2.0 * s - 1.0 * h + 0.0 * p - 270.0);
    v[18] = (2.0 * s + 1.0 * h + 0.0 * p + 90.0);
    v[19] = (-4.0 * s + 2.0 * h + 2.0 * p + 0.0);
    return v;
  }

  /// argumentV2 関数：s, h, p から v[20..39] のリストを返す
  List<double> argumentV2(double s, double h, double p, List<double> v) {
    v[20] = (-4.0 * s + 4.0 * h + 0.0 * p + 0.0);
    v[21] = (-3.0 * s + 2.0 * h + 1.0 * p + 0.0);
    v[22] = (-3.0 * s + 4.0 * h - 1.0 * p + 0.0);
    v[23] = (-2.0 * s + 0.0 * h + 0.0 * p + 180.0);
    v[24] = (-2.0 * s + 2.0 * h + 0.0 * p + 0.0);
    v[25] = (-1.0 * s + 0.0 * h + 1.0 * p + 180.0);
    v[26] = (-1.0 * s + 2.0 * h - 1.0 * p + 180.0);
    v[27] = (0.0 * s - 1.0 * h + 0.0 * p + 282.0);
    v[28] = (0.0 * s + 0.0 * h + 0.0 * p + 0.0);
    v[29] = (0.0 * s + 1.0 * h + 0.0 * p + 258.0);
    v[30] = (0.0 * s + 2.0 * h + 0.0 * p + 0.0);
    v[31] = (2.0 * s - 2.0 * h + 0.0 * p + 0.0);
    v[32] = (-4.0 * s + 3.0 * h + 0.0 * p + 270.0);
    v[33] = (-3.0 * s + 3.0 * h + 0.0 * p + 180.0);
    v[34] = (-2.0 * s + 3.0 * h + 0.0 * p + 90.0);
    v[35] = (0.0 * s + 1.0 * h + 0.0 * p + 90.0);
    v[36] = (-4.0 * s + 4.0 * h + 0.0 * p + 0.0);
    v[37] = (-2.0 * s + 2.0 * h + 0.0 * p + 0.0);
    v[38] = (-6.0 * s + 6.0 * h + 0.0 * p + 0.0);
    v[39] = (-4.0 * s + 4.0 * h + 0.0 * p + 0.0);
    return v;
  }

  /// argumentU1 関数：u0[10] から u[0..19] を生成して返す
  List<double> argumentU1(List<double> u0) {
    List<double> u = List.filled(40, 0.0);
    u[0] = 0.0;
    u[1] = 0.0;
    u[2] = 0.0;
    u[3] = -u0[6];
    u[4] = u0[1];
    u[5] = u0[2];
    u[6] = u0[2];
    u[7] = u0[2];
    u[8] = u0[6];
    u[9] = u0[9];
    u[10] = 0.0;
    u[11] = 0.0;
    u[12] = 0.0;
    u[13] = u0[3];
    u[14] = 0.0;
    u[15] = 0.0;
    u[16] = u0[4];
    u[17] = -u0[2];
    u[18] = u0[5];
    u[19] = u0[6];
    return u;
  }

  /// argumentU2 関数：u0[10] から u[20..39] を生成して返す
  List<double> argumentU2(List<double> u0, List<double> u) {
    //List<double> u = List.filled(40, 0.0);
    u[20] = u0[6];
    u[21] = u0[6];
    u[22] = u0[6];
    u[23] = u0[2];
    u[24] = u0[6];
    u[25] = u0[6];
    u[26] = u0[8];
    u[27] = 0.0;
    u[28] = 0.0;
    u[29] = 0.0;
    u[30] = u0[7];
    u[31] = -u0[6];
    u[32] = u0[6] + u0[2];
    u[33] = u0[6] * 1.5;
    u[34] = u0[6] + u0[3];
    u[35] = u0[3];
    u[36] = u0[6] * 2.0;
    u[37] = u0[6];
    u[38] = u0[6] * 3.0;
    u[39] = u0[6] * 2.0;
    return u;
  }

  // -------------------------
  // coeffic_f1
  // -------------------------
  void coefficF1(List<double> f0, List<double> f) {
    f[0] = 1.0;
    f[1] = 1.0;
    f[2] = f0[0];
    f[3] = f0[6];
    f[4] = f0[1];
    f[5] = f0[2];
    f[6] = f0[2];
    f[7] = f0[2];
    f[8] = f0[6];
    f[9] = f0[9];
    f[10] = 1.0;
    f[11] = 1.0;
    f[12] = 1.0;
    f[13] = f0[3];
    f[14] = 1.0;
    f[15] = 1.0;
    f[16] = f0[4];
    f[17] = f0[2];
    f[18] = f0[5];
    f[19] = f0[6];
  }

  // -------------------------
  // coeffic_f2
  // -------------------------
  void coefficF2(List<double> f0, List<double> f) {
    f[20] = f0[6];
    f[21] = f0[6];
    f[22] = f0[6];
    f[23] = f0[2];
    f[24] = f0[6];
    f[25] = f0[6];
    f[26] = f0[8];
    f[27] = 1.0;
    f[28] = 1.0;
    f[29] = 1.0;
    f[30] = f0[7];
    f[31] = f0[6];
    f[32] = f0[6] * f0[2];
    f[33] = pow(f0[6], 1.5).toDouble();
    f[34] = f0[6] * f0[3];
    f[35] = f0[3];
    f[36] = pow(f0[6], 2.0).toDouble();
    f[37] = f0[6];
    f[38] = pow(f0[6], 3.0).toDouble();
    f[39] = pow(f0[6], 2.0).toDouble();
  }

  void setLeap(List<int> m, int year) {
    if ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)) {
      m[2] = 29;
      gLeap = 1;
    } else {
      m[2] = 28;
      gLeap = 0;
    }
  }

  // -------------------------
  // cycle_number
  // -------------------------
  void cycleNumber(List<int> nc) {
    nc[0] = 0;
    nc[10] = 1;
    nc[20] = 2;
    nc[30] = 2;
    nc[1] = 0;
    nc[11] = 1;
    nc[21] = 2;
    nc[31] = 2;
    nc[2] = 0;
    nc[12] = 1;
    nc[22] = 2;
    nc[32] = 3;
    nc[3] = 0;
    nc[13] = 1;
    nc[23] = 2;
    nc[33] = 3;
    nc[4] = 0;
    nc[14] = 1;
    nc[24] = 2;
    nc[34] = 3;
    nc[5] = 1;
    nc[15] = 1;
    nc[25] = 2;
    nc[35] = 3;
    nc[6] = 1;
    nc[16] = 1;
    nc[26] = 2;
    nc[36] = 4;
    nc[7] = 1;
    nc[17] = 1;
    nc[27] = 2;
    nc[37] = 4;
    nc[8] = 1;
    nc[18] = 1;
    nc[28] = 2;
    nc[38] = 6;
    nc[9] = 1;
    nc[19] = 2;
    nc[29] = 2;
    nc[39] = 6;
  }

  bool tideSub(bool detailFlag, SioInfo sioInfo) {
    int i;
    int l;
    int tz;
    double s, h, p, n;
    List<double> f0 = List.filled(10, 0.0);
    List<double> u0 = List.filled(10, 0.0);
    double z;
    double arg1, arg2;

    // うるう年設定：setLeap は gMonthDay と sioInfo.inYear を更新する前提
    setLeap(gMonthDay, sioInfo.inYear);

    // 天文計算用通日
    z = serialZ(sioInfo.inYear, sioInfo.inMonth, sioInfo.inDay);

    // 曜日取得： arg1 = z + 6.5; arg2 = floor(arg1/7.0); weekday = arg1 - arg2*7.0;
    arg1 = z + 6.5;
    arg2 = (arg1 / 7.0).floorToDouble();
    sioInfo.weekday = (arg1 - arg2 * 7.0).toInt();

    // 潮汐計算用通日
    tz = serialDay(sioInfo.inMonth, sioInfo.inDay, gMonthDay);
    l = fix((sioInfo.inYear + 3) / 4.0).toInt() - 500;
    tz = tz + l;

    // 太陽、月の軌道要素：mean_longitudes( year, tz, &s, &h, &p, &n );
    // ここでは meanLongitudes() が List<double> [s, h, p, n] を返すと仮定
    List<double> ml = meanLongitudes(sioInfo.inYear, tz);
    s = ml[0];
    h = ml[1];
    p = ml[2];
    n = ml[3];

    // 基本となる分潮の天文因数および天文引数
    f0 = argumentF0(p, n);
    u0 = argumentU0(p, n);
    gV = argumentV1(s, h, p);
    gV = argumentV2(s, h, p, gV);
    gU = argumentU1(u0);
    gU = argumentU2(u0, gU);

    // 天文引数 (V0+U)g の計算（グリニッチに於ける午前零時の値）
    for (i = 0; i < 40; i++) {
      gV[i] = rnd(gV[i] + gU[i]);
    }

    // 天文因数 f の計算
    coefficF1(f0, gF);
    coefficF2(f0, gF);

    // 分潮の波数の計算
    cycleNumber(gNc);

    // 分潮の角速度の計算
    angularSpeed(gAgs);

    // 観測地の帯域時午前零時の値に変換（天文引数 (V0+U)l の計算）
    for (i = 0; i < 40; i++) {
      gVl[i] = gV[i] - (-gLng) * gNc[i] + gAgs[i] * (-gZt / 15.0);
      gVl[i] = rnd(gVl[i]);
    }

    /* 一日潮汐グラフ表示 */
    oneDayTides(detailFlag, sioInfo);
    return true;
  }

  // -------------------------
  // angular_speed
  // -------------------------
  void angularSpeed(List<double> ags) {
    ags[0] = 0.0410686;
    ags[1] = 0.0821373;
    ags[2] = 0.5443747;
    ags[3] = 1.0158958;
    ags[4] = 1.0980331;
    ags[5] = 13.3986609;
    ags[6] = 13.4715145;
    ags[7] = 13.9430356;
    ags[8] = 14.0251729;
    ags[9] = 14.4920521;
    ags[10] = 14.9178647;
    ags[11] = 14.9589314;
    ags[12] = 15.0000000;
    ags[13] = 15.0410686;
    ags[14] = 15.0821353;
    ags[15] = 15.1232059;
    ags[16] = 15.5854433;
    ags[17] = 16.0569644;
    ags[18] = 16.1391017;
    ags[19] = 27.8953548;
    ags[20] = 27.9682084;
    ags[21] = 28.4397295;
    ags[22] = 28.5125831;
    ags[23] = 28.9019669;
    ags[24] = 28.9841042;
    ags[25] = 29.4556253;
    ags[26] = 29.5284789;
    ags[27] = 29.9589333;
    ags[28] = 30.0000000;
    ags[29] = 30.0410667;
    ags[30] = 30.0821373;
    ags[31] = 31.0158958;
    ags[32] = 42.9271398;
    ags[33] = 43.4761563;
    ags[34] = 44.0251729;
    ags[35] = 45.0410686;
    ags[36] = 57.9682084;
    ags[37] = 58.9841042;
    ags[38] = 86.9523127;
    ags[39] = 87.9682084;
  }

  double dg2dc(double x) {
    double fixX = x.truncate().toDouble();
    return fixX + ((x - fixX) / 6.0 * 10.0);
  }

  double dc2dg(double x) {
    double dd = x.truncateToDouble();
    double mm = (x - dd) * 60.0;
    return dd + (mm / 100.0);
  }

  bool tideOneDay(SioInfo sioInfo) {
    return tideSub(true, sioInfo);
  }

  /// setOneDaySioWave() の処理（sioInfo の一部のデータを oneDaySioInfo にコピーする）
  void setOneDaySioWave(SioInfo sioInfo) {
    // 潮汐一日情報　73項目 配列コピー
    Common.instance.oneDaySioInfo.dayTide = List<SioPoint>.from(
      sioInfo.dayTide,
    );
    Common.instance.oneDaySioInfo.dayTideCnt = sioInfo.dayTideCnt;

    // 満潮、干潮　4項目 配列コピー
    Common.instance.oneDaySioInfo.peakTide = List<SioPoint>.from(
      sioInfo.peakTide,
    );
    Common.instance.oneDaySioInfo.peakTideCnt = sioInfo.peakTideCnt;

    // 日の出・日没時刻のコピー
    Common.instance.oneDaySioInfo.pSunRise = SunPoint(
      hh: sioInfo.pSunRise.hh,
      mm: sioInfo.pSunRise.mm,
    );
    Common.instance.oneDaySioInfo.pSunSet = SunPoint(
      hh: sioInfo.pSunSet.hh,
      mm: sioInfo.pSunSet.mm,
    );
  }

  /// setOneDaySio() の処理（StatefulWidget の State 内で呼び出す例）
  void setOneDaySio(SioInfo sioInfo) {
    // 1. 潮汐波形の設定
    // _tideWave はカスタムウィジェットのインスタンス。setOneDaySioWave() を呼び出し、再描画を要求する
    setOneDaySioWave(sioInfo);
    // Flutter では setState() を呼ぶことで再描画を要求します
    // ※ここでは、_tideWave 内部で自動で再描画している前提

    // 2. 表示日付の設定
    Sio.instance.dispTideDate =
        "${sioInfo.inYear.toString().padLeft(4, '0')}/"
        "${sioInfo.inMonth.toString().padLeft(2, '0')}/"
        "${sioInfo.inDay.toString().padLeft(2, '0')} "
        "(${gWeekday[sioInfo.weekday]})";

    // 3. その他の表示テキストを更新（sioInfo の各文字列フィールドを利用）
    Sio.instance.sunRiseTime = sioInfo.sunrise;
    Sio.instance.sunSetTime = sioInfo.sunset;
    // 大潮、中潮、小潮など
    Sio.instance.sioName = sioInfo.sio;

    // 4. 高潮・低潮時刻の初期化
    Sio.instance.highTideTime1 = "-";
    Sio.instance.highTideTime2 = "-";
    Sio.instance.lowTideTime1 = "-";
    Sio.instance.lowTideTime2 = "-";

    // 5. peakTide 配列のうち、flag != 0 を「高潮」、flag == 0 を「低潮」として表示文字列を設定する
    int highCnt = 0;
    int lowCnt = 0;
    for (int i = 0; i < sioInfo.peakTideCnt; i++) {
      // peakTide[i].hh, .mm を用いて "HH:MM" 形式の文字列を作成
      String tideTime =
          "${sioInfo.peakTide[i].hh.floor().toString().padLeft(2, '0')}:"
          "${sioInfo.peakTide[i].mm.floor().toString().padLeft(2, '0')}";
      if (sioInfo.peakTide[i].flag != 0) {
        // 高潮の場合
        if (highCnt == 0) {
          Sio.instance.highTideTime1 = tideTime;
        } else if (highCnt == 1) {
          Sio.instance.highTideTime2 = tideTime;
        }
        highCnt++;
      } else {
        // 低潮の場合
        if (lowCnt == 0) {
          Sio.instance.lowTideTime1 = tideTime;
        } else if (lowCnt == 1) {
          Sio.instance.lowTideTime2 = tideTime;
        }
        lowCnt++;
      }
    }
  }

  void setOneDaySioAlt(SioInfo sioInfo) {
    oneDaySioInfoAlt.dayTide = List<SioPoint>.from(sioInfo.dayTide);
    oneDaySioInfoAlt.dayTideCnt = sioInfo.dayTideCnt;
    oneDaySioInfoAlt.peakTide = List<SioPoint>.from(sioInfo.peakTide);
    oneDaySioInfoAlt.peakTideCnt = sioInfo.peakTideCnt;
    oneDaySioInfoAlt.pSunRise = SunPoint(
      hh: sioInfo.pSunRise.hh,
      mm: sioInfo.pSunRise.mm,
    );
    oneDaySioInfoAlt.pSunSet = SunPoint(
      hh: sioInfo.pSunSet.hh,
      mm: sioInfo.pSunSet.mm,
    );
  }

  Future<void> computeAltTideForSelected(DateTime tideDate) async {
    if (selectedTeibouLat == 0.0 && selectedTeibouLng == 0.0) {
      oneDaySioInfoAlt.dayTideCnt = 0;
      return;
    }
    // 退避
    final bakLat0 = gLat0;
    final bakLng0 = gLng0;
    final bakLat = gLat;
    final bakLng = gLng;
    final bakZt = gZt;

    // 選択漁港の座標（decimal度）を適用
    gLat = selectedTeibouLat;
    gLng = selectedTeibouLng;
    gLat0 = dc2dg(gLat);
    gLng0 = dc2dg(gLng);
    gZt = 135.0; // 日本国内はJST固定

    // 当日で再計算（調和定数は直前の最寄りポイント読込を使用）
    final alt = SioInfo();
    alt.inYear = tideDate.year;
    alt.inMonth = tideDate.month;
    alt.inDay = tideDate.day;
    alt.average = gSioInfo.average; // 平均水面は最寄を流用
    tideOneDay(alt);
    setOneDaySioAlt(alt);

    // 復元
    gLat0 = bakLat0;
    gLng0 = bakLng0;
    gLat = bakLat;
    gLng = bakLng;
    gZt = bakZt;
  }

  // --------------------
  // 月齢関連処理
  // --------------------

  // 月齢から何夜かを求める
  int getMitikake(double fAge, double ilum) {
    double interval = 29.53 / 29;
    double age = fAge + interval / 2;
    int iage = (age / interval).toInt();
    iage = iage % 29;
    return iage;

    /*
    int iAge = fAge.round();
    int iDx = min(max(iAge,0), 28);
    return iDx;
    */
  }

  bool setTideMonth(SioMonthInfo sioMonthInfo) {
    //print('setTideMonth');

    // 年、月取得
    int year = sioMonthInfo.inYear;
    int month = sioMonthInfo.inMonth;
    // 月の日数取得
    setLeap(gMonthDay, sioMonthInfo.inYear);
    sioMonthInfo.daycnt = gMonthDay[month];

    // 指定月の全日の潮汐取得
    for (int i = 1; i <= sioMonthInfo.daycnt; i++) {
      SioInfo sioInfo = SioInfo();
      sioInfo.inYear = year;
      sioInfo.inMonth = month;
      sioInfo.inDay = i;

      // 潮汐定数　取得
      tideSub(false, sioInfo);

      // flag初期化
      sioMonthInfo.sioSummaryDayInfo[i - 1].flag = 0;
      // 年設定
      sioMonthInfo.sioSummaryDayInfo[i - 1].year = year;
      // 月設定
      sioMonthInfo.sioSummaryDayInfo[i - 1].month = month;

      // 日設定
      sioMonthInfo.sioSummaryDayInfo[i - 1].day = i;
      // 曜日
      sioMonthInfo.sioSummaryDayInfo[i - 1].weekday = sioInfo.weekday;
      // 月齢
      sioMonthInfo.sioSummaryDayInfo[i - 1].age = sioInfo.age;
      // 月輝面
      sioMonthInfo.sioSummaryDayInfo[i - 1].ilum = sioInfo.ilum;

      // 潮設定
      sioMonthInfo.sioSummaryDayInfo[i - 1].sio = sioInfo.sio;
    }
    return true;
  }

  void copyMonthInfo(Sio3MonthInfo sio3MonthInfo, SioMonthInfo sioMonthInfo) {
    int spos = sio3MonthInfo.infoCnt;
    for (int i = 0; i < sioMonthInfo.daycnt; i++) {
      sio3MonthInfo.sioSummaryDayInfo[spos].flag =
          sioMonthInfo.sioSummaryDayInfo[i].flag;
      sio3MonthInfo.sioSummaryDayInfo[spos].year =
          sioMonthInfo.sioSummaryDayInfo[i].year;
      sio3MonthInfo.sioSummaryDayInfo[spos].month =
          sioMonthInfo.sioSummaryDayInfo[i].month;
      sio3MonthInfo.sioSummaryDayInfo[spos].day =
          sioMonthInfo.sioSummaryDayInfo[i].day;
      sio3MonthInfo.sioSummaryDayInfo[spos].weekday =
          sioMonthInfo.sioSummaryDayInfo[i].weekday;
      sio3MonthInfo.sioSummaryDayInfo[spos].age =
          sioMonthInfo.sioSummaryDayInfo[i].age;
      sio3MonthInfo.sioSummaryDayInfo[spos].ilum =
          sioMonthInfo.sioSummaryDayInfo[i].ilum;
      sio3MonthInfo.sioSummaryDayInfo[spos].sio =
          sioMonthInfo.sioSummaryDayInfo[i].sio;
      spos++;
    }
    sio3MonthInfo.infoCnt = spos;
  }

  // 潮汐取得
  // onedat = true : 1日詳細潮汐
  Future<void> getTide(bool oneday, DateTime tideDate) async {
    /*print(
      'getTide ${oneday == true ? "日" : "月"} ${tideDate.year}/${tideDate.month}/${tideDate.day}',
    );*/

    // 日付設定
    Common.instance.gSioInfo.inYear = tideDate.year;
    Common.instance.gSioInfo.inMonth = tideDate.month;
    Common.instance.gSioInfo.inDay = tideDate.day;

    // 釣り場指定
    String port = Common.instance.tidePoint;
    if (port.isEmpty) {
      // メモリに未設定の場合のみ、保存値を読み込む
      port = await Common.instance.loadPoint();
      // 初期化目的でメモリ側にも反映
      Common.instance.tidePoint = port;
    }
    Common.instance.gSioInfo.portName = port;

    // 釣り場ファイル名取得
    String fileName = Common.instance.getPortFileName(
      Common.instance.gSioInfo.portName,
    );

    // 釣り場情報取得（最寄り潮汐ポイントの調和定数などを読み込み）
    await getPortData(fileName, Common.instance.gSioInfo);

    // 指定漁港の緯度経度がある場合は、天文計算・潮汐計算の座標を漁港の座標へ置き換える
    if (selectedTeibouName.isNotEmpty &&
        selectedTeibouNearestPoint == Common.instance.gSioInfo.portName &&
        (selectedTeibouLat != 0.0 || selectedTeibouLng != 0.0)) {
      // decimal度 → dd.mm（分を百分表現）に変換して内部表現も更新
      gLat = selectedTeibouLat;
      gLng = selectedTeibouLng;
      gLat0 = dc2dg(gLat);
      gLng0 = dc2dg(gLng);
      // 日本国内はJST（135°）固定
      gZt = 135.0;
    }

    // 1日潮汐 ?
    if (oneday == true) {
      tideOneDay(Common.instance.gSioInfo);

      setOneDaySio(Common.instance.gSioInfo);
      int iAge = getMitikake(
        Common.instance.gSioInfo.age,
        Common.instance.gSioInfo.ilum,
      );

      Common.instance.moonFilePath = 'assets/moon/${moonInfo[iAge].moonFile}';
    } else {
      // 月
      sioPreMonthInfo.inYear = gSioInfo.inYear;
      sioPreMonthInfo.inMonth = gSioInfo.inMonth - 1;
      if (sioPreMonthInfo.inMonth == 0) {
        sioPreMonthInfo.inYear--;
        sioPreMonthInfo.inMonth = 12;
      }
      setTideMonth(sioPreMonthInfo);

      sio3MonthInfo.infoCnt = 0;

      copyMonthInfo(sio3MonthInfo, sioPreMonthInfo);

      // 1月潮汐取得
      sioMonthInfo.inYear = gSioInfo.inYear;
      sioMonthInfo.inMonth = gSioInfo.inMonth;
      setTideMonth(sioMonthInfo);
      copyMonthInfo(sio3MonthInfo, sioMonthInfo);

      sioNextMonthInfo.inYear = gSioInfo.inYear;
      sioNextMonthInfo.inMonth = gSioInfo.inMonth + 1;
      if (sioNextMonthInfo.inMonth > 12) {
        sioNextMonthInfo.inYear++;
        sioNextMonthInfo.inMonth = 1;
      }
      setTideMonth(sioNextMonthInfo);
      copyMonthInfo(sio3MonthInfo, sioNextMonthInfo);

      setMoonPhase(sio3MonthInfo);

      for (int ii = 0; ii < sio3MonthInfo.infoCnt; ii++) {
        if (sio3MonthInfo.sioSummaryDayInfo[ii].month == gSioInfo.inMonth) {
          for (int iii = 0; iii < sioMonthInfo.daycnt; iii++) {
            sioMonthInfo.sioSummaryDayInfo[iii].flag =
                sio3MonthInfo.sioSummaryDayInfo[ii + iii].flag;
            sioMonthInfo.sioSummaryDayInfo[iii].age2 =
                sio3MonthInfo.sioSummaryDayInfo[ii + iii].age2;
          }
          break;
        }
      }
    }
  }

  void setMoonPhase(Sio3MonthInfo sio3MonthInfo) {
    //int preAge = -1;
    for (int i = 0; i < sio3MonthInfo.infoCnt; i++) {
      int age = getMitikake(
        sio3MonthInfo.sioSummaryDayInfo[i].age,
        sio3MonthInfo.sioSummaryDayInfo[i].ilum,
      );
      sio3MonthInfo.sioSummaryDayInfo[i].age2 = age;

      if (age == 15) {
        sio3MonthInfo.sioSummaryDayInfo[i].flag = upIlum;
      } else if (age == 0) {
        sio3MonthInfo.sioSummaryDayInfo[i].flag = downIlum;
      } else if (age == 7) {
        sio3MonthInfo.sioSummaryDayInfo[i].flag = jyougenIlum;
      } else if (age == 22) {
        sio3MonthInfo.sioSummaryDayInfo[i].flag = kagenIlum;
      }
    }
  }

  // 指定したpoinntに対して、ファイル名称取得
  String getPortFileName(String name) {
    for (var row in portFileData) {
      // row[0] が名前、row[1] がメールアドレス
      if (row[0] == name) {
        return row[1];
      }
    }
    return '';
  }

  // **********************************************************
  // 天文計算用通日
  // ﾕﾘｳｽ日を求める式を利用したもの  暦便利帳
  // 2000年 1月 1日を第１日とする通日
  // この式の通用期間は、1582年10月15日以降永久に通用する
  // M[]の内容に関係なく通日が計算される
  // ***********************************************************/
  double serialZ(int yr, int mh, int dy) {
    int b, yK, xK;
    double a, c, z;

    if (mh > 2) {
      yK = yr;
      xK = mh;
    } else {
      yK = yr - 1;
      xK = mh + 12;
    }

    a = fix(yK / 100.0);
    b = (2.0 - a + fix(a / 4.0)).toInt();
    c = fix(365.25 * yK);
    z = fix(30.6001 * (xK + 1)) + b + c + dy;
    z = z - 730550.5;
    return z;
  }

  // fix 関数：x の小数部分を切り捨てた値を返す
  double fix(double x) {
    return x.truncateToDouble();
  }

  double frc(double x) {
    return (x - fix(x)) * 60.0;
  }

  // rnd: 関数の Dart 版
  double rnd(double x) {
    return x - (x / 360.0).floor() * 360.0;
  }

  // rnd2 関数の Dart 版
  double rnd2(double x) {
    return x - fix((x + sgn(x) * 180.0) / 360.0) * 360.0;
  }

  // sgn 関数
  int sgn(double x) {
    if (x > 0) return 1;
    if (x < 0) return -1;
    return 0;
  }

  // -------------------------------------------------
  // long_sun 関数
  // -------------------------------------------------
  double longSun(double t) {
    double g = 36000.77 * t;
    double g2 = rnd(g);
    g2 = g2 + 357.53;
    double ls = g2 - (77.06 - 1.91 * sin(g2 * dr));
    ls = rnd(ls);
    return rnd(ls);
  }

  // -------------------------------------------------
  // sunposition 関数
  // -------------------------------------------------
  Map<String, double> sunposition(double t) {
    double ls = longSun(t);
    double p = 23.44; // 黄道傾斜角（度）
    double u = cos(ls * dr);
    double v = sin(ls * dr) * cos(p * dr);
    double w = sin(ls * dr) * sin(p * dr);
    double ra = rnd(atan2(v, u) * rd);
    double dc = atan(w / sqrt(u * u + v * v)) * rd;
    return {'ra': ra, 'dc': dc};
  }

  // -------------------------------------------------
  // sun_meripass 関数
  // -------------------------------------------------
  double sunMeripass(double z, double lo) {
    double tu = 180.0 - lo;
    for (int i = 1; i < 3; i++) {
      double tj = tu / 360.0;
      double t = (z + tj) / 36525.0;
      var pos = sunposition(t);
      double ra = pos['ra']!;
      //double dc = pos['dc']!;
      double tg = grsidtime(t, tj);
      double hg = rnd(tg - ra);
      double lha = hg + lo;
      if (lha > 180.0) lha = lha - 360.0;
      if (lha < -180.0) lha = lha + 360.0;
      tu = tu - lha;
    }
    return tu;
  }

  // -------------------------------------------------
  // grsidtime 関数
  // -------------------------------------------------
  double grsidtime(double t, double tj) {
    double tg = 100.4604 + 36000.7695 * t + 360.0 * tj;
    return rnd(tg);
  }

  // -------------------------------------------------
  // riseset_hourangle 関数
  // -------------------------------------------------
  double risesetHourAngle(double x, double la, double dc) {
    double arg =
        (sin(x * dr) - sin(la * dr) * sin(dc * dr)) /
        (cos(la * dr) * cos(dc * dr));
    if (arg < -1.0 || arg > 1.0) {
      return 360.0;
    } else {
      return acos(arg) * rd;
    }
  }

  // -------------------------------------------------
  // subroutine 関数
  // -------------------------------------------------
  double subroutine(
    double als,
    double sg,
    double tu,
    double z,
    double la,
    double lo,
  ) {
    for (int i = 1; i < 3; i++) {
      double tj = tu / 360.0;
      double t = (z + tj) / 36525.0;
      var pos = sunposition(t);
      double ra = pos['ra']!;
      double dc = pos['dc']!;
      double tg = grsidtime(t, tj);
      double hg = rnd(tg - ra);
      double lha = hg + lo;
      if (lha > 180.0) {
        lha = lha - 360.0;
      }
      if (lha < -180.0) {
        lha = lha + 360.0;
      }
      double hr = risesetHourAngle(als, la, dc);
      if (hr == 360.0) {
        return 360.0;
      }
      tu = hr * sg + tu - lha;
      double lst = tu + lo;
      if (lst < 0.0 || lst > 360.0) {
        throw Exception("ERROR in Sunrise");
      }
    }
    return tu;
  }

  // -------------------------------------------------
  // sunrise 関数
  // -------------------------------------------------
  void sunrise(double z, double la, double lo, List<double> sunEvent) {
    double tu, als, sg;
    // Morning events
    tu = sunEvent[3]; // Meridian Passage
    als = -18.0;
    sg = -1.0;
    sunEvent[0] = subroutine(als, sg, tu, z, la, lo);
    if (sunEvent[0] != 360.0) tu = sunEvent[0];

    als = -6.0;
    sg = -1.0;
    sunEvent[1] = subroutine(als, sg, tu, z, la, lo);
    if (sunEvent[1] != 360.0) tu = sunEvent[1];

    als = -54.2 / 60.0;
    sg = -1.0;
    sunEvent[2] = subroutine(als, sg, tu, z, la, lo);
    if (sunEvent[2] != 360.0) tu = sunEvent[2];

    tu = sunEvent[3];

    // Evening events
    tu = sunEvent[3]; // Meridian Passage
    als = -18.0;
    sg = 1.0;
    sunEvent[6] = subroutine(als, sg, tu, z, la, lo);
    if (sunEvent[6] != 360.0) tu = sunEvent[6];

    als = -6.0;
    sg = 1.0;
    sunEvent[5] = subroutine(als, sg, tu, z, la, lo);
    if (sunEvent[5] != 360.0) tu = sunEvent[5];

    als = -54.2 / 60.0;
    sg = 1.0;
    sunEvent[4] = subroutine(als, sg, tu, z, la, lo);
  }

  // -------------------------------------------------
  // sun 関数
  // -------------------------------------------------
  void sun(int yr, int mh, int dy, double la, double lo, SioInfo tideInfo) {
    double z = serialZ(yr, mh, dy);
    double mp = sunMeripass(z, lo);
    List<double> sunEvent = List.filled(7, 0.0);
    sunEvent[3] = mp;
    sunrise(z, la, lo, sunEvent);

    for (int i = 0; i < 7; i++) {
      if (sunEvent[i] != 360.0) {
        sunEvent[i] = (sunEvent[i] + gZt) / 15.0;
      }
    }
    sunriseDisp(sunEvent, tideInfo);
  }

  String timePrint(double x) {
    // x の整数部分を時として取得
    int hour = x.floor();
    // 小数部分を分に変換して四捨五入
    int minute = ((x - x.floor()) * 60).round();

    // もし分が 60 になってしまったら、1時間加算して分を 0 にする
    if (minute == 60) {
      hour += 1;
      minute = 0;
    }

    // 2桁の時と分にフォーマットして返す（例："08:05"）
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  // -------------------------------------------------
  // sunrise_disp 関数
  // -------------------------------------------------
  void sunriseDisp(List<double> sunEvent, SioInfo tideInfo) {
    String buffer;
    if (sunEvent[2] == 360.0) {
      buffer = "**:**";
      tideInfo.pSunRise.hh = 0.0;
      tideInfo.pSunRise.mm = 0.0;
    } else {
      buffer = timePrint(sunEvent[2]);
      double arg1 = sunEvent[2].floorToDouble();
      double arg2 = (sunEvent[2] - sunEvent[2].floorToDouble()) * 60.0;
      tideInfo.pSunRise.hh = arg1;
      tideInfo.pSunRise.mm = arg2;
    }
    tideInfo.sunrise = buffer;
    if (sunEvent[4] == 360.0) {
      buffer = "**:**";
      tideInfo.pSunSet.hh = 0.0;
      tideInfo.pSunSet.mm = 0.0;
    } else {
      buffer = timePrint(sunEvent[4]);
      double arg1 = sunEvent[4].floorToDouble();
      double arg2 = (sunEvent[4] - sunEvent[4].floorToDouble()) * 60.0;
      tideInfo.pSunSet.hh = arg1;
      tideInfo.pSunSet.mm = arg2;
    }
    tideInfo.sunset = buffer;
  }

  // --------------------
  // sine_pai: 月の視差関連
  double sinePai(double t) {
    double sp = 0.950725;
    sp += 0.05182 * fnc(477198.868, t, 134.963);
    return sp;
  }

  // --------------------
  // moon_position: 月の位置（赤道座標）を計算して返す
  Map<String, double> moonPosition(double t) {
    double lm = longMoon(t);
    double bt = latMoon(t);
    double sp = sinePai(t);
    double hp = asin(sp * dr) * rd * 60;
    double sd = 0.2725 * hp;
    double p = 23.43928 - 0.01300417 * t;
    double u = cos(bt * dr) * cos(lm * dr);
    double v =
        cos(bt * dr) * sin(lm * dr) * cos(p * dr) - sin(bt * dr) * sin(p * dr);
    double w =
        cos(bt * dr) * sin(lm * dr) * sin(p * dr) + sin(bt * dr) * cos(p * dr);
    double ra = rnd(atan2(v, u) * rd);
    double dc = atan(w / sqrt(u * u + v * v)) * rd;
    return {'lm': lm, 'ra': ra, 'dc': dc, 'hp': hp, 'sd': sd};
  }

  // --------------------
  // lat_moon: 月の黄緯
  double latMoon(double t) {
    double bt;
    bt = 5.1281 * fnc(483202.019, t, 3.273);
    bt += 0.2806 * fnc(960400.89, t, 138.24);
    bt += 0.2777 * fnc(6003.15, t, 48.31);
    bt += 0.1733 * fnc(407332.2, t, 52.43);
    return bt;
  }

  // --------------------
  // moon_meripass: 月の正中時刻を求める
  double moonMeripass(double z, double lo) {
    double tu = 180.0 - lo;
    for (int i = 1; i < 3; i++) {
      double tj = tu / 360.0;
      double t = (z + tj) / 36525.0;
      // ここでは sunposition を流用（本来は太陽の赤経等ですが元のコードと同じ処理）
      Map<String, double> pos = sunposition(t); // ※ sunposition() は別途実装
      double ra = pos['ra']!;
      //double dc = pos['dc']!;
      double tg = grsidtime(t, tj);
      double hg = rnd(tg - ra);
      double lha = hg + lo;
      if (lha > 180.0) lha -= 360.0;
      if (lha < -180.0) lha += 360.0;
      tu = tu - lha;
    }
    return tu;
  }

  // --------------------
  // fnc: b*t+c を360で正規化し、cos(arg) を返す
  double fnc(double b, double t, double c) {
    double arg = b * t + c;
    arg = arg - (arg / 360.0).floor() * 360.0;
    double arg2 = cos(arg * dr);
    return arg2;
  }

  // 例: ポインタの代わりに Map<String, double> を返す
  Map<String, double> moonriseSet(double z, double la, double lo, double mmp) {
    double mr = 0.0;
    double ms = 0.0;
    double tu = mmp; // 正中時刻を使って計算開始

    // Moonrise の計算
    for (int J = 1; J < 4; J++) {
      double tJ = tu / 360.0;
      double t = (z + tJ) / 36525.0;
      double tg = grsidtime(t, tJ); // grsidtime() は別途定義
      // moonPosition() は月の位置（黄経、赤経、赤緯、視差など）を Map で返すと仮定
      Map<String, double> pos = moonPosition(t);
      double ra = pos["ra"]!;
      double dc = pos["dc"]!;
      double hp = pos["hp"]!;
      double sd = pos["sd"]!;
      double lha = rnd2(tg - ra + lo); // rnd2() は丸め処理の補助関数
      double ac = (-34.0 - sd + hp) / 60.0;
      double hr = risesetHourAngle(ac, la, dc); // risesetHourAngle() は出没時角を返す関数
      if (hr == 360.0) {
        mr = 360.0;
        break;
      } else {
        tu = -hr + tu - lha;
        mr = tu;
      }
    }

    // Moonset の計算
    tu = mmp;
    for (int J = 1; J < 4; J++) {
      double tJ = tu / 360.0;
      double t = (z + tJ) / 36525.0;
      double tg = grsidtime(t, tJ);
      Map<String, double> pos = moonPosition(t);
      double ra = pos["ra"]!;
      double dc = pos["dc"]!;
      double hp = pos["hp"]!;
      double sd = pos["sd"]!;
      double lha = rnd2(tg - ra + lo);
      double ac = (-34.0 - sd + hp) / 60.0;
      double hr = risesetHourAngle(ac, la, dc);
      if (hr == 360.0) {
        ms = 360.0;
        break;
      } else {
        tu = hr + tu - lha;
        ms = tu;
      }
    }
    return {"mr": mr, "ms": ms, "mmp": mmp};
  }

  // --------------------
  // sio: 月齢から潮決定のインデックスを返す
  int sio(double age) {
    int k = 0;
    if (age <= 1.5) {
      k = 0;
    } else if (age > 1.5 && age <= 5.5) {
      k = 1;
    } else if (age > 5.5 && age <= 8.5) {
      k = 2;
    } else if (age > 8.5 && age <= 9.5) {
      k = 3;
    } else if (age > 9.5 && age <= 10.5) {
      k = 4;
    } else if (age > 10.5 && age <= 12.5) {
      k = 5;
    } else if (age > 12.5 && age <= 16.5) {
      k = 6;
    } else if (age > 16.5 && age <= 20.5) {
      k = 7;
    } else if (age > 20.5 && age <= 23.5) {
      k = 8;
    } else if (age > 23.5 && age <= 24.5) {
      k = 9;
    } else if (age > 24.5 && age <= 25.5) {
      k = 10;
    } else if (age > 25.5 && age <= 27.5) {
      k = 11;
    } else if (age > 27.5 && age <= 30.5) {
      k = 12;
    }
    return k;
  }

  // --------------------
  // moon_age: 月齢を計算する
  double moonAge(double td12, double lm12, double ls12) {
    double age = lm12 - ls12;
    if (age < 0) age += 360;
    double x = 29.5305 * age / 360;
    double td = td12 - x;
    double smd = 0;
    int incl = 3;
    td = moonAgeSub(incl, td, smd);
    return td12 - td;
  }

  // --------------------
  // moon_age_sub: Newton‐Raphson法による月太陽黄経差が所定値になる時刻を求める
  double moonAgeSub(int incl, double td, double smd) {
    double lm, ls, t, x;
    for (int j = 1; j <= incl; j++) {
      t = td / 36525.0;
      lm = longMoon(t);
      ls = longSun(t);
      x = 29.5305 * rnd2(lm - ls - smd) / 360;
      td = td - x;
    }
    return td;
  }

  // --------------------
  // moon 関数：指定年月日と観測地の緯度経度から月の情報を計算
  void moon(int yr, int mh, int dy, double la, double lo, SioInfo tideInfo) {
    int dyMr, dyMp, dyMs;
    double lm12, bt12, ls12, td12;
    double tu, tj, z;
    double t;
    double mmp, mr, ms;
    double smd, smd12, iota;
    String buffer = "";

    z = serialZ(yr, mh, dy); // serialZ は別途定義
    tu = 180.0 - gZt;
    tj = tu / 360.0;
    td12 = z + tj;
    t = (z + tj) / 36525.0;

    ls12 = longSun(t);
    lm12 = longMoon(t);
    bt12 = latMoon(t);
    mmp = moonMeripass(z, lo);

    // moonrise: moonrise 関数は Map<String, double> を返すものとする
    var mrms = moonriseSet(z, la, lo, mmp);
    mr = mrms['mr']!;
    mmp = mrms['mmp']!;
    ms = mrms['ms']!;

    tideInfo.age = moonAge(td12, lm12, ls12);

    mmp = (mmp + gZt) / 15.0;
    dyMr = dy;
    dyMp = dy;
    dyMs = dy;

    if (mmp > 24) {
      dyMp = dy + 1;
      mmp = mmp - 24;
      if (dyMp > gMonthDay[mh]) dyMp = 1;
    }

    if (mr != 360.0) {
      mr = (mr + gZt) / 15.0;
      ms = (ms + gZt) / 15.0;
      if (mr < 0) {
        dyMr = dy - 1;
        mr = mr + 24;
        if (dyMr < 1) dyMr = gMonthDay[mh - 1];
      }
      if (ms > 24) {
        dyMs = dy + 1;
        ms = ms - 24;
        if (dyMs > gMonthDay[mh]) dyMs = 1;
      }
    }

    smd12 = rnd(lm12 - ls12);
    smd = cos(smd12 * dr) * cos(bt12 * dr);
    smd = acos(smd) * rd;
    iota = 180 - smd - 0.1468 * sin(smd * dr);

    tideInfo.ilum = (1 + cos(iota * dr)) / 2 * 100;

    // 月の満ち欠け（sio）設定
    tideInfo.sio = gShio[sio(tideInfo.age)];

    // moon_out: if mr == 360.0 → "**日 **:**", elseフォーマット
    if (mr == 360.0) {
      buffer = "**日 **:**";
    } else {
      buffer =
          "${dyMp.toString().padLeft(2, ' ')}日 ${fix(mr).toStringAsFixed(0)}:${frc(mr).toStringAsFixed(0)}";
    }
    tideInfo.moonOut = buffer;

    if (ms == 360.0) {
      buffer = "**日 **:**";
    } else {
      buffer =
          "${dyMs.toString().padLeft(2, ' ')}日 ${fix(ms).toStringAsFixed(0)}:${frc(ms).toStringAsFixed(0)}";
    }
    tideInfo.moonIn = buffer;
  }

  // --------------------
  // long_moon: 月の黄経（幾何学的）
  double longMoon(double t) {
    double arg;
    double lm = 218.316;
    arg = 481267.8809 * t;
    arg = arg - (arg / 360.0).floor() * 360.0;
    lm = lm + arg - 0.00133 * t * t;
    lm += 6.2888 * fnc(477198.868, t, 44.963);
    lm += 1.274 * fnc(413335.35, t, 10.74);
    lm += 0.6583 * fnc(890534.22, t, 145.7);
    lm += 0.2136 * fnc(954397.74, t, 179.93);
    lm += 0.1851 * fnc(35999.05, t, 87.53);
    lm += 0.1144 * fnc(966404.0, t, 276.5);
    lm += 0.0588 * fnc(63863.5, t, 124.2);
    lm += 0.0571 * fnc(377336.3, t, 13.2);
    lm += 0.0533 * fnc(1367733.1, t, 280.7);
    lm += 0.0458 * fnc(854535.2, t, 148.2);
    lm += 0.0409 * fnc(441199.8, t, 47.4);
    lm += 0.0347 * fnc(445267.1, t, 27.9);
    lm += 0.0304 * fnc(513197.9, t, 222.5);
    lm = rnd(lm);
    return rnd(lm);
  }

  void oneDayTides(bool detailFlag, SioInfo tideInfo) {
    // 変数宣言
    double ddlat, mmlat, ddlng, mmlng;

    // グローバル変数 g_lat0, g_lng0 を絶対値に
    gLat0 = gLat0.abs();
    gLng0 = gLng0.abs();

    ddlat = gLat0.floorToDouble();
    mmlat = (gLat0 - ddlat) * 100.0;

    ddlng = gLng0.floorToDouble();
    mmlng = (gLng0 - ddlng) * 100.0;

    // 太陽、月の出没・月齢の計算
    sun(
      tideInfo.inYear,
      tideInfo.inMonth,
      tideInfo.inDay,
      gLat,
      gLng,
      tideInfo,
    );
    moon(
      tideInfo.inYear,
      tideInfo.inMonth,
      tideInfo.inDay,
      gLat,
      gLng,
      tideInfo,
    );

    if (detailFlag) {
      getTidePoint(tideInfo, gF, gHr, gVl, gAgs, gPl, 0);
      getTidePoint(tideInfo, gF, gHr, gVl, gAgs, gPl, 1);
    }
  }

  String moonFilePath = '';

  // サーバーにユーザー登録を依頼する処理
  Future<Map<String, dynamic>> sendmail(
    String email,
    String authenticationNumber,
  ) async {
    // 指定メールに指定認証番号を送信
    final response = await http.post(
      Uri.parse('${AppConfig.instance.baseUrl}send_number.php'),
      body: {'mail': email, 'authenticationNumber': authenticationNumber},
    );

    if (response.statusCode == 200) {
      // サーバー側で JSON エンコードされた配列を返す前提
      return json.decode(response.body);
    } else {
      throw Exception(
        'Failed to register user. Status code: ${response.statusCode}',
      );
    }
  }

  // メール形式チェック用の正規表現
  bool isValidEmail(String email) {
    final RegExp emailRegExp = RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegExp.hasMatch(email);
  }

  // 推奨パターンチェック用の正規表現
  bool isValidPassword(String password) {
    /*  // 8文字以上で、大文字・小文字・数字・特殊文字(@$!%*?&#)をそれぞれ最低1文字含む
    final RegExp passwordRegExp = RegExp(
        r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[@$!%*?&#])[A-Za-z\d@$!%*?&#]{8,}$');
    return passwordRegExp.hasMatch(password);
    */
    return true;
  }

  // サーバーにユーザー登録を依頼する処理
  Future<Map<String, dynamic>> checkRegistUser(
    String email,
    String uuid,
  ) async {
    final response = await http.post(
      Uri.parse('${AppConfig.instance.baseUrl}user_check.php'),
      body: {'mail': email, 'uuid': uuid},
    );

    if (response.statusCode == 200) {
      // サーバー側で JSON エンコードされた配列を返す前提
      return json.decode(response.body);
    } else if (response.statusCode == 500) {
      throw Exception(json.decode(response.body)['reason']);
    } else {
      throw Exception(
        'Failed to register user. Status code: ${response.statusCode}',
      );
    }
  }

  // 選択された行を特定するための GlobalKey を用意
  final GlobalKey selectedKey = GlobalKey();
  // 確認コード取得 6桁のランダムな数値を返す
  String getRandomNumber() {
    Random random = Random();
    int number = random.nextInt(1000000); // 0から999999までの整数を生成
    String authenticationNumber = number.toString().padLeft(6, '0');
    return authenticationNumber;
  }
}
