import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'spot_apply_confirm_page.dart';
import 'main.dart';

class SpotApplyFormPage extends StatefulWidget {
  const SpotApplyFormPage({
    super.key,
    required this.lat,
    required this.lng,
    this.editMode = false,
    this.initialKind,
    this.initialName,
    this.initialYomi,
    this.initialAddress,
    this.initialPrefName,
    this.initialPrivate,
    this.initialPortId,
    this.applicantUserId,
    this.canModerate = false,
    this.buttonMode,
  });
  final double lat;
  final double lng;
  final bool editMode; // true のとき編集モード（タイトル差し替え）
  final String? initialKind;
  final String? initialName;
  final String? initialYomi;
  final String? initialAddress; // 都道府県を除いた住所
  final String? initialPrefName; // 都道府県名
  final int? initialPrivate; // 0/1
  final int? initialPortId; // 既存のport_id（編集時）
  final int? applicantUserId; // 申請者 user_id（admin 編集時も保持）
  final bool canModerate; // 承認/非承認を表示可能か（admin からの遷移時のみ true）
  final String? buttonMode; // confirmOnly / withdrawOnly

  @override
  State<SpotApplyFormPage> createState() => _SpotApplyFormPageState();
}

class _SpotApplyFormPageState extends State<SpotApplyFormPage> {
  static const List<String> _kinds = ['gyoko', 'teibou', 'surf', 'kako', 'iso'];
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
  bool? _resultOk; // 未使用（確認画面で表示）
  bool _isAdmin = false;

  String _normalizeKind(String raw) {
    final k = raw.trim().toLowerCase();
    switch (k) {
      case 'gyoko':
      case '漁港':
        return 'gyoko';
      case 'teibou':
      case '堤防':
        return 'teibou';
      case 'surf':
      case 'サーフ':
        return 'surf';
      case 'kako':
      case '河口':
        return 'kako';
      case 'iso':
      case '磯':
        return 'iso';
      default:
        // 旧コード系や想定外は「漁港」に寄せる（未対応値は未選択にしない）
        if (RegExp(r'^(?:[0-9]+|特)').hasMatch(k)) return 'gyoko';
        return raw.trim();
    }
  }

  DropdownMenuItem<String> _kindMenuItem(
    String value,
    IconData icon,
    String label,
  ) {
    return DropdownMenuItem<String>(
      value: value,
      child: Row(
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // 権限チェック
    (() async {
      try {
        // 起動時に最新化済みのローカル情報のみ参照（フォーム表示時の再取得はしない）
        final info = await loadUserInfo() ?? await getOrInitUserInfo();
        if (mounted)
          setState(() {
            _isAdmin = ((info.role ?? '').toLowerCase() == 'admin');
          });
      } catch (_) {}
    })();
    // 初期値が渡された場合はそれを採用し、住所逆引きはスキップ
    bool applied = false;
    if (widget.initialKind != null ||
        widget.initialName != null ||
        widget.initialYomi != null ||
        widget.initialAddress != null ||
        widget.initialPrefName != null ||
        widget.initialPrivate != null) {
      if (widget.initialKind != null)
        _kind = _normalizeKind(widget.initialKind!);
      if (widget.initialName != null) _nameCtl.text = widget.initialName!;
      if (widget.initialYomi != null) _yomiCtl.text = widget.initialYomi!;
      if (widget.initialAddress != null) _address = widget.initialAddress;
      if (widget.initialPrefName != null) _prefName = widget.initialPrefName;
      if (widget.initialPrivate != null)
        _private = (widget.initialPrivate == 1);
      _loadingAddr = false;
      applied = true;
    }
    if (!applied) {
      _reverseGeocode();
    }
  }

  Future<void> _reverseGeocode() async {
    setState(() {
      _loadingAddr = true;
      _address = null;
    });
    try {
      final list = await geo.placemarkFromCoordinates(widget.lat, widget.lng);
      if (list.isNotEmpty) {
        final p = list.first;
        final pref = (p.administrativeArea ?? '').trim();
        // 日本向けに町名・番地を優先して結合（都道府県は除外して保持）
        final parts =
            <String?>[
                  p.locality, // 市区町村
                  p.subLocality, // 区・町域
                  p.thoroughfare, // 丁目・通り
                  p.subThoroughfare, // 番地
                ]
                .where((e) => (e ?? '').trim().isNotEmpty)
                .map((e) => e!.trim())
                .toList();
        setState(() {
          _prefName = pref.isNotEmpty ? pref : null;
          _address = parts.join(' ');
        });
      } else {
        setState(() {
          _address = '住所を取得できませんでした';
        });
      }
    } catch (_) {
      setState(() {
        _address = '住所を取得できませんでした';
      });
    } finally {
      setState(() {
        _loadingAddr = false;
      });
    }
  }

  Future<void> _goConfirm() async {
    if (!_formKey.currentState!.validate()) return;
    final addr = (_address ?? '').toString();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => SpotApplyConfirmPage(
              kind: _kind,
              name: _nameCtl.text.trim(),
              yomi: _yomiCtl.text.trim(),
              lat: widget.lat,
              lng: widget.lng,
              address: addr,
              prefName: _prefName ?? '',
              privateFlag: 0,
              portId: widget.initialPortId,
              applicantUserId: widget.applicantUserId,
            ),
      ),
    );
  }

