//+------------------------------------------------------------------+
//|                    LQS ZONE SCALPER  (MT5 v1.180)               |
//|  Standalone Liquidity Sweep EA — LQS signals only               |
//|  Runs alongside ATR_AUTO_LOCK_SCALPER_MT5 (MagicNumber 7777)   |
//|                                                                  |
//| v1.180: LQS_HTF_DI_Align — M5 trend direction filter           |
//|  Blocks SELL sweeps when M5 +DI > -DI (M5 is bullish).         |
//|  Blocks BUY  sweeps when M5 -DI > +DI (M5 is bearish).         |
//|  Fixes the March problem: all-SELL during a gold bull run.      |
//|  M5 DI reflects a 25-bar trend window — stable enough to filter |
//|  direction without being as noisy as M1 DI.                     |
//|                                                                  |
//| v1.170: LQS_TP_ATR_Factor — dynamic ATR-based TP               |
//| v1.160: DI-align + bar-range entry quality filters              |
//| v1.150: CloseBack + BodyDirection sweep-quality filters         |
//| v1.140: LQS_Trend_Only filter                                   |
//+------------------------------------------------------------------+
#property copyright "Project ATR"
#property version   "1.180"
#property description "LQS Zone Scalper | Liquidity Sweep Only | XAUUSD M1 | M5 trend filter"

#include <Trade\Trade.mqh>

#define LQS_LINE_SELL  "LQS_SwingHigh"
#define LQS_LINE_BUY   "LQS_SwingLow"
CTrade trade;

//===================================================================
//  INPUTS
//===================================================================
input group "=== Trade ==="
input double LotSize             = 0.01;
input int    MagicNumber         = 7777;
input double ExpireHours         = 0.5;
input int    CooldownMinutes     = 5;

input group "=== ATR Settings ==="
input int    ATR_Period          = 14;
input double ATR_Min_Filter      = 1.0;
input double ATR_Max_Filter      = 8.0;
input double SL_ATR_Factor       = 1.5;
input double SL_ATR_Ranging_Mult = 2.0;
input double M1_Ranging_Threshold = 25.0;
input double TSstart_ATR_Factor  = 0.8;
input double TSstep_ATR_Factor   = 0.4;

input group "=== LQS Settings ==="
input int    LQS_Lookback        = 20;
input double LQS_Wick_Min_ATR    = 0.0;
input double LQS_DI_Spread_Filter = 30.0;
input double LQS_M1_DI_Max_Counter  = 0.0;
input bool   LQS_Trend_Only         = true;
input double LQS_CloseBack_Min_ATR  = 0.3;
// Minimum close-back distance as a fraction of ATR.
// SELL: bar[1] must close at least (N × ATR) below swingHigh.
// BUY:  bar[1] must close at least (N × ATR) above swingLow.
// Filters weak rejections that barely graze the level before closing back.
// 0.3 = bar must close $0.60+ below swing (at ATR=$2). Set 0 to disable.
input bool   LQS_Body_Direction     = true;
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
// Blocks sweeps where M1 momentum still runs against the trade direction —
// e.g. a strong bull bar that barely poked above swing with DI still bullish.
// Set false to disable (original behaviour).
input double LQS_Bar_Range_Min_ATR  = 0.0;
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
input double LQS_TP_ATR_Factor   = 1.0;
// Dynamic TP: TP = ATR × LQS_TP_ATR_Factor.
// Scales with volatility — keeps R:R consistent across market conditions.
// At 1.0×ATR TP vs SL=1.5×ATR: need 60% win rate to break even.
// At 1.0×ATR TP vs SL=2.0×ATR: need 67% win rate to break even.
// Set 0 to disable and use LQS_TP_Fixed (fixed dollar) instead.
input double LQS_TP_Fixed        = 0.35;
// Fixed dollar TP. Only used when LQS_TP_ATR_Factor = 0.

input group "=== Session Filter (SGT auto-detected) ==="
input bool   EnableSessionFilter = true;
input int    SG_Start            = 6;
input int    SG_End              = 20;

input group "=== Notifications ==="
input bool   Enable_Notify       = true;
input int    Notify_Interval_Min = 15;
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

