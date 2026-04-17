import 'package:flutter/material.dart';
import '../models/help_models.dart';

class HelpContent {
  static const List<FAQItem> globalFAQs = [
    FAQItem(
      question: 'How do I download offline content?',
      answer: 'Go to Settings > Manage Databases. You can download or import Bible and Sermon databases for offline use.',
    ),
    FAQItem(
      question: 'How do I change the app theme?',
      answer: 'Tap the palette icon on the Dashboard or go to Settings to choose between Light, Dark, Sepia, and other color modes.',
    ),
    FAQItem(
      question: 'How do I search across all content?',
      answer: 'Use the Search module from the Dashboard. You can search both Bible verses and Sermon paragraphs simultaneously using keywords or verse references.',
    ),
    FAQItem(
      question: 'Can I read Bible and Sermons side-by-side?',
      answer: 'Yes! Open the Reader, tap the "Split View" icon in the top bar, and choose a parallel source to view two panels at once.',
    ),
    FAQItem(
      question: 'Is the app available in Tamil?',
      answer: 'Yes, the app supports both English and Tamil for the Bible, Sermons, and Questions & Answers (COD).',
    ),
  ];

  static const List<HelpTopic> topics = [
    HelpTopic(
      id: 'dashboard',
      title: 'Dashboard Help',
      sections: [
        HelpSection(
          title: 'Modules',
          icon: Icons.grid_view,
          bulletPoints: [
            'Tap on any module card (e.g., English Bible, Tamil Sermon) to open it.',
            'Modules are grouped by language and content type.',
          ],
        ),
        HelpSection(
          title: 'Continue Reading',
          icon: Icons.restore,
          bulletPoints: [
            'The top cards show your last read Bible and Sermon.',
            'Tap "Resume" to pick up exactly where you left off.',
          ],
        ),
        HelpSection(
          title: 'Quick Actions',
          icon: Icons.flash_on,
          bulletPoints: [
            'Use the icons in the top bar to access your history, change themes, or open system settings.',
          ],
        ),
      ],
    ),
    HelpTopic(
      id: 'reader',
      title: 'Reader Help',
      sections: [
        HelpSection(
          title: 'Navigation',
          icon: Icons.navigation,
          bulletPoints: [
            'Use the "Previous" and "Next" buttons at the bottom to navigate chapters or sermons.',
            'Tap the chapter/sermon title in the top bar for quick navigation.',
          ],
        ),
        HelpSection(
          title: 'Split View',
          icon: Icons.splitscreen,
          bulletPoints: [
            'Tap the Split View icon in the top right to open a second pane.',
            'You can read Bible and Sermon side-by-side, or two different languages of the same book.',
            'On mobile, use the divider handle to adjust the pane heights.',
          ],
        ),
        HelpSection(
          title: 'Text Controls',
          icon: Icons.text_fields,
          bulletPoints: [
            'Adjust font size using the A- and A+ buttons in the header.',
            'Long-press a verse to select it for copying or sharing.',
          ],
        ),
        HelpSection(
          title: 'Search Within',
          icon: Icons.search,
          bulletPoints: [
            'Tap the search icon in the header to find specific words within the current chapter or sermon.',
          ],
        ),
      ],
    ),
    HelpTopic(
      id: 'search',
      title: 'Search Help',
      sections: [
        HelpSection(
          title: 'Search Methods',
          icon: Icons.manage_search,
          bulletPoints: [
            'Keywords: Enter any word or phrase to find matches.',
            'Verse References: Type references like "John 3:16" to jump directly to a verse.',
          ],
        ),
        HelpSection(
          title: 'Filters',
          icon: Icons.filter_list,
          bulletPoints: [
            'Bible: Filter by Old/New Testament or specific books.',
            'Sermons: Filter by year range (e.g., 1947–1965).',
          ],
        ),
        HelpSection(
          title: 'Languages',
          icon: Icons.language,
          bulletPoints: [
            'Switch between EN (English) and TA (Tamil) chips to search in different languages.',
          ],
        ),
      ],
    ),
    HelpTopic(
      id: 'cod',
      title: 'COD Help',
      sections: [
        HelpSection(
          title: 'Questions & Answers',
          icon: Icons.question_answer,
          bulletPoints: [
            'Browse church questions answered by Rev. William Branham.',
            'Topics: Scroll through the horizontal list at the top to filter questions by category.',
          ],
        ),
        HelpSection(
          title: 'Finding Answers',
          icon: Icons.search,
          bulletPoints: [
            'Use the search bar to find specific keywords within the questions or answers.',
            'Tap on any question to view the full answer and related sermon references.',
          ],
        ),
      ],
    ),
    HelpTopic(
      id: 'songs',
      title: 'Songs Help',
      sections: [
        HelpSection(
          title: 'Only Believe Songbook',
          icon: Icons.music_note,
          bulletPoints: [
            'Search for hymns by typing their number (1–1196) or title.',
            'Category Filtering: Use the filter icon to browse by song categories (e.g., Worship, Baptism).',
          ],
        ),
        HelpSection(
          title: 'Song Details',
          icon: Icons.list,
          bulletPoints: [
            'Tap a song to see the full lyrics.',
            'Change the font size using the controls in the song detail header.',
          ],
        ),
      ],
    ),
    HelpTopic(
      id: 'sermons',
      title: 'Sermon List Help',
      sections: [
        HelpSection(
          title: 'Browsing Sermons',
          icon: Icons.history_edu,
          bulletPoints: [
            'Browse messages by year or search for titles by keyword.',
            'Filter by speaker or specific time periods using the advanced filters.',
          ],
        ),
        HelpSection(
          title: 'Seven Seals',
          icon: Icons.layers,
          bulletPoints: [
            'Access the Seven Seals series directly from the Dashboard for a curated chronological reading.',
          ],
        ),
      ],
    ),
  ];

  static HelpTopic getTopic(String id) {
    return topics.firstWhere(
      (topic) => topic.id == id,
      orElse: () => topics.first,
    );
  }
}
