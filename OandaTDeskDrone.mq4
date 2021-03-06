//+------------------------------------------------------------------+
//|                                                   OandaTDesk.mq4 |
//|                                                   Lonnie Coffman |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Lonnie Coffman"
#property link      "https://github.com/LonnieCoffman"
#property version   "1.01"
#property strict

#define version "Version 1.01"

#include <TDeskSignals.mqh>
/*
   Changelog:
   12/23/18 - 1.01
      - Fixed an issue with manual trade management
      - Fixed an issue with manual/auto selection not being remembered between reloads
      - Fixed an issue with the AutoTrade button not pausing trading activity

   NOTES:
   1. Rollover not needed since financing charged and paid continuously, second-by-second.
   2. AutoTrading switch enables/disables trading
   3. Checks to see if python script is running
   4. Checks to see if TDesk is running
   5. Displays messages about trading times and days of week
   6. Notification System:
      a. send Warning Messages
      b. send trade open/close messages
      c. send margin warnings
      d. send shirt protection warnings
   7. Margin closeout
      a. option to close all positions when one account is unacceptable
      b. alternatively close just offending account
      c. or just send warning if one account is in danger to reconcile
   8. Backup/Restore data to file
   9. AutoTrading button either disables all trade management or prevents opening of new trades based on expert option
   10. If using Hedging make sure to choose close on opposite signal or hedge will not close
   11. MaxPairsAllowedToTrade setting of 0 disables check
   12. Auto / Manual trading
   13. Fixed Friday Closure
   
   USAGE:
   1. Reconcile accounts on weekend
   2. Restart python script after reconciliation
   
   TODO:
   1. Implement Done for the week
   2. Implement Basket Take Profits
   3. Implement Recovery
   4. Implement Counter-trend scalping
   5. Implement Dollop

*/

enum DaysOfWeek
{
   Sunday = 0,
   Monday = 1,
   Tuesday = 2,
   Wednesday = 3,
   Thursday = 4,
   Friday = 5,
   Saturday = 6
};

//Thomas again
enum SLTPStrategies 
{
   FixedPips,
   PriceFractions,
   ATRPercent
};

enum LotCalc
{
   FixedLotSize, // Fixed Lot Size
   RiskBased,    // Risk Based
   MaxLotSize    // Max Lot Size
};

enum TickMode 
{
   EveryTick = 1,   // Every Tick
   AtNewCandle = 0  // At New Candle
};

enum AutoTrade
{
   PauseNewTrading = 0, // Pause Opening New Trades
   PauseAllTrading = 1  // Pause All Trading Activity
};

extern string           externDash0 = "";                      // -------- DASHBOARD SETTINGS --------
int      EventTimerIntervalSeconds = 1;                        // To remain responsive, the dashboard needs to update every second.
extern TickMode         EveryTickMode = true;                  // When to allow new trades
extern ENUM_TIMEFRAMES  EveryTickTimeFrame = PERIOD_M15;       // -- "At New Candle" timeframe
extern double           ShortPandLOffset = 0.0;                // Offset to Adjust Short P/L Reported by Oanda
extern double           LongPandLOffset = 0.0;                 // Offset to Adjust Long P/L Reported by Oanda
extern AutoTrade        AutoTradingAll = 0;                    // When AutoTrading button is pressed:

extern string           spacer1 = "";                          // .
extern string           externNotify1="";                      // -------- NOTIFICATIONS ---------
extern string           externNotify2="";                      // -- note: Notifications must be set up in MT4
extern bool             NotifyWarning = true;                  // Notify of Warning Messages?
extern bool             NotifyTradeOpen = true;                // Notify when Opening Trades?
extern bool             NotifyTradeClose = true;               // Notify when Closing Trades?
extern int              NotifyStart = 5;                       // Hour Notification Start (local time)
extern int              NotifyEnd = 20;                        // Hour Notification End (local time)

extern string           spacer2 = "";                          // .
extern string           externSignal0 = "";                    // -------- SIGNAL SETTINGS --------
extern int              TDeskSignalIntervalSeconds = 5;        // Seconds between TDesk signal checks
extern int              MaxSignalAgeMinutes = 60;              // Minutes to Consider Signal Valid

extern string           spacer3 = "";                          // .
extern string           externLotCalc0 = "";                   // -------- LOT CALCULATIONS --------
extern LotCalc          LotCalculation = MaxLotSize;           // Lot Calculation Method
extern int              SetLotSize = 1000;                     // -- Fixed: Lot Size (1000 = 0.01)
extern int              AveragePipLoss = 20;                   // -- Risk: Avg Loss in Pips
extern double           RiskPercent = 2;                       // -- Risk: Percent Risk per Trade
extern int              PercentReserveMargin = 20;             // -- Risk/Max: % Acct Balance Not used in Calculations
extern int              NumberOfTradesPerPair = 2;             // -- Risk/Max: Max Num Trades/Pair for Calculations
extern bool             UseIncrementalLotSizing = false;       // Increment the Size of Each Trade?
extern int              LotIncrement = 1;                      // -- Increment Amount

extern string           Spacer4 = "";                          // .
extern string           externTradeEntry = "";                 // -------- TRADE ENTRIES --------
extern int              MaxTradesAllowed = 5;                  // Max Trades Allowed Per Pair
extern int              MinDistanceBetweenTradesPips = 30;     // Min Pip Distance Between Trades
extern double           MinMarginLevelToTrade = 50;            // Min Margin Level to Trade (0 = disable)
extern int              MaxPairsAllowedToTrade = 0;            // Max Number of Pairs to Trade (0 = disable)

extern string           Spacer5 = "";                          // .
extern string           externTradeExit = "";                  // -------- TRADE EXITS --------
extern bool             CloseOnOppositeSignal = true;          // Close Trade on Opposite Signal?
extern bool             CloseTradesOnFlatSignal = false;       // Close Trade on Flat Signal?
extern bool             UseMarginLevelClosure = true;          // Use Margin Level Closure?
extern double           CloseBelowMarginLevel = 25;            // -- Close Below Margin Level 
extern bool             TreatAccountsAsCombined = true;        // -- Use Combined Margin from Both Accounts?
extern double           AcceptableProfitCash=50;               // -- Profit Close Level (0 = disable)
extern int              AcceptableProfitPips=0;                // -- Pip Close Level (0 = disable)

extern string           Spacer6 = "";                          // .
extern string           externHedging = "";                    // -------- HEDGING --------
extern bool             HedgeOnFlatSignal=true;                // Hedge on Flat Signal
extern bool             HedgeOnOppositeDirectionSignal=false;  // Hedge on Opposite Signal
extern bool             CloseHedgeOnOppositeSignal=true;       // Close Hedge on Opposite Signal
extern bool             MaintainHedgeOnConfirmedSignal=true;   // On Signal Reversal Keep Profitable Hedge
extern int              TimeBetweenHedgeTrades=300;            // Min Seconds to Reopen Hedge Trade
extern double           PercentageToHedge=100;                 // Percentage of Trade Size to Hedge

extern string           Spacer7 = "";                          // .
extern string           externTradeHours = "";                 // -------- TRADING HOURS --------
extern string           tr1= "tradingHours is a comma delimited list";
extern string           tr1a="of start and stop times.";
extern string           tr2="Prefix start with '+', stop with '-'";
extern string           tr2a="Use 24H format, local time.";
extern string           tr3="Example: '+07.00,-10.30,+14.15,-16.00'";
extern string           tr3a="Do not leave spaces";
extern string           tr4="Blank input means 24 hour trading.";
extern string           tradingHours="";                       // Hours to Allow Trading

extern string           Spacer8 = "";                          // .
extern string           externTradeDays = "";                  // -------- TRADING DAYS --------
extern string           externTradeDays1 = "";                 // -- note: Set >23 to Disable
extern string           externTradeDays2 = "";                 // -- note: Use 24 Hour Local Time
extern int              FridayStopTradingHour = 14;            // Friday Stop Trading Hour
extern int              FridayCloseAllHour=25;                 // Friday Close All Trades Hour 
extern bool             TradeSundayCandle = true;              // Trade on Sunday?
extern int              MondayStartHour = 8;                   // Monday Start Trading Hour                        
extern bool             TradeThursdayCandle = true;            // Trade on Thursday?

int              SaturdayStopTradingHour=25;                   // Saturday Stop Trading Hour     (DISABLED: Not currently needed)
int              SaturdayCloseAllHour=25;                      // Saturday Close All Trades Hour (DISABLED: Not currently needed)

extern string           Spacer9 = "";                          // .
extern string           externTradeFilter = "";                // -------- TRADING FILTERS --------
extern bool             UseZeljko = false;                     // Balancing: Use Zeljko Filter?
extern bool             OnlyTradeCurrencyTwice = false;        // Balancing: Only Trade Currency Twice
extern bool             CadPairsPositiveOnly = false;          // Swap: CAD Positive Only
extern bool             AudPairsPositiveOnly = false;          // Swap: AUD Positive Only
extern bool             NzdPairsPositiveOnly = false;          // Swap: NZD Positive Only
extern bool             OnlyTradePositiveSwap = false;         // Swap: Only Trade Positive Swap
extern double        MaximumAcceptableNegativeSwap = -1000000; // Swap: Max Negative Swap

extern string           Spacer10 = "";                         // .
extern string           externShirtProtection = "";            // -------- SHIRT PROTECTION --------
extern bool             UseShirtProtection = false;            // Use Shirt Protection?
extern double           MaxLoss = -150;                        // -- Maximum Allowable Loss

// TODO: Modify for hidden tp and sl
int              TakeProfitValue = 0;
int              StopLossValue = 0;
SLTPStrategies   SLTPCalcMode=ATRPercent;

////////////////////////////////////////////////////////////////////////////////////////
// graphics
string CloseLongButton ="\\Images\\CloseLongButton.bmp";
string CloseShortButton="\\Images\\CloseShortButton.bmp";
string CloseHedgeButton="\\Images\\CloseHedgeButton.bmp";
string CloseAllButton = "\\Images\\CloseAllButton.bmp";
string AutoButton =     "\\Images\\AutoButton.bmp";
string ManualButton =   "\\Images\\ManualButton.bmp";
string ChartButton =    "\\Images\\ShowChart.bmp";
string BuyButton =      "\\Images\\BuyButton.bmp";
string SellButton =     "\\Images\\SellButton.bmp";
string CloseButton =    "\\Images\\CloseButton.bmp";

////////////////////////////////////////////////////////////////////////////////////////
// dashboard messages
string LiveTradingDisabledMsg =  "THIS EXPERT HAS LIVE TRADING DISABLED!";
string PythonScriptMsg =         "PYTHON SCRIPT NOT RUNNING!";
string TDeskStoppedMsg =         "TDESK IS NOT RUNNING!";
string NoTradingAutoTrading =    "Not Looking for New Trades: AutoTrading disabled";
string NoTradingStopTrading =    "Not Looking for New Trades: Stop Trading Enabled in Settings";
string NoTradingThursday =       "Not Looking for New Trades: No New Trades on Thursday";
string NoTradingFriday =         "Not Looking for New Trades: No New Trades on Friday";
string NoTradingSaturday =       "Not Looking for New Trades: No New Trades on Saturday";
string NoTradingSunday =         "Not Looking for New Trades: No New Trades on Sunday";
string NoTradingFridayStop =     "Not Looking for New Trades: Trading Stops on Friday at ";
string NoTradingSaturdayStop =   "Not Looking for New Trades: Trading Stops on Saturday at ";
string NoTradingMondayStart =    "Not Looking for New Trades: Trading Does Not Resume Until ";
string NoTradingOutsideHours =   "Not Looking for New Trades: Outside Trading Hours of: ";
string NoTradingMaxPairs =       "Not Looking for New Trades: Max Pairs Limit Reached";
string FridayCloseAll =          "Friday Close Hour Hit: Closing all Trades";
string MarginLevelAll =          "Margin Level Hit: Closing all Trades";
string MarginLevelShort =        "Margin Level Hit: Closing all Short Trades";
string MarginLevelLong =         "Margin Level Hit: Closing all Long Trades";
string ShirtProtectionHit =      "Shirt Protection: All Trades Closed";
string WaitingMsg =              "Waiting for signals....";
bool   MessageFlash;

////////////////////////////////////////////////////////////////////////////////////////
// Notification Messages
string NotifyLiveTradingMsg =    "Live Trading is Disabled";
string NotifyPythonMsg =         "Python Script not Running";
string NotifyTDeskMsg =          "TDesk not Running";
string NotifyStopTradingMsg =    "Stop Trading Option Set";
string NotifyFridayCloseAll =    "Friday Closure: $";
string NotifyMarginAll =         "Margin Closure: All";
string NotifyMarginShort =       "Margin Closure: Short";
string NotifyMarginLong =        "Margin Closure: Long";
string NotifyShirtProtection =   "Shirt Protection Activated";

////////////////////////////////////////////////////////////////////////////////////////
// Filenames
string LockFilename =  "FXtrade\\bridge_lock";
string AliveFileName = "FXtrade\\alive_check";

////////////////////////////////////////////////////////////////////////////////////////
// Pair Struct
struct pairinf {
   string         Pair;
   string         FXtradeName;
   double         Spread;
   TDESKSPREADS   SpreadType;
   TDESKNEWS      News;
   TDESKSIGNALS   Signal;
   TDESKSIGNALS   OriginalSignal;
   long           ChartId;
   double         ADR;
   double         ADRPips;
   double         Profit;
   double         LongProfit;
   double         ShortProfit;
   double         ProfitPips;
   double         ShortProfitPips;
   double         LongProfitPips;
   string         TradeDirection;
   string         SignalChange;
   string         HedgedDirection;
   bool           Hedged;
   bool           BackupExists;
   bool           Managed;
   int            TradeCount;
   int            ShortTradeCount;
   int            LongTradeCount;
   int            OpenLotsize;
   int            ShortOpenLotsize;
   int            LongOpenLotsize;
   double         ShortAveragePrice;
   double         LongAveragePrice;
   double         AveragePrice;
   double         MinShortOrderPrice;
   double         MaxShortOrderPrice;
   double         MinLongOrderPrice;
   double         MaxLongOrderPrice;
   double         USMarginRequirement;
   int            HedgeTime;
   datetime       SignalTime;
   datetime       TickTime;
   datetime       TimeToStartTrading;
}; pairinf PairInfo[];

////////////////////////////////////////////////////////////////////////////////////////

double         MinimumDistanceBetweenTrades = 0;

bool           hedged=false;
bool           hedgeIsBuy=false, hedgeIsSell=false;
double         totalBuyLots=0, totalSellLots=0;
int            hedgeTradeTicket=0;

double         TradeTimeOn[];
double         TradeTimeOff[];
// trading hours variables
int            tradeHours[];
string         tradingHoursDisplay;//tradingHours is reduced to "" on initTradingHours, so this variable saves it for screen display.
bool           TradeTimeOk;
////////////////////////////////////////////////////////////////////////////////////////

bool           CanTradeThisPair;
////////////////////////////////////////////////////////////////////////////////////////

//Basic multi-pair stuff
double         ask=0, bid=0, spread=0;//Replaces Ask. Bid, Digits. factor replaces Point
int            digits;//Replaces Digits.
double         longSwap=0, shortSwap=0;

//Calculating the factor needed to turn pip values into their correct points value to accommodate different Digit size.
double         factor;//For pips/points stuff.

//Trade signals
bool           BuySignal= false, SellSignal=false, TradeLong=false, TradeShort=false;
bool           BuyCloseSignal=false, SellCloseSignal=false;

double ShortAccountBal,ShortAvailMargin,ShortUsedMargin,ShortMarginLevel,ShortAccountEquity,ShortRealizedPL,ShortAccountProfit,ShortAccountPips;
int ShortNumOpenTrades;

double LongAccountBal,LongAvailMargin,LongUsedMargin,LongMarginLevel,LongAccountEquity,LongRealizedPL,LongAccountProfit,LongAccountPips;
int LongNumOpenTrades;

double AccountBal,AvailMargin,UsedMargin,MarginLevel,AcctEquity,RealizedPL,CurrentProfit,CurrentPips;
int NumOpenTrades;

int TDeskSignalIntervalCount;

int AliveTimer,AliveSeconds;
bool EaWarningSent,PythonWarningSent,TDeskWarningSent,StopWarningSent;

int messageLotSize; // placeholder to store lot size when closing trades
bool NotifyAllowed;
bool AdvisorReady;

