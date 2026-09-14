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
- The record carries a strong identifier (a `customer_id`, email or phone)
  or a name+city pair, and none of them matches any master record →
  **No Match / New Entity**.
- Anything else (e.g. only a name, or only a city) → **Incomplete Match**.

## Results on the supplied data

`python3 match_customers.py` classifies all 2000 incoming records:

| Category | Records | % | Matched via |
|---|---|---|---|
| Complete Match | 400 | 20.0 | customer_id (400) |
| Partial Match | 657 | 32.9 | customer_id (450), name+city (91), email (77), phone (39) |
| Incomplete Match | 193 | 9.7 | no usable candidate |
| No Match / New Entity | 400 | 20.0 | no candidate |
| Conflicting Information | 350 | 17.5 | customer_id (350) |

1200 JSON documents are written to `json_output/` (every partial,
incomplete and conflicting record); the per-record table is
`classification_results.csv` (row, ids, status, and which rule fired).

### Evidence behind the rule order (measured on the master file)

- **email, phone and name+city are unique in the master file** (0 duplicate
  emails, 0 duplicate phones, 0 duplicate name+city pairs), so a hit on any
  of them identifies exactly one customer. The ambiguity branches in the
  code therefore never fire on this data, but they keep the program safe on
  other inputs.
- **Name alone is not unique**: 23 names appear more than once in the
  master file, and 8 of the 400 new-entity records (ids starting with `N`,
  whose email and phone match nobody in the master file) share a name with
  an existing master customer. That is why a record
  that has *only* a name is Incomplete rather than matched: 104 incoming
  records have only a name (100 of those names happen to be unique in the
  master file, 4 are not) and 27 have only a city.
- **62 incoming rows are completely empty**, so they are Incomplete.
- **Incoming ids are consistent**: all 1200 `C…` ids exist in the master
  file and none of the 400 `N…` ids do, so `customer_id` is safe as the
  first rule.
- **Conflicts are real value disagreements, not formatting noise**: for all
  350 conflicting records, the incoming and master values still differ
  after removing case, spaces and punctuation (e.g. email
  `ekalinga.narayanan48812@example.in` vs `ikshita.swamy1165@example.in`).
  167 records conflict on one field and 183 on two. By field: phone 124,
  name 108, address 104, city 101, email 96. So exact (case-insensitive)
  comparison is enough here, and no fuzzy matching was needed.

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

## Difficulties encountered
- **Deciding what "reliably matched" means without a ground truth.** There is
  no label telling us which incoming row belongs to which customer, so the rule
  order had to come from properties of the data itself (uniqueness of each
  attribute, shown above) rather than from accuracy against known answers.
- **Name-only records.** 100 name-only records have a name that appears once in
  the master file, so matching on name would have been easy. We still did not
  do it, because 8 of the new customers share names with existing ones. That
  shows a unique name in *this* master file does not prove it is the same
  person.
- **Partial vs conflicting when both apply.** A record with one missing field
  and one disagreeing field fits both definitions. We chose Conflicting,
  because the category must be unique and the conflict is what needs a human
  to review it.
- **Rows with no information at all.** An empty row technically "does not
  correspond to any master record", which reads like New Entity. We classify
  it as Incomplete, because creating a customer with no attributes would be
  worse than flagging it.
