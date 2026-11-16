export interface NiraAvailabilityPort {
  available(kloterId: string): Promise<number>;
  reserve(kloterId: string, volumeMl: number, reservationId: string): Promise<boolean>;
  release?(kloterId: string, reservationId: string): Promise<void>;
  consume?(kloterId: string, reservationId: string): Promise<void>;
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
import { FactoryAccess } from '../auth/auth.types';
import { JuiceRepository } from '../juice/juice.repository';
import { parseReservation } from '../juice/juice.dto';


/** Backend A ledger adapter. Batch service keeps fixture mode untouched. */
export class LedgerNiraAvailability implements NiraAvailabilityPort {
  constructor(private readonly juice: JuiceRepository, private readonly access: FactoryAccess, private readonly batchId: string) {}
  async available(lotId: string) {
    const value = await this.juice.availability(this.access, lotId, false);
    return Number(value.availableMl);
  }
  async reserve(lotId: string, volumeMl: number, reservationId: string) {
    const input = parseReservation({ requestId: reservationId, batchId: this.batchId, quantityMl: String(volumeMl), synthetic: false });
    await this.juice.reserve(this.access, lotId, input);
    return true;
  }
  async release(lotId: string, reservationId: string) {
    await this.juice.finalize(this.access, lotId, reservationId, 'released');
  }
  async consume(lotId: string, reservationId: string) {
    await this.juice.finalize(this.access, lotId, reservationId, 'consumed');
  }
}
