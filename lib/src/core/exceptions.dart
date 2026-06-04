/// Exception that is thrown when the user aborts an operation.
class UserAbortException implements Exception {
  final String message;

  new(this.message);

  @override
  String toString() => message;
}
