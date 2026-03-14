# API Call Limit — Design & Concurrency Walkthrough

## The Problem

Every API request must be counted against a user's rate limit (e.g. 600 calls/minute
for a Pro plan). A user can make many requests concurrently — 10 processes on the
same web node might all be handling requests for the same user at the same time.

Writing to Postgres on every request would be too slow and create a bottleneck.
Instead, we batch: track usage in-memory, flush to Postgres periodically.

The challenge: how do 10 concurrent processes safely update the same in-memory
counter without losing counts, double-counting, or corrupting state?

## Background: Erlang Primitives

### ETS (Erlang Term Storage)

ETS is an in-memory key-value store built into the BEAM VM. It lives outside the
process heap, so any process can read/write to it without message passing.

```elixir
# Create a table (once, at app startup)
:ets.new(:my_table, [:set, :public, :named_table])

# Insert/overwrite a record
:ets.insert(:my_table, {"user_42", 100})

# Read a record — returns a list of matching tuples
:ets.lookup(:my_table, "user_42")
#=> [{"user_42", 100}]

# Atomically insert only if the key doesn't exist yet
:ets.insert_new(:my_table, {"user_42", 100})
#=> true (inserted) or false (key already existed)
```

Key properties:
- **Fast**: lookups and inserts are O(1), sub-microsecond.
- **Concurrent**: with `read_concurrency: true, write_concurrency: true`,
  operations on *different* keys are fully parallel.
- **Per-key atomic**: a single `insert` or `lookup` on one key is atomic.
  But a *read-then-write* sequence is NOT atomic — another process can
  change the value between your read and your write.

That last point is the core problem. If two processes both read `remaining = 5`,
both compute `5 - 1 = 4`, and both write `4` back, we lost one decrement.

### :atomics

`:atomics` is an OTP module (since OTP 21) that provides arrays of integers
with hardware-level atomic operations. Think of it as a fixed-size array of
`int64` values where operations like "subtract and return the new value" execute
as a single CPU instruction — no locks, no possibility of interleaving.

```elixir
# Create an array of 4 signed integers (all initialized to 0)
ref = :atomics.new(4, signed: true)

# Set slot 1 to 100
:atomics.put(ref, 1, 100)

# Read slot 1
:atomics.get(ref, 1)
#=> 100

# Subtract 3 from slot 1 and return the NEW value — atomically
:atomics.sub_get(ref, 1, 3)
#=> 97

# Add 500 to slot 2 — atomically
:atomics.add(ref, 2, 500)

# Compare-and-swap: only change slot 3 from 0 to 1
:atomics.compare_exchange(ref, 3, 0, 1)
#=> :ok (success — it was 0, now it's 1)

:atomics.compare_exchange(ref, 3, 0, 1)
#=> 1 (failure — it's already 1, not 0)
```

Key properties:
- **Truly atomic**: `sub_get` reads and writes in one CPU instruction. If 10
  processes all call `sub_get(ref, 1, 1)` concurrently on a value of 10,
  they'll get back 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 in some order — no value
  is returned twice, no decrement is lost.
- **No locks**: uses hardware atomic instructions (e.g. `LOCK XADD` on x86).
  No GenServer, no Mutex, no blocking.
- **compare_exchange**: the building block for lock-free coordination. "Set this
  to 1, but only if it's currently 0" — exactly one process wins.

The ref is a reference to off-heap memory. It can be stored in ETS, passed between
processes, etc. It's garbage-collected when nothing points to it.

## Architecture Overview

```
                   ┌─────────────────────────────────────────────┐
   HTTP Request    │             Web Node (one pod)              │
  ──────────────►  │                                             │
                   │  ┌─────────────────────────────────────┐   │
                   │  │     ETS table (one per node)        │   │
                   │  │                                     │   │
                   │  │  user_42 → {:active, ref, 8, ...}   │   │
                   │  │  user_99 → {:infinity}               │   │
                   │  │  1.2.3.4 → {:error, :rate_limited}  │   │
                   │  │                                     │   │
                   │  │  ref is an :atomics array:          │   │
                   │  │    [remaining=8, bytes=1200,        │   │
                   │  │     flush_lock=0, writers=0]        │   │
                   │  └─────────────────────────────────────┘   │
                   │                    │                        │
                   │          (flush when remaining ≤ 0          │
                   │           or every 60 seconds)              │
                   │                    ▼                        │
                   │  ┌─────────────────────────────────────┐   │
                   │  │  Postgres (authoritative counters)  │   │
                   │  │                                     │   │
                   │  │  api_call_limits table:              │   │
                   │  │    user_id=42, api_calls={           │   │
                   │  │      "2026-03-01...": 4500,          │   │
                   │  │      "2026-03-14T20:00:00...": 150,  │   │
                   │  │      "2026-03-14T20:05:00...": 23    │   │
                   │  │    }                                 │   │
                   │  └─────────────────────────────────────┘   │
                   └─────────────────────────────────────────────┘
```

The system has two layers:

1. **Postgres** (`api_call_limits` table): stores cumulative API call counts per
   month/hour/minute. This is the source of truth. Updated infrequently (every
   ~100 calls or ~60 seconds).

