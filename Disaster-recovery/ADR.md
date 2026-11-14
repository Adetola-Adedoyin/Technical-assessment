# ADR-001: Disaster Recovery Strategy — AetherPay Multi-Region Failover

**Status:** Accepted  
**Date:** 2025  
**Regions:** Primary `us-east-1` · Secondary `us-west-2`

---

## Context

At 02:15 UTC, the primary region (`us-east-1`) experiences a severe control-plane outage with partial data-plane degradation (~40% packet loss, asymmetric network partition). Banking partner webhooks begin timing out, payment networks suspend traffic, and some transactions may remain queued in application memory. The secondary region (`us-west-2`) is a warm standby with infrastructure already provisioned via Terraform.

The recovery strategy must prevent data loss, duplicate processing, and double settlement.

---

## A. Architecture Decision

**Decision: Retain Active-Passive multi-region architecture.**

| Concern | Active-Active | Active-Passive |
|---|---|---|
| Operational complexity | High — requires distributed transaction coordination across regions at all times | Moderate — complexity is concentrated in the failover path, not steady state |
| Database consistency | Difficult — concurrent writes to two regions require conflict resolution | Simpler — single writer at all times; Aurora Global Database replicates from one primary cluster |
| Transaction safety | Risk of duplicate settlement if both regions accept the same payment | Controlled — only one region holds write ownership at any given time |
| Recovery behaviour | Graceful degradation; no hard cutover needed | Requires deliberate failover; secondary must be explicitly promoted |

Active-Passive is appropriate here because payment processing demands strict write serialisation. Allowing two regions to accept financial writes simultaneously — even briefly — creates an unacceptable risk of double settlement. The added operational complexity of Active-Active is not justified when the system can tolerate a short, controlled recovery window.

---

## B. Recovery Objectives

| Component | RPO | RTO |
|---|---|---|
| Immutable financial ledger | 0 (see note below) | — |
| Webhook deduplication / session state | Up to 5 minutes | — |
| Application services | N/A (stateless) | 15 minutes |
| Overall service recovery | — | 30 minutes |

**Important — RPO=0 for the financial ledger:**  
Aurora Global Database uses asynchronous replication with a typical lag under one second, but it does not independently guarantee zero data loss. To achieve RPO=0 for acknowledged transactions, the application must obtain a durable cross-region confirmation (e.g. a synchronous write to a quorum store or a cross-region durable log) before returning a success response to the caller. If that confirmation is unavailable, the application must **fail closed** — it must not acknowledge new financial transactions rather than risk acknowledging a write that has not yet replicated.

This is an **additional required control**, not a capability provided automatically by the existing Aurora Global Database configuration.

---

## C. Failover and Split-Brain Prevention

The most critical risk during failover is a split-brain scenario: both regions briefly believe they hold write authority and process financial transactions simultaneously, leading to duplicate settlement.

Aurora Global Database promotion and Route 53 DNS failover do **not** provide application-level split-brain protection on their own. DNS propagation is not instantaneous, and the old primary may still be reachable. An additional fencing mechanism is required.

### Required controls

1. **Single-writer model.** At any point in time, exactly one region is authorised to process financial writes. This is enforced at the application layer, not inferred from DNS or database availability.

2. **Lease-based write ownership.** A coordination service outside both application regions (e.g. a DynamoDB global table or a dedicated quorum store) holds a write-ownership lease. The lease has a TTL. The current lease holder must renew it continuously; if renewal fails, the lease expires automatically.

3. **Monotonically increasing fencing token (epoch).** Each lease grant increments a global epoch counter. The epoch is included in every financial write request.

4. **Write rejection on stale token.** The transaction-processing service rejects any write that carries an epoch lower than the current epoch. This prevents a recovered primary — which holds an old epoch — from committing writes after the secondary has taken over.

5. **Secondary acquires lease before writing.** Before the secondary region processes any financial write, it must successfully acquire the lease and receive a new, higher epoch from the coordination service. It must not begin writing based solely on Aurora promotion or DNS update.

6. **Recovered primary remains fenced.** When `us-east-1` recovers, it must not automatically resume financial writes. It must remain isolated until reconciliation is complete and it is safely reintroduced as a secondary (see Section E).

### In-memory transactions at time of failure

Transactions that were queued in application memory in the primary region at the time of the outage must **not** be assumed committed. They should be treated as unacknowledged. Recovery relies on:
- Banking partners retrying via idempotency keys.
- Durable SQS messages that were not yet deleted from the queue (these survive independently in each region).
- The financial ledger audit trail in the promoted Aurora cluster.

---

## D. First 30 Minutes: Disaster Recovery Runbook

> **Legend:** `[INSPECT]` = read-only check · `[ACTION]` = operator-approved change · `[GATE]` = do not proceed until this passes

