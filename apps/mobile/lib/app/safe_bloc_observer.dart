import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';

class SafeBlocObserver extends BlocObserver {
  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    if (kDebugMode) debugPrint('${bloc.runtimeType}: state changed');
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    // Never interpolate states, exception messages, or stack traces.
    if (kDebugMode) debugPrint('${bloc.runtimeType}: operation failed');
  }
}
