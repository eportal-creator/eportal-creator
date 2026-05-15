#!/usr/bin/env python3
"""Trade visualization — Project BB Breakout v3.1 (XAUUSD @ 0.01 lots)"""

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

np.random.seed(42)
plt.style.use('dark_background')

fig, axes = plt.subplots(2, 2, figsize=(20, 13))
fig.patch.set_facecolor('#0d1117')
fig.suptitle(
    'Project BB Breakout v3.1  —  XAUUSD @ 0.01 lots\n'
    'How BB and BO Trades Are Entered and Managed',
    fontsize=15, fontweight='bold', color='#e6edf3', y=0.99
)
plt.subplots_adjust(hspace=0.45, wspace=0.55, top=0.93, bottom=0.09, left=0.04, right=0.97)

# ── Palette ────────────────────────────────────────────
C_SL       = '#ff5555'
C_BE_SL    = '#ffaa44'
C_FILL     = '#50fa7b'
C_BE       = '#f1fa8c'
C_TRAIL    = '#8be9fd'
C_TRAIL_SL = '#55bbcc'
C_BAND     = '#bd93f9'
C_PRICE    = '#6699ff'
C_SIGNAL   = '#ffb86c'

# ── Helpers ────────────────────────────────────────────
def setup_ax(ax, title, ylim):
    ax.set_facecolor('#161b22')
    ax.set_title(title, color='#79c0ff', fontsize=11.5, fontweight='bold', pad=10)
    ax.set_ylim(ylim[0], ylim[1])
    ax.set_xlim(0, 24)
    ax.grid(True, alpha=0.1, linewidth=0.4)
    ax.set_xticks([])
    ax.tick_params(axis='y', labelsize=8.5, colors='#6e7681')
    for s in ['top', 'right', 'bottom']:
        ax.spines[s].set_visible(False)
    ax.spines['left'].set_color('#2d333b')
    ax.axvline(x=20.3, color='#2d333b', linewidth=0.8, alpha=0.5)

def price_path(waypoints, noise=0.05):
    xs = [p[0] for p in waypoints]
    ys = [p[1] for p in waypoints]
    ax_x, ax_y = [], []
    for i in range(len(xs) - 1):
        n = max(10, int((xs[i+1] - xs[i]) * 18))
        xi = np.linspace(xs[i], xs[i+1], n)
        yi = np.linspace(ys[i], ys[i+1], n)
        nz = np.random.normal(0, noise, n)
        nz[0] = nz[-1] = 0
        ax_x.extend(xi[:-1])
        ax_y.extend((yi + nz)[:-1])
    ax_x.append(xs[-1]); ax_y.append(ys[-1])
    return np.array(ax_x), np.array(ax_y)

def add_hline(ax, y, color, style='--', lw=1.3, x_end=20):
    ax.hlines(y, 0, x_end, colors=color, linestyles=style, linewidth=lw, alpha=0.8, zorder=2)

def add_label(ax, y, text, color, fs=8.5):
    ax.text(20.6, y, text, color=color, fontsize=fs, va='center', fontweight='bold',
            bbox=dict(facecolor='#0d1117', edgecolor='none', pad=1.5))

def mark_fill(ax, x, y, color=C_FILL):
    ax.plot(x, y, 'o', color=color, markersize=11, zorder=8,
            markeredgecolor='white', markeredgewidth=0.8)
    ax.plot(x, y, '*', color='white', markersize=6, zorder=9)

def signal_arrow(ax, x_bar, y_tip, y_text, text, ylim_top, up=True):
    ax.annotate(
        text,
        xy=(x_bar, y_tip),
        xytext=(x_bar, y_text),
        color=C_SIGNAL, fontsize=8, ha='center', va='bottom' if up else 'top',
        style='italic',
        bbox=dict(facecolor='#161b22', edgecolor=C_SIGNAL, boxstyle='round,pad=0.4', alpha=0.9),
        arrowprops=dict(arrowstyle='->', color=C_SIGNAL, lw=1.4),
        zorder=10
    )

