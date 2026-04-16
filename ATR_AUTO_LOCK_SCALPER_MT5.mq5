//+------------------------------------------------------------------+
//|                    PROJECT ATR  (MT5 v2.14)                      |
//|  Converted from MT4 + all unit bugs fixed + XAUUSD optimised    |
//|                                                                  |
//|  KEY FIXES vs MT4 version:                                       |
//|  1. ATR_Min_Filter  — compared in price (was always blocking)    |
//|  2. CandleATR_Factor— range vs candleMin both in price (no /Pt) |
//|  3. SL calculation  — price ± slDist  (removed double *Point)   |
//|  4. Trailing stop   — profit & step in price (no unit mismatch) |
//|  5. Entry signal    — bar 1 (completed candle, not live bar 0)  |
//|  6. OnInit log      — shows actual MomentumMode value           |
//|  7. ExpireHours     — reduced 2.0 → 0.5 to cap large losses     |
//|  8. CooldownMinutes — increased 3 → 5                           |
//|  9. CandleATR_Factor— default 200 → 1.5 (sensible multiplier)  |
//| 10. IsNewBar()      — entry checked once per bar, not every tick |
//| 11. SGT auto-detect — TimeGMT()+8h, no manual offset needed     |
//| 12. ADX auto-detect — H1 ADX decides Momentum vs Reversal mode  |
//| 13. DI direction    — Momentum BUY only when +DI>-DI, SELL only |
//|                        when -DI>+DI (prevents buying downtrend)  |
//| 14. ADX=0 guard     — skip entry if ADX data not loaded yet     |
//| 15. M1 counter-trend guard — block SELL when M1 ADX>25 & M1     |
//|      +DI>-DI (strong M1 rally); block BUY when M1 -DI>+DI      |
//|      Prevents selling into a strong M1 bounce                   |
//| 16. Dual-bar M1 guard (v2.6) — guard checks BOTH bar 1          |
//|      (last completed) AND bar 0 (current real-time) DI values.  |
//|      Catches fast-starting M1 rallies that lag in bar-1 DI.     |
//|      Bar-0 DI still requires M1 ADX>=threshold to filter noise. |
//| 17. M1 Ranging SL boost (v2.7) — when M1 ADX < threshold        |
//|      (default 15), SL widens to SL_ATR_Ranging_Mult (2.0×ATR). |
//|      Survives M1 noise before H1 trend takes hold.              |
//| 18. M1 DI spread filter (v2.8) — block SELL if M1 +DI exceeds  |
//|      -DI by >= M1_DI_Spread_Filter regardless of M1 ADX level.  |
//|      Catches clear M1 bullish bias the ADX-gated guard misses.  |
//|      Surgical: blocks late bounce entries, keeps early wins.     |
//| 19. M1 DI convergence filter (v2.9) — block entry if M1 DI gap  |
//|      is too small even in the correct direction. Catches "re-    |
//|      entry after win" where price bounced and M1 momentum        |
//|      exhausted — -DI barely > +DI means weak bearish conviction. |
//|      On 9 Apr: 4/5 losses came from re-entries with converging  |
//|      DI after a winning trade. Gap < M1_DI_Min_Gap → skip.      |
//| 20. Raised M1_DI_Min_Gap 3.0 → 5.0 (v2.10) — 10 Apr 04:51      |
//|      SELL at 4762.26 passed v2.9 with fresh DI flip gap ~3-4 pt  |
//|      after strong bullish run. 5.0 threshold requires more       |
//|      established M1 directional conviction before entry.         |
//| 21. Extended session end 1700 → 2000 SGT (v2.10)                |
//| 22. M1 dual-bar guard extended to REV mode (v2.11) — REV had     |
//|      zero M1 filters; REV SELL into strong M1 bull trend caused  |
//|      -$4.89 on 10 Apr 05:33. Guard now blocks REV trades that    |
//|      conflict with strong M1 momentum, same as MOM mode.         |
//| 23. H1 DI direction filter for REV mode (v2.12) — REV SELL only  |
//|      when H1 -DI > +DI (H1 leans bearish); REV BUY only when H1  |
//|      +DI > -DI (H1 leans bullish). REV SELLs into bullish H1     |
//|      recovery caused -$2.88, -$2.34, -$1.63 on 10 Apr. Filter   |
//|      blocks all 3 losses (+$6.85 saved, -$0.56 missed win).      |
//| 24. H1 DI minimum gap for REV mode (v2.13) — REV direction must  |
//|      exceed opposite DI by >= H1_REV_DI_Min_Gap (default 3.0).   |
//|      Mirrors MOM convergence filter but applied to H1 DI for REV.|
//|      Weak H1 conviction (-DI barely > +DI) = poor REV SELL basis.|
//|      10 Apr 08:31 REV SELL: H1 gap only 2.14 pts → now blocked.  |
//|      Surgical: winning REV trades have clear H1 DI bias.          |
//| 25. M1 DI direction guard replaces ADX-gated guard for REV mode  |
//|      (v2.14) — root cause of 06:31/08:31/10:04 losses: M1 was    |
//|      bullish (+DI>-DI) but ADX<25 so v2.11 guard silently passed.|
//|      ADX lags — rally starts before ADX climbs to 25. DI direction|
//|      is immediately meaningful at ANY ADX level. Fix: block REV   |
//|      SELL if M1 +DI>-DI, block REV BUY if M1 -DI>+DI, no ADX    |
//|      gate. REV only fires when M1 DI agrees with fade direction.  |
//| 26. M1 DI minimum gap for REV mode (v2.15) — v2.14 checks M1 DI  |
//|      direction but not conviction strength. At 18:25 M1 +DI=20.44 |
//|      vs -DI=19.90 (gap=0.54) — barely bullish, crossover imminent.|
//|      Trade fired as REV BUY at 18:26 then price dropped. Fix:     |
//|      require M1 DI gap >= M1_REV_DI_Min_Gap in fade direction.    |
//|      REV SELL: M1 -DI must exceed +DI by >= gap (M1 bearish conv) |
//|      REV BUY:  M1 +DI must exceed -DI by >= gap (M1 bullish conv) |
//|      18:25 gap=0.54 < 2.0 → blocked. Mirrors H1_REV_DI_Min_Gap.  |
//| 27. M1 ADX minimum + DI max gap for REV mode (v2.16) — two new    |
//|      quality filters for REV entries, identified from 3 REV BUYs: |
//|      A) M1_REV_ADX_Min (default 22): if M1 ADX too low, DI lines  |
//|         oscillate randomly — not a reliable directional signal.    |
//|         13 Apr 05:33 REV BUY: M1 ADX=18 → DI flip every 1-2 bars  |
//|         → loss. ADX<22 means M1 is choppy; DI is noise.           |
//|      B) M1_REV_DI_Max_Gap (default 25): if M1 DI gap is extreme,  |
//|         the strong trend is near exhaustion and about to reverse.   |
//|         13 Apr 10:04 REV BUY: M1 gap=36 (peak) → reversed → loss. |
//|         13 Apr 06:37 REV BUY: M1 ADX=34, gap=5.53 → won ✓        |
//|         Sweet spot: M1 trending (ADX≥22) but not extreme (gap≤25) |
//| 28. MOM counter-trend guard ADX gate removed (v2.17) — guard used  |
//|      g_M1ADX >= ADX_Trend_Level (25) before checking DI direction. |
//|      14 Apr 07:27 and 07:49 MOM BUY losses: M1 -DI already > +DI  |
//|      (bearish) but M1 ADX < 25 so guard silently passed. Same root |
//|      cause as v2.14 (REV mode). Fix: check M1 DI direction at ANY  |
//|      ADX level — no gate. Verified: all 5 Apr 14 winning signal    |
//|      bars had M1 +DI > -DI; zero winners blocked by this change.   |
//| 29. M1_Ranging_Threshold raised 15 → 25 (v2.18) — threshold of 15  |
//|      only widened SL when M1 was very choppy (ADX<15). Evidence:    |
//|      14 Apr 11:07 (ADX=20.86) and 11:12 (ADX=21.83) MOM BUY losses |
//|      used 1.5×ATR SL and were stopped by M1 pullback within strong  |
//|      H1 trend; price reversed up immediately after. With 2.0×ATR:   |
//|      11:07 SL=4777.74 vs low=4778.65 → survives; 11:12 SL=4775.66  |
//|      vs low=4776.53 → survives. Conceptually cleaner: M1 ADX < 25  |
//|      (unconfirmed trend) → wider SL; M1 ADX ≥ 25 (confirmed) →     |
//|      normal SL. Threshold now aligned with ADX_Trend_Level.         |
//| 30. H1 DI minimum gap for MOM mode (v2.19) — MOM had no minimum H1  |
//|      DI gap requirement. REV got this in v2.13; MOM was missed.     |
//|      14 Apr 12:57 MOM BUY: H1 +DI=15.73 vs -DI=14.62 (gap=1.11)   |
//|      → loss -$4.19. 13:20 MOM BUY: H1 +DI=13.63 vs -DI=12.67      |
//|      (gap=0.96) → loss -$4.23. H1 technically bullish but DI lines  |
//|      near-equal = trend nearly exhausted. Both losses hit the wide   |
//|      2×ATR SL (v2.18) confirming it is a direction quality problem, |
//|      not an SL width problem. Fix: require H1 DI gap ≥ 3.0 for MOM.|
//|      gap=1.11 < 3.0 → blocked; gap=0.96 < 3.0 → blocked. Early-   |
//|      morning winners (03:xx–05:xx) had H1 gaps > 10 → unaffected.  |
//| 31. M1 ADX minimum for MOM mode (v2.20) — MOM had no M1 ADX floor.  |
//|      REV got M1_REV_ADX_Min in v2.16; MOM was missed. When M1 ADX  |
//|      is too low, DI lines oscillate randomly — direction is noise.  |
//|      15 Apr 01:03 MOM BUY: M1 ADX=14.24 → DI flipped every 1-2    |
//|      bars across 01:00-01:10 window (BULL→BEAR→BULL→BEAR×5) →      |
//|      trade lost -$3.93. Fix: block MOM entry if M1 ADX < 20.0.     |
//|      ADX=14.24 < 20 → blocked. Apr 14 winners: M1 ADX 30-50+ →    |
//|      unaffected. Mirrors M1_REV_ADX_Min (v2.16) for MOM mode.      |
//| 32. H1 ADX slope filter for MOM mode (v2.21) — bearish-day pattern: |
//|      price pushed up briefly, fired MOM BUY, then sharp drop. Root  |
//|      cause: H1 ADX was declining (momentum weakening) even though   |
//|      ADX still ≥ 25. Diagnostic confirmed: both Apr 15 losses had   |
//|      declining H1 ADX; both Apr 14 winners had rising H1 ADX.      |
//|      Fix: require H1 ADX bar-1 > H1 ADX bar-2 for MOM entry.       |
//|      15 Apr 02:07 BUY: H1 ADX 44.08→43.11 (↓0.97) → -$2.50 →     |
//|        blocked ✓. 15 Apr 05:08 BUY: 37.08→34.69 (↓2.39) → -$3.55 |
//|        → blocked ✓. 14 Apr 11:07/11:12 winners: 43.26→44.05 (↑)  |
//|        → both pass unaffected ✓. H4 filter ruled out (H4 was BULL  |
//|        throughout). Slope check is minimal overhead: one extra       |
//|        CopyBuffer(shift=2) on the existing ADX handle.              |
//| 33. H4 direction alignment for MOM mode (v2.22) — MOM trade that  |
//|      opposes the H4 trend is counter-trend on the next TF up.     |
//|      H1 bearish while H4 still bullish = H1 correcting inside     |
//|      H4 uptrend → MOM SELL here is a counter-trend trade, not a   |
//|      genuine downtrend signal. High risk of SL hit on H4 bounce.  |
//|      15 Apr 11:11 MOM SELL: H4 +DI=29.70 > -DI=12.48 (H4 BULL)  |
//|      → sold into H4 uptrend correction → SL hit → -$3.85.        |
//|      Fix: MOM BUY requires H4 +DI > -DI; MOM SELL requires        |
//|      H4 -DI > +DI. Skip if H4 direction opposes trade.           |
//|      15 Apr 11:28 MOM SELL winner also blocked (same H4 bar):     |
//|      net +$3.85 saved − $1.20 missed = +$2.65. Worth applying.   |
//|      Apr 14 MOM BUY winners: H4 BULL → all pass unaffected ✓     |
//| 37. LQS DI filter bar[2] context (v2.26) — the LQS sweep bar     |
//|      closes AGAINST the dominant trend (BUY sweep closes UP),    |
//|      temporarily inflating +DI / suppressing -DI on bar[1].      |
//|      This makes the spread drop below threshold → filter passes  |
//|      → bad trade into an established downtrend.                  |
//|      Fix: also check bar[2] (pre-sweep). If EITHER bar[1] or     |
//|      bar[2] shows spread >= threshold, block the trade.          |
//|      16 Apr 08:52 LQS BUY: 48-bar M1 downtrend, sweep bounce    |
//|      pushed bar[1] spread < 15 → entered → SL hit → -$4.31.     |
//|      Bar[2] spread would have blocked it correctly.              |
//| 36. LQS M1 DI spread filter (v2.25) — block LQS SELL when M1 is  |
//|      strongly bullish (+DI >> -DI), block LQS BUY when M1 is    |
//|      strongly bearish (-DI >> +DI). A sweep-rejection signal     |
//|      fired against a dominant M1 trend rarely holds: the trend  |
//|      overwhelms the structural level and reverses back through.  |
//|      16 Apr 07:39 LQS SELL: M1 ADX=41.75, +DI=29.01 vs -DI=7.36 |
//|      (spread=21.65) — strongly bullish M1. Price resumed up and  |
//|      hit SL → -$1.64. Threshold 15.0 blocks spread=21.65.       |
//|      Mirrors M1_DI_Spread_Filter used by MOM/REV, applied to LQS.|
//|      Set 0.0 to disable. Default 15.0 (higher than MOM/REV 8.0  |
//|      since LQS sweeps can occur in mild trends; only extreme     |
//|      one-sided M1 should be blocked).                            |
//| 35. ATR_Max_Filter (v2.24) — skip entry when M1 ATR exceeds a    |
//|      maximum threshold. During extreme volatility events (e.g.    |
//|      Apr 2 tariff crash) ATR hit $11–$17, producing SL distances  |
//|      of $17–$34 per 0.01 lot — far beyond normal scalper sizing.  |
//|      Apr 1–9 v2.23 backtest: nearly all outsized losses occurred  |
//|      when ATR > $8. Blocking entry during extreme ATR prevents    |
//|      the disproportionate SL losses that dominate the drawdown.  |
//|      The trailing stop and entry filters cannot compensate for a  |
//|      $29 SL distance on a $0.01/lot scalper — only skipping the  |
//|      trade avoids it. Pairs with ATR_Min_Filter (both act on ATR).|
//|      Default 8.0 for XAUUSD M1. Set 0.0 to disable (off).       |
//| 34. Liquidity Sweep mode (v2.23) — independent third signal that  |
//|      fires when a M1 bar pokes above the N-bar swing high         |
//|      (sweeping buy-side stops) then closes back below it → SELL.  |
//|      Or pokes below the N-bar swing low, closes back above → BUY.|
//|      Fires in ANY market condition — no ADX/DI dependency.        |
//|      Catches "push up then sharp drop" patterns that MOM/REV miss.|
//|      Runs as a separate signal block after MOM/REV; the shared    |
//|      cooldown and position count prevent double entries.          |
//|      Three controls: Enable_LQS (on/off), LQS_Lookback (N bars   |
//|      to define the swing), LQS_Wick_Min_ATR (min poke size×ATR). |
//+------------------------------------------------------------------+
#property copyright "Project ATR"
#property version   "2.260"
#property description "Project ATR | M1 Scalper | ADX Auto Mode | Auto SL/TP/Trailing | Auto SGT | XAUUSD"

