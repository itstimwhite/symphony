```text
╭─ SYMPHONY STATUS
│ Agents: 1/10
│ Throughput: 15 tps
│ Runtime: 45m 0s
│ Tokens: in 18,000 | out 2,200 | total 20,200
│ Rate Limits: gpt-5 | primary 0/20,000 reset 95s | secondary 0/60 reset 45s | credits none
│ Artifact: symphony 0.0.2 · source 119f28a · build snapshot-build · built 2026-09-01T15:40:00Z · host gem
│ Project: https://linear.app/project/project/issues
│ Next refresh: n/a
├─ Running
│
│   ID         TITLE                    LIFECYCLE      AGE / TURN   TOKENS       ACTION
│   ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ ● MT-638     (untitled)               Active         20m 25s / 7        14,200 agent message streaming: waitin...
│
├─ Backoff queue
│
│  ↻ MT-450 attempt=4 in 1.250s error=rate limit exhausted
│  ↻ MT-451 attempt=2 in 3.900s error=retrying after API timeout with jitter
│  ↻ MT-452 attempt=6 in 8.100s error=worker crashed restarting cleanly
│  ↻ MT-453 attempt=1 in 11.000s error=fourth queued retry should also render after removing the top-three limit
│
├─ Blocked
│
│  No blocked tasks
│
├─ Recent landed · native merge proof
│
│  No native merges observed
╰─
```
