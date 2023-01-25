part of worker_manager;

class CanceledError implements Exception {}

class Cancelable<O> implements Future<O> {
  final Completer<O> _completer;
  final void Function()? _onCancel;
  final void Function()? _onPause;
  final void Function()? _onResume;
  final Task? _task;

  Cancelable({
    required Completer<O> completer,
    void Function()? onCancel,
    void Function()? onPause,
    void Function()? onResume,
    Task? task,
  })  : _onCancel = onCancel,
        _onPause = onPause,
        _onResume = onResume,
        _completer = completer,
        _task = task;

  factory Cancelable.justValue(O value) {
    return Cancelable(completer: Completer()..complete(value));
  }

  factory Cancelable.justError(Object error) {
    return Cancelable(completer: Completer()..completeError(error));
  }

  factory Cancelable.fromFuture(Future<O> future) {
    final completer = Completer<O>();
    future.then((value) {
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }, onError: (Object e, StackTrace s) => completer.completeError(e, s));
    return Cancelable(
      completer: completer,
      onCancel: () {
        if (!completer.isCompleted) {
          completer.completeError(CanceledError());
        }
      },
    );
  }

  TypeSendPort? get port => _task?.runnable.sendPort;

  Future<O> get future => _completer.future;

  static void _completeError<T>({
    required Completer<T> completer,
    required Object e,
    FutureOr<T> Function(Object)? onError,
  }) {
    if (!completer.isCompleted) {
      if (onError != null) {
        completer.complete(onError(e));
      } else {
        completer.completeError(e);
      }
    }
  }

  void _completeValue<T>({required Completer<T> completer, T? value}) {
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  void cancel() => _onCancel?.call();

  Cancelable<R> thenNext<R>(FutureOr<R> Function(O value)? onValue,
      [FutureOr<R> Function(Object error)? onError]) {
    final resultCompleter = Completer<R>();
    _completer.future.then((value) {
      try {
        _completeValue(
          completer: resultCompleter,
          value: onValue?.call(value),
        );
      } catch (error) {
        _completeError(
          completer: resultCompleter,
          onError: onError,
          e: error,
        );
      }
    }, onError: (Object e) {
      if (e is! CanceledError) {
        _completeError(
          completer: resultCompleter,
          onError: onError,
          e: e,
        );
      }
    });
    return Cancelable(
      completer: resultCompleter,
      task: _task,
      onCancel: () {
        _onCancel?.call();
        _completeError(
          completer: resultCompleter,
          e: CanceledError(),
          onError: onError,
        );
      },
      onPause: _onPause,
      onResume: _onResume,
    );
  }

  static Cancelable<Iterable<R>> mergeAll<R>(
      Iterable<Cancelable<R>> cancelables) {
    final resultCompleter = Completer<Iterable<R>>();
    Future.wait(cancelables).then((value) {
      resultCompleter.complete(value);
    }, onError: (Object e) {
      _completeError(completer: resultCompleter, e: e);
    });
    return Cancelable(
        completer: resultCompleter,
        onCancel: () {
          for (final cancelable in cancelables) {
            cancelable.cancel();
          }
          _completeError(completer: resultCompleter, e: CanceledError());
        },
        onResume: () {
          for (final cancelable in cancelables) {
            cancelable.resume();
          }
        },
        onPause: () {
          for (final cancelable in cancelables) {
            cancelable.pause();
          }
        });
  }

  void pause() => _onPause?.call();

  void resume() => _onResume?.call();

  @override
  Stream<O> asStream() => future.asStream();

  @override
  Future<O> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) =>
      future.catchError(onError, test: test);

  @override
  Future<O> timeout(
    Duration timeLimit, {
    FutureOr Function()? onTimeout,
  }) =>
      future.timeout(timeLimit);

  @override
  Future<O> whenComplete(FutureOr Function() action) =>
      future.whenComplete(action);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(O value) onValue, {
    Function? onError,
  }) =>
      future.then(onValue, onError: onError);
}
