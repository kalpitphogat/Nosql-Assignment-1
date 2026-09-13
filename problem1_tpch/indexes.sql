-- Standard primary/foreign-key indexes (not query-specific tuning) so the
-- scaling study reflects a normally-administered database rather than an
-- unindexed table scan on every join -- built AFTER bulk load (much faster
-- than maintaining indexes row-by-row during COPY) and kept identical
-- across all scale factors per the assignment's "unchanged experimental
-- environment" rule.
ALTER TABLE region   ADD PRIMARY KEY (r_regionkey);
ALTER TABLE nation   ADD PRIMARY KEY (n_nationkey);
ALTER TABLE part     ADD PRIMARY KEY (p_partkey);
ALTER TABLE supplier ADD PRIMARY KEY (s_suppkey);
ALTER TABLE customer ADD PRIMARY KEY (c_custkey);
ALTER TABLE orders   ADD PRIMARY KEY (o_orderkey);
ALTER TABLE partsupp ADD PRIMARY KEY (ps_partkey, ps_suppkey);
ALTER TABLE lineitem ADD PRIMARY KEY (l_orderkey, l_linenumber);

CREATE INDEX idx_nation_regionkey   ON nation(n_regionkey);
CREATE INDEX idx_supplier_nationkey ON supplier(s_nationkey);
CREATE INDEX idx_customer_nationkey ON customer(c_nationkey);
CREATE INDEX idx_orders_custkey     ON orders(o_custkey);
CREATE INDEX idx_partsupp_suppkey   ON partsupp(ps_suppkey);
CREATE INDEX idx_lineitem_orderkey  ON lineitem(l_orderkey);
CREATE INDEX idx_lineitem_partkey   ON lineitem(l_partkey);
CREATE INDEX idx_lineitem_suppkey   ON lineitem(l_suppkey);
CREATE INDEX idx_lineitem_shipdate  ON lineitem(l_shipdate);
CREATE INDEX idx_orders_orderdate   ON orders(o_orderdate);