| Time | Action | Command or verification | Expected result / decision gate |
|---|---|---|---|
| **0–2 min** | Confirm primary region is unhealthy | `aws cloudwatch get-metric-statistics --region us-east-1 ...` / check ALB target health in CloudWatch | ALB health checks failing; ECS tasks unreachable `[INSPECT]` |
| **2–4 min** | Check network connectivity to primary | `aws ec2 describe-vpc-endpoints --region us-east-1` / attempt ALB endpoint ping | Confirm control-plane degradation; do not assume full outage from DNS failure alone `[INSPECT]` |
| **4–5 min** | Verify secondary region is healthy | `aws ecs describe-clusters --clusters <SECONDARY_CLUSTER_NAME> --region us-west-2` | Secondary ECS cluster active; tasks in RUNNING or STOPPED (warm standby) state `[GATE]` |
| **5–7 min** | Expire or revoke primary lease | Invoke coordination service API to revoke `us-east-1` lease, or wait for TTL expiry | Lease for `us-east-1` confirmed expired; epoch incremented `[GATE]` |
| **7–10 min** | Secondary acquires write-ownership lease | Invoke coordination service API from `us-west-2` to claim lease | New epoch issued to `us-west-2`; confirmed in coordination store `[GATE]` — do not proceed to financial writes without this |
| **10–12 min** | Inspect Aurora Global Database replication lag | `aws rds describe-global-clusters --global-cluster-identifier <GLOBAL_CLUSTER_ID>` | Note `GlobalWriteForwardingStatus` and replication lag; assess potential data-loss window `[INSPECT]` |
| **12–15 min** | Promote secondary Aurora cluster (unplanned failover) | `aws rds failover-global-cluster --global-cluster-identifier <GLOBAL_CLUSTER_ID> --target-db-cluster-identifier <SECONDARY_CLUSTER_ARN>` | Secondary cluster transitions to writer role; primary cluster detaches `[ACTION]` |
| **15 min** | Verify secondary database is writable | `aws rds describe-db-clusters --db-cluster-identifier <SECONDARY_CLUSTER_ID> --region us-west-2` | `Status: available`, `DBClusterMembers` shows writer instance `[GATE]` |
| **15–17 min** | Scale secondary ECS service to operational target | `aws ecs update-service --cluster <SECONDARY_CLUSTER_NAME> --service <SERVICE_NAME> --desired-count <TARGET_COUNT> --region us-west-2` | ECS service scaling event initiated `[ACTION]` |
| **17–20 min** | Verify ECS tasks healthy and DB connection live | `aws ecs describe-services --cluster <SECONDARY_CLUSTER_NAME> --services <SERVICE_NAME> --region us-west-2` | Tasks in RUNNING state; application health endpoint returns 200 `[GATE]` |
| **20–22 min** | Activate Route 53 failover routing | Confirm or update Route 53 health check for `us-east-1` to UNHEALTHY; verify failover record points to secondary ALB | `aws route53 get-health-check-status --health-check-id <HEALTH_CHECK_ID>` `[ACTION]` |
| **22–25 min** | Verify DNS resolution and webhook reachability | `nslookup api.aetherpay.example` / `curl -I https://api.aetherpay.example/health` | DNS resolves to secondary ALB; health endpoint reachable from external network `[GATE]` |
| **25–27 min** | Inspect SQS queues and DLQs | `aws sqs get-queue-attributes --queue-url <SECONDARY_QUEUE_URL> --attribute-names All --region us-west-2` | Check `ApproximateNumberOfMessages` and DLQ depth; identify unprocessed events `[INSPECT]` |
| **27–29 min** | Replay eligible events; verify idempotency | Replay from durable SQS source or banking partner retry; confirm idempotency keys prevent duplicate processing | No duplicate settlements in ledger; DLQ depth stable or decreasing `[GATE]` |
| **29–30 min** | Record incident status | Document epoch at failover, replication lag at promotion time, any transactions requiring reconciliation | Incident log updated; on-call team notified |

---

## E. Recovery of the Original Primary Region (`us-east-1`)

When `us-east-1` becomes available again, **do not automatically restore it as the active writer.** The following steps are required:

1. **Keep it fenced.** The coordination service must not grant a write-ownership lease to `us-east-1`. Application services in that region must reject financial writes until explicitly cleared.

2. **Inspect its database state.** Compare the `us-east-1` Aurora cluster's last committed LSN against the promoted `us-west-2` cluster. Identify any transactions that were committed in `us-east-1` but did not replicate before the outage.

3. **Reconcile transactions.** Cross-reference the `us-east-1` ledger with `us-west-2`. Identify missing, duplicated, or conflicting events. Resolve discrepancies before either cluster is used as a source of truth.

4. **Rebuild as secondary.** Re-attach `us-east-1` to the Aurora Global Database as a read replica of the new primary (`us-west-2`). Allow replication to catch up fully before considering any routing changes.

5. **Validate before restoring traffic.** Only update Route 53 routing after the reconciliation is confirmed complete and the team has explicitly approved the switchback.

6. **Never auto-failback.** A region becoming healthy is not sufficient reason to restore it as primary. Automatic failback risks re-introducing stale state or triggering another split-brain window.

---

## F. Risks and Trade-offs

| Risk | Mitigation |
|---|---|
| Asynchronous Aurora replication lag — acknowledged transactions may not have replicated at time of failover | Require synchronous cross-region durable confirmation before acknowledging financial transactions; fail closed if unavailable |
| Independent SQS queues — messages in the primary queue do not automatically appear in the secondary | Banking partners must retry using idempotency keys; replay from durable sources after failover; DLQ monitoring alerts on unprocessed events |
| DNS propagation delay — Route 53 failover is not instantaneous; some traffic may still reach the unhealthy primary | Do not rely on DNS as the sole write-ownership signal; fencing token enforcement at the application layer is the authoritative control |
| Split-brain and duplicate settlement | Lease-based write ownership with fencing tokens (Section C); secondary must hold a valid lease before processing any financial write |
| Complexity of the independent fencing mechanism | The coordination service must itself be highly available and outside both application regions; its failure mode must be fail-closed (deny writes) not fail-open |
