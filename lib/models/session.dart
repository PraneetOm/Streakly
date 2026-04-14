import 'package:hive/hive.dart';

part 'session.g.dart';

@HiveType(typeId: 2)
class Sessions extends HiveObject {
  @HiveField(0)
  String habitId;

  @HiveField(1)
  double value;

  @HiveField(2)
  DateTime date;

  @HiveField(3)
  int xpEarned;

  Sessions({
    required this.habitId,
    required this.value,
    required this.date,
    required this.xpEarned,
  });
}