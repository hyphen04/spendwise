import 'package:flutter/material.dart';
import 'tabs/accounts_tab.dart';
import 'tabs/budgets_tab.dart';
import 'tabs/categories_tab.dart';
import 'tabs/modes_tab.dart';
import 'tabs/tags_tab.dart';

class ManageScreen extends StatefulWidget {
  const ManageScreen({super.key});

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(text: 'Accounts'),
            Tab(text: 'Categories'),
            Tab(text: 'Modes'),
            Tab(text: 'Budgets'),
            Tab(text: 'Tags'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          AccountsTab(),
          CategoriesTab(),
          ModesTab(),
          BudgetsTab(),
          TagsTab(),
        ],
      ),
    );
  }
}
