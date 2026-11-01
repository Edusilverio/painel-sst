

create table if not exists crm.contrato (
  id                   uuid primary key default gen_random_uuid(),
  numero               bigint generated always as identity unique,
  empresa_id           uuid references public.empresa(id) on delete set null,
  cliente_nome         text,
  negocio_id           uuid references crm.negocio(id) on delete set null,
  titulo               text not null check (length(trim(titulo)) > 1),
  status               text not null default 'rascunho'
                         check (status in ('rascunho','revisao','enviado','parcial','assinado','cancelado')),
  inicio               date,
  fim                  date,
  renovacao_automatica boolean not null default false,
  aviso_dias           int not null default 60 check (aviso_dias between 0 and 365),
  valor_mensal         numeric(12,2) check (valor_mensal >= 0),
  valor_total          numeric(12,2) not null default 0 check (valor_total >= 0),
  dia_vencimento       int check (dia_vencimento between 1 and 31),
  forma_pagamento      text,
  indice_reajuste      text,
  responsavel_id       uuid references crm.perfil(user_id) on delete set null,
  observacao           text,
  arquivo_path         text,
  arquivo_nome         text,
  assinado_em          timestamptz,
  cancelado_motivo     text,
  renovacao_negocio_id uuid references crm.negocio(id) on delete set null,
  ultimo_alerta_em     date,
  criado_por           uuid,
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now(),
  constraint contrato_tem_cliente check (empresa_id is not null or nullif(trim(cliente_nome), '') is not null),
  constraint contrato_vigencia check (inicio is null or fim is null or fim >= inicio)
);
create unique index if not exists contrato_negocio_uq on crm.contrato (negocio_id) where negocio_id is not null;
create index if not exists contrato_empresa_idx on crm.contrato (empresa_id);
create index if not exists contrato_fim_idx on crm.contrato (fim) where status = 'assinado';

create table if not exists crm.contrato_item (
  id           uuid primary key default gen_random_uuid(),
  contrato_id  uuid not null references crm.contrato(id) on delete cascade,
  produto_id   uuid references crm.produto(id) on delete set null,
  descricao    text not null,
  quantidade   numeric(12,2) not null default 1 check (quantidade > 0),
  preco        numeric(12,2) not null default 0 check (preco >= 0),
  total        numeric(14,2) generated always as (quantidade * preco) stored,
  criado_em    timestamptz not null default now()
);
create index if not exists contrato_item_idx on crm.contrato_item (contrato_id);

create table if not exists crm.contrato_evento (
  id           bigint generated always as identity primary key,
  contrato_id  uuid not null references crm.contrato(id) on delete cascade,
  texto        text not null,
  autor_id     uuid,
  criado_em    timestamptz not null default now()
);
create index if not exists contrato_evento_idx on crm.contrato_evento (contrato_id, criado_em);

alter table crm.contrato        enable row level security;
alter table crm.contrato_item   enable row level security;
alter table crm.contrato_evento enable row level security;

alter table crm.notificacao add column if not exists contrato_id uuid references crm.contrato(id) on delete cascade;

create or replace function crm.contrato_status_rotulo(p text) returns text
language sql immutable set search_path = '' as $$
  select case p when 'rascunho' then 'Rascunho' when 'revisao' then 'Sob revisão' when 'enviado' then 'Enviado'
                when 'parcial' then 'Parcialmente assinado' when 'assinado' then 'Assinado'
                when 'cancelado' then 'Cancelado' else p end
$$;

create or replace function crm.contrato_situacao(p_status text, p_fim date, p_aviso int) returns text
language sql stable set search_path = '' as $$
  select case
    when p_status = 'cancelado' then 'cancelado'
    when p_status <> 'assinado' then 'em_assinatura'
    when p_fim is null then 'vigente'
    when p_fim < (now() at time zone 'America/Sao_Paulo')::date then 'vencido'
    when p_fim <= (now() at time zone 'America/Sao_Paulo')::date + p_aviso then 'a_renovar'
    else 'vigente' end
$$;

create or replace function crm.contrato_log(p_contrato uuid, p_texto text) returns void
language sql security definer set search_path = '' as $$
  insert into crm.contrato_evento (contrato_id, texto, autor_id) values (p_contrato, p_texto, auth.uid())
$$;

create or replace function crm.exige_contratos() returns uuid
language sql stable security definer set search_path = '' as $$
  select crm.exige('gestor','comercial','financeiro')
$$;

