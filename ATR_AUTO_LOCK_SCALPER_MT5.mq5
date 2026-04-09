//+------------------------------------------------------------------+
//|                    PROJECT ATR  (MT5 v2.8)                       |
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
//+------------------------------------------------------------------+
#property copyright "Project ATR"
#property version   "2.80"
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

input double M1_Ranging_Threshold = 15.0;
// M1 ADX below this = very choppy → use SL_ATR_Ranging_Mult (wider).
// M1 ADX above this = trending   → use SL_ATR_Factor (normal).
// Recommended: 15 (very choppy). Raise to 20 to widen more often.

input double M1_DI_Spread_Filter = 8.0;
// Block SELL if M1 +DI exceeds -DI by >= this value (any M1 ADX level).
// Block BUY  if M1 -DI exceeds +DI by >= this value (any M1 ADX level).
// Catches clear M1 directional bias that ADX-gated guard (fix 15/16)
// misses when M1 ADX < 25. Surgical — only blocks when M1 DI strongly
// disagrees with trade direction (e.g. +DI=24 vs -DI=14 → spread 10 ≥ 8).
// Set 0 to disable. Recommended: 8.0.

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
input int    SG_End              = 17;    // Session close (SGT hour, 24h)
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
datetime LastBarTime  = 0;

// ── Tick-level cache (set once at top of OnTick) ───────────────────
double g_ATR         = 0.0;    // M1 ATR
double g_ADX         = 0.0;    // H1 ADX main line
double g_PlusDI      = 0.0;    // H1 +DI
double g_MinusDI     = 0.0;    // H1 -DI
double g_M1ADX       = 0.0;    // M1 ADX main line     (bar 1, completed)
double g_M1PlusDI    = 0.0;    // M1 +DI               (bar 1, completed)
double g_M1MinusDI   = 0.0;    // M1 -DI               (bar 1, completed)
double g_M1PlusDI0   = 0.0;    // M1 +DI               (bar 0, real-time)
double g_M1MinusDI0  = 0.0;    // M1 -DI               (bar 0, real-time)
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

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(GetFillType());
   trade.LogLevel(LOG_LEVEL_ERRORS);

   TodayDate = DayOfTime(TimeCurrent());

   int detectedOffset = (int)((TimeCurrent() - TimeGMT()) / 3600);

   Print("Project ATR MT5 v2.8 | Symbol=", Symbol(),
         " | AutoMode=", (AutoModeDetect ? "ADX" : (MomentumMode ? "MOMENTUM" : "REVERSAL")),
         " | ADX_TF=",   EnumToString(ADX_TimeFrame),
         " | ADX_Level=",ADX_Trend_Level,
         " | SL=",       SL_ATR_Factor, "xATR (trend) / ",
                         SL_ATR_Ranging_Mult, "xATR (ranging M1<", M1_Ranging_Threshold, ")",
         " | TS@",       TSstart_ATR_Factor, "xATR",
         " | BrokerGMT=UTC+", detectedOffset, " (auto)");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(ATR_Handle   != INVALID_HANDLE) IndicatorRelease(ATR_Handle);
   if(ADX_Handle   != INVALID_HANDLE) IndicatorRelease(ADX_Handle);
   if(M1ADX_Handle != INVALID_HANDLE) IndicatorRelease(M1ADX_Handle);
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
// Sets g_ADX, g_PlusDI, g_MinusDI
void RefreshADX()
{
   double buf[];   ArraySetAsSeries(buf, true);
   g_ADX     = (CopyBuffer(ADX_Handle, 0, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_PlusDI  = (CopyBuffer(ADX_Handle, 1, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_MinusDI = (CopyBuffer(ADX_Handle, 2, 1, 1, buf) >= 1) ? buf[0] : 0.0;
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

   if(useMomentum)
   {
      // MOMENTUM: trade candle direction AND H1 DI must agree
      // +DI > -DI = H1 bullish bias  → only BUY  bullish candle
      // -DI > +DI = H1 bearish bias  → only SELL bearish candle
      // Prevents buying a bounce inside a strong downtrend
      if     (c > o && g_PlusDI  > g_MinusDI) { dir = ORDER_TYPE_BUY;  price = ask; }
      else if(c < o && g_MinusDI > g_PlusDI)  { dir = ORDER_TYPE_SELL; price = bid; }
      else return;  // candle and H1 DI direction disagree — skip

      // ── M1 counter-trend guard — dual-bar (v2.6) ──────────────
      // Block if EITHER the last completed bar (shift 1) OR the current
      // forming bar (shift 0) shows M1 trending against the trade.
      // Bar 0 DI catches fast-starting rallies that lag in bar-1 values.
      // Both bars require M1 ADX >= threshold so random noise is filtered.
      bool m1BullBar1 = (g_M1ADX >= ADX_Trend_Level && g_M1PlusDI  > g_M1MinusDI);
      bool m1BullBar0 = (g_M1ADX >= ADX_Trend_Level && g_M1PlusDI0 > g_M1MinusDI0);
      bool m1BearBar1 = (g_M1ADX >= ADX_Trend_Level && g_M1MinusDI  > g_M1PlusDI);
      bool m1BearBar0 = (g_M1ADX >= ADX_Trend_Level && g_M1MinusDI0 > g_M1PlusDI0);

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
   }
   else
   {
      // REVERSAL: fade the completed candle
      if     (c > o) { dir = ORDER_TYPE_SELL; price = bid; }
      else if(c < o) { dir = ORDER_TYPE_BUY;  price = ask; }
      else           return;
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
            " | M1ADX=",   DoubleToString(g_M1ADX,   1),
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

   string atrOk  = (g_ATR >= ATR_Min_Filter) ? "[OK]" : "[LOW - no trade]";
   string sessStr = !EnableSessionFilter ? "DISABLED"
                  : (InSession() ? "OPEN  [OK]" : "CLOSED [waiting]");

   // M1 DI spread for panel display
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

   string info =
      "╔══ PROJECT ATR  v2.8  (MT5) ══════════╗\n"
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
      "────────────────────────────────────────\n"
      "  ATR(" + IntegerToString(ATR_Period) + ")    : " + DoubleToString(g_ATR, 2)
                       + "   min=" + DoubleToString(ATR_Min_Filter, 2)
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
   RefreshADX();                                // fills g_ADX, g_PlusDI, g_MinusDI
   RefreshM1ADX();                              // fills g_M1ADX/DI bar1 + bar0
   g_IsTrending = (g_ADX >= ADX_Trend_Level);  // true = trend → Momentum
   g_IsNewBar   = IsNewBar();

   if(g_IsNewBar)
      UpdateTodayProfit();

   ManageTrades();
   TryOpenTrade();
   DrawInfoPanel();
}
//+------------------------------------------------------------------+
