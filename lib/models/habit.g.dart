// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'habit.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HabitAdapter extends TypeAdapter<Habit> {
  @override
  final int typeId = 1;

  @override
  Habit read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Habit(
      id: fields[0] as String,
      title: fields[1] as String,
      description: fields[2] as String,
      type: fields[3] as HabitType,
      unit: fields[4] as String,
      dailyTarget: fields[5] as double,
      xpPerUnit: fields[6] as double,
      streak: fields[7] as int,
      totalXP: fields[8] as int,
      lastCompletedDate: fields[9] as DateTime?,
      isRunning: fields[10] as bool,
      startTime: fields[11] as DateTime?,
      frequency: fields[12] as HabitFrequency,
      customDays: (fields[13] as List?)?.cast<int>(),
      isArchived: fields[14] as bool,
      linkedGroupIds: (fields[15] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Habit obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.unit)
      ..writeByte(5)
      ..write(obj.dailyTarget)
      ..writeByte(6)
      ..write(obj.xpPerUnit)
      ..writeByte(7)
      ..write(obj.streak)
      ..writeByte(8)
      ..write(obj.totalXP)
      ..writeByte(9)
      ..write(obj.lastCompletedDate)
      ..writeByte(10)
      ..write(obj.isRunning)
      ..writeByte(11)
      ..write(obj.startTime)
      ..writeByte(12)
      ..write(obj.frequency)
      ..writeByte(13)
      ..write(obj.customDays)
      ..writeByte(14)
      ..write(obj.isArchived)
      ..writeByte(15)
      ..write(obj.linkedGroupIds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HabitAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HabitTypeAdapter extends TypeAdapter<HabitType> {
  @override
  final int typeId = 0;

  @override
  HabitType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return HabitType.duration;
      case 1:
        return HabitType.count;
      case 2:
        return HabitType.quantity;
      default:
        return HabitType.duration;
    }
  }

  @override
  void write(BinaryWriter writer, HabitType obj) {
    switch (obj) {
      case HabitType.duration:
        writer.writeByte(0);
        break;
      case HabitType.count:
        writer.writeByte(1);
        break;
      case HabitType.quantity:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HabitTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HabitFrequencyAdapter extends TypeAdapter<HabitFrequency> {
  @override
  final int typeId = 3;

  @override
  HabitFrequency read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return HabitFrequency.daily;
      case 1:
        return HabitFrequency.weekly;
      case 2:
        return HabitFrequency.custom;
      default:
        return HabitFrequency.daily;
    }
  }

  @override
  void write(BinaryWriter writer, HabitFrequency obj) {
    switch (obj) {
      case HabitFrequency.daily:
        writer.writeByte(0);
        break;
      case HabitFrequency.weekly:
        writer.writeByte(1);
        break;
      case HabitFrequency.custom:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HabitFrequencyAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