2. **ETS + atomics** (per web node): tracks usage between Postgres flushes. Each
   entity (user or IP) gets a "batch" — an atomics ref that counts down from a
   quota number. When the countdown hits zero, the batch is flushed to Postgres
   and a new batch starts.

## The Two Paths

### Fast Path: Recording an API Call (99% of requests)

When a request completes successfully, `ETS.update_usage/5` is called.
Here's what happens when 10 processes call it for the same user:

```
Process 1 ──┐
Process 2 ──┤
Process 3 ──┤     :ets.lookup(user_42)
Process 4 ──┤     → {:active, ref, quota=10, ...}
  ...       ┤
Process 10 ─┘     All 10 get the SAME ref (pointer to the same atomics array)
                  │
                  ▼
            Counters.update_usage(ref, 1, byte_size)
                  │
                  ├─ Step 1: atomics.add(ref, writers_slot, 1)   ← "I'm here"
                  ├─ Step 2: atomics.get(ref, flush_lock_slot)   ← "is anyone flushing?"
                  │          └─ If 0 (no flush):
                  │             ├─ atomics.sub_get(ref, remaining_slot, 1)  ← THE KEY OP
                  │             └─ atomics.add(ref, byte_size_slot, bytes)
                  │          └─ If 1 (flush in progress):
                  │             └─ return :flushing (retry later)
                  └─ Step 3: atomics.sub(ref, writers_slot, 1)   ← "I'm done"
```

The critical operation is `sub_get` in step 2. All 10 processes call it on the
same atomics ref. The hardware guarantees each one gets a unique decremented value:

```
Initial remaining = 10

Process A: sub_get(ref, remaining, 1) → 9
Process B: sub_get(ref, remaining, 1) → 8
Process C: sub_get(ref, remaining, 1) → 7
  ... (order is nondeterministic but values are unique) ...
Process J: sub_get(ref, remaining, 1) → 0
```

No locks. No blocking. No lost decrements. All 10 proceed in parallel.

The process that gets `0` (or negative) knows it exhausted the batch and
triggers a flush.

### Flush Path: Persisting to Postgres

When `remaining` hits zero, one process needs to:
1. Write the accumulated usage to Postgres
2. Fetch a fresh quota from Postgres
3. Replace the ETS entry with a new atomics ref

But other processes might still be in the middle of their `update_usage` call.
We need to coordinate without blocking the fast path.

#### Step 1: Acquire the flush lock (CAS)

```elixir
atomics.compare_exchange(ref, flush_lock_slot, 0, 1)
```

This is compare-and-swap: "set flush_lock to 1, but only if it's currently 0."
If 3 processes all try this simultaneously, exactly one gets `:ok` (the winner),
the others get `:contended`.

The winner proceeds with the flush. The losers back off (retry or fall back).

#### Step 2: Wait for in-flight writers to finish

The winner can't snapshot the counters yet — other processes might be between
steps 1 and 3 of the writer protocol (they've incremented `writers` but haven't
finished their `sub_get` yet).

```elixir
# Spin until writers == 0
wait_for_writers(ref)
```

This is typically instant (writers do a few atomic ops that take nanoseconds).
But we wait to be safe.

#### Why the writers_inflight counter prevents lost writes

This is the subtle part. Consider what would happen WITHOUT the writers counter:

```
Timeline WITHOUT writers_inflight:
────────────────────────────────────────────────────────────────
Process A (writer):       Process F (flusher):

  reads ETS → gets ref
                            CAS flush_lock 0→1 ✓
                            reads remaining → 5
                            api_calls_made = 10 - 5 = 5
                            writes 5 to Postgres
                            replaces ETS with new ref
  sub_get(OLD ref, 1)
  → decremented old ref
  → but old ref is gone
  → THIS WRITE IS LOST   ← BUG!
```

Process A's decrement landed on an orphaned ref that nobody will ever read.

Now with the writers counter:

```
Timeline WITH writers_inflight:
────────────────────────────────────────────────────────────────
Process A (writer):       Process F (flusher):

  writers++ (now = 1)
  reads flush_lock → 0
  sub_get(ref, 1) → 9      CAS flush_lock 0→1 ✓
  byte_size += 500          waits: writers == 1... not yet
  writers-- (now = 0)       waits: writers == 0... YES
                            reads remaining → 9
                            api_calls_made = 10 - 9 = 1
                            (Process A's write is included ✓)
                            writes 1 to Postgres
                            replaces ETS with new ref
```

The invariant: a writer increments `writers` BEFORE checking `flush_lock`.
The flusher sets `flush_lock` BEFORE checking `writers`. So:

- If the writer increments `writers` first → the flusher will see it and wait.
  The writer will complete its `sub_get`, decrement `writers`, and the flusher's
  snapshot will include the write. **No loss.**

- If the flusher sets `flush_lock` first → the writer will see `flush_lock == 1`
  and return `:flushing` without touching the counters. The writer retries on
  the new ref after the flush completes. **No loss.**

There's no third case. Atomic operations on the same slot are totally ordered,
so one of these two orderings always holds.

#### Step 3: Snapshot and persist

