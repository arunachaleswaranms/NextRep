/// Runs async tasks strictly one after another, in submission order.
///
/// Used by controllers so rapid taps are applied sequentially, each one
/// seeing the persisted result of the previous one.
final class SerialQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    // The caller observes errors through `result`; the tail only sequences.
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
