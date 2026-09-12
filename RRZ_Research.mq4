
#property strict


input string ParamFileName         = "params.txt";
input bool   UseCommonFiles        = false;
input string SummaryFileName       = "RRZ_Research_Summary.txt";
input int    MaxScenarios          = 100;


input double StopBufferPips        = 2.0;
input double RR_Multiple           = 1.5;
input int    MaxHoldingBars        = 12;
input bool   UseCommission         = true;
input double CommissionPips        = 0.7;   // round-turn commission in pips per trade

input bool   OneSignalPerBar       = true;
input bool   VerboseJournal        = true;


enum SetupState
{
   ST_IDLE = 0,
   ST_SWEEPED = 1,
   ST_MSS_CONFIRMED = 2,
   ST_WAIT_RETEST = 3
};


struct Scenario
{
   bool   Enabled;
   string Name;

   bool   UseSpreadFilter;
   double MaxSpreadPips;

   int    CooldownBars;
   int    MaxTradesPerDay;
   int    MaxHoldingBars;
   bool   UseInitialSweep;
   double MinBuyTPPips;
   double MinSellTPPips;

   double RR_Multiple;
   double StopBufferPips;
   bool   UseCommission;
   double CommissionPips;


   int    LookbackBars;
   int    ATR_Period;
   double ZoneATR_Mult;
   double MinRangePips;
   string TargetMode;

   bool   UseNextBarOpenEntry;

   bool   RequireStrictSellSweep;
   bool   RequireStrictBuySweep;

   string BuyTargetMode;
   string SellTargetMode;

   double Buy_RR_Multiple;
   double Sell_RR_Multiple;

   double SellSweepBufferPips;
   double BuySweepBufferPips;

   int    SwingStrength;
   bool   UseSweepMSS;
   int    MSSLookbackBars;
   double BreakBufferPips;
   double RetestTolerancePips;
   double SweepMinPips;
   double MinDisplacementPips;
   double FVGMinSizePips;
   bool   UseFVG;
   bool   UseOB;
   string RetestEntryMode;  
   int    PendingExpiryBars;
   string SLMode;           
   string TPMode;           


   bool   UseEarlyExitModel;
   int    EarlyExitBars;
   int    EarlyExitFastEMA;
   int    EarlyExitSlowEMA;

   double Good_MaxAdvEarly_Pips;
   double Good_MinFavEarly_Pips;
   double Good_MinEMAspreadDelta_Pips;
   string Good_FirstMove; 

   double Bad_MinAdvEarly_Pips;
   double Bad_MaxFavEarly_Pips;
   double Bad_MaxEMAspreadDelta_Pips;
   string Bad_FirstMove;  
};

=
struct ScenarioState
{
   bool     InTrade;
   int      Direction;
   datetime EntryTime;
   int      EntryBarShift;
   double   EntryPrice;
   double   StopLoss;
   double   TakeProfit;
   int      HoldingBars;
   datetime LastEntryBarTime;
   datetime LastExitBarTime;
   datetime LastTradeDay;
   int      TradesToday;

   int      TotalTrades;
   int      Wins;
   int      Losses;
   int      TimeExits;
   double   GrossProfit;
   double   GrossLoss;
   double   NetProfit;
   double   SumR;
   double   BestTrade;
   double   WorstTrade;

   double   EquityCurvePips;
   double   PeakEquityPips;
   double   MaxDrawdownSeenPips;
   double   DailyNetPips;
   datetime DailyNetDay;
   bool     DrawdownLocked;
   bool     DailyLossLocked;

   int      LastTradeDirection;
   datetime LastTradeCloseTime;

   string   LogFileName;


   int      SetupStage;            
   int      SetupDirection;        
   datetime SetupStartTime;
   int      SetupStartBarShift;
   int      SweepBarShift;
   double   SweepHigh;
   double   SweepLow;
   double   RangeHigh;
   double   RangeLow;
   double   RangeMid;
   double   RangeATR;
   double   MSSLevel;
   int      MSSBarShift;
   double   ZoneTop;
   double   ZoneBottom;
   bool     ZoneFromFVG;
   bool     ZoneFromOB;
   int      SetupBarsAlive;


   double   PendingEntryPrice;


   int      EarlyBarsSeen;
   double   EarlyMaxFavPips;
   double   EarlyMaxAdvPips;
   double   EarlyEMAStartSpreadPips;
   double   EarlyEMALastSpreadPips;
   string   EarlyFirstMove; 


   int      BarsChecked;
   int      SpreadRejected;
   int      RangeFoundCount;
   int      SweepFoundCount;
   int      MSSFoundCount;
   int      DisplacementOKCount;
   int      FVGFoundCount;
   int      OBFoundCount;
   int      RetestFoundCount;
   int      OrdersPlacedCount;
   int      InvalidSLTPCount;
   int      ExpiredSetupCount;


   datetime LastProcessedClosedBarTime;
};

Scenario      g_scenarios[];
ScenarioState g_states[];
int           g_scenarioCount = 0;
datetime      g_lastBarTime = 0;


MqlRates g_rates[];
int      g_rates_count = 0;


double GetFloatingPnLPips(int idx)
{
   if(!g_states[idx].InTrade) 
      return 0.0;

   double bid = GetBid();
   double ask = GetAsk();
   if(bid <= 0.0 || ask <= 0.0)
      return 0.0;

   if(g_states[idx].Direction == 1)
      return (bid - g_states[idx].EntryPrice) / PipPoint();   // BUY
   else
      return (g_states[idx].EntryPrice - ask) / PipPoint();   // SELL
}

double GetCurrentEquityPips(int idx)
{
   return g_states[idx].EquityCurvePips + GetFloatingPnLPips(idx);
}

double GetCurrentDrawdownPips(int idx)
{
   double eq = GetCurrentEquityPips(idx);
   double dd = g_states[idx].PeakEquityPips - eq;
   if(dd < 0.0) dd = 0.0;
   return dd;
}

double GetDrawdownPercent(int idx)
{
   if(g_states[idx].PeakEquityPips <= 0.0)
      return 0.0;

   return 100.0 * GetCurrentDrawdownPips(idx) / g_states[idx].PeakEquityPips;
}

void UpdateFloatingDrawdownState(int idx)
{
   double eq = GetCurrentEquityPips(idx);

   if(eq > g_states[idx].PeakEquityPips)
      g_states[idx].PeakEquityPips = eq;

   double dd = g_states[idx].PeakEquityPips - eq;
   if(dd > g_states[idx].MaxDrawdownSeenPips)
      g_states[idx].MaxDrawdownSeenPips = dd;
}



string Trim(string s){ string t = s; StringTrimLeft(t); StringTrimRight(t); return t; }

string ToLowerStr(string s)
{
   string t = Trim(s);
   StringToLower(t);
   return t;
}

bool ParseBool(string v, bool def=false)
{
   v = ToLowerStr(v);
   if(v=="1" || v=="true" || v=="yes" || v=="on")  return true;
   if(v=="0" || v=="false" || v=="no" || v=="off") return false;
   return def;
}

int ParseInt(string v, int def=0){ v = Trim(v); if(StringLen(v)==0) return def; return (int)StringToInteger(v); }
double ParseDouble(string v, double def=0.0){ v = Trim(v); if(StringLen(v)==0) return def; return StringToDouble(v); }

int DigitsCount(){ return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS); }
double PointValue(){ return SymbolInfoDouble(_Symbol, SYMBOL_POINT); }

double PipPoint()
{
   int digits = DigitsCount();
   double point = PointValue();
   if(digits == 3 || digits == 5) return point * 10.0;
   return point;
}

double NormalizePrice(double price){ return NormalizeDouble(price, DigitsCount()); }
string BoolToStr(bool v){ return v ? "true" : "false"; }

int FileFlagsRead(){ int flags = FILE_READ | FILE_TXT | FILE_ANSI; if(UseCommonFiles) flags |= FILE_COMMON; return flags; }
int FileFlagsWriteCSV()
{
   int flags = FILE_WRITE | FILE_ANSI;
   if(UseCommonFiles) flags |= FILE_COMMON;
   return flags;
}
int FileFlagsAppendCSV(){ int flags = FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI; if(UseCommonFiles) flags |= FILE_COMMON; return flags; }

void PrintV(string msg){ if(VerboseJournal) Print("[RRZ_PRO_MQL5] ", msg); }

string SafeScenarioFileName(string s)
{
   string out = s;
   StringReplace(out, " ", "_"); StringReplace(out, "/", "_"); StringReplace(out, "\\", "_");
   StringReplace(out, ":", "_"); StringReplace(out, "*", "_"); StringReplace(out, "?", "_");
   StringReplace(out, "\"", "_"); StringReplace(out, "<", "_"); StringReplace(out, ">", "_");
   StringReplace(out, "|", "_");
   return out;
}

datetime DayStart(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

bool RefreshRatesCache(int need_bars)
{
   ArraySetAsSeries(g_rates, true);
   int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, need_bars, g_rates);
   if(copied <= 0)
   {
      Print("CopyRates failed. error=", GetLastError());
      return false;
   }
   g_rates_count = copied;
   return true;
}

int BarsCount(){ return g_rates_count; }
double GetOpen(int shift){ if(shift < 0 || shift >= g_rates_count) return 0.0; return g_rates[shift].open; }
double GetHigh(int shift){ if(shift < 0 || shift >= g_rates_count) return 0.0; return g_rates[shift].high; }
double GetLow(int shift){ if(shift < 0 || shift >= g_rates_count) return 0.0; return g_rates[shift].low; }
double GetClose(int shift){ if(shift < 0 || shift >= g_rates_count) return 0.0; return g_rates[shift].close; }
datetime GetTimeBar(int shift){ if(shift < 0 || shift >= g_rates_count) return 0; return g_rates[shift].time; }
double GetBid(){ return SymbolInfoDouble(_Symbol, SYMBOL_BID); }
double GetAsk(){ return SymbolInfoDouble(_Symbol, SYMBOL_ASK); }

double BodySize(int shift){ return MathAbs(GetClose(shift) - GetOpen(shift)); }
double CandleRange(int shift){ return GetHigh(shift) - GetLow(shift); }
double UpperWick(int shift){ return GetHigh(shift) - MathMax(GetOpen(shift), GetClose(shift)); }
double LowerWick(int shift){ return MathMin(GetOpen(shift), GetClose(shift)) - GetLow(shift); }



double GetCommissionPips(int idx)
{
   if(idx < 0 || idx >= g_scenarioCount)
      return 0.0;

   if(!g_scenarios[idx].UseCommission)
      return 0.0;

   if(g_scenarios[idx].CommissionPips < 0.0)
      return 0.0;

   return g_scenarios[idx].CommissionPips;
}

double GetATRValue(int period, int shift)
{
   if(period <= 1) return 0.0;
   int handle = iATR(_Symbol, PERIOD_CURRENT, period);
   if(handle == INVALID_HANDLE) return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   int need = shift + 5;
   int copied = CopyBuffer(handle, 0, 0, need, buf);
   if(copied <= shift)
   {
      IndicatorRelease(handle);
      return 0.0;
   }

   double v = buf[shift];
   IndicatorRelease(handle);
   return v;
}

double GetEMAValue(int period, int shift)
{
   if(period <= 1) return 0.0;
   int handle = iMA(_Symbol, PERIOD_CURRENT, period, 0, MODE_EMA, PRICE_CLOSE);
   if(handle == INVALID_HANDLE) return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   int need = shift + 5;
   int copied = CopyBuffer(handle, 0, 0, need, buf);
   if(copied <= shift)
   {
      IndicatorRelease(handle);
      return 0.0;
   }

   double v = buf[shift];
   IndicatorRelease(handle);
   return v;
}

