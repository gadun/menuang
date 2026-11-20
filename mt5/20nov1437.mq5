//+------------------------------------------------------------------+
//|                                                 RiskRadarHUD.mq5 |
//|  Radar Risiko + Fast Bulk Close + Auto TP/SL + One-Click Trading |
//|  + Hedge 1:1 + Reverse + Auto Target (+) & Auto Cutloss (-)      |
//|  + InstantOrderIOC Engine (Auto Filling + TP/SL USD + Bridge)    |
//|                                      https://cindo.pages.dev     |
//+------------------------------------------------------------------+
#property copyright   "Mochamad Tabrani & Antigravity AI"
#property link        "https://cindo.pages.dev"
#property version     "2.80"
#property description "EA All-In-One Pro: One-Click IOC, TP/SL USD/Pts, Radar Risiko, Auto Target (+)/(-), Trailing & MCP Bridge"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enum Mode TP/SL                                                  |
//+------------------------------------------------------------------+
enum ENUM_TPSL_MODE
{
   TPSL_MODE_POINTS = 0, // Berdasarkan Points
   TPSL_MODE_USD    = 1  // Berdasarkan Nominal USD ($)
};

//+------------------------------------------------------------------+
//| [1] Parameter Input                                              |
//+------------------------------------------------------------------+
input group "=== PENGATURAN TAMPILAN PANEL (WIDESCREEN ANTI TUMPUK) ==="
input int             InpWidth            = 430;   // Lebar Panel HUD (Pixel)
input int             InpX                = 25;    // Posisi X dari kiri layar (Pixel)
input int             InpY                = 35;    // Posisi Y dari atas layar (Pixel)

input group "=== PENGATURAN TRADING CEPAT (ONE-CLICK) ==="
input double          InpDefaultLot       = 0.01;  // Ukuran Lot Default
input double          InpLotStep          = 0.01;  // Nilai Tambah/Kurang Lot tombol [-] [+]

input group "=== AUTO TARGET KERANJANG (+PROFIT & -CUTLOSS) ==="
input double          InpBasketTargetMoney= 25.0;  // Target Profit Uang ($) Tutup Otomatis (0 = Nonaktif)
input double          InpBasketMaxLossMoney= 20.0; // Target Rugi Maksimal ($) Cutloss Otomatis (0 = Nonaktif)
input bool            InpEnableTrailingBE = true;  // Aktifkan Trailing Breakeven Pengunci Profit?
input int             InpTrailingStartPts = 50;    // Jarak Profit (pts) untuk Mulai Aktifkan Trailing
input int             InpTrailingLockPts  = 15;    // Kunci Minimal Profit (pts) saat harga retrace

input group "=== PENGATURAN AUTO TP & SL (EXNESS / XM IOC READY) ==="
input bool            InpEnableAutoTPSL   = true;          // Otomatis Pasang TP/SL untuk Posisi Baru?
input ENUM_TPSL_MODE  InpTPSLMode         = TPSL_MODE_USD; // Mode Hitung TP/SL (Points atau Nominal USD)
input double          InpTPUsd            = 3.0;           // Target Take Profit dalam USD (jika Mode = USD)
input double          InpSLUsd            = 0.0;           // Jarak Stop Loss dalam USD (jika Mode = USD & UseSL = true)
input int             InpTPPoints         = 1000;          // Jarak Take Profit (Points, jika Mode = Points)
input bool            InpUseSL            = false;         // Aktifkan Stop Loss?
input int             InpSLPoints         = 500;           // Jarak Stop Loss (Points, jika Mode = Points & UseSL = true)
input int             InpMaxRetry         = 3;             // Maksimal percobaan pasang TP/SL jika gagal
input int             InpRetryDelayMs     = 60;            // Delay antar retry (milidetik)

input group "=== PENGATURAN JEMBATAN INSTANT ORDER IOC (MCP BRIDGE) ==="
input bool            InpEnableCmdBridge  = true;            // Aktifkan Penerima Perintah Instant Order via File?
input string          InpCmdFileName      = "radar_cmd.txt"; // File Perintah di MQL5\Files
input string          InpResFileName      = "radar_res.txt"; // File Hasil Eksekusi di MQL5\Files

input group "=== PENGATURAN RADAR RISIKO & ZONA KERANJANG ==="
input int             InpWarningPts       = 500;   // Jarak Pts ke SO: Batas Status WASPADA
input int             InpDangerPts        = 200;   // Jarak Pts ke SO: Batas Status BAHAYA
input bool            InpShowSOLine       = true;  // Gambar Garis Level Stop Out (MC) di Chart
input bool            InpShowBELine       = true;  // Gambar Garis Titik Impas (Breakeven) di Chart
input bool            InpAutoCutEmergency = false; // [AUTO CUT] Tutup Semua jika masuk Status BAHAYA

input group "=== PENGATURAN NOTIFIKASI / ALERT ==="
input bool            InpEnableAlert      = true;  // Popup Alert di layar MT5 saat TP/SL kena?
input bool            InpEnablePush       = false; // Kirim Notifikasi ke HP (MetaQuotes ID)?
input bool            InpEnableEmail      = false; // Kirim Notifikasi via Email?

input group "=== PENGATURAN BULK CLOSE & FILTER ==="
input int             InpSlippage         = 30;    // Toleransi slippage (pts)
input bool            InpTPSLCurrentOnly  = false; // Auto TP/SL: true = hanya chart ini, false = semua pair
input long            InpMagicFilter      = 0;     // 0 = proses semua posisi (manual + EA lain)

//+------------------------------------------------------------------+
//| [2] Definisi Warna & Gaya Tampilan (Modern Glassmorphism)         |
//+------------------------------------------------------------------+
#define PREFIX          "RADAR_"
#define COLOR_PANEL_BG  C'18,20,26'      // Obsidian Black Modern
#define COLOR_CARD_BG   C'26,30,39'      // Slate Dark
#define COLOR_BORDER    C'45,52,65'      // Border Minimalis
#define COLOR_TEXT_DIM  C'150,158,175'   // Abu-abu elegan
#define COLOR_TEXT_VAL  C'235,240,250'   // Putih bersih
#define COLOR_SAFE      C'0,230,130'     // Hijau Emerald
#define COLOR_WARN      C'255,185,45'    // Kuning Amber
#define COLOR_DANGER    C'255,65,85'     // Merah Ruby
#define COLOR_ACCENT    C'60,165,255'    // Biru Cyan Futuristik
#define FONT_UI         "Segoe UI"

enum ENUM_RISK_STATUS
{
   RISK_SAFE,
   RISK_WARNING,
   RISK_CRITICAL
};

//+------------------------------------------------------------------+
//| [3] Variabel Global                                              |
//+------------------------------------------------------------------+
double            g_point;
int               g_digits;
uint              g_lastUiTick      = 0;
bool              g_isClosing       = false;
bool              g_isMinimized     = false;
bool              g_trailingActive  = false;
ENUM_RISK_STATUS  g_currentStatus   = RISK_SAFE;
double            g_tradeLot        = 0.01;
CTrade            g_trade;

