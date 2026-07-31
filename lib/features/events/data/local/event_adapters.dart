import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../domain/entities/school_event.dart';

/// Hand-written adapters, matching the pattern used elsewhere: no build_runner,
/// and field indices are append-only so old data keeps reading.
class SchoolEventCategoryAdapter extends TypeAdapter<SchoolEventCategory> {
  @override
  final int typeId = HiveTypeIds.schoolEventCategory;

  @override
  SchoolEventCategory read(BinaryReader reader) {
    final int index = reader.readByte();
    // A category written by a newer build degrades to "other" rather than
    // crashing the app.
    if (index < 0 || index >= SchoolEventCategory.values.length) {
      return SchoolEventCategory.other;
    }
    return SchoolEventCategory.values[index];
  }

  @override
  void write(BinaryWriter writer, SchoolEventCategory obj) {
    writer.writeByte(obj.index);
  }
}

class SchoolEventAdapter extends TypeAdapter<SchoolEvent> {
  @override
  final int typeId = HiveTypeIds.schoolEvent;

  @override
  SchoolEvent read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
    };

    return SchoolEvent(
      id: fields[0] as String,
      date: fields[1] as DateTime,
      category: fields[2] as SchoolEventCategory,
      title: fields[3] as String,
      classGroup: fields[4] as String? ?? '',
      subject: fields[5] as String? ?? '',
      startMinute: fields[6] as int?,
      endMinute: fields[7] as int?,
      location: fields[8] as String? ?? '',
      opponent: fields[9] as String? ?? '',
      notes: fields[10] as String? ?? '',
      // Hive returns a List<dynamic>; whereType both casts and drops anything
      // unexpected.
      reminderLeadMinutes: (fields[11] as List<dynamic>? ?? <dynamic>[])
          .whereType<int>()
          .toList(growable: false),
      teacherId: fields[12] as String? ?? '',
      updatedAt: fields[13] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, SchoolEvent obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.category)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.classGroup)
      ..writeByte(5)
      ..write(obj.subject)
      ..writeByte(6)
      ..write(obj.startMinute)
      ..writeByte(7)
      ..write(obj.endMinute)
      ..writeByte(8)
      ..write(obj.location)
      ..writeByte(9)
      ..write(obj.opponent)
      ..writeByte(10)
      ..write(obj.notes)
      ..writeByte(11)
      ..write(obj.reminderLeadMinutes)
      ..writeByte(12)
      ..write(obj.teacherId)
      ..writeByte(13)
      ..write(obj.updatedAt);
  }
}