double GetEMASpreadPips(int fastPeriod, int slowPeriod, int shift)
{
   double fast = GetEMAValue(fastPeriod, shift);
   double slow = GetEMAValue(slowPeriod, shift);
   if(fast == 0.0 || slow == 0.0) return 0.0;
   return (fast - slow) / PipPoint();
}
 
void LogScenarioEvent(int idx,
                      string eventName,
                      string directionText,
                      double entryPrice,
                      double sl,
                      double tp,
                      double exitPrice,
                      double pnlPips,
                      double rMultiple,
                      string reason,
                      int barShift = 0)
{
   if(idx < 0 || idx >= g_scenarioCount) return;

   string logFileName = g_states[idx].LogFileName;

   int h = FileOpen(logFileName, FileFlagsAppendCSV());
   if(h == INVALID_HANDLE)
      return;

   if(FileSize(h) == 0)
   {
      FileWrite(h,
                "Time",
                "Scenario",
                "Event",

                "BarTime",
                "BarShift",
                "O",
                "H",
                "L",
                "C",

                "Bid",
                "Ask",
                "SpreadPips",

                "SetupStage",
                "SetupDirection",

                "InTrade",
                "TradeDirection",

                "Direction",
                "Entry",
                "SL",
                "TP",
                "Exit",

                "PnL_Pips",
                "R_Multiple",

                "HoldingBars",
                "EarlyBarsSeen",
                "EarlyMaxFavPips",
                "EarlyMaxAdvPips",
                "EarlyFirstMove",

                "Reason");
   }

   double bid = GetBid();
   double ask = GetAsk();

   double spreadPips = 0.0;
   if(bid > 0.0 && ask > 0.0)
      spreadPips = (ask - bid) / PipPoint();

   string setupDir = "NONE";
   if(g_states[idx].SetupDirection == 1) setupDir = "BUY";
   else if(g_states[idx].SetupDirection == -1) setupDir = "SELL";

   string tradeDir = "NONE";
   if(g_states[idx].Direction == 1) tradeDir = "BUY";
   else if(g_states[idx].Direction == -1) tradeDir = "SELL";

   string barTimeText = "";
   string o="", hh="", ll="", c="";
   int usedShift = -1;

   if(barShift >= 0 && barShift < BarsCount())
   {
      usedShift   = barShift;
      barTimeText = TimeToString(GetTimeBar(barShift), TIME_DATE|TIME_MINUTES);
      o  = DoubleToString(GetOpen(barShift), DigitsCount());
      hh = DoubleToString(GetHigh(barShift), DigitsCount());
      ll = DoubleToString(GetLow(barShift), DigitsCount());
      c  = DoubleToString(GetClose(barShift), DigitsCount());
   }

   FileSeek(h, 0, SEEK_END);

   FileWrite(h,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
             g_scenarios[idx].Name,
             eventName,

             barTimeText,
             IntegerToString(usedShift),
             o,
             hh,
             ll,
             c,

             DoubleToString(bid, DigitsCount()),
             DoubleToString(ask, DigitsCount()),
             DoubleToString(spreadPips, 2),

             IntegerToString(g_states[idx].SetupStage),
             setupDir,

             BoolToStr(g_states[idx].InTrade),
             tradeDir,

             directionText,
             DoubleToString(entryPrice, DigitsCount()),
             DoubleToString(sl, DigitsCount()),
             DoubleToString(tp, DigitsCount()),
             DoubleToString(exitPrice, DigitsCount()),

             DoubleToString(pnlPips, 2),
             DoubleToString(rMultiple, 4),

             IntegerToString(g_states[idx].HoldingBars),
             IntegerToString(g_states[idx].EarlyBarsSeen),
             DoubleToString(g_states[idx].EarlyMaxFavPips, 2),
             DoubleToString(g_states[idx].EarlyMaxAdvPips, 2),
             g_states[idx].EarlyFirstMove,

             reason);

   FileClose(h);
}

void LogBarState(int idx, string tag, int barShift, string reason="")
{
   if(idx < 0 || idx >= g_scenarioCount) return;
   if(barShift < 0 || barShift >= BarsCount()) return;

   string logFileName = g_states[idx].LogFileName;

   int h = FileOpen(logFileName, FileFlagsAppendCSV());
   if(h == INVALID_HANDLE)
      return;

   if(FileSize(h) == 0)
   {
      FileWrite(h,
                "Time",
                "Scenario",
                "Event",

                "BarTime",
                "BarShift",
                "O",
                "H",
                "L",
                "C",

                "Bid",
                "Ask",
                "SpreadPips",

                "SetupStage",
                "SetupDirection",

                "InTrade",
                "TradeDirection",

                "Direction",
                "Entry",
                "SL",
                "TP",
                "Exit",

                "PnL_Pips",
                "R_Multiple",

                "HoldingBars",
                "EarlyBarsSeen",
                "EarlyMaxFavPips",
                "EarlyMaxAdvPips",
                "EarlyFirstMove",

                "Reason");
   }

   double bid = GetBid();
   double ask = GetAsk();

   double spreadPips = 0.0;
   if(bid > 0.0 && ask > 0.0)
      spreadPips = (ask - bid) / PipPoint();

   string setupDir = "NONE";
   if(g_states[idx].SetupDirection == 1) setupDir = "BUY";
   else if(g_states[idx].SetupDirection == -1) setupDir = "SELL";

   string tradeDir = "NONE";
   if(g_states[idx].Direction == 1) tradeDir = "BUY";
   else if(g_states[idx].Direction == -1) tradeDir = "SELL";

   FileSeek(h, 0, SEEK_END);

   FileWrite(h,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
             g_scenarios[idx].Name,
             tag,

             TimeToString(GetTimeBar(barShift), TIME_DATE|TIME_MINUTES),
             IntegerToString(barShift),
             DoubleToString(GetOpen(barShift), DigitsCount()),
             DoubleToString(GetHigh(barShift), DigitsCount()),
             DoubleToString(GetLow(barShift), DigitsCount()),
             DoubleToString(GetClose(barShift), DigitsCount()),

             DoubleToString(bid, DigitsCount()),
             DoubleToString(ask, DigitsCount()),
             DoubleToString(spreadPips, 2),

             IntegerToString(g_states[idx].SetupStage),
             setupDir,

             BoolToStr(g_states[idx].InTrade),
             tradeDir,

             tradeDir,
             DoubleToString(g_states[idx].EntryPrice, DigitsCount()),
             DoubleToString(g_states[idx].StopLoss, DigitsCount()),
             DoubleToString(g_states[idx].TakeProfit, DigitsCount()),
             "",

             "",
             "",

             IntegerToString(g_states[idx].HoldingBars),
             IntegerToString(g_states[idx].EarlyBarsSeen),
             DoubleToString(g_states[idx].EarlyMaxFavPips, 2),
             DoubleToString(g_states[idx].EarlyMaxAdvPips, 2),
             g_states[idx].EarlyFirstMove,

             reason);

   FileClose(h);
}



input int    Filter_Lookback        = 4;
input double Filter_BTR_Threshold   = 0.35;  
input double Filter_Comp_Threshold  = 0.65;   
input bool   UsePreEntryFilter      = true;

struct PreEntryFeatures
{
   double avg_body_to_range;
   double compression_ratio;
   double avg_range_pips;
   bool   valid;
};
 

bool ShouldSkipTradeByFilter(int entryBarShift)
{
   if(!UsePreEntryFilter) return false;

   PreEntryFeatures f = ComputePreEntryFeatures(Filter_Lookback, entryBarShift);

   if(!f.valid) return false;


   return (f.avg_body_to_range <= Filter_BTR_Threshold &&
           f.compression_ratio  <= Filter_Comp_Threshold);
} 

PreEntryFeatures ComputePreEntryFeatures(int lookback, int entryBarShift)
{
   PreEntryFeatures f;
   f.valid = false;
   f.avg_body_to_range = 0.0;
   f.compression_ratio = 0.0;

   int startShift = entryBarShift + 1;
   int endShift   = entryBarShift + lookback;

   double sumBTR    = 0.0;
   double sumRange  = 0.0;
   double swingHigh = -DBL_MAX;
   double swingLow  =  DBL_MAX;
   int    count      = 0;

   for(int s = startShift; s <= endShift; s++)
   {
      double o = GetOpen(s);
      double h = GetHigh(s);
      double l = GetLow(s);
      double c = GetClose(s);

      double rng = h - l;
      if(rng > 0) {
         sumBTR += MathAbs(c - o) / rng;
         count++;
      }
      sumRange += rng;
      if(h > swingHigh) swingHigh = h;
      if(l < swingLow)  swingLow  = l;
   }

   if(count > 0 && sumRange > 0)
   {
      f.avg_body_to_range = sumBTR / (double)count;
      f.compression_ratio = (swingHigh - swingLow) / sumRange;
      f.valid = true;
   }
   return f;
}


bool IsSwingHigh(int shift, int strength)
{
   if(shift - strength < 0) return false;
   if(shift + strength >= BarsCount()) return false;

   double h = GetHigh(shift);
   for(int k=1; k<=strength; k++)
   {
      if(h <= GetHigh(shift-k)) return false;
      if(h <= GetHigh(shift+k)) return false;
   }
   return true;
}

bool IsSwingLow(int shift, int strength)
{
   if(shift - strength < 0) return false;
   if(shift + strength >= BarsCount()) return false;

   double l = GetLow(shift);
   for(int k=1; k<=strength; k++)
   {
      if(l >= GetLow(shift-k)) return false;
      if(l >= GetLow(shift+k)) return false;
   }
   return true;
}


bool IsConfirmedSwingHighNow(int shift, int strength)
{
   if(shift < 1 + strength) return false;
   return IsSwingHigh(shift, strength);
}

bool IsConfirmedSwingLowNow(int shift, int strength)
{
   if(shift < 1 + strength) return false;
   return IsSwingLow(shift, strength);
}

bool FindRecentSwingLowBefore(int fromShift, int lookbackBars, int strength, double &level, int &foundShift)
{
   int minConfirmedShift = 1 + strength;
   int startShift = fromShift;
   if(startShift < minConfirmedShift) startShift = minConfirmedShift;

   int endShift = fromShift + lookbackBars;
   if(endShift >= BarsCount()) endShift = BarsCount() - 1;

   for(int s = startShift; s <= endShift; s++)
   {
      if(IsConfirmedSwingLowNow(s, strength))
      {
         level = GetLow(s);
         foundShift = s;
         return true;
      }
   }
   return false;
}

bool FindRecentSwingHighBefore(int fromShift, int lookbackBars, int strength, double &level, int &foundShift)
{
   int minConfirmedShift = 1 + strength;
   int startShift = fromShift;
   if(startShift < minConfirmedShift) startShift = minConfirmedShift;

   int endShift = fromShift + lookbackBars;
   if(endShift >= BarsCount()) endShift = BarsCount() - 1;

   for(int s = startShift; s <= endShift; s++)
   {
      if(IsConfirmedSwingHighNow(s, strength))
      {
         level = GetHigh(s);
         foundShift = s;
         return true;
      }
   }
   return false;
}

bool BuildRangeRRZ(int lookback, int atrPeriod, double &rangeHigh, double &rangeLow, double &mid, double &atr)
{
   if(BarsCount() < lookback + 10) return false;

   rangeHigh = -DBL_MAX;
   rangeLow  =  DBL_MAX;

   for(int i=1; i<=lookback; i++)
   {
      double h = GetHigh(i);
      double l = GetLow(i);
      if(h > rangeHigh) rangeHigh = h;
      if(l < rangeLow)  rangeLow  = l;
   }

   if(rangeHigh <= rangeLow) return false;

   atr = GetATRValue(atrPeriod, 1);
   if(atr <= 0) return false;

   mid = 0.5 * (rangeHigh + rangeLow);
   return true;
}

