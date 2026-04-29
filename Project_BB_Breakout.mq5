//+------------------------------------------------------------------+
//|                    PROJECT BB BREAKOUT  (MT5 v1.6)                        |
//|  LQS Liquidity Sweep + Bollinger Band Confluence EA             |
//|  Based on LQS Zone Scalper v1.191                               |
//|                                                                  |
//| v1.6: BO_Max_Run_Bars — block BO after extended candle run        |
//|  BO SELL blocked if N+ consecutive red bars already printed.    |
//|  BO BUY  blocked if N+ consecutive green bars already printed.  |
//|  Prevents entering a breakout at exhaustion (12:43 trap: 7 red  |
//|  candles then immediate reversal). Default: 5 bars.             |
//|                                                                  |
//| v1.5: BO_HTF_DI_Required — M5 DI confirmation for breakouts      |
//|  BO SELL blocked when M5 +DI > -DI (M5 still bullish).          |
//|  BO BUY  blocked when M5 -DI > +DI (M5 still bearish).          |
//|  Prevents false breakouts at M1 that conflict with M5 trend.    |
//|  Pullback (LQS/BB) entries unaffected.                          |
//|                                                                  |
//| v1.4: LQS_M1_DI_Align default true                               |
//|  Block counter-DI entries even in ranging mode (was only         |
//|    enforced when ADX >= threshold).                              |
//|                                                                  |
//| v1.3: Lower BE trigger default 0.50→0.35                         |
//|  Trades reversing near $0.40 profit now exit at breakeven        |
//|  instead of taking a full ATR-based SL loss.                    |
//|  Ambiguous-bar fix: outside bar sweeping both swing levels       |
//|  now skipped (was silently defaulting to SELL).                 |
//|                                                                  |
//| v1.0: Breakout continuation entry (Riding mode only)             |
//|  Uptrend BUY  : bar sweeps ABOVE swing high + closes above it.  |
//|    Momentum confirmed — trend continuing to new highs.           |
//|  Downtrend SELL: bar sweeps BELOW swing low  + closes below it. |
//|    Momentum confirmed — trend continuing to new lows.            |
//|  LQS pullback entries retained for all modes.                   |
//|  BB_Close_Zone_Filter skipped for breakout entries.             |
//|  Entry tagged "BO" to distinguish from "BB+LQS" / "BB" entries. |
//|                                                                  |
//| Inherited from Project BB v1.4 (all prior filters included):    |
//|  Mode-aware HTF filter, M1 DI riding enforcement, SL cap,       |
//|  BE buffer, BB_Close_Zone_Filter, DI spread filter.             |
//|                                                                  |
//| v1.2: Risk & direction filters                                   |
//|  SL_Max_Dollar: skip trade if SL > N dollars. Prevents          |
//|    oversized risk during high-ATR volatile sessions.             |
//|  LQS_HTF_DI_Align=true: block counter-trend entries using M5    |
//|    DI direction. BUY blocked when M5 -DI > +DI (bearish M5).   |
//|  BB_Close_Zone_Filter=true: bar[1] must close in correct BB     |
//|    half — SELL needs close >= BB Middle, BUY needs <= BB Middle. |
//|  LQS_BE_Buffer: BE stop locks in small profit instead of exact  |
//|    entry, absorbs SL fill slippage.                             |
//|                                                                  |
//| v1.1: Entry quality & dual path                                  |
//|  BB_Band_Entry: BB-only entry (no swing sweep required).        |
//|  BB_Close_Zone_Filter: prevent mid-range entries.               |
//|  CooldownMinutes reduced 5→2.                                   |
//|  LQS_Bar_Range_Max_ATR moved to LQS-only filters.               |
//|                                                                  |
//| v1.0: Bollinger Band layer added on top of LQS signals          |
//|  BB_Require_Band_Touch, BB_Midline_Trend_Filter,                |
//|  BB_Width_Min/Max_ATR, dual entry path BB+LQS / BB-only.        |
//|                                                                  |
//| Inherited from LQS v1.191:                                      |
//|  Dollar trail/BE, DI-align, bar-range, HTF M5 filter,          |
//|  close-back, body-direction, explosion-bar block.               |
//+------------------------------------------------------------------+
#property copyright "Project BB Breakout"
#property version   "1.600"
#property description "Project BB Breakout | LQS + Breakout Continuation | XAUUSD M1"

#include <Trade\Trade.mqh>

#define LQS_LINE_SELL  "LQS_SwingHigh"
#define LQS_LINE_BUY   "LQS_SwingLow"
#define BB_LINE_UPPER  "BB_Upper"
#define BB_LINE_MIDDLE "BB_Middle"
#define BB_LINE_LOWER  "BB_Lower"
CTrade trade;

//===================================================================
//  INPUTS
//===================================================================
input group "=== Trade ==="
input double LotSize             = 0.01;
input int    MagicNumber         = 3333;
input double ExpireHours         = 0.5;
input int    CooldownMinutes     = 2;

input group "=== ATR Settings ==="
input int    ATR_Period          = 14;
input double ATR_Min_Filter      = 0.0;
input double ATR_Max_Filter      = 0.0;
input double SL_ATR_Factor       = 1.5;
input double SL_ATR_Ranging_Mult = 2.0;
input double M1_Ranging_Threshold = 25.0;
input double SL_Max_Dollar       = 5.0;
// Skip trade if calculated SL distance exceeds this dollar amount.
// Prevents large SL during high-ATR volatile periods (news spikes, big
// reversals) where ATR is inflated and 1.5-2x ATR becomes unacceptably
// large (e.g. ATR=$4.76 → ranging SL=$9.52 → far exceeds max).
// Set 0 to disable. Recommended: 4.0–6.0 for XAUUSD M1 at 0.01 lots.
input bool   Riding_Structure_SL  = true;
// Riding mode only: use swing level as SL instead of ATR-based.
// LQS SELL: SL = swept swing high + buffer (price reclaims → trade invalid).
// LQS BUY:  SL = swept swing low  - buffer.
// Tighter than ATR-based; aligns SL with the exact level that must hold.
input double Riding_SL_Buffer     = 0.20;
// Dollar buffer beyond swing level for structure-based SL.
// Absorbs minor wicks past the level without invalidating the trade.
input group "=== LQS Trail / Breakeven ==="
input double LQS_BE_Trigger   = 0.35;
// Move SL to breakeven when trade profit reaches this dollar amount.
// Set 0 to disable.
// 0.35: catches reversals that peak around $0.40 before BE triggers.
input double LQS_BE_Buffer    = 0.25;
// Dollar buffer added beyond entry when BE triggers.
// SELL: SL = entry - buffer (locks in $0.15 minimum profit).
// BUY:  SL = entry + buffer (locks in $0.15 minimum profit).
// Absorbs SL fill slippage so BE never closes at a loss.
// Set 0 for exact entry breakeven.
input double LQS_Trail_Start  = 0.60;
// Begin trailing SL when trade profit reaches this dollar amount.
// When > 0, the fixed TP is removed at entry — trail manages the exit.
// Set 0 to use fixed TP only (original behaviour).
input double LQS_Trail_Step   = 0.35;
// Dollar gap kept between the trailing SL and current price.
// Smaller = tighter trail (exits sooner on reversal, captures less).
// Suggested range: 0.20–0.50 for XAUUSD M1.

