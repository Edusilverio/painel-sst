

create table if not exists crm.agenda_regra (
  id                    boolean primary key default true check (id),
  limite_empresa_dia    int check (limite_empresa_dia > 0),
  bloquear_inadimplente boolean not null default true,
  vagas_padrao          int not null default 40 check (vagas_padrao between 1 and 500),
  hora_inicio_padrao    time not null default '07:00',
  hora_fim_padrao       time not null default '11:30',
  atualizado_em         timestamptz not null default now(),
  atualizado_por        uuid
);
insert into crm.agenda_regra (id) values (true) on conflict do nothing;

create table if not exists crm.agenda (
  id               uuid primary key default gen_random_uuid(),
  data             date not null,
  profissional_id  uuid references public.profissional(id) on delete restrict,
  local            text not null default 'clinica' check (local in ('clinica','in_company')),
  empresa_id       uuid references public.empresa(id) on delete restrict,
  hora_inicio      time,
  hora_fim         time,
  vagas            int not null check (vagas between 1 and 500),
  observacao       text,
  criado_por       uuid,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  constraint agenda_in_company_tem_empresa check (local = 'clinica' or empresa_id is not null),
  constraint agenda_horario check (hora_inicio is null or hora_fim is null or hora_fim > hora_inicio)
);
create index if not exists agenda_data_idx on crm.agenda (data, profissional_id);

create table if not exists crm.agendamento (
  id               uuid primary key default gen_random_uuid(),
  numero           bigint generated always as identity unique,
  agenda_id        uuid not null references crm.agenda(id) on delete restrict,
  horario          time,
  empresa_id       uuid references public.empresa(id) on delete set null,
  empresa_nome     text,
  colaborador_id   uuid references public.colaborador(id) on delete set null,
  paciente_nome    text not null check (length(trim(paciente_nome)) > 1),
  cpf              text,
  telefone         text,
  funcao           text,
  tipo             text not null default 'periodico' check (tipo in
                     ('admissional','periodico','demissional','mudanca_de_funcao',
                      'retorno_ao_trabalho','monitoracao_pontual','outro')),
  situacao         text not null default 'agendado' check (situacao in
                     ('agendado','aguardando','atendido','finalizado','cancelado','faltou')),
  encaixe          boolean not null default false,
  excecao_motivo   text,
  cancelado_motivo text,
  negocio_id       uuid references crm.negocio(id) on delete set null,
  observacao       text,
  chegou_em        timestamptz,
  atendido_em      timestamptz,
  finalizado_em    timestamptz,
  criado_por       uuid,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  constraint agendamento_tem_empresa check (empresa_id is not null or nullif(trim(empresa_nome), '') is not null)
);
create index if not exists agendamento_agenda_idx on crm.agendamento (agenda_id, situacao);
create index if not exists agendamento_empresa_idx on crm.agendamento (empresa_id);

create table if not exists crm.agendamento_evento (
  id              bigint generated always as identity primary key,
  agendamento_id  uuid not null references crm.agendamento(id) on delete cascade,
  texto           text not null,
  autor_id        uuid,
  criado_em       timestamptz not null default now()
);
create index if not exists agendamento_evento_idx on crm.agendamento_evento (agendamento_id, criado_em);

alter table crm.agenda_regra       enable row level security;
alter table crm.agenda             enable row level security;
alter table crm.agendamento        enable row level security;
alter table crm.agendamento_evento enable row level security;

create or replace function crm.agenda_rotulo(p_situacao text) returns text
language sql immutable set search_path = '' as $$
  select case p_situacao
    when 'agendado' then 'Agendado' when 'aguardando' then 'Aguardando'
    when 'atendido' then 'Atendido' when 'finalizado' then 'Finalizado'
    when 'cancelado' then 'Cancelado' when 'faltou' then 'Faltou' else p_situacao end
$$;

create or replace function crm.agenda_registrar(p_agendamento uuid, p_texto text) returns void
language sql security definer set search_path = '' as $$
  insert into crm.agendamento_evento (agendamento_id, texto, autor_id) values (p_agendamento, p_texto, auth.uid())
$$;

