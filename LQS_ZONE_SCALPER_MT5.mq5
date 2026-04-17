//+------------------------------------------------------------------+
//|                    LQS ZONE SCALPER  (MT5 v1.100)               |
//|  Standalone Liquidity Sweep EA — LQS signals only               |
//|  Runs alongside ATR_AUTO_LOCK_SCALPER_MT5 (MagicNumber 7777)   |
//+------------------------------------------------------------------+
#property copyright "Project ATR"
#property version   "1.100"
#property description "LQS Zone Scalper | Liquidity Sweep Only | XAUUSD M1"

#include <Trade\Trade.mqh>
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
input double LQS_DI_Spread_Filter = 0.0;
input double LQS_M1_DI_Max_Counter = 0.0;
input double LQS_TP_Fixed        = 0.35;

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

double g_ATR        = 0.0;
double g_M1ADX      = 0.0;
double g_M1PlusDI   = 0.0;
double g_M1MinusDI  = 0.0;
double g_M1PlusDI2  = 0.0;
double g_M1MinusDI2 = 0.0;
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

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(GetFillType());
   trade.LogLevel(LOG_LEVEL_ERRORS);

   TodayDate = DayOfTime(TimeCurrent());

   Print("LQS Zone Scalper v1.100 | Symbol=", Symbol(),
         " | Magic=", MagicNumber,
         " | LQS_TP_Fixed=", LQS_TP_Fixed,
         " | DI_Max_Counter=", LQS_M1_DI_Max_Counter,
         " | DI_Spread_Filter=", LQS_DI_Spread_Filter);

   if(Enable_Notify && Notify_Interval_Min > 0)
      EventSetTimer(Notify_Interval_Min * 60);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(ATR_Handle   != INVALID_HANDLE) IndicatorRelease(ATR_Handle);
   if(M1ADX_Handle != INVALID_HANDLE) IndicatorRelease(M1ADX_Handle);
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

   bool sellBlocked = ((g_M1PlusDI  - g_M1MinusDI)  >= LQS_DI_Spread_Filter)
                   || ((g_M1PlusDI2 - g_M1MinusDI2) >= LQS_DI_Spread_Filter)
                   || (LQS_M1_DI_Max_Counter > 0.0 &&
                       (g_M1PlusDI - g_M1MinusDI) >= LQS_M1_DI_Max_Counter);
   bool buyBlocked  = ((g_M1MinusDI - g_M1PlusDI)   >= LQS_DI_Spread_Filter)
                   || ((g_M1MinusDI2 - g_M1PlusDI2) >= LQS_DI_Spread_Filter)
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
      msg = "XAUUSD " + DoubleToString(price, 2) + " | " + zoneSide + " ZONE $"
            + DoubleToString(dist, 1) + " away\n"
            + action + "\n"
            + m1Dir + " | ATR=" + DoubleToString(g_ATR, 2) + "\n"
            + (blocked ? "LQS EA: BLOCKED (manual trade only)"
                       : "LQS EA: will auto-trade if sweep fires");
   }
   else
   {
      msg = "XAUUSD " + DoubleToString(price, 2) + " | " + m1Dir + "\n"
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
   double slMult      = m1IsRanging ? SL_ATR_Ranging_Mult : SL_ATR_Factor;
   double slDist      = g_ATR * slMult;
   double tpDist      = LQS_TP_Fixed;

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
//  INFO PANEL
//===================================================================
void DrawInfoPanel()
{
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
      "╔══ LQS ZONE SCALPER  v1.100 (MT5) ════╗\n"
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
                        ? "  [RANGING -> SL " + DoubleToString(SL_ATR_Ranging_Mult,1) + "xATR]"
                        : "  [TREND   -> SL " + DoubleToString(SL_ATR_Factor,      1) + "xATR]") + "\n"
      "  M1 DI(1)  : +" + DoubleToString(g_M1PlusDI,  1)
                     + " / -" + DoubleToString(g_M1MinusDI, 1)            + "\n"
      "  M1 DI(2)  : +" + DoubleToString(g_M1PlusDI2,  1)
                     + " / -" + DoubleToString(g_M1MinusDI2, 1)
                     + "  [pre-sweep]"                                     + "\n"
      "────────────────────────────────────────\n"
      "  LQS lb    : " + IntegerToString(LQS_Lookback) + " bars"          + "\n"
      "  SELL zone : " + DoubleToString(g_LQS_SwingHigh, 2)
                     + "  (price +" + DoubleToString(distSell, 1) + ")"   + "\n"
      "  BUY  zone : " + DoubleToString(g_LQS_SwingLow, 2)
                     + "  (price -" + DoubleToString(distBuy, 1) + ")"    + "\n"
      "  TP fixed  : " + (LQS_TP_Fixed > 0.0
                          ? DoubleToString(LQS_TP_Fixed, 2) + " (fixed)"
                          : "OFF (trailing only)")                         + "\n"
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
