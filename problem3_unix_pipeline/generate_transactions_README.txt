# Transaction Data Generator

Generate TSV transaction data for the Unix Data-Processing Pipeline assignment.

## Usage

```bash
./generate_transactions --records 100000 --seed 42 > transactions_100K.tsv
./generate_transactions --records 1000000 --seed 42 > transactions_1M.tsv
```

For malformed-record testing:

```bash
./generate_transactions --records 100000 --seed 42 --malformed > transactions_malformed.tsv
```

The generator outputs:

`transaction_id    date    category    quantity    price`

with TAB separators.

The `--seed` option makes the generated dataset reproducible.
