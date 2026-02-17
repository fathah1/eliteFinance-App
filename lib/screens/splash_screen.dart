import 'package:flutter/material.dart';
import '../api.dart';
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
