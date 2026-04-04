//+------------------------------------------------------------------+
//|  XAUUSD M1 Scalper — EMA8/EMA200 + RSI                          |
//|  Singapore Session: 06:00–20:00 SGT (UTC+8)                     |
//|  Strategy: EMA8 vs EMA200 trend filter, RSI momentum entries    |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Scalper"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input Parameters
input group "=== SYMBOL & TIMEFRAME ==="
input string   InpSymbol       = "XAUUSD";        // Symbol

input group "=== SESSION FILTER (Singapore Time UTC+8) ==="
input int      InpStartHour    = 6;               // Session Start Hour (SGT)
input int      InpStartMin     = 0;               // Session Start Minute (SGT)
input int      InpEndHour      = 20;              // Session End Hour (SGT)
input int      InpEndMin       = 0;               // Session End Minute (SGT)

input group "=== INDICATORS ==="
input int      InpEMA8Period   = 8;               // EMA Fast Period
input int      InpEMA200Period = 200;             // EMA Slow Period
input int      InpRSIPeriod    = 14;              // RSI Period
input int      InpRSIOverbought= 70;              // RSI Overbought Level
input int      InpRSIOversold  = 30;              // RSI Oversold Level

input group "=== ENTRY SIGNALS ==="
input bool     InpUseCross     = true;            // EMA8 Cross Signal
input bool     InpUsePullback  = true;            // EMA8 Pullback Signal
input bool     InpUseRSIBreak  = true;            // RSI Mid-Level Break Signal
input int      InpRSIMid       = 50;              // RSI Mid-Level

input group "=== RISK MANAGEMENT ==="
input double   InpLotSize      = 0.10;            // Lot Size
input double   InpTP_Pips      = 15.0;            // Take Profit (pips)
input double   InpSL_Pips      = 10.0;            // Stop Loss (pips)
input int      InpMaxTrades    = 3;               // Max Open Positions
input int      InpCooldownBars = 3;               // Bars cooldown after trade open
input double   InpMaxSpread    = 30.0;            // Max Spread (points) allowed

input group "=== TRAILING STOP ==="
input bool     InpUseTrailing  = true;            // Enable Trailing Stop
input double   InpTrailStart   = 8.0;             // Trail Start (pips profit)
input double   InpTrailStep    = 5.0;             // Trail Step (pips)

input group "=== MAGIC ==="
input long     InpMagic        = 202404001;       // Magic Number

//--- Global variables
CTrade         trade;
CPositionInfo  posInfo;

int            handleEMA8;
int            handleEMA200;
int            handleRSI;

double         ema8[];
double         ema200[];
double         rsi[];

double         pipSize;          // 1 pip in price
datetime       lastBarTime = 0;
datetime       lastTradeBar = 0;
int            barsSinceLastTrade = 0;

//+------------------------------------------------------------------+
//| Expert initialisation                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   // Pip size for XAUUSD (2 decimal digits → 1 pip = 1.0, point = 0.01)
   // MT5 XAUUSD: Digits=2, Point=0.01, so 1 pip = 1 * Point * 100 = 0.01*100 won't work
   // For XAUUSD: price ~4676, digits=2, point=0.01
   // 1 pip convention for gold = $1.00 move = 100 points
   // We treat 1 "pip" = 10 points = 0.10 price units for scalping
   // Adjust: if digits=2 then point=0.01 and 1pip=0.10 (10 points)
   pipSize = SymbolInfoDouble(InpSymbol, SYMBOL_POINT) * 10.0;
   if(Digits() <= 2) pipSize = 0.10; // XAUUSD standard

   // Create indicator handles on M1
   handleEMA8   = iMA(InpSymbol, PERIOD_M1, InpEMA8Period,   0, MODE_EMA, PRICE_CLOSE);
   handleEMA200 = iMA(InpSymbol, PERIOD_M1, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI    = iRSI(InpSymbol, PERIOD_M1, InpRSIPeriod,   PRICE_CLOSE);

   if(handleEMA8 == INVALID_HANDLE || handleEMA200 == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles");
      return INIT_FAILED;
   }

   ArraySetAsSeries(ema8,   true);
   ArraySetAsSeries(ema200, true);
   ArraySetAsSeries(rsi,    true);

   Print("XAUUSD M1 Scalper initialised | PipSize=", pipSize,
         " | TP=", InpTP_Pips, " pips | SL=", InpSL_Pips, " pips");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEMA8   != INVALID_HANDLE) IndicatorRelease(handleEMA8);
   if(handleEMA200 != INVALID_HANDLE) IndicatorRelease(handleEMA200);
   if(handleRSI    != INVALID_HANDLE) IndicatorRelease(handleRSI);
}