//+------------------------------------------------------------------+
//| [4] Inisialisasi & Lifecycle                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   g_point    = _Point;
   g_digits   = _Digits;
   g_tradeLot = NormalizeLotForSymbol(_Symbol, InpDefaultLot);

   g_trade.SetExpertMagicNumber(InpMagicFilter);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(GetOptimalFilling(_Symbol));

   DeleteRadarObjects();
   CreateRadarHUD();

   Print("=== RiskRadarHUD v2.80 Master Pro (InstantOrderIOC + TP/SL USD + Bridge) Aktif ===");
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteRadarObjects();
   ChartRedraw();
   Print("=== RiskRadarHUD Dihentikan ===");
}

void OnTick()
{
   if(InpEnableCmdBridge)
      ProcessCommandBridge();

   uint now = GetTickCount();
   if(now - g_lastUiTick >= 120)
   {
      UpdateRiskRadar();
      g_lastUiTick = now;
   }
}

void OnTimer()
{
   if(InpEnableCmdBridge)
      ProcessCommandBridge();

   UpdateRiskRadar();
   if(g_isClosing)
   {
      if(CountActivePositions(true) == 0)
      {
         g_isClosing = false;
         UpdateButtonState(false);
      }
   }
}

//+------------------------------------------------------------------+
//| [5] TRADE TRANSACTION - AUTO TP/SL & ALERT                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = trans.deal;
   if(dealTicket == 0 || !HistoryDealSelect(dealTicket)) return;

   long   dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   long   dealType  = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
   string sym       = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   long   magic     = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);

   if(InpMagicFilter != 0 && magic != InpMagicFilter) return;
   if(InpTPSLCurrentOnly && sym != _Symbol) return;

   if(dealEntry == DEAL_ENTRY_IN && (dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL))
   {
      if(InpEnableAutoTPSL)
      {
         ulong posTicket = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
         if(posTicket != 0)
            ProcessNewPosition(posTicket);
      }
   }

   if(dealEntry == DEAL_ENTRY_OUT)
   {
      long dealReason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
      if(dealReason == DEAL_REASON_TP || dealReason == DEAL_REASON_SL)
      {
         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                         HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                         HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);

         string statusType = (dealReason == DEAL_REASON_TP) ? "🎯 TAKE PROFIT (TP)" : "❌ STOP LOSS (SL)";
         string posStr     = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";
         double priceClose = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
         ulong  posId      = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

         string message = StringFormat("%s Tersentuh! [%s %s] | Tiket: #%I64d | Harga: %s | P/L: $%.2f",
                                       statusType, posStr, sym, posId,
                                       DoubleToString(priceClose, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)), profit);

         Print(message);
         if(InpEnableAlert) Alert(message);
         if(InpEnablePush)  SendNotification(message);
         if(InpEnableEmail) SendMail("AutoTP/SL Alert: " + sym, message);
      }
   }
}

//+------------------------------------------------------------------+
//| [6] FITUR TRADING LANJUTAN: HEDGE 1:1, REVERSE, & CLOSE 50%      |
//+------------------------------------------------------------------+
void ExecuteEmergencyHedge()
{
   double buyLots = 0, sellLots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               buyLots += PositionGetDouble(POSITION_VOLUME);
            else
               sellLots += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }

   double netLots = buyLots - sellLots;
   if(MathAbs(netLots) < 0.00001)
   {
      Alert("Akun sudah terkunci 100% (Hedge 1:1)!");
      return;
   }

   double hedgeLot = NormalizeLotForSymbol(_Symbol, MathAbs(netLots));
   if(hedgeLot <= 0) return;

   g_trade.SetTypeFilling(GetOptimalFilling(_Symbol));

   if(netLots > 0)
   {
      if(g_trade.Sell(hedgeLot, _Symbol, 0.0, 0, 0, "EMERGENCY HEDGE 1:1"))
         Alert("🔒 EMERGENCY HEDGE BERHASIL: Membuka SELL " + DoubleToString(hedgeLot, 2) + " Lot. Akun Terkunci Aman!");
   }
   else
   {
      if(g_trade.Buy(hedgeLot, _Symbol, 0.0, 0, 0, "EMERGENCY HEDGE 1:1"))
         Alert("🔒 EMERGENCY HEDGE BERHASIL: Membuka BUY " + DoubleToString(hedgeLot, 2) + " Lot. Akun Terkunci Aman!");
   }
}

void ExecuteReversePosition()
{
   double buyLots = 0, sellLots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               buyLots += PositionGetDouble(POSITION_VOLUME);
            else
               sellLots += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }

   if(buyLots == 0 && sellLots == 0) return;

   ENUM_POSITION_TYPE targetType = (buyLots >= sellLots) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
   double targetLot = NormalizeLotForSymbol(_Symbol, MathMax(buyLots, sellLots));

   FastBulkClose(true);

   if(targetLot > 0)
   {
      g_trade.SetTypeFilling(GetOptimalFilling(_Symbol));
      if(targetType == POSITION_TYPE_BUY)
         g_trade.Buy(targetLot, _Symbol, 0.0, 0, 0, "REVERSE POSISI BUY");
      else
         g_trade.Sell(targetLot, _Symbol, 0.0, 0, 0, "REVERSE POSISI SELL");

      Print("🔄 REVERSE POSITION BERHASIL dieksekusi!");
   }
}

void ExecuteCloseHalf()
{
   int closed = 0;
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_trade.SetTypeFilling(GetOptimalFilling(_Symbol));

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double vol = PositionGetDouble(POSITION_VOLUME);
            double halfVol = NormalizeDouble(MathRound((vol * 0.5) / stepLot) * stepLot, 2);

            if(halfVol >= minLot && halfVol < vol)
            {
               if(g_trade.PositionClosePartial(t, halfVol))
                  closed++;
            }
         }
      }
   }
   if(closed > 0)
      Print("✂️ Berhasil menutup 50% volume dari ", closed, " posisi!");
}

//+------------------------------------------------------------------+
//| [7] ENGINE INSTANT ORDER IOC + KONVERSI TP/SL USD                |
//+------------------------------------------------------------------+
double UsdToPriceDistance(const string sym, const double usd, const double volume)
{
   if(usd <= 0.0 || volume <= 0.0)
      return 0.0;

   double tick_val  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tick_val <= 0.0 || tick_size <= 0.0)
      return 0.0;

   double usd_per_price_unit = (tick_val / tick_size) * volume;
   if(usd_per_price_unit <= 0.0)
      return 0.0;

   return usd / usd_per_price_unit;
}

