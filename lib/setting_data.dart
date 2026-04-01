//
// 設定情報
class SettingData {
  final bool buzzerOn;
  final int mode;
  final int outputOrder;
  final int? yearId;
  final int? subjectIndex;
  final bool pinOnly;

  SettingData({
    required this.buzzerOn,
    required this.mode,
    required this.outputOrder,
    required this.yearId,
    required this.subjectIndex,
    required this.pinOnly,
  });

  SettingData copyWith({
    bool? buzzerOn,
    int? mode,
    int? outputOrder,
    int? yearId,
    int? subjectIndex,
    bool? pinOnly,
  }) {
    return SettingData(
      buzzerOn: buzzerOn ?? this.buzzerOn,
      mode: mode ?? this.mode,
      outputOrder: outputOrder ?? this.outputOrder,
      yearId: yearId ?? this.yearId,
      subjectIndex: subjectIndex ?? this.subjectIndex,
      pinOnly: pinOnly ?? this.pinOnly,
    );
  }
}
