//+------------------------------------------------------------------+
//|                                              StreakReversal.mq5  |
//|  Faithful MQL5 port of the TradingView "Streak Reversal" script   |
//|  (© Uncle_the_shooter, Pine v6).  Glow / background options are   |
//|  intentionally omitted.                                           |
//|                                                                   |
//|  Design notes                                                     |
//|   • All series are processed oldest -> newest (non-series arrays) |
//|     so Pine's x[1] == x[i-1].                                     |
//|   • Fully incremental: only bars >= prev_calculated-1 are          |
//|     recomputed on every tick.                                     |
//|   • Pine "var" state (TP/SL levels, last signals) is kept in a    |
//|     committed copy so the live bar is rolled back and re-run on   |
//|     every tick exactly like TradingView does.                     |
//|   • Chart objects are re-rendered only when their content changes.|
//|                                                                  |
//|  Original Concept & Pine Script:                                 |
//|  Author  : Uncle_the_shooter                                     |
//|  Source  : https://www.tradingview.com/script/Gk62mf6d/          |
//|  License : Mozilla Public License 2.0 (MPL 2.0)                  |
//|                                                                  |
//|  Ported to MQL5 by: AlgoToolbox.com (atoskueko)                     |
//+------------------------------------------------------------------+
#property copyright "Uncle_the_shooter (Original) / AlgoToolbox.com (atoskueko) (MQL5 Port)"
#property link      "https://algotoolbox.com/products/streak-reversal-indicator/"
#property link      "https://t.me/algotoolbox"
#property version   "1.00"
#property description "Faithful MQL5 port of TradingView Streak Reversal indicator by Uncle_the_shooter."
#property indicator_chart_window
#property indicator_buffers 12
#property indicator_plots   11

//--- plot 0 : EMA (2-colour line)
#property indicator_label1  "EMA"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrNONE,clrNONE
#property indicator_width1  3
//--- plot 1..4 : signal shapes
#property indicator_label2  "Long trend"
#property indicator_type2   DRAW_ARROW
#property indicator_label3  "Long counter"
#property indicator_type3   DRAW_ARROW
#property indicator_label4  "Short trend"
#property indicator_type4   DRAW_ARROW
#property indicator_label5  "Short counter"
#property indicator_type5   DRAW_ARROW
//--- plot 5..6 : opposite-candle circles
#property indicator_label6  "Opposite candle (long)"
#property indicator_type6   DRAW_ARROW
#property indicator_label7  "Opposite candle (short)"
#property indicator_type7   DRAW_ARROW
//--- plot 7..10 : backtester outputs (hidden)  1 = signal, EMPTY_VALUE = none
#property indicator_label8  "backtest_buy_trend"
#property indicator_type8   DRAW_NONE
#property indicator_label9  "backtest_buy_counter"
#property indicator_type9   DRAW_NONE
#property indicator_label10 "backtest_sell_trend"
#property indicator_type10  DRAW_NONE
#property indicator_label11 "backtest_sell_counter"
#property indicator_type11  DRAW_NONE

//+------------------------------------------------------------------+
//| INPUTS (same numbering / defaults as the Pine script)             |
//+------------------------------------------------------------------+
enum ENUM_SIZE3   { SZ_TINY=0, SZ_SMALL=1, SZ_NORMAL=2 };
enum ENUM_LEVEL   { LVL_BODY=0, LVL_HIGHLOW=1 };
enum ENUM_SIZEMODE{ SM_BODY=0, SM_RANGE=1 };

input group "1. Signals"
input bool   InpShowLong           = true;   // Long (after bearish streak)
input bool   InpShowShort          = true;   // Short (after bullish streak)
input bool   InpShowTrendSignals   = true;   // Trend (end of pullback)
input bool   InpShowCounterSignals = true;   // Counter-trend

input group "2. Streak"
input int    InpMinStreak      = 2;      // Min. same-color candles
input bool   InpUseAtrFilter   = true;   // Streak move filter
input double InpMinAtrMove     = 1.5;    // Min. streak move (ATR)
input int    InpAtrLenStreak   = 100;    // ATR length (streak move)

input group "3. Signal candle"
input ENUM_LEVEL    InpConfirmLevel     = LVL_BODY; // Confirmation level
input bool          InpUseOppWickFilter = true;     // Opposite wick filter
input double        InpMaxOppWickPct    = 40.0;     // Max. opposite wick (% of range)
input bool          InpUseSignalSizeFilter = false; // Candle size filter
input ENUM_SIZEMODE InpSignalSizeMode   = SM_BODY;  // Measure size as
input double        InpMinSignalSizeAtr = 0.30;     // Min. size (ATR)
input int           InpAtrLenSize       = 100;      // ATR length (candle size)

input group "4. EMA (trend)"
input int    InpEmaLen           = 100;   // EMA length
input bool   InpUseEmaMoveFilter = false; // Flat EMA filter
input int    InpEmaMoveLen       = 20;    // EMA move window (bars)
input double InpMinEmaMoveAtr    = 0.50;  // Min. EMA move (ATR)
input int    InpAtrLenEmaMove    = 100;   // ATR length (EMA move)
input double InpStrongTrendAtr   = 1.0;   // Strong trend threshold (ATR)
input double InpVStrongTrendAtr  = 2.5;   // Very strong trend threshold (ATR)

input group "5. Distance from EMA"
input bool   InpUseTrendMaxDist   = false; // Max. distance filter - trend
input double InpMaxTrendDistAtr   = 2.0;   // Max. distance from EMA (ATR)
input bool   InpUseCounterMinDist = false; // Min. distance filter - counter-trend
input double InpMinCounterDistAtr = 3.0;   // Min. distance from EMA (ATR)
input int    InpAtrLenDist        = 100;   // ATR length (EMA distance)

input group "6. Colors"
input color  InpBullColor       = C'38,166,154';  // Bullish (long / above EMA)   #26a69a
input color  InpBearColor       = C'239,83,80';   // Bearish (short / below EMA)  #ef5350
input color  InpTrendLabelCol   = clrWhite;       // Label text - trend
input color  InpCounterLabelCol = clrWhite;       // Label text - counter-trend
input color  InpTblBgCol        = C'19,23,34';    // Table - background           #131722
input color  InpTblTxtCol       = C'209,212,220'; // Table - text                 #d1d4dc
input color  InpTblHdrCol       = C'42,46,57';    // Table - header background    #2a2e39

input group "7. Display - shapes"
input bool       InpShowShapes   = false;    // Show signal shapes
input ENUM_SIZE3 InpShapeSize    = SZ_TINY;  // Shape size
input bool       InpHighlightOpp = true;     // Mark opposite candle

input group "8. Display - labels"
input bool       InpShowDistLabel  = true;     // Show labels
input ENUM_SIZE3 InpLabelSize      = SZ_SMALL; // Label size
input double     InpLabelOffsetAtr = 0.6;      // Offset from candle (x ATR)

input group "9. Display - EMA"
input bool   InpShowEma  = true;  // Show EMA
input int    InpEmaWidth = 3;     // Line width

input group "10. Table"
input bool        InpShowTable = true;         // Show table (top-left, small text)
input int         InpTableX    = 3;            // Table X offset (px from left)
input int         InpTableY    = 20;            // Table Y offset (px from top)

input group "11. TP/SL"
input bool   InpShowTargets = true;  // Show TP/SL levels
input bool   InpUseAtrSL    = true;  // ATR-based SL
input int    InpTpAtrPeriod = 14;    // ATR length (TP/SL)
input double InpSlAtrMult   = 1.5;   // SL ATR multiplier
input double InpSlPercent   = 1.0;   // SL % from entry
input double InpRrTP1       = 1.0;   // TP1 risk:reward
input double InpRrTP2       = 2.0;   // TP2 risk:reward
input double InpRrTP3       = 3.0;   // TP3 risk:reward

input group "12. TP/SL - display"
input bool   InpShowSlLevel  = true; // Show SL
input bool   InpShowTp1Level = true; // Show TP1
input bool   InpShowTp2Level = true; // Show TP2
input bool   InpShowTp3Level = true; // Show TP3

