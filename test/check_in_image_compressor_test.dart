import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:fhub/Long/utils/check_in_image_compressor.dart';

void main() {
  group('compressCheckInImage', () {
    test('returns a resized JPEG below the Firestore document limit', () {
      final source = img.Image(width: 1800, height: 1200);
      final random = Random(23);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgb(
            x,
            y,
            random.nextInt(256),
            random.nextInt(256),
            random.nextInt(256),
          );
        }
      }
      final originalBytes = img.encodeJpg(source, quality: 95);
      expect(originalBytes.length, greaterThan(600 * 1024));

      final compressed = compressCheckInImage(
        Uint8List.fromList(originalBytes),
      );
      final decoded = img.decodeImage(compressed);

      expect(compressed.length, lessThanOrEqualTo(600 * 1024));
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(1024));
      expect(decoded.height, lessThanOrEqualTo(1024));
    });

    test('rejects invalid image bytes', () {
      expect(
        () => compressCheckInImage(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });
}
