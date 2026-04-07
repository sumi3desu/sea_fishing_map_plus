import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geocoding/geocoding.dart' as geo;
import 'constants.dart';
import 'package:flutter/cupertino.dart' show CupertinoSegmentedControl;
import 'appconfig.dart';
import 'spot_apply_confirm_page.dart';
import 'main.dart';

class SpotApplyFormPage extends StatefulWidget {
  const SpotApplyFormPage({super.key, required this.lat, required this.lng, this.editMode = false, this.initialKind, this.initialName, this.initialYomi, this.initialAddress, this.initialPrefName, this.initialPrivate, this.initialPortId});
  final double lat;
  final double lng;
  final bool editMode; // true のとき編集モード（タイトル差し替え）
  final String? initialKind;
  final String? initialName;
  final String? initialYomi;
  final String? initialAddress;   // 都道府県を除いた住所
  final String? initialPrefName; // 都道府県名
  final int? initialPrivate;     // 0/1
  final int? initialPortId;      // 既存のport_id（編集時）

  @override
  State<SpotApplyFormPage> createState() => _SpotApplyFormPageState();
}

class _SpotApplyFormPageState extends State<SpotApplyFormPage> {
  final _formKey = GlobalKey<FormState>();
  String _kind = '';
  final TextEditingController _nameCtl = TextEditingController();
  final TextEditingController _yomiCtl = TextEditingController();
  String? _address;
  bool _private = false; // 公開(false:0)/非公開(true:1)
  String? _prefName; // 都道府県名（行政名）
  bool _loadingAddr = true;
  bool _submitting = false; // 住所取得・画面内送信は行わないため未使用
  String? _resultMessage; // 未使用（確認画面で表示）
  bool? _resultOk;        // 未使用（確認画面で表示）
  bool _isAdmin = false;

  DropdownMenuItem<String> _kindMenuItem(String value, IconData icon, String label) {
    return DropdownMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // 権限チェック
    (() async {
      try {
        final info = await loadUserInfo() ?? await getOrInitUserInfo();
        if (mounted) setState(() { _isAdmin = ((info.role ?? '').toLowerCase() == 'admin'); });
      } catch (_) {}
    })();
    // 初期値が渡された場合はそれを採用し、住所逆引きはスキップ
    bool applied = false;
    if (widget.initialKind != null || widget.initialName != null || widget.initialYomi != null || widget.initialAddress != null || widget.initialPrefName != null || widget.initialPrivate != null) {
      if (widget.initialKind != null) _kind = widget.initialKind!;
      if (widget.initialName != null) _nameCtl.text = widget.initialName!;
      if (widget.initialYomi != null) _yomiCtl.text = widget.initialYomi!;
      if (widget.initialAddress != null) _address = widget.initialAddress;
      if (widget.initialPrefName != null) _prefName = widget.initialPrefName;
      if (widget.initialPrivate != null) _private = (widget.initialPrivate == 1);
      _loadingAddr = false;
      applied = true;
    }
    if (!applied) {
      _reverseGeocode();
    }
  }

  Future<void> _reverseGeocode() async {
    setState(() { _loadingAddr = true; _address = null; });
    try {
      final list = await geo.placemarkFromCoordinates(widget.lat, widget.lng);
      if (list.isNotEmpty) {
        final p = list.first;
        final pref = (p.administrativeArea ?? '').trim();
        // 日本向けに町名・番地を優先して結合（都道府県は除外して保持）
        final parts = <String?>[
          p.locality,           // 市区町村
          p.subLocality,        // 区・町域
          p.thoroughfare,       // 丁目・通り
          p.subThoroughfare,    // 番地
        ].where((e) => (e ?? '').trim().isNotEmpty).map((e) => e!.trim()).toList();
        setState(() { _prefName = pref.isNotEmpty ? pref : null; _address = parts.join(' '); });
      } else {
        setState(() { _address = '住所を取得できませんでした'; });
      }
    } catch (_) {
      setState(() { _address = '住所を取得できませんでした'; });
    } finally {
      setState(() { _loadingAddr = false; });
    }
  }

