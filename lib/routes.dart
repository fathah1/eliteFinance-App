import 'package:flutter/material.dart';
import 'screens/add_customer_screen.dart';
import 'screens/add_entry_screen.dart';
import 'screens/add_supplier_entry_screen.dart';
import 'screens/add_supplier_screen.dart';
import 'screens/business_switch_screen.dart';
import 'screens/customer_ledger_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/supplier_ledger_screen.dart';

class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const addCustomer = '/customers/add';
  static const customerLedger = '/customers/ledger';
  static const addEntry = '/entries/add';
  static const reports = '/reports';
  static const settings = '/settings';
  static const businesses = '/businesses';
  static const addSupplier = '/suppliers/add';
  static const supplierLedger = '/suppliers/ledger';
  static const addSupplierEntry = '/suppliers/entries/add';

  static Route<dynamic> onGenerateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case register:
        return MaterialPageRoute(builder: (_) => const RegisterScreen());
      case home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case addCustomer:
        return MaterialPageRoute(builder: (_) => const AddCustomerScreen());
      case customerLedger:
        final args = routeSettings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => CustomerLedgerScreen(customer: args),
        );
      case addEntry:
        final args = routeSettings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => AddEntryScreen(
            customerId: args['customerId'] as int,
            transaction: args['transaction'] as Map<String, dynamic>?,
            initialType: args['initialType'] as String?,
          ),
        );
      case reports:
        return MaterialPageRoute(builder: (_) => const ReportsScreen());
      case settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      case businesses:
        return MaterialPageRoute(builder: (_) => const BusinessSwitchScreen());
      case addSupplier:
        return MaterialPageRoute(builder: (_) => const AddSupplierScreen());
      case supplierLedger:
        final args = routeSettings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => SupplierLedgerScreen(supplier: args),
        );
      case addSupplierEntry:
        final args = routeSettings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => AddSupplierEntryScreen(
            supplierId: args['supplierId'] as int,
            transaction: args['transaction'] as Map<String, dynamic>?,
            initialType: args['initialType'] as String?,
          ),
        );
      default:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
    }
  }
}