input group "=== LQS Settings ==="
input int    LQS_Lookback        = 20;
input double LQS_Wick_Min_ATR    = 0.0;
input double LQS_DI_Spread_Filter = 30.0;
input double LQS_M1_DI_Max_Counter  = 0.0;
input bool   LQS_Trend_Only         = false;
input double LQS_CloseBack_Min_ATR  = 0.0;
// Minimum close-back distance as a fraction of ATR.
// SELL: bar[1] must close at least (N × ATR) below swingHigh.
// BUY:  bar[1] must close at least (N × ATR) above swingLow.
// Filters weak rejections that barely graze the level before closing back.
// 0.3 = bar must close $0.60+ below swing (at ATR=$2). Set 0 to disable.
input bool   LQS_Body_Direction     = false;
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
// Blocks sweeps where M1 momentum runs against the trade direction —
// e.g. BB BUY triggered at lower band while -DI >> +DI (downtrend).
// Enabled by default — covers the ranging case where m1IsTrending=false
// and the trending DI check would otherwise be skipped entirely.
// Set false to allow counter-DI entries in ranging markets.
input double LQS_Bar_Range_Min_ATR  = 0.0;
input double LQS_Bar_Range_Max_ATR  = 3.0;
// Block signal if sweep bar range (H-L) exceeds N×ATR.
// Filters explosion/news bars that technically sweep a level but are
// really just a large directional move — not a genuine liquidity grab.
// Nov 21 07:58: bar range=$11.71, ATR=$3.35 → 3.49×ATR → blocked.
// All normal sweep bars have range < 2.5×ATR. Set 0 to disable.
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
input double LQS_TP_ATR_Factor   = 0.0;
// Dynamic TP: TP = ATR × LQS_TP_ATR_Factor.
// Scales with volatility — keeps R:R consistent across market conditions.
// At 1.0×ATR TP vs SL=1.5×ATR: need 60% win rate to break even.
// At 1.0×ATR TP vs SL=2.0×ATR: need 67% win rate to break even.
// Set 0 to disable and use LQS_TP_Fixed (fixed dollar) instead.
input double LQS_TP_Fixed        = 0.75;
// Fixed dollar TP. Only used when LQS_TP_ATR_Factor = 0.

input group "=== Bollinger Band Settings ==="
input int    BB_Period              = 20;
input double BB_Deviation           = 1.5;
input bool   BB_Require_Band_Touch  = true;
// SELL: sweep bar[1] high must reach or exceed BB upper band.
// BUY:  sweep bar[1] low  must reach or fall below BB lower band.
// Ensures the liquidity sweep also touches a statistically extreme
// price level — filters mid-range pokes that lack band confluence.
// Set false to disable (LQS sweeps fire regardless of BB position).
input bool   BB_Band_Entry          = true;
// Secondary entry: bar[1] touches the BB band and closes back inside — no LQS
// swing sweep required.
// SELL: bar[1] high >= BB upper AND close < BB upper.
// BUY:  bar[1] low  <= BB lower AND close > BB lower.
// Catches bounces at the band that don't sweep a swing level (e.g. 11:04 setup).
// All other active filters (DI align, body direction, bar range) still apply.

input bool   BB_Midline_Trend_Filter = false;
// Only enable when using Riding the Bands (trending) strategy.
// SELL: requires bar[1] close < BB middle. BUY: requires bar[1] close > BB middle.
// WARNING: contradicts mean reversion — when price sweeps the upper band the close
// is by definition above the middle, so this filter will always block SELL signals
// at the upper band. Leave false for standard LQS + BB mean reversion use.
input bool   BB_Close_Zone_Filter   = true;
// Mean reversion entry quality: entry must still be in the correct BB zone.
// SELL: bar[1] close must be >= BB Middle (upper half). Prevents selling after
//   the bar has already crashed through the midline — entry would be mid-range
//   or lower half, offering poor risk:reward for a SELL.
// BUY:  bar[1] close must be <= BB Middle (lower half). Prevents buying after
//   the bar has already bounced back above the midline.

input group "=== Breakout Settings ==="
input bool   BO_HTF_DI_Required     = true;
// Require M5 DI to confirm breakout direction, regardless of M1 trending status.
// BO SELL blocked when M5 +DI > -DI (M5 still bullish — false breakdown risk).
// BO BUY  blocked when M5 -DI > +DI (M5 still bearish — false breakout risk).
// Breakouts are higher-risk entries; a false break at M1 is less likely when M5
// also agrees. Pullback (LQS/BB) entries are unaffected by this flag.
// Set false to disable (breakouts allowed regardless of M5 direction).
input int    BO_Max_Run_Bars        = 5;
// Block BO entry when price has already run N or more consecutive bars in the
// breakout direction — signals an extended move at risk of exhaustion reversal.
// BO SELL blocked when bar[1..N] are all red (close < open).
// BO BUY  blocked when bar[1..N] are all green (close > open).
// 5 = block if 5+ consecutive bars already moved in that direction.
// XAUUSD M1 typically reverses within 4–5 bars; 6 lets exhausted entries through.
// Set 0 to disable.
// Enable for mean reversion (default). Disable only for breakout/trend setups.
input double BB_Width_Min_ATR       = 0.0;
// Minimum BB width (upper - lower) as a multiple of ATR.
// Blocks entries when bands are too narrow (squeeze — imminent breakout risk).
// 0 = disabled. Suggested: 1.0.
input double BB_Width_Max_ATR       = 0.0;
// Maximum BB width (upper - lower) as a multiple of ATR.
// Blocks entries when bands are over-expanded (mean reversion may be exhausted).
// 0 = disabled.

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
int BB_Handle    = INVALID_HANDLE;

