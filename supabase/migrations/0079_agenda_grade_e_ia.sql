

create table if not exists crm.agenda_grade (
  horario       time primary key,
  vagas         int not null check (vagas between 0 and 50),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid
);
alter table crm.agenda_grade enable row level security;

insert into crm.agenda_grade (horario, vagas)
select h::time, 4 from generate_series('2000-01-01 08:30'::timestamp, '2000-01-01 11:30', interval '20 minutes') h
on conflict (horario) do nothing;

alter table crm.perfil add column if not exists agenda_encaixe boolean not null default false;
update crm.perfil set agenda_encaixe = true
 where email in ('gerencia@exemplo.com.br', 'exames@exemplo.com.br', 'atendimento@exemplo.com.br', 'recepcao@exemplo.com.br');

create or replace function crm.pode_encaixe() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select p.papel = 'admin' or p.agenda_encaixe from crm.perfil p where p.user_id = auth.uid() and p.ativo), false)
$$;
revoke execute on function crm.pode_encaixe() from public, anon, authenticated;

alter table crm.agendamento add column if not exists criado_via text not null default 'painel' check (criado_via in ('painel', 'ia'));
alter table crm.agendamento add column if not exists ia_ref text;

create or replace function crm.agenda_horarios(p_agenda uuid, p_ignorar uuid default null)
returns table (horario time, vagas int, ocupadas int)
language sql stable security definer set search_path = '' as $$
  select g.horario, g.vagas,
         (select count(*)::int from crm.agendamento a
           where a.agenda_id = p_agenda and a.horario = g.horario and not a.encaixe
             and a.situacao not in ('cancelado', 'faltou') and a.id is distinct from p_ignorar)
    from crm.agenda_grade g where g.vagas > 0 order by g.horario
$$;

