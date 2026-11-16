create extension if not exists pgcrypto;

create table if not exists pans (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null, factory_id uuid not null,
  code text not null, name text not null, capacity_ml integer not null check (capacity_ml > 0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (factory_id, code)
);
create table if not exists grades (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null, factory_id uuid not null,
  code text not null, name text not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (factory_id, code)
);
create table if not exists additives (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null, factory_id uuid not null,
  code text not null, name text not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (factory_id, code)
);
create table if not exists production_configs (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null, factory_id uuid not null,
  max_nira_ml integer not null default 115000 check (max_nira_ml > 0), config jsonb not null default '{}',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists price_versions (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null, factory_id uuid not null,
  effective_at timestamptz not null, prices jsonb not null default '{}', created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists batches (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null, factory_id uuid not null,
  kloter_id uuid not null, pan_id uuid not null references pans(id), status text not null default 'DRAFT' check (status in ('DRAFT','COOKED','WEIGHED','GRADED','VALIDATED')),
  occurred_at timestamptz not null, production_config_id uuid not null references production_configs(id), price_version_id uuid not null references price_versions(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists batch_nira_contributions (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null, factory_id uuid not null,
  batch_id uuid not null references batches(id) on delete cascade, kloter_id uuid not null, volume_ml integer not null check (volume_ml > 0), occurred_at timestamptz not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists cooking_records (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null, factory_id uuid not null,
  batch_id uuid not null unique references batches(id) on delete cascade, started_at timestamptz not null, ended_at timestamptz, additive_ids uuid[] not null default '{}', created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists weighings (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null, factory_id uuid not null,
  batch_id uuid not null unique references batches(id) on delete cascade, cane_weight_grams bigint, sugar_weight_grams bigint not null check (sugar_weight_grams >= 0), occurred_at timestamptz not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists batch_grades (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null, factory_id uuid not null,
  batch_id uuid not null unique references batches(id) on delete cascade, grade_id uuid not null references grades(id), sugar_weight_grams bigint not null check (sugar_weight_grams >= 0), occurred_at timestamptz not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists reworks (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null, factory_id uuid not null,
  source_batch_id uuid not null references batches(id), receiving_batch_id uuid not null references batches(id), weight_grams bigint not null check (weight_grams > 0), status text not null default 'RECORDED', occurred_at timestamptz not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists batches_scope_idx on batches (tenant_id, factory_id, occurred_at);
create index if not exists contributions_batch_idx on batch_nira_contributions (batch_id);

create table if not exists sugar_stock_movements (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null, factory_id uuid not null,
  grade_id uuid not null references grades(id), batch_id uuid references batches(id), delta_grams bigint not null check (delta_grams <> 0),
  reason text not null, occurred_at timestamptz not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists batch_economic_allocations (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null, factory_id uuid not null, batch_id uuid not null references batches(id), kloter_id uuid not null,
  proportion numeric not null check (proportion >= 0 and proportion <= 1), cost_rupiah bigint not null check (cost_rupiah >= 0), revenue_rupiah bigint not null check (revenue_rupiah >= 0), margin_rupiah bigint not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists sugar_stock_scope_idx on sugar_stock_movements (tenant_id, factory_id, grade_id, occurred_at);
create index if not exists allocation_batch_idx on batch_economic_allocations (batch_id);
