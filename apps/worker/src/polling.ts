export class SerialPoller {
  private active: Promise<void> | null = null;
  private stopping = false;

  constructor(
    private readonly run: () => Promise<void>,
    private readonly onError: (error: unknown) => void,
  ) {}

  start(): void {
    if (this.active || this.stopping) return;
    const running = this.run()
      .catch(this.onError)
      .finally(() => {
        if (this.active === running) this.active = null;
      });
    this.active = running;
  }

  async stop(): Promise<void> {
    this.stopping = true;
    await this.active;
  }
}
