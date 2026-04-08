//+------------------------------------------------------------------+
//|              ATR_AUTO_LOCK_SCALPER EA  (MT5 v2.0)               |
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
//+------------------------------------------------------------------+
#property copyright "ATR Auto Scalper"
#property version   "2.00"
#property description "ATR-based M1 scalper | Auto SL/TP/Trailing | Session filter | XAUUSD"

#include <Trade\Trade.mqh>

CTrade trade;

//===================================================================
//  INPUT GROUPS
//===================================================================

input group "=== Trade ==="
input double LotSize             = 0.01;   // Lot size
input int    MagicNumber         = 5555;   // EA identifier
input double ExpireHours         = 0.5;    // Force-close after N hours (was 2.0 → large losses)
input int    CooldownMinutes     = 5;      // Min gap between entries (minutes)

input group "=== ATR Settings ==="
input int    ATR_Period          = 14;     // ATR period (M1 bars)
input double ATR_Min_Filter      = 1.0;
// Minimum ATR in PRICE to allow trading.
// XAUUSD M1 typical ATR: 2.0–3.5. Set to 1.5 to skip low-vol periods.

input double CandleATR_Factor    = 1.5;
// Candle range (high-low) must be >= N × ATR.
// Filters small indecision candles. 1.0–2.0 recommended.

input double SL_ATR_Factor       = 1.5;
// Stop loss = N × ATR from entry price (in dollars for XAUUSD).
// 1.5 × 2.5 ATR = $3.75 SL on 0.01 lot.

input double TP_ATR_Factor       = 0.0;
// Take profit = N × ATR (0 = disabled → rely on trailing stop).
// Suggested: 2.0–3.0 for fixed TP, or leave 0 for trailing only.

input double TSstart_ATR_Factor  = 0.8;
// Start trailing after N × ATR profit in price.
// 0.8 × 2.5 = $2.0 profit before trailing activates.

input double TSstep_ATR_Factor   = 0.4;
// Trail the SL by N × ATR from current price.
// 0.4 × 2.5 = $1.0 trail step.

input group "=== Entry Mode ==="
input bool   MomentumMode        = false;
// false = REVERSAL  → BUY on red candle / SELL on green candle
// true  = MOMENTUM  → BUY on green candle / SELL on red candle

input group "=== Session Filter (Singapore Time, UTC+8) ==="
input bool   EnableSessionFilter = true;
input int    BrokerGMT_Offset    = 0;     // Broker server UTC offset in hours
input int    SG_Start            = 7;     // Session open  (SGT hour, 24h)
input int    SG_End              = 17;    // Session close (SGT hour, 24h)

//===================================================================
//  GLOBALS
//===================================================================
datetime LastEntry   = 0;
double   TodayProfit = 0.0;
int      TodayDate   = 0;
int      ATR_Handle  = INVALID_HANDLE;
datetime LastBarTime = 0;

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

   Print("ATR Auto Scalper MT5 v2.0 | Symbol=", Symbol(),
         " | Mode=", (MomentumMode ? "MOMENTUM" : "REVERSAL"),
         " | Magic=", MagicNumber,
         " | SL=", SL_ATR_Factor, "xATR",
         " | TS@", TSstart_ATR_Factor, "xATR");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(ATR_Handle != INVALID_HANDLE)
      IndicatorRelease(ATR_Handle);
   Comment("");
}

//===================================================================
//  SMALL HELPERS
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

// Broker time → Singapore time (UTC+8)
datetime ToSGT(datetime brokerTime)
{
   return brokerTime - (long)BrokerGMT_Offset * 3600 + 8 * 3600;
}

bool InSession()
{
   int h = HourOfTime(ToSGT(TimeCurrent()));
   return (h >= SG_Start && h < SG_End);
}

// Detect the correct order fill type for this symbol/broker
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
   double buf[1];
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
      if(PositionGetString(POSITION_SYMBOL)  == Symbol() &&
         (int)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   }
   return count;
}

