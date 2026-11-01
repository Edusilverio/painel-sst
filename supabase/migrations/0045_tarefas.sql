

create table if not exists crm.quadro (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null check (length(trim(nome)) > 1),
  descricao   text,
  ordem       int not null default 0,
  arquivado   boolean not null default false,
  criado_por  uuid,
  criado_em   timestamptz not null default now()
);

create table if not exists crm.tarefa (
  id              uuid primary key default gen_random_uuid(),
  numero          bigint generated always as identity unique,
  quadro_id       uuid not null references crm.quadro(id) on delete cascade,
  titulo          text not null check (length(trim(titulo)) > 1),
  status          text not null default 'nao_iniciado'
                    check (status in ('nao_iniciado','em_andamento','parado','feito')),
  prioridade      text not null default 'media' check (prioridade in ('baixa','media','alta','critica')),
  prazo           date,
  responsavel_id  uuid references crm.perfil(user_id) on delete set null,
  notas           text,
  empresa_id      uuid references public.empresa(id) on delete set null,
  negocio_id      uuid references crm.negocio(id) on delete set null,
  ordem           double precision not null default extract(epoch from now()),
  ultimo_alerta_em date,
  concluida_em    timestamptz,
  criado_por      uuid,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);
create index if not exists tarefa_quadro_idx on crm.tarefa (quadro_id, status, ordem);
create index if not exists tarefa_resp_idx on crm.tarefa (responsavel_id) where status <> 'feito';

create table if not exists crm.tarefa_item (
  id         uuid primary key default gen_random_uuid(),
  tarefa_id  uuid not null references crm.tarefa(id) on delete cascade,
  texto      text not null check (length(trim(texto)) > 0),
  feito      boolean not null default false,
  ordem      double precision not null default extract(epoch from now()),
  criado_em  timestamptz not null default now()
);
create index if not exists tarefa_item_idx on crm.tarefa_item (tarefa_id, ordem);

create table if not exists crm.tarefa_comentario (
  id         bigint generated always as identity primary key,
  tarefa_id  uuid not null references crm.tarefa(id) on delete cascade,
  autor_id   uuid,
  texto      text not null check (length(trim(texto)) > 0),
  sistema    boolean not null default false,
  criado_em  timestamptz not null default now()
);
create index if not exists tarefa_comentario_idx on crm.tarefa_comentario (tarefa_id, criado_em);

alter table crm.quadro            enable row level security;
alter table crm.tarefa            enable row level security;
alter table crm.tarefa_item       enable row level security;
alter table crm.tarefa_comentario enable row level security;

alter table crm.notificacao add column if not exists tarefa_id uuid references crm.tarefa(id) on delete cascade;

insert into crm.quadro (nome, descricao, ordem)
select 'Fluxo de Trabalho', 'Tarefas da equipe Vitalis', 1
 where not exists (select 1 from crm.quadro);

create or replace function crm.exige_editor() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare eu uuid;
begin
  eu := crm.exige_ativo();
  if crm.papel_atual() = 'leitura' then
    raise exception 'Seu perfil é só de leitura.' using errcode = '42501';
  end if;
  return eu;
end $$;

create or replace function crm.status_rotulo(p text) returns text
language sql immutable set search_path = '' as $$
  select case p when 'nao_iniciado' then 'Não iniciado' when 'em_andamento' then 'Em andamento'
                when 'parado' then 'Parado' when 'feito' then 'Feito' else p end
$$;

create or replace function crm.tarefa_log(p_tarefa uuid, p_texto text) returns void
language sql security definer set search_path = '' as $$
  insert into crm.tarefa_comentario (tarefa_id, autor_id, texto, sistema) values (p_tarefa, auth.uid(), p_texto, true)
$$;

create or replace function crm.notificar_tarefa(p_user uuid, p_tarefa uuid, p_tipo text, p_texto text) returns void
language sql security definer set search_path = '' as $$
  insert into crm.notificacao (user_id, tarefa_id, tipo, texto)
  select p_user, p_tarefa, p_tipo, p_texto
   where p_user is not null and p_user is distinct from auth.uid()
$$;

create or replace function crm.alertas_tarefas() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; qtd int := 0; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  for r in
    select t.id, t.titulo, t.prazo, t.responsavel_id from crm.tarefa t
     where t.status <> 'feito' and t.prazo is not null and t.prazo <= hoje
       and t.responsavel_id is not null and t.ultimo_alerta_em is distinct from hoje
  loop
    insert into crm.notificacao (user_id, tarefa_id, tipo, texto)
    values (r.responsavel_id, r.id, 'prazo',
            case when r.prazo = hoje then 'Vence hoje: ' else 'Atrasada: ' end || r.titulo);
    update crm.tarefa set ultimo_alerta_em = hoje where id = r.id;
    qtd := qtd + 1;
  end loop;
  return qtd;