create or replace function crm.contrato_recalcular(p_contrato uuid) returns void
language sql security definer set search_path = '' as $$
  update crm.contrato c
     set valor_total = coalesce((select sum(i.total) from crm.contrato_item i where i.contrato_id = c.id), 0),
         atualizado_em = now()
   where c.id = p_contrato
$$;

create or replace function crm.tg_negocio_ganho_contrato() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v uuid;
begin
  if new.etapa_id is not distinct from old.etapa_id then return new; end if;
  if not exists (select 1 from crm.etapa e join crm.funil f on f.id = e.funil_id
                  where e.id = new.etapa_id and e.tipo = 'ganho' and f.slug = 'comercial') then
    return new;
  end if;
  if exists (select 1 from crm.contrato where negocio_id = new.id) then return new; end if;
  insert into crm.contrato (empresa_id, cliente_nome, negocio_id, titulo, responsavel_id, valor_total, criado_por)
  values (new.empresa_id, new.cliente_nome, new.id, 'Contrato — ' || new.titulo, new.responsavel_id, new.valor, auth.uid())
  returning id into v;
  insert into crm.contrato_item (contrato_id, produto_id, descricao, quantidade, preco)
  select v, i.produto_id, i.descricao, i.quantidade, i.preco_unitario from crm.negocio_item i where i.negocio_id = new.id;
  if found then perform crm.contrato_recalcular(v); end if;
  insert into crm.contrato_evento (contrato_id, texto, autor_id)
  values (v, 'Criado a partir do negócio #' || new.numero || ' (ganho no Comercial)', auth.uid());
  return new;
end $$;

drop trigger if exists negocio_ganho_contrato on crm.negocio;
create trigger negocio_ganho_contrato after update of etapa_id on crm.negocio
  for each row execute function crm.tg_negocio_ganho_contrato();

create or replace function crm.alertas_contratos() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; qtd int := 0; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        etapa_ren uuid; funil_pv uuid; neg uuid; destino uuid;
begin
  select f.id, e.id into funil_pv, etapa_ren
    from crm.funil f join crm.etapa e on e.funil_id = f.id
   where f.slug = 'pos-venda' and e.nome ilike 'renova%' and e.ativo limit 1;

  for r in
    select c.*, coalesce(nullif(em.nome_fantasia, ''), em.razao_social, c.cliente_nome) as cliente
      from crm.contrato c left join public.empresa em on em.id = c.empresa_id
     where c.status = 'assinado' and c.fim is not null and c.fim <= hoje + c.aviso_dias
       and (c.ultimo_alerta_em is null or c.ultimo_alerta_em <= hoje - 7)
  loop
    destino := coalesce(r.responsavel_id,
                        (select p.user_id from crm.perfil p where p.ativo and p.papel = 'gestor' order by p.nome limit 1));
    if destino is not null then
      insert into crm.notificacao (user_id, contrato_id, tipo, texto)
      values (destino, r.id, 'renovacao',
              case when r.fim < hoje then 'Contrato vencido: ' else 'Contrato vence em ' || to_char(r.fim, 'DD/MM') || ': ' end || r.cliente);
    end if;
    if r.renovacao_negocio_id is null and etapa_ren is not null then
      insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, responsavel_id, valor, origem, observacao)
      values (funil_pv, etapa_ren, 'Renovação: ' || r.cliente, r.empresa_id, r.cliente_nome, r.responsavel_id,
              coalesce(r.valor_total, 0), 'renovacao', 'Contrato #' || r.numero || ' vence em ' || to_char(r.fim, 'DD/MM/YYYY'))
      returning id into neg;
      insert into crm.evento (negocio_id, tipo, texto) values (neg, 'criado', 'Aberto pelo aviso de renovação do contrato #' || r.numero);
      update crm.contrato set renovacao_negocio_id = neg where id = r.id;
      insert into crm.contrato_evento (contrato_id, texto) values (r.id, 'Aviso de renovação: card aberto em Pós-venda → Renovações');
    end if;
    update crm.contrato set ultimo_alerta_em = hoje where id = r.id;
    qtd := qtd + 1;
  end loop;
  return qtd;
end $$;

revoke execute on function crm.contrato_log(uuid, text), crm.exige_contratos(), crm.contrato_recalcular(uuid),
  crm.tg_negocio_ganho_contrato(), crm.alertas_contratos() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('crm-alertas-contratos', '10 11 * * *', 'select crm.alertas_contratos()');
  end if;
end $$;

create or replace function public.painel_papel_em(p_papeis text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select p.papel = 'admin' or p.papel::text = any (p_papeis)
                     from crm.perfil p where p.user_id = auth.uid() and p.ativo), false)
