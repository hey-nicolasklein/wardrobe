import 'package:flutter/material.dart';
import 'package:form_mobile/repository/overview_repository.dart';
import 'package:form_mobile/widgets/foundation_page.dart';

class WardrobePage extends StatelessWidget {
  const WardrobePage({super.key});

  @override
  Widget build(BuildContext context) =>
      const FoundationPage(collection: Collection.wardrobe);
}
