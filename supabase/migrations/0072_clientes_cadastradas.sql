

create or replace function public.painel_clientes(p_busca text default null, p_situacao text default null, p_limite integer default 50, p_offset integer default 0)
returns table(id uuid, nome text, razao_social text, cnpj text, situacao text, cidade text, uf text, telefone text, email text,
              unidades integer, colaboradores integer, negocios_abertos integer, total bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); dig text; so_minhas boolean;
begin
  perform crm.exige_ativo();
  so_minhas := crm.papel_atual() = 'comercial';
  dig := nullif(regexp_replace(coalesce(termo, ''), '\D', '', 'g'), '');
  return query
    with minhas as (
      select n.empresa_id from crm.negocio n where so_minhas and n.responsavel_id = auth.uid() and n.empresa_id is not null
      union
      select c.empresa_id from crm.contrato c where so_minhas and c.responsavel_id = auth.uid() and c.empresa_id is not null
      union
      select e.id from public.empresa e where so_minhas and e.cadastrado_por = auth.uid()
    ), base as (
      select e.*
        from public.empresa e
       where (not so_minhas or e.id in (select m.empresa_id from minhas m))
         and (termo is null
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