// Returns true once per new M1 bar (prevents multiple entry attempts per bar)
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
//  DAILY P/L TRACKER
//===================================================================
void UpdateTodayProfit()
{
   int today = DayOfTime(TimeCurrent());
   if(TodayDate != today)
   {
      TodayDate   = today;
      TodayProfit = 0.0;
   }

   TodayProfit = 0.0;
   if(!HistorySelect(StartOfDay(TimeCurrent()), TimeCurrent())) return;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((int)HistoryDealGetInteger(ticket, DEAL_MAGIC)  != MagicNumber) continue;
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
   // Entry is evaluated once per new M1 bar only
   if(!IsNewBar()) return;

   if(EnableSessionFilter && !InSession()) return;

   double atr = GetATR();
   if(atr <= 0.0 || atr < ATR_Min_Filter) return;

   if((long)(TimeCurrent() - LastEntry) < (long)(CooldownMinutes * 60)) return;
   if(CountMyPositions() > 0) return;

   // ── Signal from bar 1 (last COMPLETED candle) ──────────────────
   // Using bar 0 causes the signal to flip every tick mid-candle.
   double o = iOpen(Symbol(),  PERIOD_M1, 1);
   double h = iHigh(Symbol(),  PERIOD_M1, 1);
   double l = iLow(Symbol(),   PERIOD_M1, 1);
   double c = iClose(Symbol(), PERIOD_M1, 1);

   // Candle range filter — price vs price, no Point conversion needed
   double range    = h - l;
   double candleMin = atr * CandleATR_Factor;
   if(range < candleMin) return;

   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   ENUM_ORDER_TYPE dir;
   double          price;

   if(MomentumMode)
   {
      // Trend-following: trade in the direction of the completed candle
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
   // iATR already returns values in price units (e.g. $2.54 for XAUUSD),
   // so multiplying by _Point again would make the SL microscopic.
   double slDist = atr * SL_ATR_Factor;
   double tpDist = (TP_ATR_Factor > 0.0) ? atr * TP_ATR_Factor : 0.0;

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
            " | ATR=",   DoubleToString(atr,   2),
            " | Range=", DoubleToString(range, 2),
            " | SL±",    DoubleToString(slDist,2),
            " | TP=",    (tpDist > 0 ? DoubleToString(tpDist,2) : "OFF"),
            " | Mode=",  (MomentumMode ? "Momentum" : "Reversal"));
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
   double atr = GetATR();
   if(atr <= 0.0) return;

   // All distances in price — consistent with how SL was set at entry
   double tsStart = atr * TSstart_ATR_Factor;
   double tsStep  = atr * TSstep_ATR_Factor;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)      != Symbol())      continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber)   continue;

      ENUM_POSITION_TYPE ptype   = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             op      = PositionGetDouble(POSITION_PRICE_OPEN);
      double             sl      = PositionGetDouble(POSITION_SL);
      double             tp      = PositionGetDouble(POSITION_TP);
      datetime           opened  = (datetime)PositionGetInteger(POSITION_TIME);

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
      // profit in price (same units as ATR, same units as tsStart)
      double profit = (ptype == POSITION_TYPE_BUY) ? (bid - op) : (op - ask);

      if(profit >= tsStart)
      {
         double newSL = (ptype == POSITION_TYPE_BUY)
                        ? NormalizeDouble(bid - tsStep, _Digits)
                        : NormalizeDouble(ask + tsStep, _Digits);

         // Only modify when the new SL is strictly better for the position
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
   double atr = GetATR();
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   datetime sg = ToSGT(TimeCurrent());

   string atrOk  = (atr >= ATR_Min_Filter) ? "[OK]" : "[LOW - no trade]";
   string sessStr;
   if(!EnableSessionFilter) sessStr = "DISABLED";
   else                     sessStr = InSession() ? "OPEN  [OK]" : "CLOSED [waiting]";

   string info =
      "╔══ ATR AUTO SCALPER v2.0  (MT5) ══════╗\n"
      "  Symbol    : " + Symbol()                                            + "\n"
      "  Mode      : " + (MomentumMode ? "MOMENTUM" : "REVERSAL")           + "\n"
      "────────────────────────────────────────\n"
      "  ATR(14)   : " + DoubleToString(atr, 2)
                       + "   min=" + DoubleToString(ATR_Min_Filter, 2)
                       + "  " + atrOk                                        + "\n"
      "  Candle≥   : " + DoubleToString(atr * CandleATR_Factor, 2)           + "\n"
      "  SL dist   : " + DoubleToString(atr * SL_ATR_Factor,    2)           + "\n"
      "  TP dist   : " + (TP_ATR_Factor > 0
                          ? DoubleToString(atr * TP_ATR_Factor, 2)
                          : "DISABLED (trailing only)")                       + "\n"
      "  TS start  : +" + DoubleToString(atr * TSstart_ATR_Factor, 2)        + "\n"
      "  TS step   : "  + DoubleToString(atr * TSstep_ATR_Factor,  2)        + "\n"
      "────────────────────────────────────────\n"
      "  Positions : " + IntegerToString(CountMyPositions())                  + "\n"
      "  Today P/L : $" + DoubleToString(TodayProfit, 2)                     + "\n"
      "  Last Entry: " + (LastEntry > 0
                          ? TimeToString(LastEntry, TIME_DATE|TIME_SECONDS)
                          : "---")                                            + "\n"
      "────────────────────────────────────────\n"
      "  SG Time   : " + TimeToString(sg, TIME_MINUTES)                      + "\n"
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
   UpdateTodayProfit();
   ManageTrades();    // every tick — accurate expiry + trailing
   TryOpenTrade();    // entry gated by IsNewBar() — once per bar
   DrawInfoPanel();
}
//+------------------------------------------------------------------+
