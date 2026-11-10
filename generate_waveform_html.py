#!/usr/bin/env python3
import json

def parse_vcd(filename):
    signals = {}
    time_series = [] # list of (timestamp, {sig_name: value})
    current_time = 0
    current_vals = {}

    id_to_name = {
        '!': 'clk',
        '"': 'rst',
        '#': 'start',
        '$': 'angle_in',
        '%': 'done',
        '&': 'cosine_out',
        "'": 'sine_out',
        '(': 'fsm_state',
        ')': 'count',
        '*': 'sigma',
        '+': 'x_reg',
        ',': 'y_reg',
        '-': 'z_reg'
    }

    for name in id_to_name.values():
        current_vals[name] = 0

    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith('$'):
                continue
            if line.startswith('#'):
                current_time = int(line[1:])
                time_series.append((current_time, dict(current_vals)))
                continue

            # Scalar values: e.g. 0!, 1", 1#
            if len(line) >= 2 and line[0] in '01xz' and line[1:] in id_to_name:
                sig = id_to_name[line[1:]]
                val = int(line[0]) if line[0] in '01' else 0
                current_vals[sig] = val
                if time_series:
                    time_series[-1][1][sig] = val
            # Vector values: e.g. b0000000000000000 $
            elif line.startswith('b'):
                parts = line.split(' ')
                if len(parts) == 2 and parts[1] in id_to_name:
                    sig = id_to_name[parts[1]]
                    bin_str = parts[0][1:]
                    val = int(bin_str, 2)
                    current_vals[sig] = val
                    if time_series:
                        time_series[-1][1][sig] = val

    return time_series

def format_signal_val(sig, val):
    if sig in ['clk', 'rst', 'start', 'done', 'sigma']:
        return str(val)
    elif sig == 'fsm_state':
        states = {0: 'IDLE', 1: 'LOAD', 2: 'ITER', 3: 'DONE'}
        return states.get(val, str(val))
    elif sig == 'count':
        return str(val)
    elif sig in ['x_reg', 'y_reg', 'z_reg']:
        # 22-bit signed
        if val >= (1 << 21):
            val -= (1 << 22)
        return str(val)
    elif sig in ['cosine_out', 'sine_out']:
        # 16-bit signed Q1.15
        s = val
        if s >= 32768: s -= 65536
        flt = s / 32768.0
        return f"0x{val:04X} ({flt:+.3f})"
    elif sig == 'angle_in':
        s = val
        if s >= 32768: s -= 65536
        deg = (s / 8192.0) * (180.0 / 3.1415926535)
        return f"0x{val:04X} ({deg:+.0f}°)"
    return str(val)

