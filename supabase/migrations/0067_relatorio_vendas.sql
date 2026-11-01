

create or replace function public.painel_relatorio_vendas(p_de date default null, p_ate date default null, p_responsavel uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  de date := coalesce(p_de, ((now() at time zone 'America/Sao_Paulo')::date - interval '1 year')::date);
  ate date := coalesce(p_ate, (now() at time zone 'America/Sao_Paulo')::date);
  papel text;
  resp uuid := p_responsavel;
begin
  perform crm.exige('gestor','comercial');
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

revoke execute on function public.painel_relatorio_vendas(date, date, uuid) from public, anon;
grant execute on function public.painel_relatorio_vendas(date, date, uuid) to authenticated;
