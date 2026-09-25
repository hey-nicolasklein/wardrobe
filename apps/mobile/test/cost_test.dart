import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/settings/cost_cubit.dart';
import 'package:form_mobile/features/settings/cost_display.dart';
import 'package:form_mobile/features/settings/cost_week.dart';
import 'package:form_mobile/models/generation_costs.dart';
import 'package:form_mobile/repository/generation_cost_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/widgets/form_cost_gauge.dart';

Map<String, dynamic> fixture() => {
  'lookTotalMicrounits': 1000000,
  'successfulLookCount': 2,
  'averageSuccessfulLookMicrounits': 500000,
  'characterSheetTotalMicrounits': 9000000,
  'wardrobeTotalMicrounits': 1000000,
  'wardrobeRequestCount': 3,
  'detectionTotalMicrounits': 1000000,
  'detectionRequestCount': 4,
};

class CostApi extends FormApi {
  CostApi() : super(Dio());
  final paths = <String>[];
  Future<Map<String, dynamic>> Function()? respond;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) async {
    paths.add(path);
    return respond == null ? {'costs': fixture()} : respond!();
  }
}

void main() {
  test('ISO weeks span years, leap years and DST with calendar arithmetic', () {
    for (final entry in {
      DateTime(2021): '2020-W53',
      DateTime(2021, 1, 4): '2021-W01',
      DateTime(2018, 12, 31): '2019-W01',
      DateTime(2024, 2, 29): '2024-W09',
      DateTime(2026, 3, 29): '2026-W13',
      DateTime(2026, 3, 30): '2026-W14',
    }.entries) {
      final week = CostWeek.fromDate(entry.key);
      expect(week.value, entry.value);
      expect(CostWeek.parse(entry.value), week);
      expect(week.monday.weekday, DateTime.monday);
      expect(week.sunday.weekday, DateTime.sunday);
    }
    expect(CostWeek.parse('2020-W53').offset(1).value, '2021-W01');
    expect(CostWeek.parse('2021-W01').offset(-1).value, '2020-W53');
    for (final value in ['2021-W53', '2026-W00', '2026-W54', '2026-01']) {
      expect(() => CostWeek.parse(value), throwsFormatException);
    }
  });
  test('cost DTO requires every nonnegative integral contract field', () {
    expect(GenerationCosts.fromJson(fixture()).detectionRequestCount, 4);
    for (final field in fixture().keys) {
      expect(
        () => GenerationCosts.fromJson(fixture()..remove(field)),
        throwsFormatException,
      );
      expect(
        () => GenerationCosts.fromJson(fixture()..[field] = -1),
        throwsFormatException,
      );
      expect(
        () => GenerationCosts.fromJson(fixture()..[field] = 1.5),
        throwsFormatException,
      );
    }
  });
  test(
    'display totals exclude character cost and rounded shares sum to 100',
    () {
      final display = CostDisplay(GenerationCosts.fromJson(fixture()));
      expect(display.totalMicrounits, 3000000);
      expect(display.parts.map((part) => part.share), [33, 33, 34]);
      expect(display.parts.map((part) => part.count), [2, 3, 4]);
      expect(display.averageMicrounits, 500000);
      final empty = CostDisplay(
        GenerationCosts.fromJson({for (final key in fixture().keys) key: 0}),
      );
      expect(empty.parts.every((part) => part.share == null), isTrue);
      expect(costMoney(1234567, 'en_US'), contains('1.23'));
      expect(costMoney(1234567, 'de_DE'), contains('1,23'));
    },
  );
  test(
    'half ring reserves tiny nonzero arcs and no gaps for a single source',
    () {
      expect(costGaugeArcs([0, 0, 0]), isEmpty);
      expect(costGaugeArcs([1, 0, 0]).single.length, costGaugeLength);
      final arcs = costGaugeArcs([999999, 0, 1]);
      expect(arcs.map((arc) => arc.index), [0, 2]);
      expect(arcs.last.length, costGaugeWidth);
      expect(
        arcs.last.start + arcs.last.length,
        closeTo(costGaugeLength, 0.0001),
      );
    },
  );
  test('repository sends selected week and maps invalid responses', () async {
    final api = CostApi();
    final repository = GenerationCostRepository(api);
    await repository.fetch(CostWeek.parse('2026-W39'));
    expect(api.paths.single, 'v1/generation-costs?week=2026-W39');
    api.respond = () async => {'costs': <String, dynamic>{}};
    await expectLater(
      repository.fetch(CostWeek.parse('2026-W39')),
      throwsA(
        isA<FormApiException>().having(
          (e) => e.failure,
          'failure',
          ApiFailure.incompatible,
        ),
      ),
    );
  });
  test(
    'week navigation prevents future weeks and discards late responses',
    () async {
      final api = CostApi();
      final cubit = CostCubit(
        GenerationCostRepository(api),
        now: () => DateTime(2026, 9, 25),
      );
      addTearDown(cubit.close);
      await cubit.nextWeek();
      expect(api.paths, isEmpty);
      final first = Completer<Map<String, dynamic>>();
      api.respond = () => first.future;
      final old = cubit.refresh();
      api.respond = () async => {'costs': fixture()};
      await cubit.previousWeek();
      expect(cubit.state.week.value, '2026-W38');
      expect(cubit.state.canGoNext, isTrue);
      first.complete({
        'costs': {...fixture(), 'lookTotalMicrounits': 99},
      });
      await old;
      expect(cubit.state.costs!.lookTotalMicrounits, 1000000);
      await cubit.nextWeek();
      expect(cubit.state.isCurrentWeek, isTrue);
      expect(cubit.state.canGoNext, isFalse);
      api.respond = () async =>
          throw const FormApiException(ApiFailure.unavailable);
      await cubit.previousWeek();
      expect(cubit.state.failure, ApiFailure.unavailable);
      expect(cubit.state.costs, isNull);
    },
  );
}
