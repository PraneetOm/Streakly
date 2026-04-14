import 'package:hive/hive.dart';

part 'habit.g.dart';

@HiveType(typeId: 0)
enum HabitType {
  @HiveField(0)
  duration,

  @HiveField(1)
  count,

  @HiveField(2)
  quantity,
}

// NEW: frequency enum
@HiveType(typeId: 3)
enum HabitFrequency {
  @HiveField(0)
  daily,

  @HiveField(1)
  weekly,

  @HiveField(2)
  custom,
}

@HiveType(typeId: 1)
class Habit extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  String description;

  @HiveField(3)
  HabitType type;

  @HiveField(4)
  String unit;

  @HiveField(5)
  double dailyTarget;

  @HiveField(6)
  double xpPerUnit;

  @HiveField(7)
  int streak;

  @HiveField(8)
  int totalXP;

  @HiveField(9)
  DateTime? lastCompletedDate;

  @HiveField(10)
  bool isRunning;

  @HiveField(11)
  DateTime? startTime;

  // NEW fields appended — IMPORTANT: do not reuse old field indices
  @HiveField(12)
  HabitFrequency frequency;

  @HiveField(13)
  List<int>? customDays; // weekdays 1..7 (Mon=1,...Sun=7)

  @HiveField(14) // Use the next available number!
  bool isArchived;

  @HiveField(15) 
  List<String> linkedGroupIds;

  Habit({
    required this.id,
    required this.title,
    this.description = '',
    required this.type,
    required this.unit,
    required this.dailyTarget,
    required this.xpPerUnit,
    this.streak = 0,
    this.totalXP = 0,
    this.lastCompletedDate,
    this.isRunning = false,
    this.startTime,
    this.frequency = HabitFrequency.daily,
    this.customDays,
    this.isArchived = false,
    this.linkedGroupIds = const [],
  });
}