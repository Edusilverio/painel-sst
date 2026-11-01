

alter table crm.tarefa add column if not exists responsaveis uuid[] not null default '{}';
update crm.tarefa set responsaveis = array[responsavel_id] where responsavel_id is not null and responsaveis = '{}';
create index if not exists tarefa_responsaveis_idx on crm.tarefa using gin (responsaveis);

create or replace function crm.tg_tarefa_responsaveis() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.responsaveis := coalesce(array(select u.x from unnest(new.responsaveis) with ordinality u(x, o) where u.x is not null group by u.x order by min(u.o)), '{}');
  if new.responsavel_id is not null and not (new.responsavel_id = any (new.responsaveis)) then
    new.responsaveis := array_prepend(new.responsavel_id, new.responsaveis);
  end if;
  if new.responsavel_id is null and cardinality(new.responsaveis) > 0 then
    new.responsavel_id := new.responsaveis[1];
  end if;
  return new;
end $$;
create or replace trigger trg_tarefa_responsaveis before insert or update of responsavel_id, responsaveis on crm.tarefa
  for each row execute function crm.tg_tarefa_responsaveis();

create or replace function crm.ve_tarefa(p_criador uuid, p_resps uuid[])
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(crm.papel_atual()::text = 'admin' or p_criador = auth.uid() or auth.uid() = any (coalesce(p_resps, '{}')), false)
$$;
revoke execute on function crm.ve_tarefa(uuid, uuid[]) from public, anon;
grant execute on function crm.ve_tarefa(uuid, uuid[]) to authenticated;

create or replace function crm.nomes_responsaveis(p_resps uuid[])
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.user_id, 'nome', p.nome) order by array_position(p_resps, p.user_id)), '[]'::jsonb)
    from crm.perfil p where p.user_id = any (coalesce(p_resps, '{}'))
$$;

create or replace function public.painel_tarefas_v2(p_quadro uuid, p_responsavel uuid default null, p_busca text default null)
returns table(id uuid, numero bigint, titulo text, status text, prioridade text, prazo date, responsavel_id uuid, responsavel_nome text,
              responsaveis jsonb, criado_por_nome text, notas text, empresa_id uuid, empresa text, negocio_id uuid, ordem double precision,
              itens integer, itens_feitos integer, comentarios integer, atrasada boolean, criado_em timestamptz, concluida_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform crm.exige_ativo();
  return query
    select t.id, t.numero, t.titulo, t.status, t.prioridade, t.prazo, t.responsavel_id, p.nome::text,
           crm.nomes_responsaveis(t.responsaveis), c.nome::text,
           t.notas, t.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social)::text, t.negocio_id, t.ordem,
           (select count(*)::int from crm.tarefa_item i where i.tarefa_id = t.id),
           (select count(*)::int from crm.tarefa_item i where i.tarefa_id = t.id and i.feito),
           (select count(*)::int from crm.tarefa_comentario m where m.tarefa_id = t.id and not m.sistema),
           t.status <> 'feito' and t.prazo < (now() at time zone 'America/Sao_Paulo')::date,
           t.criado_em, t.concluida_em
      from crm.tarefa t
      left join crm.perfil p on p.user_id = t.responsavel_id
      left join crm.perfil c on c.user_id = t.criado_por
      left join public.empresa e on e.id = t.empresa_id
     where t.quadro_id = p_quadro
       and crm.ve_tarefa(t.criado_por, t.responsaveis)
       and (p_responsavel is null or p_responsavel = any (t.responsaveis))
       and (termo is null or t.titulo ilike '%' || termo || '%' or t.notas ilike '%' || termo || '%')
       and (t.status <> 'feito' or t.concluida_em is null or t.concluida_em > now() - interval '60 days')
     order by t.ordem;
end $$;
revoke execute on function public.painel_tarefas_v2(uuid, uuid, text) from public, anon;
grant execute on function public.painel_tarefas_v2(uuid, uuid, text) to authenticated;

