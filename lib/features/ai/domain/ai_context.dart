/// The result of building an AI context payload.
///
/// - [json]: the map that gets JSON-encoded and sent to the LLM. It contains
///   only anonymized aggregations (opaque rank keys like `cat_0`); a `legend`
///   key is embedded in [json] **only** when `shareNames` is true.
/// - [legend]: the full `label → real-name` map, **always** populated
///   internally (regardless of `shareNames`). It never leaves the device — it
///   is returned to the caller so [AiGatekeeper] can restore real names in the
///   LLM's reply on-device. When `shareNames` is true, [legend] is the same
///   map that was embedded in [json]['legend'].
/// - [labelToId]: the inverse `label → real-id` map (e.g. `cat_0 → <category
///   id>`), **always** populated internally. Never leaves the device. Used by
///   the on-device tool executor to resolve labels the LLM emits back to the
///   real ids needed to run its fixed queries.
typedef AiContext =
    ({Map<String, Object?> json, Map<String, String> legend, Map<String, String> labelToId});