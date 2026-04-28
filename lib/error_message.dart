class ErrorMessage {
  // プライベートコンストラクタ
  ErrorMessage._privateConstructor();

  // 唯一のインスタンスを生成して保持する静的フィールド
  static final ErrorMessage _instance = ErrorMessage._privateConstructor();

  // グローバルアクセサ
  static ErrorMessage get instance => _instance;

  final String pleaseInputMailAddress = "メールアドレスを入力してください。";
  final String pleaseInputValidMailAddress = "有効なメールアドレスを入力してください。";
  final String nowMailAddress = "現在設定されているメールアドレスです。";

  final String pleaseInputPassword = "パスワードを入力してください。";
  final String pleaseInputConfirmPassword = "パスワード確認を入力してください。";
  final String notMatchPassword = "パスワードが一致していません。";
  final String pleaseInputValidPassword =
      "パスワードは8文字以上で、大文字・小文字・数字・特殊文字(@\$!%*?&)を各1文字以上含む必要があります。";
  final String notMatchCertificationCode = "確認コードが一致しません。";

  String exceptionCheckMail(Object e) {
    return "メールアドレスチェック処理でエラーが発生しました。[$e]";
  }

  String exceptionUserRegist(Object e) {
    return "アカウント登録処理でエラーが発生しました。[$e]";
  }

  String exceptionMailRegist(Object e) {
    return "メールアドレスの処理でエラーが発生しました。[$e]";
  }

  String exceptionPasswordRegist(Object e) {
    return "パスワード設定処理でエラーが発生しました。[$e]";
  }
}
