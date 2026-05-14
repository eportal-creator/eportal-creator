//+------------------------------------------------------------------+
//|              PROJECT BB BREAKOUT  (MT5 v3.0)  — GBPUSD          |
//|  LQS Liquidity Sweep + Bollinger Band Confluence EA             |
//|  Based on LQS Zone Scalper v1.191                               |
//|                                                                  |
//| v3.0: Require bar[2] M1 DI confirmation for BO entries           |
//|  BO BUY  now requires +DI > -DI on BOTH bar[1] AND bar[2].      |
//|  BO SELL now requires -DI > +DI on BOTH bar[1] AND bar[2].      |
//|  A single-bar DI crossover (bar[2] still counter-directional)   |
//|  is no longer enough to fire a breakout entry. This blocks       |
//|  false breakouts triggered by brief M1 DI flips during          |
//|  counter-trend bounces (e.g. 3 consecutive BO BUY losses on     |
//|  07 May at 09:21/09:23/09:30 — all fired on single-bar DI       |
//|  crossovers within a sustained morning downtrend).               |
//|  bar[2] DI data (g_M1PlusDI2/g_M1MinusDI2) was already         |
//|  computed each bar in RefreshM1ADX() but unused for BO           |
//|  direction confirmation. No new indicator handle required.       |
//|                                                                  |
//| v2.9: Bug fixes                                                  |
//|  Fix 1: DI Spread Filter now skips BO entries. Previously the   |
//|    previous bar's DI spread (spreadBuy2/spreadSell2) could block |
//|    valid BO entries right at DI crossovers — the prior bar is    |
//|    always counter-directional just before a breakout fires.      |
//|  Fix 2: Pending orders cancelled before placing any new order.  |
//|    A pending BB/LQS limit + new BO market could create two open  |
//|    positions simultaneously. All pending orders for this         |
//|    symbol/magic are now cancelled first.                         |
//|  Fix 3: Guard added for limitPrice = 0. If BB bands return 0    |
//|    mid-session (CopyBuffer failure), limit orders are skipped    |
//|    instead of sending a price=0 order to the broker.            |
//|                                                                  |
//| v2.8: BO exhaustion filter improvements                           |
//|  Fix 1: BO_Max_Run_Bars now counts all directional bars in the   |
//|    window — removed else break. Previously one doji reset the    |
//|    entire consecutive streak, allowing exhausted entries through. |
//|    Block threshold lowered to N-1: 4 of 5 bars directional       |
//|    triggers the block (was requiring all 5 consecutive).          |
//|  Fix 2: RSI thresholds widened — BO_RSI_Oversold 32→35,         |
//|    BO_RSI_Overbought 68→65. Provides buffer against entries       |
//|    that slip through near the boundary (e.g. RSI=32.5 SELL at    |
//|    exhaustion low, RSI=67.5 BUY at exhaustion high).             |
//|                                                                  |
//| v2.6: Per-entry-type trail settings                              |
//|  BB+LQS / BB: restored to v2.2 trail (Start=0.60, Step=0.35,    |
//|    BE=0.35) — gives mean reversion trades room to develop before  |
//|    trailing. Fixed TP ($0.75) removed at entry; trail manages     |
//|    exit. Structure SL (ATR or swing level) unaffected.            |
//|  BO only: BE trigger at $0.20 (entry + $0.05 buffer), then trail  |
//|    at $0.35 with $0.15 step — locks in $0.20 profit at $0.35.    |
//|    Trail_Start (0.20→0.35) Trail_Step (0.30→0.15) BO_BE added.   |
//|    Fix: old step ($0.30) > trigger ($0.20) meant trail activated  |
//|    at loss position. Now BE fires first, trail locks real profit.  |
//|  ManageTrades() reads position comment to apply correct trail.   |
//|                                                                  |
//| v2.5: Trail tuned above M1 noise level                           |
//|  Trail_Start 0.01→0.30: trail waits for $0.30 profit before      |
//|  activating — above normal GBPUSD M1 tick noise.                 |
//|  Trail_Step  0.20→0.30: SL follows $0.30 behind price, giving    |
//|  trades room to run without premature stop-outs on minor dips.   |
//|  Fixed SL still acts as backstop if price drops before $0.30.    |
//|                                                                  |
//| v2.4: Immediate trailing SL for all entry types                  |
//|  Trail activates as soon as any profit exists (Trail_Start=0.01) |
//|  and follows $0.20 behind BID/ASK (Trail_Step=0.20). Applies to  |
//|  BB+LQS, BB, and BO entries equally. Fixed SL (BB_SL_Dollar,     |
//|  BO_SL_Dollar) remains as backstop if price drops before trail   |
//|  activates. BE trigger disabled — trail handles it.              |
//|  BB_SL_Dollar raised 0.75→1.00 for extra initial room.           |
//|                                                                  |
//| v2.3: RSI exhaustion filter for BO entries                       |
//|  Block BO SELL when RSI(14) < BO_RSI_Oversold (default 32).     |
//|  Block BO BUY  when RSI(14) > BO_RSI_Overbought (default 68).   |
//|  RSI lag is intentional — confirms prolonged multi-bar move,     |
//|  not a single-bar spike. 10:52 BO SELL (RSI=29.85) blocked;     |
//|  09:20 BO SELL (RSI=32.45) preserved. LQS and BB entries        |
//|  are unaffected. Toggle via BO_RSI_Filter input.                 |
//|                                                                  |
//| v2.2: Post-fill SL correction for fixed-dollar SL entries        |
//|  BO and BB entries now anchor SL to the actual fill price, not   |
//|  the signal price. Slippage between signal detection and fill    |
//|  can no longer shrink the intended SL buffer.                    |
//|  Example: signal BID=4596.93, fill=4597.71 (+$0.78 slip),        |
//|  BO_SL_Dollar=1.00 → old SL=4597.93 (only $0.22 from fill),     |
//|  corrected SL=4598.71 (full $1.00 from fill). Structure-based    |
//|  SL (LQS swing level) is unaffected — anchored to price level.   |
//|  BO_SL_Dollar default updated: 1.50→1.00.                        |
//|                                                                  |
//| v2.1: BB_SL_Dollar — fixed dollar SL for BB-only entries         |
//|  Overrides band-based SL for BB entries. Places SL exactly N     |
//|  dollars from entry — predictable loss cap regardless of band    |
//|  position or ATR. Default 0.75. Does not affect LQS or BO        |
//|  entries. Set 0 to use band-based SL.                            |
//|                                                                  |
//| v2.0: BO_SL_Dollar — fixed dollar SL for BO entries               |
//|  Overrides structure SL (BO_SL_Buffer) for BO entries. Places SL  |
//|  exactly N dollars from entry — predictable loss cap regardless of |
//|  swing level distance or ATR. Default 1.50 caps BO loss to ~$1.55 |
//|  (vs -$2.39 with structure SL + slippage). BE and trail still move |
//|  SL to better levels after entry — no interference.               |
//|  Set 0 to revert to structure SL (BO_SL_Buffer behaviour).        |
//|                                                                  |
//| v1.9: Revert Fix 1 and Fix 3 — keep only BO_SL_Buffer             |
//|  Fix 1 (bar range) and Fix 3 (entry distance) both blocked valid  |
//|  high-momentum BO entries (+$4.31 BO BUY at ATR=1.11). BO entries |
//|  are spike-driven by design — filtering on spike characteristics  |
//|  contradicts the strategy premise. BO_SL_Buffer (0.60) retained   |
//|  as the sole BO-specific improvement: wider buffer at the broken  |
//|  level survives normal retests without blocking genuine entries.  |
//|                                                                  |
//| v1.7–v1.8: (reverted — see above)                                 |
//|                                                                  |
//| v1.6: BO_Max_Run_Bars — block BO after extended candle run        |
//|  BO SELL blocked if N+ consecutive red bars already printed.    |
//|  BO BUY  blocked if N+ consecutive green bars already printed.  |
//|  Prevents entering a breakout at exhaustion (12:43 trap: 7 red  |
//|  candles then immediate reversal). Default: 5 bars.             |
//|                                                                  |
//| v1.5: BO_HTF_DI_Required — M5 DI confirmation for breakouts      |
//|  BO SELL blocked when M5 +DI > -DI (M5 still bullish).          |
//|  BO BUY  blocked when M5 -DI > +DI (M5 still bearish).          |
//|  Prevents false breakouts at M1 that conflict with M5 trend.    |
//|  Pullback (LQS/BB) entries unaffected.                          |
//|                                                                  |
//| v1.4: LQS_M1_DI_Align default true                               |
//|  Block counter-DI entries even in ranging mode (was only         |
//|    enforced when ADX >= threshold).                              |
//|                                                                  |
//| v1.3: Lower BE trigger default 0.50→0.35                         |
//|  Trades reversing near $0.40 profit now exit at breakeven        |
//|  instead of taking a full ATR-based SL loss.                    |
//|  Ambiguous-bar fix: outside bar sweeping both swing levels       |
//|  now skipped (was silently defaulting to SELL).                 |
//|                                                                  |
//| v1.0: Breakout continuation entry (Riding mode only)             |
//|  Uptrend BUY  : bar sweeps ABOVE swing high + closes above it.  |
//|    Momentum confirmed — trend continuing to new highs.           |
//|  Downtrend SELL: bar sweeps BELOW swing low  + closes below it. |
//|    Momentum confirmed — trend continuing to new lows.            |
//|  LQS pullback entries retained for all modes.                   |
//|  BB_Close_Zone_Filter skipped for breakout entries.             |
//|  Entry tagged "BO" to distinguish from "BB+LQS" / "BB" entries. |
//|                                                                  |
//| Inherited from Project BB v1.4 (all prior filters included):    |
//|  Mode-aware HTF filter, M1 DI riding enforcement, SL cap,       |
//|  BE buffer, BB_Close_Zone_Filter, DI spread filter.             |
//|                                                                  |
//| v1.2: Risk & direction filters                                   |
//|  SL_Max_Dollar: skip trade if SL > N dollars. Prevents          |
//|    oversized risk during high-ATR volatile sessions.             |
//|  LQS_HTF_DI_Align=true: block counter-trend entries using M5    |
//|    DI direction. BUY blocked when M5 -DI > +DI (bearish M5).   |
//|  BB_Close_Zone_Filter=true: bar[1] must close in correct BB     |
//|    half — SELL needs close >= BB Middle, BUY needs <= BB Middle. |
//|  LQS_BE_Buffer: BE stop locks in small profit instead of exact  |
//|    entry, absorbs SL fill slippage.                             |
//|                                                                  |
//| v1.1: Entry quality & dual path                                  |
//|  BB_Band_Entry: BB-only entry (no swing sweep required).        |
//|  BB_Close_Zone_Filter: prevent mid-range entries.               |
//|  CooldownMinutes reduced 5→2.                                   |
//|  LQS_Bar_Range_Max_ATR moved to LQS-only filters.               |
//|                                                                  |
//| v1.0: Bollinger Band layer added on top of LQS signals          |
//|  BB_Require_Band_Touch, BB_Midline_Trend_Filter,                |
//|  BB_Width_Min/Max_ATR, dual entry path BB+LQS / BB-only.        |
//|                                                                  |
//| Inherited from LQS v1.191:                                      |
//|  Dollar trail/BE, DI-align, bar-range, HTF M5 filter,          |
//|  close-back, body-direction, explosion-bar block.               |
//+------------------------------------------------------------------+
#property copyright "Project BB Breakout"
#property version   "3.200"
#property description "Project BB Breakout | LQS + Breakout Continuation | GBPUSD M1 v3.2"