////////////////////////////////////////////////////////////////////////////////////////
// Dashboard Variables
int   x_axis = 30;
int   y_axis = 130;
int   TextSize = 8;
int   HeaderTextSize = 9;
int   LabelTextSize = 7;
int   DashWidth = 1020;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
   // Remove leftover objects and set colors
   CleanChart();
   
   //Give TDesk time to start up and set initial data
   //for (int Count = 10; Count >=0; Count--){
   //   Comment("Giving TDesk some time in case it has not finished initializing....."+IntegerToString(Count));
   //   Sleep(1000);
   //}
   Comment("");
   
   //create timer
   SecureSetTimer(EventTimerIntervalSeconds); //Explanation at the top of the function
   TDeskSignalIntervalCount = 0;
   
   // warning messages and notifications
   AliveTimer = 0;
   AliveSeconds = 0;
   EaWarningSent      = false;
   PythonWarningSent  = false;
   TDeskWarningSent   = false;

   MinimumDistanceBetweenTrades = MinDistanceBetweenTradesPips;

   //Set up the trading hours
   tradingHoursDisplay=tradingHours;//For display
   initTradingHours();//Sets up the trading hours array

   //MaxLoss idiot proofing
   if (UseShirtProtection)
      if (MaxLoss > 0)
         MaxLoss*= -1;

   //FridayCloseAll idiot proofing - if we close all trades on Friday we obviously do not want to continue trading afterwards
   if (FridayStopTradingHour > FridayCloseAllHour) FridayStopTradingHour = FridayCloseAllHour;

   ReadTDeskSignals();

   ArrayResize(PairInfo,ArraySize(TDeskSymbols));
   for(int i=0;i<ArraySize(TDeskSymbols);i++){
      PairInfo[i].Pair               = TDeskSymbols[i];
      PairInfo[i].FXtradeName        = StringSubstr(TDeskSymbols[i],0,3)+"_"+StringSubstr(TDeskSymbols[i],3,3);
      // assign chartID to each pair
      long chartID=ChartFirst();
      while(chartID >= 0){
         if(ChartSymbol(chartID) == TDeskSymbols[i]){
            PairInfo[i].ChartId      = chartID; 
            break;
         }
         chartID = ChartNext(chartID);
      }
      PairInfo[i].SignalTime         = TDeskTimes[i];
      PairInfo[i].TickTime           = iTime(PairInfo[i].Pair, EveryTickTimeFrame, 0);
      PairInfo[i].HedgeTime          = int((GetTickCount() * 0.001) - TimeBetweenHedgeTrades);
      PairInfo[i].TimeToStartTrading = 0;
      PairInfo[i].USMarginRequirement= GetPairMarginRequired(PairInfo[i].Pair);
      PairInfo[i].Managed            = true;
      // updated on each timer
      PairInfo[i].SpreadType         = TDeskSpreads[i];
      PairInfo[i].News               = TDeskNews[i];
      PairInfo[i].Signal             = TDeskSignals[i];
      PairInfo[i].OriginalSignal     = -1;
   }

   // ensure that all pairs are loaded in market watch window.
   for(int i=0;i<ArraySize(PairInfo);i++){
      SymbolSelect(PairInfo[i].Pair, true);
   }

   // create dashboard objects
   SetPanel("BP",0,x_axis-1,y_axis-55,DashWidth,475,clrBlack,clrBlack,1);
   SetPanel("AccountBar",0,x_axis-2,y_axis-100,DashWidth,75,C'34,34,34',clrBlack,1);
   
   SetPanel("HeaderBar",0,x_axis-2,y_axis-30,DashWidth,26,C'136,136,136',clrBlack,1);
   
   SetText("AccountBalance","Account Balance: $000.00",x_axis+21,y_axis-90,C'136,136,136',HeaderTextSize);
   SetText("ShortAccountBalance","Short Account: $000.00",x_axis+48,y_axis-70,C'114,114,114',HeaderTextSize-1);
   SetText("LongAccountBalance","Long Account: $000.00",x_axis+50,y_axis-52,C'114,114,114',HeaderTextSize-1);
   
   SetText("AccountEquity","Account Equity: $000.00",x_axis+235,y_axis-90,C'136,136,136',HeaderTextSize);
   SetText("ShortAccountEquity","Short Equity: $000.00",x_axis+262,y_axis-70,C'114,114,114',HeaderTextSize-1);
   SetText("LongAccountEquity","Long Equity: $000.00",x_axis+264,y_axis-52,C'114,114,114',HeaderTextSize-1);
   
   SetText("AccountMargin","Margin Used / Avail: $000.00 / $000.00",x_axis+450,y_axis-90,C'136,136,136',HeaderTextSize);
   SetText("ShortAccountMargin","Short Margin: $000.00 / $000.00",x_axis+507,y_axis-70,C'114,114,114',HeaderTextSize-1);
   SetText("LongAccountMargin","Long Margin: $000.00 / $000.00",x_axis+509,y_axis-52,C'114,114,114',HeaderTextSize-1);
   
   SetText("AccountRealPL","Realized P/L: $000.00",x_axis+815,y_axis-90,C'136,136,136',HeaderTextSize);
   SetText("ShortAccountRealPL","Short P/L: $000.00",x_axis+832,y_axis-70,C'114,114,114',HeaderTextSize-1);
   SetText("LongAccountRealPL","Long P/L: $000.00",x_axis+834,y_axis-52,C'114,114,114',HeaderTextSize-1);
   
   SetText ("SpreadLabel","Spread",x_axis+117,y_axis-20,C'68,68,68',LabelTextSize);
   SetText ("RangeLabel","Range",x_axis+177,y_axis-20,C'68,68,68',LabelTextSize);
   SetText ("NewsLabel","News",x_axis+252,y_axis-20,C'68,68,68',LabelTextSize);
   SetText ("SignalLabel","Signal",x_axis+318,y_axis-20,C'68,68,68',LabelTextSize);
   
   SetText ("LotsLabel","Units",x_axis+589,y_axis-30,C'68,68,68',LabelTextSize);
   SetText ("LotsBuyLabel","Buy",x_axis+566,y_axis-19,C'68,68,68',LabelTextSize);
   SetText ("LotsSellLabel","Sell",x_axis+615,y_axis-19,C'68,68,68',LabelTextSize);
   SetText ("OrdersLabel","Orders",x_axis+662,y_axis-30,C'68,68,68',LabelTextSize);
   SetText ("OrdersBuyLabel","Buy",x_axis+656,y_axis-19,C'68,68,68',LabelTextSize);
   SetText ("OrdersSellLabel","Sell",x_axis+685,y_axis-19,C'68,68,68',LabelTextSize);
   SetText ("BuyPriceLabel","Buy",x_axis+719,y_axis-19,C'68,68,68',LabelTextSize);
   SetText ("SellPriceLabel","Sell",x_axis+771,y_axis-19,C'68,68,68',LabelTextSize);
   
   SetPanel("PandLBox",0,x_axis+810,y_axis-28,54,22,clrBlack,clrNONE,1);
   SetText ("PandLText","0.00",x_axis+820,y_axis-24,C'68,68,68',TextSize);
   
   SetText ("PipsLabel","Pips",x_axis+878,y_axis-19,C'68,68,68',LabelTextSize);
   
   //BitmapCreate("Btn_CloseAll",CloseAllButton,x_axis+932,y_axis-24,0,true);
   
   int i;
   for(i=0;i<ArraySize(PairInfo);i++){
      SetPanel(PairInfo[i].Pair+"_BG",0,x_axis-2,(i*26)+y_axis-5,1415,25,clrBlack,clrBlack,1);
      BitmapCreate("Btn_Chart_"+IntegerToString(i),ChartButton,x_axis,(i*26)+y_axis+1);
      BitmapCreate("Btn_Managed_"+IntegerToString(i),AutoButton,x_axis+30,(i*26)+y_axis+1);
      SetText(PairInfo[i].Pair+"_Label",PairInfo[i].Pair,x_axis+52,(i*26)+y_axis+1,clrBlanchedAlmond,TextSize);
      SetText(PairInfo[i].Pair+"_Spread","0.0",x_axis+120,(i*26)+y_axis+1,C'68,68,68',TextSize);
      
      SetText(PairInfo[i].Pair+"_Range1","000",x_axis+168,(i*26)+y_axis+1,C'68,68,68',TextSize);
      SetText(PairInfo[i].Pair+"_RangeDiv","/",x_axis+191,(i*26)+y_axis+1,C'128,128,128',TextSize+1);
      SetText(PairInfo[i].Pair+"_Range2","000",x_axis+198,(i*26)+y_axis+1,C'68,68,68',TextSize);
      
      SetText(PairInfo[i].Pair+"_News","--------",x_axis+253,(i*26)+y_axis+1,C'68,68,68',TextSize);
      SetText(PairInfo[i].Pair+"_Signal","  --------",x_axis+315,(i*26)+y_axis+1,C'68,68,68',TextSize);
      
      SetPanel(PairInfo[i].Pair+"_VertDivider",0,x_axis+230,(i*26)+y_axis-5,2,26,C'85,85,85',C'45,83,121',3);
      
      
      SetPanel(PairInfo[i].Pair+"_VertDivider2",0,x_axis+480,(i*26)+y_axis-5,2,26,C'85,85,85',C'45,83,121',3);

      SetText(PairInfo[i].Pair+"_Label2",PairInfo[i].Pair,x_axis+488,(i*26)+y_axis+2,C'85,85,85',TextSize);

      BitmapCreate("Btn_Buy_"+IntegerToString(i),BuyButton,x_axis+385,(i*26)+y_axis-1,0,true);
      BitmapCreate("Btn_Sell_"+IntegerToString(i),SellButton,x_axis+430,(i*26)+y_axis-1,0,true);
      SetText(PairInfo[i].Pair+"_Managed","",x_axis+409,(i*26)+y_axis+1,C'34,34,34',TextSize);
      
      SetText(PairInfo[i].Pair+"_LotsBuy","00000",x_axis+560,(i*26)+y_axis+1,C'68,68,68',TextSize);
      SetText(PairInfo[i].Pair+"_LotsSell","00000",x_axis+610,(i*26)+y_axis+1,C'68,68,68',TextSize);
      SetText(PairInfo[i].Pair+"_OrdersBuy","0",x_axis+662,(i*26)+y_axis+1,C'68,68,68',TextSize);
      SetText(PairInfo[i].Pair+"_LongHedge","",x_axis+670,(i*26)+y_axis+6,C'68,68,68',TextSize);
      SetText(PairInfo[i].Pair+"_Hedged","",x_axis+675,(i*26)+y_axis+1,C'68,68,68',TextSize);
      SetText(PairInfo[i].Pair+"_ShortHedge","",x_axis+684,(i*26)+y_axis+6,C'68,68,68',TextSize);
      SetText(PairInfo[i].Pair+"_OrdersSell","0",x_axis+690,(i*26)+y_axis+1,C'68,68,68',TextSize);
      SetText(PairInfo[i].Pair+"_BuyPrice","0.00",x_axis+716,(i*26)+y_axis+1,C'68,68,68',TextSize);
      SetText(PairInfo[i].Pair+"_SellPrice","0.00",x_axis+768,(i*26)+y_axis+1,C'68,68,68',TextSize);
      SetText(PairInfo[i].Pair+"_ProfitLoss","0.00",x_axis+820,(i*26)+y_axis+1,C'68,68,68',TextSize);
      SetText(PairInfo[i].Pair+"_Pips","0.0",x_axis+878,(i*26)+y_axis+2,C'68,68,68',TextSize);
      
      SetPanel(PairInfo[i].Pair+"_VertDivider3",0,x_axis+916,(i*26)+y_axis-5,2,26,C'85,85,85',C'45,83,121',3);
      
      BitmapCreate("Btn_Close_"+IntegerToString(i),CloseShortButton,x_axis+927,(i*26)+y_axis-3,0,true);
      BitmapCreate("Btn_Close_Hedge_"+IntegerToString(i),CloseHedgeButton,x_axis+974,(i*26)+y_axis-3,0,true);

      SetPanel(PairInfo[i].Pair+"_Divider",0,x_axis,(i*26)+y_axis+20,DashWidth,1,C'73,73,73',clrNONE,1);
   }
   SetPanel("FooterBar",0,x_axis,(i*26)+y_axis-5,DashWidth,25,C'34,34,34',clrBlack,1);
   SetText("StatusLabel","Current Status:",x_axis+30,(i*26)+y_axis-1,C'164,164,164',TextSize);
   SetText("StatusMessage",WaitingMsg,x_axis+124,(i*26)+y_axis-1,clrMediumSeaGreen,TextSize);
   SetText("RecentStatusLabel","Recent Status:",x_axis+30,(i*26)+y_axis+25,C'68,68,68',TextSize);
   SetText("RecentStatusMessage","",x_axis+124,(i*26)+y_axis+25,C'68,68,68',TextSize);
   SetText("RecentTradeLabel","Recent Activity:",x_axis+30,(i*26)+y_axis+45,C'68,68,68',TextSize);
   SetText("RecentTradeMessage","",x_axis+124,(i*26)+y_axis+45,C'68,68,68',TextSize);
   SetText("RecentSignalLabel","Recent Signal:",x_axis+30,(i*26)+y_axis+65,C'68,68,68',TextSize);
   SetText("RecentSignalMessage","",x_axis+124,(i*26)+y_axis+65,C'68,68,68',TextSize);
   SetText("TotalBuyUnits","00000",x_axis+560,(i*26)+y_axis-1,C'114,114,114',TextSize);
   SetText("TotalSellUnits","00000",x_axis+610,(i*26)+y_axis-1,C'114,114,114',TextSize);
   SetText("TotalBuyOrders","0",x_axis+662,(i*26)+y_axis-1,C'114,114,114',TextSize);
   SetText("TotalSellOrders","0",x_axis+690,(i*26)+y_axis-1,C'114,114,114',TextSize);
   SetText("TotalBuyProfit","0.00",x_axis+716,(i*26)+y_axis-1,C'114,114,114',TextSize);
   SetText("TotalSellProfit","0.00",x_axis+768,(i*26)+y_axis-1,C'114,114,114',TextSize);
   SetText("TotalProfit","0.00",x_axis+820,(i*26)+y_axis-1,C'114,114,114',TextSize);
   SetText("TotalPips","0.0",x_axis+878,(i*26)+y_axis-1,C'114,114,114',TextSize);
   
   //import saved data
   ReadDataFile();
   for(i=0;i<ArraySize(PairInfo);i++){
      ReadPairDataFiles(i);
   }
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
//--- destroy timer
   EventKillTimer();

   //remove dashboard objects
   ObjectDelete(0,"BP");
   ObjectDelete(0,"AccountBar");
   
   ObjectDelete(0,"HeaderBar");
   
   ObjectDelete(0,"AccountBalance");
   ObjectDelete(0,"ShortAccountBalance");
   ObjectDelete(0,"LongAccountBalance");
   
   ObjectDelete(0,"AccountEquity");
   ObjectDelete(0,"ShortAccountEquity");
   ObjectDelete(0,"LongAccountEquity");
   
   ObjectDelete(0,"AccountMargin");
   ObjectDelete(0,"ShortAccountMargin");
   ObjectDelete(0,"LongAccountMargin");
   
   ObjectDelete(0,"AccountRealPL");
   ObjectDelete(0,"ShortAccountRealPL");
   ObjectDelete(0,"LongAccountRealPL");
   
   ObjectDelete(0,"AccountUnrealPL");
   
   ObjectDelete(0,"ExpertActive");
   ObjectDelete(0,"LiveTrading");
   ObjectDelete(0,"AutoTrading");
   
   ObjectDelete(0,"SpreadLabel");
   ObjectDelete(0,"RangeLabel");
   ObjectDelete(0,"NewsLabel");
   ObjectDelete(0,"SignalLabel");

   ObjectDelete(0,"LotsLabel");
   ObjectDelete(0,"LotsBuyLabel");
   ObjectDelete(0,"LotsSellLabel");
   ObjectDelete(0,"OrdersLabel");
   ObjectDelete(0,"OrdersBuyLabel");
   ObjectDelete(0,"OrdersSellLabel");
   ObjectDelete(0,"BuyPriceLabel");
   ObjectDelete(0,"SellPriceLabel");
   ObjectDelete(0,"PipsLabel");
   
   ObjectDelete(0,"PandLBox");
   ObjectDelete(0,"PandLText");
   
   ObjectDelete(0,"FooterBar");
   
   ObjectDelete(0,"StatusLabel");
   ObjectDelete(0,"StatusMessage");
   ObjectDelete(0,"RecentStatusLabel");
   ObjectDelete(0,"RecentStatusMessage");
   ObjectDelete(0,"RecentTradeLabel");
   ObjectDelete(0,"RecentTradeMessage");
   ObjectDelete(0,"RecentSignalLabel");
   ObjectDelete(0,"RecentSignalMessage");
   
   ObjectDelete(0,"TotalBuyUnits");
   ObjectDelete(0,"TotalSellUnits");
   ObjectDelete(0,"TotalBuyOrders");
   ObjectDelete(0,"TotalSellOrders");
   ObjectDelete(0,"TotalBuyProfit");
   ObjectDelete(0,"TotalSellProfit");
   ObjectDelete(0,"TotalProfit");
   ObjectDelete(0,"TotalPips");
   
   ObjectDelete(0,"Btn_CloseAll");
   
   for(int i=0;i<ArraySize(PairInfo);i++){
      ObjectDelete(0,PairInfo[i].Pair+"_BG");
      ObjectDelete(0,"Btn_Chart_"+IntegerToString(i));
      ObjectDelete(0,"Btn_Managed_"+IntegerToString(i));
      ObjectDelete(0,PairInfo[i].Pair+"_Label");
      ObjectDelete(0,PairInfo[i].Pair+"_Spread");
      
      ObjectDelete(0,PairInfo[i].Pair+"_Range1");
      ObjectDelete(0,PairInfo[i].Pair+"_RangeDiv");
      ObjectDelete(0,PairInfo[i].Pair+"_Range2");
      ObjectDelete(0,PairInfo[i].Pair+"_News");
      ObjectDelete(0,PairInfo[i].Pair+"_Signal");
      
      ObjectDelete(0,"Btn_Buy_"+IntegerToString(i));
      ObjectDelete(0,"Btn_Sell_"+IntegerToString(i));
      ObjectDelete(0,PairInfo[i].Pair+"_Managed");
      
      ObjectDelete(0,PairInfo[i].Pair+"_LotsBuy");
      ObjectDelete(0,PairInfo[i].Pair+"_LotsSell");
      ObjectDelete(0,PairInfo[i].Pair+"_OrdersBuy");
      ObjectDelete(0,PairInfo[i].Pair+"_ShortHedge");
      ObjectDelete(0,PairInfo[i].Pair+"_Hedged");
      ObjectDelete(0,PairInfo[i].Pair+"_LongHedge");
      ObjectDelete(0,PairInfo[i].Pair+"_OrdersSell");
      ObjectDelete(0,PairInfo[i].Pair+"_BuyPrice");
      ObjectDelete(0,PairInfo[i].Pair+"_SellPrice");
      ObjectDelete(0,PairInfo[i].Pair+"_ProfitLoss");
      ObjectDelete(0,PairInfo[i].Pair+"_Locked");
      
      ObjectDelete(0,"Btn_Close_"+IntegerToString(i));
      ObjectDelete(0,"Btn_Close_Hedge_"+IntegerToString(i));
      
      ObjectDelete(0,PairInfo[i].Pair+"_VertDivider");
      ObjectDelete(0,PairInfo[i].Pair+"_VertDivider2");
      ObjectDelete(0,PairInfo[i].Pair+"_VertDivider3");
      
      ObjectDelete(0,PairInfo[i].Pair+"_Label2");
      ObjectDelete(0,PairInfo[i].Pair+"_Pips");
      ObjectDelete(0,PairInfo[i].Pair+"_Divider");
   }
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer(){
   //long search_handle;
   string filefind, SignalChange;

   Comment("      Broker Time: "+TimeToStr(TimeCurrent(),TIME_DATE|TIME_MINUTES)+" | Local Time: "+TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES));
   
   // Are notifications allowed?
   int LocalHour = TimeHour(TimeLocal());
   if (NotifyEnd < NotifyStart){
      if (LocalHour >= NotifyStart || LocalHour < NotifyEnd){
         NotifyAllowed = true;
      } else NotifyAllowed = false;
   } else {
      if (LocalHour >= NotifyStart && LocalHour < NotifyEnd) NotifyAllowed = true;
      else NotifyAllowed = false;
   }
   
   // Trading Allowed? check if AutoTrading, Python Script and TDesk
   AdvisorReady = CheckAdvisorReady();
   
   UpdateInfo();
   if (TDeskSignalIntervalCount >= TDeskSignalIntervalSeconds) UpdateSignals(); // only check for new signals every X seconds
   UpdateDashboard();
   
   if (!AdvisorReady) return; // Advisor is not ready so do nothing!
   
   // Check if we are within trading hours for opening new trades
   if (AdvisorReady){
      TradeTimeOk = SundayMondayFridayStuff();
      if (TradeTimeOk) TradeTimeOk = CheckTradingTimes();
   }

   //Margin level closure. The called function returns a direction if the position should close.
   if (UseMarginLevelClosure){
      string MarginClosureDirection = MarginPercentClosure();
      if (MarginClosureDirection != "none"){
         MarginLevelShutdown(MarginClosureDirection);
         return;// Start again at next timer event
      }
   }
   
   // Use shirt protection
   if (UseShirtProtection){
      if (ShirtProtection()) return;// Shirt protection activated start again at next timer event
   }
   
   // loop through all pairs
   for(int i=0;i<ArraySize(PairInfo);i++){
      // if pair is set to manual trade do nothing
      if (PairInfo[i].Managed == false) continue;
      
      // if bridge_lock file does not exist continue otherwise Python script is busy
      if (FileIsExist(LockFilename) != true){

         bool result = false;
         
         // set basic information for pair
         GetBasics(PairInfo[i].Pair);
         
         //if(PairInfo[i].Pair == "CHFJPY") Print(PairInfo[i].Hedged);
         
         // reset signal data
         BuySignal = false;
         SellSignal = false;
         BuyCloseSignal = false;
         SellCloseSignal = false;

         //Hedging
         if (PairInfo[i].TradeCount > 0){
            if ((HedgeOnOppositeDirectionSignal)||(HedgeOnFlatSignal))
               if (!PairInfo[i].Hedged)
                  if (ShouldWeHedge(PairInfo[i].Pair, i)) return;
            
            if (PairInfo[i].Hedged)
               if (CanWeRemoveTheHedge(PairInfo[i].Pair, i)) return;
         }
         
         //A NONE signal is usually caused by a massively widened spread,
         //so do nothing - even basket closures could be badly affected.
         if (PairInfo[i].Signal == NONE) return;
         
         BuySignal = false;
         SellSignal = false;
         BuyCloseSignal = false;
         SellCloseSignal = false;
         
         //Opposite signal closure
         if (PairInfo[i].TradeCount > 0){
            if (PairInfo[i].Signal == LONG){
               if ((TimeLocal() - PairInfo[i].SignalTime) / 60 <= MaxSignalAgeMinutes)
                  BuySignal = true;
               if (CloseOnOppositeSignal){
                  if (!PairInfo[i].Hedged){
                     if (PairInfo[i].ShortTradeCount > 0){
                        messageLotSize = PairInfo[i].ShortOpenLotsize;
                        if (ClosePosition(PairInfo[i].FXtradeName,i,"sell")){
                           SetStatusMessage("trade", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+PairInfo[i].Pair+" - Close Short - "+IntegerToString(messageLotSize)+" Units");
                           if ((NotifyTradeClose)&&(NotifyAllowed)) SendNotification(PairInfo[i].Pair+" - Close Short Trade");
                           WriteDataFile();
                           return;
                        }
                     }
                  }
               }
            }
            
            if (PairInfo[i].Signal == SHORT){
               if ((TimeLocal() - PairInfo[i].SignalTime) / 60 <= MaxSignalAgeMinutes)
                  SellSignal = true;
               if (CloseOnOppositeSignal){
                  if (!PairInfo[i].Hedged){
                     if (PairInfo[i].LongTradeCount > 0){
                        messageLotSize = PairInfo[i].LongOpenLotsize;
                        if (ClosePosition(PairInfo[i].FXtradeName,i,"buy")){
                           SetStatusMessage("trade", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+PairInfo[i].Pair+" - Close Long - "+IntegerToString(messageLotSize)+" Units");
                           if ((NotifyTradeClose)&&(NotifyAllowed)) SendNotification(PairInfo[i].Pair+" - Close Long Trade");
                           WriteDataFile();
                           return;
                        }
                     }
                  }
               }             
            }
         }
         
         //Look for trade exits
         if (PairInfo[i].TradeCount > 0){
            if (CloseTradesOnFlatSignal){
               if (PairInfo[i].TradeCount > 0){
                  if (!PairInfo[i].Hedged){//Do not close when hedged
                     if (PairInfo[i].Signal == FLAT){
                        
                        if (PairInfo[i].ShortTradeCount > 0){
                           if (ClosePosition(PairInfo[i].FXtradeName,i,"sell")){
                              PairInfo[i].ShortTradeCount = 0;
                           }
                        }
                        if (PairInfo[i].LongTradeCount > 0){
                           if (ClosePosition(PairInfo[i].FXtradeName,i,"buy")){
                              PairInfo[i].LongTradeCount = 0;
                           }
                        }
                        if ((PairInfo[i].ShortTradeCount == 0)&&(PairInfo[i].LongTradeCount == 0)){
                           SetStatusMessage("trade", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+PairInfo[i].Pair+" - Close All (Flat Signal) - "+IntegerToString(PairInfo[i].OpenLotsize)+" Units");
                           if ((NotifyTradeClose)&&(NotifyAllowed)) SendNotification(PairInfo[i].Pair+" - Close All (Flat)");
                           WriteDataFile();
                           return;
                        }
                     }
                  }
               }
            }
         }
         
         //Is there a trading signal?
         if (PairInfo[i].TradeCount == 0){
            BuySignal = false;
            SellSignal = false;
            if ((TimeLocal() - PairInfo[i].SignalTime) / 60 <= MaxSignalAgeMinutes){
               if (PairInfo[i].Signal == LONG)
                  BuySignal = true;
               
               if (PairInfo[i].Signal == SHORT)
                  SellSignal = true;
            }
         }
         
         //Code to allow trading only at the start of a new candle
         if (!EveryTickMode){
            if (PairInfo[i].TickTime == iTime(PairInfo[i].Pair, EveryTickTimeFrame, 0) )
               continue;
            PairInfo[i].TickTime = iTime(PairInfo[i].Pair, EveryTickTimeFrame, 0); 
         }
         
         //Note to coders adding non TDesk compatible indicators. Here is where you would put your iCustom call.
         //Use this construct:
         if (BuySignal){
            //iCustom call goes here
            //Set BuySignal to false if the buying condition is not met
         }//if (BuySignal)
         
         if (SellSignal){
            //iCustom call goes here
            //Set SellSignal to false if the selling condition is not met
         }//if (SellSignal)
         
         // Look for new trades
         if (!PairInfo[i].Hedged){
            if (TimeCurrent() >= PairInfo[i].TimeToStartTrading){
               if (PairInfo[i].TradeCount < MaxTradesAllowed){
                  if (BuySignal || SellSignal){
                    
                    if (BuySignal){
                        //Immediate market trade
                        result = LookForTradingOpportunities(PairInfo[i].Pair, i, "buy");
                     }
     
                     if (SellSignal){
                        //Immediate market trade
                        result = LookForTradingOpportunities(PairInfo[i].Pair, i, "sell");
                     }
                  }
               }
            }
         }
      }
   }
   if (TDeskSignalIntervalCount >= TDeskSignalIntervalSeconds) TDeskSignalIntervalCount = 0;
      else TDeskSignalIntervalCount++;
}
//+------------------------------------------------------------------+

