import 'package:flutter/material.dart';
import '../models/help_models.dart';
import '../data/help_content.dart';

class HelpSheet extends StatelessWidget {
  final String topicId;

  const HelpSheet({
    super.key,
    required this.topicId,
  });

  static Future<void> show(BuildContext context, String topicId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => HelpSheet(topicId: topicId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final topic = HelpContent.getTopic(topicId);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                TabBar(
                  tabs: const [
                    Tab(text: 'How to Use'),
                    Tab(text: 'General FAQ'),
                  ],
                  labelColor: cs.primary,
                  unselectedLabelColor: cs.onSurfaceVariant,
                  indicatorColor: cs.primary,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildHelpContent(context, topic, scrollController),
                      _buildFAQContent(context, scrollController),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHelpContent(
    BuildContext context,
    HelpTopic topic,
    ScrollController scrollController,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Icon(Icons.help_outline, color: cs.primary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                topic.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ...topic.sections.map((section) => _buildSection(context, section)),
        const SizedBox(height: 40),
        Center(
          child: Text(
            'Need more help? Check the FAQ tab.',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(BuildContext context, HelpSection section) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (section.icon != null) ...[
                Icon(section.icon, size: 20, color: cs.secondary),
                const SizedBox(width: 10),
              ],
              Text(
                section.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...section.bulletPoints.map((point) => Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        point,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                          color: cs.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildFAQContent(
    BuildContext context,
    ScrollController scrollController,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final faqs = HelpContent.globalFAQs;

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: faqs.length,
      itemBuilder: (context, index) {
        final faq = faqs[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: ExpansionTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: Icon(Icons.quiz_outlined, color: cs.primary),
            title: Text(
              faq.question,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                faq.answer,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
