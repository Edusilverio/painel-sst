

create table if not exists crm.atestado_regra (
  id          boolean primary key default true check (id),
  limite      int not null default 5 check (limite between 1 and 100),
  prazo_dias  int not null default 3 check (prazo_dias between 0 and 60),
  ativo       boolean not null default true
);
insert into crm.atestado_regra (id) values (true) on conflict (id) do nothing;

create table if not exists crm.atestado (
  id                uuid primary key default gen_random_uuid(),
  numero            bigint generated always as identity unique,
  empresa_id        uuid references public.empresa(id) on delete set null,
  colaborador_id    uuid references public.colaborador(id) on delete set null,
  colaborador_nome  text,
  colaborador_cpf   text,
  data_emissao      date,
  data_inicio       date,
  dias              int check (dias is null or dias between 0 and 3650),
  cid               text,
  medico            text,
  medico_crm        text,
  arquivo_path      text,
  arquivo_nome      text,
  origem            text not null default 'painel' check (origem in ('painel','whatsapp')),
  wa_telefone       text,
  wa_mensagem_id    text,
  leitura_ia        jsonb,
  situacao          text not null default 'ok' check (situacao in ('ok','revisar','descartado')),
  observacao        text,
  mes               date not null,
  criado_por        uuid,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);
create index if not exists atestado_empresa_mes_idx on crm.atestado (empresa_id, mes) where situacao = 'ok';
create index if not exists atestado_situacao_idx on crm.atestado (situacao, criado_em desc);
create unique index if not exists atestado_wa_msg_uq on crm.atestado (wa_mensagem_id) where wa_mensagem_id is not null;

create table if not exists crm.atestado_alerta (
  empresa_id   uuid not null references public.empresa(id) on delete cascade,
  mes          date not null,
  quantidade   int not null,
  responsavel_id uuid references crm.perfil(user_id) on delete set null,
  tarefa_id    uuid references crm.tarefa(id) on delete set null,
  negocio_id   uuid references crm.negocio(id) on delete set null,
  criado_em    timestamptz not null default now(),
  primary key (empresa_id, mes)
);

create table if not exists crm.wa_saida (
  id           bigint generated always as identity primary key,
  telefone     text not null,
  texto        text not null,
  origem       text not null,
  ref_id       text,
  status       text not null default 'pendente' check (status in ('pendente','enviado','erro','cancelado')),
  tentativas   int not null default 0,
  erro         text,
  criado_em    timestamptz not null default now(),
  enviado_em   timestamptz
);
create index if not exists wa_saida_pend_idx on crm.wa_saida (criado_em) where status = 'pendente';

alter table crm.atestado_regra  enable row level security;
alter table crm.atestado        enable row level security;
alter table crm.atestado_alerta enable row level security;
alter table crm.wa_saida        enable row level security;

insert into crm.etapa (funil_id, nome, ordem, tipo, cor, alerta_dias)
select f.id, 'Agendar consulta', 3, 'aberta', 'warning', 3 from crm.funil f where f.slug = 'pos-venda'
on conflict (funil_id, nome) do nothing;

insert into crm.quadro (nome, descricao, ordem)
select 'Atestados', 'Tarefas abertas pelo alerta de atestados (5 no mês por empresa).', 10
 where not exists (select 1 from crm.quadro where nome = 'Atestados');

create or replace function crm.atestado_mes(p_inicio date, p_emissao date, p_criado timestamptz) returns date
language sql immutable set search_path = '' as $$
  select date_trunc('month', coalesce(p_inicio, p_emissao, (p_criado at time zone 'America/Sao_Paulo')::date))::date
$$;

