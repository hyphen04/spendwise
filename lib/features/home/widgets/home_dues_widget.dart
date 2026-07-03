import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/db/app_database.dart';
import '../../../state/dues_providers.dart';
import '../../../state/prefs_providers.dart';
import '../../../widgets/swipe_action_button.dart';

import 'package:flutter/services.dart';

class HomeDuesWidget extends ConsumerStatefulWidget {
  const HomeDuesWidget({super.key});

  @override
  ConsumerState<HomeDuesWidget> createState() => _HomeDuesWidgetState();
}

class _HomeDuesWidgetState extends ConsumerState<HomeDuesWidget> {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.9);
    _loadSavedIndex();
  }

  Future<void> _loadSavedIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt('home_dues_last_index') ?? 0;
    if (mounted) {
      setState(() {
        _currentIndex = savedIndex;
      });
    }
  }

  Future<void> _saveIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('home_dues_last_index', index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(dueContactsStreamProvider);
    
    return contactsAsync.when(
      data: (contacts) {
        if (contacts.isEmpty) return const SizedBox.shrink();

        final balances = ref.watch(allContactBalancesProvider).valueOrNull ?? {};

        // Auto jump to initial index once contacts are loaded
        if (!_isInit && _pageController.hasClients && contacts.length > _currentIndex) {
          _isInit = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pageController.hasClients) {
              _pageController.jumpToPage(_currentIndex);
            }
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'quick dues entry',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            SizedBox(
              height: 152, // Increased height to prevent clipping
              child: PageView.builder(
                clipBehavior: Clip.none,
                controller: _pageController,
                itemCount: contacts.length,
                onPageChanged: (idx) {
                  setState(() => _currentIndex = idx);
                  _saveIndex(idx);
                },
                itemBuilder: (context, index) {
                  final contact = contacts[index];
                  final balance = balances[contact.id] ?? 0.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: _DueQuickCard(
                      contact: contact, 
                      balance: balance,
                      onLogged: (amt) {
                        if (!mounted) return;
                        
                        final messages = [
                          'Cha-ching! 🎉',
                          'Money moves! 💸',
                          'Got it down! 📝',
                          'Books balanced! ⚖️',
                          'Ka-ching! 💰',
                          'Logged it! ✅',
                          'Secure the bag! 💼',
                        ];
                        final randomMessage = messages[Random().nextInt(messages.length)];
                        
                        final overlay = Overlay.of(context, rootOverlay: true);
                        late OverlayEntry entry;
                        entry = OverlayEntry(
                          builder: (context) => _AnimatedSuccessOverlay(
                            amt: amt,
                            message: randomMessage,
                          ),
                        );
                        overlay.insert(entry);
                        Future.delayed(const Duration(seconds: 2), () {
                          if (entry.mounted) {
                            entry.remove();
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _DueQuickCard extends ConsumerStatefulWidget {
  const _DueQuickCard({required this.contact, required this.balance, this.onLogged});
  final DueContact contact;
  final double balance;
  final void Function(double)? onLogged;

  @override
  ConsumerState<_DueQuickCard> createState() => _DueQuickCardState();
}

class _DueQuickCardState extends ConsumerState<_DueQuickCard> {
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _showAddDialog(bool isPayable) {
    final cs = Theme.of(context).colorScheme;
    final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
    final direction = isPayable ? 'payable' : 'receivable';

    final actionColor = isPayable 
        ? (isDark ? Colors.red.shade400 : Colors.red.shade600) 
        : (isDark ? Colors.green.shade400 : Colors.green.shade600);

    if (widget.contact.defaultAmount != null && widget.contact.defaultAmount! > 0) {
      _amountController.text = widget.contact.defaultAmount.toString();
    } else {
      _amountController.clear();
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            'Add Entry',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: actionColor),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Text(
                'Logging a new ${isPayable ? 'Payable (You Owe)' : 'Receivable (They Owe)'} for ${widget.contact.name}.',
                style: GoogleFonts.inter(color: cs.onSurfaceVariant, fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: false,
                cursorColor: actionColor,
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  floatingLabelStyle: TextStyle(color: actionColor, fontWeight: FontWeight.w600),
                  prefixText: '₹ ',
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: actionColor, width: 2),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SwipeActionButton(
                label: 'Swipe to Add',
                color: actionColor,
                enabled: true,
                onAction: () async {
                  final amt = double.tryParse(_amountController.text);
                  if (amt == null || amt <= 0) return;

                  final repo = ref.read(duesRepositoryProvider);
                  await repo.addEntry(
                    contactId: widget.contact.id,
                    amount: amt,
                    direction: direction,
                    date: DateTime.now(),
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  _amountController.clear();
                  if (widget.onLogged != null) {
                    widget.onLogged!(amt);
                  }
                },
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    
    final fmt = NumberFormat('#,##,###.##', 'en_IN');
    String balanceText = 'Settled up';
    Color balanceColor = cs.onSurfaceVariant;
    
    if (widget.balance > 0) {
      balanceText = 'They owe you ₹${fmt.format(widget.balance)}';
      balanceColor = isDark ? Colors.green.shade400 : Colors.green.shade600;
    } else if (widget.balance < 0) {
      balanceText = 'You owe them ₹${fmt.format(widget.balance.abs())}';
      balanceColor = cs.error;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8), 
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Color(int.parse(widget.contact.color.replaceFirst('#', '0xFF'))).withValues(alpha: 0.2),
                child: Text(
                  widget.contact.icon,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.contact.name,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      balanceText,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: balanceColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => _showAddDialog(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.errorContainer.withValues(alpha: 0.5),
                    foregroundColor: isDark ? Colors.red.shade300 : Colors.red.shade700,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.remove, size: 16),
                      const SizedBox(width: 4),
                      Text('I Owe', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => _showAddDialog(false),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.withValues(alpha: 0.15),
                    foregroundColor: isDark ? Colors.green.shade400 : Colors.green.shade700,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add, size: 16),
                      const SizedBox(width: 4),
                      Text('They Owe', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnimatedSuccessOverlay extends StatefulWidget {
  final double amt;
  final String message;

  const _AnimatedSuccessOverlay({
    required this.amt,
    required this.message,
  });

  @override
  State<_AnimatedSuccessOverlay> createState() => _AnimatedSuccessOverlayState();
}

class _AnimatedSuccessOverlayState extends State<_AnimatedSuccessOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bgOpacityAnimation;
  late final Animation<double> _boxScaleAnimation;
  late final Animation<double> _iconScaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _bgOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );
    
    _boxScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic)),
    );

    _iconScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.3, 1.0, curve: Curves.easeOutBack)),
    );

    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            children: [
              Positioned.fill(
                child: FadeTransition(
                  opacity: _bgOpacityAnimation,
                  child: Container(color: cs.scrim.withValues(alpha: 0.3)),
                ),
              ),
              Center(
                child: FadeTransition(
                  opacity: _bgOpacityAnimation,
                  child: ScaleTransition(
                    scale: _boxScaleAnimation,
                    child: Container(
                      width: 240,
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withValues(alpha: 0.1),
                            blurRadius: 24,
                            spreadRadius: 2,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ScaleTransition(
                            scale: _iconScaleAnimation,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.teal.withValues(alpha: 0.1),
                              ),
                              child: const Icon(Icons.check_rounded, color: Colors.teal, size: 36),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.message,
                            style: GoogleFonts.manrope(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${widget.amt.toStringAsFixed(widget.amt.truncateToDouble() == widget.amt ? 0 : 2)} logged',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