bool ExecuteInstantOrderIOC(const string symInput,
                            const ENUM_POSITION_TYPE orderType,
                            const double rawVol,
                            const double tpUsd,
                            const double slUsd,
                            const double tpPriceAbs,
                            const double slPriceAbs,
                            const string comment,
                            string &outReport)
{
   string sym = (StringLen(symInput) > 0) ? symInput : _Symbol;

   if(!SymbolSelect(sym, true))
   {
      outReport = StringFormat("ERROR|Gagal memilih simbol: %s", sym);
      Print("[InstantIOC] ", outReport);
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(sym, tick))
   {
      outReport = StringFormat("ERROR|Gagal mengambil harga tick untuk %s", sym);
      Print("[InstantIOC] ", outReport);
      return false;
   }

   double vol     = NormalizeLotForSymbol(sym, rawVol);
   int    dig     = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double pt      = SymbolInfoDouble(sym, SYMBOL_POINT);
   long   stops   = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stops * pt;

   bool   isBuy = (orderType == POSITION_TYPE_BUY);
   double entry = isBuy ? tick.ask : tick.bid;

   double tpPrice = 0.0;
   double slPrice = 0.0;

   if(tpPriceAbs > 0.0)
   {
      tpPrice = NormalizeDouble(tpPriceAbs, dig);
   }
   else if(tpUsd > 0.0)
   {
      double dist = MathMax(UsdToPriceDistance(sym, tpUsd, vol), minDist);
      tpPrice = NormalizeDouble(isBuy ? (entry + dist) : (entry - dist), dig);
   }

   if(slPriceAbs > 0.0)
   {
      slPrice = NormalizeDouble(slPriceAbs, dig);
   }
   else if(slUsd > 0.0)
   {
      double dist = MathMax(UsdToPriceDistance(sym, slUsd, vol), minDist);
      slPrice = NormalizeDouble(isBuy ? (entry - dist) : (entry + dist), dig);
   }

   ENUM_ORDER_TYPE_FILLING fillMode = GetOptimalFilling(sym);
   g_trade.SetExpertMagicNumber(InpMagicFilter);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(fillMode);

   bool ok = false;
   if(isBuy)
      ok = g_trade.Buy(vol, sym, 0.0, slPrice, tpPrice, comment);
   else
      ok = g_trade.Sell(vol, sym, 0.0, slPrice, tpPrice, comment);

   if(ok)
   {
      outReport = StringFormat("OK|%s|%s|%.2f|Deal=%I64u|Order=%I64u|Price=%.*f|SL=%.*f|TP=%.*f|Fill=%d",
                               isBuy ? "BUY" : "SELL", sym, vol,
                               g_trade.ResultDeal(), g_trade.ResultOrder(),
                               dig, g_trade.ResultPrice(),
                               dig, slPrice, dig, tpPrice, (int)fillMode);
      Print("[InstantIOC] SUKSES ", outReport);
      return true;
   }
   else
   {
      outReport = StringFormat("FAIL|%s|%s|%.2f|Retcode=%u|%s|Fill=%d",
                               isBuy ? "BUY" : "SELL", sym, vol,
                               g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription(), (int)fillMode);
      Print("[InstantIOC] GAGAL ", outReport);
      return false;
   }
}

void ExecuteOneClickOrder(ENUM_POSITION_TYPE orderType)
{
   double price   = (orderType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pt      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    dig     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long   stops   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stops * pt;

   double tpUsd      = 0.0;
   double slUsd      = 0.0;
   double tpPriceAbs = 0.0;
   double slPriceAbs = 0.0;

   if(InpEnableAutoTPSL)
   {
      if(InpTPSLMode == TPSL_MODE_USD)
      {
         tpUsd = (InpTPUsd > 0.0) ? InpTPUsd : 0.0;
         slUsd = (InpUseSL && InpSLUsd > 0.0) ? InpSLUsd : 0.0;
      }
      else
      {
         if(InpTPPoints > 0)
         {
            double dist = MathMax((double)InpTPPoints * pt, minDist);
            tpPriceAbs = NormalizeDouble((orderType == POSITION_TYPE_BUY) ? (price + dist) : (price - dist), dig);
         }
         if(InpUseSL && InpSLPoints > 0)
         {
            double dist = MathMax((double)InpSLPoints * pt, minDist);
            slPriceAbs = NormalizeDouble((orderType == POSITION_TYPE_BUY) ? (price - dist) : (price + dist), dig);
         }
      }
   }

   string report = "";
   string cmt    = (orderType == POSITION_TYPE_BUY) ? "Radar One-Click BUY" : "Radar One-Click SELL";
   ExecuteInstantOrderIOC(_Symbol, orderType, g_tradeLot, tpUsd, slUsd, tpPriceAbs, slPriceAbs, cmt, report);
}

//+------------------------------------------------------------------+
//| [7B] JEMBATAN PERINTAH INSTANT ORDER VIA FILE (MQL5\Files)       |
//| Format baris: ACTION|SYMBOL|VOL|TP_USD|SL_USD|TP_PRC|SL_PRC|CMT  |
//| Contoh:       BUY|GOLD|0.01|3.0|0|0|0|MCP_IOC                    |
//+------------------------------------------------------------------+
void WriteBridgeResult(const string text)
{
   int h = FileOpen(InpResFileName, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      FileWriteString(h, TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS) + "|" + text + "\r\n");
      FileClose(h);
   }
}

