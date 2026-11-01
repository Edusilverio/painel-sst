

create extension if not exists pgcrypto with schema extensions;

create table if not exists crm.wa_config (
  id                  boolean primary key default true check (id),
  inbox_url           text not null default 'https://painel.ai.exemplo.com.br/inbox',
  criar_negocio       boolean not null default false,
  funil_id            uuid references crm.funil(id) on delete set null,
  token_hash          text,
  token_gerado_em     timestamptz,
  ultimo_recebimento  timestamptz
);
insert into crm.wa_config (id, funil_id)
select true, (select id from crm.funil where slug = 'comercial') on conflict do nothing;
alter table crm.wa_config enable row level security;

create table if not exists crm.wa_contato (
  id               uuid primary key default gen_random_uuid(),
  ext_lead_id      uuid not null unique,
  ext_conversa_id  uuid,
  nome             text,
  telefone         text,
  status           text,
  ultima_mensagem  text,
  ultima_direcao   text check (ultima_direcao in ('in','out')),
  ultima_em        timestamptz,
  mensagens        int not null default 0,
  primeiro_em      timestamptz not null default now(),
  empresa_id       uuid references public.empresa(id) on delete set null,
  negocio_id       uuid references crm.negocio(id) on delete set null,
  ignorado         boolean not null default false,
  atualizado_em    timestamptz not null default now()
);
create index if not exists wa_contato_ultima_idx on crm.wa_contato (ultima_em desc nulls last);
create index if not exists wa_contato_negocio_idx on crm.wa_contato (negocio_id);
alter table crm.wa_contato enable row level security;

create table if not exists crm.wa_modelo (
  id             uuid primary key default gen_random_uuid(),
  titulo         text not null,
  categoria      text not null default 'geral'
                 check (categoria in ('geral','comercial','agendamento','exames','cobranca','documentos')),
  texto          text not null,
  ativo          boolean not null default true,
  ordem          int not null default 0,
  atualizado_em  timestamptz not null default now()
);
alter table crm.wa_modelo enable row level security;

insert into crm.wa_modelo (titulo, categoria, ordem, texto)
select * from (values
  ('Primeiro contato', 'comercial', 1,
   'Olá, {nome}! Aqui é {atendente}, da Vitalis Medicina e Engenharia do Trabalho. Recebemos seu contato e quero entender melhor o que a {empresa} precisa. Podemos conversar agora?'),
  ('Envio de proposta', 'comercial', 2,
   '{nome}, conforme conversamos, segue a proposta da Vitalis para a {empresa}. Fico à disposição para qualquer dúvida.'),
  ('Confirmação de exame', 'agendamento', 3,
   'Olá, {nome}! Confirmamos o exame de {colaborador} no dia {data} às {hora}, na Vitalis. Levar documento com foto. Qualquer dúvida, é só responder esta mensagem.'),
  ('Exames a vencer', 'exames', 4,
   'Olá, {nome}! Os exames periódicos de alguns colaboradores da {empresa} vencem nos próximos dias. Vamos agendar?'),
  ('Lembrete de pagamento', 'cobranca', 5,
   'Olá, {nome}! Consta em aberto a mensalidade de {competencia} da {empresa}, no valor de {valor}, vencida em {vencimento}. Se já pagou, pode desconsiderar. Quer que eu envie a segunda via?'),
  ('Renovação de documento', 'documentos', 6,
   'Olá, {nome}! O {documento} da {empresa} vence em {vencimento}. Vamos iniciar a renovação?')
) v(titulo, categoria, ordem, texto)
where not exists (select 1 from crm.wa_modelo);

create or replace function crm.so_digitos(p text) returns text
language sql immutable set search_path = '' as $$ select nullif(regexp_replace(coalesce(p, ''), '\D', '', 'g'), '') $$;

create or replace function crm.wa_empresa_por_telefone(p_tel text) returns uuid
language sql stable security definer set search_path = '' as $$
  with t as (select right(crm.so_digitos(p_tel), 8) fim where length(crm.so_digitos(p_tel)) >= 8),
  achadas as (
    select e.id from public.empresa e, t where right(crm.so_digitos(e.telefone), 8) = t.fim
    union
    select c.empresa_id from public.empresa_contato c, t where right(crm.so_digitos(c.telefone), 8) = t.fim
  )
  select case when (select count(*) from achadas) = 1 then (select id from achadas) end
$$;