input group "13. Alerts (MT5 only)"
input bool   InpEnableAlerts     = false; // Enable alerts
input bool   InpAlertsOnBarClose = true;  // Alert on bar close only

//+------------------------------------------------------------------+
//| BUFFERS                                                           |
//+------------------------------------------------------------------+
double BufEma[], BufEmaColor[];
double BufLongTrend[], BufLongCounter[], BufShortTrend[], BufShortCounter[];
double BufOppLong[], BufOppShort[];
double BufBuyTrend[], BufBuyCounter[], BufSellTrend[], BufSellCounter[];

//+------------------------------------------------------------------+
//| WORKING SERIES (non-series, index 0 = oldest bar)                 |
//+------------------------------------------------------------------+
double gTR[];
double gAtrStreak[], gAtrSize[], gAtrEmaMove[], gAtrDist[], gAtrTP[];
double gEma[];        bool gEmaReady[];
int    gBullStreak[], gBearStreak[];
double gBearFirstHigh[], gBullFirstLow[];   // 0 == na
double gBearMoveNow[], gBullMoveNow[];      // -1 == na
double gEmaDistAtr[];                       // -1 == na
double gEmaMoveAtr[];                       // -1 == na
bool   gEmaRising[];
bool   gLongSig[], gShortSig[], gLongIsTrend[], gShortIsTrend[];
int    gArrSize = 0;

//+------------------------------------------------------------------+
//| Pine "var" state, committed after every CLOSED bar                |
//+------------------------------------------------------------------+
struct VarState
  {
   // last signals
   datetime lastLongTime;   bool lastLongTrend;
   datetime lastShortTime;  bool lastShortTrend;
   // TP/SL
   bool     tpslVisible;    // lines exist on chart
   int      tpslDir;        // 1 long, -1 short, 0 = frozen / none
   datetime tpslEntryTime;
   double   tpslEntry, tpslSL, tpslTP1, tpslTP2, tpslTP3, tpslExtreme;
   bool     tpslHasExtreme;
   datetime tpslEndTime;    // valid when tpslDir == 0 && tpslVisible
  };
VarState gCommitted;   // state after the last closed bar
VarState gS;           // working copy

//+------------------------------------------------------------------+
//| misc globals                                                      |
//+------------------------------------------------------------------+
string   gPrefix;
bool     gHeadless=false;
datetime gLastBarTime=0;
datetime gLastAlertTime=0;
datetime gLabelTimes[];            // signal-label registry (max 500, like Pine)
string   gTpslKey="";
// table cache
#define TBL_COLS 3
#define TBL_ROWS 13
string   gTblText[TBL_COLS*TBL_ROWS];
color    gTblCol [TBL_COLS*TBL_ROWS];
string   gTblTip [TBL_COLS*TBL_ROWS];
bool     gTblBuilt=false;

#define NA_NEG (-1.0)

//+------------------------------------------------------------------+
//| helpers                                                           |
//+------------------------------------------------------------------+
int    SafeLen(const int v) { return(v<1 ? 1 : v); }
string FNum(const double x) { return(x<0.0 ? "—" : DoubleToString(x,2)); }   // Pine f_num  (na -> "—")
string FmtTick(const double p){ return(DoubleToString(p,_Digits)); }
string Icon(const int st)
  {
   if(st==1) return("✓ ");
   if(st==2) return("✗ ");
   if(st==3) return("… ");
   if(st==4) return("○ ");
   return("");
  }
color  StCol(const int st)
  {
   if(st==1) return(InpBullColor);
   if(st==2) return(InpBearColor);
   if(st==3) return(clrOrange);
   return(clrGray);
  }
int FontSize3(const ENUM_SIZE3 s){ return(s==SZ_TINY ? 7 : (s==SZ_SMALL ? 8 : 10)); }
int ShapeWidth(const ENUM_SIZE3 s){ return(s==SZ_TINY ? 1 : (s==SZ_SMALL ? 2 : 3)); }

void ResetState(VarState &s)
  {
   s.lastLongTime=0; s.lastLongTrend=false; s.lastShortTime=0; s.lastShortTrend=false;
   s.tpslVisible=false; s.tpslDir=0; s.tpslEntryTime=0;
   s.tpslEntry=0; s.tpslSL=0; s.tpslTP1=0; s.tpslTP2=0; s.tpslTP3=0; s.tpslExtreme=0;
   s.tpslHasExtreme=false; s.tpslEndTime=0;
  }

void ResizeWork(const int n)
  {
   if(n==gArrSize) return;
   gArrSize=n;
   ArrayResize(gTR,n);
   ArrayResize(gAtrStreak,n); ArrayResize(gAtrSize,n); ArrayResize(gAtrEmaMove,n);
   ArrayResize(gAtrDist,n);   ArrayResize(gAtrTP,n);
   ArrayResize(gEma,n);       ArrayResize(gEmaReady,n);
   ArrayResize(gBullStreak,n);ArrayResize(gBearStreak,n);
   ArrayResize(gBearFirstHigh,n); ArrayResize(gBullFirstLow,n);
   ArrayResize(gBearMoveNow,n);   ArrayResize(gBullMoveNow,n);
   ArrayResize(gEmaDistAtr,n);    ArrayResize(gEmaMoveAtr,n); ArrayResize(gEmaRising,n);
   ArrayResize(gLongSig,n); ArrayResize(gShortSig,n); ArrayResize(gLongIsTrend,n); ArrayResize(gShortIsTrend,n);
  }

//+------------------------------------------------------------------+
//| ta.atr()  == RMA(TR, len): SMA seed, then Wilder smoothing        |
//| returns 0 while Pine would return na                              |
//+------------------------------------------------------------------+
double AtrAt(const int i,const int len,const double &atr[])
  {
   int p=SafeLen(len);
   if(i<p-1) return(0.0);
   if(i==p-1 || atr[i-1]<=0.0)
     {
      double sum=0.0;
      for(int j=i-p+1;j<=i;j++) sum+=gTR[j];
      return(sum/p);
     }
   return((atr[i-1]*(p-1)+gTR[i])/p);
  }

//+------------------------------------------------------------------+
//| object helpers (create-once, cheap updates)                       |
//+------------------------------------------------------------------+
void ObjCommon(const string nm)
  {
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
  }
void PutHLine(const string nm,const datetime t1,const datetime t2,const double p,const color c,const int w,const ENUM_LINE_STYLE st)
  {
   if(ObjectFind(0,nm)<0)
     {
      ObjectCreate(0,nm,OBJ_TREND,0,t1,p,t2,p);
      ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,nm,OBJPROP_BACK,true);    // behind the chart -> never covers the table
      ObjCommon(nm);
     }
   ObjectSetInteger(0,nm,OBJPROP_TIME,0,t1);  ObjectSetDouble(0,nm,OBJPROP_PRICE,0,p);
   ObjectSetInteger(0,nm,OBJPROP_TIME,1,t2);  ObjectSetDouble(0,nm,OBJPROP_PRICE,1,p);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,c);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,w);
   ObjectSetInteger(0,nm,OBJPROP_STYLE,st);
  }
void PutText(const string nm,const datetime t,const double p,const string txt,const color c,const int fs,const ENUM_ANCHOR_POINT a)
  {
   if(ObjectFind(0,nm)<0)
     {
      ObjectCreate(0,nm,OBJ_TEXT,0,t,p);
      ObjectSetString(0,nm,OBJPROP_FONT,"Arial");
      ObjectSetInteger(0,nm,OBJPROP_BACK,true);    // behind the chart -> never covers the table
      ObjCommon(nm);
     }
   ObjectSetInteger(0,nm,OBJPROP_TIME,0,t);
   ObjectSetDouble(0,nm,OBJPROP_PRICE,0,p);
   ObjectSetString(0,nm,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,c);
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,fs);
   ObjectSetInteger(0,nm,OBJPROP_ANCHOR,a);
  }
void DelObj(const string nm){ if(ObjectFind(0,nm)>=0) ObjectDelete(0,nm); }

