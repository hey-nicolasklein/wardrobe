// Fixed-window counter kept in memory. Good enough for a single API instance;
// move the counters to Postgres or Redis once the API runs on several hosts.
export class RateLimiter {
  private readonly windows = new Map<string, { startedAt: number; count: number }>();

  constructor(
    private readonly limit: number,
    private readonly windowMs: number,
    private readonly now: () => number = Date.now,
  ) {}

  // Counts one hit for `key` and returns false once the window is exhausted.
  take(key: string): boolean {
    const now = this.now();
    const window = this.windows.get(key);
    if (!window || now - window.startedAt >= this.windowMs) {
      if (this.windows.size > 10_000) this.prune(now);
      this.windows.set(key, { startedAt: now, count: 1 });
      return true;
    }
    window.count += 1;
    return window.count <= this.limit;
  }

  private prune(now: number): void {
    for (const [key, window] of this.windows)
      if (now - window.startedAt >= this.windowMs) this.windows.delete(key);
  }
}