create or replace function crm.tg_atestado_antes() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.mes := crm.atestado_mes(new.data_inicio, new.data_emissao, coalesce(new.criado_em, now()));
  new.colaborador_cpf := crm.so_digitos(new.colaborador_cpf);
  new.cid := nullif(upper(btrim(new.cid)), '');
  new.atualizado_em := now();

  if new.empresa_id is null and new.situacao = 'ok' then new.situacao := 'revisar'; end if;

  if new.colaborador_id is not null then
    select coalesce(new.colaborador_nome, c.nome), coalesce(new.colaborador_cpf, c.cpf), coalesce(new.empresa_id, c.empresa_id)
      into new.colaborador_nome, new.colaborador_cpf, new.empresa_id
      from public.colaborador c where c.id = new.colaborador_id;
  elsif new.empresa_id is not null and new.colaborador_cpf is not null then
    select c.id, coalesce(new.colaborador_nome, c.nome) into new.colaborador_id, new.colaborador_nome
      from public.colaborador c where c.empresa_id = new.empresa_id and c.cpf = new.colaborador_cpf
     order by c.data_demissao nulls first limit 1;
  end if;
  return new;
end $$;

drop trigger if exists atestado_antes on crm.atestado;
create trigger atestado_antes before insert or update on crm.atestado
  for each row execute function crm.tg_atestado_antes();

create or replace function crm.atestado_verificar(p_empresa uuid, p_mes date) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  r crm.atestado_regra; qtd int; resp uuid; v_nome text; rotulo text; v_tarefa uuid; v_neg uuid;
  v_funil uuid; v_etapa uuid; v_quadro uuid; tel text; lista text;
begin
  if p_empresa is null or p_mes is null then return false; end if;
  select * into r from crm.atestado_regra where id;
  if not r.ativo then return false; end if;
  select count(*) into qtd from crm.atestado where empresa_id = p_empresa and mes = p_mes and situacao = 'ok';

  if exists (select 1 from crm.atestado_alerta where empresa_id = p_empresa and mes = p_mes) then
    update crm.atestado_alerta set quantidade = qtd where empresa_id = p_empresa and mes = p_mes and quantidade <> qtd;
    return false;
  end if;
  if qtd < r.limite then return false; end if;

  select coalesce(nullif(e.nome_fantasia, ''), e.razao_social) into v_nome from public.empresa e where e.id = p_empresa;
  rotulo := to_char(p_mes, 'MM/YYYY');
  resp := coalesce(crm.responsavel_cliente(p_empresa),
                   (select p.user_id from crm.perfil p where p.ativo and p.papel = 'gestor' order by p.nome limit 1));
  select string_agg(coalesce(a.colaborador_nome, '(sem nome)') || coalesce(' — ' || to_char(a.data_inicio, 'DD/MM'), '')
                    || coalesce(' (' || a.dias || ' dia' || case when a.dias = 1 then '' else 's' end || ')', ''), E'\n' order by a.data_inicio nulls last, a.criado_em)
    into lista from crm.atestado a where a.empresa_id = p_empresa and a.mes = p_mes and a.situacao = 'ok';

  select id into v_quadro from crm.quadro where nome = 'Atestados' and not arquivado order by criado_em limit 1;
  if v_quadro is not null then
    insert into crm.tarefa (quadro_id, titulo, prioridade, prazo, responsavel_id, notas, empresa_id)
    values (v_quadro, 'Agendar consulta: ' || v_nome || ' (' || qtd || ' atestados em ' || rotulo || ')', 'alta',
            (now() at time zone 'America/Sao_Paulo')::date + r.prazo_dias, resp,
            'A empresa chegou a ' || qtd || ' atestados em ' || rotulo || '. Entrar em contato para agendar consulta médica.' || E'\n\nAtestados:\n' || lista,
            p_empresa)
    returning id into v_tarefa;
  end if;

  select f.id into v_funil from crm.funil f where f.slug = 'pos-venda';
  select e.id into v_etapa from crm.etapa e where e.funil_id = v_funil and e.nome = 'Agendar consulta' and e.ativo;
  if v_etapa is not null then
    insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, responsavel_id, valor, origem, observacao)
    values (v_funil, v_etapa, 'Atestados ' || rotulo || ': ' || v_nome, p_empresa, resp, 0, 'atestados',
            qtd || ' atestados em ' || rotulo || '. Agendar consulta médica com a empresa.')
    returning id into v_neg;
    insert into crm.evento (negocio_id, tipo, texto) values (v_neg, 'criado', 'Aberto pelo alerta de atestados (' || qtd || ' em ' || rotulo || ')');
    if v_tarefa is not null then update crm.tarefa set negocio_id = v_neg where id = v_tarefa; end if;
  end if;

  if resp is not null then
    insert into crm.notificacao (user_id, negocio_id, tarefa_id, tipo, texto)
    values (resp, v_neg, v_tarefa, 'atestados', v_nome || ': ' || qtd || ' atestados em ' || rotulo || ' — agendar consulta médica');

    select crm.so_digitos(p.telefone) into tel from crm.perfil p where p.user_id = resp;
    if length(tel) in (10, 11) then tel := '55' || tel; end if;
    if tel is not null then
      insert into crm.wa_saida (telefone, texto, origem, ref_id)
      values (tel, 'Vitalis Painel: ' || v_nome || ' chegou a ' || qtd || ' atestados em ' || rotulo
                   || '. Agendar consulta médica com a empresa. A tarefa já está no seu painel.', 'atestados', p_empresa::text);
    end if;
  end if;

  insert into crm.atestado_alerta (empresa_id, mes, quantidade, responsavel_id, tarefa_id, negocio_id)
  values (p_empresa, p_mes, qtd, resp, v_tarefa, v_neg);
  return true;
