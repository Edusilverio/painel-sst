

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
  escopo := case when papel in ('admin', 'gestor', 'financeiro') then 'empresa'
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
