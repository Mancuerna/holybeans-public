import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/niimbot_identity.dart';

void main() {
  test('model identity cannot be substituted by another profile', () {
    final ids = {
      LabelPrinterModel.d110: 2304,
      LabelPrinterModel.d110M: 2320,
      LabelPrinterModel.d11: 512,
      LabelPrinterModel.d11H: 528,
      LabelPrinterModel.b1: 4096,
      LabelPrinterModel.b1Pro: 4097,
      LabelPrinterModel.b21: 768,
      LabelPrinterModel.b2: 6913,
      LabelPrinterModel.b2Pro: 6912,
    };
    for (final model in LabelPrinterModel.values) {
      for (final entry in ids.entries) {
        if (entry.key == model) {
          expect(
            NiimbotIdentity.resolve(
              model,
              entry.value,
              protocolVersion: model == LabelPrinterModel.d11 ? 0 : 4,
            ).model,
            model,
          );
        } else {
          expect(
            () =>
                NiimbotIdentity.resolve(model, entry.value, protocolVersion: 4),
            throwsFormatException,
          );
        }
      }
    }
    expect(
      () => NiimbotIdentity.resolve(LabelPrinterModel.b21, 785),
      throwsFormatException,
    );
  });
  test('status revision needs a complete, recognized payload', () {
    for (final (revision, version) in [
      (0, 0),
      (203, 0),
      (204, 3),
      (299, 3),
      (300, 4),
      (301, 4),
      (302, 5),
      (399, 5),
      (400, 0),
    ]) {
      expect(
        niimbotProtocolVersion([
          ...List.filled(11, 0),
          revision ~/ 100,
          revision % 100,
        ]),
        version,
      );
    }
    expect(niimbotProtocolVersion([3, 2]), 0);
  });
  test('advertising names discover variants but never unrelated models', () {
    for (final name in ['B1-X', 'B1 Pro-X', 'B1_PRO-X']) {
      expect(LabelPrinterModel.b1Pro.matchesName(name), isTrue);
    }
    for (final name in ['B21-X', 'B21S-X', 'B21_C2B-X', 'B21-L2B-X']) {
      expect(LabelPrinterModel.b21.matchesName(name), isTrue);
    }
    expect(LabelPrinterModel.b21.matchesName('B21Pro-X'), isFalse);
    expect(LabelPrinterModel.b1Pro.matchesName('B1SE-X'), isFalse);
    expect(LabelPrinterModel.b2Pro.matchesName('B2 Pro-X'), isTrue);
  });
  test('paper choices remain isolated even when dimensions match', () {
    for (final model in LabelPrinterModel.values) {
      expect(model.papers, contains(model.defaultPaper));
      for (final paper in model.papers) {
        expect(paper.model, model);
        expect(paper.crossFeedPixels, lessThanOrEqualTo(model.headPixels));
        for (final other in LabelPrinterModel.values.where((m) => m != model)) {
          expect(other.papers, isNot(contains(paper)));
        }
      }
    }
  });
}
