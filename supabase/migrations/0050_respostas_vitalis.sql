

alter table crm.perfil add column if not exists libera_agenda boolean not null default false;

create table if not exists crm.pre_cadastro (
  email          text primary key check (email = lower(email)),
  nome           text not null,
  papel          crm.papel not null,
  cargo          text,
  libera_agenda  boolean not null default false,
  rodizio_ordem  int,
  usado_em       timestamptz,
  criado_em      timestamptz not null default now()
);
alter table crm.pre_cadastro enable row level security;

insert into crm.pre_cadastro (email, nome, cargo, papel, libera_agenda, rodizio_ordem) values
  ('gerencia@exemplo.com.br',            'Helena Costa',  'Gerente de atendimento', 'gestor',     true,  null),
  ('contato@exemplo.com.br',             'Renata Alves',   'Diretoria',              'admin',      false, null),
  ('exames@exemplo.com.br',              'Carla Nunes',    'Atendimento',            'operacoes',  false, null),
  ('atendimento@exemplo.com.br',         'Paula Reis',    'Atendimento',            'operacoes',  false, null),
  ('recepcao@exemplo.com.br',            'Daniela',           'Atendimento',            'operacoes',  false, null),
  ('credenciamento@exemplo.com.br',      'Bianca Lima',   'Credenciamento',         'operacoes',  false, null),
  ('faturamento@exemplo.com.br',         'Sônia Duarte',  'Financeiro',             'financeiro', false, null),
  ('laudos@exemplo.com.br',              'Tânia Melo',      'Laudos',                 'operacoes',  false, null),
  ('segurancadotrabalho@exemplo.com.br', 'Otávio Ramos', 'Técnico de segurança',   'operacoes',  false, null),
  ('dr.eduardo@exemplo.com.br',          'Rafael Alves',  'Médico',                 'operacoes',  false, null),
  ('ana.ribeiro@exemplo.com.br',       'Ana Ribeiro',     'Comercial',              'comercial',  false, 1),
  ('luana.prado@exemplo.com.br',    'Luana Prado',  'Comercial',              'comercial',  false, 2),
  ('e.moura@exemplo.com.br',            'Fábio Moura',    'Comercial',              'comercial',  false, 3)
on conflict (email) do nothing;

