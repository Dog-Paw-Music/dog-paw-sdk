import 'package:flutter_test/flutter_test.dart';
import 'package:namer/utils/chord_utils.dart';

void main() {
  test('smoke: formats a simple major chord name', () {
    // Placeholder smoke coverage for the SDK v1 release surface.
    // Expand this into fuller chord-detection coverage as Namer matures.
    expect(ChordUtils.formatChord('C', 'Major', null, false), 'C');
  });
}
