import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/label_graphic.dart';
import 'package:holybeans/ui/labels/label_graphic_controller.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final png = LabelGraphic.prepare(
    img.encodePng(img.Image(width: 20, height: 10)),
  );
  test('saved image loads, bad image blocks, and removal clears it', () async {
    final controller = LabelGraphicController();
    addTearDown(controller.dispose);
    await controller.load(png);
    expect(controller.image!.width, 20);
    expect(controller.loading, isFalse);
    expect(controller.failed, isFalse);
    await controller.load('broken');
    expect(controller.image, isNull);
    expect(controller.failed, isTrue);
    await controller.load(null);
    expect(controller.image, isNull);
    expect(controller.failed, isFalse);
    expect(controller.data, isNull);
  });
  test(
    'late image load cannot restore a removed image or notify after disposal',
    () async {
      final controller = LabelGraphicController();
      final pending = controller.load(png);
      await controller.load(null);
      await pending;
      expect(controller.image, isNull);
      final closing = controller.load(png);
      controller.dispose();
      await closing;
    },
  );
}
