String formatClock(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

String formatDate(DateTime value) {
  const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
  return '${value.month}月${value.day}日  星期${weekdays[value.weekday - 1]}';
}

String formatDuration(Duration value, {bool showSeconds = false}) {
  final duration = value.isNegative ? Duration.zero : value;
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (showSeconds) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '$hours小时 ${minutes.toString().padLeft(2, '0')}分';
}

String formatShortTime(DateTime? value) {
  if (value == null) return '--:--';
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
