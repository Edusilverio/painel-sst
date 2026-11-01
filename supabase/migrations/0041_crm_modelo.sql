

do $$ begin
  create type crm.tipo_etapa as enum ('aberta','ganho','perdido');
exception when duplicate_object then null; end $$;

create table if not exists crm.funil (
  id           uuid primary key default gen_random_uuid(),
  slug         text not null unique,
  nome         text not null unique,
  descricao    text,
  ordem        int  not null default 0,
  ativo        boolean not null default true,
  usa_rodizio  boolean not null default false,

  papeis       crm.papel[] not null default '{comercial}',
  criado_em    timestamptz not null default now()
);

create table if not exists crm.etapa (
  id           uuid primary key default gen_random_uuid(),
  funil_id     uuid not null references crm.funil(id) on delete cascade,
  nome         text not null,
  ordem        int  not null,
  tipo         crm.tipo_etapa not null default 'aberta',
  cor          text not null default 'muted'
               check (cor in ('muted','info','primary','warning','marca','success','destructive')),

  alerta_dias  int check (alerta_dias is null or alerta_dias > 0),
  ativo        boolean not null default true,
  unique (funil_id, nome)
);
create index if not exists etapa_funil_idx on crm.etapa (funil_id, ordem);

create table if not exists crm.produto (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null unique,
  descricao   text,
  categoria   text,
  preco       numeric(12,2) check (preco is null or preco >= 0),
  unidade     text not null default 'un',
  recorrente  boolean not null default false,
  ativo       boolean not null default true,
  criado_em   timestamptz not null default now()
);

create table if not exists crm.negocio (
  id                  uuid primary key default gen_random_uuid(),
  numero              bigint generated always as identity unique,
  funil_id            uuid not null references crm.funil(id),
  etapa_id            uuid not null references crm.etapa(id),
  titulo              text not null,

  empresa_id          uuid references public.empresa(id) on delete set null,
  cliente_nome        text,
  cliente_cnpj        text,
  contato_nome        text,
  contato_telefone    text,
  contato_email       text,
  responsavel_id      uuid references crm.perfil(user_id) on delete set null,
  valor               numeric(12,2) not null default 0 check (valor >= 0),
  origem              text not null default 'manual',
  negocio_origem_id   uuid references crm.negocio(id) on delete set null,
  previsao_fechamento date,
  motivo_perda        text,
  observacao          text,
  entrou_etapa_em     timestamptz not null default now(),
  ultimo_alerta_em    timestamptz,
  fechado_em          timestamptz,
  criado_por          uuid,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  constraint negocio_tem_cliente check (empresa_id is not null or nullif(trim(cliente_nome), '') is not null)
);
create index if not exists negocio_funil_etapa_idx on crm.negocio (funil_id, etapa_id);
create index if not exists negocio_responsavel_idx on crm.negocio (responsavel_id);
create index if not exists negocio_empresa_idx on crm.negocio (empresa_id);
create unique index if not exists negocio_origem_funil_uq on crm.negocio (negocio_origem_id, funil_id)
  where negocio_origem_id is not null;

create table if not exists crm.negocio_item (
  id              uuid primary key default gen_random_uuid(),
  negocio_id      uuid not null references crm.negocio(id) on delete cascade,
  produto_id      uuid references crm.produto(id) on delete set null,
  descricao       text not null,
  quantidade      numeric(12,2) not null default 1 check (quantidade > 0),
  preco_unitario  numeric(12,2) not null default 0 check (preco_unitario >= 0),
  total           numeric(12,2) generated always as (quantidade * preco_unitario) stored,
  criado_em       timestamptz not null default now()
);
create index if not exists negocio_item_negocio_idx on crm.negocio_item (negocio_id);

create table if not exists crm.evento (
  id             bigint generated always as identity primary key,
  negocio_id     uuid not null references crm.negocio(id) on delete cascade,
  tipo           text not null check (tipo in
                   ('criado','etapa','nota','ligacao','email','whatsapp','reuniao',
                    'responsavel','item','alerta','edicao')),
  texto          text,
  de_etapa_id    uuid references crm.etapa(id) on delete set null,
  para_etapa_id  uuid references crm.etapa(id) on delete set null,
  autor_id       uuid,
  criado_em      timestamptz not null default now()
);
create index if not exists evento_negocio_idx on crm.evento (negocio_id, criado_em desc);

create table if not exists crm.rodizio (
  funil_id  uuid not null references crm.funil(id) on delete cascade,
  user_id   uuid not null references crm.perfil(user_id) on delete cascade,
  ordem     int  not null,
  ativo     boolean not null default true,
  primary key (funil_id, user_id)
);
create table if not exists crm.rodizio_estado (
  funil_id        uuid primary key references crm.funil(id) on delete cascade,
  ultimo_user_id  uuid,
  atualizado_em   timestamptz not null default now()
);

create table if not exists crm.tunel (
  funil_origem_id   uuid not null references crm.funil(id) on delete cascade,
  funil_destino_id  uuid not null references crm.funil(id) on delete cascade,
  primary key (funil_origem_id, funil_destino_id),
  check (funil_origem_id <> funil_destino_id)
);

