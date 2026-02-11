import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _plugin.initialize(initSettings);
    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
  }

  static Future<void> schedulePaymentReminder({
    required int id,
    required String title,
    required String body,
    required DateTime date,
  }) async {
    final now = DateTime.now();
    var scheduleAt = DateTime(date.year, date.month, date.day, 9, 0);
    if (scheduleAt.isBefore(now)) {
      scheduleAt = now.add(const Duration(minutes: 1));
    }
    final tzTime = tz.TZDateTime.from(scheduleAt, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'payment_reminders',
      'Payment Reminders',
      channelDescription: 'Payment due date reminders',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzTime,
      details,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
  }

  static Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }
}