#include <Trade\Trade.mqh>

CTrade trade;

//===================================================================
//  INPUT GROUPS
//===================================================================

input group "=== Trade ==="
input double LotSize             = 0.01;   // Lot size
input int    MagicNumber         = 6666;   // EA identifier
input double ExpireHours         = 0.5;    // Force-close after N hours
input int    CooldownMinutes     = 5;      // Min gap between entries (minutes)

input group "=== ATR Settings ==="
input int    ATR_Period          = 14;     // ATR period (M1 bars)
input double ATR_Min_Filter      = 1.0;
// Minimum ATR in PRICE to allow trading.
// XAUUSD M1 typical ATR: 2.0–3.5. Set 1.5 to skip low-vol periods.

input double ATR_Max_Filter      = 8.0;
// Maximum ATR in PRICE to allow trading (0 = disabled).
// Blocks entry when volatility is extreme — e.g. tariff crash (Apr 2
// 2026) pushed M1 ATR to $11–$17, producing SL distances of $17–$34
// per 0.01 lot. Nearly all outsized losses in the Apr 1–9 backtest
// occurred when ATR exceeded $8. Skipping entry above this threshold
// prevents disproportionate losses that trailing stop cannot recover.
// XAUUSD M1 normal range: $2–$5. Crash spikes reach $10+.
// Set 0.0 to disable (trade at any ATR). Recommended: 8.0.

input double CandleATR_Factor    = 1.5;
// Candle range (high-low) must be >= N × ATR.
// Filters small/indecision candles. 1.0–2.0 recommended.

input double SL_ATR_Factor       = 1.5;
// Stop loss = N × ATR from entry price (dollars for XAUUSD).
// Used when M1 ADX >= M1_Ranging_Threshold (M1 is trending).
// e.g. 1.5 × $2.90 ATR = $4.35 SL per 0.01 lot.

input double SL_ATR_Ranging_Mult = 2.0;
// Wider SL multiplier when M1 ADX < M1_Ranging_Threshold (choppy M1).
// In a ranging M1, normal SL gets clipped by noise even when H1
// direction is correct. Wider SL survives the chop until H1 takes hold.
// e.g. 2.0 × $2.90 ATR = $5.80 SL per 0.01 lot.

input double M1_Ranging_Threshold = 25.0;
// M1 ADX below this → use SL_ATR_Ranging_Mult (wider SL).
// M1 ADX above this → use SL_ATR_Factor (normal SL).
// Raised 15 → 25 in v2.18: M1 ADX 15–24 (building momentum, not yet
// confirmed trend) still sees deep pullbacks within strong H1 trends.
// 14 Apr 11:07 (ADX=20.86) and 11:12 (ADX=21.83): 1.5×ATR SL stopped
// out; 2.0×ATR would have survived both. Now aligned with ADX_Trend_Level:
// M1 ADX < 25 = unconfirmed → wider; M1 ADX ≥ 25 = trending → normal.

input double M1_DI_Spread_Filter = 8.0;
// Block SELL if M1 +DI exceeds -DI by >= this value (any M1 ADX level).
// Block BUY  if M1 -DI exceeds +DI by >= this value (any M1 ADX level).
// Catches clear M1 directional bias that ADX-gated guard (fix 15/16)
// misses when M1 ADX < 25. Surgical — only blocks when M1 DI strongly
// disagrees with trade direction (e.g. +DI=24 vs -DI=14 → spread 10 ≥ 8).
// Set 0 to disable. Recommended: 8.0.

