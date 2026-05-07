import 'package:flutter/material.dart';

class HorizontalScrollWithArrows extends StatefulWidget {
  const HorizontalScrollWithArrows({
    super.key,
    required this.children,
    this.scrollStep = 260,
    this.arrowSize = 36,
    this.arrowIconSize = 20,
    this.padding,
  });

  final List<Widget> children;
  final double scrollStep;
  final double arrowSize;
  final double arrowIconSize;
  final EdgeInsetsGeometry? padding;

  @override
  State<HorizontalScrollWithArrows> createState() => _HorizontalScrollWithArrowsState();
}

class _HorizontalScrollWithArrowsState extends State<HorizontalScrollWithArrows> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    setState(() {});
  }

  bool get _canScroll {
    if (!_controller.hasClients) return false;
    return _controller.position.maxScrollExtent > 0;
  }

  bool get _canScrollLeft {
    if (!_canScroll) return false;
    return _controller.offset > 0;
  }

  bool get _canScrollRight {
    if (!_canScroll) return false;
    return _controller.offset < _controller.position.maxScrollExtent;
  }

  Future<void> _scrollBy(double delta) async {
    if (!_controller.hasClients) return;
    final target = (_controller.offset + delta).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    await _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arrowBg = theme.colorScheme.surface.withValues(alpha: 0.92);
    final arrowFg = theme.colorScheme.onSurface;

    final arrowPadding = widget.arrowSize + 6;
    final hasOverflow = _canScroll;
    final double leftPad = hasOverflow ? arrowPadding : 6.0;
    final double rightPad = hasOverflow ? arrowPadding : 6.0;

    return SizedBox(
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: widget.padding ?? EdgeInsets.only(left: leftPad, right: rightPad),
            child: Row(children: widget.children),
          ),
          if (_canScrollLeft)
            Positioned(
              left: 0,
              child: _ArrowButton(
                enabled: true,
                size: widget.arrowSize,
                iconSize: widget.arrowIconSize,
                background: arrowBg,
                foreground: arrowFg,
                icon: Icons.chevron_left,
                onTap: () => _scrollBy(-widget.scrollStep),
              ),
            ),
          if (_canScrollRight)
            Positioned(
              right: 0,
              child: _ArrowButton(
                enabled: true,
                size: widget.arrowSize,
                iconSize: widget.arrowIconSize,
                background: arrowBg,
                foreground: arrowFg,
                icon: Icons.chevron_right,
                onTap: () => _scrollBy(widget.scrollStep),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.enabled,
    required this.size,
    required this.iconSize,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.onTap,
  });

  final bool enabled;
  final double size;
  final double iconSize;
  final Color background;
  final Color foreground;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        elevation: 1,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Icon(icon, size: iconSize, color: foreground),
        ),
      ),
    );

    if (enabled) return child;
    return Opacity(opacity: 0.6, child: child);
  }
}