#include <Trade\Trade.mqh>

#define LQS_LINE_SELL  "LQS_SwingHigh"
#define LQS_LINE_BUY   "LQS_SwingLow"
#define BB_LINE_UPPER  "BB_Upper"
#define BB_LINE_MIDDLE "BB_Middle"
#define BB_LINE_LOWER  "BB_Lower"
CTrade trade;

//===================================================================
//  INPUTS
//===================================================================
input group "=== Trade ==="
input double LotSize             = 0.01;
input int    MagicNumber         = 3636;
input double ExpireHours         = 0.5;
input int    CooldownMinutes     = 2;

input group "=== ATR Settings ==="
input int    ATR_Period          = 14;
input double ATR_Min_Filter      = 0.0;
input double ATR_Max_Filter      = 0.0;
input double SL_ATR_Factor       = 1.5;
input double SL_ATR_Ranging_Mult = 2.0;
input double M1_Ranging_Threshold = 35.0;
input double SL_Max_Dollar       = 5.0;
// Skip trade if calculated SL distance exceeds this dollar amount.
// Prevents large SL during high-ATR volatile periods (news spikes, big
// reversals) where ATR is inflated and 1.5-2x ATR becomes unacceptably
// large (e.g. ATR=$4.76 → ranging SL=$9.52 → far exceeds max).
// Set 0 to disable. Recommended: 0.50–1.00 for GBPUSD M1 at 0.01 lots.
input bool   Riding_Structure_SL  = true;
// Riding mode only: use swing level as SL instead of ATR-based.
// LQS SELL: SL = swept swing high + buffer (price reclaims → trade invalid).
// LQS BUY:  SL = swept swing low  - buffer.
// Tighter than ATR-based; aligns SL with the exact level that must hold.
input double Riding_SL_Buffer     = 0.20;
// Dollar buffer beyond swing level for structure-based SL.
// Absorbs minor wicks past the level without invalidating the trade.
input group "=== LQS Trail / Breakeven (BB+LQS and BB entries) ==="
input double LQS_BE_Trigger   = 0.20;
// Move SL to breakeven when BB+LQS / BB trade profit reaches this amount.
// 0.20: locks in profit early — achievable even in quiet low-ATR sessions.
// Set 0 to disable.
input double LQS_BE_Buffer    = 0.15;
// Dollar buffer added beyond entry when BE triggers.
// SELL: SL = entry - buffer. BUY: SL = entry + buffer.
// Absorbs fill slippage so BE never closes at a loss.
input double LQS_Trail_Start  = 0.30;
// Begin trailing SL for BB+LQS / BB entries when profit reaches this amount.
// 0.30: trail activates after BE has fired at $0.20 — 3 pips at 0.01 lots.
// When > 0, fixed TP is removed — trail manages the exit.
// Set 0 to use fixed TP (LQS_TP_Fixed) instead.
input double LQS_Trail_Step   = 0.15;
// Dollar gap between trailing SL and current BID/ASK for BB+LQS / BB entries.
// 0.15: tight — at $0.30 profit, SL at $0.15 locked. At $0.45, $0.30 locked.
// BO entries use BO_Trail_Start / BO_Trail_Step instead (see Breakout Settings).

input group "=== LQS Settings ==="
input int    LQS_Lookback        = 20;
input double LQS_Wick_Min_ATR    = 0.0;
input double LQS_DI_Spread_Filter = 30.0;
input double LQS_M1_DI_Max_Counter  = 0.0;
input bool   LQS_Trend_Only         = false;
input double LQS_CloseBack_Min_ATR  = 0.0;
// Minimum close-back distance as a fraction of ATR.
// SELL: bar[1] must close at least (N × ATR) below swingHigh.
// BUY:  bar[1] must close at least (N × ATR) above swingLow.
// Filters weak rejections that barely graze the level before closing back.
// 0.3 = bar must close $0.60+ below swing (at ATR=$2). Set 0 to disable.
input bool   LQS_Body_Direction     = false;
// Require sweep bar to close in the correct half of its range.
// SELL: bar[1] close must be in the lower 50% of bar range (bearish body).
// BUY:  bar[1] close must be in the upper 50% of bar range (bullish body).
// Bars closing near their high (bullish pressure) after a SELL sweep signal
// lack genuine rejection conviction. Set false to disable.
// Block LQS entry when M1 ADX < M1_Ranging_Threshold (M1 is ranging).
// Ranging mode uses 2.0×ATR SL — when ATR is high this creates large
// losses ($7-$11) that overwhelm the small fixed TP wins.
// true = only trade when M1 is trending (ADX >= threshold, SL=1.5×ATR).
// false = trade in both trending and ranging conditions (original behaviour).
input bool   LQS_M1_DI_Align        = true;
// Require bar[1] M1 DI direction to agree with the sweep signal.
// SELL: -DI >= +DI on sweep bar (M1 bears in control or neutral).
// BUY:  +DI >= -DI on sweep bar (M1 bulls in control or neutral).
// Blocks sweeps where M1 momentum runs against the trade direction —
// e.g. BB BUY triggered at lower band while -DI >> +DI (downtrend).
// Enabled by default — covers the ranging case where m1IsTrending=false
// and the trending DI check would otherwise be skipped entirely.
// Set false to allow counter-DI entries in ranging markets.
input double LQS_Bar_Range_Min_ATR  = 0.0;
input double LQS_Bar_Range_Max_ATR  = 0.0;
// Block signal if sweep bar range (H-L) exceeds N×ATR.
// Filters explosion/news bars that technically sweep a level but are
// really just a large directional move — not a genuine liquidity grab.
// Nov 21 07:58: bar range=$11.71, ATR=$3.35 → 3.49×ATR → blocked.
// All normal sweep bars have range < 2.5×ATR. Set 0 to disable.
input bool   LQS_HTF_DI_Align       = true;
// Block signal when M5 trend opposes the sweep direction.
// SELL blocked when M5 +DI > -DI (M5 bullish — don't sell into strength).
// BUY  blocked when M5 -DI > +DI (M5 bearish — don't buy into weakness).
// Fixes trading against a clear higher-timeframe trend (e.g. all-SELL
// during a bull market). Set false to disable.
// Minimum sweep bar total range (H-L) as a fraction of ATR.
// e.g. 0.5 = bar[1] range must be >= 0.5×ATR ($1.00+ at ATR=$2).
// Filters 1-tick-poke sweeps with no real volatility or momentum.
// 0 = disabled. Suggested starting value: 0.5.
input double LQS_TP_ATR_Factor   = 0.0;
// Dynamic TP: TP = ATR × LQS_TP_ATR_Factor.
// Scales with volatility — keeps R:R consistent across market conditions.
// At 1.0×ATR TP vs SL=1.5×ATR: need 60% win rate to break even.
// At 1.0×ATR TP vs SL=2.0×ATR: need 67% win rate to break even.
// Set 0 to disable and use LQS_TP_Fixed (fixed dollar) instead.
input double LQS_TP_Fixed        = 0.75;
// Fixed dollar TP. Only used when LQS_TP_ATR_Factor = 0.

input group "=== Bollinger Band Settings ==="
input int    BB_Period              = 20;
input double BB_Deviation           = 1.5;
input bool   BB_Require_Band_Touch  = true;
// SELL: sweep bar[1] high must reach or exceed BB upper band.
// BUY:  sweep bar[1] low  must reach or fall below BB lower band.
// Ensures the liquidity sweep also touches a statistically extreme
// price level — filters mid-range pokes that lack band confluence.
// Set false to disable (LQS sweeps fire regardless of BB position).
input bool   BB_Band_Entry          = true;
// Secondary entry: bar[1] touches the BB band and closes back inside — no LQS
// swing sweep required.
// SELL: bar[1] high >= BB upper AND close < BB upper.
// BUY:  bar[1] low  <= BB lower AND close > BB lower.
// Catches bounces at the band that don't sweep a swing level (e.g. 11:04 setup).
// All other active filters (DI align, body direction, bar range) still apply.

input bool   BB_Midline_Trend_Filter = false;
// Only enable when using Riding the Bands (trending) strategy.
// SELL: requires bar[1] close < BB middle. BUY: requires bar[1] close > BB middle.
// WARNING: contradicts mean reversion — when price sweeps the upper band the close
// is by definition above the middle, so this filter will always block SELL signals
// at the upper band. Leave false for standard LQS + BB mean reversion use.
input bool   BB_Close_Zone_Filter   = true;
// Mean reversion entry quality: entry must still be in the correct BB zone.
// SELL: bar[1] close must be >= BB Middle (upper half). Prevents selling after
//   the bar has already crashed through the midline — entry would be mid-range
//   or lower half, offering poor risk:reward for a SELL.
// BUY:  bar[1] close must be <= BB Middle (lower half). Prevents buying after
//   the bar has already bounced back above the midline.
input double BB_SL_Dollar           = 1.00;
// Fixed dollar SL for BB-only entries (BB BUY / BB SELL, no LQS sweep, no BO).
// Overrides band-based SL — places SL exactly N dollars from entry price.
// BB BUY: SL = entry - BB_SL_Dollar. BB SELL: SL = entry + BB_SL_Dollar.
// Acts as backstop only — immediate trail (Trail_Start=0.01) overtakes
// this SL as soon as price moves in your favour.
// Does not affect LQS or BO entries. Set 0 to use band-based SL.