create or replace function crm.empresa_inadimplente(p_empresa uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from crm.negocio n
      join crm.etapa e on e.id = n.etapa_id
      join crm.funil f on f.id = n.funil_id
     where n.empresa_id = p_empresa and f.slug = 'pos-venda'
       and e.tipo = 'aberta' and e.nome ilike 'inadimpl%')
$$;

create or replace function crm.agenda_checar(p_agenda uuid, p_empresa uuid, p_encaixe boolean,
                                             p_ignorar uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  a crm.agenda; r crm.agenda_regra;
  ocupadas int; na_empresa int := 0; inad boolean := false; sit text;
  bloqueios text[] := '{}'; avisos text[] := '{}';
begin
  select * into a from crm.agenda where id = p_agenda;
  if a.id is null then raise exception 'Agenda não encontrada.'; end if;
  select * into r from crm.agenda_regra where id;

  select count(*) into ocupadas from crm.agendamento g
   where g.agenda_id = a.id and not g.encaixe and g.situacao not in ('cancelado','faltou')
     and g.id is distinct from p_ignorar;

  if ocupadas >= a.vagas then
    if coalesce(p_encaixe, false) then
      avisos := array_append(avisos, format('Agenda lotada (%s/%s): entra como encaixe.', ocupadas, a.vagas));
    else
      bloqueios := array_append(bloqueios, format('Agenda lotada (%s/%s vagas). Marque como encaixe para incluir.', ocupadas, a.vagas));
    end if;
  end if;

  if p_empresa is not null then
    select count(*) into na_empresa from crm.agendamento g join crm.agenda ag on ag.id = g.agenda_id
     where ag.data = a.data and g.empresa_id = p_empresa and g.situacao not in ('cancelado','faltou')
       and g.id is distinct from p_ignorar;
    if r.limite_empresa_dia is not null and na_empresa >= r.limite_empresa_dia
       and a.local = 'clinica' then
      bloqueios := array_append(bloqueios, format('Esta empresa já tem %s agendado(s) em %s (limite %s por dia).',
                                       na_empresa, to_char(a.data, 'DD/MM'), r.limite_empresa_dia));
    elsif na_empresa > 0 then
      avisos := array_append(avisos, format('Esta empresa já tem %s agendado(s) neste dia.', na_empresa));
    end if;

    inad := crm.empresa_inadimplente(p_empresa);
    if inad and r.bloquear_inadimplente then
      bloqueios := array_append(bloqueios, 'Empresa inadimplente (Pós-venda → Inadimplentes). Fale com o financeiro.');
    elsif inad then
      avisos := array_append(avisos, 'Empresa marcada como inadimplente no Pós-venda.');
    end if;

    select e.situacao::text into sit from public.empresa e where e.id = p_empresa;
    if sit in ('inativo','sem_contrato') then
      avisos := array_append(avisos, case sit when 'inativo' then 'Empresa inativa no cadastro.'
                                   else 'Empresa sem contrato vigente.' end);
    end if;
  end if;

  if a.data < (now() at time zone 'America/Sao_Paulo')::date then
    avisos := array_append(avisos, 'Data já passou.');
  end if;

  return jsonb_build_object('vagas', a.vagas, 'ocupadas', ocupadas, 'empresa_no_dia', na_empresa,
                            'limite_empresa_dia', r.limite_empresa_dia, 'inadimplente', inad,
                            'bloqueios', to_jsonb(bloqueios), 'avisos', to_jsonb(avisos));
end $$;

revoke execute on function crm.agenda_registrar(uuid, text), crm.empresa_inadimplente(uuid),
  crm.agenda_checar(uuid, uuid, boolean, uuid) from public, anon, authenticated;

create or replace function public.painel_agenda_regras() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform crm.exige('gestor','operacoes','comercial');
  return (select jsonb_build_object('limite_empresa_dia', r.limite_empresa_dia,
                                    'bloquear_inadimplente', r.bloquear_inadimplente,
                                    'vagas_padrao', r.vagas_padrao,
                                    'hora_inicio_padrao', to_char(r.hora_inicio_padrao, 'HH24:MI'),
                                    'hora_fim_padrao', to_char(r.hora_fim_padrao, 'HH24:MI'),
                                    'pode_configurar', crm.papel_atual() in ('admin','gestor','operacoes'),
                                    'pode_excecao', crm.papel_atual() in ('admin','gestor'))
            from crm.agenda_regra r where r.id);
end $$;

create or replace function public.painel_profissionais()
returns table (id uuid, nome text, tipo text, conselho text, registro text, ativo boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige('gestor','operacoes','comercial');
  return query
    select p.id, p.nome::text, p.tipo::text, p.conselho::text, p.registro::text, p.ativo
      from public.profissional p order by not p.ativo, p.nome;
end $$;

create or replace function public.painel_agenda_periodo(p_de date, p_ate date)
returns table (id uuid, data date, profissional_id uuid, profissional text, local text,
               empresa_id uuid, empresa text, hora_inicio text, hora_fim text, vagas int,
               ocupadas int, encaixes int, agendados int, aguardando int, atendidos int,
               finalizados int, faltas int, cancelados int, observacao text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige('gestor','operacoes','comercial');
  if p_ate < p_de or p_ate - p_de > 62 then
    raise exception 'Período inválido (máximo de 62 dias).';
  end if;
  return query
    select a.id, a.data, a.profissional_id, p.nome::text, a.local, a.empresa_id,
           coalesce(nullif(e.nome_fantasia, ''), e.razao_social)::text,
           to_char(a.hora_inicio, 'HH24:MI'), to_char(a.hora_fim, 'HH24:MI'), a.vagas,
           count(g.id) filter (where not g.encaixe and g.situacao not in ('cancelado','faltou'))::int,
           count(g.id) filter (where g.encaixe and g.situacao not in ('cancelado','faltou'))::int,
           count(g.id) filter (where g.situacao = 'agendado')::int,
           count(g.id) filter (where g.situacao = 'aguardando')::int,
           count(g.id) filter (where g.situacao = 'atendido')::int,
           count(g.id) filter (where g.situacao = 'finalizado')::int,
           count(g.id) filter (where g.situacao = 'faltou')::int,
           count(g.id) filter (where g.situacao = 'cancelado')::int,
           a.observacao
      from crm.agenda a
      left join public.profissional p on p.id = a.profissional_id
      left join public.empresa e on e.id = a.empresa_id
      left join crm.agendamento g on g.agenda_id = a.id
     where a.data between p_de and p_ate
     group by a.id, p.nome, e.nome_fantasia, e.razao_social
     order by a.data, a.hora_inicio nulls last, p.nome;
end $$;

create or replace function public.painel_agenda_dia(p_data date, p_agenda uuid default null)
returns table (id uuid, numero bigint, agenda_id uuid, horario text, situacao text, tipo text,
               paciente_nome text, cpf text, telefone text, funcao text, empresa_id uuid,
               empresa text, encaixe boolean, inadimplente boolean, excecao_motivo text,
               cancelado_motivo text, observacao text, negocio_id uuid, chegou_em timestamptz,
               atendido_em timestamptz, finalizado_em timestamptz, criado_por text, criado_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige('gestor','operacoes','comercial');
  return query
    select g.id, g.numero, g.agenda_id, to_char(g.horario, 'HH24:MI'), g.situacao, g.tipo,
           g.paciente_nome, g.cpf, g.telefone, g.funcao, g.empresa_id,
           coalesce(nullif(e.nome_fantasia, ''), e.razao_social, g.empresa_nome)::text,
           g.encaixe, case when g.empresa_id is null then false else crm.empresa_inadimplente(g.empresa_id) end,
           g.excecao_motivo, g.cancelado_motivo, g.observacao, g.negocio_id,
           g.chegou_em, g.atendido_em, g.finalizado_em, u.nome::text, g.criado_em
      from crm.agendamento g
      join crm.agenda a on a.id = g.agenda_id
      left join public.empresa e on e.id = g.empresa_id
      left join crm.perfil u on u.user_id = g.criado_por
     where a.data = p_data and (p_agenda is null or g.agenda_id = p_agenda)
     order by case g.situacao when 'aguardando' then 0 when 'agendado' then 1 when 'atendido' then 2
                              when 'finalizado' then 3 when 'faltou' then 4 else 5 end,
              g.horario nulls last, g.chegou_em nulls last, g.numero;
end $$;

create or replace function public.painel_agendamento_historico(p_id uuid)
returns table (texto text, autor text, criado_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige('gestor','operacoes','comercial');
  return query
    select ev.texto, coalesce(u.nome, 'Sistema')::text, ev.criado_em
      from crm.agendamento_evento ev left join crm.perfil u on u.user_id = ev.autor_id
     where ev.agendamento_id = p_id order by ev.criado_em desc, ev.id desc;
end $$;

create or replace function public.painel_agendamento_checar(p_agenda uuid, p_empresa uuid default null,
                                                            p_encaixe boolean default false,
                                                            p_ignorar uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform crm.exige('gestor','operacoes','comercial');
  return crm.agenda_checar(p_agenda, p_empresa, p_encaixe, p_ignorar);
end $$;

create or replace function public.painel_agenda_regras_salvar(p_dados jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare eu uuid;
begin
  eu := crm.exige('gestor');
  update crm.agenda_regra set
    limite_empresa_dia    = case when p_dados ? 'limite_empresa_dia'
                                 then nullif(p_dados->>'limite_empresa_dia', '')::int else limite_empresa_dia end,
    bloquear_inadimplente = coalesce((p_dados->>'bloquear_inadimplente')::boolean, bloquear_inadimplente),
    vagas_padrao          = coalesce(nullif(p_dados->>'vagas_padrao', '')::int, vagas_padrao),
    hora_inicio_padrao    = coalesce(nullif(p_dados->>'hora_inicio_padrao', '')::time, hora_inicio_padrao),
    hora_fim_padrao       = coalesce(nullif(p_dados->>'hora_fim_padrao', '')::time, hora_fim_padrao),
    atualizado_em = now(), atualizado_por = eu
  where id;
end $$;

create or replace function public.painel_agenda_salvar(p_id uuid, p_dados jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  eu uuid; v_id uuid := p_id; ocup int;
  v_data date := nullif(p_dados->>'data', '')::date;
  v_local text := coalesce(nullif(p_dados->>'local', ''), 'clinica');
  v_empresa uuid := nullif(p_dados->>'empresa_id', '')::uuid;
  v_vagas int := nullif(p_dados->>'vagas', '')::int;
begin
  eu := crm.exige('gestor','operacoes');
  if v_data is null then raise exception 'Informe a data.'; end if;
  if v_vagas is null or v_vagas < 1 then raise exception 'Informe o número de vagas.'; end if;
  if v_local = 'in_company' and v_empresa is null then
    raise exception 'Agenda in company precisa da empresa.';
  end if;
  if v_local = 'clinica' then v_empresa := null; end if;

  if v_id is null then
    insert into crm.agenda (data, profissional_id, local, empresa_id, hora_inicio, hora_fim, vagas, observacao, criado_por)
    values (v_data, nullif(p_dados->>'profissional_id', '')::uuid, v_local, v_empresa,
            nullif(p_dados->>'hora_inicio', '')::time, nullif(p_dados->>'hora_fim', '')::time,
            v_vagas, nullif(trim(p_dados->>'observacao'), ''), eu)
    returning id into v_id;
  else
    select count(*) into ocup from crm.agendamento g
     where g.agenda_id = v_id and not g.encaixe and g.situacao not in ('cancelado','faltou');
    if v_vagas < ocup then
      raise exception 'Já há % pacientes nesta agenda; as vagas não podem ficar abaixo disso.', ocup;
    end if;
    if exists (select 1 from crm.agenda a where a.id = v_id and a.data <> v_data)
       and exists (select 1 from crm.agendamento g where g.agenda_id = v_id and g.situacao not in ('agendado','cancelado','faltou')) then
      raise exception 'Esta agenda já tem atendimentos; não dá para mudar a data.';
    end if;
    update crm.agenda set data = v_data, profissional_id = nullif(p_dados->>'profissional_id', '')::uuid,
           local = v_local, empresa_id = v_empresa,
           hora_inicio = nullif(p_dados->>'hora_inicio', '')::time, hora_fim = nullif(p_dados->>'hora_fim', '')::time,
           vagas = v_vagas, observacao = nullif(trim(p_dados->>'observacao'), ''), atualizado_em = now()
     where id = v_id;
    if not found then raise exception 'Agenda não encontrada.'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.painel_agenda_excluir(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform crm.exige('gestor','operacoes');
  select count(*) into n from crm.agendamento g where g.agenda_id = p_id and g.situacao <> 'cancelado';
  if n > 0 then
    raise exception 'A agenda tem % paciente(s). Mova ou cancele antes de excluir.', n;
  end if;
  delete from crm.agendamento where agenda_id = p_id;
  delete from crm.agenda where id = p_id;
end $$;

create or replace function public.painel_agendamento_salvar(p_id uuid, p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  eu uuid; papel crm.papel; v_id uuid := p_id; atual crm.agendamento; chk jsonb;
  v_agenda uuid := nullif(p_dados->>'agenda_id', '')::uuid;
  v_empresa uuid := nullif(p_dados->>'empresa_id', '')::uuid;
  v_encaixe boolean := coalesce((p_dados->>'encaixe')::boolean, false);
  v_excecao text := nullif(trim(p_dados->>'excecao_motivo'), '');
  v_nome text := nullif(trim(p_dados->>'paciente_nome'), '');
  v_cpf text := nullif(regexp_replace(coalesce(p_dados->>'cpf', ''), '\D', '', 'g'), '');
  mudou_vaga boolean := true;
begin
  eu := crm.exige('gestor','operacoes','comercial');
  papel := crm.papel_atual();
  if v_agenda is null then raise exception 'Escolha a agenda.'; end if;
  if v_nome is null then raise exception 'Informe o nome do paciente.'; end if;
  if v_empresa is null and nullif(trim(p_dados->>'empresa_nome'), '') is null then
    raise exception 'Informe a empresa (ou "Particular").';
  end if;
  if v_cpf is not null and length(v_cpf) <> 11 then raise exception 'CPF deve ter 11 dígitos.'; end if;

  if v_id is not null then
    select * into atual from crm.agendamento where id = v_id for update;
    if atual.id is null then raise exception 'Agendamento não encontrado.'; end if;
    if atual.situacao in ('finalizado','cancelado') and papel not in ('admin','gestor') then
      raise exception 'Agendamento % não pode ser editado; peça a um gestor.', lower(crm.agenda_rotulo(atual.situacao));
    end if;

    mudou_vaga := atual.agenda_id <> v_agenda or atual.empresa_id is distinct from v_empresa
                  or atual.encaixe <> v_encaixe;
  end if;

  chk := crm.agenda_checar(v_agenda, v_empresa, v_encaixe, v_id);
  if mudou_vaga and jsonb_array_length(chk->'bloqueios') > 0 then
    if v_excecao is null then
      raise exception '%', (select string_agg(x, ' ') from jsonb_array_elements_text(chk->'bloqueios') x)
        using errcode = 'P0001', hint = 'bloqueio_agenda';
    end if;
    if papel not in ('admin','gestor') then
      raise exception 'Só gestor pode liberar fora da regra: %',
        (select string_agg(x, ' ') from jsonb_array_elements_text(chk->'bloqueios') x) using errcode = '42501';
    end if;
  end if;

  if v_id is null then
    insert into crm.agendamento (agenda_id, horario, empresa_id, empresa_nome, colaborador_id, paciente_nome, cpf,
                                 telefone, funcao, tipo, encaixe, excecao_motivo, negocio_id, observacao, criado_por)
    values (v_agenda, nullif(p_dados->>'horario', '')::time, v_empresa,
            case when v_empresa is null then nullif(trim(p_dados->>'empresa_nome'), '') end,
            nullif(p_dados->>'colaborador_id', '')::uuid, v_nome, v_cpf,
            nullif(trim(p_dados->>'telefone'), ''), nullif(trim(p_dados->>'funcao'), ''),
            coalesce(nullif(p_dados->>'tipo', ''), 'periodico'), v_encaixe,
            case when mudou_vaga and jsonb_array_length(chk->'bloqueios') > 0 then v_excecao end,
            nullif(p_dados->>'negocio_id', '')::uuid, nullif(trim(p_dados->>'observacao'), ''), eu)
    returning id into v_id;
    perform crm.agenda_registrar(v_id, 'Agendado' || case when v_encaixe then ' (encaixe)' else '' end);
  else
    update crm.agendamento set agenda_id = v_agenda, horario = nullif(p_dados->>'horario', '')::time,
           empresa_id = v_empresa,
           empresa_nome = case when v_empresa is null then nullif(trim(p_dados->>'empresa_nome'), '') end,
           colaborador_id = nullif(p_dados->>'colaborador_id', '')::uuid, paciente_nome = v_nome, cpf = v_cpf,
           telefone = nullif(trim(p_dados->>'telefone'), ''), funcao = nullif(trim(p_dados->>'funcao'), ''),
           tipo = coalesce(nullif(p_dados->>'tipo', ''), tipo), encaixe = v_encaixe,
           excecao_motivo = case when mudou_vaga and jsonb_array_length(chk->'bloqueios') > 0 then v_excecao
                                 else excecao_motivo end,
           negocio_id = nullif(p_dados->>'negocio_id', '')::uuid,
           observacao = nullif(trim(p_dados->>'observacao'), ''), atualizado_em = now()
     where id = v_id;
    perform crm.agenda_registrar(v_id, case when atual.agenda_id <> v_agenda then 'Remarcado para outra agenda'
                                            else 'Dados atualizados' end);
  end if;

  if mudou_vaga and jsonb_array_length(chk->'bloqueios') > 0 then
    perform crm.agenda_registrar(v_id, 'Liberado fora da regra: ' || v_excecao);
  end if;
  return jsonb_build_object('id', v_id, 'avisos', chk->'avisos');
end $$;

create or replace function public.painel_agendamento_situacao(p_id uuid, p_situacao text, p_motivo text default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare eu uuid; papel crm.papel; atual crm.agendamento; motivo text := nullif(trim(p_motivo), '');
begin
  eu := crm.exige('gestor','operacoes','comercial');
  papel := crm.papel_atual();
  if p_situacao not in ('agendado','aguardando','atendido','finalizado','cancelado','faltou') then
    raise exception 'Situação inválida: %', p_situacao;
  end if;
  select * into atual from crm.agendamento where id = p_id for update;
  if atual.id is null then raise exception 'Agendamento não encontrado.'; end if;
  if atual.situacao = p_situacao then return; end if;

  if papel = 'comercial' and p_situacao not in ('agendado','cancelado') then
    raise exception 'Seu perfil agenda e cancela; chegada e atendimento ficam com operações.' using errcode = '42501';
  end if;
  if atual.situacao in ('finalizado','cancelado') and papel not in ('admin','gestor','operacoes') then
    raise exception 'Só operações ou gestor reabre um agendamento %.', lower(crm.agenda_rotulo(atual.situacao))
      using errcode = '42501';
  end if;
  if p_situacao = 'cancelado' and motivo is null then
    raise exception 'Informe o motivo do cancelamento.';
  end if;

  if atual.situacao in ('cancelado','faltou') and p_situacao not in ('cancelado','faltou') and not atual.encaixe
     and exists (select 1 from crm.agenda a where a.id = atual.agenda_id
                  and a.vagas <= (select count(*) from crm.agendamento g where g.agenda_id = a.id and not g.encaixe
                                    and g.situacao not in ('cancelado','faltou'))) then
    update crm.agendamento set encaixe = true where id = p_id;
    perform crm.agenda_registrar(p_id, 'Agenda lotada: voltou como encaixe');
  end if;

  update crm.agendamento set
    situacao = p_situacao,
    chegou_em     = case when p_situacao = 'aguardando' then coalesce(chegou_em, now())
                         when p_situacao = 'agendado' then null else chegou_em end,
    atendido_em   = case when p_situacao in ('atendido','finalizado') then coalesce(atendido_em, now())
                         when p_situacao in ('agendado','aguardando') then null else atendido_em end,
    finalizado_em = case when p_situacao = 'finalizado' then now() else null end,
    cancelado_motivo = case when p_situacao = 'cancelado' then motivo else null end,
    atualizado_em = now()
  where id = p_id;
  perform crm.agenda_registrar(p_id, crm.agenda_rotulo(atual.situacao) || ' → ' || crm.agenda_rotulo(p_situacao)
                                     || coalesce(': ' || motivo, ''));
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
