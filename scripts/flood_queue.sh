#!/usr/bin/env bash
# =============================================================================
# flood_queue_observable.sh
#
# Join-free resource-group queue demonstration with per-query logs.
# Use this instead of the silent flood scripts while testing the workshop.
# =============================================================================

set -u

COORDINATOR="presto-coordinator"
CLI="presto-cli"
LOG_DIR="query-logs-$(date +%Y%m%d-%H%M%S)"

# Start with 50. Raise to 100 only if test runs show the queue does not remain
# above 20 for five minutes. This workload has NO hash join.
QUERY="
SELECT
    l.returnflag,
    l.linestatus,
    SUM(
        sin(l.extendedprice * expansion.multiplier)
        + cos(l.discount * expansion.multiplier)
        + sqrt(l.quantity * expansion.multiplier)
    ) AS cpu_work,
    COUNT(*) AS expanded_row_count
FROM tpch.sf1.lineitem AS l
CROSS JOIN UNNEST(sequence(1, 50)) AS expansion(multiplier)
GROUP BY l.returnflag, l.linestatus
ORDER BY l.returnflag, l.linestatus
"

submit_query() {
    local user="$1"
    local query_number="$2"
    local log_file="${LOG_DIR}/${user}-${query_number}.log"

    docker exec "$COORDINATOR" "$CLI" \
        --user "$user" \
        --client-request-timeout 30m \
        --execute "$QUERY" \
        >"$log_file" 2>&1 &

    printf "Submitted %s query #%s → %s (shell PID %s)\n" \
        "$user" "$query_number" "$log_file" "$!"
}

if ! docker ps --format '{{.Names}}' | grep -qx "$COORDINATOR"; then
    printf "Error: the %s container is not running. Start the stack first.\n" "$COORDINATOR" >&2
    exit 1
fi

mkdir -p "$LOG_DIR"

cat <<INTRO
====================================================================
Observable Presto resource-group queue demonstration
====================================================================
Log directory: ${LOG_DIR}

Expected, while the initial work remains active:
  bob:  11 submitted → 4 running + 7 queued
  sam:   9 submitted → 2 running + 7 queued
  noah: 11 submitted → 4 running + 7 queued
  ------------------------------------------------
  total: 31 submitted → 10 running + 21 queued
====================================================================
INTRO

for i in $(seq 1 11); do submit_query "bob" "$i"; done
for i in $(seq 1 9);  do submit_query "sam" "$i"; done
for i in $(seq 1 11); do submit_query "noah" "$i"; done

cat <<NEXT_STEPS

Use Prometheus to observe the queue:
  sum(presto_user_resourcegroup_queuedqueries{user!~"all|global"})

If the queue count falls unexpectedly, inspect failures without losing
any evidence:
  grep -R -n -E 'failed|error|rejected|cancelled|killed' "${LOG_DIR}"

For Presto-side state, open an observer CLI:
  docker exec -it presto-coordinator presto-cli --user workshop_observer

Then run:
  SELECT user, state, COUNT(*) AS query_count
  FROM system.runtime.queries
  WHERE user IN ('bob', 'sam', 'noah')
  GROUP BY user, state
  ORDER BY user, state;

This script uses no hash JOIN, so it avoids the Java join-spill error.
NEXT_STEPS
