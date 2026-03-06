import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../offline_sync_service.dart';
import '../routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final token = await Api.getToken();

    if (!mounted) return;
    if (token != null && token.isNotEmpty) {
      unawaited(_warmUpOfflineCache());
      Navigator.pushAndRemoveUntil(
        context,
        AppRoutes.onGenerateRoute(
          const RouteSettings(name: AppRoutes.home),
        ),
        (route) => false,
      );
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        AppRoutes.onGenerateRoute(
          const RouteSettings(name: AppRoutes.login),
        ),
        (route) => false,
      );
    }
  }

  Future<void> _warmUpOfflineCache() async {
    try {
      await OfflineSyncService.instance.syncPendingNow();
      final prefs = await SharedPreferences.getInstance();
      final activeBusinessId = prefs.getInt('active_business_server_id');
      if (activeBusinessId != null) {
        await Api.prefetchBusinessData(businessId: activeBusinessId);
      }
      final businesses = await Api.getBusinesses();
      for (final b in businesses) {
        final id = (b as Map)['id'];
        if (id is int && id != activeBusinessId) {
          await Api.prefetchBusinessData(businessId: id);
        }
      }
    } catch (_) {
      // best effort only
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store, size: 64),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      ),
    );
  }
}
