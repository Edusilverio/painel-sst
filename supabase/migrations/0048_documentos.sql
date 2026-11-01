

create table if not exists crm.documento_renovacao (
  documento_id uuid primary key references public.documento(id) on delete cascade,
  negocio_id   uuid references crm.negocio(id) on delete set null,
  criado_em    timestamptz not null default now()
);
alter table crm.documento_renovacao enable row level security;

create table if not exists crm.documento_regra (
  id          boolean primary key default true check (id),
  aviso_dias  int not null default 60 check (aviso_dias between 0 and 365)
);
insert into crm.documento_regra (id) values (true) on conflict do nothing;
alter table crm.documento_regra enable row level security;

create or replace function crm.documento_situacao(p_situacao text, p_fim date, p_aviso int) returns text
language sql stable set search_path = '' as $$
  select case
    when p_situacao = 'cancelado' then 'cancelado'
    when p_situacao = 'em_elaboracao' then 'em_elaboracao'
    when p_fim is null then 'vigente'
    when p_fim < (now() at time zone 'America/Sao_Paulo')::date then 'vencido'
    when p_fim <= (now() at time zone 'America/Sao_Paulo')::date + p_aviso then 'a_vencer'
    else 'vigente' end
$$;

create or replace function crm.alertas_documentos() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0; aviso int; funil_l uuid; etapa_l uuid; neg uuid; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  select aviso_dias into aviso from crm.documento_regra where id;
  select f.id into funil_l from crm.funil f where f.slug = 'laudos';
  select e.id into etapa_l from crm.etapa e where e.funil_id = funil_l and e.tipo = 'aberta' and e.ativo order by e.ordem limit 1;
  if etapa_l is null then return 0; end if;
  for r in
    select d.id, d.tipo::text tipo, d.vigencia_fim, d.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social) nome
      from public.documento d join public.empresa e on e.id = d.empresa_id
     where d.situacao::text not in ('cancelado','em_elaboracao') and d.vigencia_fim is not null
       and d.vigencia_fim <= hoje + aviso
       and not exists (select 1 from crm.documento_renovacao x where x.documento_id = d.id)
  loop
    insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, origem, observacao)
    values (funil_l, etapa_l, 'Renovar ' || r.tipo || ': ' || r.nome, r.empresa_id, 'renovacao',
            r.tipo || ' vence em ' || to_char(r.vigencia_fim, 'DD/MM/YYYY'))
    returning id into neg;
    insert into crm.evento (negocio_id, tipo, texto) values (neg, 'criado', 'Aberto pelo vencimento do ' || r.tipo);
    insert into crm.documento_renovacao (documento_id, negocio_id) values (r.id, neg);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function crm.alertas_documentos() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('crm-alertas-documentos', '20 11 * * *', 'select crm.alertas_documentos()');
  end if;
end $$;

create or replace function public.painel_documentos_resumo() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare aviso int;
begin
  perform crm.exige('gestor','operacoes','comercial');
  select aviso_dias into aviso from crm.documento_regra where id;
  return (with s as (select crm.documento_situacao(situacao::text, vigencia_fim, aviso) sit from public.documento)
          select jsonb_build_object('vigentes', count(*) filter (where sit = 'vigente'),
                                    'a_vencer', count(*) filter (where sit = 'a_vencer'),
                                    'vencidos', count(*) filter (where sit = 'vencido'),
                                    'em_elaboracao', count(*) filter (where sit = 'em_elaboracao'),
                                    'aviso_dias', aviso,
                                    'pode_editar', crm.papel_atual() in ('admin','gestor','operacoes'))
            from s);
end $$;

create or replace function public.painel_documentos(p_busca text default null, p_tipo text default null, p_situacao text default null,
                                                    p_empresa uuid default null)
returns table (id uuid, empresa_id uuid, empresa text, cnpj text, tipo text, versao text, data_elaboracao date,
               vigencia_inicio date, vigencia_fim date, dias_para_vencer int, situacao text, situacao_cadastro text,
               responsavel_id uuid, responsavel text, arquivo_path text, observacao text, origem text, renovacao_negocio_id uuid)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); aviso int; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        dig text := nullif(regexp_replace(coalesce(p_busca, ''), '\D', '', 'g'), '');
