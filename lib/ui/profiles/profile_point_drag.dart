import 'package:flutter/gestures.dart';

class ProfilePointDrag extends PanGestureRecognizer {
  bool Function(Offset)? hitsPoint;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      (hitsPoint?.call(event.localPosition) ?? false) &&
      super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    // Claim only touches on a handle before the parent vertical scroll wins.
    resolve(GestureDisposition.accepted);
  }
}
