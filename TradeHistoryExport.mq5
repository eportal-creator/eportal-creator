//+------------------------------------------------------------------+
//|                    TRADE HISTORY EXPORT                          |
//|  Exports closed trade history to CSV.                            |
//|  Output: MQL5\Files\TradeHistory.csv                             |
//|  Run: Attach script to any chart. File opens automatically.      |
//+------------------------------------------------------------------+
#property script_show_inputs

input datetime From         = D'2026.01.01 00:00';
input datetime To           = D'2026.12.31 23:59';
input string   FileName     = "TradeHistory.csv";
input bool     OpenFileAfter = true;
// Open the CSV in the default application after export.

void OnStart()
{
   if(!HistorySelect(From, To))
   {
      Print("ERROR: HistorySelect failed.");
      return;
   }

   int total = HistoryDealsTotal();
   if(total == 0)
   {
      Print("No deals found in selected range.");
      return;
   }

   //--- RSI handle for M1 RSI(14) lookups
   int rsiHandle = iRSI(Symbol(), PERIOD_M1, 14, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE)
      Print("WARNING: RSI handle failed — RSI_at_Entry will be 0.");

   //--- First pass: index all ENTRY deals by position ID
   ulong    ep_posID[];
   ulong    ep_ticket[];
   double   ep_price[];
   datetime ep_time[];
   int      ep_type[];
   double   ep_volume[];
   double   ep_rsi[];
   int      epCount = 0;

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;

      ArrayResize(ep_posID,   epCount + 1);
      ArrayResize(ep_ticket,  epCount + 1);
      ArrayResize(ep_price,   epCount + 1);
      ArrayResize(ep_time,    epCount + 1);
      ArrayResize(ep_type,    epCount + 1);
      ArrayResize(ep_volume,  epCount + 1);
      ArrayResize(ep_rsi,     epCount + 1);

      ep_posID  [epCount] = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      ep_ticket [epCount] = ticket;
      ep_price  [epCount] = HistoryDealGetDouble (ticket, DEAL_PRICE);
      ep_time   [epCount] = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      ep_type   [epCount] = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
      ep_volume [epCount] = HistoryDealGetDouble (ticket, DEAL_VOLUME);

      //--- Look up RSI value at the entry bar
      double   rsiVal  = 0.0;
      datetime entryT  = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      int      barShift = iBarShift(Symbol(), PERIOD_M1, entryT, false);
      if(rsiHandle != INVALID_HANDLE && barShift >= 0)
      {
         double rsiBuf[]; ArraySetAsSeries(rsiBuf, true);
         if(CopyBuffer(rsiHandle, 0, barShift, 1, rsiBuf) == 1)
            rsiVal = rsiBuf[0];
      }
      ep_rsi[epCount] = rsiVal;
      epCount++;
   }

   //--- Open CSV file
   int fh = FileOpen(FileName, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(fh == INVALID_HANDLE)
   {
      Print("ERROR: Cannot open file '", FileName, "'. Code=", GetLastError());
      return;
   }

   //--- Header row
   FileWrite(fh,
      "OpenTime", "CloseTime", "Duration(min)",
      "Symbol", "Type", "Volume",
      "OpenPrice", "ClosePrice",
      "Profit", "Commission", "Swap", "NetProfit",
      "RSI_at_Entry",
      "Magic", "Comment", "PositionID"
   );

   //--- Second pass: match EXIT deals to their ENTRY deals
   int written = 0;
   double totalNet = 0.0;

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      ulong    posID     = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      datetime closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      double   closePrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
      double   profit     = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double   commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double   swap       = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double   volume     = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      string   symbol     = HistoryDealGetString(ticket, DEAL_SYMBOL);
      long     magic      = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      string   comment    = HistoryDealGetString(ticket, DEAL_COMMENT);

      //--- Find matching entry deal
      double   openPrice  = 0.0;
      datetime openTime   = 0;
      string   typeStr    = "?";
      double   rsiEntry   = 0.0;

      for(int j = 0; j < epCount; j++)
      {
         if(ep_posID[j] == posID)
         {
            openPrice = ep_price[j];
            openTime  = ep_time[j];
            typeStr   = (ep_type[j] == DEAL_TYPE_BUY) ? "BUY" : "SELL";
            rsiEntry  = ep_rsi[j];
            break;
         }
      }

      long   durationMin = (openTime > 0) ? (long)(closeTime - openTime) / 60 : 0;
      double netProfit   = profit + commission + swap;
      int    digits      = (StringFind(symbol, "JPY") >= 0) ? 3 : 2;
      totalNet          += netProfit;

      FileWrite(fh,
         TimeToString(openTime,  TIME_DATE | TIME_SECONDS),
         TimeToString(closeTime, TIME_DATE | TIME_SECONDS),
         durationMin,
         symbol,
         typeStr,
         DoubleToString(volume,     2),
         DoubleToString(openPrice,  digits),
         DoubleToString(closePrice, digits),
         DoubleToString(profit,     2),
         DoubleToString(commission, 2),
         DoubleToString(swap,       2),
         DoubleToString(netProfit,  2),
         DoubleToString(rsiEntry,   1),
         magic,
         comment,
         posID
      );
      written++;
   }

   //--- Summary row
   FileWrite(fh, "", "", "", "", "", "", "", "TOTAL", "", "", "", DoubleToString(totalNet, 2), "", "", "");

   FileClose(fh);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);

   string path = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + FileName;
   Print("Done. ", written, " trades exported.");
   Print("File: ", path);

   if(OpenFileAfter)
      ShellExecuteW(0, "open", path, "", "", 1);
}

//--- Shell helper to open file
#import "shell32.dll"
int ShellExecuteW(int hwnd, string op, string file, string params, string dir, int show);
#import