void ProcessCommandBridge()
{
   if(!FileIsExist(InpCmdFileName))
      return;

   int h = FileOpen(InpCmdFileName, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;

   string line = "";
   while(!FileIsEnding(h))
   {
      string cur = FileReadString(h);
      StringTrimLeft(cur);
      StringTrimRight(cur);
      if(StringLen(cur) > 0)
      {
         line = cur;
         break;
      }
   }
   FileClose(h);

   // Hapus file perintah segera agar tidak dieksekusi ganda
   FileDelete(InpCmdFileName);

   if(StringLen(line) == 0)
      return;

   string parts[];
   int count = StringSplit(line, '|', parts);
   if(count < 1)
      return;

   string action = parts[0];
   StringToUpper(action);

   if(action == "BUY" || action == "SELL")
   {
      string sym        = (count > 1 && StringLen(parts[1]) > 0) ? parts[1] : _Symbol;
      double vol        = (count > 2 && StringToDouble(parts[2]) > 0.0) ? StringToDouble(parts[2]) : g_tradeLot;
      double tpUsd      = (count > 3) ? StringToDouble(parts[3]) : 0.0;
      double slUsd      = (count > 4) ? StringToDouble(parts[4]) : 0.0;
      double tpPriceAbs = (count > 5) ? StringToDouble(parts[5]) : 0.0;
      double slPriceAbs = (count > 6) ? StringToDouble(parts[6]) : 0.0;
      string cmt        = (count > 7 && StringLen(parts[7]) > 0) ? parts[7] : "RadarBridgeIOC";

      ENUM_POSITION_TYPE side = (action == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      string report = "";
      ExecuteInstantOrderIOC(sym, side, vol, tpUsd, slUsd, tpPriceAbs, slPriceAbs, cmt, report);
      WriteBridgeResult(report);
   }
   else if(action == "CLOSE_CURR")
   {
      FastBulkClose(true);
      WriteBridgeResult("OK|CLOSE_CURR|" + _Symbol);
   }
   else if(action == "CLOSE_ALL")
   {
      FastBulkClose(false);
      WriteBridgeResult("OK|CLOSE_ALL");
   }
   else
   {
      WriteBridgeResult("ERROR|Unknown action: " + action);
   }
}

//+------------------------------------------------------------------+
//| [8] PROSES POSISI BARU (PASANG TP/SL JIKA BELUM ADA)             |
//+------------------------------------------------------------------+
void ProcessNewPosition(ulong positionTicket)
{
   if(!PositionSelectByTicket(positionTicket)) return;

   string sym        = PositionGetString(POSITION_SYMBOL);
   long   magic      = PositionGetInteger(POSITION_MAGIC);
   double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
   double vol        = PositionGetDouble(POSITION_VOLUME);
   long   posType    = PositionGetInteger(POSITION_TYPE);
   double currentTP  = PositionGetDouble(POSITION_TP);
   double currentSL  = PositionGetDouble(POSITION_SL);

   if(InpMagicFilter != 0 && magic != InpMagicFilter) return;
   if(InpTPSLCurrentOnly && sym != _Symbol) return;
   if(currentTP > 0) return;

   double pt         = SymbolInfoDouble(sym, SYMBOL_POINT);
   int    dig        = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   long   stopsLevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLevel * pt;

   double tpPrice = 0.0;
   double slPrice = currentSL;

   if(InpTPSLMode == TPSL_MODE_USD)
   {
      if(InpTPUsd > 0.0)
      {
         double dist = MathMax(UsdToPriceDistance(sym, InpTPUsd, vol), minDist);
         tpPrice = NormalizeDouble((posType == POSITION_TYPE_BUY) ? (openPrice + dist) : (openPrice - dist), dig);
      }
      if(InpUseSL && InpSLUsd > 0.0 && currentSL <= 0.0)
      {
         double dist = MathMax(UsdToPriceDistance(sym, InpSLUsd, vol), minDist);
         slPrice = NormalizeDouble((posType == POSITION_TYPE_BUY) ? (openPrice - dist) : (openPrice + dist), dig);
      }
   }
   else
   {
      if(InpTPPoints > 0)
      {
         double dist = MathMax((double)InpTPPoints * pt, minDist);
         tpPrice = NormalizeDouble((posType == POSITION_TYPE_BUY) ? (openPrice + dist) : (openPrice - dist), dig);
      }
      if(InpUseSL && InpSLPoints > 0 && currentSL <= 0.0)
      {
         double dist = MathMax((double)InpSLPoints * pt, minDist);
         slPrice = NormalizeDouble((posType == POSITION_TYPE_BUY) ? (openPrice - dist) : (openPrice + dist), dig);
      }
   }

   if(tpPrice <= 0.0 && slPrice <= 0.0) return;

   for(int attempt = 1; attempt <= InpMaxRetry; attempt++)
   {
      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};
      request.action   = TRADE_ACTION_SLTP;
      request.position = positionTicket;
      request.symbol   = sym;
      request.sl       = slPrice;
      request.tp       = tpPrice;
      request.magic    = InpMagicFilter;

      if(OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE)
         break;
      if(attempt < InpMaxRetry)
         Sleep(InpRetryDelayMs);
   }
}

//+------------------------------------------------------------------+
//| [9] Deteksi Otomatis Mode Filling Broker (IOC/FOK/RETURN)        |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetOptimalFilling(string symbol)
{
   uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}

double NormalizeLotForSymbol(const string sym, double lot)
{
   double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(minLot  <= 0.0) minLot  = 0.01;
   if(maxLot  <= 0.0) maxLot  = 100.0;
   if(stepLot <= 0.0) stepLot = 0.01;
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);
   return NormalizeDouble(MathRound(lot / stepLot) * stepLot, 2);
}

//+------------------------------------------------------------------+
//| [10] MESIN BULK CLOSE KILAT (Asinkron / Non-Blocking)            |
//+------------------------------------------------------------------+
void FastBulkClose(bool currentSymbolOnly)
{
   ulong tickets[];
   int total = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t))
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         if(currentSymbolOnly && sym != _Symbol) continue;

         ArrayResize(tickets, total + 1);
         tickets[total++] = t;
      }
   }

   if(total == 0) return;

   g_isClosing = true;
   UpdateButtonState(true);

   for(int i = 0; i < total; i++)
   {
      if(!PositionSelectByTicket(tickets[i])) continue;

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);

      ENUM_POSITION_TYPE pType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string sym               = PositionGetString(POSITION_SYMBOL);
      double vol               = PositionGetDouble(POSITION_VOLUME);

      request.action       = TRADE_ACTION_DEAL;
      request.position     = tickets[i];
      request.symbol       = sym;
      request.volume       = vol;
      request.deviation    = InpSlippage;
      request.type         = (pType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      request.price        = (pType == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      request.type_filling = GetOptimalFilling(sym);

      if(!OrderSendAsync(request, result))
         Print("[FastBulkClose] Gagal kirim OrderSendAsync untuk tiket #", tickets[i], " | Retcode=", result.retcode);
   }
}

//+------------------------------------------------------------------+
//| [11] Event Handler Klik Tombol UI                                |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == PREFIX + "BTN_MINMAX")
      {
         g_isMinimized = !g_isMinimized;
         DeleteRadarObjects();
         CreateRadarHUD();
         ChartRedraw();
         return;
      }

      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(stepLot <= 0) stepLot = 0.01;

      if(sparam == PREFIX + "BTN_LOT_MINUS")
      {
         g_tradeLot -= InpLotStep;
         if(g_tradeLot < minLot) g_tradeLot = minLot;
         g_tradeLot = NormalizeDouble(MathRound(g_tradeLot / stepLot) * stepLot, 2);
         SetTxt(PREFIX + "V_TradeLot", DoubleToString(g_tradeLot, 2) + " Lot", COLOR_TEXT_VAL);
         ChartRedraw();
      }
      else if(sparam == PREFIX + "BTN_LOT_PLUS")
      {
         g_tradeLot += InpLotStep;
         if(g_tradeLot > maxLot) g_tradeLot = maxLot;
         g_tradeLot = NormalizeDouble(MathRound(g_tradeLot / stepLot) * stepLot, 2);
         SetTxt(PREFIX + "V_TradeLot", DoubleToString(g_tradeLot, 2) + " Lot", COLOR_TEXT_VAL);
         ChartRedraw();
      }
      else if(sparam == PREFIX + "BTN_EXEC_BUY")
      {
         ExecuteOneClickOrder(POSITION_TYPE_BUY);
         ChartRedraw();
      }
      else if(sparam == PREFIX + "BTN_EXEC_SELL")
      {
         ExecuteOneClickOrder(POSITION_TYPE_SELL);
         ChartRedraw();
      }
      else if(sparam == PREFIX + "BTN_HEDGE")
      {
         ExecuteEmergencyHedge();
         ChartRedraw();
      }
      else if(sparam == PREFIX + "BTN_REVERSE")
      {
         ExecuteReversePosition();
         ChartRedraw();
      }
      else if(sparam == PREFIX + "BTN_CLOSE_HALF")
      {
         ExecuteCloseHalf();
         ChartRedraw();
      }
      else if(sparam == PREFIX + "BTN_CLOSE_CURR")
      {
         FastBulkClose(true);
         ChartRedraw();
      }
      else if(sparam == PREFIX + "BTN_CLOSE_ALL")
      {
         FastBulkClose(false);
         ChartRedraw();
      }
   }
}

