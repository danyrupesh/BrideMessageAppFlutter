import 'package:flutter/material.dart';

class SermonScreen extends StatelessWidget {
  final String sermonId;
  final String sermonTitle;

  const SermonScreen({Key? key, required this.sermonId, required this.sermonTitle}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Logic for copying the sermonId and sermonTitle
        Clipboard.setData(ClipboardData(text: '$sermonId - $sermonTitle'));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $sermonId - $sermonTitle')));
      },
      child: Tooltip(
        message: 'Copy Sermon Info',
        child: Column(
          children: [
            Text(
              sermonTitle,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), // Adjust for your layout
            ),
            Text(
              sermonId,
              style: TextStyle(fontSize: 16), // Likewise
            ),
          ],
        ),
      ),
    );
  }
}