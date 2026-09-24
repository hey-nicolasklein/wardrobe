import 'package:form_mobile/repository/wardrobe_repository.dart';

final colorPatterns = <String, RegExp>{
  'black': RegExp('schwarz|black|anthrazit|charcoal'),
  'white': RegExp('weiß|weiss|white|elfenbein|ivory|off.?white'),
  'gray': RegExp('grau|gr[ae]y|silber|silver'),
  'beige': RegExp('beige|creme|cream|sand|ecru'),
  'brown': RegExp('braun|brown|camel|cognac|taupe|chocolat|schoko'),
  'blue': RegExp('blau|blue|navy|denim|türkis|tuerkis|turquoise|petrol|teal'),
  'green': RegExp('grün|gruen|green|oliv|khaki|mint|salbei|sage'),
  'yellow': RegExp('gelb|yellow|gold|senf|mustard'),
  'orange': RegExp(
    'orange|apricot|aprikos|peach|pfirsich|terracotta|rost|rust',
  ),
  'red': RegExp('rot|red|bordeaux|burgund|burgundy|wein|korall|coral'),
  'purple': RegExp('lila|purple|violet|lavendel|lavender|flieder|mauve'),
  'pink': RegExp('rosa|pink|rosé|rose|magenta|fuchsia'),
  'other': RegExp('bunt|multi'),
};

Set<String> colorFamilies(String color) {
  final matches = colorPatterns.entries
      .where((e) => e.value.hasMatch(color.toLowerCase().trim()))
      .map((e) => e.key)
      .toSet();
  return matches.isEmpty ? {'other'} : matches;
}

class WardrobeFilter {
  const WardrobeFilter({
    this.state = 'all',
    this.query = '',
    this.categories = const {},
    this.colors = const {},
  });
  final String state;
  final String query;
  final Set<String> categories;
  final Set<String> colors;
  bool get isFiltered =>
      state != 'all' ||
      query.isNotEmpty ||
      categories.isNotEmpty ||
      colors.isNotEmpty;
  WardrobeFilter copyWith({
    String? state,
    String? query,
    Set<String>? categories,
    Set<String>? colors,
  }) => WardrobeFilter(
    state: state ?? this.state,
    query: query ?? this.query,
    categories: categories ?? this.categories,
    colors: colors ?? this.colors,
  );

  List<CachedItem> apply(
    List<CachedItem> records, {
    required bool archived,
    required Map<String, String> categoryLabels,
  }) {
    return records.where((record) {
      final item = record.item;
      final metadata = item.metadata;
      final searchable = [
        metadata.name,
        ...metadata.colors,
        metadata.notes ?? '',
        categoryLabels[metadata.category] ?? metadata.category,
      ].join(' ').toLowerCase();
      return (item.state == 'archived') == archived &&
          (archived || state == 'all' || item.state == state) &&
          (categories.isEmpty || categories.contains(metadata.category)) &&
          (colors.isEmpty ||
              metadata.colors.any(
                (c) => colorFamilies(c).intersection(colors).isNotEmpty,
              )) &&
          searchable.contains(query.toLowerCase());
    }).toList()..sort((a, b) => b.item.createdAt.compareTo(a.item.createdAt));
  }
}
