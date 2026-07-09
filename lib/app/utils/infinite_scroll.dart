import 'package:flutter/widgets.dart';

/// Lightweight client-side paging state for infinite-scroll lists.
///
/// SpendWise streams/loads the full list for a screen and slices it in Dart
/// (see `transactionRowsProvider` and the report providers). This class holds
/// the mutable "how many are visible" counter and exposes the predicates the
/// host screen needs. The screen drives it through `setState`:
///
/// ```dart
/// final _paging = PagingState();
/// // on filter / period / contact change:
/// setState(_paging.reset);
/// // to reveal the next page (scroll or button):
/// setState(_paging.loadMore);
/// ```
class PagingState {
  PagingState({this.pageSize = 20}) : visibleCount = pageSize;

  /// How many rows one load (scroll-near-bottom or button tap) reveals.
  final int pageSize;

  /// How many rows are currently rendered.
  int visibleCount;

  /// True when there are more rows to reveal.
  bool hasMore(int total) => visibleCount < total;

  /// Reveal the next page.
  void loadMore() => visibleCount += pageSize;

  /// Back to the first page. Call on filter / period / contact change so the
  /// list never keeps a stale over-count from the previous data set.
  void reset() => visibleCount = pageSize;
}

/// Detects "scrolled near the bottom" and calls [onLoadMore] once.
///
/// Wrap the scroll view in a `NotificationListener` for `ScrollNotification`
/// and call [maybeLoadMore] from `onNotification`, returning `false`.
///
/// - Only reacts to the main scroll view (`notification.depth == 0`), so nested
///   shrinkWrap lists (e.g. the contact statement's inner list) don't fire it.
/// - Only fires on [ScrollEndNotification] when the viewport has settled within
///   [triggerFraction] of `maxScrollExtent`, so it never rapid-fires mid-gesture.
/// - The host's `hasMore` guards against firing once everything is loaded.
///
/// Returns true if it triggered a load (useful for logging/tests), false
/// otherwise. Always returns `false` from the `onNotification` callback so the
/// notification keeps bubbling.
bool maybeLoadMore(
  ScrollNotification notification, {
  required bool hasMore,
  required VoidCallback onLoadMore,
  double triggerFraction = 0.85,
}) {
  if (!hasMore) return false;
  if (notification.depth != 0) return false;
  if (notification is! ScrollEndNotification) return false;
  final metrics = notification.metrics;
  if (metrics.maxScrollExtent <= 0) return false;
  if (metrics.pixels < metrics.maxScrollExtent * triggerFraction) return false;
  onLoadMore();
  return true;
}