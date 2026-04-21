
import 'package:flutter/material.dart';

class AppConfig {
  // プライベートコンストラクタ
  AppConfig._privateConstructor();

  // 唯一のインスタンスを生成して保持する静的フィールド
  static final AppConfig _instance = AppConfig._privateConstructor();

  // グローバルアクセサ
  static AppConfig get instance => _instance;

  // 辞書のバージョンを保持
  String dicVersion = "";
  // passwordを保持
  String password = "";
  // mailを保持
  String mail = "";
  // AppBarの背景色
  Color appBarBackgroundColor = Colors.black;
  // AppBarの全景色
  Color appBarForegroundColor = Colors.white;
  
  Color buttonBackgroundColor = Colors.greenAccent;
  Color buttonForegroundColor = Colors.black;

  String baseUrl = "https://www.bouzer.jp/seafishingmap/";
}