//+------------------------------------------------------------------+
//| Signal labels (Pine label.new, max 500 kept)                      |
//+------------------------------------------------------------------+
string LabelName(const datetime t){ return(gPrefix+"LB_"+IntegerToString((long)t)); }

void RegisterLabel(const datetime t)
  {
   int n=ArraySize(gLabelTimes);
   if(n>0 && gLabelTimes[n-1]==t) return;          // live bar re-run
   ArrayResize(gLabelTimes,n+1); gLabelTimes[n]=t;
   if(n+1>500)
     {
      DelObj(LabelName(gLabelTimes[0]));
      ArrayRemove(gLabelTimes,0,1);
     }
  }
void UnregisterLabel(const datetime t)              // signal vanished on live bar
  {
   int n=ArraySize(gLabelTimes);
   if(n>0 && gLabelTimes[n-1]==t) ArrayResize(gLabelTimes,n-1);
   DelObj(LabelName(t));
  }

void DrawSignalLabel(const int i,const datetime &time[],const double &high[],const double &low[])
  {
   bool sig=gLongSig[i]||gShortSig[i];
   if(!InpShowDistLabel || !sig || gEmaDistAtr[i]<0.0) { UnregisterLabel(time[i]); return; }
   bool isTrend=(gLongSig[i]&&gLongIsTrend[i])||(gShortSig[i]&&gShortIsTrend[i]);
   string txt=(isTrend ? "Trend" : "Counter")+"\n"+DoubleToString(gEmaDistAtr[i],2)+" ATR";
   color  tc =isTrend ? InpTrendLabelCol : InpCounterLabelCol;
   // Pine: white text on a coloured label. OBJ_TEXT has no background, so we
   // fall back to the side colour when the text colour would be invisible.
   color  side=gLongSig[i] ? InpBullColor : InpBearColor;
   if(tc==clrWhite) tc=side;
   double off=gAtrDist[i]*InpLabelOffsetAtr;
   double p=gLongSig[i] ? low[i]-off : high[i]+off;
   PutText(LabelName(time[i]),time[i],p,txt,tc,FontSize3(InpLabelSize),gLongSig[i] ? ANCHOR_UPPER : ANCHOR_LOWER);
   RegisterLabel(time[i]);
  }

//+------------------------------------------------------------------+
//| TP/SL rendering from state                                        |
//+------------------------------------------------------------------+
void RenderTpsl(const VarState &s,const datetime lastTime)
  {
   string b=gPrefix+"TPSL_";
   if(!s.tpslVisible)
     {
      if(gTpslKey!="")
        {
         string nm[]={"ENTRY","ENTRY_L","SL","SL_L","TP1","TP1_L","TP2","TP2_L","TP3","TP3_L"};
         for(int k=0;k<ArraySize(nm);k++) DelObj(b+nm[k]);
         gTpslKey="";
        }
      return;
     }
   datetime t1=s.tpslEntryTime;
   // active: extend 12 bars past the current candle; frozen: end at the hit bar
   datetime t2=(s.tpslDir!=0) ? (datetime)(lastTime+12*PeriodSeconds(_Period)) : s.tpslEndTime;
   string key=IntegerToString((long)t1)+"|"+IntegerToString((long)t2)+"|"+DoubleToString(s.tpslEntry,_Digits)+"|"+DoubleToString(s.tpslSL,_Digits);
   if(key==gTpslKey) return;
   gTpslKey=key;
   bool L=(s.tpslEntry>s.tpslSL);           // long trade
   color ec=L ? InpBullColor : InpBearColor; // entry = side colour
   color sc=InpBearColor;                    // SL always bearish colour
   color tc=InpBullColor;                    // TP always bullish colour
   datetime lt=(datetime)(t2+PeriodSeconds(_Period));   // labels one bar right of the line end

   PutHLine(b+"ENTRY",t1,t2,s.tpslEntry,ec,2,STYLE_SOLID);
   PutText (b+"ENTRY_L",lt,s.tpslEntry,(L ? "LONG" : "SHORT"),ec,8,ANCHOR_LEFT_LOWER);
   if(InpShowSlLevel)
     {
      PutHLine(b+"SL",t1,t2,s.tpslSL,sc,1,STYLE_DASH);
      PutText (b+"SL_L",lt,s.tpslSL,"SL",sc,8,ANCHOR_LEFT_LOWER);
     }
   if(InpShowTp1Level){ PutHLine(b+"TP1",t1,t2,s.tpslTP1,tc,1,STYLE_SOLID); PutText(b+"TP1_L",lt,s.tpslTP1,"TP1",tc,8,ANCHOR_LEFT_LOWER); }
   if(InpShowTp2Level){ PutHLine(b+"TP2",t1,t2,s.tpslTP2,tc,1,STYLE_SOLID); PutText(b+"TP2_L",lt,s.tpslTP2,"TP2",tc,8,ANCHOR_LEFT_LOWER); }
   if(InpShowTp3Level){ PutHLine(b+"TP3",t1,t2,s.tpslTP3,tc,1,STYLE_DOT);   PutText(b+"TP3_L",lt,s.tpslTP3,"TP3",tc,8,ANCHOR_LEFT_LOWER); }
  }

//+------------------------------------------------------------------+
//| TABLE                                                             |
//+------------------------------------------------------------------+
string CellName(const int c,const int r){ return(gPrefix+"TBL_"+IntegerToString(c)+"_"+IntegerToString(r)); }

void TblCell(const int c,const int r,const string txt,const color col,const string tip)
  {
   int idx=c*TBL_ROWS+r;
   string nm=CellName(c,r);
   if(gTblText[idx]!=txt) { ObjectSetString(0,nm,OBJPROP_TEXT,txt); gTblText[idx]=txt; }
   if(gTblCol[idx]!=col)  { ObjectSetInteger(0,nm,OBJPROP_COLOR,col); gTblCol[idx]=col; }
   if(gTblTip[idx]!=tip)  { ObjectSetString(0,nm,OBJPROP_TOOLTIP,tip); gTblTip[idx]=tip; }
  }
void TblStCell(const int c,const int r,const int st,const string txt,const string tip,const color col=clrNONE)
  {
   TblCell(c,r,Icon(st)+txt,(col==clrNONE ? StCol(st) : col),tip);
  }

