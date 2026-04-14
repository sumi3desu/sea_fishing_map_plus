import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'constants.dart';
import 'appconfig.dart';
import 'main.dart';
import 'sio_database.dart';
import 'common.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'new_account_page.dart';

class SpotApplyConfirmPage extends StatefulWidget {
  const SpotApplyConfirmPage({super.key, required this.kind, required this.name, required this.yomi, required this.lat, required this.lng, required this.address, required this.prefName, required this.privateFlag, this.titleOverride, this.submitLabel, this.overrideFlag, this.portId});

  final String kind; // gyoko/teibou/surf/kako/iso
  final String name;
  final String yomi;
  final double lat;
  final double lng;
  final String address;
  final String prefName; // 都道府県名（一致すればtodoufuken_idへ）
  final int privateFlag; // 0:公開, 1:非公開
  final String? titleOverride; // 確認/承認/非承認
  final String? submitLabel;   // 申請/承認/非承認
  final int? overrideFlag;     // null: 通常申請、1:承認、-2:非承認
  final int? portId;           // 既存のport_id（編集時）

  @override
  State<SpotApplyConfirmPage> createState() => _SpotApplyConfirmPageState();
}

class _SpotApplyConfirmPageState extends State<SpotApplyConfirmPage> {
  bool _submitting = false;
  String? _resultMessage;
  bool? _resultOk;
  bool _emailVerified = false;

  String _kindLabel(String k) {
    switch (k) {
      case 'gyoko':
        return '漁港';
      case 'teibou':
        return '堤防';
      case 'surf':
        return 'サーフ';
      case 'kako':
        return '河口';
      case 'iso':
        return '磯';
      default:
        return k;
    }
  }