//+------------------------------------------------------------------+
//| Singapore time check (UTC+8)                                     |
//+------------------------------------------------------------------+
bool IsInSession()
{
   datetime utcNow   = TimeGMT();
   datetime sgtNow   = utcNow + 8 * 3600;            // SGT = UTC+8
   MqlDateTime sgt;
   TimeToStruct(sgtNow, sgt);

   int sgtMinutes = sgt.hour * 60 + sgt.min;
   int startMin   = InpStartHour * 60 + InpStartMin;
   int endMin     = InpEndHour   * 60 + InpEndMin;

   return (sgtMinutes >= startMin && sgtMinutes < endMin);
}

//+------------------------------------------------------------------+
//| Count open positions by magic                                    |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type = -1)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == InpSymbol && posInfo.Magic() == InpMagic)
         {
            if(type == -1 || posInfo.PositionType() == type)
               count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Manage trailing stops                                            |
//+------------------------------------------------------------------+
void ManageTrailing()
{
   if(!InpUseTrailing) return;

   double trailStartPrice = InpTrailStart * pipSize;
   double trailStepPrice  = InpTrailStep  * pipSize;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != InpSymbol || posInfo.Magic() != InpMagic) continue;

      double currentPrice = posInfo.PositionType() == POSITION_TYPE_BUY
                            ? SymbolInfoDouble(InpSymbol, SYMBOL_BID)
                            : SymbolInfoDouble(InpSymbol, SYMBOL_ASK);

      double openPrice = posInfo.PriceOpen();
      double curSL     = posInfo.StopLoss();
      ulong  ticket    = posInfo.Ticket();

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double profit = currentPrice - openPrice;
         if(profit >= trailStartPrice)
         {
            double newSL = currentPrice - trailStepPrice;
            newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS));
            if(newSL > curSL + pipSize * 0.5)
               trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
         }
      }
      else // SELL
      {
         double profit = openPrice - currentPrice;
         if(profit >= trailStartPrice)
         {
            double newSL = currentPrice + trailStepPrice;
            newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS));
            if(newSL < curSL - pipSize * 0.5 || curSL == 0)
               trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all positions at end of session                            |