void BuildTable()
  {
   int fs=8;                                   // hard-coded: small text
   int rowH=fs*2+2;
   int colW[3]; colW[0]=fs*13; colW[1]=fs*22; colW[2]=fs*22;
   int footH=rowH+2;                                            // sleek footer bar
   int w=colW[0]+colW[1]+colW[2]+12, h=rowH*TBL_ROWS+8+footH;
   ENUM_BASE_CORNER corner=CORNER_LEFT_UPPER;  // hard-coded: top-left
   bool right=false, lower=false;
   int x0=MathMax(0,InpTableX), y0=MathMax(0,InpTableY);

   string bg=gPrefix+"TBL_BG";
   if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,x0); ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,y0);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,w);      ObjectSetInteger(0,bg,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,InpTblBgCol);
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,clrGray);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   ObjectSetInteger(0,bg,OBJPROP_ZORDER,100);
   ObjCommon(bg);
   // header / result row backgrounds
   for(int k=0;k<2;k++)
     {
      string hb=gPrefix+"TBL_HB"+IntegerToString(k);
      int r=(k==0 ? 0 : 11);
      if(ObjectFind(0,hb)<0) ObjectCreate(0,hb,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,hb,OBJPROP_CORNER,corner);
      ObjectSetInteger(0,hb,OBJPROP_XDISTANCE,x0+2);
      ObjectSetInteger(0,hb,OBJPROP_YDISTANCE,lower ? y0+4+(TBL_ROWS-1-r)*rowH : y0+4+r*rowH);
      ObjectSetInteger(0,hb,OBJPROP_XSIZE,w-4); ObjectSetInteger(0,hb,OBJPROP_YSIZE,rowH);
      ObjectSetInteger(0,hb,OBJPROP_BGCOLOR,InpTblHdrCol);
      ObjectSetInteger(0,hb,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,hb,OBJPROP_COLOR,InpTblHdrCol);
      ObjectSetInteger(0,hb,OBJPROP_BACK,false);
      ObjectSetInteger(0,hb,OBJPROP_ZORDER,101);
      ObjCommon(hb);
     }
   // --- full-width footer bar
   string fb=gPrefix+"TBL_FTB", ft=gPrefix+"TBL_FTT";
   if(ObjectFind(0,fb)<0) ObjectCreate(0,fb,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,fb,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,fb,OBJPROP_XDISTANCE,x0+2);
   ObjectSetInteger(0,fb,OBJPROP_YDISTANCE,y0+h-footH-2);
   ObjectSetInteger(0,fb,OBJPROP_XSIZE,w-4); ObjectSetInteger(0,fb,OBJPROP_YSIZE,footH);
   ObjectSetInteger(0,fb,OBJPROP_BGCOLOR,C'240,166,58');     // gold footer
   ObjectSetInteger(0,fb,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,fb,OBJPROP_COLOR,C'240,166,58');       // border same as fill -> no visible border
   ObjectSetInteger(0,fb,OBJPROP_BACK,false);
   ObjectSetInteger(0,fb,OBJPROP_ZORDER,101);
   ObjCommon(fb);
   if(ObjectFind(0,ft)<0) ObjectCreate(0,ft,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,ft,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,ft,OBJPROP_ANCHOR,ANCHOR_CENTER);
   ObjectSetInteger(0,ft,OBJPROP_XDISTANCE,x0+w/2);
   ObjectSetInteger(0,ft,OBJPROP_YDISTANCE,y0+h-2-footH/2);
   ObjectSetString(0,ft,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,ft,OBJPROP_FONTSIZE,fs);
   ObjectSetString(0,ft,OBJPROP_TEXT,"t.me/algotoolbox   •   AlgoToolbox.com");
   ObjectSetInteger(0,ft,OBJPROP_COLOR,C'19,23,34');         // dark text on gold
   ObjectSetString(0,ft,OBJPROP_TOOLTIP,"AlgoToolbox — Telegram: t.me/algotoolbox  |  Web: AlgoToolbox.com");
   ObjectSetInteger(0,ft,OBJPROP_BACK,false);
   ObjectSetInteger(0,ft,OBJPROP_ZORDER,102);
   ObjCommon(ft);

   for(int c=0;c<TBL_COLS;c++)
      for(int r=0;r<TBL_ROWS;r++)
        {
         string nm=CellName(c,r);
         if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
         int xd=x0+6;
         if(!right) { for(int q=0;q<c;q++) xd+=colW[q]; }              // distance from left edge to column start
         else       { for(int q=c+1;q<TBL_COLS;q++) xd+=colW[q]; }     // distance from right edge to column end
         int yd=lower ? y0+4+(TBL_ROWS-1-r)*rowH+2 : y0+4+r*rowH+2;
         ENUM_ANCHOR_POINT an=right ? (lower ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER)
                                    : (lower ? ANCHOR_LEFT_LOWER  : ANCHOR_LEFT_UPPER);
         ObjectSetInteger(0,nm,OBJPROP_CORNER,corner);
         ObjectSetInteger(0,nm,OBJPROP_ANCHOR,an);
         ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,xd);
         ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,yd);
         ObjectSetString(0,nm,OBJPROP_FONT,"Arial");
         ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,fs);
         ObjectSetInteger(0,nm,OBJPROP_BACK,false);
         ObjectSetInteger(0,nm,OBJPROP_ZORDER,102);
         ObjCommon(nm);
         gTblText[c*TBL_ROWS+r]=""; gTblCol[c*TBL_ROWS+r]=clrNONE; gTblTip[c*TBL_ROWS+r]="";
        }
   gTblBuilt=true;
  }

void DeleteTable()
  {
   if(!gTblBuilt) return;
   DelObj(gPrefix+"TBL_BG"); DelObj(gPrefix+"TBL_HB0"); DelObj(gPrefix+"TBL_HB1");
   DelObj(gPrefix+"TBL_FTB"); DelObj(gPrefix+"TBL_FTT");
   for(int c=0;c<TBL_COLS;c++) for(int r=0;r<TBL_ROWS;r++) DelObj(CellName(c,r));
   gTblBuilt=false;
  }

