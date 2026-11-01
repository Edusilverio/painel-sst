

create or replace function crm.ve_valores()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(crm.papel_atual()::text in ('admin', 'financeiro', 'comercial'), false)
$$;
revoke execute on function crm.ve_valores() from public, anon;
grant execute on function crm.ve_valores() to authenticated;

create or replace function public.painel_crm_quadro(p_funil uuid, p_responsavel uuid default null, p_busca text default null, p_dias_fechados integer default 30)
returns table(id uuid, numero bigint, etapa_id uuid, titulo text, cliente text, empresa_id uuid, responsavel_id uuid, responsavel_nome text,
              valor numeric, origem text, entrou_etapa_em timestamptz, dias_na_etapa integer, atrasado boolean, qtd_itens integer,
              previsao_fechamento date, criado_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); vv boolean;
begin
  perform crm.exige_ativo();
  vv := crm.ve_valores();
  return query
    select n.id, n.numero, n.etapa_id, n.titulo,
           coalesce(nullif(em.nome_fantasia, ''), em.razao_social, n.cliente_nome)::text,
           n.empresa_id, n.responsavel_id, p.nome, case when vv then n.valor end, n.origem, n.entrou_etapa_em,
           floor(extract(epoch from now() - n.entrou_etapa_em) / 86400)::int,
           (e.tipo = 'aberta' and e.alerta_dias is not null
             and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)),
           (select count(*)::int from crm.negocio_item i where i.negocio_id = n.id),
           n.previsao_fechamento, n.criado_em
      from crm.negocio n
      join crm.etapa e on e.id = n.etapa_id
      left join public.empresa em on em.id = n.empresa_id
      left join crm.perfil p on p.user_id = n.responsavel_id
     where n.funil_id = p_funil
       and crm.ve_negocio(n.responsavel_id)
       and (p_responsavel is null or n.responsavel_id = p_responsavel)
       and (e.tipo = 'aberta' or n.fechado_em >= now() - make_interval(days => greatest(p_dias_fechados, 0)))
       and (termo is null
            or n.titulo ilike '%' || termo || '%'
            or n.cliente_nome ilike '%' || termo || '%'
            or em.razao_social ilike '%' || termo || '%'
            or em.nome_fantasia ilike '%' || termo || '%'
            or n.contato_nome ilike '%' || termo || '%'
            or n.numero::text = termo)
     order by n.entrou_etapa_em;
end $$;

create or replace function public.painel_crm_pendencias(p_so_minhas boolean default false)
returns table(id uuid, numero bigint, titulo text, cliente text, funil_id uuid, funil text, etapa text, responsavel_id uuid,
              responsavel_nome text, dias_na_etapa integer, alerta_dias integer, valor numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare eu uuid; vv boolean;
begin
  eu := crm.exige_ativo();
  vv := crm.ve_valores();
  return query
    select n.id, n.numero, n.titulo,
           coalesce(nullif(em.nome_fantasia, ''), em.razao_social, n.cliente_nome)::text,
           f.id, f.nome, e.nome, n.responsavel_id, p.nome,
           floor(extract(epoch from now() - n.entrou_etapa_em) / 86400)::int,
           e.alerta_dias, case when vv then n.valor end
      from crm.negocio n
      join crm.etapa e on e.id = n.etapa_id
      join crm.funil f on f.id = n.funil_id
      left join public.empresa em on em.id = n.empresa_id
      left join crm.perfil p on p.user_id = n.responsavel_id
     where e.tipo = 'aberta' and e.alerta_dias is not null
       and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)
       and (not p_so_minhas or n.responsavel_id = eu)
       and crm.ve_negocio(n.responsavel_id)
     order by n.entrou_etapa_em;
end $$;

create or replace function public.painel_resumo()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  r jsonb;
  clin boolean;
  papel text;
  escopo text;
  eu uuid := auth.uid();
  carteira uuid[];
