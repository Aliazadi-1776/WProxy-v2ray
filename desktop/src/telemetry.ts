export interface TrafficPoint {
  download: number;
  upload: number;
}

export interface TrafficCounters {
  active: boolean;
  node_id: string | null;
  rx_bytes?: number;
  tx_bytes?: number;
}

interface Observation {
  at: number;
  rx: number;
  tx: number;
  nodeId: string | null;
}

const HISTORY_LIMIT = 60;

export class TelemetryHistory {
  private observation: Observation | null = null;
  private history: TrafficPoint[] = [];

  get points(): readonly TrafficPoint[] {
    return this.history;
  }

  reset(): void {
    this.observation = null;
    this.history = [];
  }

  // Observation times use the same millisecond clock, such as performance.now().
  sample(counters: TrafficCounters, at: number): TrafficPoint {
    const idle = { download: 0, upload: 0 };
    const rx = counters.rx_bytes;
    const tx = counters.tx_bytes;
    if (!counters.active || typeof rx !== "number" || typeof tx !== "number"
      || !Number.isFinite(rx) || !Number.isFinite(tx) || rx < 0 || tx < 0) {
      this.reset();
      return idle;
    }
    if (!Number.isFinite(at) || at < 0 || (this.observation && at <= this.observation.at)) return idle;

    const previous = this.observation;
    this.observation = { at, rx, tx, nodeId: counters.node_id };
    if (!previous || previous.nodeId !== counters.node_id || rx < previous.rx || tx < previous.tx) {
      this.history = [];
      return idle;
    }

    const elapsed = (at - previous.at) / 1000;
    const point = { download: (rx - previous.rx) / elapsed, upload: (tx - previous.tx) / elapsed };
    if (!Number.isFinite(point.download) || !Number.isFinite(point.upload)) {
      this.history = [];
      return idle;
    }
    this.history.push(point);
    if (this.history.length > HISTORY_LIMIT) this.history.shift();
    return point;
  }
}

export function renderTrafficChart(points: readonly TrafficPoint[]): string {
  const visible = points.slice(-HISTORY_LIMIT).filter((point) =>
    Number.isFinite(point.download) && point.download >= 0
    && Number.isFinite(point.upload) && point.upload >= 0);
  if (visible.length < 2) {
    return '<div class="traffic-chart-empty" role="status">Connect to a server to see live traffic. The chart appears after two measurements.</div>';
  }

  const width = 560;
  const height = 112;
  const padding = 8;
  const maximum = Math.max(1, ...visible.flatMap((point) => [point.download, point.upload]));
  const path = (key: keyof TrafficPoint): string => visible.map((point, index) => {
    const x = padding + index / (visible.length - 1) * (width - 2 * padding);
    const y = height - padding - (point[key] / maximum) * (height - 2 * padding);
    return `${index === 0 ? "M" : "L"}${x.toFixed(2)},${y.toFixed(2)}`;
  }).join(" ");

  return `<svg class="traffic-chart" viewBox="0 0 ${width} ${height}" role="img" aria-label="Live download and upload rates across ${visible.length} measurements">
    <title>Live traffic</title>
    <desc>Download and upload in bytes per second share the same vertical scale. Older measurements are on the left. Only measured counter changes are shown.</desc>
    <path class="traffic-grid" d="M8,8 H552 M8,56 H552 M8,104 H552" fill="none" />
    <path class="traffic-download" d="${path("download")}" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" />
    <path class="traffic-upload" d="${path("upload")}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="5 4" />
  </svg>`;
}
