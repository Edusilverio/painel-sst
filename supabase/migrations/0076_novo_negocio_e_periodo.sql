

create or replace function public.painel_crm_quadro_v2(p_funil uuid, p_responsavel uuid default null, p_busca text default null,
                                                       p_dias_fechados integer default 30, p_de date default null, p_ate date default null)
returns table(id uuid, numero bigint, etapa_id uuid, titulo text, cliente text, empresa_id uuid, responsavel_id uuid, responsavel_nome text,
              valor numeric, origem text, entrou_etapa_em timestamptz, dias_na_etapa integer, atrasado boolean, qtd_itens integer,
              previsao_fechamento date, criado_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); vv boolean; periodo boolean := p_de is not null or p_ate is not null;
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
revoke execute on function public.painel_crm_quadro_v2(uuid, uuid, text, integer, date, date) from public, anon;
grant execute on function public.painel_crm_quadro_v2(uuid, uuid, text, integer, date, date) to authenticated;

create or replace function public.painel_crm_negocio_criar_v2(p_dados jsonb, p_itens jsonb default '[]'::jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  d jsonb := coalesce(p_dados, '{}'::jsonb);
  v_emp public.empresa;
  v_id uuid;
  v_parc int := nullif(d ->> 'parcelas', '')::int;
  v_fp text := nullif(trim(d ->> 'forma_pagamento'), '');
  it jsonb;
  v_prod crm.produto;
  v_qtd numeric;
  v_preco numeric;
  tem_itens boolean := jsonb_typeof(p_itens) = 'array' and jsonb_array_length(p_itens) > 0;
begin
  select * into v_emp from public.empresa e where e.id = nullif(d ->> 'empresa_id', '')::uuid;
  if v_emp.id is null then
    raise exception 'Escolha a empresa (razão social e CNPJ). Se ela não existir, cadastre em "Cadastrar empresa nova".';
  end if;
  if nullif(trim(v_emp.razao_social), '') is null or app.digits(v_emp.cnpj) is null then
    raise exception 'A empresa % está sem razão social ou CNPJ. Complete o cadastro dela antes de criar o negócio.',
      coalesce(v_emp.nome_fantasia, v_emp.razao_social);
  end if;
  if v_parc is not null and v_parc not between 1 and 60 then raise exception 'Parcelas: de 1 a 60.'; end if;
  if v_fp is not null and v_fp not in ('boleto', 'pix', 'transferencia', 'cartao') then raise exception 'Forma de pagamento inválida.'; end if;

  v_id := public.painel_crm_negocio_criar(
    (d ->> 'funil')::uuid,
    coalesce(nullif(trim(d ->> 'titulo'), ''), coalesce(nullif(v_emp.nome_fantasia, ''), v_emp.razao_social)),
    v_emp.id, null, null,
    d ->> 'contato_nome', d ->> 'contato_telefone', d ->> 'contato_email',
    nullif(d ->> 'responsavel', '')::uuid,
    case when tem_itens then 0 else coalesce(nullif(d ->> 'valor', '')::numeric, 0) end,
    coalesce(nullif(d ->> 'origem', ''), 'manual'),
    d ->> 'observacao',
    nullif(d ->> 'previsao', '')::date);

  update crm.negocio set parcelas = v_parc, forma_pagamento = v_fp where id = v_id;

  if tem_itens then
    for it in select * from jsonb_array_elements(p_itens) loop
      select * into v_prod from crm.produto pr where pr.id = nullif(it ->> 'produto', '')::uuid and pr.ativo;
      if v_prod.id is null then raise exception 'Serviço do catálogo não encontrado ou inativo.'; end if;
      v_qtd := coalesce(nullif(it ->> 'quantidade', '')::numeric, 1);
      v_preco := coalesce(nullif(it ->> 'preco', '')::numeric, v_prod.preco);
      if v_qtd <= 0 then raise exception 'Quantidade inválida em %.', v_prod.nome; end if;
      if v_preco is null then raise exception 'Informe o preço de % (o catálogo não tem valor).', v_prod.nome; end if;
      if v_prod.preco is not null and v_preco < v_prod.preco then
        raise exception '% abaixo do valor mínimo do catálogo (R$ %).', v_prod.nome, replace(to_char(v_prod.preco, 'FM9999990.00'), '.', ',');
      end if;
      perform public.painel_crm_item_adicionar(v_id, v_prod.id, null, v_qtd, v_preco);
    end loop;
  end if;
  return v_id;
end $$;
revoke execute on function public.painel_crm_negocio_criar_v2(jsonb, jsonb) from public, anon;
grant execute on function public.painel_crm_negocio_criar_v2(jsonb, jsonb) to authenticated;
