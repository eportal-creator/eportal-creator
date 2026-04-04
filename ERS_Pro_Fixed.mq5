//+------------------------------------------------------------------+
//| EMA Rejection Scalper (ERS) - PRO FIXED VERSION                  |
//| Fixes: magic number, HasPosition filter, INVALID_HANDLE,         |
//|        R:R ratio, OnDeinit, session-end auto-close               |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//---- Inputs
input double LotSize         = 0.01;
input double TakeProfitPrice = 1.8;   // FIX: was 1.2 — TP must be > SL for positive R:R
input double StopLossPrice   = 1.2;   // FIX: was 1.8 — now R:R = 1.5:1

input int FastEMA  = 8;
input int TrendEMA = 200;

input int    MaxSpreadPoints = 2000;
input int    MagicNumber     = 7777;

input int    SidewaysRange = 120;
input double WickRatio     = 1.5;
input int    MinDistance   = 30;
input int    MaxDistance   = 120;

input int StartHour = 6;
input int EndHour   = 20;

//---- Global
int      emaFastHandle, emaTrendHandle;
MqlRates rates[20];
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // FIX 1: Apply magic number to all trades placed by this EA
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);

   emaFastHandle  = iMA(_Symbol, PERIOD_M1, FastEMA,  0, MODE_EMA, PRICE_CLOSE);
   emaTrendHandle = iMA(_Symbol, PERIOD_M1, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);

   // FIX 2: Validate indicator handles before proceeding
   if(emaFastHandle == INVALID_HANDLE || emaTrendHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create EMA indicator handles. EA will not run.");
      return INIT_FAILED;
   }

   Print("ERS PRO Fixed | Magic=", MagicNumber,
         " | TP=", TakeProfitPrice, " | SL=", StopLossPrice,
         " | R:R=", DoubleToString(TakeProfitPrice / StopLossPrice, 2), ":1");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT — FIX 3: Release indicator handles on removal             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaFastHandle  != INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaTrendHandle != INVALID_HANDLE) IndicatorRelease(emaTrendHandle);
   Comment("");  // clear dashboard
}

//+------------------------------------------------------------------+
//| LOAD RATES                                                       |
//+------------------------------------------------------------------+
bool LoadRates()
{
   return (CopyRates(_Symbol, PERIOD_M1, 0, 20, rates) >= 20);
}

//+------------------------------------------------------------------+
//| NEW BAR DETECTION                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = rates[0].time;
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| SGT TIME (auto broker offset)                                    |
//+------------------------------------------------------------------+
datetime GetSGTime()
{
   datetime serverTime  = TimeCurrent();
   datetime gmtTime     = TimeGMT();
   int      brokerOffset = (int)((serverTime - gmtTime) / 3600);
   return serverTime + (8 - brokerOffset) * 3600;
}

//+------------------------------------------------------------------+
//| TRADING TIME                                                     |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime t;
   TimeToStruct(GetSGTime(), t);
   return (t.hour >= StartHour && t.hour < EndHour);
}

//+------------------------------------------------------------------+
//| GET EMA VALUE                                                    |
//+------------------------------------------------------------------+
double GetEMA(int handle)
{
   double buffer[];
   if(CopyBuffer(handle, 0, 0, 1, buffer) > 0)
      return buffer[0];
   return 0;
}

//+------------------------------------------------------------------+
//| SPREAD FILTER                                                    |
//+------------------------------------------------------------------+
bool IsSpreadOK()
{
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                    SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   return (spread <= MaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| SIDEWAYS FILTER (last 10 closed bars)                            |
//+------------------------------------------------------------------+
bool IsSideways()
{
   double high = rates[1].high;
   double low  = rates[1].low;
   for(int i = 1; i <= 10; i++)
   {
      if(rates[i].high > high) high = rates[i].high;
      if(rates[i].low  < low)  low  = rates[i].low;
   }
   return ((high - low) < SidewaysRange * _Point);
}

//+------------------------------------------------------------------+
//| REJECTION CANDLE (uses rates[2] — fully closed, 2 bars ago)      |
//+------------------------------------------------------------------+
bool IsBuyRejection()
{
   double body = MathAbs(rates[2].close - rates[2].open);
   double wick = MathMin(rates[2].open, rates[2].close) - rates[2].low;
   if(body == 0) return false;   // doji guard
   return (wick > body * WickRatio);
}

bool IsSellRejection()
{
   double body = MathAbs(rates[2].close - rates[2].open);
   double wick = rates[2].high - MathMax(rates[2].open, rates[2].close);
   if(body == 0) return false;   // doji guard
   return (wick > body * WickRatio);
}

//+------------------------------------------------------------------+
//| DISTANCE (price to EMA in points)                                |
//+------------------------------------------------------------------+
double Distance(double price, double ema)
{
   return MathAbs(price - ema) / _Point;
}

//+------------------------------------------------------------------+
//| POSITION CHECK — FIX 4: filter by magic number                   |
//+------------------------------------------------------------------+
bool HasPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| SESSION-END AUTO-CLOSE — FIX 5: close all EA positions at 20:00  |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         trade.PositionClose(PositionGetTicket(i));
   }
}

