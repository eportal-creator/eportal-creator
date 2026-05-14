//+------------------------------------------------------------------+
//|                    PROJECT BB BREAKOUT  (MT5 v3.1)                        |
//|  LQS Liquidity Sweep + Bollinger Band Confluence EA             |
//|  Based on LQS Zone Scalper v1.191                               |
//|                                                                  |
//| v3.1: Alternative A — BO retracement limit entry                 |
//|  BO BUY  now places BuyLimit  at the broken swing high (the      |
//|  level that was breached). Price must retest the breakout level  |
//|  before entry fills. Limit expires in 2 minutes if unfilled.    |
//|  BO SELL now places SellLimit at the broken swing low.          |
//|  Rationale: the two losing BO BUY trades on 07/08 May were      |
//|  stopped within 3–15 seconds by normal M1 noise — BO_SL_Dollar  |
//|  $1.00 = 0.49×ATR(2.03), inside the routine tick range.         |
//|  Direction was correct (price recovered to 4701+) but entry at  |
//|  momentum peak gave no room. Waiting for a retest of the broken  |
//|  level provides a structurally superior entry with a tighter SL  |
//|  anchored to the level, and natural confirmation that the level  |
//|  is holding as support/resistance.                               |
//|  SL for limit BO entries is recalculated from the limit price    |
//|  (same as BB/LQS limit logic in v3.0).                          |
//|  Unified BE/trail parameters applied to BOTH BO and BB entries:  |
//|  BE Trigger $0.25, BE Buffer $0.10, Trail Start $0.45,          |
//|  Trail Step $0.30 — tighter and more consistent across types.   |
//|  New BO-specific inputs: BO_BE_Trigger, BO_BE_Buffer.           |
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
//|  BO only: tight trail (BO_Trail_Start=0.20, BO_Trail_Step=0.30)  |
//|    — follows momentum closely, exits quickly if move stalls.      |
//|    Fixed SL (BO_SL_Dollar) remains backstop.                     |
//|  ManageTrades() reads position comment to apply correct trail.   |
//|                                                                  |
//| v2.5: Trail tuned above M1 noise level                           |
//|  Trail_Start 0.01→0.30: trail waits for $0.30 profit before      |
//|  activating — above normal XAUUSD M1 tick noise ($0.10–0.20).    |
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
#property version   "3.100"
#property description "Project BB Breakout | LQS + Breakout Continuation | XAUUSD M1 v3.1"

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
input int    MagicNumber         = 3535;
input double ExpireHours         = 0.5;
input int    CooldownMinutes     = 2;

input group "=== ATR Settings ==="
input int    ATR_Period          = 14;
input double ATR_Min_Filter      = 0.0;
input double ATR_Max_Filter      = 0.0;
input double SL_ATR_Factor       = 1.5;
input double SL_ATR_Ranging_Mult = 2.0;
input double M1_Ranging_Threshold = 25.0;
input double SL_Max_Dollar       = 5.0;
input bool   Riding_Structure_SL  = true;
input double Riding_SL_Buffer     = 0.20;
input group "=== LQS Trail / Breakeven (BB+LQS and BB entries) ==="
input double LQS_BE_Trigger   = 0.25;
input double LQS_BE_Buffer    = 0.10;
input double LQS_Trail_Start  = 0.45;
input double LQS_Trail_Step   = 0.30;

input group "=== LQS Settings ==="
input int    LQS_Lookback        = 20;
input double LQS_Wick_Min_ATR    = 0.0;
input double LQS_DI_Spread_Filter = 30.0;
input double LQS_M1_DI_Max_Counter  = 0.0;
input bool   LQS_Trend_Only         = false;
input double LQS_CloseBack_Min_ATR  = 0.0;
input bool   LQS_Body_Direction     = false;
input bool   LQS_M1_DI_Align        = true;
input double LQS_Bar_Range_Min_ATR  = 0.0;
input double LQS_Bar_Range_Max_ATR  = 3.0;
input bool   LQS_HTF_DI_Align       = true;
input double LQS_TP_ATR_Factor   = 0.0;
input double LQS_TP_Fixed        = 0.75;

