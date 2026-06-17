import 'package:dogpaw/dogpaw.dart';
import 'package:test/test.dart';

void main() {
  group('ScaleCatalog named scales', () {
    test('ScaleNamesIncludeCustom', () {
      expect(ScaleCatalog.scaleNames.first, equals('Major'));
      expect(ScaleCatalog.scaleNames, contains('Minor'));
      expect(ScaleCatalog.scaleNames.last, equals('Custom'));
    });

    test('ScaleDataForNameBuildsExpectedScale', () {
      final ScaleData scaleData = ScaleCatalog.scaleDataForName(
        scaleName: 'Dorian',
        rootNote: 2,
      );

      expect(scaleData.rootNote, equals(2));
      expect(ScaleCatalog.detectScaleName(scaleData), equals('Dorian'));
      expect(ScaleCatalog.isIncluded(scaleData, 2), isTrue);
      expect(ScaleCatalog.isIncluded(scaleData, 4), isTrue);
      expect(ScaleCatalog.isIncluded(scaleData, 1), isFalse);
    });

    test('ScaleDataForNameMarksTheRootWithTheDistinctRootCategory', () {
      final ScaleData scaleData = ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 2,
      );

      expect(scaleData.noteCategories[2], equals(3));
      expect(scaleData.noteCategories[4], equals(1));
    });
  });

  group('ScaleCatalog root operations', () {
    test('TransposeRootPreservesScaleIdentity', () {
      final ScaleData cMajor = ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      );

      final ScaleData dMajor = ScaleCatalog.transposeRoot(cMajor, 2);

      expect(dMajor.rootNote, equals(2));
      expect(ScaleCatalog.detectScaleName(dMajor), equals('Major'));
      expect(ScaleCatalog.isIncluded(dMajor, 2), isTrue);
      expect(ScaleCatalog.isIncluded(dMajor, 6), isTrue);
      expect(ScaleCatalog.isIncluded(dMajor, 3), isFalse);
    });

    test('SetRootNotePreservesTheDistinctRootCategoryAtTheNewRoot', () {
      final ScaleData cMajor = ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      );

      final ScaleData eMajor = ScaleCatalog.setRootNote(cMajor, 4);

      expect(eMajor.rootNote, equals(4));
      expect(eMajor.noteCategories[4], equals(3));
      expect(eMajor.noteCategories[0], isNot(equals(3)));
      expect(ScaleCatalog.detectScaleName(eMajor), equals('Major'));
    });
  });

  group('ScaleCatalog note editing', () {
    test('ToggleIncludedNoteMakesScaleCustom', () {
      final ScaleData cMajor = ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      );

      final ScaleData customScale = ScaleCatalog.toggleIncludedNote(cMajor, 1);

      expect(ScaleCatalog.isIncluded(customScale, 1), isTrue);
      expect(ScaleCatalog.detectScaleName(customScale), equals('Custom'));
    });

    test('RootNoteIsAlwaysReportedAsRoot', () {
      final ScaleData cMajor = ScaleCatalog.scaleDataForName(
        scaleName: 'Major',
        rootNote: 0,
      );

      expect(ScaleCatalog.isRoot(cMajor, 0), isTrue);
      expect(ScaleCatalog.isRoot(cMajor, 7), isFalse);
    });
  });
}