  Future<void> _goConfirm() async {
    if (!_formKey.currentState!.validate()) return;
    final addr = (_address ?? '').toString();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SpotApplyConfirmPage(
          kind: _kind,
          name: _nameCtl.text.trim(),
          yomi: _yomiCtl.text.trim(),
          lat: widget.lat,
          lng: widget.lng,
          address: addr,
          prefName: _prefName ?? '',
          privateFlag: _private ? 1 : 0,
          portId: widget.initialPortId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.editMode ? '釣場申請編集' : '釣場新規申請'), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 公開/非公開 セグメント（投稿一覧の「釣果/環境」と同じUI）
                const Text('公開/非公開選択', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CupertinoSegmentedControl<String>(
                    groupValue: _private ? 'private' : 'public',
                    padding: const EdgeInsets.all(0),
                    children: const {
                      'public': Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('公開')),
                      'private': Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('非公開')),
                    },
                    onValueChanged: (val) {
                      setState(() { _private = (val == 'private'); });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const Text('釣場種別', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _kind.isEmpty ? null : _kind,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  hint: const Text('選択してください'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '釣場種別を選択してください';
                    return null;
                  },
                  items: [
                    _kindMenuItem('gyoko', Icons.anchor, '漁港'),
                    _kindMenuItem('teibou', Icons.fence, '堤防'),
                    _kindMenuItem('surf', Icons.waves, 'サーフ'),
                    _kindMenuItem('kako', Icons.water, '河口'),
                    _kindMenuItem('iso', Icons.terrain, '磯'),
                  ],
                  onChanged: (v) => setState(() => _kind = v ?? ''),
                ),
                const SizedBox(height: 16),
                const Text('釣場名（32文字以内）', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtl,
                  maxLength: 32,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '例）〇〇港 南防波堤'),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return '釣場名を入力してください';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                const Text('釣場名の読み方（ひらがな）', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _yomiCtl,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'れい）まるまるこう みなみぼうはてい'),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return '読み方を入力してください';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text('長押しした位置（参照）', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('緯度: ${_fmt(widget.lat)} / 経度: ${_fmt(widget.lng)}'),
                const SizedBox(height: 8),
                const Text('住所（参照）', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _loadingAddr
                    ? const Text('住所取得中...')
                    : Text((() {
                        final pref = (_prefName ?? '').trim();
                        final base = (_address ?? '').trim();
                        if (base.isEmpty) return base;
                        if (base == '住所を取得できませんでした') return base;
                        return pref.isNotEmpty ? '$pref $base' : base;
                      })()),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: widget.editMode && _isAdmin
                          ? Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      if (!_formKey.currentState!.validate()) return;
                                      final addr = (_address ?? '').toString();
                                      if (!mounted) return;
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => SpotApplyConfirmPage(
                                            kind: _kind,
                                            name: _nameCtl.text.trim(),
                                            yomi: _yomiCtl.text.trim(),
                                            lat: widget.lat,
                                            lng: widget.lng,
                                            address: addr,
                                            prefName: _prefName ?? '',
                                            privateFlag: _private ? 1 : 0,
                                            portId: widget.initialPortId,
                                            titleOverride: '承認',
                                            submitLabel: '承認',
                                            overrideFlag: 1,
                                          ),
                                        ),
                                      );
                                    },
                                    child: const Text('承認'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      if (!_formKey.currentState!.validate()) return;
                                      final addr = (_address ?? '').toString();
                                      if (!mounted) return;
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => SpotApplyConfirmPage(
                                            kind: _kind,
                                            name: _nameCtl.text.trim(),
                                            yomi: _yomiCtl.text.trim(),
                                            lat: widget.lat,
                                            lng: widget.lng,
                                            address: addr,
                                            prefName: _prefName ?? '',
                                            privateFlag: _private ? 1 : 0,
                                            portId: widget.initialPortId,
                                            titleOverride: '非承認',
                                            submitLabel: '非承認',
                                            overrideFlag: -2,
                                          ),
                                        ),
                                      );
                                    },
                                    child: const Text('非承認'),
                                  ),
                                ),
                              ],
                            )
                          : ElevatedButton(
                              onPressed: _goConfirm,
                              child: const Text('確認'),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(6);
}
