import 'dart:async';
import 'dart:io';

const enterKey = [10];
const spaceKey = [32];
const downArrowKey = [27, 91, 66];

/// Swallows all actual output and can configure whether or not it has a
/// terminal.
///
/// Intended for use with [IOOverrides.runZoned].
class DummyStdout implements Stdout {
  @override
  final bool hasTerminal;

  DummyStdout({this.hasTerminal = true});

  @override
  void writeln([Object? object = '']) {}

  @override
  void write(Object? object) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Never provides input and can configure whether or not it has a terminal.
///
/// Intended for use with [IOOverrides.runZoned].
class DummyStdin extends Stream<List<int>> implements Stdin {
  @override
  final bool hasTerminal;

  @override
  bool lineMode = true;

  @override
  bool echoMode = true;

  DummyStdin({this.hasTerminal = true});

  @override
  int readByteSync() => throw UnimplementedError();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.empty().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
