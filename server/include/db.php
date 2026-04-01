<?php
// ************************************************************
	require_once 'define.php';

	// *************************************************
	// DBアクセスクラス
	// *************************************************
	class dbAccess {

		var $db_reason = '';
		var $db_result = true;
		var $db_pdo = null;
		var $db_stm = null;
		var $db_tran = false;

		// *************************************************
		// コンストラクタ
		// *************************************************
		function dbAccess() {
			$this->db_reason = '';
			$this->db_result = true;
			$this->db_pdo = null;
			$this->db_tran = false;
		}

		// *************************************************
		// 接続
		// *************************************************
		function connect($dsn, $user, $password){

			try{

				log_put("called connect DSN[".$dsn."] user[".$user."] pass[".$password."]");
			$this->db_pdo = new PDO($dsn, $user, $password);
    			$sql = 'set names utf8';
    			$this->db_pdo->query($sql);

 				$this->db_result = true;

			} catch(PDOException $e){
				log_put("DB error[".$e->getMessage()."]");
        		$this->db_pdo = null;
				$this->db_result = false;
        		$this->db_reason = $e->getMessage();
			}
			return $this->db_pdo;
		}
		// *************************************************
		// 接続 & トランザクション
		// *************************************************
		function connectTran($dsn, $user, $password){
			if ($this->connect($dsn, $user, $password) != null){
				$this->db_pdo->beginTransaction();
				$this->db_tran = true;
			} else {
				return null;
			}
		}
		function commit(){
			$this->db_pdo->commit();
		}
		function rollBack(){
			$this->db_pdo->rollBack();

		}
		// *************************************************
		// 接続解除
		// *************************************************
		function disconnect()
		{
			if ($this->db_pdo !=null){
				$this->db_pdo = null;
			}
		}
		// *************************************************
		// get PDO
		// *************************************************
		function getPDO(){
			return $this->db_pdo;
		}

		// *************************************************
		// prepare
		// @param  $sql  : SQL
		// *************************************************
		function prepare($sql){
			$this->db_stm = $this->db_pdo->prepare($sql);
		}
		// *************************************************
		// execute
		// @param  $array_para  : 引数配列
		// *************************************************
		function execute($array_para){
			return $this->db_stm->execute($array_para);
		}
		// *************************************************
		// execute
		// *************************************************
		function fetch(){
			return $this->db_stm->fetch();
		}

		// *************************************************
		// query
		// @param  $sql  : SQL
		// *************************************************
		function query($sql){
			return $this->db_pdo->query($sql);
		}

		// *************************************************
		// error情報設定
		// @param  $error  : エラー文字列
		// *************************************************
		function setError($error){
			$this->db_error = $error;
			$this->db_result = false;
		}
		// *************************************************
		// error情報取得
		// *************************************************
		function getError(){
			return $this->db_error;
		}
	}

?>