input double M1_DI_Min_Gap = 5.0;
// Block entry if M1 DI gap in the CORRECT direction is too small.
// For SELL: block if M1 -DI > +DI but (-DI - +DI) < this value.
// For BUY:  block if M1 +DI > -DI but (+DI - -DI) < this value.
// Catches "re-entry after win" trades where price bounced and M1
// bearish/bullish momentum has exhausted — DI lines converging near
// equal means weak directional conviction despite correct direction.
// Analysis of 9 Apr: 4/5 losses were re-entries within 14 min of a
// previous win, all with converging M1 DI. Winners had larger gaps.
// Raised 3.0 → 5.0 in v2.10: fresh DI flip after strong counter-run
// typically shows gap 3-4 pt — passes 3.0 but momentum not yet set.
// 5.0 requires established M1 directional conviction.
// Set 0 to disable. Recommended: 5.0.

input double M1_MOM_ADX_Min = 20.0;
// MOM mode only: minimum M1 ADX required before entry.
// When M1 ADX is too low, DI lines flip randomly bar-to-bar — any
// "direction" shown is noise, not a real signal, even when H1 is
// trending strongly. Mirrors M1_REV_ADX_Min (v2.16) for MOM mode.
// 15 Apr 01:03 MOM BUY: M1 ADX=14.24 → DI flipped every 1-2 bars
// throughout 01:00-01:10 window → trade lost -$3.93.
// Apr 14 winning signal bars had M1 ADX 30-50+ → unaffected.
// Set 0 to disable. Recommended: 20.0.

input double H1_MOM_DI_Min_Gap = 3.0;
// MOM mode only: minimum H1 DI gap required in the trade direction.
// For MOM BUY:  H1 +DI must exceed -DI by at least this value.
// For MOM SELL: H1 -DI must exceed +DI by at least this value.
// When H1 DI lines are nearly equal the H1 trend is near exhaustion
// — entering MOM direction chases a fading move with little cushion.
// 14 Apr 12:57 MOM BUY: H1 gap=1.11 pts → loss -$4.19.
// 14 Apr 13:20 MOM BUY: H1 gap=0.96 pts → loss -$4.23.
// Both blocked by 3.0 threshold. Mirrors H1_REV_DI_Min_Gap (v2.13).
// Set 0 to disable. Recommended: 3.0.

input bool H1_MOM_ADX_Rising = true;
// MOM mode only: require H1 ADX to be rising bar-to-bar (current
// completed H1 bar ADX > previous completed H1 bar ADX).
// A declining H1 ADX means the H1 trend is weakening even if ADX is
// still above 25 — the "push up then sharp drop" bull-trap pattern.
// Verified against Apr 14 data before implementing:
// 15 Apr 02:07 BUY: H1 ADX 44.08→43.11 (↓0.97) → loss -$2.50  BLOCKED ✓
// 15 Apr 05:08 BUY: H1 ADX 37.08→34.69 (↓2.39) → loss -$3.55  BLOCKED ✓
// 14 Apr 11:07 BUY: H1 ADX 43.26→44.05 (↑0.79) → winner        PASSES ✓
// 14 Apr 11:12 BUY: H1 ADX 43.26→44.05 (↑0.79) → winner        PASSES ✓
// Set false to disable. Recommended: true.

input bool H4_MOM_Align = true;
// MOM mode only: require H4 ADX direction to match the trade direction.
// For MOM BUY:  H4 +DI must exceed -DI (H4 trending bullish).
// For MOM SELL: H4 -DI must exceed +DI (H4 trending bearish).
// A MOM SELL when H4 is still bullish = counter-trend trade on H4.
// H1 bearish while H4 bull = correction inside a larger uptrend.
// 15 Apr 11:11 MOM SELL: H4 +DI=29.70 > -DI=12.48 → loss -$3.85.
// 15 Apr 11:28 MOM SELL winner also blocked; net +$2.65 saved.
// Apr 14 MOM BUY winners (H4 BULL, trade BUY) → all pass ✓.
// Set false to disable. Recommended: true.

input group "=== Liquidity Sweep Mode ==="
input bool   Enable_LQS       = true;
// Fires when bar 1 pokes above the N-bar swing high (sweeping buy-side
// stops) then closes back below it → SELL entry. Or pokes below the
// N-bar swing low then closes back above → BUY entry.
// Independent signal — no ADX/DI required. Works in ranging AND
// trending markets. Catches "push up then sharp drop" traps that
// MOM/REV miss. Runs after MOM/REV; shared cooldown + position count
// prevent double entries on the same bar.
// Set false to disable. Recommended: true.

input int    LQS_Lookback     = 20;
// Bars back (excluding bar 1) used to define the swing high/low.
// e.g. 20 = highest high and lowest low of completed bars 2..21.
// Smaller = more frequent signals (shorter-term structure).
// Larger  = only fires on significant structural level breaks.
// Recommended: 20.

input double LQS_Wick_Min_ATR = 0.3;
// Minimum poke distance above/below the swing level (× ATR).
// The wick breaching the level must be at least this large.
// Filters noise wicks that barely graze the swing level.
// e.g. 0.3 × $2.50 ATR = $0.75 minimum poke required.
// Set 0.0 to allow any-size poke. Recommended: 0.3.

input double LQS_DI_Spread_Filter = 15.0;
// Block LQS SELL when M1 +DI exceeds -DI by >= this value (M1 strongly
// bullish). Block LQS BUY when M1 -DI exceeds +DI by >= this value
// (M1 strongly bearish). A sweep reversal against a dominant M1 trend
// rarely holds: the trend overwhelms the level and reverses through.
// 16 Apr 07:39 LQS SELL: M1 +DI=29.01 vs -DI=7.36 (spread=21.65) —
// strongly bullish. Price continued up, SL hit → -$1.64.
// Set 15.0 to block spread ≥ 15 (only extreme one-sided M1 blocked).
// Mirrors M1_DI_Spread_Filter for MOM/REV but higher threshold since
// LQS sweeps can legitimately occur in mild trends.
// Set 0.0 to disable. Recommended: 15.0.

input double H1_REV_DI_Min_Gap = 3.0;
// REV mode only: minimum H1 DI gap required in the trade direction.
// For REV SELL: H1 -DI must exceed +DI by at least this value.
// For REV BUY:  H1 +DI must exceed -DI by at least this value.
// Mirrors the MOM convergence filter (M1_DI_Min_Gap) but applied to H1.
// A narrow H1 DI gap means weak H1 directional conviction — fading a
// candle when H1 barely leans one way risks a whipsaw reversal.
// 10 Apr 08:31 REV SELL: H1 gap = 2.14 pts (−DI 16.73 vs +DI 14.59)
// — below 3.0, so this filter would have blocked the -$2.64 loss.
// Set 0 to disable. Recommended: 3.0.

input double M1_REV_DI_Min_Gap = 2.0;
// REV mode only: minimum M1 DI gap required in the fade direction.
// For REV SELL: M1 -DI must exceed +DI by at least this value.
// For REV BUY:  M1 +DI must exceed -DI by at least this value.
// Complements v2.14 direction guard: when DI is correct but the gap is
// tiny, the crossover just happened and M1 momentum hasn't built yet.
// 10 Apr 18:26 REV BUY: M1 +DI=20.44 vs -DI=19.90 → gap=0.54 — passes
// v2.14 direction check but barely; price dropped after entry (-$3.73).
// Gap of 2.0 would block any near-crossover entry.
// Set 0 to disable. Recommended: 2.0.

input double M1_REV_ADX_Min = 22.0;
// REV mode only: minimum M1 ADX required before entry.
// When M1 ADX is too low (near ranging), the DI lines oscillate randomly
// — any "direction" shown is noise, not real conviction.
// 13 Apr 05:33 REV BUY: M1 ADX=18.02 → DI flipped every 1-2 bars → loss.
// 13 Apr 06:37 REV BUY: M1 ADX=34.20 → stable DI → won.
// Set 0 to disable. Recommended: 22.0.

input double M1_REV_DI_Max_Gap = 25.0;
// REV mode only: maximum M1 DI gap allowed in the fade direction.
// When M1 gap is extreme (+DI far above -DI), the strong trend is likely
// near peak/exhaustion — fading a pullback at peak momentum risks a sharp
// reversal against the trade as momentum collapses.
// 13 Apr 10:04 REV BUY: M1 gap=36.02 (peak) → reversed immediately → loss.
// 13 Apr 06:37 REV BUY: M1 gap=5.53 (moderate) → won cleanly.
// Set 0 to disable. Recommended: 25.0.

input double TP_ATR_Factor       = 0.0;
// Take profit = N × ATR (0 = disabled → trailing stop only).
// Suggested: 2.0–3.0 for fixed TP.

input double TSstart_ATR_Factor  = 0.8;
// Begin trailing after N × ATR profit.
// e.g. 0.8 × $2.50 = $2.00 profit before trailing activates.

input double TSstep_ATR_Factor   = 0.4;
// Trail SL N × ATR behind current price.
// e.g. 0.4 × $2.50 = $1.00 trail step.

input group "=== Mode Detection ==="
input bool             AutoModeDetect  = true;
// true  = EA auto-selects Momentum/Reversal using H1 ADX (recommended)
// false = use manual MomentumMode input below

input bool             MomentumMode    = false;
// Only used when AutoModeDetect = false.
// false = REVERSAL  → BUY red candle  / SELL green candle
// true  = MOMENTUM  → BUY green candle / SELL red candle

input int              ADX_Period      = 14;
// ADX period on the higher timeframe chart.

input ENUM_TIMEFRAMES  ADX_TimeFrame   = PERIOD_H1;
// Timeframe for ADX trend detection. H1 recommended for M1 scalping.

input double           ADX_Trend_Level = 25.0;
// ADX >= this value → TRENDING → Momentum mode
// ADX <  this value → RANGING  → Reversal mode
// Standard: 20 = weak trend, 25 = trend, 40 = strong trend