//+------------------------------------------------------------------+
void CloseAllOnSessionEnd()
{
   if(IsInSession()) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == InpSymbol && posInfo.Magic() == InpMagic)
            trade.PositionClose(posInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Main tick handler                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   // Close positions outside session
   CloseAllOnSessionEnd();

   // Manage trailing stop on every tick
   ManageTrailing();

   // Only process new bar
   datetime currentBar = iTime(InpSymbol, PERIOD_M1, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;
   barsSinceLastTrade++;

   // Session filter
   if(!IsInSession()) return;

   // Spread filter
   double spread = SymbolInfoInteger(InpSymbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
   {
      Print("Spread too wide: ", spread, " points. Skipping.");
      return;
   }

   // Position limit
   int totalPos = CountPositions();
   if(totalPos >= InpMaxTrades) return;

   // Cooldown after last trade
   if(barsSinceLastTrade < InpCooldownBars) return;

   // Fetch indicator values (need 3 bars for crossover)
   if(CopyBuffer(handleEMA8,   0, 0, 4, ema8)   < 4) return;
   if(CopyBuffer(handleEMA200, 0, 0, 4, ema200) < 4) return;
   if(CopyBuffer(handleRSI,    0, 0, 3, rsi)    < 3) return;

   // Current values (index 0 = current bar, 1 = previous)
   double ema8_cur  = ema8[0],  ema8_prev  = ema8[1];
   double ema200_cur= ema200[0],ema200_prev= ema200[1];
   double rsi_cur   = rsi[0],   rsi_prev   = rsi[1];

   bool bullTrend = (ema8_cur > ema200_cur);     // EMA8 above EMA200
   bool bearTrend = (ema8_cur < ema200_cur);     // EMA8 below EMA200

   int buyBias  = 0;  // signal score
   int sellBias = 0;

   //--- SIGNAL 1: EMA8 Cross over EMA200
   if(InpUseCross)
   {
      if(ema8_prev < ema200_prev && ema8_cur >= ema200_cur) buyBias  += 2;
      if(ema8_prev > ema200_prev && ema8_cur <= ema200_cur) sellBias += 2;
   }

   //--- SIGNAL 2: Pullback to EMA8 in trend direction (price bounces off EMA8)
   if(InpUsePullback)
   {
      double close0 = iClose(InpSymbol, PERIOD_M1, 1);  // closed bar
      double close1 = iClose(InpSymbol, PERIOD_M1, 2);  // 2 bars ago
      double low1   = iLow(InpSymbol,   PERIOD_M1, 1);
      double high1  = iHigh(InpSymbol,  PERIOD_M1, 1);

      // Bullish: trend up, price dipped toward EMA8 then closed above it
      if(bullTrend && low1 <= ema8[1] * 1.001 && close0 > ema8[0])
         buyBias++;

      // Bearish: trend down, price popped toward EMA8 then closed below it
      if(bearTrend && high1 >= ema8[1] * 0.999 && close0 < ema8[0])
         sellBias++;
   }

   //--- SIGNAL 3: RSI mid-level (50) cross for momentum confirmation
   if(InpUseRSIBreak)
   {
      // RSI crossed above 50 from below while bullish trend
      if(bullTrend && rsi_prev < InpRSIMid && rsi_cur >= InpRSIMid) buyBias++;
      // RSI crossed below 50 from above while bearish trend
      if(bearTrend && rsi_prev > InpRSIMid && rsi_cur <= InpRSIMid) sellBias++;

      // RSI momentum: overbought filter (avoid buying into overbought)
      if(rsi_cur >= InpRSIOverbought) buyBias  = MathMin(buyBias,  0);
      if(rsi_cur <= InpRSIOversold)   sellBias = MathMin(sellBias, 0);
   }

   //--- Execute trades based on bias score
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS);

   double tpDist = InpTP_Pips * pipSize;
   double slDist = InpSL_Pips * pipSize;

   if(buyBias >= 1 && CountPositions(POSITION_TYPE_BUY) == 0)
   {
      double tp = NormalizeDouble(ask + tpDist, digits);
      double sl = NormalizeDouble(ask - slDist, digits);

      string comment = StringFormat("Scalp_BUY bias=%d EMA8=%.2f EMA200=%.2f RSI=%.1f",
                                     buyBias, ema8_cur, ema200_cur, rsi_cur);
      if(trade.Buy(InpLotSize, InpSymbol, ask, sl, tp, comment))
      {
         Print("BUY opened | ", comment, " | TP=", tp, " SL=", sl);
         lastTradeBar       = currentBar;
         barsSinceLastTrade = 0;
      }
   }
   else if(sellBias >= 1 && CountPositions(POSITION_TYPE_SELL) == 0)
   {
      double tp = NormalizeDouble(bid - tpDist, digits);
      double sl = NormalizeDouble(bid + slDist, digits);

      string comment = StringFormat("Scalp_SELL bias=%d EMA8=%.2f EMA200=%.2f RSI=%.1f",
                                     sellBias, ema8_cur, ema200_cur, rsi_cur);
      if(trade.Sell(InpLotSize, InpSymbol, bid, sl, tp, comment))
      {
         Print("SELL opened | ", comment, " | TP=", tp, " SL=", sl);
         lastTradeBar       = currentBar;
         barsSinceLastTrade = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Chart event — display dashboard                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam,
                  const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE) DrawDashboard();
}

void DrawDashboard()
{
   string prefix = "XAUScalp_";
   int    x = 10, y = 20;
   color  clrTitle = clrGold;
   color  clrInfo  = clrWhite;
   color  clrSess  = IsInSession() ? clrLime : clrOrangeRed;

   // Title
   CreateLabel(prefix+"title",  x, y,      "XAUUSD M1 Scalper",         clrTitle, 12, true);
   CreateLabel(prefix+"sess",   x, y+20,   IsInSession()
               ? "Session: ACTIVE (SGT 06-20h)" : "Session: CLOSED", clrSess);
   CreateLabel(prefix+"lot",    x, y+38,   "Lot: "   + DoubleToString(InpLotSize, 2), clrInfo);
   CreateLabel(prefix+"tp",     x, y+54,   "TP: "    + DoubleToString(InpTP_Pips, 1) + " pips", clrInfo);
   CreateLabel(prefix+"sl",     x, y+70,   "SL: "    + DoubleToString(InpSL_Pips, 1) + " pips", clrInfo);
   CreateLabel(prefix+"pos",    x, y+86,   "Positions: " + IntegerToString(CountPositions()), clrInfo);

   ChartRedraw();
}

void CreateLabel(string name, int x, int y, string text,
                 color clr, int size=9, bool bold=false)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   }
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   size);
   ObjectSetString (0, name, OBJPROP_FONT,       bold ? "Arial Bold" : "Arial");
}
//+------------------------------------------------------------------+
