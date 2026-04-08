//+------------------------------------------------------------------+
//|              ATR_AUTO_LOCK_SCALPER EA  (MT5 v2.1)               |
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
//+------------------------------------------------------------------+
#property copyright "ATR Auto Scalper"
#property version   "2.10"
#property description "ATR-based M1 scalper | Auto SL/TP/Trailing | Auto SGT | XAUUSD"

#include <Trade\Trade.mqh>

CTrade trade;

//===================================================================
//  INPUT GROUPS
//===================================================================

input group "=== Trade ==="
input double LotSize             = 0.01;   // Lot size
input int    MagicNumber         = 5555;   // EA identifier
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
// e.g. 1.5 × $2.50 ATR = $3.75 SL per 0.01 lot.

input double TP_ATR_Factor       = 0.0;
// Take profit = N × ATR (0 = disabled → trailing stop only).
// Suggested: 2.0–3.0 for fixed TP.

input double TSstart_ATR_Factor  = 0.8;
// Begin trailing after N × ATR profit.
// e.g. 0.8 × $2.50 = $2.00 profit before trailing activates.

input double TSstep_ATR_Factor   = 0.4;
// Trail SL N × ATR behind current price.
// e.g. 0.4 × $2.50 = $1.00 trail step.

input group "=== Entry Mode ==="
input bool   MomentumMode        = false;
// false = REVERSAL  → BUY red candle  / SELL green candle
// true  = MOMENTUM  → BUY green candle / SELL red candle

input group "=== Session Filter (Singapore Time — auto-detected) ==="
input bool   EnableSessionFilter = true;
input int    SG_Start            = 7;     // Session open  (SGT hour, 24h)
input int    SG_End              = 17;    // Session close (SGT hour, 24h)
// SGT = UTC+8. Broker GMT offset is auto-detected via TimeGMT().
// No manual offset entry needed — works on any broker.

//===================================================================
//  GLOBALS
//===================================================================
datetime LastEntry   = 0;
double   TodayProfit = 0.0;
int      TodayDate   = 0;
int      ATR_Handle  = INVALID_HANDLE;
datetime LastBarTime = 0;

// ── Tick-level cache (set once at top of OnTick) ───────────────────
double g_ATR      = 0.0;   // avoids 3× CopyBuffer per tick
bool   g_IsNewBar = false; // avoids duplicate IsNewBar() calls

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

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(GetFillType());
   trade.LogLevel(LOG_LEVEL_ERRORS);

   TodayDate = DayOfTime(TimeCurrent());

   // Show auto-detected broker GMT offset in log for verification
   int detectedOffset = (int)((TimeCurrent() - TimeGMT()) / 3600);

   Print("ATR Auto Scalper MT5 v2.1 | Symbol=", Symbol(),
         " | Mode=",   (MomentumMode ? "MOMENTUM" : "REVERSAL"),
         " | Magic=",  MagicNumber,
         " | SL=",     SL_ATR_Factor, "xATR",
         " | TS@",     TSstart_ATR_Factor, "xATR",
         " | BrokerGMT=UTC+", detectedOffset, " (auto)");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(ATR_Handle != INVALID_HANDLE)
      IndicatorRelease(ATR_Handle);
   Comment("");
}

//===================================================================
//  HELPERS
//===================================================================

// Return day-of-month from a datetime
int DayOfTime(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.day;
}

// Return hour from a datetime
int HourOfTime(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.hour;
}

// Return midnight of the day containing t
datetime StartOfDay(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   s.hour = 0; s.min = 0; s.sec = 0;
   return StructToTime(s);
}

// ── SGT auto-detection ─────────────────────────────────────────────
// TimeGMT() returns true UTC from the MT5 terminal — no manual broker
// offset needed. SGT = UTC+8, so we simply add 8 hours to UTC.
datetime GetSGT()
{
   return (datetime)((long)TimeGMT() + 8 * 3600);
}

bool InSession()
{
   int h = HourOfTime(GetSGT());
   return (h >= SG_Start && h < SG_End);
}

// Auto-detect broker GMT offset (for display only)
int BrokerGMTOffset()
{
   return (int)((TimeCurrent() - TimeGMT()) / 3600);
}