def generate_html():
    raw_series = parse_vcd('cordic_tb.vcd')
    
    # Compress time series: only keep points where timestamp changes
    data_points = []
    for t, vals in raw_series:
        formatted = {k: format_signal_val(k, v) for k, v in vals.items()}
        raw_num = {k: v for k, v in vals.items()}
        data_points.append({'t': t, 'raw': raw_num, 'fmt': formatted})

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>CORDIC Waveform Viewer</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #0d1117; color: #c9d1d9; overflow-x: hidden; }}
  header {{ background: #161b22; padding: 14px 20px; border-bottom: 1px solid #30363d; display: flex; justify-content: space-between; align-items: center; position: sticky; top: 0; z-index: 100; }}
  h1 {{ font-size: 18px; color: #58a6ff; font-weight: 600; }}
  .toolbar {{ display: flex; gap: 8px; align-items: center; }}
  button, select {{ background: #21262d; color: #c9d1d9; border: 1px solid #30363d; padding: 6px 12px; border-radius: 6px; cursor: pointer; font-size: 13px; }}
  button:hover, select:hover {{ background: #30363d; color: #58a6ff; border-color: #58a6ff; }}
  .container {{ display: flex; height: calc(100vh - 60px); }}
  .sidebar {{ width: 240px; background: #161b22; border-right: 1px solid #30363d; overflow-y: auto; flex-shrink: 0; }}
  .sig-row {{ height: 38px; display: flex; align-items: center; padding: 0 12px; border-bottom: 1px solid #21262d; font-family: monospace; font-size: 13px; font-weight: 600; color: #79c0ff; }}
  .canvas-container {{ flex: 1; overflow: auto; position: relative; background: #0d1117; }}
  canvas {{ display: block; }}
  .info-bar {{ position: fixed; bottom: 0; left: 0; right: 0; background: #161b22; border-top: 1px solid #30363d; padding: 8px 16px; font-size: 13px; display: flex; gap: 20px; font-family: monospace; color: #8b949e; z-index: 90; }}
  .info-bar span b {{ color: #58a6ff; }}
  .badge {{ background: #238636; color: white; padding: 2px 8px; border-radius: 12px; font-size: 11px; margin-left: 8px; }}
</style>
</head>
<body>
<header>
  <div>
    <h1>CORDIC 16-Bit Hardware Waveforms <span class="badge">18-CYCLE LATENCY</span></h1>
  </div>
  <div class="toolbar">
    <label style="font-size: 13px;">Jump to Test:</label>
    <select id="jumpSelect" onchange="jumpToTime(this.value)">
      <option value="0">Reset Sequence (0 ns)</option>
      <option value="110">T01: 0° Angle (110 ns)</option>
      <option value="530">T02: 15° Angle (530 ns)</option>
      <option value="950">T03: 30° Angle (950 ns)</option>
      <option value="1370">T04: 45° Angle (1370 ns)</option>
      <option value="1790">T05: 60° Angle (1790 ns)</option>
      <option value="2210">T06: 75° Angle (2210 ns)</option>
      <option value="2630">T07: 90° Angle (2630 ns)</option>
      <option value="3050">T08: 120° Angle (3050 ns)</option>
      <option value="4730">T12: -15° Angle (4730 ns)</option>
      <option value="5570">T14: -45° Angle (5570 ns)</option>
      <option value="8930">T22: Back-to-Back (8930 ns)</option>
    </select>
    <button onclick="zoom(1.25)">Zoom In (+)</button>
    <button onclick="zoom(0.8)">Zoom Out (-)</button>
    <button onclick="resetZoom()">Fit</button>
  </div>
</header>

<div class="container">
  <div class="sidebar" id="sidebar"></div>
  <div class="canvas-container" id="canvasContainer">
    <canvas id="waveCanvas"></canvas>
  </div>
</div>

<div class="info-bar" id="infoBar">
  <span>Hover cursor over waveforms to inspect signal values at that timestamp</span>
</div>

<script>
const data = {json.dumps(data_points)};
const signals = [
  {{ name: 'clk', type: 'digital', color: '#58a6ff' }},
  {{ name: 'rst', type: 'digital', color: '#ff7b72' }},
  {{ name: 'start', type: 'digital', color: '#7ee787' }},
  {{ name: 'done', type: 'digital', color: '#d2a8ff' }},
  {{ name: 'angle_in', type: 'bus', color: '#ffa657' }},
  {{ name: 'fsm_state', type: 'bus', color: '#f2cc60' }},
  {{ name: 'count', type: 'bus', color: '#79c0ff' }},
  {{ name: 'sigma', type: 'digital', color: '#bc8cff' }},
  {{ name: 'x_reg', type: 'bus', color: '#56d364' }},
  {{ name: 'y_reg', type: 'bus', color: '#e3b341' }},
  {{ name: 'z_reg', type: 'bus', color: '#ff7b72' }},
  {{ name: 'cosine_out', type: 'bus', color: '#3fb950' }},
  {{ name: 'sine_out', type: 'bus', color: '#a5d6ff' }}
];

const ROW_HEIGHT = 38;
let scaleX = 1.2; // pixels per 10ns
const canvas = document.getElementById('waveCanvas');
const ctx = canvas.getContext('2d');
const container = document.getElementById('canvasContainer');

function buildSidebar() {{
  const sb = document.getElementById('sidebar');
  sb.innerHTML = '';
  // Time header placeholder
  const th = document.createElement('div');
  th.className = 'sig-row';
  th.style.color = '#8b949e';
  th.textContent = 'TIME (ns)';
  sb.appendChild(th);

  signals.forEach(s => {{
    const r = document.createElement('div');
    r.className = 'sig-row';
    r.style.color = s.color;
    r.textContent = s.name;
    sb.appendChild(r);
  }});
}}

function render() {{
  const maxTime = data[data.length - 1].t;
  const width = Math.max(window.innerWidth - 240, maxTime * scaleX + 100);
  const height = (signals.length + 1) * ROW_HEIGHT;
  canvas.width = width;
  canvas.height = height;

  ctx.clearRect(0, 0, width, height);

  // Time grid & ruler
  ctx.fillStyle = '#161b22';
  ctx.fillRect(0, 0, width, ROW_HEIGHT);
  ctx.strokeStyle = '#21262d';
  ctx.font = '11px monospace';
  ctx.fillStyle = '#8b949e';

  for (let t = 0; t <= maxTime; t += 100) {{
    const x = t * scaleX;
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, height);
    ctx.stroke();
    ctx.fillText(t + 'ns', x + 4, 24);
  }}

  // Render each signal
  signals.forEach((sig, sIdx) => {{
    const yTop = (sIdx + 1) * ROW_HEIGHT;
    const yBot = yTop + ROW_HEIGHT - 8;
    const yMid = (yTop + yBot) / 2;

    // Horizontal baseline
    ctx.strokeStyle = '#21262d';
    ctx.beginPath();
    ctx.moveTo(0, yTop + ROW_HEIGHT);
    ctx.lineTo(width, yTop + ROW_HEIGHT);
    ctx.stroke();

    ctx.strokeStyle = sig.color;
    ctx.lineWidth = 1.5;

    if (sig.type === 'digital') {{
      ctx.beginPath();
      let lastY = yBot;
      for (let i = 0; i < data.length; i++) {{
        const pt = data[i];
        const x = pt.t * scaleX;
        const v = pt.raw[sig.name];
        const y = v ? (yTop + 6) : yBot;
        if (i === 0) {{
          ctx.moveTo(x, y);
        }} else {{
          ctx.lineTo(x, lastY);
          ctx.lineTo(x, y);
        }}
        lastY = y;
      }}
      ctx.stroke();
    }} else {{
      // Bus type
      for (let i = 0; i < data.length; i++) {{
        const pt = data[i];
        const nextPt = data[i + 1];
        const x1 = pt.t * scaleX;
        const x2 = nextPt ? nextPt.t * scaleX : width;
        const str = pt.fmt[sig.name] || '';

        // Draw hexagon/box
        ctx.fillStyle = '#161b22';
        ctx.fillRect(x1 + 1, yTop + 4, Math.max(0, x2 - x1 - 2), ROW_HEIGHT - 12);
        ctx.strokeStyle = sig.color;
        ctx.strokeRect(x1 + 1, yTop + 4, Math.max(0, x2 - x1 - 2), ROW_HEIGHT - 12);

        // Text
        if (x2 - x1 > 28) {{
          ctx.fillStyle = '#e6edf3';
          ctx.font = '10px monospace';
          ctx.save();
          ctx.beginPath();
          ctx.rect(x1 + 2, yTop + 4, x2 - x1 - 4, ROW_HEIGHT - 12);
          ctx.clip();
          ctx.fillText(str, x1 + 5, yTop + 18);
          ctx.restore();
        }}
      }}
    }}
  }});
}}

function zoom(factor) {{
  scaleX *= factor;
  scaleX = Math.max(0.1, Math.min(10.0, scaleX));
  render();
}}

function resetZoom() {{
  scaleX = 1.2;
  render();
}}

function jumpToTime(ns) {{
  container.scrollLeft = ns * scaleX - 50;
}}

canvas.addEventListener('mousemove', e => {{
  const rect = canvas.getBoundingClientRect();
  const mouseX = e.clientX - rect.left;
  const t = Math.round(mouseX / scaleX);

  // Find nearest data point
  let pt = data[0];
  for (let i = 0; i < data.length; i++) {{
    if (data[i].t <= t) pt = data[i];
    else break;
  }}

  const bar = document.getElementById('infoBar');
  bar.innerHTML = `<span>TIME: <b>${{t}} ns</b></span>` +
    `<span>STATE: <b>${{pt.fmt.fsm_state}}</b></span>` +
    `<span>COUNT: <b>${{pt.fmt.count}}</b></span>` +
    `<span>ANGLE: <b>${{pt.fmt.angle_in}}</b></span>` +
    `<span>DONE: <b>${{pt.fmt.done}}</b></span>` +
    `<span>COS: <b>${{pt.fmt.cosine_out}}</b></span>` +
    `<span>SIN: <b>${{pt.fmt.sine_out}}</b></span>`;
}});

buildSidebar();
render();
</script>
</body>
</html>
"""
    with open('view_waves.html', 'w', encoding='utf-8') as f:
        f.write(html)
    print("Created view_waves.html successfully.")

if __name__ == '__main__':
    generate_html()

