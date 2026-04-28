import 'package:flutter/foundation.dart';

/// Wrapper for debug logging used in tests/dev.
/// Replace direct `debugPrint` calls with this function.
void testDebugPrint(String message, {int? wrapWidth}) {
  if (!kReleaseMode) {
    //debugPrint(message, wrapWidth: wrapWidth);
  }
}
