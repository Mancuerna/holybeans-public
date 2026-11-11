/// Calendar date represented in UTC, without converting the supplied date.
DateTime calendarDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

/// Signed calendar days, independent of time of day and daylight-saving shifts.
int calendarDaysBetween(DateTime from, DateTime to) =>
    calendarDay(to).difference(calendarDay(from)).inDays;
