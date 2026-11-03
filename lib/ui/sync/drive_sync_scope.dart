import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';

class DriveSyncScope extends InheritedNotifier<DriveSyncModel> {
  const DriveSyncScope({
    super.key,
    required DriveSyncModel model,
    required super.child,
  }) : super(notifier: model);

  static DriveSyncModel? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DriveSyncScope>()?.notifier;
}

// Only an explicit restoration can delay a journal write. Uploads never do.
Future<void> waitForDriveCheck(DriveSyncModel model) async {
  if (!model.applying) return;
  final idle = Completer<void>();
  void changed() {
    if (!model.busy && !idle.isCompleted) idle.complete();
  }

  model.addListener(changed);
  try {
    await idle.future.timeout(const Duration(seconds: 35));
  } finally {
    model.removeListener(changed);
  }
}
