import { BadRequestException, Body, ConflictException, Controller, ForbiddenException, Get, Header,
  Injectable, Param, Patch, Post, Query } from '@nestjs/common';
import { CurrentFactory, FactoryRoles } from '../auth/auth.decorators';
import { ACTIVE_ACCESS_SQL, FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseSession } from '../database/database.service';
import { CatalogQuery, found, object, Pagination, parseCatalogQuery, parsePage, scopeValues, text, uuid } from '../production/production.dto';
import { queryPage } from '../production/production.repository';
import { Database } from './database';

interface Contact {
  id: string;
  factoryId: string;
  displayName: string;
  phoneE164: string;
  isActive: boolean;
}

const columns = `o.id, o.factory_id AS "factoryId", o.display_name AS "displayName",
  o.phone_e164 AS "phoneE164", o.active AS "isActive"`;

function snapshot(contact: Contact) {
  return { displayName: contact.displayName, isActive: contact.isActive };
}

@Injectable()
export class Operators {
  constructor(private readonly db: Database) {}

  list(access: FactoryAccess, query: CatalogQuery) {
    return queryPage<Contact>(this.db, `${FACTORY_SCOPE_CTE}, filtered AS (
      SELECT ${columns} FROM operator_contacts o JOIN authorized_scope s ON s."factoryId" = o.factory_id
      WHERE ($4::text IS NULL OR strpos(lower(o.display_name), lower($4)) > 0 OR strpos(o.phone_e164, $4) > 0)
        AND ($5::boolean IS NULL OR o.active = $5)
    )`, [...scopeValues(access), query.q ?? null, query.isActive ?? null], query, '"displayName", id');
  }

  async history(access: FactoryAccess, id: string, page: Pagination) {
    const visible = await this.db.query(`WITH ${FACTORY_SCOPE_CTE}
      SELECT o.id FROM operator_contacts o JOIN authorized_scope s ON s."factoryId" = o.factory_id WHERE o.id = $4`,
    [...scopeValues(access), id]);
    found(visible.rows[0]);
    return queryPage<{ id: string; action: string; actorId: string; before: unknown; after: unknown; occurredAt: Date }>(
      this.db, `${FACTORY_SCOPE_CTE}, filtered AS (
        SELECT e.id, e.action, e.actor_id AS "actorId", e.before_data AS before, e.after_data AS after,
          e.occurred_at AS "occurredAt"
        FROM operator_contact_events e JOIN operator_contacts o ON o.id = e.operator_id
        JOIN authorized_scope s ON s."factoryId" = o.factory_id WHERE o.id = $4
      )`, [...scopeValues(access), id], page, '"occurredAt" DESC, id');
  }

  create(access: FactoryAccess, displayName: string, phone: string) {
    return this.db.transaction(async (tx) => {
      await this.requireAccess(tx, access);
      const { rows: [contact] } = await tx.query<Contact>(`INSERT INTO operator_contacts AS o (factory_id, display_name, phone_e164)
        VALUES ($1,$2,$3) ON CONFLICT (phone_e164) DO NOTHING RETURNING ${columns}`, [access.factoryId, displayName, phone]);
      if (!contact) throw new ConflictException('Nomor WhatsApp sudah terdaftar.');
      await this.audit(tx, access, contact, 'created');
      return contact;
    });
  }

  update(access: FactoryAccess, id: string, values: { displayName?: string; isActive?: boolean }) {
    return this.db.transaction(async (tx) => {
      await this.requireAccess(tx, access);
      // Intake holds the same row lock while it accepts a new WhatsApp message.
      const previous = found((await tx.query<Contact>(`SELECT ${columns} FROM operator_contacts o
        WHERE o.factory_id = $1 AND o.id = $2 FOR UPDATE`, [access.factoryId, id])).rows[0]);
      const displayName = values.displayName ?? previous.displayName;
      const active = values.isActive ?? previous.isActive;
      if (displayName === previous.displayName && active === previous.isActive) return previous;
      const { rows: [contact] } = await tx.query<Contact>(`UPDATE operator_contacts AS o SET display_name = $3, active = $4
        WHERE o.factory_id = $1 AND o.id = $2 RETURNING ${columns}`, [access.factoryId, id, displayName, active]);
      await this.audit(tx, access, contact, 'updated', previous);
      return contact;
    });
  }

  private async requireAccess(tx: DatabaseSession, access: FactoryAccess) {
    const { rows } = await tx.query(`${ACTIVE_ACCESS_SQL}
      AND fm.tenant_id = $2 AND fm.factory_id = $3 AND fm.role IN ('admin', 'owner') FOR SHARE OF fm, tm, f, t`, scopeValues(access));
    if (!rows.length) throw new ForbiddenException('Akses pabrik tidak lagi tersedia.');
  }

  private async audit(tx: DatabaseSession, access: FactoryAccess, contact: Contact, action: 'created' | 'updated', previous?: Contact) {
    await tx.query(`INSERT INTO operator_contact_events (operator_id, actor_id, action, before_data, after_data)
      VALUES ($1,$2,$3,$4,$5)`, [contact.id, access.userId, action, previous ? snapshot(previous) : null, snapshot(contact)]);
  }
}

@Controller('tenants/:tenantId/factories/:factoryId/operators')
@FactoryRoles('admin', 'owner')
export class OperatorsController {
  constructor(private readonly operators: Operators) {}

  @Get()
  @Header('Cache-Control', 'private, no-store')
  list(@CurrentFactory() access: FactoryAccess, @Query() query: unknown) {
    return this.operators.list(access, parseCatalogQuery(query));
  }

  @Post()
  @Header('Cache-Control', 'private, no-store')
  create(@CurrentFactory() access: FactoryAccess, @Body() body: unknown) {
    const row = object(body, ['displayName', 'phoneE164']);
    const displayName = text(row.displayName, 'displayName', 100);
    const phone = text(row.phoneE164, 'phoneE164', 16);
    if (!/^\+[1-9][0-9]{7,14}$/.test(phone)) throw new BadRequestException('phoneE164 harus memakai format E.164.');
    return this.operators.create(access, displayName, phone);
  }

  @Patch(':operatorId')
  @Header('Cache-Control', 'private, no-store')
  update(@CurrentFactory() access: FactoryAccess, @Param('operatorId') id: string, @Body() body: unknown) {
    const row = object(body, ['displayName', 'isActive']);
    if (!Object.keys(row).length) throw new BadRequestException('Minimal satu field diperlukan.');
    if ('isActive' in row && typeof row.isActive !== 'boolean') throw new BadRequestException('isActive harus berupa boolean.');
    return this.operators.update(access, uuid(id, 'operatorId'), {
      displayName: 'displayName' in row ? text(row.displayName, 'displayName', 100) : undefined,
      isActive: row.isActive as boolean | undefined,
    });
  }

  @Get(':operatorId/history')
  @Header('Cache-Control', 'private, no-store')
  history(@CurrentFactory() access: FactoryAccess, @Param('operatorId') id: string, @Query() query: unknown) {
    return this.operators.history(access, uuid(id, 'operatorId'), parsePage(query));
  }
}
