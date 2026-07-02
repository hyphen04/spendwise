import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app/themes/app_colors.dart';
import '../../app/widgets/screen_header.dart';
import '../../state/dues_providers.dart';
import 'sheets/add_contact_sheet.dart';
import 'sheets/add_entry_sheet.dart';

class DuesScreen extends ConsumerStatefulWidget {
  const DuesScreen({super.key});

  @override
  ConsumerState<DuesScreen> createState() => _DuesScreenState();
}

class _DuesScreenState extends ConsumerState<DuesScreen> {
  String _filter = 'all'; // 'all', 'payable', 'receivable'

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final contactsAsync = ref.watch(dueContactsStreamProvider);
    final totalPayable = ref.watch(totalPayableProvider);
    final totalReceivable = ref.watch(totalReceivableProvider);

    final appColors = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Fixed Header
            ScreenHeader(
              title: 'dues & tabs',
              subtitle: contactsAsync.valueOrNull != null
                  ? '${contactsAsync.value!.length} contact${contactsAsync.value!.length == 1 ? '' : 's'}'
                  : 'Loading...',
            ),
            
            Expanded(
              child: CustomScrollView(
                slivers: [
                  // Inline Stats
                  if (totalPayable > 0 || totalReceivable > 0)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                        child: Row(
                          children: [
                            _InlineStat(
                              arrow: '↑',
                              label: 'you get',
                              value: totalReceivable,
                              color: appColors.income,
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                              width: 1,
                              height: 14,
                              color: cs.outlineVariant,
                            ),
                            _InlineStat(
                              arrow: '↓',
                              label: 'you owe',
                              value: totalPayable,
                              color: appColors.expense,
                            ),
                            const Spacer(),
                            Text(
                              'net',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${totalReceivable >= totalPayable ? '+' : '−'}₹${NumberFormat('#,##,###').format((totalReceivable - totalPayable).abs())}',
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: totalReceivable >= totalPayable ? appColors.income : appColors.expense,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Filters
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'All',
                            isSelected: _filter == 'all',
                            onTap: () => setState(() => _filter = 'all'),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Payable',
                            isSelected: _filter == 'payable',
                            onTap: () => setState(() => _filter = 'payable'),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Receivable',
                            isSelected: _filter == 'receivable',
                            onTap: () => setState(() => _filter = 'receivable'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Contacts List
                  contactsAsync.when(
                    loading: () => const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                    error: (e, st) => SliverToBoxAdapter(
                      child: Center(child: Text('Error: $e')),
                    ),
                    data: (contacts) {
                      if (contacts.isEmpty) {
                        return SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.people_alt_outlined, size: 48, color: cs.outlineVariant),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No contacts yet',
                                    style: GoogleFonts.manrope(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Your dues contacts will appear here.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.tonalIcon(
                                    onPressed: () => showAddContactSheet(context),
                                    icon: const Icon(Icons.add_rounded),
                                    label: const Text('Add Contact'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      
                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final contact = contacts[index];
                            final balanceAsync = ref.watch(contactSummaryProvider(contact.id));
                            
                            return balanceAsync.when(
                              data: (summary) {
                                if (_filter == 'payable' && summary.balance >= 0) return const SizedBox.shrink();
                                if (_filter == 'receivable' && summary.balance <= 0) return const SizedBox.shrink();
                                
                                final balanceColor = summary.balance == 0 
                                    ? cs.onSurface 
                                    : (summary.balance < 0 ? appColors.expense : appColors.income);

                                return InkWell(
                                  onTap: () => context.push('/dues/${contact.id}'),
                                  onLongPress: () => showAddDueEntrySheet(context, prefilledContact: contact),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 46,
                                          height: 46,
                                          decoration: BoxDecoration(
                                            color: Color(int.parse(contact.color.replaceFirst('#', '0xFF'))).withValues(alpha: 0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(contact.icon, style: const TextStyle(fontSize: 22)),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                contact.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.manrope(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: cs.onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${summary.unsettledCount} pending entr${summary.unsettledCount == 1 ? 'y' : 'ies'}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.inter(
                                                  fontSize: 12, 
                                                  fontWeight: FontWeight.w400,
                                                  color: cs.onSurfaceVariant
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '₹${summary.balance.abs().toStringAsFixed(0)}',
                                              style: GoogleFonts.manrope(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                fontFeatures: const [FontFeature.tabularFigures()],
                                                color: balanceColor,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              summary.balance == 0 
                                                  ? 'Settled' 
                                                  : (summary.balance < 0 ? 'Payable' : 'Receivable'),
                                              style: GoogleFonts.inter(
                                                fontSize: 11, 
                                                fontWeight: FontWeight.w500,
                                                color: cs.onSurfaceVariant
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              loading: () => const SizedBox(height: 72, child: Center(child: CircularProgressIndicator())),
                              error: (_, __) => const SizedBox.shrink(),
                            );
                          },
                          childCount: contacts.length,
                        ),
                      );
                    },
                  ),

                  SliverToBoxAdapter(
                    child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 96),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddContactSheet(context),
        tooltip: 'Add Contact',
        child: const Icon(Icons.person_add_alt_1_rounded),
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({
    required this.arrow,
    required this.label,
    required this.value,
    required this.color,
  });
  final String arrow;
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          arrow,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '₹${NumberFormat('#,##,###').format(value)}',
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}


class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isSelected ? null : Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