double g_ATR        = 0.0;
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

   M1ADX_Handle = iADX(Symbol(), PERIOD_M1, 14);
   if(M1ADX_Handle == INVALID_HANDLE) { Print("ERROR: M1 ADX handle failed."); return INIT_FAILED; }

   M5ADX_Handle = iADX(Symbol(), PERIOD_M5, 14);
   if(M5ADX_Handle == INVALID_HANDLE) { Print("ERROR: M5 ADX handle failed."); return INIT_FAILED; }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(GetFillType());
   trade.LogLevel(LOG_LEVEL_ERRORS);

   TodayDate = DayOfTime(TimeCurrent());

   Print("LQS Zone Scalper v1.180 | Symbol=", Symbol(),
         " | Magic=", MagicNumber,
         " | TP=", (LQS_TP_ATR_Factor > 0.0
                    ? DoubleToString(LQS_TP_ATR_Factor,2)+"xATR [dynamic]"
                    : "$"+DoubleToString(LQS_TP_Fixed,2)+" [fixed]"),
         " | DI_Align=", LQS_M1_DI_Align,
         " | BarRange=", LQS_Bar_Range_Min_ATR, "xATR",
         " | TrendOnly=", LQS_Trend_Only,
         " | HTF_DI_Align=", LQS_HTF_DI_Align,
         " | RangingThresh=M1ADX<", M1_Ranging_Threshold);

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
   ObjectDelete(0, LQS_LINE_SELL);
   ObjectDelete(0, LQS_LINE_BUY);
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
string BuildNotifyStatus(bool zoneAlert, string zoneSide)
{
   double price    = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double distSell = (g_LQS_SwingHigh > 0) ? g_LQS_SwingHigh - price : 0.0;
   double distBuy  = (g_LQS_SwingLow  > 0) ? price - g_LQS_SwingLow  : 0.0;

   string m1Dir;
   double m1Spread = g_M1PlusDI - g_M1MinusDI;
   if     (m1Spread >=  8) m1Dir = "M1 BULL";
   else if(m1Spread <= -8) m1Dir = "M1 BEAR";
   else                    m1Dir = "M1 NEUTRAL";

   bool sellBlocked = (LQS_DI_Spread_Filter > 0.0 &&
                       ((g_M1PlusDI  - g_M1MinusDI)  >= LQS_DI_Spread_Filter ||
                        (g_M1PlusDI2 - g_M1MinusDI2) >= LQS_DI_Spread_Filter))
                   || (LQS_M1_DI_Max_Counter > 0.0 &&
                       (g_M1PlusDI - g_M1MinusDI) >= LQS_M1_DI_Max_Counter);
   bool buyBlocked  = (LQS_DI_Spread_Filter > 0.0 &&
                       ((g_M1MinusDI - g_M1PlusDI)   >= LQS_DI_Spread_Filter ||
                        (g_M1MinusDI2 - g_M1PlusDI2) >= LQS_DI_Spread_Filter))
                   || (LQS_M1_DI_Max_Counter > 0.0 &&
                       (g_M1MinusDI - g_M1PlusDI) >= LQS_M1_DI_Max_Counter);

   string msg = "";
   if(zoneAlert)
   {
      bool   isBuy     = (zoneSide == "BUY");
      double zonePrice = isBuy ? g_LQS_SwingLow : g_LQS_SwingHigh;
      double dist      = isBuy ? distBuy : distSell;
      bool   blocked   = isBuy ? buyBlocked : sellBlocked;
      string action    = isBuy
                         ? "Spike BELOW " + DoubleToString(zonePrice, 2) + " then close ABOVE -> BUY"
                         : "Spike ABOVE " + DoubleToString(zonePrice, 2) + " then close BELOW -> SELL";
      msg = "[LQS] XAUUSD " + DoubleToString(price, 2) + " | " + zoneSide + " ZONE $"
            + DoubleToString(dist, 1) + " away\n"
            + action + "\n"
            + m1Dir + " | ATR=" + DoubleToString(g_ATR, 2) + "\n"
            + (blocked ? "LQS EA: BLOCKED (manual trade only)"
                       : "LQS EA: will auto-trade if sweep fires");
   }
   else
   {
      msg = "[LQS] XAUUSD " + DoubleToString(price, 2) + " | " + m1Dir + "\n"
            + "SELL zone: " + DoubleToString(g_LQS_SwingHigh, 2)
            + "  (price +" + DoubleToString(distSell, 1) + " away)\n"
            + "  -> spike above + close below = SELL\n"
            + "BUY  zone: " + DoubleToString(g_LQS_SwingLow, 2)
            + "  (price -" + DoubleToString(distBuy, 1) + " away)\n"
            + "  -> spike below + close above = BUY\n"
            + "ATR=" + DoubleToString(g_ATR, 2)
            + (sellBlocked ? "  [SELL EA-blocked]" : "")
            + (buyBlocked  ? "  [BUY EA-blocked]"  : "");
   }
   return msg;
}

