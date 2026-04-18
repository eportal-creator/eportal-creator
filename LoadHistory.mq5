//+------------------------------------------------------------------+
//|                        LoadHistory.mq5                           |
//|  Forces MT5 to fetch and cache M1 history for a date range.     |
//|  Run this script once before using LQS_TP_Optimizer on old data.|
//+------------------------------------------------------------------+
#property script_show_inputs
#property copyright "Project ATR"
#property version   "1.00"
#property description "Force-loads M1 history so the optimizer can read it"

input datetime DateFrom = D'2026.01.01 00:00';
input datetime DateTo   = D'2026.01.31 23:59';

void OnStart()
{
   Print("LoadHistory: requesting M1 data from ",
         TimeToString(DateFrom, TIME_DATE), " to ",
         TimeToString(DateTo,   TIME_DATE), " ...");

   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int attempts = 0;
   int copied   = 0;

   while(attempts < 20)
   {
      copied = CopyRates(Symbol(), PERIOD_M1, DateFrom, DateTo, rates);
      if(copied > 0) break;
      Sleep(1000);
      attempts++;
   }

   if(copied > 0)
      Print("LoadHistory: OK — ", copied, " M1 bars loaded. Run the optimizer now.");
   else
      Print("LoadHistory: FAILED after ", attempts, " attempts. ",
            "Check broker provides this history or scroll back manually on the chart.");
}
//+------------------------------------------------------------------+
