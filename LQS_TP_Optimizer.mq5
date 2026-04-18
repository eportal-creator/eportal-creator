//+------------------------------------------------------------------+
//|                  LQS_TP_Optimizer.mq5               v1.10        |
//|                                                                  |
//|  Replays LQS signal detection over a date range using the same   |
//|  filters as LQS_ZONE_SCALPER_MT5.mq5, then simulates each trade  |
//|  at 8 TP levels to find the optimal TP setting.                  |
//|                                                                  |
//|  v1.10 changes:                                                  |
//|  - TP mode: FIXED DOLLAR (matches LQS_TP_Fixed in EA). The      |
//|    LQS EA uses a fixed $ amount, not an ATR multiple.            |
//|    TP levels tested: $0.20, $0.35, $0.50, $0.75, $1.00, $1.50, |
//|    $2.00, $3.00. Mark current with LQS_TP_Current.              |
//|  - LQS_Trend_Only: skip ranging-mode signals (ADX < threshold). |
//|    Matches new v1.140 filter in LQS_ZONE_SCALPER_MT5.mq5.       |
//|                                                                  |
//|  HOW TO USE:                                                     |
//|  1. Attach to XAUUSD M1 chart                                    |
//|  2. Set DateFrom / DateTo to the period you want to analyse      |
//|  3. Match all inputs to your LQS EA's current settings           |
//|  4. Run — output appears in the Experts / Journal tab            |
//|                                                                  |
//|  SL simulation rule: if both SL and TP hit on the same M1 bar,  |
//|  bar close direction is used as tiebreaker.                      |
//+------------------------------------------------------------------+
#property script_show_inputs
#property copyright "Project ATR"
#property version   "1.20"
#property description "LQS TP Optimizer v1.20 — close-back + body-direction filters"

input group "=== Date Range ==="
input datetime DateFrom              = D'2026.04.13 00:00';
input datetime DateTo                = D'2026.04.17 23:59';

input group "=== LQS Settings (match EA) ==="
input int      LQS_Lookback          = 20;
// Bars back (excl bar[1]) used to define swing high/low.

input double   LQS_Wick_Min_ATR      = 0.3;
// Min poke above/below swing level as a fraction of ATR.

input double   LQS_DI_Spread_Filter  = 30.0;
// Block trade when counter-DI lead >= this on bar[1] OR bar[2].
// Set 0 to disable.

input bool     LQS_M1_DI_Align       = true;
// Require bar[1] M1 DI to align with the trade direction.

input bool     LQS_Trend_Only        = true;
// Block entry when M1 ADX < M1_Ranging_Thresh (ranging mode).
// Matches LQS_Trend_Only in LQS_ZONE_SCALPER_MT5 v1.150.
// Set false to include ranging-mode signals (original behaviour).

input double   LQS_CloseBack_Min_ATR = 0.3;
// Minimum close-back distance (× ATR). SELL: bar[1] close must be at
// least N×ATR below swingHigh. BUY: N×ATR above swingLow. Set 0 to disable.

input bool     LQS_Body_Direction    = true;
// SELL: bar[1] must close in lower 50% of its range (bearish rejection).
// BUY:  bar[1] must close in upper 50% of its range (bullish rejection).
// Set false to disable.

input group "=== Trade / EA Settings (match EA) ==="
input int      ATR_Period            = 14;
input double   SL_ATR_Factor         = 1.5;    // SL when M1 trending (ADX >= threshold)
input double   SL_ATR_Ranging        = 2.0;    // SL when M1 ranging  (ADX <  threshold)
input double   M1_Ranging_Thresh     = 25.0;   // M1 ADX below this → ranging
input double   ATR_Min_Filter        = 1.0;    // Skip if M1 ATR < this ($ value)
input double   ATR_Max_Filter        = 8.0;    // Skip if M1 ATR > this (0 = off)
input int      CooldownMinutes       = 5;      // Min gap between entries (minutes)
input double   ExpireHours           = 0.5;    // Max bars forward before forced close
input double   LotSize               = 0.01;   // Lot size (for $ P&L calculation)

input group "=== TP Testing ==="
input double   LQS_TP_Current        = 0.35;
// Your current LQS_TP_Fixed value — marked with ◄ CURRENT in output.
// NOTE: TP levels are FIXED DOLLAR AMOUNTS (matching LQS_TP_Fixed in EA).