begin
  perform crm.exige('gestor','operacoes','comercial');
  select aviso_dias into aviso from crm.documento_regra where id;
  return query
    select d.id, d.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social)::text, e.cnpj::text, d.tipo::text, d.versao,
           d.data_elaboracao, d.vigencia_inicio, d.vigencia_fim, (d.vigencia_fim - hoje)::int,
           crm.documento_situacao(d.situacao::text, d.vigencia_fim, aviso), d.situacao::text,
           d.responsavel_id, p.nome::text, d.arquivo_path, d.observacao, d.origem::text, x.negocio_id
      from public.documento d
      join public.empresa e on e.id = d.empresa_id
      left join public.profissional p on p.id = d.responsavel_id
      left join crm.documento_renovacao x on x.documento_id = d.id
     where (p_empresa is null or d.empresa_id = p_empresa)
       and (p_tipo is null or d.tipo::text = p_tipo)
       and (p_situacao is null or crm.documento_situacao(d.situacao::text, d.vigencia_fim, aviso) = p_situacao)
       and (termo is null or e.razao_social ilike '%' || termo || '%' or e.nome_fantasia ilike '%' || termo || '%'
            or (dig is not null and length(dig) >= 4 and regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') like dig || '%'))
     order by case crm.documento_situacao(d.situacao::text, d.vigencia_fim, aviso)
                when 'vencido' then 0 when 'a_vencer' then 1 when 'em_elaboracao' then 2 when 'vigente' then 3 else 4 end,
              d.vigencia_fim nulls last
     limit 1000;
end $$;

create or replace function public.painel_documento_salvar(p_id uuid, p_dados jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v uuid := p_id; fim_antigo date;
begin
  perform crm.exige('gestor','operacoes');
  if p_dados ? 'tipo' and p_dados->>'tipo' not in ('PGR','PCMSO','LTCAT','LTIP','PPR','PCA','PPP','OUTRO') then
    raise exception 'Tipo inválido.';
  end if;
  if p_dados ? 'situacao' and p_dados->>'situacao' not in ('em_elaboracao','vigente','vencido','cancelado') then
    raise exception 'Situação inválida.';
  end if;
  if v is null then
    if nullif(p_dados->>'empresa_id', '') is null then raise exception 'Informe a empresa.'; end if;
    insert into public.documento (empresa_id, tipo, versao, data_elaboracao, vigencia_inicio, vigencia_fim, situacao,
                                  responsavel_id, observacao, origem)
    values ((p_dados->>'empresa_id')::uuid, coalesce(nullif(p_dados->>'tipo', ''), 'PGR')::public.tipo_documento,
            nullif(trim(p_dados->>'versao'), ''), nullif(p_dados->>'data_elaboracao', '')::date,
            nullif(p_dados->>'vigencia_inicio', '')::date, nullif(p_dados->>'vigencia_fim', '')::date,
            coalesce(nullif(p_dados->>'situacao', ''), 'vigente')::public.situacao_documento,
            nullif(p_dados->>'responsavel_id', '')::uuid, nullif(trim(p_dados->>'observacao'), ''), 'manual')
    returning id into v;
    return v;
  end if;
  select vigencia_fim into fim_antigo from public.documento where id = v;
  if not found then raise exception 'Documento não encontrado.'; end if;
  update public.documento set
    tipo = coalesce(nullif(p_dados->>'tipo', ''), tipo::text)::public.tipo_documento,
    versao = case when p_dados ? 'versao' then nullif(trim(p_dados->>'versao'), '') else versao end,
    data_elaboracao = case when p_dados ? 'data_elaboracao' then nullif(p_dados->>'data_elaboracao', '')::date else data_elaboracao end,
    vigencia_inicio = case when p_dados ? 'vigencia_inicio' then nullif(p_dados->>'vigencia_inicio', '')::date else vigencia_inicio end,
    vigencia_fim = case when p_dados ? 'vigencia_fim' then nullif(p_dados->>'vigencia_fim', '')::date else vigencia_fim end,
    situacao = coalesce(nullif(p_dados->>'situacao', ''), situacao::text)::public.situacao_documento,
    responsavel_id = case when p_dados ? 'responsavel_id' then nullif(p_dados->>'responsavel_id', '')::uuid else responsavel_id end,
    observacao = case when p_dados ? 'observacao' then nullif(trim(p_dados->>'observacao'), '') else observacao end,
    updated_at = now()
  where id = v;

  if p_dados ? 'vigencia_fim' and nullif(p_dados->>'vigencia_fim', '')::date > coalesce(fim_antigo, '-infinity'::date) then
    delete from crm.documento_renovacao where documento_id = v;
  end if;
  return v;
end $$;

create or replace function public.painel_documento_arquivo(p_id uuid, p_path text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('gestor','operacoes');
  if p_path is not null and p_path not like 'documentos/' || p_id::text || '/%' then
    raise exception 'Caminho de arquivo inválido.';
  end if;
  update public.documento set arquivo_path = p_path, updated_at = now() where id = p_id;
end $$;

create or replace function public.painel_documento_regra_salvar(p_aviso int) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('gestor');
  update crm.documento_regra set aviso_dias = p_aviso where id;
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
