import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db/app_database.dart';

final appDatabaseProvider = Provider<AppDatabase>(
  (_) => throw UnimplementedError('Override appDatabaseProvider in ProviderScope'),
);
