# Streak Reversal Indicator — MetaTrader 5

An MT5 port of [Streak Reversal on TradingView](https://www.tradingview.com/script/Gk62mf6d/) by **Uncle_the_shooter**, ported to MQL5 by [AlgoToolbox.com](https://algotoolbox.com/products/streak-reversal-indicator/) (**atoskueko**).

Streak Reversal looks for a run of same-color candles, then waits for **two candles in the opposite direction** and a confirmation break. It distinguishes signals that follow the EMA trend from those that go against it. A live checklist shows which conditions are met, pending, or blocking a setup.

> **Important:** This is an indicator, not an Expert Advisor. It does not place orders or manage broker-side stops. Current-candle signals are provisional; use the last **closed** candle for confirmed signals.

## TradingView vs MT5

**TradingView — original indicator**

<img width="1259" height="560" alt="streak-reversal99" src="https://github.com/user-attachments/assets/c3f709e1-17d1-449c-ab0d-6ced48ad328f" />


**MetaTrader 5 — port by AlgoToolbox.com**

<img width="1360" height="638" alt="streak-reversal3" src="https://github.com/user-attachments/assets/89b70e98-636f-4394-89ae-2ff0b095fb08" />


The screenshots above are unedited. TradingView and MT5 can have different prices, candle shapes, or timestamps because of their data feeds and chart settings; compare behavior using the same instrument, timeframe, inputs, and available history.

## Features

- Long and short streak-reversal signals, categorized as **Trend** or **Counter** relative to EMA(100).
- Optional ATR-based streak, signal-candle size, EMA movement, and EMA-distance filters.
- Opposite-wick and candle-close confirmation checks.
- Two-color EMA, signal labels, optional arrows, and first-opposite-candle markers.
- On-chart **LONG / SHORT** checklist with explanations on hover.
- Reference entry, SL, and three TP levels, with ATR-based or percentage-based stops.
- Optional MT5 **popup** alerts and four hidden buffers for EA/Strategy Tester access.

## Installation

1. Download the repository's `StreakReversal.mq5` file.
2. In MT5, open **File → Open Data Folder** and copy the file into `MQL5/Indicators/`.
3. Open the file in **MetaEditor** and press **F7** to compile.
4. Refresh **Navigator → Indicators** in MT5, then add **Streak Reversal** to a chart.
5. Leave **Show table** enabled to see the condition checklist while learning the setup.

The indicator source does not declare external MQL5 library dependencies. If MetaEditor reports an error, check its Errors tab; compilation and trading performance depend on your MT5 environment and data.

## Signal logic

### Long signal

1. At least `Min Streak` consecutive **bearish** candles (default: **2**).
2. With the streak ATR filter on, the move from the first bearish candle's **high** to the streak's final **low** is at least **1.5 × ATR(100)**.
3. Two consecutive **bullish** candles follow the streak.
4. The **second** bullish candle closes **above** the first bullish candle's body top, or above its high if High/Low confirmation is selected.
5. Enabled wick, candle-size, EMA-movement, category, and EMA-distance filters also pass.

### Short signal

The reverse: a bullish streak, then two bearish candles; the second bearish candle must close **below** the first one's body bottom (or low with High/Low confirmation). The short signal checks the **lower** wick; the long signal checks the **upper** wick.

| Signal | Trend category | Counter category |
|---|---|---|
| **Long** | Signal close **above** EMA | Otherwise |
| **Short** | Signal close **below** EMA | Otherwise |

The checklist's **Trend strength** row describes EMA movement but is *informational only*. Its thresholds do not filter entries unless the separate **Flat EMA filter** is enabled. ATR and EMA values require sufficient chart history to initialize.

## Settings at a glance

These are the defaults in the supplied MQL5 implementation. Disabled filters are shown as **off** even if a threshold is listed.

| Group | Settings and defaults | Purpose |
|---|---|---|
| **1. Signals** | Long, Short, Trend, Counter: **on** | Choose allowed directions and categories. |
| **2. Streak** | Minimum **2** candles; ATR move filter **on**; minimum **1.5 ATR(100)** | Require a meaningful preceding move. |
| **3. Signal candle** | Confirm against **body**; opposite wick filter **on**, maximum **40%**; size filter **off**, minimum **0.30 ATR(100)** if enabled | Check the second opposite candle. Size can measure body or full range. |
| **4. EMA** | EMA **100**; flat EMA filter **off**, window **20** bars, minimum **0.50 ATR(100)** if enabled; strength labels **1.0 / 2.5 ATR** | Display and optionally filter EMA movement. |
| **5. EMA distance** | Trend maximum filter **off**, **2.0 ATR**; counter minimum filter **off**, **3.0 ATR**; ATR length **100** | Optionally constrain the signal close's distance from EMA. |
| **6. Colors** | Teal/red signals and dark checklist | Configure display colors. |
| **7. Shapes** | Signal arrows **off**; first-opposite-candle marker **on** | Control chart markers. |
| **8. Labels** | Distance labels **on**; size **small**; offset **0.6 ATR** | Control signal labels. |
| **9. EMA display** | Visible **on**, line width **3** | Show or hide the EMA. |
| **10. Table** | **On** | Show the live LONG/SHORT condition checklist. |
| **11. TP/SL** | Levels **on**; ATR stop **on**: **1.5 × ATR(14)**; percent stop **1%** if chosen; targets **1R / 2R / 3R** | Draw *reference* entry, stop, and targets. |
| **12. TP/SL display** | SL, TP1, TP2, TP3: **on** | Choose which reference lines appear. |
| **13. Alerts** | Alerts **off**; alert on bar close **on** | Enable MT5 popup alerts, normally after confirmation. |

### Understanding the checklist

`✓` means passed, `✗` means blocking, `…` means still waiting, and `○` means the filter is off. The **SIGNAL** row shows `YES`, `NO` and blocking reasons, or `waiting`. Hover over a cell in MT5 for its tooltip. Because the checklist evaluates the **current** candle, its contents can change during that candle.

## Reference TP/SL lines

After a signal is confirmed on a **closed bar**, the indicator uses that candle's **close** as a reference entry. By default, the SL distance is **1.5 × ATR(14)**, and TP1/TP2/TP3 are **1R/2R/3R** from entry. With ATR-based SL disabled, the alternative stop distance is **1% of entry**.

While active, lines extend 12 bars beyond the current bar. If a later **closed** bar reaches the SL or the **furthest enabled TP**, the displayed lines freeze at that hit bar. Reaching TP1 alone does **not** necessarily end the displayed setup. A new signal can replace it. These chart levels are not placed as real orders, and actual fills may differ.

## Confirmed signals and repainting

The forming bar is recalculated on every tick. Its signal labels, hidden buffers, EMA color, and checklist can change or vanish before it closes. Read signals on the **last closed bar** to avoid acting on provisional signals. The code does not intentionally revise prior closed-bar signals on subsequent ticks, although changed history, symbol data, or settings can change a fresh calculation.

`Alerts on bar close` is enabled by default, but `Enable alerts` is **off** until you turn it on. The source uses MT5's `Alert()` (popup); it does not call `SendMail()` or `SendNotification()`.

## EA integration

Four hidden buffers contain `1.0` on signal bars and `EMPTY_VALUE` otherwise:

| `CopyBuffer()` buffer index | Signal |
|---:|---|
| `8` | Long Trend |
| `9` | Long Counter |
| `10` | Short Trend |
| `11` | Short Counter |

Example: query buffer **8** on shift **1** (the last **closed** bar). This snippet belongs inside an EA function; create the indicator handle once, check it, and release it on deinitialization.

```cpp
// Assume 'handle' is a valid iCustom(_Symbol, _Period, "StreakReversal") handle.
double signal[];
if(CopyBuffer(handle, 8, 1, 1, signal) == 1 && signal[0] == 1.0)
{
   Print("Long Trend signal on the last closed candle");
}
```

Use a **new-bar check** in the EA so the same closed-bar signal is not processed on every tick. `shift 0` is the still-forming bar and may change. If you pass custom inputs to `iCustom()`, keep the source declaration order.

## License and credits

The MQL5 source identifies the original Pine Script author as **Uncle_the_shooter** and the MQL5 porter as **AlgoToolbox.com (atoskueko)**. The supplied code identifies its license as **Mozilla Public License 2.0** (`MPL-2.0`): see the full text in [`LICENSE`](LICENSE). Retain applicable copyright and license notices and comply with the MPL when distributing covered source or compiled versions. The MPL does not itself grant rights to third-party trademarks or automatically license the screenshots.

- Original: [TradingView Streak Reversal](https://www.tradingview.com/script/Gk62mf6d/)
- MT5 port: [AlgoToolbox.com — Streak Reversal Indicator](https://algotoolbox.com/products/streak-reversal-indicator/)
- License text: [Mozilla Public License 2.0](https://www.mozilla.org/en-US/MPL/2.0/)

> **Risk notice:** The indicator is a decision-support tool, not financial advice or a guaranteed trading strategy. Test on demo data first and size positions according to your own risk limits.