def retrace_note(ax, x, y, text, right=True):
    xoff = 1.2 if right else -1.2
    ax.annotate(
        text,
        xy=(x, y), xytext=(x + xoff, y),
        color='#aaaaaa', fontsize=8, ha='left' if right else 'right', va='center',
        arrowprops=dict(arrowstyle='->', color='#aaaaaa', lw=1.0,
                        connectionstyle='arc3,rad=0.25'),
        zorder=10
    )


# ════════════════════════════════════════════════════════
#  ① BB BUY — Mean Reversion at Lower Band
# ════════════════════════════════════════════════════════
ax = axes[0, 0]
setup_ax(ax, '① BB BUY  —  Fade at Lower Band', (2340.3, 2345.1))

for y, col, sty, lw, lbl in [
    (2341.50, C_SL,    '-',  1.8, 'STOP LOSS  −$1.00'),
    (2342.50, C_FILL,  '-',  1.8, 'FILL @ 2342.50\n(BB Lower Band)'),
    (2342.60, C_BE_SL, '--', 1.3, 'BE SL = entry +$0.10'),
    (2342.75, C_BE,    ':',  1.3, 'BE fires  +$0.25'),
    (2342.95, C_TRAIL, ':',  1.3, 'Trail START  +$0.45'),
]:
    add_hline(ax, y, col, sty, lw)
    add_label(ax, y, lbl, col)

wp = [(0, 2344.2), (4, 2343.5), (6, 2343.0), (7, 2342.85),
      (7.5, 2342.05), (8.2, 2342.80),
      (9.0, 2342.55), (9.6, 2342.50),
      (11,  2342.75), (13, 2343.05), (16, 2343.60), (19, 2344.10), (20, 2344.25)]
px, py = price_path(wp, noise=0.04)
ax.plot(px, py, color=C_PRICE, linewidth=2.2, zorder=5)

mask = px >= 13.5
ax.plot(px[mask], py[mask] - 0.30, color=C_TRAIL_SL, lw=1.3, ls='-.', zorder=4, alpha=0.85)
ax.fill_between(px[mask], py[mask] - 0.30, 2342.95, alpha=0.07, color=C_TRAIL)

mark_fill(ax, 9.6, 2342.50)
signal_arrow(ax, 7.5, 2342.10, 2340.70,
    'bar[1]: low wicks below BB Lower\nclose back above → SIGNAL\n→ BuyLimit @ 2342.50',
    2345.1, up=False)
ax.text(1, 2344.6, '← price declining', color='#666', fontsize=8.5, style='italic')
ax.text(16, 2344.6, 'price rising →', color='#666', fontsize=8.5, style='italic')
ax.text(18.5, 2343.80, 'Trail SL\n↑ follows', color=C_TRAIL_SL, fontsize=7.5, ha='center')

# ════════════════════════════════════════════════════════
#  ② BB SELL — Mean Reversion at Upper Band
# ════════════════════════════════════════════════════════
ax = axes[0, 1]
setup_ax(ax, '② BB SELL  —  Fade at Upper Band', (2346.9, 2350.8))

for y, col, sty, lw, lbl in [
    (2349.50, C_SL,    '-',  1.8, 'STOP LOSS  +$1.00'),
    (2348.50, C_FILL,  '-',  1.8, 'FILL @ 2348.50\n(BB Upper Band)'),
    (2348.40, C_BE_SL, '--', 1.3, 'BE SL = entry −$0.10'),
    (2348.25, C_BE,    ':',  1.3, 'BE fires  −$0.25'),
    (2348.05, C_TRAIL, ':',  1.3, 'Trail START  −$0.45'),
]:
    add_hline(ax, y, col, sty, lw)
    add_label(ax, y, lbl, col)

wp2 = [(0, 2347.3), (4, 2347.9), (6, 2348.2), (7, 2348.35),
       (7.5, 2348.98), (8.2, 2348.25),
       (9.0, 2348.55), (9.6, 2348.50),
       (11,  2348.25), (13, 2347.95), (16, 2347.40), (19, 2347.10), (20, 2347.00)]