//+------------------------------------------------------------------+
//| NORMALIZE PRICE                                                  |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
//| OPEN BUY                                                         |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl    = NormalizePrice(price - StopLossPrice);
   double tp    = NormalizePrice(price + TakeProfitPrice);
   trade.Buy(LotSize, _Symbol, price, sl, tp, "ERS BUY");
}

//+------------------------------------------------------------------+
//| OPEN SELL                                                        |
//+------------------------------------------------------------------+
void OpenSell()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl    = NormalizePrice(price + StopLossPrice);
   double tp    = NormalizePrice(price - TakeProfitPrice);
   trade.Sell(LotSize, _Symbol, price, sl, tp, "ERS SELL");
}

//+------------------------------------------------------------------+
//| DASHBOARD                                                        |
//+------------------------------------------------------------------+
void DrawDashboard(double emaFast, double emaTrend)
{
   string text =
      "=== ERS EA PRO (FIXED) ===\n"                                             +
      "SG Time : " + TimeToString(GetSGTime(), TIME_MINUTES)                    + "\n" +
      "Session : " + (IsTradingTime() ? "ACTIVE" : "CLOSED")                   + "\n" +
      "Spread  : " + (IsSpreadOK()    ? "OK"     : "WIDE")                     + "\n" +
      "Market  : " + (IsSideways()    ? "SIDEWAYS (no trade)" : "TRENDING")    + "\n" +
      "Position: " + (HasPosition()   ? "OPEN"   : "NONE")                     + "\n" +
      "EMA8    : " + DoubleToString(emaFast,  2)                                + "\n" +
      "EMA200  : " + DoubleToString(emaTrend, 2)                                + "\n" +
      "TP / SL : " + DoubleToString(TakeProfitPrice,2) +
               " / " + DoubleToString(StopLossPrice,2) +
               " (R:R " + DoubleToString(TakeProfitPrice/StopLossPrice,2) + ":1)";
   Comment(text);
}

//+------------------------------------------------------------------+
//| MAIN                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!LoadRates()) return;

   double emaFast  = GetEMA(emaFastHandle);
   double emaTrend = GetEMA(emaTrendHandle);

   DrawDashboard(emaFast, emaTrend);

   // FIX 5: Auto-close all positions when session ends
   if(!IsTradingTime())
   {
      if(HasPosition()) CloseAllPositions();
      return;
   }

   if(!IsNewBar())   return;   // process once per closed bar only
   if(!IsSpreadOK()) return;
   if(IsSideways())  return;
   if(HasPosition()) return;

   double price = rates[1].close;   // last fully closed bar
   double dist  = Distance(price, emaFast);

   if(dist < MinDistance || dist > MaxDistance) return;

   // Confirmation: rates[1] (closed) breaks out of rates[2] (rejection) range
   bool confirmBuy  = rates[1].close > rates[2].high;
   bool confirmSell = rates[1].close < rates[2].low;

   // BUY: uptrend + price at/below EMA8 + rejection + confirmation
   if(price > emaTrend && price <= emaFast)
      if(IsBuyRejection() && confirmBuy)
         OpenBuy();

   // SELL: downtrend + price at/above EMA8 + rejection + confirmation
   if(price < emaTrend && price >= emaFast)
      if(IsSellRejection() && confirmSell)
         OpenSell();
}
//+------------------------------------------------------------------+
