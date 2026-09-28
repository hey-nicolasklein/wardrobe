import 'package:bloc/bloc.dart';
import 'package:form_mobile/repository/credits_repository.dart';

/// The signed-in account's credit balance. Null until the first fetch
/// succeeds and again after sign-out. Failed refreshes keep the last value.
class CreditsCubit extends Cubit<Credits?> {
  CreditsCubit(this._repository) : super(null);

  final CreditsRepository _repository;
  int _requestId = 0;

  Future<void> refresh() async {
    final id = ++_requestId;
    try {
      final credits = await _repository.fetch();
      if (!isClosed && id == _requestId) emit(credits);
    } on Object {
      // The wallet stays on its last known balance.
    }
  }

  void clear() {
    _requestId++;
    if (!isClosed) emit(null);
  }
}
