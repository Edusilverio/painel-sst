

create or replace function crm.pode_clinico() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(crm.papel_atual() in ('admin','gestor','operacoes'), false)
$$;
revoke execute on function crm.pode_clinico() from public, anon, authenticated;

create or replace function public.painel_resumo() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb; clin boolean;
begin
  perform crm.exige_ativo();
  clin := crm.pode_clinico();

  select jsonb_build_object(
    'clientes_total',        (select count(*) from public.empresa),
    'clientes_ativos',       (select count(*) from public.empresa where situacao = 'ativo'),
    'clientes_sem_contrato', (select count(*) from public.empresa where situacao = 'sem_contrato'),
    'clientes_inativos',     (select count(*) from public.empresa where situacao = 'inativo'),
    'clientes_a_confirmar',  (select count(*) from public.empresa where situacao is null),
    'unidades',              (select count(*) from public.unidade),
    'colaboradores_ativos',  (select count(*) from public.colaborador where situacao = 'ativo'),
    'negocios_abertos',      (select count(*) from crm.negocio n join crm.etapa e on e.id = n.etapa_id where e.tipo = 'aberta'),
    'valor_aberto_comercial',(select coalesce(sum(n.valor), 0) from crm.negocio n
                                join crm.etapa e on e.id = n.etapa_id join crm.funil f on f.id = n.funil_id
                               where e.tipo = 'aberta' and f.slug = 'comercial'),
    'ganhos_mes',            (select count(*) from crm.negocio n join crm.etapa e on e.id = n.etapa_id
                               join crm.funil f on f.id = n.funil_id
                              where e.tipo = 'ganho' and f.slug = 'comercial'
                                and n.fechado_em >= date_trunc('month', now())),
    'valor_ganho_mes',       (select coalesce(sum(n.valor), 0) from crm.negocio n join crm.etapa e on e.id = n.etapa_id
                               join crm.funil f on f.id = n.funil_id
                              where e.tipo = 'ganho' and f.slug = 'comercial'
                                and n.fechado_em >= date_trunc('month', now())),
    'parados',               (select count(*) from crm.negocio n join crm.etapa e on e.id = n.etapa_id
                              where e.tipo = 'aberta' and e.alerta_dias is not null
                                and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)),
    'acesso_clinico',        clin,
    'exames_vencidos',       case when clin then (select count(*) from app.vw_aso_vencimento where status = 'vencido') end,
    'exames_30_dias',        case when clin then (select count(*) from app.vw_aso_vencimento where status = 'vence_em_30_dias') end,
    'exames_60_dias',        case when clin then (select count(*) from app.vw_aso_vencimento where status = 'vence_em_60_dias') end,
    'atendimentos_mes',      case when clin then (select count(*) from public.atendimento
                                                   where data_atendimento >= date_trunc('month', now())) end
  ) into r;

  r := r || jsonb_build_object('funil_comercial', coalesce((
    select jsonb_agg(jsonb_build_object('etapa', e.nome, 'cor', e.cor, 'qtd', coalesce(c.qtd, 0), 'valor', coalesce(c.valor, 0)) order by e.ordem)
      from crm.etapa e join crm.funil f on f.id = e.funil_id and f.slug = 'comercial'
      left join (select n.etapa_id, count(*) qtd, sum(n.valor) valor from crm.negocio n group by 1) c on c.etapa_id = e.id
     where e.ativo and e.tipo = 'aberta'), '[]'::jsonb));
  return r;
end $$;

create or replace function public.painel_clientes(
  p_busca text default null, p_situacao text default null, p_limite int default 50, p_offset int default 0
) returns table (id uuid, nome text, razao_social text, cnpj text, situacao text, cidade text, uf text,
                 telefone text, email text, unidades int, colaboradores int, negocios_abertos int, total bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); dig text;