//================================================//
// Update Information                             //
//================================================//
void UpdateInfo(){
   int fuFilehandle;
   string fuFilename;
   int fuOrderCount = 0;
   int shortTime = 0;
   int longTime = 0;
   
   // update TDesk and other info
   ReadTDeskSignals();
   for(int i=0;i<ArraySize(PairInfo);i++){
      // TDesk
      PairInfo[i].SpreadType  = TDeskSpreads[i];
      PairInfo[i].News        = TDeskNews[i];
      PairInfo[i].Signal      = TDeskSignals[i];
      // Other info
      PairInfo[i].Spread = MarketInfo(PairInfo[i].Pair,MODE_SPREAD)/10;
   }
   
//-----------  update account information
   // update short account
   fuFilename = "FXtrade\\account-short.txt";
   if (FileIsExist(fuFilename)){
      fuFilehandle=FileOpen(fuFilename,FILE_READ|FILE_CSV,",");
      
      ShortAccountBal =      StrToDouble(FileReadString(fuFilehandle));
      ShortNumOpenTrades =   StrToInteger(FileReadString(fuFilehandle));
      ShortAvailMargin =     StrToDouble(FileReadString(fuFilehandle));
      ShortUsedMargin =      StrToDouble(FileReadString(fuFilehandle));
      ShortRealizedPL =      StrToDouble(FileReadString(fuFilehandle));
      
      FileClose(fuFilehandle);
   }
   // update long account
   fuFilename = "FXtrade\\account-long.txt";
   if (FileIsExist(fuFilename)){
      fuFilehandle=FileOpen(fuFilename,FILE_READ|FILE_CSV,",");
      
      LongAccountBal =      StrToDouble(FileReadString(fuFilehandle));
      LongNumOpenTrades =   StrToInteger(FileReadString(fuFilehandle));
      LongAvailMargin =     StrToDouble(FileReadString(fuFilehandle));
      LongUsedMargin =      StrToDouble(FileReadString(fuFilehandle));
      LongRealizedPL =      StrToDouble(FileReadString(fuFilehandle));
      
      FileClose(fuFilehandle);
   }
   // update combined account
   AccountBal = NormalizeDouble(ShortAccountBal + LongAccountBal,2);
   NumOpenTrades = ShortNumOpenTrades + LongNumOpenTrades;
   AvailMargin = NormalizeDouble(ShortAvailMargin + LongAvailMargin,2);
   UsedMargin = NormalizeDouble(ShortUsedMargin + LongUsedMargin,2);
   RealizedPL = NormalizeDouble(ShortRealizedPL + LongRealizedPL,2);
   
   // update short orders
   for(int i=0;i<ArraySize(PairInfo);i++){
      // read position
      fuFilename = "FXtrade\\position-"+PairInfo[i].FXtradeName+"-short.txt";
      if (FileIsExist(fuFilename)){
         // assign values
         fuFilehandle=FileOpen(fuFilename,FILE_READ|FILE_CSV,",");
         PairInfo[i].TradeDirection = FileReadString(fuFilehandle);
         PairInfo[i].ShortOpenLotsize = int(FileReadString(fuFilehandle));
         PairInfo[i].ShortAveragePrice = StringToDouble(FileReadString(fuFilehandle));
         PairInfo[i].ShortTradeCount = int(FileReadString(fuFilehandle));
         FileClose(fuFilehandle);
         
      } else {
         // reset values
         PairInfo[i].TradeDirection = "none";
         PairInfo[i].ShortOpenLotsize = 0;
         PairInfo[i].ShortAveragePrice = 0;
         PairInfo[i].ShortProfitPips = 0;
         PairInfo[i].ShortTradeCount = 0;
      }
      
      // read minmax
      fuFilename = "FXtrade\\minmax-"+PairInfo[i].FXtradeName+"-short.txt";
      if (FileIsExist(fuFilename)){
         fuFilehandle=FileOpen(fuFilename,FILE_READ|FILE_CSV,",");
         PairInfo[i].MinShortOrderPrice = StringToDouble(FileReadString(fuFilehandle));
         PairInfo[i].MaxShortOrderPrice = StringToDouble(FileReadString(fuFilehandle));
         FileClose(fuFilehandle);
      } else {
         PairInfo[i].MinShortOrderPrice = 0;
         PairInfo[i].MaxShortOrderPrice = 0;
      }
   }

   // update long orders
   for(int i=0;i<ArraySize(PairInfo);i++){
      fuFilename = "FXtrade\\position-"+PairInfo[i].FXtradeName+"-long.txt";
      if (FileIsExist(fuFilename)){
         // assign values
         fuFilehandle=FileOpen(fuFilename,FILE_READ|FILE_CSV,",");
         PairInfo[i].TradeDirection = FileReadString(fuFilehandle);
         PairInfo[i].LongOpenLotsize = int(FileReadString(fuFilehandle));
         PairInfo[i].LongAveragePrice = StringToDouble(FileReadString(fuFilehandle));
         PairInfo[i].LongTradeCount = int(FileReadString(fuFilehandle));
         FileClose(fuFilehandle);
         
      } else {
         // reset values
         PairInfo[i].TradeDirection = "none";
         PairInfo[i].LongOpenLotsize = 0;
         PairInfo[i].LongAveragePrice = 0;
         PairInfo[i].LongProfitPips = 0;
         PairInfo[i].LongTradeCount = 0;
      }
      
      // read minmax
      fuFilename = "FXtrade\\minmax-"+PairInfo[i].FXtradeName+"-long.txt";
      if (FileIsExist(fuFilename)){
         fuFilehandle=FileOpen(fuFilename,FILE_READ|FILE_CSV,",");
         PairInfo[i].MinLongOrderPrice = StringToDouble(FileReadString(fuFilehandle));
         PairInfo[i].MaxLongOrderPrice = StringToDouble(FileReadString(fuFilehandle));
         FileClose(fuFilehandle);
      } else {
         PairInfo[i].MinLongOrderPrice = 0;
         PairInfo[i].MaxLongOrderPrice = 0;
      }
   }
   
   // update tradedirection/hedgedirection + trade count
   for(int i=0;i<ArraySize(PairInfo);i++){
      fuFilename = "FXtrade\\time-"+PairInfo[i].FXtradeName+"-short.txt";
      if (FileIsExist(fuFilename)){
         fuFilehandle=FileOpen(fuFilename,FILE_READ|FILE_CSV,",");
         shortTime = int(StringToInteger(FileReadString(fuFilehandle)));
         FileClose(fuFilehandle);
      } else {
         shortTime = 0;
      }
      fuFilename = "FXtrade\\time-"+PairInfo[i].FXtradeName+"-long.txt";
      if (FileIsExist(fuFilename)){
         fuFilehandle=FileOpen(fuFilename,FILE_READ|FILE_CSV,",");
         longTime = int(StringToInteger(FileReadString(fuFilehandle)));
         FileClose(fuFilehandle);
      } else {
         longTime = 0;
      }

      // assign vals to original and hedge
      if (((PairInfo[i].ShortTradeCount == 1)&&(longTime == 0)) ||
          ((PairInfo[i].ShortTradeCount == 1)&&(longTime > shortTime)) ||
          (PairInfo[i].ShortTradeCount > 1))
      {
         PairInfo[i].TradeDirection = "sell";
         if ((PairInfo[i].ShortTradeCount > 0)&&(PairInfo[i].LongTradeCount > 0)){
            PairInfo[i].Hedged = true;
            PairInfo[i].HedgedDirection = "buy";
         } else {
            PairInfo[i].Hedged = false;
            PairInfo[i].HedgedDirection = "none";
         }
      } else {
         PairInfo[i].TradeDirection = "buy";
         if ((PairInfo[i].ShortTradeCount > 0)&&(PairInfo[i].LongTradeCount > 0)){
            PairInfo[i].Hedged = true;
            PairInfo[i].HedgedDirection = "sell";
         } else {
            PairInfo[i].Hedged = false;
            PairInfo[i].HedgedDirection = "none";
         }
      }
   }
   
   
   // update trade count and hedged
   for(int i=0;i<ArraySize(PairInfo);i++){
      PairInfo[i].TradeCount = PairInfo[i].ShortTradeCount + PairInfo[i].LongTradeCount;
      if ((PairInfo[i].ShortTradeCount > 0)&&(PairInfo[i].LongTradeCount > 0)){
         PairInfo[i].Hedged = true;
      } else {
         PairInfo[i].Hedged = false;
         PairInfo[i].HedgedDirection = "none";
      }
   }
   
   // update equity and margin levels
   AcctEquity       = NormalizeDouble(AccountBal + CurrentProfit,2);
   ShortAccountEquity  = NormalizeDouble(ShortAccountBal + ShortAccountProfit,2);
   LongAccountEquity   = NormalizeDouble(LongAccountBal + LongAccountProfit,2);
   if (UsedMargin != 0) MarginLevel = NormalizeDouble((AcctEquity / UsedMargin) * 100, 2);
      else MarginLevel = 0;
   if (ShortUsedMargin != 0) ShortMarginLevel = NormalizeDouble((ShortAccountEquity / ShortUsedMargin) * 100, 2);
      else ShortMarginLevel = 0;
   if (LongUsedMargin != 0) LongMarginLevel  = NormalizeDouble((LongAccountEquity / LongUsedMargin) * 100, 2);
      else LongMarginLevel = 0;
   
   PlotADR();
   PlotADRpips();
   
   return;
}

