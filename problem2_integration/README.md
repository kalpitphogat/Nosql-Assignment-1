# Problem 2 — Incomplete Data Integration and JSON Generation

## Files
- `match_customers.py` — the matching/classification program (stdlib only, no dependencies)
- `customer_master.csv`, `customer_incoming.csv` — supplied input data (3000 / 2000 records)
- `classification_results.csv` — one row per incoming record: assigned category + which matching rule fired
- `json_output/` — one JSON document per record classified as `partial_match`, `incomplete_match`, or `conflicting`
- `summary_statistics.txt` — record counts per category

Run with:
```bash
python3 match_customers.py
```

## Matching strategy

Records are matched against the master dataset using a **priority-ordered
chain of identifiers**, from strongest to weakest signal:

1. **`customer_id` (exact)** — the intended primary key. If the incoming
   record carries an id that exists in the master file, that master record
   is the candidate — no ambiguity possible.
2. **`email` (exact, case-insensitive)** — used only when `customer_id` is
   absent. Emails are effectively unique per person in this dataset. If more
   than one master record shares the same email (`email_ambiguous`), the
   match is deliberately *not* taken — it's classified as **Incomplete
   Match** rather than guessed.
3. **`phone` (exact, digits-only comparison)** — same logic as email, one
   rung down in reliability since phone numbers are more prone to typos
   and to being shared/reused. Same ambiguity handling.
4. **`name` + `city` (both exact, case-insensitive)** — the weakest signal,
   used only when nothing stronger is available. Names collide far more
   often than emails or ids, so this rule requires *both* fields to agree
   and still only fires if it comes back with exactly one candidate.

Priority order matters because a wrong match is worse than no match — e.g.
trusting a possibly-mistyped phone number over a correct email would
misclassify a genuine new customer as a conflicting existing one.

### Classifying once a candidate is (or isn't) found

If exactly one master candidate is found (via whichever rule fires first),
every **available** (non-empty) attribute in the incoming record — `name`,
`email`, `phone`, `address`, `city` — is compared to the candidate:

- All available attributes agree, none missing → **Complete Match**
- All available attributes agree, but ≥1 attribute is empty in the incoming
  record → **Partial Match**
- Any available attribute disagrees with the master record → **Conflicting
  Information** (checked before "missing", since a wrong value is worse
  than an absent one)

If no unique candidate is found:
- The record is empty or near-empty (no id, no name, no contact info at
  all), or the weak signals matched more than one master record
  (`*_ambiguous`) → **Incomplete Match** — there genuinely isn't enough
  reliable information to place the record anywhere.
- The record has a `customer_id`-shaped identity gap but internally
  consistent, distinguishing information (an email, a phone number, or a
  name+city pair) that matches **no** master record → **No Match / New
  Entity**.

## Why JSON for partial/incomplete/conflicting records

A flat CSV row can't represent "this field is missing" vs. "this field
disagrees with the master record" vs. "this field simply wasn't compared"
without inventing sentinel values that get confused with real data. JSON
lets each record carry:
- `available_information` — a sub-object of only the fields that *are*
  present and (if matched) agree,
- `missing_information` — a list of which fields were absent,
- `conflicting_information` — for Conflicting records, both the incoming
  and master values side by side, so a human reviewer can see exactly what
  disagreed and decide how to resolve it,

as three independently-sized, self-describing pieces — instead of forcing
every record into a fixed set of CSV columns where "missing" and "not
applicable" look identical.

## Assumptions / limitations
- Matching is deterministic and rule-based, not a fuzzy/probabilistic
  matcher (no edit-distance on names, no address normalization) — a
  misspelled name that doesn't share an id/email/phone with its true
  master record will be treated as a new entity rather than a partial
  match. This is a conscious precision-over-recall choice: we'd rather
  create a duplicate "new" customer than silently merge two different
  people.
- Phone comparison strips non-digit characters (spaces, dashes, `+91`
  prefixes would need extra normalization not present in this dataset)
  but does not attempt cross-country-code equivalence.
- "Conflicting" is checked before "missing" — a record with one wrong
  field and one missing field is classified Conflicting, not Partial,
  since the disagreement is the more serious issue to flag.
- A completely blank incoming row (all fields empty, including
  `customer_id`) is Incomplete Match, not New Entity, since there is
  nothing to distinguish it as a new customer either.

## Which records get a JSON document
JSON documents are written for `partial_match`, `incomplete_match`, and
`conflicting` records — the ones the assignment asks to preserve
(missing, irregular, or conflicting information). `complete_match` records
need no special representation (every field agrees and a flat row is
enough), and `new_entity` records are, by definition, brand-new customers
with no master counterpart to reconcile against, so they are recorded in
`classification_results.csv` rather than as reconciliation JSON. The full
classification of *every* incoming record (all five categories) is in
`classification_results.csv`; the summary counts are in
`summary_statistics.txt`.

## Difficulties encountered
- **No clean key across the datasets.** Many incoming records have a blank
  `customer_id` (or one shaped like `N…` that isn't in the master file), so
  the match can't rely on the intended primary key alone — hence the
  fall-through chain email → phone → name+city.
- **Distinguishing "missing" from "conflicting" from "just new".** The
  hardest boundary was Incomplete vs. New Entity: a record with only a name
  and nothing else could be a new customer or a fragment of an existing
  one. We resolved it conservatively (require a strong identifier or a
  name+city pair before calling something a new entity), accepting that
  some genuine new customers with sparse data are labelled Incomplete.
- **Ambiguous weak matches.** Some emails/phones/names map to more than one
  master row; rather than guess, these are routed to Incomplete
  (`*_ambiguous`) so no arbitrary match is recorded.
- **Data hygiene.** Phone numbers needed digit-only normalization and
  email/name/city needed case-folding before comparison; addresses were
  left un-normalized (free-text, no reliable canonical form), which is a
  known source of missed matches.
