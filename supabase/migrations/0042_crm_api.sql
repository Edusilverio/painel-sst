

create or replace function crm.pode_operar(p_funil uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select v.papel in ('admin','gestor') or v.papel = any (f.papeis)
       from crm.perfil v, crm.funil f
      where v.user_id = auth.uid() and v.ativo and f.id = p_funil),
    false)
$$;

create or replace function crm.exige_operar(p_funil uuid) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare eu uuid;
begin
  eu := crm.exige_ativo();
  if not crm.pode_operar(p_funil) then
    raise exception 'Seu perfil pode ver, mas não pode alterar este funil' using errcode = '42501';
  end if;
  return eu;
end $$;

create or replace function crm.registrar(p_negocio uuid, p_tipo text, p_texto text,
                                         p_de uuid default null, p_para uuid default null)
returns void language sql security definer set search_path = '' as $$
  insert into crm.evento (negocio_id, tipo, texto, de_etapa_id, para_etapa_id, autor_id)
  values (p_negocio, p_tipo, p_texto, p_de, p_para, auth.uid())
$$;

create or replace function crm.recalcular_valor(p_negocio uuid) returns void
language sql security definer set search_path = '' as $$
  update crm.negocio n
     set valor = coalesce((select sum(i.total) from crm.negocio_item i where i.negocio_id = n.id), 0),
         atualizado_em = now()
   where n.id = p_negocio
     and exists (select 1 from crm.negocio_item i where i.negocio_id = n.id)
$$;

create or replace function crm.proximo_rodizio(p_funil uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare ultimo uuid; ordem_ultimo int; prox uuid;
begin
  insert into crm.rodizio_estado (funil_id) values (p_funil) on conflict do nothing;
  select ultimo_user_id into ultimo from crm.rodizio_estado where funil_id = p_funil for update;
  select r.ordem into ordem_ultimo from crm.rodizio r where r.funil_id = p_funil and r.user_id = ultimo;

  select r.user_id into prox
    from crm.rodizio r join crm.perfil p on p.user_id = r.user_id and p.ativo
   where r.funil_id = p_funil and r.ativo and r.ordem > coalesce(ordem_ultimo, -1)
   order by r.ordem limit 1;
  if prox is null then
    select r.user_id into prox
      from crm.rodizio r join crm.perfil p on p.user_id = r.user_id and p.ativo
     where r.funil_id = p_funil and r.ativo
     order by r.ordem limit 1;
  end if;

  if prox is not null then
    update crm.rodizio_estado set ultimo_user_id = prox, atualizado_em = now() where funil_id = p_funil;
  end if;
  return prox;
end $$;

create or replace function crm.notificar(p_user uuid, p_negocio uuid, p_tipo text, p_texto text)
returns void language sql security definer set search_path = '' as $$
  insert into crm.notificacao (user_id, negocio_id, tipo, texto)
  select p_user, p_negocio, p_tipo, p_texto
   where p_user is not null and p_user is distinct from auth.uid()
$$;

revoke execute on function crm.pode_operar(uuid), crm.exige_operar(uuid),
  crm.registrar(uuid, text, text, uuid, uuid), crm.recalcular_valor(uuid),
  crm.proximo_rodizio(uuid), crm.notificar(uuid, uuid, text, text)
  from public, anon, authenticated;

create or replace function public.painel_crm_funis() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform crm.exige_ativo();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', f.id, 'slug', f.slug, 'nome', f.nome, 'descricao', f.descricao,
             'usa_rodizio', f.usa_rodizio, 'papeis', to_jsonb(f.papeis),
             'pode_operar', crm.pode_operar(f.id),
             'etapas', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'id', e.id, 'nome', e.nome, 'ordem', e.ordem, 'tipo', e.tipo,
                        'cor', e.cor, 'alerta_dias', e.alerta_dias, 'ativo', e.ativo)
                      order by e.ordem)
                 from crm.etapa e where e.funil_id = f.id), '[]'::jsonb))
           order by f.ordem)
      from crm.funil f where f.ativo), '[]'::jsonb);
