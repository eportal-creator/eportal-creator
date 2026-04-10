//+------------------------------------------------------------------+
//|                   ATR DI History Dump                            |
//|  Script — run on M1 chart to print exact ADX/DI values at each  |
//|  M1 bar in the specified time range.                             |
//|                                                                  |
//|  HOW TO USE:                                                     |
//|  1. Copy to MT5 → File → Open Data Folder → MQL5 → Scripts      |
//|  2. Compile in MetaEditor (F7)                                   |
//|  3. Attach to any XAUUSD M1 chart                               |
//|  4. Set From_Time / To_Time in the input dialog                  |
//|  5. Results appear in MT5 → View → Terminal → Experts tab       |
//|     Copy the text out for analysis.                              |
//+------------------------------------------------------------------+
#property copyright "Project ATR"
#property version   "1.00"
#property script_show_inputs true

input datetime From_Time  = D'2026.04.10 10:50:00';  // Start (broker server time)
input datetime To_Time    = D'2026.04.10 11:20:00';  // End   (broker server time)
input int      ADX_Period = 14;                        // ADX period (must match EA)

//-------------------------------------------------------------------
void OnStart()
{
   Print("═══════════════════════════════════════════════════════");
   Print("  ATR DI HISTORY DUMP  |  Symbol=", Symbol(),
         "  |  ADX period=", ADX_Period);
   Print("  From: ", TimeToString(From_Time, TIME_DATE|TIME_MINUTES),
         "  →  To: ", TimeToString(To_Time, TIME_DATE|TIME_MINUTES),
         "  (broker time)");
   Print("═══════════════════════════════════════════════════════");

   // ── Create indicator handles ──────────────────────────────────
   int h_M1  = iADX(Symbol(), PERIOD_M1, ADX_Period);
   int h_H1  = iADX(Symbol(), PERIOD_H1, ADX_Period);

   if(h_M1 == INVALID_HANDLE || h_H1 == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create ADX handles. Is the symbol correct?");
      return;
   }

   // Wait for indicator data to be ready (up to 5 seconds)
   int wait = 0;
   while((BarsCalculated(h_M1) < 10 || BarsCalculated(h_H1) < 10) && wait < 50)
   { Sleep(100); wait++; }

   if(BarsCalculated(h_M1) < 10)
   { Print("ERROR: M1 ADX data not ready after 5s — try again."); return; }

   // ── Copy M1 bar times in range ────────────────────────────────
   datetime m1Times[];
   ArraySetAsSeries(m1Times, false);  // oldest first
   int barCount = CopyTime(Symbol(), PERIOD_M1, From_Time, To_Time, m1Times);

   if(barCount <= 0)
   {
      Print("ERROR: No M1 bars found in the specified range.");
      Print("  Check that From_Time < To_Time and the date has M1 data.");
      IndicatorRelease(h_M1); IndicatorRelease(h_H1);
      return;
   }

   Print("  M1 bars found in range: ", barCount);
   Print("───────────────────────────────────────────────────────");
   Print("  Bar Time (broker)  │ M1 ADX │ M1 +DI │ M1 -DI │ M1 Dir │ H1 ADX │ H1 +DI │ H1 -DI │ H1 Dir │ REV SELL v2.14");
   Print("───────────────────────────────────────────────────────");

   // ── Loop through each bar (oldest → newest) ───────────────────
   for(int i = 0; i < barCount; i++)
   {
      datetime barTime = m1Times[i];

      // Shift from current bar (bar 0) — pos 0 = current forming bar
      // shift = iBarShift equivalent: how many bars ago is barTime?
      int m1Shift = Bars(Symbol(), PERIOD_M1, barTime, TimeCurrent()) - 1;
      int h1Shift = Bars(Symbol(), PERIOD_H1, barTime, TimeCurrent()) - 1;

      if(m1Shift < 0) m1Shift = 0;
      if(h1Shift < 0) h1Shift = 0;

      // Read M1 ADX values at this bar
      double m1Buf[], m1Pdi[], m1Mdi[];
      ArraySetAsSeries(m1Buf, true);
      ArraySetAsSeries(m1Pdi, true);
      ArraySetAsSeries(m1Mdi, true);

      bool m1Ok = (CopyBuffer(h_M1, 0, m1Shift, 1, m1Buf) >= 1 &&
                   CopyBuffer(h_M1, 1, m1Shift, 1, m1Pdi) >= 1 &&
                   CopyBuffer(h_M1, 2, m1Shift, 1, m1Mdi) >= 1);

      // Read H1 ADX values at the H1 bar containing this M1 bar
      double h1Buf[], h1Pdi[], h1Mdi[];
      ArraySetAsSeries(h1Buf, true);
      ArraySetAsSeries(h1Pdi, true);
      ArraySetAsSeries(h1Mdi, true);

      bool h1Ok = (CopyBuffer(h_H1, 0, h1Shift, 1, h1Buf) >= 1 &&
                   CopyBuffer(h_H1, 1, h1Shift, 1, h1Pdi) >= 1 &&
                   CopyBuffer(h_H1, 2, h1Shift, 1, h1Mdi) >= 1);

      // Format output
      string m1Dir   = !m1Ok ? "N/A" : (m1Pdi[0] > m1Mdi[0] ? "BULL(+)" : (m1Mdi[0] > m1Pdi[0] ? "BEAR(-)" : "EQUAL"));
      string h1Dir   = !h1Ok ? "N/A" : (h1Pdi[0] > h1Mdi[0] ? "BULL(+)" : (h1Mdi[0] > h1Pdi[0] ? "BEAR(-)" : "EQUAL"));

      // v2.14 REV SELL guard check: blocked if M1 +DI > -DI
      string v214 = "N/A";
      if(m1Ok)
         v214 = (m1Pdi[0] > m1Mdi[0]) ? "BLOCKED (M1 bull)" : "ALLOWED (M1 bear)";

      string m1Str = !m1Ok ? "  ERR  |  ERR  |  ERR  |  ERR  " :
                     StringFormat(" %5.2f  | %5.2f  | %5.2f  | %s",
                                  m1Buf[0], m1Pdi[0], m1Mdi[0], m1Dir);

      string h1Str = !h1Ok ? "  ERR  |  ERR  |  ERR  |  ERR  " :
                     StringFormat(" %5.2f  | %5.2f  | %5.2f  | %s",
                                  h1Buf[0], h1Pdi[0], h1Mdi[0], h1Dir);

      Print("  ", TimeToString(barTime, TIME_DATE|TIME_MINUTES),
            "  │", m1Str,
            "│", h1Str,
            "│ ", v214);
   }

   Print("═══════════════════════════════════════════════════════");
   Print("  Done. Check ALLOWED/BLOCKED column for v2.14 verdict.");
   Print("  Note: values shown are for each BAR (bar-1 signal bar).");
   Print("  Trade at HH:MM fires using bar (HH:MM - 1min) values.");
   Print("═══════════════════════════════════════════════════════");

   IndicatorRelease(h_M1);
   IndicatorRelease(h_H1);
}
//+------------------------------------------------------------------+
