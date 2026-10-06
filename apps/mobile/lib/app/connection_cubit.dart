import 'package:bloc/bloc.dart';
import 'package:form_mobile/repository/server_repository.dart';
import 'package:form_mobile/services/form_api.dart';

enum ConnectionStatus {
  checking,
  ready,
  unavailable,
  missingSession,
  incompatible,
  rejected,
  configurationRequired,
}

class ConnectionCubit extends Cubit<ConnectionStatus> {
  ConnectionCubit(this._repository)
    : super(
        _repository == null
            ? ConnectionStatus.configurationRequired
            : ConnectionStatus.checking,
      );

  final ServerRepository? _repository;
  Future<void>? _running;
  bool _again = false;

  /// A check requested while one is running queues one more run instead of
  /// being dropped. Sign-in relies on this: the resume check fired by the
  /// Apple sheet can start before the session token exists, and its stale
  /// answer must not be the last one.
  Future<void> check() {
    if (_repository == null || isClosed) return Future.value();
    if (_running case final running?) {
      _again = true;
      return running;
    }
    return _running = _runUntilSettled().whenComplete(() => _running = null);
  }

  Future<void> _runUntilSettled() async {
    do {
      _again = false;
      await _checkOnce(_repository!);
    } while (_again && !isClosed);
  }

  Future<void> _checkOnce(ServerRepository repository) async {
    if (isClosed) return;
    emit(ConnectionStatus.checking);
    try {
      await repository.checkAccess();
      if (!isClosed) emit(ConnectionStatus.ready);
    } on FormApiException catch (error) {
      if (!isClosed) {
        emit(switch (error.failure) {
          ApiFailure.unavailable => ConnectionStatus.unavailable,
          ApiFailure.missingSession => ConnectionStatus.missingSession,
          ApiFailure.incompatible => ConnectionStatus.incompatible,
          ApiFailure.rejected => ConnectionStatus.rejected,
        });
      }
    }
  }
}