bool PassCooldown(int idx)
{
   if(g_scenarios[idx].CooldownBars <= 0) return true;
   if(g_states[idx].LastExitBarTime <= 0) return true;

   int barsSinceExit = iBarShift(_Symbol, PERIOD_CURRENT, g_states[idx].LastExitBarTime, false);
   if(barsSinceExit < 0) return true;

   return (barsSinceExit > g_scenarios[idx].CooldownBars);
}

bool PassSpreadFilter(int idx)
{
   if(!g_scenarios[idx].UseSpreadFilter) return true;

   double bid = GetBid();
   double ask = GetAsk();
   if(bid <= 0 || ask <= 0) return false;

   double spreadPips = (ask - bid) / PipPoint();
   return (spreadPips <= g_scenarios[idx].MaxSpreadPips);
}

bool PassMaxTradesPerDay(int idx, datetime signalTime)
{
   datetime d = DayStart(signalTime);

   if(g_states[idx].LastTradeDay != d)
   {
      g_states[idx].LastTradeDay = d;
      g_states[idx].TradesToday = 0;
   }

   return (g_states[idx].TradesToday < g_scenarios[idx].MaxTradesPerDay);
}


void ResetSetup(int idx)
{
   g_states[idx].SetupStage      = ST_IDLE;
   g_states[idx].SetupDirection  = 0;
   g_states[idx].SetupStartTime  = 0;
   g_states[idx].SetupStartBarShift = -1;
   g_states[idx].SweepBarShift   = -1;
   g_states[idx].SweepHigh       = 0.0;
   g_states[idx].SweepLow        = 0.0;
   g_states[idx].RangeHigh       = 0.0;
   g_states[idx].RangeLow        = 0.0;
   g_states[idx].RangeMid        = 0.0;
   g_states[idx].RangeATR        = 0.0;
   g_states[idx].MSSLevel        = 0.0;
   g_states[idx].MSSBarShift     = -1;
   g_states[idx].ZoneTop         = 0.0;
   g_states[idx].ZoneBottom      = 0.0;
   g_states[idx].ZoneFromFVG     = false;
   g_states[idx].ZoneFromOB      = false;
   g_states[idx].SetupBarsAlive  = 0;
   g_states[idx].PendingEntryPrice = 0.0;
}

bool FindBearishFVG(int shift, double minSizePips, double &zoneTop, double &zoneBottom)
{
   if(shift + 2 >= BarsCount())
      return false;

   double high_left  = GetHigh(shift+2);
   double low_left   = GetLow(shift+2);

   double high_right = GetHigh(shift);
   double low_right  = GetLow(shift);

   if(low_right > high_left)
   {
      double sizePips = (low_right - high_left) / PipPoint();
      if(sizePips >= minSizePips)
      {
         zoneTop = low_right;
         zoneBottom = high_left;
         return true;
      }
   }

   return false;
}

bool FindBullishFVG(int shift, double minSizePips, double &zoneTop, double &zoneBottom)
{
   if(shift + 2 >= BarsCount())
      return false;

   double high_left  = GetHigh(shift+2);
   double low_left   = GetLow(shift+2);

   double high_right = GetHigh(shift);
   double low_right  = GetLow(shift);

   if(high_right < low_left)
   {
      double sizePips = (low_left - high_right) / PipPoint();
      if(sizePips >= minSizePips)
      {
         zoneTop = low_left;
         zoneBottom = high_right;
         return true;
      }
   }

   return false;
}

bool FindLastBullishOBBefore(int fromShift, int lookback, double &zoneTop, double &zoneBottom)
{
   if(fromShift < 1)
      fromShift = 1;

   int endShift = fromShift + lookback;
   if(endShift >= BarsCount())
      endShift = BarsCount() - 1;

   for(int s = fromShift; s <= endShift; s++)
   {
      if(GetClose(s) > GetOpen(s))
      {
         zoneTop = GetHigh(s);
         zoneBottom = GetLow(s);
         return true;
      }
   }
   return false;
}

bool FindLastBearishOBBefore(int fromShift, int lookback, double &zoneTop, double &zoneBottom)
{
   int endShift = fromShift + lookback;
   if(endShift >= BarsCount()) endShift = BarsCount() - 1;

   for(int s = fromShift; s <= endShift; s++)
   {
      if(GetClose(s) < GetOpen(s))
      {
         zoneTop = GetHigh(s);
         zoneBottom = GetLow(s);
         return true;
      }
   }
   return false;
}


string NormalizeRetestEntryMode(string mode)
{
   mode = ToLowerStr(mode);
   if(mode == "edge") mode = "touch";
   return mode;
}

double ComputeEntryPriceFromZone(int idx)
{
   double top = MathMax(g_states[idx].ZoneTop, g_states[idx].ZoneBottom);
   double bot = MathMin(g_states[idx].ZoneTop, g_states[idx].ZoneBottom);

   string mode = NormalizeRetestEntryMode(g_scenarios[idx].RetestEntryMode);

   if(mode == "midpoint")
      return NormalizePrice(0.5 * (top + bot));

   if(g_states[idx].SetupDirection == 1)
      return NormalizePrice(bot);
   else
      return NormalizePrice(top);
}

double ComputeEntryPrice(int idx, int barShift)
{
   string mode = NormalizeRetestEntryMode(g_scenarios[idx].RetestEntryMode);
   if(mode == "close")
      return NormalizePrice(GetClose(barShift));

   return ComputeEntryPriceFromZone(idx);
}

bool EntryPriceTouched(int idx, double entryPrice, int barShift)
{
   double h = GetHigh(barShift);
   double l = GetLow(barShift);
   double tol = g_scenarios[idx].RetestTolerancePips * PipPoint();

   return (entryPrice >= l - tol && entryPrice <= h + tol);
} 
double GetPipSize(int idx)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   

   if(digits == 5 || digits == 3)
      return point * 10.0;
   

   if(digits == 2)
      return point * 10.0; 

   return point;
}

double GetPendingFillPrice(int idx, double requestedEntry)
{
   double bid = GetBid();
   double ask = GetAsk();

   if(bid <= 0.0 || ask <= 0.0)
      return 0.0;

   int dir = g_states[idx].SetupDirection;

   if(dir == 1) 
   {
      
      if(ask <= requestedEntry)
         return NormalizePrice(ask);
      return NormalizePrice(ask);
   }

   if(dir == -1) 
   {
      
      if(bid >= requestedEntry)
         return NormalizePrice(bid);
      return NormalizePrice(bid);
   }

   return 0.0;
}


bool EntryPriceInsideZone(int idx, double entryPrice)
{
   double top = MathMax(g_states[idx].ZoneTop, g_states[idx].ZoneBottom);
   double bot = MathMin(g_states[idx].ZoneTop, g_states[idx].ZoneBottom);
   double tol = g_scenarios[idx].RetestTolerancePips * PipPoint();

   return (entryPrice >= bot - tol && entryPrice <= top + tol);
}


bool EntryPriceTouchedNow(int idx, double entryPrice)
{
   double bid = GetBid();
   double ask = GetAsk();
   double tol = g_scenarios[idx].RetestTolerancePips * PipPoint();
   if(bid <= 0.0 || ask <= 0.0)
      return false;

   int dir = g_states[idx].SetupDirection;

   
   if(dir == 1)
      return (ask <= entryPrice + tol);

   
   if(dir == -1)
      return (bid >= entryPrice - tol);

   return false;
}


bool EntryPriceInsideZoneNow(int idx, double entryPrice)
{
   double top = MathMax(g_states[idx].ZoneTop, g_states[idx].ZoneBottom);
   double bot = MathMin(g_states[idx].ZoneTop, g_states[idx].ZoneBottom);
   double tol = g_scenarios[idx].RetestTolerancePips * PipPoint();

   double bid = GetBid();
   double ask = GetAsk();
   if(bid <= 0.0 || ask <= 0.0)
      return false;

   double px = (bid + ask) * 0.5;
   return (px >= bot - tol && px <= top + tol);
}


bool CalcSLTP(int idx, int dir, double entry, double &sl, double &tp)
{
   double top = MathMax(g_states[idx].ZoneTop, g_states[idx].ZoneBottom);
   double bot = MathMin(g_states[idx].ZoneTop, g_states[idx].ZoneBottom);

   string slMode = ToLowerStr(g_scenarios[idx].SLMode);
   string tpMode = ToLowerStr(g_scenarios[idx].TPMode);

   if(dir == 1)
   {
      if(slMode == "abovesweep")
         sl = g_states[idx].SweepLow - g_scenarios[idx].StopBufferPips * PipPoint();
      else if(slMode == "structure")
         sl = MathMin(g_states[idx].RangeLow, bot) - g_scenarios[idx].StopBufferPips * PipPoint();
      else
         sl = g_states[idx].RangeLow - g_scenarios[idx].StopBufferPips * PipPoint();

      double risk = entry - sl;
      if(risk <= 0.0) return false;

      if(tpMode == "fixedr")
         tp = entry + g_scenarios[idx].Buy_RR_Multiple * risk;
      else if(tpMode == "mid")
         tp = g_states[idx].RangeMid;
      else if(tpMode == "oppositerange")
         tp = g_states[idx].RangeHigh;
      else if(tpMode == "oppositezone")
         tp = g_states[idx].RangeHigh - g_scenarios[idx].ZoneATR_Mult * g_states[idx].RangeATR;
      else
         tp = entry + g_scenarios[idx].Buy_RR_Multiple * risk;

      if(tp <= entry) return false;

      double tpDistPips = (tp - entry) / PipPoint();
      if(tpDistPips < g_scenarios[idx].MinBuyTPPips)
         return false;
   }
   else
   {
      if(slMode == "abovesweep")
         sl = g_states[idx].SweepHigh + g_scenarios[idx].StopBufferPips * PipPoint();
      else if(slMode == "structure")
         sl = MathMax(g_states[idx].RangeHigh, top) + g_scenarios[idx].StopBufferPips * PipPoint();
      else
         sl = g_states[idx].RangeHigh + g_scenarios[idx].StopBufferPips * PipPoint();

      double risk = sl - entry;
      if(risk <= 0.0) return false;

      if(tpMode == "fixedr")
         tp = entry - g_scenarios[idx].Sell_RR_Multiple * risk;
      else if(tpMode == "mid")
         tp = g_states[idx].RangeMid;
      else if(tpMode == "oppositerange")
         tp = g_states[idx].RangeLow;
      else if(tpMode == "oppositezone")
         tp = g_states[idx].RangeLow + g_scenarios[idx].ZoneATR_Mult * g_states[idx].RangeATR;
      else
         tp = entry - g_scenarios[idx].Sell_RR_Multiple * risk;

      if(tp >= entry) return false;

      double tpDistPips = (entry - tp) / PipPoint();
      if(tpDistPips < g_scenarios[idx].MinSellTPPips)
         return false;
   }

   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
   return true;
}