//================================================//
// Update Signals                                 //
//================================================//
void UpdateSignals(){
   for(int i=0;i<ArraySize(PairInfo);i++){
      // set initial signal state
      if (PairInfo[i].OriginalSignal == -1) PairInfo[i].OriginalSignal = PairInfo[i].Signal;
      // check for signal change
      if (PairInfo[i].OriginalSignal != PairInfo[i].Signal){
         // set signal change
         PairInfo[i].SignalChange = EnumToString(PairInfo[i].OriginalSignal)+" to "+EnumToString(PairInfo[i].Signal);
         // send message
         SetStatusMessage("signal", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - Signal for "+PairInfo[i].Pair+" changed from "+PairInfo[i].SignalChange);
         // write to data file
         WriteDataFile();
         WritePairDataFiles(i);
         // reassign value
         PairInfo[i].OriginalSignal = PairInfo[i].Signal;
      }
   }
}

//================================================//
// Update Dashboard                               //
//================================================//
void UpdateDashboard(){
   
   double fuProfit,fuTotalProfit,fuShortProfit,fuLongProfit,fuTotalPips,fuShortPips,fuLongPips;
   int fuTotalSellOrders, fuTotalBuyOrders,fuTotalSellUnits,fuTotalBuyUnits;
   string fuSpacer,ADRstring,ADRpipsString,StrLots;
   color  fuSpreadColor,fuADRColor;
   
   fuTotalProfit = 0;
   fuShortProfit = 0;
   fuLongProfit = 0;
   fuTotalPips = 0;
   fuShortPips = 0;
   fuLongPips = 0;
   fuTotalSellUnits = 0;
   fuTotalBuyUnits = 0;
   fuTotalSellOrders = 0;
   fuTotalBuyOrders = 0;
   
   ObjectSetText("AccountBalance","Account Balance: $"+DoubleToStr(AccountBal,2),HeaderTextSize,NULL,C'136,136,136');
   ObjectSetText("ShortAccountBalance","Short Balance: $"+DoubleToStr(ShortAccountBal,2),HeaderTextSize-1,NULL,C'114,114,114');
   ObjectSetText("LongAccountBalance","Long Balance: $"+DoubleToStr(LongAccountBal,2),HeaderTextSize-1,NULL,C'114,114,114');
   
   if (MarginLevel > 0) ObjectSetText("AccountMargin","Margin Used / Avail: $"+DoubleToStr(UsedMargin,2)+" / $"+DoubleToStr(AvailMargin,2)+" ("+DoubleToStr(MarginLevel,2)+"%)",HeaderTextSize,NULL,C'136,136,136');
      else ObjectSetText("AccountMargin","Margin Used / Avail: $"+DoubleToStr(UsedMargin,2)+" / $"+DoubleToStr(AvailMargin,2),HeaderTextSize,NULL,C'136,136,136');
   if (ShortMarginLevel > 0) ObjectSetText("ShortAccountMargin","Short Margin: $"+DoubleToStr(ShortUsedMargin,2)+" / $"+DoubleToStr(ShortAvailMargin,2)+"  ("+DoubleToStr(ShortMarginLevel,2)+"%)",HeaderTextSize-1,NULL,C'114,114,114');
      else  ObjectSetText("ShortAccountMargin","Short Margin: $"+DoubleToStr(ShortUsedMargin,2)+" / $"+DoubleToStr(ShortAvailMargin,2),HeaderTextSize-1,NULL,C'114,114,114');
   if (LongMarginLevel > 0) ObjectSetText("LongAccountMargin","Long Margin: $"+DoubleToStr(LongUsedMargin,2)+" / $"+DoubleToStr(LongAvailMargin,2)+"  ("+DoubleToStr(LongMarginLevel,2)+"%)",HeaderTextSize-1,NULL,C'114,114,114');
      else  ObjectSetText("LongAccountMargin","Long Margin: $"+DoubleToStr(LongUsedMargin,2)+" / $"+DoubleToStr(LongAvailMargin,2),HeaderTextSize-1,NULL,C'114,114,114');
      
   ObjectSetText("AccountRealPL","Realized P/L: $"+DoubleToStr((NormalizeDouble(ShortRealizedPL + ShortPandLOffset,2) + NormalizeDouble(LongRealizedPL + LongPandLOffset,2)),2),HeaderTextSize,NULL,C'136,136,136');
   ObjectSetText("ShortAccountRealPL","Short P/L: $"+DoubleToStr((NormalizeDouble(ShortRealizedPL + ShortPandLOffset,2)),2),HeaderTextSize-1,NULL,C'114,114,114');
   ObjectSetText("LongAccountRealPL","Long P/L: $"+DoubleToStr((NormalizeDouble(LongRealizedPL + LongPandLOffset,2)),2),HeaderTextSize-1,NULL,C'114,114,114');

   for(int i=0;i<ArraySize(PairInfo);i++){
      
      // Managed Button
      if (PairInfo[i].Managed) ObjectSetString(0,"Btn_Managed_"+IntegerToString(i),OBJPROP_BMPFILE,0,AutoButton);
         else ObjectSetString(0,"Btn_Managed_"+IntegerToString(i),OBJPROP_BMPFILE,0,ManualButton);
      
      // Spread
      if (PairInfo[i].Spread < 10) fuSpacer = "  ";
         else fuSpacer = "";
      if (PairInfo[i].SpreadType == ABNORMAL) fuSpreadColor = clrOrange;
         else if (PairInfo[i].SpreadType == STOPHUNT) fuSpreadColor = clrRed;
         else fuSpreadColor = clrLimeGreen;
      ObjectSetText(PairInfo[i].Pair+"_Spread",fuSpacer+DoubleToStr(PairInfo[i].Spread,1),TextSize,NULL,fuSpreadColor);

      // ADR Values
      if (PairInfo[i].ADR < 99) fuSpacer = "0";
         else fuSpacer = "";
      ADRstring = fuSpacer+DoubleToStr(PairInfo[i].ADR,0);
      if (PairInfo[i].ADRPips < 10) fuSpacer = "00";
         else if (PairInfo[i].ADRPips < 100) fuSpacer = "0";
         else fuSpacer = "";
      ADRpipsString = fuSpacer+DoubleToStr(PairInfo[i].ADRPips,0);
      if ((PairInfo[i].ADRPips > PairInfo[i].ADR * 0.9) && (PairInfo[i].ADRPips < PairInfo[i].ADR)) fuADRColor = clrOrange;
         else if (PairInfo[i].ADRPips >= PairInfo[i].ADR) fuADRColor = clrOrangeRed;
         else fuADRColor = clrLimeGreen;
      ObjectSetText(PairInfo[i].Pair+"_Range1",ADRpipsString,TextSize,NULL,fuADRColor);
      ObjectSetText(PairInfo[i].Pair+"_Range2",ADRstring,TextSize,NULL,fuADRColor);
      
      // News
      if (PairInfo[i].News == LOWNEWS) ObjectSetText(PairInfo[i].Pair+"_News","Low",TextSize,NULL,clrSienna);
         else if (PairInfo[i].News == MEDNEWS) ObjectSetText(PairInfo[i].Pair+"_News","Medium",TextSize,NULL,clrOrange);
         else if (PairInfo[i].News == HIGHNEWS) ObjectSetText(PairInfo[i].Pair+"_News","High",TextSize,NULL,clrOrangeRed);
         else ObjectSetText(PairInfo[i].Pair+"_News","none",TextSize,NULL,C'68,68,68');
      fuProfit = 0;
      
      // Signal
      if (PairInfo[i].Signal == FLAT) ObjectSetText(PairInfo[i].Pair+"_Signal"," --flat--",TextSize,NULL,clrSienna);
         else if (PairInfo[i].Signal == LONG) ObjectSetText(PairInfo[i].Pair+"_Signal"," LONG",TextSize,NULL,clrLimeGreen);
         else if (PairInfo[i].Signal == SHORT) ObjectSetText(PairInfo[i].Pair+"_Signal","SHORT",TextSize,NULL,clrDeepSkyBlue);
         else ObjectSetText(PairInfo[i].Pair+"_Signal","  none",TextSize,NULL,C'68,68,68');

      // Show/Hide Buy and Sell Buttons
      if (PairInfo[i].Managed){
         ObjectSetInteger(0,"Btn_Buy_"+IntegerToString(i),OBJPROP_XSIZE,-1);
         ObjectSetInteger(0,"Btn_Sell_"+IntegerToString(i),OBJPROP_XSIZE,-1);
         ObjectSetInteger(0,PairInfo[i].Pair+"_Managed",OBJPROP_XDISTANCE,x_axis+409);
         ObjectSetText(PairInfo[i].Pair+"_Managed",". . . . .",TextSize,NULL,C'68,68,68');
      } else {
         ObjectSetInteger(0,"Btn_Buy_"+IntegerToString(i),OBJPROP_XSIZE,37);
         ObjectSetInteger(0,"Btn_Sell_"+IntegerToString(i),OBJPROP_XSIZE,37);
         ObjectSetInteger(0,PairInfo[i].Pair+"_Managed",OBJPROP_XDISTANCE,-1000);
         ObjectSetText(PairInfo[i].Pair+"_Managed","",TextSize,NULL,C'68,68,68');
      }

      // Active Trades Label2
      if (PairInfo[i].ShortTradeCount > 0 || PairInfo[i].LongTradeCount > 0) ObjectSetInteger(0,PairInfo[i].Pair+"_Label2",OBJPROP_COLOR,clrBlanchedAlmond);
         else ObjectSetInteger(0,PairInfo[i].Pair+"_Label2",OBJPROP_COLOR,C'85,85,85');
         
      // Open Short Lot Size
      if (PairInfo[i].ShortOpenLotsize > 0){
         if (PairInfo[i].ShortOpenLotsize >= 10000) StrLots = IntegerToString(PairInfo[i].ShortOpenLotsize);
            else if ((PairInfo[i].ShortOpenLotsize >= 1000) && (PairInfo[i].ShortOpenLotsize <= 9999)) StrLots = "0"+IntegerToString(PairInfo[i].ShortOpenLotsize);
            else if ((PairInfo[i].ShortOpenLotsize >= 100) && (PairInfo[i].ShortOpenLotsize <= 999)) StrLots = "00"+IntegerToString(PairInfo[i].ShortOpenLotsize);
            else if ((PairInfo[i].ShortOpenLotsize >= 10) && (PairInfo[i].ShortOpenLotsize <= 99)) StrLots = "000"+IntegerToString(PairInfo[i].ShortOpenLotsize);
            else  StrLots = "0000"+IntegerToString(PairInfo[i].ShortOpenLotsize);
         ObjectSetText(PairInfo[i].Pair+"_LotsSell",StrLots,TextSize,NULL,clrBlanchedAlmond);
         fuTotalSellUnits += PairInfo[i].ShortOpenLotsize;
      } else {
         ObjectSetText(PairInfo[i].Pair+"_LotsSell","00000",TextSize,NULL,C'68,68,68');
      }
      
      // Open Long Lot Size
      if (PairInfo[i].LongOpenLotsize > 0){
         if (PairInfo[i].LongOpenLotsize >= 10000) StrLots = IntegerToString(PairInfo[i].LongOpenLotsize);
            else if ((PairInfo[i].LongOpenLotsize >= 1000) && (PairInfo[i].LongOpenLotsize <= 9999)) StrLots = "0"+IntegerToString(PairInfo[i].LongOpenLotsize);
            else if ((PairInfo[i].LongOpenLotsize >= 100) && (PairInfo[i].LongOpenLotsize <= 999)) StrLots = "00"+IntegerToString(PairInfo[i].LongOpenLotsize);
            else if ((PairInfo[i].LongOpenLotsize >= 10) && (PairInfo[i].LongOpenLotsize <= 99)) StrLots = "000"+IntegerToString(PairInfo[i].LongOpenLotsize);
            else  StrLots = "0000"+IntegerToString(PairInfo[i].LongOpenLotsize);
         ObjectSetText(PairInfo[i].Pair+"_LotsBuy",StrLots,TextSize,NULL,clrBlanchedAlmond);
         fuTotalBuyUnits += PairInfo[i].LongOpenLotsize;
      } else {
         ObjectSetText(PairInfo[i].Pair+"_LotsBuy","00000",TextSize,NULL,C'68,68,68');
      }
      
      // Order Count
      if (PairInfo[i].ShortTradeCount > 0){
         ObjectSetText(PairInfo[i].Pair+"_OrdersSell",IntegerToString(PairInfo[i].ShortTradeCount),TextSize,NULL,clrBlanchedAlmond);
         fuTotalSellOrders += PairInfo[i].ShortTradeCount;
      } else ObjectSetText(PairInfo[i].Pair+"_OrdersSell","0",TextSize,NULL,C'68,68,68');
      
      if (PairInfo[i].LongTradeCount > 0){
         ObjectSetText(PairInfo[i].Pair+"_OrdersBuy",IntegerToString(PairInfo[i].LongTradeCount),TextSize,NULL,clrBlanchedAlmond);
         fuTotalBuyOrders += PairInfo[i].LongTradeCount;
      } else ObjectSetText(PairInfo[i].Pair+"_OrdersBuy","0",TextSize,NULL,C'68,68,68');
         
      // Hedged?
      if (PairInfo[i].ShortTradeCount > 0 && PairInfo[i].LongTradeCount > 0) ObjectSetText(PairInfo[i].Pair+"_Hedged","H",TextSize,NULL,clrTeal);
         else ObjectSetText(PairInfo[i].Pair+"_Hedged","",TextSize,NULL,C'68,68,68');
      if (PairInfo[i].HedgedDirection == "buy") ObjectSetText(PairInfo[i].Pair+"_LongHedge","n",TextSize-4,"Wingdings",clrTeal);
         else ObjectSetText(PairInfo[i].Pair+"_LongHedge","",TextSize,NULL,C'68,68,68');
      if (PairInfo[i].HedgedDirection == "sell") ObjectSetText(PairInfo[i].Pair+"_ShortHedge","n",TextSize-4,"Wingdings",clrTeal);
         else  ObjectSetText(PairInfo[i].Pair+"_ShortHedge","",TextSize,NULL,C'68,68,68');
      
      // Short profit / loss
      if (PairInfo[i].ShortTradeCount > 0){
         if (StringFind(PairInfo[i].Pair,"JPY") >= 0) PairInfo[i].ShortProfit = MarketInfo(PairInfo[i].Pair, MODE_TICKVALUE) * PairInfo[i].ShortOpenLotsize * (PairInfo[i].ShortAveragePrice - MarketInfo(PairInfo[i].Pair,MODE_ASK))/100;
            else PairInfo[i].ShortProfit = MarketInfo(PairInfo[i].Pair, MODE_TICKVALUE) * PairInfo[i].ShortOpenLotsize * (PairInfo[i].ShortAveragePrice - MarketInfo(PairInfo[i].Pair,MODE_ASK));
         PairInfo[i].ShortProfitPips = NormalizeDouble((PairInfo[i].ShortAveragePrice - MarketInfo(PairInfo[i].Pair,MODE_ASK))/MarketInfo(PairInfo[i].Pair,MODE_POINT)/10,1);
         if (PairInfo[i].ShortProfit > 0) ObjectSetText(PairInfo[i].Pair+"_SellPrice",DoubleToStr(MathAbs(PairInfo[i].ShortProfit),2),TextSize,NULL,C'147,255,38');
            else if (PairInfo[i].ShortProfit == 0) ObjectSetText(PairInfo[i].Pair+"_SellPrice","0.00",TextSize,NULL,C'147,255,38');
            else ObjectSetText(PairInfo[i].Pair+"_SellPrice",DoubleToStr(MathAbs(PairInfo[i].ShortProfit),2),TextSize,NULL,clrOrangeRed);
      } else {
         PairInfo[i].ShortProfit = 0;
         PairInfo[i].ShortProfitPips = 0;
         ObjectSetText(PairInfo[i].Pair+"_SellPrice","0.00",TextSize,NULL,C'68,68,68');
      }
      
      // Long profit / loss
      if (PairInfo[i].LongTradeCount > 0){
         if (StringFind(PairInfo[i].Pair,"JPY") >= 0) PairInfo[i].LongProfit = MarketInfo(PairInfo[i].Pair, MODE_TICKVALUE) * PairInfo[i].LongOpenLotsize * (MarketInfo(PairInfo[i].Pair,MODE_BID) - PairInfo[i].LongAveragePrice)/100;
            else PairInfo[i].LongProfit = MarketInfo(PairInfo[i].Pair, MODE_TICKVALUE) * PairInfo[i].LongOpenLotsize * (MarketInfo(PairInfo[i].Pair,MODE_BID) - PairInfo[i].LongAveragePrice);
         PairInfo[i].LongProfitPips = NormalizeDouble((MarketInfo(PairInfo[i].Pair,MODE_BID) - PairInfo[i].LongAveragePrice)/MarketInfo(PairInfo[i].Pair,MODE_POINT)/10,1);
         if (PairInfo[i].LongProfit > 0) ObjectSetText(PairInfo[i].Pair+"_BuyPrice",DoubleToStr(MathAbs(PairInfo[i].LongProfit),2),TextSize,NULL,C'147,255,38');
            else if (PairInfo[i].LongProfit == 0) ObjectSetText(PairInfo[i].Pair+"_BuyPrice","0.00",TextSize,NULL,C'147,255,38');
            else ObjectSetText(PairInfo[i].Pair+"_BuyPrice",DoubleToStr(MathAbs(PairInfo[i].LongProfit),2),TextSize,NULL,clrOrangeRed);
      } else {
         PairInfo[i].LongProfit = 0;
         PairInfo[i].LongProfitPips = 0;
         ObjectSetText(PairInfo[i].Pair+"_BuyPrice","0.00",TextSize,NULL,C'68,68,68');
      }
      
      // Combined profit / loss
      if (PairInfo[i].ShortTradeCount > 0 || PairInfo[i].LongTradeCount > 0){
         fuProfit = NormalizeDouble(PairInfo[i].ShortProfit + PairInfo[i].LongProfit,2);
         if (fuProfit > 0) ObjectSetText(PairInfo[i].Pair+"_ProfitLoss",DoubleToStr(MathAbs(fuProfit),2),TextSize,NULL,C'147,255,38');
            else if (fuProfit == 0) ObjectSetText(PairInfo[i].Pair+"_ProfitLoss","0.00",TextSize,NULL,C'147,255,38');
            else  ObjectSetText(PairInfo[i].Pair+"_ProfitLoss",DoubleToStr(MathAbs(fuProfit),2),TextSize,NULL,clrOrangeRed);
      } else {
         ObjectSetText(PairInfo[i].Pair+"_ProfitLoss","0.00",TextSize,NULL,C'68,68,68');
      }
      
      // Combined Pips
      if (PairInfo[i].ShortTradeCount > 0 || PairInfo[i].LongTradeCount > 0){
         PairInfo[i].ProfitPips = NormalizeDouble(PairInfo[i].ShortProfitPips + PairInfo[i].LongProfitPips,1);
         if (PairInfo[i].ProfitPips < 0) ObjectSetText(PairInfo[i].Pair+"_Pips",DoubleToStr(MathAbs(PairInfo[i].ProfitPips),1),TextSize,NULL,clrOrangeRed);
            else ObjectSetText(PairInfo[i].Pair+"_Pips",DoubleToStr(PairInfo[i].ProfitPips,1),TextSize,NULL,C'147,255,38');
      } else {
         PairInfo[i].ProfitPips = 0;
         ObjectSetText(PairInfo[i].Pair+"_Pips","0.0",TextSize,NULL,C'68,68,68');
      }
      
      // Show close buttons
      if ((PairInfo[i].ShortTradeCount > 0 || PairInfo[i].LongTradeCount > 0)&&(!PairInfo[i].Managed)){
         if (PairInfo[i].TradeDirection == "sell"){
            ObjectSetInteger(0,"Btn_Close_"+IntegerToString(i),OBJPROP_XSIZE,40);
            ObjectSetString(0,"Btn_Close_"+IntegerToString(i),OBJPROP_BMPFILE,0,CloseShortButton);
            if (PairInfo[i].Hedged){
               ObjectSetInteger(0,"Btn_Close_Hedge_"+IntegerToString(i),OBJPROP_XSIZE,40);
               ObjectSetString(0,"Btn_Close_Hedge_"+IntegerToString(i),OBJPROP_BMPFILE,0,CloseHedgeButton);
            }
         }
         if (PairInfo[i].TradeDirection == "buy"){
            ObjectSetInteger(0,"Btn_Close_"+IntegerToString(i),OBJPROP_XSIZE,40);
            ObjectSetString(0,"Btn_Close_"+IntegerToString(i),OBJPROP_BMPFILE,0,CloseLongButton);
            if (PairInfo[i].Hedged){
               ObjectSetInteger(0,"Btn_Close_Hedge_"+IntegerToString(i),OBJPROP_XSIZE,40);
               ObjectSetString(0,"Btn_Close_Hedge_"+IntegerToString(i),OBJPROP_BMPFILE,0,CloseHedgeButton);
            }
         }
      } else {
         ObjectSetInteger(0,"Btn_Close_"+IntegerToString(i),OBJPROP_XSIZE,-1);
      }
      
      // Total Profit Calculation for all pairs
      fuShortProfit  += PairInfo[i].ShortProfit;
      fuLongProfit   += PairInfo[i].LongProfit;
      fuTotalPips    += PairInfo[i].ProfitPips;
      fuShortPips    += PairInfo[i].ShortProfitPips;
      fuLongPips     += PairInfo[i].LongProfitPips;
   }
   
   ShortAccountProfit   = NormalizeDouble(fuShortProfit,2);
   LongAccountProfit    = NormalizeDouble(fuLongProfit,2);
   CurrentProfit        = NormalizeDouble(fuShortProfit + fuLongProfit,2);
   
   ShortAccountPips     = NormalizeDouble(fuShortPips,1);
   LongAccountPips      = NormalizeDouble(fuLongPips,1);
   CurrentPips          = NormalizeDouble(fuTotalPips,1);
   
   if (NumOpenTrades > 0){
      if (CurrentProfit > 0) ObjectSetText("PandLText",DoubleToStr(CurrentProfit,2),TextSize,NULL,C'147,255,38');
         else if (CurrentProfit == 0) ObjectSetText("PandLText","0.00",TextSize,NULL,C'147,255,38');
         else ObjectSetText("PandLText",DoubleToStr(MathAbs(CurrentProfit),2),TextSize,NULL,clrOrangeRed);
   } else {
      ObjectSetText("PandLText","0.00",TextSize,NULL,C'68,68,68');
   }

   ObjectSetText("AccountEquity","Account Equity: $"+DoubleToStr(AccountBal+CurrentProfit,2),HeaderTextSize,NULL,C'136,136,136');
   ObjectSetText("ShortAccountEquity","Short Equity: $"+DoubleToStr(ShortAccountBal+fuShortProfit,2),HeaderTextSize-1,NULL,C'114,114,114');
   ObjectSetText("LongAccountEquity","Long Equity: $"+DoubleToStr(LongAccountBal+fuLongProfit,2),HeaderTextSize-1,NULL,C'114,114,114');
   
   if (NumOpenTrades > 0){
      if (fuTotalSellUnits >= 10000) StrLots = IntegerToString(fuTotalSellUnits);
         else if ((fuTotalSellUnits >= 1000) && (fuTotalSellUnits <= 9999)) StrLots = "0"+IntegerToString(fuTotalSellUnits);
         else if ((fuTotalSellUnits >= 100) && (fuTotalSellUnits <= 999)) StrLots = "00"+IntegerToString(fuTotalSellUnits);
         else if ((fuTotalSellUnits >= 10) && (fuTotalSellUnits <= 99)) StrLots = "000"+IntegerToString(fuTotalSellUnits);
         else  StrLots = "000"+IntegerToString(fuTotalSellUnits);
      ObjectSetText("TotalSellUnits",StrLots,TextSize,NULL,C'114,114,114');
      if (fuTotalBuyUnits >= 10000) StrLots = IntegerToString(fuTotalBuyUnits);
         else if ((fuTotalBuyUnits >= 1000) && (fuTotalBuyUnits <= 9999)) StrLots = "0"+IntegerToString(fuTotalBuyUnits);
         else if ((fuTotalBuyUnits >= 100) && (fuTotalBuyUnits <= 999)) StrLots = "00"+IntegerToString(fuTotalBuyUnits);
         else if ((fuTotalBuyUnits >= 10) && (fuTotalBuyUnits <= 99)) StrLots = "000"+IntegerToString(fuTotalBuyUnits);
         else  StrLots = "000"+IntegerToString(fuTotalBuyUnits);
      ObjectSetText("TotalBuyUnits",StrLots,TextSize,NULL,C'114,114,114');
      
      ObjectSetText("TotalSellOrders",IntegerToString(fuTotalSellOrders),TextSize,NULL,C'114,114,114');
      ObjectSetText("TotalBuyOrders",IntegerToString(fuTotalBuyOrders),TextSize,NULL,C'114,114,114');
      
      if (fuShortProfit > 0) ObjectSetText("TotalSellProfit",DoubleToStr(fuShortProfit,2),TextSize,NULL,clrMediumSeaGreen);
         else if (fuShortProfit == 0) ObjectSetText("TotalSellProfit","0.00",TextSize,NULL,clrMediumSeaGreen);
         else ObjectSetText("TotalSellProfit",DoubleToStr(MathAbs(fuShortProfit),2),TextSize,NULL,clrOrangeRed);
      if (fuLongProfit > 0) ObjectSetText("TotalBuyProfit",DoubleToStr(fuLongProfit,2),TextSize,NULL,clrMediumSeaGreen);
         else if (fuLongProfit == 0) ObjectSetText("TotalBuyProfit","0.00",TextSize,NULL,clrMediumSeaGreen);
         else ObjectSetText("TotalBuyProfit",DoubleToStr(MathAbs(fuLongProfit),2),TextSize,NULL,clrOrangeRed);

      if (CurrentProfit > 0) ObjectSetText("TotalProfit",DoubleToStr(CurrentProfit,2),TextSize,NULL,clrMediumSeaGreen);
         else if (CurrentProfit == 0) ObjectSetText("TotalProfit","0.00",TextSize,NULL,clrMediumSeaGreen);
         else ObjectSetText("TotalProfit",DoubleToStr(MathAbs(CurrentProfit),2),TextSize,NULL,clrOrangeRed);
         
       if (fuTotalPips > 0) ObjectSetText("TotalPips",DoubleToStr(fuTotalPips,1),TextSize,NULL,clrMediumSeaGreen);
         else if (fuTotalPips == 0) ObjectSetText("TotalPips","0.0",TextSize,NULL,clrMediumSeaGreen);
         else ObjectSetText("TotalPips",DoubleToStr(MathAbs(fuTotalPips),1),TextSize,NULL,clrOrangeRed);
   } else {
      ObjectSetText("TotalSellUnits",StrLots,TextSize,NULL,C'114,114,114');
      ObjectSetText("TotalBuyUnits",StrLots,TextSize,NULL,C'114,114,114');
      ObjectSetText("TotalSellOrders",IntegerToString(fuTotalSellOrders),TextSize,NULL,C'114,114,114');
      ObjectSetText("TotalBuyOrders",IntegerToString(fuTotalBuyOrders),TextSize,NULL,C'114,114,114');
      ObjectSetText("TotalSellProfit",DoubleToStr(MathAbs(fuShortProfit),2),TextSize,NULL,clrOrangeRed);
      ObjectSetText("TotalBuyProfit",DoubleToStr(MathAbs(fuLongProfit),2),TextSize,NULL,clrOrangeRed);
      ObjectSetText("TotalProfit",DoubleToStr(MathAbs(CurrentProfit),2),TextSize,NULL,clrOrangeRed);
      ObjectSetText("TotalPips",DoubleToStr(MathAbs(fuTotalPips),0),TextSize,NULL,clrOrangeRed);
   }
   
}

//================================================//
// Messages                                       //
//================================================//
void SetStatusMessage(string Type, string Message, bool Flash = false){
   color MsgColor = C'164,164,164';
   if (Type == "warning") MsgColor = clrOrangeRed;
      else if (Type == "message") MsgColor = clrDarkOrange;
   if (Flash){
      if (MessageFlash) MsgColor = C'164,164,164';
      MessageFlash = !MessageFlash;
   }
   if (Type == "recentStatus")ObjectSetText("RecentStatusMessage",Message,TextSize,NULL,C'68,68,68');
   else if (Type == "trade")  ObjectSetText("RecentTradeMessage",Message,TextSize,NULL,C'68,68,68');
   else if (Type == "signal") ObjectSetText("RecentSignalMessage",Message,TextSize,NULL,C'68,68,68');
   else ObjectSetText("StatusMessage",Message,TextSize,NULL,MsgColor);
}

void ClearStatusMessage(){
   ObjectSetText("StatusMessage",WaitingMsg,TextSize,NULL,clrMediumSeaGreen);
}

//================================================//
// AutoTrading Enabled and Script Active          //
//================================================//
bool CheckAdvisorReady(){
   int SecondsDown = 2; // number of seconds script down before displaying error message
   
   // Opening of new trades is disabled if AutoTrading is disabled.
   if (AutoTradingAll){
      if (!IsExpertEnabled()){
         SetStatusMessage("warning", LiveTradingDisabledMsg, true);
         if ((NotifyWarning)&&(!EaWarningSent)&&(NotifyAllowed)){
            SendNotification(NotifyLiveTradingMsg);
            EaWarningSent = true;
         }
         return false;
      } else {
         if (ObjectGetString(0,"StatusMessage",OBJPROP_TEXT) == LiveTradingDisabledMsg){
            ClearStatusMessage();
            SetStatusMessage("recentStatus", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+LiveTradingDisabledMsg);
            WriteDataFile();
         }
         EaWarningSent = false;
      }
   }
   
   // Cannot trade if TDesk is not running
   if (!ReadTDeskSignals()){
      SetStatusMessage("warning", TDeskStoppedMsg, true);
      if ((NotifyWarning)&&(!TDeskWarningSent)&&(NotifyAllowed)){
         SendNotification(NotifyTDeskMsg);
         TDeskWarningSent = true;
      }
      return false;
   } else {
      if (ObjectGetString(0,"StatusMessage",OBJPROP_TEXT) == TDeskStoppedMsg){
         ClearStatusMessage();
         SetStatusMessage("recentStatus", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+TDeskStoppedMsg);
         WriteDataFile();
      }
      TDeskWarningSent = false;
   }

   // All trade activity is ceased if the Python script is not running.
   if (FileIsExist(LockFilename) != true){ // Wait for python to finish
      if (!FileIsExist(AliveFileName)){
         AliveSeconds++;
         if (AliveSeconds >= SecondsDown){
            SetStatusMessage("warning", PythonScriptMsg, true);
            if ((NotifyWarning)&&(!PythonWarningSent)&&(NotifyAllowed)){
               SendNotification(NotifyPythonMsg);
               PythonWarningSent = true;
            }
            return false;
         }
      } else {
         if (ObjectGetString(0,"StatusMessage",OBJPROP_TEXT) == PythonScriptMsg){
            ClearStatusMessage();
            SetStatusMessage("recentStatus", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+PythonScriptMsg);
            WriteDataFile();
         }
         PythonWarningSent = false;
      }
   }
   
   // Verify Python script still running by deleting the alive check file every 5 seconds   
   if (AliveTimer % 5 == 0){
      AliveTimer = 0;
      AliveSeconds = 0;
      FileDelete(AliveFileName);
   }
   AliveTimer++;

   return true;
}

//================================================//
// Plot Daily Range                               //
//================================================//
void PlotADR(){
   double adr;
   int b,c,i;
   for (i=0;i<ArraySize(PairInfo);i++) {
      b = 1;
      c = 1;
      adr = 0.0;
      while(b <= 20){
         if (TimeDayOfWeek(iTime(PairInfo[i].Pair,PERIOD_D1,c)) != 0){
            adr = adr + (iHigh(PairInfo[i].Pair,PERIOD_D1,c)-iLow(PairInfo[i].Pair,PERIOD_D1,c))/MarketInfo(PairInfo[i].Pair,MODE_POINT)/10;
            b++;
         }
         c++;
      }
      adr = adr / 20;
      PairInfo[i].ADR = adr;
   }
}

//================================================//
// Plot Pips Towards Today's Range                //
//================================================//
void PlotADRpips(){
   double fuAdrPips;
   for (int i=0;i<ArraySize(PairInfo);i++) {
      fuAdrPips = 0;
      fuAdrPips = NormalizeDouble((iHigh(PairInfo[i].Pair,PERIOD_D1,0)-iLow(PairInfo[i].Pair,PERIOD_D1,0))/MarketInfo(PairInfo[i].Pair,MODE_POINT)/10,0);
      PairInfo[i].ADRPips = fuAdrPips;
   }
}

//================================================//
// Open a Chart for the given pair/timeframe      //
//================================================//
void OpenChart(long id){
   ChartSetInteger(id,CHART_BRING_TO_TOP,0,true);   
   return;
}

//================================================//
// Clean Chart on First Open                      //
//================================================//
void CleanChart(){
   // remove any leftover objects
   for (int obj = ObjectsTotal(); obj > 0; obj--){
      ObjectDelete(ObjectName(obj));
   }
   // change chart colors
   ChartSetInteger(0,CHART_SCALE,0,5);
   ChartSetInteger(0,CHART_COLOR_GRID,0,clrNONE);
   ChartSetInteger(0,CHART_COLOR_BACKGROUND,0,clrNONE);
   ChartSetInteger(0,CHART_COLOR_FOREGROUND,0,clrGainsboro);
   ChartSetInteger(0,CHART_COLOR_CANDLE_BEAR,0,clrNONE);
   ChartSetInteger(0,CHART_COLOR_CHART_DOWN,0,clrNONE);
   ChartSetInteger(0,CHART_COLOR_CANDLE_BULL,0,clrNONE);
   ChartSetInteger(0,CHART_COLOR_CHART_UP,0,clrNONE);
   ChartSetInteger(0,CHART_COLOR_ASK,0,clrNONE);
   ChartSetInteger(0,CHART_COLOR_BID,0,clrNONE);
   ChartSetInteger(0,CHART_COLOR_CHART_LINE,0,clrNONE);
   ChartSetInteger(0,CHART_COLOR_VOLUME,0,clrNONE);
   ChartSetInteger(0,CHART_COLOR_STOP_LEVEL,0,clrNONE);
   ChartSetInteger(0,CHART_COLOR_LAST,0,clrNONE);
   ChartSetInteger(0,CHART_MODE,0,0);
}

//================================================//
// Read and Write Data File                       //
//================================================//
void WritePairDataFiles(int arrID){
   int filehandle;
   string filename = "data-"+PairInfo[arrID].Pair+".txt";

   // write file
   filehandle=FileOpen("FXtrade\\"+filename,FILE_READ|FILE_WRITE|FILE_CSV,",");
   if(filehandle==INVALID_HANDLE){
      filehandle=FileOpen("FXtrade\\"+filename,FILE_READ|FILE_WRITE|FILE_CSV,",");
   }
   if(filehandle!=INVALID_HANDLE){
      FileWrite(filehandle,
         PairInfo[arrID].Signal,
         PairInfo[arrID].SignalTime,
         PairInfo[arrID].OriginalSignal,
         PairInfo[arrID].SignalChange,
         PairInfo[arrID].HedgedDirection,
         int(PairInfo[arrID].Managed)
      );
   }
   FileClose(filehandle);
}

void ReadPairDataFiles(int arrID){
   int filehandle;
   string filename = "FXtrade\\data-"+PairInfo[arrID].Pair+".txt";
   
   string SignalChange,HedgedDirection;
   TDESKSIGNALS OriginalSignal,Signal;
   datetime SignalTime;
   int Managed;
   
   if (FileIsExist(filename)){
      filehandle=FileOpen(filename,FILE_READ|FILE_CSV,",");
      
      Signal =         (TDESKSIGNALS)StrToInteger(FileReadString(filehandle));
      SignalTime =     StrToTime(FileReadString(filehandle));
      OriginalSignal = (TDESKSIGNALS)StrToInteger(FileReadString(filehandle)); 
      SignalChange =   FileReadString(filehandle);
      HedgedDirection =FileReadString(filehandle);
      Managed =        int(StringToInteger(FileReadString(filehandle))); 

      FileClose(filehandle);
      
      // only restore original signal if current signal has not changed.
      if (SignalTime == PairInfo[arrID].SignalTime){
         PairInfo[arrID].OriginalSignal = OriginalSignal;
         PairInfo[arrID].SignalChange = SignalChange;
      }
      PairInfo[arrID].HedgedDirection = HedgedDirection;
      PairInfo[arrID].Managed = Managed;
      
      PairInfo[arrID].BackupExists = true;
   } else PairInfo[arrID].BackupExists = false;
}

void WriteDataFile(){
   int filehandle;
   string filename = "data.txt";

   // write file
   filehandle=FileOpen("FXtrade\\"+filename,FILE_READ|FILE_WRITE|FILE_CSV,",");
   if(filehandle==INVALID_HANDLE){
      filehandle=FileOpen("FXtrade\\"+filename,FILE_READ|FILE_WRITE|FILE_CSV,",");
   }
   if(filehandle!=INVALID_HANDLE){
      FileWrite(filehandle,
         ObjectGetString(0,"RecentStatusMessage",OBJPROP_TEXT),
         ObjectGetString(0,"RecentTradeMessage",OBJPROP_TEXT),
         ObjectGetString(0,"RecentSignalMessage",OBJPROP_TEXT)
      );
   }
   FileClose(filehandle);
}

void ReadDataFile(){
   int filehandle;
   string filename = "FXtrade\\data.txt";
   string statusMessage,tradeMessage,signalMessage;

   if (FileIsExist(filename)){
      filehandle=FileOpen(filename,FILE_READ|FILE_CSV,",");
      
      statusMessage =FileReadString(filehandle);
      tradeMessage = FileReadString(filehandle); 
      signalMessage =FileReadString(filehandle);

      FileClose(filehandle);

      ObjectSetText("RecentStatusMessage",statusMessage,TextSize,NULL,C'68,68,68');
      ObjectSetText("RecentTradeMessage",tradeMessage,TextSize,NULL,C'68,68,68');
      ObjectSetText("RecentSignalMessage",signalMessage,TextSize,NULL,C'68,68,68');
   }
}

//================================================//
// FXtrade Bridge Functions                       //
//================================================//
// create order file
bool OpenMarketOrder(string fuInstrument, string fuSide, int fuUnits, double fuStop=0.0, double fuTarget=0.0){
   int fuFilehandle;
   bool fuOrder;
   string pair = fuInstrument;
   StringReplace(pair,"_","");
   
   //Print(TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - Open "+fuInstrument+" - "+fuSide+" - "+IntegerToString(fuUnits));
   
   string fuCommand = "openmarket-"+fuInstrument+"-"+fuSide+"-"+IntegerToString(fuUnits)+"-"+DoubleToStr(fuStop,int(MarketInfo(pair,MODE_DIGITS)))+"-"+DoubleToStr(fuTarget,int(MarketInfo(pair,MODE_DIGITS)));

   if (FileIsExist(LockFilename) != true){ // Wait for python to finish
      LockDirectory();
      fuFilehandle=FileOpen("FXtrade\\"+fuCommand,FILE_WRITE|FILE_TXT);
      if(fuFilehandle!=INVALID_HANDLE){
         FileClose(fuFilehandle);
         fuOrder = true;
      } else fuOrder = false;
      UnlockDirectory();
      Sleep(5000);
      return fuOrder;
   } return false;
}

// create close position file
bool ClosePosition(string fuInstrument, int arrID, string fuSide, int fuUnits=0){
   double profit = 0.0;
   string pair = fuInstrument;
   StringReplace(pair,"_","");

   if (fuSide == "sell") profit = PairInfo[arrID].ShortProfit;
   if (fuSide == "buy")  profit = PairInfo[arrID].LongProfit;

   //Print(TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - Close "+fuInstrument+" - "+fuSide);

   if (FileIsExist(LockFilename) != true){ // Wait for python to finish
      int fuFilehandle;
      fuFilehandle=FileOpen("FXtrade\\close-"+fuInstrument+"-"+fuSide+"-"+IntegerToString(fuUnits),FILE_WRITE|FILE_TXT);
      if(fuFilehandle!=INVALID_HANDLE){
         FileClose(fuFilehandle);
         //SendNotification("Close "+pair+" "+fuSide+": "+DoubleToStr(profit,2));
         return false;
      } else return false;
   } return false;
}

// lock directory so python does not access files
bool LockDirectory(){
   int fuFilehandle;
   fuFilehandle=FileOpen("FXtrade\\MT4-Locked",FILE_WRITE|FILE_TXT);
   if(fuFilehandle!=INVALID_HANDLE){
      FileClose(fuFilehandle);
      return true;
   } else return false;
}

// unlock directory so python can access files
bool UnlockDirectory(){
   int fuFilehandle;
   fuFilehandle=FileDelete("FXtrade\\MT4-Locked");
   if (fuFilehandle == false) return false;
      else return true;
}

//================================================//
// Draw Panel on Chart                            //
//================================================//
void SetPanel(string name,int sub_window,int x,int y,int width,int height,color bg_color,color border_clr,int border_width){
   if(ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,sub_window,0,0)){
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
      ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
      ObjectSetInteger(0,name,OBJPROP_COLOR,border_clr);
      ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,border_width);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,0);
      ObjectSetInteger(0,name,OBJPROP_SELECTED,0);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_ZORDER,0);
   }
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg_color);
  }
