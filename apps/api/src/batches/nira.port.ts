export interface NiraAvailabilityPort {
  available(kloterId: string): Promise<number>;
  reserve(kloterId: string, volumeMl: number, reservationId: string): Promise<boolean>;
}

/** Mock contract. Backend A can replace implementation without changing B1 service. */
export class FixtureNiraAvailability implements NiraAvailabilityPort {
  private readonly balances = new Map<string, number>();
  private readonly reservations = new Set<string>();
  async available(kloterId: string) { return this.balances.get(kloterId) ?? 115000; }
  async reserve(kloterId: string, volumeMl: number, reservationId: string) {
    if (this.reservations.has(reservationId)) return true;
    const balance = await this.available(kloterId);
    if (volumeMl > balance) return false;
    this.balances.set(kloterId, balance - volumeMl);
    this.reservations.add(reservationId);
    return true;
  }
}
