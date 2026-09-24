import 'package:form_mobile/models/wardrobe.dart';

class ItemEdit {
  ItemEdit({
    required String name,
    required String category,
    required String colors,
    required String notes,
    required this.state,
  }) : metadata = ItemMetadata.fromJson({
         'name': name.trim(),
         'category': category,
         'colors': parseColors(colors),
         'notes': notes.trim().isEmpty ? null : notes.trim(),
       }) {
    if (!supportedCategories.contains(category)) {
      throw const FormatException('Choose a supported category');
    }
    if (!itemStates.contains(state)) {
      throw const FormatException('Invalid state');
    }
  }
  final ItemMetadata metadata;
  final String state;
  static List<String> parseColors(String value) =>
      value.split(',').map((c) => c.trim()).toList();
  static bool validColors(String value) =>
      ItemMetadata.validColors(parseColors(value));
  Map<String, dynamic> toJson() => {
    'metadata': metadata.toJson(),
    'state': state,
  };
}
