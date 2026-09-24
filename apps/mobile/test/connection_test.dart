import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/app/connection_cubit.dart';
import 'package:form_mobile/models/server_info.dart';
import 'package:form_mobile/repository/server_repository.dart';
import 'package:form_mobile/services/form_api.dart';

import 'support/fake_server.dart';

void main() {
  test('stable API error codes take precedence over generic HTTP mapping', () {
    final request = RequestOptions(path: 'v1/looks');
    final error = DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(
        requestOptions: request,
        statusCode: 403,
        data: {
          'error': {
            'code': 'authentication-required',
            'message': 'Private text',
          },
        },
      ),
    );
    expect(FormApi.mapFailure(error), ApiFailure.missingSession);
  });

  test(
    'contract DTO round trips and rejects unknown versions and services',
    () {
      const json = {'service': 'form-api', 'contractVersion': 5};
      final info = ServerInfo.fromJson(json);
      expect(info.toJson(), json);
      expect(info.isCompatible, isTrue);
      expect(
        const ServerInfo(service: 'form-api', contractVersion: 6).isCompatible,
        isFalse,
      );
      expect(
        const ServerInfo(service: 'other', contractVersion: 5).isCompatible,
        isFalse,
      );
      expect(
        () => ServerInfo.fromJson({'service': 'form-api'}),
        throwsA(isA<TypeError>()),
      );
      expect(
        PersonalSession.fromJson({
          'accountId': 'fixture-account',
          'email': 'unused',
        }).toJson(),
        {'accountId': 'fixture-account'},
      );
    },
  );

  test(
    'valid contract and personal session open the shell without login',
    () async {
      final adapter = FakeServer(
        (request) async => jsonResponse(
          request.path == 'v1/meta'
              ? '{"service":"form-api","contractVersion":5}'
              : '{"session":{"accountId":"fixture-account"}}',
        ),
      );
      final api = FormApi(Dio()..httpClientAdapter = adapter);
      final cubit = ConnectionCubit(ServerRepository(api));
      addTearDown(api.close);
      addTearDown(cubit.close);
      await cubit.check();
      expect(cubit.state, ConnectionStatus.ready);
      expect(adapter.paths, ['v1/meta', 'v1/auth/session']);
    },
  );

  for (final body in [
    '{"service":"form-api","contractVersion":6}',
    '{"service":"form-api","contractVersion":"5"}',
    '{"service":"another-server","contractVersion":5}',
    '<html>PWA</html>',
  ]) {
    test('incompatible metadata blocks session access: $body', () async {
      final adapter = FakeServer((_) async => jsonResponse(body));
      final api = FormApi(Dio()..httpClientAdapter = adapter);
      final cubit = ConnectionCubit(ServerRepository(api));
      addTearDown(api.close);
      addTearDown(cubit.close);
      await cubit.check();
      expect(cubit.state, ConnectionStatus.incompatible);
      expect(adapter.paths, ['v1/meta']);
    });
  }

  for (final (status, expected) in [
    (401, ConnectionStatus.missingSession),
    (403, ConnectionStatus.rejected),
    (503, ConnectionStatus.unavailable),
  ]) {
    test('session HTTP $status maps to $expected', () async {
      final api = FormApi(
        Dio()
          ..httpClientAdapter = FakeServer(
            (request) async => jsonResponse(
              request.path == 'v1/meta'
                  ? '{"service":"form-api","contractVersion":5}'
                  : '{"error":{"code":"fixture-error"}}',
              request.path == 'v1/meta' ? 200 : status,
            ),
          ),
      );
      final cubit = ConnectionCubit(ServerRepository(api));
      addTearDown(api.close);
      addTearDown(cubit.close);
      await cubit.check();
      expect(cubit.state, expected);
    });
  }

  test('timeout is unavailable and retry can recover', () async {
    var online = false;
    final api = FormApi(
      Dio()
        ..httpClientAdapter = FakeServer((request) async {
          if (!online) {
            throw DioException(
              requestOptions: request,
              type: DioExceptionType.connectionTimeout,
            );
          }
          return jsonResponse(
            request.path == 'v1/meta'
                ? '{"service":"form-api","contractVersion":5}'
                : '{"session":{"accountId":"fixture-account"}}',
          );
        }),
    );
    final cubit = ConnectionCubit(ServerRepository(api));
    final states = <ConnectionStatus>[];
    final subscription = cubit.stream.listen(states.add);
    addTearDown(subscription.cancel);
    addTearDown(api.close);
    addTearDown(cubit.close);
    await cubit.check();
    expect(cubit.state, ConnectionStatus.unavailable);
    online = true;
    await cubit.check();
    await Future<void>.delayed(Duration.zero);
    expect(
      states,
      containsAllInOrder([
        ConnectionStatus.unavailable,
        ConnectionStatus.checking,
        ConnectionStatus.ready,
      ]),
    );
  });

  test(
    'overlapping retries share a check and disposal ignores completion',
    () async {
      final completion = Completer<ResponseBody>();
      final started = Completer<void>();
      final adapter = FakeServer((_) {
        started.complete();
        return completion.future;
      });
      final api = FormApi(Dio()..httpClientAdapter = adapter);
      final cubit = ConnectionCubit(ServerRepository(api));
      addTearDown(api.close);
      final pending = cubit.check();
      await cubit.check();
      await started.future;
      expect(adapter.paths, ['v1/meta']);
      await cubit.close();
      completion.complete(
        jsonResponse('{"service":"form-api","contractVersion":6}'),
      );
      await pending;
    },
  );

  test(
    'missing URL requires configuration without attempting a request',
    () async {
      final cubit = ConnectionCubit(null);
      addTearDown(cubit.close);
      await cubit.check();
      expect(cubit.state, ConnectionStatus.configurationRequired);
    },
  );
}
