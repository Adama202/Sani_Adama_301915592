#!/usr/bin/env bash
# collect_results.sh - gathers the REAL output of P1-P5 into my_results.txt
R=my_results.txt; D=advanced-database-portfolio; [ -d portfolio-1-database-design ] && D=.
sec(){ echo; echo "################ $1 ################"; }
{
echo "MIT 8103 results - generated $(date) on this Codespace"
sec "P1 row counts and constraint tests"
psql -d crumble -c "SELECT 'production_run' t,count(*) FROM production_run UNION ALL SELECT 'batch_usage',count(*) FROM batch_usage UNION ALL SELECT 'outlet_stock',count(*) FROM outlet_stock UNION ALL SELECT 'sale',count(*) FROM sale UNION ALL SELECT 'sale_line',count(*) FROM sale_line" 2>&1
f=portfolio-1-database-design/p1_output.log
[ -f $f ] && grep -E "^ [a-z_]+ +\| (PASSED|FAILED)" $f || echo "(no $f)"
sec "P2 EXPLAIN before/after"
cat portfolio-2-query-optimisation/explain_summary.txt 2>/dev/null || echo "(no P2 summary)"
sec "P3 race condition, deadlock, isolation demos"
cat portfolio-3-transactions-concurrency/race_demos_output.log 2>/dev/null || echo "(no race_demos_output.log)"
sec "P4 MongoDB index demo and validator tests"
f=portfolio-4-nosql/p4_output.log
[ -f $f ] && { grep -A5 "P4 INDEX SUMMARY" $f; grep -E "^(bad |good )" $f; grep -E "oven_logs    :|recipe_cards :" $f; } || echo "(no $f)"
sec "P5 partitions and replica"
f=portfolio-5-distributed-cloud/p5_output.log
[ -f $f ] && { grep -A14 "Rows per partition" $f; grep -A3 "DEFAULT partition" $f; grep -E "Execution Time|^EXPLAIN|SAME one-month" $f; } || echo "(no $f)"
cat portfolio-5-distributed-cloud/replication_output.log 2>/dev/null || echo "(no replication_output.log)"
} > $R 2>&1
echo "Wrote $R"