end $$;

create or replace function crm.tg_atestado_depois() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.empresa_id is distinct from old.empresa_id or new.mes is distinct from old.mes
     or new.situacao is distinct from old.situacao then
    perform crm.atestado_verificar(new.empresa_id, new.mes);
    if tg_op = 'UPDATE' and (old.empresa_id, old.mes) is distinct from (new.empresa_id, new.mes) then
      perform crm.atestado_verificar(old.empresa_id, old.mes);
    end if;
  end if;
  return null;
end $$;

drop trigger if exists atestado_depois on crm.atestado;
create trigger atestado_depois after insert or update on crm.atestado
  for each row execute function crm.tg_atestado_depois();

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit)
    values ('atestados', 'atestados', false, 15728640)
    on conflict (id) do nothing;
    execute 'drop policy if exists "atestados_ler" on storage.objects';
    execute 'drop policy if exists "atestados_enviar" on storage.objects';
    execute 'drop policy if exists "atestados_apagar" on storage.objects';
    execute $p$create policy "atestados_ler" on storage.objects for select to authenticated
      using (bucket_id = 'atestados' and public.painel_papel_em(array['gestor','operacoes']))$p$;
    execute $p$create policy "atestados_enviar" on storage.objects for insert to authenticated
      with check (bucket_id = 'atestados' and public.painel_papel_em(array['gestor','operacoes']))$p$;
    execute $p$create policy "atestados_apagar" on storage.objects for delete to authenticated
      using (bucket_id = 'atestados' and public.painel_papel_em(array['gestor']))$p$;
  end if;
end $$;