input group "=== Session Filter (Singapore Time — auto-detected) ==="
input bool   EnableSessionFilter = true;
input int    SG_Start            = 6;     // Session open  (SGT hour, 24h)
input int    SG_End              = 20;    // Session close (SGT hour, 24h)
// SGT = UTC+8. Broker GMT offset is auto-detected via TimeGMT().
// No manual offset entry needed — works on any broker.

//===================================================================
//  GLOBALS
//===================================================================
datetime LastEntry   = 0;
double   TodayProfit = 0.0;
int      TodayDate   = 0;
int      ATR_Handle   = INVALID_HANDLE;
int      ADX_Handle   = INVALID_HANDLE;   // H1 ADX
int      M1ADX_Handle = INVALID_HANDLE;   // M1 ADX (counter-trend guard)
int      H4ADX_Handle = INVALID_HANDLE;   // H4 ADX (direction alignment v2.22)
datetime LastBarTime  = 0;

// ── Tick-level cache (set once at top of OnTick) ───────────────────
double g_ATR         = 0.0;    // M1 ATR
double g_ADX         = 0.0;    // H1 ADX main line     (bar 1, completed)
double g_H1ADX_Prev  = 0.0;    // H1 ADX previous bar  (bar 2, completed) — slope check
double g_PlusDI      = 0.0;    // H1 +DI
double g_MinusDI     = 0.0;    // H1 -DI
double g_M1ADX       = 0.0;    // M1 ADX main line     (bar 1, completed)
double g_M1PlusDI    = 0.0;    // M1 +DI               (bar 1, completed)
double g_M1MinusDI   = 0.0;    // M1 -DI               (bar 1, completed)
double g_M1PlusDI0   = 0.0;    // M1 +DI               (bar 0, real-time)
double g_M1MinusDI0  = 0.0;    // M1 -DI               (bar 0, real-time)
double g_M1PlusDI2   = 0.0;    // M1 +DI               (bar 2, pre-signal context)
double g_M1MinusDI2  = 0.0;    // M1 -DI               (bar 2, pre-signal context)
double g_H4PlusDI    = 0.0;    // H4 +DI               (bar 1, completed)
double g_H4MinusDI   = 0.0;    // H4 -DI               (bar 1, completed)
bool   g_IsTrending  = false;  // true = H1 ADX >= ADX_Trend_Level
bool   g_IsNewBar    = false;  // avoids duplicate IsNewBar() calls

