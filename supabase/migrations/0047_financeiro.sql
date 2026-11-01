

create table if not exists crm.fin_regra (
  id                  boolean primary key default true check (id),
  tolerancia_dias     int not null default 5 check (tolerancia_dias between 0 and 90),
  atualizado_em       timestamptz not null default now()
);
insert into crm.fin_regra (id) values (true) on conflict do nothing;

create table if not exists crm.cobranca (
  id             uuid primary key default gen_random_uuid(),
  numero         bigint generated always as identity unique,
  empresa_id     uuid references public.empresa(id) on delete set null,
  cliente_nome   text,
  contrato_id    uuid references crm.contrato(id) on delete set null,
  descricao      text not null,
  competencia    date not null,
  vencimento     date not null,
  valor          numeric(12,2) not null check (valor > 0),
  valor_pago     numeric(12,2) check (valor_pago >= 0),
  pago_em        date,
  forma          text check (forma in ('boleto','pix','transferencia','cartao','dinheiro','outro')),
  nota_fiscal    text,
  boleto         text,
  observacao     text,
  cancelada      boolean not null default false,
  cancelada_motivo text,
  origem         text not null default 'manual' check (origem in ('manual','contrato','importacao')),
  criado_por     uuid,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  constraint cobranca_tem_cliente check (empresa_id is not null or nullif(trim(cliente_nome), '') is not null),
  constraint cobranca_competencia check (competencia = date_trunc('month', competencia)::date)
);
create unique index if not exists cobranca_contrato_mes_uq on crm.cobranca (contrato_id, competencia)
  where contrato_id is not null and not cancelada;
create index if not exists cobranca_venc_idx on crm.cobranca (vencimento) where pago_em is null and not cancelada;
create index if not exists cobranca_empresa_idx on crm.cobranca (empresa_id);
create index if not exists cobranca_comp_idx on crm.cobranca (competencia);

create table if not exists crm.cobranca_evento (
  id           bigint generated always as identity primary key,
  cobranca_id  uuid not null references crm.cobranca(id) on delete cascade,
  texto        text not null,
  autor_id     uuid,
  criado_em    timestamptz not null default now()
);

alter table crm.fin_regra       enable row level security;
alter table crm.cobranca        enable row level security;
alter table crm.cobranca_evento enable row level security;

create or replace function crm.cobranca_situacao(p_cancelada boolean, p_pago date, p_venc date) returns text
language sql stable set search_path = '' as $$
  select case when p_cancelada then 'cancelada' when p_pago is not null then 'paga'
              when p_venc < (now() at time zone 'America/Sao_Paulo')::date then 'vencida' else 'aberta' end
$$;

create or replace function crm.exige_financeiro() returns uuid
language sql stable security definer set search_path = '' as $$
  select crm.exige('gestor','financeiro')
$$;

create or replace function crm.cobranca_log(p_cobranca uuid, p_texto text) returns void
language sql security definer set search_path = '' as $$
  insert into crm.cobranca_evento (cobranca_id, texto, autor_id) values (p_cobranca, p_texto, auth.uid())
$$;

