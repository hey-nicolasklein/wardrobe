import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

/// Calendar dates use UTC arithmetic to avoid DST changing week boundaries.
/// Uses the supplied date's calendar fields, as the PWA does.
@immutable
class CostWeek implements Comparable<CostWeek> {
  const CostWeek._(this.monday);

  factory CostWeek.fromDate(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    return CostWeek._(day.subtract(Duration(days: day.weekday - 1)));
  }

  factory CostWeek.parse(String value) {
    final match = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(value);
    if (match == null) throw const FormatException('Invalid ISO week');
    final year = int.parse(match[1]!);
    final number = int.parse(match[2]!);
    final week = CostWeek.fromDate(
      DateTime.utc(year, 1, 4),
    ).offset(number - 1);
    if (week.value != value) throw const FormatException('Invalid ISO week');
    return week;
  }

  final DateTime monday;

  DateTime get sunday => monday.add(const Duration(days: 6));

  String get value {
    final year = monday.add(const Duration(days: 3)).year;
    final first = CostWeek.fromDate(DateTime.utc(year, 1, 4));
    final number = monday.difference(first.monday).inDays ~/ 7 + 1;
    return '${year.toString().padLeft(4, '0')}'
        '-W${number.toString().padLeft(2, '0')}';
  }

  CostWeek offset(int weeks) =>
      CostWeek._(monday.add(Duration(days: weeks * 7)));

  String label(String locale) {
    final format = DateFormat.MMMd(locale);
    return '${format.format(monday)} – ${format.format(sunday)}';
  }

  @override
  int compareTo(CostWeek other) => monday.compareTo(other.monday);

  @override
  bool operator ==(Object other) => other is CostWeek && monday == other.monday;

  @override
  int get hashCode => monday.hashCode;
}
