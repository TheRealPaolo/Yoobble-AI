import 'package:flutter/material.dart';

// Dans un fichier utils/tab_extensions.dart
extension TabControllerExtensions on TabController {
  /// Navigue vers l'onglet des résultats après la génération du contenu
  /// si l'appareil est en mode mobile (largeur < 768)
  void navigateToResultsTabIfMobile(BuildContext context) {
    if (MediaQuery.of(context).size.width < 600) {
      animateTo(1); // Switch to results tab (index 1)
    }
  }
}
