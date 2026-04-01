import 'common_class.dart';

class LagrangeCalculator {
  // static変数（配列は0番は使わず1～4を利用）
  static int k = 0;
  static List<int> sg = [0, 0, 0, 0, 0];
  static List<double> tm = [0, 0, 0, 0, 0];
  static List<double> tArr = [0, 0, 0, 0, 0]; // t 配列（名前がtなので予約語との混同を避けるため tArr としています）
  static List<double> fx = [0, 0, 0, 0, 0];
  static List<double> df = [0, 0, 0, 0, 0];

  // sgn 関数：値の符号を返す
  static int sgn(double value) {
    if (value > 0) return 1;
    if (value < 0) return -1;
    return 0;
  }

  /// [T] と [y] はそれぞれシングル要素のリストとして渡し、値の更新を行います。
  /// 戻り値は条件に応じて 1 または 0 を返します。
  static int lagrange(FloatWrapper T, FloatWrapper y) {
    // T[0] が -60.0 の場合、k をリセット
    if (T.value == -60.0) {
      k = 0;
    }

    k = k + 1;
    // tm 配列のシフト（tm[1] = tm[2], tm[2] = tm[3], tm[3] = tm[4], tm[4] = T[0]）
    tm[1] = tm[2];
    tm[2] = tm[3];
    tm[3] = tm[4];
    tm[4] = T.value;

    // fx 配列のシフト（fx[1] = fx[2], fx[2] = fx[3], fx[3] = fx[4], fx[4] = y[0]）
    fx[1] = fx[2];
    fx[2] = fx[3];
    fx[3] = fx[4];
    fx[4] = y.value;

    // df 配列のシフトと更新（df[1] = df[2], df[2] = df[3], df[3] = fx[4] - fx[3]）
    df[1] = df[2];
    df[2] = df[3];
    df[3] = fx[4] - fx[3];

    // sg 配列のシフトと更新（sg[1] = sg[2], sg[2] = sg[3], sg[3] = sgn(df[3])）
    sg[1] = sg[2];
    sg[2] = sg[3];
    sg[3] = sgn(df[3]);

    if (k > 3 && sg[1] != sg[2]) {
      double itv = tm[4] - tm[3];
      tArr[1] = tm[1] + itv / 2;
      tArr[2] = tm[2] + itv / 2;
      tArr[3] = tm[3] + itv / 2;

      double x = 0;
      double fnn = (x - df[1]) / (df[2] - df[1]);
      double lag1 = (1 - fnn) * (2 - fnn) * tArr[1] / 2 +
          fnn * (2 - fnn) * tArr[2] -
          (1 - fnn) * fnn * tArr[3] / 2;
      if (lag1 > 0) {
        T.value = lag1;
        x = lag1;
        fnn = (x - tm[2]) / (tm[3] - tm[2]);
        double lag2 = (1 - fnn) * (2 - fnn) * fx[2] / 2 +
            fnn * (2 - fnn) * fx[3] -
            (1 - fnn) * fnn * fx[4] / 2;
        y.value = lag2;
        return 1;
      } else {
        return 0;
      }
    } else {
      return 0;
    }
  }
}
