import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

class SermonHtmlPreview extends StatelessWidget {
  final String html;
  final EdgeInsetsGeometry? padding;

  const SermonHtmlPreview({
    super.key,
    required this.html,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final widget = HtmlWidget(
      html,
      textStyle: const TextStyle(
        fontFamily: 'NotoSerifTamil',
        fontSize: 14,
        height: 1.4,
      ),
    );

    if (padding != null) {
      return Padding(
        padding: padding!,
        child: widget,
      );
    }
    return widget;
  }
}
