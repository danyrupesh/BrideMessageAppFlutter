import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class DeveloperDetailsScreen extends StatelessWidget {
  const DeveloperDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── Hero Header ──
          const _HeroHeader(),
          const SizedBox(height: 16),

          // ── Vision & Sponsorship ──
          _AboutSectionCard(
            label: 'Vision & Sponsorship',
            children: [
              const _InfoLabel('Project Vision & Sponsor'),
              _PersonRow(
                name: 'Bro. Kathiresan',
                church: 'Calvary Tabernacle, Chennai',
                email: 'contact@endtimebride.in',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Spiritual Oversight ──
          _AboutSectionCard(
            label: 'Spiritual Oversight',
            children: [
              const _InfoLabel('Project Guidance'),
              _PersonRow(
                name: 'Pr. James Srini',
                church: 'Revival Message Tabernacle, Coimbatore',
                email: 'contact@endtimebride.in',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── App Website ──
          _AboutSectionCard(
            label: 'App Website',
            children: [
              _OrgRow(
                name: 'Bride Message App',
                website: 'endtimebride.in',
                url: 'https://endtimebride.in/',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Developed By ──
          _AboutSectionCard(
            label: 'Developed By',
            children: [
              _OrgRow(
                name: 'NiflaRosh Technologies',
                website: 'niflarosh.com',
                url: 'https://niflarosh.com',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Development Team ──
          _AboutSectionCard(
            label: 'Development Team',
            children: [
              _PersonRow(
                name: 'Bro. Dany Rufus',
                church: 'Revival Message Tabernacle, Coimbatore',
                email: 'danyrupesh@gmail.com',
              ),
              const Divider(height: 24),
              _PersonRow(
                name: 'Bro. Samuel Jonathan',
                church: 'Endtime Church, Trichy',
                email: 'jesusforsam@gmail.com',
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Hero Header Component ──
class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '0.1.0';

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 12),
            Text(
              'BrideMessageApp',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'A Digital Ministry for the End-Time Bride',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            _VersionChip(version: 'v$version'),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

// ── Version Chip Component ──
class _VersionChip extends StatelessWidget {
  final String version;

  const _VersionChip({required this.version});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        version,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Section Card Component ──
class _AboutSectionCard extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _AboutSectionCard({
    required this.label,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ── Info Label Component ──
class _InfoLabel extends StatelessWidget {
  final String text;

  const _InfoLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      text,
      style: theme.textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ── Person Row Component ──
class _PersonRow extends StatelessWidget {
  final String name;
  final String church;
  final String email;

  const _PersonRow({
    required this.name,
    required this.church,
    required this.email,
  });

  void _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                church,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                email,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Material(
          shape: const CircleBorder(),
          color: Colors.transparent,
          child: IconButton(
            icon: const Icon(Icons.email),
            onPressed: _launchEmail,
            tooltip: 'Send email',
          ),
        ),
      ],
    );
  }
}

// ── Org/Website Row Component ──
class _OrgRow extends StatelessWidget {
  final String name;
  final String website;
  final String url;

  const _OrgRow({
    required this.name,
    required this.website,
    required this.url,
  });

  void _launchUrl() async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                website,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Material(
          shape: const CircleBorder(),
          color: Colors.transparent,
          child: IconButton(
            icon: const Icon(Icons.language),
            onPressed: _launchUrl,
            tooltip: 'Open website',
          ),
        ),
      ],
    );
  }
}