input group "=== Breakout Settings ==="
input bool   BO_HTF_DI_Required     = true;
// Require M5 DI to confirm breakout direction, regardless of M1 trending status.
// BO SELL blocked when M5 +DI > -DI (M5 still bullish — false breakdown risk).
// BO BUY  blocked when M5 -DI > +DI (M5 still bearish — false breakout risk).
// Breakouts are higher-risk entries; a false break at M1 is less likely when M5
// also agrees. Pullback (LQS/BB) entries are unaffected by this flag.
// Set false to disable (breakouts allowed regardless of M5 direction).
input int    BO_Max_Run_Bars        = 5;
// Block BO entry when N-1 or more of the last N bars moved in the breakout
// direction — signals an extended move at risk of exhaustion reversal.
// Scans all N bars (doji does not reset count — was the old flaw).
// BO SELL blocked when 4+ of 5 bars are red. BO BUY blocked when 4+ of 5 green.
// 5 = scan 5 bars, block if 4 or more are directional.
// Set 0 to disable.
input double BO_SL_Buffer           = 0.60;
// SL buffer for breakout entries — wider than Riding_SL_Buffer to survive retests.
// BO SELL SL = swing_low  + BO_SL_Buffer (above broken support, now resistance).
// BO BUY  SL = swing_high - BO_SL_Buffer (below broken resistance, now support).
// Breakouts routinely retest the broken level before continuing; 0.20 is too tight.
// Recommended: 0.0010–0.0020 for GBPUSD M1 (10–20 pips buffer).
input double BO_SL_Dollar           = 1.00;
// Fixed dollar SL distance for BO entries, anchored to fill price.
// Overrides the structure SL (BO_SL_Buffer) — places SL exactly N dollars
// from the actual fill price regardless of swing level or slippage.
// BO SELL: SL = fill + BO_SL_Dollar. BO BUY: SL = fill - BO_SL_Dollar.
// SL is corrected after fill — slippage cannot shrink the buffer.
// Does not interfere with BE or trail — both still move SL to better levels.
// Set 0 to use structure SL (BO_SL_Buffer) instead.
// Recommended: 1.00 for GBPUSD M1 at 0.01 lots (≈10 pips SL).
input double BO_BE_Trigger           = 0.20;
// Move SL to breakeven for BO entries when profit reaches this amount.
// Fires before trail — guarantees no loss after $0.20 profit is seen.
// Set 0 to disable (trail alone manages exit).
input double BO_BE_Buffer            = 0.15;
// Dollar buffer beyond entry when BO BE triggers.
// SELL: SL = entry - buffer. BUY: SL = entry + buffer.
// Unified with BB/LQS BE buffer — $0.15 locked at $0.20 profit.
input double BO_Trail_Start         = 0.30;
// Begin trailing SL for BO entries when profit reaches this dollar amount.
// 0.30: trail activates after BE has fired at $0.20.
// At $0.30 profit with step=$0.15: SL locks in $0.15 minimum profit.
// Fixed SL (BO_SL_Dollar) acts as backstop until BE/trail activates.
input double BO_Trail_Step          = 0.15;
// Dollar gap between trailing SL and current BID/ASK for BO entries.
// 0.15: unified with BB/LQS trail step.
// At $0.30 profit: SL at $0.15 locked. At $0.45: SL at $0.30 locked.
input bool   BO_RSI_Filter          = false;
// Block BO entries when RSI(14) is at an extreme — price already exhausted.
// BO SELL blocked when RSI < BO_RSI_Oversold  (sustained downward exhaustion).
// BO BUY  blocked when RSI > BO_RSI_Overbought (sustained upward exhaustion).
// RSI lag is intentional: confirms prolonged move, not a single-bar spike.
// LQS and BB entries are unaffected. Set false to disable.
input double BO_RSI_Oversold        = 35.0;
// BO SELL blocked when RSI(14) falls below this level.
// Raised 32→35 to catch boundary cases (e.g. RSI=32.5 SELL at exhaustion low
// that slips through the old threshold). Only active when BO_RSI_Filter=true.
input double BO_RSI_Overbought      = 65.0;
// BO BUY blocked when RSI(14) rises above this level.
// Lowered 68→65 to catch boundary cases (e.g. RSI=67.5 BUY at exhaustion high).
// Only active when BO_RSI_Filter=true.
input double BB_Width_Min_ATR       = 0.0;
// Minimum BB width (upper - lower) as a multiple of ATR.
// Blocks entries when bands are too narrow (squeeze — imminent breakout risk).
// 0 = disabled. Suggested: 1.0.
input double BB_Width_Max_ATR       = 0.0;
// Maximum BB width (upper - lower) as a multiple of ATR.
// Blocks entries when bands are over-expanded (mean reversion may be exhausted).
// 0 = disabled.

input group "=== Session Filter (SGT auto-detected) ==="
input bool   EnableSessionFilter = true;
input int    SG_Start            = 6;
input int    SG_End              = 23;

input group "=== Notifications ==="
input bool   Enable_Notify       = true;
input int    Notify_Interval_Min = 10;
input double Notify_Zone_ATR_Dist = 2.0;

//===================================================================
//  GLOBALS
//===================================================================
datetime LastEntry       = 0;
double   TodayProfit     = 0.0;
int      TodayDate       = 0;
datetime LastBarTime     = 0;
datetime g_LastZoneAlert = 0;
double   g_LQS_SwingHigh = 0.0;
double   g_LQS_SwingLow  = 0.0;

int ATR_Handle   = INVALID_HANDLE;
int M1ADX_Handle = INVALID_HANDLE;
int M5ADX_Handle = INVALID_HANDLE;
int BB_Handle    = INVALID_HANDLE;
int RSI_Handle   = INVALID_HANDLE;

double g_ATR        = 0.0;
double g_RSI        = 50.0;
double g_BB_Upper   = 0.0;
double g_BB_Middle  = 0.0;
double g_BB_Lower   = 0.0;
double g_M1ADX      = 0.0;
double g_M1PlusDI   = 0.0;
double g_M1MinusDI  = 0.0;
double g_M1PlusDI2  = 0.0;
double g_M1MinusDI2 = 0.0;
double g_M5PlusDI   = 0.0;
double g_M5MinusDI  = 0.0;
bool   g_IsNewBar   = false;

