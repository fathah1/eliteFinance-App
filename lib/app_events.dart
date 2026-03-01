import 'package:flutter/foundation.dart';

/// Lightweight app-wide refresh signals for screens kept alive in IndexedStack.
class AppEvents {
  static final ValueNotifier<int> itemsRefreshTick = ValueNotifier<int>(0);

  static void notifyItemsChanged() {
    itemsRefreshTick.value++;
  }
}