begin
  perform crm.exige_ativo();
  clin := crm.pode_clinico();
  papel := crm.papel_atual()::text;
  escopo := case when papel in ('admin', 'financeiro') then 'empresa'
                 when papel = 'comercial' then 'meus'
                 else 'nenhum' end;

  if escopo = 'meus' then
    carteira := array(
      select n.empresa_id from crm.negocio n where n.responsavel_id = eu and n.empresa_id is not null
      union select c.empresa_id from crm.contrato c where c.responsavel_id = eu and c.empresa_id is not null
      union select e.id from public.empresa e where e.cadastrado_por = eu);
  end if;

  select jsonb_build_object(
    'escopo',                escopo,
    'clientes_total',        (select count(*) from public.empresa e where escopo <> 'meus' or e.id = any (carteira)),
    'clientes_ativos',       (select count(*) from public.empresa e where e.situacao = 'ativo' and (escopo <> 'meus' or e.id = any (carteira))),
    'clientes_sem_contrato', (select count(*) from public.empresa e where e.situacao = 'sem_contrato' and (escopo <> 'meus' or e.id = any (carteira))),
    'clientes_inativos',     (select count(*) from public.empresa e where e.situacao = 'inativo' and (escopo <> 'meus' or e.id = any (carteira))),
    'clientes_a_confirmar',  (select count(*) from public.empresa e where e.situacao is null and (escopo <> 'meus' or e.id = any (carteira))),
    'unidades',              (select count(*) from public.unidade u where escopo <> 'meus' or u.empresa_id = any (carteira)),
    'colaboradores_ativos',  (select count(*) from public.colaborador c where c.situacao = 'ativo' and (escopo <> 'meus' or c.empresa_id = any (carteira))),
    'negocios_abertos',      case when escopo <> 'nenhum' then
                               (select count(*) from crm.negocio n join crm.etapa e on e.id = n.etapa_id
                                 where e.tipo = 'aberta' and (escopo = 'empresa' or n.responsavel_id = eu)) end,
    'valor_aberto_comercial',case when escopo <> 'nenhum' then
                               (select coalesce(sum(n.valor), 0) from crm.negocio n
                                  join crm.etapa e on e.id = n.etapa_id join crm.funil f on f.id = n.funil_id
                                 where e.tipo = 'aberta' and f.slug = 'comercial' and (escopo = 'empresa' or n.responsavel_id = eu)) end,
    'ganhos_mes',            case when escopo <> 'nenhum' then
                               (select count(*) from crm.negocio n join crm.etapa e on e.id = n.etapa_id
                                  join crm.funil f on f.id = n.funil_id
                                 where e.tipo = 'ganho' and f.slug = 'comercial' and n.fechado_em >= date_trunc('month', now())
                                   and (escopo = 'empresa' or n.responsavel_id = eu)) end,
    'valor_ganho_mes',       case when escopo <> 'nenhum' then
                               (select coalesce(sum(n.valor), 0) from crm.negocio n join crm.etapa e on e.id = n.etapa_id
                                  join crm.funil f on f.id = n.funil_id
                                 where e.tipo = 'ganho' and f.slug = 'comercial' and n.fechado_em >= date_trunc('month', now())
                                   and (escopo = 'empresa' or n.responsavel_id = eu)) end,
    'parados',               case when escopo <> 'nenhum' then
                               (select count(*) from crm.negocio n join crm.etapa e on e.id = n.etapa_id
                                 where e.tipo = 'aberta' and e.alerta_dias is not null
                                   and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)
                                   and (escopo = 'empresa' or n.responsavel_id = eu)) end,
    'acesso_clinico',        clin,
    'exames_vencidos',       case when clin then (select count(*) from app.vw_aso_vencimento where status = 'vencido') end,
    'exames_30_dias',        case when clin then (select count(*) from app.vw_aso_vencimento where status = 'vence_em_30_dias') end,
    'exames_60_dias',        case when clin then (select count(*) from app.vw_aso_vencimento where status = 'vence_em_60_dias') end,
    'atendimentos_mes',      case when clin then (select count(*) from public.atendimento
                                                   where data_atendimento >= date_trunc('month', now())) end
  ) into r;

  r := r || jsonb_build_object('funil_comercial', case when escopo = 'nenhum' then '[]'::jsonb else coalesce((
    select jsonb_agg(jsonb_build_object('etapa', e.nome, 'cor', e.cor, 'qtd', coalesce(c.qtd, 0), 'valor', coalesce(c.valor, 0)) order by e.ordem)
      from crm.etapa e join crm.funil f on f.id = e.funil_id and f.slug = 'comercial'
      left join (select n.etapa_id, count(*) qtd, sum(n.valor) valor from crm.negocio n
                  where escopo = 'empresa' or n.responsavel_id = eu group by 1) c on c.etapa_id = e.id
     where e.ativo and e.tipo = 'aberta'), '[]'::jsonb) end);
  return r;