end $$;

create or replace function public.painel_crm_quadro(
  p_funil uuid, p_responsavel uuid default null, p_busca text default null, p_dias_fechados int default 30
) returns table (
  id uuid, numero bigint, etapa_id uuid, titulo text, cliente text, empresa_id uuid,
  responsavel_id uuid, responsavel_nome text, valor numeric, origem text,
  entrou_etapa_em timestamptz, dias_na_etapa int, atrasado boolean, qtd_itens int,
  previsao_fechamento date, criado_em timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform crm.exige_ativo();
  return query
    select n.id, n.numero, n.etapa_id, n.titulo,
           coalesce(nullif(em.nome_fantasia, ''), em.razao_social, n.cliente_nome)::text,
           n.empresa_id, n.responsavel_id, p.nome, n.valor, n.origem, n.entrou_etapa_em,
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

create or replace function public.painel_crm_negocio(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform crm.exige_ativo();
  select jsonb_build_object(
           'id', n.id, 'numero', n.numero, 'funil_id', n.funil_id, 'etapa_id', n.etapa_id,
           'titulo', n.titulo, 'empresa_id', n.empresa_id,
           'empresa', case when em.id is null then null else jsonb_build_object(
               'id', em.id, 'razao_social', em.razao_social, 'nome_fantasia', em.nome_fantasia,
               'cnpj', em.cnpj, 'cidade', em.cidade, 'uf', em.uf, 'telefone', em.telefone, 'email', em.email) end,
           'cliente_nome', n.cliente_nome, 'cliente_cnpj', n.cliente_cnpj,
           'contato_nome', n.contato_nome, 'contato_telefone', n.contato_telefone, 'contato_email', n.contato_email,
           'responsavel_id', n.responsavel_id, 'responsavel_nome', p.nome,
           'valor', n.valor, 'origem', n.origem, 'previsao_fechamento', n.previsao_fechamento,
           'motivo_perda', n.motivo_perda, 'observacao', n.observacao,
           'entrou_etapa_em', n.entrou_etapa_em, 'fechado_em', n.fechado_em, 'criado_em', n.criado_em,
           'pode_operar', crm.pode_operar(n.funil_id),
           'negocio_origem', (select jsonb_build_object('id', o.id, 'numero', o.numero, 'funil', fo.nome)
                                from crm.negocio o join crm.funil fo on fo.id = o.funil_id
                               where o.id = n.negocio_origem_id),
           'derivados', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'numero', d.numero,
                                          'funil', fd.nome, 'etapa', ed.nome))
                                    from crm.negocio d join crm.funil fd on fd.id = d.funil_id
                                    join crm.etapa ed on ed.id = d.etapa_id
                                   where d.negocio_origem_id = n.id), '[]'::jsonb),
           'itens', coalesce((select jsonb_agg(jsonb_build_object(
                          'id', i.id, 'produto_id', i.produto_id, 'descricao', i.descricao,
                          'quantidade', i.quantidade, 'preco_unitario', i.preco_unitario, 'total', i.total)
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
   where n.id = p_id;
  if r is null then
    raise exception 'Negócio não encontrado.';
  end if;
  return r;
end $$;

create or replace function public.painel_crm_pendencias(p_so_minhas boolean default false)
returns table (id uuid, numero bigint, titulo text, cliente text, funil_id uuid, funil text,
               etapa text, responsavel_id uuid, responsavel_nome text, dias_na_etapa int,
               alerta_dias int, valor numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := crm.exige_ativo();
  return query
    select n.id, n.numero, n.titulo,
           coalesce(nullif(em.nome_fantasia, ''), em.razao_social, n.cliente_nome)::text,
           f.id, f.nome, e.nome, n.responsavel_id, p.nome,
           floor(extract(epoch from now() - n.entrou_etapa_em) / 86400)::int,
           e.alerta_dias, n.valor
      from crm.negocio n
      join crm.etapa e on e.id = n.etapa_id
      join crm.funil f on f.id = n.funil_id
      left join public.empresa em on em.id = n.empresa_id
      left join crm.perfil p on p.user_id = n.responsavel_id
     where e.tipo = 'aberta' and e.alerta_dias is not null
       and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)
       and (not p_so_minhas or n.responsavel_id = eu)
     order by n.entrou_etapa_em;
end $$;

create or replace function public.painel_crm_responsaveis()
returns table (user_id uuid, nome text, papel text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige_ativo();
  return query
    select p.user_id, p.nome, p.papel::text from crm.perfil p
     where p.ativo and p.papel <> 'leitura' order by p.nome;
end $$;

create or replace function public.painel_crm_produtos(p_todos boolean default false)
returns table (id uuid, nome text, descricao text, categoria text, preco numeric,
               unidade text, recorrente boolean, ativo boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige_ativo();
  return query
    select pr.id, pr.nome, pr.descricao, pr.categoria, pr.preco, pr.unidade, pr.recorrente, pr.ativo
      from crm.produto pr where p_todos or pr.ativo
     order by pr.categoria nulls last, pr.nome;
end $$;

create or replace function public.painel_empresas_buscar(p_busca text)
returns table (id uuid, nome text, razao_social text, cnpj text, cidade text, uf text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); dig text;
begin
  perform crm.exige_ativo();
  if termo is null or length(termo) < 2 then return; end if;
  dig := nullif(regexp_replace(termo, '\D', '', 'g'), '');
  return query
    select e.id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social)::text, e.razao_social::text, e.cnpj::text, e.cidade::text, e.uf::text
      from public.empresa e
     where e.razao_social ilike '%' || termo || '%'
        or e.nome_fantasia ilike '%' || termo || '%'
        or (dig is not null and length(dig) >= 4 and regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') like dig || '%')
     order by e.razao_social
     limit 20;
end $$;

create or replace function public.painel_crm_rodizio(p_funil uuid)
returns table (user_id uuid, nome text, ordem int, ativo boolean, proximo boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare ultimo uuid; ord_ult int; prox uuid;
begin
  perform crm.exige_ativo();
  select s.ultimo_user_id into ultimo from crm.rodizio_estado s where s.funil_id = p_funil;
  select r.ordem into ord_ult from crm.rodizio r where r.funil_id = p_funil and r.user_id = ultimo;
  select r.user_id into prox from crm.rodizio r join crm.perfil p on p.user_id = r.user_id and p.ativo
   where r.funil_id = p_funil and r.ativo and r.ordem > coalesce(ord_ult, -1) order by r.ordem limit 1;
  if prox is null then
    select r.user_id into prox from crm.rodizio r join crm.perfil p on p.user_id = r.user_id and p.ativo
     where r.funil_id = p_funil and r.ativo order by r.ordem limit 1;
  end if;
  return query
    select r.user_id, p.nome, r.ordem, r.ativo and p.ativo, coalesce(r.user_id = prox, false)
      from crm.rodizio r join crm.perfil p on p.user_id = r.user_id
     where r.funil_id = p_funil order by r.ordem;
end $$;

create or replace function public.painel_crm_negocio_criar(
  p_funil uuid,
  p_titulo text,
  p_empresa_id uuid default null,
  p_cliente_nome text default null,
  p_cliente_cnpj text default null,
  p_contato_nome text default null,
  p_contato_telefone text default null,
  p_contato_email text default null,
  p_responsavel uuid default null,
  p_valor numeric default 0,
  p_origem text default 'manual',
  p_observacao text default null,
  p_previsao date default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare eu uuid; v_etapa uuid; v_resp uuid := p_responsavel; v_id uuid; v_rodizio boolean;
begin
  eu := crm.exige_operar(p_funil);
  if nullif(trim(p_titulo), '') is null then
    raise exception 'Informe um título para o negócio.';
  end if;
  if p_empresa_id is null and nullif(trim(p_cliente_nome), '') is null then
    raise exception 'Escolha um cliente da base ou informe o nome do cliente.';
  end if;

  select e.id into v_etapa from crm.etapa e
   where e.funil_id = p_funil and e.ativo and e.tipo = 'aberta' order by e.ordem limit 1;
  if v_etapa is null then
    raise exception 'Este funil não tem etapa aberta configurada.';
  end if;

  select f.usa_rodizio into v_rodizio from crm.funil f where f.id = p_funil;
  if v_resp is null and v_rodizio then
    v_resp := crm.proximo_rodizio(p_funil);
  end if;

  insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, cliente_cnpj,
                           contato_nome, contato_telefone, contato_email, responsavel_id,
                           valor, origem, observacao, previsao_fechamento, criado_por)
  values (p_funil, v_etapa, trim(p_titulo), p_empresa_id, nullif(trim(p_cliente_nome), ''),
          nullif(trim(p_cliente_cnpj), ''), nullif(trim(p_contato_nome), ''),
          nullif(trim(p_contato_telefone), ''), nullif(trim(p_contato_email), ''), v_resp,
          greatest(coalesce(p_valor, 0), 0), coalesce(nullif(trim(p_origem), ''), 'manual'),
          nullif(trim(p_observacao), ''), p_previsao, eu)
  returning id into v_id;

  perform crm.registrar(v_id, 'criado',
    case when p_responsavel is null and v_resp is not null then 'Criado e distribuído pelo rodízio' else 'Negócio criado' end,
    null, v_etapa);
  perform crm.notificar(v_resp, v_id, 'atribuido', 'Novo negócio para você: ' || trim(p_titulo));
  return v_id;
end $$;

create or replace function public.painel_crm_negocio_mover(p_id uuid, p_etapa uuid, p_motivo text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  eu uuid; n crm.negocio; atual crm.etapa; alvo crm.etapa; f crm.funil;
  papel crm.papel; v_fat uuid; v_etapa_fat uuid; v_novo uuid; v_gerados int := 0;
begin
  select * into n from crm.negocio where id = p_id for update;
  if n.id is null then raise exception 'Negócio não encontrado.'; end if;
  eu := crm.exige_operar(n.funil_id);
  select * into atual from crm.etapa where id = n.etapa_id;
  select * into alvo from crm.etapa where id = p_etapa;
  if alvo.id is null or alvo.funil_id <> n.funil_id then
    raise exception 'Etapa inválida para este funil.';
  end if;
  if alvo.id = atual.id then
    return jsonb_build_object('ok', true, 'sem_mudanca', true);
  end if;
  if not alvo.ativo then
    raise exception 'A etapa "%" está desativada.', alvo.nome;
  end if;

  papel := crm.papel_atual();
  if atual.tipo <> 'aberta' and papel not in ('admin','gestor') then
    raise exception 'Negócio fechado (%). Só um gestor pode reabrir.', atual.nome using errcode = '42501';
  end if;
  if alvo.tipo = 'perdido' and nullif(trim(p_motivo), '') is null then
    raise exception 'Informe o motivo da perda.';
  end if;

  update crm.negocio
     set etapa_id = alvo.id,
         entrou_etapa_em = now(),
         ultimo_alerta_em = null,
         fechado_em = case when alvo.tipo = 'aberta' then null else now() end,
         motivo_perda = case when alvo.tipo = 'perdido' then trim(p_motivo)
                             when alvo.tipo = 'aberta' then null else motivo_perda end,
         atualizado_em = now()
   where id = n.id;

  perform crm.registrar(n.id, 'etapa',
    case when alvo.tipo = 'perdido' then 'Motivo: ' || trim(p_motivo) else nullif(trim(p_motivo), '') end,
    atual.id, alvo.id);

  if alvo.tipo = 'ganho' then
    for v_fat in
      select t.funil_destino_id from crm.tunel t join crm.funil d on d.id = t.funil_destino_id and d.ativo
       where t.funil_origem_id = n.funil_id
    loop
      continue when exists (select 1 from crm.negocio d where d.negocio_origem_id = n.id and d.funil_id = v_fat);
      select id into v_etapa_fat from crm.etapa where funil_id = v_fat and ativo and tipo = 'aberta' order by ordem limit 1;
      continue when v_etapa_fat is null;
      select * into f from crm.funil where id = v_fat;
      insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, cliente_cnpj,
                               contato_nome, contato_telefone, contato_email, responsavel_id,
                               valor, origem, negocio_origem_id, observacao, criado_por)
      values (v_fat, v_etapa_fat, n.titulo, n.empresa_id, n.cliente_nome, n.cliente_cnpj,
              n.contato_nome, n.contato_telefone, n.contato_email,
              case when f.slug = 'pos-venda' then n.responsavel_id end,
              n.valor, 'ganho_comercial', n.id, n.observacao, eu)
      returning id into v_novo;
      insert into crm.negocio_item (negocio_id, produto_id, descricao, quantidade, preco_unitario)
      select v_novo, i.produto_id, i.descricao, i.quantidade, i.preco_unitario
        from crm.negocio_item i where i.negocio_id = n.id;
      perform crm.registrar(v_novo, 'criado', 'Aberto automaticamente pelo fechamento do negócio #' || n.numero, null, v_etapa_fat);
      perform crm.registrar(n.id, 'nota', 'Card aberto automaticamente em ' || f.nome, null, null);
      insert into crm.notificacao (user_id, negocio_id, tipo, texto)
      select p.user_id, v_novo, 'tunel', 'Novo card em ' || f.nome || ': ' || n.titulo
        from crm.perfil p
       where p.ativo and p.user_id <> eu
         and (p.papel = 'gestor' or p.papel = any (f.papeis));
      v_gerados := v_gerados + 1;
    end loop;
  end if;

  if n.responsavel_id is distinct from eu then
    perform crm.notificar(n.responsavel_id, n.id, 'etapa', n.titulo || ': movido para ' || alvo.nome);
  end if;

  return jsonb_build_object('ok', true, 'cards_gerados', v_gerados);
end $$;

create or replace function public.painel_crm_negocio_atualizar(p_id uuid, p_dados jsonb)
returns void
language plpgsql security definer set search_path = '' as $$
declare eu uuid; n crm.negocio; v_resp uuid; tem_itens boolean; mudou text[] := '{}';
begin
  select * into n from crm.negocio where id = p_id for update;
  if n.id is null then raise exception 'Negócio não encontrado.'; end if;
  eu := crm.exige_operar(n.funil_id);

  if p_dados ? 'titulo' and nullif(trim(p_dados->>'titulo'), '') is null then
    raise exception 'O título não pode ficar vazio.';
  end if;
  select exists (select 1 from crm.negocio_item i where i.negocio_id = n.id) into tem_itens;
  if p_dados ? 'valor' and tem_itens then
    raise exception 'O valor é a soma dos itens. Edite os itens do negócio.';
  end if;

  v_resp := case when p_dados ? 'responsavel_id' then nullif(p_dados->>'responsavel_id', '')::uuid else n.responsavel_id end;
  if v_resp is not null and not exists (select 1 from crm.perfil where user_id = v_resp and ativo) then
    raise exception 'Responsável inválido ou inativo.';
  end if;

  update crm.negocio set
    titulo              = case when p_dados ? 'titulo' then trim(p_dados->>'titulo') else titulo end,
    empresa_id          = case when p_dados ? 'empresa_id' then nullif(p_dados->>'empresa_id', '')::uuid else empresa_id end,
    cliente_nome        = case when p_dados ? 'cliente_nome' then nullif(trim(p_dados->>'cliente_nome'), '') else cliente_nome end,
    cliente_cnpj        = case when p_dados ? 'cliente_cnpj' then nullif(trim(p_dados->>'cliente_cnpj'), '') else cliente_cnpj end,
    contato_nome        = case when p_dados ? 'contato_nome' then nullif(trim(p_dados->>'contato_nome'), '') else contato_nome end,
    contato_telefone    = case when p_dados ? 'contato_telefone' then nullif(trim(p_dados->>'contato_telefone'), '') else contato_telefone end,
    contato_email       = case when p_dados ? 'contato_email' then nullif(trim(p_dados->>'contato_email'), '') else contato_email end,
    responsavel_id      = v_resp,
    valor               = case when p_dados ? 'valor' then greatest(coalesce((p_dados->>'valor')::numeric, 0), 0) else valor end,
    origem              = case when p_dados ? 'origem' then coalesce(nullif(trim(p_dados->>'origem'), ''), 'manual') else origem end,
    previsao_fechamento = case when p_dados ? 'previsao_fechamento' then nullif(p_dados->>'previsao_fechamento', '')::date else previsao_fechamento end,
    observacao          = case when p_dados ? 'observacao' then nullif(trim(p_dados->>'observacao'), '') else observacao end,
    atualizado_em       = now()
  where id = n.id;

  if v_resp is distinct from n.responsavel_id then
    perform crm.registrar(n.id, 'responsavel',
      'Responsável: ' || coalesce((select nome from crm.perfil where user_id = v_resp), 'ninguém'));
    perform crm.notificar(v_resp, n.id, 'atribuido', 'Negócio atribuído a você: ' || n.titulo);
  end if;
  select array_agg(k) into mudou from jsonb_object_keys(p_dados) k where k <> 'responsavel_id';
  if mudou is not null then
    perform crm.registrar(n.id, 'edicao', 'Alterado: ' || array_to_string(mudou, ', '));
  end if;
end $$;

create or replace function public.painel_crm_atividade(p_id uuid, p_tipo text, p_texto text)
returns void
language plpgsql security definer set search_path = '' as $$
declare v_funil uuid;
begin
  select funil_id into v_funil from crm.negocio where id = p_id;
  if v_funil is null then raise exception 'Negócio não encontrado.'; end if;
  perform crm.exige_operar(v_funil);
  if p_tipo not in ('nota','ligacao','email','whatsapp','reuniao') then
    raise exception 'Tipo de atividade inválido.';
  end if;
  if nullif(trim(p_texto), '') is null then
    raise exception 'Escreva o que aconteceu.';
  end if;
  perform crm.registrar(p_id, p_tipo, trim(p_texto));
  update crm.negocio set atualizado_em = now() where id = p_id;
end $$;

create or replace function public.painel_crm_item_adicionar(
  p_negocio uuid, p_produto uuid default null, p_descricao text default null,
  p_quantidade numeric default 1, p_preco numeric default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_funil uuid; pr crm.produto; v_id uuid; v_desc text; v_preco numeric;
begin
  select funil_id into v_funil from crm.negocio where id = p_negocio;
  if v_funil is null then raise exception 'Negócio não encontrado.'; end if;
  perform crm.exige_operar(v_funil);
  if p_produto is not null then
    select * into pr from crm.produto where id = p_produto;
    if pr.id is null then raise exception 'Produto não encontrado.'; end if;
  end if;
  v_desc := coalesce(nullif(trim(p_descricao), ''), pr.nome);
  if v_desc is null then raise exception 'Escolha um produto ou descreva o item.'; end if;
  v_preco := coalesce(p_preco, pr.preco, 0);
  if coalesce(p_quantidade, 0) <= 0 then raise exception 'Quantidade precisa ser maior que zero.'; end if;

  insert into crm.negocio_item (negocio_id, produto_id, descricao, quantidade, preco_unitario)
  values (p_negocio, p_produto, v_desc, p_quantidade, greatest(v_preco, 0))
  returning id into v_id;
  perform crm.recalcular_valor(p_negocio);
  perform crm.registrar(p_negocio, 'item', 'Item adicionado: ' || v_desc);
  return v_id;
end $$;

create or replace function public.painel_crm_item_remover(p_item uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare i crm.negocio_item; v_funil uuid;
begin
  select * into i from crm.negocio_item where id = p_item;
  if i.id is null then raise exception 'Item não encontrado.'; end if;
  select funil_id into v_funil from crm.negocio where id = i.negocio_id;
  perform crm.exige_operar(v_funil);
  delete from crm.negocio_item where id = p_item;

  perform crm.recalcular_valor(i.negocio_id);
  perform crm.registrar(i.negocio_id, 'item', 'Item removido: ' || i.descricao);
end $$;

create or replace function public.painel_crm_produto_salvar(
  p_id uuid, p_nome text, p_descricao text default null, p_categoria text default null,
  p_preco numeric default null, p_unidade text default 'un', p_recorrente boolean default false,
  p_ativo boolean default true
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  perform crm.exige('gestor');
  if nullif(trim(p_nome), '') is null then raise exception 'Informe o nome do produto.'; end if;
  if p_id is null then
    insert into crm.produto (nome, descricao, categoria, preco, unidade, recorrente, ativo)
    values (trim(p_nome), nullif(trim(p_descricao), ''), nullif(trim(p_categoria), ''), p_preco,
            coalesce(nullif(trim(p_unidade), ''), 'un'), coalesce(p_recorrente, false), coalesce(p_ativo, true))
    returning id into v_id;
  else
    update crm.produto set nome = trim(p_nome), descricao = nullif(trim(p_descricao), ''),
           categoria = nullif(trim(p_categoria), ''), preco = p_preco,
           unidade = coalesce(nullif(trim(p_unidade), ''), 'un'),
           recorrente = coalesce(p_recorrente, false), ativo = coalesce(p_ativo, true)
     where id = p_id returning id into v_id;
    if v_id is null then raise exception 'Produto não encontrado.'; end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'Já existe um produto com esse nome.';
end $$;

create or replace function public.painel_crm_etapa_salvar(
  p_id uuid, p_funil uuid, p_nome text, p_tipo text default 'aberta', p_cor text default 'muted',
  p_alerta_dias int default null, p_ativo boolean default true
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_abertos int;
begin
  perform crm.exige('gestor');
  if nullif(trim(p_nome), '') is null then raise exception 'Informe o nome da etapa.'; end if;
  if p_tipo not in ('aberta','ganho','perdido') then raise exception 'Tipo de etapa inválido.'; end if;
  if p_alerta_dias is not null and p_alerta_dias <= 0 then raise exception 'O aviso precisa ser de 1 dia ou mais.'; end if;

  if p_id is null then
    insert into crm.etapa (funil_id, nome, ordem, tipo, cor, alerta_dias, ativo)
    values (p_funil, trim(p_nome),
            coalesce((select max(ordem) + 1 from crm.etapa where funil_id = p_funil), 1),
            p_tipo::crm.tipo_etapa, p_cor, p_alerta_dias, coalesce(p_ativo, true))
    returning id into v_id;
  else
    if p_ativo is false then
      select count(*) into v_abertos from crm.negocio where etapa_id = p_id;
      if v_abertos > 0 then
        raise exception 'Há % negócio(s) nesta etapa. Mova-os antes de desativar.', v_abertos;
      end if;
    end if;
    update crm.etapa set nome = trim(p_nome), tipo = p_tipo::crm.tipo_etapa, cor = p_cor,
           alerta_dias = p_alerta_dias, ativo = coalesce(p_ativo, true)
     where id = p_id and funil_id = p_funil returning id into v_id;
    if v_id is null then raise exception 'Etapa não encontrada.'; end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'Já existe uma etapa com esse nome neste funil.';
end $$;

create or replace function public.painel_crm_etapas_reordenar(p_funil uuid, p_ids uuid[]) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('gestor');
  update crm.etapa e set ordem = x.pos
    from unnest(p_ids) with ordinality as x(id, pos)
   where e.id = x.id and e.funil_id = p_funil;
end $$;

create or replace function public.painel_crm_rodizio_salvar(p_funil uuid, p_users uuid[]) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('gestor');
  delete from crm.rodizio where funil_id = p_funil and not (user_id = any (coalesce(p_users, '{}')));
  insert into crm.rodizio (funil_id, user_id, ordem, ativo)
  select p_funil, x.id, x.pos, true
    from unnest(coalesce(p_users, '{}')) with ordinality as x(id, pos)
    join crm.perfil p on p.user_id = x.id
  on conflict (funil_id, user_id) do update set ordem = excluded.ordem, ativo = true;
end $$;

create or replace function public.painel_notificacoes(p_limite int default 30)
returns table (id bigint, negocio_id uuid, tipo text, texto text, lida_em timestamptz, criado_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := crm.exige_ativo();
  return query
    select n.id, n.negocio_id, n.tipo, n.texto, n.lida_em, n.criado_em
      from crm.notificacao n where n.user_id = eu
     order by n.criado_em desc limit least(greatest(p_limite, 1), 100);
end $$;

create or replace function public.painel_notificacoes_nao_lidas() returns int
language plpgsql stable security definer set search_path = '' as $$
declare eu uuid;
begin
  eu := crm.exige_ativo();
  return (select count(*)::int from crm.notificacao where user_id = eu and lida_em is null);
end $$;

create or replace function public.painel_notificacoes_marcar_lidas(p_id bigint default null) returns void
language plpgsql security definer set search_path = '' as $$
declare eu uuid;
begin
  eu := crm.exige_ativo();
  update crm.notificacao set lida_em = now()
   where user_id = eu and lida_em is null and (p_id is null or id = p_id);
end $$;

create or replace function crm.gerar_alertas() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; qtd int := 0; dias int;
begin
  for r in
    select n.id, n.titulo, n.responsavel_id, e.nome as etapa, e.alerta_dias, n.entrou_etapa_em
      from crm.negocio n join crm.etapa e on e.id = n.etapa_id
     where e.tipo = 'aberta' and e.alerta_dias is not null
       and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)
       and (n.ultimo_alerta_em is null or now() - n.ultimo_alerta_em >= make_interval(days => e.alerta_dias))
  loop
    dias := floor(extract(epoch from now() - r.entrou_etapa_em) / 86400)::int;
    if r.responsavel_id is not null then
      insert into crm.notificacao (user_id, negocio_id, tipo, texto)
      values (r.responsavel_id, r.id, 'parado', r.titulo || ': há ' || dias || ' dias em ' || r.etapa);
    else
      insert into crm.notificacao (user_id, negocio_id, tipo, texto)
      select p.user_id, r.id, 'parado', r.titulo || ' (sem responsável): há ' || dias || ' dias em ' || r.etapa
        from crm.perfil p where p.ativo and p.papel in ('gestor','admin');
    end if;
    insert into crm.evento (negocio_id, tipo, texto) values (r.id, 'alerta', 'Aviso: ' || dias || ' dias em ' || r.etapa);
    update crm.negocio set ultimo_alerta_em = now() where id = r.id;
    qtd := qtd + 1;
  end loop;
  return qtd;
end $$;
revoke execute on function crm.gerar_alertas() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('crm-alertas', '0 11 * * 1-5', 'select crm.gerar_alertas()');
  end if;
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
