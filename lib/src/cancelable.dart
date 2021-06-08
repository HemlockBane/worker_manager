import 'dart:async';
import 'package:meta/meta.dart';

import 'cancelation_token.dart';

class CanceledError implements Exception {}

class Cancelable<O> implements Future<O> {
  final Completer<O> _completer;
  final void Function()? _onCancel;

  Cancelable(this._completer, this._onCancel);

  @experimental
  factory Cancelable.justValue(O value) {
    return Cancelable(Completer()
      ..complete(value), () {});
  }

  factory Cancelable.justError(Object error) {
    return Cancelable(Completer()
      ..completeError(error), () {});
  }

  @experimental
  factory Cancelable.fromFunction(Future<O> Function(CancelationToken token) fun,) {
    final cancelationTokenSource = CancelationTokenSource();
    final completer = Completer<O>();
    final future = fun(cancelationTokenSource.token);
    future.then((value) {
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }).onError((error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error!, stackTrace);
      }
    });
    return Cancelable<O>(
      completer,
          () {
        if (!cancelationTokenSource.token.canceled) {
          cancelationTokenSource.cancel();
        }
        if (!completer.isCompleted) {
          completer.completeError(CanceledError());
        }
      },
    );
  }

  factory Cancelable.fromFuture(Future<O> future) {
    final completer = Completer<O>();
    future.then((value) {
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }, onError: (Object e, StackTrace s) => completer.completeError(e, s));
    return Cancelable(completer, () {
      if (!completer.isCompleted) {
        completer.completeError(CanceledError());
      }
    });
  }

  Future<O> get _future => _completer.future;

  static Cancelable<Iterable<R>> mergeAll<R>(Iterable<Cancelable<R>> cancelables,) {
    final resultCompleter = Completer<Iterable<R>>();
    Future.wait(cancelables).then((value) {
      resultCompleter.complete(value);
    }, onError: (Object e) {
      if (!resultCompleter.isCompleted) {
        resultCompleter.completeError(e);
      }
    });
    return Cancelable(resultCompleter, () {
      for (final cancelable in cancelables) {
        cancelable._onCancel?.call();
      }
      if (!resultCompleter.isCompleted) {
        resultCompleter.completeError(CanceledError());
      }
    });
  }

  @override
  Stream<O> asStream() => _future.asStream();

  @override
  Future<O> catchError(Function onError, {
    bool Function(Object error)? test,
  }) =>
      _future.catchError(onError, test: test);

  void _completeError<T>({
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

  void cancel() => _onCancel?.call();

  void _completeValue<T>({required Completer<T> completer, T? value}) {
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  Cancelable<O> withToken(CancelationToken token) {
    if (token.canceled) {
      cancel();
    } else {
      token.addListener(cancel);
    }
    return this;
  }

  Cancelable<R> next<R>({
    FutureOr<R> Function(O value)? onValue,
    FutureOr<R> Function(Object error)? onError,
  }) {
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
    return Cancelable(resultCompleter, () {
      _onCancel?.call();
      _completeError(
        completer: resultCompleter,
        e: CanceledError(),
        onError: onError,
      );
    });
  }

  @override
  Future<O> timeout(Duration timeLimit, {
    FutureOr Function()? onTimeout,
  }) =>
      _future.timeout(timeLimit);

  @override
  Future<O> whenComplete(FutureOr Function() action) =>
      _future.whenComplete(action);

  @override
  Future<R> then<R>(FutureOr<R> Function(O value) onValue, {
    Function? onError,
  }) =>
      _future.then(onValue, onError: onError);
}