input group "=== Bollinger Band Settings ==="
input int    BB_Period              = 20;
input double BB_Deviation           = 1.5;
input bool   BB_Require_Band_Touch  = true;
input bool   BB_Band_Entry          = true;
input bool   BB_Midline_Trend_Filter = false;
input bool   BB_Close_Zone_Filter   = true;
input double BB_SL_Dollar           = 1.00;

input group "=== Breakout Settings ==="
input bool   BO_HTF_DI_Required     = true;
input int    BO_Max_Run_Bars        = 5;
input double BO_SL_Buffer           = 0.60;
input double BO_SL_Dollar           = 1.00;
input double BO_BE_Trigger          = 0.25;
input double BO_BE_Buffer           = 0.10;
input double BO_Trail_Start         = 0.45;
input double BO_Trail_Step          = 0.30;
input bool   BO_RSI_Filter          = false;
input double BO_RSI_Oversold        = 35.0;
input double BO_RSI_Overbought      = 65.0;
input double BB_Width_Min_ATR       = 0.0;
input double BB_Width_Max_ATR       = 0.0;

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
   Print("Project BB Breakout v3.1 | Symbol=", Symbol(),
         " | Magic=", MagicNumber,
         " | Exit=", exitMode,
         " | HTF_DI=", LQS_HTF_DI_Align,
         " | SL_Max=$", SL_Max_Dollar,
         " | BE_Buf=$", LQS_BE_Buffer,
         " | CloseZone=", BB_Close_Zone_Filter,
         " | DI_Spread=", LQS_DI_Spread_Filter,
         " | RidingDIEnforce=ON",
         " | RangingThresh=ADX<", M1_Ranging_Threshold,
         " | BO_BE=$", BO_BE_Trigger,
         " | BO_Trail=$", BO_Trail_Start);

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
   if(today != TodayDate) { TodayProfit = 0.0; TodayDate = today; }

   datetime dayStart = StartOfDay(TimeCurrent());
   HistorySelect(dayStart, TimeCurrent());
   double profit = 0.0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != Symbol()) continue;
      if((int)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
   }
   TodayProfit = profit;
}

//===================================================================
//  NOTIFICATIONS
//===================================================================
string M1Direction()
{
   if(g_M1ADX < M1_Ranging_Threshold) return "M1:RANGING";
   return (g_M1PlusDI >= g_M1MinusDI) ? "M1:UP" : "M1:DOWN";
}

string BBMode()
{
   double bbWidth = (g_BB_Upper > 0.0 && g_BB_Lower > 0.0) ? g_BB_Upper - g_BB_Lower : 0.0;
   if(g_ATR > 0.0 && bbWidth > 0.0 && bbWidth < g_ATR) return "BB:SQUEEZE";
   if(g_M1ADX >= M1_Ranging_Threshold) return "BB:RIDING";
   return "BB:MEANREV";
}

