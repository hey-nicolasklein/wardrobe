import 'dart:math';

/// A random 48-character hex key for one logical server command. Reuse the
/// same key when retrying that command so the server never runs it twice.
String newIdempotencyKey() => List.generate(
  24,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
