import 'common.dart';

class Location {
  // プライベートコンストラクタ
  Location._privateConstructor();

  // 唯一のインスタンスを生成して保持する静的フィールド
  static final Location _instance = Location._privateConstructor();

  // グローバルアクセサ
  static Location get instance => _instance;

  // ハードコードした例のデータ
  List<Map<String, dynamic>> locationData = [
    {
      'region': '北海道',
      'prefecture': '北海道',
      'spots': [
        {'name': '函館', 'flag': 0},
        {'name': '吉岡', 'flag': 0},
        {'name': '室蘭', 'flag': 0},
        {'name': '小樽', 'flag': 0},
        {'name': '忍路', 'flag': 0},
        {'name': '浦河', 'flag': 0},
        {'name': '留萌', 'flag': 0},
        {'name': '稚内', 'flag': 0},
        {'name': '紋別', 'flag': 0},
        {'name': '網走', 'flag': 0},
        {'name': '花咲', 'flag': 0},
        {'name': '苫小牧', 'flag': 0},
        {'name': '釧路', 'flag': 0},
      ],
    },
    {
      'region': '東北',
      'prefecture': '青森県',
      'spots': [
        {'name': '三厩', 'flag': 0},
        {'name': '八戸', 'flag': 0},
        {'name': '大湊', 'flag': 0},
        {'name': '大畑', 'flag': 0},
        {'name': '大間', 'flag': 0},
        {'name': '小泊', 'flag': 0},
        {'name': '小湊', 'flag': 0},
        {'name': '尻矢', 'flag': 0},
        {'name': '尻矢崎', 'flag': 0},
        {'name': '岩崎', 'flag': 0},
        {'name': '泊', 'flag': 0},
        {'name': '浅虫', 'flag': 0},
        {'name': '深浦', 'flag': 0},
        {'name': '白糠', 'flag': 0},
        {'name': '竜飛', 'flag': 0},
        {'name': '竜飛埼', 'flag': 0},
        {'name': '茂浦', 'flag': 0},
        {'name': '野辺地', 'flag': 0},
        {'name': '関根浜', 'flag': 0},
        {'name': '青森', 'flag': 0},
        {'name': '鯵ヶ沢', 'flag': 0},
      ],
    },
    {
      'region': '東北',
      'prefecture': '岩手県',
      'spots': [
        {'name': '久慈', 'flag': 0},
        {'name': '八木', 'flag': 0},
        {'name': '大船渡', 'flag': 0},
        {'name': '宮古', 'flag': 0},
        {'name': '山田', 'flag': 0},
        {'name': '釜石', 'flag': 0},
      ],
    },
    {
      'region': '東北',
      'prefecture': '宮城県',
      'spots': [
        {'name': '仙台', 'flag': 0},
        {'name': '塩釜仙', 'flag': 0},
        {'name': '塩釜港', 'flag': 0},
        {'name': '女川', 'flag': 0},
        {'name': '志津川', 'flag': 0},
        {'name': '気仙沼', 'flag': 0},
        {'name': '港橋', 'flag': 0},
        {'name': '石巻', 'flag': 0},
        {'name': '石浜', 'flag': 0},
        {'name': '船越湾', 'flag': 0},
        {'name': '花淵浜', 'flag': 0},
        {'name': '荻浜', 'flag': 0},
        {'name': '野蒜湾', 'flag': 0},
        {'name': '閖上', 'flag': 0},
        {'name': '鮎川', 'flag': 0},
      ],
    },
    {
      'region': '東北',
      'prefecture': '秋田県',
      'spots': [
        {'name': '岩舘', 'flag': 0},
        {'name': '男鹿', 'flag': 0},
        {'name': '秋田', 'flag': 0},
        {'name': '金浦', 'flag': 0},
      ],
    },
    {
      'region': '東北',
      'prefecture': '山形県',
      'spots': [
        {'name': '加茂', 'flag': 0},
        {'name': '由良', 'flag': 0},
        {'name': '酒田', 'flag': 0},
        {'name': '鼠ヶ関', 'flag': 0},
      ],
    },
    {
      'region': '東北',
      'prefecture': '福島県',
      'spots': [
        {'name': '四倉', 'flag': 0},
        {'name': '夫沢', 'flag': 0},
        {'name': '富岡', 'flag': 0},
        {'name': '小名浜', 'flag': 0},
        {'name': '松川浦', 'flag': 0},
        {'name': '相馬', 'flag': 0},
      ],
    },
    {
      'region': '関東',
      'prefecture': '茨城県',
      'spots': [
        {'name': '大洗', 'flag': 0},
        {'name': '大津', 'flag': 0},
        {'name': '日立', 'flag': 0},
        {'name': '那珂湊', 'flag': 0},
        {'name': '鹿島', 'flag': 0},
      ],
    },
    {
      'region': '関東',
      'prefecture': '千葉県',
      'spots': [
        {'name': '一海堡', 'flag': 0},
        {'name': '上総勝', 'flag': 0},
        {'name': '勝浦', 'flag': 0},
        {'name': '千葉灯', 'flag': 0},
        {'name': '名洗', 'flag': 0},
        {'name': '君津', 'flag': 0},
        {'name': '姉崎', 'flag': 0},
        {'name': '寒川', 'flag': 0},
        {'name': '岩井袋', 'flag': 0},
        {'name': '市原', 'flag': 0},
        {'name': '市川', 'flag': 0},
        {'name': '布良', 'flag': 0},
        {'name': '犬吠崎', 'flag': 0},
        {'name': '白浜', 'flag': 0},
        {'name': '船橋', 'flag': 0},
        {'name': '銚子', 'flag': 0},
        {'name': '銚子新', 'flag': 0},
        {'name': '銚子港', 'flag': 0},
        {'name': '館山', 'flag': 0},
        {'name': '鴨川', 'flag': 0},
      ],
    },
    {
      'region': '関東',
      'prefecture': '東京都',
      'spots': [
        {'name': '三宅島', 'flag': 0},
        {'name': '二見', 'flag': 0},
        {'name': '八重根', 'flag': 0},
        {'name': '岡田', 'flag': 0},
        {'name': '式根島', 'flag': 0},
        {'name': '晴海', 'flag': 0},
        {'name': '母島', 'flag': 0},
        {'name': '波浮', 'flag': 0},
        {'name': '父島', 'flag': 0},
        {'name': '硫黄島', 'flag': 0},
        {'name': '神津島', 'flag': 0},
        {'name': '神湊', 'flag': 0},
        {'name': '築地', 'flag': 0},
        {'name': '羽田', 'flag': 0},
        {'name': '芝浦', 'flag': 0},
        {'name': '阿古', 'flag': 0},
        {'name': '鳥島', 'flag': 0},
      ],
    },
    {
      'region': '関東',
      'prefecture': '神奈川県',
      'spots': [
        {'name': '向ヶ崎', 'flag': 0},
        {'name': '塩浜運', 'flag': 0},
        {'name': '小田和', 'flag': 0},
        {'name': '川崎', 'flag': 0},
        {'name': '新宿湾', 'flag': 0},
        {'name': '新山下', 'flag': 0},
        {'name': '新港', 'flag': 0},
        {'name': '末広', 'flag': 0},
        {'name': '根岸', 'flag': 0},
        {'name': '横浜', 'flag': 0},
        {'name': '横浜新', 'flag': 0},
        {'name': '横須賀', 'flag': 0},
        {'name': '江ノ島', 'flag': 0},
        {'name': '油壷', 'flag': 0},
        {'name': '真鶴', 'flag': 0},
        {'name': '走水', 'flag': 0},
        {'name': '金田湾', 'flag': 0},
        {'name': '長浦', 'flag': 0},
        {'name': '間口', 'flag': 0},
      ],
    },
    {
      'region': '中部',
      'prefecture': '新潟県',
      'spots': [
        {'name': '小木', 'flag': 0},
        {'name': '新潟東', 'flag': 0},
        {'name': '新潟西', 'flag': 0},
        {'name': '柏崎', 'flag': 0},
        {'name': '直江津', 'flag': 0},
        {'name': '粟島', 'flag': 0},
        {'name': '能生', 'flag': 0},
      ],
    },
    {
      'region': '中部',
      'prefecture': '富山県',
      'spots': [
        {'name': '伏木', 'flag': 0},
        {'name': '富山', 'flag': 0},
      ],
    },
    {
      'region': '中部',
      'prefecture': '石川県',
      'spots': [
        {'name': '輪島', 'flag': 0},
        {'name': '金沢', 'flag': 0},
      ],
    },
    {
      'region': '中部',
      'prefecture': '福井県',
      'spots': [
        {'name': '三国', 'flag': 0},
        {'name': '内浦湾', 'flag': 0},
        {'name': '小浜', 'flag': 0},
        {'name': '敦賀', 'flag': 0},
        {'name': '福井', 'flag': 0},
      ],
    },
    {
      'region': '中部',
      'prefecture': '静岡県',
      'spots': [
        {'name': '三保', 'flag': 0},
        {'name': '三津', 'flag': 0},
        {'name': '伊東', 'flag': 0},
        {'name': '南伊豆', 'flag': 0},
        {'name': '妻良', 'flag': 0},
        {'name': '宇久須', 'flag': 0},
        {'name': '川奈', 'flag': 0},
        {'name': '御前崎', 'flag': 0},
        {'name': '御津', 'flag': 0},
        {'name': '江ノ浦', 'flag': 0},
        {'name': '清水', 'flag': 0},
        {'name': '焼津', 'flag': 0},
        {'name': '田子', 'flag': 0},
        {'name': '田子浦', 'flag': 0},
        {'name': '白浜', 'flag': 0},
        {'name': '相良', 'flag': 0},
        {'name': '網代', 'flag': 0},
        {'name': '興津', 'flag': 0},
        {'name': '舞阪', 'flag': 0},
      ],
    },
    {
      'region': '中部',
      'prefecture': '愛知県',
      'spots': [
        {'name': '伊良胡', 'flag': 0},
        {'name': '名古屋', 'flag': 0},
        {'name': '師崎', 'flag': 0},
        {'name': '武豊', 'flag': 0},
        {'name': '神島', 'flag': 0},
        {'name': '蒲郡', 'flag': 0},
        {'name': '豊橋', 'flag': 0},
        {'name': '赤羽', 'flag': 0},
        {'name': '赤羽根', 'flag': 0},
        {'name': '鬼崎', 'flag': 0},
      ],
    },
    {
      'region': '近畿',
      'prefecture': '三重県',
      'spots': [
        {'name': '五ヵ所', 'flag': 0},
        {'name': '四日市', 'flag': 0},
        {'name': '尾鷲', 'flag': 0},
        {'name': '松阪', 'flag': 0},
        {'name': '的矢', 'flag': 0},
        {'name': '長島', 'flag': 0},
        {'name': '鳥羽', 'flag': 0},
      ],
    },
    {
      'region': '近畿',
      'prefecture': '京都府',
      'spots': [
        {'name': '島崎', 'flag': 0},
        {'name': '舞鶴東', 'flag': 0},
        {'name': '舞鶴西', 'flag': 0},
      ],
    },
    {
      'region': '近畿',
      'prefecture': '大阪府',
      'spots': [
        {'name': '堺', 'flag': 0},
        {'name': '大阪', 'flag': 0},
        {'name': '岸和田', 'flag': 0},
        {'name': '泉大津', 'flag': 0},
        {'name': '淡輪', 'flag': 0},
      ],
    },
    {
      'region': '近畿',
      'prefecture': '兵庫県',
      'spots': [
        {'name': '垂水', 'flag': 0},
        {'name': '室津', 'flag': 0},
        {'name': '家島', 'flag': 0},
        {'name': '尼崎', 'flag': 0},
        {'name': '岩屋', 'flag': 0},
        {'name': '明石', 'flag': 0},
        {'name': '江井', 'flag': 0},
        {'name': '江崎', 'flag': 0},
        {'name': '洲本', 'flag': 0},
        {'name': '由良', 'flag': 0},
        {'name': '神戸', 'flag': 0},
        {'name': '福良', 'flag': 0},
        {'name': '飾磨', 'flag': 0},
        {'name': '高砂', 'flag': 0},
      ],
    },
    {
      'region': '近畿',
      'prefecture': '和歌山県',
      'spots': [
        {'name': '下津', 'flag': 0},
        {'name': '串本', 'flag': 0},
        {'name': '和歌山', 'flag': 0},
        {'name': '沖ノ島', 'flag': 0},
        {'name': '浦神', 'flag': 0},
        {'name': '海南', 'flag': 0},
        {'name': '田辺', 'flag': 0},
      ],
    },
    {
      'region': '中国',
      'prefecture': '鳥取県',
      'spots': [
        {'name': '境', 'flag': 0},
        {'name': '田後', 'flag': 0},
      ],
    },
    {
      'region': '中国',
      'prefecture': '島根県',
      'spots': [
        {'name': '外ノ浦', 'flag': 0},
        {'name': '西郷', 'flag': 0},
      ],
    },
    {
      'region': '中国',
      'prefecture': '岡山県',
      'spots': [
        {'name': '宇野', 'flag': 0},
        {'name': '水島', 'flag': 0},
        {'name': '笠岡', 'flag': 0},
      ],
    },
    {
      'region': '中国',
      'prefecture': '広島県',
      'spots': [
        {'name': '厳島', 'flag': 0},
        {'name': '呉', 'flag': 0},
        {'name': '尾道', 'flag': 0},
        {'name': '広島', 'flag': 0},
        {'name': '福山', 'flag': 0},
        {'name': '竹原', 'flag': 0},
        {'name': '糸崎', 'flag': 0},
      ],
    },
    {
      'region': '中国',
      'prefecture': '山口県',
      'spots': [
        {'name': '三田尻', 'flag': 0},
        {'name': '上の関', 'flag': 0},
        {'name': '下関桟', 'flag': 0},
        {'name': '両源田', 'flag': 0},
        {'name': '南風泊', 'flag': 0},
        {'name': '壇ノ浦', 'flag': 0},
        {'name': '大山鼻', 'flag': 0},
        {'name': '大泊', 'flag': 0},
        {'name': '宇部', 'flag': 0},
        {'name': '岩国', 'flag': 0},
        {'name': '弟子待', 'flag': 0},
        {'name': '徳山', 'flag': 0},
        {'name': '東安下', 'flag': 0},
        {'name': '沖家室', 'flag': 0},
        {'name': '油谷', 'flag': 0},
        {'name': '田の首', 'flag': 0},
        {'name': '萩', 'flag': 0},
        {'name': '長府', 'flag': 0},
      ],
    },
    {
      'region': '四国',
      'prefecture': '徳島県',
      'spots': [
        {'name': '堂ノ浦', 'flag': 0},
        {'name': '小松島', 'flag': 0},
      ],
    },
    {
      'region': '四国',
      'prefecture': '香川県',
      'spots': [
        {'name': '与島', 'flag': 0},
        {'name': '佐柳', 'flag': 0},
        {'name': '坂出', 'flag': 0},
        {'name': '坂手', 'flag': 0},
        {'name': '引田', 'flag': 0},
        {'name': '男木島', 'flag': 0},
        {'name': '粟島', 'flag': 0},
        {'name': '青木', 'flag': 0},
        {'name': '高松', 'flag': 0},
      ],
    },
    {
      'region': '四国',
      'prefecture': '愛媛県',
      'spots': [
        {'name': '三島', 'flag': 0},
        {'name': '三机', 'flag': 0},
        {'name': '今治', 'flag': 0},
        {'name': '八幡浜', 'flag': 0},
        {'name': '宇和島', 'flag': 0},
        {'name': '小島', 'flag': 0},
        {'name': '新居浜', 'flag': 0},
        {'name': '日振島', 'flag': 0},
        {'name': '松山', 'flag': 0},
        {'name': '波止浜', 'flag': 0},
        {'name': '興居島', 'flag': 0},
        {'name': '菊間', 'flag': 0},
        {'name': '西条', 'flag': 0},
        {'name': '長浜', 'flag': 0},
        {'name': '青島', 'flag': 0},
        {'name': '鼻粟瀬', 'flag': 0},
      ],
    },
    {
      'region': '四国',
      'prefecture': '高知県',
      'spots': [
        {'name': '土佐清', 'flag': 0},
        {'name': '室戸岬', 'flag': 0},
        {'name': '高知', 'flag': 0},
      ],
    },
    {
      'region': '九州',
      'prefecture': '福岡県',
      'spots': [
        {'name': '三池', 'flag': 0},
        {'name': '八幡', 'flag': 0},
        {'name': '博多船', 'flag': 0},
        {'name': '室戸岬', 'flag': 0},
        {'name': '日明', 'flag': 0},
        {'name': '旧門司', 'flag': 0},
        {'name': '砂津', 'flag': 0},
        {'name': '福岡船', 'flag': 0},
        {'name': '苅田', 'flag': 0},
        {'name': '若松', 'flag': 0},
        {'name': '西海岸', 'flag': 0},
        {'name': '青浜', 'flag': 0},
      ],
    },
    {
      'region': '九州',
      'prefecture': '佐賀県',
      'spots': [
        {'name': '仮屋', 'flag': 0},
        {'name': '唐津', 'flag': 0},
        {'name': '竹崎島', 'flag': 0},
      ],
    },
    {
      'region': '九州',
      'prefecture': '長崎県',
      'spots': [
        {'name': '久根浜', 'flag': 0},
        {'name': '佐世保', 'flag': 0},
        {'name': '佐賀', 'flag': 0},
        {'name': '佐須奈', 'flag': 0},
        {'name': '厳原', 'flag': 0},
        {'name': '口之津', 'flag': 0},
        {'name': '巌原', 'flag': 0},
        {'name': '志々伎', 'flag': 0},
        {'name': '松ヶ枝', 'flag': 0},
        {'name': '松浦', 'flag': 0},
        {'name': '深堀', 'flag': 0},
        {'name': '福江', 'flag': 0},
        {'name': '芦辺', 'flag': 0},
        {'name': '郷ノ浦', 'flag': 0},
        {'name': '青方', 'flag': 0},
        {'name': '鴨居瀬', 'flag': 0},
      ],
    },
    {
      'region': '九州',
      'prefecture': '熊本県',
      'spots': [
        {'name': '三角', 'flag': 0},
        {'name': '八代', 'flag': 0},
        {'name': '富岡', 'flag': 0},
        {'name': '本渡', 'flag': 0},
        {'name': '柳瀬戸', 'flag': 0},
        {'name': '水俣', 'flag': 0},
        {'name': '池の浦', 'flag': 0},
        {'name': '熊本', 'flag': 0},
        {'name': '牛深', 'flag': 0},
        {'name': '袋浦', 'flag': 0},
        {'name': '長洲', 'flag': 0},
      ],
    },
    {
      'region': '九州',
      'prefecture': '大分県',
      'spots': [
        {'name': '下浦', 'flag': 0},
        {'name': '姫島', 'flag': 0},
        {'name': '西大分', 'flag': 0},
        {'name': '長島', 'flag': 0},
        {'name': '高田', 'flag': 0},
        {'name': '鶴崎', 'flag': 0},
      ],
    },
    {
      'region': '九州',
      'prefecture': '宮崎県',
      'spots': [
        {'name': '宮崎', 'flag': 0},
        {'name': '油津', 'flag': 0},
        {'name': '細島', 'flag': 0},
      ],
    },
    {
      'region': '九州',
      'prefecture': '鹿児島県',
      'spots': [
        {'name': '中之島', 'flag': 0},
        {'name': '古仁屋', 'flag': 0},
        {'name': '名瀬', 'flag': 0},
        {'name': '喜入', 'flag': 0},
        {'name': '大泊', 'flag': 0},
        {'name': '枕崎', 'flag': 0},
        {'name': '西之表', 'flag': 0},
        {'name': '阿久根', 'flag': 0},
        {'name': '鹿児島', 'flag': 0},
      ],
    },
    {
      'region': '九州',
      'prefecture': '沖縄県',
      'spots': [
        {'name': '平良', 'flag': 0},
        {'name': '波照間', 'flag': 0},
        {'name': '石垣', 'flag': 0},
        {'name': '石川', 'flag': 0},
        {'name': '西表島', 'flag': 0},
        {'name': '那覇', 'flag': 0},
      ],
    },
  ];