//===================================================================
//  INIT / DEINIT
//===================================================================
int OnInit()
{
   ATR_Handle = iATR(Symbol(), PERIOD_M1, ATR_Period);
   if(ATR_Handle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create ATR indicator handle.");
      return INIT_FAILED;
   }

   ADX_Handle = iADX(Symbol(), ADX_TimeFrame, ADX_Period);
   if(ADX_Handle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create H1 ADX indicator handle.");
      return INIT_FAILED;
   }

   M1ADX_Handle = iADX(Symbol(), PERIOD_M1, ADX_Period);
   if(M1ADX_Handle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create M1 ADX indicator handle.");
      return INIT_FAILED;
   }

   H4ADX_Handle = iADX(Symbol(), PERIOD_H4, ADX_Period);
   if(H4ADX_Handle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create H4 ADX indicator handle.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(GetFillType());
   trade.LogLevel(LOG_LEVEL_ERRORS);

   TodayDate = DayOfTime(TimeCurrent());

   int detectedOffset = (int)((TimeCurrent() - TimeGMT()) / 3600);
   string gmtStr = (detectedOffset >= 0)
                   ? "UTC+" + IntegerToString(detectedOffset)
                   : "UTC"  + IntegerToString(detectedOffset);

   Print("Project ATR MT5 v2.26 | Symbol=", Symbol(),
         " | AutoMode=", (AutoModeDetect ? "ADX" : (MomentumMode ? "MOMENTUM" : "REVERSAL")),
         " | ADX_TF=",   EnumToString(ADX_TimeFrame),
         " | ADX_Level=",ADX_Trend_Level,
         " | SL=",       SL_ATR_Factor, "xATR (trend) / ",
                         SL_ATR_Ranging_Mult, "xATR (ranging M1<", M1_Ranging_Threshold, ")",
         " | TS@",       TSstart_ATR_Factor, "xATR",
         " | BrokerGMT=", gmtStr, " (auto)");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(ATR_Handle   != INVALID_HANDLE) IndicatorRelease(ATR_Handle);
   if(ADX_Handle   != INVALID_HANDLE) IndicatorRelease(ADX_Handle);
   if(M1ADX_Handle != INVALID_HANDLE) IndicatorRelease(M1ADX_Handle);
   if(H4ADX_Handle != INVALID_HANDLE) IndicatorRelease(H4ADX_Handle);
   Comment("");
}

//===================================================================
//  HELPERS
//===================================================================

int DayOfTime(datetime t)
{
   MqlDateTime s; TimeToStruct(t, s); return s.day;
}

int HourOfTime(datetime t)
{
   MqlDateTime s; TimeToStruct(t, s); return s.hour;
}

datetime StartOfDay(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   s.hour = 0; s.min = 0; s.sec = 0;
   return StructToTime(s);
}

// SGT = UTC+8, auto-detected via TimeGMT()
datetime GetSGT()
{
   return (datetime)((long)TimeGMT() + 8 * 3600);
}

bool InSession()
{
   int h = HourOfTime(GetSGT());
   return (h >= SG_Start && h < SG_End);
}

int BrokerGMTOffset()
{
   return (int)((TimeCurrent() - TimeGMT()) / 3600);
}

ENUM_ORDER_TYPE_FILLING GetFillType()
{
   long mode = (long)SymbolInfoInteger(Symbol(), SYMBOL_FILLING_MODE);
   if((mode & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((mode & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

// ATR from last COMPLETED M1 bar (shift 1)
double GetATR()
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(ATR_Handle, 0, 1, 1, buf) < 1) return 0.0;
   return buf[0];
}

// Refresh ADX + DI lines from last COMPLETED bar on ADX_TimeFrame (shift 1)
// Buffer 0 = ADX main, Buffer 1 = +DI, Buffer 2 = -DI
// Sets g_ADX, g_H1ADX_Prev, g_PlusDI, g_MinusDI
void RefreshADX()
{
   double buf[];   ArraySetAsSeries(buf, true);
   g_ADX      = (CopyBuffer(ADX_Handle, 0, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_H1ADX_Prev = (CopyBuffer(ADX_Handle, 0, 2, 1, buf) >= 1) ? buf[0] : 0.0;
   g_PlusDI   = (CopyBuffer(ADX_Handle, 1, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_MinusDI  = (CopyBuffer(ADX_Handle, 2, 1, 1, buf) >= 1) ? buf[0] : 0.0;
}

// Refresh M1 ADX + DI (counter-trend guard, dual-bar)
// Bar 1 (completed) → g_M1ADX, g_M1PlusDI,  g_M1MinusDI
// Bar 0 (real-time) → g_M1PlusDI0, g_M1MinusDI0
// Both bars are checked in the guard to catch fast-starting rallies
// that haven't yet reflected in the completed-bar DI values.
void RefreshM1ADX()
{
   double buf[];   ArraySetAsSeries(buf, true);
   // Bar 1 — last completed M1 bar
   g_M1ADX      = (CopyBuffer(M1ADX_Handle, 0, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_M1PlusDI   = (CopyBuffer(M1ADX_Handle, 1, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_M1MinusDI  = (CopyBuffer(M1ADX_Handle, 2, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   // Bar 0 — current forming bar (real-time DI only; uses bar-1 ADX for threshold)
   g_M1PlusDI0  = (CopyBuffer(M1ADX_Handle, 1, 0, 1, buf) >= 1) ? buf[0] : 0.0;
   g_M1MinusDI0 = (CopyBuffer(M1ADX_Handle, 2, 0, 1, buf) >= 1) ? buf[0] : 0.0;
   // Bar 2 — pre-signal context (v2.26: LQS sweep bar distorts bar-1 DI)
   g_M1PlusDI2  = (CopyBuffer(M1ADX_Handle, 1, 2, 1, buf) >= 1) ? buf[0] : 0.0;
   g_M1MinusDI2 = (CopyBuffer(M1ADX_Handle, 2, 2, 1, buf) >= 1) ? buf[0] : 0.0;
}

// Refresh H4 +DI and -DI from last COMPLETED H4 bar (shift 1)
// Buffer 1 = +DI, Buffer 2 = -DI
// Sets g_H4PlusDI, g_H4MinusDI — used by H4_MOM_Align filter (v2.22)
void RefreshH4ADX()
{
   double buf[];   ArraySetAsSeries(buf, true);
   g_H4PlusDI  = (CopyBuffer(H4ADX_Handle, 1, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_H4MinusDI = (CopyBuffer(H4ADX_Handle, 2, 1, 1, buf) >= 1) ? buf[0] : 0.0;
}

int CountMyPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)      == Symbol() &&
         (int)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   }
   return count;
}

bool IsNewBar()
{
   datetime t = iTime(Symbol(), PERIOD_M1, 0);
   if(t != LastBarTime) { LastBarTime = t; return true; }
   return false;
}

//===================================================================
//  DAILY P/L TRACKER  (once per bar)
//===================================================================
void UpdateTodayProfit()
{
   int today = DayOfTime(TimeCurrent());
   if(TodayDate != today)
      TodayDate = today;

   TodayProfit = 0.0;
   if(!HistorySelect(StartOfDay(TimeCurrent()), TimeCurrent())) return;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((int)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != Symbol()) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
         TodayProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                      + HistoryDealGetDouble(ticket, DEAL_SWAP)
                      + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }
}

//===================================================================
//  TRADE ENTRY
//===================================================================
void TryOpenTrade()
{
   if(!g_IsNewBar) return;
   if(EnableSessionFilter && !InSession()) return;
   if(g_ATR <= 0.0 || g_ATR < ATR_Min_Filter) return;
   if(ATR_Max_Filter > 0.0 && g_ATR > ATR_Max_Filter) return;   // skip extreme volatility (v2.24)
   // If AutoModeDetect is on, ADX must be loaded — never default to REVERSAL silently
   if(AutoModeDetect && g_ADX <= 0.0) return;
   if((long)(TimeCurrent() - LastEntry) < (long)(CooldownMinutes * 60)) return;
   if(CountMyPositions() > 0) return;

   // ── Signal from bar 1 (last COMPLETED candle) ──────────────────
   double o = iOpen(Symbol(),  PERIOD_M1, 1);
   double h = iHigh(Symbol(),  PERIOD_M1, 1);
   double l = iLow(Symbol(),   PERIOD_M1, 1);
   double c = iClose(Symbol(), PERIOD_M1, 1);

   if((h - l) < g_ATR * CandleATR_Factor) return;

   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   // ── Auto Mode Detection ────────────────────────────────────────
   // AutoModeDetect = true  → use H1 ADX to decide
   //   ADX >= ADX_Trend_Level → MOMENTUM (trade with candle)
   //   ADX <  ADX_Trend_Level → REVERSAL (fade the candle)
   // AutoModeDetect = false → use manual MomentumMode input
   bool useMomentum = AutoModeDetect ? g_IsTrending : MomentumMode;

   ENUM_ORDER_TYPE dir;
   double          price;

   // ── M1 dual-bar guard flags — pre-computed, used by MOM mode ─────
   // v2.17: ADX gate removed — DI direction is meaningful at ANY ADX.
   // Previously required M1 ADX >= ADX_Trend_Level (25), which let
   // 07:27 and 07:49 Apr 14 MOM BUY losses through when M1 ADX was
   // below 25 but -DI was already clearly > +DI (M1 bearish).
   // Mirrors the v2.14 fix applied to REV mode.
   // Verified safe: all 5 Apr 14 winning signal bars had +DI > -DI.
   // Bar 1 = last completed M1 bar. Bar 0 = current forming bar.
   bool m1BullBar1 = (g_M1PlusDI  > g_M1MinusDI);
   bool m1BullBar0 = (g_M1PlusDI0 > g_M1MinusDI0);
   bool m1BearBar1 = (g_M1MinusDI  > g_M1PlusDI);
   bool m1BearBar0 = (g_M1MinusDI0 > g_M1PlusDI0);

   if(useMomentum)
   {
      // MOMENTUM: trade candle direction AND H1 DI must agree
      // +DI > -DI = H1 bullish bias  → only BUY  bullish candle
      // -DI > +DI = H1 bearish bias  → only SELL bearish candle
      // Prevents buying a bounce inside a strong downtrend
      if     (c > o && g_PlusDI  > g_MinusDI) { dir = ORDER_TYPE_BUY;  price = ask; }
      else if(c < o && g_MinusDI > g_PlusDI)  { dir = ORDER_TYPE_SELL; price = bid; }
      else return;  // candle and H1 DI direction disagree — skip

      // ── H1 DI minimum gap for MOM mode (v2.19) ────────────────
      // When H1 DI lines are nearly equal the H1 trend is near exhaustion
      // — MOM entry chases a fading move. Require meaningful H1 DI lead.
      // 14 Apr 12:57 BUY: H1 gap=1.11; 13:20 BUY: H1 gap=0.96 → losses.
      // Mirrors H1_REV_DI_Min_Gap (v2.13) now applied to MOM mode.
      // Set H1_MOM_DI_Min_Gap=0 to disable.
      if(H1_MOM_DI_Min_Gap > 0.0)
      {
         if(dir == ORDER_TYPE_BUY  && (g_PlusDI  - g_MinusDI) < H1_MOM_DI_Min_Gap) return;
         if(dir == ORDER_TYPE_SELL && (g_MinusDI - g_PlusDI)  < H1_MOM_DI_Min_Gap) return;
      }

      // ── M1 ADX minimum for MOM mode (v2.20) ───────────────────
      // When M1 ADX is too low, DI lines oscillate randomly — any
      // direction signal is noise, even within a strong H1 trend.
      // 15 Apr 01:03 BUY: M1 ADX=14.24 → DI flipped every 1-2 bars
      // across 01:00-01:10 window → no real M1 conviction → loss.
      // Mirrors M1_REV_ADX_Min (v2.16) now applied to MOM mode.
      // Set M1_MOM_ADX_Min=0 to disable.
      if(M1_MOM_ADX_Min > 0.0 && g_M1ADX < M1_MOM_ADX_Min) return;

      // ── H1 ADX slope filter for MOM mode (v2.21) ──────────────
      // Require H1 ADX to be rising (current H1 bar > previous H1 bar).
      // Declining H1 ADX = momentum weakening = "push up then drop" trap.
      // Skip if prev bar not yet loaded (g_H1ADX_Prev == 0).
      // 15 Apr 02:07 BUY: H1 ADX 44.08→43.11 (↓) → loss -$2.50 blocked.
      // 15 Apr 05:08 BUY: H1 ADX 37.08→34.69 (↓) → loss -$3.55 blocked.
      // 14 Apr winners: H1 ADX 43.26→44.05 (↑) → both pass unaffected.
      if(H1_MOM_ADX_Rising && g_H1ADX_Prev > 0.0 && g_ADX < g_H1ADX_Prev) return;

      // ── H4 direction alignment for MOM mode (v2.22) ───────────
      // Require H4 DI direction to match the trade direction.
      // MOM SELL into H4 bull trend = counter-trend correction trade.
      // MOM BUY into H4 bear trend = counter-trend bounce trade.
      // Both are high-risk — the dominant H4 trend opposes the entry.
      // 15 Apr 11:11 MOM SELL: H4 +DI=29.70 > -DI=12.48 → BLOCKED ✓
      // Skip check if H4 data not yet loaded (g_H4PlusDI == 0).
      if(H4_MOM_Align && g_H4PlusDI > 0.0)
      {
         if(dir == ORDER_TYPE_BUY  && g_H4MinusDI > g_H4PlusDI)  return;
         if(dir == ORDER_TYPE_SELL && g_H4PlusDI  > g_H4MinusDI) return;
      }

      // ── M1 counter-trend guard — dual-bar (v2.6) ──────────────
      // Block if EITHER bar 1 OR bar 0 shows M1 trending against trade.
      // Bar 0 catches fast-starting rallies that lag in bar-1 DI values.
      if(dir == ORDER_TYPE_SELL && (m1BullBar1 || m1BullBar0)) return;
      if(dir == ORDER_TYPE_BUY  && (m1BearBar1 || m1BearBar0)) return;

      // ── M1 DI spread filter — unconditional (v2.8) ────────────
      // Block if M1 DI strongly disagrees regardless of M1 ADX level.
      // Catches clear M1 directional bias the ADX-gated guard misses
      // (e.g. M1 ADX=17 but +DI=24 >> -DI=14 → spread 10 ≥ 8).
      // Uses bar-1 (completed) values for stability.
      // Set M1_DI_Spread_Filter=0 to disable.
      if(M1_DI_Spread_Filter > 0.0)
      {
         if(dir == ORDER_TYPE_SELL && (g_M1PlusDI  - g_M1MinusDI) >= M1_DI_Spread_Filter) return;
         if(dir == ORDER_TYPE_BUY  && (g_M1MinusDI - g_M1PlusDI)  >= M1_DI_Spread_Filter) return;
      }

      // ── M1 DI convergence filter (v2.9 / v2.10) ───────────────
      // Block if M1 DI gap in the correct direction is too small.
      // "Correct direction" means -DI > +DI for SELL, +DI > -DI for BUY.
      // A tiny gap = exhausted momentum, likely a bounce/re-entry trap.
      // 9 Apr analysis: 4/5 losses were re-entries with converging DI.
      // Set M1_DI_Min_Gap=0 to disable.
      if(M1_DI_Min_Gap > 0.0)
      {
         if(dir == ORDER_TYPE_SELL && (g_M1MinusDI - g_M1PlusDI) < M1_DI_Min_Gap) return;
         if(dir == ORDER_TYPE_BUY  && (g_M1PlusDI  - g_M1MinusDI) < M1_DI_Min_Gap) return;
      }
   }
   else
   {
      // REVERSAL: fade the completed candle (H1 ADX < ADX_Trend_Level)
      if     (c > o) { dir = ORDER_TYPE_SELL; price = bid; }
      else if(c < o) { dir = ORDER_TYPE_BUY;  price = ask; }
      else           return;

      // ── M1 ADX minimum for REV mode (v2.16a) ─────────────────
      // Low M1 ADX = DI lines oscillate randomly = noise, not signal.
      // 13 Apr 05:33 REV BUY: M1 ADX=18 → DI flipped every 1-2 bars → loss.
      // Must check ADX quality BEFORE acting on DI direction.
      if(M1_REV_ADX_Min > 0.0 && g_M1ADX < M1_REV_ADX_Min) return;

      // ── M1 DI direction guard for REV mode (v2.14) ────────────
      // Replaces the v2.11 ADX-gated guard. Root cause of 06:31/08:31/
      // 10:04 losses: M1 was bullish (+DI>-DI) but ADX<25 so the guard
      // silently passed. ADX lags — the rally builds before ADX reaches
      // 25. DI direction is immediately meaningful at ANY ADX level.
      // Block REV SELL if M1 +DI > -DI (M1 bullish — any strength).
      // Block REV BUY  if M1 -DI > +DI (M1 bearish — any strength).
      // REV trades only fire when M1 DI agrees with the fade direction.
      // Uses bar-1 (completed) DI — stable, no noise from bar-0 needed
      // now that the ADX gate (the real noise filter) is removed.
      if(dir == ORDER_TYPE_SELL && g_M1PlusDI  > g_M1MinusDI) return;
      if(dir == ORDER_TYPE_BUY  && g_M1MinusDI > g_M1PlusDI)  return;

      // ── M1 DI minimum gap for REV mode (v2.15) ────────────────
      // Even when M1 DI direction is correct, a tiny gap means the
      // crossover just happened — conviction hasn't built yet.
      // 10 Apr 18:26 REV BUY: M1 +DI=20.44 vs -DI=19.90 → gap=0.54
      // → passed v2.14 direction check but barely; lost -$3.73.
      // Set M1_REV_DI_Min_Gap=0 to disable.
      if(M1_REV_DI_Min_Gap > 0.0)
      {
         if(dir == ORDER_TYPE_SELL && (g_M1MinusDI - g_M1PlusDI) < M1_REV_DI_Min_Gap) return;
         if(dir == ORDER_TYPE_BUY  && (g_M1PlusDI  - g_M1MinusDI) < M1_REV_DI_Min_Gap) return;
      }

      // ── M1 DI max gap for REV mode (v2.16b) ──────────────────
      // Extreme M1 gap = momentum at peak, likely near exhaustion.
      // 13 Apr 10:04 REV BUY: M1 gap=36.02 → reversed immediately → loss.
      // 13 Apr 06:37 REV BUY: M1 gap=5.53 (moderate) → won cleanly.
      if(M1_REV_DI_Max_Gap > 0.0)
      {
         if(dir == ORDER_TYPE_SELL && (g_M1MinusDI - g_M1PlusDI) > M1_REV_DI_Max_Gap) return;
         if(dir == ORDER_TYPE_BUY  && (g_M1PlusDI  - g_M1MinusDI) > M1_REV_DI_Max_Gap) return;
      }

      // ── H1 DI direction filter for REV mode (v2.12) ───────────
      // REV SELL only when H1 -DI > +DI (H1 leans bearish).
      // REV BUY  only when H1 +DI > -DI (H1 leans bullish).
      // When H1 is in bullish recovery, REV SELLs into green candles
      // lose; when bearish, REV BUYs into red candles lose.
      // 10 Apr: REV SELLs 06:01/06:31/07:14 fired into bullish H1
      // recovery — this filter blocks all 3 (saves ~$6.85 in losses).
      if(dir == ORDER_TYPE_SELL && g_PlusDI  >= g_MinusDI) return;
      if(dir == ORDER_TYPE_BUY  && g_MinusDI >= g_PlusDI)  return;

      // ── H1 DI minimum gap for REV mode (v2.13) ────────────────
      // Even when H1 DI leans the right way, a narrow gap means weak
      // conviction. Require H1 DI lead >= H1_REV_DI_Min_Gap.
      // Analogous to M1_DI_Min_Gap in MOM mode.
      // 10 Apr 08:31 REV SELL: H1 gap=2.14 < 3.0 → blocked (-$2.64).
      if(H1_REV_DI_Min_Gap > 0.0)
      {
         if(dir == ORDER_TYPE_SELL && (g_MinusDI - g_PlusDI) < H1_REV_DI_Min_Gap) return;
         if(dir == ORDER_TYPE_BUY  && (g_PlusDI  - g_MinusDI) < H1_REV_DI_Min_Gap) return;
      }
   }

   // ── SL / TP — adaptive SL based on M1 trend state ─────────────
   // When M1 is very choppy (ADX < M1_Ranging_Threshold), widen SL
   // so normal M1 noise cannot stop-hunt the trade before H1 trend
   // takes hold. M1 trending → normal SL_ATR_Factor.
   bool   m1IsRanging = (g_M1ADX < M1_Ranging_Threshold);
   double slMult      = m1IsRanging ? SL_ATR_Ranging_Mult : SL_ATR_Factor;
   double slDist      = g_ATR * slMult;
   double tpDist      = (TP_ATR_Factor > 0.0) ? g_ATR * TP_ATR_Factor : 0.0;

   double sl, tp;
   if(dir == ORDER_TYPE_BUY)
   {
      sl = NormalizeDouble(price - slDist, _Digits);
      tp = (tpDist > 0.0) ? NormalizeDouble(price + tpDist, _Digits) : 0.0;
   }
   else
   {
      sl = NormalizeDouble(price + slDist, _Digits);
      tp = (tpDist > 0.0) ? NormalizeDouble(price - tpDist, _Digits) : 0.0;
   }

   string tradeComment = "Project ATR | "
                        + (useMomentum ? "MOM" : "REV")
                        + (dir == ORDER_TYPE_BUY ? " BUY" : " SELL");

   bool ok = (dir == ORDER_TYPE_BUY)
             ? trade.Buy (LotSize, Symbol(), price, sl, tp, tradeComment)
             : trade.Sell(LotSize, Symbol(), price, sl, tp, tradeComment);

   if(ok)
   {
      LastEntry = TimeCurrent();
      Print("OPEN ", (dir == ORDER_TYPE_BUY ? "BUY " : "SELL"),
            " | Mode=",    (useMomentum ? "MOMENTUM" : "REVERSAL"),
            " | ADX=",     DoubleToString(g_ADX,     1),
            " | +DI=",     DoubleToString(g_PlusDI,  1),
            " | -DI=",     DoubleToString(g_MinusDI, 1),
            " | M1ADX=",   DoubleToString(g_M1ADX,    1),
            " | M1+DI=",   DoubleToString(g_M1PlusDI, 1),
            " | M1-DI=",   DoubleToString(g_M1MinusDI,1),
            " | SL=",      DoubleToString(slMult, 1), "xATR",
                           (m1IsRanging ? " [RANGING]" : " [TREND]"),
            " | SLdist=",  DoubleToString(slDist, 2),
            " | ATR=",     DoubleToString(g_ATR,  2),
            " | Range=",   DoubleToString(h - l,  2),
            " | TP=",      (tpDist > 0 ? DoubleToString(tpDist, 2) : "OFF"),
            " | SGT=",     TimeToString(GetSGT(), TIME_MINUTES));
   }
   else
      Print("Order FAIL [", trade.ResultRetcode(), "] ",
            trade.ResultRetcodeDescription());
}

//===================================================================
//  LQS ENTRY  (Liquidity Sweep — independent of MOM/REV)
//===================================================================
// Fires when bar 1 pokes above the N-bar swing high and closes back
// below it (SELL), or pokes below the swing low and closes back above
// it (BUY). No ADX/DI dependency — purely price-structure based.
// Respects the same session filter, ATR min, cooldown, and position
// count as TryOpenTrade(), so they cannot both fire on the same bar.
void TryLQSTrade()
{
   if(!Enable_LQS)  return;
   if(!g_IsNewBar)  return;
   if(EnableSessionFilter && !InSession()) return;
   if(g_ATR <= 0.0 || g_ATR < ATR_Min_Filter) return;
   if(ATR_Max_Filter > 0.0 && g_ATR > ATR_Max_Filter) return;   // skip extreme volatility (v2.24)
   if((long)(TimeCurrent() - LastEntry) < (long)(CooldownMinutes * 60)) return;
   if(CountMyPositions() > 0) return;

   // ── Bar 1 (last completed M1 bar) ─────────────────────────────
   double h1 = iHigh(Symbol(),  PERIOD_M1, 1);
   double l1 = iLow(Symbol(),   PERIOD_M1, 1);
   double c1 = iClose(Symbol(), PERIOD_M1, 1);

   // ── Swing high/low: bars 2..LQS_Lookback+1 ────────────────────
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows,  true);
   if(CopyHigh(Symbol(), PERIOD_M1, 2, LQS_Lookback, highs) < LQS_Lookback) return;
   if(CopyLow (Symbol(), PERIOD_M1, 2, LQS_Lookback, lows)  < LQS_Lookback) return;

   double swingHigh = highs[ArrayMaximum(highs)];
   double swingLow  = lows [ArrayMinimum(lows)];

   // ── Sweep detection ────────────────────────────────────────────
   // LQS SELL: bar 1 poked ABOVE swing high AND closed back below it
   // LQS BUY:  bar 1 poked BELOW swing low  AND closed back above it
   bool lqsSell = (h1 > swingHigh) && (c1 < swingHigh);
   bool lqsBuy  = (l1 < swingLow)  && (c1 > swingLow);

   if(!lqsSell && !lqsBuy) return;

   ENUM_ORDER_TYPE dir;
   double          price;
   if(lqsSell) { dir = ORDER_TYPE_SELL; price = SymbolInfoDouble(Symbol(), SYMBOL_BID); }
   else        { dir = ORDER_TYPE_BUY;  price = SymbolInfoDouble(Symbol(), SYMBOL_ASK); }

   // ── Wick size filter ───────────────────────────────────────────
   // The poke above/below the swing level must be >= LQS_Wick_Min_ATR × ATR.
   // Filters noise wicks that barely graze the level.
   if(LQS_Wick_Min_ATR > 0.0)
   {
      double wickSize = (dir == ORDER_TYPE_SELL) ? (h1 - swingHigh) : (swingLow - l1);
      if(wickSize < g_ATR * LQS_Wick_Min_ATR) return;
   }

   // ── M1 DI spread filter for LQS (v2.25 / v2.26) ─────────────────
   // Block LQS SELL when M1 is strongly bullish (+DI >> -DI).
   // Block LQS BUY  when M1 is strongly bearish (-DI >> +DI).
   // A sweep rejection fired against a dominant M1 trend rarely holds.
   // v2.25: uses bar[1] (signal bar). 16 Apr 07:39 LQS SELL: spread=21.65 → blocked.
   // v2.26: ALSO checks bar[2] (pre-signal). The sweep bar itself closes against the
   //        dominant trend (e.g. LQS BUY bar closes UP), temporarily boosting +DI and
   //        suppressing -DI on bar[1] → spread drops below threshold → filter misses.
   //        16 Apr 08:52 LQS BUY: strong M1 downtrend for 48 bars but sweep bounce
   //        bar pushed spread below 15 on bar[1] → bad trade → -$4.31 SL hit.
   //        Bar[2] (pre-sweep) still shows the real bearish bias → blocks correctly.
   if(LQS_DI_Spread_Filter > 0.0)
   {
      double spreadSell1 = g_M1PlusDI  - g_M1MinusDI;   // bar 1
      double spreadBuy1  = g_M1MinusDI - g_M1PlusDI;    // bar 1
      double spreadSell2 = g_M1PlusDI2 - g_M1MinusDI2;  // bar 2
      double spreadBuy2  = g_M1MinusDI2 - g_M1PlusDI2;  // bar 2
      if(dir == ORDER_TYPE_SELL && (spreadSell1 >= LQS_DI_Spread_Filter ||
                                    spreadSell2 >= LQS_DI_Spread_Filter)) return;
      if(dir == ORDER_TYPE_BUY  && (spreadBuy1  >= LQS_DI_Spread_Filter ||
                                    spreadBuy2  >= LQS_DI_Spread_Filter)) return;
   }

   // ── SL / TP — same adaptive logic as MOM/REV ──────────────────
   bool   m1IsRanging = (g_M1ADX < M1_Ranging_Threshold);
   double slMult      = m1IsRanging ? SL_ATR_Ranging_Mult : SL_ATR_Factor;
   double slDist      = g_ATR * slMult;
   double tpDist      = (TP_ATR_Factor > 0.0) ? g_ATR * TP_ATR_Factor : 0.0;

   double sl, tp;
   if(dir == ORDER_TYPE_BUY)
   {
      sl = NormalizeDouble(price - slDist, _Digits);
      tp = (tpDist > 0.0) ? NormalizeDouble(price + tpDist, _Digits) : 0.0;
   }
   else
   {
      sl = NormalizeDouble(price + slDist, _Digits);
      tp = (tpDist > 0.0) ? NormalizeDouble(price - tpDist, _Digits) : 0.0;
   }

   string tradeComment = "Project ATR | LQS"
                        + (dir == ORDER_TYPE_BUY ? " BUY" : " SELL");

   bool ok = (dir == ORDER_TYPE_BUY)
             ? trade.Buy (LotSize, Symbol(), price, sl, tp, tradeComment)
             : trade.Sell(LotSize, Symbol(), price, sl, tp, tradeComment);

   if(ok)
   {
      LastEntry = TimeCurrent();
      Print("OPEN LQS ", (dir == ORDER_TYPE_BUY ? "BUY " : "SELL"),
            " | swingH=",  DoubleToString(swingHigh, _Digits),
            " | swingL=",  DoubleToString(swingLow,  _Digits),
            " | bar1H=",   DoubleToString(h1, _Digits),
            " | bar1L=",   DoubleToString(l1, _Digits),
            " | bar1C=",   DoubleToString(c1, _Digits),
            " | SL=",      DoubleToString(slMult, 1), "xATR",
                           (m1IsRanging ? " [RANGING]" : " [TREND]"),
            " | SLdist=",  DoubleToString(slDist, 2),
            " | ATR=",     DoubleToString(g_ATR,  2),
            " | SGT=",     TimeToString(GetSGT(), TIME_MINUTES));
   }
   else
      Print("LQS Order FAIL [", trade.ResultRetcode(), "] ",
            trade.ResultRetcodeDescription());
}

//===================================================================
//  TRADE MANAGEMENT  (every tick)
//===================================================================
void ManageTrades()
{
   // ATR only needed for trailing stop — pre-compute distances if valid
   // Expiry close runs ALWAYS regardless of ATR availability
   bool   trailOk = (g_ATR > 0.0);
   double tsStart = trailOk ? g_ATR * TSstart_ATR_Factor : 0.0;
   double tsStep  = trailOk ? g_ATR * TSstep_ATR_Factor  : 0.0;

   // Fetch price once outside loop — does not change per-position
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)      != Symbol())    continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      ENUM_POSITION_TYPE ptype  = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             op     = PositionGetDouble(POSITION_PRICE_OPEN);
      double             sl     = PositionGetDouble(POSITION_SL);
      double             tp     = PositionGetDouble(POSITION_TP);
      datetime           opened = (datetime)PositionGetInteger(POSITION_TIME);

      // ── Expiry — always runs, independent of ATR ───────────────
      if((long)(TimeCurrent() - opened) > (long)(ExpireHours * 3600))
      {
         if(trade.PositionClose(ticket))
            Print("EXPIRY | ticket=", ticket,
                  " | held=", DoubleToString((TimeCurrent() - opened) / 3600.0, 2), "h");
         else
            Print("Expiry close FAIL: ", trade.ResultRetcodeDescription());
         continue;
      }

      // ── Trailing stop — only when ATR is valid ─────────────────
      if(!trailOk) continue;

      double profit = (ptype == POSITION_TYPE_BUY) ? (bid - op) : (op - ask);

      if(profit >= tsStart)
      {
         double newSL = (ptype == POSITION_TYPE_BUY)
                        ? NormalizeDouble(bid - tsStep, _Digits)
                        : NormalizeDouble(ask + tsStep, _Digits);

         bool improve = (ptype == POSITION_TYPE_BUY)
                        ? (newSL > sl)
                        : (sl == 0.0 || newSL < sl);

         if(improve && !trade.PositionModify(ticket, newSL, tp))
            Print("Modify SL FAIL: ", trade.ResultRetcodeDescription());
      }
   }
}

//===================================================================
//  INFO PANEL
//===================================================================
void DrawInfoPanel()
{
   double ask    = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid    = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   datetime sgt  = GetSGT();
   int gmtOffset = BrokerGMTOffset();

   // Determine what mode is actually active right now
   bool   useMomentum  = AutoModeDetect ? g_IsTrending : MomentumMode;
   string activeMode   = useMomentum ? "MOMENTUM" : "REVERSAL";
   string modeSource   = AutoModeDetect ? "AUTO-ADX" : "MANUAL";

   // ADX status string
   string adxStr;
   if(!AutoModeDetect)
      adxStr = "DISABLED (manual mode)";
   else
      adxStr = (g_ADX > 0.0 ? DoubleToString(g_ADX, 1) : "LOADING...")
             + "  [" + EnumToString(ADX_TimeFrame) + "]"
             + "  thr=" + DoubleToString(ADX_Trend_Level, 0)
             + "  → " + (g_ADX <= 0.0 ? "NO DATA" : (g_IsTrending ? "TREND" : "RANGE"));

   string atrOk  = (g_ATR < ATR_Min_Filter)                            ? "[LOW - no trade]"
                : (ATR_Max_Filter > 0.0 && g_ATR > ATR_Max_Filter) ? "[HIGH - no trade]"
                :                                                      "[OK]";
   string sessStr = !EnableSessionFilter ? "DISABLED"
                  : (InSession() ? "OPEN  [OK]" : "CLOSED [waiting]");

   // M1 DI spread for panel display (v2.8 filter — wrong direction)
   double m1DiSpread   = g_M1PlusDI - g_M1MinusDI;   // positive = bull, negative = bear
   string spreadSign   = (m1DiSpread >= 0) ? "+" : "";
   string spreadBlock  = "";
   if(M1_DI_Spread_Filter > 0.0)
   {
      if(m1DiSpread >= M1_DI_Spread_Filter)
         spreadBlock = "  [SELL BLOCKED ▲" + DoubleToString(m1DiSpread, 1) + "]";
      else if(-m1DiSpread >= M1_DI_Spread_Filter)
         spreadBlock = "  [BUY  BLOCKED ▼" + DoubleToString(-m1DiSpread, 1) + "]";
      else
         spreadBlock = "  [OK  spread=" + spreadSign + DoubleToString(m1DiSpread, 1) + "]";
   }
   else
      spreadBlock = "  [DISABLED]";

   // M1 DI convergence for panel display (v2.9 filter — exhausted momentum)
   string convBlock = "";
   if(M1_DI_Min_Gap > 0.0)
   {
      double sellGap = g_M1MinusDI - g_M1PlusDI;   // positive = M1 bearish
      double buyGap  = g_M1PlusDI  - g_M1MinusDI;  // positive = M1 bullish
      if(sellGap < M1_DI_Min_Gap && sellGap >= 0)
         convBlock = "  [SELL WEAK gap=" + DoubleToString(sellGap, 1) + "<" + DoubleToString(M1_DI_Min_Gap,1) + "]";
      else if(buyGap < M1_DI_Min_Gap && buyGap >= 0)
         convBlock = "  [BUY  WEAK gap=" + DoubleToString(buyGap,  1) + "<" + DoubleToString(M1_DI_Min_Gap,1) + "]";
      else if(sellGap >= M1_DI_Min_Gap)
         convBlock = "  [SELL OK  gap=" + DoubleToString(sellGap, 1) + "]";
      else
         convBlock = "  [BUY  OK  gap=" + DoubleToString(buyGap,  1) + "]";
   }
   else
      convBlock = "  [DISABLED]";

   string info =
      "╔══ PROJECT ATR  v2.26 (MT5) ══════════╗\n"
      "  Symbol    : " + Symbol()                                            + "\n"
      "────────────────────────────────────────\n"
      "  Mode      : " + activeMode
                       + "  [" + modeSource + "]"                           + "\n"
      "  ADX(" + IntegerToString(ADX_Period) + ")  : " + adxStr             + "\n"
      "  +DI / -DI : " + DoubleToString(g_PlusDI, 1)
                       + " / " + DoubleToString(g_MinusDI, 1)
                       + (g_PlusDI > g_MinusDI ? "  [H1-BULL]" : "  [H1-BEAR]") + "\n"
      "  M1 DI(1)  : +" + DoubleToString(g_M1PlusDI, 1)
                       + " / -" + DoubleToString(g_M1MinusDI, 1)
                       + (g_M1ADX >= ADX_Trend_Level
                          ? (g_M1PlusDI > g_M1MinusDI ? "  [M1-BULL⚠ bar1]" : "  [M1-BEAR⚠ bar1]")
                          : "  [M1-RANGE bar1]")                             + "\n"
      "  M1 DI(0)  : +" + DoubleToString(g_M1PlusDI0, 1)
                       + " / -" + DoubleToString(g_M1MinusDI0, 1)
                       + (g_M1ADX >= ADX_Trend_Level
                          ? (g_M1PlusDI0 > g_M1MinusDI0 ? "  [M1-BULL⚠ bar0]" : "  [M1-BEAR⚠ bar0]")
                          : "  [M1-RANGE bar0]")                             + "\n"
      "  DI spread : thr=" + (M1_DI_Spread_Filter > 0.0
                              ? DoubleToString(M1_DI_Spread_Filter, 1)
                              : "OFF")
                           + spreadBlock                                      + "\n"
      "  DI conv   : min=" + (M1_DI_Min_Gap > 0.0
                              ? DoubleToString(M1_DI_Min_Gap, 1)
                              : "OFF")
                           + convBlock                                        + "\n"
      "  M1 MOM ADX: min=" + (M1_MOM_ADX_Min > 0.0
                              ? DoubleToString(M1_MOM_ADX_Min, 1)
                              : "OFF")
                           + (M1_MOM_ADX_Min > 0.0
                              ? ("  [ADX=" + DoubleToString(g_M1ADX, 1)
                                 + (g_M1ADX >= M1_MOM_ADX_Min
                                    ? " OK]" : " LOW]"))
                              : "")                                           + "\n"
      "  H1 MOM slope: " + (!H1_MOM_ADX_Rising ? "OFF"
                           : (g_H1ADX_Prev <= 0.0 ? "LOADING..."
                           : (g_ADX >= g_H1ADX_Prev
                              ? ("↑ " + DoubleToString(g_H1ADX_Prev,1)
                                 + "→" + DoubleToString(g_ADX,1) + " [OK]")
                              : ("↓ " + DoubleToString(g_H1ADX_Prev,1)
                                 + "→" + DoubleToString(g_ADX,1) + " [BLOCK]")))) + "\n"
      "  H4 MOM align: " + (!H4_MOM_Align ? "OFF"
                           : (g_H4PlusDI <= 0.0 ? "LOADING..."
                           : (g_H4PlusDI > g_H4MinusDI
                              ? ("+DI=" + DoubleToString(g_H4PlusDI,1)
                                 + " -DI=" + DoubleToString(g_H4MinusDI,1)
                                 + " [H4-BULL: BUY=OK SELL=BLOCK]")
                              : ("+DI=" + DoubleToString(g_H4PlusDI,1)
                                 + " -DI=" + DoubleToString(g_H4MinusDI,1)
                                 + " [H4-BEAR: SELL=OK BUY=BLOCK]")))) + "\n"
      "  H1 MOM gap: min=" + (H1_MOM_DI_Min_Gap > 0.0
                              ? DoubleToString(H1_MOM_DI_Min_Gap, 1)
                              : "OFF")
                           + (H1_MOM_DI_Min_Gap > 0.0
                              ? ("  [gap=" + DoubleToString(MathAbs(g_PlusDI - g_MinusDI), 1)
                                 + (MathAbs(g_PlusDI - g_MinusDI) >= H1_MOM_DI_Min_Gap
                                    ? " OK]" : " WEAK]"))
                              : "")                                           + "\n"
      "  H1 REV gap: min=" + (H1_REV_DI_Min_Gap > 0.0
                              ? DoubleToString(H1_REV_DI_Min_Gap, 1)
                              : "OFF")
                           + (H1_REV_DI_Min_Gap > 0.0
                              ? ("  [gap=" + DoubleToString(MathAbs(g_PlusDI - g_MinusDI), 1)
                                 + (MathAbs(g_PlusDI - g_MinusDI) >= H1_REV_DI_Min_Gap
                                    ? " OK]" : " WEAK]"))
                              : "")                                           + "\n"
      "  M1 REV gap: min=" + (M1_REV_DI_Min_Gap > 0.0
                              ? DoubleToString(M1_REV_DI_Min_Gap, 1)
                              : "OFF")
                           + (M1_REV_DI_Min_Gap > 0.0
                              ? ("  [gap=" + DoubleToString(MathAbs(g_M1PlusDI - g_M1MinusDI), 1)
                                 + (MathAbs(g_M1PlusDI - g_M1MinusDI) >= M1_REV_DI_Min_Gap
                                    ? " OK]" : " WEAK]"))
                              : "")                                           + "\n"
      "  M1 REV ADX: min=" + (M1_REV_ADX_Min > 0.0
                              ? DoubleToString(M1_REV_ADX_Min, 1)
                              : "OFF")
                           + (M1_REV_ADX_Min > 0.0
                              ? ("  [ADX=" + DoubleToString(g_M1ADX, 1)
                                 + (g_M1ADX >= M1_REV_ADX_Min
                                    ? " OK]" : " LOW]"))
                              : "")                                           + "\n"
      "  M1 REV Xgap: max=" + (M1_REV_DI_Max_Gap > 0.0
                              ? DoubleToString(M1_REV_DI_Max_Gap, 1)
                              : "OFF")
                           + (M1_REV_DI_Max_Gap > 0.0
                              ? ("  [gap=" + DoubleToString(MathAbs(g_M1PlusDI - g_M1MinusDI), 1)
                                 + (MathAbs(g_M1PlusDI - g_M1MinusDI) <= M1_REV_DI_Max_Gap
                                    ? " OK]" : " PEAK]"))
                              : "")                                           + "\n"
      "────────────────────────────────────────\n"
      "  LQS mode  : " + (!Enable_LQS ? "OFF"
                         : ("ON  lb=" + IntegerToString(LQS_Lookback)
                            + "  wick≥" + DoubleToString(LQS_Wick_Min_ATR, 2) + "×ATR"
                            + (LQS_DI_Spread_Filter > 0.0
                               ? ("  DIspread<" + DoubleToString(LQS_DI_Spread_Filter, 0)
                                  + (((g_M1PlusDI  - g_M1MinusDI) >= LQS_DI_Spread_Filter ||
                                      (g_M1PlusDI2 - g_M1MinusDI2) >= LQS_DI_Spread_Filter) ? " [SELL BLK]"
                                   : ((g_M1MinusDI - g_M1PlusDI)  >= LQS_DI_Spread_Filter ||
                                      (g_M1MinusDI2 - g_M1PlusDI2) >= LQS_DI_Spread_Filter) ? " [BUY BLK]"
                                   :                                                             " [OK]"))
                               : "  DIspread=OFF"))) + "\n"
      "────────────────────────────────────────\n"
      "  ATR(" + IntegerToString(ATR_Period) + ")    : " + DoubleToString(g_ATR, 2)
                       + "   min=" + DoubleToString(ATR_Min_Filter, 2)
                       + (ATR_Max_Filter > 0.0
                          ? "  max=" + DoubleToString(ATR_Max_Filter, 2)
                          : "  max=OFF")
                       + "  " + atrOk                                        + "\n"
      "  Candle≥   : " + DoubleToString(g_ATR * CandleATR_Factor, 2)         + "\n"
      "  M1 ADX    : " + DoubleToString(g_M1ADX, 1)
                       + (g_M1ADX < M1_Ranging_Threshold
                          ? "  [RANGING → SL " + DoubleToString(SL_ATR_Ranging_Mult,1) + "×ATR]"
                          : "  [TREND   → SL " + DoubleToString(SL_ATR_Factor,      1) + "×ATR]") + "\n"
      "  SL dist   : " + DoubleToString(g_ATR * (g_M1ADX < M1_Ranging_Threshold
                                                  ? SL_ATR_Ranging_Mult
                                                  : SL_ATR_Factor), 2)          + "\n"
      "  TP dist   : " + (TP_ATR_Factor > 0
                          ? DoubleToString(g_ATR * TP_ATR_Factor, 2)
                          : "DISABLED (trailing only)")                       + "\n"
      "  TS start  : +" + DoubleToString(g_ATR * TSstart_ATR_Factor, 2)      + "\n"
      "  TS step   : "  + DoubleToString(g_ATR * TSstep_ATR_Factor,  2)      + "\n"
      "────────────────────────────────────────\n"
      "  Positions : " + IntegerToString(CountMyPositions())                  + "\n"
      "  Today P/L : $" + DoubleToString(TodayProfit, 2)                     + "\n"
      "  Last Entry: " + (LastEntry > 0
                          ? TimeToString(LastEntry, TIME_DATE|TIME_SECONDS)
                          : "---")                                            + "\n"
      "────────────────────────────────────────\n"
      "  SGT (auto): " + TimeToString(sgt, TIME_MINUTES)
                       + "  [broker UTC+" + IntegerToString(gmtOffset) + "]" + "\n"
      "  Session   : " + sessStr                                              + "\n"
      "  Bid / Ask : " + DoubleToString(bid, _Digits)
                       + " / " + DoubleToString(ask, _Digits)                + "\n"
      "╚════════════════════════════════════════╝";

   Comment(info);
}

//===================================================================
//  MAIN LOOP
//===================================================================
void OnTick()
{
   g_ATR        = GetATR();
   RefreshADX();                                // fills g_ADX, g_H1ADX_Prev, g_PlusDI, g_MinusDI
   RefreshM1ADX();                              // fills g_M1ADX/DI bar1 + bar0
   RefreshH4ADX();                              // fills g_H4PlusDI, g_H4MinusDI
   g_IsTrending = (g_ADX >= ADX_Trend_Level);  // true = trend → Momentum
   g_IsNewBar   = IsNewBar();

   if(g_IsNewBar)
      UpdateTodayProfit();

   ManageTrades();
   TryLQSTrade();     // Liquidity Sweep — runs FIRST; sweep signal takes priority over MOM/REV
   TryOpenTrade();    // MOM or REV — blocked if LQS already opened a position
   DrawInfoPanel();
}
//+------------------------------------------------------------------+
