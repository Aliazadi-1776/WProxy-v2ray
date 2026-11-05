export interface SubscriptionMetadata {
  updated_at: number | null;
  usage?: {
    upload?: number;
    download?: number;
    total?: number;
    expire?: number;
  };
}

export interface SubscriptionHealth {
  updatedLabel: string;
  expiryLabel: string | null;
  expired: boolean;
  usedBytes: number | null;
  totalBytes: number | null;
  usagePercent: number | null;
}

function nonnegative(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function updatedLabel(updated: unknown, now: number): string {
  if (!nonnegative(updated)) return "Never updated";
  const age = Math.max(0, now - updated);
  if (age < 60) return "Updated just now";
  const [amount, unit] = age < 3600
    ? [Math.floor(age / 60), "minute"]
    : age < 86400
      ? [Math.floor(age / 3600), "hour"]
      : [Math.floor(age / 86400), "day"];
  return `Updated ${amount} ${unit}${amount === 1 ? "" : "s"} ago`;
}

export function subscriptionHealth(subscription: SubscriptionMetadata, nowSeconds = Date.now() / 1000): SubscriptionHealth {
  const now = nonnegative(nowSeconds) ? nowSeconds : Date.now() / 1000;
  const usage = subscription.usage;
  const upload = usage?.upload;
  const download = usage?.download;
  const combined = nonnegative(upload) && nonnegative(download) ? upload + download : null;
  const usedBytes = combined !== null && Number.isFinite(combined) ? combined : null;
  const totalBytes = nonnegative(usage?.total) && usage.total > 0 ? usage.total : null;
  const usagePercent = usedBytes !== null && totalBytes !== null
    ? Math.min(100, Math.max(0, usedBytes / totalBytes * 100))
    : null;
  const expiry = nonnegative(usage?.expire) && usage.expire > 0 ? usage.expire : null;
  const expired = expiry !== null && expiry <= now;
  let expiryLabel: string | null = null;
  if (expiry !== null) {
    const days = Math.ceil((expiry - now) / 86400);
    expiryLabel = expired ? "Expired" : expiry - now < 86400
      ? "Expires today"
      : `Expires in ${days} ${days === 1 ? "day" : "days"}`;
  }
  return {
    updatedLabel: updatedLabel(subscription.updated_at, now),
    expiryLabel,
    expired,
    usedBytes,
    totalBytes,
    usagePercent,
  };
}
