import 'package:flutter/material.dart';

class SearchHelpScreen extends StatelessWidget {
  const SearchHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Help'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to Search',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Bride Message Search supports powerful Bible + Sermon search with different match modes, language filters, and advanced filters.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _SearchTypeCard(
              title: '1️⃣ Exact Phrase (Default on Android)',
              description:
                  'Finds words in the exact order you type them. Best for quotes and specific phrases.',
              examples: const [
                _SearchExample(
                  input: 'born again',
                  expected:
                      "Matches: 'ye must be born again'\nNo match: 'again you must be born'",
                ),
                _SearchExample(
                  input: 'kingdom of heaven',
                  expected:
                      "Matches: 'the kingdom of heaven is at hand'\nNo match: 'heaven belongs to the kingdom'",
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SearchTypeCard(
              title: '2️⃣ Smart (All Words)',
              description:
                  'Finds verses/sermons containing ALL the words you type (in any order). This is the default in Flutter.',
              examples: const [
                _SearchExample(
                  input: 'faith obedience',
                  expected:
                      "Matches: 'faith without obedience is dead'\nMatches: 'obedience comes from faith'\nNo match: 'only faith' (missing obedience)",
                ),
                _SearchExample(
                  input: 'grace salvation Jesus',
                  expected:
                      'Must contain all three words (order does not matter).',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SearchTypeCard(
              title: '3️⃣ Any Word',
              description:
                  'Finds results containing at least one word. Good for broad exploration.',
              examples: const [
                _SearchExample(
                  input: 'healing miracle',
                  expected:
                      "Matches: 'healing of the sick'\nMatches: 'the miracle happened'\nMatches: 'miraculous healing'",
                ),
                _SearchExample(
                  input: 'cross sacrifice redemption',
                  expected:
                      'Shows verses with any of these words (broadest search).',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SearchTypeCard(
              title: '4️⃣ Autocomplete (Prefix)',
              description:
                  'As-you-type search. Automatically adds a wildcard to your last word.',
              examples: const [
                _SearchExample(
                  input: 'God is go',
                  expected:
                      "Finds: 'God is good', 'God is going', 'God is gone', etc.",
                ),
                _SearchExample(
                  input: 'faith witho',
                  expected:
                      "Finds: 'faith without works', 'faith without obedience', etc.",
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SearchTypeCard(
              title: '🎯 Ranking modes',
              description:
                  'These options only change how results are ordered after matching. They never change which verses or sermons can appear.',
              examples: const [
                _SearchExample(
                  input: 'Standard rank',
                  expected:
                      'Default relevance scoring for the selected search type.',
                ),
                _SearchExample(
                  input: 'Accurate rank',
                  expected:
                      'Uses stricter scoring, often pushing more exact matches to the top while returning the same set of results.',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SearchTypeCard(
              title: '📖 Verse Reference Search',
              description:
                  'Jump directly to Bible verses by typing references in many common formats.',
              examples: const [
                _SearchExample(
                  input: 'John 3:16',
                  expected: "Shows: 'For God so loved the world...'",
                ),
                _SearchExample(
                  input: 'Genesis 1',
                  expected: 'Shows entire chapter (all verses in Genesis 1).',
                ),
                _SearchExample(
                  input: 'Matt 24:29-31',
                  expected: 'Shows the verse range.',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SearchTypeCard(
              title: '📚 Bible / Sermons Tabs',
              description: 'Control what you are searching.',
              examples: const [
                _SearchExample(
                  input: 'Bible tab',
                  expected:
                      'Searches only Bible verses. Use book/testament filters.',
                ),
                _SearchExample(
                  input: 'Sermons tab',
                  expected:
                      'Searches only sermon paragraphs. Use year filters to narrow by time.',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SearchTypeCard(
              title: '🎛 Filters (Advanced)',
              description:
                  'Use the filters icon on each tab to refine your search.',
              examples: const [
                _SearchExample(
                  input: 'Bible filters',
                  expected:
                      'Filter by Testament (OT/NT), pick specific books, and choose sort order (Relevance / Book Order).',
                ),
                _SearchExample(
                  input: 'Sermon filters',
                  expected:
                      'Filter by year range (e.g. 1947–1965) for sermon searches.',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SearchTypeCard(
              title: '🌐 Tamil & English Search',
              description:
                  'Use the EN / TA chips under the search bar to switch between English and Tamil.',
              examples: const [
                _SearchExample(
                  input: 'English',
                  expected: 'Searches English Bible and English sermons only.',
                ),
                _SearchExample(
                  input: 'தமிழ் (Tamil)',
                  expected:
                      'Searches Tamil Bible and Tamil sermons only. Type queries directly in Tamil script for best results.',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ProTipsSection(),
          ],
        ),
      ),
    );
  }
}

class _SearchTypeCard extends StatelessWidget {
  const _SearchTypeCard({
    required this.title,
    required this.description,
    required this.examples,
  });

  final String title;
  final String description;
  final List<_SearchExample> examples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Column(
              children: examples
                  .map(
                    (e) => _ExampleBox(
                      input: e.input,
                      expected: e.expected,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExampleBox extends StatelessWidget {
  const _ExampleBox({
    required this.input,
    required this.expected,
  });

  final String input;
  final String expected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Input:',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          Text(
            input,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Result:',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.secondary,
            ),
          ),
          Text(
            expected,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ProTipsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '💡 Pro Tips',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const _BulletPoint(
              'Smart (All Words) is the default in this app; use Exact Phrase for strict quotes.',
            ),
            const _BulletPoint(
              'Use Any Word when exploring related concepts or when you are not sure of the exact wording.',
            ),
            const _BulletPoint(
              "Type verse references directly (e.g., 'John 3:16', 'Matt 24:29-31', '1 Cor 13:4-8').",
            ),
            const _BulletPoint(
              'Use filters (book, testament, year) to narrow results quickly.',
            ),
            const _BulletPoint(
              'Toggle between English and Tamil anytime to see results for that language only.',
            ),
          ],
        ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  const _BulletPoint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: theme.textTheme.bodyMedium),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchExample {
  const _SearchExample({
    required this.input,
    required this.expected,
  });

  final String input;
  final String expected;
}