void InitScenarioDefaults(int idx)
{
   g_scenarios[idx].Enabled           = true;
   g_scenarios[idx].Name              = "Scenario_RRZ";

   g_scenarios[idx].UseSpreadFilter   = true;
   g_scenarios[idx].MaxSpreadPips     = 2.0;

   g_scenarios[idx].CooldownBars      = 0;
   g_scenarios[idx].MaxTradesPerDay   = 999999;
   g_scenarios[idx].MaxHoldingBars    = MaxHoldingBars;

   g_scenarios[idx].RR_Multiple       = RR_Multiple;
   g_scenarios[idx].StopBufferPips    = StopBufferPips;
   g_scenarios[idx].UseCommission = UseCommission;
   g_scenarios[idx].CommissionPips = CommissionPips;

   g_scenarios[idx].UseInitialSweep = true;
   g_scenarios[idx].MinBuyTPPips  = 25.0;
   g_scenarios[idx].MinSellTPPips = 25.0;

   g_scenarios[idx].LookbackBars      = 48;
   g_scenarios[idx].ATR_Period        = 14;
   g_scenarios[idx].ZoneATR_Mult      = 0.8;
   g_scenarios[idx].MinRangePips      = 10.0;
   g_scenarios[idx].TargetMode        = "rr";

   g_scenarios[idx].UseNextBarOpenEntry = true;

   g_scenarios[idx].RequireStrictSellSweep = true;
   g_scenarios[idx].RequireStrictBuySweep  = false;

   g_scenarios[idx].BuyTargetMode  = "rr";
   g_scenarios[idx].SellTargetMode = "mid";

   g_scenarios[idx].Buy_RR_Multiple  = RR_Multiple;
   g_scenarios[idx].Sell_RR_Multiple = 1.20;

   g_scenarios[idx].SellSweepBufferPips = 0.0;
   g_scenarios[idx].BuySweepBufferPips  = 0.0;

   g_scenarios[idx].SwingStrength = 2;
   g_scenarios[idx].UseSweepMSS = true;
   g_scenarios[idx].MSSLookbackBars = 12;
   g_scenarios[idx].BreakBufferPips = 1.0;
   g_scenarios[idx].RetestTolerancePips = 0.0;
   g_scenarios[idx].SweepMinPips = 1.5;
   g_scenarios[idx].MinDisplacementPips = 5.0;
   g_scenarios[idx].FVGMinSizePips = 2.0;
   g_scenarios[idx].UseFVG = true;
   g_scenarios[idx].UseOB = true;
   g_scenarios[idx].RetestEntryMode = "midpoint";
   g_scenarios[idx].PendingExpiryBars = 6;
   g_scenarios[idx].SLMode = "abovesweep";
   g_scenarios[idx].TPMode = "fixedr";

   // Early exit defaults
   g_scenarios[idx].UseEarlyExitModel = false;
   g_scenarios[idx].EarlyExitBars = 5;
   g_scenarios[idx].EarlyExitFastEMA = 9;
   g_scenarios[idx].EarlyExitSlowEMA = 21;

   g_scenarios[idx].Good_MaxAdvEarly_Pips = 3.0;
   g_scenarios[idx].Good_MinFavEarly_Pips = 4.0;
   g_scenarios[idx].Good_MinEMAspreadDelta_Pips = 0.0;
   g_scenarios[idx].Good_FirstMove = "fav";

   g_scenarios[idx].Bad_MinAdvEarly_Pips = 3.0;
   g_scenarios[idx].Bad_MaxFavEarly_Pips = 3.0;
   g_scenarios[idx].Bad_MaxEMAspreadDelta_Pips = 0.0;
   g_scenarios[idx].Bad_FirstMove = "none";
}

void InitStateDefaults(int idx, string scenarioName)
{
   g_states[idx].InTrade          = false;
   g_states[idx].Direction        = 0;
   g_states[idx].EntryTime        = 0;
   g_states[idx].EntryBarShift    = -1;
   g_states[idx].EntryPrice       = 0;
   g_states[idx].StopLoss         = 0;
   g_states[idx].TakeProfit       = 0;
   g_states[idx].HoldingBars      = 0;
   g_states[idx].LastEntryBarTime = 0;
   g_states[idx].LastExitBarTime  = 0;
   g_states[idx].LastTradeDay     = 0;
   g_states[idx].TradesToday      = 0;

   g_states[idx].TotalTrades      = 0;
   g_states[idx].Wins             = 0;
   g_states[idx].Losses           = 0;
   g_states[idx].TimeExits        = 0;
   g_states[idx].GrossProfit      = 0;
   g_states[idx].GrossLoss        = 0;
   g_states[idx].NetProfit        = 0;
   g_states[idx].SumR             = 0;
   g_states[idx].BestTrade        = -DBL_MAX;
   g_states[idx].WorstTrade       = DBL_MAX;

   g_states[idx].EquityCurvePips     = 0.0;
   g_states[idx].PeakEquityPips      = 0.0;
   g_states[idx].MaxDrawdownSeenPips = 0.0;
   g_states[idx].DailyNetPips        = 0.0;
   g_states[idx].DailyNetDay         = 0;
   g_states[idx].DrawdownLocked      = false;
   g_states[idx].DailyLossLocked     = false;

   g_states[idx].LastTradeDirection = 0;
   g_states[idx].LastTradeCloseTime = 0;

   g_states[idx].LogFileName = SafeScenarioFileName("RRZ_Log_" + scenarioName + ".txt");

   g_states[idx].BarsChecked = 0;
   g_states[idx].SpreadRejected = 0;
   g_states[idx].RangeFoundCount = 0;
   g_states[idx].SweepFoundCount = 0;
   g_states[idx].MSSFoundCount = 0;
   g_states[idx].DisplacementOKCount = 0;
   g_states[idx].FVGFoundCount = 0;
   g_states[idx].OBFoundCount = 0;
   g_states[idx].RetestFoundCount = 0;
   g_states[idx].OrdersPlacedCount = 0;
   g_states[idx].InvalidSLTPCount = 0;
   g_states[idx].ExpiredSetupCount = 0;

   g_states[idx].PendingEntryPrice = 0.0;

   g_states[idx].EarlyBarsSeen = 0;
   g_states[idx].EarlyMaxFavPips = 0.0;
   g_states[idx].EarlyMaxAdvPips = 0.0;
   g_states[idx].EarlyEMAStartSpreadPips = 0.0;
   g_states[idx].EarlyEMALastSpreadPips = 0.0;
   g_states[idx].EarlyFirstMove = "NONE";

   g_states[idx].LastProcessedClosedBarTime = 0;

   ResetSetup(idx);

   int h = FileOpen(g_states[idx].LogFileName, FileFlagsWriteCSV());
   if(h != INVALID_HANDLE)
      FileClose(h);
}

void ApplyKeyValueToScenario(int idx, string key, string val)
{
   key = ToLowerStr(key);
   val = Trim(val);

   if(key=="enabled")                g_scenarios[idx].Enabled           = ParseBool(val, g_scenarios[idx].Enabled);
   else if(key=="name" || key=="scenario") g_scenarios[idx].Name        = val;

   else if(key=="usespreadfilter")   g_scenarios[idx].UseSpreadFilter   = ParseBool(val, g_scenarios[idx].UseSpreadFilter);
   else if(key=="maxspreadpips")     g_scenarios[idx].MaxSpreadPips     = ParseDouble(val, g_scenarios[idx].MaxSpreadPips);

   else if(key=="cooldownbars")      g_scenarios[idx].CooldownBars      = ParseInt(val, g_scenarios[idx].CooldownBars);
   else if(key=="maxtradesperday")   g_scenarios[idx].MaxTradesPerDay   = ParseInt(val, g_scenarios[idx].MaxTradesPerDay);
   else if(key=="usecommission")
      g_scenarios[idx].UseCommission = ParseBool(val, g_scenarios[idx].UseCommission);
   else if(key=="commissionpips")
      g_scenarios[idx].CommissionPips = ParseDouble(val, g_scenarios[idx].CommissionPips);
   else if(key=="minbuytppips")
      g_scenarios[idx].MinBuyTPPips = ParseDouble(val, g_scenarios[idx].MinBuyTPPips);
   else if(key=="minselltppips")
      g_scenarios[idx].MinSellTPPips = ParseDouble(val, g_scenarios[idx].MinSellTPPips);

   else if(key=="maxholdingbars")    g_scenarios[idx].MaxHoldingBars    = ParseInt(val, g_scenarios[idx].MaxHoldingBars);
   else if(key=="rr_multiple" || key=="rrmultiple") g_scenarios[idx].RR_Multiple = ParseDouble(val, g_scenarios[idx].RR_Multiple);
   else if(key=="stopbufferpips")    g_scenarios[idx].StopBufferPips    = ParseDouble(val, g_scenarios[idx].StopBufferPips);
   else if(key=="useinitialsweep")
      g_scenarios[idx].UseInitialSweep = ParseBool(val, g_scenarios[idx].UseInitialSweep);

   else if(key=="lookbackbars")      g_scenarios[idx].LookbackBars      = ParseInt(val, g_scenarios[idx].LookbackBars);
   else if(key=="atr_period" || key=="atrperiod") g_scenarios[idx].ATR_Period = ParseInt(val, g_scenarios[idx].ATR_Period);
   else if(key=="zoneatr_mult" || key=="zoneatrmult") g_scenarios[idx].ZoneATR_Mult = ParseDouble(val, g_scenarios[idx].ZoneATR_Mult);
   else if(key=="minrangepips")      g_scenarios[idx].MinRangePips      = ParseDouble(val, g_scenarios[idx].MinRangePips);
   else if(key=="targetmode")        g_scenarios[idx].TargetMode        = ToLowerStr(val);

   else if(key=="usenextbaropenentry" || key=="useopennextbarentry")
      g_scenarios[idx].UseNextBarOpenEntry = ParseBool(val, g_scenarios[idx].UseNextBarOpenEntry);

   else if(key=="requirestrictsellsweep" || key=="strictsell")
      g_scenarios[idx].RequireStrictSellSweep = ParseBool(val, g_scenarios[idx].RequireStrictSellSweep);

   else if(key=="requirestrictbuysweep" || key=="strictbuy")
      g_scenarios[idx].RequireStrictBuySweep = ParseBool(val, g_scenarios[idx].RequireStrictBuySweep);

   else if(key=="buytargetmode")
      g_scenarios[idx].BuyTargetMode = ToLowerStr(val);

   else if(key=="selltargetmode")
      g_scenarios[idx].SellTargetMode = ToLowerStr(val);

   else if(key=="buy_rr_multiple" || key=="buyrrmultiple")
      g_scenarios[idx].Buy_RR_Multiple = ParseDouble(val, g_scenarios[idx].Buy_RR_Multiple);

   else if(key=="sell_rr_multiple" || key=="sellrrmultiple")
      g_scenarios[idx].Sell_RR_Multiple = ParseDouble(val, g_scenarios[idx].Sell_RR_Multiple);

   else if(key=="sellsweepbufferpips")
      g_scenarios[idx].SellSweepBufferPips = ParseDouble(val, g_scenarios[idx].SellSweepBufferPips);

   else if(key=="buysweepbufferpips")
      g_scenarios[idx].BuySweepBufferPips = ParseDouble(val, g_scenarios[idx].BuySweepBufferPips);

   else if(key=="swingstrength")
      g_scenarios[idx].SwingStrength = ParseInt(val, g_scenarios[idx].SwingStrength);
   else if(key=="usesweepmss")
      g_scenarios[idx].UseSweepMSS = ParseBool(val, g_scenarios[idx].UseSweepMSS);
   else if(key=="msslookbackbars")
      g_scenarios[idx].MSSLookbackBars = ParseInt(val, g_scenarios[idx].MSSLookbackBars);
   else if(key=="breakbufferpips")
      g_scenarios[idx].BreakBufferPips = ParseDouble(val, g_scenarios[idx].BreakBufferPips);
   else if(key=="retesttolerancepips")
      g_scenarios[idx].RetestTolerancePips = ParseDouble(val, g_scenarios[idx].RetestTolerancePips);
   else if(key=="sweepminpips")
      g_scenarios[idx].SweepMinPips = ParseDouble(val, g_scenarios[idx].SweepMinPips);
   else if(key=="mindisplacementpips")
      g_scenarios[idx].MinDisplacementPips = ParseDouble(val, g_scenarios[idx].MinDisplacementPips);
   else if(key=="fvgminsizepips")
      g_scenarios[idx].FVGMinSizePips = ParseDouble(val, g_scenarios[idx].FVGMinSizePips);
   else if(key=="usefvg")
      g_scenarios[idx].UseFVG = ParseBool(val, g_scenarios[idx].UseFVG);
   else if(key=="useob")
      g_scenarios[idx].UseOB = ParseBool(val, g_scenarios[idx].UseOB);
   else if(key=="retestentrymode")
      g_scenarios[idx].RetestEntryMode = ToLowerStr(val);
   else if(key=="pendingexpirybars")
      g_scenarios[idx].PendingExpiryBars = ParseInt(val, g_scenarios[idx].PendingExpiryBars);
   else if(key=="slmode")
      g_scenarios[idx].SLMode = ToLowerStr(val);
   else if(key=="tpmode")
      g_scenarios[idx].TPMode = ToLowerStr(val);


   else if(key=="useearlyexitmodel")
      g_scenarios[idx].UseEarlyExitModel = ParseBool(val, g_scenarios[idx].UseEarlyExitModel);
   else if(key=="earlyexitbars")
      g_scenarios[idx].EarlyExitBars = ParseInt(val, g_scenarios[idx].EarlyExitBars);
   else if(key=="earlyexitfastema")
      g_scenarios[idx].EarlyExitFastEMA = ParseInt(val, g_scenarios[idx].EarlyExitFastEMA);
   else if(key=="earlyexitslowema")
      g_scenarios[idx].EarlyExitSlowEMA = ParseInt(val, g_scenarios[idx].EarlyExitSlowEMA);

   else if(key=="good_maxadvearly_pips")
      g_scenarios[idx].Good_MaxAdvEarly_Pips = ParseDouble(val, g_scenarios[idx].Good_MaxAdvEarly_Pips);
   else if(key=="good_minfavearly_pips")
      g_scenarios[idx].Good_MinFavEarly_Pips = ParseDouble(val, g_scenarios[idx].Good_MinFavEarly_Pips);
   else if(key=="good_minemaspreaddelta_pips")
      g_scenarios[idx].Good_MinEMAspreadDelta_Pips = ParseDouble(val, g_scenarios[idx].Good_MinEMAspreadDelta_Pips);
   else if(key=="good_firstmove")
      g_scenarios[idx].Good_FirstMove = ToLowerStr(val);

   else if(key=="bad_minadvearly_pips")
      g_scenarios[idx].Bad_MinAdvEarly_Pips = ParseDouble(val, g_scenarios[idx].Bad_MinAdvEarly_Pips);
   else if(key=="bad_maxfavearly_pips")
      g_scenarios[idx].Bad_MaxFavEarly_Pips = ParseDouble(val, g_scenarios[idx].Bad_MaxFavEarly_Pips);
   else if(key=="bad_maxemaspreaddelta_pips")
      g_scenarios[idx].Bad_MaxEMAspreadDelta_Pips = ParseDouble(val, g_scenarios[idx].Bad_MaxEMAspreadDelta_Pips);
   else if(key=="bad_firstmove")
      g_scenarios[idx].Bad_FirstMove = ToLowerStr(val);
}