//+------------------------------------------------------------------+
//| [12] Kalkulasi & Update Radar Risiko + Zona Impas Keranjang      |
//+------------------------------------------------------------------+
void UpdateRiskRadar()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double buyLots      = 0, sellLots      = 0;
   double buyValSum    = 0, sellValSum    = 0;
   double symbolPL     = 0;
   int    posCountCurr = 0;
   int    posCountAll  = PositionsTotal();

   for(int i = posCountAll - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            posCountCurr++;
            double vol   = PositionGetDouble(POSITION_VOLUME);
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            if(type == POSITION_TYPE_BUY)       { buyLots  += vol; buyValSum  += price * vol; }
            else if(type == POSITION_TYPE_SELL) { sellLots += vol; sellValSum += price * vol; }

            symbolPL += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         }
      }
   }

   double avgBuyPrice  = (buyLots  > 0) ? (buyValSum  / buyLots)  : 0;
   double avgSellPrice = (sellLots > 0) ? (sellValSum / sellLots) : 0;
   double netLots      = buyLots - sellLots;
   bool   hasExposure  = (buyLots > 0 || sellLots > 0);

   // 1. AUTO TARGET POSITIF (+PROFIT TARGET)
   if(InpBasketTargetMoney > 0 && symbolPL >= InpBasketTargetMoney && !g_isClosing && posCountCurr > 0)
   {
      Print(StringFormat("🎯 AUTO TARGET POSITIF TERCAPAI ($%.2f)! Eksekusi Bulk Close...", symbolPL));
      if(InpEnableAlert) Alert("🎯 TARGET PROFIT KERANJANG TERCAPAI: $" + DoubleToString(symbolPL, 2));
      FastBulkClose(true);
      return;
   }

   // 2. AUTO TARGET NEGATIF (-MAX LOSS CUTLOSS)
   double maxLossLimit = -MathAbs(InpBasketMaxLossMoney);
   if(InpBasketMaxLossMoney > 0 && symbolPL <= maxLossLimit && !g_isClosing && posCountCurr > 0)
   {
      Print(StringFormat("🛑 AUTO TARGET NEGATIF (MAX LOSS) TERSENTUH ($%.2f)! Eksekusi Cutloss Darurat...", symbolPL));
      if(InpEnableAlert) Alert("🛑 AUTO CUTLOSS KERANJANG TERSENTUH: $" + DoubleToString(symbolPL, 2));
      FastBulkClose(true);
      return;
   }

   // --- KALKULASI ZONA UNTUNG (+) & RUGI (-) KERANJANG ---
   double bePrice      = 0;
   string netBiasStr   = "NETRAL (0.00 Lot)";
   string posZoneStr   = "-";
   string negZoneStr   = "-";
   string distZoneStr  = "-";
   color  distZoneClr  = COLOR_TEXT_DIM;
   string beLabelTxt   = "";
   double diffPts      = 0;

   if(hasExposure)
   {
      if(MathAbs(netLots) > 0.00001)
      {
         if(netLots > 0) // Net BUY
         {
            bePrice    = (buyValSum - sellValSum) / netLots;
            netBiasStr = StringFormat("+%.2f Lot BUY (Net Long)", netLots);
            posZoneStr = StringFormat("> %s (Harga Naik = Untung)", DoubleToString(bePrice, g_digits));
            negZoneStr = StringFormat("< %s (Harga Turun = Rugi)", DoubleToString(bePrice, g_digits));
            beLabelTxt = " (▲ Di atas = UNTUNG, ▼ Di bawah = RUGI)";

            diffPts = (bid - bePrice) / g_point;
            if(diffPts >= 0)
            {
               distZoneStr = StringFormat("✅ Di Zona Untung (+%d pts)", (int)MathRound(diffPts));
               distZoneClr = COLOR_SAFE;
            }
            else
            {
               distZoneStr = StringFormat("⏳ Butuh Naik +%d pts menuju Untung", (int)MathRound(-diffPts));
               distZoneClr = COLOR_WARN;
            }
         }
         else // Net SELL
         {
            bePrice    = (sellValSum - buyValSum) / MathAbs(netLots);
            netBiasStr = StringFormat("%.2f Lot SELL (Net Short)", netLots);
            posZoneStr = StringFormat("< %s (Harga Turun = Untung)", DoubleToString(bePrice, g_digits));
            negZoneStr = StringFormat("> %s (Harga Naik = Rugi)", DoubleToString(bePrice, g_digits));
            beLabelTxt = " (▼ Di bawah = UNTUNG, ▲ Di atas = RUGI)";

            diffPts = (bePrice - ask) / g_point;
            if(diffPts >= 0)
            {
               distZoneStr = StringFormat("✅ Di Zona Untung (+%d pts)", (int)MathRound(diffPts));
               distZoneClr = COLOR_SAFE;
            }
            else
            {
               distZoneStr = StringFormat("⏳ Butuh Turun +%d pts menuju Untung", (int)MathRound(-diffPts));
               distZoneClr = COLOR_WARN;
            }
         }

         // Trailing Basket
         if(InpEnableTrailingBE && posCountCurr > 0)
         {
            if(!g_trailingActive && diffPts >= InpTrailingStartPts)
            {
               g_trailingActive = true;
               Print("🏃 TRAILING BASKET AKTIF! Mengawal keuntungan keranjang...");
            }
            else if(g_trailingActive && diffPts <= InpTrailingLockPts && !g_isClosing)
            {
               Print("🏃 TRAILING LOCK TRIGGER! Mengunci profit keranjang sebelum berbalik...");
               if(InpEnableAlert) Alert("🏃 Trailing Lock Mengunci Profit Keranjang!");
               FastBulkClose(true);
               g_trailingActive = false;
               return;
            }
         }
      }
      else
      {
         netBiasStr  = "TERKUNCI (Hedge 100%)";
         posZoneStr  = "P/L Terkunci Tetap";
         negZoneStr  = "Kebal Fluktuasi Pasar";
         distZoneStr = "🔒 Posisi Hedging Imbang";
         distZoneClr = COLOR_ACCENT;
         g_trailingActive = false;
      }
   }
   else
   {
      g_trailingActive = false;
   }

   // Nilai Poin Stop Out
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ptVal1Lot  = (tickSize > 0) ? tickValue * (g_point / tickSize) : g_point;
   double totalPtVal = MathAbs(netLots) * ptVal1Lot;
   double ptsFloating = (totalPtVal > 0) ? (symbolPL / totalPtVal) : 0;

   double margin       = AccountInfoDouble(ACCOUNT_MARGIN);
   double marginLevel  = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double soLevel      = AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
   long   soMode       = AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);

   double equitySO     = (soMode == ACCOUNT_STOPOUT_MODE_PERCENT) ? (soLevel * margin / 100.0) : soLevel;
   double eqToSO       = equity - equitySO;
   double ptsToSO      = 0;
   double soPrice      = 0;
   string ptsToSOStr   = "-";
   string soPriceStr   = "-";

   if(hasExposure && margin > 0)
   {
      if(totalPtVal > 0)
      {
         ptsToSO = eqToSO / totalPtVal;
         if(ptsToSO < 0) ptsToSO = 0;
         ptsToSOStr = StringFormat("%d pts (%d pips)", (int)MathRound(ptsToSO), (int)MathRound(ptsToSO / 10.0));

         if(netLots > 0)
            soPrice = bid - ptsToSO * g_point;
         else
            soPrice = ask + ptsToSO * g_point;

         soPriceStr = DoubleToString(soPrice, g_digits);
      }
      else
      {
         ptsToSOStr = "TERKUNCI (Hedge 100%)";
         soPriceStr = "AMAN (Terkunci)";
      }
   }

   color statusColor = COLOR_SAFE;
   string statusText = "● STATUS: AMAN";
   g_currentStatus   = RISK_SAFE;

   if(hasExposure && totalPtVal > 0)
   {
      if(ptsToSO <= InpDangerPts || (marginLevel > 0 && marginLevel <= 150.0))
      {
         statusColor     = COLOR_DANGER;
         statusText      = "🚨 KRITIS / BAHAYA!";
         g_currentStatus = RISK_CRITICAL;

         if(InpAutoCutEmergency && !g_isClosing)
         {
            FastBulkClose(true);
         }
      }
      else if(ptsToSO <= InpWarningPts || (marginLevel > 0 && marginLevel <= 300.0))
      {
         statusColor     = COLOR_WARN;
         statusText      = "⚠️ WASPADA!";
         g_currentStatus = RISK_WARNING;
      }
   }

   // Update HUD Label
   SetTxt(PREFIX + "Badge", statusText, statusColor);

   string plStr = StringFormat("$%.2f (%+d pts)", symbolPL, (int)MathRound(ptsFloating));
   color  plClr = (symbolPL > 0.001) ? COLOR_SAFE : (symbolPL < -0.001 ? COLOR_DANGER : COLOR_TEXT_DIM);

   if(g_isMinimized)
   {
      SetTxt(PREFIX + "MiniPL", plStr, plClr);
      ChartRedraw();
      return;
   }

   SetTxt(PREFIX + "V_Bal",  StringFormat("$%.2f", balance), COLOR_TEXT_VAL);
   SetTxt(PREFIX + "V_Eq",   StringFormat("$%.2f", equity),  COLOR_TEXT_VAL);
   SetTxt(PREFIX + "V_PL",   plStr, plClr);

   // CARD 2 (Analisis Exposure)
   int avgDig = (g_digits > 0) ? (g_digits - 1) : 0;
   string bExp = (buyLots > 0) ? StringFormat("%.2f Lot @ %s ▲", buyLots, DoubleToString(avgBuyPrice, avgDig)) : "0.00 Lot";
   string sExp = (sellLots > 0)? StringFormat("%.2f Lot @ %s ▼", sellLots, DoubleToString(avgSellPrice, avgDig)) : "0.00 Lot";
   SetTxt(PREFIX + "V_BuyExp",   bExp, (buyLots > 0 ? COLOR_SAFE : COLOR_TEXT_DIM));
   SetTxt(PREFIX + "V_SellExp",  sExp, (sellLots > 0 ? COLOR_DANGER : COLOR_TEXT_DIM));
   SetTxt(PREFIX + "V_NetBias",  netBiasStr, (netLots > 0 ? COLOR_SAFE : (netLots < 0 ? COLOR_DANGER : COLOR_ACCENT)));
   SetTxt(PREFIX + "V_BEPrice",  (bePrice > 0 ? DoubleToString(bePrice, g_digits) : "-"), COLOR_ACCENT);
   SetTxt(PREFIX + "V_PosZone",  posZoneStr, COLOR_SAFE);
   SetTxt(PREFIX + "V_NegZone",  negZoneStr, COLOR_DANGER);
   SetTxt(PREFIX + "V_DistZone", distZoneStr, distZoneClr);

   // CARD 3 (Radar Stop Out)
   string mlStr = (margin > 0) ? StringFormat("%.1f%% (SO: %.0f%%)", marginLevel, soLevel) : "-";
   SetTxt(PREFIX + "V_ML",      mlStr, statusColor);
   SetTxt(PREFIX + "V_EqSO",    (margin > 0 ? StringFormat("$%.2f", eqToSO) : "-"), statusColor);
   SetTxt(PREFIX + "V_PtsSO",   ptsToSOStr, statusColor);
   SetTxt(PREFIX + "V_PriceSO", soPriceStr, statusColor);

   // Tombol BUY & SELL (Live Price)
   SetTxt(PREFIX + "BTN_EXEC_BUY",  StringFormat("▲ BUY  %s", DoubleToString(ask, g_digits)), clrWhite);
   SetTxt(PREFIX + "BTN_EXEC_SELL", StringFormat("▼ SELL  %s", DoubleToString(bid, g_digits)), clrWhite);

   // Tombol Bulk
   SetTxt(PREFIX + "BTN_CLOSE_CURR", StringFormat("⚡ BULK CLOSE %s (%d Posisi)", _Symbol, posCountCurr), clrWhite);
   SetTxt(PREFIX + "BTN_CLOSE_ALL",  StringFormat("💀 PANIC CLOSE ALL AKUN (%d Posisi)", posCountAll), clrWhite);

   UpdateChartLines(soPrice, bePrice, hasExposure, totalPtVal > 0, beLabelTxt);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| [13] Garis Visual Chart: Garis Stop Out & Breakeven              |