end $$;

create or replace function public.painel_crm_negocio(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r jsonb; vv boolean;
begin
  perform crm.exige_ativo();
  vv := crm.ve_valores();
  select jsonb_build_object(
           'id', n.id, 'numero', n.numero, 'funil_id', n.funil_id, 'etapa_id', n.etapa_id,
           'titulo', n.titulo, 'empresa_id', n.empresa_id,
           'empresa', case when em.id is null then null else jsonb_build_object(
               'id', em.id, 'razao_social', em.razao_social, 'nome_fantasia', em.nome_fantasia,
               'cnpj', em.cnpj, 'cidade', em.cidade, 'uf', em.uf, 'telefone', em.telefone, 'email', em.email) end,
           'cliente_nome', n.cliente_nome, 'cliente_cnpj', n.cliente_cnpj,
           'contato_nome', n.contato_nome, 'contato_telefone', n.contato_telefone, 'contato_email', n.contato_email,
           'responsavel_id', n.responsavel_id, 'responsavel_nome', p.nome,
           'valor', case when vv then n.valor end, 've_valores', vv,
           'origem', n.origem, 'previsao_fechamento', n.previsao_fechamento,
           'motivo_perda', n.motivo_perda, 'observacao', n.observacao,
           'qtd_funcionarios', n.qtd_funcionarios, 'forma_pagamento', n.forma_pagamento, 'parcelas', n.parcelas,
           'entrou_etapa_em', n.entrou_etapa_em, 'fechado_em', n.fechado_em, 'criado_em', n.criado_em,
           'pode_operar', crm.pode_operar(n.funil_id),
           'negocio_origem', (select jsonb_build_object('id', o.id, 'numero', o.numero, 'funil', fo.nome,
                                       'observacao', o.observacao, 'qtd_funcionarios', o.qtd_funcionarios,
                                       'forma_pagamento', o.forma_pagamento, 'parcelas', o.parcelas,
                                       'responsavel_nome', po.nome, 'atualizado_em', o.atualizado_em)
                                from crm.negocio o join crm.funil fo on fo.id = o.funil_id
                                left join crm.perfil po on po.user_id = o.responsavel_id
                               where o.id = n.negocio_origem_id),
           'derivados', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'numero', d.numero,
                                          'funil', fd.nome, 'etapa', ed.nome))
                                    from crm.negocio d join crm.funil fd on fd.id = d.funil_id
                                    join crm.etapa ed on ed.id = d.etapa_id
                                   where d.negocio_origem_id = n.id), '[]'::jsonb),
           'itens', coalesce((select jsonb_agg(jsonb_build_object(
                          'id', i.id, 'produto_id', i.produto_id, 'descricao', i.descricao,
                          'quantidade', i.quantidade,
                          'preco_unitario', case when vv then i.preco_unitario end,
                          'total', case when vv then i.total end)
                        order by i.criado_em)
                        from crm.negocio_item i where i.negocio_id = n.id), '[]'::jsonb),
           'eventos', coalesce((select jsonb_agg(x order by x.criado_em desc) from (
                          select ev.id, ev.tipo, ev.texto, ev.criado_em, a.nome as autor,
                                 de.nome as de_etapa, pa.nome as para_etapa
                            from crm.evento ev
                            left join crm.perfil a on a.user_id = ev.autor_id
                            left join crm.etapa de on de.id = ev.de_etapa_id
                            left join crm.etapa pa on pa.id = ev.para_etapa_id
                           where ev.negocio_id = n.id
                           order by ev.criado_em desc limit 200) x), '[]'::jsonb))
    into r
    from crm.negocio n
    left join public.empresa em on em.id = n.empresa_id
    left join crm.perfil p on p.user_id = n.responsavel_id
   where n.id = p_id and crm.ve_negocio(n.responsavel_id);
  if r is null then
    raise exception 'Negócio não encontrado.';
  end if;
  return r;
