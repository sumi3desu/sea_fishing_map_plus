/// Global network timeout for HTTP requests
/// Adjust this value to change all app-wide HTTP timeouts at once.
const Duration kHttpTimeout = Duration(seconds: 20);
const int kPostPageSize = 20; // 投稿一覧の1ページ件数

final String _tosUrl = 'asset://assets/policies/terms_of_use.html';
final String _privacyUrl = 'asset://assets/policies/privacy_policy.html';
 
const bool ambiguous_point = false;