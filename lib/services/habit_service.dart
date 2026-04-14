import 'package:hive/hive.dart';
import '../models/habit.dart';

class HabitService {
  final Box<Habit> _box = Hive.box<Habit>('habits');

  List<Habit> getHabits() {
    return _box.values.toList();
  }

  Future<void> addHabit(Habit habit) async {
    await _box.put(habit.id, habit);
  }

  Future<void> deleteHabit(String id) async {
    await _box.delete(id);
  }

  Future<void> updateHabit(Habit habit) async {
    await _box.put(habit.id, habit);
  }
}