create table if not exists crm.notificacao (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references crm.perfil(user_id) on delete cascade,
  negocio_id  uuid references crm.negocio(id) on delete cascade,
  tipo        text not null,
  texto       text not null,
  lida_em     timestamptz,
  criado_em   timestamptz not null default now()
);
create index if not exists notificacao_user_idx on crm.notificacao (user_id, lida_em, criado_em desc);

alter table crm.funil          enable row level security;
alter table crm.etapa          enable row level security;
alter table crm.produto        enable row level security;
alter table crm.negocio        enable row level security;
alter table crm.negocio_item   enable row level security;
alter table crm.evento         enable row level security;
alter table crm.rodizio        enable row level security;
alter table crm.rodizio_estado enable row level security;
alter table crm.notificacao    enable row level security;
alter table crm.tunel          enable row level security;

insert into crm.funil (slug, nome, descricao, ordem, usa_rodizio, papeis) values
  ('comercial',   'Comercial',   'Venda de novos serviços e contratos',       1, true,  '{comercial}'),
  ('faturamento', 'Faturamento', 'Faturar o que foi vendido',                 2, false, '{financeiro}'),
  ('vistoria',    'Vistoria',    'Visitas técnicas aos clientes',             3, false, '{operacoes}'),
  ('laudos',      'Laudos',      'Elaboração e entrega de laudos',            4, false, '{operacoes}'),
  ('pos-venda',   'Pós-venda',   'Contratos ativos, inadimplência e renovação', 5, false, '{comercial,financeiro}')
on conflict (slug) do nothing;

insert into crm.etapa (funil_id, nome, ordem, tipo, cor, alerta_dias)
select f.id, e.nome, e.ordem, e.tipo::crm.tipo_etapa, e.cor, e.alerta
  from crm.funil f
  join (values
    ('comercial',   'Novo negócio',          1, 'aberta',  'destructive', 3),
    ('comercial',   'Contato feito',         2, 'aberta',  'warning',     5),
    ('comercial',   'Reunião agendada',      3, 'aberta',  'primary',     null::int),
    ('comercial',   'Follow-up',             4, 'aberta',  'info',        null),
    ('comercial',   'Proposta',              5, 'aberta',  'marca',       3),
    ('comercial',   'Envio de contrato',     6, 'aberta',  'success',     3),
    ('comercial',   'Negócio fechado',       7, 'ganho',   'success',     null),
    ('comercial',   'Oportunidade perdida',  8, 'perdido', 'destructive', null),
    ('faturamento', 'Não tocado',            1, 'aberta',  'destructive', 2),
    ('faturamento', 'Em execução',           2, 'aberta',  'warning',     null),
    ('faturamento', 'Concluído',             3, 'ganho',   'success',     null),
    ('faturamento', 'Não concluído',         4, 'perdido', 'destructive', null),
    ('vistoria',    'Não tocado',            1, 'aberta',  'destructive', 3),
    ('vistoria',    'Em execução',           2, 'aberta',  'warning',     null),
    ('vistoria',    'Concluído',             3, 'ganho',   'success',     null),
    ('vistoria',    'Não concluído',         4, 'perdido', 'destructive', null),
    ('laudos',      'Não tocado',            1, 'aberta',  'destructive', 3),
    ('laudos',      'Em execução',           2, 'aberta',  'warning',     null),
    ('laudos',      'Concluído',             3, 'ganho',   'success',     null),
    ('laudos',      'Não concluído',         4, 'perdido', 'destructive', null),
    ('pos-venda',   'Contratos fechados',    1, 'aberta',  'info',        null),
    ('pos-venda',   'Inadimplentes',         2, 'aberta',  'destructive', 3),
    ('pos-venda',   'Renovações',            3, 'aberta',  'marca',       3),
    ('pos-venda',   'Concluído',             4, 'ganho',   'success',     null),
    ('pos-venda',   'Sem entrega',           5, 'perdido', 'destructive', null)
  ) as e(funil, nome, ordem, tipo, cor, alerta) on e.funil = f.slug
on conflict (funil_id, nome) do nothing;

insert into crm.tunel (funil_origem_id, funil_destino_id)
select o.id, d.id from crm.funil o, crm.funil d
 where o.slug = 'comercial' and d.slug in ('faturamento','pos-venda')
on conflict do nothing;

insert into crm.produto (nome, categoria, recorrente, descricao) values
  ('PGR — Programa de Gerenciamento de Riscos (NR-1)', 'Engenharia', true,  'Preço por faixa de funcionários'),
  ('PCMSO — Programa de Controle Médico',              'Medicina',   true,  'Elaboração e revisão anual'),
  ('Exames clínicos + laudo PCMSO',                    'Medicina',   false, 'Por colaborador'),
  ('Mensageria eSocial (SST)',                         'eSocial',    true,  'Envio de S-2210, S-2220 e S-2240'),
  ('Treinamentos e palestras',                         'Treinamento',false, null),
  ('Implantação',                                      'Consultoria',false, null),
  ('LTCAT',                                            'Engenharia', false, null),
  ('Vistoria técnica',                                 'Engenharia', false, null),
  ('Plano mensal',                                     'Contrato',   true,  'Contrato fixo mensal')
on conflict (nome) do nothing;
