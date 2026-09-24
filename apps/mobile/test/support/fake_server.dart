import 'dart:typed_data';

import 'package:dio/dio.dart';

class FakeServer implements HttpClientAdapter {
  FakeServer(this.respond);

  final Future<ResponseBody> Function(RequestOptions) respond;
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    paths.add(options.path);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(String body, [int status = 200]) =>
    ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
