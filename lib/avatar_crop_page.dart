import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class AvatarCropPage extends StatefulWidget {
  const AvatarCropPage({super.key, required this.imageFile});

  final XFile imageFile;

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  final TransformationController _controller = TransformationController();
  final GlobalKey _ivKey = GlobalKey();
  final GlobalKey _imageKey = GlobalKey();
  final GlobalKey _overlayKey = GlobalKey();
  ui.Image? _image;

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('画像のトリミング')),
      body:
          _image == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  final diameter = math.min(w, h) * 0.7; // 円の直径
                  final center = Offset(w / 2, h / 2);
                  final radius = diameter / 2;

                  final dpr = MediaQuery.of(context).devicePixelRatio;
                  return Container(
                    key: _overlayKey,
                    child: Stack(
                      children: [
                        Center(
                          child: InteractiveViewer(
                            key: _ivKey,
                            transformationController: _controller,
                            minScale: 0.5,
                            maxScale: 8.0,
                            // パン・ピンチズームは InteractiveViewer に任せる
                            panEnabled: true,
                            boundaryMargin: const EdgeInsets.all(1000),
                            clipBehavior: Clip.none,
                            child: RepaintBoundary(
                              key: _imageKey,
                              child: SizedBox(
                                width: _image!.width / dpr,
                                height: _image!.height / dpr,
                                child: RawImage(image: _image, scale: dpr),
                              ),
                            ),
                          ),
                        ),
                        // 円形オーバーレイ
                        IgnorePointer(
                          child: CustomPaint(
                            size: Size(w, h),
                            painter: _CircleOverlayPainter(diameter: diameter),
                          ),
                        ),
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
                                    diameter,
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
                    ),
                  );
                },
              ),
    );
  }

  Future<String?> _exportCroppedPng(double diameterLogical) async {
    try {
      // オーバーレイ（Stackコンテナ）の中心と円の矩形（オーバーレイ座標）
      final overlayCtx = _overlayKey.currentContext;
      if (overlayCtx == null) return null;
      final overlayBox = overlayCtx.findRenderObject() as RenderBox;
      final size = overlayBox.size;
      final cx = size.width / 2;
      final cy = size.height / 2;
      final r = diameterLogical / 2;
      final cropRectOverlay = Rect.fromLTWH(
        cx - r,
        cy - r,
        diameterLogical,
        diameterLogical,
      );

      // Overlay -> 画像子(RenderBox)の厳密行列を取得し、直接子座標へ写像
      final imgCtx = _imageKey.currentContext;
      if (imgCtx == null) return null;
      final imgBox = imgCtx.findRenderObject() as RenderBox;
      final vm.Matrix4 ov2img = overlayBox.getTransformTo(imgBox);
      Offset mapPt(vm.Matrix4 m, Offset p) {
        final v = m.transform3(vm.Vector3(p.dx, p.dy, 0));
        return Offset(v.x, v.y);
      }

      final p1 = mapPt(ov2img, cropRectOverlay.topLeft);
      final p2 = mapPt(ov2img, cropRectOverlay.topRight);
      final p3 = mapPt(ov2img, cropRectOverlay.bottomLeft);
      final p4 = mapPt(ov2img, cropRectOverlay.bottomRight);
      final cropInChild =
          (() {
            final left = [p1.dx, p2.dx, p3.dx, p4.dx].reduce(math.min);
            final top = [p1.dy, p2.dy, p3.dy, p4.dy].reduce(math.min);
            final right = [p1.dx, p2.dx, p3.dx, p4.dx].reduce(math.max);
            final bottom = [p1.dy, p2.dy, p3.dy, p4.dy].reduce(math.max);
            return Rect.fromLTRB(left, top, right, bottom);
          })();

      // child座標は論理座標（RawImage は scale=dpr で表示）なので、ピクセルに変換
      final dpr = MediaQuery.of(overlayCtx).devicePixelRatio;
      final srcPx = Rect.fromLTWH(
        (cropInChild.left * dpr).clamp(0.0, _image!.width.toDouble()),
        (cropInChild.top * dpr).clamp(0.0, _image!.height.toDouble()),
        (cropInChild.width * dpr).clamp(1.0, _image!.width.toDouble()),
        (cropInChild.height * dpr).clamp(1.0, _image!.height.toDouble()),
      );

      // 出力は正方形（透明の円以外を透明にする）
      const outSize = 512.0; // 仕上がりサイズ
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final dst = Rect.fromLTWH(0, 0, outSize, outSize);

      // まず透明
      final bgPaint = Paint()..color = const Color(0x00000000);
      canvas.drawRect(dst, bgPaint);

      // 円でクリップ
      final clipPath =
          Path()..addOval(
            Rect.fromCircle(
              center: Offset(outSize / 2, outSize / 2),
              radius: outSize / 2,
            ),
          );
      canvas.save();
      canvas.clipPath(clipPath);

      // 画像を描画
      final paint =
          Paint()
            ..isAntiAlias = true
            ..filterQuality = FilterQuality.high;
      canvas.drawImageRect(_image!, srcPx, dst, paint);
      canvas.restore();

      final picture = recorder.endRecording();
      final uiImg = await picture.toImage(outSize.toInt(), outSize.toInt());
      final pngBytes = await uiImg.toByteData(format: ui.ImageByteFormat.png);
      if (pngBytes == null) return null;

      // PNG -> WebP（lossy、アルファ対応）
      final webp = await FlutterImageCompress.compressWithList(
        pngBytes.buffer.asUint8List(),
        format: CompressFormat.webp,
        quality: 85,
      );

      final dir = await getTemporaryDirectory();
      final path = p.join(
        dir.path,
        'avatar_cropped_${DateTime.now().millisecondsSinceEpoch}.webp',
      );
      final file = File(path);
      await file.writeAsBytes(webp);
      return path;
    } catch (_) {
      return null;
    }
  }
}

class _CircleOverlayPainter extends CustomPainter {
  _CircleOverlayPainter({required this.diameter});
  final double diameter;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = diameter / 2;
    // 半透明の暗幕レイヤーに円形の穴を開ける
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.5);
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, overlayPaint);
    canvas.drawCircle(center, r, clearPaint);
    canvas.restore();
    // 円の枠
    final stroke =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
    canvas.drawCircle(center, r, stroke);
  }

  @override
  bool shouldRepaint(covariant _CircleOverlayPainter oldDelegate) =>
      oldDelegate.diameter != diameter;
}