begin
  perform crm.exige_ativo();
  dig := nullif(regexp_replace(coalesce(termo, ''), '\D', '', 'g'), '');
  return query
    with base as (
      select e.*
        from public.empresa e
       where (termo is null
              or e.razao_social ilike '%' || termo || '%'
              or e.nome_fantasia ilike '%' || termo || '%'
              or (dig is not null and length(dig) >= 4 and regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') like '%' || dig || '%'))
         and (p_situacao is null
              or (p_situacao = 'a_confirmar' and e.situacao is null)
              or e.situacao::text = p_situacao)
    ), pagina as (
      select b.*, count(*) over () as total_linhas from base b
       order by b.razao_social
       limit least(greatest(p_limite, 1), 200) offset greatest(p_offset, 0)
    )
    select pg.id, coalesce(nullif(pg.nome_fantasia, ''), pg.razao_social)::text, pg.razao_social::text, pg.cnpj::text,
           coalesce(pg.situacao::text, 'a_confirmar'), pg.cidade::text, pg.uf::text, pg.telefone::text, pg.email::text,
           (select count(*)::int from public.unidade u where u.empresa_id = pg.id),
           (select count(*)::int from public.colaborador c where c.empresa_id = pg.id and c.situacao = 'ativo'),
           (select count(*)::int from crm.negocio n join crm.etapa et on et.id = n.etapa_id
             where n.empresa_id = pg.id and et.tipo = 'aberta'),
           pg.total_linhas
      from pagina pg
     order by pg.razao_social;
end $$;

create or replace function public.painel_cliente(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb; clin boolean;
begin
  perform crm.exige_ativo();
  clin := crm.pode_clinico();
  select jsonb_build_object(
    'id', e.id, 'razao_social', e.razao_social, 'nome_fantasia', e.nome_fantasia, 'cnpj', e.cnpj,
    'situacao', coalesce(e.situacao::text, 'a_confirmar'), 'cnae_principal', e.cnae_principal,
    'grau_risco', e.grau_risco, 'cidade', e.cidade, 'uf', e.uf, 'cep', e.cep,
    'endereco', concat_ws(', ', nullif(e.logradouro, ''), nullif(e.numero, ''), nullif(e.complemento, ''), nullif(e.bairro, '')),
    'telefone', e.telefone, 'email', e.email,
    'contrato_inicio', e.contrato_inicio, 'contrato_fim', e.contrato_fim,
    'contatos', coalesce((select jsonb_agg(jsonb_build_object('nome', c.nome, 'cargo', c.cargo, 'email', c.email,
                              'telefone', c.telefone, 'tipo', c.tipo, 'recebe_alerta_exame', c.recebe_alerta_exame) order by c.nome)
                            from public.empresa_contato c where c.empresa_id = e.id), '[]'::jsonb),
    'unidades', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'nome', u.nome, 'cnpj', u.cnpj,
                              'cidade', u.cidade, 'uf', u.uf, 'ativa', u.ativa,
                              'setores', (select count(*) from public.setor s where s.unidade_id = u.id),
                              'colaboradores', (select count(*) from public.colaborador c where c.unidade_id = u.id and c.situacao = 'ativo'))
                            order by u.nome)
                            from public.unidade u where u.empresa_id = e.id), '[]'::jsonb),
    'documentos', coalesce((select jsonb_agg(jsonb_build_object('tipo', d.tipo, 'versao', d.versao,
                              'vigencia_inicio', d.vigencia_inicio, 'vigencia_fim', d.vigencia_fim, 'situacao', d.situacao)
                            order by d.vigencia_fim desc nulls last)
                            from public.documento d where d.empresa_id = e.id), '[]'::jsonb),
    'negocios', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'numero', n.numero, 'titulo', n.titulo,
                              'funil', f.nome, 'etapa', et.nome, 'tipo', et.tipo, 'valor', n.valor, 'criado_em', n.criado_em)
                            order by n.criado_em desc)
                            from crm.negocio n join crm.funil f on f.id = n.funil_id join crm.etapa et on et.id = n.etapa_id
                           where n.empresa_id = e.id), '[]'::jsonb),
    'acesso_clinico', clin,
    'vencimentos', case when clin then (
        select jsonb_build_object(
          'vencido', count(*) filter (where v.status = 'vencido'),
          'vence_em_30_dias', count(*) filter (where v.status = 'vence_em_30_dias'),
          'vence_em_60_dias', count(*) filter (where v.status = 'vence_em_60_dias'),
          'em_dia', count(*) filter (where v.status = 'em_dia'))
          from app.vw_aso_vencimento v where v.empresa_id = e.id) end,
    'ultimo_atendimento', case when clin then (select max(a.data_atendimento) from public.atendimento a where a.empresa_id = e.id) end,
    'atendimentos_12m', case when clin then (select count(*) from public.atendimento a
                                              where a.empresa_id = e.id and a.data_atendimento >= now() - interval '12 months') end
  ) into r
  from public.empresa e where e.id = p_id;
  if r is null then raise exception 'Cliente não encontrado.'; end if;
  return r;
