import 'package:flutter_test/flutter_test.dart';
import 'package:impression_day/main.dart';

void main() {
  test('D-day counts calendar dates and preserves saved events', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final event = DayEvent(id: 'sample', title: '여행', date: tomorrow);
    expect(event.dDay, 'D-1');
    final restored = DayEvent.fromJson(event.toJson());
    expect(restored.title, '여행');
    expect(restored.dDay, 'D-1');
  });

  test(
    'multi-day event changes from countdown to in-progress to completed',
    () {
      final event = DayEvent(
        id: 'trip',
        title: '여행',
        date: DateTime(2026, 10, 26),
        endDate: DateTime(2026, 10, 29),
      );
      expect(event.statusOn(DateTime(2026, 10, 25)), 'D-1');
      expect(event.statusOn(DateTime(2026, 10, 26)), 'D-DAY');
      expect(event.statusOn(DateTime(2026, 10, 28)), '진행 3일차');
      expect(event.statusOn(DateTime(2026, 10, 30)), 'D+1');
      expect(DayEvent.fromJson(event.toJson()).endDate, DateTime(2026, 10, 29));
    },
  );

  test('existing single-day events load without an end date', () {
    final event = DayEvent.fromJson({
      'id': 'old',
      'title': '면접',
      'date': '2026-10-26T00:00:00.000',
    });
    expect(event.endDate, isNull);
    expect(event.statusOn(DateTime(2026, 10, 27)), 'D+1');
  });
}