//+------------------------------------------------------------------+
void UpdateChartLines(double soPrice, double bePrice, bool hasExposure, bool isNotHedged, string beNote)
{
   string soLineName = PREFIX + "LINE_SO";
   string beLineName = PREFIX + "LINE_BE";

   if(InpShowSOLine && hasExposure && isNotHedged && soPrice > 0)
   {
      if(ObjectFind(0, soLineName) < 0)
         ObjectCreate(0, soLineName, OBJ_HLINE, 0, 0, soPrice);
      else
         ObjectSetDouble(0, soLineName, OBJPROP_PRICE, soPrice);

      ObjectSetInteger(0, soLineName, OBJPROP_COLOR, COLOR_DANGER);
      ObjectSetInteger(0, soLineName, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, soLineName, OBJPROP_WIDTH, 2);
      ObjectSetString (0, soLineName, OBJPROP_TEXT,  " 🚨 LEVEL STOP OUT / MARGIN CALL (" + DoubleToString(soPrice, g_digits) + ")");
   }
   else
   {
      ObjectDelete(0, soLineName);
   }

   if(InpShowBELine && hasExposure && bePrice > 0)
   {
      if(ObjectFind(0, beLineName) < 0)
         ObjectCreate(0, beLineName, OBJ_HLINE, 0, 0, bePrice);
      else
         ObjectSetDouble(0, beLineName, OBJPROP_PRICE, bePrice);

      ObjectSetInteger(0, beLineName, OBJPROP_COLOR, COLOR_ACCENT);
      ObjectSetInteger(0, beLineName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, beLineName, OBJPROP_WIDTH, 1);
      ObjectSetString (0, beLineName, OBJPROP_TEXT,  " 🎯 TITIK IMPAS KERANJANG: " + DoubleToString(bePrice, g_digits) + beNote);
   }
   else
   {
      ObjectDelete(0, beLineName);
   }
}

