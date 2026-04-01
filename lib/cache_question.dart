// 問題キャッシュ
class CacheQuestion {
  final int? nendoId;
  final int? mode;
  final int? outputOrder;
  final int? subjectIndex;
  final bool pinOnly;
  final List<dynamic> listQuestions;
  int? readedIdx;

  void setIndex(int idx){
    if (idx < listQuestions.length ){
      readedIdx = idx;
    } else {
      readedIdx = 0;
     }
    print('nendoId[${nendoId}] mode[${mode}] outputOrder[${outputOrder}] subjectIndex[${subjectIndex}] pinOnly[${pinOnly}] キャッシュ読込位置設定[${readedIdx}]');
  }

  int getIndex(){
    print('nendoId[${nendoId}] mode[${mode}] outputOrder[${outputOrder}] subjectIndex[${subjectIndex}] pinOnly[${pinOnly}] キャッシュ読込位置取得[${readedIdx}]');
    return readedIdx!;
  }

  // すでに読み込み済みかチェック
  isMatch(
    int nendoId,
    int mode,
    int outputOrder,
    int subjectIndex,
    bool pinOnly,
  ) {
    if (this.nendoId == nendoId &&
        this.mode == mode &&
        this.outputOrder == outputOrder &&
        this.subjectIndex == subjectIndex &&
        this.pinOnly == pinOnly) {
      return true;
    }
    return false;
  }

  CacheQuestion({
    required this.nendoId,
    required this.mode,
    required this.outputOrder,
    required this.subjectIndex,
    required this.pinOnly,
    required this.readedIdx,
    required this.listQuestions,
  }) {
  }
}
