

update crm.agenda_grade set vagas = 0, atualizado_em = now() where true;
insert into crm.agenda_grade (horario, vagas) values
  ('08:30', 4), ('08:50', 3), ('09:00', 4), ('09:20', 4), ('09:40', 4), ('09:50', 4),
  ('10:00', 4), ('10:20', 3), ('10:30', 4), ('10:50', 4), ('11:10', 3), ('11:30', 4)
on conflict (horario) do update set vagas = excluded.vagas, atualizado_em = now();
update crm.agenda_regra set vagas_padrao = 40, hora_inicio_padrao = '08:30', hora_fim_padrao = '11:30', atualizado_em = now() where id;

do $$ begin
  execute replace(pg_get_functiondef('public.painel_agenda_grade_salvar(jsonb)'::regprocedure),
    $x$update crm.agenda_regra set vagas_padrao = greatest(total, 1), atualizado_em = now(), atualizado_por = eu where id;$x$,
    $x$
  execute replace(pg_get_functiondef('crm.agenda_clinica_do_dia(date)'::regprocedure),
    $x$greatest(total, 1), 'Aberta automaticamente$x$,
    $x$coalesce((select rg.vagas_padrao from crm.agenda_regra rg where rg.id), 40), 'Aberta automaticamente$x$);
end $$;

alter table crm.negocio_item
  add column if not exists preco_catalogo numeric(12,2),
  add column if not exists desconto_pct numeric(5,2) not null default 0 check (desconto_pct between 0 and 100);
alter table crm.negocio_item
  add column if not exists total_liquido numeric generated always as
    (round(quantidade * preco_unitario * (1 - desconto_pct / 100), 2)) stored;
alter table crm.negocio
  add column if not exists desconto_pct numeric(5,2) not null default 0 check (desconto_pct between 0 and 100);

create or replace function crm.recalcular_valor(p_negocio uuid)
returns void language sql security definer set search_path = '' as $$
  update crm.negocio n
     set valor = round(coalesce((select sum(i.total_liquido) from crm.negocio_item i where i.negocio_id = n.id), 0)
                       * (1 - coalesce(n.desconto_pct, 0) / 100), 2),
         atualizado_em = now()
   where n.id = p_negocio
     and exists (select 1 from crm.negocio_item i where i.negocio_id = n.id)
$$;

do $$ begin
  execute replace(pg_get_functiondef('public.painel_crm_item_adicionar(uuid,uuid,text,numeric,numeric)'::regprocedure),
    $x$insert into crm.negocio_item (negocio_id, produto_id, descricao, quantidade, preco_unitario)
  values (p_negocio, p_produto, v_desc, p_quantidade, greatest(v_preco, 0))$x$,
    $x$insert into crm.negocio_item (negocio_id, produto_id, descricao, quantidade, preco_unitario, preco_catalogo)
  values (p_negocio, p_produto, v_desc, p_quantidade, greatest(v_preco, 0), pr.preco)$x$);
end $$;

create or replace function public.painel_crm_item_salvar(p_item uuid, p_dados jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare i crm.negocio_item; v_funil uuid; d jsonb := coalesce(p_dados, '{}'::jsonb);
  v_qtd numeric; v_preco numeric; v_desc numeric;
begin
  select * into i from crm.negocio_item where id = p_item;
  if i.id is null then raise exception 'Item não encontrado.'; end if;
  select funil_id into v_funil from crm.negocio where id = i.negocio_id;
  perform crm.exige_operar(v_funil);
  if not crm.ve_valores_funil(v_funil) then raise exception 'Sem permissão para alterar valores.'; end if;
  v_qtd := coalesce(nullif(d ->> 'quantidade', '')::numeric, i.quantidade);
  v_preco := coalesce(nullif(d ->> 'preco', '')::numeric, i.preco_unitario);
  v_desc := coalesce(nullif(d ->> 'desconto', '')::numeric, i.desconto_pct);
  if v_qtd <= 0 then raise exception 'Quantidade precisa ser maior que zero.'; end if;
  if v_preco < 0 then raise exception 'Preço inválido.'; end if;
  if v_desc < 0 or v_desc > 100 then raise exception 'Desconto deve ficar entre 0 e 100%%.'; end if;
  update crm.negocio_item set quantidade = v_qtd, preco_unitario = v_preco, desconto_pct = v_desc where id = p_item;
  perform crm.recalcular_valor(i.negocio_id);
  perform crm.registrar(i.negocio_id, 'item', format('Item alterado: %s (qtd %s, R$ %s, desconto %s%%)', i.descricao,
    v_qtd, replace(to_char(v_preco, 'FM9999990.00'), '.', ','), v_desc));
end $$;
revoke execute on function public.painel_crm_item_salvar(uuid, jsonb) from public, anon;
grant execute on function public.painel_crm_item_salvar(uuid, jsonb) to authenticated;

create or replace function public.painel_crm_item_adicionar_v2(p_negocio uuid, p_produto uuid, p_descricao text,
  p_quantidade numeric, p_preco numeric, p_desconto numeric default 0)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  v_id := public.painel_crm_item_adicionar(p_negocio, p_produto, p_descricao, p_quantidade, p_preco);
  if coalesce(p_desconto, 0) <> 0 then
    if p_desconto < 0 or p_desconto > 100 then raise exception 'Desconto deve ficar entre 0 e 100%%.'; end if;
    update crm.negocio_item set desconto_pct = p_desconto where id = v_id;
    perform crm.recalcular_valor(p_negocio);
  end if;
  return v_id;
end $$;
revoke execute on function public.painel_crm_item_adicionar_v2(uuid, uuid, text, numeric, numeric, numeric) from public, anon;
grant execute on function public.painel_crm_item_adicionar_v2(uuid, uuid, text, numeric, numeric, numeric) to authenticated;

create or replace function public.painel_crm_negocio_desconto(p_negocio uuid, p_pct numeric)
returns void language plpgsql security definer set search_path = '' as $$
declare v_funil uuid; v_pct numeric := coalesce(p_pct, 0);
begin
  select funil_id into v_funil from crm.negocio where id = p_negocio;
  if v_funil is null then raise exception 'Negócio não encontrado.'; end if;
  perform crm.exige_operar(v_funil);
  if not crm.ve_valores_funil(v_funil) then raise exception 'Sem permissão para alterar valores.'; end if;
  if v_pct < 0 or v_pct > 100 then raise exception 'Desconto deve ficar entre 0 e 100%%.'; end if;
  update crm.negocio set desconto_pct = v_pct where id = p_negocio;
  perform crm.recalcular_valor(p_negocio);
  perform crm.registrar(p_negocio, 'item', format('Desconto geral: %s%%', v_pct));
end $$;
revoke execute on function public.painel_crm_negocio_desconto(uuid, numeric) from public, anon;
grant execute on function public.painel_crm_negocio_desconto(uuid, numeric) to authenticated;

do $$ declare f text := pg_get_functiondef('public.painel_crm_negocio_criar_v2(jsonb,jsonb)'::regprocedure);
  velho text := $x$      if v_prod.preco is not null and v_preco < v_prod.preco then
        raise exception '% abaixo do valor mínimo do catálogo (R$ %).', v_prod.nome, replace(to_char(v_prod.preco, 'FM9999990.00'), '.', ',');
      end if;
      perform public.painel_crm_item_adicionar(v_id, v_prod.id, null, v_qtd, v_preco);
    end loop;$x$;
begin
  if strpos(f, velho) = 0 then raise exception '0081: trecho de painel_crm_negocio_criar_v2 não encontrado'; end if;
  execute replace(f, velho, $x$
      perform public.painel_crm_item_adicionar_v2(v_id, v_prod.id, null, v_qtd, v_preco,
                                                  coalesce(nullif(it ->> 'desconto', '')::numeric, 0));
    end loop;
    if coalesce(nullif(d ->> 'desconto_pct', '')::numeric, 0) > 0 then
      perform public.painel_crm_negocio_desconto(v_id, (d ->> 'desconto_pct')::numeric);
    end if;$x$);
end $$;

create or replace function crm.vendedor_id(p_negocio uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  with recursive c as (
    select n.id, n.negocio_origem_id, n.responsavel_id, 0 as nivel from crm.negocio n where n.id = p_negocio
    union all
    select o.id, o.negocio_origem_id, o.responsavel_id, c.nivel + 1
      from crm.negocio o join c on o.id = c.negocio_origem_id where c.nivel < 10)
  select c.responsavel_id from c order by c.nivel desc limit 1
$$;
revoke execute on function crm.vendedor_id(uuid) from public, anon;

create or replace function crm.ve_valores_funil(p_funil uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select crm.ve_valores()
     and (crm.papel_atual()::text = 'admin'
          or not exists (select 1 from crm.funil f where f.id = p_funil and f.slug in ('vistoria', 'laudos')))
$$;
revoke execute on function crm.ve_valores_funil(uuid) from public, anon;

create or replace function public.painel_crm_quadro_v3(p_funil uuid, p_responsavel uuid default null, p_busca text default null,
  p_dias_fechados integer default 30, p_de date default null, p_ate date default null)
returns table (id uuid, numero bigint, etapa_id uuid, titulo text, cliente text, empresa_id uuid, responsavel_id uuid,
               responsavel_nome text, valor numeric, origem text, entrou_etapa_em timestamptz, dias_na_etapa integer,
               atrasado boolean, qtd_itens integer, previsao_fechamento date, criado_em timestamptz, vendedor_nome text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); vv boolean; periodo boolean := p_de is not null or p_ate is not null;
begin
  perform crm.exige_ativo();
  vv := crm.ve_valores_funil(p_funil);
  return query
    select n.id, n.numero, n.etapa_id, n.titulo,
           coalesce(nullif(em.nome_fantasia, ''), em.razao_social, n.cliente_nome)::text,
           n.empresa_id, n.responsavel_id, p.nome, case when vv then n.valor end, n.origem, n.entrou_etapa_em,
           floor(extract(epoch from now() - n.entrou_etapa_em) / 86400)::int,
           (e.tipo = 'aberta' and e.alerta_dias is not null
             and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)),
           (select count(*)::int from crm.negocio_item i where i.negocio_id = n.id),
           n.previsao_fechamento, n.criado_em,
           case when n.negocio_origem_id is not null
                then (select pv.nome from crm.perfil pv where pv.user_id = crm.vendedor_id(n.id)) end::text
      from crm.negocio n
      join crm.etapa e on e.id = n.etapa_id
      left join public.empresa em on em.id = n.empresa_id
      left join crm.perfil p on p.user_id = n.responsavel_id
     where n.funil_id = p_funil
       and crm.ve_negocio(n.responsavel_id)
       and (p_responsavel is null or n.responsavel_id = p_responsavel)
       and (case when periodo then
                 (p_de is null or n.criado_em >= p_de::timestamp at time zone 'America/Sao_Paulo')
             and (p_ate is null or n.criado_em < (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo')
            else (e.tipo = 'aberta' or n.fechado_em >= now() - make_interval(days => greatest(p_dias_fechados, 0))) end)
       and (termo is null
            or n.titulo ilike '%' || termo || '%'
            or n.cliente_nome ilike '%' || termo || '%'
            or em.razao_social ilike '%' || termo || '%'
            or em.nome_fantasia ilike '%' || termo || '%'
            or n.contato_nome ilike '%' || termo || '%'
            or n.numero::text = termo)
     order by n.entrou_etapa_em;
end $$;
revoke execute on function public.painel_crm_quadro_v3(uuid, uuid, text, integer, date, date) from public, anon;
grant execute on function public.painel_crm_quadro_v3(uuid, uuid, text, integer, date, date) to authenticated;

do $$ declare f text := pg_get_functiondef('public.painel_crm_negocio(uuid)'::regprocedure); begin
  f := replace(f, $x$vv := crm.ve_valores();$x$,
                  $x$vv := crm.ve_valores_funil((select n0.funil_id from crm.negocio n0 where n0.id = p_id));$x$);
  f := replace(f, $x$'responsavel_id', n.responsavel_id, 'responsavel_nome', p.nome,$x$,
                  $x$'responsavel_id', n.responsavel_id, 'responsavel_nome', p.nome,
           'vendedor_nome', (select pv.nome from crm.perfil pv where pv.user_id = crm.vendedor_id(n.id)),
           'desconto_pct', case when vv then n.desconto_pct end,$x$);
  f := replace(f, $x$'total', case when vv then i.total end)$x$,
                  $x$'total', case when vv then i.total_liquido end, 'total_bruto', case when vv then i.total end,
                          'preco_catalogo', case when vv then i.preco_catalogo end,
                          'desconto_pct', case when vv then i.desconto_pct end)$x$);
  if strpos(f, 'vendedor_nome') = 0 or strpos(f, 'total_liquido') = 0 or strpos(f, 've_valores_funil') = 0 then
    raise exception '0081: painel_crm_negocio não bateu';
  end if;
  execute f;
end $$;

create or replace function public.painel_relatorio_descontos(p_de date default null, p_ate date default null)
returns table (negocio_id uuid, numero bigint, data date, cliente text, vendedor text, etapa text, servico text,
               quantidade numeric, preco_catalogo numeric, preco_praticado numeric, desconto_item numeric,
               desconto_geral numeric, total_catalogo numeric, total_final numeric, diferenca numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform crm.exige('admin', 'financeiro');
  return query
    select n.id, n.numero, (n.criado_em at time zone 'America/Sao_Paulo')::date,
           coalesce(nullif(em.nome_fantasia, ''), em.razao_social, n.cliente_nome)::text,
           pv.nome::text, e.nome::text, i.descricao, i.quantidade, i.preco_catalogo, i.preco_unitario,
           i.desconto_pct, n.desconto_pct,
           round(i.quantidade * i.preco_catalogo, 2),
           round(i.total_liquido * (1 - n.desconto_pct / 100), 2),
           round(i.quantidade * i.preco_catalogo - i.total_liquido * (1 - n.desconto_pct / 100), 2)
      from crm.negocio_item i
      join crm.negocio n on n.id = i.negocio_id
      join crm.funil f on f.id = n.funil_id and f.slug = 'comercial'
      join crm.etapa e on e.id = n.etapa_id
      left join public.empresa em on em.id = n.empresa_id
      left join crm.perfil pv on pv.user_id = n.responsavel_id
     where i.preco_catalogo is not null
       and i.total_liquido * (1 - n.desconto_pct / 100) < i.quantidade * i.preco_catalogo - 0.005
       and (p_de is null or n.criado_em >= p_de::timestamp at time zone 'America/Sao_Paulo')
       and (p_ate is null or n.criado_em < (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo')
     order by n.criado_em desc, n.numero;
end $$;
revoke execute on function public.painel_relatorio_descontos(date, date) from public, anon;
grant execute on function public.painel_relatorio_descontos(date, date) to authenticated;

notify pgrst, 'reload schema';