end $$;

create or replace function public.painel_relatorio_vendas(p_de date default null, p_ate date default null, p_responsavel uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  de date := coalesce(p_de, ((now() at time zone 'America/Sao_Paulo')::date - interval '1 year')::date);
  ate date := coalesce(p_ate, (now() at time zone 'America/Sao_Paulo')::date);
  papel text;
  resp uuid := p_responsavel;
begin
  perform crm.exige('financeiro','comercial');
  papel := crm.papel_atual()::text;
  if papel = 'comercial' then resp := auth.uid(); end if;

  return (
    with g as (
      select n.id, n.valor, n.fechado_em, n.responsavel_id, n.bitrix_responsavel, n.empresa_id, n.cliente_nome
        from crm.negocio n
        join crm.funil f on f.id = n.funil_id and f.slug = 'comercial'
        join crm.etapa e on e.id = n.etapa_id and e.tipo = 'ganho'
       where n.fechado_em >= de::timestamp at time zone 'America/Sao_Paulo'
         and n.fechado_em < (ate + 1)::timestamp at time zone 'America/Sao_Paulo'
         and (resp is null or n.responsavel_id = resp)
    ), it as (
      select g.id negocio_id, coalesce(p.nome, btrim(i.descricao)) produto, i.quantidade, i.preco_unitario, i.total
        from g join crm.negocio_item i on i.negocio_id = g.id
        left join crm.produto p on p.id = i.produto_id
    )
    select jsonb_build_object(
      'de', de, 'ate', ate,
      'negocios', (select count(*) from g),
      'valor_negocios', (select coalesce(sum(valor), 0) from g),
      'valor_itens', (select coalesce(sum(total), 0) from it),
      'clientes', (select count(distinct coalesce(empresa_id::text, cliente_nome)) from g),
      'sem_itens', (select count(*) from g where not exists (select 1 from crm.negocio_item i where i.negocio_id = g.id)),
      'produtos', coalesce((
        select jsonb_agg(x order by x.valor desc) from (
          select it.produto, count(distinct it.negocio_id) negocios, sum(it.quantidade) quantidade, sum(it.total) valor,
                 round(sum(it.total) / nullif(sum(it.quantidade), 0), 2) preco_medio,
                 min(it.preco_unitario) preco_min, max(it.preco_unitario) preco_max
            from it group by it.produto) x), '[]'::jsonb),
      'meses', coalesce((
        select jsonb_agg(x order by x.mes) from (
          select to_char(date_trunc('month', g.fechado_em at time zone 'America/Sao_Paulo'), 'YYYY-MM') mes,
                 count(*) negocios, sum(g.valor) valor
            from g group by 1) x), '[]'::jsonb),
      'responsaveis', coalesce((
        select jsonb_agg(x order by x.valor desc) from (
          select coalesce(p.nome, bu.nome, 'Sem responsável') nome, count(*) negocios, sum(g.valor) valor
            from g left join crm.perfil p on p.user_id = g.responsavel_id
                   left join crm.bitrix_usuario bu on bu.bitrix_id = g.bitrix_responsavel
           group by 1) x), '[]'::jsonb)
    ));
end $$;

do $$ begin
  execute replace(pg_get_functiondef('public.painel_cliente(uuid)'::regprocedure),
    $x$'valor', n.valor, 'criado_em', n.criado_em)$x$,
    $x$'valor', case when crm.ve_valores() then n.valor end, 'criado_em', n.criado_em)$x$);
end $$;
