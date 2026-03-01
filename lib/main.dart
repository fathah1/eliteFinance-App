import 'package:flutter/material.dart';
import 'notifications.dart';
import 'offline_sync_service.dart';
import 'routes.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  OfflineSyncService.instance.start();
  runApp(const LedgerApp());
}

class LedgerApp extends StatelessWidget {
  const LedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return _SyncAwareApp(
      child: MaterialApp(
        title: 'ECBooks',
        theme: ThemeData(useMaterial3: true),
        initialRoute: AppRoutes.splash,
        onGenerateRoute: AppRoutes.onGenerateRoute,
      ),
    );
  }
}

class _SyncAwareApp extends StatefulWidget {
  final Widget child;
  const _SyncAwareApp({required this.child});

  @override
  State<_SyncAwareApp> createState() => _SyncAwareAppState();
}

class _SyncAwareAppState extends State<_SyncAwareApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      OfflineSyncService.instance.syncPendingNow();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