//+------------------------------------------------------------------+
//| [14] Pembuatan Tampilan GUI HUD (WIDESCREEN ANTI TUMPUK)         |
//+------------------------------------------------------------------+
void CreateRadarHUD()
{
   int x = InpX;
   int y = InpY;
   int w = InpWidth;

   // 1. JIKA MODE MINIMIZE
   if(g_isMinimized)
   {
      CreateBox(PREFIX + "MainBg", x, y, w, 44, COLOR_PANEL_BG, COLOR_BORDER);
      CreateLbl(PREFIX + "Title", x + 12, y + 13, "🛡️ RADAR PRO", COLOR_ACCENT, 9, true);
      CreateLbl(PREFIX + "MiniPL", x + 120, y + 13, "$0.00", COLOR_SAFE, 9, true);
      CreateLbl(PREFIX + "Badge", x + w - 45, y + 13, "● AMAN", COLOR_SAFE, 8, true, ANCHOR_RIGHT_UPPER);
      CreateBtn(PREFIX + "BTN_MINMAX", x + w - 35, y + 8, 26, 26, "▢", clrWhite, C'45,52,65');
      return;
   }

   // 2. JIKA MODE LENGKAP
   int h = 675;
   CreateBox(PREFIX + "MainBg", x, y, w, h, COLOR_PANEL_BG, COLOR_BORDER);

   // Header Panel
   CreateBox(PREFIX + "HeaderBg", x + 5, y + 5, w - 10, 36, COLOR_CARD_BG, COLOR_BORDER);
   CreateLbl(PREFIX + "Title", x + 15, y + 13, "🛡️ RISK RADAR PRO v2.80", COLOR_ACCENT, 10, true);
   CreateLbl(PREFIX + "Badge", x + w - 50, y + 13, "● STATUS: AMAN", COLOR_SAFE, 9, true, ANCHOR_RIGHT_UPPER);
   CreateBtn(PREFIX + "BTN_MINMAX", x + w - 38, y + 10, 26, 26, "—", clrWhite, C'45,52,65');

   int curY = y + 46;

   // STATUS ASSISTANT BANNER
   string tpslStatus = "AUTO TP/SL: NONAKTIF";
   if(InpEnableAutoTPSL)
   {
      if(InpTPSLMode == TPSL_MODE_USD)
         tpslStatus = StringFormat("AUTO TP: $%.2f %s | IOC%s",
                                   InpTPUsd,
                                   InpUseSL ? StringFormat("| SL: $%.2f", InpSLUsd) : "| SL: OFF",
                                   InpEnableCmdBridge ? " | BRIDGE: ON" : "");
      else
         tpslStatus = StringFormat("AUTO TP: %d pts %s | IOC%s",
                                   InpTPPoints,
                                   InpUseSL ? StringFormat("| SL: %d pts", InpSLPoints) : "| SL: OFF",
                                   InpEnableCmdBridge ? " | BRIDGE: ON" : "");
   }
   CreateBox(PREFIX + "SubHead", x + 5, curY, w - 10, 20, C'20,25,32', COLOR_BORDER);
   CreateLbl(PREFIX + "L_TPSLInfo", x + 15, curY + 4, "⚡ " + tpslStatus, COLOR_ACCENT, 7, true);

   curY += 25;

   // CARD TRADING CEPAT (ONE-CLICK BUY & SELL)
   CreateBox(PREFIX + "CardTrade", x + 5, curY, w - 10, 115, COLOR_CARD_BG, COLOR_BORDER);
   
   CreateLbl(PREFIX + "L_LotLabel", x + 15, curY + 8, "Volume Lot Trading:", COLOR_TEXT_DIM, 8);
   CreateBtn(PREFIX + "BTN_LOT_MINUS", x + 145, curY + 5, 34, 20, "-", COLOR_TEXT_VAL, C'45,50,65');
   CreateLbl(PREFIX + "V_TradeLot",  x + 230, curY + 7, DoubleToString(g_tradeLot, 2) + " Lot", COLOR_ACCENT, 9, true, ANCHOR_CENTER);
   CreateBtn(PREFIX + "BTN_LOT_PLUS",  x + 280, curY + 5, 34, 20, "+", COLOR_TEXT_VAL, C'45,50,65');

   int btnW = (w - 20) / 2;
   CreateBtn(PREFIX + "BTN_EXEC_BUY",  x + 7,        curY + 32, btnW, 36, "▲ BUY",  clrWhite, C'16,140,75');
   CreateBtn(PREFIX + "BTN_EXEC_SELL", x + 11 + btnW, curY + 32, btnW, 36, "▼ SELL", clrWhite, C'175,35,45');

   // BARIS TOOL TRADING LANJUTAN (HEDGE 1:1, REVERSE, CLOSE 50%)
   int toolW = (w - 24) / 3;
   CreateBtn(PREFIX + "BTN_HEDGE",      x + 7,             curY + 74, toolW, 32, "🔒 HEDGE 1:1", clrWhite, C'20,95,155');
   CreateBtn(PREFIX + "BTN_REVERSE",    x + 9 + toolW,     curY + 74, toolW, 32, "🔄 REVERSE",   clrWhite, C'180,105,15');
   CreateBtn(PREFIX + "BTN_CLOSE_HALF", x + 11 + toolW * 2, curY + 74, toolW, 32, "✂️ CLOSE 50%", clrWhite, C'95,45,135');

   curY += 123;

   // CARD 1: KEUANGAN & TARGET OTOMATIS (+ PROFIT & - CUTLOSS)
   CreateBox(PREFIX + "Card1", x + 5, curY, w - 10, 85, COLOR_CARD_BG, COLOR_BORDER);
   CreateLbl(PREFIX + "L_Bal",  x + 15, curY + 8,  "Saldo Akun:",  COLOR_TEXT_DIM, 8);
   CreateLbl(PREFIX + "V_Bal",  x + 115, curY + 8, "$0.00",        COLOR_TEXT_VAL, 8, true);
   CreateLbl(PREFIX + "L_Eq",   x + 220, curY + 8, "Equity:",      COLOR_TEXT_DIM, 8);
   CreateLbl(PREFIX + "V_Eq",   x + w - 15, curY + 8, "$0.00",     COLOR_TEXT_VAL, 8, true, ANCHOR_RIGHT_UPPER);

   CreateLbl(PREFIX + "L_PL",   x + 15, curY + 32, "Simbol Floating P/L:", COLOR_TEXT_DIM, 8);
   CreateLbl(PREFIX + "V_PL",   x + w - 15, curY + 32, "$0.00 (0 pts)", COLOR_TEXT_VAL, 9, true, ANCHOR_RIGHT_UPPER);

   string targetTxt  = (InpBasketTargetMoney > 0)  ? StringFormat("🎯 Target (+): +$%.2f", InpBasketTargetMoney)  : "🎯 Target: OFF";
   string cutlossTxt = (InpBasketMaxLossMoney > 0) ? StringFormat("🛑 Cutloss (-): -$%.2f", InpBasketMaxLossMoney) : "🛑 Cutloss: OFF";
   CreateLbl(PREFIX + "L_Target",  x + 15, curY + 56, targetTxt,  COLOR_SAFE,   8, true);
   CreateLbl(PREFIX + "L_Cutloss", x + 220, curY + 56, cutlossTxt, COLOR_DANGER, 8, true);

   curY += 92;

   // CARD 2: ANALISIS EXPOSURE & ZONA KERANJANG (HEDGE ANALYZER)
   CreateBox(PREFIX + "Card2", x + 5, curY, w - 10, 130, COLOR_CARD_BG, COLOR_BORDER);
   CreateLbl(PREFIX + "L_ExpTitle", x + 15, curY + 6, "ANALISIS KERANJANG & ZONA IMPAS", COLOR_ACCENT, 8, true);

   CreateLbl(PREFIX + "L_BuyExp",   x + 15, curY + 25, "Buy Exposure:",  COLOR_TEXT_DIM, 8);
   CreateLbl(PREFIX + "V_BuyExp",   x + w - 15, curY + 25, "0.00 Lot",   COLOR_TEXT_VAL, 8, true, ANCHOR_RIGHT_UPPER);

   CreateLbl(PREFIX + "L_SellExp",  x + 15, curY + 44, "Sell Exposure:", COLOR_TEXT_DIM, 8);
   CreateLbl(PREFIX + "V_SellExp",  x + w - 15, curY + 44, "0.00 Lot",   COLOR_TEXT_VAL, 8, true, ANCHOR_RIGHT_UPPER);

   CreateLbl(PREFIX + "L_NetBias",  x + 15, curY + 63, "Net Directional Bias:", COLOR_TEXT_DIM, 8);
   CreateLbl(PREFIX + "V_NetBias",  x + w - 15, curY + 63, "-",          COLOR_TEXT_VAL, 8, true, ANCHOR_RIGHT_UPPER);

   CreateLbl(PREFIX + "L_PosZone",  x + 15, curY + 82, "🟢 Zona Untung (+):", COLOR_TEXT_DIM, 8);
   CreateLbl(PREFIX + "V_PosZone",  x + w - 15, curY + 82, "-",          COLOR_SAFE,     8, true, ANCHOR_RIGHT_UPPER);

   CreateLbl(PREFIX + "L_NegZone",  x + 15, curY + 99, "🔴 Zona Rugi   (-):", COLOR_TEXT_DIM, 8);
   CreateLbl(PREFIX + "V_NegZone",  x + w - 15, curY + 99, "-",          COLOR_DANGER,   8, true, ANCHOR_RIGHT_UPPER);

   CreateLbl(PREFIX + "L_DistZone", x + 15, curY + 115, "Status Jarak Impas:", COLOR_TEXT_DIM, 8);
   CreateLbl(PREFIX + "V_DistZone", x + w - 15, curY + 115, "-",         COLOR_TEXT_VAL, 8, true, ANCHOR_RIGHT_UPPER);

   curY += 137;

   // CARD 3: RADAR MARGIN CALL / STOP OUT (VITAL)
   CreateBox(PREFIX + "Card3", x + 5, curY, w - 10, 105, COLOR_CARD_BG, COLOR_BORDER);
   CreateLbl(PREFIX + "L_RadarTitle", x + 15, curY + 6, "DETEKTOR MARGIN CALL / STOP OUT (VITAL)", COLOR_WARN, 8, true);

   CreateLbl(PREFIX + "L_ML",     x + 15, curY + 26, "Margin Level Akun:", COLOR_TEXT_DIM, 8);
   CreateLbl(PREFIX + "V_ML",     x + w - 15, curY + 26, "0.00%",       COLOR_TEXT_VAL, 8, true, ANCHOR_RIGHT_UPPER);

   CreateLbl(PREFIX + "L_EqSO",   x + 15, curY + 45, "Sisa Modal ke SO:", COLOR_TEXT_DIM, 8);
   CreateLbl(PREFIX + "V_EqSO",   x + w - 15, curY + 45, "$0.00",       COLOR_TEXT_VAL, 8, true, ANCHOR_RIGHT_UPPER);

   CreateLbl(PREFIX + "L_PtsSO",  x + 15, curY + 64, "Jarak Pts ke SO:", COLOR_TEXT_DIM, 8);
   CreateLbl(PREFIX + "V_PtsSO",  x + w - 15, curY + 64, "0 pts",       COLOR_TEXT_VAL, 8, true, ANCHOR_RIGHT_UPPER);

   CreateLbl(PREFIX + "L_PriceSO",x + 15, curY + 83, "Level Harga SO di Chart:", COLOR_TEXT_DIM, 8);
   CreateLbl(PREFIX + "V_PriceSO",x + w - 15, curY + 83, "-",           COLOR_TEXT_VAL, 8, true, ANCHOR_RIGHT_UPPER);

   curY += 112;

   // TOMBOL FAST BULK CLOSE
   CreateBtn(PREFIX + "BTN_CLOSE_CURR", x + 5, curY, w - 10, 36, "⚡ BULK CLOSE SYMBOL (0 Posisi)", clrWhite, COLOR_DANGER);
   curY += 41;
   CreateBtn(PREFIX + "BTN_CLOSE_ALL",  x + 5, curY, w - 10, 24, "💀 PANIC CLOSE ALL AKUN (0 Posisi)", COLOR_TEXT_DIM, C'38,42,54');
}

