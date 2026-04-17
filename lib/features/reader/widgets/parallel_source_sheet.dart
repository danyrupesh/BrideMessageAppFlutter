import 'package:flutter/material.dart';

class ParallelSourceSheet extends StatelessWidget {
  const ParallelSourceSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => const ParallelSourceSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _item(context, 'bible_ta', Icons.menu_book, 'Tamil Bible (BSI)'),
            _item(
              context,
              'bible_en',
              Icons.menu_book_outlined,
              'English Bible (KJV)',
            ),
            _item(
              context,
              'sermon_ta',
              Icons.library_books,
              'Tamil Sermons',
            ),
            _item(
              context,
              'sermon_en',
              Icons.library_books_outlined,
              'English Sermons',
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    String value,
    IconData icon,
    String label,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}