  Future<void> _goModerationConfirm({
    required String title,
    required int? overrideFlag,
    required String mailAction,
  }) async {
    if (!_formKey.currentState!.validate()) return;
    final addr = (_address ?? '').toString();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => SpotApplyConfirmPage(
              kind: _kind,
              name: _nameCtl.text.trim(),
              yomi: _yomiCtl.text.trim(),
              lat: widget.lat,
              lng: widget.lng,
              address: addr,
              prefName: _prefName ?? '',
              privateFlag: _private ? 1 : 0,
              portId: widget.initialPortId,
              applicantUserId: widget.applicantUserId,
              titleOverride: title,
              submitLabel: 'メール送信',
              overrideFlag: overrideFlag,
              mailAction: mailAction,
            ),
      ),
    );
  }

  Future<void> _goWithdrawConfirm() async {
    if (!_formKey.currentState!.validate()) return;
    final addr = (_address ?? '').toString();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => SpotApplyConfirmPage(
              kind: _kind,
              name: _nameCtl.text.trim(),
              yomi: _yomiCtl.text.trim(),
              lat: widget.lat,
              lng: widget.lng,
              address: addr,
              prefName: _prefName ?? '',
              privateFlag: 0,
              portId: widget.initialPortId,
              applicantUserId: widget.applicantUserId,
              titleOverride: '申請取り下げ',
              submitLabel: '申請取り下げ',
              overrideFlag: -3,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editMode ? '釣り場申請編集' : '釣り場登録'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 公開/非公開選択は廃止（すべて公開として処理）
                const SizedBox(height: 12),
                const Text(
                  '釣り場種別',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value:
                      (_kind.isEmpty || !_kinds.contains(_kind)) ? null : _kind,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('選択してください'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '釣り場種別を選択してください';
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
                const Text(
                  '釣り場名（32文字以内）',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtl,
                  maxLength: 32,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '例）〇〇港 南防波堤',
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return '釣り場名を入力してください';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  '釣り場名の読み方（ひらがな）',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _yomiCtl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'れい）まるまるこう みなみぼうはてい',
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return '読み方を入力してください';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  '長押しした位置（参照）',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text('緯度: ${_fmt(widget.lat)} / 経度: ${_fmt(widget.lng)}'),
                const SizedBox(height: 8),
                const Text(
                  '住所（参照）',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                _loadingAddr
                    ? const Text('住所取得中...')
                    : Text(
                      (() {
                        final pref = (_prefName ?? '').trim();
                        final base = (_address ?? '').trim();
                        if (base.isEmpty) return base;
                        if (base == '住所を取得できませんでした') return base;
                        String short2(String s) {
                          final parts =
                              s
                                  .split(RegExp(r'\s+'))
                                  .where((e) => e.trim().isNotEmpty)
                                  .toList();
                          if (parts.isEmpty) return s;
                          final take = parts.take(2).join(' ');
                          return take;
                        }

                        final b2 = short2(base);
                        return pref.isNotEmpty ? '$pref $b2' : b2;
                      })(),
                    ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: () {
                        if (widget.editMode &&
                            widget.buttonMode == 'confirmOnly') {
                          return Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: ElevatedButton(
                                onPressed: _goConfirm,
                                child: const Text('確認'),
                              ),
                            ),
                          );
                        }
                        if (widget.editMode &&
                            widget.buttonMode == 'withdrawOnly') {
                          return Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: OutlinedButton(
                                onPressed: _goWithdrawConfirm,
                                child: const Text('申請取り下げ'),
                              ),
                            ),
                          );
                        }
                        if (widget.editMode &&
                            (widget.canModerate && _isAdmin)) {
                          return Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed:
                                      () => _goModerationConfirm(
                                        title: '確認',
                                        overrideFlag: null,
                                        mailAction: 'confirm',
                                      ),
                                  child: const Text('確認'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed:
                                      () => _goModerationConfirm(
                                        title: '承認',
                                        overrideFlag: 1,
                                        mailAction: 'approve',
                                      ),
                                  child: const Text('承認'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed:
                                      () => _goModerationConfirm(
                                        title: '否認',
                                        overrideFlag: -2,
                                        mailAction: 'deny',
                                      ),
                                  child: const Text('否認'),
                                ),
                              ),
                            ],
                          );
                        }
                        if (widget.editMode) {
                          return Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _goWithdrawConfirm,
                                  child: const Text('申請取り下げ'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _goConfirm,
                                  child: const Text('確認'),
                                ),
                              ),
                            ],
                          );
                        }
                        return ElevatedButton(
                          onPressed: _goConfirm,
                          child: const Text('確認'),
                        );
                      }(),
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
