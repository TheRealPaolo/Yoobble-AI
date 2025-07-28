import 'dart:async';

class Throttler {
  final Duration duration;
  Timer? _timer;
  DateTime? _lastRun;

  Throttler({required this.duration});

  void throttle(Function action) {
    final now = DateTime.now();
    if (_lastRun == null || now.difference(_lastRun!) > duration) {
      action();
      _lastRun = now;
    } else {
      _timer?.cancel();
      _timer = Timer(duration - now.difference(_lastRun!), () {
        action();
        _lastRun = DateTime.now();
      });
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}