create or replace function crm.fin_sincronizar_inadimplencia(p_empresa uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  tol int; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  funil_pv uuid; etapa_inad uuid; etapa_ok uuid; card uuid; atrasado numeric; nome text;
begin
  if p_empresa is null then return; end if;
  select tolerancia_dias into tol from crm.fin_regra where id;
  select f.id into funil_pv from crm.funil f where f.slug = 'pos-venda';
  select e.id into etapa_inad from crm.etapa e where e.funil_id = funil_pv and e.nome ilike 'inadimpl%' and e.ativo limit 1;
  select e.id into etapa_ok from crm.etapa e where e.funil_id = funil_pv and e.tipo = 'ganho' and e.ativo order by e.ordem limit 1;
  if etapa_inad is null then return; end if;

  select coalesce(sum(c.valor), 0) into atrasado from crm.cobranca c
   where c.empresa_id = p_empresa and not c.cancelada and c.pago_em is null and c.vencimento < hoje - tol;
  select n.id into card from crm.negocio n
   where n.empresa_id = p_empresa and n.etapa_id = etapa_inad order by n.criado_em desc limit 1;

  if atrasado > 0 and card is null then
    select coalesce(nullif(nome_fantasia, ''), razao_social) into nome from public.empresa where id = p_empresa;
    insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, valor, origem, observacao)
    values (funil_pv, etapa_inad, 'Inadimplência: ' || nome, p_empresa, atrasado, 'inadimplencia',
            'Aberto pelo Financeiro: cobrança vencida há mais de ' || tol || ' dias.')
    returning id into card;
    insert into crm.evento (negocio_id, tipo, texto) values (card, 'criado', 'Aberto pelo Financeiro (cobrança em atraso)');
  elsif atrasado > 0 and card is not null then
    update crm.negocio set valor = atrasado, atualizado_em = now() where id = card and valor <> atrasado;
  elsif atrasado = 0 and card is not null and etapa_ok is not null then
    update crm.negocio set etapa_id = etapa_ok, entrou_etapa_em = now(), fechado_em = now(), atualizado_em = now()
     where id = card;
    insert into crm.evento (negocio_id, tipo, texto, de_etapa_id, para_etapa_id)
    values (card, 'etapa', 'Débitos quitados no Financeiro', etapa_inad, etapa_ok);
  end if;
end $$;

create or replace function crm.fin_inadimplencia() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0;
begin
  for r in
    select distinct c.empresa_id from crm.cobranca c where c.empresa_id is not null
    union
    select n2.empresa_id from crm.negocio n2 join crm.etapa e on e.id = n2.etapa_id
     where e.nome ilike 'inadimpl%' and n2.empresa_id is not null
  loop
    perform crm.fin_sincronizar_inadimplencia(r.empresa_id);
    n := n + 1;
  end loop;
  return n;
end $$;

revoke execute on function crm.exige_financeiro(), crm.cobranca_log(uuid, text),
  crm.fin_sincronizar_inadimplencia(uuid), crm.fin_inadimplencia() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('crm-inadimplencia', '15 11 * * *', 'select crm.fin_inadimplencia()');
  end if;
end $$;

