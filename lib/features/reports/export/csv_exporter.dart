import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/reports_repository.dart';

class CsvExporter {
  static Future<String> export(
      AppDatabase db, String from, String to) async {
    final repo = ReportsRepository(db);
    final rows = await repo.transactionsForExport(from: from, to: to);

    final csvRows = <List<dynamic>>[
      ['ID', 'Date', 'Title', 'Amount', 'Kind', 'Account', 'Category', 'Mode', 'Note'],
      ...rows.map((r) => [
            r.id,
            r.date.substring(0, 10),
            r.title,
            r.amount,
            r.kind,
            r.accountName,
            r.categoryName,
            r.modeName,
            r.note ?? '',
          ]),
    ];

    final csv = const ListToCsvConverter().convert(csvRows);
    final dir = await getTemporaryDirectory();
    final stamp = '${from.substring(0, 10)}_${to.substring(0, 10)}';
    final file = File('${dir.path}/spendwise_$stamp.csv');
    await file.writeAsString(csv);
    return file.path;
  }
}