```elixir
%{api_calls_made: calls, acc_byte_size: bytes} = Counters.snapshot(ref, quota)
# calls = quota - remaining (how many calls were made in this batch)

ApiCallLimit.update_usage_db(entity_type, entity, calls, bytes)
# Postgres UPDATE: increment the month/hour/minute counters by `calls`
```

#### Step 4: Replace the ETS entry

```elixir
fetch_and_store_quota(entity_type, entity, entity_key, :replace)
```

This reads the fresh state from Postgres (which now includes the flushed counts),
creates a new atomics ref with a new quota, and overwrites the ETS entry.
The old ref becomes unreachable and will be garbage-collected.

## Concrete Example: 10 Concurrent Requests

Starting state: user_42 has an ETS entry with `remaining = 3, quota = 10`.
This means 7 calls have already been counted in this batch.

Important: `Counters.update_usage` returns AFTER the `after` block runs, so
`writers` is always decremented before the caller sees the result. The process
that triggers the flush is NOT counted as an in-flight writer when it flushes.

```
Time  Process  Action                                           remaining  writers
─────────────────────────────────────────────────────────────────────────────────────
 t1   P1       Counters.update_usage: writers 0→1, sub_get,      2         0
               writers 1→0, returns {:updated, 2}
 t2   P2       Counters.update_usage: writers 0→1, sub_get,      1         0
               writers 1→0, returns {:updated, 1}
 t3   P3       Counters.update_usage: writers 0→1, sub_get,      0         0
               writers 1→0, returns {:updated, 0}
               ↑ P3 has fully exited update_usage. writers is back to 0.
 t4   P3       remaining ≤ 0 → try flush. CAS 0→1 → :acquired   0         0
 t5   P3       wait_for_writers → writers=0 → :drained (instant)  0         0
               ↑ trivially 0 because P3 already unregistered at t3.
 t6   P4       Counters.update_usage: writers 0→1,               0         1→0
               sees flush_lock=1 → writers 1→0, returns :flushing
 t7   P5       same as P4 → :flushing                             0         0
 t8   P3       snapshot: api_calls_made = 10 - 0 = 10             0         0
 t9   P3       UPDATE postgres SET api_calls += 10                 0         0
 t10  P3       Fetch new quota from DB → quota=8                   -         -
 t11  P3       Replace ETS entry: {user_42, :active, NEW_ref, 8, ...}
 t12  P4       retry → reads ETS → gets NEW_ref, update_usage → 7 7         0
 t13  P5       retry → update_usage on NEW_ref → 6                6         0
 t14  P6-P10   update_usage on NEW_ref → 5, 4, 3, 2, 1            1         ...
```

Result: all 10 calls are counted. P1-P3 were counted in the old batch (flushed
to Postgres as 10 calls). P4-P10 are counted in the new batch (will be flushed
later).

P4 and P5 saw `:flushing` and retried — their calls weren't lost, just delayed
by a few milliseconds.

## Cold Start & insert_new

When the first request arrives for a user who has no ETS entry yet, we need to
fetch their quota from Postgres and create the entry. But what if 5 requests
arrive simultaneously for a new user?

```elixir
:ets.insert_new(table, record)
#=> true  (I created it)
#=> false (someone else already created it)
```

`insert_new` is atomic — exactly one process wins. The losers see
`:already_exists` and simply retry `do_update_usage`, which will now find the
entry created by the winner.

Without `insert_new`, two processes could both create entries, with the second
overwriting the first (and losing any decrements the first batch had accumulated).

## Fallback: Direct DB Update

If a writer keeps seeing `:flushing` (the flush is taking unusually long —
maybe the DB is slow), it retries up to 50 times with 5ms sleeps. If it still
can't apply its usage to the atomics ref, it falls back to writing directly
to Postgres:

```elixir
ApiCallLimit.update_usage_db(entity_type, entity, count, result_byte_size)
```

This is slow but correct. No API call's usage is ever silently dropped.

## Rate Limit Checking (get_quota)

Before executing a GraphQL request, `RequestHaltPlug` calls `ETS.get_quota/3`.
This reads the atomics counters and computes how many calls remain:

```elixir
remaining_counter = Counters.remaining(ref)
calls_used = quota - remaining_counter

# The user's plan allows 600/minute. They've used calls_used in this batch,
# plus whatever was already in Postgres when the batch started.
minute_remaining = base_minute_remaining - calls_used
```

If any window (minute/hour/month) hits zero, the response is HTTP 429 with
`x-ratelimit-remaining-*` headers.

## Summary

| Concern | Solution |
|---------|----------|
| Fast concurrent counting | `:atomics.sub_get` — hardware-atomic, lock-free |
| Batch Postgres writes | ETS entry per entity with a quota countdown |
| Flush coordination | `flush_lock` via CAS — exactly one flusher |
| No lost writes at flush boundary | `writers_inflight` counter — flusher waits for drain |
| Concurrent cold starts | `:ets.insert_new` — exactly one initializer |
| Prolonged flush contention | Retry loop, then direct DB fallback |
| Rate limit checking | Read atomics counter + base metadata from ETS |