end $$;

create or replace function public.painel_vencimentos(
  p_empresa uuid default null, p_status text default null, p_busca text default null,
  p_limite int default 100, p_offset int default 0
) returns table (colaborador_id uuid, colaborador text, cpf text, matricula_esocial text,
                 empresa_id uuid, empresa text, unidade text, setor text, funcao text,
                 proximo_exame date, dias_para_vencer int, exames_vencidos bigint,
                 exames_nunca_feitos bigint, status text, total bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform crm.exige('gestor','operacoes');
  return query
    select v.colaborador_id, v.colaborador::text, v.cpf::text, v.matricula_esocial::text, v.empresa_id, v.empresa::text,
           v.unidade::text, v.setor::text, v.funcao::text, v.proximo_exame::date, v.dias_para_vencer::int,
           v.exames_vencidos::bigint, v.exames_nunca_feitos::bigint, v.status::text,
           count(*) over ()
      from app.vw_aso_vencimento v
     where (p_empresa is null or v.empresa_id = p_empresa)
       and (p_status is null or v.status = p_status)
       and (termo is null or v.colaborador ilike '%' || termo || '%' or v.cpf like '%' || termo || '%'
            or v.empresa ilike '%' || termo || '%')
     order by (v.status = 'vencido') desc, v.dias_para_vencer nulls first, v.colaborador
     limit least(greatest(p_limite, 1), 1000) offset greatest(p_offset, 0);
end $$;

create or replace function public.painel_atendimentos(
  p_empresa uuid default null, p_de date default null, p_ate date default null,
  p_situacao text default null, p_busca text default null, p_limite int default 100, p_offset int default 0
) returns table (id uuid, data_atendimento timestamptz, data_agendada timestamptz, tipo text, situacao text,
                 aso_resultado text, colaborador text, cpf text, empresa_id uuid, empresa text,
                 funcao text, profissional text, qtd_exames int, total bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform crm.exige('gestor','operacoes');
  return query
    select a.id, coalesce(a.data_agendada, a.data_atendimento::timestamp at time zone 'America/Sao_Paulo'), a.data_agendada::timestamptz, a.tipo::text, a.situacao::text,
           a.aso_resultado::text, c.nome::text, c.cpf::text, a.empresa_id,
           coalesce(nullif(e.nome_fantasia, ''), e.razao_social)::text, f.nome::text, p.nome::text,
           (select count(*)::int from public.atendimento_exame ae where ae.atendimento_id = a.id),
           count(*) over ()
      from public.atendimento a
      left join public.colaborador c on c.id = a.colaborador_id
      left join public.empresa e on e.id = a.empresa_id
      left join public.funcao f on f.id = a.funcao_id
      left join public.profissional p on p.id = a.profissional_id
     where (p_empresa is null or a.empresa_id = p_empresa)
       and (p_de is null or coalesce(a.data_atendimento, a.data_agendada) >= p_de)
       and (p_ate is null or coalesce(a.data_atendimento, a.data_agendada) < p_ate + 1)
       and (p_situacao is null or a.situacao::text = p_situacao)
       and (termo is null or c.nome ilike '%' || termo || '%' or c.cpf like '%' || termo || '%')
     order by coalesce(a.data_atendimento, a.data_agendada) desc nulls last
     limit least(greatest(p_limite, 1), 1000) offset greatest(p_offset, 0);
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
