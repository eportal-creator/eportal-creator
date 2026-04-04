//+------------------------------------------------------------------+
//| EMA Rejection Scalper (ERS) - PRO FINAL (ALL ISSUES RESOLVED)    |
//| Fix 1: Distance uses EMA at bar 2 (matched to rejection candle)  |
//| Fix 2: IsSideways/IsSpike cached — no repeated tick-level loops  |
//| Fix 3: price variable used consistently throughout               |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//---- Inputs
input double LotSize         = 0.01;
input double TakeProfitPrice = 1.8;
input double StopLossPrice   = 1.2;

input int FastEMA  = 8;
input int TrendEMA = 200;

input int    MaxSpreadPoints    = 2000;
input int    MagicNumber        = 7777;

input int    SidewaysRange      = 120;
input double WickRatio          = 1.5;
input int    MinDistance        = 30;
input int    MaxDistance        = 120;

input int    StartHour          = 6;
input int    EndHour            = 20;

input double EMATolerancePoints = 10;
input double SpikeMultiplier    = 2.0;

//---- Global
int      emaFastHandle, emaTrendHandle;
MqlRates rates[20];
datetime lastBarTime = 0;

// FIX 2: cached per-bar state (avoid re-running loops every tick)
bool g_sideways = false;
bool g_spike    = false;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);

   emaFastHandle  = iMA(_Symbol, PERIOD_M1, FastEMA,  0, MODE_EMA, PRICE_CLOSE);
   emaTrendHandle = iMA(_Symbol, PERIOD_M1, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(emaFastHandle == INVALID_HANDLE || emaTrendHandle == INVALID_HANDLE)
   {
      Print("ERROR: EMA handle creation failed. EA will not run.");
      return INIT_FAILED;
   }

   Print("ERS PRO FINAL LOADED | Magic=", MagicNumber,
         " | TP=", TakeProfitPrice, " | SL=", StopLossPrice,
         " | R:R=", DoubleToString(TakeProfitPrice / StopLossPrice, 2), ":1");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaFastHandle  != INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaTrendHandle != INVALID_HANDLE) IndicatorRelease(emaTrendHandle);
   Comment("");
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
   datetime t = rates[0].time;
   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| SGT TIME (auto broker offset)                                    |
//+------------------------------------------------------------------+
datetime GetSGTime()
{
   datetime server = TimeCurrent();
   datetime gmt    = TimeGMT();
   int      offset = (int)((server - gmt) / 3600);
   return server + (8 - offset) * 3600;
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
//| GET EMA AT SHIFT                                                 |
//+------------------------------------------------------------------+
double GetEMA(int handle, int shift)
{
   double buffer[];
   if(CopyBuffer(handle, 0, shift, 1, buffer) > 0)
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
//| SPIKE FILTER (rejection candle vs 6-bar average range)           |
//+------------------------------------------------------------------+
bool IsSpike()
{
   double size = rates[2].high - rates[2].low;

   double avg = 0;
   for(int i = 3; i <= 8; i++)
      avg += (rates[i].high - rates[i].low);
   avg /= 6;

   return (size > avg * SpikeMultiplier);
}

//+------------------------------------------------------------------+
//| REJECTION CANDLE (rates[2] = fully closed, 2 bars ago)           |
//+------------------------------------------------------------------+
bool IsBuyRejection()
{
   double body = MathAbs(rates[2].close - rates[2].open);
   double wick = MathMin(rates[2].open, rates[2].close) - rates[2].low;

   if(body == 0) return false;  // doji guard
   return (wick > body * WickRatio);
}

bool IsSellRejection()
{
   double body = MathAbs(rates[2].close - rates[2].open);
   double wick = rates[2].high - MathMax(rates[2].open, rates[2].close);

   if(body == 0) return false;  // doji guard
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
//| POSITION CHECK (magic-filtered)                                  |
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
//| CLOSE ALL (magic-filtered)                                       |
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
//| DASHBOARD — FIX 2: receives cached values, no loops on every tick |
//+------------------------------------------------------------------+
void DrawDashboard(double emaFast, double emaTrend,
                   bool sideways, bool spike)
{
   string text =
      "=== ERS EA PRO FINAL ===\n"                                             +
      "SG Time : " + TimeToString(GetSGTime(), TIME_MINUTES)                  + "\n" +
      "Session : " + (IsTradingTime() ? "ACTIVE" : "CLOSED")                 + "\n" +
      "Spread  : " + (IsSpreadOK()    ? "OK"     : "WIDE")                   + "\n" +
      "Market  : " + (sideways        ? "SIDEWAYS (skip)" : "TRENDING")      + "\n" +
      "Spike   : " + (spike           ? "YES (skip)"     : "NO")             + "\n" +
      "Position: " + (HasPosition()   ? "OPEN"   : "NONE")                   + "\n" +
      "EMA8    : " + DoubleToString(emaFast,  2)                              + "\n" +
      "EMA200  : " + DoubleToString(emaTrend, 2)                              + "\n" +
      "TP / SL : " + DoubleToString(TakeProfitPrice, 2) +
               " / " + DoubleToString(StopLossPrice, 2) +
               "  (R:R " + DoubleToString(TakeProfitPrice / StopLossPrice, 2) + ":1)";

   Comment(text);
}

//+------------------------------------------------------------------+
//| MAIN                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!LoadRates()) return;

   // EMA at bar 1 (last closed bar) — consistent with price = rates[1].close
   double emaFast  = GetEMA(emaFastHandle,  1);
   double emaTrend = GetEMA(emaTrendHandle, 1);

   // FIX 2: update cached bar-state only on new bar, use cache for dashboard
   if(IsNewBar())
   {
      g_sideways = IsSideways();
      g_spike    = IsSpike();
   }

   DrawDashboard(emaFast, emaTrend, g_sideways, g_spike);

   // Session guard — auto-close outside hours
   if(!IsTradingTime())
   {
      if(HasPosition()) CloseAllPositions();
      return;
   }

   if(!IsNewBar())    return;   // entry logic on new bar only
   if(!IsSpreadOK())  return;
   if(g_sideways)     return;
   if(g_spike)        return;
   if(HasPosition())  return;

   // FIX 3: use price consistently via rates[1].close throughout
   double price = rates[1].close;

   // FIX 1: distance uses EMA at bar 2 — matched to rejection candle (rates[2])
   double emaAtRejection = GetEMA(emaFastHandle, 2);
   double dist           = Distance(rates[2].close, emaAtRejection);
   if(dist < MinDistance || dist > MaxDistance) return;

   // EMA tolerance — widens entry zone slightly
   double tol = EMATolerancePoints * _Point;

   // Closed-candle confirmation: bar 1 breaks out of bar 2 range
   bool confirmBuy  = price > rates[2].high;
   bool confirmSell = price < rates[2].low;

   // BUY: uptrend + confirmation bar at/below EMA8 + rejection + confirm
   if(price > emaTrend && price <= emaFast + tol)
   {
      if(IsBuyRejection() && confirmBuy)
         OpenBuy();
   }

   // SELL: downtrend + confirmation bar at/above EMA8 + rejection + confirm
   if(price < emaTrend && price >= emaFast - tol)
   {
      if(IsSellRejection() && confirmSell)
         OpenSell();
   }
}
//+------------------------------------------------------------------+
