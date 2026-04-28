import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class BackgroundCropPage extends StatefulWidget {
  const BackgroundCropPage({super.key, required this.imageFile});

  final XFile imageFile;

  @override
  State<BackgroundCropPage> createState() => _BackgroundCropPageState();
}

class _BackgroundCropPageState extends State<BackgroundCropPage> {
  ui.Image? _image;
  double _yOffset = 0.0; // 論理座標（レイアウト単位）
  bool _yOffsetInitialized = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final bytes = await File(widget.imageFile.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      setState(() => _image = frame.image);
    } catch (_) {}
  }

  Rect _computeSrcRect(double w, double h) {
    // 画像ピクセルサイズ
    final imgW = _image!.width.toDouble();
    final imgH = _image!.height.toDouble();
    // 画像→画面へのスケール（論理座標 / ピクセル）
    final s = math.max(w / imgW, h / imgH);
    // 画像左上の表示座標（論理）: 中央寄せ（横） + 可動オフセット（縦）
    final xOffset = (w - imgW * s) / 2.0; // 中央固定（横）
    // 縦オフセットはクランプ
    final minY = h - imgH * s;
    final maxY = 0.0;
    final yOffset = _clamp(_yOffset, minY, maxY);
    // クロップ矩形に対応する画像側矩形（ピクセル）
    final srcLeft = (-xOffset) / s;
    final srcTop = (-yOffset) / s;
    final srcWidth = w / s;
    final srcHeight = h / s;
    final rect = Rect.fromLTWH(srcLeft, srcTop, srcWidth, srcHeight);
    return Rect.fromLTWH(
      rect.left.clamp(0.0, imgW),
      rect.top.clamp(0.0, imgH),
      rect.width.clamp(1.0, imgW),
      rect.height.clamp(1.0, imgH),
    );
  }

  double _clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('背景のトリミング')),
      body:
          _image == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  const phi = 1.61803398875;
                  final h = w / phi; // 黄金比

                  // 初期オフセット（中央寄せ）: 画像読み込み後の最初のビルド時のみ設定
                  final imgW = _image!.width.toDouble();
                  final imgH = _image!.height.toDouble();
                  final s = math.max(w / imgW, h / imgH);
                  final minY = h - imgH * s;
                  if (!_yOffsetInitialized) {
                    _yOffset = (h - imgH * s) / 2.0;
                    _yOffset = _clamp(_yOffset, minY, 0.0);
                    _yOffsetInitialized = true;
                  }

                  return Stack(
                    children: [
                      // クロップ表示領域
                      ClipRect(
                        child: SizedBox(
                          width: w,
                          height: h,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (d) {
                              setState(() {
                                // 指の移動に追随（下へドラッグで正のdy→画像も下へ）
                                final next = _yOffset + d.delta.dy;
                                _yOffset = _clamp(next, minY, 0.0);
                              });
                            },
                            child: CustomPaint(
                              painter: _BgImagePainter(
                                image: _image!,
                                yOffset: _yOffset,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 周囲オーバーレイ（半透明）+ 枠
                      IgnorePointer(
                        child: CustomPaint(
                          size: Size(w, h),
                          painter: _RectOverlayPainter(),
                        ),
                      ),
                      // 操作ボタン
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 16,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: () async {
                                final path = await _exportCroppedPng(
                                  context,
                                  w,
                                  h,
                                );
                                if (!mounted) return;
                                Navigator.pop(context, path);
                              },
                              child: const Text('この範囲で決定'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('キャンセル'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
    );
  }

  Future<String?> _exportCroppedPng(
    BuildContext context,
    double w,
    double h,
  ) async {
    try {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final outW = (w * dpr).round();
      final outH = (h * dpr).round();

      final src = _computeSrcRect(w, h);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final dst = Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble());

      final paint =
          Paint()
            ..isAntiAlias = true
            ..filterQuality = FilterQuality.high;
      canvas.drawImageRect(_image!, src, dst, paint);

      final picture = recorder.endRecording();
      final uiImg = await picture.toImage(outW, outH);
      final pngBytes = await uiImg.toByteData(format: ui.ImageByteFormat.png);
      if (pngBytes == null) return null;

      // PNG -> WebP（lossy）背景はアルファ不要だが保持しても問題なし
      final webp = await FlutterImageCompress.compressWithList(
        pngBytes.buffer.asUint8List(),
        format: CompressFormat.webp,
        quality: 80,
      );

      final dir = await getTemporaryDirectory();
      final path = p.join(
        dir.path,
        'bg_cropped_${DateTime.now().millisecondsSinceEpoch}.webp',
      );
      final file = File(path);
      await file.writeAsBytes(webp);
      return path;
    } catch (_) {
      return null;
    }
  }
}

class _BgImagePainter extends CustomPainter {
  _BgImagePainter({required this.image, required this.yOffset});
  final ui.Image image;
  final double yOffset; // 論理座標

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final s = math.max(w / imgW, h / imgH);
    final xOffset = (w - imgW * s) / 2.0;
    // 背景塗り
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    // 画像描画（左上基準でスケール・平行移動）
    canvas.save();
    canvas.translate(xOffset, yOffset);
    canvas.scale(s, s);
    final paint =
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high;
    canvas.drawImage(image, Offset.zero, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BgImagePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.yOffset != yOffset;
}

class _RectOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 四辺に半透明の帯を描いて矩形領域を示す（内部はそのまま可視）
    final overlay = Paint()..color = Colors.black.withOpacity(0.35);
    final rect = Offset.zero & size;
    // 外側を塗る代わりに、上下左右に帯を描く必要はなく、ここは外周ラインのみ
    // ただし見やすさのために薄い縁取りを描画
    final stroke =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
    // 半透明のオーバーレイを敷く（矩形内も薄く暗くする）
    canvas.drawRect(rect, overlay);
    // 縁取り
    canvas.drawRect(rect, stroke);
  }

  @override
  bool shouldRepaint(covariant _RectOverlayPainter oldDelegate) => false;
}