// One side of the checklist (Pine f_fillSide)
void FillSide(const int c,const bool isL,const bool enabled,const int opp,const int len,const double mv,
              const bool rightColor,const double wPct,const bool lvlOk,const double lvlPrice,
              const bool isTrendCat,const bool catOn,const bool distOk,const bool sig,
              const datetime lastTime,const bool lastTrend,
              const double candleRange,const bool signalSizeOk,const double signalSizeAtr,
              const double emaMoveAtr,const bool emaMoveOk,const bool emaRising,const double emaDistAtr,
              const double close0,const double ema0,const bool emaReady0,const int barsSinceLast)
  {
   string serName=isL ? "bearish (red)" : "bullish (green)";
   string oppName=isL ? "green" : "red";
   int nFail=0,nWait=0;
   bool noSeries=(len==0);

   // 1 streak length
   int stLen=noSeries ? 2 : (len>=InpMinStreak ? 1 : (opp==0 ? 3 : 2));
   string txtLen=noSeries ? "none" : IntegerToString(len)+" bars (min "+IntegerToString(InpMinStreak)+")";
   string tipLen=noSeries ? "There is no "+serName+" streak before the current bars." :
                 (opp==0 ? "The "+serName+" streak is still running — the current bar is part of it, so the count may still grow." :
                           "The "+serName+" streak ended "+IntegerToString(opp)+" bar(s) ago — its length is final.");
   TblStCell(c,1,stLen,txtLen,tipLen); if(stLen==2) nFail++; if(stLen==3) nWait++;

   // 2 streak move
   int stMv=!InpUseAtrFilter ? 4 : ((noSeries||mv<0.0) ? 2 : (mv>=InpMinAtrMove ? 1 : (opp==0 ? 3 : 2)));
   string txtMv=(mv<0.0 ? "—" : FNum(mv)+" ATR")+(InpUseAtrFilter ? " (min "+FNum(InpMinAtrMove)+")" : " · off");
   string tipMv="Move of the same streak as in the row above, in ATR("+IntegerToString(InpAtrLenStreak)+")."+
                (opp==0 ? "\nThe streak is still running — the move may still grow, so a value below the minimum is shown as “waiting”, not as blocking." : "");
   TblStCell(c,2,stMv,txtMv,tipMv); if(stMv==2) nFail++; if(stMv==3) nWait++;

   // 3 opposite candles
   int stOpp=noSeries ? 5 : (opp==2 ? 1 : 3);
   TblStCell(c,3,stOpp,noSeries ? "—" : IntegerToString(opp)+"/2",
             "How many "+oppName+" candles have appeared after the streak.\nA signal can only form on the close of the second one.",
             noSeries ? clrGray : clrNONE);
   if(stOpp==3) nWait++;

   // 4 level break
   int stLvl=opp==2 ? (lvlOk ? 1 : 2) : 3;
   string txtLvl=opp==2 ? (isL ? "close > " : "close < ")+FmtTick(lvlPrice) : "awaiting 2nd candle";
   string tipLvl="The close of the 2nd opposite candle must break the "+
                 (InpConfirmLevel==LVL_BODY ? (isL ? "top edge of the body" : "bottom edge of the body") : (isL ? "high" : "low"))+
                 " of the 1st opposite candle (section 3).";
   TblStCell(c,4,stLvl,txtLvl,tipLvl); if(stLvl==2) nFail++; if(stLvl==3) nWait++;

   // 5 wick
   string wickName=isL ? "upper" : "lower";
   int stWick=!rightColor ? 3 : (!InpUseOppWickFilter ? 4 : ((candleRange>0 && wPct<=InpMaxOppWickPct) ? 1 : 2));
   string txtWick=(rightColor ? DoubleToString(wPct,0)+"%" : "—")+(InpUseOppWickFilter ? " (max "+DoubleToString(InpMaxOppWickPct,0)+"%)" : " · off");
   string tipWick="The "+wickName+" wick of the CURRENT candle as % of its range.\n"+
                  (!rightColor ? "The current candle is not "+(isL ? "green" : "red")+" — not applicable." :
                   (opp==2 ? "This is the signal candle (2nd opposite) — this value is decisive." :
                             "Preview: this is not the signal candle yet — the wick of the 2nd opposite candle is decisive."));
   TblStCell(c,5,stWick,txtWick,tipWick); if(stWick==2) nFail++; if(stWick==3) nWait++;

   // 6 size
   int stSize=!rightColor ? 3 : (!InpUseSignalSizeFilter ? 4 : (signalSizeOk ? 1 : 2));
   string txtSize=(rightColor ? FNum(signalSizeAtr)+" ATR" : "—")+(InpUseSignalSizeFilter ? " (min "+FNum(InpMinSignalSizeAtr)+")" : " · off");
   string tipSize="Size of the CURRENT candle ("+(InpSignalSizeMode==SM_BODY ? "body" : "high−low range")+") in ATR("+IntegerToString(InpAtrLenSize)+").\n"+
                  (opp==2 ? "This is the signal candle — this value is decisive." : "Preview — the 2nd opposite candle is decisive.");
   TblStCell(c,6,stSize,txtSize,tipSize); if(stSize==2) nFail++; if(stSize==3) nWait++;

   // 7 flat EMA
   int stFlat=!InpUseEmaMoveFilter ? 4 : (emaMoveOk ? 1 : 2);
   string txtFlat=FNum(emaMoveAtr)+" ATR"+(InpUseEmaMoveFilter ? " (min "+FNum(InpMinEmaMoveAtr)+")" : " · off");
   TblStCell(c,7,stFlat,txtFlat,"EMA range (highest − lowest) over the last "+IntegerToString(InpEmaMoveLen)+" bars, in ATR("+IntegerToString(InpAtrLenEmaMove)+").\nShared by long and short.");
   if(stFlat==2) nFail++;

   // 8 trend strength
   bool weak=(emaMoveAtr<0.0 || emaMoveAtr<InpStrongTrendAtr);
   string strength=emaMoveAtr<0.0 ? "—" : (emaMoveAtr>=InpVStrongTrendAtr ? "very strong" : (emaMoveAtr>=InpStrongTrendAtr ? "strong" : "weak"));
   bool aligned=(isL==emaRising);
   string txtTr=(emaRising ? "↑ " : "↓ ")+strength+(weak ? " (flat)" : (aligned ? " · aligned" : " · opposed"));
   color colTr=weak ? clrGray : (aligned ? InpBullColor : clrOrange);
   TblStCell(c,8,5,txtTr,"EMA direction over a "+IntegerToString(InpEmaMoveLen)+"-bar window and strength based on the EMA move ("+FNum(emaMoveAtr)+" ATR).\nWeak < "+FNum(InpStrongTrendAtr)+" ≤ strong < "+FNum(InpVStrongTrendAtr)+" ≤ very strong.\nAligned = trend in the direction of this signal. Informational only — does not block.",colTr);

   // 9 category
   int stCat=catOn ? 1 : 2;
   string pos=(!emaReady0 ? "AT" : (close0>ema0 ? "ABOVE" : (close0<ema0 ? "BELOW" : "AT")));
   TblStCell(c,9,stCat,(isTrendCat ? "Trend" : "Counter")+(catOn ? "" : " · off"),
             "Category a "+(isL ? "long" : "short")+" signal would receive at the current close: price is "+pos+" the EMA.\n"+
             (catOn ? "This category is enabled (section 1)." : "This category is disabled in section 1 — blocking."));
   if(stCat==2) nFail++;

   // 10 distance
   bool distOn=isTrendCat ? InpUseTrendMaxDist : InpUseCounterMinDist;
   int stDist=!distOn ? 4 : (distOk ? 1 : 2);
   string txtDist=FNum(emaDistAtr)+" ATR"+(distOn ? (isTrendCat ? " (max "+FNum(InpMaxTrendDistAtr)+")" : " (min "+FNum(InpMinCounterDistAtr)+")") : " · off");
   TblStCell(c,10,stDist,txtDist,"Distance of the current bar's close from the EMA in ATR("+IntegerToString(InpAtrLenDist)+").\n"+
             (isTrendCat ? "A MAXIMUM applies to the Trend category" : "A MINIMUM applies to the Counter category")+" (section 5).");
   if(stDist==2) nFail++;

   // 11 result
   int    stArr[8]; stArr[0]=stLen; stArr[1]=stMv; stArr[2]=stLvl; stArr[3]=stWick; stArr[4]=stSize; stArr[5]=stFlat; stArr[6]=stCat; stArr[7]=stDist;
   string nmArr[8]={"streak","streak move","level break","wick","size","flat EMA","category","distance"};
   string failShort="",failAll=""; int failCnt=0;
   for(int k=0;k<8;k++)
      if(stArr[k]==2)
        {
         failAll+=(failCnt>0 ? ", " : "")+nmArr[k];
         if(failCnt<2) failShort+=(failCnt>0 ? ", " : "")+nmArr[k];
         failCnt++;
        }
   string failTxt=failShort+(failCnt>2 ? " +"+IntegerToString(failCnt-2) : "");
   int stRes=!enabled ? 4 : (sig ? 1 : (failCnt>0 ? 2 : 3));
   string txtRes=!enabled ? "off" : (sig ? "YES · "+(isTrendCat ? "Trend" : "Counter") : (failCnt>0 ? "NO · "+failTxt : "waiting"));
   string tipRes=!enabled ? "This direction is disabled in section 1." :
                 (sig ? "Signal on the current bar (confirmed at bar close)." :
                  (failCnt>0 ? "Blocking (✗): "+failAll+".\nConditions marked “…” may still change." :
                               "No condition is blocking — waiting for more bars ("+IntegerToString(nWait)+"× …)."));
   TblStCell(c,11,stRes,txtRes,tipRes);

   // 12 last signal
   string txtLast=(lastTime==0) ? "none" : ((barsSinceLast==0 ? "now" : IntegerToString(barsSinceLast)+" bars ago")+" · "+(lastTrend ? "Trend" : "Counter"));
   TblStCell(c,12,5,txtLast,"Last "+(isL ? "long" : "short")+" signal that passed all filters (drawn on the chart). Blocked signals are not counted here.",
             (lastTime==0) ? clrGray : (isL ? InpBullColor : InpBearColor));
  }

