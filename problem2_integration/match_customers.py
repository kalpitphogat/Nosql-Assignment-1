#!/usr/bin/env python3
"""
Compares customer_incoming.csv against customer_master.csv and classifies
every incoming record into one of:
    complete_match | partial_match | incomplete_match | new_entity | conflicting

Matching strategy (see README.md for full justification):
  1. customer_id (exact) -- highest priority, since it is the intended
     primary key linking the two datasets.
  2. email (exact, case-insensitive) -- effectively unique per person in
     this dataset and rarely mistyped compared to phone/name.
  3. phone (exact, digits only) -- unique per person but more prone to
     transcription errors than email.
  4. name + city (both exact, case-insensitive) -- weakest signal, used
     only when no stronger identifier is available; ambiguous if it hits
     more than one master record.

Once a *single* candidate master record is found (via the highest-priority
rule that produces exactly one match), the available incoming attributes
are compared field-by-field against that record:
  - every available attribute agrees              -> complete_match
  - every available attribute agrees, but at least
    one attribute is empty in the incoming record -> partial_match
  - any available attribute disagrees              -> conflicting
If no rule yields a unique candidate:
  - the incoming record is entirely (or almost entirely) empty, or the
    weak signals are ambiguous/contradictory        -> incomplete_match
  - the incoming record has enough distinguishing,
    internally-consistent information but matches
    no master record at all                         -> new_entity
"""

import csv
import json
import re
from collections import defaultdict
from pathlib import Path

MASTER_FILE = "customer_master.csv"
INCOMING_FILE = "customer_incoming.csv"
JSON_DIR = Path("json_output")
CLASSIFICATION_FILE = "classification_results.csv"
SUMMARY_FILE = "summary_statistics.txt"

FIELDS = ["customer_id", "name", "email", "phone", "address", "city"]
COMPARE_FIELDS = ["name", "email", "phone", "address", "city"]


def norm(value):
    return (value or "").strip()


def norm_key(value):
    return norm(value).lower()


def norm_phone(value):
    return re.sub(r"\D", "", value or "")


def load_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def build_indexes(master_rows):
    by_id, by_email, by_phone, by_name_city = {}, defaultdict(list), defaultdict(list), defaultdict(list)
    for row in master_rows:
        cid = norm(row["customer_id"])
        if cid:
            by_id[cid] = row
        email = norm_key(row["email"])
        if email:
            by_email[email].append(row)
        phone = norm_phone(row["phone"])
        if phone:
            by_phone[phone].append(row)
        key = (norm_key(row["name"]), norm_key(row["city"]))
        if key[0] and key[1]:
            by_name_city[key].append(row)
    return by_id, by_email, by_phone, by_name_city


def find_candidate(incoming, by_id, by_email, by_phone, by_name_city):
    """Returns (master_row_or_None, rule_used_str)."""
    cid = norm(incoming["customer_id"])
    if cid and cid in by_id:
        return by_id[cid], "customer_id"

    email = norm_key(incoming["email"])
    if email and len(by_email[email]) == 1:
        return by_email[email][0], "email"
    if email and len(by_email[email]) > 1:
        return None, "email_ambiguous"

    phone = norm_phone(incoming["phone"])
    if phone and len(by_phone[phone]) == 1:
        return by_phone[phone][0], "phone"
    if phone and len(by_phone[phone]) > 1:
        return None, "phone_ambiguous"

    name = norm_key(incoming["name"])
    city = norm_key(incoming["city"])
    if name and city:
        key = (name, city)
        if len(by_name_city[key]) == 1:
            return by_name_city[key][0], "name_city"
        if len(by_name_city[key]) > 1:
            return None, "name_city_ambiguous"

    return None, "no_candidate"


def has_any_info(incoming):
    return any(norm(incoming[f]) for f in COMPARE_FIELDS) or norm(incoming["customer_id"])


def compare_to_master(incoming, master):
    """Returns (status, available, missing, conflicting_dict)."""
    available, missing, conflicts = {}, [], {}
    for field in COMPARE_FIELDS:
        inc_val = norm(incoming[field])
        mas_val = norm(master[field])
        if not inc_val:
            missing.append(field)
            continue
        if field == "phone":
            same = norm_phone(inc_val) == norm_phone(mas_val)
        else:
            same = norm_key(inc_val) == norm_key(mas_val)
        if mas_val and not same:
            conflicts[field] = {"incoming": inc_val, "master": mas_val}
        else:
            available[field] = inc_val

    if conflicts:
        status = "conflicting"
    elif missing:
        status = "partial_match"
    else:
        status = "complete_match"
    return status, available, missing, conflicts