create or replace function public.painel_atestados_resumo(p_mes date default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare m date := date_trunc('month', coalesce(p_mes, (now() at time zone 'America/Sao_Paulo')::date))::date; r crm.atestado_regra;
begin
  perform crm.exige('gestor','operacoes');
  select * into r from crm.atestado_regra where id;
  return jsonb_build_object(
    'mes', m, 'limite', r.limite, 'prazo_dias', r.prazo_dias, 'ativo', r.ativo,
    'total', (select count(*) from crm.atestado where mes = m and situacao = 'ok'),
    'empresas', (select count(distinct empresa_id) from crm.atestado where mes = m and situacao = 'ok'),
    'alertas', (select count(*) from crm.atestado_alerta where mes = m),
    'revisar', (select count(*) from crm.atestado where situacao = 'revisar'),
    'ranking', coalesce((
      select jsonb_agg(x order by x.quantidade desc, x.nome) from (
        select a.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social) nome, count(*) quantidade,
               coalesce(sum(a.dias), 0) dias, exists (select 1 from crm.atestado_alerta al where al.empresa_id = a.empresa_id and al.mes = m) alertado
          from crm.atestado a join public.empresa e on e.id = a.empresa_id
         where a.mes = m and a.situacao = 'ok'
         group by a.empresa_id, e.nome_fantasia, e.razao_social
         order by count(*) desc limit 15) x), '[]'::jsonb));
end $$;

create or replace function public.painel_atestados(p_mes date default null, p_empresa uuid default null, p_situacao text default null,
                                                   p_busca text default null, p_limite int default 100, p_offset int default 0)
returns table (id uuid, numero bigint, empresa_id uuid, empresa text, colaborador_id uuid, colaborador text, cpf text,
               data_emissao date, data_inicio date, dias int, cid text, medico text, medico_crm text, origem text, wa_telefone text,
               situacao text, observacao text, arquivo_path text, arquivo_nome text, mes date, criado_em timestamptz, total bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform crm.exige('gestor','operacoes');
  return query
    select a.id, a.numero, a.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social), a.colaborador_id, a.colaborador_nome,
           a.colaborador_cpf, a.data_emissao, a.data_inicio, a.dias, a.cid, a.medico, a.medico_crm, a.origem, a.wa_telefone,
           a.situacao, a.observacao, a.arquivo_path, a.arquivo_nome, a.mes, a.criado_em, count(*) over ()
      from crm.atestado a left join public.empresa e on e.id = a.empresa_id
     where (p_mes is null or a.mes = date_trunc('month', p_mes)::date)
       and (p_empresa is null or a.empresa_id = p_empresa)
       and (case when p_situacao is null then a.situacao <> 'descartado' else a.situacao = p_situacao end)
       and (termo is null or a.colaborador_nome ilike '%' || termo || '%' or a.colaborador_cpf like '%' || crm.so_digitos(termo) || '%'
            or e.razao_social ilike '%' || termo || '%' or e.nome_fantasia ilike '%' || termo || '%')
     order by (a.situacao = 'revisar') desc, a.criado_em desc
     limit least(greatest(p_limite, 1), 500) offset greatest(p_offset, 0);
end $$;

