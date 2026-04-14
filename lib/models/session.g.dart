// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SessionsAdapter extends TypeAdapter<Sessions> {
  @override
  final int typeId = 2;

  @override
  Sessions read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Sessions(
      habitId: fields[0] as String,
      value: fields[1] as double,
      date: fields[2] as DateTime,
      xpEarned: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, Sessions obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.habitId)
      ..writeByte(1)
      ..write(obj.value)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.xpEarned);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
