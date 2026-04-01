<?php


		/*******************************************
     * iniファイル場所
     ******************************************/
define("_INI_FILE_PATH_", "/home/users/0/babyblue.jp-bouzer/web/release/siowadou_pro/siowadou_pro_lolipop.ini");


    function convert_enc($str){
        $from_enc = 'UTF8';
        $to_enc = 'SJIS';

        return mb_convert_encoding($str, $to_enc, $from_enc);
    }


    function log_put($errormes)
    {
       //error_log(convert_enc($errormes)."\n", 0);
			 debug_log($errormes);
    }

	function debug_log($mes)
	{
		global $ini_info;

		error_log($mes . "\n",3,$ini_info['log']['path']);
	}

	// *****************************************
	// セッションキー作成
	// @param source 元のサーバURL
	// @return セッションキー
	// *****************************************
	function create_session_key($source){
		$key = str_replace(array('/','.',':'), '_', $source);
		return $key;
	}
	// *****************************************
	// セッション情報　ユーザ情報取得
	// @param $session_pre_key セッションキー
	// 戻り値 申請情報
	// *****************************************
	function GET_SESSION_USER_INFO($session_pre_key){
		return $_SESSION[$session_pre_key."_"."user_info"];
	}
	// *****************************************
	// セッション情報　ユーザ情報有無チェック
	// 戻り値 true=あり、false=なし
	// *****************************************
	function IS_SET_SESSION_USER_INFO($session_pre_key){
		return isset($_SESSION[$session_pre_key."_"."user_info"]);
	}

	// *****************************************
	// セッション情報　ユーザ情報設定
	// 戻り値 なし
	// *****************************************
	function SET_SESSION_USER_INFO($session_pre_key, $info){
		$_SESSION[$session_pre_key."_"."user_info"] = $info;
	}

	// *****************************************
	// セッション情報　初期設定ファイル情報取得
	// 戻り値 初期設定ファイル情報
	// *****************************************
	function GET_SESSION_INI_INFO($session_pre_key){
		return $_SESSION[$session_pre_key."_"."ini_info"];
	}
	// *****************************************
	// セッション情報　初期設定ファイル情報設定
	// 戻り値 なし
	// *****************************************
	function SET_SESSION_INI_INFO($session_pre_key, $ini){
		$_SESSION[$session_pre_key."_"."ini_info"] = $ini;
	}

	// *****************************************
	// セッションチェック（セッションがない場合loginへ）
	// 戻り値 なし
	// *****************************************
	function checkSession($session_pre_key){
		// セッション開始されていないかまたはログイン情報ない ?
		if(!isset($_SESSION) || !isset($_SESSION[$session_pre_key."_"."user_info"])) {

			log_put('No session -> login at checkSession');

			// ログイン画面へ遷移
			header( "Location: ./memozo_login.php" );
			die();
		} else {
			log_put("session OK");
		}
	}

	// *****************************************
	// セッションチェック（セッションがない場合loginへ）
	// *****************************************
	function checkSessionForAjax($session_pre_key){
		// セッション開始されていないか
		if(!isset($_SESSION)){
			session_cache_limiter("nocache");
			//セッション開始
			session_start();
		}
		// ログイン情報ない ?
		if (!isset($_SESSION[$session_pre_key."_"."user_info"])) {
			log_put('No session -> login at checkSessionForAjax ');
			// ログイン画面へ遷移
			header( "Location: ../memozo_login.php" );
			die();
		} else {
			log_put("session OK");
		}
	}
	// *****************************************
	// セッション削除
	// 戻り値 なし
	// *****************************************
	function clearSession($session_pre_key){
		// セッション開始されていないかまたはログイン情報ない ?
		unset($_SESSION[$session_pre_key."_"."ini_info"]);
		unset($_SESSION[$session_pre_key."_"."user_info"]);
/*
		log_put('clear session -> login at clearSession');

		// ログイン画面へ遷移
		header( "Location: ../memozo_login.php" );
		die();
		*/
	}

?>