create or replace function public.painel_atestado_salvar(p_id uuid, p_dados jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare uid uuid := crm.exige('gestor','operacoes'); v uuid; antes crm.atestado;
begin
  if p_id is null then
    insert into crm.atestado (empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, data_emissao, data_inicio, dias, cid,
                              medico, medico_crm, observacao, situacao, origem, criado_por)
    values (nullif(p_dados->>'empresa_id', '')::uuid, nullif(p_dados->>'colaborador_id', '')::uuid,
            nullif(btrim(p_dados->>'colaborador_nome'), ''), nullif(p_dados->>'colaborador_cpf', ''),
            nullif(p_dados->>'data_emissao', '')::date, nullif(p_dados->>'data_inicio', '')::date, nullif(p_dados->>'dias', '')::int,
            nullif(p_dados->>'cid', ''), nullif(btrim(p_dados->>'medico'), ''), nullif(btrim(p_dados->>'medico_crm'), ''),
            nullif(btrim(p_dados->>'observacao'), ''), coalesce(nullif(p_dados->>'situacao', ''), 'ok'), 'painel', uid)
    returning id into v;
    insert into crm.edicao (tabela, registro_id, usuario_id, acao, mudancas)
    values ('atestado', v, uid, 'criar', (select jsonb_object_agg(k, jsonb_build_object('de', null, 'para', x))
                                            from jsonb_each(p_dados - 'cid') e(k, x) where x <> 'null'::jsonb and x <> '""'::jsonb));
    return v;
  end if;
  select * into antes from crm.atestado where id = p_id;
  if antes.id is null then raise exception 'Atestado não encontrado.'; end if;
  update crm.atestado set
    empresa_id       = case when p_dados ? 'empresa_id' then nullif(p_dados->>'empresa_id', '')::uuid else empresa_id end,
    colaborador_id   = case when p_dados ? 'colaborador_id' then nullif(p_dados->>'colaborador_id', '')::uuid else colaborador_id end,
    colaborador_nome = case when p_dados ? 'colaborador_nome' then nullif(btrim(p_dados->>'colaborador_nome'), '') else colaborador_nome end,
    colaborador_cpf  = case when p_dados ? 'colaborador_cpf' then nullif(p_dados->>'colaborador_cpf', '') else colaborador_cpf end,
    data_emissao     = case when p_dados ? 'data_emissao' then nullif(p_dados->>'data_emissao', '')::date else data_emissao end,
    data_inicio      = case when p_dados ? 'data_inicio' then nullif(p_dados->>'data_inicio', '')::date else data_inicio end,
    dias             = case when p_dados ? 'dias' then nullif(p_dados->>'dias', '')::int else dias end,
    cid              = case when p_dados ? 'cid' then nullif(p_dados->>'cid', '') else cid end,
    medico           = case when p_dados ? 'medico' then nullif(btrim(p_dados->>'medico'), '') else medico end,
    medico_crm       = case when p_dados ? 'medico_crm' then nullif(btrim(p_dados->>'medico_crm'), '') else medico_crm end,
    observacao       = case when p_dados ? 'observacao' then nullif(btrim(p_dados->>'observacao'), '') else observacao end,
    situacao         = case when p_dados ? 'situacao' then p_dados->>'situacao'
                            when antes.situacao = 'revisar' and p_dados ? 'empresa_id' and nullif(p_dados->>'empresa_id', '') is not null then 'ok'
                            else situacao end
   where id = p_id;
  insert into crm.edicao (tabela, registro_id, usuario_id, acao, mudancas)
  select 'atestado', p_id, uid, 'editar', jsonb_object_agg(k, case when k = 'cid' then jsonb_build_object('de', '(oculto)', 'para', '(alterado)')
                                                                    else jsonb_build_object('de', a.j -> k, 'para', d.j -> k) end)
    from (select to_jsonb(antes) j) a, (select to_jsonb(t) j from crm.atestado t where t.id = p_id) d,
         jsonb_object_keys(p_dados) k
   where (a.j -> k) is distinct from (d.j -> k)
  having count(*) > 0;
  return p_id;
end $$;

create or replace function public.painel_atestado_arquivo(p_id uuid, p_path text, p_nome text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('gestor','operacoes');
  update crm.atestado set arquivo_path = p_path, arquivo_nome = p_nome where id = p_id;
end $$;

create or replace function public.painel_atestado_regra_salvar(p_limite int, p_prazo_dias int, p_ativo boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('gestor');
  update crm.atestado_regra set limite = p_limite, prazo_dias = p_prazo_dias, ativo = p_ativo where id;
end $$;

create or replace function public.integracao_atestado_receber(p_token text, p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare h text; emp uuid; v uuid; num bigint; sit text; qtd int; m date;
begin
  select token_hash into h from crm.wa_config where id;
  if h is null or p_token is null or encode(extensions.digest(p_token, 'sha256'), 'hex') <> h then
    raise exception 'Token inválido.' using errcode = '42501';
  end if;
  if nullif(p_dados->>'mensagem_id', '') is not null then
    select id, numero, situacao into v, num, sit from crm.atestado where wa_mensagem_id = p_dados->>'mensagem_id';
    if v is not null then return jsonb_build_object('id', v, 'numero', num, 'situacao', sit, 'repetido', true); end if;
  end if;
  if length(crm.so_digitos(p_dados->>'cnpj')) = 14 then
    select e.id into emp from public.empresa e where crm.so_digitos(e.cnpj) = crm.so_digitos(p_dados->>'cnpj')
     order by (e.situacao = 'ativo') desc nulls last limit 1;
  end if;
  emp := coalesce(emp, crm.wa_empresa_por_telefone(p_dados->>'telefone'));

  insert into crm.atestado (empresa_id, colaborador_nome, colaborador_cpf, data_emissao, data_inicio, dias, cid, medico, medico_crm,
                            arquivo_path, arquivo_nome, origem, wa_telefone, wa_mensagem_id, leitura_ia, situacao, observacao)
  values (emp, nullif(btrim(p_dados->>'colaborador_nome'), ''), nullif(p_dados->>'colaborador_cpf', ''),
          nullif(p_dados->>'data_emissao', '')::date, nullif(p_dados->>'data_inicio', '')::date, nullif(p_dados->>'dias', '')::int,
          nullif(p_dados->>'cid', ''), nullif(btrim(p_dados->>'medico'), ''), nullif(btrim(p_dados->>'medico_crm'), ''),
          nullif(p_dados->>'arquivo_path', ''), nullif(p_dados->>'arquivo_nome', ''), 'whatsapp',
          crm.so_digitos(p_dados->>'telefone'), nullif(p_dados->>'mensagem_id', ''), p_dados->'leitura_ia',
          case when emp is null or nullif(p_dados->>'colaborador_nome', '') is null then 'revisar' else 'ok' end,
          case when emp is null then 'Empresa não identificada pelo telefone/CNPJ: ' || coalesce(p_dados->>'empresa', p_dados->>'telefone', '?') end)
  returning id, numero, situacao, mes into v, num, sit, m;
  select count(*) into qtd from crm.atestado where empresa_id = emp and mes = m and situacao = 'ok';
  return jsonb_build_object('id', v, 'numero', num, 'situacao', sit, 'empresa_identificada', emp is not null,
                            'atestados_no_mes', case when emp is not null then qtd end);
end $$;

create or replace function public.integracao_token_valido(p_token text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') from crm.wa_config where id), false)
$$;
revoke execute on function public.integracao_token_valido(text) from public, anon, authenticated;

create or replace function public.integracao_wa_saida(p_token text, p_resultados jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare h text; r jsonb;
begin
  select token_hash into h from crm.wa_config where id;
  if h is null or p_token is null or encode(extensions.digest(p_token, 'sha256'), 'hex') <> h then
    raise exception 'Token inválido.' using errcode = '42501';
  end if;

  for r in select * from jsonb_array_elements(coalesce(p_resultados, '[]'::jsonb)) loop
    update crm.wa_saida set
      status = case when (r->>'ok')::boolean then 'enviado' when tentativas + 1 >= 3 then 'erro' else 'pendente' end,
      tentativas = tentativas + 1, erro = r->>'erro',
      enviado_em = case when (r->>'ok')::boolean then now() end
     where id = (r->>'id')::bigint and status = 'pendente';
  end loop;

  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'telefone', s.telefone, 'texto', s.texto) order by s.id)
                     from (select * from crm.wa_saida where status = 'pendente' order by id limit 20) s), '[]'::jsonb);
end $$;

revoke execute on function crm.atestado_mes(date, date, timestamptz), crm.tg_atestado_antes(), crm.atestado_verificar(uuid, date),
  crm.tg_atestado_depois() from public, anon, authenticated;
revoke execute on function public.painel_atestados_resumo(date), public.painel_atestados(date, uuid, text, text, int, int),
  public.painel_atestado_salvar(uuid, jsonb), public.painel_atestado_arquivo(uuid, text, text),
  public.painel_atestado_regra_salvar(int, int, boolean) from public, anon;
grant execute on function public.painel_atestados_resumo(date), public.painel_atestados(date, uuid, text, text, int, int),
  public.painel_atestado_salvar(uuid, jsonb), public.painel_atestado_arquivo(uuid, text, text),
  public.painel_atestado_regra_salvar(int, int, boolean) to authenticated;
revoke execute on function public.integracao_atestado_receber(text, jsonb), public.integracao_wa_saida(text, jsonb) from public;
grant execute on function public.integracao_atestado_receber(text, jsonb), public.integracao_wa_saida(text, jsonb) to anon, authenticated;

create or replace function public.painel_auditoria(
  p_origem text default null,
  p_usuario uuid default null,
  p_de date default null,
  p_ate date default null,
  p_busca text default null,
  p_limite int default 100,
  p_offset int default 0
) returns table (em timestamptz, origem text, usuario_id uuid, usuario text, acao text, entidade text,
                 registro_id uuid, registro text, detalhe jsonb, total bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform crm.exige('admin');
  return query
    with ed as (
      select e.em, 'cadastro'::text origem, e.usuario_id, e.acao, e.tabela entidade, e.registro_id,
             coalesce(
               case e.tabela
                 when 'empresa' then (select coalesce(nullif(x.nome_fantasia, ''), x.razao_social) from public.empresa x where x.id = e.registro_id)
                 when 'colaborador' then (select x.nome || ' — ' || coalesce(nullif(em.nome_fantasia, ''), em.razao_social)
                                            from public.colaborador x join public.empresa em on em.id = x.empresa_id where x.id = e.registro_id)
                 when 'unidade' then (select x.nome from public.unidade x where x.id = e.registro_id)
                 when 'empresa_contato' then (select coalesce(x.nome, '(contato)') from public.empresa_contato x where x.id = e.registro_id)
                 when 'atestado' then (select 'Atestado #' || x.numero || coalesce(' — ' || x.colaborador_nome, '')
                                        from crm.atestado x where x.id = e.registro_id)
                 when 'atendimento' then (select c.nome || ' — ' || to_char(a.data_atendimento, 'DD/MM/YYYY')
                                            from public.atendimento a join public.colaborador c on c.id = a.colaborador_id where a.id = e.registro_id)
               end,
               e.mudancas #>> '{registro,nome}', '(registro removido)') registro,
             e.mudancas detalhe
        from crm.edicao e
       where (p_origem is null or p_origem = 'cadastro')
    ), ev as (
      select v.criado_em em, 'crm'::text, v.autor_id, v.tipo, 'negocio'::text, v.negocio_id,
             '#' || n.numero || ' ' || n.titulo || ' (' || f.nome || ')',
             jsonb_build_object('texto', v.texto, 'de', de.nome, 'para', pa.nome)
        from crm.evento v
        join crm.negocio n on n.id = v.negocio_id
        join crm.funil f on f.id = n.funil_id
        left join crm.etapa de on de.id = v.de_etapa_id
        left join crm.etapa pa on pa.id = v.para_etapa_id
       where (p_origem is null or p_origem = 'crm') and v.autor_id is not null
    ), tudo as (
      select * from ed union all select * from ev
    )
    select t.em, t.origem, t.usuario_id, coalesce(p.nome, u.email)::text, t.acao, t.entidade, t.registro_id, t.registro, t.detalhe,
           count(*) over ()
      from tudo t
      left join crm.perfil p on p.user_id = t.usuario_id
      left join auth.users u on u.id = t.usuario_id
     where (p_usuario is null or t.usuario_id = p_usuario)
       and (p_de is null or t.em >= p_de::timestamp at time zone 'America/Sao_Paulo')
       and (p_ate is null or t.em < (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo')
       and (termo is null or t.registro ilike '%' || termo || '%' or coalesce(p.nome, '') ilike '%' || termo || '%')
     order by t.em desc
     limit least(greatest(p_limite, 1), 500) offset greatest(p_offset, 0);
end $$;

