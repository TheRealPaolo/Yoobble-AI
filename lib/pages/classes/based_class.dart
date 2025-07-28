// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

abstract class BaseGenerator extends StatefulWidget {
  final String? title;
  final Color? iconColor;
  final IconData? icon;

  const BaseGenerator({
    super.key,
    this.title,
    this.iconColor,
    this.icon,
  });
}

abstract class BaseGeneratorState<T extends BaseGenerator> extends State<T> {
  bool isGenerating = false;
  bool isCopied = false;
  bool isSaved = false;
  bool isEditing = false;
  String generatedContent = '';
  final TextEditingController generatedContentController =
      TextEditingController();

  // Listes communes
  final List<String> tones = [
    'Professionnel',
    'Amical',
    'Informatif',
    'Persuasif',
    'Inspirant',
    'Humoristique',
    'Formel'
  ];

  final List<String> languages = [
    'Français',
    'Anglais',
    'Espagnol',
    'Allemand',
    'Italien'
  ];

  // Méthodes à implémenter
  Widget buildForm();
  void generateContent();

  // Méthode pour afficher une erreur
  void showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Widget pour construire les en-têtes de section
  Widget buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: widget.iconColor,
        ),
        SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: widget.iconColor,
          ),
        ),
      ],
    );
  }

  // Widget pour construire les champs de texte
  Widget buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    bool required = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 4),
            child: Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey[600]),
                SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
                if (required)
                  Text(
                    ' *',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: 12, right: 12, bottom: 12),
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Widget pour construire les listes déroulantes
  Widget buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 4),
            child: Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey[600]),
                SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: 12, right: 12, bottom: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                icon: Icon(Icons.arrow_drop_down, color: widget.iconColor),
                style: TextStyle(color: Colors.black87, fontSize: 14),
                onChanged: onChanged,
                items: items.map<DropdownMenuItem<String>>((String item) {
                  return DropdownMenuItem<String>(
                    value: item,
                    child: Text(item),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Méthode pour copier le contenu dans le presse-papier
  void copyToClipboard(String text) {
    // Cette partie serait implémentée avec Clipboard.setData dans une application réelle
    setState(() {
      isCopied = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Contenu copié dans le presse-papier!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );

    Future.delayed(Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          isCopied = false;
        });
      }
    });
  }

  // Méthode pour sauvegarder le contenu
  void saveContent() {
    // Cette partie serait implémentée avec une logique de sauvegarde réelle
    setState(() {
      isSaved = true;
      if (isEditing) {
        generatedContent = generatedContentController.text;
        isEditing = false;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Contenu sauvegardé avec succès!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );

    Future.delayed(Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          isSaved = false;
        });
      }
    });
  }
}
