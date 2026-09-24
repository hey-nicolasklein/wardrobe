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
  bool _checking = false;

  Future<void> check() async {
    final repository = _repository;
    if (_checking || repository == null || isClosed) return;
    _checking = true;
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
    } finally {
      _checking = false;
    }
  }
}
