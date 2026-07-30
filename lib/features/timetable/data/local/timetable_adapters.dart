import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../domain/entities/class_session.dart';
import '../../domain/entities/period.dart';
import '../../domain/entities/timetable_entry.dart';

/// Hand-written Hive adapters for the timetable entities.
///
/// Adapters live in the data layer so the domain entities stay pure Dart with no
/// storage dependency. Field indices are append-only: adding a field means a new
/// index and bumping the field count, never renumbering an existing one.
class PeriodAdapter extends TypeAdapter<Period> {
  @override
  final int typeId = HiveTypeIds.period;

  @override
  Period read(BinaryReader reader) {
    final Map<int, dynamic> fields = _readFields(reader);
    return Period(
      id: fields[0] as String,
      label: fields[1] as String,
      startMinute: fields[2] as int,
      endMinute: fields[3] as int,
      sortOrder: fields[4] as int,
      isBreak: fields[5] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, Period obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.label)
      ..writeByte(2)
      ..write(obj.startMinute)
      ..writeByte(3)
      ..write(obj.endMinute)
      ..writeByte(4)
      ..write(obj.sortOrder)
      ..writeByte(5)
      ..write(obj.isBreak);
  }
}

class TimetableEntryAdapter extends TypeAdapter<TimetableEntry> {
  @override
  final int typeId = HiveTypeIds.timetableEntry;

  @override
  TimetableEntry read(BinaryReader reader) {
    final Map<int, dynamic> fields = _readFields(reader);
    return TimetableEntry(
      id: fields[0] as String,
      weekday: fields[1] as int,
      periodId: fields[2] as String,
      subject: fields[3] as String,
      classGroup: fields[4] as String,
      room: fields[5] as String? ?? '',
      isPhysicalEducation: fields[6] as bool? ?? false,
      notes: fields[7] as String? ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, TimetableEntry obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.weekday)
      ..writeByte(2)
      ..write(obj.periodId)
      ..writeByte(3)
      ..write(obj.subject)
      ..writeByte(4)
      ..write(obj.classGroup)
      ..writeByte(5)
      ..write(obj.room)
      ..writeByte(6)
      ..write(obj.isPhysicalEducation)
      ..writeByte(7)
      ..write(obj.notes);
  }
}

class ClassSessionStatusAdapter extends TypeAdapter<ClassSessionStatus> {
  @override
  final int typeId = HiveTypeIds.classSessionStatus;

  @override
  ClassSessionStatus read(BinaryReader reader) {
    final int index = reader.readByte();
    // Data written by a newer build degrades to "nothing recorded" rather than
    // crashing the app on a sports field.
    if (index < 0 || index >= ClassSessionStatus.values.length) {
      return ClassSessionStatus.scheduled;
    }
    return ClassSessionStatus.values[index];
  }

  @override
  void write(BinaryWriter writer, ClassSessionStatus obj) {
    writer.writeByte(obj.index);
  }
}

class ClassSessionAdapter extends TypeAdapter<ClassSession> {
  @override
  final int typeId = HiveTypeIds.classSession;

  @override
  ClassSession read(BinaryReader reader) {
    final Map<int, dynamic> fields = _readFields(reader);
    return ClassSession(
      id: fields[0] as String,
      entryId: fields[1] as String,
      date: fields[2] as DateTime,
      status: fields[3] as ClassSessionStatus,
      updatedAt: fields[4] as DateTime?,
      note: fields[5] as String? ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, ClassSession obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.entryId)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.updatedAt)
      ..writeByte(5)
      ..write(obj.note);
  }
}

Map<int, dynamic> _readFields(BinaryReader reader) {
  final int fieldCount = reader.readByte();
  return <int, dynamic>{
    for (int i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
  };
}