create or replace function crm.aplicar_pre_cadastro(p_user uuid, p_email text, p_confirmado boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare pc crm.pre_cadastro; f uuid;
begin
  select * into pc from crm.pre_cadastro where email = lower(trim(p_email));
  if pc.email is null then return; end if;
  update crm.perfil set nome = pc.nome, papel = pc.papel, libera_agenda = pc.libera_agenda,
                        ativo = ativo or p_confirmado
   where user_id = p_user and (not ativo or p_confirmado);
  if p_confirmado then
    update crm.pre_cadastro set usado_em = coalesce(usado_em, now()) where email = pc.email;
    if pc.rodizio_ordem is not null then
      select id into f from crm.funil where slug = 'comercial';
      insert into crm.rodizio (funil_id, user_id, ordem, ativo) values (f, p_user, pc.rodizio_ordem, true)
      on conflict (funil_id, user_id) do nothing;
    end if;
  end if;
end $$;

create or replace function crm.tg_novo_usuario() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  begin
    insert into crm.perfil (user_id, nome, email, papel, ativo)
    select new.id,
           coalesce(nullif(trim(new.raw_user_meta_data->>'nome'), ''), split_part(new.email, '@', 1)),
           coalesce(new.email, ''),
           case when a.email is not null then 'admin'::crm.papel else 'leitura'::crm.papel end,
           a.email is not null
      from (select 1) x
      left join crm.admin_inicial a on lower(a.email) = lower(new.email)
    on conflict (user_id) do nothing;
    perform crm.aplicar_pre_cadastro(new.id, new.email, new.email_confirmed_at is not null);
  exception when others then
    raise warning 'crm.tg_novo_usuario: %', sqlerrm;
  end;
  return new;
end $$;

create or replace function crm.tg_usuario_confirmado() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  begin
    if new.email_confirmed_at is not null and old.email_confirmed_at is null then
      perform crm.aplicar_pre_cadastro(new.id, new.email, true);
    end if;
  exception when others then
    raise warning 'crm.tg_usuario_confirmado: %', sqlerrm;
  end;
  return new;
end $$;
revoke execute on function crm.tg_novo_usuario(), crm.tg_usuario_confirmado(), crm.aplicar_pre_cadastro(uuid, text, boolean)
  from public, anon, authenticated;

drop trigger if exists vitalis_usuario_confirmado on auth.users;
create trigger vitalis_usuario_confirmado after update of email_confirmed_at on auth.users
  for each row execute function crm.tg_usuario_confirmado();

select crm.aplicar_pre_cadastro(u.id, u.email, u.email_confirmed_at is not null) from auth.users u;

create or replace function public.painel_pre_cadastros()
returns table (email text, nome text, cargo text, papel text, libera_agenda boolean, rodizio_ordem int, usado_em timestamptz, cadastrado boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige('admin');
  return query
    select pc.email, pc.nome, pc.cargo, pc.papel::text, pc.libera_agenda, pc.rodizio_ordem, pc.usado_em,
           exists (select 1 from crm.perfil p where lower(p.email) = pc.email)
      from crm.pre_cadastro pc order by pc.usado_em is not null, pc.nome;
end $$;

create or replace function public.painel_pre_cadastro_salvar(p_email text, p_dados jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare e text := lower(trim(p_email));
begin
  perform crm.exige('admin');
  if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'E-mail inválido.'; end if;
  if coalesce(p_dados->>'papel', '') not in ('admin','gestor','comercial','operacoes','financeiro','leitura') then
    raise exception 'Perfil inválido.';
  end if;
  if nullif(trim(p_dados->>'nome'), '') is null then raise exception 'Informe o nome.'; end if;
  insert into crm.pre_cadastro (email, nome, cargo, papel, libera_agenda, rodizio_ordem)
  values (e, trim(p_dados->>'nome'), nullif(trim(p_dados->>'cargo'), ''), (p_dados->>'papel')::crm.papel,
          coalesce((p_dados->>'libera_agenda')::boolean, false), nullif(p_dados->>'rodizio_ordem', '')::int)
  on conflict (email) do update set nome = excluded.nome, cargo = excluded.cargo, papel = excluded.papel,
    libera_agenda = excluded.libera_agenda, rodizio_ordem = excluded.rodizio_ordem;
end $$;

create or replace function public.painel_pre_cadastro_excluir(p_email text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('admin');
  delete from crm.pre_cadastro where email = lower(trim(p_email));
end $$;

create or replace function public.painel_usuario_libera_agenda(p_user uuid, p_libera boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('admin');
  update crm.perfil set libera_agenda = coalesce(p_libera, false) where user_id = p_user;
  if not found then raise exception 'Usuário não encontrado.'; end if;
end $$;

drop function if exists public.painel_usuarios();
create function public.painel_usuarios()
returns table (user_id uuid, nome text, email text, papel text, ativo boolean, telefone text,
               criado_em timestamptz, ultimo_acesso timestamptz, libera_agenda boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform crm.exige('admin');
  return query
    select p.user_id, p.nome, p.email, p.papel::text, p.ativo, p.telefone, p.criado_em, p.ultimo_acesso, p.libera_agenda
      from crm.perfil p
     order by p.ativo, p.nome;
end $$;

create or replace function crm.pode_liberar_agenda() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select p.papel = 'admin' or p.libera_agenda from crm.perfil p where p.user_id = auth.uid() and p.ativo), false)
$$;
revoke execute on function crm.pode_liberar_agenda() from public, anon, authenticated;

update crm.agenda_regra set limite_empresa_dia = 2, vagas_padrao = 40,
       hora_inicio_padrao = '08:30', hora_fim_padrao = '11:30', atualizado_em = now()
 where id;
alter table crm.agenda_regra alter column hora_inicio_padrao set default '08:30';

create table if not exists crm.agenda_limite_empresa (
  empresa_id     uuid primary key references public.empresa(id) on delete cascade,
  limite         int not null check (limite between 1 and 500),
  motivo         text,
  atualizado_por uuid,
  atualizado_em  timestamptz not null default now()
);
alter table crm.agenda_limite_empresa enable row level security;

alter table crm.agendamento add column if not exists complementares text[] not null default '{}';

drop function if exists crm.agenda_checar(uuid, uuid, boolean, uuid);
create or replace function crm.agenda_checar(p_agenda uuid, p_empresa uuid, p_encaixe boolean,
                                             p_ignorar uuid default null, p_tipo text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  a crm.agenda; r crm.agenda_regra;
  ocupadas int; na_empresa int := 0; inad boolean := false; sit text; limite int; proprio boolean := false;
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
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
    select l.limite into limite from crm.agenda_limite_empresa l where l.empresa_id = p_empresa;
    proprio := limite is not null;
    limite := coalesce(limite, r.limite_empresa_dia);
    select count(*) into na_empresa from crm.agendamento g join crm.agenda ag on ag.id = g.agenda_id
     where ag.data = a.data and g.empresa_id = p_empresa and g.situacao not in ('cancelado','faltou')
       and g.id is distinct from p_ignorar;
    if limite is not null and na_empresa >= limite and a.local = 'clinica' then
      bloqueios := array_append(bloqueios, format('Esta empresa já tem %s agendado(s) em %s (limite %s por dia%s).',
                                       na_empresa, to_char(a.data, 'DD/MM'), limite,
                                       case when proprio then ', próprio desta empresa' else '' end));
    elsif na_empresa > 0 then
      avisos := array_append(avisos, format('Esta empresa já tem %s agendado(s) neste dia%s.', na_empresa,
                                            case when limite is not null then format(' (limite %s)', limite) else '' end));
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

  if a.data < hoje then
    avisos := array_append(avisos, 'Data já passou.');
  elsif a.data <= hoje + 2 then
    avisos := array_append(avisos, 'Menos de 48 h de antecedência (o Regulamento Operacional pede 48 h).');
  end if;
  if p_tipo = 'demissional' and a.data >= hoje and a.data < hoje + 10 then
    avisos := array_append(avisos, 'Demissional com exames complementares deve ser marcado com 10 dias de antecedência.');
  end if;

  return jsonb_build_object('vagas', a.vagas, 'ocupadas', ocupadas, 'empresa_no_dia', na_empresa,
                            'limite_empresa_dia', limite, 'limite_proprio', proprio, 'inadimplente', inad,
                            'bloqueios', to_jsonb(bloqueios), 'avisos', to_jsonb(avisos));
end $$;
revoke execute on function crm.agenda_checar(uuid, uuid, boolean, uuid, text) from public, anon, authenticated;

drop function if exists public.painel_agendamento_checar(uuid, uuid, boolean, uuid);
create or replace function public.painel_agendamento_checar(p_agenda uuid, p_empresa uuid default null,
                                                 p_encaixe boolean default false, p_ignorar uuid default null,
                                                 p_tipo text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform crm.exige('gestor','operacoes','comercial');
  return crm.agenda_checar(p_agenda, p_empresa, p_encaixe, p_ignorar, p_tipo);
end $$;

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
                                    'pode_excecao', crm.pode_liberar_agenda(),
                                    'liberam', coalesce((select jsonb_agg(p.nome order by p.nome) from crm.perfil p
                                                          where p.ativo and (p.libera_agenda or p.papel = 'admin')
                                                            and p.email not ilike '%@exemplo.com.br'), '[]'::jsonb),
                                    'limites', coalesce((select jsonb_agg(jsonb_build_object(
                                                  'empresa_id', l.empresa_id, 'limite', l.limite, 'motivo', l.motivo,
                                                  'empresa', coalesce(nullif(e.nome_fantasia, ''), e.razao_social), 'cnpj', e.cnpj)
                                                  order by coalesce(nullif(e.nome_fantasia, ''), e.razao_social))
                                               from crm.agenda_limite_empresa l join public.empresa e on e.id = l.empresa_id), '[]'::jsonb))
            from crm.agenda_regra r where r.id);
end $$;

create or replace function public.painel_agenda_limite_salvar(p_empresa uuid, p_limite int, p_motivo text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('gestor','operacoes');
  if not crm.pode_liberar_agenda() then
    raise exception 'Só quem libera exceções da agenda define limite por empresa.' using errcode = '42501';
  end if;
  if p_limite is null then
    delete from crm.agenda_limite_empresa where empresa_id = p_empresa;
    return;
  end if;
  insert into crm.agenda_limite_empresa (empresa_id, limite, motivo, atualizado_por)
  values (p_empresa, p_limite, nullif(trim(p_motivo), ''), auth.uid())
  on conflict (empresa_id) do update set limite = excluded.limite, motivo = excluded.motivo,
    atualizado_por = excluded.atualizado_por, atualizado_em = now();
end $$;

drop function if exists public.painel_agenda_dia(date, uuid);
create function public.painel_agenda_dia(p_data date, p_agenda uuid default null)
returns table (id uuid, numero bigint, agenda_id uuid, horario text, situacao text, tipo text,
               paciente_nome text, cpf text, telefone text, funcao text, empresa_id uuid,
               empresa text, encaixe boolean, inadimplente boolean, excecao_motivo text,
               cancelado_motivo text, observacao text, negocio_id uuid, chegou_em timestamptz,
               atendido_em timestamptz, finalizado_em timestamptz, criado_por text, criado_em timestamptz,
               complementares text[])
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
           g.chegou_em, g.atendido_em, g.finalizado_em, u.nome::text, g.criado_em, g.complementares
      from crm.agendamento g
      join crm.agenda a on a.id = g.agenda_id
      left join public.empresa e on e.id = g.empresa_id
      left join crm.perfil u on u.user_id = g.criado_por
     where a.data = p_data and (p_agenda is null or g.agenda_id = p_agenda)
     order by case g.situacao when 'aguardando' then 0 when 'agendado' then 1 when 'atendido' then 2
                              when 'finalizado' then 3 when 'faltou' then 4 else 5 end,
              g.horario nulls last, g.chegou_em nulls last, g.numero;
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
  v_tipo text := coalesce(nullif(p_dados->>'tipo', ''), 'periodico');
  v_comp text[] := coalesce((select array_agg(distinct upper(trim(x))) from jsonb_array_elements_text(
                              case when jsonb_typeof(p_dados->'complementares') = 'array' then p_dados->'complementares' else '[]'::jsonb end) x
                             where nullif(trim(x), '') is not null), '{}');
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

  chk := crm.agenda_checar(v_agenda, v_empresa, v_encaixe, v_id, v_tipo);
  if mudou_vaga and jsonb_array_length(chk->'bloqueios') > 0 then
    if v_excecao is null then
      raise exception '%', (select string_agg(x, ' ') from jsonb_array_elements_text(chk->'bloqueios') x)
        using errcode = 'P0001', hint = 'bloqueio_agenda';
    end if;
    if not crm.pode_liberar_agenda() then
      raise exception 'Só quem libera exceções da agenda pode passar por cima da regra: %',
        (select string_agg(x, ' ') from jsonb_array_elements_text(chk->'bloqueios') x) using errcode = '42501';
    end if;
  end if;

  if v_id is null then
    insert into crm.agendamento (agenda_id, horario, empresa_id, empresa_nome, colaborador_id, paciente_nome, cpf,
                                 telefone, funcao, tipo, encaixe, excecao_motivo, negocio_id, observacao, complementares, criado_por)
    values (v_agenda, nullif(p_dados->>'horario', '')::time, v_empresa,
            case when v_empresa is null then nullif(trim(p_dados->>'empresa_nome'), '') end,
            nullif(p_dados->>'colaborador_id', '')::uuid, v_nome, v_cpf,
            nullif(trim(p_dados->>'telefone'), ''), nullif(trim(p_dados->>'funcao'), ''),
            v_tipo, v_encaixe,
            case when mudou_vaga and jsonb_array_length(chk->'bloqueios') > 0 then v_excecao end,
            nullif(p_dados->>'negocio_id', '')::uuid, nullif(trim(p_dados->>'observacao'), ''), v_comp, eu)
    returning id into v_id;
    perform crm.agenda_registrar(v_id, 'Agendado' || case when v_encaixe then ' (encaixe)' else '' end);
  else
    update crm.agendamento set agenda_id = v_agenda, horario = nullif(p_dados->>'horario', '')::time,
           empresa_id = v_empresa,
           empresa_nome = case when v_empresa is null then nullif(trim(p_dados->>'empresa_nome'), '') end,
           colaborador_id = nullif(p_dados->>'colaborador_id', '')::uuid, paciente_nome = v_nome, cpf = v_cpf,
           telefone = nullif(trim(p_dados->>'telefone'), ''), funcao = nullif(trim(p_dados->>'funcao'), ''),
           tipo = v_tipo, encaixe = v_encaixe,
           excecao_motivo = case when mudou_vaga and jsonb_array_length(chk->'bloqueios') > 0 then v_excecao
                                 else excecao_motivo end,
           negocio_id = nullif(p_dados->>'negocio_id', '')::uuid,
           observacao = nullif(trim(p_dados->>'observacao'), ''),
           complementares = case when p_dados ? 'complementares' then v_comp else complementares end,
           atualizado_em = now()
     where id = v_id;
    perform crm.agenda_registrar(v_id, case when atual.agenda_id <> v_agenda then 'Remarcado para outra agenda'
                                            else 'Dados atualizados' end);
  end if;

  if mudou_vaga and jsonb_array_length(chk->'bloqueios') > 0 then
    perform crm.agenda_registrar(v_id, 'Liberado fora da regra: ' || v_excecao);
  end if;
  return jsonb_build_object('id', v_id, 'avisos', chk->'avisos');
end $$;

update crm.fin_regra set tolerancia_dias = 10 where id and tolerancia_dias = 5;

create or replace function crm.cobranca_encargos(p_valor numeric, p_vencimento date, p_pago date, p_cancelada boolean)
returns numeric language sql stable set search_path = '' as $$
  select case when p_cancelada or p_pago is not null or p_vencimento is null then 0
              when (now() at time zone 'America/Sao_Paulo')::date - p_vencimento < 30 then 0
              else round(p_valor * 0.10 + p_valor * 0.01 * (((now() at time zone 'America/Sao_Paulo')::date - p_vencimento) / 30.0), 2) end
$$;

drop function if exists public.painel_cobrancas(date, text, text);
create function public.painel_cobrancas(p_competencia date default null, p_situacao text default null, p_busca text default null)
returns table (id uuid, numero bigint, empresa_id uuid, cliente text, cnpj text, contrato_id uuid, contrato_numero bigint,
               descricao text, competencia date, vencimento date, valor numeric, valor_pago numeric, pago_em date,
               forma text, nota_fiscal text, boleto text, observacao text, situacao text, dias_atraso int, origem text,
               encargos numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        dig text := nullif(regexp_replace(coalesce(p_busca, ''), '\D', '', 'g'), '');
begin
  perform crm.exige_financeiro();
  return query
    select c.id, c.numero, c.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social, c.cliente_nome)::text, e.cnpj::text,
           c.contrato_id, ct.numero, c.descricao, c.competencia, c.vencimento, c.valor, c.valor_pago, c.pago_em,
           c.forma, c.nota_fiscal, c.boleto, c.observacao, crm.cobranca_situacao(c.cancelada, c.pago_em, c.vencimento),
           case when c.pago_em is null and not c.cancelada and c.vencimento < hoje then (hoje - c.vencimento)::int else 0 end,
           c.origem, crm.cobranca_encargos(c.valor, c.vencimento, c.pago_em, c.cancelada)
      from crm.cobranca c
      left join public.empresa e on e.id = c.empresa_id
      left join crm.contrato ct on ct.id = c.contrato_id
     where (p_competencia is null or c.competencia = date_trunc('month', p_competencia)::date
            or (p_situacao is null and c.pago_em is null and not c.cancelada and c.vencimento < hoje and c.competencia < date_trunc('month', p_competencia)::date))
       and (p_situacao is null or crm.cobranca_situacao(c.cancelada, c.pago_em, c.vencimento) = p_situacao)
       and (termo is null or c.descricao ilike '%' || termo || '%' or e.razao_social ilike '%' || termo || '%'
            or e.nome_fantasia ilike '%' || termo || '%' or c.cliente_nome ilike '%' || termo || '%'
            or c.nota_fiscal = termo or (dig is not null and length(dig) >= 4 and regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') like dig || '%'))
     order by case crm.cobranca_situacao(c.cancelada, c.pago_em, c.vencimento) when 'vencida' then 0 when 'aberta' then 1 when 'paga' then 2 else 3 end,
              c.vencimento, c.numero;
end $$;

alter table crm.produto add column if not exists codigo text unique;
alter table crm.produto add column if not exists cobranca_padrao text;

update crm.produto set codigo = 'pgr', categoria = 'B · Documentos e laudos', preco = 420, recorrente = false,
       unidade = 'laudo', cobranca_padrao = 'Parcelado em 12 meses', descricao = 'NR-01. Validade de 2 anos; renovação automática quando contratada.'
 where nome = 'PGR — Programa de Gerenciamento de Riscos (NR-1)';
update crm.produto set codigo = 'pcmso', categoria = 'A · Mensalidade por vida ativa', preco = 560, recorrente = false,
       unidade = 'laudo', cobranca_padrao = 'Parcelado em 12 meses', descricao = 'NR-7. Elaboração, implantação e manutenção.'
 where nome = 'PCMSO — Programa de Controle Médico';
update crm.produto set codigo = 'ltcat', categoria = 'B · Documentos e laudos', preco = 420, recorrente = false,
       unidade = 'laudo', cobranca_padrao = 'Parcelado em 12 meses', descricao = 'Laudo Técnico das Condições Ambientais do Trabalho.'
 where nome = 'LTCAT';
update crm.produto set codigo = 'esocial', categoria = 'C · Mensageria eSocial', preco = 400, recorrente = false,
       cobranca_padrao = 'Parcelas: 05', descricao = 'S-2220 e S-2240. Inclui gestão da procuração no eCAC.'
 where nome = 'Mensageria eSocial (SST)';

insert into crm.produto (codigo, nome, categoria, preco, unidade, recorrente, cobranca_padrao, descricao) values
  ('aso', 'Exame ocupacional (ASO)', 'A · Mensalidade por vida ativa', 50, 'exame', false, 'Por exame',
   'Admissional, periódico, retorno ao trabalho, mudança de função e demissional.'),
  ('psicossocial', 'Mapeamento psicossocial (NR-01)', 'B · Documentos e laudos', null, 'emissão', false, 'Parcelas', null),
  ('ppp', 'PPP — Perfil Profissiográfico Previdenciário', 'B · Documentos e laudos', null, 'emissão', false, 'Por emissão', null),
  ('insalubridade', 'Laudo de insalubridade', 'B · Documentos e laudos', null, 'laudo', false, 'Parcelas', null),
  ('periculosidade', 'Laudo de periculosidade', 'B · Documentos e laudos', null, 'laudo', false, 'Parcelas', null),
  ('cipa', 'Implantação e gestão de CIPA (NR-05)', 'D · Treinamentos e outros', null, 'evento', false, 'Por evento', null),
  ('brigada', 'Treinamento de brigada de incêndio', 'D · Treinamentos e outros', null, 'evento', false, 'Por evento', null),
  ('primeiros_socorros', 'Treinamento de primeiros socorros', 'D · Treinamentos e outros', null, 'evento', false, 'Por evento', null),
  ('nrs', 'Treinamentos NR-10, NR-35 e outras NRs', 'D · Treinamentos e outros', null, 'evento', false, 'Por evento', 'Especificar na proposta comercial.'),
  ('pericia', 'Perícia judicial em medicina do trabalho', 'D · Treinamentos e outros', null, 'perícia', false, 'Conforme proposta', null),
  ('avulso', 'Exame admissional/demissional avulso', 'E · Avulsos e sob demanda', null, 'exame', false, 'Por solicitação', 'Fora da mensalidade.'),
  ('atualizacao_laudo', 'Atualização de laudo por alteração de atividade ou função', 'E · Avulsos e sob demanda', null, 'evento', false, 'Por evento', null),
  ('custodia', 'Custódia de prontuários', 'E · Avulsos e sob demanda', 150, 'mês', true, 'Mensal',
   'Cobrada 60 dias após o fim do contrato, se o cliente não indicar quem recebe os prontuários.')
on conflict (nome) do update set codigo = excluded.codigo, categoria = excluded.categoria,
  preco = coalesce(crm.produto.preco, excluded.preco), unidade = excluded.unidade,
  cobranca_padrao = excluded.cobranca_padrao, descricao = coalesce(crm.produto.descricao, excluded.descricao);

alter table crm.contrato add column if not exists representante_legal text;
alter table crm.contrato add column if not exists email_notificacao text;
alter table crm.contrato add column if not exists telefone_contato text;
alter table crm.contrato add column if not exists prazo_meses int check (prazo_meses between 1 and 120);
alter table crm.contrato alter column dia_vencimento set default 5;
alter table crm.contrato alter column indice_reajuste set default 'IPCA';
alter table crm.contrato alter column forma_pagamento set default 'Boleto bancário';
alter table crm.contrato alter column renovacao_automatica set default true;
alter table crm.contrato_item add column if not exists cobranca text;

create or replace function crm.tg_contrato_item_cobranca() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.cobranca is null and new.produto_id is not null then
    select p.cobranca_padrao into new.cobranca from crm.produto p where p.id = new.produto_id;
  end if;
  return new;
end $$;
revoke execute on function crm.tg_contrato_item_cobranca() from public, anon, authenticated;
drop trigger if exists contrato_item_cobranca on crm.contrato_item;
create trigger contrato_item_cobranca before insert on crm.contrato_item
  for each row execute function crm.tg_contrato_item_cobranca();

create or replace function crm.tg_contrato_padroes() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.dia_vencimento  := coalesce(new.dia_vencimento, 5);
  new.indice_reajuste := coalesce(new.indice_reajuste, 'IPCA');
  new.forma_pagamento := coalesce(new.forma_pagamento, 'Boleto bancário');
  return new;
end $$;
revoke execute on function crm.tg_contrato_padroes() from public, anon, authenticated;
drop trigger if exists contrato_padroes on crm.contrato;
create trigger contrato_padroes before insert on crm.contrato
  for each row execute function crm.tg_contrato_padroes();

create or replace function public.painel_contrato_minuta(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform crm.exige_contratos();
  select jsonb_build_object(
      'id', c.id, 'numero', c.numero, 'titulo', c.titulo,
      'razao_social', coalesce(e.razao_social, c.cliente_nome), 'cnpj', e.cnpj,
      'endereco', concat_ws(' — ', nullif(concat_ws(', ', nullif(e.logradouro, ''), nullif(e.numero, ''), nullif(e.complemento, '')), ''),
                            nullif(e.bairro, ''), nullif(concat_ws('/', nullif(e.cidade, ''), nullif(e.uf, '')), ''),
                            case when nullif(e.cep, '') is not null then 'CEP ' || e.cep end),
      'telefone', coalesce(c.telefone_contato, e.telefone), 'email_notificacao', coalesce(c.email_notificacao, e.email),
      'representante_legal', c.representante_legal,
      'inicio', c.inicio, 'fim', c.fim, 'prazo_meses', c.prazo_meses,
      'renovacao_automatica', c.renovacao_automatica, 'dia_vencimento', c.dia_vencimento,
      'forma_pagamento', c.forma_pagamento, 'indice_reajuste', c.indice_reajuste,
      'itens', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'codigo', p.codigo, 'descricao', i.descricao,
                                                             'quantidade', i.quantidade, 'preco', i.preco, 'total', i.total,
                                                             'unidade', p.unidade, 'cobranca', coalesce(i.cobranca, p.cobranca_padrao))
                                          order by i.criado_em)
                           from crm.contrato_item i left join crm.produto p on p.id = i.produto_id
                          where i.contrato_id = c.id), '[]'::jsonb))
    into r
    from crm.contrato c left join public.empresa e on e.id = c.empresa_id
   where c.id = p_id;
  if r is null then raise exception 'Contrato não encontrado.'; end if;
  return r;
end $$;

create or replace function public.painel_contrato_minuta_salvar(p_id uuid, p_dados jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare it jsonb;
begin
  perform crm.exige_contratos();
  if (select status from crm.contrato where id = p_id) = 'cancelado' then raise exception 'Contrato cancelado não é editado.'; end if;
  update crm.contrato set
    representante_legal = case when p_dados ? 'representante_legal' then nullif(trim(p_dados->>'representante_legal'), '') else representante_legal end,
    email_notificacao   = case when p_dados ? 'email_notificacao' then nullif(trim(p_dados->>'email_notificacao'), '') else email_notificacao end,
    telefone_contato    = case when p_dados ? 'telefone' then nullif(trim(p_dados->>'telefone'), '') else telefone_contato end,
    prazo_meses         = case when p_dados ? 'prazo_meses' then nullif(p_dados->>'prazo_meses', '')::int else prazo_meses end,
    atualizado_em = now()
  where id = p_id;
  if not found then raise exception 'Contrato não encontrado.'; end if;
  for it in select * from jsonb_array_elements(coalesce(p_dados->'itens', '[]'::jsonb)) loop
    update crm.contrato_item set cobranca = nullif(trim(it->>'cobranca'), '')
     where id = (it->>'id')::uuid and contrato_id = p_id;
  end loop;
  perform crm.contrato_log(p_id, 'Minuta gerada');
end $$;

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    execute 'drop policy if exists "crm_arquivos_enviar" on storage.objects';
    execute 'drop policy if exists "crm_arquivos_apagar" on storage.objects';
    execute $p$create policy "crm_arquivos_enviar" on storage.objects for insert to authenticated
      with check (bucket_id = 'crm-arquivos' and case when name like 'modelos/%'
                    then public.painel_papel_em(array['gestor'])
                    else public.painel_papel_em(array['gestor','comercial','financeiro','operacoes']) end)$p$;
    execute $p$create policy "crm_arquivos_apagar" on storage.objects for delete to authenticated
      using (bucket_id = 'crm-arquivos' and case when name like 'modelos/%'
               then public.painel_papel_em(array['gestor'])
               else public.painel_papel_em(array['gestor','comercial','financeiro']) end)$p$;
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

notify pgrst, 'reload schema';