  void removeFavoriteSpot() {
    // お気に入りフラグリセット
    for (int i = locationData.length - 1; i >= 0; i--) {
      final entry = locationData[i];
      final String region = entry['region'] as String;
      if (region == 'お気に入り') {
        locationData.removeAt(i);
      }
    }
    //setState(() {
    addFavorite();
    Common.instance.notify();
    //});
  }

  void resetFlag() {
    // お気に入りフラグリセット
    for (var entry in locationData) {
      final String region = entry['region'] as String;
      final String prefecture = entry['prefecture'] as String;
      final List spots = (entry['spots'] as List?) ?? [];
      if (region != 'お気に入り') {
        for (var spot in spots) {
          spot['flag'] = 0;
        }
      }
    }
  }

  void setFavoriteFlag(String prefecture1, String spot1, int flag) {
    bool find = false;

    // お気に入りフラグリセット
    for (var entry in locationData) {
      final String region = entry['region'] as String;
      final String prefecture = entry['prefecture'] as String;
      final List spots = (entry['spots'] as List?) ?? [];
      if (region != 'お気に入り') {
        for (var spot in spots) {
          if (prefecture == prefecture1 && spot['name'] == spot1) {
            spot['flag'] = flag;
            find = true;
            if (flag == 1) {
              Common.instance.sioDb.addFavorite(prefecture1, spot1);
            } else {
              Common.instance.sioDb.removeFavorite(prefecture1, spot1);
            }
            break;
          }
        }
      }
      if (find == true) {
        break;
      }
    }
  }

  Future<void> addFavorite() async {
    // お気に入りリストを空の List<Map<String, dynamic>> で初期化
    List<Map<String, dynamic>> favoriteSpots = [];

    // locationData の各エントリーを処理
    for (var entry in locationData) {
      final String region = entry['region'] as String;
      final String prefecture = entry['prefecture'] as String;
      final List spots = (entry['spots'] as List?) ?? [];
      if (region != 'お気に入り') {
        // 'お気に入り' 以外の場合、各スポットの flag が 1 の場合のみ追加
        for (var spot in spots) {
          // spot は {'name': '下浦', 'flag': 0} のような Map である前提
          String name = spot['name'];
          int flag = spot['flag'];
          if (flag == 1) {
            // flag が 1 ならお気に入りに追加
            Map<String, dynamic> item = {
              'region': 'お気に入り',
              'prefecture': prefecture,
              'spots': [
                {'name': name, 'flag': 0},
              ],
            };
            favoriteSpots.add(item);
          }
        }
      }
    }
    locationData = favoriteSpots + locationData;
  }
}
