import 'dart:async';

class AsyncDebouncer {
  final Duration delay;
  Timer? _timer;
  Completer? _completer;

  AsyncDebouncer({required this.delay});

  Future<T> debounce<T>(Future<T> Function() callback) {
    _timer?.cancel();

    if (_completer?.isCompleted == false) {
      _completer!.completeError('Cancelled');
    }

    _completer = Completer<T>();

    _timer = Timer(delay, () async {
      try {
        final result = await callback();
        if (!_completer!.isCompleted) {
          _completer!.complete(result);
        }
      } catch (e) {
        if (!_completer!.isCompleted) {
          _completer!.completeError(e);
        }
      }
    });

    return _completer!.future as Future<T>;
  }

  void dispose() {
    _timer?.cancel();
  }
}