create or replace function public.painel_fin_resumo(p_competencia date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare comp date := date_trunc('month', coalesce(p_competencia, now()::date))::date; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        tol int;
begin
  perform crm.exige_financeiro();
  select tolerancia_dias into tol from crm.fin_regra where id;
  return (
    select jsonb_build_object(
      'competencia', comp,
      'previsto', coalesce(sum(valor) filter (where competencia = comp and not cancelada), 0),
      'recebido', coalesce(sum(coalesce(valor_pago, valor)) filter (where competencia = comp and pago_em is not null and not cancelada), 0),
      'a_receber', coalesce(sum(valor) filter (where competencia = comp and pago_em is null and not cancelada), 0),
      'vencido_total', coalesce(sum(valor) filter (where pago_em is null and not cancelada and vencimento < hoje), 0),
      'qtd_vencidas', count(*) filter (where pago_em is null and not cancelada and vencimento < hoje),
      'empresas_inadimplentes', count(distinct empresa_id) filter (where pago_em is null and not cancelada and vencimento < hoje - tol),
      'tolerancia_dias', tol,
      'contratos_sem_cobranca', (select count(*) from crm.contrato ct
                                  where ct.status = 'assinado' and ct.valor_mensal > 0
                                    and (ct.fim is null or ct.fim >= comp) and (ct.inicio is null or ct.inicio <= (comp + interval '1 month - 1 day')::date)
                                    and not exists (select 1 from crm.cobranca cb where cb.contrato_id = ct.id and cb.competencia = comp and not cb.cancelada)))
    from crm.cobranca);
end $$;

create or replace function public.painel_cobrancas(p_competencia date default null, p_situacao text default null, p_busca text default null)
returns table (id uuid, numero bigint, empresa_id uuid, cliente text, cnpj text, contrato_id uuid, contrato_numero bigint,
               descricao text, competencia date, vencimento date, valor numeric, valor_pago numeric, pago_em date,
               forma text, nota_fiscal text, boleto text, observacao text, situacao text, dias_atraso int, origem text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        dig text := nullif(regexp_replace(coalesce(p_busca, ''), '\D', '', 'g'), '');
begin
  perform crm.exige_financeiro();
  return query
    select c.id, c.numero, c.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social, c.cliente_nome)::text, e.cnpj::text,
           c.contrato_id, ct.numero, c.descricao, c.competencia, c.vencimento, c.valor, c.valor_pago, c.pago_em,
           c.forma, c.nota_fiscal, c.boleto, c.observacao, crm.cobranca_situacao(c.cancelada, c.pago_em, c.vencimento),
           case when c.pago_em is null and not c.cancelada and c.vencimento < hoje then (hoje - c.vencimento)::int else 0 end,
           c.origem
      from crm.cobranca c
      left join public.empresa e on e.id = c.empresa_id
      left join crm.contrato ct on ct.id = c.contrato_id
     where (p_competencia is null or c.competencia = date_trunc('month', p_competencia)::date

            or (p_situacao is null and c.pago_em is null and not c.cancelada and c.vencimento < hoje and c.competencia < date_trunc('month', p_competencia)::date))
       and (p_situacao is null or crm.cobranca_situacao(c.cancelada, c.pago_em, c.vencimento) = p_situacao)
       and (termo is null or c.descricao ilike '%' || termo || '%' or e.razao_social ilike '%' || termo || '%'
            or e.nome_fantasia ilike '%' || termo || '%' or c.cliente_nome ilike '%' || termo || '%'
            or c.nota_fiscal = termo or (dig is not null and length(dig) >= 4 and regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') like dig || '%'))
     order by case crm.cobranca_situacao(c.cancelada, c.pago_em, c.vencimento) when 'vencida' then 0 when 'aberta' then 1 when 'paga' then 2 else 3 end,
              c.vencimento, c.numero;
end $$;

create or replace function public.painel_cobranca_historico(p_id uuid)
returns table (texto text, autor text, criado_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige_financeiro();
  return query select ev.texto, coalesce(p.nome, 'Sistema')::text, ev.criado_em
    from crm.cobranca_evento ev left join crm.perfil p on p.user_id = ev.autor_id
   where ev.cobranca_id = p_id order by ev.criado_em desc, ev.id desc;
end $$;

create or replace function public.painel_fin_regra() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform crm.exige_financeiro();
  return (select jsonb_build_object('tolerancia_dias', tolerancia_dias) from crm.fin_regra where id);
end $$;

create or replace function public.painel_cobranca_salvar(p_id uuid, p_dados jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare eu uuid; v uuid := p_id; atual crm.cobranca; venc date; emp uuid;
begin
  eu := crm.exige_financeiro();
  if v is null then
    venc := nullif(p_dados->>'vencimento', '')::date;
    if venc is null then raise exception 'Informe o vencimento.'; end if;
    if coalesce(nullif(p_dados->>'valor', '')::numeric, 0) <= 0 then raise exception 'Informe o valor.'; end if;
    if nullif(p_dados->>'empresa_id', '') is null and nullif(trim(p_dados->>'cliente_nome'), '') is null then
      raise exception 'Informe o cliente.';
    end if;
    insert into crm.cobranca (empresa_id, cliente_nome, contrato_id, descricao, competencia, vencimento, valor,
                              nota_fiscal, boleto, forma, observacao, criado_por)
    values (nullif(p_dados->>'empresa_id', '')::uuid, nullif(trim(p_dados->>'cliente_nome'), ''),
            nullif(p_dados->>'contrato_id', '')::uuid, coalesce(nullif(trim(p_dados->>'descricao'), ''), 'Serviços'),
            date_trunc('month', coalesce(nullif(p_dados->>'competencia', '')::date, venc))::date, venc,
            (p_dados->>'valor')::numeric, nullif(trim(p_dados->>'nota_fiscal'), ''), nullif(trim(p_dados->>'boleto'), ''),
            nullif(p_dados->>'forma', ''), nullif(trim(p_dados->>'observacao'), ''), eu)
    returning id, empresa_id into v, emp;
    perform crm.cobranca_log(v, 'Cobrança lançada');
    perform crm.fin_sincronizar_inadimplencia(emp);
    return v;
  end if;

  select * into atual from crm.cobranca where id = v for update;
  if atual.id is null then raise exception 'Cobrança não encontrada.'; end if;
  if atual.cancelada then raise exception 'Cobrança cancelada não é editada.'; end if;
  update crm.cobranca set
    descricao   = coalesce(nullif(trim(p_dados->>'descricao'), ''), descricao),
    vencimento  = coalesce(nullif(p_dados->>'vencimento', '')::date, vencimento),
    valor       = coalesce(nullif(p_dados->>'valor', '')::numeric, valor),
    nota_fiscal = case when p_dados ? 'nota_fiscal' then nullif(trim(p_dados->>'nota_fiscal'), '') else nota_fiscal end,
    boleto      = case when p_dados ? 'boleto' then nullif(trim(p_dados->>'boleto'), '') else boleto end,
    forma       = case when p_dados ? 'forma' then nullif(p_dados->>'forma', '') else forma end,
    observacao  = case when p_dados ? 'observacao' then nullif(trim(p_dados->>'observacao'), '') else observacao end,
    atualizado_em = now()
  where id = v;
  perform crm.cobranca_log(v, 'Dados atualizados');
  perform crm.fin_sincronizar_inadimplencia(atual.empresa_id);
  return v;
end $$;

create or replace function public.painel_cobranca_baixa(p_id uuid, p_pago_em date, p_valor numeric default null, p_forma text default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare atual crm.cobranca;
begin
  perform crm.exige_financeiro();
  select * into atual from crm.cobranca where id = p_id for update;
  if atual.id is null then raise exception 'Cobrança não encontrada.'; end if;
  if atual.cancelada then raise exception 'Cobrança cancelada.'; end if;
  if p_pago_em is not null and p_pago_em > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception 'A data do pagamento não pode ser no futuro.';
  end if;
  update crm.cobranca set pago_em = p_pago_em,
         valor_pago = case when p_pago_em is null then null else coalesce(p_valor, valor) end,
         forma = coalesce(p_forma, forma), atualizado_em = now()
   where id = p_id;
  perform crm.cobranca_log(p_id, case when p_pago_em is null then 'Pagamento desfeito'
                                      else 'Pago em ' || to_char(p_pago_em, 'DD/MM/YYYY') || ' — R$ ' ||
                                           to_char(coalesce(p_valor, atual.valor), 'FM999G999G990D00') end);
  perform crm.fin_sincronizar_inadimplencia(atual.empresa_id);
end $$;

create or replace function public.painel_cobranca_cancelar(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = '' as $$
declare atual crm.cobranca;
begin
  perform crm.exige_financeiro();
  if nullif(trim(p_motivo), '') is null then raise exception 'Informe o motivo.'; end if;
  select * into atual from crm.cobranca where id = p_id for update;
  if atual.id is null then raise exception 'Cobrança não encontrada.'; end if;
  if atual.pago_em is not null then raise exception 'Cobrança paga: desfaça o pagamento antes de cancelar.'; end if;
  update crm.cobranca set cancelada = true, cancelada_motivo = trim(p_motivo), atualizado_em = now() where id = p_id;
  perform crm.cobranca_log(p_id, 'Cancelada: ' || trim(p_motivo));
  perform crm.fin_sincronizar_inadimplencia(atual.empresa_id);
end $$;

create or replace function public.painel_fin_gerar_mes(p_competencia date) returns int
language plpgsql security definer set search_path = '' as $$
declare eu uuid; comp date := date_trunc('month', p_competencia)::date; fim_mes date; n int := 0; r record; venc date;
begin
  eu := crm.exige_financeiro();
  fim_mes := (comp + interval '1 month - 1 day')::date;
  for r in
    select ct.* from crm.contrato ct
     where ct.status = 'assinado' and ct.valor_mensal > 0
       and (ct.fim is null or ct.fim >= comp) and (ct.inicio is null or ct.inicio <= fim_mes)
       and not exists (select 1 from crm.cobranca cb where cb.contrato_id = ct.id and cb.competencia = comp and not cb.cancelada)
  loop
    venc := least(comp + (coalesce(r.dia_vencimento, 10) - 1), fim_mes);
    insert into crm.cobranca (empresa_id, cliente_nome, contrato_id, descricao, competencia, vencimento, valor, forma, origem, criado_por)
    values (r.empresa_id, r.cliente_nome, r.id, r.titulo || ' — ' || to_char(comp, 'MM/YYYY'), comp, venc, r.valor_mensal,
            case lower(coalesce(r.forma_pagamento, '')) when 'boleto' then 'boleto' when 'pix' then 'pix' else null end,
            'contrato', eu);
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.painel_fin_importar(p_linhas jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare eu uuid; l jsonb; emp uuid; dig text; venc date; ok int := 0; erros jsonb := '[]'::jsonb; i int := 0; v uuid;
begin
  eu := crm.exige_financeiro();
  if jsonb_typeof(p_linhas) <> 'array' then raise exception 'Formato inválido.'; end if;
  if jsonb_array_length(p_linhas) > 5000 then raise exception 'Máximo de 5.000 linhas por importação.'; end if;
  for l in select * from jsonb_array_elements(p_linhas) loop
    i := i + 1;
    begin
      dig := nullif(regexp_replace(coalesce(l->>'cnpj', ''), '\D', '', 'g'), '');
      emp := null;
      if dig is not null then
        select e.id into emp from public.empresa e where regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') = dig
         order by e.situacao = 'ativo' desc limit 1;
      end if;
      if emp is null and nullif(trim(l->>'cliente'), '') is null then
        raise exception 'CNPJ não encontrado na base e sem nome de cliente';
      end if;
      venc := (l->>'vencimento')::date;
      insert into crm.cobranca (empresa_id, cliente_nome, descricao, competencia, vencimento, valor, pago_em, valor_pago,
                                nota_fiscal, origem, criado_por)
      values (emp, case when emp is null then trim(l->>'cliente') end, coalesce(nullif(trim(l->>'descricao'), ''), 'Importado'),
              date_trunc('month', coalesce(nullif(l->>'competencia', '')::date, venc))::date, venc, (l->>'valor')::numeric,
              nullif(l->>'pago_em', '')::date, nullif(l->>'valor_pago', '')::numeric, nullif(trim(l->>'nota_fiscal'), ''),
              'importacao', eu)
      returning id into v;
      insert into crm.cobranca_evento (cobranca_id, texto, autor_id) values (v, 'Importada de planilha', eu);
      ok := ok + 1;
    exception when others then
      erros := erros || jsonb_build_object('linha', i, 'erro', sqlerrm);
    end;
  end loop;
  perform crm.fin_inadimplencia();
  return jsonb_build_object('importadas', ok, 'erros', erros);
end $$;

create or replace function public.painel_fin_regra_salvar(p_tolerancia int) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('gestor');
  update crm.fin_regra set tolerancia_dias = p_tolerancia, atualizado_em = now() where id;
  perform crm.fin_inadimplencia();
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