double g_ATR        = 0.0;
double g_BB_Upper   = 0.0;
double g_BB_Middle  = 0.0;
double g_BB_Lower   = 0.0;
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

   M1ADX_Handle = iADX(Symbol(), PERIOD_M1, ATR_Period);
   if(M1ADX_Handle == INVALID_HANDLE) { Print("ERROR: M1 ADX handle failed."); return INIT_FAILED; }

   M5ADX_Handle = iADX(Symbol(), PERIOD_M5, ATR_Period);
   if(M5ADX_Handle == INVALID_HANDLE) { Print("ERROR: M5 ADX handle failed."); return INIT_FAILED; }

   BB_Handle = iBands(Symbol(), PERIOD_M1, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   if(BB_Handle == INVALID_HANDLE) { Print("ERROR: BB handle failed."); return INIT_FAILED; }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(GetFillType());
   trade.LogLevel(LOG_LEVEL_ERRORS);

   TodayDate = DayOfTime(TimeCurrent());

   string exitMode = (LQS_Trail_Start > 0.0)
                    ? "Trail +$" + DoubleToString(LQS_Trail_Start,2)
                      + " step=$" + DoubleToString(LQS_Trail_Step,2)
                      + (LQS_BE_Trigger > 0.0
                         ? " BE=$" + DoubleToString(LQS_BE_Trigger,2)
                         : "")
                    : (LQS_TP_ATR_Factor > 0.0
                       ? DoubleToString(LQS_TP_ATR_Factor,2)+"xATR [dynamic]"
                       : "$"+DoubleToString(LQS_TP_Fixed,2)+" [fixed]");
   Print("Project BB Breakout v1.2 | Symbol=", Symbol(),
         " | Magic=", MagicNumber,
         " | Exit=", exitMode,
         " | HTF_DI=", LQS_HTF_DI_Align,
         " | SL_Max=$", SL_Max_Dollar,
         " | BE_Buf=$", LQS_BE_Buffer,
         " | CloseZone=", BB_Close_Zone_Filter,
         " | DI_Spread=", LQS_DI_Spread_Filter,
         " | RidingDIEnforce=ON",
         " | RangingThresh=ADX<", M1_Ranging_Threshold);

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
   if(BB_Handle    != INVALID_HANDLE) IndicatorRelease(BB_Handle);
   ObjectDelete(0, LQS_LINE_SELL);
   ObjectDelete(0, LQS_LINE_BUY);
   ObjectDelete(0, BB_LINE_UPPER);
   ObjectDelete(0, BB_LINE_MIDDLE);
   ObjectDelete(0, BB_LINE_LOWER);
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

void RefreshBB()
{
   double buf[]; ArraySetAsSeries(buf, true);
   g_BB_Upper  = (CopyBuffer(BB_Handle, 1, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_BB_Middle = (CopyBuffer(BB_Handle, 0, 1, 1, buf) >= 1) ? buf[0] : 0.0;
   g_BB_Lower  = (CopyBuffer(BB_Handle, 2, 1, 1, buf) >= 1) ? buf[0] : 0.0;
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
string M1Direction()
{
   double spread = g_M1PlusDI - g_M1MinusDI;
   if     (spread >=  8) return "M1 BULL";
   else if(spread <= -8) return "M1 BEAR";
   else                  return "M1 NEUTRAL";
}

string BBMode()
{
   double bbWidth = (g_BB_Upper > 0.0 && g_BB_Lower > 0.0) ? g_BB_Upper - g_BB_Lower : 0.0;
   if(g_ATR > 0.0 && bbWidth > 0.0 && bbWidth < g_ATR)
      return "★SQUEEZE | breakout either direction";
   if(g_M1ADX >= M1_Ranging_Threshold)
   {
      bool uptrend = (g_M1PlusDI > g_M1MinusDI);
      return uptrend
             ? "★RIDING UPTREND ADX=" + DoubleToString(g_M1ADX,1)
               + " | BUY dips to lower band only"
             : "★RIDING DOWNTREND ADX=" + DoubleToString(g_M1ADX,1)
               + " | SELL rallies to upper band only";
   }
   return "★MEAN REVERSION ADX=" + DoubleToString(g_M1ADX,1)
          + " | fade both extremes";
}

// ── 1. Signal Alert — fires when EA detects a valid entry ─────
// Gives exact entry, SL and TP for manual trading.
void SendSignalAlert(ENUM_ORDER_TYPE dir, double entryPrice,
                     double sl, double tp, double slDist, double tpDist,
                     double h1, double l1, double c1)
{
   if(!Enable_Notify) return;
   string side    = (dir == ORDER_TYPE_SELL) ? "SELL" : "BUY";
   string bbBand  = (dir == ORDER_TYPE_SELL)
                    ? "BB Upper: " + DoubleToString(g_BB_Upper, 2)
                    : "BB Lower: " + DoubleToString(g_BB_Lower, 2);
   string sweepInfo = (dir == ORDER_TYPE_SELL)
                    ? "Spike to " + DoubleToString(h1, 2)
                      + " | SwingH " + DoubleToString(g_LQS_SwingHigh, 2)
                      + " | Close " + DoubleToString(c1, 2)
                    : "Spike to " + DoubleToString(l1, 2)
                      + " | SwingL " + DoubleToString(g_LQS_SwingLow, 2)
                      + " | Close " + DoubleToString(c1, 2);
   string tpStr   = (tpDist > 0.0)
                    ? DoubleToString(tp, 2) + "  ($" + DoubleToString(tpDist, 2) + ")"
                    : "Trail $" + DoubleToString(LQS_Trail_Start, 2)
                      + " step $" + DoubleToString(LQS_Trail_Step, 2);
   string msg =
      "[BB+LQS] " + side + " SIGNAL  XAUUSD\n"
      + "Entry : " + DoubleToString(entryPrice, 2) + "\n"
      + "SL    : " + DoubleToString(sl, 2)
      + "  ($" + DoubleToString(slDist, 2) + ")\n"
      + "TP    : " + tpStr + "\n"
      + bbBand + "  |  " + sweepInfo + "\n"
      + M1Direction() + "  ATR=" + DoubleToString(g_ATR, 2)
      + "  " + BBMode()
      + "  SGT=" + TimeToString(GetSGT(), TIME_MINUTES);
   SendNotification(msg);
}

// ── 2. Zone Approach Alert — price near BB band + swing level ──
void CheckZoneApproach()
{
   if(!Enable_Notify || Notify_Zone_ATR_Dist <= 0.0) return;
   if(g_ATR <= 0.0 || g_LQS_SwingHigh <= 0.0 || g_LQS_SwingLow <= 0.0) return;
   if(g_BB_Upper <= 0.0 || g_BB_Lower <= 0.0) return;
   if((long)(TimeCurrent() - g_LastZoneAlert) < 300) return;

   double price  = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double thresh = Notify_Zone_ATR_Dist * g_ATR;

   double distSwingH = g_LQS_SwingHigh - price;
   double distSwingL = price - g_LQS_SwingLow;
   double distBBUp   = g_BB_Upper - price;
   double distBBLow  = price - g_BB_Lower;

   bool m1Trending  = (g_M1ADX >= M1_Ranging_Threshold);
   bool m1Uptrend   = m1Trending && (g_M1PlusDI  > g_M1MinusDI);
   bool m1Downtrend = m1Trending && (g_M1MinusDI > g_M1PlusDI);

   bool nearSell = distSwingH <= thresh && price < g_LQS_SwingHigh
                && distBBUp   <= thresh && price < g_BB_Upper;
   bool nearBuy  = distSwingL <= thresh && price > g_LQS_SwingLow
                && distBBLow  <= thresh && price > g_BB_Lower;

   if(m1Uptrend   && nearSell && !nearBuy) return;
   if(m1Downtrend && nearBuy  && !nearSell) return;
   if(!nearSell && !nearBuy) return;

   string side    = nearSell ? "SELL" : "BUY";
   string swing   = nearSell ? DoubleToString(g_LQS_SwingHigh, 2) : DoubleToString(g_LQS_SwingLow, 2);
   string bbLevel = nearSell ? DoubleToString(g_BB_Upper, 2)       : DoubleToString(g_BB_Lower, 2);
   double dSwing  = nearSell ? distSwingH : distSwingL;
   double dBB     = nearSell ? distBBUp   : distBBLow;
   string action  = nearSell
                    ? "Spike ABOVE " + swing + " + touch BB " + bbLevel + " then close below"
                    : "Spike BELOW " + swing + " + touch BB " + bbLevel + " then close above";
   string blocked = (m1Uptrend && nearSell)  ? "  [SELL BLOCKED — uptrend]"
                  : (m1Downtrend && nearBuy) ? "  [BUY BLOCKED — downtrend]"
                  : "";

   string msg =
      "[BB+LQS] " + side + " ZONE APPROACH  XAUUSD\n"
      + "Price     : " + DoubleToString(price, 2) + "\n"
      + "Swing " + (nearSell ? "High" : "Low ") + " : " + swing
      + "  ($" + DoubleToString(dSwing, 2) + " away)\n"
      + "BB " + (nearSell ? "Upper" : "Lower") + "   : " + bbLevel
      + "  ($" + DoubleToString(dBB, 2) + " away)\n"
      + "Watch for : " + action + " → " + side + blocked + "\n"
      + M1Direction() + "  ATR=" + DoubleToString(g_ATR, 2) + "\n"
      + BBMode()
      + "  SGT=" + TimeToString(GetSGT(), TIME_MINUTES);

   SendNotification(msg);
   g_LastZoneAlert = TimeCurrent();
}

// ── 3. Periodic Status — every N minutes ──────────────────────
void OnTimer()
{
   if(!Enable_Notify) return;
   double price    = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double distSell = (g_LQS_SwingHigh > 0) ? g_LQS_SwingHigh - price : 0.0;
   double distBuy  = (g_LQS_SwingLow  > 0) ? price - g_LQS_SwingLow  : 0.0;
   double bbWidth  = (g_BB_Upper > 0.0 && g_BB_Lower > 0.0) ? g_BB_Upper - g_BB_Lower : 0.0;
   string msg =
      "[BB+LQS] XAUUSD " + DoubleToString(price, 2)
      + "  " + M1Direction() + "  " + BBMode() + "\n"
      + "BB(" + IntegerToString(BB_Period) + "," + DoubleToString(BB_Deviation,1) + ")"
      + "  U=" + DoubleToString(g_BB_Upper,  2)
      + "  M=" + DoubleToString(g_BB_Middle, 2)
      + "  L=" + DoubleToString(g_BB_Lower,  2)
      + "  W=$" + DoubleToString(bbWidth, 2) + "\n"
      + "SELL zone: SwingH " + DoubleToString(g_LQS_SwingHigh, 2)
      + "  ($+" + DoubleToString(distSell, 1) + ")  BBU " + DoubleToString(g_BB_Upper, 2) + "\n"
      + "BUY  zone: SwingL " + DoubleToString(g_LQS_SwingLow, 2)
      + "  ($-" + DoubleToString(distBuy,  1) + ")  BBL " + DoubleToString(g_BB_Lower, 2) + "\n"
      + "ATR=" + DoubleToString(g_ATR, 2)
      + "  ADX=" + DoubleToString(g_M1ADX, 1)
      + "  P&L=$" + DoubleToString(TodayProfit, 2)
      + "  SGT=" + TimeToString(GetSGT(), TIME_MINUTES);
   SendNotification(msg);
}

//===================================================================
//  TRADE MANAGEMENT
//===================================================================
void ManageTrades()
{
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

      // Price-distance profit in dollars (XAUUSD price = dollars per oz)
      double profit = (ptype == POSITION_TYPE_BUY) ? (bid - op) : (op - ask);
      double newSL  = sl;

      // Trail: price-follows SL once profit >= LQS_Trail_Start
      if(LQS_Trail_Start > 0.0 && profit >= LQS_Trail_Start)
      {
         double trailSL = (ptype == POSITION_TYPE_BUY)
                          ? NormalizeDouble(bid - LQS_Trail_Step, _Digits)
                          : NormalizeDouble(ask + LQS_Trail_Step, _Digits);
         bool improve = (ptype == POSITION_TYPE_BUY)
                        ? (trailSL > newSL + _Point)
                        : (newSL == 0.0 || trailSL < newSL - _Point);
         if(improve) newSL = trailSL;
      }
      // Breakeven: move SL to entry + buffer when profit >= LQS_BE_Trigger
      else if(LQS_BE_Trigger > 0.0 && profit >= LQS_BE_Trigger)
      {
         double beSL  = (ptype == POSITION_TYPE_BUY)
                        ? NormalizeDouble(op + LQS_BE_Buffer, _Digits)
                        : NormalizeDouble(op - LQS_BE_Buffer, _Digits);
         bool improve = (ptype == POSITION_TYPE_BUY)
                        ? (beSL > newSL + _Point)
                        : (newSL == 0.0 || beSL < newSL - _Point);
         if(improve) newSL = beSL;
      }

      if(newSL != sl && !trade.PositionModify(ticket, newSL, tp))
         Print("Modify SL FAIL: ", trade.ResultRetcodeDescription());
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

   // ── Entry condition A: LQS swing sweep (all modes) ──────────
   // Reversal fade: sweep past level then close back inside.
   bool lqsSell = false, lqsBuy = false;
   if(g_LQS_SwingHigh > 0.0 && g_LQS_SwingLow > 0.0)
   {
      lqsSell = (h1 > g_LQS_SwingHigh) && (c1 < g_LQS_SwingHigh);
      lqsBuy  = (l1 < g_LQS_SwingLow)  && (c1 > g_LQS_SwingLow);
   }

   // ── Entry condition B: BB band touch + close back inside ──────
   // No swing sweep required — bar[1] touches the band and closes inside.
   bool bbSell = BB_Band_Entry && g_BB_Upper > 0.0 && (h1 >= g_BB_Upper) && (c1 < g_BB_Upper);
   bool bbBuy  = BB_Band_Entry && g_BB_Lower > 0.0 && (l1 <= g_BB_Lower) && (c1 > g_BB_Lower);

   // ── Entry condition C: Breakout continuation (Riding mode only) ──
   // Trend follow: sweep past level and close OUTSIDE = momentum confirmed.
   // Uptrend BUY  : bar sweeps above swing high AND closes above it.
   // Downtrend SELL: bar sweeps below swing low  AND closes below it.
   bool boBuy = false, boSell = false;
   bool m1IsTrendingEntry = (g_M1ADX >= M1_Ranging_Threshold);
   if(m1IsTrendingEntry && g_LQS_SwingHigh > 0.0 && g_LQS_SwingLow > 0.0)
   {
      boBuy  = (g_M1PlusDI  > g_M1MinusDI) && (h1 > g_LQS_SwingHigh) && (c1 >= g_LQS_SwingHigh);
      boSell = (g_M1MinusDI > g_M1PlusDI)  && (l1 < g_LQS_SwingLow)  && (c1 <= g_LQS_SwingLow);
   }

   bool isSell     = lqsSell || bbSell || boSell;
   bool isBuy      = lqsBuy  || bbBuy  || boBuy;
   bool isLQS      = lqsSell || lqsBuy;
   bool isBreakout = boBuy   || boSell;
   if(!isSell && !isBuy) return;
   // Outside bar sweeping both levels — direction ambiguous, skip.
   if(isSell && isBuy) return;

   ENUM_ORDER_TYPE dir;
   double          price;
   if(isSell) { dir = ORDER_TYPE_SELL; price = SymbolInfoDouble(Symbol(), SYMBOL_BID); }
   else       { dir = ORDER_TYPE_BUY;  price = SymbolInfoDouble(Symbol(), SYMBOL_ASK); }

   // ── LQS-only filters ─────────────────────────────────────────
   if(isLQS)
   {
      if(LQS_Wick_Min_ATR > 0.0)
      {
         double wickSize = (dir == ORDER_TYPE_SELL) ? (h1 - g_LQS_SwingHigh) : (g_LQS_SwingLow - l1);
         if(wickSize < g_ATR * LQS_Wick_Min_ATR) return;
      }
      if(LQS_CloseBack_Min_ATR > 0.0)
      {
         double closeBack = lqsSell ? (g_LQS_SwingHigh - c1) : (c1 - g_LQS_SwingLow);
         if(closeBack < g_ATR * LQS_CloseBack_Min_ATR) return;
      }
      // BB touch required on LQS path only.
      // BB-only and breakout entries have a touch/close condition built in,
      // so BB_Require_Band_Touch has no additional effect on those paths.
      if(BB_Require_Band_Touch && g_BB_Upper > 0.0 && g_BB_Lower > 0.0)
      {
         if(lqsSell && h1 < g_BB_Upper) return;
         if(lqsBuy  && l1 > g_BB_Lower) return;
      }
      // Bar range filters — LQS only. Large bars on BB-only entry are valid
      // band-touch bounces, not news spikes (e.g. 12:55 $6 drop to lower band).
      if(LQS_Bar_Range_Min_ATR > 0.0)
      {
         double barRange = h1 - l1;
         if(barRange < g_ATR * LQS_Bar_Range_Min_ATR) return;
      }
      if(LQS_Bar_Range_Max_ATR > 0.0)
      {
         double barRange = h1 - l1;
         if(barRange > g_ATR * LQS_Bar_Range_Max_ATR) return;
      }
   }

   // ── Common filters (apply to both LQS and BB entry) ───────────
   if(LQS_Body_Direction)
   {
      double midPoint = (h1 + l1) * 0.5;
      if(isSell && c1 > midPoint) return;
      if(isBuy  && c1 < midPoint) return;
   }

   // Riding the Bands: always enforce M1 DI direction — no lag unlike M5 HTF.
   // Mean Reversion / Squeeze: respect the LQS_M1_DI_Align toggle only.
   bool m1IsTrending = (g_M1ADX >= M1_Ranging_Threshold);
   if(m1IsTrending || LQS_M1_DI_Align)
   {
      if(isSell && g_M1PlusDI  > g_M1MinusDI) return;
      if(isBuy  && g_M1MinusDI > g_M1PlusDI)  return;
   }

   // Riding mode: M1 DI already confirms direction — M5 HTF not needed and
   // would block valid with-trend pullback entries during intraday retracements.
   if(LQS_HTF_DI_Align && !m1IsTrending)
   {
      if(isSell && g_M5PlusDI  > g_M5MinusDI) return;
      if(isBuy  && g_M5MinusDI > g_M5PlusDI)  return;
   }

   // Breakout entries: always enforce M5 DI alignment regardless of trending status.
   // False breakouts at M1 level are less likely when M5 trend agrees.
   // Pullback entries (LQS/BB) are unaffected.
   if(BO_HTF_DI_Required && isBreakout)
   {
      if(isSell && g_M5PlusDI  > g_M5MinusDI) return;
      if(isBuy  && g_M5MinusDI > g_M5PlusDI)  return;
   }

   // Block BO entry when price has already run N+ consecutive bars in the
   // breakout direction — extended moves are prone to exhaustion reversals.
   if(BO_Max_Run_Bars > 0 && isBreakout)
   {
      int runCount = 0;
      for(int k = 1; k <= BO_Max_Run_Bars; k++)
      {
         double o = iOpen(Symbol(),  PERIOD_M1, k);
         double c = iClose(Symbol(), PERIOD_M1, k);
         if(isSell && c < o) runCount++;   // red candle
         else if(isBuy  && c > o) runCount++;   // green candle
         else break;
      }
      if(runCount >= BO_Max_Run_Bars) return;
   }

   if(g_BB_Upper > 0.0 && g_BB_Lower > 0.0)
   {
      double bbWidth = g_BB_Upper - g_BB_Lower;
      if(BB_Width_Min_ATR > 0.0 && bbWidth < g_ATR * BB_Width_Min_ATR) return;
      if(BB_Width_Max_ATR > 0.0 && bbWidth > g_ATR * BB_Width_Max_ATR) return;
   }

   if(BB_Midline_Trend_Filter && g_BB_Middle > 0.0)
   {
      if(isSell && c1 >= g_BB_Middle) return;
      if(isBuy  && c1 <= g_BB_Middle) return;
   }

   // Entry zone quality: bar[1] must have closed in the correct BB half.
   // Skipped for breakout entries — their close is outside the band by definition.
   if(BB_Close_Zone_Filter && g_BB_Middle > 0.0 && !isBreakout)
   {
      if(isSell && c1 < g_BB_Middle) return;
      if(isBuy  && c1 > g_BB_Middle) return;
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
   if(LQS_Trend_Only && m1IsRanging) return;

   // ── Trend direction filter (disabled by default) ─────────────
   // When enabled: in trending mode only trade with trend direction.
   // Ranging: both directions. Trending UP: BUY only. Trending DOWN: SELL only.
   // Disabled by default — in strong trends price rarely reaches the
   // opposite band, causing the EA to stop trading entirely.
   // Enable manually when you want strict trend-following behaviour.
   if(LQS_Trend_Only && !m1IsRanging)
   {
      if(g_M1PlusDI > g_M1MinusDI && dir == ORDER_TYPE_SELL) return;
      if(g_M1MinusDI > g_M1PlusDI && dir == ORDER_TYPE_BUY)  return;
   }

   double slMult = m1IsRanging ? SL_ATR_Ranging_Mult : SL_ATR_Factor;
   double slDist = g_ATR * slMult;
   double sl;

   // Riding mode: use swing level as SL — tighter and structure-based.
   // LQS: SL at swept level (if price reclaims it the trade is invalid).
   // BO:  SL at the broken level (if price reclaims it breakout has failed).
   // Falls back to ATR-based if swing level produces invalid distance.
   if(m1IsTrending && Riding_Structure_SL &&
      g_LQS_SwingHigh > 0.0 && g_LQS_SwingLow > 0.0 &&
      (isLQS || isBreakout))
   {
      double structSL;
      if(isBreakout)
         // BO entries: SL at the broken level — reclaim = breakout failed
         structSL = (dir == ORDER_TYPE_BUY)
                    ? NormalizeDouble(g_LQS_SwingHigh - Riding_SL_Buffer, _Digits)
                    : NormalizeDouble(g_LQS_SwingLow  + Riding_SL_Buffer, _Digits);
      else
         // LQS entries: SL at the swept level — reclaim = sweep was real
         structSL = (dir == ORDER_TYPE_BUY)
                    ? NormalizeDouble(g_LQS_SwingLow  - Riding_SL_Buffer, _Digits)
                    : NormalizeDouble(g_LQS_SwingHigh + Riding_SL_Buffer, _Digits);
      double structDist = (dir == ORDER_TYPE_BUY) ? (price - structSL) : (structSL - price);
      if(structDist > 0.0) { sl = structSL; slDist = structDist; }
      else sl = (dir == ORDER_TYPE_BUY) ? NormalizeDouble(price - slDist, _Digits)
                                        : NormalizeDouble(price + slDist, _Digits);
   }
   // BB-only entries: SL at the band that triggered the entry.
   // Use whichever is tighter — band-based or ATR-based.
   // BUY: if price breaks back below BB_Lower the reversal has failed.
   // SELL: if price breaks back above BB_Upper the reversal has failed.
   // Note: breakout entries use the structure SL path above even when they
   // coincide with a BB touch — isBreakout takes priority over the band SL.
   else if(Riding_Structure_SL && !isLQS && !isBreakout && g_BB_Upper > 0.0 && g_BB_Lower > 0.0)
   {
      double bandSL  = (dir == ORDER_TYPE_BUY)
                       ? NormalizeDouble(g_BB_Lower - Riding_SL_Buffer, _Digits)
                       : NormalizeDouble(g_BB_Upper + Riding_SL_Buffer, _Digits);
      double atrSL   = (dir == ORDER_TYPE_BUY)
                       ? NormalizeDouble(price - slDist, _Digits)
                       : NormalizeDouble(price + slDist, _Digits);
      sl = (dir == ORDER_TYPE_BUY) ? MathMax(bandSL, atrSL) : MathMin(bandSL, atrSL);
      slDist = (dir == ORDER_TYPE_BUY) ? (price - sl) : (sl - price);
   }
   else
      sl = (dir == ORDER_TYPE_BUY) ? NormalizeDouble(price - slDist, _Digits)
                                   : NormalizeDouble(price + slDist, _Digits);

   if(SL_Max_Dollar > 0.0 && slDist > SL_Max_Dollar)
   {
      Print("SKIP | SL too large: $", DoubleToString(slDist, 2),
            " > max $", DoubleToString(SL_Max_Dollar, 2),
            " | ATR=", DoubleToString(g_ATR, 2));
      return;
   }

   double tpDist = (LQS_Trail_Start > 0.0) ? 0.0
                 : (LQS_TP_ATR_Factor > 0.0) ? g_ATR * LQS_TP_ATR_Factor
                 : LQS_TP_Fixed;

   double tp;
   if(dir == ORDER_TYPE_BUY)
      tp = (tpDist > 0.0) ? NormalizeDouble(price + tpDist, _Digits) : 0.0;
   else
      tp = (tpDist > 0.0) ? NormalizeDouble(price - tpDist, _Digits) : 0.0;

   string entryType = isBreakout ? "BO" : (isLQS ? "BB+LQS" : "BB");
   string comment   = entryType + (dir == ORDER_TYPE_BUY ? " BUY" : " SELL");
   SendSignalAlert(dir, price, sl, tp, slDist, tpDist, h1, l1, c1);
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
               if(ticket > 0)
               {
                  if(trade.PositionModify(ticket, sl, realTP))
                     Print("TP corrected fill=", DoubleToString(fillPrice, _Digits),
                           " requested=", DoubleToString(price, _Digits),
                           " slip=", DoubleToString(fillPrice - price, _Digits),
                           " oldTP=", DoubleToString(tp, _Digits),
                           " newTP=", DoubleToString(realTP, _Digits));
                  else
                     Print("TP correct FAIL: ", trade.ResultRetcodeDescription());
               }
            }
         }
      }

      Print("OPEN ", entryType, " ", (dir == ORDER_TYPE_BUY ? "BUY " : "SELL"),
            " | swingH=",  DoubleToString(g_LQS_SwingHigh, _Digits),
            " | swingL=",  DoubleToString(g_LQS_SwingLow,  _Digits),
            " | bar1H=",   DoubleToString(h1, _Digits),
            " | bar1L=",   DoubleToString(l1, _Digits),
            " | bar1C=",   DoubleToString(c1, _Digits),
            " | BB_U=",    DoubleToString(g_BB_Upper,  _Digits),
            " | BB_M=",    DoubleToString(g_BB_Middle, _Digits),
            " | BB_L=",    DoubleToString(g_BB_Lower,  _Digits),
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

void DrawBBLines()
{
   if(g_BB_Upper  > 0.0) SetHLine(BB_LINE_UPPER,  g_BB_Upper,  clrOrangeRed,  "BB Upper Band");
   if(g_BB_Middle > 0.0) SetHLine(BB_LINE_MIDDLE, g_BB_Middle, clrGold,       "BB Middle (SMA)");
   if(g_BB_Lower  > 0.0) SetHLine(BB_LINE_LOWER,  g_BB_Lower,  clrCornflowerBlue, "BB Lower Band");
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

   double bbWidth    = (g_BB_Upper > 0.0 && g_BB_Lower > 0.0) ? (g_BB_Upper - g_BB_Lower) : 0.0;
   bool   isSqueeze  = (g_ATR > 0.0 && bbWidth > 0.0 && bbWidth < g_ATR);
   bool   isTrending = (g_M1ADX >= M1_Ranging_Threshold);

   // ── BB Strategy Mode ─────────────────────────────────────────
   string bbMode, bbModeDesc, bbLongRule, bbShortRule;
   if(isSqueeze)
   {
      bbMode      = "★ SQUEEZE  [Breakout imminent — low volatility]";
      bbModeDesc  = "  Bands contracted below 1×ATR. A sharp move is likely.";
      bbLongRule  = "  LONG  : price breaks & closes ABOVE upper band";
      bbShortRule = "  SHORT : price breaks & closes BELOW lower band";
   }
   else if(isTrending)
   {
      bbMode      = "★ RIDING THE BANDS  [Trending — ADX " + DoubleToString(g_M1ADX,1) + "]";
      bbModeDesc  = "  Strong trend — band touches show strength, not reversal.";
      if(g_M1PlusDI >= g_M1MinusDI)
      {
         bbLongRule  = "  LONG  : dips to LOWER band = add to uptrend";
         bbShortRule = "  SHORT : wait for trend change before selling";
      }
      else
      {
         bbLongRule  = "  LONG  : wait for trend change before buying";
         bbShortRule = "  SHORT : rallies to UPPER band = add to downtrend";
      }
   }
   else
   {
      bbMode      = "★ MEAN REVERSION  [Ranging — ADX " + DoubleToString(g_M1ADX,1) + "]";
      bbModeDesc  = "  Price oscillates between bands. Trade the extremes.";
      bbLongRule  = "  LONG  : price touches/breaks LOWER band (oversold)";
      bbShortRule = "  SHORT : price touches/breaks UPPER band (overbought)";
   }

   // ── Price position relative to BB ────────────────────────────
   string priceZone;
   if(g_BB_Upper > 0.0 && g_BB_Lower > 0.0 && g_BB_Middle > 0.0)
   {
      if(bid >= g_BB_Upper)
         priceZone = "ABOVE UPPER BAND  [Overbought → SELL signal]";
      else if(bid >= g_BB_Middle)
         priceZone = "Upper half  [" + (isTrending && g_M1PlusDI >= g_M1MinusDI
                      ? "Uptrend — hold longs"
                      : "Bearish bias — watch SELL") + "]";
      else if(bid > g_BB_Lower)
         priceZone = "Lower half  [" + (isTrending && g_M1MinusDI > g_M1PlusDI
                      ? "Downtrend — hold shorts"
                      : "Bullish bias — watch BUY") + "]";
      else
         priceZone = "BELOW LOWER BAND  [Oversold → BUY signal]";
   }
   else priceZone = "---";

   // ── BB width status ───────────────────────────────────────────
   string bbWidthStatus;
   if(BB_Width_Min_ATR > 0.0 && bbWidth > 0.0 && bbWidth < g_ATR * BB_Width_Min_ATR)
      bbWidthStatus = "[SQUEEZE - entry blocked]";
   else if(BB_Width_Max_ATR > 0.0 && bbWidth > 0.0 && bbWidth > g_ATR * BB_Width_Max_ATR)
      bbWidthStatus = "[EXPANDED - entry blocked]";
   else
      bbWidthStatus = "[OK]";

   string info =
      "╔══ PROJECT BB BREAKOUT  v1.2  |  LQS + Bollinger Bands ══╗\n"
      "  Symbol  : " + Symbol()
                     + "   Magic : " + IntegerToString(MagicNumber)        + "\n"
      "  Bid/Ask : " + DoubleToString(bid, _Digits)
                     + " / " + DoubleToString(ask, _Digits)               + "\n"
      "  SGT     : " + TimeToString(sgt, TIME_MINUTES)
                     + "  UTC+" + IntegerToString(BrokerGMTOffset())
                     + "   " + sessStr                                     + "\n"
      "══════════════════════════════════════════════════\n"
      "  BOLLINGER BANDS  (" + IntegerToString(BB_Period) + " SMA, "
                     + DoubleToString(BB_Deviation, 1) + " StdDev)\n"
      "  Upper  : " + DoubleToString(g_BB_Upper,  2) + "  ← SELL extreme" + "\n"
      "  Middle : " + DoubleToString(g_BB_Middle, 2) + "  ← " + IntegerToString(BB_Period) + "-bar SMA (trend baseline)" + "\n"
      "  Lower  : " + DoubleToString(g_BB_Lower,  2) + "  ← BUY  extreme" + "\n"
      "  Width  : " + DoubleToString(bbWidth, 2)
                     + "  ATR=" + DoubleToString(g_ATR, 2)
                     + "  " + bbWidthStatus                                + "\n"
      "──────────────────────────────────────────────────\n"
      "  BB STRATEGY MODE\n"
      "  " + bbMode                                                        + "\n"
      + bbModeDesc                                                         + "\n"
      + bbLongRule                                                         + "\n"
      + bbShortRule                                                        + "\n"
      "──────────────────────────────────────────────────\n"
      "  CURRENT PRICE ZONE\n"
      "  " + priceZone                                                     + "\n"
      "──────────────────────────────────────────────────\n"
      "  LQS ZONES  (Lookback: " + IntegerToString(LQS_Lookback) + " bars)\n"
      "  SELL zone : " + DoubleToString(g_LQS_SwingHigh, 2)
                     + "  ($+" + DoubleToString(distSell, 1) + " away)"  + "\n"
      "    → Spike ABOVE swing + close BELOW + touch BB upper = SELL\n"
      "  BUY  zone : " + DoubleToString(g_LQS_SwingLow, 2)
                     + "  ($-" + DoubleToString(distBuy, 1) + " away)"   + "\n"
      "    → Spike BELOW swing + close ABOVE + touch BB lower = BUY\n"
      "  BB Touch  : " + (BB_Require_Band_Touch   ? "REQUIRED" : "OFF")
                     + "   Midline filter : " + (BB_Midline_Trend_Filter ? "ON" : "OFF")
                     + "   Zone filter : " + (BB_Close_Zone_Filter ? "ON" : "OFF") + "\n"
      "──────────────────────────────────────────────────\n"
      "  TREND / MOMENTUM\n"
      "  ATR(" + IntegerToString(ATR_Period) + ")  : " + DoubleToString(g_ATR, 2)
                     + "  SL=" + (isTrending
                        ? DoubleToString(SL_ATR_Factor,1) + "×ATR=$"
                          + DoubleToString(g_ATR*SL_ATR_Factor,2) + " [TREND]"
                        : DoubleToString(SL_ATR_Ranging_Mult,1) + "×ATR=$"
                          + DoubleToString(g_ATR*SL_ATR_Ranging_Mult,2) + " [RANGING]"
                          + (LQS_Trend_Only ? " BLOCKED" : ""))
                     + (SL_Max_Dollar > 0.0
                        ? "  cap=$" + DoubleToString(SL_Max_Dollar,2)
                          + ((isTrending   ? g_ATR*SL_ATR_Factor       : g_ATR*SL_ATR_Ranging_Mult) > SL_Max_Dollar
                             ? " [SKIP]" : " [OK]")
                        : "")                                              + "\n"
      "  M1 ADX   : " + DoubleToString(g_M1ADX, 1)
                     + "  M1 DI: +" + DoubleToString(g_M1PlusDI, 1)
                     + " / -"       + DoubleToString(g_M1MinusDI, 1)     + "\n"
      "  M5 DI    : +" + DoubleToString(g_M5PlusDI, 1)
                     + " / -"       + DoubleToString(g_M5MinusDI, 1)
                     + (LQS_HTF_DI_Align
                        ? (g_M5PlusDI > g_M5MinusDI ? "  [M5 BULL: SELL blocked]"
                          : g_M5MinusDI > g_M5PlusDI ? "  [M5 BEAR: BUY blocked]"
                          :                             "  [M5 NEUTRAL]")
                        : "  [HTF filter OFF]")                           + "\n"
      "──────────────────────────────────────────────────\n"
      "  Exit     : " + (LQS_Trail_Start > 0.0
                          ? "Trail +$" + DoubleToString(LQS_Trail_Start, 2)
                            + "  step=$" + DoubleToString(LQS_Trail_Step, 2)
                            + (LQS_BE_Trigger > 0.0
                               ? "  BE=$" + DoubleToString(LQS_BE_Trigger, 2)
                                 + "+buf$" + DoubleToString(LQS_BE_Buffer, 2)
                               : "")
                          : (LQS_TP_ATR_Factor > 0.0
                             ? DoubleToString(LQS_TP_ATR_Factor,2) + "×ATR=$"
                               + DoubleToString(g_ATR*LQS_TP_ATR_Factor,2) + " [dynamic]"
                             : "$" + DoubleToString(LQS_TP_Fixed,2) + " [fixed]")) + "\n"
      "  Positions: " + IntegerToString(CountMyPositions())
                     + "   Today P/L: $" + DoubleToString(TodayProfit, 2) + "\n"
      "  Last Entry: " + (LastEntry > 0
                          ? TimeToString(LastEntry, TIME_DATE|TIME_SECONDS)
                          : "---")                                         + "\n"
      "╚══════════════════════════════════════════════════╝";

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
   RefreshBB();
   g_IsNewBar = IsNewBar();

   if(g_IsNewBar)
      UpdateTodayProfit();

   RefreshLQSLevels();
   CheckZoneApproach();

   ManageTrades();
   TryLQSTrade();
   DrawBBLines();
   DrawInfoPanel();
}
//+------------------------------------------------------------------+