  Future<void> _submit() async {
    setState(() { _submitting = true; _resultMessage = null; _resultOk = null; });
    try {
      final info = await loadUserInfo() ?? await getOrInitUserInfo();
      // 都道府県名からIDを引く
      int? todoufukenId;
      try {
        final rows = await SioDatabase().getTodoufukenAll();
        for (final r in rows) {
          final name = (r['todoufuken_name'] ?? '').toString();
          if (name == widget.prefName) {
            todoufukenId = r['todoufuken_id'] is int
                ? r['todoufuken_id'] as int
                : int.tryParse(r['todoufuken_id']?.toString() ?? '');
            break;
          }
        }
      } catch (_) {}
      final uri = Uri.parse('${AppConfig.instance.baseUrl}request_spot.php');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'kubun': widget.kind,
              'name': widget.name,
              'yomi': widget.yomi,
              'lat': widget.lat.toString(),
              'lng': widget.lng.toString(),
              'address': widget.address,
              'user_id': info.userId.toString(),
              'private': widget.privateFlag.toString(),
              if (widget.portId != null && widget.portId! > 0) 'port_id': widget.portId.toString(),
              if (widget.overrideFlag != null) 'flag': widget.overrideFlag.toString(),
              if (todoufukenId != null) 'todoufuken_id': todoufukenId.toString(),
              'platform': Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other'),
            },
          )
          .timeout(kHttpTimeout);
      String msg = '送信に失敗しました';
      bool ok = false;
      int? newPortId;
      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(resp.body);
          final result = (data is Map) ? (data['result']?.toString() ?? '') : '';
          if (result == 'success') {
            ok = true;
            msg = '申請を受け付けました';
            // 新規port_idを受領したら保存
            final pid = (data is Map) ? data['port_id'] : null;
            if (pid is int) newPortId = pid; else if (pid is String) newPortId = int.tryParse(pid);
          } else {
            final reason = (data is Map) ? (data['reason']?.toString() ?? '') : '';
            msg = reason.isNotEmpty ? reason : '申請に失敗しました';
          }
        } catch (_) {
          msg = 'サーバー応答の解析に失敗しました';
        }
      } else {
        msg = '通信に失敗しました（${resp.statusCode}）';
      }
      if (!mounted) return;
      setState(() { _resultOk = ok; _resultMessage = msg; });

      if (ok) {
        // ローカルDBにも即時反映
        try {
          final db = await SioDatabase().database;
          final row = <String, Object?>{
            'port_id': (widget.portId != null && widget.portId! > 0) ? widget.portId! : (newPortId ?? 0),
            'port_name': widget.name,
            'furigana': widget.yomi,
            'j_yomi': widget.yomi,
            'kubun': widget.kind,
            'address': widget.address,
            'latitude': widget.lat,
            'longitude': widget.lng,
            'note': '',
            'flag': widget.overrideFlag ?? -1,
            'private': widget.privateFlag,
            'user_id': info.userId,
            'create_at': DateTime.now().toIso8601String(),
          };
          await db.insert('teibou', row, conflictAlgorithm: ConflictAlgorithm.replace);
        } catch (_) {}
        // 共通状態にも反映して地図へ戻ったときに表示を更新
        try {
          await Common.instance.saveSelectedTeibou(
            widget.name,
            Common.instance.tidePoint,
            id: (widget.portId != null && widget.portId! > 0) ? widget.portId! : newPortId,
            lat: widget.lat,
            lng: widget.lng,
            prefId: todoufukenId,
          );
          Common.instance.shouldJumpPage = true;
          Common.instance.notify();
        } catch (_) {}

        // スナックバー表示→地図へ戻る（2段戻る）
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          const SnackBar(content: Text('申請を受け付けました'), duration: Duration(seconds: 2)),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        Navigator.pop(context); // 確認画面を閉じる
        Navigator.pop(context, true); // 入力画面も閉じる
        return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _resultOk = false; _resultMessage = '送信中にエラーが発生しました'; });
    } finally {
      if (mounted) setState(() { _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 認証状態を一度だけ読み取り（必要に応じて更新）
    (() async {
      try {
        final info = await loadUserInfo() ?? await getOrInitUserInfo();
        final verified = (info.email.trim().isNotEmpty);
        if (mounted && verified != _emailVerified) setState(() => _emailVerified = verified);
      } catch (_) {}
    })();
    return Scaffold(
      appBar: AppBar(title: Text(widget.titleOverride ?? '確認'), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('タイトル', '釣り場登録'),
          const SizedBox(height: 8),
          _row('釣り場種別', _kindLabel(widget.kind)),
          const SizedBox(height: 8),
          _row('公開/非公開', widget.privateFlag == 1 ? '非公開' : '公開'),
          const SizedBox(height: 8),
          _row('釣り場名', widget.name),
              const SizedBox(height: 8),
              _row('読み方', widget.yomi),
              const SizedBox(height: 8),
              _row('緯度/経度', '緯度: ${_fmt(widget.lat)} / 経度: ${_fmt(widget.lng)}'),
              const SizedBox(height: 8),
              _row('住所', widget.address.isNotEmpty ? widget.address : '（住所を取得できませんでした）'),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              if (!_emailVerified) ...[
                const Text(
                  '※ 釣り場申請は「メール認証」が必要です。申請ボタンを押すと「メール認証」を行います。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : () => Navigator.pop(context),
                      child: const Text('戻る'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submitting
                          ? null
                          : () async {
                              // 未認証ならアカウント登録へ遷移し、戻ってきてから改めて送信
                              try {
                                final info = await loadUserInfo() ?? await getOrInitUserInfo();
                                if ((info.email).trim().isEmpty) {
                                  final res = await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const NewAccountPage(returnToInputPost: true)),
                                  );
                                  // 戻ってきたら認証状態を再確認
                                  try {
                                    final after = await loadUserInfo() ?? await getOrInitUserInfo();
                                    final verified = (after.email.trim().isNotEmpty);
                                    if (mounted) setState(() => _emailVerified = verified);
                                    if (!verified) return;
                                  } catch (_) { return; }
                                }
                              } catch (_) {}
                              // 認証済みなら送信
                              await _submit();
                            },
                      child: _submitting
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(widget.submitLabel ?? '申請'),
                    ),
                  ),
                ],
              ),
              if (_resultMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _resultMessage!,
                  style: TextStyle(color: (_resultOk == true) ? Colors.green : Colors.red, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 2),
        Text(v, style: const TextStyle(fontSize: 16)),
      ],
    );
  }

  String _fmt(double v) => v.toStringAsFixed(6);
}