bool ParseScenarioLine(string line, int idx)
{
   line = Trim(line);
   if(StringLen(line)==0) return false;
   if(StringSubstr(line,0,1)=="#") return false;

   InitScenarioDefaults(idx);

   string parts[];
   int n = StringSplit(line, ';', parts);
   if(n <= 0) return false;

   for(int i=0; i<n; i++)
   {
      string kv = Trim(parts[i]);
      if(StringLen(kv)==0) continue;

      int pos = StringFind(kv, "=");
      if(pos < 0) continue;

      string key = StringSubstr(kv, 0, pos);
      string val = StringSubstr(kv, pos+1);
      ApplyKeyValueToScenario(idx, key, val);
   }

   if(StringLen(Trim(g_scenarios[idx].Name))==0)
      g_scenarios[idx].Name = "Scenario_RRZ";

   g_scenarios[idx].TargetMode       = ToLowerStr(g_scenarios[idx].TargetMode);
   g_scenarios[idx].BuyTargetMode    = ToLowerStr(g_scenarios[idx].BuyTargetMode);
   g_scenarios[idx].SellTargetMode   = ToLowerStr(g_scenarios[idx].SellTargetMode);
   g_scenarios[idx].RetestEntryMode  = NormalizeRetestEntryMode(g_scenarios[idx].RetestEntryMode);
   g_scenarios[idx].SLMode           = ToLowerStr(g_scenarios[idx].SLMode);
   g_scenarios[idx].TPMode           = ToLowerStr(g_scenarios[idx].TPMode);
   g_scenarios[idx].Good_FirstMove   = ToLowerStr(g_scenarios[idx].Good_FirstMove);
   g_scenarios[idx].Bad_FirstMove    = ToLowerStr(g_scenarios[idx].Bad_FirstMove);

   if(g_scenarios[idx].TargetMode!="rr" && g_scenarios[idx].TargetMode!="mid")
      g_scenarios[idx].TargetMode = "rr";

   if(g_scenarios[idx].BuyTargetMode!="rr" && g_scenarios[idx].BuyTargetMode!="mid")
      g_scenarios[idx].BuyTargetMode = g_scenarios[idx].TargetMode;

   if(g_scenarios[idx].SellTargetMode!="rr" && g_scenarios[idx].SellTargetMode!="mid")
      g_scenarios[idx].SellTargetMode = g_scenarios[idx].TargetMode;

   if(g_scenarios[idx].RetestEntryMode!="touch" && g_scenarios[idx].RetestEntryMode!="midpoint" && g_scenarios[idx].RetestEntryMode!="close")
      g_scenarios[idx].RetestEntryMode = "midpoint";

   if(g_scenarios[idx].SLMode!="abovesweep" && g_scenarios[idx].SLMode!="structure" && g_scenarios[idx].SLMode!="beyondzone")
      g_scenarios[idx].SLMode = "abovesweep";

   if(g_scenarios[idx].TPMode!="fixedr" && g_scenarios[idx].TPMode!="mid" && g_scenarios[idx].TPMode!="oppositerange" && g_scenarios[idx].TPMode!="oppositezone")
      g_scenarios[idx].TPMode = "fixedr";

   if(g_scenarios[idx].Good_FirstMove!="fav" && g_scenarios[idx].Good_FirstMove!="adv" && g_scenarios[idx].Good_FirstMove!="none")
      g_scenarios[idx].Good_FirstMove = "fav";

   if(g_scenarios[idx].Bad_FirstMove!="fav" && g_scenarios[idx].Bad_FirstMove!="adv" && g_scenarios[idx].Bad_FirstMove!="none")
      g_scenarios[idx].Bad_FirstMove = "none";

   if(g_scenarios[idx].Buy_RR_Multiple <= 0.0)
      g_scenarios[idx].Buy_RR_Multiple = g_scenarios[idx].RR_Multiple;

   if(g_scenarios[idx].Sell_RR_Multiple <= 0.0)
      g_scenarios[idx].Sell_RR_Multiple = g_scenarios[idx].RR_Multiple;

   if(g_scenarios[idx].EarlyExitBars <= 0)
      g_scenarios[idx].EarlyExitBars = 5;

   if(g_scenarios[idx].EarlyExitFastEMA <= 1)
      g_scenarios[idx].EarlyExitFastEMA = 9;

   if(g_scenarios[idx].EarlyExitSlowEMA <= 1)
      g_scenarios[idx].EarlyExitSlowEMA = 21;

   return true;
}

bool LoadScenarios()
{
   g_scenarioCount = 0;
   ArrayResize(g_scenarios, 0);
   ArrayResize(g_states, 0);

   int h = FileOpen(ParamFileName, FileFlagsRead());
   if(h == INVALID_HANDLE)
   {
      Print("Failed to open params file: ", ParamFileName, " error=", GetLastError(), " UseCommonFiles=", UseCommonFiles);
      return false;
   }

   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      line = Trim(line);
      if(StringLen(line)==0) continue;
      if(StringSubstr(line,0,1)=="#") continue;

      if(g_scenarioCount >= MaxScenarios) break;

      int newSize = g_scenarioCount + 1;
      ArrayResize(g_scenarios, newSize);
      ArrayResize(g_states, newSize);

      if(!ParseScenarioLine(line, g_scenarioCount))
         continue;

      InitStateDefaults(g_scenarioCount, g_scenarios[g_scenarioCount].Name);
      g_scenarioCount++;
   }

   FileClose(h);

   PrintV("Loaded scenarios: " + IntegerToString(g_scenarioCount));
   return (g_scenarioCount > 0);
}

void ResetEarlyTradeStats(int idx)
{
   g_states[idx].EarlyBarsSeen = 0;
   g_states[idx].EarlyMaxFavPips = 0.0;
   g_states[idx].EarlyMaxAdvPips = 0.0;
   g_states[idx].EarlyEMAStartSpreadPips = 0.0;
   g_states[idx].EarlyEMALastSpreadPips = 0.0;
   g_states[idx].EarlyFirstMove = "NONE";
}




 



void UpdateEarlyTradeStatsOnBar(int idx, int barShift)
{
   if(!g_states[idx].InTrade) return;
   if(barShift <= 0) return;
   if(g_scenarios[idx].EarlyExitBars <= 0) return;
   if(g_states[idx].EarlyBarsSeen >= g_scenarios[idx].EarlyExitBars) return;

   double fav = 0.0;
   double adv = 0.0;

   if(g_states[idx].Direction == 1)
   {
      fav = (GetHigh(barShift) - g_states[idx].EntryPrice) / PipPoint();
      adv = (g_states[idx].EntryPrice - GetLow(barShift)) / PipPoint();
   }
   else
   {
      fav = (g_states[idx].EntryPrice - GetLow(barShift)) / PipPoint();
      adv = (GetHigh(barShift) - g_states[idx].EntryPrice) / PipPoint();
   }

   if(fav < 0.0) fav = 0.0;
   if(adv < 0.0) adv = 0.0;

   if(fav > g_states[idx].EarlyMaxFavPips)
      g_states[idx].EarlyMaxFavPips = fav;

   if(adv > g_states[idx].EarlyMaxAdvPips)
      g_states[idx].EarlyMaxAdvPips = adv;

   double emaSpread = GetEMASpreadPips(g_scenarios[idx].EarlyExitFastEMA, g_scenarios[idx].EarlyExitSlowEMA, barShift);

   if(g_states[idx].EarlyBarsSeen == 0)
      g_states[idx].EarlyEMAStartSpreadPips = emaSpread;

   g_states[idx].EarlyEMALastSpreadPips = emaSpread;

   if(g_states[idx].EarlyFirstMove == "NONE")
   {
      if(fav > 0.0 && adv <= 0.0)
         g_states[idx].EarlyFirstMove = "FAV";
      else if(adv > 0.0 && fav <= 0.0)
         g_states[idx].EarlyFirstMove = "ADV";
      else if(fav > adv && fav > 0.0)
         g_states[idx].EarlyFirstMove = "FAV";
      else if(adv > fav && adv > 0.0)
         g_states[idx].EarlyFirstMove = "ADV";
   }

   g_states[idx].EarlyBarsSeen++;
}

bool MatchFirstMove(string actualUpper, string expectedLower)
{
   if(expectedLower == "none") return true;
   string a = ToLowerStr(actualUpper);
   return (a == expectedLower);
}

bool CheckEarlyGoodExit(int idx)
{
   if(!g_scenarios[idx].UseEarlyExitModel) return false;
   if(g_states[idx].EarlyBarsSeen <= 0) return false;
   if(g_states[idx].EarlyBarsSeen > g_scenarios[idx].EarlyExitBars) return false;

   double emaDelta = g_states[idx].EarlyEMALastSpreadPips - g_states[idx].EarlyEMAStartSpreadPips;

   if(g_states[idx].EarlyMaxAdvPips <= g_scenarios[idx].Good_MaxAdvEarly_Pips &&
      g_states[idx].EarlyMaxFavPips >= g_scenarios[idx].Good_MinFavEarly_Pips &&
      emaDelta >= g_scenarios[idx].Good_MinEMAspreadDelta_Pips &&
      MatchFirstMove(g_states[idx].EarlyFirstMove, g_scenarios[idx].Good_FirstMove))
      return true;

   return false;
}

