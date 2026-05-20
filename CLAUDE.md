# Project Instructions

## Branch Policy
- **Always work on `main` branch.** Never create new branches.
- Before starting any work, ensure you are on `main`: `git checkout main && git pull origin main`
- Commit and push all changes directly to `main`.

## General
- Always ask the user for clarification before making any code changes, commits, or file modifications.

## Reference Trades

### BB+LQS SELL — Gold Standard Example
This is the benchmark for what a good BB+LQS SELL trade looks like.

| Field | Detail |
|---|---|
| Symbol | XAUUSD |
| Direction | SELL |
| Entry | 4595.69 |
| Exit | 4592.95 |
| P&L | +$2.74 (net +$2.70 after commission) |
| Duration | ~1 minute (10:08:01 → 10:09:04) |
| SL | 4592.78 |
| TP | None — trail managed exit |
| Comment | BB+LQS SELL |
| Date | 2026.05.01 |

**Why it is a good trade:**
- Price moved cleanly $2.74 in favour within 1 minute — strong momentum right after entry
- Trail captured the move without a fixed TP dragging it
- Both LQS (liquidity sweep) and BB band confluence confirmed the entry
- Tight SL relative to the move captured
