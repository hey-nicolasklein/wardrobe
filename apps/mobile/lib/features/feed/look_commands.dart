import 'package:form_mobile/utils/idempotency_key.dart';
import 'package:form_mobile/utils/immutable_json.dart';

class LookCommand {
  LookCommand(this.path, this.method, Map<String, dynamic> fields)
    : lookId = null,
      body = immutableJson({
        ...fields,
        if (!fields.containsKey('idempotencyKey'))
          'idempotencyKey': newIdempotencyKey(),
      });

  factory LookCommand.create({
    required List<String> exactItemIds,
    required List<String> categories,
    required String? occasion,
    required bool completeWithWardrobe,
    String? parentLookId,
    bool preserveComposition = false,
    String quality = 'low',
    String? idempotencyKey,
  }) => LookCommand('v1/looks', 'POST', {
    'exactItemIds': exactItemIds,
    'categories': categories,
    'occasion': occasion,
    'completeWithWardrobe': completeWithWardrobe,
    'parentLookId': parentLookId,
    'preserveComposition': preserveComposition,
    'quality': quality,
    'idempotencyKey': ?idempotencyKey,
  });

  factory LookCommand.retry(String lookId) =>
      LookCommand('v1/looks/$lookId/retry', 'POST', {});

  LookCommand.delete(this.lookId)
    : path = 'v1/looks/${lookId!}',
      method = 'DELETE',
      body = const {};

  final String path;
  final String method;
  final Map<String, dynamic> body;

  /// The look a DELETE removes. Null for every other command.
  final String? lookId;
}