void UpdateTable(const int n,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[])
  {
   if(!InpShowTable) { DeleteTable(); return; }
   if(!gTblBuilt || ObjectFind(0,gPrefix+"TBL_BG")<0) BuildTable();
   int i=n-1;
   if(i<2) return;

   // header + row names (cached, so effectively written once)
   TblCell(0,0,"Condition",InpTblTxtCol,"Signal condition checklist for the CURRENT bar.\n✓ met\n✗ blocks the signal\n… cannot be evaluated yet (waiting for more bars)\n○ filter off\nHover over a cell to see details.");
   TblCell(1,0,"LONG",InpBullColor,"Upside reversal: streak of red candles → 2 green candles.");
   TblCell(2,0,"SHORT",InpBearColor,"Downside reversal: streak of green candles → 2 red candles.");
   TblCell(0,1,"Streak length",InpTblTxtCol,"Length of the streak preceding the reversal (long: red, short: green).\nSingle opposite candles are not counted as a streak.\nSection 2.");
   TblCell(0,2,"Streak move",InpTblTxtCol,"Distance covered by this streak, in ATR.\nSection 2.");
   TblCell(0,3,"Opposite candles",InpTblTxtCol,"How many opposite candles have appeared after the streak (2 required).");
   TblCell(0,4,"Level break",InpTblTxtCol,"Close of the 2nd opposite candle beyond the level of the 1st opposite candle.\nSection 3.");
   TblCell(0,5,"Current candle wick",InpTblTxtCol,"Opposite wick of the current candle (long: upper, short: lower) as % of its range.\nSection 3.");
   TblCell(0,6,"Current candle size",InpTblTxtCol,"Body or range of the current candle in ATR.\nSection 3.");
   TblCell(0,7,"Flat EMA",InpTblTxtCol,"Flat EMA filter — EMA range over the window, in ATR.\nSection 4.");
   TblCell(0,8,"Trend strength",InpTblTxtCol,"Trend direction and strength based on the EMA move; thresholds in section 4.\nInformational only.");
   TblCell(0,9,"Category",InpTblTxtCol,"Trend / Counter — based on price position relative to the EMA; shows whether this category is enabled.\nSection 1.");
   TblCell(0,10,"Distance from EMA",InpTblTxtCol,"Distance of the close from the EMA in ATR, with the applicable limit.\nSection 5.");
   TblCell(0,11,"SIGNAL",InpTblTxtCol,"Whether there is a signal on the current bar.\nYES — with the signal category.\nNO — names of the blocking conditions (max 2, “+N” = more; full list in the cell tooltip).\nwaiting — nothing is blocking, more bars are needed.");
   TblCell(0,12,"Last signal",InpTblTxtCol,"Last signal that passed all filters.");

   // --- current-bar setup state (Pine "SETUP STATE FOR THE TABLE")
   bool isBull=close[i]>open[i], isBear=close[i]<open[i];
   bool isBull1=close[i-1]>open[i-1], isBear1=close[i-1]<open[i-1];
   int  lOpp=(isBull&&isBull1) ? 2 : ((isBull&&isBear1) ? 1 : 0);
   int  sOpp=(isBear&&isBear1) ? 2 : ((isBear&&isBull1) ? 1 : 0);
   int    lLen =lOpp==2 ? gBearStreak[i-2]  : (lOpp==1 ? gBearStreak[i-1]  : gBearStreak[i]);
   double lMove=lOpp==2 ? gBearMoveNow[i-2] : (lOpp==1 ? gBearMoveNow[i-1] : gBearMoveNow[i]);
   int    sLen =sOpp==2 ? gBullStreak[i-2]  : (sOpp==1 ? gBullStreak[i-1]  : gBullStreak[i]);
   double sMove=sOpp==2 ? gBullMoveNow[i-2] : (sOpp==1 ? gBullMoveNow[i-1] : gBullMoveNow[i]);

   double oppBodyHigh=MathMax(open[i-1],close[i-1]), oppBodyLow=MathMin(open[i-1],close[i-1]);
   double longLevel =(InpConfirmLevel==LVL_BODY) ? oppBodyHigh : high[i-1];
   double shortLevel=(InpConfirmLevel==LVL_BODY) ? oppBodyLow  : low[i-1];

   double candleRange=high[i]-low[i];
   double upperWick=high[i]-MathMax(open[i],close[i]);
   double lowerWick=MathMin(open[i],close[i])-low[i];
   double oppWickPct=candleRange>0 ? upperWick/candleRange*100.0 : 0.0;
   double lowWickPct=candleRange>0 ? lowerWick/candleRange*100.0 : 0.0;
   double bodySize=MathAbs(close[i]-open[i]);
   double signalSize=(InpSignalSizeMode==SM_BODY) ? bodySize : candleRange;
   double signalSizeAtr=gAtrSize[i]>0 ? signalSize/gAtrSize[i] : NA_NEG;
   bool   signalSizeOk=!InpUseSignalSizeFilter || (signalSizeAtr>=0.0 && signalSizeAtr>=InpMinSignalSizeAtr);

   bool above=gEmaReady[i]&&close[i]>gEma[i], below=gEmaReady[i]&&close[i]<gEma[i];
   bool catL=(above&&InpShowTrendSignals)||(!above&&InpShowCounterSignals);
   bool catS=(below&&InpShowTrendSignals)||(!below&&InpShowCounterSignals);
   double d=gEmaDistAtr[i];
   bool trendDistOk  =!InpUseTrendMaxDist   || (d>=0.0 && d<=InpMaxTrendDistAtr);
   bool counterDistOk=!InpUseCounterMinDist || (d>=0.0 && d>=InpMinCounterDistAtr);
   bool longDistOk =above ? trendDistOk : counterDistOk;
   bool shortDistOk=below ? trendDistOk : counterDistOk;
   double emaMoveAtr=gEmaMoveAtr[i];
   bool emaMoveOk=!InpUseEmaMoveFilter || (emaMoveAtr>=0.0 && emaMoveAtr>=InpMinEmaMoveAtr);

   int barsL=(gS.lastLongTime==0) ? 0 : iBarShift(_Symbol,_Period,gS.lastLongTime,false);
   int barsS=(gS.lastShortTime==0) ? 0 : iBarShift(_Symbol,_Period,gS.lastShortTime,false);

   FillSide(1,true ,InpShowLong ,lOpp,lLen,lMove,isBull,oppWickPct,close[i]>longLevel ,longLevel ,above,catL,longDistOk ,gLongSig[i] ,gS.lastLongTime ,gS.lastLongTrend,
            candleRange,signalSizeOk,signalSizeAtr,emaMoveAtr,emaMoveOk,gEmaRising[i],d,close[i],gEma[i],gEmaReady[i],barsL);
   FillSide(2,false,InpShowShort,sOpp,sLen,sMove,isBear,lowWickPct,close[i]<shortLevel,shortLevel,below,catS,shortDistOk,gShortSig[i],gS.lastShortTime,gS.lastShortTrend,
            candleRange,signalSizeOk,signalSizeAtr,emaMoveAtr,emaMoveOk,gEmaRising[i],d,close[i],gEma[i],gEmaReady[i],barsS);
  }

//+------------------------------------------------------------------+
//| INIT                                                              |
//+------------------------------------------------------------------+
int OnInit()
  {
   gPrefix="SR_"+IntegerToString((int)ChartID())+"_";
   gHeadless=(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) || MQLInfoInteger(MQL_OPTIMIZATION);

   SetIndexBuffer(0,BufEma,INDICATOR_DATA);       SetIndexBuffer(1,BufEmaColor,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,BufLongTrend,INDICATOR_DATA); SetIndexBuffer(3,BufLongCounter,INDICATOR_DATA);
   SetIndexBuffer(4,BufShortTrend,INDICATOR_DATA);SetIndexBuffer(5,BufShortCounter,INDICATOR_DATA);
   SetIndexBuffer(6,BufOppLong,INDICATOR_DATA);   SetIndexBuffer(7,BufOppShort,INDICATOR_DATA);
   SetIndexBuffer(8,BufBuyTrend,INDICATOR_DATA);  SetIndexBuffer(9,BufBuyCounter,INDICATOR_DATA);
   SetIndexBuffer(10,BufSellTrend,INDICATOR_DATA);SetIndexBuffer(11,BufSellCounter,INDICATOR_DATA);

   PlotIndexSetInteger(0,PLOT_LINE_COLOR,0,InpBullColor);
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,1,InpBearColor);
   PlotIndexSetInteger(0,PLOT_LINE_WIDTH,MathMax(1,MathMin(8,InpEmaWidth)));

   int w=ShapeWidth(InpShapeSize);
   // Wingdings: 233 ▲, 234 ▼, 117 ◆, 159 ●
   PlotIndexSetInteger(1,PLOT_ARROW,233); PlotIndexSetInteger(1,PLOT_LINE_COLOR,InpBullColor); PlotIndexSetInteger(1,PLOT_ARROW_SHIFT, 12); PlotIndexSetInteger(1,PLOT_LINE_WIDTH,w);
   PlotIndexSetInteger(2,PLOT_ARROW,117); PlotIndexSetInteger(2,PLOT_LINE_COLOR,InpBullColor); PlotIndexSetInteger(2,PLOT_ARROW_SHIFT, 12); PlotIndexSetInteger(2,PLOT_LINE_WIDTH,w);
   PlotIndexSetInteger(3,PLOT_ARROW,234); PlotIndexSetInteger(3,PLOT_LINE_COLOR,InpBearColor); PlotIndexSetInteger(3,PLOT_ARROW_SHIFT,-12); PlotIndexSetInteger(3,PLOT_LINE_WIDTH,w);
   PlotIndexSetInteger(4,PLOT_ARROW,117); PlotIndexSetInteger(4,PLOT_LINE_COLOR,InpBearColor); PlotIndexSetInteger(4,PLOT_ARROW_SHIFT,-12); PlotIndexSetInteger(4,PLOT_LINE_WIDTH,w);
   PlotIndexSetInteger(5,PLOT_ARROW,159); PlotIndexSetInteger(5,PLOT_LINE_COLOR,InpBullColor); PlotIndexSetInteger(5,PLOT_ARROW_SHIFT, 6);  PlotIndexSetInteger(5,PLOT_LINE_WIDTH,1);
   PlotIndexSetInteger(6,PLOT_ARROW,159); PlotIndexSetInteger(6,PLOT_LINE_COLOR,InpBearColor); PlotIndexSetInteger(6,PLOT_ARROW_SHIFT,-6);  PlotIndexSetInteger(6,PLOT_LINE_WIDTH,1);
   for(int p=0;p<11;p++) PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME,"Streak Reversal");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   ResetState(gCommitted); gS=gCommitted;
   gArrSize=0; gTblBuilt=false; gTpslKey=""; ArrayResize(gLabelTimes,0);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0,gPrefix,-1,-1);
  }

