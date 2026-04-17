import 'package:flutter/material.dart';

class HelpTopic {
  final String id;
  final String title;
  final List<HelpSection> sections;

  const HelpTopic({
    required this.id,
    required this.title,
    required this.sections,
  });
}

class HelpSection {
  final String title;
  final List<String> bulletPoints;
  final IconData? icon;

  const HelpSection({
    required this.title,
    required this.bulletPoints,
    this.icon,
  });
}

class FAQItem {
  final String question;
  final String answer;

  const FAQItem({
    required this.question,
    required this.answer,
  });
}
