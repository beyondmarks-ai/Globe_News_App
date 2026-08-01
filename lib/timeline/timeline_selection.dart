class TimelineSelection {
  const TimelineSelection(this.ist);

  static const istOffset = Duration(hours: 5, minutes: 30);
  final DateTime ist;

  factory TimelineSelection.latestCompleted({DateTime? utcNow}) {
    final nowIst = (utcNow ?? DateTime.now().toUtc()).toUtc().add(istOffset);
    final completedMinute = (nowIst.minute ~/ 15) * 15;
    return TimelineSelection(
      DateTime.utc(
        nowIst.year,
        nowIst.month,
        nowIst.day,
        nowIst.hour,
        completedMinute,
      ),
    );
  }

  DateTime get utc => DateTime.utc(
    ist.year,
    ist.month,
    ist.day,
    ist.hour,
    ist.minute,
  ).subtract(istOffset);

  String get apiDate =>
      '${utc.year.toString().padLeft(4, '0')}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}';

  String get apiTime =>
      '${utc.hour.toString().padLeft(2, '0')}:${utc.minute.toString().padLeft(2, '0')}';

  String get displayDate =>
      '${ist.day.toString().padLeft(2, '0')}/${ist.month.toString().padLeft(2, '0')}/${ist.year}';

  String get displayTime =>
      '${ist.hour.toString().padLeft(2, '0')}:${ist.minute.toString().padLeft(2, '0')} IST';

  TimelineSelection withDate(DateTime date) => TimelineSelection(
    DateTime.utc(date.year, date.month, date.day, ist.hour, ist.minute),
  );

  TimelineSelection withTime({required int hour, required int minute}) =>
      TimelineSelection(
        DateTime.utc(ist.year, ist.month, ist.day, hour, minute),
      );
}