px2, py2 = price_path(wp2, noise=0.04)
ax.plot(px2, py2, color=C_PRICE, linewidth=2.2, zorder=5)

mask2 = px2 >= 13.5
ax.plot(px2[mask2], py2[mask2] + 0.30, color=C_TRAIL_SL, lw=1.3, ls='-.', zorder=4, alpha=0.85)
ax.fill_between(px2[mask2], py2[mask2] + 0.30, 2348.05, alpha=0.07, color=C_TRAIL)

mark_fill(ax, 9.6, 2348.50)
signal_arrow(ax, 7.5, 2348.90, 2350.50,
    'bar[1]: high wicks above BB Upper\nclose back below → SIGNAL\n→ SellLimit @ 2348.50',
    2350.8, up=True)
ax.text(1, 2347.1, '← price rising', color='#666', fontsize=8.5, style='italic')
ax.text(15, 2347.1, 'price falling →', color='#666', fontsize=8.5, style='italic')
ax.text(18.5, 2347.25, '↓ follows\nTrail SL', color=C_TRAIL_SL, fontsize=7.5, ha='center')

# ════════════════════════════════════════════════════════
#  ③ BO BUY — Breakout Retest at Broken Swing High
# ════════════════════════════════════════════════════════
ax = axes[1, 0]
setup_ax(ax, '③ BO BUY  —  Breakout: Wait for Retest at Swing High', (2344.5, 2350.2))

SW_H = 2346.80
for y, col, sty, lw, lbl in [
    (2345.80, C_SL,    '-',  1.8, 'STOP LOSS  −$1.00'),
    (SW_H,    C_FILL,  '-',  1.8, 'FILL @ 2346.80\n(Broken Swing High)'),
    (2346.90, C_BE_SL, '--', 1.3, 'BE SL = entry +$0.10'),
    (2347.05, C_BE,    ':',  1.3, 'BE fires  +$0.25'),
    (2347.25, C_TRAIL, ':',  1.3, 'Trail START  +$0.45'),
]:
    add_hline(ax, y, col, sty, lw)
    add_label(ax, y, lbl, col)

ax.hlines(SW_H, 0, 7, colors=C_BAND, linestyles=(0, (5, 4)), linewidth=1.2, alpha=0.65)
ax.text(3.5, SW_H + 0.08, 'Swing High = old resistance', color=C_BAND,
        fontsize=8, va='bottom', ha='center')

wp3 = [(0, 2345.2), (3, 2345.7), (6, 2346.4), (7.0, 2346.55),
       (7.7, 2347.35), (8.1, 2347.25),
       (8.8, 2347.40), (10.0, 2346.80),
       (11.5, 2347.15), (13, 2347.60), (16, 2348.40), (19, 2349.10), (20, 2349.30)]
px3, py3 = price_path(wp3, noise=0.04)
ax.plot(px3, py3, color=C_PRICE, linewidth=2.2, zorder=5)

mask3 = px3 >= 14
ax.plot(px3[mask3], py3[mask3] - 0.30, color=C_TRAIL_SL, lw=1.3, ls='-.', zorder=4, alpha=0.85)
ax.fill_between(px3[mask3], py3[mask3] - 0.30, 2347.25, alpha=0.07, color=C_TRAIL)

mark_fill(ax, 10.0, SW_H)
retrace_note(ax, 10.0, SW_H + 0.15, 'price retraces\n(2-min window)', right=False)
signal_arrow(ax, 7.7, 2347.30, 2344.85,
    'bar[1]: breaks & closes\nABOVE Swing High → SIGNAL\n→ BuyLimit @ 2346.80',
    2350.2, up=False)
ax.text(1, 2349.7, '← uptrend', color='#666', fontsize=8.5, style='italic')
ax.text(16, 2349.7, 'trend continues →', color='#666', fontsize=8.5, style='italic')
ax.text(18.5, 2349.0, 'Trail SL\n↑ follows', color=C_TRAIL_SL, fontsize=7.5, ha='center')