//+------------------------------------------------------------------+
//| MAIN                                                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   if(rates_total<3) return(0);
   // everything chronological (oldest -> newest), like Pine
   ArraySetAsSeries(time,false); ArraySetAsSeries(open,false); ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false);  ArraySetAsSeries(close,false);
   ArraySetAsSeries(BufEma,false); ArraySetAsSeries(BufEmaColor,false);
   ArraySetAsSeries(BufLongTrend,false); ArraySetAsSeries(BufLongCounter,false);
   ArraySetAsSeries(BufShortTrend,false); ArraySetAsSeries(BufShortCounter,false);
   ArraySetAsSeries(BufOppLong,false); ArraySetAsSeries(BufOppShort,false);
   ArraySetAsSeries(BufBuyTrend,false); ArraySetAsSeries(BufBuyCounter,false);
   ArraySetAsSeries(BufSellTrend,false); ArraySetAsSeries(BufSellCounter,false);

   ResizeWork(rates_total);

   int start;
   bool full=(prev_calculated<=0 || prev_calculated>rates_total);
   if(full)
     {
      start=0;
      ResetState(gCommitted);
      if(!gHeadless) { ObjectsDeleteAll(0,gPrefix,-1,-1); gTblBuilt=false; gTpslKey=""; ArrayResize(gLabelTimes,0); }
     }
   else start=prev_calculated-1;

   gS=gCommitted;              // roll the live bar back (Pine semantics)
   int emaP=SafeLen(InpEmaLen);
   double alpha=2.0/(emaP+1.0);

   for(int i=start;i<rates_total;i++)
     {
      //--- true range & the five ATRs
      double range=high[i]-low[i];
      if(i>0) { range=MathMax(range,MathAbs(high[i]-close[i-1])); range=MathMax(range,MathAbs(low[i]-close[i-1])); }
      gTR[i]=range;
      gAtrStreak[i] =AtrAt(i,InpAtrLenStreak ,gAtrStreak);
      gAtrSize[i]   =AtrAt(i,InpAtrLenSize   ,gAtrSize);
      gAtrEmaMove[i]=AtrAt(i,InpAtrLenEmaMove,gAtrEmaMove);
      gAtrDist[i]   =AtrAt(i,InpAtrLenDist   ,gAtrDist);
      gAtrTP[i]     =AtrAt(i,InpTpAtrPeriod  ,gAtrTP);

      //--- ta.ema (SMA seed)
      if(i<emaP-1) { gEma[i]=0.0; gEmaReady[i]=false; }
      else if(i==emaP-1 || !gEmaReady[i-1])
        {
         double sum=0.0; for(int j=i-emaP+1;j<=i;j++) sum+=close[j];
         gEma[i]=sum/emaP; gEmaReady[i]=true;
        }
      else { gEma[i]=alpha*close[i]+(1.0-alpha)*gEma[i-1]; gEmaReady[i]=true; }

      //--- candles / streaks
      bool isBull=close[i]>open[i], isBear=close[i]<open[i];
      int  bs1=(i>0 ? gBullStreak[i-1] : 0), rs1=(i>0 ? gBearStreak[i-1] : 0);
      gBullStreak[i]=isBull ? bs1+1 : 0;
      gBearStreak[i]=isBear ? rs1+1 : 0;
      gBearFirstHigh[i]=isBear ? (gBearStreak[i]==1 ? high[i] : (i>0 ? gBearFirstHigh[i-1] : 0.0)) : 0.0;
      gBullFirstLow[i] =isBull ? (gBullStreak[i]==1 ? low[i]  : (i>0 ? gBullFirstLow[i-1]  : 0.0)) : 0.0;
      gBearMoveNow[i]=(isBear && gAtrStreak[i]>0) ? (gBearFirstHigh[i]-low[i])/gAtrStreak[i] : NA_NEG;
      gBullMoveNow[i]=(isBull && gAtrStreak[i]>0) ? (high[i]-gBullFirstLow[i])/gAtrStreak[i] : NA_NEG;

      //--- EMA move (highest-lowest over window, na values ignored) & direction
      double emaMoveAtr=NA_NEG; bool emaRising=true;
      if(gEmaReady[i])
        {
         double hi=gEma[i],lo=gEma[i];
         for(int j=MathMax(0,i-InpEmaMoveLen+1);j<=i;j++)
            if(gEmaReady[j]) { hi=MathMax(hi,gEma[j]); lo=MathMin(lo,gEma[j]); }
         if(gAtrEmaMove[i]>0) emaMoveAtr=(hi-lo)/gAtrEmaMove[i];
         int k=i-InpEmaMoveLen;
         double prevE=(k>=0 && gEmaReady[k]) ? gEma[k] : gEma[i];   // nz(emaVal[len], emaVal)
         emaRising=(gEma[i]>=prevE);
        }
      gEmaMoveAtr[i]=emaMoveAtr; gEmaRising[i]=emaRising;
      bool emaMoveOk=!InpUseEmaMoveFilter || (emaMoveAtr>=0.0 && emaMoveAtr>=InpMinEmaMoveAtr);

      //--- distance from EMA
      gEmaDistAtr[i]=(gEmaReady[i] && gAtrDist[i]>0) ? MathAbs(close[i]-gEma[i])/gAtrDist[i] : NA_NEG;
      bool above=gEmaReady[i]&&close[i]>gEma[i], below=gEmaReady[i]&&close[i]<gEma[i];
      gLongIsTrend[i]=above; gShortIsTrend[i]=below;
      double dAtr=gEmaDistAtr[i];
      bool trendDistOk  =!InpUseTrendMaxDist   || (dAtr>=0.0 && dAtr<=InpMaxTrendDistAtr);
      bool counterDistOk=!InpUseCounterMinDist || (dAtr>=0.0 && dAtr>=InpMinCounterDistAtr);
      bool longDistOk =above ? trendDistOk : counterDistOk;
      bool shortDistOk=below ? trendDistOk : counterDistOk;
      bool catL=(above&&InpShowTrendSignals)||(!above&&InpShowCounterSignals);
      bool catS=(below&&InpShowTrendSignals)||(!below&&InpShowCounterSignals);

      //--- signal candle filters
      double upperWick=high[i]-MathMax(open[i],close[i]);
      double lowerWick=MathMin(open[i],close[i])-low[i];
      double bodySize=MathAbs(close[i]-open[i]);
      double candleRange=high[i]-low[i];
      double oppWickPct=candleRange>0 ? upperWick/candleRange*100.0 : 0.0;
      double lowWickPct=candleRange>0 ? lowerWick/candleRange*100.0 : 0.0;
      bool longWickOk =!InpUseOppWickFilter || (candleRange>0 && oppWickPct<=InpMaxOppWickPct);
      bool shortWickOk=!InpUseOppWickFilter || (candleRange>0 && lowWickPct<=InpMaxOppWickPct);
      double signalSize=(InpSignalSizeMode==SM_BODY) ? bodySize : candleRange;
      double signalSizeAtr=gAtrSize[i]>0 ? signalSize/gAtrSize[i] : NA_NEG;
      bool signalSizeOk=!InpUseSignalSizeFilter || (signalSizeAtr>=0.0 && signalSizeAtr>=InpMinSignalSizeAtr);

      //--- signals (need i-2)
      bool longSignal=false, shortSignal=false;
      if(i>=2)
        {
         bool isBull1=close[i-1]>open[i-1], isBear1=close[i-1]<open[i-1];
         double longLevel =(InpConfirmLevel==LVL_BODY) ? MathMax(open[i-1],close[i-1]) : high[i-1];
         double shortLevel=(InpConfirmLevel==LVL_BODY) ? MathMin(open[i-1],close[i-1]) : low[i-1];
         double bearDrop=gBearFirstHigh[i-2]-low[i-2];
         double bullRise=high[i-2]-gBullFirstLow[i-2];
         double a2=gAtrStreak[i-2];
         bool longMoveOk =!InpUseAtrFilter || (a2>0 && bearDrop/a2>=InpMinAtrMove);
         bool shortMoveOk=!InpUseAtrFilter || (a2>0 && bullRise/a2>=InpMinAtrMove);
         longSignal =InpShowLong  && gBearStreak[i-2]>=InpMinStreak && isBull1 && isBull && longMoveOk  && longWickOk  && signalSizeOk && emaMoveOk && catL && longDistOk  && close[i]>longLevel;
         shortSignal=InpShowShort && gBullStreak[i-2]>=InpMinStreak && isBear1 && isBear && shortMoveOk && shortWickOk && signalSizeOk && emaMoveOk && catS && shortDistOk && close[i]<shortLevel;
        }
      gLongSig[i]=longSignal; gShortSig[i]=shortSignal;
      bool lT=longSignal&&above, lC=longSignal&&!above, sT=shortSignal&&below, sC=shortSignal&&!below;

      //--- buffers
      BufEma[i]=(InpShowEma && gEmaReady[i]) ? gEma[i] : EMPTY_VALUE;
      BufEmaColor[i]=(gEmaReady[i] && close[i]>=gEma[i]) ? 0 : 1;
      BufLongTrend[i]  =(InpShowShapes&&lT) ? low[i]  : EMPTY_VALUE;
      BufLongCounter[i]=(InpShowShapes&&lC) ? low[i]  : EMPTY_VALUE;
      BufShortTrend[i] =(InpShowShapes&&sT) ? high[i] : EMPTY_VALUE;
      BufShortCounter[i]=(InpShowShapes&&sC)? high[i] : EMPTY_VALUE;
      BufBuyTrend[i]   =lT ? 1.0 : EMPTY_VALUE;
      BufBuyCounter[i] =lC ? 1.0 : EMPTY_VALUE;
      BufSellTrend[i]  =sT ? 1.0 : EMPTY_VALUE;
      BufSellCounter[i]=sC ? 1.0 : EMPTY_VALUE;
      if(i>0)   // plotshape offset=-1 -> drawn on the previous bar
        {
         BufOppLong[i-1] =(InpHighlightOpp&&longSignal)  ? low[i-1]  : EMPTY_VALUE;
         BufOppShort[i-1]=(InpHighlightOpp&&shortSignal) ? high[i-1] : EMPTY_VALUE;
        }
      BufOppLong[i]=EMPTY_VALUE; BufOppShort[i]=EMPTY_VALUE;

      //--- Pine var state: last signals
      if(longSignal)  { gS.lastLongTime =time[i]; gS.lastLongTrend =above; }
      if(shortSignal) { gS.lastShortTime=time[i]; gS.lastShortTrend=below; }

      //--- TP/SL state machine
      bool closedBar=(i<rates_total-1);
      if(InpShowTargets && (longSignal||shortSignal) && closedBar)   // confirmed (closed-bar) entries only
        {
         bool L=longSignal;
         double entry=close[i];
         double risk=InpUseAtrSL ? gAtrTP[i]*InpSlAtrMult : entry*(InpSlPercent/100.0);
         gS.tpslVisible=true; gS.tpslDir=L ? 1 : -1; gS.tpslEntryTime=time[i];
         gS.tpslEntry=entry;
         gS.tpslSL =L ? entry-risk : entry+risk;
         gS.tpslTP1=L ? entry+risk*InpRrTP1 : entry-risk*InpRrTP1;
         gS.tpslTP2=L ? entry+risk*InpRrTP2 : entry-risk*InpRrTP2;
         gS.tpslTP3=L ? entry+risk*InpRrTP3 : entry-risk*InpRrTP3;
         gS.tpslHasExtreme=false; gS.tpslExtreme=entry;
         if(InpShowTp1Level||InpShowTp2Level||InpShowTp3Level)
           {
            double t1=InpShowTp1Level ? gS.tpslTP1 : entry, t2=InpShowTp2Level ? gS.tpslTP2 : entry, t3=InpShowTp3Level ? gS.tpslTP3 : entry;
            gS.tpslExtreme=L ? MathMax(t1,MathMax(t2,t3)) : MathMin(t1,MathMin(t2,t3));
            gS.tpslHasExtreme=(gS.tpslExtreme!=entry);
           }
         gS.tpslEndTime=0;
        }
      if(gS.tpslDir!=0 && closedBar)
        {
         bool slHit=(gS.tpslDir==1) ? low[i]<=gS.tpslSL : high[i]>=gS.tpslSL;
         bool tpHit=gS.tpslHasExtreme && ((gS.tpslDir==1) ? high[i]>=gS.tpslExtreme : low[i]<=gS.tpslExtreme);
         if(time[i]>gS.tpslEntryTime && (slHit||tpHit)) { gS.tpslEndTime=time[i]; gS.tpslDir=0; }
        }

      //--- labels: during the initial pass only the last 500 are drawn afterwards
      if(!gHeadless && !full) DrawSignalLabel(i,time,high,low);

      //--- commit state after each CLOSED bar
      if(i<rates_total-1) gCommitted=gS;
     }

   //--- objects
   if(!gHeadless)
     {
      if(full && InpShowDistLabel)
        {
         // Pine max_labels_count = 500: draw only the most recent 500 signals, oldest -> newest
         int cnt=0, firstIdx=0;
         for(int i=rates_total-1;i>=0;i--) if(gLongSig[i]||gShortSig[i]) { cnt++; if(cnt==500){ firstIdx=i; break; } }
         for(int i=firstIdx;i<rates_total;i++) if(gLongSig[i]||gShortSig[i]) DrawSignalLabel(i,time,high,low);
        }
      RenderTpsl(gS,time[rates_total-1]);
      UpdateTable(rates_total,time,open,high,low,close);
      ChartRedraw(0);
     }

   //--- alerts
   int a=InpAlertsOnBarClose ? rates_total-2 : rates_total-1;
   if(InpEnableAlerts && a>=0 && !full)
     {
      bool newBar=(time[rates_total-1]!=gLastBarTime);
      if((InpAlertsOnBarClose && newBar) || (!InpAlertsOnBarClose && time[a]!=gLastAlertTime))
        {
         if(gLongSig[a])  { Alert("REV LONG " ,_Symbol," ",EnumToString(_Period)," @ ",FmtTick(close[a])); gLastAlertTime=time[a]; }
         if(gShortSig[a]) { Alert("REV SHORT ",_Symbol," ",EnumToString(_Period)," @ ",FmtTick(close[a])); gLastAlertTime=time[a]; }
        }
     }
   gLastBarTime=time[rates_total-1];
   return(rates_total);
  }
//+------------------------------------------------------------------+