input group "=== Output ==="
input bool     LogEachSignal         = true;
// Print one line per detected signal (time, side, ATR, SL, MFE/result).

//--- Fixed-dollar TP levels to test
#define N_TP 8
static const double TP_LEVELS[N_TP] = { 0.20, 0.35, 0.50, 0.75, 1.00, 1.50, 2.00, 3.00 };

//+------------------------------------------------------------------+
void OnStart()
{
   //--- Validate
   if(DateFrom >= DateTo)
   { Print("ERROR: DateFrom must be earlier than DateTo"); return; }

   int maxFwdBars = (int)(ExpireHours * 60) + 5;

   //--- Locate bar range (bar 0 = current, larger shift = older bar)
   int fromShift = iBarShift(Symbol(), PERIOD_M1, DateFrom, false);
   int toShift   = iBarShift(Symbol(), PERIOD_M1, DateTo,   false);
   if(fromShift < 0 || toShift < 0)
   { Print("ERROR: iBarShift failed — check date range covers available history"); return; }
   if(fromShift < toShift) { int t = fromShift; fromShift = toShift; toShift = t; }
   // fromShift = oldest bar (large index), toShift = newest bar (small index)

   int copyCount = fromShift + LQS_Lookback + 10;

   //--- Copy OHLC + time
   double h[], l[], c[];
   datetime t[];
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   ArraySetAsSeries(c, true);
   ArraySetAsSeries(t, true);

   if(CopyHigh (Symbol(), PERIOD_M1, 0, copyCount, h) < copyCount ||
      CopyLow  (Symbol(), PERIOD_M1, 0, copyCount, l) < copyCount ||
      CopyClose(Symbol(), PERIOD_M1, 0, copyCount, c) < copyCount ||
      CopyTime (Symbol(), PERIOD_M1, 0, copyCount, t) < copyCount)
   { Print("ERROR: OHLC copy failed — request fewer bars or update history"); return; }

   //--- ATR indicator
   int atrH = iATR(Symbol(), PERIOD_M1, ATR_Period);
   if(atrH == INVALID_HANDLE) { Print("ERROR: iATR handle failed"); return; }

   //--- ADX indicator (buffer 0=ADX, 1=+DI, 2=-DI)
   int adxH = iADX(Symbol(), PERIOD_M1, ATR_Period);
   if(adxH == INVALID_HANDLE)
   { Print("ERROR: iADX handle failed"); IndicatorRelease(atrH); return; }

   //--- Wait for indicator data
   int waits = 0;
   while((BarsCalculated(atrH) < copyCount || BarsCalculated(adxH) < copyCount) && waits < 200)
   { Sleep(50); waits++; }

   double atrBuf[], adxBuf[], plusDI[], minusDI[];
   ArraySetAsSeries(atrBuf,  true);
   ArraySetAsSeries(adxBuf,  true);
   ArraySetAsSeries(plusDI,  true);
   ArraySetAsSeries(minusDI, true);

   bool bufOK =
      (CopyBuffer(atrH, 0, 0, copyCount, atrBuf)  >= copyCount) &&
      (CopyBuffer(adxH, 0, 0, copyCount, adxBuf)  >= copyCount) &&
      (CopyBuffer(adxH, 1, 0, copyCount, plusDI)  >= copyCount) &&
      (CopyBuffer(adxH, 2, 0, copyCount, minusDI) >= copyCount);

   IndicatorRelease(atrH);
   IndicatorRelease(adxH);

   if(!bufOK) { Print("ERROR: indicator buffer copy failed"); return; }

   //--- P&L per price unit ($ per 1.00 price move at LotSize)
   double tickVal  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSz   = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double pnlPerPt = (tickSz > 0.0 && tickVal > 0.0)
                     ? (LotSize * tickVal / tickSz)
                     : LotSize * 100.0;   // XAUUSD fallback: $1 per 1.00 pt per 0.01 lot

   //--- Per-TP accumulators
   int    wins[N_TP], losses[N_TP], expired_c[N_TP];
   double pnl[N_TP];
   double mfe[N_TP];   // total max-favourable-excursion for averaging
   ArrayInitialize(wins,      0);
   ArrayInitialize(losses,    0);
   ArrayInitialize(expired_c, 0);
   ArrayInitialize(pnl,       0.0);
   ArrayInitialize(mfe,       0.0);

   //--- Scan
   int      signals   = 0;
   datetime lastSig   = 0;

   for(int i = fromShift; i >= (int)MathMax(toShift, maxFwdBars + 2); i--)
   {
      //--- Date guard
      if(t[i] < DateFrom || t[i] > DateTo) continue;

      //--- ATR filter
      double atr = atrBuf[i];
      if(atr <= 0.0 || atr < ATR_Min_Filter)                        continue;
      if(ATR_Max_Filter > 0.0 && atr > ATR_Max_Filter)              continue;

      //--- Cooldown
      if(lastSig > 0 && (long)(t[i] - lastSig) < (long)(CooldownMinutes * 60)) continue;

      //--- Lookback bounds check
      if(i + LQS_Lookback + 1 >= copyCount) continue;

      double h1 = h[i], l1 = l[i], c1 = c[i];

      //--- Swing high/low: bars [i+2 .. i+LQS_Lookback+1]
      double swHigh = h[i + 2];
      double swLow  = l[i + 2];
      for(int k = i + 3; k <= i + LQS_Lookback + 1; k++)
      {
         if(h[k] > swHigh) swHigh = h[k];
         if(l[k] < swLow)  swLow  = l[k];
      }

      //--- Sweep detection
      bool lqsSell = (h1 > swHigh) && (c1 < swHigh);
      bool lqsBuy  = (l1 < swLow)  && (c1 > swLow);
      if(!lqsSell && !lqsBuy) continue;

      //--- Wick filter
      if(LQS_Wick_Min_ATR > 0.0)
      {
         double wick = lqsSell ? (h1 - swHigh) : (swLow - l1);
         if(wick < atr * LQS_Wick_Min_ATR) continue;
      }

      //--- Close-back distance filter (v1.150)
      if(LQS_CloseBack_Min_ATR > 0.0)
      {
         double closeBack = lqsSell ? (swHigh - c1) : (c1 - swLow);
         if(closeBack < atr * LQS_CloseBack_Min_ATR) continue;
      }

      //--- Bar body direction filter (v1.150)
      if(LQS_Body_Direction)
      {
         double midPoint = (h1 + l1) * 0.5;
         if(lqsSell && c1 > midPoint) continue;
         if(lqsBuy  && c1 < midPoint) continue;
      }

      //--- DI spread filter: check bar[1]=i and bar[2]=i+1
      if(LQS_DI_Spread_Filter > 0.0 && i + 1 < copyCount)
      {
         double s1s = plusDI[i]    - minusDI[i];      // bar[1] bearish spread (for SELL block)
         double s1b = minusDI[i]   - plusDI[i];       // bar[1] bullish spread (for BUY block)
         double s2s = plusDI[i+1]  - minusDI[i+1];    // bar[2] bearish spread
         double s2b = minusDI[i+1] - plusDI[i+1];     // bar[2] bullish spread
         if(lqsSell && (s1s >= LQS_DI_Spread_Filter || s2s >= LQS_DI_Spread_Filter)) continue;
         if(lqsBuy  && (s1b >= LQS_DI_Spread_Filter || s2b >= LQS_DI_Spread_Filter)) continue;
      }

      //--- M1 DI alignment: bar[1] DI must agree with trade direction
      if(LQS_M1_DI_Align)
      {
         if(lqsBuy  && minusDI[i] > plusDI[i]) continue;   // M1 bearish on sweep bar
         if(lqsSell && plusDI[i]  > minusDI[i]) continue;  // M1 bullish on sweep bar
      }

      //--- Trend-only filter (matches LQS_Trend_Only in EA v1.140)
      bool   m1Rang = (adxBuf[i] < M1_Ranging_Thresh);
      if(LQS_Trend_Only && m1Rang) continue;

      //--- Signal confirmed
      signals++;
      lastSig = t[i];

      double slMult = m1Rang ? SL_ATR_Ranging : SL_ATR_Factor;
      double slDist = atr * slMult;
      double entry  = c1;
      bool   isSell = lqsSell;

      //--- Compute max favourable excursion across forward window (shared for all TP levels)
      int    fwdEnd  = MathMax(i - maxFwdBars, 1);
      double maxFavE = 0.0;
      for(int j = i - 1; j >= fwdEnd; j--)
      {
         double fav = isSell ? (entry - l[j]) : (h[j] - entry);
         if(fav > maxFavE) maxFavE = fav;
      }

      if(LogEachSignal)
         Print(StringFormat("%s  LQS %-4s | ATR=%.2f | SL=%.2fx[%s]=%.2f | MFE=%.2f",
               TimeToString(t[i], TIME_DATE|TIME_MINUTES),
               (isSell ? "SELL" : "BUY"),
               atr, slMult, (m1Rang ? "RNG" : "TRD"), slDist, maxFavE));

      //--- Simulate at each TP level (fixed dollar, matches LQS_TP_Fixed in EA)
      for(int tp = 0; tp < N_TP; tp++)
      {
         double tpDist = TP_LEVELS[tp];   // fixed dollar amount
         bool   hit    = false;
         bool   isWin  = false;

         for(int j = i - 1; j >= fwdEnd && !hit; j--)
         {
            bool tpHit, slHit;
            if(isSell)
            {
               tpHit = (l[j] <= entry - tpDist);
               slHit = (h[j] >= entry + slDist);
            }
            else
            {
               tpHit = (h[j] >= entry + tpDist);
               slHit = (l[j] <= entry - slDist);
            }

            if(slHit && tpHit)
            {
               // Both hit same bar: use close direction as tiebreaker
               bool bearish = (c[j] < (h[j] + l[j]) * 0.5);
               isWin = isSell ? bearish : !bearish;
               hit   = true;
            }
            else if(tpHit) { hit = true; isWin = true;  }
            else if(slHit) { hit = true; isWin = false; }
         }

         if(!hit)
         {
            // Expired: close at last forward bar
            expired_c[tp]++;
            double exitPx = c[fwdEnd];
            double gain   = isSell ? (entry - exitPx) : (exitPx - entry);
            pnl[tp]      += gain * pnlPerPt;
         }
         else if(isWin)
         {
            wins[tp]++;
            pnl[tp] += tpDist * pnlPerPt;
         }
         else
         {
            losses[tp]++;
            pnl[tp] -= slDist * pnlPerPt;
         }

         mfe[tp] += maxFavE;
      }
   }

   //--- Print results table
   string sep = "  ─────────────────────────────────────────────────────────";
   Print("══════════════════════════════════════════════════════════");
   Print("  LQS TP OPTIMIZER RESULTS  |  ", Symbol(), " M1");
   Print("  Period  : ", TimeToString(DateFrom, TIME_DATE|TIME_MINUTES),
         " → ", TimeToString(DateTo, TIME_DATE|TIME_MINUTES));
   Print("  Signals : ", signals,
         "   SL=", DoubleToString(SL_ATR_Factor, 1), "/",
                   DoubleToString(SL_ATR_Ranging, 1), "×ATR",
         "   TrendOnly=", LQS_Trend_Only,
         "   Lookback=", LQS_Lookback,
         "   Expire=",   DoubleToString(ExpireHours * 60, 0), "min");
   Print("  NOTE: TP levels are FIXED DOLLAR amounts (matches LQS_TP_Fixed in EA).");
   Print(sep);
   Print(StringFormat("  %-6s | %4s | %4s | %4s | %6s | %8s | %s",
         "TP $","Wins","Loss","Exp","WinRate","Net P&L","Avg MFE"));
   Print(sep);

   for(int tp = 0; tp < N_TP; tp++)
   {
      int    total = wins[tp] + losses[tp] + expired_c[tp];
      double wr    = (total > 0) ? 100.0 * wins[tp] / total : 0.0;
      double avgMFE= (signals > 0) ? mfe[tp] / signals : 0.0;
      string mark  = (MathAbs(TP_LEVELS[tp] - LQS_TP_Current) < 0.001) ? "  ◄ CURRENT" : "";

      Print(StringFormat("  $%-5.2f | %4d | %4d | %4d | %5.1f%% | $%7.2f | %.2f%s",
            TP_LEVELS[tp],
            wins[tp], losses[tp], expired_c[tp],
            wr, pnl[tp], avgMFE, mark));
   }
   Print(sep);
   Print("  Avg MFE = average max favourable excursion per signal (in $).");
   Print("  TP levels are fixed $ — any level above Avg MFE will often not be reached.");
   Print("══════════════════════════════════════════════════════════");
}
//+------------------------------------------------------------------+
