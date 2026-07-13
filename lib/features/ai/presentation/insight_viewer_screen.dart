import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../state/ai_providers.dart';
import '../domain/local_insight_engine.dart';
import '../services/ai_insight_polish_controller.dart';
import '../widgets/insight_status_page.dart';

/// Fullscreen, WhatsApp-status-style viewer for the locally-computed smart
/// insights. One [InsightStatusPage] per insight in a `PageView`: swipe, or
/// tap the left / right half of the screen, to move between them. A thin
/// progress bar per card sits at the top and auto-advances after ~6s — paused
/// while the user is pressing / holding the page. The header carries a close
/// button (top-right, respects the status bar via [SafeArea]), a small index
/// counter, and a raw / polished toggle when AI-polished insights are
/// available.
///
/// Privacy note: this screen only **renders** insights — it never sends
/// anything to the LLM. The polish pass that produces the "polished" list runs
/// via [aiPolishedInsightsProvider] (anonymized outbound, on-device restore);
/// this viewer just consumes its already-built state shape, unchanged.
class InsightViewerScreen extends ConsumerStatefulWidget {
  const InsightViewerScreen({super.key});

  @override
  ConsumerState<InsightViewerScreen> createState() =>
      _InsightViewerScreenState();
}

class _InsightViewerScreenState extends ConsumerState<InsightViewerScreen>
    with TickerProviderStateMixin {
  static const _cardDuration = Duration(seconds: 6);

  late final PageController _pageController;
  late final AnimationController _progress;
  int _index = 0;
  int _length = 0;
  bool _showRaw = false;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _progress = AnimationController(vsync: this, duration: _cardDuration);
    _progress.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_paused) {
        _advance();
      }
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _startProgress() {
    _progress.stop();
    _progress.value = 0;
    if (!_paused) _progress.forward();
  }

  void _advance() {
    if (_index >= _length - 1) return;
    _goTo(_index + 1);
  }

  void _goTo(int i) {
    if (i < 0 || i >= _length) return;
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    _startProgress();
  }

  /// Hold the page to pause auto-advance; release to resume from where the
  /// progress bar stopped.
  void _togglePause(bool paused) {
    if (paused == _paused) return;
    setState(() => _paused = paused);
    if (paused) {
      _progress.stop();
    } else if (_progress.status != AnimationStatus.completed) {
      _progress.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final localAsync = ref.watch(aiInsightsProvider);
    final polish = ref.watch(aiPolishedInsightsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: localAsync.when(
          loading: () => _loading(cs),
          error: (e, _) => _error(cs),
          data: (local) {
            if (local.isEmpty) return _empty(cs);

            final showingPolished = polish.polished != null && !_showRaw;
            final displayed = showingPolished ? polish.polished! : local;

            // (Re)start the progress bar whenever the visible list identity
            // changes (polish arrives, raw/polished toggle swaps the list) so
            // the bar never desyncs from the page count. Post-frame so the
            // controller is wired to the right length before it runs.
            if (displayed.length != _length) {
              _length = displayed.length;
              _index = _index.clamp(0, _length - 1);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _startProgress();
              });
            }

            return Column(
              children: [
                _header(cs, displayed.length, showingPolished, polish),
                _progressBars(cs, displayed.length),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: displayed.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, i) => _page(displayed[i]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// A status page with transparent tap-zone + hold-to-pause overlay. The
  /// overlay uses `HitTestBehavior.translucent` so vertical drags still reach
  /// the page's scrollable body, taps navigate, and a long-press pauses
  /// auto-advance.
  Widget _page(AiInsight insight) {
    final halfWidth = MediaQuery.sizeOf(context).width / 2;
    return Stack(
      children: [
        InsightStatusPage(insight: insight),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (d) => _goTo(
              d.localPosition.dx < halfWidth ? _index - 1 : _index + 1,
            ),
            onLongPressStart: (_) => _togglePause(true),
            onLongPressEnd: (_) => _togglePause(false),
          ),
        ),
      ],
    );
  }

  Widget _header(
    ColorScheme cs,
    int total,
    bool showingPolished,
    AiPolishState polish,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${_index + 1}/$total',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Spacer(),
          if (polish.polished != null)
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => setState(() => _showRaw = !_showRaw),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showRaw
                        ? Icons.auto_awesome_outlined
                        : Icons.auto_awesome_rounded,
                    size: 16,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showRaw ? 'View polished' : 'View raw',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
            onPressed: () => context.pop(),
          ),
        ],
      ),
    );
  }

  /// One segment per card: completed cards are full, the current card fills
  /// with the running progress animation, future cards are empty. Listens to
  /// the controller so it repaints as the bar advances.
  Widget _progressBars(ColorScheme cs, int total) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: List.generate(total, (i) {
              final isCurrent = i == _index;
              final isDone = i < _index;
              final fill = isDone
                  ? 1.0
                  : isCurrent
                      ? _progress.value.clamp(0.0, 1.0)
                      : 0.0;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Container(
                      height: 3,
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: fill,
                        child: Container(color: cs.onSurface),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _loading(ColorScheme cs) {
    return Center(
      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
    );
  }

  Widget _error(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Insights unavailable right now.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _empty(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No notable patterns this month yet. Keep tracking — insights '
          'appear as your data grows.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            height: 1.5,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}