// Detect correct order fill type for this symbol/broker
ENUM_ORDER_TYPE_FILLING GetFillType()
{
   long mode = (long)SymbolInfoInteger(Symbol(), SYMBOL_FILLING_MODE);
   if((mode & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((mode & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

// ATR from last COMPLETED bar (shift 1) — avoids mid-bar noise
double GetATR()
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(ATR_Handle, 0, 1, 1, buf) < 1) return 0.0;
   return buf[0];
}

// Count open positions belonging to this EA on this symbol
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

// Returns true once per new M1 bar — prevents multiple entries per bar
bool IsNewBar()
{
   datetime t = iTime(Symbol(), PERIOD_M1, 0);
   if(t != LastBarTime)
   {
      LastBarTime = t;
      return true;
   }
   return false;
}

//===================================================================
//  DAILY P/L TRACKER  (called once per bar, not every tick)
//===================================================================
void UpdateTodayProfit()
{
   int today = DayOfTime(TimeCurrent());
   if(TodayDate != today)
      TodayDate = today;   // TodayProfit reset below unconditionally

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
   // Entry evaluated once per new M1 bar only (g_IsNewBar set in OnTick)
   if(!g_IsNewBar) return;

   if(EnableSessionFilter && !InSession()) return;

   // g_ATR set once in OnTick — no redundant CopyBuffer call here
   if(g_ATR <= 0.0 || g_ATR < ATR_Min_Filter) return;

   if((long)(TimeCurrent() - LastEntry) < (long)(CooldownMinutes * 60)) return;
   if(CountMyPositions() > 0) return;

   // ── Signal from bar 1 (last COMPLETED candle) ──────────────────
   // Bar 0 flips every tick mid-candle — bar 1 is stable.
   double o = iOpen(Symbol(),  PERIOD_M1, 1);
   double h = iHigh(Symbol(),  PERIOD_M1, 1);
   double l = iLow(Symbol(),   PERIOD_M1, 1);
   double c = iClose(Symbol(), PERIOD_M1, 1);

   // Candle range filter — price vs price, no Point conversion
   double range     = h - l;
   double candleMin = g_ATR * CandleATR_Factor;
   if(range < candleMin) return;

   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   ENUM_ORDER_TYPE dir;
   double          price;

   if(MomentumMode)
   {
      // Trend-following: trade direction of completed candle
      if     (c > o) { dir = ORDER_TYPE_BUY;  price = ask; }
      else if(c < o) { dir = ORDER_TYPE_SELL; price = bid; }
      else           return;  // doji — skip
   }
   else
   {
      // Reversal: fade the completed candle
      if     (c > o) { dir = ORDER_TYPE_SELL; price = bid; }
      else if(c < o) { dir = ORDER_TYPE_BUY;  price = ask; }
      else           return;  // doji — skip
   }

   // ── SL / TP — all in price (no * _Point) ───────────────────────
   // iATR returns price units (e.g. $2.54 for XAUUSD).
   // Multiplying by _Point would make SL microscopic — don't do it.
   double slDist = g_ATR * SL_ATR_Factor;
   double tpDist = (TP_ATR_Factor > 0.0) ? g_ATR * TP_ATR_Factor : 0.0;

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

   bool ok = (dir == ORDER_TYPE_BUY)
             ? trade.Buy (LotSize, Symbol(), price, sl, tp, "ATR_SCALPER")
             : trade.Sell(LotSize, Symbol(), price, sl, tp, "ATR_SCALPER");

   if(ok)
   {
      LastEntry = TimeCurrent();
      Print("OPEN ", (dir == ORDER_TYPE_BUY ? "BUY " : "SELL"),
            " | ATR=",   DoubleToString(g_ATR,  2),
            " | Range=", DoubleToString(range, 2),
            " | SL±",    DoubleToString(slDist,2),
            " | TP=",    (tpDist > 0 ? DoubleToString(tpDist,2) : "OFF"),
            " | Mode=",  (MomentumMode ? "Momentum" : "Reversal"),
            " | SGT=",   TimeToString(GetSGT(), TIME_MINUTES));
   }
   else
      Print("Order FAIL [", trade.ResultRetcode(), "] ",
            trade.ResultRetcodeDescription());
}

//===================================================================
//  TRADE MANAGEMENT  (runs every tick)
//===================================================================
void ManageTrades()
{
   // g_ATR set once in OnTick — no redundant CopyBuffer call here
   if(g_ATR <= 0.0) return;

   // All distances in price — consistent with how SL was set at entry
   double tsStart = g_ATR * TSstart_ATR_Factor;
   double tsStep  = g_ATR * TSstep_ATR_Factor;

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

      double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

      // ── Expiry: force close after N hours ──────────────────────
      if((long)(TimeCurrent() - opened) > (long)(ExpireHours * 3600))
      {
         if(trade.PositionClose(ticket))
            Print("EXPIRY | ticket=", ticket,
                  " | held=", DoubleToString((TimeCurrent() - opened) / 3600.0, 2), "h");
         else
            Print("Expiry close FAIL: ", trade.ResultRetcodeDescription());
         continue;
      }

      // ── Trailing stop ──────────────────────────────────────────
      // profit in price (same units as ATR and tsStart)
      double profit = (ptype == POSITION_TYPE_BUY) ? (bid - op) : (op - ask);

      if(profit >= tsStart)
      {
         double newSL = (ptype == POSITION_TYPE_BUY)
                        ? NormalizeDouble(bid - tsStep, _Digits)
                        : NormalizeDouble(ask + tsStep, _Digits);

         // Only modify when new SL is strictly better for the position
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
   // Use g_ATR cached this tick — no extra CopyBuffer call
   double ask    = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid    = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   datetime sgt  = GetSGT();
   int gmtOffset = BrokerGMTOffset();

   string atrOk  = (g_ATR >= ATR_Min_Filter) ? "[OK]" : "[LOW - no trade]";
   string sessStr;
   if(!EnableSessionFilter) sessStr = "DISABLED";
   else                     sessStr = InSession() ? "OPEN  [OK]" : "CLOSED [waiting]";

   string info =
      "╔══ ATR AUTO SCALPER v2.1  (MT5) ══════╗\n"
      "  Symbol    : " + Symbol()                                            + "\n"
      "  Mode      : " + (MomentumMode ? "MOMENTUM" : "REVERSAL")           + "\n"
      "────────────────────────────────────────\n"
      "  ATR(14)   : " + DoubleToString(g_ATR, 2)
                       + "   min=" + DoubleToString(ATR_Min_Filter, 2)
                       + "  " + atrOk                                        + "\n"
      "  Candle≥   : " + DoubleToString(g_ATR * CandleATR_Factor, 2)         + "\n"
      "  SL dist   : " + DoubleToString(g_ATR * SL_ATR_Factor,    2)         + "\n"
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
   g_ATR      = GetATR();    // single CopyBuffer call — shared by all functions
   g_IsNewBar = IsNewBar();  // single new-bar check — shared by all functions

   if(g_IsNewBar)
      UpdateTodayProfit();   // only recalc P/L on bar open, not every tick

   ManageTrades();    // every tick — accurate expiry + trailing
   TryOpenTrade();    // entry gated by g_IsNewBar — once per bar
   DrawInfoPanel();
}
//+------------------------------------------------------------------+