$$;

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit)
    values ('crm-arquivos', 'crm-arquivos', false, 26214400)
    on conflict (id) do nothing;

    execute 'drop policy if exists "crm_arquivos_ler" on storage.objects';
    execute 'drop policy if exists "crm_arquivos_enviar" on storage.objects';
    execute 'drop policy if exists "crm_arquivos_apagar" on storage.objects';
    execute $p$create policy "crm_arquivos_ler" on storage.objects for select to authenticated
      using (bucket_id = 'crm-arquivos' and public.painel_papel_em(array['gestor','comercial','financeiro','operacoes']))$p$;
    execute $p$create policy "crm_arquivos_enviar" on storage.objects for insert to authenticated
      with check (bucket_id = 'crm-arquivos' and public.painel_papel_em(array['gestor','comercial','financeiro','operacoes']))$p$;
    execute $p$create policy "crm_arquivos_apagar" on storage.objects for delete to authenticated
      using (bucket_id = 'crm-arquivos' and public.painel_papel_em(array['gestor','comercial','financeiro']))$p$;
  end if;
end $$;

create or replace function public.painel_contratos_resumo() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform crm.exige_contratos();
  return (
    with s as (select crm.contrato_situacao(status, fim, aviso_dias) sit, valor_mensal from crm.contrato)
    select jsonb_build_object(
      'vigentes', count(*) filter (where sit = 'vigente'),
      'a_renovar', count(*) filter (where sit = 'a_renovar'),
      'vencidos', count(*) filter (where sit = 'vencido'),
      'em_assinatura', count(*) filter (where sit = 'em_assinatura'),
      'receita_mensal', coalesce(sum(valor_mensal) filter (where sit in ('vigente','a_renovar')), 0))
    from s);
end $$;

create or replace function public.painel_contratos(p_busca text default null, p_situacao text default null)
returns table (id uuid, numero bigint, titulo text, empresa_id uuid, cliente text, status text, situacao text,
               inicio date, fim date, dias_para_vencer int, valor_mensal numeric, valor_total numeric,
               responsavel_id uuid, responsavel_nome text, tem_arquivo boolean, negocio_id uuid,
               renovacao_negocio_id uuid, atualizado_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  perform crm.exige_contratos();
  return query
    select c.id, c.numero, c.titulo, c.empresa_id,
           coalesce(nullif(e.nome_fantasia, ''), e.razao_social, c.cliente_nome)::text,
           c.status, crm.contrato_situacao(c.status, c.fim, c.aviso_dias),
           c.inicio, c.fim, (c.fim - hoje)::int, c.valor_mensal, c.valor_total,
           c.responsavel_id, p.nome::text, c.arquivo_path is not null, c.negocio_id, c.renovacao_negocio_id, c.atualizado_em
      from crm.contrato c
      left join public.empresa e on e.id = c.empresa_id
      left join crm.perfil p on p.user_id = c.responsavel_id
     where (termo is null or c.titulo ilike '%' || termo || '%' or e.razao_social ilike '%' || termo || '%'
            or e.nome_fantasia ilike '%' || termo || '%' or c.cliente_nome ilike '%' || termo || '%'
            or c.numero::text = termo)
       and (p_situacao is null or crm.contrato_situacao(c.status, c.fim, c.aviso_dias) = p_situacao)
     order by case crm.contrato_situacao(c.status, c.fim, c.aviso_dias)
                when 'vencido' then 0 when 'a_renovar' then 1 when 'em_assinatura' then 2 when 'vigente' then 3 else 4 end,
              c.fim nulls last, c.numero desc;
end $$;

create or replace function public.painel_contrato(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform crm.exige_contratos();
  select to_jsonb(c) || jsonb_build_object(
      'cliente', coalesce(nullif(e.nome_fantasia, ''), e.razao_social, c.cliente_nome),
      'cnpj', e.cnpj,
      'situacao', crm.contrato_situacao(c.status, c.fim, c.aviso_dias),
      'responsavel_nome', p.nome,
      'negocio_numero', n.numero,
      'itens', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'produto_id', i.produto_id, 'descricao', i.descricao,
                                                             'quantidade', i.quantidade, 'preco', i.preco, 'total', i.total)
                                          order by i.criado_em)
                           from crm.contrato_item i where i.contrato_id = c.id), '[]'::jsonb),
      'eventos', coalesce((select jsonb_agg(jsonb_build_object('texto', ev.texto, 'autor', coalesce(a.nome, 'Sistema'),
                                                               'criado_em', ev.criado_em) order by ev.criado_em desc, ev.id desc)
                             from crm.contrato_evento ev left join crm.perfil a on a.user_id = ev.autor_id
                            where ev.contrato_id = c.id), '[]'::jsonb))
    into r
    from crm.contrato c
    left join public.empresa e on e.id = c.empresa_id
    left join crm.perfil p on p.user_id = c.responsavel_id
    left join crm.negocio n on n.id = c.negocio_id
   where c.id = p_id;
  if r is null then raise exception 'Contrato não encontrado.'; end if;
  return r;
