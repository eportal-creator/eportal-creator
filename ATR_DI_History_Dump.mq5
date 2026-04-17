//+------------------------------------------------------------------+
//|                   ATR DI History Dump  v1.20                     |
//|  Adds OHLC, ATR, LQS swing levels, wick size, and signal flag.  |
//|  Use to analyse LQS_Wick_Min_ATR and DI_Spread_Filter impact.   |
//+------------------------------------------------------------------+
#property copyright "Project ATR"
#property version   "1.20"
#property script_show_inputs true

input datetime From_Time      = D'2026.04.17 12:00:00';
input datetime To_Time        = D'2026.04.17 14:48:00';
input int      ADX_Period     = 14;
input int      LQS_Lookback   = 20;
input double   ATR_Period_Inp = 14;

void OnStart()
{
   Print("═══════════════════════════════════════════════════════════════════");
   Print("  LQS OHLC + DI DUMP  |  Symbol=", Symbol(), "  |  ADX=", ADX_Period,
         "  |  LQS_Lookback=", LQS_Lookback);
   Print("  From: ", TimeToString(From_Time, TIME_DATE|TIME_MINUTES),
         "  ->  To: ", TimeToString(To_Time, TIME_DATE|TIME_MINUTES));
   Print("═══════════════════════════════════════════════════════════════════");

   int h_M1  = iADX(Symbol(), PERIOD_M1, ADX_Period);
   int h_ATR = iATR(Symbol(), PERIOD_M1, (int)ATR_Period_Inp);

   if(h_M1 == INVALID_HANDLE || h_ATR == INVALID_HANDLE)
   { Print("ERROR: Cannot create indicator handles."); return; }

   int wait = 0;
   while((BarsCalculated(h_M1) < 10 || BarsCalculated(h_ATR) < 10) && wait < 50)
   { Sleep(100); wait++; }

   datetime m1Times[];
   ArraySetAsSeries(m1Times, false);
   int barCount = CopyTime(Symbol(), PERIOD_M1, From_Time, To_Time, m1Times);

   if(barCount <= 0)
   { Print("ERROR: No M1 bars found."); IndicatorRelease(h_M1); IndicatorRelease(h_ATR); return; }

   Print("  Bars in range: ", barCount);
   Print("  Note: LQS signal uses bar[1] — trade fires on bar[0] open (next bar).");
   Print("  Wick = how far bar HIGH poked above swing high (SELL) or LOW below swing low (BUY).");
   Print("───────────────────────────────────────────────────────────────────");
   Print("  Bar Time   │  Open    High    Low     Close  │  ATR  │SwingH  SwingL│ Wick  │LQS?│ M1+DI  M1-DI  Spread");
   Print("───────────────────────────────────────────────────────────────────");

   for(int i = 0; i < barCount; i++)
   {
      datetime barTime = m1Times[i];
      int shift = Bars(Symbol(), PERIOD_M1, barTime, TimeCurrent()) - 1;
      if(shift < 0) shift = 0;

      // OHLC
      double o = iOpen (Symbol(), PERIOD_M1, shift);
      double h = iHigh (Symbol(), PERIOD_M1, shift);
      double l = iLow  (Symbol(), PERIOD_M1, shift);
      double c = iClose(Symbol(), PERIOD_M1, shift);

      // ATR (bar 1 of this bar = shift+1)
      double atrBuf[]; ArraySetAsSeries(atrBuf, true);
      double atr = (CopyBuffer(h_ATR, 0, shift+1, 1, atrBuf) >= 1) ? atrBuf[0] : 0.0;

      // M1 DI at this bar
      double m1Pdi[], m1Mdi[]; ArraySetAsSeries(m1Pdi,true); ArraySetAsSeries(m1Mdi,true);
      bool diOk = (CopyBuffer(h_M1, 1, shift, 1, m1Pdi) >= 1 &&
                   CopyBuffer(h_M1, 2, shift, 1, m1Mdi) >= 1);
      double pdi = diOk ? m1Pdi[0] : 0.0;
      double mdi = diOk ? m1Mdi[0] : 0.0;

      // LQS swing high/low: max/min of bars [shift+2 .. shift+LQS_Lookback+1]
      double highs[], lows[];
      ArraySetAsSeries(highs, true); ArraySetAsSeries(lows, true);
      double swingH = 0.0, swingL = 0.0;
      if(CopyHigh(Symbol(), PERIOD_M1, shift+2, LQS_Lookback, highs) >= LQS_Lookback)
         swingH = highs[ArrayMaximum(highs)];
      if(CopyLow (Symbol(), PERIOD_M1, shift+2, LQS_Lookback, lows)  >= LQS_Lookback)
         swingL = lows[ArrayMinimum(lows)];

      // LQS signal check
      bool lqsSell = (swingH > 0 && h > swingH && c < swingH);
      bool lqsBuy  = (swingL > 0 && l < swingL && c > swingL);
      string lqsFlag = lqsSell ? "SELL" : (lqsBuy ? "BUY " : "    ");

      // Wick size
      double wick = 0.0;
      if(lqsSell) wick = h - swingH;
      if(lqsBuy)  wick = swingL - l;

      // Spread: for SELL counter = +DI - -DI; for BUY counter = -DI - +DI
      double spread = lqsSell ? (pdi - mdi) : (mdi - pdi);

      // Min wick needed
      double minWick = atr * 0.3;
      string wickStr = (lqsSell || lqsBuy)
                       ? StringFormat("%5.2f", wick) + (wick >= minWick ? " OK " : " LOW")
                       : "  -  ";

      Print("  ", TimeToString(barTime, TIME_MINUTES), "  │",
            StringFormat(" %7.2f %7.2f %7.2f %7.2f │", o, h, l, c),
            StringFormat(" %4.2f │", atr),
            StringFormat("%7.2f %7.2f│", swingH, swingL),
            " ", wickStr, " │", lqsFlag, "│",
            StringFormat(" %5.2f  %5.2f  %+6.2f", pdi, mdi,
                         (lqsSell || lqsBuy) ? spread : (pdi - mdi)));
   }

   Print("═══════════════════════════════════════════════════════════════════");
   Print("  Done. Spread shown = counter-DI spread at signal bar.");
   Print("  Wick OK = >= 0.3 x ATR. Wick LOW = < 0.3 x ATR (would be blocked).");
   Print("═══════════════════════════════════════════════════════════════════");

   IndicatorRelease(h_M1);
   IndicatorRelease(h_ATR);
}
//+------------------------------------------------------------------+
