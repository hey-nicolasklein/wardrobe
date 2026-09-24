import 'dart:math';
import 'dart:ui';

import 'package:form_mobile/models/wardrobe.dart';
import 'package:json_annotation/json_annotation.dart';

part 'intake.g.dart';

String intakeKey() {
  final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

enum DraftPhase {
  local,
  uploading,
  uploaded,
  detecting,
  ready,
  manual,
  saving,
  finished,
  discarded,
}

@JsonSerializable(checked: true)
class DetectionBox {
  DetectionBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) {
    if (x < 0 ||
        y < 0 ||
        width <= 0 ||
        height <= 0 ||
        x + width > 1000 ||
        y + height > 1000) {
      throw const FormatException('Invalid detection geometry');
    }
  }
  factory DetectionBox.fromJson(Map<String, dynamic> json) =>
      _$DetectionBoxFromJson(json);
  final int x;
  final int y;
  final int width;
  final int height;
  Rect pixels(Size size) => Rect.fromLTWH(
    x * size.width / 1000,
    y * size.height / 1000,
    width * size.width / 1000,
    height * size.height / 1000,
  );
  Map<String, dynamic> toJson() => _$DetectionBoxToJson(this);
}

@JsonSerializable(checked: true, explicitToJson: true)
class DetectionProposal {
  DetectionProposal({
    required this.id,
    required this.name,
    required this.category,
    required List<String> colors,
    required this.boundingBox,
  }) : colors = List.unmodifiable(colors);
  factory DetectionProposal.fromJson(Map<String, dynamic> json) =>
      _$DetectionProposalFromJson(json);
  final String id;
  final String name;
  final String category;
  final List<String> colors;
  final DetectionBox boundingBox;
  Map<String, dynamic> toJson() => _$DetectionProposalToJson(this);
}

@JsonSerializable(checked: true, explicitToJson: true)
class IntakeChoice {
  IntakeChoice({
    required this.itemKey,
    required this.generationKey,
    this.proposal,
    this.metadata,
    this.selected = true,
    this.ownership = 'owning',
    this.itemId,
    this.enqueued = false,
    this.command,
  });
  factory IntakeChoice.fromJson(Map<String, dynamic> json) =>
      _$IntakeChoiceFromJson(json);
  final String itemKey;
  final String generationKey;
  final DetectionProposal? proposal;
  final ItemMetadata? metadata;
  bool selected;
  String ownership;
  String? itemId;
  bool enqueued;
  // Freeze the payload before sending: an uncertain retry must be identical.
  Map<String, dynamic>? command;
  bool get locked => command != null;
  Map<String, dynamic> toJson() => _$IntakeChoiceToJson(this);
}

@JsonSerializable(checked: true, explicitToJson: true)
class IntakeDraft {
  IntakeDraft({
    required this.id,
    required this.filePath,
    required this.width,
    required this.height,
    required this.completionKey,
    required this.detectionKey,
    this.phase = DraftPhase.local,
    this.sourceId,
    this.intent,
    this.failure,
    this.ownership = 'owning',
    this.quality = 'low',
    List<IntakeChoice>? choices,
  }) : choices = choices ?? [];
  factory IntakeDraft.fromJson(Map<String, dynamic> json) =>
      _$IntakeDraftFromJson(json);
  final String id;
  final String filePath;
  final int width;
  final int height;
  String completionKey;
  final String detectionKey;
  DraftPhase phase;
  String? sourceId;
  Map<String, dynamic>? intent;
  String? failure;
  String ownership;
  final String quality;
  final List<IntakeChoice> choices;
  Map<String, dynamic> toJson() => _$IntakeDraftToJson(this);
  IntakeDraft snapshot() => IntakeDraft.fromJson(toJson());
}