end $$;

create or replace function public.painel_contrato_salvar(p_id uuid, p_dados jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare eu uuid; v uuid := p_id; atual crm.contrato;
begin
  eu := crm.exige_contratos();
  if v is null then
    if nullif(trim(p_dados->>'titulo'), '') is null then raise exception 'Informe o título do contrato.'; end if;
    if nullif(p_dados->>'empresa_id', '') is null and nullif(trim(p_dados->>'cliente_nome'), '') is null then
      raise exception 'Informe o cliente.';
    end if;
    insert into crm.contrato (empresa_id, cliente_nome, titulo, inicio, fim, renovacao_automatica, aviso_dias,
                              valor_mensal, dia_vencimento, forma_pagamento, indice_reajuste, responsavel_id,
                              observacao, criado_por)
    values (nullif(p_dados->>'empresa_id', '')::uuid, nullif(trim(p_dados->>'cliente_nome'), ''), trim(p_dados->>'titulo'),
            nullif(p_dados->>'inicio', '')::date, nullif(p_dados->>'fim', '')::date,
            coalesce((p_dados->>'renovacao_automatica')::boolean, false), coalesce(nullif(p_dados->>'aviso_dias', '')::int, 60),
            nullif(p_dados->>'valor_mensal', '')::numeric, nullif(p_dados->>'dia_vencimento', '')::int,
            nullif(trim(p_dados->>'forma_pagamento'), ''), nullif(trim(p_dados->>'indice_reajuste'), ''),
            coalesce(nullif(p_dados->>'responsavel_id', '')::uuid, eu), nullif(trim(p_dados->>'observacao'), ''), eu)
    returning id into v;
    perform crm.contrato_log(v, 'Contrato criado');
    return v;
  end if;

  select * into atual from crm.contrato where id = v for update;
  if atual.id is null then raise exception 'Contrato não encontrado.'; end if;
  if atual.status = 'cancelado' then raise exception 'Contrato cancelado não é editado.'; end if;

  update crm.contrato set
    titulo       = coalesce(nullif(trim(p_dados->>'titulo'), ''), titulo),
    empresa_id   = case when p_dados ? 'empresa_id' then nullif(p_dados->>'empresa_id', '')::uuid else empresa_id end,
    cliente_nome = case when p_dados ? 'cliente_nome' then nullif(trim(p_dados->>'cliente_nome'), '') else cliente_nome end,
    inicio       = case when p_dados ? 'inicio' then nullif(p_dados->>'inicio', '')::date else inicio end,
    fim          = case when p_dados ? 'fim' then nullif(p_dados->>'fim', '')::date else fim end,
    renovacao_automatica = coalesce((p_dados->>'renovacao_automatica')::boolean, renovacao_automatica),
    aviso_dias   = coalesce(nullif(p_dados->>'aviso_dias', '')::int, aviso_dias),
    valor_mensal = case when p_dados ? 'valor_mensal' then nullif(p_dados->>'valor_mensal', '')::numeric else valor_mensal end,
    dia_vencimento = case when p_dados ? 'dia_vencimento' then nullif(p_dados->>'dia_vencimento', '')::int else dia_vencimento end,
    forma_pagamento = case when p_dados ? 'forma_pagamento' then nullif(trim(p_dados->>'forma_pagamento'), '') else forma_pagamento end,
    indice_reajuste = case when p_dados ? 'indice_reajuste' then nullif(trim(p_dados->>'indice_reajuste'), '') else indice_reajuste end,
    responsavel_id = case when p_dados ? 'responsavel_id' then nullif(p_dados->>'responsavel_id', '')::uuid else responsavel_id end,
    observacao   = case when p_dados ? 'observacao' then nullif(trim(p_dados->>'observacao'), '') else observacao end,

    ultimo_alerta_em = case when p_dados ? 'fim' and nullif(p_dados->>'fim', '')::date is distinct from fim then null else ultimo_alerta_em end,
    renovacao_negocio_id = case when p_dados ? 'fim' and nullif(p_dados->>'fim', '')::date > coalesce(fim, '-infinity'::date)
                                then null else renovacao_negocio_id end,
    atualizado_em = now()
  where id = v;

  if p_dados ? 'fim' and nullif(p_dados->>'fim', '')::date is distinct from atual.fim then
    perform crm.contrato_log(v, 'Vigência até ' || coalesce(to_char(nullif(p_dados->>'fim', '')::date, 'DD/MM/YYYY'), 'indeterminada'));
  else
    perform crm.contrato_log(v, 'Dados atualizados');
  end if;
  return v;
end $$;

create or replace function public.painel_contrato_status(p_id uuid, p_status text, p_motivo text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare atual crm.contrato; motivo text := nullif(trim(p_motivo), '');
begin
  perform crm.exige_contratos();
  if p_status not in ('rascunho','revisao','enviado','parcial','assinado','cancelado') then
    raise exception 'Status inválido.';
  end if;
  select * into atual from crm.contrato where id = p_id for update;
  if atual.id is null then raise exception 'Contrato não encontrado.'; end if;
  if atual.status = p_status then return; end if;
  if p_status = 'cancelado' and motivo is null then raise exception 'Informe o motivo do cancelamento.'; end if;
  if atual.status = 'cancelado' and crm.papel_atual() not in ('admin','gestor') then
    raise exception 'Só gestor reabre contrato cancelado.' using errcode = '42501';
  end if;
  if p_status = 'assinado' and (atual.inicio is null or atual.fim is null) and not atual.renovacao_automatica then
    raise exception 'Informe início e fim da vigência (ou marque renovação automática) antes de marcar como assinado.';
  end if;
  update crm.contrato set status = p_status,
         assinado_em = case when p_status = 'assinado' then coalesce(assinado_em, now()) else assinado_em end,
         cancelado_motivo = case when p_status = 'cancelado' then motivo else null end,
         atualizado_em = now()
   where id = p_id;
  perform crm.contrato_log(p_id, crm.contrato_status_rotulo(atual.status) || ' → ' || crm.contrato_status_rotulo(p_status)
                                 || coalesce(': ' || motivo, ''));
end $$;

create or replace function public.painel_contrato_item_adicionar(p_contrato uuid, p_produto uuid, p_descricao text,
                                                                 p_quantidade numeric default 1, p_preco numeric default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v uuid; prod crm.produto;
begin
  perform crm.exige_contratos();
  if p_produto is not null then select * into prod from crm.produto where id = p_produto; end if;
  if coalesce(nullif(trim(p_descricao), ''), prod.nome) is null then raise exception 'Informe o serviço.'; end if;
  insert into crm.contrato_item (contrato_id, produto_id, descricao, quantidade, preco)
  values (p_contrato, p_produto, coalesce(nullif(trim(p_descricao), ''), prod.nome), coalesce(p_quantidade, 1),
          coalesce(p_preco, prod.preco, 0))
  returning id into v;
  perform crm.contrato_recalcular(p_contrato);
  return v;
end $$;

create or replace function public.painel_contrato_item_remover(p_item uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare c uuid;
begin
  perform crm.exige_contratos();
  delete from crm.contrato_item where id = p_item returning contrato_id into c;
  if c is not null then perform crm.contrato_recalcular(c); end if;
end $$;

create or replace function public.painel_contrato_arquivo(p_id uuid, p_path text, p_nome text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige_contratos();
  if p_path is not null and p_path not like 'contratos/' || p_id::text || '/%' then
    raise exception 'Caminho de arquivo inválido.';
  end if;
  update crm.contrato set arquivo_path = p_path, arquivo_nome = p_nome, atualizado_em = now() where id = p_id;
  perform crm.contrato_log(p_id, case when p_path is null then 'Arquivo removido' else 'Arquivo anexado: ' || coalesce(p_nome, '') end);
end $$;

drop function if exists public.painel_notificacoes(int);
create function public.painel_notificacoes(p_limite int default 30)
returns table (id bigint, negocio_id uuid, tarefa_id uuid, contrato_id uuid, tipo text, texto text,
               lida_em timestamptz, criado_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := crm.exige_ativo();
  return query
    select n.id, n.negocio_id, n.tarefa_id, n.contrato_id, n.tipo, n.texto, n.lida_em, n.criado_em
      from crm.notificacao n where n.user_id = eu
     order by n.criado_em desc limit least(greatest(p_limite, 1), 100);
end $$;

do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as assinatura
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'painel\_%'
  loop
    execute format('revoke execute on function %s from public, anon', f.assinatura);
    execute format('grant execute on function %s to authenticated', f.assinatura);
  end loop;
end $$;