void SendSignalAlert(ENUM_ORDER_TYPE dir, double entryPrice,
                     double sl, double tp,
                     double slDist, double tpDist,
                     double h1, double l1, double c1)
{
   if(!Enable_Notify) return;
   string side    = (dir == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   string bbBand  = (dir == ORDER_TYPE_BUY)
                    ? "BBL=" + DoubleToString(g_BB_Lower, 2)
                    : "BBU=" + DoubleToString(g_BB_Upper, 2);
   string sweepInfo = (dir == ORDER_TYPE_BUY)
                      ? "SwL=" + DoubleToString(g_LQS_SwingLow,  2)
                        + " l1=" + DoubleToString(l1, 2)
                        + " c1=" + DoubleToString(c1, 2)
                      : "SwH=" + DoubleToString(g_LQS_SwingHigh, 2)
                        + " h1=" + DoubleToString(h1, 2)
                        + " c1=" + DoubleToString(c1, 2);
   string tpStr   = (tpDist > 0.0)
                    ? DoubleToString(tp, 2) + "  ($" + DoubleToString(tpDist, 2) + ")"
                    : "Trail $" + DoubleToString(LQS_Trail_Start, 2)
                      + " step $" + DoubleToString(LQS_Trail_Step, 2);
   string msg =
      "[BB+LQS] " + side + " SIGNAL  XAUUSD\n"
      + "Entry : " + DoubleToString(entryPrice, 2) + "\n"
      + "SL    : " + DoubleToString(sl, 2)
      + "  ($" + DoubleToString(slDist, 2) + ")\n"
      + "TP    : " + tpStr + "\n"
      + bbBand + "  |  " + sweepInfo + "\n"
      + M1Direction() + "  ATR=" + DoubleToString(g_ATR, 2)
      + "  " + BBMode()
      + "  SGT=" + TimeToString(GetSGT(), TIME_MINUTES);
   SendNotification(msg);
}

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
   string swing   = nearSell ? DoubleToString(g_LQS_SwingHigh, 2) : DoubleToString(g_LQS_SwingLow, 2);
   string bbLevel = nearSell ? DoubleToString(g_BB_Upper, 2)       : DoubleToString(g_BB_Lower, 2);
   double dSwing  = nearSell ? distSwingH : distSwingL;
   double dBB     = nearSell ? distBBUp   : distBBLow;
   string action  = nearSell
                    ? "Spike ABOVE " + swing + " + touch BB " + bbLevel + " then close below"
                    : "Spike BELOW " + swing + " + touch BB " + bbLevel + " then close above";
   string blocked = (m1Uptrend && nearSell)  ? "  [SELL BLOCKED — uptrend]"
                  : (m1Downtrend && nearBuy) ? "  [BUY BLOCKED — downtrend]"
                  : "";

   string msg =
      "[BB+LQS] " + side + " ZONE APPROACH  XAUUSD\n"
      + "Price     : " + DoubleToString(price, 2) + "\n"
      + "Swing " + (nearSell ? "High" : "Low ") + " : " + swing
      + "  ($" + DoubleToString(dSwing, 2) + " away)\n"
      + "BB " + (nearSell ? "Upper" : "Lower") + "   : " + bbLevel
      + "  ($" + DoubleToString(dBB, 2) + " away)\n"
      + "Watch for : " + action + " → " + side + blocked + "\n"
      + M1Direction() + "  ATR=" + DoubleToString(g_ATR, 2) + "\n"
      + BBMode()
      + "  SGT=" + TimeToString(GetSGT(), TIME_MINUTES);

   SendNotification(msg);
   g_LastZoneAlert = TimeCurrent();
}

