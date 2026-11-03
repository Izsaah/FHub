import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int _maxCheckInImageBytes = 600 * 1024;
const List<int> _maxDimensions = [1024, 800, 640, 480];
const List<int> _jpegQualities = [80, 70, 60, 50, 40];

Uint8List compressCheckInImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('The captured photo could not be decoded.');
  }

  final oriented = img.bakeOrientation(decoded);
  for (final maxDimension in _maxDimensions) {
    final resized =
        oriented.width > maxDimension || oriented.height > maxDimension
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? maxDimension : null,
            height: oriented.height > oriented.width ? maxDimension : null,
            interpolation: img.Interpolation.average,
          )
        : oriented;

    for (final quality in _jpegQualities) {
      final compressed = img.encodeJpg(resized, quality: quality);
      if (compressed.length <= _maxCheckInImageBytes) {
        return compressed;
      }
    }
  }

  throw StateError('The captured photo could not be reduced to a safe size.');
}