# ════════════════════════════════════════════════════════
#  ④ BO SELL — Breakdown Retest at Broken Swing Low
# ════════════════════════════════════════════════════════
ax = axes[1, 1]
setup_ax(ax, '④ BO SELL  —  Breakdown: Wait for Retest at Swing Low', (2335.8, 2342.4))

SW_L = 2340.20
for y, col, sty, lw, lbl in [
    (2341.20, C_SL,    '-',  1.8, 'STOP LOSS  +$1.00'),
    (SW_L,    C_FILL,  '-',  1.8, 'FILL @ 2340.20\n(Broken Swing Low)'),
    (2340.10, C_BE_SL, '--', 1.3, 'BE SL = entry −$0.10'),
    (2339.95, C_BE,    ':',  1.3, 'BE fires  −$0.25'),
    (2339.75, C_TRAIL, ':',  1.3, 'Trail START  −$0.45'),
]:
    add_hline(ax, y, col, sty, lw)
    add_label(ax, y, lbl, col)

ax.hlines(SW_L, 0, 7, colors=C_BAND, linestyles=(0, (5, 4)), linewidth=1.2, alpha=0.65)
ax.text(3.5, SW_L - 0.10, 'Swing Low = old support', color=C_BAND,
        fontsize=8, va='top', ha='center')

wp4 = [(0, 2341.7), (3, 2341.2), (6, 2340.6), (7.0, 2340.45),
       (7.7, 2339.65), (8.1, 2339.75),
       (8.8, 2339.60), (10.0, 2340.20),
       (11.5, 2339.85), (13, 2339.40), (16, 2338.60), (19, 2337.10), (20, 2336.80)]
px4, py4 = price_path(wp4, noise=0.04)
ax.plot(px4, py4, color=C_PRICE, linewidth=2.2, zorder=5)

mask4 = px4 >= 14
ax.plot(px4[mask4], py4[mask4] + 0.30, color=C_TRAIL_SL, lw=1.3, ls='-.', zorder=4, alpha=0.85)
ax.fill_between(px4[mask4], py4[mask4] + 0.30, 2339.75, alpha=0.07, color=C_TRAIL)

mark_fill(ax, 10.0, SW_L)
retrace_note(ax, 10.0, SW_L - 0.15, 'price retraces\n(2-min window)', right=False)
signal_arrow(ax, 7.7, 2339.70, 2342.15,
    'bar[1]: breaks & closes\nBELOW Swing Low → SIGNAL\n→ SellLimit @ 2340.20',
    2342.4, up=True)
ax.text(1, 2341.9, '← downtrend', color='#666', fontsize=8.5, style='italic')
ax.text(15, 2336.1, 'trend continues →', color='#666', fontsize=8.5, style='italic')
ax.text(18.5, 2337.3, '↓ follows\nTrail SL', color=C_TRAIL_SL, fontsize=7.5, ha='center')

# ── Legend ────────────────────────────────────────────
handles = [
    mpatches.Patch(color=C_PRICE,    label='Price'),
    mpatches.Patch(color=C_SL,       label='Stop Loss  ($1.00)'),
    mpatches.Patch(color=C_FILL,     label='Limit Fill  (entry point)'),
    mpatches.Patch(color=C_BE_SL,    label='BE Stop Loss  (entry ± $0.10)'),
    mpatches.Patch(color=C_BE,       label='BE trigger  (± $0.25 profit)'),
    mpatches.Patch(color=C_TRAIL,    label='Trail activates  (± $0.45 profit)'),
    mpatches.Patch(color=C_TRAIL_SL, label='Trail SL  (price ± $0.30)'),
    mpatches.Patch(color=C_BAND,     label='Swing Level  (BO only)'),
]
fig.legend(handles=handles, loc='lower center', ncol=4, fontsize=9,
           framealpha=0.2, facecolor='#1a1a2a', edgecolor='#444',
           labelcolor='white', bbox_to_anchor=(0.5, 0.005), handlelength=1.5)

out = 'bb_bo_trade_visual.png'
plt.savefig(out, dpi=150, bbox_inches='tight', facecolor='#0d1117')
print(f'Saved: {out}')