void ColorPanel(string name,color bg_color,color border_clr)
  {
   ObjectSetInteger(0,name,OBJPROP_COLOR,border_clr);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg_color);
  }
void SetText(string name,string text,int x,int y,color colour,int fontsize=12)
  {
   if (ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);

    ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
    ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
    ObjectSetInteger(0,name,OBJPROP_COLOR,colour);
    ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontsize);
    ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
    ObjectSetString(0,name,OBJPROP_FONT,"arial");
    ObjectSetString(0,name,OBJPROP_TEXT,text);
  }
//+------------------------------------------------------------------+
//| Create bitmap                                                    |
//+------------------------------------------------------------------+
bool BitmapCreate(const string            name,
                  const string            image,
                  const int               x=0,
                  const int               y=0,
                  const long              chart_ID=0,
                  const bool              hidden=false)
  {
//--- reset the error value
   ResetLastError();
//--- create the button
   if(!ObjectCreate(chart_ID,name,OBJ_BITMAP_LABEL,0,0,0))
     {
      Print(__FUNCTION__,
            ": failed to create the button! Error code = ",GetLastError());
      return(false);
     }
//--- set button coordinates
   ObjectSetInteger(chart_ID,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(chart_ID,name,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,name,OBJPROP_BMPFILE,0,image);
   if (hidden) ObjectSetInteger(0,name,OBJPROP_XSIZE,-1);
   return(true);
}

//+------------------------------------------------------------------+
//| Create the button                                                |
//+------------------------------------------------------------------+
bool ButtonCreate(const string            name="Button",            // button name
                  const string            text="Button",            // text
                  const int               x=0,                      // X coordinate
                  const int               y=0,                      // Y coordinate
                  const int               width=50,                 // button width
                  const int               height=22,                // button height
                  const color             clr=clrWhite,             // text color
                  const color             back_clr=clrRoyalBlue,    // background color
                  const color             border_clr=clrWhite,      // border color
                  const int               font_size=10,             // font size
                  const ENUM_BASE_CORNER  corner=CORNER_LEFT_UPPER, // chart corner for anchoring
                  const string            font="Arial",             // font
                  
                  const bool              back=false,               // in the background
                  const bool              selection=false,          // highlight to move
                  const bool              state=false,              // pressed/released
                  const long              chart_ID=0,               // chart's ID
                  const int               sub_window=0,             // subwindow index
                  const bool              hidden=true,              // hidden in the object list
                  const long              z_order=0)                // priority for mouse click
  {
//--- reset the error value
   ResetLastError();
//--- create the button
   if(!ObjectCreate(chart_ID,name,OBJ_BUTTON,sub_window,0,0))
     {
      Print(__FUNCTION__,
            ": failed to create the button! Error code = ",GetLastError());
      return(false);
     }
//--- set button coordinates
   ObjectSetInteger(chart_ID,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(chart_ID,name,OBJPROP_YDISTANCE,y);
//--- set button size
   ObjectSetInteger(chart_ID,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(chart_ID,name,OBJPROP_YSIZE,height);
//--- set the chart's corner, relative to which point coordinates are defined
   ObjectSetInteger(chart_ID,name,OBJPROP_CORNER,corner);
//--- set the text
   ObjectSetString(chart_ID,name,OBJPROP_TEXT,text);
//--- set text font
   ObjectSetString(chart_ID,name,OBJPROP_FONT,font);
//--- set font size
   ObjectSetInteger(chart_ID,name,OBJPROP_FONTSIZE,font_size);
//--- set text color
   ObjectSetInteger(chart_ID,name,OBJPROP_COLOR,clr);
//--- set background color
   ObjectSetInteger(chart_ID,name,OBJPROP_BGCOLOR,back_clr);
//--- set border color
   ObjectSetInteger(chart_ID,name,OBJPROP_BORDER_COLOR,border_clr);
//--- display in the foreground (false) or background (true)
   ObjectSetInteger(chart_ID,name,OBJPROP_BACK,back);
//--- set button state
   ObjectSetInteger(chart_ID,name,OBJPROP_STATE,state);
//--- enable (true) or disable (false) the mode of moving the button by mouse
   ObjectSetInteger(chart_ID,name,OBJPROP_SELECTABLE,selection);
   ObjectSetInteger(chart_ID,name,OBJPROP_SELECTED,selection);
//--- hide (true) or display (false) graphical object name in the object list
   ObjectSetInteger(chart_ID,name,OBJPROP_HIDDEN,hidden);
//--- set the priority for receiving the event of a mouse click in the chart
   ObjectSetInteger(chart_ID,name,OBJPROP_ZORDER,z_order);
//--- successful execution
   return(true);
}

//+------------------------------------------------------------------+
//| Button Presses                                                   |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,  const long &lparam, const double &dparam,  const string &sparam){
   string arrID;
   int i;
   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      if (StringSubstr(sparam,0,3) == "Btn"){ // this is a button, thus has an action associated with it
         // Chart Button
         if (StringSubstr(sparam,0,9) == "Btn_Chart") {
            arrID = StringSubstr(sparam,10,0);
            OpenChart(PairInfo[int(StringToInteger(arrID))].ChartId);
            //ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
            //ChartRedraw();
         }

         // Managed Button
         if (StringSubstr(sparam,0,11) == "Btn_Managed") {
            arrID = StringSubstr(sparam,12,0);
            PairInfo[int(StringToInteger(arrID))].Managed = !PairInfo[int(StringToInteger(arrID))].Managed;
            WritePairDataFiles(int(StringToInteger(arrID)));
         }

         // Buy Button
         if (StringSubstr(sparam,0,7) == "Btn_Buy") {
            arrID = StringSubstr(sparam,8,0);
            i = int(StringToInteger(arrID));
            if (AdvisorReady){
               if (ObjectGetInteger(0,"Btn_Buy_"+arrID,OBJPROP_XSIZE) > 0)
                  SendSingleTrade(PairInfo[i].Pair,i,"buy",GetLotSize(i),MarketInfo(PairInfo[i].Pair, MODE_ASK),0.0,0.0);
            } else MessageBox("Cannot open trade: "+ObjectGetString(0,"StatusMessage",OBJPROP_TEXT),"", MB_OK|MB_ICONWARNING); // Message box
         }
         
         // Sell Button
         if (StringSubstr(sparam,0,8) == "Btn_Sell") {
            arrID = StringSubstr(sparam,9,0);
            i = int(StringToInteger(arrID));
            if (AdvisorReady){
               if (ObjectGetInteger(0,"Btn_Sell_"+arrID,OBJPROP_XSIZE) > 0)
                  SendSingleTrade(PairInfo[i].Pair,i,"sell",GetLotSize(i),MarketInfo(PairInfo[i].Pair, MODE_BID),0.0,0.0);
            } else MessageBox("Cannot open trade: "+ObjectGetString(0,"StatusMessage",OBJPROP_TEXT),"", MB_OK|MB_ICONWARNING); // Message box
         }
         
         // Close Button
         if (StringSubstr(sparam,0,9) == "Btn_Close") {
            arrID = StringSubstr(sparam,10,0);
            i = int(StringToInteger(arrID));
            if (AdvisorReady){
               if (ObjectGetInteger(0,"Btn_Close_"+arrID,OBJPROP_XSIZE) > 0){
                  if (PairInfo[i].ShortTradeCount > 0) ClosePosition(PairInfo[i].FXtradeName,i,"sell");
                  if (PairInfo[i].LongTradeCount > 0) ClosePosition(PairInfo[i].FXtradeName,i,"buy");
               }
            } else MessageBox("Cannot close trade: "+ObjectGetString(0,"StatusMessage",OBJPROP_TEXT),"", MB_OK|MB_ICONWARNING); // Message box
         }
         
         // Close Short Button
         if (StringSubstr(sparam,0,15) == "Btn_Close_Short") {
            arrID = StringSubstr(sparam,16,0);
            i = int(StringToInteger(arrID));
            if (AdvisorReady){
               if (ObjectGetInteger(0,"Btn_Close_Short_"+arrID,OBJPROP_XSIZE) > 0){
                  if (PairInfo[i].ShortTradeCount > 0) ClosePosition(PairInfo[i].FXtradeName,i,"sell");
               }
            } else MessageBox("Cannot close short trade: "+ObjectGetString(0,"StatusMessage",OBJPROP_TEXT),"", MB_OK|MB_ICONWARNING); // Message box
         }
         
         // Close Long Button
         if (StringSubstr(sparam,0,14) == "Btn_Close_Long") {
            arrID = StringSubstr(sparam,15,0);
            i = int(StringToInteger(arrID));
            if (AdvisorReady){
               if (ObjectGetInteger(0,"Btn_Close_Long_"+arrID,OBJPROP_XSIZE) > 0){
                  if (PairInfo[i].LongTradeCount > 0) ClosePosition(PairInfo[i].FXtradeName,i,"buy");
               }
            } else MessageBox("Cannot close long trade: "+ObjectGetString(0,"StatusMessage",OBJPROP_TEXT),"", MB_OK|MB_ICONWARNING); // Message box
         }
         
         // Close Hedge Button
         if (StringSubstr(sparam,0,15) == "Btn_Close_Hedge") {
            arrID = StringSubstr(sparam,16,0);
            i = int(StringToInteger(arrID));
            if (AdvisorReady){
               if (ObjectGetInteger(0,"Btn_Close_Hedge_"+arrID,OBJPROP_XSIZE) > 0){
                  if (PairInfo[i].HedgedDirection == "sell") ClosePosition(PairInfo[i].FXtradeName,i,"sell");
                  if (PairInfo[i].HedgedDirection == "buy") ClosePosition(PairInfo[i].FXtradeName,i,"buy");
               }
            } else MessageBox("Cannot close hedge trade: "+ObjectGetString(0,"StatusMessage",OBJPROP_TEXT),"", MB_OK|MB_ICONWARNING); // Message box
         }
         
      } else { // this is not a button
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         ChartRedraw();
      }
      
   }
}

//================================================//
// Calculate Lot Size                             //
//================================================//
// get lot size based on chosen calculation method
int GetLotSize(int arrID){
   if(LotCalculation == FixedLotSize) return SetLotSize;
   if(LotCalculation == RiskBased) return CalculateLotSizeRisk(AccountBal,NumberOfTradesPerPair,RiskPercent,AveragePipLoss,arrID);
   if(LotCalculation == MaxLotSize) return CalculateLotSizeMax(AccountBal,NumberOfTradesPerPair,arrID);
   return 0; 
}

// Max lot size based on average pip stoploss
int CalculateLotSizeRisk(double balance, int numTradesPerPair, double riskPercent, int pips, int arrID){
   
   double Mult = 0.0;
   
   for(int i=0;i<ArraySize(PairInfo);i++){
      Mult += (PairInfo[i].USMarginRequirement * numTradesPerPair);
   }
   
   double Multiplier = 100 / Mult / 100;
   double maxMargin = NormalizeDouble((100 - PercentReserveMargin) * 0.01,2);
   balance = (balance * maxMargin) * (PairInfo[arrID].USMarginRequirement * Multiplier);
   
   // using balance rather than avail margin for use with multiple pairs.
   double TickValue = MarketInfo(PairInfo[arrID].Pair,MODE_TICKVALUE);
   double LotStep=MarketInfo(PairInfo[arrID].Pair,MODE_LOTSTEP);
   
   double SLPts=pips*MarketInfo(PairInfo[arrID].Pair,MODE_POINT)*10;
   SLPts = int(SLPts * GetPipFactor(PairInfo[arrID].Pair) * 10);

   double Exposure=SLPts*TickValue; // Exposure based on 1 full lot

   double AllowedExposure=(balance*riskPercent)/100;

   double TotalSteps = (AllowedExposure / Exposure) / LotStep;
   double Lots = TotalSteps * LotStep;

   double MinLots = MarketInfo(PairInfo[arrID].Pair,MODE_MINLOT);
   double MaxLots = MarketInfo(PairInfo[arrID].Pair,MODE_MAXLOT);
   //Print(DoubleToStr(Lots,5));
   //if(Lots < MinLots) Lots = MinLots;
   if(Lots > MaxLots) Lots = MaxLots;
   //return(Lots);
   //Print(DoubleToStr(Lots,5));
   // Added (5/PairInfo[arrID].MarginRequired) To adjust for incorrect risk calc....find real fix!
   return(int(NormalizeDouble(Lots*100000*(5/PairInfo[arrID].USMarginRequirement),0)));
}

// Max lot size
int CalculateLotSizeMax(double balance, int numTradesPerPair, int arrID){
   //double Multiplier = .067; // total of MarginRequired / 100
   
   double Mult = 0.0;
   
   for(int i=0;i<ArraySize(PairInfo);i++){
      Mult += (PairInfo[i].USMarginRequirement * numTradesPerPair);
   }
   
   if (Mult == 0) return 0;
   
   double Multiplier = 100 / Mult / 100;
   
   double leverage = 100 / PairInfo[arrID].USMarginRequirement;
   double maxMargin = NormalizeDouble((100 - PercentReserveMargin) * 0.01,2);
   double margin = (balance * maxMargin) * (PairInfo[arrID].USMarginRequirement * Multiplier);
   
   // do not use more margin than is available
   if (margin > AvailMargin) margin = (AvailMargin * 0.95)  * (PairInfo[arrID].USMarginRequirement * Multiplier);
   
   double basePrice;
   int volume;
   
   string base =  StringSubstr(PairInfo[arrID].Pair,0,3);
   string home = "USD";
   
   if (base == "USD") basePrice = 1;
   else basePrice = NormalizeDouble(MarketInfo(base+"USD",MODE_BID),int(MarketInfo(base+"USD",MODE_DIGITS)));
   
   if (basePrice == 0) basePrice = NormalizeDouble(1 / MarketInfo("USD"+base,MODE_BID),int(MarketInfo(base+"USD",MODE_DIGITS)));
   if (basePrice == 0) return -1;
   
   volume = int((margin * leverage) / basePrice);
   return volume;
}

//================================================//
// US Margin Requirements                         //
//================================================//
double GetPairMarginRequired(string Pair){
        if (Pair == "AUDCAD") return 3.0;
   else if (Pair == "AUDCHF") return 3.0;
   else if (Pair == "AUDHKD") return 5.0;
   else if (Pair == "AUDJPY") return 4.0;
   else if (Pair == "AUDNZD") return 3.0;
   else if (Pair == "AUDSGD") return 5.0;
   else if (Pair == "AUDUSD") return 3.0;
   else if (Pair == "CADCHF") return 3.0;
   else if (Pair == "CADHKD") return 5.0;
   else if (Pair == "CADJPY") return 4.0;
   else if (Pair == "CADSGD") return 5.0;
   else if (Pair == "CHFHKD") return 5.0;
   else if (Pair == "CHFJPY") return 4.0;
   else if (Pair == "CHFZAR") return 7.0;
   else if (Pair == "EURAUD") return 3.0;
   else if (Pair == "EURCAD") return 2.0;
   else if (Pair == "EURCHF") return 3.0;
   else if (Pair == "EURCZK") return 5.0;
   else if (Pair == "EURDKK") return 2.0;
   else if (Pair == "EURGBP") return 5.0;
   else if (Pair == "EURHKD") return 5.0;
   else if (Pair == "EURHUF") return 5.0;
   else if (Pair == "EURJPY") return 4.0;
   else if (Pair == "EURNOK") return 3.0;
   else if (Pair == "EURNZD") return 3.0;
   else if (Pair == "EURPLN") return 5.0;
   else if (Pair == "EURSEK") return 3.0;
   else if (Pair == "EURSGD") return 5.0;
   else if (Pair == "EURTRY") return 12.0;
   else if (Pair == "EURUSD") return 2.0;
   else if (Pair == "EURZAR") return 7.0;
   else if (Pair == "GBPAUD") return 5.0;
   else if (Pair == "GBPCAD") return 5.0;
   else if (Pair == "GBPCHF") return 5.0;
   else if (Pair == "GBPHKD") return 5.0;
   else if (Pair == "GBPJPY") return 5.0;
   else if (Pair == "GBPNZD") return 5.0;
   else if (Pair == "GBPPLN") return 5.0;
   else if (Pair == "GBPSGD") return 5.0;
   else if (Pair == "GBPUSD") return 5.0;
   else if (Pair == "GBPZAR") return 7.0;
   else if (Pair == "HKDJPY") return 5.0;
   else if (Pair == "NZDCAD") return 3.0;
   else if (Pair == "NZDCHF") return 3.0;
   else if (Pair == "NZDHKD") return 5.0;
   else if (Pair == "NZDJPY") return 4.0;
   else if (Pair == "NZDSGD") return 5.0;
   else if (Pair == "NZDUSD") return 3.0;
   else if (Pair == "SGDCHF") return 5.0;
   else if (Pair == "SGDHKD") return 5.0;
   else if (Pair == "SGDJPY") return 5.0;
   else if (Pair == "TRYJPY") return 12.0;
   else if (Pair == "USDCAD") return 2.0;
   else if (Pair == "USDCHF") return 3.0;
   else if (Pair == "USDCNH") return 5.0;
   else if (Pair == "USDCZK") return 5.0;
   else if (Pair == "USDDKK") return 2.0;
   else if (Pair == "USDHKD") return 5.0;
   else if (Pair == "USDHUF") return 5.0;
   else if (Pair == "USDJPY") return 4.0;
   else if (Pair == "USDMXN") return 8.0;
   else if (Pair == "USDNOK") return 3.0;
   else if (Pair == "USDPLN") return 5.0;
   else if (Pair == "USDSAR") return 5.0;
   else if (Pair == "USDSEK") return 3.0;
   else if (Pair == "USDSGD") return 5.0;
   else if (Pair == "USDTHB") return 5.0;
   else if (Pair == "USDTRY") return 12.0;
   else if (Pair == "USDZAR") return 7.0;
   else if (Pair == "ZARJPY") return 7.0;
   else return 0.0;
}

//================================================//
// Close All Trades                               //
//================================================//
void CloseAllTrades(){
   for(int i=0;i<ArraySize(PairInfo);i++){
      if (PairInfo[i].ShortTradeCount > 0) ClosePosition(PairInfo[i].FXtradeName,i,"sell");
      if (PairInfo[i].LongTradeCount > 0)  ClosePosition(PairInfo[i].FXtradeName,i,"buy");
   }
   return;
}

//+------------------------------------------------------------------+
//*******************************************************************|
//+------------------------------------------------------------------+
//| Desky Functions                                                  |
//|   Functions below modified from TDesk Trading Partner EA         |
//+------------------------------------------------------------------+
//*******************************************************************|
//+------------------------------------------------------------------+

bool SecureSetTimer(int seconds){
   
// **** NO MODIFICATIONS MADE TO THIS FUNCTION
// -------------------------------------------------

   //This is another brilliant idea by tomele. Many thanks Thomas. Here is the explanation:
/*
I am testing something René has developed on Eaymon's VPS as well as on Google's VPS. I ran into a problem with EventSetTimer(). 
This problem was reported by other users before and apparently occurs only on VPS's, not on desktop machines. The problem is that 
calls to EventSetTimer() eventually fail with different error codes returned. The EA stays on the chart with a smiley (it 
is not removed), but no timer events are sent to OnTimer() and the EA doesn't act anymore. 

The problem might be caused by the VPS running out of handles. A limited number of these handles is shared as a pool 
between all virtual machines running on the same host machine. The problem occurs randomly when all handles are in use 
and can be cured by repeatedly trying to set a timer until you get no error code.

I have implemented a function SecureSetTimer() that does this. If you replace EventSetTimer() calls with SecureSetTimer() 
calls in the EA code, this VPS problem will not affect you anymore:
*/
   int error=-1;
   int counter=1;
   
   do {
      EventKillTimer();
      ResetLastError();
      EventSetTimer(seconds);
      error=GetLastError();
      Print("SecureSetTimer, attempt=",counter,", error=",error);
      if(error!=0) Sleep(1000);
      counter++;
   }
   while(error!=0 && !IsStopped() && counter<100);
   
   return(error==0);
}

//+------------------------------------------------------------------+
//| Initialize Trading Hours Array                                   |
//+------------------------------------------------------------------+
bool initTradingHours() 
{
// **** NO MODIFICATIONS MADE TO THIS FUNCTION
// -------------------------------------------------

   // Called from init()
   
	// Assume 24 trading if no input found
	if ( tradingHours == "" )	
	{
		ArrayFree(tradeHours);
		return ( true );
	}

	int i;

	// Add 00:00 start time if first element is stop time
	if ( StringSubstrOld( tradingHours, 0, 1 ) == "-" ) 
	{
		tradingHours = StringConcatenate( "+0,", tradingHours );   
	}
	
	// Add delimiter
	if ( StringSubstrOld( tradingHours, StringLen( tradingHours ) - 1) != "," ) 
	{
		tradingHours = StringConcatenate( tradingHours, "," );   
	}
	
	string lastPrefix = "-";
	i = StringFind( tradingHours, "," );
	
	while (i != -1) 
	{

		// Resize array
		int size = ArraySize( tradeHours );
		ArrayResize( tradeHours, size + 1 );

		// Get part to process
		string part = StringSubstrOld( tradingHours, 0, i );

		// Check start or stop prefix
		string prefix = StringSubstrOld ( part, 0, 1 );
		if ( prefix != "+" && prefix != "-" ) 
		{
			Print("ERROR IN TRADINGHOURS INPUT (NO START OR CLOSE FOUND), ASSUME 24HOUR TRADING.");
			ArrayFree( tradeHours );
			return ( true );
		}

		if ( ( prefix == "+" && lastPrefix == "+" ) || ( prefix == "-" && lastPrefix == "-" ) )	
		{
			Print("ERROR IN TRADINGHOURS INPUT (START OR CLOSE IN WRONG ORDER), ASSUME 24HOUR TRADING.");
			ArrayFree ( tradeHours );
			return ( true );
		}
		
		lastPrefix = prefix;

		// Convert to time in minutes
		part = StringSubstrOld( part, 1 );
		double time = StrToDouble( part );
		int hour = (int)MathFloor( time );
		int minutes = (int)MathRound( ( time - hour ) * 100 );

		// Add to array
		tradeHours[size] = 60 * hour + minutes;

		// Trim input string
		tradingHours = StringSubstrOld( tradingHours, i + 1 );
		i = StringFind( tradingHours, "," );
	}//while (i != -1) 

	return ( true );
}//End bool initTradingHours() 

bool CheckTradingTimes() 
{
// **** Added message display
// -------------------------------------------------
   string TradingHoursMsg = NoTradingOutsideHours + tradingHoursDisplay;
   
   //Code by Baluda. Cheers Paul.
   
	// Trade 24 hours if no input is given
	if ( ArraySize( tradeHours ) == 0 ) return ( true );

	// Get local time in minutes from midnight
    int time = TimeHour( TimeLocal() ) * 60 + TimeMinute( TimeLocal() );
   
	// Don't you love this?
	int i = 0;
	while ( time >= tradeHours[i] ) 
	{	
		i++;		
		if ( i == ArraySize( tradeHours ) ) break;
	}
	if ( i % 2 == 1 ){
	   if (ObjectGetString(0,"StatusMessage",OBJPROP_TEXT) == TradingHoursMsg) ClearStatusMessage();
	   return ( true );
	} else {
	   SetStatusMessage("message", TradingHoursMsg);
	   return ( false );
	}
}//End bool CheckTradingTimes2() 


bool SundayMondayFridayStuff()
{
// **** Changed OpenTrades to NumOpenTrades
// **** Added message display
// **** Removed open trade == 0 for FridayStopTradingHour
// **** Add message for stop trading property
// **** Modified FridayCloseAllHour to actually close all trades
// **** Modified FridayStopTradingHour to also display a message on Saturday
// **** Changed logic so that trading hour for Monday is only considered if trading is not allowed on Sunday
// -------------------------------------------------

   string FridayHour    = NoTradingFridayStop + IntegerToString(FridayStopTradingHour) + ":00";
   string SaturdayHour  = NoTradingSaturdayStop + IntegerToString(SaturdayStopTradingHour) + ":00";
   string MondayHour    = NoTradingMondayStart + IntegerToString(MondayStartHour) + ":00";
   
   //Friday/Saturday stop trading hour
   int d = TimeDayOfWeek(TimeLocal());
   int h = TimeHour(TimeLocal());
   
   // AutoTrading
   if (!AutoTradingAll){
      // Opening of new trades is disabled if AutoTrading is disabled.
      if (!IsExpertEnabled()){
         SetStatusMessage("message", NoTradingAutoTrading);
         return(false);
      } else if (ObjectGetString(0,"StatusMessage",OBJPROP_TEXT) == NoTradingAutoTrading) ClearStatusMessage();
   }
   
   //This snippet courtesy of 1of3. Many thanks, John.
   if (d == 5 && h >= FridayCloseAllHour && NumOpenTrades > 0)
   {
      if (d == 5) SetStatusMessage("message", FridayCloseAll);
      
      double fridayProfit = CurrentProfit;
      CloseAllTrades();
      
      //Send notification of friday closure
      if ((NotifyWarning)&&(NotifyAllowed)) SendNotification(NotifyFridayCloseAll+DoubleToStr(CurrentProfit,2));
      
      Sleep(5000);

      // move warning message to recent status message
      SetStatusMessage("recentStatus", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+FridayCloseAll);
      
      // clear warning message
      ClearStatusMessage();
      
      return(false);
   } else {
      if (ObjectGetString(0,"StatusMessage",OBJPROP_TEXT) == FridayCloseAll) ClearStatusMessage();
   }

   if ((d == 5)||(d == 6))
   {
      if ((h >= FridayStopTradingHour)||(FridayStopTradingHour < 24 && d == 6)){
         
         // if (NumOpenTrades == 0) Do we really want to not manage open trades while the market is still open?
         SetStatusMessage("message", FridayHour);
         return(false);
      }
   } else if (ObjectGetString(0,"StatusMessage",OBJPROP_TEXT) == FridayHour) ClearStatusMessage();
   
   if (d == 4)
   {
      if (!TradeThursdayCandle){
         SetStatusMessage("message", NoTradingThursday);
         return(false);
      }
   } else if (ObjectGetString(0,"StatusMessage",OBJPROP_TEXT) == NoTradingThursday) ClearStatusMessage();
        
   
   if (d == 6)
   {
      if (h >= SaturdayStopTradingHour){
         SetStatusMessage("message", SaturdayHour);
         return(false);
      }
   } else if (ObjectGetString(0,"StatusMessage",OBJPROP_TEXT) == SaturdayHour) ClearStatusMessage();
  
   //Sunday candle
   if (d == 0)
   {
      if (!TradeSundayCandle){
         SetStatusMessage("message", NoTradingSunday);
         return(false);
      }
   } else if (ObjectGetString(0,"StatusMessage",OBJPROP_TEXT) == NoTradingSunday) ClearStatusMessage();
   
   //Monday start hour if trading is not allowed on Sunday
   if ((d == 1)&&(!TradeSundayCandle)){
      if (h < MondayStartHour){     
         SetStatusMessage("message", MondayHour);
         return(false);
      }
   } else if (ObjectGetString(0,"StatusMessage",OBJPROP_TEXT) == MondayHour) ClearStatusMessage();
   
   //Got this far, so we are in a trading period
   return(true);      
   
}//End bool  SundayMondayFridayStuff()

// for 6xx build compatibilità added by milanese
string StringSubstrOld(string x,int a,int b=-1) 
{
// **** NO MODIFICATIONS MADE TO THIS FUNCTION
// -------------------------------------------------
   if(a<0) a=0; // Stop odd behaviour
   if(b<=0) b=-1; // new MQL4 EOL flag
   return StringSubstr(x,a,b);
}

void MarginLevelShutdown(string direction="all")
{
// **** removed mql4 order closing
// **** set closure based on TreatAccountsAsCombined setting
// **** warning display and notification
// -------------------------------------------------
   
   //Warn message for margin closure
   if (direction == "short") SetStatusMessage("warning", MarginLevelShort);
   else if (direction == "long") SetStatusMessage("warning", MarginLevelLong);
   else SetStatusMessage("warning", MarginLevelAll);
   
   //Attempts to close/delete all trades on the platform, regardless of their origin
   for(int i=0;i<ArraySize(PairInfo);i++){
      if (!TreatAccountsAsCombined){
         if (PairInfo[i].ShortTradeCount > 0) ClosePosition(PairInfo[i].FXtradeName,i,"sell");
         if (PairInfo[i].LongTradeCount > 0)  ClosePosition(PairInfo[i].FXtradeName,i,"buy");
      } else {
         if ((direction == "short" || direction == "all")&&(PairInfo[i].ShortTradeCount > 0)) ClosePosition(PairInfo[i].FXtradeName,i,"sell");
         if ((direction == "long"  || direction == "all")&&(PairInfo[i].LongTradeCount > 0))  ClosePosition(PairInfo[i].FXtradeName,i,"buy");
      }
   }
   
   //Send notification of margin closure
   if ((NotifyWarning)&&(NotifyAllowed)){
      if (direction == "short") SendNotification(NotifyMarginShort);
      else if (direction == "long") SendNotification(NotifyMarginLong);
      else SendNotification(NotifyMarginAll);
   }
   
   // wait 5 seconds
   Sleep(5000);
   
   // move warning message to recent status message
   if (direction == "short") SetStatusMessage("recentStatus", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+MarginLevelShort);
   else if (direction == "long") SetStatusMessage("recentStatus", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+MarginLevelLong);
   else SetStatusMessage("recentStatus", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+MarginLevelAll);
   
   // clear warning message
   ClearStatusMessage();
   
}//End void MarginLevelShutdown()

string MarginPercentClosure()
{
// **** changed OrdersTotal()   to NumOpenTrades
//              AccountMargin() to UsedMargin
//              AccountEquity() to AcctEquity
//              AccountProfit() to CurrentProfit
// **** modified function to work with separate long and short accounts
// **** for simplicity changed return value so do not have to check again in marginlevelshutdown 
// -------------------------------------------------
   //No trades open
   if (NumOpenTrades == 0) return("none");
   if (UsedMargin == 0)    return("none");
   
   //Returns 'true' if the margin level has dropped below
   //CloseBelowMarginLevel and the profit is acceptable, else returns 'false'

   if ((MarginLevel < CloseBelowMarginLevel)&&(MarginLevel > 0)){
      //Cash target
      if (!CloseEnough(AcceptableProfitCash, 0)){
         if (CurrentProfit >= AcceptableProfitCash) return("all");
      }
      //Pips target
      if (AcceptableProfitPips != 0){
         if (CurrentPips >= AcceptableProfitPips) return("all");
      }
   }
   
   if ((ShortMarginLevel < CloseBelowMarginLevel)&&(ShortUsedMargin > 0)){
      //Cash target
      if (!CloseEnough(AcceptableProfitCash, 0)){
         if (ShortAccountProfit >= AcceptableProfitCash){
            if (TreatAccountsAsCombined) return("all");
            else return("short");
         }
      }
      //Pips target
      if (AcceptableProfitPips != 0){
         if (ShortAccountPips >= AcceptableProfitPips){
            if (TreatAccountsAsCombined) return("all");
            else return("short");
         }
      }
   }
   
   if ((LongMarginLevel < CloseBelowMarginLevel)&&(LongUsedMargin > 0)){
      //Cash target
      if (!CloseEnough(AcceptableProfitCash, 0)){
         if (LongAccountProfit >= AcceptableProfitCash){
            if (TreatAccountsAsCombined) return("all");
            else return("long");
         }
      }
      //Pips target
      if (AcceptableProfitPips != 0){
         if (LongAccountPips >= AcceptableProfitPips){
            if (TreatAccountsAsCombined) return("all");
            else return("long");
         }
      }
   }
   //Got here, so no closure
   return("none");

}//bool MarginPercentClosure()

bool CloseEnough(double num1,double num2)
{
// **** NO MODIFICATIONS MADE TO THIS FUNCTION
// -------------------------------------------------
/*
   This function addresses the problem of the way in which mql4 compares doubles. It often messes up the 8th
   decimal point.
   For example, if A = 1.5 and B = 1.5, then these numbers are clearly equal. Unseen by the coder, mql4 may
   actually be giving B the value of 1.50000001, and so the variable are not equal, even though they are.
   This nice little quirk explains some of the problems I have endured in the past when comparing doubles. This
   is common to a lot of program languages, so watch out for it if you program elsewhere.
   Gary (garyfritz) offered this solution, so our thanks to him.
   */

   if(num1==0 && num2==0) return(true); //0==0
   if(MathAbs(num1 - num2) / (MathAbs(num1) + MathAbs(num2)) < 0.00000001) return(true);

//Doubles are unequal
   return(false);

}//End bool CloseEnough(double num1, double num2)

double CalculatePipsOnPlatform()
{
// **** replace with CurrentPips.  No need to calculate pips on platform
// -------------------------------------------------
   //Returns the total number of pips for all trades on the platform, regardless
   //of their origin.
   
   return CurrentPips;
   
}//double CalculatePipsOnPlatform()

bool ShirtProtection()
{
// **** replace with AccountProfit() with CurrentProfit
// **** changed type to bool to get a return value
// -------------------------------------------------

   // Code for this routine is based on code in CloseOrders_After_Account_Loss_TooMuch.mq4
   // by Tradinator, so my appreciation to Tradinator.
   
   if (CloseEnough(MaxLoss, 0) ) return(false); // Idiotic user entry
  
   if (CurrentProfit<= MaxLoss)
   {
      Alert("Disaster has happened. Your shirt protection loss point has been reached and all open orders have been closed.");
      Print ("All Open Trades Have Been Closed - Shirt protection loss point reached");
       
      //Warn message for margin closure
      SetStatusMessage("warning", ShirtProtectionHit);
      
      //Attempts to close/delete all trades on the platform, regardless of their origin
      for(int i=0;i<ArraySize(PairInfo);i++){
         if (PairInfo[i].ShortTradeCount > 0) ClosePosition(PairInfo[i].FXtradeName,i,"sell");
         if (PairInfo[i].LongTradeCount > 0)  ClosePosition(PairInfo[i].FXtradeName,i,"buy");
      }
      
      //Send notification of margin closure
      if ((NotifyWarning)&&(NotifyAllowed)){
         SendNotification(NotifyShirtProtection);
      }
      
      // move shirtprotection warning to recent status
      SetStatusMessage("recentStatus", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+ShirtProtectionHit);
      
      // wait 5 seconds
      Sleep(5000);
      
      // clear warning message
      ClearStatusMessage();
      
      return(true);
      
   }//if (AccountProfit()<= MaxLoss)
   
   return(false);

}//End of ShirtProtection()

void GetBasics(string symbol)
{
// **** NO MODIFICATIONS MADE TO THIS FUNCTION
// -------------------------------------------------
   //Sets up bid, ask, digits, factor for the passed pair
   bid = MarketInfo(symbol, MODE_BID);
   ask = MarketInfo(symbol, MODE_ASK);
   digits = (int)MarketInfo(symbol, MODE_DIGITS);
   factor = GetPipFactor(symbol);
   longSwap = MarketInfo(symbol, MODE_SWAPLONG);
   shortSwap = MarketInfo(symbol, MODE_SWAPSHORT);
}//End void GetBasics(string symbol)

//Thomas and Rene provided this pip factor function. Thanks guys.
//There is also a contribution by lifesys, who gave us the first ever
//incarnation of this.
double GetPipFactor(string symbolName)
{
// **** NO MODIFICATIONS MADE TO THIS FUNCTION
// -------------------------------------------------
   static bool brokerDigitsKnown=false;
   static int  brokerDigits=0;
 
   // We want the additional pip digits of the broker (only once)
   if(!brokerDigitsKnown)
   {  
      // Try to get the broker digits for plain EURUSD
      brokerDigits=(int)SymbolInfoInteger("EURUSD",SYMBOL_DIGITS)-4;
      
      // If plain EURUSD was found, we take that
      if(brokerDigits>=0)
         brokerDigitsKnown=true;
         
      // If plain EURUSD not found, we take the most precise of all symbols containing EURUSD 
      else
      {
         brokerDigits=0;
         
         // Cycle through all symbols
         for(int i=0; i<SymbolsTotal(false); i++) 
         {
            string symName=SymbolName(i,false);
            if(StringFind(symName,"EURUSD")>=0)
               brokerDigits=MathMax(brokerDigits,(int)SymbolInfoInteger(symName,SYMBOL_DIGITS)-4);
         }
         
         brokerDigitsKnown=true;
      }
   }

   // Now we can calculate the pip factor for the symbol
   double symbolDigits = (int) SymbolInfoInteger(symbolName,SYMBOL_DIGITS);
   double symbolFactor=MathPow(10,symbolDigits-brokerDigits);
   
   return(symbolFactor);
}//End int getPipFactor(string symbolName)

bool ShouldWeHedge(string symbol, int pairIndex)
{
// **** Modified to work with Oanda and removed unecessary operations
// -------------------------------------------------

   //Calculate and send a hedge trade if necessary
   
   bool sendHedge = false;
   string hedgeType = "";
   int hedgeLotSize = 0;
   double price = 0;
   
   //If required interval between hedge trades has not been met return
   if (PairInfo[pairIndex].HedgeTime + TimeBetweenHedgeTrades < int(GetTickCount() * 0.001)) return false;
   
   //Buys
   if (PairInfo[pairIndex].LongTradeCount > 0)
   {
      //SHORT
      if (HedgeOnOppositeDirectionSignal)
         if (PairInfo[pairIndex].Signal == SHORT)
         {
            sendHedge = true;
            hedgeType = "short";
            hedgeLotSize = int((PairInfo[pairIndex].LongOpenLotsize * PercentageToHedge) / 100);       
         }//if (TDeskSignals[pairIndex] == SHORT)
         
      if (HedgeOnFlatSignal)
         if (PairInfo[pairIndex].Signal == FLAT)
         {
            sendHedge = true;
            hedgeType = "short";
            hedgeLotSize = int((PairInfo[pairIndex].LongOpenLotsize * PercentageToHedge) / 100);       
         }//if (TDeskSignals[pairIndex] == FLAT)
         
      if (sendHedge)
      {
         hedgeIsSell = true;
      }//if (sendHedge)
         
   }//if (BuyOpen)

   //Sells
   if (PairInfo[pairIndex].ShortTradeCount > 0)
   {
      //LONG
      if (HedgeOnOppositeDirectionSignal)
         if (PairInfo[pairIndex].Signal == LONG)
         {
            sendHedge = true;
            hedgeType = "long";
            hedgeLotSize = int((PairInfo[pairIndex].ShortOpenLotsize * PercentageToHedge) / 100); 
         }//if (TDeskSignals[pairIndex] == LONG)
         
      if (HedgeOnFlatSignal)
         if (PairInfo[pairIndex].Signal == FLAT)
         {
            sendHedge = true;
            hedgeType = "long";
            hedgeLotSize = int((PairInfo[pairIndex].ShortOpenLotsize * PercentageToHedge) / 100);
         }//if (TDeskSignals[pairIndex] == FLAT)
         
      if (sendHedge)
      {
         hedgeIsBuy = true;
      }//if (sendHedge)
      
   }//if (SellOpen)
   
   
   
   if (sendHedge)
   {
      // if autotrading button is pressed and AutoTradingAll is false do not open new trade.
      if (!AutoTradingAll && !IsExpertEnabled()) return(false);
      
      if ((MinMarginLevelToTrade > 0)&&(MarginLevel > 0)&&(MarginLevel < MinMarginLevelToTrade)) return false; // margin level too low to open any trade
      
      if (hedgeType == "short"){
         if ((MinMarginLevelToTrade > 0)&&(ShortMarginLevel > 0)&&(ShortMarginLevel < MinMarginLevelToTrade)) return false; // margin level too low to open short trade
         
         if (OpenMarketOrder(PairInfo[pairIndex].FXtradeName, "sell", hedgeLotSize)){
            PairInfo[pairIndex].HedgedDirection = "sell";
            SetStatusMessage("trade", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+PairInfo[pairIndex].Pair+" - Open Short Hedge - "+IntegerToString(hedgeLotSize)+" Units");
            if ((NotifyTradeOpen)&&(NotifyAllowed)) SendNotification(PairInfo[pairIndex].Pair+" - Open Short Hedge");
            WriteDataFile();
            WritePairDataFiles(pairIndex);
            return true;
         }
      }
      if (hedgeType == "long"){
         if ((MinMarginLevelToTrade > 0)&&(LongMarginLevel > 0)&&(LongMarginLevel < MinMarginLevelToTrade)) return false; // margin level too low to open long trade
         
         if (OpenMarketOrder(PairInfo[pairIndex].FXtradeName, "buy",  hedgeLotSize)){
            PairInfo[pairIndex].HedgedDirection = "buy";
            SetStatusMessage("trade", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+PairInfo[pairIndex].Pair+" - Open Long Hedge - "+IntegerToString(hedgeLotSize)+" Units");
            if ((NotifyTradeOpen)&&(NotifyAllowed)) SendNotification(PairInfo[pairIndex].Pair+" - Open Long Hedge");
            WriteDataFile();
            WritePairDataFiles(pairIndex);
            return true;
         }
      }
   }//if (sendHedge)
   return false;

}//End void ShouldWeHedge(string symbol, int pairIndex)

bool CanWeRemoveTheHedge(string symbol, int pairIndex)
{
// **** Modified to work with Oanda and removed unecessary operations
// -------------------------------------------------
   //Remove a hedge trade on a change of signal.
   string closeTrade = "none";

   //Close original trade and keep hedge if in profit and signal agrees
   if (MaintainHedgeOnConfirmedSignal){
      if (PairInfo[pairIndex].HedgedDirection == "buy"){
         if ((PairInfo[pairIndex].Signal == LONG)&&(PairInfo[pairIndex].LongProfit > 0)){
            if (PairInfo[pairIndex].ShortTradeCount > 0){
               messageLotSize = PairInfo[pairIndex].ShortOpenLotsize;
               if (ClosePosition(PairInfo[pairIndex].FXtradeName,pairIndex,"sell")){
                  SetStatusMessage("trade", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+PairInfo[pairIndex].Pair+" - Reverse Hedge - "+IntegerToString(messageLotSize)+" Units");
                  if ((NotifyTradeClose)&&(NotifyAllowed)) SendNotification(PairInfo[pairIndex].Pair+" - Reverse Hedge");
                  PairInfo[pairIndex].HedgedDirection = "none";
                  PairInfo[pairIndex].HedgeTime = int(GetTickCount() * 0.001);
                  WriteDataFile();
                  WritePairDataFiles(pairIndex);
                  return true;
               }
            }
         }
      }
      
      if (PairInfo[pairIndex].HedgedDirection == "sell"){
         if ((PairInfo[pairIndex].Signal == SHORT)&&(PairInfo[pairIndex].ShortProfit > 0)){
            if (PairInfo[pairIndex].LongTradeCount > 0){
               messageLotSize = PairInfo[pairIndex].LongOpenLotsize;
               if (ClosePosition(PairInfo[pairIndex].FXtradeName,pairIndex,"buy")){
                  SetStatusMessage("trade", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+PairInfo[pairIndex].Pair+" - Reverse Hedge - "+IntegerToString(messageLotSize)+" Units");
                  if ((NotifyTradeClose)&&(NotifyAllowed)) SendNotification(PairInfo[pairIndex].Pair+" - Reverse Hedge");
                  PairInfo[pairIndex].HedgedDirection = "none";
                  PairInfo[pairIndex].HedgeTime = int(GetTickCount() * 0.001);
                  WriteDataFile();
                  WritePairDataFiles(pairIndex);
                  return true;
               }
            }
         }
      }
   }

   //Buy hedge 
   if (PairInfo[pairIndex].HedgedDirection == "buy")
   {
      //SHORT      
      if (CloseHedgeOnOppositeSignal)
         if (PairInfo[pairIndex].Signal == SHORT)
            closeTrade = "buy";

   }//if (hedgeIsBuy)
   
   //Sell hedge 
   if (PairInfo[pairIndex].HedgedDirection == "sell")
   {
           
      //SHORT      
      if (CloseHedgeOnOppositeSignal)
         if (PairInfo[pairIndex].Signal == LONG)
            closeTrade = "sell";

   }//if (hedgeIsSell)
   
   if (closeTrade == "buy"){
      if (PairInfo[pairIndex].LongTradeCount > 0){
         messageLotSize = PairInfo[pairIndex].LongOpenLotsize;
         if (ClosePosition(PairInfo[pairIndex].FXtradeName,pairIndex,"buy")){
            SetStatusMessage("trade", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+PairInfo[pairIndex].Pair+" - Close Long Hedge - "+IntegerToString(messageLotSize)+" Units");
            if ((NotifyTradeClose)&&(NotifyAllowed)) SendNotification(PairInfo[pairIndex].Pair+" - Close Long Hedge");
            PairInfo[pairIndex].HedgedDirection = "none";
            WriteDataFile();
            WritePairDataFiles(pairIndex);
            return true;
         }
      }
   }
   if (closeTrade == "sell"){
      if (PairInfo[pairIndex].ShortTradeCount > 0){
         messageLotSize = PairInfo[pairIndex].ShortOpenLotsize;
         if (ClosePosition(PairInfo[pairIndex].FXtradeName,pairIndex,"sell")){
            SetStatusMessage("trade", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+PairInfo[pairIndex].Pair+" - Close Short Hedge - "+IntegerToString(messageLotSize)+" Units");
            if ((NotifyTradeClose)&&(NotifyAllowed)) SendNotification(PairInfo[pairIndex].Pair+" - Close Short Hedge");
            PairInfo[pairIndex].HedgedDirection = "none";
            WriteDataFile();
            WritePairDataFiles(pairIndex);
            return true;
         }
      }
   }
   
   return false;

}//End void CanWeRemoveTheHedge(string symbol, int pairIndex)

bool LookForTradingOpportunities(string symbol, int pairIndex, string type)
{
// **** Incremental lot sizing set to increment plus number of trades
// -------------------------------------------------
   
   GetBasics(symbol);
   double take = 0, stop = 0, price = 0;
   bool SendTrade = false, result = false;

   int SendLots = GetLotSize(pairIndex);
   if (UseIncrementalLotSizing){
      if (type == "sell"){
         SendLots = int(GetLotSize(pairIndex) + (LotIncrement * PairInfo[pairIndex].ShortTradeCount));
      } else if (type == "buy"){
         SendLots = int(GetLotSize(pairIndex) + (LotIncrement * PairInfo[pairIndex].LongTradeCount));
      }
   }

   //Check filters
   if (!IsTradingAllowed(symbol, pairIndex) ) return(false);
   
   /////////////////////////////////////////////////////////////////////////////////////
   
   //Trading decision.
   bool SendLong = false, SendShort = false;

   //Long trade
   
   //Specific system filters
   if (BuySignal)
      SendLong = true;
   
   //Usual filters
   if (SendLong)
   {
      if (UseZeljko && !BalancedPair(symbol, "buy") ) return(false);
      
   }//if (SendLong)
   /////////////////////////////////////////////////////////////////////////////////////

   if (!SendLong)
   {
      //Short trade
      //Specific system filters
      if (SellSignal) 
         SendShort = true;
      
      if (SendShort)
      {      
         //Usual filters

         //Other filters
           
         if (UseZeljko && !BalancedPair(symbol, "sell") ) return(false);
         
      }//if (SendShort)
      
   }//if (!SendLong)
     

////////////////////////////////////////////////////////////////////////////////////////
   
   
   //Long 
   if (SendLong)
   {
       
      price = NormalizeDouble(MarketInfo(symbol, MODE_ASK), digits);
      
      //Immediate market trade need no further adjustment
         
      stop = CalculateStopLoss(symbol, "buy", price);
         
      take = CalculateTakeProfit(symbol, "buy", price);

      //Lot size calculated by risk
      if (!CloseEnough(RiskPercent, 0)) SendLots = CalculateLotSize(symbol, price, stop, pairIndex );

      SendTrade = true;
      
   }//if (SendLong)
   
   //Short
   if (SendShort)
   {
      
      price = NormalizeDouble(MarketInfo(symbol, MODE_BID), digits);


      //Immediate market trade need no further adjustment
      
      stop = CalculateStopLoss(symbol, "sell", price);
         
      take = CalculateTakeProfit(symbol, "sell", price);

      //Lot size calculated by risk
      if (!CloseEnough(RiskPercent, 0)) SendLots = CalculateLotSize(symbol, price, stop, pairIndex);
         
      SendTrade = true;      
   
      
   }//if (SendShort)
   

   if (SendTrade)
   {
      // if autotrading button is pressed and AutoTradingAll is false do not open new trade.
      if (!AutoTradingAll && !IsExpertEnabled()) return(false);
      
      result = true;//Allow sending the grid if not sending an immediate market trade
      
      //if (SendImmediateMarketTrade)
      result = SendSingleTrade(symbol, pairIndex, type, SendLots, price, stop, take);
      
      
   }//if (SendTrade)   

   return(result);
   

}//End bool LookForTradingOpportunities(string symbol, int PairIndex)

bool IsTradingAllowed(string symbol, int pairIndex)
{
// **** read SpreadType variable
// **** 
// -------------------------------------------------
   //Returns false if any of the filters should cancel trading, else returns true to allow trading
   
   //Distance between trades for multi-trading
   GetBasics(symbol);
   
   if (BuySignal)
      if (!CheckDistanceBetweenTrades(symbol, pairIndex, ask, "buy"))
         return(false);
   
   if (SellSignal)
      if (!CheckDistanceBetweenTrades(symbol, pairIndex, bid, "sell"))
         return(false);

   //Max pairs
   if (!AreWeBelowMaxPairsThreshold())
      return(false);
      
   //Maximum spread. We do not want any trading operations  during a wide spread period
   if (PairInfo[pairIndex].SpreadType == STOPHUNT)
      return(false);
   
    
   //An individual currency can only be traded twice, so check for this
   CanTradeThisPair = true;
   if (OnlyTradeCurrencyTwice && PairInfo[pairIndex].TradeCount > 0)
   {
      IsThisPairTradable(symbol);
   }//if (OnlyTradeCurrencyTwice)
   if (!CanTradeThisPair) return(false);
   
   //Swap filter
   if (PairInfo[pairIndex].TradeCount == 0) TradeDirectionBySwap(symbol);
   

   return(true);


}//End bool IsTradingAllowed()

bool CheckDistanceBetweenTrades(string symbol, int pairIndex, double price, string type)
{
// **** same logic. rewrite
// -------------------------------------------------

   //Returns true if there is no open order within MinimumDistanceBetweenTradesPips of the 
   //proposed order open price, else returns false
   double distance;

   // there are no open trades return true
   if (type == "buy"){
      if (PairInfo[pairIndex].LongTradeCount == 0) return(true);
      
      GetBasics(symbol);
      
      distance = NormalizeDouble((ask - PairInfo[pairIndex].MaxLongOrderPrice) / MarketInfo(symbol,MODE_POINT) / 10,1);
      
      if (distance < MinimumDistanceBetweenTrades)
         return(false);//Too close, so cancel the trade      
   }
   
   if (type == "sell"){
      if (PairInfo[pairIndex].ShortTradeCount == 0) return(true);
      
      GetBasics(symbol);
            
      distance = NormalizeDouble((PairInfo[pairIndex].MinShortOrderPrice - bid) / MarketInfo(symbol,MODE_POINT) / 10,1);

      if (distance < MinimumDistanceBetweenTrades)
         return(false);//Too close, so cancel the trade
   }

   //Got this far, so OK to trade
   return(true);

}//End bool CheckDistanceBetweenTrades(string symbol, int pairIndex, double price, int type)

bool AreWeBelowMaxPairsThreshold()
{
// **** same logic. rewrite
// -------------------------------------------------
   // Returns true if there are < MaxPairsAllowedToTrade pairs trading,
   //else returns false.
   if (MaxPairsAllowedToTrade == 0) return(true);
   
   int PairsTrading = 0;
   
   // loop through all pairs
   for(int i=0;i<ArraySize(PairInfo);i++){
      if (PairInfo[i].TradeCount > 0) PairsTrading++;
   }
   
   if (PairsTrading >= MaxPairsAllowedToTrade){ //At or beyond the max, so no more trading
      // set trading message
      SetStatusMessage("message", NoTradingMaxPairs);
      return(false);
   }
   
   if (ObjectGetString(0,"StatusMessage",OBJPROP_TEXT) == NoTradingMaxPairs) ClearStatusMessage();
   
   //Got here, so ok to trade;
   return(true);
   
}//End bool AreWeBelowMaxPairsThreshold()

bool IsThisPairTradable(string symbol)
{
// **** modified orderselect loop
// -------------------------------------------------
   //Checks to see if either of the currencies in the pair is already being traded twice.
   //If not, then return true to show that the pair can be traded, else return false
   
   string c1 = StringSubstrOld(symbol, 0, 3);//First currency in the pair
   string c2 = StringSubstrOld(symbol, 3, 3);//Second currency in the pair
   int c1open = 0, c2open = 0;
   CanTradeThisPair = true;
   
   // loop through all pairs
   for(int i=0;i<ArraySize(PairInfo);i++){
      if (PairInfo[i].Pair == symbol) continue;//We can allow multiple trades on the same symbol
      // check pairs that have open trades
      if (PairInfo[i].TradeCount > 0){
         int index = StringFind(PairInfo[i].Pair, c1);
            if (index > -1) c1open++;
         index = StringFind(OrderSymbol(), c2);
            if (index > -1) c2open++;
         if (c1open > 1 || c2open > 1){
            CanTradeThisPair = false;
            return(false);   
         }
      }
   }

   //Got this far, so ok to trade
   return(true);
   
}//End bool IsThisPairTradable()

void TradeDirectionBySwap(string symbol)
{
// **** NO MODIFICATIONS MADE TO THIS FUNCTION
// -------------------------------------------------

   //Sets TradeLong & TradeShort according to the positive/negative swap it attracts

   //Swap is read in init() and AutoTrading()

   TradeLong = true;
   TradeShort = true;
   
   if (CadPairsPositiveOnly)
   {
      if (StringSubstrOld(symbol, 0, 3) == "CAD" || StringSubstrOld(symbol, 0, 3) == "cad" || StringSubstrOld(symbol, 3, 3) == "CAD" || StringSubstrOld(symbol, 3, 3) == "cad" )      
      {
         if (longSwap > 0) TradeLong = true;
         else TradeLong = false;
         if (shortSwap > 0) TradeShort = true;
         else TradeShort = false;         
      }//if (StringSubstrOld()      
   }//if (CadPairsPositiveOnly)
   
   if (AudPairsPositiveOnly)
   {
      if (StringSubstrOld(symbol, 0, 3) == "AUD" || StringSubstrOld(symbol, 0, 3) == "aud" || StringSubstrOld(symbol, 3, 3) == "AUD" || StringSubstrOld(symbol, 3, 3) == "aud" )      
      {
         if (longSwap > 0) TradeLong = true;
         else TradeLong = false;
         if (shortSwap > 0) TradeShort = true;
         else TradeShort = false;         
      }//if (StringSubstrOld()      
   }//if (AudPairsPositiveOnly)
   
   
   if (NzdPairsPositiveOnly)
   {
      if (StringSubstrOld(symbol, 0, 3) == "NZD" || StringSubstrOld(symbol, 0, 3) == "nzd" || StringSubstrOld(symbol, 3, 3) == "NZD" || StringSubstrOld(symbol, 3, 3) == "nzd" )      
      {
         if (longSwap > 0) TradeLong = true;
         else TradeLong = false;
         if (shortSwap > 0) TradeShort = true;
         else TradeShort = false;         
      }//if (StringSubstrOld()      
   }//if (AudPairsPositiveOnly)
   
   //OnlyTradePositiveSwap filter
   if (OnlyTradePositiveSwap)
   {
      if (longSwap < 0) TradeLong = false;
      if (shortSwap < 0) TradeShort = false;      
   }//if (OnlyTradePositiveSwap)
   
   //MaximumAcceptableNegativeSwap filter
   if (longSwap < MaximumAcceptableNegativeSwap) TradeLong = false;
   if (shortSwap < MaximumAcceptableNegativeSwap) TradeShort = false;      


}//void TradeDirectionBySwap()

bool BalancedPair(string symbol, string type)
{
// **** changed type argument to string
// **** removed pending order logic
// **** modified orderselect loop
// -------------------------------------------------

   //Only allow an individual currency to trade if it is a balanced trade
   //e.g. UJ Buy open, so only allow Sell xxxJPY.
   //The passed parameter is the proposed trade, so an existing one must balance that

   //This code courtesy of Zeljko (zkucera) who has my grateful appreciation.
   
   string BuyCcy1, SellCcy1, BuyCcy2, SellCcy2;

   if (type == "buy")
   {
      BuyCcy1 = StringSubstrOld(symbol, 0, 3);
      SellCcy1 = StringSubstrOld(symbol, 3, 3);
   }//if (type == OP_BUY || type == OP_BUYSTOP)
   else
   {
      BuyCcy1 = StringSubstrOld(symbol, 3, 3);
      SellCcy1 = StringSubstrOld(symbol, 0, 3);
   }//else

      // loop through all pairs
   for(int i=0;i<ArraySize(PairInfo);i++){
      // check pairs that have open trades
      if (PairInfo[i].TradeCount > 0){
         if (PairInfo[i].Pair == symbol) continue;
         // get correct direction for hedged trades
         if (PairInfo[i].Hedged){
            if (PairInfo[i].HedgedDirection == "sell"){ // long trade
               BuyCcy2 =  StringSubstrOld(PairInfo[i].Pair, 0, 3);
               SellCcy2 = StringSubstrOld(PairInfo[i].Pair, 3, 3);
            }
            if (PairInfo[i].HedgedDirection == "buy"){ // short trade
               BuyCcy2 =  StringSubstrOld(PairInfo[i].Pair, 3, 3);
               SellCcy2 = StringSubstrOld(PairInfo[i].Pair, 0, 3);
            }
         } else {
            if (PairInfo[i].ShortOpenLotsize > 0){ // short trade
               BuyCcy2 =  StringSubstrOld(PairInfo[i].Pair, 3, 3);
               SellCcy2 = StringSubstrOld(PairInfo[i].Pair, 0, 3);
            }
            if (PairInfo[i].LongOpenLotsize > 0){ // long trade
               BuyCcy2 =  StringSubstrOld(PairInfo[i].Pair, 0, 3);
               SellCcy2 = StringSubstrOld(PairInfo[i].Pair, 3, 3);
            }
         }
         if (BuyCcy1 == BuyCcy2 || SellCcy1 == SellCcy2) return(false);
      }
   }

   //Got this far, so it is ok to send the trade
   return(true);

}//End bool BalancedPair(int type)

double CalculateStopLoss(string symbol, string type, double price)
{
// **** changed type argument to string
// -------------------------------------------------
   //Returns the stop loss for use in LookForTradingOpps and InsertMissingStopLoss
   
   //Code by Thomas.

   double stop = 0;

   if (type == "buy")
   {
      if (StopLossValue > 0) 
      {
         switch(SLTPCalcMode)
         {
            case FixedPips:      stop=price-StopLossValue/factor; break;
            case PriceFractions: stop=price-price*StopLossValue*0.0001; break;
            case ATRPercent:     stop=price-iATR(symbol,PERIOD_D1,14,1)*StopLossValue*0.01; break;
         }
         
         //HiddenStopLoss = stop;
      }//if (StopLossValue > 0) 

      //if (HiddenPips > 0 && stop > 0) stop = NormalizeDouble(stop - (HiddenPips / factor), Digits);
   }//if (type == OP_BUY)
   
   if (type == "sell")
   {
      if (StopLossValue > 0) 
      {
         switch(SLTPCalcMode)
         {
            case FixedPips:      stop=price+StopLossValue/factor; break;
            case PriceFractions: stop=price+price*StopLossValue*0.0001; break;
            case ATRPercent:     stop=price+iATR(symbol,PERIOD_D1,14,1)*StopLossValue*0.01; break;
         }
         
         //HiddenStopLoss = stop;         
      }//if (StopLossValue > 0) 
      
      //if (HiddenPips > 0 && stop > 0) stop = NormalizeDouble(stop + (HiddenPips / factor), Digits);

   }//if (type == OP_SELL)
   
   return(stop);
   
}//End double CalculateStopLoss(int type)

double CalculateTakeProfit(string symbol, string type, double price)
{
// **** changed type argument to string
// -------------------------------------------------
   //Returns the stop loss for use in LookForTradingOpps and InsertMissingStopLoss.
   
   //Code by Thomas.
   
   double take = 0;

   if (type == "buy")
   {
      if (TakeProfitValue > 0) 
      {
         switch(SLTPCalcMode)
         {
            case FixedPips:      take=price+TakeProfitValue/factor; break;
            case PriceFractions: take=price+price*TakeProfitValue*0.0001; break;
            case ATRPercent:     take=price+iATR(symbol,PERIOD_D1,14,1)*TakeProfitValue*0.01; break;
         }
         //HiddenTakeProfit = take;
      }//if (TakeProfitValue > 0) 

               
      //if (HiddenPips > 0 && take > 0) take = NormalizeDouble(take + (HiddenPips / factor), Digits);

   }//if (type == OP_BUY)
   
   if (type == "sell")
   {
      if (TakeProfitValue > 0) 
      {
         switch(SLTPCalcMode)
         {
            case FixedPips:      take=price-TakeProfitValue/factor; break;
            case PriceFractions: take=price-price*TakeProfitValue*0.0001; break;
            case ATRPercent:     take=price-iATR(symbol,PERIOD_D1,14,1)*TakeProfitValue*0.01; break;
         }
         //HiddenTakeProfit = take;         
      }//if (TakeProfitValue > 0) 
      
      
      //if (HiddenPips > 0 && take > 0) take = NormalizeDouble(take - (HiddenPips / factor), Digits);

   }//if (type == OP_SELL)
   
   return(take);
   
}//End double CalculateTakeProfit(int type)

int CalculateLotSize(string symbol, double price1,double price2, int pairIndex)
{
// **** modified to return units
// -------------------------------------------------
   //Calculate the lot size by risk. Code kindly supplied by jmw1970. Nice one jmw.

   if(price1==0 || price2==0) return(GetLotSize(pairIndex));//Just in case

   double FreeMargin= AvailMargin;
   double TickValue = MarketInfo(symbol,MODE_TICKVALUE);
   double LotStep=MarketInfo(symbol,MODE_LOTSTEP);

   double SLPts=MathAbs(price1-price2);
   //SLPts/=Point;//No idea why *= factor does not work here, but it doesn't
   SLPts = int(SLPts * factor * 10);//Code from Radar. Thanks Radar; much appreciated

   double Exposure=SLPts*TickValue; // Exposure based on 1 full lot

   double AllowedExposure=(FreeMargin*RiskPercent)/100;

   int TotalSteps = (int)((AllowedExposure / Exposure) / LotStep);
   double LotSize = TotalSteps * LotStep;

   double MinLots = MarketInfo(symbol, MODE_MINLOT);
   double MaxLots = MarketInfo(symbol, MODE_MAXLOT);

   if(LotSize < MinLots) LotSize = MinLots;
   if(LotSize > MaxLots) LotSize = MaxLots;
   
   return(int(NormalizeDouble(LotSize*100000,0)));

}//double CalculateLotSize(double price1, double price1)

bool SendSingleTrade(string symbol,int pairIndex,string type,int lotsize,double price,double stop,double take)
{
// **** modified to work with OpenMarketOrder function for FXTrade
// **** messages and notification
// -------------------------------------------------
   bool success;

   // margin level too low to open trades
   if ((MinMarginLevelToTrade > 0)&&(MarginLevel > 0)&&(MarginLevel < MinMarginLevelToTrade)) return false;
   if ((type == "sell")&&(ShortMarginLevel > 0)&&(MinMarginLevelToTrade > 0)&&(ShortMarginLevel < MinMarginLevelToTrade)) return false;
   if ((type == "buy") &&(LongMarginLevel > 0)&&(MinMarginLevelToTrade > 0)&&(LongMarginLevel  < MinMarginLevelToTrade)) return false;

   success = OpenMarketOrder(PairInfo[pairIndex].FXtradeName, type, lotsize, stop, take);
   
   // message and notification
   if (type == "sell"){
      SetStatusMessage("trade", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+PairInfo[pairIndex].Pair+" - Open Short Trade - "+IntegerToString(lotsize)+" Units");
      if ((NotifyTradeOpen)&&(NotifyAllowed)) SendNotification(PairInfo[pairIndex].Pair+" - Open Short Trade");
   }
   if (type == "buy"){
      SetStatusMessage("trade", TimeToStr(TimeLocal(),TIME_DATE|TIME_MINUTES)+" - "+PairInfo[pairIndex].Pair+" - Open Long Trade - "+IntegerToString(lotsize)+" Units");
      if ((NotifyTradeOpen)&&(NotifyAllowed)) SendNotification(PairInfo[pairIndex].Pair+" - Open Long Trade");
   }
   
   // backup data
   WriteDataFile();
   WritePairDataFiles(pairIndex);
   
   return(success);

}//End bool SendSingleTrade(int type, string comment, double lotsize, double price, double stop, double take)