create or replace function public.painel_agenda_horarios(p_agenda uuid, p_ignorar uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform crm.exige('gestor', 'operacoes', 'comercial');
  return jsonb_build_object(
    'pode_encaixe', crm.pode_encaixe(),
    'horarios', coalesce((select jsonb_agg(jsonb_build_object('horario', to_char(h.horario, 'HH24:MI'), 'vagas', h.vagas,
                                                              'ocupadas', h.ocupadas, 'livres', greatest(h.vagas - h.ocupadas, 0))
                                           order by h.horario)
                            from crm.agenda_horarios(p_agenda, p_ignorar) h), '[]'::jsonb));
end $$;
revoke execute on function public.painel_agenda_horarios(uuid, uuid) from public, anon;
grant execute on function public.painel_agenda_horarios(uuid, uuid) to authenticated;

create or replace function public.painel_agenda_grade()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform crm.exige('gestor', 'operacoes', 'comercial');
  return coalesce((select jsonb_agg(jsonb_build_object('horario', to_char(g.horario, 'HH24:MI'), 'vagas', g.vagas) order by g.horario)
                     from crm.agenda_grade g where g.vagas > 0), '[]'::jsonb);
end $$;
revoke execute on function public.painel_agenda_grade() from public, anon;
grant execute on function public.painel_agenda_grade() to authenticated;

create or replace function public.painel_agenda_grade_salvar(p_grade jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare eu uuid; total int;
begin
  eu := crm.exige('gestor');
  if jsonb_typeof(p_grade) <> 'array' or jsonb_array_length(p_grade) = 0 then raise exception 'Informe ao menos um horário.'; end if;
  update crm.agenda_grade set vagas = 0, atualizado_em = now(), atualizado_por = eu where true;
  insert into crm.agenda_grade (horario, vagas, atualizado_por)
  select (x->>'horario')::time, greatest(coalesce((x->>'vagas')::int, 0), 0), eu from jsonb_array_elements(p_grade) x
  on conflict (horario) do update set vagas = excluded.vagas, atualizado_em = now(), atualizado_por = eu;
  select coalesce(sum(vagas), 0) into total from crm.agenda_grade;
  update crm.agenda_regra set vagas_padrao = greatest(total, 1), atualizado_em = now(), atualizado_por = eu where id;
  return public.painel_agenda_grade();
end $$;
revoke execute on function public.painel_agenda_grade_salvar(jsonb) from public, anon;
grant execute on function public.painel_agenda_grade_salvar(jsonb) to authenticated;

create or replace function public.painel_agenda_dia(p_data date, p_agenda uuid default null)
returns table(id uuid, numero bigint, agenda_id uuid, horario text, situacao text, tipo text, paciente_nome text, cpf text, telefone text,
              funcao text, empresa_id uuid, empresa text, encaixe boolean, inadimplente boolean, excecao_motivo text, cancelado_motivo text,
              observacao text, negocio_id uuid, chegou_em timestamptz, atendido_em timestamptz, finalizado_em timestamptz, criado_por text,
              criado_em timestamptz, complementares text[])
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
           g.chegou_em, g.atendido_em, g.finalizado_em,
           case when g.criado_via = 'ia' then 'IA (Lia)' else u.nome end::text, g.criado_em, g.complementares
      from crm.agendamento g
      join crm.agenda a on a.id = g.agenda_id
      left join public.empresa e on e.id = g.empresa_id
      left join crm.perfil u on u.user_id = g.criado_por
     where a.data = p_data and (p_agenda is null or g.agenda_id = p_agenda)
     order by case g.situacao when 'aguardando' then 0 when 'agendado' then 1 when 'atendido' then 2
                              when 'finalizado' then 3 when 'faltou' then 4 else 5 end,
              g.horario nulls last, g.chegou_em nulls last, g.numero;
end $$;

create or replace function public.painel_agendamento_salvar(p_id uuid, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  eu uuid; papel crm.papel; v_id uuid := p_id; atual crm.agendamento; chk jsonb;
  v_agenda uuid := nullif(p_dados->>'agenda_id', '')::uuid;
  v_empresa uuid := nullif(p_dados->>'empresa_id', '')::uuid;
  v_encaixe boolean := coalesce((p_dados->>'encaixe')::boolean, false);
  v_excecao text := nullif(trim(p_dados->>'excecao_motivo'), '');
  v_nome text := nullif(trim(p_dados->>'paciente_nome'), '');
  v_cpf text := nullif(regexp_replace(coalesce(p_dados->>'cpf', ''), '\D', '', 'g'), '');
  v_tipo text := coalesce(nullif(p_dados->>'tipo', ''), 'periodico');
  v_hora time := nullif(p_dados->>'horario', '')::time;
  v_comp text[] := coalesce((select array_agg(distinct upper(trim(x))) from jsonb_array_elements_text(
                              case when jsonb_typeof(p_dados->'complementares') = 'array' then p_dados->'complementares' else '[]'::jsonb end) x
                             where nullif(trim(x), '') is not null), '{}');
  mudou_vaga boolean := true;
  slot record;
  tem_grade boolean := exists (select 1 from crm.agenda_grade where vagas > 0);
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
                  or atual.encaixe <> v_encaixe or atual.horario is distinct from v_hora;
  end if;

  if v_encaixe and not crm.pode_encaixe() and not (v_id is not null and atual.encaixe) then
    raise exception 'Encaixe (além das 40 vagas) só o atendimento pode marcar. Escolha um horário vago.';
  end if;

  chk := crm.agenda_checar(v_agenda, v_empresa, v_encaixe, v_id, v_tipo);

  if mudou_vaga and not v_encaixe and tem_grade then
    if v_hora is null then
      chk := jsonb_set(chk, '{bloqueios}', (chk->'bloqueios') || to_jsonb('Escolha um horário da grade.'::text));
    else
      select * into slot from crm.agenda_horarios(v_agenda, v_id) h where h.horario = v_hora;
      if slot.horario is null then
        chk := jsonb_set(chk, '{bloqueios}', (chk->'bloqueios') || to_jsonb(format('%s não é um horário da grade.', to_char(v_hora, 'HH24:MI'))));
      elsif slot.ocupadas >= slot.vagas then
        chk := jsonb_set(chk, '{bloqueios}', (chk->'bloqueios') || to_jsonb(format('Horário %s lotado (%s/%s). Escolha outro horário ou marque encaixe.',
                                                                                   to_char(v_hora, 'HH24:MI'), slot.ocupadas, slot.vagas)));
      end if;
    end if;
  end if;

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
    values (v_agenda, v_hora, v_empresa,
            case when v_empresa is null then nullif(trim(p_dados->>'empresa_nome'), '') end,
            nullif(p_dados->>'colaborador_id', '')::uuid, v_nome, v_cpf,
            nullif(trim(p_dados->>'telefone'), ''), nullif(trim(p_dados->>'funcao'), ''),
            v_tipo, v_encaixe,
            case when mudou_vaga and jsonb_array_length(chk->'bloqueios') > 0 then v_excecao end,
            nullif(p_dados->>'negocio_id', '')::uuid, nullif(trim(p_dados->>'observacao'), ''), v_comp, eu)
    returning id into v_id;
    perform crm.agenda_registrar(v_id, 'Agendado' || case when v_encaixe then ' (encaixe)' else '' end);
  else
    update crm.agendamento set agenda_id = v_agenda, horario = v_hora,
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
                                            when atual.horario is distinct from v_hora then 'Horário: ' || coalesce(to_char(v_hora, 'HH24:MI'), 'sem horário')
                                            else 'Dados atualizados' end);
  end if;

  if mudou_vaga and jsonb_array_length(chk->'bloqueios') > 0 then
    perform crm.agenda_registrar(v_id, 'Liberado fora da regra: ' || v_excecao);
  end if;
  return jsonb_build_object('id', v_id, 'avisos', chk->'avisos');
end $$;

create or replace function crm.integracao_token_ok(p_token text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select c.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') from crm.wa_config c where c.id), false)
$$;
revoke execute on function crm.integracao_token_ok(text) from public, anon, authenticated;

create or replace function crm.agenda_clinica_do_dia(p_data date) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v uuid; total int; ini time; fim time;
begin
  select a.id into v from crm.agenda a where a.data = p_data and a.local = 'clinica' order by a.criado_em limit 1;
  if v is not null then return v; end if;
  select coalesce(sum(vagas), 40), min(horario) filter (where vagas > 0), max(horario) filter (where vagas > 0)
    into total, ini, fim from crm.agenda_grade;
  insert into crm.agenda (data, local, hora_inicio, hora_fim, vagas, observacao)
  values (p_data, 'clinica', ini, case when fim > ini then fim end, greatest(total, 1), 'Aberta automaticamente (agendamento pela IA)')
  returning id into v;
  return v;
end $$;

create or replace function public.integracao_agenda_horarios(p_token text, p_data date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_agenda uuid; agora timestamptz := now(); total_ocup int; total_vagas int;
begin
  if not crm.integracao_token_ok(p_token) then raise exception 'Token inválido.' using errcode = '42501'; end if;
  if p_data is null then raise exception 'Informe a data.'; end if;
  if extract(isodow from p_data) > 5 then
    return jsonb_build_object('data', p_data, 'disponivel', false, 'motivo', 'Agendamos só de segunda a sexta.', 'horarios', '[]'::jsonb);
  end if;
  select a.id, a.vagas into v_agenda, total_vagas from crm.agenda a where a.data = p_data and a.local = 'clinica' order by a.criado_em limit 1;
  select count(*) into total_ocup from crm.agendamento g where g.agenda_id = v_agenda and not g.encaixe and g.situacao not in ('cancelado','faltou');
  if v_agenda is not null and total_ocup >= total_vagas then
    return jsonb_build_object('data', p_data, 'disponivel', false, 'motivo', 'Agenda do dia lotada.', 'horarios', '[]'::jsonb);
  end if;
  return jsonb_build_object('data', p_data, 'disponivel', true, 'local', 'Vitalis Jardins — Rua das Acácias, 100',
    'horarios', coalesce((
      select jsonb_agg(jsonb_build_object('horario', to_char(h.horario, 'HH24:MI'), 'livres', h.vagas - h.ocupadas) order by h.horario)
        from (select g.horario, g.vagas,
                     (select count(*)::int from crm.agendamento a
                       where a.agenda_id = v_agenda and a.horario = g.horario and not a.encaixe and a.situacao not in ('cancelado','faltou')) ocupadas
                from crm.agenda_grade g where g.vagas > 0) h
       where h.vagas > h.ocupadas
         and (p_data + h.horario) at time zone 'America/Sao_Paulo' >= agora + interval '24 hours'), '[]'::jsonb));
end $$;
revoke execute on function public.integracao_agenda_horarios(text, date) from public;
grant execute on function public.integracao_agenda_horarios(text, date) to anon, authenticated, service_role;

create or replace function public.integracao_agendamento_criar(p_token text, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  d jsonb := coalesce(p_dados, '{}'::jsonb);
  v_data date := nullif(d->>'data', '')::date;
  v_hora time := nullif(d->>'horario', '')::time;
  v_nome text := nullif(trim(d->>'paciente_nome'), '');
  v_cpf text := nullif(regexp_replace(coalesce(d->>'cpf', ''), '\D', '', 'g'), '');
  v_cnpj text := nullif(regexp_replace(coalesce(d->>'empresa_cnpj', ''), '\D', '', 'g'), '');
  v_empresa_nome text := nullif(trim(d->>'empresa_nome'), '');
  v_tipo text := lower(coalesce(nullif(trim(d->>'tipo'), ''), ''));
  v_funcao text := nullif(trim(d->>'funcao'), '');
  v_tel text := nullif(regexp_replace(coalesce(d->>'telefone', ''), '\D', '', 'g'), '');
  v_empresa uuid; v_agenda uuid; chk jsonb; slot record; v_id uuid; v_num bigint; falta text[] := '{}';
begin
  if not crm.integracao_token_ok(p_token) then raise exception 'Token inválido.' using errcode = '42501'; end if;

  if v_nome is null then falta := array_append(falta, 'nome do paciente'::text); end if;
  if v_cpf is null then falta := array_append(falta, 'CPF'::text); end if;
  if v_cnpj is null and v_empresa_nome is null then falta := array_append(falta, 'empresa'::text); end if;
  if v_tipo = '' then falta := array_append(falta, 'tipo de exame'::text); end if;
  if v_funcao is null then falta := array_append(falta, 'função'::text); end if;
  if v_tel is null then falta := array_append(falta, 'telefone'::text); end if;
  if v_data is null or v_hora is null then falta := array_append(falta, 'data e horário'::text); end if;
  if cardinality(falta) > 0 then
    return jsonb_build_object('ok', false, 'motivo', 'Faltam: ' || array_to_string(falta, ', ') || '.', 'faltam', to_jsonb(falta));
  end if;
  if length(v_cpf) <> 11 then return jsonb_build_object('ok', false, 'motivo', 'CPF deve ter 11 dígitos.'); end if;

  v_tipo := case
    when v_tipo like 'admiss%' then 'admissional'
    when v_tipo like 'peri%' then 'periodico'
    when v_tipo like 'demiss%' then 'demissional'
    when v_tipo like 'mudan%' then 'mudanca_de_funcao'
    when v_tipo like 'retorno%' then 'retorno_ao_trabalho'
    when v_tipo like 'monitor%' then 'monitoracao_pontual'
    when v_tipo in ('admissional','periodico','demissional','mudanca_de_funcao','retorno_ao_trabalho','monitoracao_pontual','outro') then v_tipo
    else 'outro' end;

  if extract(isodow from v_data) > 5 then return jsonb_build_object('ok', false, 'motivo', 'Agendamos só de segunda a sexta.'); end if;
  if (v_data + v_hora) at time zone 'America/Sao_Paulo' < now() + interval '24 hours' then
    return jsonb_build_object('ok', false, 'motivo', 'Precisa de 24 horas de antecedência.');
  end if;

  if v_cnpj is not null then
    select e.id into v_empresa from public.empresa e where app.digits(e.cnpj) = v_cnpj
     order by (e.situacao = 'ativo') desc, e.updated_at desc limit 1;
  end if;

  v_agenda := crm.agenda_clinica_do_dia(v_data);
  select * into slot from crm.agenda_horarios(v_agenda, null) h where h.horario = v_hora;
  if slot.horario is null then return jsonb_build_object('ok', false, 'motivo', to_char(v_hora, 'HH24:MI') || ' não é um horário da agenda.'); end if;
  if slot.ocupadas >= slot.vagas then return jsonb_build_object('ok', false, 'motivo', 'Horário ' || to_char(v_hora, 'HH24:MI') || ' já está lotado.'); end if;

  chk := crm.agenda_checar(v_agenda, v_empresa, false, null, v_tipo);
  if jsonb_array_length(chk->'bloqueios') > 0 then
    return jsonb_build_object('ok', false, 'motivo', (select string_agg(x, ' ') from jsonb_array_elements_text(chk->'bloqueios') x),
                              'transferir_para_atendimento', true);
  end if;

  insert into crm.agendamento (agenda_id, horario, empresa_id, empresa_nome, paciente_nome, cpf, telefone, funcao, tipo,
                               encaixe, observacao, criado_via, ia_ref)
  values (v_agenda, v_hora, v_empresa,
          case when v_empresa is null then coalesce(v_empresa_nome, 'CNPJ ' || v_cnpj) end,
          v_nome, v_cpf, v_tel, v_funcao, v_tipo, false,
          nullif(trim(concat_ws(E'\n',
            case when v_empresa is null and v_cnpj is not null then 'CNPJ informado: ' || v_cnpj end,
            nullif(trim(d->>'observacao'), ''))), ''),
          'ia', nullif(trim(d->>'ref'), ''))
  returning id, numero into v_id, v_num;
  perform crm.agenda_registrar(v_id, 'Agendado pela IA (Lia) no WhatsApp');

  return jsonb_build_object('ok', true, 'numero', v_num, 'data', v_data, 'horario', to_char(v_hora, 'HH24:MI'),
                            'local', 'Vitalis Jardins — Rua das Acácias, 100', 'empresa_identificada', v_empresa is not null,
                            'avisos', chk->'avisos');
end $$;
revoke execute on function public.integracao_agendamento_criar(text, jsonb) from public;
grant execute on function public.integracao_agendamento_criar(text, jsonb) to anon, authenticated, service_role;