end $$;

revoke execute on function crm.exige_editor(), crm.tarefa_log(uuid, text),
  crm.notificar_tarefa(uuid, uuid, text, text), crm.alertas_tarefas() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('crm-alertas-tarefas', '5 11 * * *', 'select crm.alertas_tarefas()');
  end if;
end $$;

create or replace function public.painel_tarefas_quadros()
returns table (id uuid, nome text, descricao text, abertas int, atrasadas int)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige_ativo();
  return query
    select q.id, q.nome, q.descricao,
           (select count(*)::int from crm.tarefa t where t.quadro_id = q.id and t.status <> 'feito'),
           (select count(*)::int from crm.tarefa t where t.quadro_id = q.id and t.status <> 'feito'
               and t.prazo < (now() at time zone 'America/Sao_Paulo')::date)
      from crm.quadro q where not q.arquivado order by q.ordem, q.nome;
end $$;

create or replace function public.painel_tarefas(p_quadro uuid, p_responsavel uuid default null, p_busca text default null)
returns table (id uuid, numero bigint, titulo text, status text, prioridade text, prazo date,
               responsavel_id uuid, responsavel_nome text, notas text, empresa_id uuid, empresa text,
               negocio_id uuid, ordem double precision, itens int, itens_feitos int, comentarios int,
               atrasada boolean, criado_em timestamptz, concluida_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform crm.exige_ativo();
  return query
    select t.id, t.numero, t.titulo, t.status, t.prioridade, t.prazo, t.responsavel_id, p.nome::text,
           t.notas, t.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social)::text, t.negocio_id, t.ordem,
           (select count(*)::int from crm.tarefa_item i where i.tarefa_id = t.id),
           (select count(*)::int from crm.tarefa_item i where i.tarefa_id = t.id and i.feito),
           (select count(*)::int from crm.tarefa_comentario c where c.tarefa_id = t.id and not c.sistema),
           t.status <> 'feito' and t.prazo < (now() at time zone 'America/Sao_Paulo')::date,
           t.criado_em, t.concluida_em
      from crm.tarefa t
      left join crm.perfil p on p.user_id = t.responsavel_id
      left join public.empresa e on e.id = t.empresa_id
     where t.quadro_id = p_quadro
       and (p_responsavel is null or t.responsavel_id = p_responsavel)
       and (termo is null or t.titulo ilike '%' || termo || '%' or t.notas ilike '%' || termo || '%')

       and (t.status <> 'feito' or t.concluida_em is null or t.concluida_em > now() - interval '60 days')
     order by t.ordem;
end $$;

create or replace function public.painel_tarefa(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform crm.exige_ativo();
  select jsonb_build_object(
    'id', t.id, 'numero', t.numero, 'quadro_id', t.quadro_id, 'titulo', t.titulo, 'status', t.status,
    'prioridade', t.prioridade, 'prazo', t.prazo, 'responsavel_id', t.responsavel_id,
    'responsavel_nome', p.nome, 'notas', t.notas, 'empresa_id', t.empresa_id,
    'empresa', coalesce(nullif(e.nome_fantasia, ''), e.razao_social), 'negocio_id', t.negocio_id,
    'criado_por_nome', c.nome, 'criado_em', t.criado_em, 'concluida_em', t.concluida_em,
    'pode_excluir', t.criado_por = auth.uid() or t.responsavel_id = auth.uid() or crm.papel_atual() in ('admin','gestor'),
    'itens', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'texto', i.texto, 'feito', i.feito) order by i.ordem)
                         from crm.tarefa_item i where i.tarefa_id = t.id), '[]'::jsonb),
    'comentarios', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'texto', m.texto, 'sistema', m.sistema,
                                                               'autor', coalesce(a.nome, 'Sistema'), 'criado_em', m.criado_em)
                                              order by m.criado_em desc, m.id desc)
                               from crm.tarefa_comentario m left join crm.perfil a on a.user_id = m.autor_id
                              where m.tarefa_id = t.id), '[]'::jsonb))
    into r
    from crm.tarefa t
    left join crm.perfil p on p.user_id = t.responsavel_id
    left join crm.perfil c on c.user_id = t.criado_por
    left join public.empresa e on e.id = t.empresa_id
   where t.id = p_id;
  if r is null then raise exception 'Tarefa não encontrada.'; end if;
  return r;