bool CheckEarlyBadExit(int idx)
{
   if(!g_scenarios[idx].UseEarlyExitModel) return false;
   if(g_states[idx].EarlyBarsSeen <= 0) return false;
   if(g_states[idx].EarlyBarsSeen > g_scenarios[idx].EarlyExitBars) return false;

   double emaDelta = g_states[idx].EarlyEMALastSpreadPips - g_states[idx].EarlyEMAStartSpreadPips;

   if(g_states[idx].EarlyMaxAdvPips >= g_scenarios[idx].Bad_MinAdvEarly_Pips &&
      g_states[idx].EarlyMaxFavPips <= g_scenarios[idx].Bad_MaxFavEarly_Pips &&
      emaDelta <= g_scenarios[idx].Bad_MaxEMAspreadDelta_Pips &&
      MatchFirstMove(g_states[idx].EarlyFirstMove, g_scenarios[idx].Bad_FirstMove))
      return true;

   return false;
}


void OpenVirtualTrade_RRZ(int idx, int dir, double entry, double sl, double tp, string reason, int entryBarShift)
{
   g_states[idx].InTrade          = true;
   g_states[idx].Direction        = dir;
   g_states[idx].EntryTime        = TimeCurrent();
   g_states[idx].EntryBarShift    = entryBarShift;
   g_states[idx].EntryPrice       = NormalizePrice(entry);
   g_states[idx].StopLoss         = NormalizePrice(sl);
   g_states[idx].TakeProfit       = NormalizePrice(tp);
   g_states[idx].HoldingBars      = 0;
   g_states[idx].LastEntryBarTime = GetTimeBar(0);
   g_states[idx].TradesToday++;
   g_states[idx].OrdersPlacedCount++;

   ResetEarlyTradeStats(idx);

   string dirTxt = (dir == 1 ? "BUY" : "SELL");
   LogScenarioEvent(idx, "ENTRY", dirTxt,
                    g_states[idx].EntryPrice,
                    g_states[idx].StopLoss,
                    g_states[idx].TakeProfit,
                    0, 0, 0,
                    reason,
                    0);

   ResetSetup(idx);
}

void UpdateDrawdownStateAfterClose(int idx, double pnlPips)
{
   datetime today = DayStart(TimeCurrent());
   if(g_states[idx].DailyNetDay != today)
   {
      g_states[idx].DailyNetDay = today;
      g_states[idx].DailyNetPips = 0.0;
      g_states[idx].DailyLossLocked = false;
   }

   g_states[idx].EquityCurvePips += pnlPips;

   if(g_states[idx].EquityCurvePips > g_states[idx].PeakEquityPips)
      g_states[idx].PeakEquityPips = g_states[idx].EquityCurvePips;

   double dd = g_states[idx].PeakEquityPips - g_states[idx].EquityCurvePips;
   if(dd > g_states[idx].MaxDrawdownSeenPips)
      g_states[idx].MaxDrawdownSeenPips = dd;

   g_states[idx].DailyNetPips += pnlPips;
}

void CloseVirtualTrade(int idx, double exitPrice, string reason, bool isWin, bool isLoss, bool isTimeExit)
{
   if(!g_states[idx].InTrade) return;

   double riskPrice = 0.0;
   double grossPnlPips = 0.0;
   double commissionPips = 0.0;
   double pnlPips = 0.0;
   double rmult = 0.0;


   exitPrice = NormalizePrice(exitPrice);

   if(g_states[idx].Direction == 1)
   {
      riskPrice    = g_states[idx].EntryPrice - g_states[idx].StopLoss;
      grossPnlPips = (exitPrice - g_states[idx].EntryPrice) / PipPoint();
   }
   else
   {
      riskPrice    = g_states[idx].StopLoss - g_states[idx].EntryPrice;
      grossPnlPips = (g_states[idx].EntryPrice - exitPrice) / PipPoint();
   }

   commissionPips = GetCommissionPips(idx);
   pnlPips = grossPnlPips - commissionPips;

   if(riskPrice > 0.0)
      rmult = (pnlPips * PipPoint()) / riskPrice;


   g_states[idx].TotalTrades++;
   if(isWin)      g_states[idx].Wins++;
   if(isLoss)     g_states[idx].Losses++;
   if(isTimeExit) g_states[idx].TimeExits++;

   if(pnlPips >= 0.0) g_states[idx].GrossProfit += pnlPips;
   else               g_states[idx].GrossLoss   += -pnlPips;

   g_states[idx].NetProfit = g_states[idx].GrossProfit - g_states[idx].GrossLoss;
   g_states[idx].SumR += rmult;

   if(g_states[idx].BestTrade == -DBL_MAX || pnlPips > g_states[idx].BestTrade) g_states[idx].BestTrade = pnlPips;
   if(g_states[idx].WorstTrade == DBL_MAX || pnlPips < g_states[idx].WorstTrade) g_states[idx].WorstTrade = pnlPips;

   g_states[idx].LastExitBarTime = GetTimeBar(1);
   g_states[idx].LastTradeDirection = g_states[idx].Direction;
   g_states[idx].LastTradeCloseTime = TimeCurrent();

   UpdateDrawdownStateAfterClose(idx, pnlPips);

   string dirTxt = (g_states[idx].Direction == 1 ? "BUY" : "SELL");
   LogScenarioEvent(idx, "EXIT", dirTxt,
                    g_states[idx].EntryPrice,
                    g_states[idx].StopLoss,
                    g_states[idx].TakeProfit,
                    exitPrice,
                    pnlPips,
                    rmult,
                    reason,
                    0);

   g_states[idx].InTrade       = false;
   g_states[idx].Direction     = 0;
   g_states[idx].EntryTime     = 0;
   g_states[idx].EntryBarShift = -1;
   g_states[idx].EntryPrice    = 0;
   g_states[idx].StopLoss      = 0;
   g_states[idx].TakeProfit    = 0;
   g_states[idx].HoldingBars   = 0;

   ResetEarlyTradeStats(idx);
}


void CheckTradeHitNow(int idx)
{
   if(!g_states[idx].InTrade) return;

   double bid = GetBid();
   double ask = GetAsk();
   if(bid <= 0.0 || ask <= 0.0) return;

   if(g_states[idx].Direction == 1)
   {
      if(bid <= g_states[idx].StopLoss)
      {
         CloseVirtualTrade(idx, g_states[idx].StopLoss, "TICK_SL", false, true, false);
         return;
      }
      if(bid >= g_states[idx].TakeProfit)
      {
         CloseVirtualTrade(idx, g_states[idx].TakeProfit, "TICK_TP", true, false, false);
         return;
      }
   }
   else
   {
      if(ask >= g_states[idx].StopLoss)
      {
         CloseVirtualTrade(idx, g_states[idx].StopLoss, "TICK_SL", false, true, false);
         return;
      }
      if(ask <= g_states[idx].TakeProfit)
      {
         CloseVirtualTrade(idx, g_states[idx].TakeProfit, "TICK_TP", true, false, false);
         return;
      }
   }
}

void ProcessOpenTradeTick(int idx)
{
   if(!g_states[idx].InTrade) return;

   datetime lastClosedBarTime = GetTimeBar(1);
   if(lastClosedBarTime > 0 && lastClosedBarTime != g_states[idx].LastProcessedClosedBarTime)
   {
      g_states[idx].LastProcessedClosedBarTime = lastClosedBarTime;
      g_states[idx].HoldingBars++;
      UpdateEarlyTradeStatsOnBar(idx, 1);
   }

   CheckTradeHitNow(idx);
   if(!g_states[idx].InTrade) return;
   UpdateFloatingDrawdownState(idx);

   if(CheckEarlyBadExit(idx))
   {
      double px = (g_states[idx].Direction == 1 ? GetBid() : GetAsk());
      CloseVirtualTrade(idx, px, "EarlyExit_SL_Like", false, true, true);
      return;
   }

   if(CheckEarlyGoodExit(idx))
   {
      double px = (g_states[idx].Direction == 1 ? GetBid() : GetAsk());
      CloseVirtualTrade(idx, px, "EarlyExit_TP_Like", true, false, true);
      return;
   }

   if(g_scenarios[idx].MaxHoldingBars > 0 &&
      g_states[idx].HoldingBars >= g_scenarios[idx].MaxHoldingBars)
   {
      double px = (g_states[idx].Direction == 1 ? GetBid() : GetAsk());
      CloseVirtualTrade(idx, px, "TimeExit", false, false, true);
      return;
   }
}


bool DetectInitialSweep(int idx, double rangeHigh, double rangeLow, double upperZoneLow, double lowerZoneHigh, int &dirOut)
{
   double sweepMin = g_scenarios[idx].SweepMinPips * PipPoint();

   bool sellSweep = false;
   bool buySweep = false;

   if(g_scenarios[idx].RequireStrictSellSweep)
   {
      sellSweep = (GetHigh(1) > rangeHigh + MathMax(sweepMin, g_scenarios[idx].SellSweepBufferPips * PipPoint())) &&
                  (GetClose(1) < rangeHigh);
   }
   else
   {
      sellSweep = (GetHigh(1) >= upperZoneLow) && (GetClose(1) < upperZoneLow);
   }

   if(g_scenarios[idx].RequireStrictBuySweep)
   {
      buySweep = (GetLow(1) < rangeLow - MathMax(sweepMin, g_scenarios[idx].BuySweepBufferPips * PipPoint())) &&
                 (GetClose(1) > rangeLow);
   }
   else
   {
      buySweep = (GetLow(1) <= lowerZoneHigh) && (GetClose(1) > lowerZoneHigh);
   }

   if(buySweep)
   {
      dirOut = 1;
      return true;
   }
   if(sellSweep)
   {
      dirOut = -1;
      return true;
   }
   return false;
}

bool ConfirmMSS(int idx)
{
   int dir = g_states[idx].SetupDirection;
   double breakBuf = g_scenarios[idx].BreakBufferPips * PipPoint();

   if(dir == -1)
   {
      if(GetClose(1) < g_states[idx].MSSLevel - breakBuf)
      {
         double disp = g_states[idx].MSSLevel - GetClose(1);
         double dispPips = disp / PipPoint();
         if(dispPips < g_scenarios[idx].MinDisplacementPips)
            return false;

         double rng = CandleRange(1);
         if(rng <= 0.0) return false;
         double body = BodySize(1);
         if(body < 0.4 * rng) return false;
         if(GetClose(1) > GetLow(1) + 0.25 * rng) return false;

         return true;
      }
   }
   else if(dir == 1)
   {
      if(GetClose(1) > g_states[idx].MSSLevel + breakBuf)
      {
         double disp = GetClose(1) - g_states[idx].MSSLevel;
         double dispPips = disp / PipPoint();
         if(dispPips < g_scenarios[idx].MinDisplacementPips)
            return false;

         double rng = CandleRange(1);
         if(rng <= 0.0) return false;
         double body = BodySize(1);
         if(body < 0.4 * rng) return false;
         if(GetClose(1) < GetHigh(1) - 0.25 * rng) return false;

         return true;
      }
   }

   return false;
}

