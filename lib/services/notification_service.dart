import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  final FlutterLocalNotificationsPlugin _notifications;

  NotificationService(this._notifications);

  Future<void> initTimeZone() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  }

  //temp function to test notifications
  Future<void> showTestNotification() async {
    await _notifications.show(
      1,
      "Test Notification",
      "If you see this, notifications work.",
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'habit_channel',
          'Habit Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> scheduleDailyReminder(int hour, int minute) async {
    await initTimeZone();

    await _notifications.zonedSchedule(
      0,
      "Habit Reminder 🔥",
      "Don't forget to complete your habits today!",
      _nextInstanceOfTime(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'habit_channel',
          'Habit Reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, 
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    return scheduledDate;
  }
}