def classify(incoming, by_id, by_email, by_phone, by_name_city):
    candidate, rule = find_candidate(incoming, by_id, by_email, by_phone, by_name_city)

    if candidate is not None:
        status, available, missing, conflicts = compare_to_master(incoming, candidate)
        return status, candidate["customer_id"], rule, available, missing, conflicts

    if not has_any_info(incoming):
        return "incomplete_match", None, rule, {}, COMPARE_FIELDS[:], {}

    if rule in ("email_ambiguous", "phone_ambiguous", "name_city_ambiguous"):
        available = {f: norm(incoming[f]) for f in COMPARE_FIELDS if norm(incoming[f])}
        missing = [f for f in COMPARE_FIELDS if not norm(incoming[f])]
        return "incomplete_match", None, rule, available, missing, {}

    has_strong_id = norm(incoming["email"]) or norm_phone(incoming["phone"]) or norm(incoming["customer_id"])
    has_name = norm(incoming["name"])
    available = {f: norm(incoming[f]) for f in COMPARE_FIELDS if norm(incoming[f])}
    missing = [f for f in COMPARE_FIELDS if not norm(incoming[f])]

    if has_strong_id or (has_name and norm(incoming["city"])):
        return "new_entity", None, rule, available, missing, {}

    return "incomplete_match", None, rule, available, missing, {}


def make_json_doc(row_num, incoming, matched_id, status, available, missing, conflicts):
    doc = {
        "source_row": row_num,
        "customer_id": norm(incoming["customer_id"]) or None,
        "matched_master_id": matched_id,
        "name": norm(incoming["name"]) or None,
        "available_information": available,
        "missing_information": missing,
        "match_status": status,
    }
    if conflicts:
        doc["conflicting_information"] = conflicts
    return doc


def main():
    master_rows = load_csv(MASTER_FILE)
    incoming_rows = load_csv(INCOMING_FILE)
    indexes = build_indexes(master_rows)

    JSON_DIR.mkdir(exist_ok=True)
    counts = defaultdict(int)
    results = []

    for i, incoming in enumerate(incoming_rows, start=2):  # row 1 is header
        status, matched_id, rule, available, missing, conflicts = classify(incoming, *indexes)
        counts[status] += 1
        results.append({
            "row": i,
            "customer_id": norm(incoming["customer_id"]),
            "name": norm(incoming["name"]),
            "matched_master_id": matched_id or "",
            "match_status": status,
            "match_rule": rule,
        })

        if status in ("partial_match", "incomplete_match", "conflicting"):
            doc = make_json_doc(i, incoming, matched_id, status, available, missing, conflicts)
            out_path = JSON_DIR / f"row_{i:04d}_{status}.json"
            with open(out_path, "w", encoding="utf-8") as jf:
                json.dump(doc, jf, indent=2)

    with open(CLASSIFICATION_FILE, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["row", "customer_id", "name", "matched_master_id", "match_status", "match_rule"])
        writer.writeheader()
        writer.writerows(results)

    total = len(incoming_rows)
    with open(SUMMARY_FILE, "w", encoding="utf-8") as f:
        f.write("Matching summary statistics\n")
        f.write("=" * 30 + "\n")
        f.write(f"Total incoming records: {total}\n\n")
        for status in ["complete_match", "partial_match", "incomplete_match", "new_entity", "conflicting"]:
            n = counts[status]
            pct = (n / total * 100) if total else 0
            f.write(f"{status:20s}: {n:5d}  ({pct:5.1f}%)\n")

    print(f"Processed {total} incoming records.")
    for status in ["complete_match", "partial_match", "incomplete_match", "new_entity", "conflicting"]:
        print(f"  {status:20s}: {counts[status]}")
    print(f"\nClassification table: {CLASSIFICATION_FILE}")
    print(f"JSON documents:       {JSON_DIR}/ ({sum(1 for _ in JSON_DIR.glob('*.json'))} files)")
    print(f"Summary stats:        {SUMMARY_FILE}")


if __name__ == "__main__":
    main()
