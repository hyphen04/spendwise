import 'dart:convert';
import 'import_models.dart';

class JsonImporter {
  static List<ParsedRow> parse(String content) {
    dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      return [const ParsedRow(rowIndex: 0, note: '__JSON_PARSE_ERROR__')];
    }

    if (decoded is! Map<String, dynamic>) {
      return [const ParsedRow(rowIndex: 0, note: '__JSON_NOT_OBJECT__')];
    }

    final txList = decoded['transactions'];
    if (txList == null || txList is! List) {
      return [const ParsedRow(rowIndex: 0, note: '__NO_TRANSACTIONS_KEY__')];
    }

    String? toStr(dynamic value) {
      if (value == null) return null;
      final v = value.toString().trim();
      return v.isEmpty ? null : v;
    }

    final result = <ParsedRow>[];
    for (var i = 0; i < txList.length; i++) {
      final tx = txList[i];
      if (tx is! Map<String, dynamic>) continue;

      // Skip EXAMPLE rows
      final note = toStr(tx['note']) ?? '';
      if (note.toLowerCase().startsWith('example')) continue;

      result.add(ParsedRow(
        rowIndex: i + 1,
        rawDate: toStr(tx['date']),
        rawTime: toStr(tx['time']),
        title: toStr(tx['title']),
        rawAmount: toStr(tx['amount']),
        kind: toStr(tx['kind']),
        account: toStr(tx['account']),
        category: toStr(tx['category']),
        mode: toStr(tx['mode']),
        note: toStr(tx['note']),
      ));
    }
    return result;
  }
}