void OnTimer()
{
   if(!Enable_Notify) return;
   SendNotification(BuildNotifyStatus(false, ""));
}

void CheckZoneApproach()
{
   if(!Enable_Notify || Notify_Zone_ATR_Dist <= 0.0) return;
   if(g_ATR <= 0.0 || g_LQS_SwingHigh <= 0.0 || g_LQS_SwingLow <= 0.0) return;
   if((long)(TimeCurrent() - g_LastZoneAlert) < 300) return;
   double price  = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double thresh = Notify_Zone_ATR_Dist * g_ATR;
   bool nearSell = (g_LQS_SwingHigh - price) <= thresh && price < g_LQS_SwingHigh;
   bool nearBuy  = (price - g_LQS_SwingLow)  <= thresh && price > g_LQS_SwingLow;
   if(nearSell || nearBuy)
   {
      SendNotification(BuildNotifyStatus(true, nearSell ? "SELL" : "BUY"));
      g_LastZoneAlert = TimeCurrent();
   }
}

//===================================================================
//  TRADE MANAGEMENT
//===================================================================
void ManageTrades()
{
   bool   trailOk = (g_ATR > 0.0);
   double tsStart = trailOk ? g_ATR * TSstart_ATR_Factor : 0.0;
   double tsStep  = trailOk ? g_ATR * TSstep_ATR_Factor  : 0.0;
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

   if(g_LQS_SwingHigh <= 0.0 || g_LQS_SwingLow <= 0.0) return;

   bool lqsSell = (h1 > g_LQS_SwingHigh) && (c1 < g_LQS_SwingHigh);
   bool lqsBuy  = (l1 < g_LQS_SwingLow)  && (c1 > g_LQS_SwingLow);
   if(!lqsSell && !lqsBuy) return;

   ENUM_ORDER_TYPE dir;
   double          price;
   if(lqsSell) { dir = ORDER_TYPE_SELL; price = SymbolInfoDouble(Symbol(), SYMBOL_BID); }
   else        { dir = ORDER_TYPE_BUY;  price = SymbolInfoDouble(Symbol(), SYMBOL_ASK); }

   if(LQS_Wick_Min_ATR > 0.0)
   {
      double wickSize = (dir == ORDER_TYPE_SELL) ? (h1 - g_LQS_SwingHigh) : (g_LQS_SwingLow - l1);
      if(wickSize < g_ATR * LQS_Wick_Min_ATR) return;
   }

   // ── Close-back distance filter (v1.150) ───────────────────────
   // Bar[1] must close N×ATR below swingHigh (SELL) or above swingLow (BUY).
   // Bars that barely close back past the swing level lack rejection strength.
   if(LQS_CloseBack_Min_ATR > 0.0)
   {
      double closeBack = lqsSell ? (g_LQS_SwingHigh - c1) : (c1 - g_LQS_SwingLow);
      if(closeBack < g_ATR * LQS_CloseBack_Min_ATR) return;
   }

   // ── Bar body direction filter (v1.150) ────────────────────────
   // Sweep bar must close in the lower half of its range (SELL) or upper
   // half (BUY). A bar closing near its high after a SELL sweep still has
   // bullish pressure — not a genuine rejection candle.
   if(LQS_Body_Direction)
   {
      double midPoint = (h1 + l1) * 0.5;
      if(lqsSell && c1 > midPoint) return;   // bullish body — not a real rejection
      if(lqsBuy  && c1 < midPoint) return;   // bearish body — not a real rejection
   }

   // ── M1 DI alignment filter (v1.160) ──────────────────────────
   // Sweep bar DI must agree with signal direction.
   // SELL: -DI >= +DI. BUY: +DI >= -DI.
   if(LQS_M1_DI_Align)
   {
      if(lqsSell && g_M1PlusDI  > g_M1MinusDI) return;   // M1 still bullish — skip sell
      if(lqsBuy  && g_M1MinusDI > g_M1PlusDI)  return;   // M1 still bearish — skip buy
   }

   // ── M5 higher-timeframe trend filter (v1.180) ─────────────────
   // Block sweep when M5 DI trend opposes the trade direction.
   // SELL blocked when M5 is bullish (+DI > -DI): don't sell into strength.
   // BUY  blocked when M5 is bearish (-DI > +DI): don't buy into weakness.
   if(LQS_HTF_DI_Align)
   {
      if(lqsSell && g_M5PlusDI  > g_M5MinusDI) return;
      if(lqsBuy  && g_M5MinusDI > g_M5PlusDI)  return;
   }

   // ── Sweep bar minimum range filter (v1.160) ───────────────────
   // Bar[1] total range (H-L) must be at least N×ATR.
   // Filters minimal-volatility pokes with no institutional footprint.
   if(LQS_Bar_Range_Min_ATR > 0.0)
   {
      double barRange = h1 - l1;
      if(barRange < g_ATR * LQS_Bar_Range_Min_ATR) return;
   }

   if(LQS_DI_Spread_Filter > 0.0)
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
   if(LQS_Trend_Only && m1IsRanging) return;   // v1.140: skip ranging-mode entries

   double slMult      = m1IsRanging ? SL_ATR_Ranging_Mult : SL_ATR_Factor;
   double slDist      = g_ATR * slMult;
   double tpDist      = (LQS_TP_ATR_Factor > 0.0) ? g_ATR * LQS_TP_ATR_Factor : LQS_TP_Fixed;

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

   string comment = "LQS Zone" + (dir == ORDER_TYPE_BUY ? " BUY" : " SELL");
   bool ok = (dir == ORDER_TYPE_BUY)
             ? trade.Buy (LotSize, Symbol(), price, sl, tp, comment)
             : trade.Sell(LotSize, Symbol(), price, sl, tp, comment);

   if(ok)
   {
      LastEntry = TimeCurrent();

      // Correct TP for slippage: fill price may differ from requested price,
      // which would place TP on the wrong side of entry.
      if(tpDist > 0.0)
      {
         double fillPrice = trade.ResultPrice();
         if(fillPrice > 0.0)
         {
            double realTP = (dir == ORDER_TYPE_BUY)
                            ? NormalizeDouble(fillPrice + tpDist, _Digits)
                            : NormalizeDouble(fillPrice - tpDist, _Digits);
            if(realTP != tp)
            {
               ulong ticket = trade.ResultOrder();
               if(ticket > 0 && !trade.PositionModify(ticket, sl, realTP))
                  Print("TP correct FAIL: ", trade.ResultRetcodeDescription());
               else
                  Print("TP corrected fill=", DoubleToString(fillPrice, _Digits),
                        " requested=", DoubleToString(price, _Digits),
                        " slip=", DoubleToString(fillPrice - price, _Digits),
                        " oldTP=", DoubleToString(tp, _Digits),
                        " newTP=", DoubleToString(realTP, _Digits));
            }
         }
      }

      Print("OPEN LQS ", (dir == ORDER_TYPE_BUY ? "BUY " : "SELL"),
            " | swingH=",  DoubleToString(g_LQS_SwingHigh, _Digits),
            " | swingL=",  DoubleToString(g_LQS_SwingLow,  _Digits),
            " | bar1H=",   DoubleToString(h1, _Digits),
            " | bar1L=",   DoubleToString(l1, _Digits),
            " | bar1C=",   DoubleToString(c1, _Digits),
            " | SL=",      DoubleToString(slMult, 1), "xATR",
                           (m1IsRanging ? " [RANGING]" : " [TREND]"),
            " | SLdist=",  DoubleToString(slDist, 2),
            " | TP=",      DoubleToString(tpDist, 2),
            " | ATR=",     DoubleToString(g_ATR,  2),
            " | M1+DI=",   DoubleToString(g_M1PlusDI,  1),
            " | M1-DI=",   DoubleToString(g_M1MinusDI, 1),
            " | SGT=",     TimeToString(GetSGT(), TIME_MINUTES));
   }
   else
      Print("LQS Order FAIL [", trade.ResultRetcode(), "] ",
            trade.ResultRetcodeDescription());
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

   string info =
      "╔══ LQS ZONE SCALPER  v1.180 (MT5) ════╗\n"
      "  Symbol    : " + Symbol()                                          + "\n"
      "  Magic     : " + IntegerToString(MagicNumber)                      + "\n"
      "────────────────────────────────────────\n"
      "  ATR(" + IntegerToString(ATR_Period) + ")   : " + DoubleToString(g_ATR, 2)
                     + "  min=" + DoubleToString(ATR_Min_Filter, 2)
                     + (ATR_Max_Filter > 0.0
                        ? "  max=" + DoubleToString(ATR_Max_Filter, 2)
                        : "  max=OFF")
                     + "  " + atrOk                                        + "\n"
      "  M1 ADX    : " + DoubleToString(g_M1ADX, 1)
                     + (g_M1ADX < M1_Ranging_Threshold
                        ? "  [RANGING -> SL " + DoubleToString(SL_ATR_Ranging_Mult,1) + "xATR"
                          + (LQS_Trend_Only ? " BLOCKED]" : "]")
                        : "  [TREND   -> SL " + DoubleToString(SL_ATR_Factor,      1) + "xATR]") + "\n"
      "  M1 DI(1)  : +" + DoubleToString(g_M1PlusDI,  1)
                     + " / -" + DoubleToString(g_M1MinusDI, 1)            + "\n"
      "  M1 DI(2)  : +" + DoubleToString(g_M1PlusDI2,  1)
                     + " / -" + DoubleToString(g_M1MinusDI2, 1)
                     + "  [pre-sweep]"                                     + "\n"
      "  M5 DI     : +" + DoubleToString(g_M5PlusDI,  1)
                     + " / -" + DoubleToString(g_M5MinusDI, 1)
                     + (LQS_HTF_DI_Align
                        ? (g_M5PlusDI > g_M5MinusDI ? "  [M5 BULL: SELL blocked]"
                          : g_M5MinusDI > g_M5PlusDI ? "  [M5 BEAR: BUY blocked]"
                          :                             "  [M5 NEUTRAL: both OK]")
                        : "  [HTF filter OFF]")                            + "\n"
      "────────────────────────────────────────\n"
      "  LQS lb    : " + IntegerToString(LQS_Lookback) + " bars"          + "\n"
      "  SELL zone : " + DoubleToString(g_LQS_SwingHigh, 2)
                     + "  (price +" + DoubleToString(distSell, 1) + ")"   + "\n"
      "  BUY  zone : " + DoubleToString(g_LQS_SwingLow, 2)
                     + "  (price -" + DoubleToString(distBuy, 1) + ")"    + "\n"
      "  TP mode   : " + (LQS_TP_ATR_Factor > 0.0
                          ? DoubleToString(LQS_TP_ATR_Factor, 2) + "×ATR = $"
                            + DoubleToString(g_ATR * LQS_TP_ATR_Factor, 2) + " [dynamic]"
                          : "$" + DoubleToString(LQS_TP_Fixed, 2) + " [fixed]") + "\n"
      "  DI spread : thr=" + DoubleToString(LQS_DI_Spread_Filter, 1)
                     + (((g_M1PlusDI  - g_M1MinusDI)  >= LQS_DI_Spread_Filter ||
                         (g_M1PlusDI2 - g_M1MinusDI2) >= LQS_DI_Spread_Filter) ? "  [SELL BLK]"
                      : ((g_M1MinusDI - g_M1PlusDI)   >= LQS_DI_Spread_Filter ||
                         (g_M1MinusDI2 - g_M1PlusDI2) >= LQS_DI_Spread_Filter) ? "  [BUY BLK]"
                      :                                                            "  [OK]")     + "\n"
      "  DI counter: max=" + (LQS_M1_DI_Max_Counter > 0.0
                              ? DoubleToString(LQS_M1_DI_Max_Counter, 1)
                              : "OFF")
                     + ctrStr                                               + "\n"
      "────────────────────────────────────────\n"
      "  Positions : " + IntegerToString(CountMyPositions())               + "\n"
      "  Today P/L : $" + DoubleToString(TodayProfit, 2)                  + "\n"
      "  Last Entry: " + (LastEntry > 0
                          ? TimeToString(LastEntry, TIME_DATE|TIME_SECONDS)
                          : "---")                                         + "\n"
      "────────────────────────────────────────\n"
      "  SGT (auto): " + TimeToString(sgt, TIME_MINUTES)
                     + "  [broker UTC+" + IntegerToString(BrokerGMTOffset()) + "]" + "\n"
      "  Session   : " + sessStr                                           + "\n"
      "  Bid / Ask : " + DoubleToString(bid, _Digits)
                     + " / " + DoubleToString(ask, _Digits)               + "\n"
      "╚════════════════════════════════════════╝";

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
   g_IsNewBar = IsNewBar();

   if(g_IsNewBar)
      UpdateTodayProfit();

   RefreshLQSLevels();
   CheckZoneApproach();

   ManageTrades();
   TryLQSTrade();
   DrawInfoPanel();
}
//+------------------------------------------------------------------+