bool BuildEntryZoneAfterMSS(int idx)
{
   int dir = g_states[idx].SetupDirection;
   bool foundAny = false;

   double fvgTop=0.0, fvgBot=0.0;
   double obTop=0.0, obBot=0.0;
   bool hasFVG = false;
   bool hasOB = false;

   if(dir == -1)
   {
      if(g_scenarios[idx].UseFVG)
      {
         hasFVG = FindBearishFVG(1, g_scenarios[idx].FVGMinSizePips, fvgTop, fvgBot);
         if(hasFVG) g_states[idx].FVGFoundCount++;
      }

      if(g_scenarios[idx].UseOB)
      {
         hasOB = FindLastBullishOBBefore(2, 8, obTop, obBot);
         if(hasOB) g_states[idx].OBFoundCount++;
      }
   }
   else
   {
      if(g_scenarios[idx].UseFVG)
      {
         hasFVG = FindBullishFVG(1, g_scenarios[idx].FVGMinSizePips, fvgTop, fvgBot);
         if(hasFVG) g_states[idx].FVGFoundCount++;
      }

      if(g_scenarios[idx].UseOB)
      {
         hasOB = FindLastBearishOBBefore(2, 8, obTop, obBot);
         if(hasOB) g_states[idx].OBFoundCount++;
      }
   }

   if(g_scenarios[idx].UseFVG && hasFVG)
   {
      g_states[idx].ZoneTop = fvgTop;
      g_states[idx].ZoneBottom = fvgBot;
      g_states[idx].ZoneFromFVG = true;
      g_states[idx].ZoneFromOB = false;
      foundAny = true;
   }

   if(!foundAny && g_scenarios[idx].UseOB && hasOB)
   {
      g_states[idx].ZoneTop = obTop;
      g_states[idx].ZoneBottom = obBot;
      g_states[idx].ZoneFromFVG = false;
      g_states[idx].ZoneFromOB = true;
      foundAny = true;
   }

   if(!foundAny && !g_scenarios[idx].UseFVG && !g_scenarios[idx].UseOB)
   {
      if(dir == -1)
      {
         g_states[idx].ZoneTop = g_states[idx].RangeHigh;
         g_states[idx].ZoneBottom = g_states[idx].RangeMid;
      }
      else
      {
         g_states[idx].ZoneTop = g_states[idx].RangeMid;
         g_states[idx].ZoneBottom = g_states[idx].RangeLow;
      }
      foundAny = true;
   }

   if(foundAny)
   {
      if(NormalizeRetestEntryMode(g_scenarios[idx].RetestEntryMode) == "close")
         g_states[idx].PendingEntryPrice = 0.0;
      else
         g_states[idx].PendingEntryPrice = ComputeEntryPriceFromZone(idx);
   }

   return foundAny;
}

void ProcessSetupMachine(int idx)
{
   g_states[idx].BarsChecked++;

   if(g_states[idx].InTrade)
      return;

   if(!PassSpreadFilter(idx))
   {
      g_states[idx].SpreadRejected++;
      return;
   }

   if(g_states[idx].SetupStage == ST_IDLE)
   {
      double rangeHigh, rangeLow, mid, atr;
      if(!BuildRangeRRZ(g_scenarios[idx].LookbackBars, g_scenarios[idx].ATR_Period, rangeHigh, rangeLow, mid, atr))
         return;

      double rangePips = (rangeHigh - rangeLow) / PipPoint();
      if(rangePips < g_scenarios[idx].MinRangePips)
         return;

      g_states[idx].RangeFoundCount++;

      double zoneW = g_scenarios[idx].ZoneATR_Mult * atr;
      if(zoneW <= 0) return;

      double upperZoneLow = rangeHigh - zoneW;
      double lowerZoneHigh = rangeLow + zoneW;

      int dir = 0;
      
      if(g_scenarios[idx].UseInitialSweep)
      {
         if(!DetectInitialSweep(idx, rangeHigh, rangeLow, upperZoneLow, lowerZoneHigh, dir))
            return;
      }
      else
      {
         
         if(GetClose(1) <= mid)
            dir = 1;   
         else
            dir = -1;  
      }


      g_states[idx].SweepFoundCount++;

      g_states[idx].SetupStage = ST_SWEEPED;
      g_states[idx].SetupDirection = dir;
      g_states[idx].SetupStartTime = GetTimeBar(1);
      g_states[idx].SetupStartBarShift = 1;
      g_states[idx].SweepBarShift = 1;
      g_states[idx].SweepHigh = GetHigh(1);
      g_states[idx].SweepLow = GetLow(1);
      g_states[idx].RangeHigh = rangeHigh;
      g_states[idx].RangeLow = rangeLow;
      g_states[idx].RangeMid = mid;
      g_states[idx].RangeATR = atr;
      g_states[idx].SetupBarsAlive = 0;

      double mssLevel = 0.0;
      int foundShift = -1;

      if(dir == -1)
      {
         if(!FindRecentSwingLowBefore(2 + g_scenarios[idx].SwingStrength,
                                      g_scenarios[idx].MSSLookbackBars,
                                      g_scenarios[idx].SwingStrength,
                                      mssLevel,
                                      foundShift))
         {
            ResetSetup(idx);
            return;
         }
      }
      else
      {
         if(!FindRecentSwingHighBefore(2 + g_scenarios[idx].SwingStrength,
                                       g_scenarios[idx].MSSLookbackBars,
                                       g_scenarios[idx].SwingStrength,
                                       mssLevel,
                                       foundShift))
         {
            ResetSetup(idx);
            return;
         }
      }

      g_states[idx].MSSLevel = mssLevel;
      g_states[idx].MSSBarShift = foundShift;

      LogScenarioEvent(idx, "SETUP_SWEEP", (dir==1?"BUY":"SELL"),
                 0, 0, 0, 0, 0, 0,
                 "Sweep detected",
                 1);

      return;
   }

   if(g_states[idx].SetupStage == ST_SWEEPED)
   {
      g_states[idx].SetupBarsAlive++;

      if(g_states[idx].SetupBarsAlive > g_scenarios[idx].PendingExpiryBars)
      {
         g_states[idx].ExpiredSetupCount++;
         ResetSetup(idx);
         return;
      }

      if(!g_scenarios[idx].UseSweepMSS)
      {
         if(!BuildEntryZoneAfterMSS(idx))
         {
            ResetSetup(idx);
            return;
         }

         g_states[idx].SetupStage = ST_WAIT_RETEST;
         LogScenarioEvent(idx,
                 "SETUP_MSS",
                 (g_states[idx].SetupDirection==1?"BUY":"SELL"),
                 0, 0, 0, 0, 0, 0,
                 "MSS confirmed, pending order active",
                 1);

         return;
      }

      if(ConfirmMSS(idx))
      {
         g_states[idx].MSSFoundCount++;
         g_states[idx].DisplacementOKCount++;

         if(!BuildEntryZoneAfterMSS(idx))
         {
            ResetSetup(idx);
            return;
         }

         g_states[idx].SetupStage = ST_WAIT_RETEST;
         LogScenarioEvent(idx,
                          "SETUP_MSS",
                          (g_states[idx].SetupDirection==1?"BUY":"SELL"),
                          0, 0, 0, 0, 0, 0,
                          "MSS confirmed, pending order active");
      }

      return;
   }

   if(g_states[idx].SetupStage == ST_WAIT_RETEST)
   {
      g_states[idx].SetupBarsAlive++;

      if(g_states[idx].SetupBarsAlive > g_scenarios[idx].PendingExpiryBars)
      {
         g_states[idx].ExpiredSetupCount++;
         ResetSetup(idx);
         return;
      }

      if(NormalizeRetestEntryMode(g_scenarios[idx].RetestEntryMode) != "close")
      {
         if(g_states[idx].PendingEntryPrice <= 0.0)
            g_states[idx].PendingEntryPrice = ComputeEntryPriceFromZone(idx);
      }

      return;
   }
}

bool EntryExecutablePriceInsideZoneNow(int idx)
{
   double top = MathMax(g_states[idx].ZoneTop, g_states[idx].ZoneBottom);
   double bot = MathMin(g_states[idx].ZoneTop, g_states[idx].ZoneBottom);
   double tol = g_scenarios[idx].RetestTolerancePips * PipPoint();

   double bid = GetBid();
   double ask = GetAsk();

   if(bid <= 0.0 || ask <= 0.0)
      return false;

   int dir = g_states[idx].SetupDirection;

   double executable = 0.0;

   if(dir == 1)
      executable = ask;
   else if(dir == -1)
      executable = bid;
   else
      return false;

   return (executable >= bot - tol && executable <= top + tol);
}



void ProcessPendingEntryTick(int idx)
{
   if(g_states[idx].InTrade) return;
   if(g_states[idx].SetupStage != ST_WAIT_RETEST) return;

   if(!PassSpreadFilter(idx)) return;
   if(!PassCooldown(idx)) return;
   if(!PassMaxTradesPerDay(idx, TimeCurrent())) return;

   string mode = NormalizeRetestEntryMode(g_scenarios[idx].RetestEntryMode);

   double entry = 0.0;
   double requestedEntry = 0.0;

   double bid = GetBid();
   double ask = GetAsk();

   if(bid <= 0.0 || ask <= 0.0) return;
   if(mode == "close") return;

   requestedEntry = g_states[idx].PendingEntryPrice;
   if(requestedEntry <= 0.0)
      requestedEntry = ComputeEntryPriceFromZone(idx);

   if(requestedEntry <= 0.0) return;

   if(!EntryPriceTouchedNow(idx, requestedEntry))
      return;


   if(ShouldSkipTradeByFilter(0))
   {
      LogScenarioEvent(idx, "FILTER_SKIP", (g_states[idx].SetupDirection==1?"BUY":"SELL"),
                       0,0,0,0,0,0,"PreEntryFilter_BTR_Comp",0);
      ResetSetup(idx);
      return;
   }

   entry = GetPendingFillPrice(idx, requestedEntry);
   if(entry <= 0.0) return;

   g_states[idx].RetestFoundCount++;

   double sl = 0.0, tp = 0.0;
   if(!CalcSLTP(idx, g_states[idx].SetupDirection, entry, sl, tp))
   {
      g_states[idx].InvalidSLTPCount++;
      ResetSetup(idx);
      return;
   }

   string entryReason = "RRZ_" + mode + "_" + (g_states[idx].SetupDirection == 1 ? "BUY" : "SELL");
   OpenVirtualTrade_RRZ(idx, g_states[idx].SetupDirection, entry, sl, tp, entryReason, 0);
}



void ProcessPendingEntryOnNewBar_CloseMode(int idx)
{
   if(g_states[idx].InTrade) return;
   if(g_states[idx].SetupStage != ST_WAIT_RETEST) return;

   if(!PassSpreadFilter(idx)) return;
   if(!PassCooldown(idx)) return;
   if(!PassMaxTradesPerDay(idx, GetTimeBar(1))) return;

   if(NormalizeRetestEntryMode(g_scenarios[idx].RetestEntryMode) != "close")
      return;

   double close1 = GetClose(1);
   if(!EntryPriceInsideZone(idx, close1))
      return;


   if(ShouldSkipTradeByFilter(0))
   {
      LogScenarioEvent(idx, "FILTER_SKIP", (g_states[idx].SetupDirection==1?"BUY":"SELL"),
                       0,0,0,0,0,0,"PreEntryFilter_BTR_Comp_Close",1);
      ResetSetup(idx);
      return;
   }

   double entry = NormalizePrice(GetOpen(0));
   double sl=0, tp=0;

   g_states[idx].RetestFoundCount++;

   if(!CalcSLTP(idx, g_states[idx].SetupDirection, entry, sl, tp))
   {
      g_states[idx].InvalidSLTPCount++;
      ResetSetup(idx);
      return;
   }

   string entryReason = "RRZ_close_" + (g_states[idx].SetupDirection == 1 ? "BUY" : "SELL");
   OpenVirtualTrade_RRZ(idx, g_states[idx].SetupDirection, entry, sl, tp, entryReason, 0);
}