void OnTimer()
{
   if(!Enable_Notify) return;
   double price    = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double distSell = (g_LQS_SwingHigh > 0) ? g_LQS_SwingHigh - price : 0.0;
   double distBuy  = (g_LQS_SwingLow  > 0) ? price - g_LQS_SwingLow  : 0.0;
   double bbWidth  = (g_BB_Upper > 0.0 && g_BB_Lower > 0.0) ? g_BB_Upper - g_BB_Lower : 0.0;
   string msg =
      "[BB+LQS] XAUUSD " + DoubleToString(price, 2)
      + "  " + M1Direction() + "  " + BBMode() + "\n"
      + "BB(" + IntegerToString(BB_Period) + "," + DoubleToString(BB_Deviation,1) + ")"
      + "  U=" + DoubleToString(g_BB_Upper,  2)
      + "  M=" + DoubleToString(g_BB_Middle, 2)
      + "  L=" + DoubleToString(g_BB_Lower,  2)
      + "  W=$" + DoubleToString(bbWidth, 2) + "\n"
      + "SELL zone: SwingH " + DoubleToString(g_LQS_SwingHigh, 2)
      + "  ($+" + DoubleToString(distSell, 1) + ")  BBU " + DoubleToString(g_BB_Upper, 2) + "\n"
      + "BUY  zone: SwingL " + DoubleToString(g_LQS_SwingLow, 2)
      + "  ($-" + DoubleToString(distBuy,  1) + ")  BBL " + DoubleToString(g_BB_Lower, 2) + "\n"
      + "ATR=" + DoubleToString(g_ATR, 2)
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

      double profit = (ptype == POSITION_TYPE_BUY) ? (bid - op) : (op - ask);
      double newSL  = sl;

      string posComment  = PositionGetString(POSITION_COMMENT);
      bool   posIsBO     = (StringFind(posComment, "BO") == 0);
      double trailStart  = posIsBO ? BO_Trail_Start  : LQS_Trail_Start;
      double trailStep   = posIsBO ? BO_Trail_Step   : LQS_Trail_Step;

      if(trailStart > 0.0 && profit >= trailStart)
      {
         double trailSL = (ptype == POSITION_TYPE_BUY)
                          ? NormalizeDouble(bid - trailStep, _Digits)
                          : NormalizeDouble(ask + trailStep, _Digits);
         bool improve = (ptype == POSITION_TYPE_BUY)
                        ? (trailSL > newSL + _Point)
                        : (newSL == 0.0 || trailSL < newSL - _Point);
         if(improve) newSL = trailSL;
      }
      else if(posIsBO && BO_BE_Trigger > 0.0 && profit >= BO_BE_Trigger)
      {
         double beSL  = (ptype == POSITION_TYPE_BUY)
                        ? NormalizeDouble(op + BO_BE_Buffer, _Digits)
                        : NormalizeDouble(op - BO_BE_Buffer, _Digits);
         bool improve = (ptype == POSITION_TYPE_BUY)
                        ? (beSL > newSL + _Point)
                        : (newSL == 0.0 || beSL < newSL - _Point);
         if(improve) newSL = beSL;
      }
      else if(!posIsBO && LQS_BE_Trigger > 0.0 && profit >= LQS_BE_Trigger)
      {
         double beSL  = (ptype == POSITION_TYPE_BUY)
                        ? NormalizeDouble(op + LQS_BE_Buffer, _Digits)
                        : NormalizeDouble(op - LQS_BE_Buffer, _Digits);
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

   bool lqsSell = false, lqsBuy = false;
   if(g_LQS_SwingHigh > 0.0 && g_LQS_SwingLow > 0.0)
   {
      lqsSell = (h1 > g_LQS_SwingHigh) && (c1 < g_LQS_SwingHigh);
      lqsBuy  = (l1 < g_LQS_SwingLow)  && (c1 > g_LQS_SwingLow);
   }

   bool bbSell = BB_Band_Entry && g_BB_Upper > 0.0 && (h1 >= g_BB_Upper) && (c1 < g_BB_Upper);
   bool bbBuy  = BB_Band_Entry && g_BB_Lower > 0.0 && (l1 <= g_BB_Lower) && (c1 > g_BB_Lower);

   bool boBuy = false, boSell = false;
   bool m1IsTrendingEntry = (g_M1ADX >= M1_Ranging_Threshold);
   if(m1IsTrendingEntry && g_LQS_SwingHigh > 0.0 && g_LQS_SwingLow > 0.0)
   {
      boBuy  = (g_M1PlusDI  > g_M1MinusDI) && (g_M1PlusDI2  > g_M1MinusDI2)
               && (h1 > g_LQS_SwingHigh) && (c1 >= g_LQS_SwingHigh);
      boSell = (g_M1MinusDI > g_M1PlusDI)  && (g_M1MinusDI2 > g_M1PlusDI2)
               && (l1 < g_LQS_SwingLow)  && (c1 <= g_LQS_SwingLow);
   }

   bool isSell     = lqsSell || bbSell || boSell;
   bool isBuy      = lqsBuy  || bbBuy  || boBuy;
   bool isLQS      = lqsSell || lqsBuy;
   bool isBreakout = boBuy   || boSell;
   if(!isSell && !isBuy) return;
   if(isSell && isBuy) return;

   ENUM_ORDER_TYPE dir;
   double          price;
   if(isSell) { dir = ORDER_TYPE_SELL; price = SymbolInfoDouble(Symbol(), SYMBOL_BID); }
   else       { dir = ORDER_TYPE_BUY;  price = SymbolInfoDouble(Symbol(), SYMBOL_ASK); }

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
      if(BB_Require_Band_Touch && g_BB_Upper > 0.0 && g_BB_Lower > 0.0)
      {
         if(lqsSell && h1 < g_BB_Upper) return;
         if(lqsBuy  && l1 > g_BB_Lower) return;
      }
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

   if(LQS_Body_Direction)
   {
      double midPoint = (h1 + l1) * 0.5;
      if(isSell && c1 > midPoint) return;
      if(isBuy  && c1 < midPoint) return;
   }

   bool m1IsTrending = (g_M1ADX >= M1_Ranging_Threshold);
   if(m1IsTrending || LQS_M1_DI_Align)
   {
      if(isSell && g_M1PlusDI  > g_M1MinusDI) return;
      if(isBuy  && g_M1MinusDI > g_M1PlusDI)  return;
   }

   if(LQS_HTF_DI_Align && !m1IsTrending)
   {
      if(isSell && g_M5PlusDI  > g_M5MinusDI) return;
      if(isBuy  && g_M5MinusDI > g_M5PlusDI)  return;
   }

   if(BO_HTF_DI_Required && isBreakout)
   {
      if(isSell && g_M5PlusDI  > g_M5MinusDI) return;
      if(isBuy  && g_M5MinusDI > g_M5PlusDI)  return;
   }

   if(BO_Max_Run_Bars > 0 && isBreakout)
   {
      int runCount = 0;
      for(int k = 1; k <= BO_Max_Run_Bars; k++)
      {
         double o = iOpen(Symbol(),  PERIOD_M1, k);
         double c = iClose(Symbol(), PERIOD_M1, k);
         if(isSell && c < o) runCount++;
         else if(isBuy  && c > o) runCount++;
      }
      if(runCount >= BO_Max_Run_Bars - 1) return;
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

   if(BB_Close_Zone_Filter && g_BB_Middle > 0.0 && !isBreakout)
   {
      if(isSell && c1 < g_BB_Middle) return;
      if(isBuy  && c1 > g_BB_Middle) return;
   }

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

   if(LQS_Trend_Only && !m1IsRanging)
   {
      if(g_M1PlusDI > g_M1MinusDI && dir == ORDER_TYPE_SELL) return;
      if(g_M1MinusDI > g_M1PlusDI && dir == ORDER_TYPE_BUY)  return;
   }

   double slMult        = m1IsRanging ? SL_ATR_Ranging_Mult : SL_ATR_Factor;
   double slDist        = g_ATR * slMult;
   double sl;
   bool   slIsFixedDollar = false;

   if(isBreakout && BO_SL_Dollar > 0.0)
   {
      slDist          = BO_SL_Dollar;
      slIsFixedDollar = true;
      sl = (dir == ORDER_TYPE_BUY)
           ? NormalizeDouble(price - BO_SL_Dollar, _Digits)
           : NormalizeDouble(price + BO_SL_Dollar, _Digits);
   }
   else if(m1IsTrending && Riding_Structure_SL &&
      g_LQS_SwingHigh > 0.0 && g_LQS_SwingLow > 0.0 &&
      (isLQS || isBreakout))
   {
      double structSL;
      if(isBreakout)
         structSL = (dir == ORDER_TYPE_BUY)
                    ? NormalizeDouble(g_LQS_SwingHigh - BO_SL_Buffer, _Digits)
                    : NormalizeDouble(g_LQS_SwingLow  + BO_SL_Buffer, _Digits);
      else
         structSL = (dir == ORDER_TYPE_BUY)
                    ? NormalizeDouble(g_LQS_SwingLow  - Riding_SL_Buffer, _Digits)
                    : NormalizeDouble(g_LQS_SwingHigh + Riding_SL_Buffer, _Digits);
      double structDist = (dir == ORDER_TYPE_BUY) ? (price - structSL) : (structSL - price);
      if(structDist > 0.0) { sl = structSL; slDist = structDist; }
      else sl = (dir == ORDER_TYPE_BUY) ? NormalizeDouble(price - slDist, _Digits)
                                        : NormalizeDouble(price + slDist, _Digits);
   }
   else if(!isLQS && !isBreakout && BB_SL_Dollar > 0.0)
   {
      sl              = (dir == ORDER_TYPE_BUY)
                        ? NormalizeDouble(price - BB_SL_Dollar, _Digits)
                        : NormalizeDouble(price + BB_SL_Dollar, _Digits);
      slDist          = BB_SL_Dollar;
      slIsFixedDollar = true;
   }
   else if(Riding_Structure_SL && !isLQS && !isBreakout && g_BB_Upper > 0.0 && g_BB_Lower > 0.0)
   {
      double bandSL  = (dir == ORDER_TYPE_BUY)
                       ? NormalizeDouble(g_BB_Lower - Riding_SL_Buffer, _Digits)
                       : NormalizeDouble(g_BB_Upper + Riding_SL_Buffer, _Digits);
      double atrSL   = (dir == ORDER_TYPE_BUY)
                       ? NormalizeDouble(price - slDist, _Digits)
                       : NormalizeDouble(price + slDist, _Digits);
      sl = (dir == ORDER_TYPE_BUY) ? MathMax(bandSL, atrSL) : MathMin(bandSL, atrSL);
      slDist = (dir == ORDER_TYPE_BUY) ? (price - sl) : (sl - price);
   }
   else
      sl = (dir == ORDER_TYPE_BUY) ? NormalizeDouble(price - slDist, _Digits)
                                   : NormalizeDouble(price + slDist, _Digits);

   if(SL_Max_Dollar > 0.0 && slDist > SL_Max_Dollar)
   {
      Print("SKIP | SL too large: $", DoubleToString(slDist, 2),
            " > max $", DoubleToString(SL_Max_Dollar, 2),
            " | ATR=", DoubleToString(g_ATR, 2));
      return;
   }

   bool   trailActive = isBreakout ? (BO_Trail_Start > 0.0) : (LQS_Trail_Start > 0.0);
   double tpDist = trailActive ? 0.0
                 : (LQS_TP_ATR_Factor > 0.0) ? g_ATR * LQS_TP_ATR_Factor
                 : LQS_TP_Fixed;

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
      double limitPrice = (dir == ORDER_TYPE_BUY) ? g_LQS_SwingHigh : g_LQS_SwingLow;
      if(limitPrice <= 0.0) { Print("BO LIMIT skip — swing level is 0"); return; }
      datetime expiry = TimeCurrent() + 120;

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
         Print("LIMIT BO ", (dir == ORDER_TYPE_BUY ? "BUY " : "SELL"),
               " @ ", DoubleToString(limitPrice, _Digits),
               " | SL=",  DoubleToString(limitSL, _Digits),
               " | exp=2min",
               " | SGT=", TimeToString(GetSGT(), TIME_MINUTES));
      }
      else
         Print("BO Limit Order FAIL [", trade.ResultRetcode(), "] ",
               trade.ResultRetcodeDescription());
   }
   else
   {
      double limitPrice = (dir == ORDER_TYPE_BUY) ? g_BB_Lower : g_BB_Upper;
      if(limitPrice <= 0.0) { Print("LIMIT skip — band price is 0"); return; }
      datetime expiry   = TimeCurrent() + 120;

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

   string bbWidthStatus;
   if(BB_Width_Min_ATR > 0.0 && bbWidth > 0.0 && bbWidth < g_ATR * BB_Width_Min_ATR)
      bbWidthStatus = "[SQUEEZE - entry blocked]";
   else if(BB_Width_Max_ATR > 0.0 && bbWidth > 0.0 && bbWidth > g_ATR * BB_Width_Max_ATR)
      bbWidthStatus = "[EXPANDED - entry blocked]";
   else
      bbWidthStatus = "[OK]";

   string info =
      "╔══ PROJECT BB BREAKOUT  v3.1  |  LQS + Bollinger Bands ══╗\n"
      "  Symbol  : " + Symbol()
                     + "   Magic : " + IntegerToString(MagicNumber)        + "\n"
      "  Bid/Ask : " + DoubleToString(bid, _Digits)
                     + " / " + DoubleToString(ask, _Digits)               + "\n"
      "  SGT     : " + TimeToString(sgt, TIME_MINUTES)
                     + "  UTC+" + IntegerToString(BrokerGMTOffset())
                     + "   " + sessStr                                     + "\n"
      "════════════════════════════════════════════════\n"
      "  BOLLINGER BANDS  (" + IntegerToString(BB_Period) + " SMA, "
                     + DoubleToString(BB_Deviation, 1) + " StdDev)\n"
      "  Upper  : " + DoubleToString(g_BB_Upper,  2) + "  ← SELL extreme" + "\n"
      "  Middle : " + DoubleToString(g_BB_Middle, 2) + "  ← " + IntegerToString(BB_Period) + "-bar SMA (trend baseline)" + "\n"
      "  Lower  : " + DoubleToString(g_BB_Lower,  2) + "  ← BUY  extreme" + "\n"
      "  Width  : " + DoubleToString(bbWidth, 2)
                     + "  ATR=" + DoubleToString(g_ATR, 2)
                     + "  " + bbWidthStatus                                + "\n"
      "────────────────────────────────────────────────\n"
      "  BB STRATEGY MODE\n"
      "  " + bbMode                                                        + "\n"
      + bbModeDesc                                                         + "\n"
      + bbLongRule                                                         + "\n"
      + bbShortRule                                                        + "\n"
      "────────────────────────────────────────────────\n"
      "  CURRENT PRICE ZONE\n"
      "  " + priceZone                                                     + "\n"
      "────────────────────────────────────────────────\n"
      "  LQS ZONES  (Lookback: " + IntegerToString(LQS_Lookback) + " bars)\n"
      "  SELL zone : " + DoubleToString(g_LQS_SwingHigh, 2)
                     + "  ($+" + DoubleToString(distSell, 1) + " away)"  + "\n"
      "    → Spike ABOVE swing + close BELOW + touch BB upper = SELL\n"
      "  BUY  zone : " + DoubleToString(g_LQS_SwingLow, 2)
                     + "  ($-" + DoubleToString(distBuy, 1) + " away)"   + "\n"
      "    → Spike BELOW swing + close ABOVE + touch BB lower = BUY\n"
      "  BB Touch  : " + (BB_Require_Band_Touch   ? "REQUIRED" : "OFF")
                     + "   Midline filter : " + (BB_Midline_Trend_Filter ? "ON" : "OFF")
                     + "   Zone filter : " + (BB_Close_Zone_Filter ? "ON" : "OFF") + "\n"
      "────────────────────────────────────────────────\n"
      "  TREND / MOMENTUM\n"
      "  ATR(" + IntegerToString(ATR_Period) + ")  : " + DoubleToString(g_ATR, 2)
                     + "  SL=" + (isTrending
                        ? DoubleToString(SL_ATR_Factor,1) + "×ATR=$"
                          + DoubleToString(g_ATR*SL_ATR_Factor,2) + " [TREND]"
                        : DoubleToString(SL_ATR_Ranging_Mult,1) + "×ATR=$"
                          + DoubleToString(g_ATR*SL_ATR_Ranging_Mult,2) + " [RANGING]"
                          + (LQS_Trend_Only ? " BLOCKED" : ""))
                     + (SL_Max_Dollar > 0.0
                        ? "  cap=$" + DoubleToString(SL_Max_Dollar,2)
                          + ((isTrending   ? g_ATR*SL_ATR_Factor       : g_ATR*SL_ATR_Ranging_Mult) > SL_Max_Dollar
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
      "────────────────────────────────────────────────\n"
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
      "  BO Exit  : Trail +$" + DoubleToString(BO_Trail_Start, 2)
                     + "  step=$" + DoubleToString(BO_Trail_Step, 2)
                     + (BO_BE_Trigger > 0.0
                        ? "  BE=$" + DoubleToString(BO_BE_Trigger, 2)
                          + "+buf$" + DoubleToString(BO_BE_Buffer, 2)
                        : "")                                              + "\n"
      "  Positions: " + IntegerToString(CountMyPositions())
                     + "   Today P/L: $" + DoubleToString(TodayProfit, 2) + "\n"
      "  Last Entry: " + (LastEntry > 0
                          ? TimeToString(LastEntry, TIME_DATE|TIME_SECONDS)
                          : "---")                                         + "\n"
      "╚════════════════════════════════════════════════╝";

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
