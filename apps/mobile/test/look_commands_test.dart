import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/feed/look_commands.dart';

void main() {
  test('create command carries selection and idempotency key', () {
    final command = LookCommand.create(
      exactItemIds: ['wardrobe-item-0001'],
      categories: ['top'],
      occasion: 'casual',
      completeWithWardrobe: true,
      parentLookId: 'look-parent',
      preserveComposition: true,
      quality: 'medium',
    );
    expect(command.path, 'v1/looks');
    expect(command.method, 'POST');
    expect(command.body['exactItemIds'], ['wardrobe-item-0001']);
    expect(command.body['completeWithWardrobe'], isTrue);
    expect(command.body['idempotencyKey'], hasLength(48));
    expect(
      LookCommand.create(
        exactItemIds: const [],
        categories: const [],
        occasion: null,
        completeWithWardrobe: false,
        idempotencyKey: 'fixed-key',
      ).body['idempotencyKey'],
      'fixed-key',
    );
    expect(
      command.body['idempotencyKey'],
      isNot(
        LookCommand.create(
          exactItemIds: const [],
          categories: const [],
          occasion: null,
          completeWithWardrobe: false,
        ).body['idempotencyKey'],
      ),
    );
  });

  test('retry and delete target look endpoints', () {
    final retry = LookCommand.retry('look-0001');
    expect(retry.path, 'v1/looks/look-0001/retry');
    expect(retry.method, 'POST');
    expect(retry.body['idempotencyKey'], hasLength(48));
    final delete = LookCommand.delete('look-0001');
    expect(delete.path, 'v1/looks/look-0001');
    expect(delete.method, 'DELETE');
  });
}
