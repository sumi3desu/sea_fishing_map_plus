import 'package:flutter/foundation.dart';

/// Global logging function for server-style logs.
///
/// Prints in the format:
///   'ServerLog' + YYYY/MM/DD HH/MM/SS + ' ' + message
/// Example:
///   ServerLog2025/10/22 14/03/55 Purchased product_id=com.example.pro
void logPrint(String message) {
  //if (!kReleaseMode) {

  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final ts =
      '${now.year.toString().padLeft(4, '0')}/'
      '${two(now.month)}/'
      '${two(now.day)} '
      '${two(now.hour)}:'
      '${two(now.minute)}';

  // Note: No space between 'ServerLog' and timestamp per requested format
  // Output example: ServerLog2025/10/22 14/03/55 Your message here
  // ignore: avoid_print
  print('ServerLog $ts $message');
  //}
}