void ProcessScenariosOnTick()
{
   for(int i=0; i<g_scenarioCount; i++)
   {
      if(!g_scenarios[i].Enabled) continue;
      ProcessOpenTradeTick(i);
   }

   for(int i=0; i<g_scenarioCount; i++)
   {
      if(!g_scenarios[i].Enabled) continue;
      if(OneSignalPerBar && g_states[i].LastEntryBarTime == GetTimeBar(0)) continue;
      ProcessPendingEntryTick(i);
   }
}
void EvaluateScenariosOnNewBar()
{
   for(int i=0; i<g_scenarioCount; i++)
   {
      if(!g_scenarios[i].Enabled)
         continue;

      LogBarState(i, "BAR_CLOSE", 1, "Closed candle snapshot");

      if(OneSignalPerBar && g_states[i].LastEntryBarTime == GetTimeBar(0))
         continue;

      string mode = NormalizeRetestEntryMode(g_scenarios[i].RetestEntryMode);

      // close-mode entry فقط روی bar جدید
      if(mode == "close")
      {
         ProcessPendingEntryOnNewBar_CloseMode(i);

         if(g_states[i].InTrade)
            continue;
      }

      ProcessSetupMachine(i);
   }
}



void WriteSummary()
{
   int h = FileOpen("RRZ_Research_Summary.txt", FileFlagsWriteCSV());
   if(h == INVALID_HANDLE)
   {
      Print("Failed to write summary: ", "RRZ_Research_Summary.txt", " error=", GetLastError());
      return;
   }

   string header =
      "Scenario,Enabled,"
      "UseSpread,MaxSpreadPips,"
      "CooldownBars,MaxTradesPerDay,"
      "MaxHoldingBars,StopBufferPips,"
      "LookbackBars,ATR_Period,ZoneATR_Mult,MinRangePips,"
      "UseNextBarOpenEntry,RequireStrictSellSweep,RequireStrictBuySweep,"
      "BuyTargetMode,SellTargetMode,BuyRR,SellRR,SellSweepBufferPips,BuySweepBufferPips,"
      "SwingStrength,UseSweepMSS,MSSLookbackBars,BreakBufferPips,RetestTolerancePips,SweepMinPips,MinDisplacementPips,FVGMinSizePips,UseFVG,UseOB,RetestEntryMode,PendingExpiryBars,SLMode,TPMode,"
      "UseEarlyExitModel,EarlyExitBars,EarlyExitFastEMA,EarlyExitSlowEMA,"
      "Good_MaxAdvEarly_Pips,Good_MinFavEarly_Pips,Good_MinEMAspreadDelta_Pips,Good_FirstMove,"
      "Bad_MinAdvEarly_Pips,Bad_MaxFavEarly_Pips,Bad_MaxEMAspreadDelta_Pips,Bad_FirstMove,"
      "Trades,Wins,Losses,TimeExits,WinRatePct,NetProfitPips,GrossProfitPips,"
      "GrossLossPips,AvgR,BestTradePips,WorstTradePips,"
      "EquityCurvePips,PeakEquityPips,MaxDrawdownSeenPips,DailyNetPips,"
      "BarsChecked,SpreadRejected,RangeFound,SweepFound,MSSFound,DisplacementOK,FVGFound,OBFound,RetestFound,OrdersPlaced,InvalidSLTP,ExpiredSetup,"
      "CurrentDDPips,CurrentDDPct,LogFile";

   FileWriteString(h, header + "\r\n");

   for(int i=0; i<g_scenarioCount; i++)
   {
      double winRate = 0.0;
      double avgR    = 0.0;

      if(g_states[i].TotalTrades > 0)
      {
         winRate = 100.0 * (double)g_states[i].Wins / (double)g_states[i].TotalTrades;
         avgR    = g_states[i].SumR / (double)g_states[i].TotalTrades;
      }

      double bestTrade  = (g_states[i].BestTrade  == -DBL_MAX ? 0.0 : g_states[i].BestTrade);
      double worstTrade = (g_states[i].WorstTrade ==  DBL_MAX ? 0.0 : g_states[i].WorstTrade);

      string row = "";
      row += g_scenarios[i].Name + ",";
      row += BoolToStr(g_scenarios[i].Enabled) + ",";
      row += BoolToStr(g_scenarios[i].UseSpreadFilter) + ",";
      row += DoubleToString(g_scenarios[i].MaxSpreadPips,2) + ",";
      row += IntegerToString(g_scenarios[i].CooldownBars) + ",";
      row += IntegerToString(g_scenarios[i].MaxTradesPerDay) + ",";
      row += IntegerToString(g_scenarios[i].MaxHoldingBars) + ",";
      row += DoubleToString(g_scenarios[i].StopBufferPips,2) + ",";
      row += IntegerToString(g_scenarios[i].LookbackBars) + ",";
      row += IntegerToString(g_scenarios[i].ATR_Period) + ",";
      row += DoubleToString(g_scenarios[i].ZoneATR_Mult,2) + ",";
      row += DoubleToString(g_scenarios[i].MinRangePips,2) + ",";
      row += BoolToStr(g_scenarios[i].UseNextBarOpenEntry) + ",";
      row += BoolToStr(g_scenarios[i].RequireStrictSellSweep) + ",";
      row += BoolToStr(g_scenarios[i].RequireStrictBuySweep) + ",";
      row += g_scenarios[i].BuyTargetMode + ",";
      row += g_scenarios[i].SellTargetMode + ",";
      row += DoubleToString(g_scenarios[i].Buy_RR_Multiple,2) + ",";
      row += DoubleToString(g_scenarios[i].Sell_RR_Multiple,2) + ",";
      row += DoubleToString(g_scenarios[i].SellSweepBufferPips,2) + ",";
      row += DoubleToString(g_scenarios[i].BuySweepBufferPips,2) + ",";
      row += IntegerToString(g_scenarios[i].SwingStrength) + ",";
      row += BoolToStr(g_scenarios[i].UseSweepMSS) + ",";
      row += IntegerToString(g_scenarios[i].MSSLookbackBars) + ",";
      row += DoubleToString(g_scenarios[i].BreakBufferPips,2) + ",";
      row += DoubleToString(g_scenarios[i].RetestTolerancePips,2) + ",";
      row += DoubleToString(g_scenarios[i].SweepMinPips,2) + ",";
      row += DoubleToString(g_scenarios[i].MinDisplacementPips,2) + ",";
      row += DoubleToString(g_scenarios[i].FVGMinSizePips,2) + ",";
      row += BoolToStr(g_scenarios[i].UseFVG) + ",";
      row += BoolToStr(g_scenarios[i].UseOB) + ",";
      row += g_scenarios[i].RetestEntryMode + ",";
      row += IntegerToString(g_scenarios[i].PendingExpiryBars) + ",";
      row += g_scenarios[i].SLMode + ",";
      row += g_scenarios[i].TPMode + ",";
      row += BoolToStr(g_scenarios[i].UseEarlyExitModel) + ",";
      row += IntegerToString(g_scenarios[i].EarlyExitBars) + ",";
      row += IntegerToString(g_scenarios[i].EarlyExitFastEMA) + ",";
      row += IntegerToString(g_scenarios[i].EarlyExitSlowEMA) + ",";
      row += DoubleToString(g_scenarios[i].Good_MaxAdvEarly_Pips,2) + ",";
      row += DoubleToString(g_scenarios[i].Good_MinFavEarly_Pips,2) + ",";
      row += DoubleToString(g_scenarios[i].Good_MinEMAspreadDelta_Pips,2) + ",";
      row += g_scenarios[i].Good_FirstMove + ",";
      row += DoubleToString(g_scenarios[i].Bad_MinAdvEarly_Pips,2) + ",";
      row += DoubleToString(g_scenarios[i].Bad_MaxFavEarly_Pips,2) + ",";
      row += DoubleToString(g_scenarios[i].Bad_MaxEMAspreadDelta_Pips,2) + ",";
      row += g_scenarios[i].Bad_FirstMove + ",";
      row += IntegerToString(g_states[i].TotalTrades) + ",";
      row += IntegerToString(g_states[i].Wins) + ",";
      row += IntegerToString(g_states[i].Losses) + ",";
      row += IntegerToString(g_states[i].TimeExits) + ",";
      row += DoubleToString(winRate,2) + ",";
      row += DoubleToString(g_states[i].NetProfit,2) + ",";
      row += DoubleToString(g_states[i].GrossProfit,2) + ",";
      row += DoubleToString(g_states[i].GrossLoss,2) + ",";
      row += DoubleToString(avgR,2) + ",";
      row += DoubleToString(bestTrade,2) + ",";
      row += DoubleToString(worstTrade,2) + ",";
      row += DoubleToString(g_states[i].EquityCurvePips,2) + ",";
      row += DoubleToString(g_states[i].PeakEquityPips,2) + ",";
      row += DoubleToString(g_states[i].MaxDrawdownSeenPips,2) + ",";
      row += DoubleToString(g_states[i].DailyNetPips,2) + ",";
      row += IntegerToString(g_states[i].BarsChecked) + ",";
      row += IntegerToString(g_states[i].SpreadRejected) + ",";
      row += IntegerToString(g_states[i].RangeFoundCount) + ",";
      row += IntegerToString(g_states[i].SweepFoundCount) + ",";
      row += IntegerToString(g_states[i].MSSFoundCount) + ",";
      row += IntegerToString(g_states[i].DisplacementOKCount) + ",";
      row += IntegerToString(g_states[i].FVGFoundCount) + ",";
      row += IntegerToString(g_states[i].OBFoundCount) + ",";
      row += IntegerToString(g_states[i].RetestFoundCount) + ",";
      row += IntegerToString(g_states[i].OrdersPlacedCount) + ",";
      row += IntegerToString(g_states[i].InvalidSLTPCount) + ",";
      row += IntegerToString(g_states[i].ExpiredSetupCount) + ",";
      row += DoubleToString(GetCurrentDrawdownPips(i),2) + ",";
      row += DoubleToString(GetDrawdownPercent(i),2) + ",";

      row += g_states[i].LogFileName;

      FileWriteString(h, row + "\r\n");
   }

   FileClose(h);
   PrintV("Summary written: " + "RRZ_Research_Summary.txt");
}

int OnInit()
{
   PrintV("Initializing RRZ...");

   if(!LoadScenarios())
   {
      Print("No scenarios loaded. Check file: ", ParamFileName);
      return(INIT_FAILED);
   }

   g_lastBarTime = 0;
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(g_rates_count > 10)
   {
      for(int i=0; i<g_scenarioCount; i++)
      {
         if(g_states[i].InTrade)
         {
            double px = (g_states[i].Direction == 1 ? GetBid() : GetAsk());
            if(px <= 0.0) px = GetClose(1);
            CloseVirtualTrade(i, px, "ForcedClose_OnDeinit", false, false, true);
         }
      }
   }

   WriteSummary();
   PrintV("Deinitialized.");
}

void OnTick()
{
   int maxLookback = 0, maxATR = 0, maxMSS = 0, maxEarlySlow = 0;
   for(int i=0;i<g_scenarioCount;i++)
   {
      if(g_scenarios[i].LookbackBars > maxLookback) maxLookback = g_scenarios[i].LookbackBars;
      if(g_scenarios[i].ATR_Period   > maxATR)      maxATR      = g_scenarios[i].ATR_Period;
      if(g_scenarios[i].MSSLookbackBars > maxMSS)   maxMSS      = g_scenarios[i].MSSLookbackBars;
      if(g_scenarios[i].EarlyExitSlowEMA > maxEarlySlow) maxEarlySlow = g_scenarios[i].EarlyExitSlowEMA;
   }

   int needBars = MathMax(maxATR + maxLookback + maxMSS + maxEarlySlow + 100, 400);
   if(!RefreshRatesCache(needBars)) return;

   if(BarsCount() < MathMax(maxATR + maxLookback + maxMSS + maxEarlySlow + 30, 250))
      return;

   datetime currentBarTime = GetTimeBar(0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      EvaluateScenariosOnNewBar();
   }

   ProcessScenariosOnTick();

} 


