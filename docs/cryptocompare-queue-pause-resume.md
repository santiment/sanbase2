# Cryptocompare historical queues — pause/resume design

Why the rate-limit pause/resume around the Cryptocompare scrapers
(`open_interest`, `funding_rate`, `price` historical queues) carries extra
machinery on top of Oban's built-in `pause_queue/resume_queue`.

## The incident this design comes from

When a Cryptocompare rate limit is hit, the historical queue is paused and a
single scheduled `PauseResumeWorker` job resumes it later. In production the
exporters would occasionally stop and never recover until the pod was
restarted: the queue was paused, and the one resume that should have fired was
lost. Restarting "fixed" it only because the schedulers resume their queues on
boot.

## Why Oban's pause/resume is not enough on its own

OSS Oban's pause/resume is an **ephemeral, fire-and-forget signal — not
managed state**:

1. **No persistence.** The `paused` flag lives in the queue producer process's
   memory. A producer crash, restart, or deploy resets it to the static config,
   which for these queues is `paused: true` (they are resumed from code on boot
   only when the scheduler is enabled). Oban Pro's DynamicQueues persist queue
   state; OSS does not.
2. **No delivery guarantee.** `Oban.resume_queue/2` returns `:ok` after handing
   the signal to the notifier (Postgres LISTEN/NOTIFY). If the listening
   connection is down at that instant, the signal is silently dropped — no ack,
   no retry, no replay.
3. **No "pause for N seconds" primitive.** A timed resume has to be built from
   something. We use a scheduled Oban job, which is itself losable and raceable.
4. **Uniqueness discards are silent.** Resume jobs are unique (to avoid a
   pileup of pending resumes). `Oban.insert/2` reports a uniqueness conflict as
   a success with `conflict?: true` — without explicit handling, a pause could
   silently end up with no scheduled resume at all.

## The layers, one per gap

| Gap | Mechanism | Where |
|---|---|---|
| Lost resume signal | Resume jobs verify via `Oban.check_queue/2` that the queue actually unpaused; failure returns an error so Oban retries the job (re-sending the signal) | `Handler.resume_and_verify/1` |
| Silent uniqueness discard | Insert conflicting with an `executing` resume job (which may have already resumed *before* our pause landed) resumes the queue immediately instead of scheduling nothing | `Handler.schedule_resume_job/2` |
| Producer restart into `paused: true`, or any other unforeseen stuck-pause | Reconciliation loop: cron every 10 minutes resumes any *enabled* queue that is paused without an alive resume job | `QueueWatchdogWorker` |
| Job rows orphaned in `executing` by dead pods (incl. a resume job itself, which would otherwise look "alive" to the watchdog forever) | `Oban.Plugins.Lifeline` (`rescue_after: 90m`, above the 60m max worker timeout) | `config/scrapers_config.exs` |

Related hardening in the same change: `429` responses are handled through the
same pause path (they carry the same `X-RateLimit-*` headers as 200s;
previously they crashed with `CaseClauseError`), and the pause length is the
reset of the *exhausted* window capped at 1h — the biggest window overall
(monthly) can be weeks away.

## Invariant and failure bias

Every pause is followed by at least one alive recovery mechanism: a pending
resume job, an immediate resume, or the next watchdog tick. No code path
leaves the queue paused with nothing pending.

All ambiguous cases resolve toward **resuming**: a spurious resume costs a few
extra API calls and, if the limit is still hit, simply re-pauses; a missed
resume silently stops ingestion. Worst-case recovery: seconds (verify retry),
≤10 min (watchdog), ≤ ~90 min + one watchdog tick (orphaned executing resume
job, needs Lifeline first).

## Known limitations

- Verification and the watchdog check the **local** producer only. Fine while
  the scrapers deployment is a single pod; multiple pods running these queues
  would need per-node checks.
- The per-second rate-limit window produces 1s pauses, so pause/resume can
  churn every few seconds under sustained load. Noisy but harmless; a minimum
  pause floor would calm it.
- Oban Pro's Smart Engine (global rate limiting + persisted queue state) would
  replace essentially all of this machinery — this is the OSS-tier design.

## Debugging

Use `scripts/oban_scrapers_debug.exs` (paste into `bin/sanbase remote` on the
scrapers pod): `ObanScrapersDebug.report/1` shows queue/producer/cron/resume
state; `force_resume/1` is the manual override.