//+------------------------------------------------------------------+
//| [15] Helper Objek Grafik                                         |
//+------------------------------------------------------------------+
void UpdateButtonState(bool isClosing)
{
   if(isClosing)
   {
      ObjectSetString(0, PREFIX + "BTN_CLOSE_CURR", OBJPROP_TEXT, "⏳ MEMPROSES BULK CLOSE...");
      ObjectSetInteger(0, PREFIX + "BTN_CLOSE_CURR", OBJPROP_BGCOLOR, C'160,110,20');
   }
   else
   {
      ObjectSetInteger(0, PREFIX + "BTN_CLOSE_CURR", OBJPROP_BGCOLOR, COLOR_DANGER);
   }
}

int CountActivePositions(bool currentOnly)
{
   if(!currentOnly) return PositionsTotal();
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
            count++;
   }
   return count;
}

void DeleteRadarObjects()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, PREFIX) == 0)
         ObjectDelete(0, name);
   }
}

void CreateBox(string name, int x, int y, int w, int h, color bg, color border)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR,border);
   ObjectSetInteger(0, name, OBJPROP_BACK,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
}

void CreateLbl(string name, int x, int y, string txt, color clr, int size = 8, bool bold = false, ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT,       txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  size);
   ObjectSetString(0, name, OBJPROP_FONT,       bold ? "Segoe UI Semibold" : FONT_UI);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,    anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
}

void CreateBtn(string name, int x, int y, int w, int h, string txt, color txtClr, color bgClr)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
   ObjectSetString (0, name, OBJPROP_TEXT,         txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        txtClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, COLOR_BORDER);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,     8);
   ObjectSetString (0, name, OBJPROP_FONT,         "Segoe UI Semibold");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
}

void SetTxt(string name, string txt, color clr)
{
   ObjectSetString (0, name, OBJPROP_TEXT,  txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}
//+------------------------------------------------------------------+