create or replace function public.painel_tarefas(p_quadro uuid, p_responsavel uuid default null, p_busca text default null)
returns table(id uuid, numero bigint, titulo text, status text, prioridade text, prazo date, responsavel_id uuid, responsavel_nome text,
              notas text, empresa_id uuid, empresa text, negocio_id uuid, ordem double precision, itens integer, itens_feitos integer,
              comentarios integer, atrasada boolean, criado_em timestamptz, concluida_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  return query
    select v.id, v.numero, v.titulo, v.status, v.prioridade, v.prazo, v.responsavel_id, v.responsavel_nome, v.notas, v.empresa_id,
           v.empresa, v.negocio_id, v.ordem, v.itens, v.itens_feitos, v.comentarios, v.atrasada, v.criado_em, v.concluida_em
      from public.painel_tarefas_v2(p_quadro, p_responsavel, p_busca) v;
end $$;

create or replace function public.painel_tarefas_quadros()
returns table(id uuid, nome text, descricao text, abertas integer, atrasadas integer)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige_ativo();
  return query
    select q.id, q.nome, q.descricao,
           (select count(*)::int from crm.tarefa t where t.quadro_id = q.id and t.status <> 'feito'
               and crm.ve_tarefa(t.criado_por, t.responsaveis)),
           (select count(*)::int from crm.tarefa t where t.quadro_id = q.id and t.status <> 'feito'
               and t.prazo < (now() at time zone 'America/Sao_Paulo')::date and crm.ve_tarefa(t.criado_por, t.responsaveis))
      from crm.quadro q where not q.arquivado order by q.ordem, q.nome;
end $$;

create or replace function public.painel_tarefa(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform crm.exige_ativo();
  select jsonb_build_object(
    'id', t.id, 'numero', t.numero, 'quadro_id', t.quadro_id, 'titulo', t.titulo, 'status', t.status,
    'prioridade', t.prioridade, 'prazo', t.prazo, 'responsavel_id', t.responsavel_id,
    'responsavel_nome', p.nome, 'responsaveis', crm.nomes_responsaveis(t.responsaveis),
    'notas', t.notas, 'empresa_id', t.empresa_id,
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
   where t.id = p_id and crm.ve_tarefa(t.criado_por, t.responsaveis);
  if r is null then raise exception 'Tarefa não encontrada.'; end if;
  return r;
end $$;

create or replace function public.painel_tarefa_salvar(p_id uuid, p_dados jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  eu uuid; v uuid := p_id; atual crm.tarefa; novo_status text;
  novos uuid[]; antes uuid[]; x uuid; tem_resps boolean;
begin
  eu := crm.exige_editor();
  if p_dados ? 'status' and p_dados->>'status' not in ('nao_iniciado','em_andamento','parado','feito') then
    raise exception 'Status inválido.';
  end if;
  if p_dados ? 'prioridade' and p_dados->>'prioridade' not in ('baixa','media','alta','critica') then
    raise exception 'Prioridade inválida.';
  end if;
  tem_resps := p_dados ? 'responsaveis' or p_dados ? 'responsavel_id';
  if p_dados ? 'responsaveis' then
    novos := coalesce(array(select (u.j #>> '{}')::uuid from jsonb_array_elements(p_dados->'responsaveis') with ordinality u(j, o)
                             where nullif(u.j #>> '{}', '') is not null group by 1 order by min(u.o)), '{}');
  elsif p_dados ? 'responsavel_id' then
    novos := case when nullif(p_dados->>'responsavel_id', '') is null then '{}'::uuid[] else array[(p_dados->>'responsavel_id')::uuid] end;
  end if;

  if v is null then
    if nullif(trim(p_dados->>'titulo'), '') is null then raise exception 'Informe o título da tarefa.'; end if;
    insert into crm.tarefa (quadro_id, titulo, status, prioridade, prazo, responsavel_id, responsaveis, notas, empresa_id, negocio_id,
                            criado_por, concluida_em)
    values ((p_dados->>'quadro_id')::uuid, trim(p_dados->>'titulo'),
            coalesce(nullif(p_dados->>'status', ''), 'nao_iniciado'), coalesce(nullif(p_dados->>'prioridade', ''), 'media'),
            nullif(p_dados->>'prazo', '')::date, novos[1], coalesce(novos, '{}'),
            nullif(trim(p_dados->>'notas'), ''), nullif(p_dados->>'empresa_id', '')::uuid,
            nullif(p_dados->>'negocio_id', '')::uuid, eu,
            case when p_dados->>'status' = 'feito' then now() end)
    returning id into v;
    perform crm.tarefa_log(v, 'Tarefa criada');
    select * into atual from crm.tarefa where id = v;
    foreach x in array atual.responsaveis loop
      perform crm.notificar_tarefa(x, v, 'tarefa', 'Nova tarefa para você: ' || atual.titulo);
    end loop;
    return v;
  end if;

  select * into atual from crm.tarefa where id = v for update;
  if atual.id is null or not crm.ve_tarefa(atual.criado_por, atual.responsaveis) then raise exception 'Tarefa não encontrada.'; end if;
  antes := atual.responsaveis;
  if not tem_resps then novos := antes; end if;
  novo_status := coalesce(nullif(p_dados->>'status', ''), atual.status);

  update crm.tarefa set
    titulo        = coalesce(nullif(trim(p_dados->>'titulo'), ''), titulo),
    status        = novo_status,
    prioridade    = coalesce(nullif(p_dados->>'prioridade', ''), prioridade),
    prazo         = case when p_dados ? 'prazo' then nullif(p_dados->>'prazo', '')::date else prazo end,
    responsavel_id = novos[1],
    responsaveis  = novos,
    notas         = case when p_dados ? 'notas' then nullif(trim(p_dados->>'notas'), '') else notas end,
    empresa_id    = case when p_dados ? 'empresa_id' then nullif(p_dados->>'empresa_id', '')::uuid else empresa_id end,
    quadro_id     = coalesce(nullif(p_dados->>'quadro_id', '')::uuid, quadro_id),
    ultimo_alerta_em = case when p_dados ? 'prazo' then null else ultimo_alerta_em end,
    concluida_em  = case when novo_status = 'feito' then coalesce(concluida_em, now()) else null end,
    atualizado_em = now()
  where id = v;

  if novo_status <> atual.status then
    perform crm.tarefa_log(v, crm.status_rotulo(atual.status) || ' → ' || crm.status_rotulo(novo_status));
    if novo_status = 'feito' and not (atual.criado_por = any (atual.responsaveis)) then
      perform crm.notificar_tarefa(atual.criado_por, v, 'tarefa', 'Concluída: ' || atual.titulo);
    end if;
  end if;
  if tem_resps and (select array_agg(y order by y) from unnest(novos) y) is distinct from (select array_agg(y order by y) from unnest(antes) y) then
    perform crm.tarefa_log(v, 'Responsáveis: ' || coalesce((select string_agg(p.nome, ', ' order by array_position(novos, p.user_id))
                                                              from crm.perfil p where p.user_id = any (novos)), 'ninguém'));
    foreach x in array novos loop
      if not (x = any (antes)) then
        perform crm.notificar_tarefa(x, v, 'tarefa', 'Tarefa atribuída a você: ' || atual.titulo);
      end if;
    end loop;
  end if;
  if p_dados ? 'prazo' and nullif(p_dados->>'prazo', '')::date is distinct from atual.prazo then
    perform crm.tarefa_log(v, 'Prazo: ' || coalesce(to_char(nullif(p_dados->>'prazo', '')::date, 'DD/MM/YYYY'), 'sem prazo'));
  end if;
  return v;
end $$;

create or replace function public.painel_minhas_tarefas()
returns table(id uuid, quadro_id uuid, quadro text, titulo text, status text, prioridade text, prazo date, atrasada boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := crm.exige_ativo();
  return query
    select t.id, t.quadro_id, q.nome, t.titulo, t.status, t.prioridade, t.prazo,
           t.prazo < (now() at time zone 'America/Sao_Paulo')::date
      from crm.tarefa t join crm.quadro q on q.id = t.quadro_id
     where eu = any (t.responsaveis) and t.status <> 'feito'
     order by t.prazo nulls last, t.ordem;
end $$;

create or replace function public.painel_tarefa_comentar(p_id uuid, p_texto text)
returns void language plpgsql security definer set search_path = '' as $$
declare eu uuid; t crm.tarefa; x uuid;
begin
  eu := crm.exige_editor();
  if nullif(trim(p_texto), '') is null then raise exception 'Escreva o comentário.'; end if;
  select * into t from crm.tarefa where id = p_id;
  if t.id is null or not crm.ve_tarefa(t.criado_por, t.responsaveis) then raise exception 'Tarefa não encontrada.'; end if;
  insert into crm.tarefa_comentario (tarefa_id, autor_id, texto) values (p_id, eu, trim(p_texto));
  foreach x in array t.responsaveis loop
    perform crm.notificar_tarefa(x, p_id, 'comentario', 'Comentário em: ' || t.titulo);
  end loop;
  if not (t.criado_por = any (t.responsaveis)) then
    perform crm.notificar_tarefa(t.criado_por, p_id, 'comentario', 'Comentário em: ' || t.titulo);
  end if;
end $$;

create or replace function crm.alertas_tarefas()
returns integer language plpgsql security definer set search_path = '' as $$
declare r record; x uuid; qtd int := 0; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  for r in
    select t.id, t.titulo, t.prazo, t.responsaveis from crm.tarefa t
     where t.status <> 'feito' and t.prazo is not null and t.prazo <= hoje
       and cardinality(t.responsaveis) > 0 and t.ultimo_alerta_em is distinct from hoje
  loop
    foreach x in array r.responsaveis loop
      insert into crm.notificacao (user_id, tarefa_id, tipo, texto)
      values (x, r.id, 'prazo', case when r.prazo = hoje then 'Vence hoje: ' else 'Atrasada: ' end || r.titulo);
      qtd := qtd + 1;
    end loop;
    update crm.tarefa set ultimo_alerta_em = hoje where id = r.id;
  end loop;
  return qtd;
end $$;
