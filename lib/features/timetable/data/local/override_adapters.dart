import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../domain/entities/schedule_override.dart';

class ScheduleOverrideKindAdapter extends TypeAdapter<ScheduleOverrideKind> {
  @override
  final int typeId = HiveTypeIds.scheduleOverrideKind;

  @override
  ScheduleOverrideKind read(BinaryReader reader) {
    final int index = reader.readByte();
    // A kind written by a newer build degrades to a generic special schedule
    // rather than crashing.
    if (index < 0 || index >= ScheduleOverrideKind.values.length) {
      return ScheduleOverrideKind.special;
    }
    return ScheduleOverrideKind.values[index];
  }

  @override
  void write(BinaryWriter writer, ScheduleOverrideKind obj) {
    writer.writeByte(obj.index);
  }
}

class OverrideSlotAdapter extends TypeAdapter<OverrideSlot> {
  @override
  final int typeId = HiveTypeIds.overrideSlot;

  @override
  OverrideSlot read(BinaryReader reader) {
    final Map<int, dynamic> fields = _readFields(reader);
    return OverrideSlot(
      id: fields[0] as String,
      date: fields[1] as DateTime,
      startMinute: fields[2] as int,
      title: fields[3] as String,
      endMinute: fields[4] as int?,
      classGroup: fields[5] as String? ?? '',
      subject: fields[6] as String? ?? '',
      location: fields[7] as String? ?? '',
      isInvigilating: fields[8] as bool? ?? false,
      isMySubject: fields[9] as bool? ?? false,
      notes: fields[10] as String? ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, OverrideSlot obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.startMinute)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.endMinute)
      ..writeByte(5)
      ..write(obj.classGroup)
      ..writeByte(6)
      ..write(obj.subject)
      ..writeByte(7)
      ..write(obj.location)
      ..writeByte(8)
      ..write(obj.isInvigilating)
      ..writeByte(9)
      ..write(obj.isMySubject)
      ..writeByte(10)
      ..write(obj.notes);
  }
}

class ScheduleOverrideAdapter extends TypeAdapter<ScheduleOverride> {
  @override
  final int typeId = HiveTypeIds.scheduleOverride;

  @override
  ScheduleOverride read(BinaryReader reader) {
    final Map<int, dynamic> fields = _readFields(reader);
    return ScheduleOverride(
      id: fields[0] as String,
      name: fields[1] as String,
      kind: fields[2] as ScheduleOverrideKind,
      startDate: fields[3] as DateTime,
      endDate: fields[4] as DateTime,
      // Slots are nested rather than kept in their own box: they are only ever
      // read with their override, so a second box would add a join for nothing.
      slots: (fields[5] as List<dynamic>? ?? <dynamic>[])
          .whereType<OverrideSlot>()
          .toList(growable: false),
      notes: fields[6] as String? ?? '',
      teacherId: fields[7] as String? ?? '',
      updatedAt: fields[8] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ScheduleOverride obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.kind)
      ..writeByte(3)
      ..write(obj.startDate)
      ..writeByte(4)
      ..write(obj.endDate)
      ..writeByte(5)
      ..write(obj.slots)
      ..writeByte(6)
      ..write(obj.notes)
      ..writeByte(7)
      ..write(obj.teacherId)
      ..writeByte(8)
      ..write(obj.updatedAt);
  }
}

Map<int, dynamic> _readFields(BinaryReader reader) {
  final int fieldCount = reader.readByte();
  return <int, dynamic>{
    for (int i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
  };
}