end $$;

create or replace function public.painel_minhas_tarefas()
returns table (id uuid, quadro_id uuid, quadro text, titulo text, status text, prioridade text, prazo date, atrasada boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := crm.exige_ativo();
  return query
    select t.id, t.quadro_id, q.nome, t.titulo, t.status, t.prioridade, t.prazo,
           t.prazo < (now() at time zone 'America/Sao_Paulo')::date
      from crm.tarefa t join crm.quadro q on q.id = t.quadro_id
     where t.responsavel_id = eu and t.status <> 'feito'
     order by t.prazo nulls last, t.ordem;
end $$;

create or replace function public.painel_tarefa_quadro_salvar(p_id uuid, p_nome text, p_descricao text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare eu uuid; v uuid := p_id;
begin
  eu := crm.exige_editor();
  if nullif(trim(p_nome), '') is null then raise exception 'Informe o nome do quadro.'; end if;
  if v is null then
    insert into crm.quadro (nome, descricao, ordem, criado_por)
    values (trim(p_nome), nullif(trim(p_descricao), ''), coalesce((select max(ordem) + 1 from crm.quadro), 1), eu)
    returning id into v;
  else
    update crm.quadro set nome = trim(p_nome), descricao = nullif(trim(p_descricao), '') where id = v;
  end if;
  return v;
end $$;

create or replace function public.painel_tarefa_quadro_arquivar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('gestor');
  update crm.quadro set arquivado = true where id = p_id;
end $$;

create or replace function public.painel_tarefa_salvar(p_id uuid, p_dados jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  eu uuid; v uuid := p_id; atual crm.tarefa; novo_resp uuid; novo_status text;
begin
  eu := crm.exige_editor();
  if p_dados ? 'status' and p_dados->>'status' not in ('nao_iniciado','em_andamento','parado','feito') then
    raise exception 'Status inválido.';
  end if;
  if p_dados ? 'prioridade' and p_dados->>'prioridade' not in ('baixa','media','alta','critica') then
    raise exception 'Prioridade inválida.';
  end if;

  if v is null then
    if nullif(trim(p_dados->>'titulo'), '') is null then raise exception 'Informe o título da tarefa.'; end if;
    insert into crm.tarefa (quadro_id, titulo, status, prioridade, prazo, responsavel_id, notas, empresa_id, negocio_id,
                            criado_por, concluida_em)
    values ((p_dados->>'quadro_id')::uuid, trim(p_dados->>'titulo'),
            coalesce(nullif(p_dados->>'status', ''), 'nao_iniciado'), coalesce(nullif(p_dados->>'prioridade', ''), 'media'),
            nullif(p_dados->>'prazo', '')::date, nullif(p_dados->>'responsavel_id', '')::uuid,
            nullif(trim(p_dados->>'notas'), ''), nullif(p_dados->>'empresa_id', '')::uuid,
            nullif(p_dados->>'negocio_id', '')::uuid, eu,
            case when p_dados->>'status' = 'feito' then now() end)
    returning id into v;
    perform crm.tarefa_log(v, 'Tarefa criada');
    select * into atual from crm.tarefa where id = v;
    perform crm.notificar_tarefa(atual.responsavel_id, v, 'tarefa', 'Nova tarefa para você: ' || atual.titulo);
    return v;
  end if;

  select * into atual from crm.tarefa where id = v for update;
  if atual.id is null then raise exception 'Tarefa não encontrada.'; end if;
  novo_resp := case when p_dados ? 'responsavel_id' then nullif(p_dados->>'responsavel_id', '')::uuid else atual.responsavel_id end;
  novo_status := coalesce(nullif(p_dados->>'status', ''), atual.status);

  update crm.tarefa set
    titulo        = coalesce(nullif(trim(p_dados->>'titulo'), ''), titulo),
    status        = novo_status,
    prioridade    = coalesce(nullif(p_dados->>'prioridade', ''), prioridade),
    prazo         = case when p_dados ? 'prazo' then nullif(p_dados->>'prazo', '')::date else prazo end,
    responsavel_id = novo_resp,
    notas         = case when p_dados ? 'notas' then nullif(trim(p_dados->>'notas'), '') else notas end,
    empresa_id    = case when p_dados ? 'empresa_id' then nullif(p_dados->>'empresa_id', '')::uuid else empresa_id end,
    quadro_id     = coalesce(nullif(p_dados->>'quadro_id', '')::uuid, quadro_id),
    ultimo_alerta_em = case when p_dados ? 'prazo' then null else ultimo_alerta_em end,
    concluida_em  = case when novo_status = 'feito' then coalesce(concluida_em, now()) else null end,
    atualizado_em = now()
  where id = v;

  if novo_status <> atual.status then
    perform crm.tarefa_log(v, crm.status_rotulo(atual.status) || ' → ' || crm.status_rotulo(novo_status));
    if novo_status = 'feito' and atual.criado_por is distinct from atual.responsavel_id then
      perform crm.notificar_tarefa(atual.criado_por, v, 'tarefa', 'Concluída: ' || atual.titulo);
    end if;
  end if;
  if novo_resp is distinct from atual.responsavel_id then
    perform crm.tarefa_log(v, 'Responsável: ' || coalesce((select nome from crm.perfil where user_id = novo_resp), 'ninguém'));
    perform crm.notificar_tarefa(novo_resp, v, 'tarefa', 'Tarefa atribuída a você: ' || atual.titulo);
  end if;
  if p_dados ? 'prazo' and nullif(p_dados->>'prazo', '')::date is distinct from atual.prazo then
    perform crm.tarefa_log(v, 'Prazo: ' || coalesce(to_char(nullif(p_dados->>'prazo', '')::date, 'DD/MM/YYYY'), 'sem prazo'));
  end if;
  return v;
end $$;

create or replace function public.painel_tarefa_mover(p_id uuid, p_status text, p_ordem double precision default null)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.painel_tarefa_salvar(p_id, jsonb_build_object('status', p_status));
  if p_ordem is not null then
    update crm.tarefa set ordem = p_ordem where id = p_id;
  end if;
end $$;

create or replace function public.painel_tarefa_excluir(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare eu uuid; t crm.tarefa;
begin
  eu := crm.exige_editor();
  select * into t from crm.tarefa where id = p_id;
  if t.id is null then return; end if;
  if not (t.criado_por = eu or t.responsavel_id = eu or crm.papel_atual() in ('admin','gestor')) then
    raise exception 'Só quem criou, o responsável ou um gestor exclui esta tarefa.' using errcode = '42501';
  end if;
  delete from crm.tarefa where id = p_id;
end $$;

create or replace function public.painel_tarefa_item_salvar(p_tarefa uuid, p_id uuid, p_texto text, p_feito boolean default false)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v uuid := p_id;
begin
  perform crm.exige_editor();
  if v is null then
    if nullif(trim(p_texto), '') is null then raise exception 'Escreva o item.'; end if;
    insert into crm.tarefa_item (tarefa_id, texto, feito) values (p_tarefa, trim(p_texto), coalesce(p_feito, false))
    returning id into v;
  else
    update crm.tarefa_item set texto = coalesce(nullif(trim(p_texto), ''), texto), feito = coalesce(p_feito, feito)
     where id = v and tarefa_id = p_tarefa;
  end if;
  update crm.tarefa set atualizado_em = now() where id = p_tarefa;
  return v;
end $$;

create or replace function public.painel_tarefa_item_excluir(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige_editor();
  delete from crm.tarefa_item where id = p_id;
end $$;

create or replace function public.painel_tarefa_comentar(p_id uuid, p_texto text) returns void
language plpgsql security definer set search_path = '' as $$
declare eu uuid; t crm.tarefa;
begin
  eu := crm.exige_editor();
  if nullif(trim(p_texto), '') is null then raise exception 'Escreva o comentário.'; end if;
  select * into t from crm.tarefa where id = p_id;
  if t.id is null then raise exception 'Tarefa não encontrada.'; end if;
  insert into crm.tarefa_comentario (tarefa_id, autor_id, texto) values (p_id, eu, trim(p_texto));
  perform crm.notificar_tarefa(t.responsavel_id, p_id, 'comentario', 'Comentário em: ' || t.titulo);
  if t.criado_por is distinct from t.responsavel_id then
    perform crm.notificar_tarefa(t.criado_por, p_id, 'comentario', 'Comentário em: ' || t.titulo);
  end if;
end $$;

drop function if exists public.painel_notificacoes(int);
create function public.painel_notificacoes(p_limite int default 30)
returns table (id bigint, negocio_id uuid, tarefa_id uuid, tipo text, texto text, lida_em timestamptz, criado_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := crm.exige_ativo();
  return query
    select n.id, n.negocio_id, n.tarefa_id, n.tipo, n.texto, n.lida_em, n.criado_em
      from crm.notificacao n where n.user_id = eu
     order by n.criado_em desc limit least(greatest(p_limite, 1), 100);
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