create or replace function crm.wa_abrir_negocio(p_contato uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare c crm.wa_contato; v_funil uuid; v_etapa uuid; v_resp uuid; v_id uuid; rotulo text;
begin
  select * into c from crm.wa_contato where id = p_contato for update;
  if c.id is null then raise exception 'Contato não encontrado.'; end if;
  if c.negocio_id is not null then return c.negocio_id; end if;
  select coalesce(w.funil_id, (select f.id from crm.funil f where f.slug = 'comercial')) into v_funil from crm.wa_config w where w.id;
  select e.id into v_etapa from crm.etapa e where e.funil_id = v_funil and e.ativo and e.tipo = 'aberta' order by e.ordem limit 1;
  if v_etapa is null then raise exception 'O funil de destino do WhatsApp não tem etapa aberta.'; end if;
  if (select f.usa_rodizio from crm.funil f where f.id = v_funil) then v_resp := crm.proximo_rodizio(v_funil); end if;
  rotulo := coalesce(nullif(trim(c.nome), ''), '+' || c.telefone, 'Contato sem nome');

  insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, contato_nome, contato_telefone,
                           responsavel_id, origem, observacao, criado_por)
  values (v_funil, v_etapa, 'WhatsApp · ' || rotulo, c.empresa_id,
          case when c.empresa_id is null then rotulo end, nullif(trim(c.nome), ''), c.telefone,
          v_resp, 'whatsapp',
          'Primeiro contato pelo WhatsApp em ' || to_char(c.primeiro_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
          auth.uid())
  returning id into v_id;
  update crm.wa_contato set negocio_id = v_id, atualizado_em = now() where id = c.id;
  perform crm.registrar(v_id, 'whatsapp',
    case when v_resp is not null then 'Veio do WhatsApp e foi distribuído pelo rodízio' else 'Veio do WhatsApp' end, null, v_etapa);
  perform crm.notificar(v_resp, v_id, 'atribuido', 'Novo lead do WhatsApp: ' || rotulo);
  return v_id;
end $$;

create or replace function crm.wa_receber(p_eventos jsonb, p_criar boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ev jsonb; v_id uuid; novo boolean; n_rec int := 0; n_novos int := 0; n_neg int := 0; cfg crm.wa_config;
begin
  if jsonb_typeof(p_eventos) <> 'array' then raise exception 'Envie uma lista de eventos.'; end if;
  if jsonb_array_length(p_eventos) > 500 then raise exception 'No máximo 500 eventos por chamada.'; end if;
  select * into cfg from crm.wa_config where id;
  for ev in select * from jsonb_array_elements(p_eventos) loop
    if nullif(ev->>'lead_id', '') is null then continue; end if;
    insert into crm.wa_contato as w (ext_lead_id, ext_conversa_id, nome, telefone, status, ultima_mensagem, ultima_direcao,
                                     ultima_em, mensagens, primeiro_em)
    values ((ev->>'lead_id')::uuid, nullif(ev->>'conversa_id', '')::uuid, nullif(trim(ev->>'nome'), ''),
            crm.so_digitos(ev->>'telefone'), nullif(ev->>'status', ''), left(nullif(ev->>'ultima_mensagem', ''), 300),
            case when ev->>'ultima_direcao' in ('in','out') then ev->>'ultima_direcao' end,
            nullif(ev->>'ultima_em', '')::timestamptz, coalesce((ev->>'mensagens')::int, 0),
            coalesce(nullif(ev->>'criado_em', '')::timestamptz, now()))
    on conflict (ext_lead_id) do update set
      ext_conversa_id = coalesce(excluded.ext_conversa_id, w.ext_conversa_id),
      nome            = coalesce(excluded.nome, w.nome),
      telefone        = coalesce(excluded.telefone, w.telefone),
      status          = coalesce(excluded.status, w.status),
      ultima_mensagem = case when excluded.ultima_em >= coalesce(w.ultima_em, '-infinity') then coalesce(excluded.ultima_mensagem, w.ultima_mensagem) else w.ultima_mensagem end,
      ultima_direcao  = case when excluded.ultima_em >= coalesce(w.ultima_em, '-infinity') then coalesce(excluded.ultima_direcao, w.ultima_direcao) else w.ultima_direcao end,
      ultima_em       = greatest(excluded.ultima_em, w.ultima_em),
      mensagens       = greatest(excluded.mensagens, w.mensagens),
      primeiro_em     = least(excluded.primeiro_em, w.primeiro_em),
      atualizado_em   = now()
    returning w.id, (w.xmax = 0) into v_id, novo;
    n_rec := n_rec + 1;
    if novo then
      n_novos := n_novos + 1;
      update crm.wa_contato set empresa_id = crm.wa_empresa_por_telefone(telefone) where id = v_id and empresa_id is null;
      if p_criar and cfg.criar_negocio then
        perform crm.wa_abrir_negocio(v_id);
        n_neg := n_neg + 1;
      end if;
    end if;
  end loop;
  update crm.wa_config set ultimo_recebimento = now() where id;
  return jsonb_build_object('recebidos', n_rec, 'novos', n_novos, 'negocios', n_neg);
end $$;

revoke execute on function crm.wa_empresa_por_telefone(text), crm.wa_abrir_negocio(uuid), crm.wa_receber(jsonb, boolean)
  from public, anon, authenticated;

create or replace function public.integracao_wa_receber(p_token text, p_eventos jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare h text;
begin
  select token_hash into h from crm.wa_config where id;
  if h is null or p_token is null or encode(extensions.digest(p_token, 'sha256'), 'hex') <> h then
    raise exception 'Token inválido.' using errcode = '42501';
  end if;
  return crm.wa_receber(p_eventos, true);
end $$;
revoke execute on function public.integracao_wa_receber(text, jsonb) from public;
grant execute on function public.integracao_wa_receber(text, jsonb) to anon, authenticated;

create or replace function public.painel_wa_resumo() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare cfg crm.wa_config; papel crm.papel;
begin
  perform crm.exige('gestor','comercial','operacoes','financeiro');
  select * into cfg from crm.wa_config where id;
  papel := crm.papel_atual();
  return (select jsonb_build_object(
    'contatos', count(*) filter (where not ignorado),
    'novos_7d', count(*) filter (where not ignorado and primeiro_em > now() - interval '7 days'),
    'sem_negocio', count(*) filter (where not ignorado and negocio_id is null),
    'com_negocio', count(*) filter (where negocio_id is not null),
    'humano', count(*) filter (where not ignorado and status = 'human'),
    'ativos_24h', count(*) filter (where ultima_em > now() - interval '24 hours'),
    'ultimo_recebimento', cfg.ultimo_recebimento,
    'integracao_ativa', cfg.token_hash is not null,
    'token_gerado_em', cfg.token_gerado_em,
    'criar_negocio', cfg.criar_negocio,
    'inbox_url', cfg.inbox_url,
    'funil_id', cfg.funil_id,
    'funil_nome', (select f.nome from crm.funil f where f.id = cfg.funil_id),
    'pode_configurar', papel in ('admin','gestor'),
    'pode_criar_negocio', crm.pode_operar(cfg.funil_id))
    from crm.wa_contato);
end $$;

create or replace function public.painel_wa_contatos(p_busca text default null, p_filtro text default null)
returns table (id uuid, nome text, telefone text, status text, ultima_mensagem text, ultima_direcao text, ultima_em timestamptz,
               mensagens int, primeiro_em timestamptz, ignorado boolean, ext_lead_id uuid, ext_conversa_id uuid,
               empresa_id uuid, empresa text, negocio_id uuid, negocio_numero bigint, negocio_etapa text,
               negocio_etapa_tipo text, funil_slug text, responsavel text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); dig text := crm.so_digitos(p_busca);
begin
  perform crm.exige('gestor','comercial','operacoes','financeiro');
  return query
    select w.id, w.nome, w.telefone, w.status, w.ultima_mensagem, w.ultima_direcao, w.ultima_em, w.mensagens, w.primeiro_em,
           w.ignorado, w.ext_lead_id, w.ext_conversa_id, w.empresa_id,
           coalesce(nullif(e.nome_fantasia, ''), e.razao_social)::text, n.id, n.numero, et.nome, et.tipo::text, f.slug, p.nome::text
      from crm.wa_contato w
      left join public.empresa e on e.id = w.empresa_id
      left join crm.negocio n on n.id = w.negocio_id
      left join crm.etapa et on et.id = n.etapa_id
      left join crm.funil f on f.id = n.funil_id
      left join crm.perfil p on p.user_id = n.responsavel_id
     where case coalesce(p_filtro, 'todos')
             when 'ignorados' then w.ignorado
             when 'sem_negocio' then not w.ignorado and w.negocio_id is null
             when 'com_negocio' then w.negocio_id is not null
             when 'humano' then not w.ignorado and w.status = 'human'
             when 'novos' then not w.ignorado and w.primeiro_em > now() - interval '7 days'
             else not w.ignorado end
       and (termo is null or w.nome ilike '%' || termo || '%' or e.razao_social ilike '%' || termo || '%'
            or e.nome_fantasia ilike '%' || termo || '%' or (dig is not null and length(dig) >= 4 and w.telefone like '%' || dig || '%'))
     order by w.ultima_em desc nulls last
     limit 500;
end $$;

create or replace function public.painel_wa_modelos() returns table (id uuid, titulo text, categoria text, texto text, ativo boolean, ordem int)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige_ativo();
  return query select m.id, m.titulo, m.categoria, m.texto, m.ativo, m.ordem from crm.wa_modelo m order by m.ordem, m.titulo;
end $$;

create or replace function public.painel_wa_contexto(p_negocio uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform crm.exige_ativo();
  return jsonb_build_object(
    'inbox_url', (select inbox_url from crm.wa_config where id),
    'atendente', (select p.nome from crm.perfil p where p.user_id = auth.uid()),
    'contato', (select jsonb_build_object('id', w.id, 'nome', w.nome, 'telefone', w.telefone,
                                          'ext_lead_id', w.ext_lead_id, 'ext_conversa_id', w.ext_conversa_id)
                  from crm.wa_contato w where p_negocio is not null and w.negocio_id = p_negocio limit 1));
end $$;

create or replace function public.painel_wa_criar_negocio(p_contato uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare f uuid;
begin
  select coalesce(funil_id, (select id from crm.funil where slug = 'comercial')) into f from crm.wa_config where id;
  perform crm.exige_operar(f);
  if (select ignorado from crm.wa_contato where id = p_contato) then
    update crm.wa_contato set ignorado = false where id = p_contato;
  end if;
  return crm.wa_abrir_negocio(p_contato);
end $$;

create or replace function public.painel_wa_contato_salvar(p_contato uuid, p_dados jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('gestor','comercial','operacoes');
  update crm.wa_contato set
    empresa_id = case when p_dados ? 'empresa_id' then nullif(p_dados->>'empresa_id', '')::uuid else empresa_id end,
    ignorado   = case when p_dados ? 'ignorado' then (p_dados->>'ignorado')::boolean else ignorado end,
    atualizado_em = now()
  where id = p_contato;
  if not found then raise exception 'Contato não encontrado.'; end if;

  if nullif(p_dados->>'empresa_id', '') is not null then
    update crm.negocio n set empresa_id = (p_dados->>'empresa_id')::uuid, atualizado_em = now()
      from crm.wa_contato w where w.id = p_contato and n.id = w.negocio_id and n.empresa_id is null;
  end if;
end $$;

create or replace function public.painel_wa_modelo_salvar(p_id uuid, p_dados jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v uuid := p_id;
begin
  perform crm.exige('gestor');
  if nullif(trim(p_dados->>'titulo'), '') is null or nullif(trim(p_dados->>'texto'), '') is null then
    raise exception 'Preencha o título e o texto.';
  end if;
  if coalesce(p_dados->>'categoria', 'geral') not in ('geral','comercial','agendamento','exames','cobranca','documentos') then
    raise exception 'Categoria inválida.';
  end if;
  if v is null then
    insert into crm.wa_modelo (titulo, categoria, texto, ordem)
    values (trim(p_dados->>'titulo'), coalesce(p_dados->>'categoria', 'geral'), trim(p_dados->>'texto'),
            coalesce((select max(ordem) + 1 from crm.wa_modelo), 1))
    returning id into v;
  else
    update crm.wa_modelo set titulo = trim(p_dados->>'titulo'), categoria = coalesce(p_dados->>'categoria', categoria),
           texto = trim(p_dados->>'texto'), ativo = coalesce((p_dados->>'ativo')::boolean, ativo), atualizado_em = now()
     where id = v;
    if not found then raise exception 'Modelo não encontrado.'; end if;
  end if;
  return v;
end $$;

create or replace function public.painel_wa_modelo_excluir(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('gestor');
  delete from crm.wa_modelo where id = p_id;
end $$;

create or replace function public.painel_wa_config_salvar(p_dados jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('gestor');
  if p_dados ? 'inbox_url' and coalesce(p_dados->>'inbox_url', '') !~ '^https://' then
    raise exception 'O link do Inbox precisa começar com https://';
  end if;
  if nullif(p_dados->>'funil_id', '') is not null
     and not exists (select 1 from crm.funil f where f.id = (p_dados->>'funil_id')::uuid and f.ativo) then
    raise exception 'Funil inválido.';
  end if;
  update crm.wa_config set
    inbox_url     = coalesce(nullif(trim(p_dados->>'inbox_url'), ''), inbox_url),
    criar_negocio = coalesce((p_dados->>'criar_negocio')::boolean, criar_negocio),
    funil_id      = coalesce(nullif(p_dados->>'funil_id', '')::uuid, funil_id)
  where id;
end $$;

create or replace function public.painel_wa_token_gerar() returns text
language plpgsql security definer set search_path = '' as $$
declare t text := 'vitalis_wa_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  perform crm.exige('gestor');
  update crm.wa_config set token_hash = encode(extensions.digest(t, 'sha256'), 'hex'), token_gerado_em = now() where id;
  return t;
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