//===================================================================
//  INIT / DEINIT
//===================================================================
int OnInit()
{
   ATR_Handle = iATR(Symbol(), PERIOD_M1, ATR_Period);
   if(ATR_Handle == INVALID_HANDLE) { Print("ERROR: ATR handle failed."); return INIT_FAILED; }

   M1ADX_Handle = iADX(Symbol(), PERIOD_M1, ATR_Period);
   if(M1ADX_Handle == INVALID_HANDLE) { Print("ERROR: M1 ADX handle failed."); return INIT_FAILED; }

   M5ADX_Handle = iADX(Symbol(), PERIOD_M5, ATR_Period);
   if(M5ADX_Handle == INVALID_HANDLE) { Print("ERROR: M5 ADX handle failed."); return INIT_FAILED; }

   BB_Handle = iBands(Symbol(), PERIOD_M1, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   if(BB_Handle == INVALID_HANDLE) { Print("ERROR: BB handle failed."); return INIT_FAILED; }

   RSI_Handle = iRSI(Symbol(), PERIOD_M1, 14, PRICE_CLOSE);
   if(RSI_Handle == INVALID_HANDLE) { Print("ERROR: RSI handle failed."); return INIT_FAILED; }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(GetFillType());
   trade.LogLevel(LOG_LEVEL_ERRORS);

   TodayDate = DayOfTime(TimeCurrent());

   string exitMode = (LQS_Trail_Start > 0.0)
                    ? "Trail +$" + DoubleToString(LQS_Trail_Start,2)
                      + " step=$" + DoubleToString(LQS_Trail_Step,2)
                      + (LQS_BE_Trigger > 0.0
                         ? " BE=$" + DoubleToString(LQS_BE_Trigger,2)
                         : "")
                    : (LQS_TP_ATR_Factor > 0.0
                       ? DoubleToString(LQS_TP_ATR_Factor,2)+"xATR [dynamic]"
                       : "$"+DoubleToString(LQS_TP_Fixed,2)+" [fixed]");
   Print("Project BB Breakout v3.2 (GBPUSD) | Symbol=", Symbol(),
         " | Magic=", MagicNumber,
         " | Exit=", exitMode,
         " | HTF_DI=", LQS_HTF_DI_Align,
         " | SL_Max=$", SL_Max_Dollar,
         " | BE_Buf=$", LQS_BE_Buffer,
         " | CloseZone=", BB_Close_Zone_Filter,
         " | DI_Spread=", LQS_DI_Spread_Filter,
         " | RidingDIEnforce=ON",
         " | RangingThresh=ADX<", M1_Ranging_Threshold);

   if(Enable_Notify && Notify_Interval_Min > 0)
      EventSetTimer(Notify_Interval_Min * 60);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(ATR_Handle   != INVALID_HANDLE) IndicatorRelease(ATR_Handle);
   if(M1ADX_Handle != INVALID_HANDLE) IndicatorRelease(M1ADX_Handle);
   if(M5ADX_Handle != INVALID_HANDLE) IndicatorRelease(M5ADX_Handle);
   if(BB_Handle    != INVALID_HANDLE) IndicatorRelease(BB_Handle);
   if(RSI_Handle   != INVALID_HANDLE) IndicatorRelease(RSI_Handle);
   ObjectDelete(0, LQS_LINE_SELL);
   ObjectDelete(0, LQS_LINE_BUY);
   ObjectDelete(0, BB_LINE_UPPER);
   ObjectDelete(0, BB_LINE_MIDDLE);
   ObjectDelete(0, BB_LINE_LOWER);
   Comment("");
}

//===================================================================
//  HELPERS
//===================================================================
int DayOfTime(datetime t)   { MqlDateTime s; TimeToStruct(t, s); return s.day;  }
int HourOfTime(datetime t)  { MqlDateTime s; TimeToStruct(t, s); return s.hour; }

datetime StartOfDay(datetime t)
{
   MqlDateTime s; TimeToStruct(t, s);
   s.hour = 0; s.min = 0; s.sec = 0;
   return StructToTime(s);
}

datetime GetSGT() { return (datetime)((long)TimeGMT() + 8 * 3600); }

bool InSession()
{
   int h = HourOfTime(GetSGT());
   return (h >= SG_Start && h < SG_End);
}

int BrokerGMTOffset() { return (int)((TimeCurrent() - TimeGMT()) / 3600); }

ENUM_ORDER_TYPE_FILLING GetFillType()
{
   long mode = (long)SymbolInfoInteger(Symbol(), SYMBOL_FILLING_MODE);
   if((mode & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((mode & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

// Convert dollar amount → price distance for this symbol/lot size.
// GBPUSD example at 0.01 lots: D2P(1.00) = 0.00100 (10 pips = $1.00)
double D2P(double dollars)
{
   double tickVal  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0.0 || tickSize <= 0.0 || LotSize <= 0.0) return dollars;
   return dollars * tickSize / (tickVal * LotSize);
}

// Convert price distance → dollar amount for this symbol/lot size.
double P2D(double priceDist)
{
   double tickVal  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0.0 || tickSize <= 0.0 || LotSize <= 0.0) return priceDist;
   return priceDist * tickVal * LotSize / tickSize;
}

double GetATR()
{
   double buf[]; ArraySetAsSeries(buf, true);
   if(CopyBuffer(ATR_Handle, 0, 1, 1, buf) < 1) return 0.0;
   return buf[0];
}

void RefreshM1ADX()
{
   double buf[]; ArraySetAsSeries(buf, true);
   g_M1ADX      = (CopyBuffer(M1ADX_Handle, 0, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_M1PlusDI   = (CopyBuffer(M1ADX_Handle, 1, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_M1MinusDI  = (CopyBuffer(M1ADX_Handle, 2, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_M1PlusDI2  = (CopyBuffer(M1ADX_Handle, 1, 2, 1, buf) >= 1) ? buf[0] : 0.0;
   g_M1MinusDI2 = (CopyBuffer(M1ADX_Handle, 2, 2, 1, buf) >= 1) ? buf[0] : 0.0;
}

void RefreshBB()
{
   double buf[]; ArraySetAsSeries(buf, true);
   g_BB_Upper  = (CopyBuffer(BB_Handle, 1, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_BB_Middle = (CopyBuffer(BB_Handle, 0, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_BB_Lower  = (CopyBuffer(BB_Handle, 2, 1, 1, buf) >= 1) ? buf[0] : 0.0;
}

void RefreshRSI()
{
   double buf[]; ArraySetAsSeries(buf, true);
   g_RSI = (CopyBuffer(RSI_Handle, 0, 1, 1, buf) >= 1) ? buf[0] : 50.0;
}

void RefreshM5DI()
{
   double buf[]; ArraySetAsSeries(buf, true);
   g_M5PlusDI  = (CopyBuffer(M5ADX_Handle, 1, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_M5MinusDI = (CopyBuffer(M5ADX_Handle, 2, 1, 1, buf) >= 1) ? buf[0] : 0.0;
}

void RefreshLQSLevels()
{
   double highs[], lows[];
   ArraySetAsSeries(highs, true); ArraySetAsSeries(lows, true);
   if(CopyHigh(Symbol(), PERIOD_M1, 2, LQS_Lookback, highs) < LQS_Lookback) return;
   if(CopyLow (Symbol(), PERIOD_M1, 2, LQS_Lookback, lows)  < LQS_Lookback) return;
   g_LQS_SwingHigh = highs[ArrayMaximum(highs)];
   g_LQS_SwingLow  = lows [ArrayMinimum(lows)];
}

void CancelPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != Symbol()) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(!trade.OrderDelete(ticket))
         Print("Cancel pending FAIL: ", trade.ResultRetcodeDescription());
   }
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
//  DAILY P/L TRACKER
//===================================================================
void UpdateTodayProfit()
{
   int today = DayOfTime(TimeCurrent());
   if(TodayDate != today) TodayDate = today;
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
//  NOTIFICATIONS
//===================================================================
string M1Direction()
{
   double spread = g_M1PlusDI - g_M1MinusDI;
   if     (spread >=  8) return "M1 BULL";
   else if(spread <= -8) return "M1 BEAR";
   else                  return "M1 NEUTRAL";
}

string BBMode()
{
   double bbWidth = (g_BB_Upper > 0.0 && g_BB_Lower > 0.0) ? g_BB_Upper - g_BB_Lower : 0.0;
   if(g_ATR > 0.0 && bbWidth > 0.0 && bbWidth < g_ATR)
      return "★SQUEEZE | breakout either direction";
   if(g_M1ADX >= M1_Ranging_Threshold)
   {
      bool uptrend = (g_M1PlusDI > g_M1MinusDI);
      return uptrend
             ? "★RIDING UPTREND ADX=" + DoubleToString(g_M1ADX,1)
               + " | BUY dips to lower band only"
             : "★RIDING DOWNTREND ADX=" + DoubleToString(g_M1ADX,1)
               + " | SELL rallies to upper band only";
   }
   return "★MEAN REVERSION ADX=" + DoubleToString(g_M1ADX,1)
          + " | fade both extremes";
}

// ── 1. Signal Alert — fires when EA detects a valid entry ─────────────
void SendSignalAlert(ENUM_ORDER_TYPE dir, double entryPrice,
                     double sl, double tp, double slDist, double tpDist,
                     double h1, double l1, double c1)
{
   if(!Enable_Notify) return;
   string side    = (dir == ORDER_TYPE_SELL) ? "SELL" : "BUY";
   string bbBand  = (dir == ORDER_TYPE_SELL)
                    ? "BB Upper: " + DoubleToString(g_BB_Upper, _Digits)
                    : "BB Lower: " + DoubleToString(g_BB_Lower, _Digits);
   string sweepInfo = (dir == ORDER_TYPE_SELL)
                    ? "Spike to " + DoubleToString(h1, _Digits)
                      + " | SwingH " + DoubleToString(g_LQS_SwingHigh, _Digits)
                      + " | Close " + DoubleToString(c1, _Digits)
                    : "Spike to " + DoubleToString(l1, _Digits)
                      + " | SwingL " + DoubleToString(g_LQS_SwingLow, _Digits)
                      + " | Close " + DoubleToString(c1, _Digits);
   string tpStr   = (tpDist > 0.0)
                    ? DoubleToString(tp, 2) + "  ($" + DoubleToString(tpDist, 2) + ")"
                    : "Trail $" + DoubleToString(LQS_Trail_Start, 2)
                      + " step $" + DoubleToString(LQS_Trail_Step, 2);
   string msg =
      "[BB+LQS] " + side + " SIGNAL  " + Symbol() + "\n"
      + "Entry : " + DoubleToString(entryPrice, _Digits) + "\n"
      + "SL    : " + DoubleToString(sl, _Digits)
      + "  ($" + DoubleToString(P2D(slDist), 2) + ")\n"
      + "TP    : " + tpStr + "\n"
      + bbBand + "  |  " + sweepInfo + "\n"
      + M1Direction() + "  ATR=" + DoubleToString(g_ATR, _Digits)
      + "  " + BBMode()
      + "  SGT=" + TimeToString(GetSGT(), TIME_MINUTES);
   SendNotification(msg);
}

// ── 2. Zone Approach Alert — price near BB band + swing level ──────
void CheckZoneApproach()
{
   if(!Enable_Notify || Notify_Zone_ATR_Dist <= 0.0) return;
   if(g_ATR <= 0.0 || g_LQS_SwingHigh <= 0.0 || g_LQS_SwingLow <= 0.0) return;
   if(g_BB_Upper <= 0.0 || g_BB_Lower <= 0.0) return;
   if((long)(TimeCurrent() - g_LastZoneAlert) < 300) return;

   double price  = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double thresh = Notify_Zone_ATR_Dist * g_ATR;

   double distSwingH = g_LQS_SwingHigh - price;
   double distSwingL = price - g_LQS_SwingLow;
   double distBBUp   = g_BB_Upper - price;
   double distBBLow  = price - g_BB_Lower;

   bool m1Trending  = (g_M1ADX >= M1_Ranging_Threshold);
   bool m1Uptrend   = m1Trending && (g_M1PlusDI  > g_M1MinusDI);
   bool m1Downtrend = m1Trending && (g_M1MinusDI > g_M1PlusDI);

   bool nearSell = distSwingH <= thresh && price < g_LQS_SwingHigh
                && distBBUp   <= thresh && price < g_BB_Upper;
   bool nearBuy  = distSwingL <= thresh && price > g_LQS_SwingLow
                && distBBLow  <= thresh && price > g_BB_Lower;

   if(m1Uptrend   && nearSell && !nearBuy) return;
   if(m1Downtrend && nearBuy  && !nearSell) return;
   if(!nearSell && !nearBuy) return;

   string side    = nearSell ? "SELL" : "BUY";
   string swing   = nearSell ? DoubleToString(g_LQS_SwingHigh, _Digits) : DoubleToString(g_LQS_SwingLow, _Digits);
   string bbLevel = nearSell ? DoubleToString(g_BB_Upper, _Digits)       : DoubleToString(g_BB_Lower, _Digits);
   double dSwing  = nearSell ? distSwingH : distSwingL;
   double dBB     = nearSell ? distBBUp   : distBBLow;
   string action  = nearSell
                    ? "Spike ABOVE " + swing + " + touch BB " + bbLevel + " then close below"
                    : "Spike BELOW " + swing + " + touch BB " + bbLevel + " then close above";
   string blocked = (m1Uptrend && nearSell)  ? "  [SELL BLOCKED — uptrend]"
                  : (m1Downtrend && nearBuy) ? "  [BUY BLOCKED — downtrend]"
                  : "";

   string msg =
      "[BB+LQS] " + side + " ZONE APPROACH  " + Symbol() + "\n"
      + "Price     : " + DoubleToString(price, _Digits) + "\n"
      + "Swing " + (nearSell ? "High" : "Low ") + " : " + swing
      + "  ($" + DoubleToString(P2D(dSwing), 2) + " away)\n"
      + "BB " + (nearSell ? "Upper" : "Lower") + "   : " + bbLevel
      + "  ($" + DoubleToString(P2D(dBB), 2) + " away)\n"
      + "Watch for : " + action + " → " + side + blocked + "\n"
      + M1Direction() + "  ATR=" + DoubleToString(g_ATR, _Digits) + "\n"
      + BBMode()
      + "  SGT=" + TimeToString(GetSGT(), TIME_MINUTES);

   SendNotification(msg);
   g_LastZoneAlert = TimeCurrent();
}

// ── 3. Periodic Status — every N minutes ──────────────────────
void OnTimer()
{
   if(!Enable_Notify) return;
   double price    = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double distSell = (g_LQS_SwingHigh > 0) ? g_LQS_SwingHigh - price : 0.0;
   double distBuy  = (g_LQS_SwingLow  > 0) ? price - g_LQS_SwingLow  : 0.0;
   double bbWidth  = (g_BB_Upper > 0.0 && g_BB_Lower > 0.0) ? g_BB_Upper - g_BB_Lower : 0.0;
   string msg =
      "[BB+LQS] " + Symbol() + " " + DoubleToString(price, _Digits)
      + "  " + M1Direction() + "  " + BBMode() + "\n"
      + "BB(" + IntegerToString(BB_Period) + "," + DoubleToString(BB_Deviation,1) + ")"
      + "  U=" + DoubleToString(g_BB_Upper,  _Digits)
      + "  M=" + DoubleToString(g_BB_Middle, _Digits)
      + "  L=" + DoubleToString(g_BB_Lower,  _Digits)
      + "  W=$" + DoubleToString(P2D(bbWidth), 2) + "\n"
      + "SELL zone: SwingH " + DoubleToString(g_LQS_SwingHigh, _Digits)
      + "  ($+" + DoubleToString(P2D(distSell), 1) + ")  BBU " + DoubleToString(g_BB_Upper, _Digits) + "\n"
      + "BUY  zone: SwingL " + DoubleToString(g_LQS_SwingLow, _Digits)
      + "  ($-" + DoubleToString(P2D(distBuy),  1) + ")  BBL " + DoubleToString(g_BB_Lower, _Digits) + "\n"
      + "ATR=" + DoubleToString(g_ATR, _Digits)
      + "  ADX=" + DoubleToString(g_M1ADX, 1)
      + "  P&L=$" + DoubleToString(TodayProfit, 2)
      + "  SGT=" + TimeToString(GetSGT(), TIME_MINUTES);
   SendNotification(msg);
}

//===================================================================
//  TRADE MANAGEMENT
//===================================================================
void ManageTrades()
{
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

      if((long)(TimeCurrent() - opened) > (long)(ExpireHours * 3600))
      {
         if(trade.PositionClose(ticket))
            Print("EXPIRY | ticket=", ticket,
                  " | held=", DoubleToString((TimeCurrent() - opened) / 3600.0, 2), "h");
         else
            Print("Expiry close FAIL: ", trade.ResultRetcodeDescription());
         continue;
      }

      // Actual position profit in account currency — symbol-agnostic.
      double profit = PositionGetDouble(POSITION_PROFIT);
      double newSL  = sl;

      // Per-entry-type trail: BO uses tight trail, BB+LQS/BB uses wider trail.
      string posComment  = PositionGetString(POSITION_COMMENT);
      bool   posIsBO     = (StringFind(posComment, "BO") == 0);
      double trailStart  = posIsBO ? BO_Trail_Start  : LQS_Trail_Start;
      double trailStep   = posIsBO ? BO_Trail_Step   : LQS_Trail_Step;

      // Trail: price-follows SL once profit (dollars) >= trailStart
      if(trailStart > 0.0 && profit >= trailStart)
      {
         double trailSL = (ptype == POSITION_TYPE_BUY)
                          ? NormalizeDouble(bid - D2P(trailStep), _Digits)
                          : NormalizeDouble(ask + D2P(trailStep), _Digits);
         bool improve = (ptype == POSITION_TYPE_BUY)
                        ? (trailSL > newSL + _Point)
                        : (newSL == 0.0 || trailSL < newSL - _Point);
         if(improve) newSL = trailSL;
      }
      // Breakeven for BO: fires before trail, locks in no-loss when profit >= BO_BE_Trigger.
      // Fixes trail_step > trail_start flaw: old step($0.30) > trigger($0.20) meant
      // trail activated at a loss position. BE now fires first at $0.20, trail at $0.35.
      else if(posIsBO && BO_BE_Trigger > 0.0 && profit >= BO_BE_Trigger)
      {
         double beSL  = (ptype == POSITION_TYPE_BUY)
                        ? NormalizeDouble(op + D2P(BO_BE_Buffer), _Digits)
                        : NormalizeDouble(op - D2P(BO_BE_Buffer), _Digits);
         bool improve = (ptype == POSITION_TYPE_BUY)
                        ? (beSL > newSL + _Point)
                        : (newSL == 0.0 || beSL < newSL - _Point);
         if(improve) newSL = beSL;
      }
      // Breakeven: BB+LQS / BB only.
      else if(!posIsBO && LQS_BE_Trigger > 0.0 && profit >= LQS_BE_Trigger)
      {
         double beSL  = (ptype == POSITION_TYPE_BUY)
                        ? NormalizeDouble(op + D2P(LQS_BE_Buffer), _Digits)
                        : NormalizeDouble(op - D2P(LQS_BE_Buffer), _Digits);
         bool improve = (ptype == POSITION_TYPE_BUY)
                        ? (beSL > newSL + _Point)
                        : (newSL == 0.0 || beSL < newSL - _Point);
         if(improve) newSL = beSL;
      }

      if(newSL != sl && !trade.PositionModify(ticket, newSL, tp))
         Print("Modify SL FAIL: ", trade.ResultRetcodeDescription());
   }
}

//===================================================================
//  LQS ENTRY
//===================================================================
void TryLQSTrade()
{
   if(!g_IsNewBar) return;
   if(EnableSessionFilter && !InSession()) return;
   if(g_ATR <= 0.0 || g_ATR < ATR_Min_Filter) return;
   if(ATR_Max_Filter > 0.0 && g_ATR > ATR_Max_Filter) return;
   if((long)(TimeCurrent() - LastEntry) < (long)(CooldownMinutes * 60)) return;
   if(CountMyPositions() > 0) return;

   double h1 = iHigh(Symbol(),  PERIOD_M1, 1);
   double l1 = iLow(Symbol(),   PERIOD_M1, 1);
   double c1 = iClose(Symbol(), PERIOD_M1, 1);

   // ── Entry condition A: LQS swing sweep (all modes) ────────────
   // Reversal fade: sweep past level then close back inside.
   bool lqsSell = false, lqsBuy = false;
   if(g_LQS_SwingHigh > 0.0 && g_LQS_SwingLow > 0.0)
   {
      lqsSell = (h1 > g_LQS_SwingHigh) && (c1 < g_LQS_SwingHigh);
      lqsBuy  = (l1 < g_LQS_SwingLow)  && (c1 > g_LQS_SwingLow);
   }

   // ── Entry condition B: BB band touch + close back inside ──────
   // No swing sweep required — bar[1] touches the band and closes inside.
   bool bbSell = BB_Band_Entry && g_BB_Upper > 0.0 && (h1 >= g_BB_Upper) && (c1 < g_BB_Upper);
   bool bbBuy  = BB_Band_Entry && g_BB_Lower > 0.0 && (l1 <= g_BB_Lower) && (c1 > g_BB_Lower);

   // ── Entry condition C: Breakout continuation (Riding mode only) ──
   // Trend follow: sweep past level and close OUTSIDE = momentum confirmed.
   // Uptrend BUY  : bar sweeps above swing high AND closes above it.
   // Downtrend SELL: bar sweeps below swing low  AND closes below it.
   bool boBuy = false, boSell = false;
   bool m1IsTrendingEntry = (g_M1ADX >= M1_Ranging_Threshold);
   if(m1IsTrendingEntry && g_LQS_SwingHigh > 0.0 && g_LQS_SwingLow > 0.0)
   {
      // BB_Middle guard: BO BUY only fires in upper BB half (c1 > middle),
      // BO SELL only fires in lower BB half (c1 < middle). Prevents BO from
      // firing at the BB bands where mean reversion is the correct entry type.
      // Fallback: if BB data unavailable (middle=0), allow BO to fire normally.
      boBuy  = (g_M1PlusDI  > g_M1MinusDI) && (g_M1PlusDI2  > g_M1MinusDI2)
               && (h1 > g_LQS_SwingHigh) && (c1 >= g_LQS_SwingHigh)
               && (g_BB_Middle <= 0.0 || c1 > g_BB_Middle);
      boSell = (g_M1MinusDI > g_M1PlusDI)  && (g_M1MinusDI2 > g_M1PlusDI2)
               && (l1 < g_LQS_SwingLow)  && (c1 <= g_LQS_SwingLow)
               && (g_BB_Middle <= 0.0 || c1 < g_BB_Middle);
   }

   bool isSell     = lqsSell || bbSell || boSell;
   bool isBuy      = lqsBuy  || bbBuy  || boBuy;
   bool isLQS      = lqsSell || lqsBuy;
   bool isBreakout = boBuy   || boSell;
   if(!isSell && !isBuy) return;
   // Outside bar sweeping both levels — direction ambiguous, skip.
   if(isSell && isBuy) return;

   ENUM_ORDER_TYPE dir;
   double          price;
   if(isSell) { dir = ORDER_TYPE_SELL; price = SymbolInfoDouble(Symbol(), SYMBOL_BID); }
   else       { dir = ORDER_TYPE_BUY;  price = SymbolInfoDouble(Symbol(), SYMBOL_ASK); }

   // ── LQS-only filters ─────────────────────────────────────
   if(isLQS)
   {
      if(LQS_Wick_Min_ATR > 0.0)
      {
         double wickSize = (dir == ORDER_TYPE_SELL) ? (h1 - g_LQS_SwingHigh) : (g_LQS_SwingLow - l1);
         if(wickSize < g_ATR * LQS_Wick_Min_ATR) return;
      }
      if(LQS_CloseBack_Min_ATR > 0.0)
      {
         double closeBack = lqsSell ? (g_LQS_SwingHigh - c1) : (c1 - g_LQS_SwingLow);
         if(closeBack < g_ATR * LQS_CloseBack_Min_ATR) return;
      }
      // BB touch required on LQS path only.
      // BB-only and breakout entries have a touch/close condition built in,
      // so BB_Require_Band_Touch has no additional effect on those paths.
      if(BB_Require_Band_Touch && g_BB_Upper > 0.0 && g_BB_Lower > 0.0)
      {
         if(lqsSell && h1 < g_BB_Upper) return;
         if(lqsBuy  && l1 > g_BB_Lower) return;
      }
      // Bar range filters — LQS only. Large bars on BB-only entry are valid
      // band-touch bounces, not news spikes (e.g. 12:55 $6 drop to lower band).
      if(LQS_Bar_Range_Min_ATR > 0.0)
      {
         double barRange = h1 - l1;
         if(barRange < g_ATR * LQS_Bar_Range_Min_ATR) return;
      }
      if(LQS_Bar_Range_Max_ATR > 0.0)
      {
         double barRange = h1 - l1;
         if(barRange > g_ATR * LQS_Bar_Range_Max_ATR) return;
      }
   }

   // ── Common filters (apply to both LQS and BB entry) ───────────
   if(LQS_Body_Direction)
   {
      double midPoint = (h1 + l1) * 0.5;
      if(isSell && c1 > midPoint) return;
      if(isBuy  && c1 < midPoint) return;
   }

   // Riding the Bands: always enforce M1 DI direction — no lag unlike M5 HTF.
   // Mean Reversion / Squeeze: respect the LQS_M1_DI_Align toggle only.
   bool m1IsTrending = (g_M1ADX >= M1_Ranging_Threshold);
   if(m1IsTrending || LQS_M1_DI_Align)
   {
      if(isSell && g_M1PlusDI  > g_M1MinusDI) return;
      if(isBuy  && g_M1MinusDI > g_M1PlusDI)  return;
   }

   // Riding mode: M1 DI already confirms direction — M5 HTF not needed and
   // would block valid with-trend pullback entries during intraday retracements.
   if(LQS_HTF_DI_Align && !m1IsTrending)
   {
      if(isSell && g_M5PlusDI  > g_M5MinusDI) return;
      if(isBuy  && g_M5MinusDI > g_M5PlusDI)  return;
   }

   // Breakout entries: always enforce M5 DI alignment regardless of trending status.
   // False breakouts at M1 level are less likely when M5 trend agrees.
   // Pullback entries (LQS/BB) are unaffected.
   if(BO_HTF_DI_Required && isBreakout)
   {
      if(isSell && g_M5PlusDI  > g_M5MinusDI) return;
      if(isBuy  && g_M5MinusDI > g_M5PlusDI)  return;
   }

   // Block BO entry when price has already run N+ consecutive bars in the
   // breakout direction — extended moves are prone to exhaustion reversals.
   if(BO_Max_Run_Bars > 0 && isBreakout)
   {
      int runCount = 0;
      for(int k = 1; k <= BO_Max_Run_Bars; k++)
      {
         double o = iOpen(Symbol(),  PERIOD_M1, k);
         double c = iClose(Symbol(), PERIOD_M1, k);
         if(isSell && c < o) runCount++;   // red candle
         else if(isBuy  && c > o) runCount++;   // green candle
         // no break — scan all N bars so one doji does not reset the count
      }
      if(runCount >= BO_Max_Run_Bars - 1) return;  // block if N-1 of N bars directional
   }


   if(g_BB_Upper > 0.0 && g_BB_Lower > 0.0)
   {
      double bbWidth = g_BB_Upper - g_BB_Lower;
      if(BB_Width_Min_ATR > 0.0 && bbWidth < g_ATR * BB_Width_Min_ATR) return;
      if(BB_Width_Max_ATR > 0.0 && bbWidth > g_ATR * BB_Width_Max_ATR) return;
   }

   if(BB_Midline_Trend_Filter && g_BB_Middle > 0.0)
   {
      if(isSell && c1 >= g_BB_Middle) return;
      if(isBuy  && c1 <= g_BB_Middle) return;
   }

   // Entry zone quality: bar[1] must have closed in the correct BB half.
   // Skipped for breakout entries — their close is outside the band by definition.
   if(BB_Close_Zone_Filter && g_BB_Middle > 0.0 && !isBreakout)
   {
      if(isSell && c1 < g_BB_Middle) return;
      if(isBuy  && c1 > g_BB_Middle) return;
   }

   // BO entries skip this filter: previous bar is always counter-directional
   // (DI just crossed), so spreadBuy2/spreadSell2 would block valid breakouts.
   if(LQS_DI_Spread_Filter > 0.0 && !isBreakout)
   {
      double spreadSell1 = g_M1PlusDI  - g_M1MinusDI;
      double spreadBuy1  = g_M1MinusDI - g_M1PlusDI;
      double spreadSell2 = g_M1PlusDI2 - g_M1MinusDI2;
      double spreadBuy2  = g_M1MinusDI2 - g_M1PlusDI2;
      if(dir == ORDER_TYPE_SELL && (spreadSell1 >= LQS_DI_Spread_Filter ||
                                    spreadSell2 >= LQS_DI_Spread_Filter)) return;
      if(dir == ORDER_TYPE_BUY  && (spreadBuy1  >= LQS_DI_Spread_Filter ||
                                    spreadBuy2  >= LQS_DI_Spread_Filter)) return;
   }

   if(LQS_M1_DI_Max_Counter > 0.0)
   {
      if(dir == ORDER_TYPE_BUY  && (g_M1MinusDI - g_M1PlusDI)  >= LQS_M1_DI_Max_Counter) return;
      if(dir == ORDER_TYPE_SELL && (g_M1PlusDI  - g_M1MinusDI) >= LQS_M1_DI_Max_Counter) return;
   }

   bool   m1IsRanging = (g_M1ADX < M1_Ranging_Threshold);
   if(LQS_Trend_Only && m1IsRanging) return;

   // ── Trend direction filter (disabled by default) ──────────────
   // When enabled: in trending mode only trade with trend direction.
   // Ranging: both directions. Trending UP: BUY only. Trending DOWN: SELL only.
   // Disabled by default — in strong trends price rarely reaches the
   // opposite band, causing the EA to stop trading entirely.
   // Enable manually when you want strict trend-following behaviour.
   if(LQS_Trend_Only && !m1IsRanging)
   {
      if(g_M1PlusDI > g_M1MinusDI && dir == ORDER_TYPE_SELL) return;
      if(g_M1MinusDI > g_M1PlusDI && dir == ORDER_TYPE_BUY)  return;
   }

   double slMult        = m1IsRanging ? SL_ATR_Ranging_Mult : SL_ATR_Factor;
   double slDist        = g_ATR * slMult;
   double sl;
   bool   slIsFixedDollar = false;

   // Riding mode: use swing level as SL — tighter and structure-based.
   // LQS: SL at swept level (if price reclaims it the trade is invalid).
   // BO:  SL at the broken level (if price reclaims it breakout has failed).
   // Falls back to ATR-based if swing level produces invalid distance.
   if(isBreakout && BO_SL_Dollar > 0.0)
   {
      // Fixed dollar SL for BO entries — predictable loss cap regardless of
      // swing level distance. Corrected to fill price after entry.
      sl              = (dir == ORDER_TYPE_BUY)
                        ? NormalizeDouble(price - D2P(BO_SL_Dollar), _Digits)
                        : NormalizeDouble(price + D2P(BO_SL_Dollar), _Digits);
      slDist          = D2P(BO_SL_Dollar);   // price distance for SL level maths
      slIsFixedDollar = true;
   }
   else if(m1IsTrending && Riding_Structure_SL &&
      g_LQS_SwingHigh > 0.0 && g_LQS_SwingLow > 0.0 &&
      (isLQS || isBreakout))
   {
      double structSL;
      if(isBreakout)
         structSL = (dir == ORDER_TYPE_BUY)
                    ? NormalizeDouble(g_LQS_SwingHigh - D2P(BO_SL_Buffer), _Digits)
                    : NormalizeDouble(g_LQS_SwingLow  + D2P(BO_SL_Buffer), _Digits);
      else
         // LQS entries: SL at the swept level — reclaim = sweep was real
         structSL = (dir == ORDER_TYPE_BUY)
                    ? NormalizeDouble(g_LQS_SwingLow  - D2P(Riding_SL_Buffer), _Digits)
                    : NormalizeDouble(g_LQS_SwingHigh + D2P(Riding_SL_Buffer), _Digits);
      double structDist = (dir == ORDER_TYPE_BUY) ? (price - structSL) : (structSL - price);
      if(structDist > 0.0) { sl = structSL; slDist = structDist; }
      else sl = (dir == ORDER_TYPE_BUY) ? NormalizeDouble(price - slDist, _Digits)
                                        : NormalizeDouble(price + slDist, _Digits);
   }
   // BB-only entries: fixed dollar SL — predictable loss cap regardless of
   // band position or ATR. Overrides band-based SL when BB_SL_Dollar > 0.
   // LQS and BO entries are excluded (handled by their own SL paths above).
   else if(!isLQS && !isBreakout && BB_SL_Dollar > 0.0)
   {
      sl              = (dir == ORDER_TYPE_BUY)
                        ? NormalizeDouble(price - D2P(BB_SL_Dollar), _Digits)
                        : NormalizeDouble(price + D2P(BB_SL_Dollar), _Digits);
      slDist          = D2P(BB_SL_Dollar);   // price distance for SL level maths
      slIsFixedDollar = true;
   }
   // BB-only entries: SL at the band that triggered the entry.
   // Use whichever is tighter — band-based or ATR-based.
   // BUY: if price breaks back below BB_Lower the reversal has failed.
   // SELL: if price breaks back above BB_Upper the reversal has failed.
   // Note: breakout entries use the structure SL path above even when they
   // coincide with a BB touch — isBreakout takes priority over the band SL.
   else if(Riding_Structure_SL && !isLQS && !isBreakout && g_BB_Upper > 0.0 && g_BB_Lower > 0.0)
   {
      double bandSL  = (dir == ORDER_TYPE_BUY)
                       ? NormalizeDouble(g_BB_Lower - D2P(Riding_SL_Buffer), _Digits)
                       : NormalizeDouble(g_BB_Upper + D2P(Riding_SL_Buffer), _Digits);
      double atrSL   = (dir == ORDER_TYPE_BUY)
                       ? NormalizeDouble(price - slDist, _Digits)
                       : NormalizeDouble(price + slDist, _Digits);
      sl = (dir == ORDER_TYPE_BUY) ? MathMax(bandSL, atrSL) : MathMin(bandSL, atrSL);
      slDist = (dir == ORDER_TYPE_BUY) ? (price - sl) : (sl - price);
   }
   else
      sl = (dir == ORDER_TYPE_BUY) ? NormalizeDouble(price - slDist, _Digits)
                                   : NormalizeDouble(price + slDist, _Digits);

   if(SL_Max_Dollar > 0.0 && P2D(slDist) > SL_Max_Dollar)
   {
      Print("SKIP | SL too large: $", DoubleToString(P2D(slDist), 2),
            " > max $", DoubleToString(SL_Max_Dollar, 2),
            " | ATR=", DoubleToString(g_ATR, _Digits));
      return;
   }

   // BO uses its own trail; BB+LQS/BB uses LQS trail. Either way, if trail
   // is active for this entry type, suppress the fixed TP (trail manages exit).
   bool   trailActive = isBreakout ? (BO_Trail_Start > 0.0) : (LQS_Trail_Start > 0.0);
   // tpDist is always a price distance — convert fixed dollar TP via D2P().
   // ATR-based TP (g_ATR * factor) is already in price units.
   double tpDist = trailActive ? 0.0
                 : (LQS_TP_ATR_Factor > 0.0) ? g_ATR * LQS_TP_ATR_Factor
                 : D2P(LQS_TP_Fixed);

   double tp;
   if(dir == ORDER_TYPE_BUY)
      tp = (tpDist > 0.0) ? NormalizeDouble(price + tpDist, _Digits) : 0.0;
   else
      tp = (tpDist > 0.0) ? NormalizeDouble(price - tpDist, _Digits) : 0.0;

   string entryType = isBreakout ? "BO" : (isLQS ? "BB+LQS" : "BB");
   string comment   = entryType + (dir == ORDER_TYPE_BUY ? " BUY" : " SELL");
   SendSignalAlert(dir, price, sl, tp, slDist, tpDist, h1, l1, c1);
   CancelPendingOrders();
   bool ok;

   if(isBreakout)
   {
      // BO: market order — needs immediate execution to catch momentum
      ok = (dir == ORDER_TYPE_BUY)
           ? trade.Buy (LotSize, Symbol(), price, sl, tp, comment)
           : trade.Sell(LotSize, Symbol(), price, sl, tp, comment);

      if(ok)
      {
         LastEntry = TimeCurrent();

         // Correct SL/TP for slippage on BO market fills
         double fillPrice = trade.ResultPrice();
         if(fillPrice > 0.0)
         {
            double realSL = sl;
            double realTP = tp;
            if(slIsFixedDollar)
               realSL = (dir == ORDER_TYPE_BUY)
                        ? NormalizeDouble(fillPrice - slDist, _Digits)
                        : NormalizeDouble(fillPrice + slDist, _Digits);
            if(tpDist > 0.0)
               realTP = (dir == ORDER_TYPE_BUY)
                        ? NormalizeDouble(fillPrice + tpDist, _Digits)
                        : NormalizeDouble(fillPrice - tpDist, _Digits);
            ulong ticket = trade.ResultOrder();
            if(ticket > 0 && (realSL != sl || realTP != tp))
            {
               if(trade.PositionModify(ticket, realSL, realTP))
               {
                  string slMsg = (realSL != sl)
                                 ? " SL " + DoubleToString(sl,_Digits) + "->" + DoubleToString(realSL,_Digits)
                                 : "";
                  string tpMsg = (realTP != tp)
                                 ? " TP " + DoubleToString(tp,_Digits) + "->" + DoubleToString(realTP,_Digits)
                                 : "";
                  Print("Fill correction | fill=", DoubleToString(fillPrice,_Digits),
                        " slip=", DoubleToString(fillPrice - price, _Digits),
                        slMsg, tpMsg);
               }
               else
                  Print("Fill correction FAIL: ", trade.ResultRetcodeDescription());
            }
         }
         Print("OPEN BO ", (dir == ORDER_TYPE_BUY ? "BUY " : "SELL"),
               " | price=", DoubleToString(price, _Digits),
               " | SL=",    DoubleToString(sl, _Digits),
               " | SGT=",   TimeToString(GetSGT(), TIME_MINUTES));
      }
      else
         Print("BO Order FAIL [", trade.ResultRetcode(), "] ",
               trade.ResultRetcodeDescription());
   }
   else
   {
      // BB/LQS: limit order at band level — enters at the rejection point,
      // not after the bounce. Expires in 2 minutes if unfilled.
      double limitPrice = (dir == ORDER_TYPE_BUY) ? g_BB_Lower : g_BB_Upper;
      if(limitPrice <= 0.0) { Print("LIMIT skip — band price is 0"); return; }
      datetime expiry   = TimeCurrent() + 120;

      // Recalculate SL/TP anchored to limit price, not market price.
      // Fixed-dollar SL must be measured from where we actually fill.
      // Absolute SL levels (band, swing) are unchanged.
      double limitSL = sl;
      double limitTP = tp;
      if(slIsFixedDollar)
         limitSL = (dir == ORDER_TYPE_BUY)
                   ? NormalizeDouble(limitPrice - slDist, _Digits)
                   : NormalizeDouble(limitPrice + slDist, _Digits);
      if(tpDist > 0.0)
         limitTP = (dir == ORDER_TYPE_BUY)
                   ? NormalizeDouble(limitPrice + tpDist, _Digits)
                   : NormalizeDouble(limitPrice - tpDist, _Digits);

      ok = (dir == ORDER_TYPE_BUY)
           ? trade.BuyLimit (LotSize, limitPrice, Symbol(), limitSL, limitTP,
                             ORDER_TIME_SPECIFIED, expiry, comment)
           : trade.SellLimit(LotSize, limitPrice, Symbol(), limitSL, limitTP,
                             ORDER_TIME_SPECIFIED, expiry, comment);

      if(ok)
      {
         LastEntry = TimeCurrent();
         Print("LIMIT ", entryType, " ", (dir == ORDER_TYPE_BUY ? "BUY " : "SELL"),
               " @ ", DoubleToString(limitPrice, _Digits),
               " | SL=",  DoubleToString(limitSL, _Digits),
               " | exp=2min",
               " | SGT=", TimeToString(GetSGT(), TIME_MINUTES));
      }
      else
         Print("Limit Order FAIL [", trade.ResultRetcode(), "] ",
               trade.ResultRetcodeDescription());
   }
}

//===================================================================
//  ZONE LINES
//===================================================================
void SetHLine(string name, double price, color clr, string tooltip)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE,     STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,     1);
      ObjectSetInteger(0, name, OBJPROP_BACK,      true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
      ObjectSetString (0, name, OBJPROP_TOOLTIP,   tooltip);
   }
   else
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
}

void DrawZoneLines()
{
   if(g_LQS_SwingHigh > 0.0)
      SetHLine(LQS_LINE_SELL, g_LQS_SwingHigh, clrTomato,
               "LQS SELL zone — spike above + close below");
   if(g_LQS_SwingLow > 0.0)
      SetHLine(LQS_LINE_BUY,  g_LQS_SwingLow,  clrDodgerBlue,
               "LQS BUY zone — spike below + close above");
}

void DrawBBLines()
{
   if(g_BB_Upper  > 0.0) SetHLine(BB_LINE_UPPER,  g_BB_Upper,  clrOrangeRed,  "BB Upper Band");
   if(g_BB_Middle > 0.0) SetHLine(BB_LINE_MIDDLE, g_BB_Middle, clrGold,       "BB Middle (SMA)");
   if(g_BB_Lower  > 0.0) SetHLine(BB_LINE_LOWER,  g_BB_Lower,  clrCornflowerBlue, "BB Lower Band");
}

//===================================================================
//  INFO PANEL
//===================================================================
void DrawInfoPanel()
{
   DrawZoneLines();

   double ask   = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid   = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   datetime sgt = GetSGT();

   string atrOk = (g_ATR < ATR_Min_Filter)                            ? "[LOW - no trade]"
               : (ATR_Max_Filter > 0.0 && g_ATR > ATR_Max_Filter) ? "[HIGH - no trade]"
               :                                                      "[OK]";
   string sessStr = !EnableSessionFilter ? "DISABLED"
                  : (InSession() ? "OPEN  [OK]" : "CLOSED [waiting]");

   double distSell   = (g_LQS_SwingHigh > 0) ? g_LQS_SwingHigh - bid : 0.0;
   double distBuy    = (g_LQS_SwingLow  > 0) ? bid - g_LQS_SwingLow  : 0.0;
   double ctrSell    = g_M1PlusDI  - g_M1MinusDI;
   double ctrBuy     = g_M1MinusDI - g_M1PlusDI;

   string ctrStr = "";
   if(LQS_M1_DI_Max_Counter > 0.0)
   {
      if(ctrSell >= LQS_M1_DI_Max_Counter)
         ctrStr = "  [SELL BLK spread=" + DoubleToString(ctrSell, 1) + "]";
      else if(ctrBuy >= LQS_M1_DI_Max_Counter)
         ctrStr = "  [BUY BLK spread="  + DoubleToString(ctrBuy,  1) + "]";
      else
         ctrStr = "  [OK]";
   }
   else ctrStr = "  [DISABLED]";

   double bbWidth    = (g_BB_Upper > 0.0 && g_BB_Lower > 0.0) ? (g_BB_Upper - g_BB_Lower) : 0.0;
   bool   isSqueeze  = (g_ATR > 0.0 && bbWidth > 0.0 && bbWidth < g_ATR);
   bool   isTrending = (g_M1ADX >= M1_Ranging_Threshold);

   // ── BB Strategy Mode ────────────────────────────────────
   string bbMode, bbModeDesc, bbLongRule, bbShortRule;
   if(isSqueeze)
   {
      bbMode      = "★ SQUEEZE  [Breakout imminent — low volatility]";
      bbModeDesc  = "  Bands contracted below 1×ATR. A sharp move is likely.";
      bbLongRule  = "  LONG  : price breaks & closes ABOVE upper band";
      bbShortRule = "  SHORT : price breaks & closes BELOW lower band";
   }
   else if(isTrending)
   {
      bbMode      = "★ RIDING THE BANDS  [Trending — ADX " + DoubleToString(g_M1ADX,1) + "]";
      bbModeDesc  = "  Strong trend — band touches show strength, not reversal.";
      if(g_M1PlusDI >= g_M1MinusDI)
      {
         bbLongRule  = "  LONG  : dips to LOWER band = add to uptrend";
         bbShortRule = "  SHORT : wait for trend change before selling";
      }
      else
      {
         bbLongRule  = "  LONG  : wait for trend change before buying";
         bbShortRule = "  SHORT : rallies to UPPER band = add to downtrend";
      }
   }
   else
   {
      bbMode      = "★ MEAN REVERSION  [Ranging — ADX " + DoubleToString(g_M1ADX,1) + "]";
      bbModeDesc  = "  Price oscillates between bands. Trade the extremes.";
      bbLongRule  = "  LONG  : price touches/breaks LOWER band (oversold)";
      bbShortRule = "  SHORT : price touches/breaks UPPER band (overbought)";
   }

   // ── Price position relative to BB ────────────────────────
   string priceZone;
   if(g_BB_Upper > 0.0 && g_BB_Lower > 0.0 && g_BB_Middle > 0.0)
   {
      if(bid >= g_BB_Upper)
         priceZone = "ABOVE UPPER BAND  [Overbought → SELL signal]";
      else if(bid >= g_BB_Middle)
         priceZone = "Upper half  [" + (isTrending && g_M1PlusDI >= g_M1MinusDI
                      ? "Uptrend — hold longs"
                      : "Bearish bias — watch SELL") + "]";
      else if(bid > g_BB_Lower)
         priceZone = "Lower half  [" + (isTrending && g_M1MinusDI > g_M1PlusDI
                      ? "Downtrend — hold shorts"
                      : "Bullish bias — watch BUY") + "]";
      else
         priceZone = "BELOW LOWER BAND  [Oversold → BUY signal]";
   }
   else priceZone = "---";

   // ── BB width status ───────────────────────────────────
   string bbWidthStatus;
   if(BB_Width_Min_ATR > 0.0 && bbWidth > 0.0 && bbWidth < g_ATR * BB_Width_Min_ATR)
      bbWidthStatus = "[SQUEEZE - entry blocked]";
   else if(BB_Width_Max_ATR > 0.0 && bbWidth > 0.0 && bbWidth > g_ATR * BB_Width_Max_ATR)
      bbWidthStatus = "[EXPANDED - entry blocked]";
   else
      bbWidthStatus = "[OK]";

   string info =
      "╔══ PROJECT BB BREAKOUT  v3.2 (GBPUSD)  |  LQS + BB ══╗\n"
      "  Symbol  : " + Symbol()
                     + "   Magic : " + IntegerToString(MagicNumber)        + "\n"
      "  Bid/Ask : " + DoubleToString(bid, _Digits)
                     + " / " + DoubleToString(ask, _Digits)               + "\n"
      "  SGT     : " + TimeToString(sgt, TIME_MINUTES)
                     + "  UTC+" + IntegerToString(BrokerGMTOffset())
                     + "   " + sessStr                                     + "\n"
      "══════════════════════════════════════════════════\n"
      "  BOLLINGER BANDS  (" + IntegerToString(BB_Period) + " SMA, "
                     + DoubleToString(BB_Deviation, 1) + " StdDev)\n"
      "  Upper  : " + DoubleToString(g_BB_Upper,  _Digits) + "  ← SELL extreme" + "\n"
      "  Middle : " + DoubleToString(g_BB_Middle, _Digits) + "  ← " + IntegerToString(BB_Period) + "-bar SMA (trend baseline)" + "\n"
      "  Lower  : " + DoubleToString(g_BB_Lower,  _Digits) + "  ← BUY  extreme" + "\n"
      "  Width  : " + DoubleToString(P2D(bbWidth), 2) + " ($)"
                     + "  ATR=" + DoubleToString(g_ATR, _Digits)
                     + "  " + bbWidthStatus                                + "\n"
      "──────────────────────────────────────────────────\n"
      "  BB STRATEGY MODE\n"
      "  " + bbMode                                                        + "\n"
      + bbModeDesc                                                         + "\n"
      + bbLongRule                                                         + "\n"
      + bbShortRule                                                        + "\n"
      "──────────────────────────────────────────────────\n"
      "  CURRENT PRICE ZONE\n"
      "  " + priceZone                                                     + "\n"
      "──────────────────────────────────────────────────\n"
      "  LQS ZONES  (Lookback: " + IntegerToString(LQS_Lookback) + " bars)\n"
      "  SELL zone : " + DoubleToString(g_LQS_SwingHigh, _Digits)
                     + "  ($+" + DoubleToString(P2D(distSell), 2) + " away)"  + "\n"
      "    → Spike ABOVE swing + close BELOW + touch BB upper = SELL\n"
      "  BUY  zone : " + DoubleToString(g_LQS_SwingLow, _Digits)
                     + "  ($-" + DoubleToString(P2D(distBuy), 2) + " away)"   + "\n"
      "    → Spike BELOW swing + close ABOVE + touch BB lower = BUY\n"
      "  BB Touch  : " + (BB_Require_Band_Touch   ? "REQUIRED" : "OFF")
                     + "   Midline filter : " + (BB_Midline_Trend_Filter ? "ON" : "OFF")
                     + "   Zone filter : " + (BB_Close_Zone_Filter ? "ON" : "OFF") + "\n"
      "──────────────────────────────────────────────────\n"
      "  TREND / MOMENTUM\n"
      "  ATR(" + IntegerToString(ATR_Period) + ")  : " + DoubleToString(g_ATR, _Digits)
                     + "  SL=" + (isTrending
                        ? DoubleToString(SL_ATR_Factor,1) + "×ATR=$"
                          + DoubleToString(P2D(g_ATR*SL_ATR_Factor),2) + " [TREND]"
                        : DoubleToString(SL_ATR_Ranging_Mult,1) + "×ATR=$"
                          + DoubleToString(P2D(g_ATR*SL_ATR_Ranging_Mult),2) + " [RANGING]"
                          + (LQS_Trend_Only ? " BLOCKED" : ""))
                     + (SL_Max_Dollar > 0.0
                        ? "  cap=$" + DoubleToString(SL_Max_Dollar,2)
                          + (P2D(isTrending ? g_ATR*SL_ATR_Factor : g_ATR*SL_ATR_Ranging_Mult) > SL_Max_Dollar
                             ? " [SKIP]" : " [OK]")
                        : "")                                              + "\n"
      "  M1 ADX   : " + DoubleToString(g_M1ADX, 1)
                     + "  M1 DI: +" + DoubleToString(g_M1PlusDI, 1)
                     + " / -"       + DoubleToString(g_M1MinusDI, 1)     + "\n"
      "  M5 DI    : +" + DoubleToString(g_M5PlusDI, 1)
                     + " / -"       + DoubleToString(g_M5MinusDI, 1)
                     + (LQS_HTF_DI_Align
                        ? (g_M5PlusDI > g_M5MinusDI ? "  [M5 BULL: SELL blocked]"
                          : g_M5MinusDI > g_M5PlusDI ? "  [M5 BEAR: BUY blocked]"
                          :                             "  [M5 NEUTRAL]")
                        : "  [HTF filter OFF]")                           + "\n"
      "  RSI(14)  : " + DoubleToString(g_RSI, 1)
                     + (BO_RSI_Filter
                        ? (g_RSI < BO_RSI_Oversold  ? "  [BO SELL BLOCKED — oversold]"
                          : g_RSI > BO_RSI_Overbought ? "  [BO BUY BLOCKED — overbought]"
                          :                              "  [BO OK]")
                        : "  [BO RSI filter OFF]")                        + "\n"
      "──────────────────────────────────────────────────\n"
      "  Exit     : " + (LQS_Trail_Start > 0.0
                          ? "Trail +$" + DoubleToString(LQS_Trail_Start, 2)
                            + "  step=$" + DoubleToString(LQS_Trail_Step, 2)
                            + (LQS_BE_Trigger > 0.0
                               ? "  BE=$" + DoubleToString(LQS_BE_Trigger, 2)
                                 + "+buf$" + DoubleToString(LQS_BE_Buffer, 2)
                               : "")
                          : (LQS_TP_ATR_Factor > 0.0
                             ? DoubleToString(LQS_TP_ATR_Factor,2) + "×ATR=$"
                               + DoubleToString(g_ATR*LQS_TP_ATR_Factor,2) + " [dynamic]"
                             : "$" + DoubleToString(LQS_TP_Fixed,2) + " [fixed]")) + "\n"
      "  Positions: " + IntegerToString(CountMyPositions())
                     + "   Today P/L: $" + DoubleToString(TodayProfit, 2) + "\n"
      "  Last Entry: " + (LastEntry > 0
                          ? TimeToString(LastEntry, TIME_DATE|TIME_SECONDS)
                          : "---")                                         + "\n"
      "╚══════════════════════════════════════════════════╝";

   Comment(info);
}

//===================================================================
//  MAIN LOOP
//===================================================================
void OnTick()
{
   g_ATR      = GetATR();
   RefreshM1ADX();
   RefreshM5DI();
   RefreshBB();
   RefreshRSI();
   g_IsNewBar = IsNewBar();

   if(g_IsNewBar)
      UpdateTodayProfit();

   RefreshLQSLevels();
   CheckZoneApproach();

   ManageTrades();
   TryLQSTrade();
   DrawBBLines();
   DrawInfoPanel();
}
//+------------------------------------------------------------------+