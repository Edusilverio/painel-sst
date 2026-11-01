-- Painel SST — base de DEMONSTRAÇÃO (estrutura). Dados 100% fictícios.
-- Schemas: pn (API do painel, exposto no PostgREST), pn_crm, pn_app, pn_sesmo, pn_bitrix.
create extension if not exists unaccent with schema public;
create extension if not exists pg_trgm with schema public;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists pn;
set check_function_bodies = false;



SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE SCHEMA IF NOT EXISTS pn_app;

CREATE SCHEMA IF NOT EXISTS pn_bitrix;

CREATE SCHEMA IF NOT EXISTS pn_crm;


CREATE SCHEMA IF NOT EXISTS pn_sesmo;

CREATE TYPE pn_crm.papel AS ENUM (
    'admin',
    'gestor',
    'comercial',
    'operacoes',
    'financeiro',
    'leitura'
);

CREATE TYPE pn_crm.tipo_etapa AS ENUM (
    'aberta',
    'ganho',
    'perdido'
);

CREATE TYPE pn.evento_esocial AS ENUM (
    'S-2210',
    'S-2220',
    'S-2221',
    'S-2240',
    'S-3000',
    'S-1060',
    'OUTRO'
);

CREATE TYPE pn.grupo_risco AS ENUM (
    'fisico',
    'quimico',
    'biologico',
    'ergonomico',
    'acidente',
    'inespecifico'
);

CREATE TYPE pn.origem_arquivo AS ENUM (
    'sesmo_armazenado',
    'sesmo_gerado',
    'servidor_vitalis',
    'upload_manual'
);

CREATE TYPE pn.origem_registro AS ENUM (
    'sesmo_exportacao',
    'sesmo_robo',
    'sgg',
    'manual',
    'importacao'
);

CREATE TYPE pn.resultado_aso AS ENUM (
    'pendente',
    'apto',
    'apto_com_restricao',
    'inapto'
);

CREATE TYPE pn.resultado_exame AS ENUM (
    'pendente',
    'normal',
    'alterado',
    'nao_realizado'
);

CREATE TYPE pn.situacao_atendimento AS ENUM (
    'agendado',
    'aguardando',
    'atendido',
    'finalizado',
    'cancelado',
    'faltou'
);

CREATE TYPE pn.situacao_colaborador AS ENUM (
    'ativo',
    'afastado',
    'desligado',
    'inativo'
);

CREATE TYPE pn.situacao_documento AS ENUM (
    'em_elaboracao',
    'vigente',
    'vencido',
    'cancelado'
);

CREATE TYPE pn.situacao_empresa AS ENUM (
    'ativo',
    'sem_contrato',
    'inativo'
);

CREATE TYPE pn.situacao_evento_esocial AS ENUM (
    'pendente',
    'em_lote',
    'transmitido',
    'processado',
    'rejeitado',
    'excluido',
    'inconsistente'
);

CREATE TYPE pn.tipo_documento AS ENUM (
    'PGR',
    'PCMSO',
    'LTCAT',
    'LTIP',
    'PPR',
    'PCA',
    'PPP',
    'OUTRO'
);

CREATE TYPE pn.tipo_exame_ocupacional AS ENUM (
    'admissional',
    'periodico',
    'demissional',
    'mudanca_de_funcao',
    'retorno_ao_trabalho',
    'monitoracao_pontual',
    'mudanca_de_riscos'
);

CREATE TYPE pn.tipo_profissional AS ENUM (
    'medico',
    'enfermeiro',
    'tecnico_enfermagem',
    'tecnico_seguranca',
    'engenheiro',
    'fonoaudiologo',
    'outro'
);

CREATE FUNCTION pn_app.digits(t text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select nullif(regexp_replace(coalesce(t,''), '\D', '', 'g'), '')
$$;

CREATE FUNCTION pn_app.norm(t text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pn', 'pg_catalog'
    AS $$
  select lower(public.unaccent('public.unaccent'::regdictionary, coalesce(t,'')))
$$;

CREATE FUNCTION pn_app.recalcular_vencimentos() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare hoje date := (now() at time zone 'America/Sao_Paulo')::date; n int;
begin
  create temp table _col on commit drop as
    select c.id, c.nome, c.cpf, c.matricula_esocial, c.empresa_id, c.data_admissao,
           coalesce(nullif(e.nome_fantasia, ''), e.razao_social) empresa, un.nome unidade,
           coalesce(c.funcao_id, (select f.id from pn.funcao f join pn.setor s on s.id = f.setor_id
                                   where s.unidade_id = c.unidade_id and lower(btrim(f.nome)) = lower(btrim(c.funcao_nome))
                                   order by f.sesmo_situacao_codigo desc nulls last limit 1)) funcao_id,
           c.setor_id, c.setor_nome, c.funcao_nome,
           (select max(a.data_atendimento) from pn.atendimento a
             where a.colaborador_id = c.id and a.situacao in ('atendido','finalizado') and a.tipo <> 'demissional') ultimo_aso
      from pn.colaborador c
      join pn.empresa e on e.id = c.empresa_id and e.situacao = 'ativo'
      left join pn.unidade un on un.id = c.unidade_id
     where c.situacao = 'ativo';
  create index on _col (id);

  create temp table _req on commit drop as
    select c.id colaborador_id, fe.exame_nome exame, fe.exame_tipo_id, fe.periodicidade_meses, fe.periodicidade_texto, fe.primeira_meses
      from _col c join pn.funcao_exame fe on fe.funcao_id = c.funcao_id
     where fe.no_periodico and fe.ocupacional and fe.periodicidade_meses is not null
    union all

    select c.id, 'Exame Clínico', (select et.id from pn.exame_tipo et where et.nome = 'Exame Clínico' order by et.sesmo_id limit 1),
           12, 'padrão (função sem PCMSO)', null
      from _col c
     where not exists (select 1 from pn.funcao_exame fe where fe.funcao_id = c.funcao_id and fe.no_periodico and fe.periodicidade_meses is not null);

  truncate pn_app.vencimento_exame;
  insert into pn_app.vencimento_exame (colaborador_id, exame, exame_tipo_id, periodicidade_meses, periodicidade_texto,
                                    ultima, origem_ultima, proxima, status)
  select distinct on (r.colaborador_id, r.exame)
         r.colaborador_id, r.exame, r.exame_tipo_id, r.periodicidade_meses, r.periodicidade_texto,
         coalesce(ex.d, c.ultimo_aso), case when ex.d is not null then 'exame' when c.ultimo_aso is not null then 'aso' end,
         p.proxima,
         case when coalesce(ex.d, c.ultimo_aso) is null then 'nunca_realizado'
              when p.proxima < hoje then 'vencido'
              when p.proxima <= hoje + 30 then 'vence_em_30_dias'
              when p.proxima <= hoje + 60 then 'vence_em_60_dias'
              else 'em_dia' end
    from _req r
    join _col c on c.id = r.colaborador_id
    left join lateral (select max(coalesce(ae.data_realizacao, a.data_atendimento)) d
                         from pn.atendimento_exame ae join pn.atendimento a on a.id = ae.atendimento_id
                        where a.colaborador_id = r.colaborador_id and ae.exame_tipo_id = r.exame_tipo_id
                          and ae.resultado <> 'nao_realizado') ex on r.exame_tipo_id is not null
    cross join lateral (select (coalesce(ex.d, c.ultimo_aso)
             + make_interval(months => case when r.primeira_meses is not null and c.data_admissao is not null
                                             and coalesce(ex.d, c.ultimo_aso) <= c.data_admissao + 30
                                            then r.primeira_meses else r.periodicidade_meses end))::date proxima) p
   order by r.colaborador_id, r.exame, r.periodicidade_meses;

  truncate pn_app.vencimento;
  insert into pn_app.vencimento (colaborador_id, colaborador, cpf, matricula_esocial, empresa_id, empresa, unidade, setor, funcao,
                              proximo_exame, dias_para_vencer, exames_vencidos, exames_nunca_feitos, status, ultimo_aso, tem_pcmso)
  select c.id, c.nome, c.cpf, c.matricula_esocial, c.empresa_id, c.empresa, c.unidade,
         coalesce(s.nome, c.setor_nome), coalesce(f.nome, c.funcao_nome),
         min(v.proxima), min(v.proxima) - hoje,
         count(*) filter (where v.status = 'vencido'), count(*) filter (where v.status = 'nunca_realizado'),
         case when count(*) filter (where v.status in ('vencido','nunca_realizado')) > 0 then 'vencido'
              when min(v.proxima) - hoje <= 30 then 'vence_em_30_dias'
              when min(v.proxima) - hoje <= 60 then 'vence_em_60_dias'
              else 'em_dia' end,
         c.ultimo_aso,
         exists (select 1 from pn.funcao_exame fe where fe.funcao_id = c.funcao_id)
    from _col c
    join pn_app.vencimento_exame v on v.colaborador_id = c.id
    left join pn.setor s on s.id = c.setor_id
    left join pn.funcao f on f.id = c.funcao_id
   group by c.id, c.nome, c.cpf, c.matricula_esocial, c.empresa_id, c.empresa, c.unidade, s.nome, c.setor_nome, f.nome, c.funcao_nome,
            c.ultimo_aso, c.funcao_id;
  get diagnostics n = row_count;
  return jsonb_build_object('colaboradores', n, 'exames', (select count(*) from pn_app.vencimento_exame));
end $$;

CREATE FUNCTION pn_app.touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  new.updated_at = now();
  return new;
end $$;

CREATE FUNCTION pn_crm.abrir_renovacao(p_empresa uuid, p_titulo text, p_cliente_nome text, p_responsavel uuid, p_valor numeric, p_origem_card uuid, p_motivo text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare fc uuid; et uuid; novo uuid; t text;
begin
  select f.id, e.id into fc, et from pn_crm.funil f join pn_crm.etapa e on e.funil_id = f.id and e.nome = 'Renovação' and e.ativo
   where f.slug = 'comercial';
  if et is null then return null; end if;

  select n.id into novo from pn_crm.negocio n join pn_crm.etapa e on e.id = n.etapa_id and e.tipo = 'aberta'
   where n.funil_id = fc and n.origem = 'renovacao' and p_empresa is not null and n.empresa_id = p_empresa
   order by n.criado_em desc limit 1;
  if novo is not null then
    insert into pn_crm.evento (negocio_id, tipo, texto) values (novo, 'nota', p_motivo);
    return novo;
  end if;
  t := 'Renovação: ' || regexp_replace(coalesce(p_titulo, p_cliente_nome, 'cliente'), '^(Renovação|Inadimplência): ', '');
  insert into pn_crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, responsavel_id, valor, origem,
                           negocio_origem_id, observacao)
  values (fc, et, t, p_empresa, p_cliente_nome, coalesce(p_responsavel, pn_crm.responsavel_cliente(p_empresa)),
          coalesce(p_valor, 0), 'renovacao', p_origem_card, p_motivo)
  returning id into novo;
  if p_origem_card is not null then
    insert into pn_crm.negocio_item (negocio_id, produto_id, descricao, quantidade, preco_unitario)
    select novo, i.produto_id, i.descricao, i.quantidade, i.preco_unitario from pn_crm.negocio_item i where i.negocio_id = p_origem_card;
  end if;
  insert into pn_crm.evento (negocio_id, tipo, texto) values (novo, 'criado', p_motivo);
  insert into pn_crm.notificacao (user_id, negocio_id, tipo, texto)
  select r, novo, 'renovacao', 'Renovação para fazer: ' || t
    from (select coalesce(p_responsavel, pn_crm.responsavel_cliente(p_empresa)) r) x where r is not null;
  return novo;
end $$;

CREATE FUNCTION pn_crm.agenda_checar(p_agenda uuid, p_empresa uuid, p_encaixe boolean, p_ignorar uuid DEFAULT NULL::uuid, p_tipo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  a pn_crm.agenda; r pn_crm.agenda_regra;
  ocupadas int; na_empresa int := 0; inad boolean := false; sit text; limite int; proprio boolean := false;
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  bloqueios text[] := '{}'; avisos text[] := '{}';
begin
  select * into a from pn_crm.agenda where id = p_agenda;
  if a.id is null then raise exception 'Agenda não encontrada.'; end if;
  select * into r from pn_crm.agenda_regra where id;

  select count(*) into ocupadas from pn_crm.agendamento g
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
    select l.limite into limite from pn_crm.agenda_limite_empresa l where l.empresa_id = p_empresa;
    proprio := limite is not null;
    limite := coalesce(limite, r.limite_empresa_dia);
    select count(*) into na_empresa from pn_crm.agendamento g join pn_crm.agenda ag on ag.id = g.agenda_id
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

    inad := pn_crm.empresa_inadimplente(p_empresa);
    if inad and r.bloquear_inadimplente then
      bloqueios := array_append(bloqueios, 'Empresa inadimplente (Pós-venda → Inadimplentes). Fale com o financeiro.');
    elsif inad then
      avisos := array_append(avisos, 'Empresa marcada como inadimplente no Pós-venda.');
    end if;

    select e.situacao::text into sit from pn.empresa e where e.id = p_empresa;
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

CREATE FUNCTION pn_crm.agenda_clinica_do_dia(p_data date) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v uuid; total int; ini time; fim time;
begin
  select a.id into v from pn_crm.agenda a where a.data = p_data and a.local = 'clinica' order by a.criado_em limit 1;
  if v is not null then return v; end if;
  select coalesce(sum(vagas), 40), min(horario) filter (where vagas > 0), max(horario) filter (where vagas > 0)
    into total, ini, fim from pn_crm.agenda_grade;
  insert into pn_crm.agenda (data, local, hora_inicio, hora_fim, vagas, observacao)
  values (p_data, 'clinica', ini, case when fim > ini then fim end, coalesce((select rg.vagas_padrao from pn_crm.agenda_regra rg where rg.id), 40), 'Aberta automaticamente (agendamento pela IA)')
  returning id into v;
  return v;
end $$;

CREATE FUNCTION pn_crm.agenda_horarios(p_agenda uuid, p_ignorar uuid DEFAULT NULL::uuid) RETURNS TABLE(horario time without time zone, vagas integer, ocupadas integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select g.horario, g.vagas,
         (select count(*)::int from pn_crm.agendamento a
           where a.agenda_id = p_agenda and a.horario = g.horario and not a.encaixe
             and a.situacao not in ('cancelado', 'faltou') and a.id is distinct from p_ignorar)
    from pn_crm.agenda_grade g where g.vagas > 0 order by g.horario
$$;

CREATE FUNCTION pn_crm.agenda_registrar(p_agendamento uuid, p_texto text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  insert into pn_crm.agendamento_evento (agendamento_id, texto, autor_id) values (p_agendamento, p_texto, auth.uid())
$$;

CREATE FUNCTION pn_crm.agenda_rotulo(p_situacao text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select case p_situacao
    when 'agendado' then 'Agendado' when 'aguardando' then 'Aguardando'
    when 'atendido' then 'Atendido' when 'finalizado' then 'Finalizado'
    when 'cancelado' then 'Cancelado' when 'faltou' then 'Faltou' else p_situacao end
$$;

CREATE FUNCTION pn_crm.alertas_contratos() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r record; qtd int := 0; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        etapa_base uuid; etapa_ok uuid; destino uuid; neg uuid; pv uuid;
begin
  select e.id into etapa_base from pn_crm.etapa e join pn_crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda'
   where e.nome ilike 'contratos%' and e.ativo limit 1;
  select e.id into etapa_ok from pn_crm.etapa e join pn_crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda'
   where e.tipo = 'ganho' and e.ativo order by e.ordem limit 1;

  update pn_crm.contrato c set renovacao_negocio_id = null
    from pn_crm.negocio n join pn_crm.etapa e on e.id = n.etapa_id
   where n.id = c.renovacao_negocio_id and e.tipo <> 'aberta';

  for r in
    select c.*, coalesce(nullif(em.nome_fantasia, ''), em.razao_social, c.cliente_nome) as cliente
      from pn_crm.contrato c left join pn.empresa em on em.id = c.empresa_id
     where c.status = 'assinado' and c.fim is not null and c.fim <= hoje + c.aviso_dias
       and (c.ultimo_alerta_em is null or c.ultimo_alerta_em <= hoje - 7)
  loop
    destino := coalesce(r.responsavel_id, pn_crm.responsavel_cliente(r.empresa_id),
                        (select p.user_id from pn_crm.perfil p where p.ativo and p.papel = 'gestor' order by p.nome limit 1));
    if destino is not null then
      insert into pn_crm.notificacao (user_id, contrato_id, tipo, texto)
      values (destino, r.id, 'renovacao',
              case when r.fim < hoje then 'Contrato vencido: ' else 'Contrato vence em ' || to_char(r.fim, 'DD/MM') || ': ' end || r.cliente);
    end if;
    if r.renovacao_negocio_id is null then
      pv := null;
      if r.empresa_id is not null then
        select n.id into pv from pn_crm.negocio n where n.empresa_id = r.empresa_id and n.etapa_id = etapa_base order by n.criado_em desc limit 1;
      end if;
      neg := pn_crm.abrir_renovacao(r.empresa_id, coalesce((select titulo from pn_crm.negocio where id = pv), r.cliente), r.cliente_nome,
               r.responsavel_id, coalesce(r.valor_total, 0), pv,
               'Contrato #' || r.numero || ' vence em ' || to_char(r.fim, 'DD/MM/YYYY'));
      if neg is not null then
        update pn_crm.contrato set renovacao_negocio_id = neg where id = r.id;
        insert into pn_crm.contrato_evento (contrato_id, texto) values (r.id, 'Aviso de renovação: card em Comercial › Renovação');
        if pv is not null and etapa_ok is not null then
          perform pn_crm.posvenda_mover(pv, etapa_ok, 'Contrato #' || r.numero || ' perto do fim: enviado ao Comercial › Renovação', false);
        end if;
      end if;
    end if;
    update pn_crm.contrato set ultimo_alerta_em = hoje where id = r.id;
    qtd := qtd + 1;
  end loop;
  return qtd;
end $$;

CREATE FUNCTION pn_crm.alertas_documentos() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r record; n int := 0; aviso int; funil_l uuid; etapa_l uuid; neg uuid; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  select aviso_dias into aviso from pn_crm.documento_regra where id;
  select f.id into funil_l from pn_crm.funil f where f.slug = 'laudos';
  select e.id into etapa_l from pn_crm.etapa e where e.funil_id = funil_l and e.tipo = 'aberta' and e.ativo order by e.ordem limit 1;
  if etapa_l is null then return 0; end if;
  for r in
    select d.id, d.tipo::text tipo, d.vigencia_fim, d.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social) nome
      from pn.documento d join pn.empresa e on e.id = d.empresa_id
     where d.situacao::text not in ('cancelado','em_elaboracao') and d.vigencia_fim is not null
       and d.vigencia_fim <= hoje + aviso
       and not exists (select 1 from pn_crm.documento_renovacao x where x.documento_id = d.id)
  loop
    insert into pn_crm.negocio (funil_id, etapa_id, titulo, empresa_id, origem, observacao)
    values (funil_l, etapa_l, 'Renovar ' || r.tipo || ': ' || r.nome, r.empresa_id, 'renovacao',
            r.tipo || ' vence em ' || to_char(r.vigencia_fim, 'DD/MM/YYYY'))
    returning id into neg;
    insert into pn_crm.evento (negocio_id, tipo, texto) values (neg, 'criado', 'Aberto pelo vencimento do ' || r.tipo);
    insert into pn_crm.documento_renovacao (documento_id, negocio_id) values (r.id, neg);
    n := n + 1;
  end loop;
  return n;
end $$;

CREATE FUNCTION pn_crm.alertas_tarefas() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r record; x uuid; qtd int := 0; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  for r in
    select t.id, t.titulo, t.prazo, t.responsaveis from pn_crm.tarefa t
     where t.status <> 'feito' and t.prazo is not null and t.prazo <= hoje
       and cardinality(t.responsaveis) > 0 and t.ultimo_alerta_em is distinct from hoje
  loop
    foreach x in array r.responsaveis loop
      insert into pn_crm.notificacao (user_id, tarefa_id, tipo, texto)
      values (x, r.id, 'prazo', case when r.prazo = hoje then 'Vence hoje: ' else 'Atrasada: ' end || r.titulo);
      qtd := qtd + 1;
    end loop;
    update pn_crm.tarefa set ultimo_alerta_em = hoje where id = r.id;
  end loop;
  return qtd;
end $$;

CREATE FUNCTION pn_crm.aplicar_pre_cadastro(p_user uuid, p_email text, p_confirmado boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare pc pn_crm.pre_cadastro; f uuid;
begin
  select * into pc from pn_crm.pre_cadastro where email = lower(trim(p_email));
  if pc.email is null then return; end if;
  update pn_crm.perfil set nome = pc.nome, papel = pc.papel, libera_agenda = pc.libera_agenda,
                        telefone = coalesce(telefone, pc.telefone),
                        ativo = ativo or p_confirmado
   where user_id = p_user and (not ativo or p_confirmado);
  if p_confirmado then
    update pn_crm.pre_cadastro set usado_em = coalesce(usado_em, now()) where email = pc.email;
    if pc.rodizio_ordem is not null then
      select id into f from pn_crm.funil where slug = 'comercial';
      insert into pn_crm.rodizio (funil_id, user_id, ordem, ativo) values (f, p_user, pc.rodizio_ordem, true)
      on conflict (funil_id, user_id) do nothing;
    end if;
    perform pn_crm.bitrix_atribuir(p_user, pc.email);
  end if;
end $$;

CREATE FUNCTION pn_crm.atestado_mes(p_inicio date, p_emissao date, p_criado timestamp with time zone) RETURNS date
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select date_trunc('month', coalesce(p_inicio, p_emissao, (p_criado at time zone 'America/Sao_Paulo')::date))::date
$$;

CREATE FUNCTION pn_crm.atestado_verificar(p_empresa uuid, p_mes date) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  r pn_crm.atestado_regra; qtd int; resp uuid; v_nome text; rotulo text; v_tarefa uuid; v_neg uuid;
  v_funil uuid; v_etapa uuid; v_quadro uuid; tel text; lista text;
begin
  if p_empresa is null or p_mes is null then return false; end if;
  select * into r from pn_crm.atestado_regra where id;
  if not r.ativo then return false; end if;
  select count(*) into qtd from pn_crm.atestado where empresa_id = p_empresa and mes = p_mes and situacao = 'ok';

  if exists (select 1 from pn_crm.atestado_alerta where empresa_id = p_empresa and mes = p_mes) then
    update pn_crm.atestado_alerta set quantidade = qtd where empresa_id = p_empresa and mes = p_mes and quantidade <> qtd;
    return false;
  end if;
  if qtd < r.limite then return false; end if;

  select coalesce(nullif(e.nome_fantasia, ''), e.razao_social) into v_nome from pn.empresa e where e.id = p_empresa;
  rotulo := to_char(p_mes, 'MM/YYYY');
  resp := coalesce(pn_crm.responsavel_cliente(p_empresa),
                   (select p.user_id from pn_crm.perfil p where p.ativo and p.papel = 'gestor' order by p.nome limit 1));
  select string_agg(coalesce(a.colaborador_nome, '(sem nome)') || coalesce(' — ' || to_char(a.data_inicio, 'DD/MM'), '')
                    || coalesce(' (' || a.dias || ' dia' || case when a.dias = 1 then '' else 's' end || ')', ''), E'\n' order by a.data_inicio nulls last, a.criado_em)
    into lista from pn_crm.atestado a where a.empresa_id = p_empresa and a.mes = p_mes and a.situacao = 'ok';

  select id into v_quadro from pn_crm.quadro where nome = 'Atestados' and not arquivado order by criado_em limit 1;
  if v_quadro is not null then
    insert into pn_crm.tarefa (quadro_id, titulo, prioridade, prazo, responsavel_id, notas, empresa_id)
    values (v_quadro, 'Agendar consulta: ' || v_nome || ' (' || qtd || ' atestados em ' || rotulo || ')', 'alta',
            (now() at time zone 'America/Sao_Paulo')::date + r.prazo_dias, resp,
            'A empresa chegou a ' || qtd || ' atestados em ' || rotulo || '. Entrar em contato para agendar consulta médica.' || E'\n\nAtestados:\n' || lista,
            p_empresa)
    returning id into v_tarefa;
  end if;

  select f.id into v_funil from pn_crm.funil f where f.slug = 'pos-venda';
  select e.id into v_etapa from pn_crm.etapa e where e.funil_id = v_funil and e.nome = 'Agendar consulta' and e.ativo;
  if v_etapa is not null then
    insert into pn_crm.negocio (funil_id, etapa_id, titulo, empresa_id, responsavel_id, valor, origem, observacao)
    values (v_funil, v_etapa, 'Atestados ' || rotulo || ': ' || v_nome, p_empresa, resp, 0, 'atestados',
            qtd || ' atestados em ' || rotulo || '. Agendar consulta médica com a empresa.')
    returning id into v_neg;
    insert into pn_crm.evento (negocio_id, tipo, texto) values (v_neg, 'criado', 'Aberto pelo alerta de atestados (' || qtd || ' em ' || rotulo || ')');
    if v_tarefa is not null then update pn_crm.tarefa set negocio_id = v_neg where id = v_tarefa; end if;
  end if;

  if resp is not null then
    insert into pn_crm.notificacao (user_id, negocio_id, tarefa_id, tipo, texto)
    values (resp, v_neg, v_tarefa, 'atestados', v_nome || ': ' || qtd || ' atestados em ' || rotulo || ' — agendar consulta médica');

    select pn_crm.so_digitos(p.telefone) into tel from pn_crm.perfil p where p.user_id = resp;
    if length(tel) in (10, 11) then tel := '55' || tel; end if;
    if tel is not null then
      insert into pn_crm.wa_saida (telefone, texto, origem, ref_id)
      values (tel, 'Vitalis Painel: ' || v_nome || ' chegou a ' || qtd || ' atestados em ' || rotulo
                   || '. Agendar consulta médica com a empresa. A tarefa já está no seu painel.', 'atestados', p_empresa::text);
    end if;
  end if;

  insert into pn_crm.atestado_alerta (empresa_id, mes, quantidade, responsavel_id, tarefa_id, negocio_id)
  values (p_empresa, p_mes, qtd, resp, v_tarefa, v_neg);
  return true;
end $$;

CREATE FUNCTION pn_crm.bitrix_atribuir(p_user uuid, p_email text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare n int;
begin
  update pn_crm.negocio n set responsavel_id = p_user, bitrix_sincronizado_em = now(), atualizado_em = now()
    from pn_crm.bitrix_usuario bu
   where bu.email_painel = lower(trim(p_email)) and n.bitrix_responsavel = bu.bitrix_id and n.responsavel_id is null;
  get diagnostics n = row_count;
  return n;
end $$;

CREATE FUNCTION pn_crm.bitrix_consolidar_posvenda() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r record; qtd int := 0; base uuid; ok uuid;
begin
  select e.id into base from pn_crm.etapa e join pn_crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda' where e.nome = 'Contratos fechados';
  select e.id into ok from pn_crm.etapa e join pn_crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda' where e.nome = 'Concluído';
  if base is null or ok is null then return 0; end if;
  for r in
    select n.id, x.mais_novo, x.quando from pn_crm.negocio n
      join lateral (select m.numero mais_novo, m.criado_em quando from pn_crm.negocio m
                     where m.etapa_id = base and m.bitrix_empresa = n.bitrix_empresa and m.criado_em > n.criado_em
                     order by m.criado_em desc limit 1) x on true
     where n.etapa_id = base and n.bitrix_id is not null and n.bitrix_empresa is not null
  loop
    perform pn_crm.posvenda_mover(r.id, ok, 'Importação do Bitrix: substituído pelo card mais recente do cliente (#' || r.mais_novo || ')', false);

    update pn_crm.negocio set fechado_em = r.quando, entrou_etapa_em = r.quando, bitrix_sincronizado_em = now(), atualizado_em = now() where id = r.id;
    qtd := qtd + 1;
  end loop;
  return qtd;
end $$;

CREATE FUNCTION pn_crm.bitrix_importar_historico() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare etapas int; ativ int; itens int;
begin

  with h as (
    select s.c, n.id negocio_id, (s.c->>'OWNER_ID')::bigint deal, (s.c->>'CREATED_TIME')::timestamptz em,
           e.id etapa_id,
           lag(e.id) over (partition by s.c->>'OWNER_ID' order by (s.c->>'CREATED_TIME')::timestamptz, (s.c->>'ID')::bigint) de_id
      from pn_crm.bx_atual('crm.stagehistory.2') s
      join pn_crm.negocio n on n.bitrix_id = (s.c->>'OWNER_ID')::bigint
      left join pn_crm.bitrix_etapa be on be.stage_id = s.c->>'STAGE_ID'
      left join pn_crm.funil f on f.slug = be.funil_slug
      left join pn_crm.etapa e on e.funil_id = f.id and e.nome = be.etapa_nome
  )
  insert into pn_crm.evento (negocio_id, tipo, texto, de_etapa_id, para_etapa_id, criado_em, bitrix_ref)
  select h.negocio_id, case when h.c->>'TYPE_ID' = '1' then 'criado' else 'etapa' end,
         case when h.c->>'TYPE_ID' = '1' then 'Criado no Bitrix' else 'Bitrix' end,
         case when h.c->>'TYPE_ID' = '1' then null else h.de_id end, h.etapa_id, h.em, 'sh:' || (h.c->>'ID')
    from h
  on conflict (bitrix_ref) do nothing;
  get diagnostics etapas = row_count;

  insert into pn_crm.evento (negocio_id, tipo, texto, criado_em, bitrix_ref)
  select n.id,
         case when a.c->>'TYPE_ID' = '1' then 'reuniao' when a.c->>'TYPE_ID' = '2' then 'ligacao'
              when a.c->>'TYPE_ID' = '4' then 'email' when a.c->>'PROVIDER_ID' = 'IMOPENLINES_SESSION' then 'whatsapp'
              else 'nota' end,
         left(concat_ws(E'\n',
           case a.c->>'PROVIDER_ID' when 'CRM_TASKS_TASK' then 'Tarefa: ' when 'CRM_TODO' then 'A fazer: '
                                    when 'CRM_WEBFORM' then 'Formulário: ' else '' end || coalesce(pn_crm.bx_txt(a.c->>'SUBJECT'), ''),
           pn_crm.bx_txt(a.c->>'DESCRIPTION'),
           case when a.c->>'COMPLETED' = 'Y' then '(concluída no Bitrix)' end,
           '— ' || coalesce((select bu.nome from pn_crm.bitrix_usuario bu where bu.bitrix_id = (a.c->>'RESPONSIBLE_ID')::int), 'Bitrix')), 4000),
         coalesce((a.c->>'CREATED')::timestamptz, now()), 'act:' || a.chave
    from pn_crm.bx_atual('crm.activity') a
    join pn_crm.negocio n on n.bitrix_id = (a.c->>'OWNER_ID')::bigint
   where a.c->>'OWNER_TYPE_ID' = '2'
  on conflict (bitrix_ref) do nothing;
  get diagnostics ativ = row_count;

  insert into pn_crm.negocio_item as t (negocio_id, produto_id, descricao, quantidade, preco_unitario, bitrix_id)
  select n.id,
         (select p.id from pn_crm.produto p where pn_crm.bx_chave(p.nome) = pn_crm.bx_chave(r->>'PRODUCT_NAME') limit 1),
         coalesce(nullif(btrim(r->>'PRODUCT_NAME'), ''), 'Item do Bitrix'),
         greatest(coalesce((r->>'QUANTITY')::numeric, 1), 0.01), greatest(coalesce((r->>'PRICE')::numeric, 0), 0), (r->>'ID')::bigint
    from pn_crm.bx_atual('crm.deal.productrows') x
    join pn_crm.negocio n on n.bitrix_id = x.chave::bigint
    cross join lateral jsonb_array_elements(case when jsonb_typeof(x.c) = 'array' then x.c else '[]'::jsonb end) r
  on conflict (bitrix_id) do update set descricao = excluded.descricao, quantidade = excluded.quantidade, preco_unitario = excluded.preco_unitario
   where (t.descricao, t.quantidade, t.preco_unitario) is distinct from (excluded.descricao, excluded.quantidade, excluded.preco_unitario);
  get diagnostics itens = row_count;
  return jsonb_build_object('etapas', etapas, 'atividades', ativ, 'itens', itens);
end $$;

CREATE FUNCTION pn_crm.bitrix_importar_negocios() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ins int; upd int;
begin
  insert into pn_crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, cliente_cnpj, contato_nome, contato_telefone,
                           contato_email, responsavel_id, valor, origem, previsao_fechamento, motivo_perda, observacao,
                           entrou_etapa_em, fechado_em, criado_em, atualizado_em, bitrix_id, bitrix_responsavel, bitrix_sincronizado_em, bitrix_empresa,
                           qtd_funcionarios, forma_pagamento, parcelas)
  select funil_id, etapa_id, titulo, empresa_id, cliente_nome, cliente_cnpj, contato_nome, contato_telefone, contato_email,
         responsavel_id, valor, 'bitrix', previsao, motivo_perda, observacao, entrou_etapa_em, fechado_em, criado_em, now(),
         id, bitrix_responsavel, now(), bitrix_empresa, qtd_funcionarios, forma_pagamento, parcelas
    from pn_crm.vw_bitrix_negocio x where not exists (select 1 from pn_crm.negocio n where n.bitrix_id = x.id);
  get diagnostics ins = row_count;
  update pn_crm.negocio n set
    funil_id = x.funil_id, etapa_id = x.etapa_id, titulo = x.titulo, empresa_id = coalesce(n.empresa_id, x.empresa_id),
    cliente_nome = x.cliente_nome, cliente_cnpj = x.cliente_cnpj, contato_nome = x.contato_nome,
    contato_telefone = x.contato_telefone, contato_email = x.contato_email,
    responsavel_id = coalesce(n.responsavel_id, x.responsavel_id), bitrix_responsavel = x.bitrix_responsavel, bitrix_empresa = x.bitrix_empresa,
    valor = x.valor, previsao_fechamento = x.previsao, motivo_perda = x.motivo_perda, observacao = x.observacao,
    entrou_etapa_em = x.entrou_etapa_em, fechado_em = x.fechado_em,
    qtd_funcionarios = x.qtd_funcionarios, forma_pagamento = x.forma_pagamento, parcelas = x.parcelas,
    atualizado_em = now(), bitrix_sincronizado_em = now()
    from pn_crm.vw_bitrix_negocio x
   where n.bitrix_id = x.id and n.atualizado_em <= n.bitrix_sincronizado_em + interval '1 second'
     and (n.etapa_id, n.titulo, n.valor, coalesce(n.observacao, ''), n.qtd_funcionarios, n.forma_pagamento, n.parcelas)
         is distinct from (x.etapa_id, x.titulo, x.valor, coalesce(x.observacao, ''), x.qtd_funcionarios, x.forma_pagamento, x.parcelas);
  get diagnostics upd = row_count;
  return jsonb_build_object('novos', ins, 'atualizados', upd, 'bitrix', (select count(*) from pn_crm.vw_bitrix_negocio));
end $$;

CREATE FUNCTION pn_crm.bitrix_importar_whatsapp() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare conv int; msgs int;
begin

  with d as (
    select b.chave::bigint chat_id, b.c->'dialog' g from pn_crm.bx_atual('im.dialog') b
  ), u as (
    select distinct on ((m.c->>'chat_id')::bigint, (us->>'id')::int) (m.c->>'chat_id')::bigint chat_id, (us->>'id')::int uid,
           pn_crm.so_digitos(coalesce(us->'phones'->>'personal_mobile', us->'phones'->>'work_phone', us->'phones'->>'personal_phone')) fone
      from pn_crm.bx_atual('im.messages') m, jsonb_array_elements(coalesce(m.c->'users', '[]'::jsonb)) us
     where (us->>'extranet')::boolean is true
  ), base as (
    select d.chat_id, d.g->>'name' nome, split_part(d.g->>'entity_id', '|', 1) canal,
           split_part(d.g->>'entity_id', '|', 3) ident, nullif(split_part(d.g->>'entity_id', '|', 4), '')::int uid,
           nullif(substring(d.g->>'entity_data_2' from 'DEAL\|(\d+)'), '0')::bigint deal,
           nullif(substring(d.g->>'entity_data_2' from 'CONTACT\|(\d+)'), '0')::bigint contato,
           nullif(substring(d.g->>'entity_data_2' from 'COMPANY\|(\d+)'), '0')::bigint empresa_bx,
           (d.g->>'date_create')::timestamptz criada
      from d
  )
  insert into pn_crm.wa_historico_conversa as t (chat_id, nome, canal, telefone, bitrix_deal, bitrix_contato, bitrix_empresa,
                                              negocio_id, empresa_id, iniciada_em)
  select b.chat_id, regexp_replace(coalesce(b.nome, ''), ' - (WhatsApp|Comercial).*$', ''), b.canal,
         coalesce(case when b.ident ~ '^\+?\d{10,13}$' then pn_crm.so_digitos(b.ident) end,
                  (select u.fone from u where u.chat_id = b.chat_id and u.uid = b.uid and length(u.fone) >= 10),
                  (select pn_crm.so_digitos(ct.c->'PHONE'->0->>'VALUE') from pn_crm.bx_atual('crm.contact') ct where ct.chave::bigint = b.contato)),
         b.deal, b.contato, coalesce(b.empresa_bx, n.bitrix_empresa),
         n.id, coalesce(n.empresa_id, (select be.empresa_id from pn_crm.bitrix_empresa be where be.bitrix_id = b.empresa_bx)),
         b.criada
    from base b left join pn_crm.negocio n on n.bitrix_id = b.deal
  on conflict (chat_id) do update set nome = excluded.nome, telefone = coalesce(excluded.telefone, t.telefone),
    bitrix_deal = excluded.bitrix_deal, bitrix_contato = excluded.bitrix_contato, bitrix_empresa = excluded.bitrix_empresa,
    negocio_id = coalesce(excluded.negocio_id, t.negocio_id), empresa_id = coalesce(t.empresa_id, excluded.empresa_id);
  get diagnostics conv = row_count;

  with p as (
    select (m.c->>'chat_id')::bigint chat_id, m.c from pn_crm.bx_atual('im.messages') m
  ), ms as (
    select distinct on ((x->>'id')::bigint) (x->>'id')::bigint id, p.chat_id, (x->>'date')::timestamptz em,
           (x->>'author_id')::int autor_id, x->>'text' texto,
           (select string_agg(f->>'name', ', ') from jsonb_array_elements(coalesce(p.c->'files', '[]'::jsonb)) f
             where (f->>'id') in (select jsonb_array_elements_text(case when jsonb_typeof(x->'params'->'FILE_ID') = 'array'
                                                                       then x->'params'->'FILE_ID' else '[]'::jsonb end))) arquivos,
           case when jsonb_typeof(x->'params'->'FILE_ID') = 'array' then jsonb_array_length(x->'params'->'FILE_ID') else 0 end n_arq,
           (select us->>'name' from jsonb_array_elements(coalesce(p.c->'users', '[]'::jsonb)) us where (us->>'id')::int = (x->>'author_id')::int) nome_autor,
           (select (us->>'extranet')::boolean from jsonb_array_elements(coalesce(p.c->'users', '[]'::jsonb)) us where (us->>'id')::int = (x->>'author_id')::int) externo
      from p, jsonb_array_elements(coalesce(p.c->'messages', '[]'::jsonb)) x
     where exists (select 1 from pn_crm.wa_historico_conversa c where c.chat_id = p.chat_id)
     order by (x->>'id')::bigint
  )
  insert into pn_crm.wa_historico_msg as t (id, chat_id, em, quem, autor, texto, arquivos)
  select ms.id, ms.chat_id, ms.em,
         case when ms.autor_id = 0 then 'sistema' when ms.externo then 'cliente' else 'equipe' end,
         case when ms.autor_id = 0 then null
              else coalesce((select bu.nome from pn_crm.bitrix_usuario bu where bu.bitrix_id = ms.autor_id), ms.nome_autor) end,
         case when ms.autor_id <> 0 and not coalesce(ms.externo, false)
              then nullif(regexp_replace(coalesce(pn_crm.bx_msg(ms.texto), ''), '^[^\n]{1,60}:\n', ''), '')
              else pn_crm.bx_msg(ms.texto) end,
         coalesce(ms.arquivos, case when ms.n_arq > 0 then ms.n_arq || ' arquivo(s) não migrado(s)' end)
    from ms
  on conflict (id) do nothing;
  get diagnostics msgs = row_count;

  update pn_crm.wa_historico_conversa c set mensagens = x.n, ultima_em = x.ult, iniciada_em = least(c.iniciada_em, x.pri),
         ultima_texto = left(x.txt, 200)
    from (select m.chat_id, count(*) filter (where m.quem <> 'sistema') n, max(m.em) ult, min(m.em) pri,
                 (array_agg(coalesce(m.texto, m.arquivos) order by m.em desc) filter (where m.quem <> 'sistema'))[1] txt
            from pn_crm.wa_historico_msg m group by m.chat_id) x
   where x.chat_id = c.chat_id;
  return jsonb_build_object('conversas', conv, 'mensagens_novas', msgs,
    'com_telefone', (select count(*) from pn_crm.wa_historico_conversa where telefone is not null),
    'com_empresa', (select count(*) from pn_crm.wa_historico_conversa where empresa_id is not null),
    'com_negocio', (select count(*) from pn_crm.wa_historico_conversa where negocio_id is not null));
end $_$;

CREATE FUNCTION pn_crm.bitrix_mapear_empresas() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  with co as (
    select b.chave::bigint id, btrim(b.c->>'TITLE') nome from pn_crm.bx_atual('crm.company') b
  ), rq as (
    select distinct on (r.c->>'ENTITY_ID') (r.c->>'ENTITY_ID')::bigint cid, pn_crm.so_digitos(r.c->>'RQ_CNPJ') cnpj
      from pn_crm.bx_atual('crm.requisite') r
     where r.c->>'ENTITY_TYPE_ID' = '4' and length(pn_crm.so_digitos(r.c->>'RQ_CNPJ')) = 14
     order by r.c->>'ENTITY_ID', r.chave desc
  ), por_cnpj as (
    select distinct on (pn_crm.so_digitos(e.cnpj)) pn_crm.so_digitos(e.cnpj) cnpj, e.id
      from pn.empresa e where length(pn_crm.so_digitos(e.cnpj)) = 14
     order by pn_crm.so_digitos(e.cnpj), (e.situacao::text = 'ativo') desc, e.id
  ), nomes as (
    select k, (array_agg(id order by ativo desc, id))[1] id, count(distinct id) filter (where ativo) ativos, count(distinct id) n
      from (select pn_crm.bx_chave(e.razao_social) k, e.id, e.situacao::text = 'ativo' ativo from pn.empresa e
            union all
            select pn_crm.bx_chave(e.nome_fantasia), e.id, e.situacao::text = 'ativo' from pn.empresa e where nullif(e.nome_fantasia, '') is not null) z
     where k is not null group by k
  )
  insert into pn_crm.bitrix_empresa as t (bitrix_id, nome, cnpj, empresa_id, metodo)
  select co.id, co.nome, rq.cnpj,
         coalesce(pc.id, case when nm.n = 1 or nm.ativos = 1 then nm.id end),
         case when pc.id is not null then 'cnpj' when nm.n = 1 or nm.ativos = 1 then 'nome' end
    from co left join rq on rq.cid = co.id
            left join por_cnpj pc on pc.cnpj = rq.cnpj
            left join nomes nm on nm.k = pn_crm.bx_chave(co.nome)
  on conflict (bitrix_id) do update set nome = excluded.nome, cnpj = excluded.cnpj,
    empresa_id = case when t.metodo = 'manual' then t.empresa_id else excluded.empresa_id end,
    metodo = case when t.metodo = 'manual' then 'manual' else excluded.metodo end,
    atualizado_em = now();
  return (select jsonb_build_object('total', count(*), 'cnpj', count(*) filter (where metodo = 'cnpj'),
                                    'nome', count(*) filter (where metodo = 'nome'), 'manual', count(*) filter (where metodo = 'manual'),
                                    'sem_vinculo', count(*) filter (where empresa_id is null))
            from pn_crm.bitrix_empresa);
end $$;

CREATE FUNCTION pn_crm.bitrix_mapear_usuarios() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare n int;
begin
  insert into pn_crm.bitrix_usuario (bitrix_id, nome, email_bitrix, email_painel)
  select (u.c->>'ID')::int, btrim(coalesce(u.c->>'NAME', '') || ' ' || coalesce(u.c->>'LAST_NAME', '')), lower(u.c->>'EMAIL'),
         (select pc.email from pn_crm.pre_cadastro pc where pc.email = lower(u.c->>'EMAIL'))
    from pn_crm.bx_atual('user') u
  on conflict (bitrix_id) do update set nome = excluded.nome, email_bitrix = excluded.email_bitrix,
    email_painel = coalesce(pn_crm.bitrix_usuario.email_painel, excluded.email_painel);

  update pn_crm.bitrix_usuario set email_painel = 'melina.pimenta@exemplo.com.br' where bitrix_id = 796;
  update pn_crm.bitrix_usuario set email_painel = 'yuri.rodrigues@exemplo.com.br' where bitrix_id = 16;
  get diagnostics n = row_count;
  return (select count(*) from pn_crm.bitrix_usuario);
end $$;

CREATE FUNCTION pn_crm.bitrix_sincronizar() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare u int; e jsonb; n jsonb; h jsonb; c int; a int := 0; p record;
begin
  u := pn_crm.bitrix_mapear_usuarios();
  e := pn_crm.bitrix_mapear_empresas();
  n := pn_crm.bitrix_importar_negocios();
  h := pn_crm.bitrix_importar_historico();
  c := pn_crm.bitrix_consolidar_posvenda();
  for p in select user_id, email from pn_crm.perfil where ativo loop
    a := a + pn_crm.bitrix_atribuir(p.user_id, p.email);
  end loop;
  return jsonb_build_object('usuarios', u, 'empresas', e, 'negocios', n, 'historico', h, 'posvenda_consolidados', c, 'atribuidos_agora', a);
end $$;

CREATE FUNCTION pn_crm.bx_atual(p_modulo text) RETURNS TABLE(chave text, c jsonb)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select distinct on (x.chave) x.chave, x.conteudo from pn_bitrix.captura x where x.modulo = p_modulo
   order by x.chave, x.capturado_em desc
$$;

CREATE FUNCTION pn_crm.bx_chave(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select nullif(regexp_replace(lower(coalesce(p, '')), '[^a-z0-9]+', '', 'g'), '')
$$;

CREATE FUNCTION pn_crm.bx_funcionarios(p_lista jsonb, p_numero text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select coalesce(
    nullif(substring((case when jsonb_typeof(p_lista) = 'array' then p_lista->>0
                           when jsonb_typeof(p_lista) = 'string' then p_lista #>> '{}' end)
                     from '^\s*(\d{1,6})(?!\s*/)')::integer, 0),
    nullif(floor(nullif(p_numero, '')::numeric)::integer, 0))
$$;

CREATE FUNCTION pn_crm.bx_msg(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select nullif(btrim(
    regexp_replace(
      regexp_replace(
        regexp_replace(replace(replace(coalesce(p, ''), '[br]', E'\n'), '[BR]', E'\n'),
                       '\[(USER|CHAT|URL|DISK|PCH|CALL|SEND|PUT|ICON|ATTACH)[^\]]*\]', '', 'gi'),
        '\[/?(USER|CHAT|URL|DISK|PCH|CALL|SEND|PUT|ICON|ATTACH|b|i|u|s|quote|code|size|color)[^\]]*\]', '', 'gi'),
      '-{20,}', '—', 'g')), '')
$$;

CREATE FUNCTION pn_crm.bx_pagamento(p_rotulo text, OUT forma text, OUT parcelas smallint) RETURNS record
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select case when p_rotulo ~* 'boleto' then 'boleto'
              when p_rotulo ~* 'pix' then 'pix'
              when p_rotulo ~* 'transfer' then 'transferencia'
              when p_rotulo ~* 'cart' then 'cartao' end,
         case when p_rotulo ~* '^\s*\d+\s*x' then substring(p_rotulo from '^\s*(\d+)')::smallint
              when p_rotulo ~* 'pix|transfer' then 1::smallint end
$$;

CREATE FUNCTION pn_crm.bx_txt(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select nullif(btrim(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''), '\[/?[a-zA-Z*]+(=[^\]]*)?\]', '', 'g'),
                                                    '<[^>]+>', ' ', 'g'), '&nbsp;', ' ', 'g')), '')
$$;

CREATE FUNCTION pn_crm.chat_acesso(p_sala uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from pn_crm.chat_sala s where s.id = p_sala and not s.arquivada
                   and (s.tipo = 'geral' or exists (select 1 from pn_crm.chat_membro m where m.sala_id = s.id and m.user_id = auth.uid())))
$$;

CREATE FUNCTION pn_crm.chat_exige(p_sala uuid) RETURNS uuid
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid;
begin
  eu := pn_crm.exige_ativo();
  if not pn_crm.chat_acesso(p_sala) then raise exception 'Você não participa desta conversa.' using errcode = '42501'; end if;
  return eu;
end $$;

CREATE FUNCTION pn_crm.chat_pode_arquivo(p_nome text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $_$
  select coalesce(
           exists (select 1 from pn_crm.perfil p where p.user_id = auth.uid() and p.ativo)
           and split_part(p_nome, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           and pn_crm.chat_acesso(split_part(p_nome, '/', 1)::uuid), false)
$_$;

CREATE FUNCTION pn_crm.cobranca_encargos(p_valor numeric, p_vencimento date, p_pago date, p_cancelada boolean) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select case when p_cancelada or p_pago is not null or p_vencimento is null then 0
              when (now() at time zone 'America/Sao_Paulo')::date - p_vencimento < 30 then 0
              else round(p_valor * 0.10 + p_valor * 0.01 * (((now() at time zone 'America/Sao_Paulo')::date - p_vencimento) / 30.0), 2) end
$$;

CREATE FUNCTION pn_crm.cobranca_log(p_cobranca uuid, p_texto text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  insert into pn_crm.cobranca_evento (cobranca_id, texto, autor_id) values (p_cobranca, p_texto, auth.uid())
$$;

CREATE FUNCTION pn_crm.cobranca_situacao(p_cancelada boolean, p_pago date, p_venc date) RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select case when p_cancelada then 'cancelada' when p_pago is not null then 'paga'
              when p_venc < (now() at time zone 'America/Sao_Paulo')::date then 'vencida' else 'aberta' end
$$;

CREATE FUNCTION pn_crm.contrato_log(p_contrato uuid, p_texto text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  insert into pn_crm.contrato_evento (contrato_id, texto, autor_id) values (p_contrato, p_texto, auth.uid())
$$;

CREATE FUNCTION pn_crm.contrato_recalcular(p_contrato uuid) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  update pn_crm.contrato c
     set valor_total = coalesce((select sum(i.total) from pn_crm.contrato_item i where i.contrato_id = c.id), 0),
         atualizado_em = now()
   where c.id = p_contrato
$$;

CREATE FUNCTION pn_crm.contrato_situacao(p_status text, p_fim date, p_aviso integer) RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select case
    when p_status = 'cancelado' then 'cancelado'
    when p_status <> 'assinado' then 'em_assinatura'
    when p_fim is null then 'vigente'
    when p_fim < (now() at time zone 'America/Sao_Paulo')::date then 'vencido'
    when p_fim <= (now() at time zone 'America/Sao_Paulo')::date + p_aviso then 'a_renovar'
    else 'vigente' end
$$;

CREATE FUNCTION pn_crm.contrato_status_rotulo(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select case p when 'rascunho' then 'Rascunho' when 'revisao' then 'Sob revisão' when 'enviado' then 'Enviado'
                when 'parcial' then 'Parcialmente assinado' when 'assinado' then 'Assinado'
                when 'cancelado' then 'Cancelado' else p end
$$;

CREATE FUNCTION pn_crm.criar(p_tabela text, p_dados jsonb, p_fixos jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare d jsonb := p_dados || p_fixos; cols text; novo uuid;
begin
  select string_agg(quote_ident(k), ', ') into cols from jsonb_object_keys(d) k;
  perform set_config('crm.edicao_painel', 'on', true);
  execute format('insert into public.%1$I (%2$s) select %2$s from jsonb_populate_record(null::public.%1$I, $1) returning id',
                 p_tabela, cols) into novo using d;
  insert into pn_crm.edicao (tabela, registro_id, acao, mudancas, usuario_id)
  values (p_tabela, novo, 'criar', (select jsonb_object_agg(k, jsonb_build_object('de', null, 'para', v)) from jsonb_each(p_dados) e(k, v)), auth.uid());
  perform set_config('crm.edicao_painel', 'off', true);
  return novo;
end $_$;

CREATE FUNCTION pn_crm.documento_situacao(p_situacao text, p_fim date, p_aviso integer) RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select case
    when p_situacao = 'cancelado' then 'cancelado'
    when p_situacao = 'em_elaboracao' then 'em_elaboracao'
    when p_fim is null then 'vigente'
    when p_fim < (now() at time zone 'America/Sao_Paulo')::date then 'vencido'
    when p_fim <= (now() at time zone 'America/Sao_Paulo')::date + p_aviso then 'a_vencer'
    else 'vigente' end
$$;

CREATE FUNCTION pn_crm.editar(p_tabela text, p_id uuid, p_dados jsonb) RETURNS text[]
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare antes jsonb; depois jsonb; cols text; mud text[];
begin
  if p_dados = '{}'::jsonb then return '{}'; end if;
  execute format('select to_jsonb(t) from public.%I t where t.id = $1 for update', p_tabela) into antes using p_id;
  if antes is null then raise exception 'Registro não encontrado.'; end if;

  select string_agg(quote_ident(k), ', ') into cols from jsonb_object_keys(p_dados) k;
  perform set_config('crm.edicao_painel', 'on', true);
  execute format('update public.%1$I t set (%2$s) = (select %2$s from jsonb_populate_record(null::public.%1$I, $1))
                   where t.id = $2 returning to_jsonb(t)', p_tabela, cols)
     into depois using p_dados, p_id;

  select array_agg(k order by k) into mud
    from jsonb_object_keys(p_dados) k where antes -> k is distinct from depois -> k;
  if mud is not null then
    execute format('update public.%I set campos_editados = array(select distinct x from unnest(campos_editados || $1) x order by 1)
                     where id = $2', p_tabela) using mud, p_id;
    insert into pn_crm.edicao (tabela, registro_id, mudancas, usuario_id)
    values (p_tabela, p_id, (select jsonb_object_agg(k, jsonb_build_object('de', antes -> k, 'para', depois -> k)) from unnest(mud) k),
            auth.uid());
  end if;
  perform set_config('crm.edicao_painel', 'off', true);
  return coalesce(mud, '{}');
end $_$;

CREATE FUNCTION pn_crm.empresa_inadimplente(p_empresa uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from pn_crm.negocio n
      join pn_crm.etapa e on e.id = n.etapa_id
      join pn_crm.funil f on f.id = n.funil_id
     where n.empresa_id = p_empresa and f.slug = 'pos-venda'
       and e.tipo = 'aberta' and e.nome ilike 'inadimpl%')
$$;

CREATE FUNCTION pn_crm.exige(VARIADIC papeis pn_crm.papel[]) RETURNS uuid
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v pn_crm.papel;
begin
  if auth.uid() is null then
    raise exception 'Sessão ausente' using errcode = '42501';
  end if;
  select p.papel into v from pn_crm.perfil p where p.user_id = auth.uid() and p.ativo;
  if v is null then
    raise exception 'Seu acesso ainda não foi liberado' using errcode = '42501';
  end if;
  if v <> 'admin' and not (v = any (papeis)) then
    raise exception 'Seu perfil (%) não tem acesso a esta função', v using errcode = '42501';
  end if;
  return auth.uid();
end $$;

CREATE FUNCTION pn_crm.exige_ativo() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select pn_crm.exige('admin','gestor','comercial','operacoes','financeiro','leitura')
$$;

CREATE FUNCTION pn_crm.exige_contratos() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select pn_crm.exige('gestor','comercial','financeiro')
$$;

CREATE FUNCTION pn_crm.exige_editor() RETURNS uuid
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid;
begin
  eu := pn_crm.exige_ativo();
  if pn_crm.papel_atual() = 'leitura' then
    raise exception 'Seu perfil é só de leitura.' using errcode = '42501';
  end if;
  return eu;
end $$;

CREATE FUNCTION pn_crm.exige_financeiro() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select pn_crm.exige('gestor','financeiro')
$$;

CREATE FUNCTION pn_crm.exige_operar(p_funil uuid) RETURNS uuid
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid;
begin
  eu := pn_crm.exige_ativo();
  if not pn_crm.pode_operar(p_funil) then
    raise exception 'Seu perfil pode ver, mas não pode alterar este funil' using errcode = '42501';
  end if;
  return eu;
end $$;

CREATE FUNCTION pn_crm.fin_inadimplencia() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r record; n int := 0;
begin
  for r in
    select distinct c.empresa_id from pn_crm.cobranca c where c.empresa_id is not null
    union
    select n2.empresa_id from pn_crm.negocio n2 join pn_crm.etapa e on e.id = n2.etapa_id
     where e.nome ilike 'inadimpl%' and n2.empresa_id is not null
  loop
    perform pn_crm.fin_sincronizar_inadimplencia(r.empresa_id);
    n := n + 1;
  end loop;
  return n;
end $$;

CREATE FUNCTION pn_crm.fin_sincronizar_inadimplencia(p_empresa uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  tol int; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  funil_pv uuid; etapa_inad uuid; etapa_ok uuid; etapa_base uuid; card uuid; volta uuid; atrasado numeric; nome text; origem_card text;
begin
  if p_empresa is null then return; end if;
  select tolerancia_dias into tol from pn_crm.fin_regra where id;
  select f.id into funil_pv from pn_crm.funil f where f.slug = 'pos-venda';
  select e.id into etapa_inad from pn_crm.etapa e where e.funil_id = funil_pv and e.nome ilike 'inadimpl%' and e.ativo limit 1;
  select e.id into etapa_ok from pn_crm.etapa e where e.funil_id = funil_pv and e.tipo = 'ganho' and e.ativo order by e.ordem limit 1;
  select e.id into etapa_base from pn_crm.etapa e where e.funil_id = funil_pv and e.nome ilike 'contratos%' and e.ativo limit 1;
  if etapa_inad is null then return; end if;

  select coalesce(sum(c.valor), 0) into atrasado from pn_crm.cobranca c
   where c.empresa_id = p_empresa and not c.cancelada and c.pago_em is null and c.vencimento < hoje - tol;
  select n.id, n.etapa_anterior_id, n.origem into card, volta, origem_card from pn_crm.negocio n
   where n.empresa_id = p_empresa and n.etapa_id = etapa_inad order by n.criado_em desc limit 1;

  if atrasado > 0 and card is null then
    card := pn_crm.posvenda_card(p_empresa);
    if card is not null then

      perform pn_crm.posvenda_mover(card, etapa_inad,
        'Em atraso no Financeiro: ' || 'R$ ' || replace(to_char(atrasado, 'FM999999990.00'), '.', ',') || ' vencidos há mais de ' || tol || ' dias', true);
    else
      select coalesce(nullif(nome_fantasia, ''), razao_social) into nome from pn.empresa where id = p_empresa;
      insert into pn_crm.negocio (funil_id, etapa_id, titulo, empresa_id, valor, origem, observacao, responsavel_id)
      values (funil_pv, etapa_inad, 'Inadimplência: ' || nome, p_empresa, atrasado, 'inadimplencia',
              'Aberto pelo Financeiro: cobrança vencida há mais de ' || tol || ' dias.', pn_crm.responsavel_cliente(p_empresa))
      returning id into card;
      insert into pn_crm.evento (negocio_id, tipo, texto) values (card, 'criado', 'Aberto pelo Financeiro (cobrança em atraso)');
    end if;
  elsif atrasado > 0 and card is not null then
    if origem_card = 'inadimplencia' then
      update pn_crm.negocio set valor = atrasado, atualizado_em = now() where id = card and valor <> atrasado;
    end if;
  elsif atrasado = 0 and card is not null then
    if volta is not null then
      perform pn_crm.posvenda_mover(card, volta, 'Débitos quitados no Financeiro — voltou para a etapa anterior', false);
    elsif etapa_ok is not null then
      perform pn_crm.posvenda_mover(card, etapa_ok, 'Débitos quitados no Financeiro', false);
    end if;
  end if;
end $_$;

CREATE FUNCTION pn_crm.gerar_alertas() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r record; qtd int := 0; dias int;
begin
  for r in
    select n.id, n.titulo, n.responsavel_id, e.nome as etapa, e.alerta_dias, n.entrou_etapa_em
      from pn_crm.negocio n join pn_crm.etapa e on e.id = n.etapa_id
     where e.tipo = 'aberta' and e.alerta_dias is not null
       and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)
       and (n.ultimo_alerta_em is null or now() - n.ultimo_alerta_em >= make_interval(days => e.alerta_dias))
  loop
    dias := floor(extract(epoch from now() - r.entrou_etapa_em) / 86400)::int;
    if r.responsavel_id is not null then
      insert into pn_crm.notificacao (user_id, negocio_id, tipo, texto)
      values (r.responsavel_id, r.id, 'parado', r.titulo || ': há ' || dias || ' dias em ' || r.etapa);
    else
      insert into pn_crm.notificacao (user_id, negocio_id, tipo, texto)
      select p.user_id, r.id, 'parado', r.titulo || ' (sem responsável): há ' || dias || ' dias em ' || r.etapa
        from pn_crm.perfil p where p.ativo and p.papel in ('gestor','admin');
    end if;
    insert into pn_crm.evento (negocio_id, tipo, texto) values (r.id, 'alerta', 'Aviso: ' || dias || ' dias em ' || r.etapa);
    update pn_crm.negocio set ultimo_alerta_em = now() where id = r.id;
    qtd := qtd + 1;
  end loop;
  return qtd;
end $$;

CREATE FUNCTION pn_crm.historico_edicao(p_tabela text, p_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object('em', e.em, 'acao', e.acao, 'mudancas', e.mudancas,
                                               'usuario', coalesce(p.nome, u.email)) order by e.em desc), '[]'::jsonb)
    from (select * from pn_crm.edicao where tabela = p_tabela and registro_id = p_id order by em desc limit 30) e
    left join pn_crm.perfil p on p.user_id = e.usuario_id
    left join auth.users u on u.id = e.usuario_id
$$;

CREATE FUNCTION pn_crm.integracao_token_ok(p_token text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select c.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') from pn_crm.wa_config c where c.id), false)
$$;

CREATE FUNCTION pn_crm.limpar_dados(p_dados jsonb, p_campos text[]) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select coalesce(jsonb_object_agg(k,
           case
             when jsonb_typeof(v) <> 'string' then v
             when btrim(v #>> '{}') = '' then 'null'::jsonb
             when k in ('cpf','cnpj','pis','cep') then to_jsonb(nullif(regexp_replace(v #>> '{}', '\D', '', 'g'), ''))
             when k = 'uf' then to_jsonb(upper(btrim(v #>> '{}')))
             when k = 'email' then to_jsonb(lower(btrim(v #>> '{}')))
             else to_jsonb(btrim(v #>> '{}'))
           end), '{}'::jsonb)
    from jsonb_each(coalesce(p_dados, '{}'::jsonb)) e(k, v)
   where k = any (p_campos)
$$;

CREATE FUNCTION pn_crm.nomes_responsaveis(p_resps uuid[]) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.user_id, 'nome', p.nome) order by array_position(p_resps, p.user_id)), '[]'::jsonb)
    from pn_crm.perfil p where p.user_id = any (coalesce(p_resps, '{}'))
$$;

CREATE FUNCTION pn_crm.notificar(p_user uuid, p_negocio uuid, p_tipo text, p_texto text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  insert into pn_crm.notificacao (user_id, negocio_id, tipo, texto)
  select p_user, p_negocio, p_tipo, p_texto
   where p_user is not null and p_user is distinct from auth.uid()
$$;

CREATE FUNCTION pn_crm.notificar_tarefa(p_user uuid, p_tarefa uuid, p_tipo text, p_texto text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  insert into pn_crm.notificacao (user_id, tarefa_id, tipo, texto)
  select p_user, p_tarefa, p_tipo, p_texto
   where p_user is not null and p_user is distinct from auth.uid()
$$;

CREATE FUNCTION pn_crm.papel_atual() RETURNS pn_crm.papel
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select p.papel from pn_crm.perfil p where p.user_id = auth.uid() and p.ativo
$$;

CREATE FUNCTION pn_crm.pode_clinico() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(pn_crm.papel_atual() in ('admin','gestor','operacoes'), false)
$$;

CREATE FUNCTION pn_crm.pode_editar_dados() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(pn_crm.papel_atual() in ('admin','gestor'), false)
$$;

CREATE FUNCTION pn_crm.pode_encaixe() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select p.papel = 'admin' or p.agenda_encaixe from pn_crm.perfil p where p.user_id = auth.uid() and p.ativo), false)
$$;

CREATE FUNCTION pn_crm.pode_liberar_agenda() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select p.papel = 'admin' or p.libera_agenda from pn_crm.perfil p where p.user_id = auth.uid() and p.ativo), false)
$$;

CREATE FUNCTION pn_crm.pode_operar(p_funil uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(
    (select v.papel in ('admin','gestor') or v.papel = any (f.papeis)
       from pn_crm.perfil v, pn_crm.funil f
      where v.user_id = auth.uid() and v.ativo and f.id = p_funil),
    false)
$$;

CREATE FUNCTION pn_crm.posvenda_card(p_empresa uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select n.id from pn_crm.negocio n
    join pn_crm.funil f on f.id = n.funil_id and f.slug = 'pos-venda'
    join pn_crm.etapa e on e.id = n.etapa_id and e.tipo = 'aberta'
   where n.empresa_id = p_empresa
   order by (e.nome ilike 'contratos%') desc, n.criado_em desc
   limit 1
$$;

CREATE FUNCTION pn_crm.posvenda_mover(p_card uuid, p_etapa uuid, p_texto text, p_guardar_anterior boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare atual uuid; tipo pn_crm.tipo_etapa;
begin
  select etapa_id into atual from pn_crm.negocio where id = p_card;
  if atual is null or atual = p_etapa then return; end if;
  select e.tipo into tipo from pn_crm.etapa e where e.id = p_etapa;
  update pn_crm.negocio
     set etapa_id = p_etapa, entrou_etapa_em = now(), ultimo_alerta_em = null, atualizado_em = now(),
         etapa_anterior_id = case when p_guardar_anterior then atual else null end,
         fechado_em = case when tipo = 'aberta' then null else now() end
   where id = p_card;
  insert into pn_crm.evento (negocio_id, tipo, texto, de_etapa_id, para_etapa_id) values (p_card, 'etapa', p_texto, atual, p_etapa);
end $$;

CREATE FUNCTION pn_crm.posvenda_renovacao() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r record; qtd int := 0; meses int; lim int; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        etapa_base uuid; etapa_ok uuid; neg uuid; num bigint;
begin
  select p.meses, p.max_por_execucao into meses, lim from pn_crm.posvenda_regra p where p.id;
  select e.id into etapa_base from pn_crm.etapa e join pn_crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda'
   where e.nome ilike 'contratos%' and e.ativo limit 1;
  select e.id into etapa_ok from pn_crm.etapa e join pn_crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda'
   where e.tipo = 'ganho' and e.ativo order by e.ordem limit 1;
  if etapa_base is null then return 0; end if;
  for r in
    select * from (
      select n.*, greatest(
               n.criado_em::date,
               (select max(c.inicio) from pn_crm.contrato c where c.empresa_id = n.empresa_id and c.status = 'assinado'),

               (select max(g.fechado_em)::date from pn_crm.negocio g join pn_crm.etapa ge on ge.id = g.etapa_id and ge.tipo = 'ganho'
                  join pn_crm.funil gf on gf.id = g.funil_id and gf.slug = 'comercial'
                 where (n.empresa_id is not null and g.empresa_id = n.empresa_id)
                    or (n.bitrix_empresa is not null and g.bitrix_empresa = n.bitrix_empresa))) base
        from pn_crm.negocio n where n.etapa_id = etapa_base) x
     where x.base <= hoje - make_interval(months => meses)
     order by x.base, x.numero
  loop
    exit when qtd >= coalesce(lim, 30);
    neg := pn_crm.abrir_renovacao(r.empresa_id, r.titulo, r.cliente_nome, r.responsavel_id, r.valor, r.id,
             'Cliente completou ' || meses || ' meses no Pós-venda (desde ' || to_char(r.base, 'DD/MM/YYYY') || ')');
    continue when neg is null;
    update pn_crm.negocio set bitrix_responsavel = r.bitrix_responsavel where id = neg and responsavel_id is null and bitrix_responsavel is null;
    select numero into num from pn_crm.negocio where id = neg;
    if etapa_ok is not null then
      perform pn_crm.posvenda_mover(r.id, etapa_ok, 'Completou ' || meses || ' meses: enviado ao Comercial › Renovação (#' || num || ')', false);
    end if;
    qtd := qtd + 1;
  end loop;
  return qtd;
end $$;

CREATE FUNCTION pn_crm.proximo_rodizio(p_funil uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ultimo uuid; ordem_ultimo int; prox uuid;
begin
  insert into pn_crm.rodizio_estado (funil_id) values (p_funil) on conflict do nothing;
  select ultimo_user_id into ultimo from pn_crm.rodizio_estado where funil_id = p_funil for update;
  select r.ordem into ordem_ultimo from pn_crm.rodizio r where r.funil_id = p_funil and r.user_id = ultimo;

  select r.user_id into prox
    from pn_crm.rodizio r join pn_crm.perfil p on p.user_id = r.user_id and p.ativo
   where r.funil_id = p_funil and r.ativo and r.ordem > coalesce(ordem_ultimo, -1)
   order by r.ordem limit 1;
  if prox is null then
    select r.user_id into prox
      from pn_crm.rodizio r join pn_crm.perfil p on p.user_id = r.user_id and p.ativo
     where r.funil_id = p_funil and r.ativo
     order by r.ordem limit 1;
  end if;

  if prox is not null then
    update pn_crm.rodizio_estado set ultimo_user_id = prox, atualizado_em = now() where funil_id = p_funil;
  end if;
  return prox;
end $$;

CREATE FUNCTION pn_crm.recalcular_valor(p_negocio uuid) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  update pn_crm.negocio n
     set valor = round(coalesce((select sum(i.total_liquido) from pn_crm.negocio_item i where i.negocio_id = n.id), 0)
                       * (1 - coalesce(n.desconto_pct, 0) / 100), 2),
         atualizado_em = now()
   where n.id = p_negocio
     and exists (select 1 from pn_crm.negocio_item i where i.negocio_id = n.id)
$$;

CREATE FUNCTION pn_crm.registrar(p_negocio uuid, p_tipo text, p_texto text, p_de uuid DEFAULT NULL::uuid, p_para uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  insert into pn_crm.evento (negocio_id, tipo, texto, de_etapa_id, para_etapa_id, autor_id)
  values (p_negocio, p_tipo, p_texto, p_de, p_para, auth.uid())
$$;

CREATE FUNCTION pn_crm.responsavel_cliente(p_empresa uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(
    (select c.responsavel_id from pn_crm.contrato c where c.empresa_id = p_empresa and c.responsavel_id is not null
      order by c.criado_em desc limit 1),
    (select n.responsavel_id from pn_crm.negocio n join pn_crm.funil f on f.id = n.funil_id and f.slug = 'comercial'
      join pn_crm.etapa e on e.id = n.etapa_id and e.tipo = 'ganho'
      where n.empresa_id = p_empresa and n.responsavel_id is not null order by n.fechado_em desc nulls last limit 1))
$$;

CREATE FUNCTION pn_crm.so_digitos(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$ select nullif(regexp_replace(coalesce(p, ''), '\D', '', 'g'), '') $$;

CREATE FUNCTION pn_crm.status_rotulo(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select case p when 'nao_iniciado' then 'Não iniciado' when 'em_andamento' then 'Em andamento'
                when 'parado' then 'Parado' when 'feito' then 'Feito' else p end
$$;

CREATE FUNCTION pn_crm.tarefa_log(p_tarefa uuid, p_texto text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  insert into pn_crm.tarefa_comentario (tarefa_id, autor_id, texto, sistema) values (p_tarefa, auth.uid(), p_texto, true)
$$;

CREATE FUNCTION pn_crm.telefone_normalizado(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select case when length(d) in (10, 11) then '55' || d when length(d) between 12 and 13 then d end
    from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') d) x
$$;

CREATE FUNCTION pn_crm.tg_atestado_antes() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  new.mes := pn_crm.atestado_mes(new.data_inicio, new.data_emissao, coalesce(new.criado_em, now()));
  new.colaborador_cpf := pn_crm.so_digitos(new.colaborador_cpf);
  new.cid := nullif(upper(btrim(new.cid)), '');
  new.atualizado_em := now();

  if new.empresa_id is null and new.situacao = 'ok' then new.situacao := 'revisar'; end if;

  if new.colaborador_id is not null then
    select coalesce(new.colaborador_nome, c.nome), coalesce(new.colaborador_cpf, c.cpf), coalesce(new.empresa_id, c.empresa_id)
      into new.colaborador_nome, new.colaborador_cpf, new.empresa_id
      from pn.colaborador c where c.id = new.colaborador_id;
  elsif new.empresa_id is not null and new.colaborador_cpf is not null then
    select c.id, coalesce(new.colaborador_nome, c.nome) into new.colaborador_id, new.colaborador_nome
      from pn.colaborador c where c.empresa_id = new.empresa_id and c.cpf = new.colaborador_cpf
     order by c.data_demissao nulls first limit 1;
  end if;
  return new;
end $$;

CREATE FUNCTION pn_crm.tg_atestado_depois() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if tg_op = 'INSERT' or new.empresa_id is distinct from old.empresa_id or new.mes is distinct from old.mes
     or new.situacao is distinct from old.situacao then
    perform pn_crm.atestado_verificar(new.empresa_id, new.mes);
    if tg_op = 'UPDATE' and (old.empresa_id, old.mes) is distinct from (new.empresa_id, new.mes) then
      perform pn_crm.atestado_verificar(old.empresa_id, old.mes);
    end if;
  end if;
  return null;
end $$;

CREATE FUNCTION pn_crm.tg_contrato_item_cobranca() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if new.cobranca is null and new.produto_id is not null then
    select p.cobranca_padrao into new.cobranca from pn_crm.produto p where p.id = new.produto_id;
  end if;
  return new;
end $$;

CREATE FUNCTION pn_crm.tg_contrato_padroes() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  new.dia_vencimento  := coalesce(new.dia_vencimento, 5);
  new.indice_reajuste := coalesce(new.indice_reajuste, 'IPCA');
  new.forma_pagamento := coalesce(new.forma_pagamento, 'Boleto bancário');
  return new;
end $$;

CREATE FUNCTION pn_crm.tg_negocio_do_comercial() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if auth.uid() is not null and pn_crm.papel_atual() = 'comercial' and old.responsavel_id is distinct from auth.uid() then
    raise exception 'Este card é de outro responsável.' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $$;

CREATE FUNCTION pn_crm.tg_negocio_ganho_contrato() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v uuid;
begin
  if new.etapa_id is not distinct from old.etapa_id then return new; end if;
  if not exists (select 1 from pn_crm.etapa e join pn_crm.funil f on f.id = e.funil_id
                  where e.id = new.etapa_id and e.tipo = 'ganho' and f.slug = 'comercial') then
    return new;
  end if;
  if exists (select 1 from pn_crm.contrato where negocio_id = new.id) then return new; end if;
  insert into pn_crm.contrato (empresa_id, cliente_nome, negocio_id, titulo, responsavel_id, valor_total, criado_por)
  values (new.empresa_id, new.cliente_nome, new.id, 'Contrato — ' || new.titulo, new.responsavel_id, new.valor, auth.uid())
  returning id into v;
  insert into pn_crm.contrato_item (contrato_id, produto_id, descricao, quantidade, preco)
  select v, i.produto_id, i.descricao, i.quantidade, i.preco_unitario from pn_crm.negocio_item i where i.negocio_id = new.id;
  if found then perform pn_crm.contrato_recalcular(v); end if;
  insert into pn_crm.contrato_evento (contrato_id, texto, autor_id)
  values (v, 'Criado a partir do negócio #' || new.numero || ' (ganho no Comercial)', auth.uid());
  return new;
end $$;

CREATE FUNCTION pn_crm.tg_novo_usuario() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  begin
    insert into pn_crm.perfil (user_id, nome, email, papel, ativo)
    select new.id,
           coalesce(nullif(trim(new.raw_user_meta_data->>'nome'), ''), split_part(new.email, '@', 1)),
           coalesce(new.email, ''),
           case when a.email is not null then 'admin'::pn_crm.papel else 'leitura'::pn_crm.papel end,
           a.email is not null
      from (select 1) x
      left join pn_crm.admin_inicial a on lower(a.email) = lower(new.email)
    on conflict (user_id) do nothing;
    perform pn_crm.aplicar_pre_cadastro(new.id, new.email, new.email_confirmed_at is not null);
  exception when others then
    raise warning 'crm.tg_novo_usuario: %', sqlerrm;
  end;
  return new;
end $$;

CREATE FUNCTION pn_crm.tg_preserva_edicao() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if current_setting('crm.edicao_painel', true) = 'on' or cardinality(old.campos_editados) = 0 then
    return new;
  end if;
  new := jsonb_populate_record(new, (select jsonb_object_agg(k, to_jsonb(old) -> k)
                                        from unnest(old.campos_editados) k));
  new.campos_editados := old.campos_editados;
  return new;
end $$;

CREATE FUNCTION pn_crm.tg_tarefa_responsaveis() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
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

CREATE FUNCTION pn_crm.tg_usuario_confirmado() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  begin
    if new.email_confirmed_at is not null and old.email_confirmed_at is null then
      perform pn_crm.aplicar_pre_cadastro(new.id, new.email, true);
    end if;
  exception when others then
    raise warning 'crm.tg_usuario_confirmado: %', sqlerrm;
  end;
  return new;
end $$;

CREATE FUNCTION pn_crm.usuario_atividade(p_user uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_strip_nulls(jsonb_build_object(
    'negocios',     nullif((select count(*) from pn_crm.negocio n where n.responsavel_id = p_user or n.criado_por = p_user), 0),
    'eventos',      nullif((select count(*) from pn_crm.evento e where e.autor_id = p_user), 0),
    'tarefas',      nullif((select count(*) from pn_crm.tarefa t where t.criado_por = p_user or p_user = any (t.responsaveis)), 0),
    'comentarios',  nullif((select count(*) from pn_crm.tarefa_comentario c where c.autor_id = p_user), 0),
    'chat',         nullif((select count(*) from pn_crm.chat_mensagem m where m.autor_id = p_user), 0),
    'agendamentos', nullif((select count(*) from pn_crm.agendamento a where a.criado_por = p_user), 0),
    'edicoes',      nullif((select count(*) from pn_crm.edicao d where d.usuario_id = p_user), 0),
    'contratos',    nullif((select count(*) from pn_crm.contrato c where c.responsavel_id = p_user), 0)))
$$;

CREATE FUNCTION pn_crm.ve_empresa(p_empresa uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(pn_crm.papel_atual() <> 'comercial', false)
      or exists (select 1 from pn_crm.negocio n where n.empresa_id = p_empresa and n.responsavel_id = auth.uid())
      or exists (select 1 from pn_crm.contrato c where c.empresa_id = p_empresa and c.responsavel_id = auth.uid())
      or exists (select 1 from pn.empresa e where e.id = p_empresa and e.cadastrado_por = auth.uid())
$$;

CREATE FUNCTION pn_crm.ve_negocio(p_responsavel uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(pn_crm.papel_atual() <> 'comercial' or p_responsavel = auth.uid(), false)
$$;

CREATE FUNCTION pn_crm.ve_tarefa(p_criador uuid, p_resps uuid[]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(pn_crm.papel_atual()::text = 'admin' or p_criador = auth.uid() or auth.uid() = any (coalesce(p_resps, '{}')), false)
$$;

CREATE FUNCTION pn_crm.ve_valores() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(pn_crm.papel_atual()::text in ('admin', 'financeiro', 'comercial'), false)
$$;

CREATE FUNCTION pn_crm.ve_valores_funil(p_funil uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select pn_crm.ve_valores()
     and (pn_crm.papel_atual()::text = 'admin'
          or not exists (select 1 from pn_crm.funil f where f.id = p_funil and f.slug in ('vistoria', 'laudos')))
$$;

CREATE FUNCTION pn_crm.vendedor_id(p_negocio uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  with recursive c as (
    select n.id, n.negocio_origem_id, n.responsavel_id, 0 as nivel from pn_crm.negocio n where n.id = p_negocio
    union all
    select o.id, o.negocio_origem_id, o.responsavel_id, c.nivel + 1
      from pn_crm.negocio o join c on o.id = c.negocio_origem_id where c.nivel < 10)
  select c.responsavel_id from c order by c.nivel desc limit 1
$$;

CREATE FUNCTION pn_crm.wa_abrir_negocio(p_contato uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare c pn_crm.wa_contato; v_funil uuid; v_etapa uuid; v_resp uuid; v_id uuid; rotulo text;
begin
  select * into c from pn_crm.wa_contato where id = p_contato for update;
  if c.id is null then raise exception 'Contato não encontrado.'; end if;
  if c.negocio_id is not null then return c.negocio_id; end if;
  select coalesce(w.funil_id, (select f.id from pn_crm.funil f where f.slug = 'comercial')) into v_funil from pn_crm.wa_config w where w.id;
  select e.id into v_etapa from pn_crm.etapa e where e.funil_id = v_funil and e.ativo and e.tipo = 'aberta' order by e.ordem limit 1;
  if v_etapa is null then raise exception 'O funil de destino do WhatsApp não tem etapa aberta.'; end if;
  if (select f.usa_rodizio from pn_crm.funil f where f.id = v_funil) then v_resp := pn_crm.proximo_rodizio(v_funil); end if;
  rotulo := coalesce(nullif(trim(c.nome), ''), '+' || c.telefone, 'Contato sem nome');

  insert into pn_crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, contato_nome, contato_telefone,
                           responsavel_id, origem, observacao, criado_por)
  values (v_funil, v_etapa, 'WhatsApp · ' || rotulo, c.empresa_id,
          case when c.empresa_id is null then rotulo end, nullif(trim(c.nome), ''), c.telefone,
          v_resp, 'whatsapp',
          'Primeiro contato pelo WhatsApp em ' || to_char(c.primeiro_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
          auth.uid())
  returning id into v_id;
  update pn_crm.wa_contato set negocio_id = v_id, atualizado_em = now() where id = c.id;
  perform pn_crm.registrar(v_id, 'whatsapp',
    case when v_resp is not null then 'Veio do WhatsApp e foi distribuído pelo rodízio' else 'Veio do WhatsApp' end, null, v_etapa);
  perform pn_crm.notificar(v_resp, v_id, 'atribuido', 'Novo lead do WhatsApp: ' || rotulo);
  return v_id;
end $$;

CREATE FUNCTION pn_crm.wa_empresa_por_telefone(p_tel text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  with t as (select right(pn_crm.so_digitos(p_tel), 8) fim where length(pn_crm.so_digitos(p_tel)) >= 8),
  achadas as (
    select e.id from pn.empresa e, t where right(pn_crm.so_digitos(e.telefone), 8) = t.fim
    union
    select c.empresa_id from pn.empresa_contato c, t where right(pn_crm.so_digitos(c.telefone), 8) = t.fim
  )
  select case when (select count(*) from achadas) = 1 then (select id from achadas) end
$$;

CREATE FUNCTION pn_crm.wa_receber(p_eventos jsonb, p_criar boolean DEFAULT true) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ev jsonb; v_id uuid; novo boolean; n_rec int := 0; n_novos int := 0; n_neg int := 0; cfg pn_crm.wa_config;
begin
  if jsonb_typeof(p_eventos) <> 'array' then raise exception 'Envie uma lista de eventos.'; end if;
  if jsonb_array_length(p_eventos) > 500 then raise exception 'No máximo 500 eventos por chamada.'; end if;
  select * into cfg from pn_crm.wa_config where id;
  for ev in select * from jsonb_array_elements(p_eventos) loop
    if nullif(ev->>'lead_id', '') is null then continue; end if;
    insert into pn_crm.wa_contato as w (ext_lead_id, ext_conversa_id, nome, telefone, status, ultima_mensagem, ultima_direcao,
                                     ultima_em, mensagens, primeiro_em)
    values ((ev->>'lead_id')::uuid, nullif(ev->>'conversa_id', '')::uuid, nullif(trim(ev->>'nome'), ''),
            pn_crm.so_digitos(ev->>'telefone'), nullif(ev->>'status', ''), left(nullif(ev->>'ultima_mensagem', ''), 300),
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
      update pn_crm.wa_contato set empresa_id = pn_crm.wa_empresa_por_telefone(telefone) where id = v_id and empresa_id is null;
      if p_criar and cfg.criar_negocio then
        perform pn_crm.wa_abrir_negocio(v_id);
        n_neg := n_neg + 1;
      end if;
    end if;
  end loop;
  update pn_crm.wa_config set ultimo_recebimento = now() where id;
  return jsonb_build_object('recebidos', n_rec, 'novos', n_novos, 'negocios', n_neg);
end $$;

CREATE FUNCTION pn.ingestao_gravar_worker(p_capturas jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pn_sesmo', 'pn', 'pg_catalog'
    AS $$
declare v_n int; v_inseridos int;
begin
  if jsonb_typeof(p_capturas) <> 'array' then
    return jsonb_build_object('erro','esperado array');
  end if;
  v_n := jsonb_array_length(p_capturas);
  if v_n = 0 then return jsonb_build_object('inseridos',0,'recebidos',0); end if;
  if v_n > 1000 then return jsonb_build_object('erro','lote acima de 1000'); end if;

  insert into pn_sesmo.captura (modulo, chave, url, conteudo, hash, capturado_em)
  select left(x->>'modulo',64), left(x->>'chave',256), left(x->>'url',1024),
         x->'conteudo', left(x->>'hash',128),
         coalesce((x->>'capturado_em')::timestamptz, now())
  from jsonb_array_elements(p_capturas) x
  where coalesce(x->>'modulo','') <> '' and coalesce(x->>'chave','') <> ''
  on conflict (modulo, chave, hash) do nothing;

  get diagnostics v_inseridos = row_count;
  return jsonb_build_object('recebidos', v_n, 'inseridos', v_inseridos,
                            'duplicados', v_n - v_inseridos);
end $$;

CREATE FUNCTION pn.integracao_agenda_horarios(p_token text, p_data date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_agenda uuid; agora timestamptz := now(); total_ocup int; total_vagas int;
begin
  if not pn_crm.integracao_token_ok(p_token) then raise exception 'Token inválido.' using errcode = '42501'; end if;
  if p_data is null then raise exception 'Informe a data.'; end if;
  if extract(isodow from p_data) > 5 then
    return jsonb_build_object('data', p_data, 'disponivel', false, 'motivo', 'Agendamos só de segunda a sexta.', 'horarios', '[]'::jsonb);
  end if;
  select a.id, a.vagas into v_agenda, total_vagas from pn_crm.agenda a where a.data = p_data and a.local = 'clinica' order by a.criado_em limit 1;
  select count(*) into total_ocup from pn_crm.agendamento g where g.agenda_id = v_agenda and not g.encaixe and g.situacao not in ('cancelado','faltou');
  if v_agenda is not null and total_ocup >= total_vagas then
    return jsonb_build_object('data', p_data, 'disponivel', false, 'motivo', 'Agenda do dia lotada.', 'horarios', '[]'::jsonb);
  end if;
  return jsonb_build_object('data', p_data, 'disponivel', true, 'local', 'Vitalis Jardins — Rua das Acácias, 100',
    'horarios', coalesce((
      select jsonb_agg(jsonb_build_object('horario', to_char(h.horario, 'HH24:MI'), 'livres', h.vagas - h.ocupadas) order by h.horario)
        from (select g.horario, g.vagas,
                     (select count(*)::int from pn_crm.agendamento a
                       where a.agenda_id = v_agenda and a.horario = g.horario and not a.encaixe and a.situacao not in ('cancelado','faltou')) ocupadas
                from pn_crm.agenda_grade g where g.vagas > 0) h
       where h.vagas > h.ocupadas
         and (p_data + h.horario) at time zone 'America/Sao_Paulo' >= agora + interval '24 hours'), '[]'::jsonb));
end $$;

CREATE FUNCTION pn.integracao_agendamento_criar(p_token text, p_dados jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
  if not pn_crm.integracao_token_ok(p_token) then raise exception 'Token inválido.' using errcode = '42501'; end if;

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
    select e.id into v_empresa from pn.empresa e where pn_app.digits(e.cnpj) = v_cnpj
     order by (e.situacao = 'ativo') desc, e.updated_at desc limit 1;
  end if;

  v_agenda := pn_crm.agenda_clinica_do_dia(v_data);
  select * into slot from pn_crm.agenda_horarios(v_agenda, null) h where h.horario = v_hora;
  if slot.horario is null then return jsonb_build_object('ok', false, 'motivo', to_char(v_hora, 'HH24:MI') || ' não é um horário da agenda.'); end if;
  if slot.ocupadas >= slot.vagas then return jsonb_build_object('ok', false, 'motivo', 'Horário ' || to_char(v_hora, 'HH24:MI') || ' já está lotado.'); end if;

  chk := pn_crm.agenda_checar(v_agenda, v_empresa, false, null, v_tipo);
  if jsonb_array_length(chk->'bloqueios') > 0 then
    return jsonb_build_object('ok', false, 'motivo', (select string_agg(x, ' ') from jsonb_array_elements_text(chk->'bloqueios') x),
                              'transferir_para_atendimento', true);
  end if;

  insert into pn_crm.agendamento (agenda_id, horario, empresa_id, empresa_nome, paciente_nome, cpf, telefone, funcao, tipo,
                               encaixe, observacao, criado_via, ia_ref)
  values (v_agenda, v_hora, v_empresa,
          case when v_empresa is null then coalesce(v_empresa_nome, 'CNPJ ' || v_cnpj) end,
          v_nome, v_cpf, v_tel, v_funcao, v_tipo, false,
          nullif(trim(concat_ws(E'\n',
            case when v_empresa is null and v_cnpj is not null then 'CNPJ informado: ' || v_cnpj end,
            nullif(trim(d->>'observacao'), ''))), ''),
          'ia', nullif(trim(d->>'ref'), ''))
  returning id, numero into v_id, v_num;
  perform pn_crm.agenda_registrar(v_id, 'Agendado pela IA (Lia) no WhatsApp');

  return jsonb_build_object('ok', true, 'numero', v_num, 'data', v_data, 'horario', to_char(v_hora, 'HH24:MI'),
                            'local', 'Vitalis Jardins — Rua das Acácias, 100', 'empresa_identificada', v_empresa is not null,
                            'avisos', chk->'avisos');
end $$;

CREATE FUNCTION pn.integracao_atestado_receber(p_token text, p_dados jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare h text; emp uuid; v uuid; num bigint; sit text; qtd int; m date;
begin
  select token_hash into h from pn_crm.wa_config where id;
  if h is null or p_token is null or encode(extensions.digest(p_token, 'sha256'), 'hex') <> h then
    raise exception 'Token inválido.' using errcode = '42501';
  end if;
  if nullif(p_dados->>'mensagem_id', '') is not null then
    select id, numero, situacao into v, num, sit from pn_crm.atestado where wa_mensagem_id = p_dados->>'mensagem_id';
    if v is not null then return jsonb_build_object('id', v, 'numero', num, 'situacao', sit, 'repetido', true); end if;
  end if;
  if length(pn_crm.so_digitos(p_dados->>'cnpj')) = 14 then
    select e.id into emp from pn.empresa e where pn_crm.so_digitos(e.cnpj) = pn_crm.so_digitos(p_dados->>'cnpj')
     order by (e.situacao = 'ativo') desc nulls last limit 1;
  end if;
  emp := coalesce(emp, pn_crm.wa_empresa_por_telefone(p_dados->>'telefone'));

  insert into pn_crm.atestado (empresa_id, colaborador_nome, colaborador_cpf, data_emissao, data_inicio, dias, cid, medico, medico_crm,
                            arquivo_path, arquivo_nome, origem, wa_telefone, wa_mensagem_id, leitura_ia, situacao, observacao)
  values (emp, nullif(btrim(p_dados->>'colaborador_nome'), ''), nullif(p_dados->>'colaborador_cpf', ''),
          nullif(p_dados->>'data_emissao', '')::date, nullif(p_dados->>'data_inicio', '')::date, nullif(p_dados->>'dias', '')::int,
          nullif(p_dados->>'cid', ''), nullif(btrim(p_dados->>'medico'), ''), nullif(btrim(p_dados->>'medico_crm'), ''),
          nullif(p_dados->>'arquivo_path', ''), nullif(p_dados->>'arquivo_nome', ''), 'whatsapp',
          pn_crm.so_digitos(p_dados->>'telefone'), nullif(p_dados->>'mensagem_id', ''), p_dados->'leitura_ia',
          case when emp is null or nullif(p_dados->>'colaborador_nome', '') is null then 'revisar' else 'ok' end,
          case when emp is null then 'Empresa não identificada pelo telefone/CNPJ: ' || coalesce(p_dados->>'empresa', p_dados->>'telefone', '?') end)
  returning id, numero, situacao, mes into v, num, sit, m;
  select count(*) into qtd from pn_crm.atestado where empresa_id = emp and mes = m and situacao = 'ok';
  return jsonb_build_object('id', v, 'numero', num, 'situacao', sit, 'empresa_identificada', emp is not null,
                            'atestados_no_mes', case when emp is not null then qtd end);
end $$;

CREATE FUNCTION pn.integracao_token_valido(p_token text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') from pn_crm.wa_config where id), false)
$$;

CREATE FUNCTION pn.integracao_usuario_email(p_user uuid, p_email text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  update pn_crm.perfil set email = lower(btrim(p_email)) where user_id = p_user;
end $$;

CREATE FUNCTION pn.integracao_wa_receber(p_token text, p_eventos jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare h text;
begin
  select token_hash into h from pn_crm.wa_config where id;
  if h is null or p_token is null or encode(extensions.digest(p_token, 'sha256'), 'hex') <> h then
    raise exception 'Token inválido.' using errcode = '42501';
  end if;
  return pn_crm.wa_receber(p_eventos, true);
end $$;

CREATE FUNCTION pn.integracao_wa_saida(p_token text, p_resultados jsonb DEFAULT NULL::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare h text; r jsonb;
begin
  select token_hash into h from pn_crm.wa_config where id;
  if h is null or p_token is null or encode(extensions.digest(p_token, 'sha256'), 'hex') <> h then
    raise exception 'Token inválido.' using errcode = '42501';
  end if;
  for r in select * from jsonb_array_elements(coalesce(p_resultados, '[]'::jsonb)) loop
    update pn_crm.wa_saida set
      status = case when (r->>'ok')::boolean then 'enviado' when tentativas + 1 >= 3 then 'erro' else 'pendente' end,
      tentativas = tentativas + 1, erro = r->>'erro',
      enviado_em = case when (r->>'ok')::boolean then now() end
     where id = (r->>'id')::bigint and status = 'pendente';
  end loop;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'telefone', s.telefone, 'texto', s.texto, 'para', s.para,
                                                       'origem', s.origem,
                                                       'atendente', (select p.nome from pn_crm.perfil p where p.user_id = s.usuario_id)) order by s.id)
                     from (select * from pn_crm.wa_saida where status = 'pendente' order by id limit 20) s), '[]'::jsonb);
end $$;

CREATE FUNCTION pn.painel_agenda_dia(p_data date, p_agenda uuid DEFAULT NULL::uuid) RETURNS TABLE(id uuid, numero bigint, agenda_id uuid, horario text, situacao text, tipo text, paciente_nome text, cpf text, telefone text, funcao text, empresa_id uuid, empresa text, encaixe boolean, inadimplente boolean, excecao_motivo text, cancelado_motivo text, observacao text, negocio_id uuid, chegou_em timestamp with time zone, atendido_em timestamp with time zone, finalizado_em timestamp with time zone, criado_por text, criado_em timestamp with time zone, complementares text[])
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  perform pn_crm.exige('gestor','operacoes','comercial');
  return query
    select g.id, g.numero, g.agenda_id, to_char(g.horario, 'HH24:MI'), g.situacao, g.tipo,
           g.paciente_nome, g.cpf, g.telefone, g.funcao, g.empresa_id,
           coalesce(nullif(e.nome_fantasia, ''), e.razao_social, g.empresa_nome)::text,
           g.encaixe, case when g.empresa_id is null then false else pn_crm.empresa_inadimplente(g.empresa_id) end,
           g.excecao_motivo, g.cancelado_motivo, g.observacao, g.negocio_id,
           g.chegou_em, g.atendido_em, g.finalizado_em,
           case when g.criado_via = 'ia' then 'IA (Lia)' else u.nome end::text, g.criado_em, g.complementares
      from pn_crm.agendamento g
      join pn_crm.agenda a on a.id = g.agenda_id
      left join pn.empresa e on e.id = g.empresa_id
      left join pn_crm.perfil u on u.user_id = g.criado_por
     where a.data = p_data and (p_agenda is null or g.agenda_id = p_agenda)
     order by case g.situacao when 'aguardando' then 0 when 'agendado' then 1 when 'atendido' then 2
                              when 'finalizado' then 3 when 'faltou' then 4 else 5 end,
              g.horario nulls last, g.chegou_em nulls last, g.numero;
end $$;

CREATE FUNCTION pn.painel_agenda_excluir(p_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare n int;
begin
  perform pn_crm.exige('gestor','operacoes');
  select count(*) into n from pn_crm.agendamento g where g.agenda_id = p_id and g.situacao <> 'cancelado';
  if n > 0 then
    raise exception 'A agenda tem % paciente(s). Mova ou cancele antes de excluir.', n;
  end if;
  delete from pn_crm.agendamento where agenda_id = p_id;
  delete from pn_crm.agenda where id = p_id;
end $$;

CREATE FUNCTION pn.painel_agenda_grade() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor', 'operacoes', 'comercial');
  return coalesce((select jsonb_agg(jsonb_build_object('horario', to_char(g.horario, 'HH24:MI'), 'vagas', g.vagas) order by g.horario)
                     from pn_crm.agenda_grade g where g.vagas > 0), '[]'::jsonb);
end $$;

CREATE FUNCTION pn.painel_agenda_grade_salvar(p_grade jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; total int;
begin
  eu := pn_crm.exige('gestor');
  if jsonb_typeof(p_grade) <> 'array' or jsonb_array_length(p_grade) = 0 then raise exception 'Informe ao menos um horário.'; end if;
  update pn_crm.agenda_grade set vagas = 0, atualizado_em = now(), atualizado_por = eu where true;
  insert into pn_crm.agenda_grade (horario, vagas, atualizado_por)
  select (x->>'horario')::time, greatest(coalesce((x->>'vagas')::int, 0), 0), eu from jsonb_array_elements(p_grade) x
  on conflict (horario) do update set vagas = excluded.vagas, atualizado_em = now(), atualizado_por = eu;
  select coalesce(sum(vagas), 0) into total from pn_crm.agenda_grade;

  return pn.painel_agenda_grade();
end $$;

CREATE FUNCTION pn.painel_agenda_horarios(p_agenda uuid, p_ignorar uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor', 'operacoes', 'comercial');
  return jsonb_build_object(
    'pode_encaixe', pn_crm.pode_encaixe(),
    'horarios', coalesce((select jsonb_agg(jsonb_build_object('horario', to_char(h.horario, 'HH24:MI'), 'vagas', h.vagas,
                                                              'ocupadas', h.ocupadas, 'livres', greatest(h.vagas - h.ocupadas, 0))
                                           order by h.horario)
                            from pn_crm.agenda_horarios(p_agenda, p_ignorar) h), '[]'::jsonb));
end $$;

CREATE FUNCTION pn.painel_agenda_limite_salvar(p_empresa uuid, p_limite integer, p_motivo text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor','operacoes');
  if not pn_crm.pode_liberar_agenda() then
    raise exception 'Só quem libera exceções da agenda define limite por empresa.' using errcode = '42501';
  end if;
  if p_limite is null then
    delete from pn_crm.agenda_limite_empresa where empresa_id = p_empresa;
    return;
  end if;
  insert into pn_crm.agenda_limite_empresa (empresa_id, limite, motivo, atualizado_por)
  values (p_empresa, p_limite, nullif(trim(p_motivo), ''), auth.uid())
  on conflict (empresa_id) do update set limite = excluded.limite, motivo = excluded.motivo,
    atualizado_por = excluded.atualizado_por, atualizado_em = now();
end $$;

CREATE FUNCTION pn.painel_agenda_periodo(p_de date, p_ate date) RETURNS TABLE(id uuid, data date, profissional_id uuid, profissional text, local text, empresa_id uuid, empresa text, hora_inicio text, hora_fim text, vagas integer, ocupadas integer, encaixes integer, agendados integer, aguardando integer, atendidos integer, finalizados integer, faltas integer, cancelados integer, observacao text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  perform pn_crm.exige('gestor','operacoes','comercial');
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
      from pn_crm.agenda a
      left join pn.profissional p on p.id = a.profissional_id
      left join pn.empresa e on e.id = a.empresa_id
      left join pn_crm.agendamento g on g.agenda_id = a.id
     where a.data between p_de and p_ate
     group by a.id, p.nome, e.nome_fantasia, e.razao_social
     order by a.data, a.hora_inicio nulls last, p.nome;
end $$;

CREATE FUNCTION pn.painel_agenda_regras() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor','operacoes','comercial');
  return (select jsonb_build_object('limite_empresa_dia', r.limite_empresa_dia,
                                    'bloquear_inadimplente', r.bloquear_inadimplente,
                                    'vagas_padrao', r.vagas_padrao,
                                    'hora_inicio_padrao', to_char(r.hora_inicio_padrao, 'HH24:MI'),
                                    'hora_fim_padrao', to_char(r.hora_fim_padrao, 'HH24:MI'),
                                    'pode_configurar', pn_crm.papel_atual() in ('admin','gestor','operacoes'),
                                    'pode_excecao', pn_crm.pode_liberar_agenda(),
                                    'liberam', coalesce((select jsonb_agg(p.nome order by p.nome) from pn_crm.perfil p
                                                          where p.ativo and (p.libera_agenda or p.papel = 'admin')
                                                            and p.email not ilike '%@vitalisvmrj'), '[]'::jsonb),
                                    'limites', coalesce((select jsonb_agg(jsonb_build_object(
                                                  'empresa_id', l.empresa_id, 'limite', l.limite, 'motivo', l.motivo,
                                                  'empresa', coalesce(nullif(e.nome_fantasia, ''), e.razao_social), 'cnpj', e.cnpj)
                                                  order by coalesce(nullif(e.nome_fantasia, ''), e.razao_social))
                                               from pn_crm.agenda_limite_empresa l join pn.empresa e on e.id = l.empresa_id), '[]'::jsonb))
            from pn_crm.agenda_regra r where r.id);
end $$;

CREATE FUNCTION pn.painel_agenda_regras_salvar(p_dados jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid;
begin
  eu := pn_crm.exige('gestor');
  update pn_crm.agenda_regra set
    limite_empresa_dia    = case when p_dados ? 'limite_empresa_dia'
                                 then nullif(p_dados->>'limite_empresa_dia', '')::int else limite_empresa_dia end,
    bloquear_inadimplente = coalesce((p_dados->>'bloquear_inadimplente')::boolean, bloquear_inadimplente),
    vagas_padrao          = coalesce(nullif(p_dados->>'vagas_padrao', '')::int, vagas_padrao),
    hora_inicio_padrao    = coalesce(nullif(p_dados->>'hora_inicio_padrao', '')::time, hora_inicio_padrao),
    hora_fim_padrao       = coalesce(nullif(p_dados->>'hora_fim_padrao', '')::time, hora_fim_padrao),
    atualizado_em = now(), atualizado_por = eu
  where id;
end $$;

CREATE FUNCTION pn.painel_agenda_salvar(p_id uuid, p_dados jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  eu uuid; v_id uuid := p_id; ocup int;
  v_data date := nullif(p_dados->>'data', '')::date;
  v_local text := coalesce(nullif(p_dados->>'local', ''), 'clinica');
  v_empresa uuid := nullif(p_dados->>'empresa_id', '')::uuid;
  v_vagas int := nullif(p_dados->>'vagas', '')::int;
begin
  eu := pn_crm.exige('gestor','operacoes');
  if v_data is null then raise exception 'Informe a data.'; end if;
  if v_vagas is null or v_vagas < 1 then raise exception 'Informe o número de vagas.'; end if;
  if v_local = 'in_company' and v_empresa is null then
    raise exception 'Agenda in company precisa da empresa.';
  end if;
  if v_local = 'clinica' then v_empresa := null; end if;

  if v_id is null then
    insert into pn_crm.agenda (data, profissional_id, local, empresa_id, hora_inicio, hora_fim, vagas, observacao, criado_por)
    values (v_data, nullif(p_dados->>'profissional_id', '')::uuid, v_local, v_empresa,
            nullif(p_dados->>'hora_inicio', '')::time, nullif(p_dados->>'hora_fim', '')::time,
            v_vagas, nullif(trim(p_dados->>'observacao'), ''), eu)
    returning id into v_id;
  else
    select count(*) into ocup from pn_crm.agendamento g
     where g.agenda_id = v_id and not g.encaixe and g.situacao not in ('cancelado','faltou');
    if v_vagas < ocup then
      raise exception 'Já há % pacientes nesta agenda; as vagas não podem ficar abaixo disso.', ocup;
    end if;
    if exists (select 1 from pn_crm.agenda a where a.id = v_id and a.data <> v_data)
       and exists (select 1 from pn_crm.agendamento g where g.agenda_id = v_id and g.situacao not in ('agendado','cancelado','faltou')) then
      raise exception 'Esta agenda já tem atendimentos; não dá para mudar a data.';
    end if;
    update pn_crm.agenda set data = v_data, profissional_id = nullif(p_dados->>'profissional_id', '')::uuid,
           local = v_local, empresa_id = v_empresa,
           hora_inicio = nullif(p_dados->>'hora_inicio', '')::time, hora_fim = nullif(p_dados->>'hora_fim', '')::time,
           vagas = v_vagas, observacao = nullif(trim(p_dados->>'observacao'), ''), atualizado_em = now()
     where id = v_id;
    if not found then raise exception 'Agenda não encontrada.'; end if;
  end if;
  return v_id;
end $$;

CREATE FUNCTION pn.painel_agendamento_checar(p_agenda uuid, p_empresa uuid DEFAULT NULL::uuid, p_encaixe boolean DEFAULT false, p_ignorar uuid DEFAULT NULL::uuid, p_tipo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor','operacoes','comercial');
  return pn_crm.agenda_checar(p_agenda, p_empresa, p_encaixe, p_ignorar, p_tipo);
end $$;

CREATE FUNCTION pn.painel_agendamento_historico(p_id uuid) RETURNS TABLE(texto text, autor text, criado_em timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  perform pn_crm.exige('gestor','operacoes','comercial');
  return query
    select ev.texto, coalesce(u.nome, 'Sistema')::text, ev.criado_em
      from pn_crm.agendamento_evento ev left join pn_crm.perfil u on u.user_id = ev.autor_id
     where ev.agendamento_id = p_id order by ev.criado_em desc, ev.id desc;
end $$;

CREATE FUNCTION pn.painel_agendamento_salvar(p_id uuid, p_dados jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  eu uuid; papel pn_crm.papel; v_id uuid := p_id; atual pn_crm.agendamento; chk jsonb;
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
  tem_grade boolean := exists (select 1 from pn_crm.agenda_grade where vagas > 0);
begin
  eu := pn_crm.exige('gestor','operacoes','comercial');
  papel := pn_crm.papel_atual();
  if v_agenda is null then raise exception 'Escolha a agenda.'; end if;
  if v_nome is null then raise exception 'Informe o nome do paciente.'; end if;
  if v_empresa is null and nullif(trim(p_dados->>'empresa_nome'), '') is null then
    raise exception 'Informe a empresa (ou "Particular").';
  end if;
  if v_cpf is not null and length(v_cpf) <> 11 then raise exception 'CPF deve ter 11 dígitos.'; end if;

  if v_id is not null then
    select * into atual from pn_crm.agendamento where id = v_id for update;
    if atual.id is null then raise exception 'Agendamento não encontrado.'; end if;
    if atual.situacao in ('finalizado','cancelado') and papel not in ('admin','gestor') then
      raise exception 'Agendamento % não pode ser editado; peça a um gestor.', lower(pn_crm.agenda_rotulo(atual.situacao));
    end if;
    mudou_vaga := atual.agenda_id <> v_agenda or atual.empresa_id is distinct from v_empresa
                  or atual.encaixe <> v_encaixe or atual.horario is distinct from v_hora;
  end if;

  if v_encaixe and not pn_crm.pode_encaixe() and not (v_id is not null and atual.encaixe) then
    raise exception 'Encaixe (além das 40 vagas) só o atendimento pode marcar. Escolha um horário vago.';
  end if;

  chk := pn_crm.agenda_checar(v_agenda, v_empresa, v_encaixe, v_id, v_tipo);

  if mudou_vaga and not v_encaixe and tem_grade then
    if v_hora is null then
      chk := jsonb_set(chk, '{bloqueios}', (chk->'bloqueios') || to_jsonb('Escolha um horário da grade.'::text));
    else
      select * into slot from pn_crm.agenda_horarios(v_agenda, v_id) h where h.horario = v_hora;
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
    if not pn_crm.pode_liberar_agenda() then
      raise exception 'Só quem libera exceções da agenda pode passar por cima da regra: %',
        (select string_agg(x, ' ') from jsonb_array_elements_text(chk->'bloqueios') x) using errcode = '42501';
    end if;
  end if;

  if v_id is null then
    insert into pn_crm.agendamento (agenda_id, horario, empresa_id, empresa_nome, colaborador_id, paciente_nome, cpf,
                                 telefone, funcao, tipo, encaixe, excecao_motivo, negocio_id, observacao, complementares, criado_por)
    values (v_agenda, v_hora, v_empresa,
            case when v_empresa is null then nullif(trim(p_dados->>'empresa_nome'), '') end,
            nullif(p_dados->>'colaborador_id', '')::uuid, v_nome, v_cpf,
            nullif(trim(p_dados->>'telefone'), ''), nullif(trim(p_dados->>'funcao'), ''),
            v_tipo, v_encaixe,
            case when mudou_vaga and jsonb_array_length(chk->'bloqueios') > 0 then v_excecao end,
            nullif(p_dados->>'negocio_id', '')::uuid, nullif(trim(p_dados->>'observacao'), ''), v_comp, eu)
    returning id into v_id;
    perform pn_crm.agenda_registrar(v_id, 'Agendado' || case when v_encaixe then ' (encaixe)' else '' end);
  else
    update pn_crm.agendamento set agenda_id = v_agenda, horario = v_hora,
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
    perform pn_crm.agenda_registrar(v_id, case when atual.agenda_id <> v_agenda then 'Remarcado para outra agenda'
                                            when atual.horario is distinct from v_hora then 'Horário: ' || coalesce(to_char(v_hora, 'HH24:MI'), 'sem horário')
                                            else 'Dados atualizados' end);
  end if;

  if mudou_vaga and jsonb_array_length(chk->'bloqueios') > 0 then
    perform pn_crm.agenda_registrar(v_id, 'Liberado fora da regra: ' || v_excecao);
  end if;
  return jsonb_build_object('id', v_id, 'avisos', chk->'avisos');
end $$;

CREATE FUNCTION pn.painel_agendamento_situacao(p_id uuid, p_situacao text, p_motivo text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; papel pn_crm.papel; atual pn_crm.agendamento; motivo text := nullif(trim(p_motivo), '');
begin
  eu := pn_crm.exige('gestor','operacoes','comercial');
  papel := pn_crm.papel_atual();
  if p_situacao not in ('agendado','aguardando','atendido','finalizado','cancelado','faltou') then
    raise exception 'Situação inválida: %', p_situacao;
  end if;
  select * into atual from pn_crm.agendamento where id = p_id for update;
  if atual.id is null then raise exception 'Agendamento não encontrado.'; end if;
  if atual.situacao = p_situacao then return; end if;

  if papel = 'comercial' and p_situacao not in ('agendado','cancelado') then
    raise exception 'Seu perfil agenda e cancela; chegada e atendimento ficam com operações.' using errcode = '42501';
  end if;
  if atual.situacao in ('finalizado','cancelado') and papel not in ('admin','gestor','operacoes') then
    raise exception 'Só operações ou gestor reabre um agendamento %.', lower(pn_crm.agenda_rotulo(atual.situacao))
      using errcode = '42501';
  end if;
  if p_situacao = 'cancelado' and motivo is null then
    raise exception 'Informe o motivo do cancelamento.';
  end if;

  if atual.situacao in ('cancelado','faltou') and p_situacao not in ('cancelado','faltou') and not atual.encaixe
     and exists (select 1 from pn_crm.agenda a where a.id = atual.agenda_id
                  and a.vagas <= (select count(*) from pn_crm.agendamento g where g.agenda_id = a.id and not g.encaixe
                                    and g.situacao not in ('cancelado','faltou'))) then
    update pn_crm.agendamento set encaixe = true where id = p_id;
    perform pn_crm.agenda_registrar(p_id, 'Agenda lotada: voltou como encaixe');
  end if;

  update pn_crm.agendamento set
    situacao = p_situacao,
    chegou_em     = case when p_situacao = 'aguardando' then coalesce(chegou_em, now())
                         when p_situacao = 'agendado' then null else chegou_em end,
    atendido_em   = case when p_situacao in ('atendido','finalizado') then coalesce(atendido_em, now())
                         when p_situacao in ('agendado','aguardando') then null else atendido_em end,
    finalizado_em = case when p_situacao = 'finalizado' then now() else null end,
    cancelado_motivo = case when p_situacao = 'cancelado' then motivo else null end,
    atualizado_em = now()
  where id = p_id;
  perform pn_crm.agenda_registrar(p_id, pn_crm.agenda_rotulo(atual.situacao) || ' → ' || pn_crm.agenda_rotulo(p_situacao)
                                     || coalesce(': ' || motivo, ''));
end $$;

CREATE FUNCTION pn.painel_atendimento(p_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r jsonb;
begin
  perform pn_crm.exige('gestor','operacoes');
  select jsonb_build_object(
           'id', a.id, 'sesmo_id', a.sesmo_id, 'tipo', a.tipo, 'situacao', a.situacao,
           'data_agendada', a.data_agendada, 'data_atendimento', a.data_atendimento,
           'hora', to_char(a.data_agendada at time zone 'America/Sao_Paulo', 'HH24:MI'),
           'aso_resultado', a.aso_resultado, 'aso_emitido_em', a.aso_emitido_em,
           'profissional_id', a.profissional_id, 'profissional', p.nome,
           'local_atendimento', a.local_atendimento, 'observacao', a.observacao, 'origem', a.origem,
           'colaborador_id', a.colaborador_id, 'colaborador', c.nome, 'cpf', c.cpf,
           'empresa_id', a.empresa_id, 'empresa', coalesce(nullif(e.nome_fantasia, ''), e.razao_social),
           'funcao', f.nome, 'campos_editados', to_jsonb(a.campos_editados),
           'exames', coalesce((select jsonb_agg(jsonb_build_object('nome', et.nome, 'data', ae.data_realizacao, 'resultado', ae.resultado) order by et.nome)
                                 from pn.atendimento_exame ae join pn.exame_tipo et on et.id = ae.exame_tipo_id
                                where ae.atendimento_id = a.id), '[]'::jsonb),
           'historico', pn_crm.historico_edicao('atendimento', a.id),
           'pode_editar', pn_crm.pode_editar_dados())
    into r
    from pn.atendimento a
    join pn.colaborador c on c.id = a.colaborador_id
    join pn.empresa e on e.id = a.empresa_id
    left join pn.funcao f on f.id = a.funcao_id
    left join pn.profissional p on p.id = a.profissional_id
   where a.id = p_id;
  if r is null then raise exception 'Atendimento não encontrado.'; end if;
  return r;
end $$;

CREATE FUNCTION pn.painel_atendimento_salvar(p_id uuid, p_dados jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare d jsonb; mud text[]; dia date; hora time;
begin
  perform pn_crm.exige('gestor');
  d := pn_crm.limpar_dados(p_dados, array['tipo','situacao','data_atendimento','profissional_id','aso_resultado','aso_emitido_em',
                                       'local_atendimento','observacao']);
  if d ? 'tipo' and d ->> 'tipo' is null then d := d - 'tipo'; end if;
  if d ? 'situacao' and d ->> 'situacao' is null then d := d - 'situacao'; end if;
  if d ? 'aso_resultado' and d ->> 'aso_resultado' is null then d := d - 'aso_resultado'; end if;
  if p_dados ? 'data_atendimento' then
    dia := nullif(p_dados ->> 'data_atendimento', '')::date;
    if dia is null then raise exception 'Informe a data do atendimento.'; end if;
    hora := coalesce(nullif(p_dados ->> 'hora', '')::time, '00:00');
    d := d || jsonb_build_object('data_agendada', ((dia + hora) at time zone 'America/Sao_Paulo'));
  end if;
  mud := pn_crm.editar('atendimento', p_id, d);
  return jsonb_build_object('alterados', to_jsonb(mud));
end $$;

CREATE FUNCTION pn.painel_atendimentos(p_empresa uuid DEFAULT NULL::uuid, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_situacao text DEFAULT NULL::text, p_busca text DEFAULT NULL::text, p_limite integer DEFAULT 100, p_offset integer DEFAULT 0) RETURNS TABLE(id uuid, data_atendimento timestamp with time zone, data_agendada timestamp with time zone, tipo text, situacao text, aso_resultado text, colaborador text, cpf text, empresa_id uuid, empresa text, funcao text, profissional text, qtd_exames integer, total bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform pn_crm.exige('gestor','operacoes');
  return query
    select a.id, coalesce(a.data_agendada, a.data_atendimento::timestamp at time zone 'America/Sao_Paulo'), a.data_agendada::timestamptz, a.tipo::text, a.situacao::text,
           a.aso_resultado::text, c.nome::text, c.cpf::text, a.empresa_id,
           coalesce(nullif(e.nome_fantasia, ''), e.razao_social)::text, f.nome::text, p.nome::text,
           (select count(*)::int from pn.atendimento_exame ae where ae.atendimento_id = a.id),
           count(*) over ()
      from pn.atendimento a
      left join pn.colaborador c on c.id = a.colaborador_id
      left join pn.empresa e on e.id = a.empresa_id
      left join pn.funcao f on f.id = a.funcao_id
      left join pn.profissional p on p.id = a.profissional_id
     where (p_empresa is null or a.empresa_id = p_empresa)
       and (p_de is null or coalesce(a.data_atendimento, a.data_agendada) >= p_de)
       and (p_ate is null or coalesce(a.data_atendimento, a.data_agendada) < p_ate + 1)
       and (p_situacao is null or a.situacao::text = p_situacao)
       and (termo is null or c.nome ilike '%' || termo || '%' or c.cpf like '%' || termo || '%')
     order by coalesce(a.data_atendimento, a.data_agendada) desc nulls last
     limit least(greatest(p_limite, 1), 1000) offset greatest(p_offset, 0);
end $$;

CREATE FUNCTION pn.painel_atestado_arquivo(p_id uuid, p_path text, p_nome text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor','operacoes');
  update pn_crm.atestado set arquivo_path = p_path, arquivo_nome = p_nome where id = p_id;
end $$;

CREATE FUNCTION pn.painel_atestado_regra_salvar(p_limite integer, p_prazo_dias integer, p_ativo boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor');
  update pn_crm.atestado_regra set limite = p_limite, prazo_dias = p_prazo_dias, ativo = p_ativo where id;
end $$;

CREATE FUNCTION pn.painel_atestado_salvar(p_id uuid, p_dados jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare uid uuid := pn_crm.exige('gestor','operacoes'); v uuid; antes pn_crm.atestado;
begin
  if p_id is null then
    insert into pn_crm.atestado (empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, data_emissao, data_inicio, dias, cid,
                              medico, medico_crm, observacao, situacao, origem, criado_por)
    values (nullif(p_dados->>'empresa_id', '')::uuid, nullif(p_dados->>'colaborador_id', '')::uuid,
            nullif(btrim(p_dados->>'colaborador_nome'), ''), nullif(p_dados->>'colaborador_cpf', ''),
            nullif(p_dados->>'data_emissao', '')::date, nullif(p_dados->>'data_inicio', '')::date, nullif(p_dados->>'dias', '')::int,
            nullif(p_dados->>'cid', ''), nullif(btrim(p_dados->>'medico'), ''), nullif(btrim(p_dados->>'medico_crm'), ''),
            nullif(btrim(p_dados->>'observacao'), ''), coalesce(nullif(p_dados->>'situacao', ''), 'ok'), 'painel', uid)
    returning id into v;
    insert into pn_crm.edicao (tabela, registro_id, usuario_id, acao, mudancas)
    values ('atestado', v, uid, 'criar', (select jsonb_object_agg(k, jsonb_build_object('de', null, 'para', x))
                                            from jsonb_each(p_dados - 'cid') e(k, x) where x <> 'null'::jsonb and x <> '""'::jsonb));
    return v;
  end if;
  select * into antes from pn_crm.atestado where id = p_id;
  if antes.id is null then raise exception 'Atestado não encontrado.'; end if;
  update pn_crm.atestado set
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
  insert into pn_crm.edicao (tabela, registro_id, usuario_id, acao, mudancas)
  select 'atestado', p_id, uid, 'editar', jsonb_object_agg(k, case when k = 'cid' then jsonb_build_object('de', '(oculto)', 'para', '(alterado)')
                                                                    else jsonb_build_object('de', a.j -> k, 'para', d.j -> k) end)
    from (select to_jsonb(antes) j) a, (select to_jsonb(t) j from pn_crm.atestado t where t.id = p_id) d,
         jsonb_object_keys(p_dados) k
   where (a.j -> k) is distinct from (d.j -> k)
  having count(*) > 0;
  return p_id;
end $$;

CREATE FUNCTION pn.painel_atestados(p_mes date DEFAULT NULL::date, p_empresa uuid DEFAULT NULL::uuid, p_situacao text DEFAULT NULL::text, p_busca text DEFAULT NULL::text, p_limite integer DEFAULT 100, p_offset integer DEFAULT 0) RETURNS TABLE(id uuid, numero bigint, empresa_id uuid, empresa text, colaborador_id uuid, colaborador text, cpf text, data_emissao date, data_inicio date, dias integer, cid text, medico text, medico_crm text, origem text, wa_telefone text, situacao text, observacao text, arquivo_path text, arquivo_nome text, mes date, criado_em timestamp with time zone, total bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform pn_crm.exige('gestor','operacoes');
  return query
    select a.id, a.numero, a.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social), a.colaborador_id, a.colaborador_nome,
           a.colaborador_cpf, a.data_emissao, a.data_inicio, a.dias, a.cid, a.medico, a.medico_crm, a.origem, a.wa_telefone,
           a.situacao, a.observacao, a.arquivo_path, a.arquivo_nome, a.mes, a.criado_em, count(*) over ()
      from pn_crm.atestado a left join pn.empresa e on e.id = a.empresa_id
     where (p_mes is null or a.mes = date_trunc('month', p_mes)::date)
       and (p_empresa is null or a.empresa_id = p_empresa)
       and (case when p_situacao is null then a.situacao <> 'descartado' else a.situacao = p_situacao end)
       and (termo is null or a.colaborador_nome ilike '%' || termo || '%' or a.colaborador_cpf like '%' || pn_crm.so_digitos(termo) || '%'
            or e.razao_social ilike '%' || termo || '%' or e.nome_fantasia ilike '%' || termo || '%')
     order by (a.situacao = 'revisar') desc, a.criado_em desc
     limit least(greatest(p_limite, 1), 500) offset greatest(p_offset, 0);
end $$;

CREATE FUNCTION pn.painel_atestados_resumo(p_mes date DEFAULT NULL::date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare m date := date_trunc('month', coalesce(p_mes, (now() at time zone 'America/Sao_Paulo')::date))::date; r pn_crm.atestado_regra;
begin
  perform pn_crm.exige('gestor','operacoes');
  select * into r from pn_crm.atestado_regra where id;
  return jsonb_build_object(
    'mes', m, 'limite', r.limite, 'prazo_dias', r.prazo_dias, 'ativo', r.ativo,
    'total', (select count(*) from pn_crm.atestado where mes = m and situacao = 'ok'),
    'empresas', (select count(distinct empresa_id) from pn_crm.atestado where mes = m and situacao = 'ok'),
    'alertas', (select count(*) from pn_crm.atestado_alerta where mes = m),
    'revisar', (select count(*) from pn_crm.atestado where situacao = 'revisar'),
    'ranking', coalesce((
      select jsonb_agg(x order by x.quantidade desc, x.nome) from (
        select a.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social) nome, count(*) quantidade,
               coalesce(sum(a.dias), 0) dias, exists (select 1 from pn_crm.atestado_alerta al where al.empresa_id = a.empresa_id and al.mes = m) alertado
          from pn_crm.atestado a join pn.empresa e on e.id = a.empresa_id
         where a.mes = m and a.situacao = 'ok'
         group by a.empresa_id, e.nome_fantasia, e.razao_social
         order by count(*) desc limit 15) x), '[]'::jsonb));
end $$;

CREATE FUNCTION pn.painel_auditoria(p_origem text DEFAULT NULL::text, p_usuario uuid DEFAULT NULL::uuid, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_busca text DEFAULT NULL::text, p_limite integer DEFAULT 100, p_offset integer DEFAULT 0) RETURNS TABLE(em timestamp with time zone, origem text, usuario_id uuid, usuario text, acao text, entidade text, registro_id uuid, registro text, detalhe jsonb, total bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform pn_crm.exige('admin');
  return query
    with ed as (
      select e.em, 'cadastro'::text origem, e.usuario_id, e.acao, e.tabela entidade, e.registro_id,
             coalesce(
               case e.tabela
                 when 'empresa' then (select coalesce(nullif(x.nome_fantasia, ''), x.razao_social) from pn.empresa x where x.id = e.registro_id)
                 when 'colaborador' then (select x.nome || ' — ' || coalesce(nullif(em.nome_fantasia, ''), em.razao_social)
                                            from pn.colaborador x join pn.empresa em on em.id = x.empresa_id where x.id = e.registro_id)
                 when 'unidade' then (select x.nome from pn.unidade x where x.id = e.registro_id)
                 when 'empresa_contato' then (select coalesce(x.nome, '(contato)') from pn.empresa_contato x where x.id = e.registro_id)
                 when 'atestado' then (select 'Atestado #' || x.numero || coalesce(' — ' || x.colaborador_nome, '')
                                        from pn_crm.atestado x where x.id = e.registro_id)
                 when 'atendimento' then (select c.nome || ' — ' || to_char(a.data_atendimento, 'DD/MM/YYYY')
                                            from pn.atendimento a join pn.colaborador c on c.id = a.colaborador_id where a.id = e.registro_id)
               end,
               e.mudancas #>> '{registro,nome}', '(registro removido)') registro,
             e.mudancas detalhe
        from pn_crm.edicao e
       where (p_origem is null or p_origem = 'cadastro')
    ), ev as (
      select v.criado_em em, 'crm'::text, v.autor_id, v.tipo, 'negocio'::text, v.negocio_id,
             '#' || n.numero || ' ' || n.titulo || ' (' || f.nome || ')',
             jsonb_build_object('texto', v.texto, 'de', de.nome, 'para', pa.nome)
        from pn_crm.evento v
        join pn_crm.negocio n on n.id = v.negocio_id
        join pn_crm.funil f on f.id = n.funil_id
        left join pn_crm.etapa de on de.id = v.de_etapa_id
        left join pn_crm.etapa pa on pa.id = v.para_etapa_id
       where (p_origem is null or p_origem = 'crm') and v.autor_id is not null
    ), tudo as (
      select * from ed union all select * from ev
    )
    select t.em, t.origem, t.usuario_id, coalesce(p.nome, u.email)::text, t.acao, t.entidade, t.registro_id, t.registro, t.detalhe,
           count(*) over ()
      from tudo t
      left join pn_crm.perfil p on p.user_id = t.usuario_id
      left join auth.users u on u.id = t.usuario_id
     where (p_usuario is null or t.usuario_id = p_usuario)
       and (p_de is null or t.em >= p_de::timestamp at time zone 'America/Sao_Paulo')
       and (p_ate is null or t.em < (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo')
       and (termo is null or t.registro ilike '%' || termo || '%' or coalesce(p.nome, '') ilike '%' || termo || '%')
     order by t.em desc
     limit least(greatest(p_limite, 1), 500) offset greatest(p_offset, 0);
end $$;

CREATE FUNCTION pn.painel_bitrix_empresa_vincular(p_bitrix_id bigint, p_empresa uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare b pn_crm.bitrix_empresa; n int;
begin
  perform pn_crm.exige('gestor');
  select * into b from pn_crm.bitrix_empresa where bitrix_id = p_bitrix_id;
  if b.bitrix_id is null then raise exception 'Empresa do Bitrix não encontrada.'; end if;
  update pn_crm.bitrix_empresa set empresa_id = p_empresa, metodo = case when p_empresa is null then null else 'manual' end, atualizado_em = now()
   where bitrix_id = p_bitrix_id;

  update pn_crm.negocio n set empresa_id = p_empresa where n.bitrix_empresa = p_bitrix_id;
  get diagnostics n = row_count;
  insert into pn_crm.edicao (tabela, registro_id, usuario_id, acao, mudancas)
  select 'empresa', p_empresa, auth.uid(), 'editar',
         jsonb_build_object('vinculo_bitrix', jsonb_build_object('de', b.empresa_id, 'para', b.nome || ' (Bitrix #' || p_bitrix_id || ', ' || n || ' cards)'))
   where p_empresa is not null;
  return n;
end $$;

CREATE FUNCTION pn.painel_bitrix_empresas(p_busca text DEFAULT NULL::text, p_so_sem_vinculo boolean DEFAULT true, p_limite integer DEFAULT 100, p_offset integer DEFAULT 0) RETURNS TABLE(bitrix_id bigint, nome text, cnpj text, empresa_id uuid, empresa text, metodo text, negocios bigint, abertos bigint, total bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform pn_crm.exige('gestor');
  return query
    select b.bitrix_id, b.nome, b.cnpj, b.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social), b.metodo,
           (select count(*) from pn_crm.negocio n where n.bitrix_empresa = b.bitrix_id),
           (select count(*) from pn_crm.negocio n join pn_crm.etapa et on et.id = n.etapa_id and et.tipo = 'aberta'
             where n.bitrix_empresa = b.bitrix_id),
           count(*) over ()
      from pn_crm.bitrix_empresa b left join pn.empresa e on e.id = b.empresa_id
     where (not p_so_sem_vinculo or b.empresa_id is null)
       and (termo is null or b.nome ilike '%' || termo || '%' or b.cnpj like '%' || pn_crm.so_digitos(termo) || '%')
     order by b.nome
     limit least(greatest(p_limite, 1), 500) offset greatest(p_offset, 0);
end $$;

CREATE FUNCTION pn.painel_chat_apagar(p_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid;
begin
  eu := pn_crm.exige_ativo();
  update pn_crm.chat_mensagem set excluida = true
   where id = p_id and (autor_id = eu or pn_crm.papel_atual() = 'admin');
  if not found then raise exception 'Só dá para apagar as próprias mensagens.'; end if;
end $$;

CREATE FUNCTION pn.painel_chat_direto(p_user uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; s uuid;
begin
  eu := pn_crm.exige_ativo();
  if p_user = eu then raise exception 'Escolha outra pessoa.'; end if;
  if not exists (select 1 from pn_crm.perfil where user_id = p_user and ativo) then raise exception 'Pessoa não encontrada.'; end if;
  select a.sala_id into s from pn_crm.chat_membro a join pn_crm.chat_membro b on b.sala_id = a.sala_id and b.user_id = p_user
    join pn_crm.chat_sala x on x.id = a.sala_id and x.tipo = 'direto'
   where a.user_id = eu limit 1;
  if s is null then
    insert into pn_crm.chat_sala (tipo, criado_por) values ('direto', eu) returning id into s;
    insert into pn_crm.chat_membro (sala_id, user_id) values (s, eu), (s, p_user);
  end if;
  return s;
end $$;

CREATE FUNCTION pn.painel_chat_enviar(p_sala uuid, p_texto text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; novo bigint; t text := btrim(coalesce(p_texto, ''));
begin
  eu := pn_crm.chat_exige(p_sala);
  if t = '' then raise exception 'Escreva uma mensagem.'; end if;
  if length(t) > 4000 then raise exception 'Mensagem muito longa (máximo 4.000 caracteres).'; end if;
  insert into pn_crm.chat_mensagem (sala_id, autor_id, texto) values (p_sala, eu, t) returning id into novo;
  update pn_crm.chat_sala set ultima_em = now() where id = p_sala;
  insert into pn_crm.chat_membro (sala_id, user_id, lida_em) values (p_sala, eu, now())
  on conflict (sala_id, user_id) do update set lida_em = now();
  return novo;
end $$;

CREATE FUNCTION pn.painel_chat_enviar_anexo(p_sala uuid, p_path text, p_tipo text, p_nome text, p_mime text, p_tamanho integer, p_duracao numeric DEFAULT NULL::numeric, p_legenda text DEFAULT NULL::text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; novo bigint; leg text := nullif(btrim(coalesce(p_legenda, '')), ''); rotulo text;
begin
  eu := pn_crm.chat_exige(p_sala);
  if p_tipo not in ('imagem', 'audio', 'arquivo') then raise exception 'Tipo de anexo inválido.'; end if;
  if split_part(coalesce(p_path, ''), '/', 1) <> p_sala::text then raise exception 'Anexo fora da pasta da conversa.'; end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'pn-chat' and o.name = p_path) then
    raise exception 'Arquivo não encontrado. Tente enviar de novo.';
  end if;
  if leg is not null and length(leg) > 4000 then raise exception 'Legenda muito longa.'; end if;
  rotulo := case p_tipo when 'imagem' then '📷 Imagem' when 'audio' then '🎤 Áudio'
                        else '📎 ' || left(coalesce(nullif(btrim(p_nome), ''), 'Arquivo'), 200) end;
  insert into pn_crm.chat_mensagem (sala_id, autor_id, texto, texto_auto, anexo_path, anexo_tipo, anexo_nome, anexo_mime, anexo_tamanho, anexo_duracao)
  values (p_sala, eu, coalesce(leg, rotulo), leg is null, p_path, p_tipo, left(p_nome, 200), left(p_mime, 100), p_tamanho, p_duracao)
  returning id into novo;
  update pn_crm.chat_sala set ultima_em = now() where id = p_sala;
  insert into pn_crm.chat_membro (sala_id, user_id, lida_em) values (p_sala, eu, now())
  on conflict (sala_id, user_id) do update set lida_em = now();
  return novo;
end $$;

CREATE FUNCTION pn.painel_chat_grupo_salvar(p_id uuid, p_nome text, p_descricao text, p_membros uuid[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; s uuid := p_id; nm text := btrim(coalesce(p_nome, ''));
begin
  eu := pn_crm.exige_ativo();
  if nm = '' then raise exception 'Dê um nome ao grupo.'; end if;
  if s is null then
    insert into pn_crm.chat_sala (tipo, nome, descricao, criado_por) values ('grupo', nm, nullif(btrim(p_descricao), ''), eu) returning id into s;
    insert into pn_crm.chat_membro (sala_id, user_id, dono) values (s, eu, true);
  else
    if not exists (select 1 from pn_crm.chat_sala where id = s and tipo = 'grupo' and not arquivada) then raise exception 'Grupo não encontrado.'; end if;
    if not (pn_crm.papel_atual() in ('admin','gestor')
            or exists (select 1 from pn_crm.chat_membro where sala_id = s and user_id = eu and dono)) then
      raise exception 'Só quem criou o grupo (ou um gestor) pode alterá-lo.' using errcode = '42501';
    end if;
    update pn_crm.chat_sala set nome = nm, descricao = nullif(btrim(p_descricao), '') where id = s;
    delete from pn_crm.chat_membro m where m.sala_id = s and not m.dono and not (m.user_id = any (coalesce(p_membros, '{}')));
  end if;
  insert into pn_crm.chat_membro (sala_id, user_id)
  select s, p.user_id from pn_crm.perfil p where p.ativo and p.user_id = any (coalesce(p_membros, '{}'))
  on conflict do nothing;
  return s;
end $$;

CREATE FUNCTION pn.painel_chat_lida(p_sala uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid;
begin
  eu := pn_crm.chat_exige(p_sala);
  insert into pn_crm.chat_membro (sala_id, user_id, lida_em) values (p_sala, eu, now())
  on conflict (sala_id, user_id) do update set lida_em = now();
end $$;

CREATE FUNCTION pn.painel_chat_mensagens(p_sala uuid, p_antes bigint DEFAULT NULL::bigint, p_limite integer DEFAULT 60) RETURNS TABLE(id bigint, autor_id uuid, autor text, texto text, criado_em timestamp with time zone, excluida boolean, minha boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := pn_crm.chat_exige(p_sala);
  return query
    select x.id, x.autor_id, p.nome::text, case when x.excluida then null else x.texto end, x.criado_em, x.excluida, x.autor_id = eu
      from (select * from pn_crm.chat_mensagem m where m.sala_id = p_sala and (p_antes is null or m.id < p_antes)
             order by m.id desc limit least(greatest(p_limite, 1), 200)) x
      left join pn_crm.perfil p on p.user_id = x.autor_id
     order by x.id;
end $$;

CREATE FUNCTION pn.painel_chat_mensagens_v2(p_sala uuid, p_antes bigint DEFAULT NULL::bigint, p_limite integer DEFAULT 60) RETURNS TABLE(id bigint, autor_id uuid, autor text, texto text, texto_auto boolean, criado_em timestamp with time zone, excluida boolean, minha boolean, anexo_path text, anexo_tipo text, anexo_nome text, anexo_mime text, anexo_tamanho integer, anexo_duracao numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := pn_crm.chat_exige(p_sala);
  return query
    select x.id, x.autor_id, p.nome::text, case when x.excluida then null else x.texto end, x.texto_auto,
           x.criado_em, x.excluida, x.autor_id = eu,
           case when x.excluida then null else x.anexo_path end, case when x.excluida then null else x.anexo_tipo end,
           case when x.excluida then null else x.anexo_nome end, case when x.excluida then null else x.anexo_mime end,
           case when x.excluida then null else x.anexo_tamanho end, case when x.excluida then null else x.anexo_duracao end
      from (select * from pn_crm.chat_mensagem m where m.sala_id = p_sala and (p_antes is null or m.id < p_antes)
             order by m.id desc limit least(greatest(p_limite, 1), 200)) x
      left join pn_crm.perfil p on p.user_id = x.autor_id
     order by x.id;
end $$;

CREATE FUNCTION pn.painel_chat_nao_lidas() RETURNS integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(sum(nao_lidas), 0)::int from pn.painel_chat_salas()
$$;

CREATE FUNCTION pn.painel_chat_pessoas() RETURNS TABLE(user_id uuid, nome text, papel text, cargo text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  perform pn_crm.exige_ativo();
  return query select p.user_id, p.nome::text, p.papel::text, pc.cargo::text
    from pn_crm.perfil p
    left join auth.users u on u.id = p.user_id
    left join pn_crm.pre_cadastro pc on lower(pc.email) = lower(u.email)
   where p.ativo and p.user_id <> auth.uid() order by p.nome;
end $$;

CREATE FUNCTION pn.painel_chat_sair(p_sala uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid;
begin
  eu := pn_crm.chat_exige(p_sala);
  if exists (select 1 from pn_crm.chat_sala where id = p_sala and tipo <> 'grupo') then raise exception 'Só dá para sair de grupos.'; end if;
  delete from pn_crm.chat_membro where sala_id = p_sala and user_id = eu;

  if not exists (select 1 from pn_crm.chat_membro where sala_id = p_sala and dono) then
    update pn_crm.chat_membro set dono = true
     where (sala_id, user_id) = (select sala_id, user_id from pn_crm.chat_membro where sala_id = p_sala order by entrou_em limit 1);
  end if;
  if not exists (select 1 from pn_crm.chat_membro where sala_id = p_sala) then
    update pn_crm.chat_sala set arquivada = true where id = p_sala;
  end if;
end $$;

CREATE FUNCTION pn.painel_chat_sala(p_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r jsonb;
begin
  perform pn_crm.chat_exige(p_id);
  select jsonb_build_object('id', s.id, 'tipo', s.tipo, 'nome', s.nome, 'descricao', s.descricao,
           'pode_editar', s.tipo = 'grupo' and (pn_crm.papel_atual() in ('admin','gestor')
                            or exists (select 1 from pn_crm.chat_membro m where m.sala_id = s.id and m.user_id = auth.uid() and m.dono)),
           'membros', case when s.tipo = 'geral' then '[]'::jsonb else coalesce((
               select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'nome', p.nome, 'dono', m.dono) order by m.dono desc, p.nome)
                 from pn_crm.chat_membro m join pn_crm.perfil p on p.user_id = m.user_id where m.sala_id = s.id), '[]'::jsonb) end)
    into r from pn_crm.chat_sala s where s.id = p_id;
  return r;
end $$;

CREATE FUNCTION pn.painel_chat_salas() RETURNS TABLE(id uuid, tipo text, nome text, descricao text, membros integer, ultima_texto text, ultima_autor text, ultima_em timestamp with time zone, nao_lidas integer, dono boolean, outro_id uuid)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := pn_crm.exige_ativo();
  return query
    with minhas as (
      select s.* from pn_crm.chat_sala s
       where not s.arquivada
         and (s.tipo = 'geral' or exists (select 1 from pn_crm.chat_membro m where m.sala_id = s.id and m.user_id = eu))
    )
    select s.id, s.tipo,
           case when s.tipo = 'direto' then (select p.nome from pn_crm.chat_membro m join pn_crm.perfil p on p.user_id = m.user_id
                                               where m.sala_id = s.id and m.user_id <> eu limit 1)
                else s.nome end::text,
           s.descricao::text,
           case when s.tipo = 'geral' then (select count(*)::int from pn_crm.perfil p where p.ativo)
                else (select count(*)::int from pn_crm.chat_membro m where m.sala_id = s.id) end,
           ul.texto::text, ul.autor::text, ul.criado_em,
           (select count(*)::int from pn_crm.chat_mensagem x
             where x.sala_id = s.id and not x.excluida and x.autor_id is distinct from eu
               and x.criado_em > coalesce((select m.lida_em from pn_crm.chat_membro m where m.sala_id = s.id and m.user_id = eu),
                                          (select p.criado_em from pn_crm.perfil p where p.user_id = eu))),
           coalesce((select m.dono from pn_crm.chat_membro m where m.sala_id = s.id and m.user_id = eu), false),
           case when s.tipo = 'direto' then (select m.user_id from pn_crm.chat_membro m where m.sala_id = s.id and m.user_id <> eu limit 1) end
      from minhas s
      left join lateral (select case when x.excluida then 'Mensagem apagada' else x.texto end texto, p.nome autor, x.criado_em
                           from pn_crm.chat_mensagem x left join pn_crm.perfil p on p.user_id = x.autor_id
                          where x.sala_id = s.id order by x.id desc limit 1) ul on true
     order by (s.tipo = 'geral') desc, coalesce(ul.criado_em, s.criado_em) desc;
end $$;

CREATE FUNCTION pn.painel_cliente(p_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r jsonb; clin boolean;
begin
  perform pn_crm.exige_ativo();
  if not pn_crm.ve_empresa(p_id) then
    raise exception 'Esta empresa não está na sua carteira.' using errcode = '42501';
  end if;
  clin := pn_crm.pode_clinico();
  select jsonb_build_object(
    'id', e.id, 'razao_social', e.razao_social, 'nome_fantasia', e.nome_fantasia, 'cnpj', e.cnpj,
    'situacao', coalesce(e.situacao::text, 'a_confirmar'), 'cnae_principal', e.cnae_principal,
    'grau_risco', e.grau_risco, 'cidade', e.cidade, 'uf', e.uf, 'cep', e.cep,
    'logradouro', e.logradouro, 'numero', e.numero, 'complemento', e.complemento, 'bairro', e.bairro,
    'endereco', concat_ws(', ', nullif(e.logradouro, ''), nullif(e.numero, ''), nullif(e.complemento, ''), nullif(e.bairro, '')),
    'telefone', e.telefone, 'email', e.email,
    'contrato_inicio', e.contrato_inicio, 'contrato_fim', e.contrato_fim,
    'sesmo_id', e.sesmo_id, 'campos_editados', to_jsonb(e.campos_editados),
    'pode_editar', pn_crm.pode_editar_dados(),
    'contatos', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'cargo', c.cargo, 'email', c.email,
                              'telefone', c.telefone, 'tipo', c.tipo, 'recebe_alerta_exame', c.recebe_alerta_exame,
                              'origem', c.origem) order by c.nome)
                            from pn.empresa_contato c where c.empresa_id = e.id), '[]'::jsonb),
    'unidades', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'nome', u.nome, 'cnpj', u.cnpj,
                              'cidade', u.cidade, 'uf', u.uf, 'ativa', u.ativa, 'endereco', u.endereco,
                              'cnae', u.cnae, 'grau_risco', u.grau_risco, 'is_matriz', u.is_matriz,
                              'editado', cardinality(u.campos_editados) > 0, 'campos_editados', to_jsonb(u.campos_editados),
                              'setores', (select count(*) from pn.setor s where s.unidade_id = u.id),
                              'colaboradores', (select count(*) from pn.colaborador c where c.unidade_id = u.id and c.situacao = 'ativo'))
                            order by u.nome)
                            from pn.unidade u where u.empresa_id = e.id), '[]'::jsonb),
    'colaboradores_ativos', (select count(*) from pn.colaborador c where c.empresa_id = e.id and c.situacao = 'ativo'),
    'documentos', coalesce((select jsonb_agg(jsonb_build_object('tipo', d.tipo, 'versao', d.versao,
                              'vigencia_inicio', d.vigencia_inicio, 'vigencia_fim', d.vigencia_fim, 'situacao', d.situacao)
                            order by d.vigencia_fim desc nulls last)
                            from pn.documento d where d.empresa_id = e.id), '[]'::jsonb),
    'negocios', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'numero', n.numero, 'titulo', n.titulo,
                              'funil', f.nome, 'etapa', et.nome, 'tipo', et.tipo, 'valor', case when pn_crm.ve_valores() then n.valor end, 'criado_em', n.criado_em)
                            order by n.criado_em desc)
                            from pn_crm.negocio n join pn_crm.funil f on f.id = n.funil_id join pn_crm.etapa et on et.id = n.etapa_id
                           where n.empresa_id = e.id and pn_crm.ve_negocio(n.responsavel_id)), '[]'::jsonb),
    'interacoes', coalesce((select jsonb_agg(x order by x.em desc) from (
                              select i.id, i.canal, i.destino, i.assunto, left(i.texto, 300) texto, i.em,
                                     coalesce(p.nome, 'Sistema') usuario, ec.nome contato,
                                     (select s.status from pn_crm.wa_saida s where s.id = i.wa_saida_id) status_wa
                                from pn_crm.empresa_interacao i
                                left join pn_crm.perfil p on p.user_id = i.usuario_id
                                left join pn.empresa_contato ec on ec.id = i.contato_id
                               where i.empresa_id = e.id order by i.em desc limit 30) x), '[]'::jsonb),
    'historico', case when pn_crm.pode_editar_dados() then pn_crm.historico_edicao('empresa', e.id) else '[]'::jsonb end,
    'acesso_clinico', clin,
    'vencimentos', case when clin then (
        select jsonb_build_object(
          'vencido', count(*) filter (where v.status = 'vencido'),
          'vence_em_30_dias', count(*) filter (where v.status = 'vence_em_30_dias'),
          'vence_em_60_dias', count(*) filter (where v.status = 'vence_em_60_dias'),
          'em_dia', count(*) filter (where v.status = 'em_dia'))
          from pn_app.vw_aso_vencimento v where v.empresa_id = e.id) end,
    'ultimo_atendimento', case when clin then (select max(a.data_atendimento) from pn.atendimento a where a.empresa_id = e.id) end,
    'atendimentos_12m', case when clin then (select count(*) from pn.atendimento a
                                              where a.empresa_id = e.id and a.data_atendimento >= now() - interval '12 months') end
  ) into r
  from pn.empresa e where e.id = p_id;
  if r is null then raise exception 'Cliente não encontrado.'; end if;
  return r;
end $$;

CREATE FUNCTION pn.painel_clientes(p_busca text DEFAULT NULL::text, p_situacao text DEFAULT NULL::text, p_limite integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE(id uuid, nome text, razao_social text, cnpj text, situacao text, cidade text, uf text, telefone text, email text, unidades integer, colaboradores integer, negocios_abertos integer, total bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); dig text; so_minhas boolean;
begin
  perform pn_crm.exige_ativo();
  so_minhas := pn_crm.papel_atual() = 'comercial';
  dig := nullif(regexp_replace(coalesce(termo, ''), '\D', '', 'g'), '');
  return query
    with minhas as (
      select n.empresa_id from pn_crm.negocio n where so_minhas and n.responsavel_id = auth.uid() and n.empresa_id is not null
      union
      select c.empresa_id from pn_crm.contrato c where so_minhas and c.responsavel_id = auth.uid() and c.empresa_id is not null
      union
      select e.id from pn.empresa e where so_minhas and e.cadastrado_por = auth.uid()
    ), base as (
      select e.*
        from pn.empresa e
       where (not so_minhas or e.id in (select m.empresa_id from minhas m))
         and (termo is null
              or e.razao_social ilike '%' || termo || '%'
              or e.nome_fantasia ilike '%' || termo || '%'
              or (dig is not null and length(dig) >= 4 and regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') like '%' || dig || '%'))
         and (p_situacao is null
              or (p_situacao = 'a_confirmar' and e.situacao is null)
              or e.situacao::text = p_situacao)
    ), pagina as (
      select b.*, count(*) over () as total_linhas from base b
       order by b.razao_social
       limit least(greatest(p_limite, 1), 200) offset greatest(p_offset, 0)
    )
    select pg.id, coalesce(nullif(pg.nome_fantasia, ''), pg.razao_social)::text, pg.razao_social::text, pg.cnpj::text,
           coalesce(pg.situacao::text, 'a_confirmar'), pg.cidade::text, pg.uf::text, pg.telefone::text, pg.email::text,
           (select count(*)::int from pn.unidade u where u.empresa_id = pg.id),
           (select count(*)::int from pn.colaborador c where c.empresa_id = pg.id and c.situacao = 'ativo'),
           (select count(*)::int from pn_crm.negocio n join pn_crm.etapa et on et.id = n.etapa_id
             where n.empresa_id = pg.id and et.tipo = 'aberta'),
           pg.total_linhas
      from pagina pg
     order by pg.razao_social;
end $$;

CREATE FUNCTION pn.painel_cobranca_baixa(p_id uuid, p_pago_em date, p_valor numeric DEFAULT NULL::numeric, p_forma text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare atual pn_crm.cobranca;
begin
  perform pn_crm.exige_financeiro();
  select * into atual from pn_crm.cobranca where id = p_id for update;
  if atual.id is null then raise exception 'Cobrança não encontrada.'; end if;
  if atual.cancelada then raise exception 'Cobrança cancelada.'; end if;
  if p_pago_em is not null and p_pago_em > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception 'A data do pagamento não pode ser no futuro.';
  end if;
  update pn_crm.cobranca set pago_em = p_pago_em,
         valor_pago = case when p_pago_em is null then null else coalesce(p_valor, valor) end,
         forma = coalesce(p_forma, forma), atualizado_em = now()
   where id = p_id;
  perform pn_crm.cobranca_log(p_id, case when p_pago_em is null then 'Pagamento desfeito'
                                      else 'Pago em ' || to_char(p_pago_em, 'DD/MM/YYYY') || ' — R$ ' ||
                                           to_char(coalesce(p_valor, atual.valor), 'FM999G999G990D00') end);
  perform pn_crm.fin_sincronizar_inadimplencia(atual.empresa_id);
end $_$;

CREATE FUNCTION pn.painel_cobranca_cancelar(p_id uuid, p_motivo text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare atual pn_crm.cobranca;
begin
  perform pn_crm.exige_financeiro();
  if nullif(trim(p_motivo), '') is null then raise exception 'Informe o motivo.'; end if;
  select * into atual from pn_crm.cobranca where id = p_id for update;
  if atual.id is null then raise exception 'Cobrança não encontrada.'; end if;
  if atual.pago_em is not null then raise exception 'Cobrança paga: desfaça o pagamento antes de cancelar.'; end if;
  update pn_crm.cobranca set cancelada = true, cancelada_motivo = trim(p_motivo), atualizado_em = now() where id = p_id;
  perform pn_crm.cobranca_log(p_id, 'Cancelada: ' || trim(p_motivo));
  perform pn_crm.fin_sincronizar_inadimplencia(atual.empresa_id);
end $$;

CREATE FUNCTION pn.painel_cobranca_historico(p_id uuid) RETURNS TABLE(texto text, autor text, criado_em timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  perform pn_crm.exige_financeiro();
  return query select ev.texto, coalesce(p.nome, 'Sistema')::text, ev.criado_em
    from pn_crm.cobranca_evento ev left join pn_crm.perfil p on p.user_id = ev.autor_id
   where ev.cobranca_id = p_id order by ev.criado_em desc, ev.id desc;
end $$;

CREATE FUNCTION pn.painel_cobranca_salvar(p_id uuid, p_dados jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; v uuid := p_id; atual pn_crm.cobranca; venc date; emp uuid;
begin
  eu := pn_crm.exige_financeiro();
  if v is null then
    venc := nullif(p_dados->>'vencimento', '')::date;
    if venc is null then raise exception 'Informe o vencimento.'; end if;
    if coalesce(nullif(p_dados->>'valor', '')::numeric, 0) <= 0 then raise exception 'Informe o valor.'; end if;
    if nullif(p_dados->>'empresa_id', '') is null and nullif(trim(p_dados->>'cliente_nome'), '') is null then
      raise exception 'Informe o cliente.';
    end if;
    insert into pn_crm.cobranca (empresa_id, cliente_nome, contrato_id, descricao, competencia, vencimento, valor,
                              nota_fiscal, boleto, forma, observacao, criado_por)
    values (nullif(p_dados->>'empresa_id', '')::uuid, nullif(trim(p_dados->>'cliente_nome'), ''),
            nullif(p_dados->>'contrato_id', '')::uuid, coalesce(nullif(trim(p_dados->>'descricao'), ''), 'Serviços'),
            date_trunc('month', coalesce(nullif(p_dados->>'competencia', '')::date, venc))::date, venc,
            (p_dados->>'valor')::numeric, nullif(trim(p_dados->>'nota_fiscal'), ''), nullif(trim(p_dados->>'boleto'), ''),
            nullif(p_dados->>'forma', ''), nullif(trim(p_dados->>'observacao'), ''), eu)
    returning id, empresa_id into v, emp;
    perform pn_crm.cobranca_log(v, 'Cobrança lançada');
    perform pn_crm.fin_sincronizar_inadimplencia(emp);
    return v;
  end if;

  select * into atual from pn_crm.cobranca where id = v for update;
  if atual.id is null then raise exception 'Cobrança não encontrada.'; end if;
  if atual.cancelada then raise exception 'Cobrança cancelada não é editada.'; end if;
  update pn_crm.cobranca set
    descricao   = coalesce(nullif(trim(p_dados->>'descricao'), ''), descricao),
    vencimento  = coalesce(nullif(p_dados->>'vencimento', '')::date, vencimento),
    valor       = coalesce(nullif(p_dados->>'valor', '')::numeric, valor),
    nota_fiscal = case when p_dados ? 'nota_fiscal' then nullif(trim(p_dados->>'nota_fiscal'), '') else nota_fiscal end,
    boleto      = case when p_dados ? 'boleto' then nullif(trim(p_dados->>'boleto'), '') else boleto end,
    forma       = case when p_dados ? 'forma' then nullif(p_dados->>'forma', '') else forma end,
    observacao  = case when p_dados ? 'observacao' then nullif(trim(p_dados->>'observacao'), '') else observacao end,
    atualizado_em = now()
  where id = v;
  perform pn_crm.cobranca_log(v, 'Dados atualizados');
  perform pn_crm.fin_sincronizar_inadimplencia(atual.empresa_id);
  return v;
end $$;

CREATE FUNCTION pn.painel_cobrancas(p_competencia date DEFAULT NULL::date, p_situacao text DEFAULT NULL::text, p_busca text DEFAULT NULL::text) RETURNS TABLE(id uuid, numero bigint, empresa_id uuid, cliente text, cnpj text, contrato_id uuid, contrato_numero bigint, descricao text, competencia date, vencimento date, valor numeric, valor_pago numeric, pago_em date, forma text, nota_fiscal text, boleto text, observacao text, situacao text, dias_atraso integer, origem text, encargos numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        dig text := nullif(regexp_replace(coalesce(p_busca, ''), '\D', '', 'g'), '');
begin
  perform pn_crm.exige_financeiro();
  return query
    select c.id, c.numero, c.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social, c.cliente_nome)::text, e.cnpj::text,
           c.contrato_id, ct.numero, c.descricao, c.competencia, c.vencimento, c.valor, c.valor_pago, c.pago_em,
           c.forma, c.nota_fiscal, c.boleto, c.observacao, pn_crm.cobranca_situacao(c.cancelada, c.pago_em, c.vencimento),
           case when c.pago_em is null and not c.cancelada and c.vencimento < hoje then (hoje - c.vencimento)::int else 0 end,
           c.origem, pn_crm.cobranca_encargos(c.valor, c.vencimento, c.pago_em, c.cancelada)
      from pn_crm.cobranca c
      left join pn.empresa e on e.id = c.empresa_id
      left join pn_crm.contrato ct on ct.id = c.contrato_id
     where (p_competencia is null or c.competencia = date_trunc('month', p_competencia)::date
            or (p_situacao is null and c.pago_em is null and not c.cancelada and c.vencimento < hoje and c.competencia < date_trunc('month', p_competencia)::date))
       and (p_situacao is null or pn_crm.cobranca_situacao(c.cancelada, c.pago_em, c.vencimento) = p_situacao)
       and (termo is null or c.descricao ilike '%' || termo || '%' or e.razao_social ilike '%' || termo || '%'
            or e.nome_fantasia ilike '%' || termo || '%' or c.cliente_nome ilike '%' || termo || '%'
            or c.nota_fiscal = termo or (dig is not null and length(dig) >= 4 and regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') like dig || '%'))
     order by case pn_crm.cobranca_situacao(c.cancelada, c.pago_em, c.vencimento) when 'vencida' then 0 when 'aberta' then 1 when 'paga' then 2 else 3 end,
              c.vencimento, c.numero;
end $$;

CREATE FUNCTION pn.painel_colaborador(p_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r jsonb;
begin
  perform pn_crm.exige('gestor','operacoes');
  select to_jsonb(c) - 'sesmo_usuario_cadastro' - 'sesmo_usuario_alteracao'
         || jsonb_build_object(
              'empresa', coalesce(nullif(e.nome_fantasia, ''), e.razao_social),
              'unidade', u.nome,
              'origem', c.origem::text,
              'atendimentos', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'data', coalesce(a.data_atendimento, a.data_agendada::date),
                                         'tipo', a.tipo, 'situacao', a.situacao, 'aso_resultado', a.aso_resultado) order by coalesce(a.data_atendimento, a.data_agendada::date) desc)
                                         from pn.atendimento a where a.colaborador_id = c.id), '[]'::jsonb),
              'historico', pn_crm.historico_edicao('colaborador', c.id),
              'pode_editar', pn_crm.pode_editar_dados())
    into r
    from pn.colaborador c
    join pn.empresa e on e.id = c.empresa_id
    left join pn.unidade u on u.id = c.unidade_id
   where c.id = p_id;
  if r is null then raise exception 'Colaborador não encontrado.'; end if;
  return r;
end $$;

CREATE FUNCTION pn.painel_colaborador_salvar(p_id uuid, p_empresa uuid, p_dados jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare d jsonb; emp uuid;
begin
  perform pn_crm.exige('gestor');
  d := pn_crm.limpar_dados(p_dados, array['nome','nome_social','cpf','rg','rg_orgao_emissor','data_nascimento','sexo','nome_mae',
                                       'pis','matricula_esocial','ctps','data_admissao','data_demissao','situacao',
                                       'telefone','email','unidade_id']);
  if d ? 'nome' and d ->> 'nome' is null then raise exception 'Informe o nome do colaborador.'; end if;
  if d ? 'situacao' and d ->> 'situacao' is null then d := d - 'situacao'; end if;
  if d ->> 'cpf' is not null and length(d ->> 'cpf') <> 11 then raise exception 'CPF deve ter 11 dígitos.'; end if;
  if d ->> 'sexo' is not null and d ->> 'sexo' not in ('M','F') then raise exception 'Sexo: use M ou F.'; end if;
  if (d ->> 'data_demissao') is not null and (d ->> 'data_admissao') is not null
     and (d ->> 'data_demissao')::date < (d ->> 'data_admissao')::date then
    raise exception 'A demissão não pode ser antes da admissão.';
  end if;

  emp := coalesce(p_empresa, (select empresa_id from pn.colaborador where id = p_id));
  if d ->> 'unidade_id' is not null and not exists (select 1 from pn.unidade u where u.id = (d ->> 'unidade_id')::uuid and u.empresa_id = emp) then
    raise exception 'A unidade escolhida não é desta empresa.';
  end if;
  if d ->> 'cpf' is not null and exists (select 1 from pn.colaborador c where c.empresa_id = emp and c.cpf = d ->> 'cpf'
                                           and c.id is distinct from p_id and c.situacao = 'ativo') then
    raise exception 'Já existe colaborador ativo com este CPF nesta empresa.';
  end if;

  if p_id is null then
    if d ->> 'nome' is null then raise exception 'Informe o nome do colaborador.'; end if;
    if not exists (select 1 from pn.empresa where id = p_empresa) then raise exception 'Empresa não encontrada.'; end if;
    return pn_crm.criar('colaborador', d, jsonb_build_object('empresa_id', p_empresa, 'origem', 'manual'));
  end if;
  perform pn_crm.editar('colaborador', p_id, d);
  return p_id;
end $$;

CREATE FUNCTION pn.painel_colaboradores(p_empresa uuid, p_busca text DEFAULT NULL::text, p_situacao text DEFAULT NULL::text, p_limite integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE(id uuid, nome text, cpf text, unidade text, setor text, funcao text, data_admissao date, data_demissao date, situacao text, editado boolean, ultimo_atendimento date, total bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); dig text;
begin
  perform pn_crm.exige('gestor','operacoes');
  dig := nullif(regexp_replace(coalesce(termo, ''), '\D', '', 'g'), '');
  return query
    with base as (
      select c.* from pn.colaborador c
       where c.empresa_id = p_empresa
         and (p_situacao is null or c.situacao::text = p_situacao)
         and (termo is null or pn_app.norm(c.nome) like '%' || pn_app.norm(termo) || '%'
              or (dig is not null and length(dig) >= 3 and c.cpf like '%' || dig || '%'))
    ), pagina as (
      select b.*, count(*) over () total_linhas from base b
       order by (b.situacao = 'ativo') desc, b.nome
       limit least(greatest(p_limite, 1), 200) offset greatest(p_offset, 0)
    )
    select pg.id, pg.nome::text, pg.cpf::text, u.nome::text, coalesce(s.nome, pg.setor_nome)::text, coalesce(f.nome, pg.funcao_nome)::text,
           pg.data_admissao, pg.data_demissao, pg.situacao::text,
           cardinality(pg.campos_editados) > 0,
           (select max(a.data_atendimento) from pn.atendimento a where a.colaborador_id = pg.id),
           pg.total_linhas
      from pagina pg
      left join pn.unidade u on u.id = pg.unidade_id
      left join pn.setor s on s.id = pg.setor_id
      left join pn.funcao f on f.id = pg.funcao_id
     order by (pg.situacao = 'ativo') desc, pg.nome;
end $$;

CREATE FUNCTION pn.painel_contrato(p_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r jsonb;
begin
  perform pn_crm.exige_contratos();
  select to_jsonb(c) || jsonb_build_object(
      'cliente', coalesce(nullif(e.nome_fantasia, ''), e.razao_social, c.cliente_nome),
      'cnpj', e.cnpj,
      'situacao', pn_crm.contrato_situacao(c.status, c.fim, c.aviso_dias),
      'responsavel_nome', p.nome,
      'negocio_numero', n.numero,
      'itens', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'produto_id', i.produto_id, 'descricao', i.descricao,
                                                             'quantidade', i.quantidade, 'preco', i.preco, 'total', i.total)
                                          order by i.criado_em)
                           from pn_crm.contrato_item i where i.contrato_id = c.id), '[]'::jsonb),
      'eventos', coalesce((select jsonb_agg(jsonb_build_object('texto', ev.texto, 'autor', coalesce(a.nome, 'Sistema'),
                                                               'criado_em', ev.criado_em) order by ev.criado_em desc, ev.id desc)
                             from pn_crm.contrato_evento ev left join pn_crm.perfil a on a.user_id = ev.autor_id
                            where ev.contrato_id = c.id), '[]'::jsonb))
    into r
    from pn_crm.contrato c
    left join pn.empresa e on e.id = c.empresa_id
    left join pn_crm.perfil p on p.user_id = c.responsavel_id
    left join pn_crm.negocio n on n.id = c.negocio_id
   where c.id = p_id;
  if r is null then raise exception 'Contrato não encontrado.'; end if;
  return r;
end $$;

CREATE FUNCTION pn.painel_contrato_arquivo(p_id uuid, p_path text, p_nome text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige_contratos();
  if p_path is not null and p_path not like 'contratos/' || p_id::text || '/%' then
    raise exception 'Caminho de arquivo inválido.';
  end if;
  update pn_crm.contrato set arquivo_path = p_path, arquivo_nome = p_nome, atualizado_em = now() where id = p_id;
  perform pn_crm.contrato_log(p_id, case when p_path is null then 'Arquivo removido' else 'Arquivo anexado: ' || coalesce(p_nome, '') end);
end $$;

CREATE FUNCTION pn.painel_contrato_item_adicionar(p_contrato uuid, p_produto uuid, p_descricao text, p_quantidade numeric DEFAULT 1, p_preco numeric DEFAULT NULL::numeric) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v uuid; prod pn_crm.produto;
begin
  perform pn_crm.exige_contratos();
  if p_produto is not null then select * into prod from pn_crm.produto where id = p_produto; end if;
  if coalesce(nullif(trim(p_descricao), ''), prod.nome) is null then raise exception 'Informe o serviço.'; end if;
  insert into pn_crm.contrato_item (contrato_id, produto_id, descricao, quantidade, preco)
  values (p_contrato, p_produto, coalesce(nullif(trim(p_descricao), ''), prod.nome), coalesce(p_quantidade, 1),
          coalesce(p_preco, prod.preco, 0))
  returning id into v;
  perform pn_crm.contrato_recalcular(p_contrato);
  return v;
end $$;

CREATE FUNCTION pn.painel_contrato_item_remover(p_item uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare c uuid;
begin
  perform pn_crm.exige_contratos();
  delete from pn_crm.contrato_item where id = p_item returning contrato_id into c;
  if c is not null then perform pn_crm.contrato_recalcular(c); end if;
end $$;

CREATE FUNCTION pn.painel_contrato_minuta(p_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r jsonb;
begin
  perform pn_crm.exige_contratos();
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
                           from pn_crm.contrato_item i left join pn_crm.produto p on p.id = i.produto_id
                          where i.contrato_id = c.id), '[]'::jsonb))
    into r
    from pn_crm.contrato c left join pn.empresa e on e.id = c.empresa_id
   where c.id = p_id;
  if r is null then raise exception 'Contrato não encontrado.'; end if;
  return r;
end $$;

CREATE FUNCTION pn.painel_contrato_minuta_salvar(p_id uuid, p_dados jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare it jsonb;
begin
  perform pn_crm.exige_contratos();
  if (select status from pn_crm.contrato where id = p_id) = 'cancelado' then raise exception 'Contrato cancelado não é editado.'; end if;
  update pn_crm.contrato set
    representante_legal = case when p_dados ? 'representante_legal' then nullif(trim(p_dados->>'representante_legal'), '') else representante_legal end,
    email_notificacao   = case when p_dados ? 'email_notificacao' then nullif(trim(p_dados->>'email_notificacao'), '') else email_notificacao end,
    telefone_contato    = case when p_dados ? 'telefone' then nullif(trim(p_dados->>'telefone'), '') else telefone_contato end,
    prazo_meses         = case when p_dados ? 'prazo_meses' then nullif(p_dados->>'prazo_meses', '')::int else prazo_meses end,
    atualizado_em = now()
  where id = p_id;
  if not found then raise exception 'Contrato não encontrado.'; end if;
  for it in select * from jsonb_array_elements(coalesce(p_dados->'itens', '[]'::jsonb)) loop
    update pn_crm.contrato_item set cobranca = nullif(trim(it->>'cobranca'), '')
     where id = (it->>'id')::uuid and contrato_id = p_id;
  end loop;
  perform pn_crm.contrato_log(p_id, 'Minuta gerada');
end $$;

CREATE FUNCTION pn.painel_contrato_salvar(p_id uuid, p_dados jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; v uuid := p_id; atual pn_crm.contrato;
begin
  eu := pn_crm.exige_contratos();
  if v is null then
    if nullif(trim(p_dados->>'titulo'), '') is null then raise exception 'Informe o título do contrato.'; end if;
    if nullif(p_dados->>'empresa_id', '') is null and nullif(trim(p_dados->>'cliente_nome'), '') is null then
      raise exception 'Informe o cliente.';
    end if;
    insert into pn_crm.contrato (empresa_id, cliente_nome, titulo, inicio, fim, renovacao_automatica, aviso_dias,
                              valor_mensal, dia_vencimento, forma_pagamento, indice_reajuste, responsavel_id,
                              observacao, criado_por)
    values (nullif(p_dados->>'empresa_id', '')::uuid, nullif(trim(p_dados->>'cliente_nome'), ''), trim(p_dados->>'titulo'),
            nullif(p_dados->>'inicio', '')::date, nullif(p_dados->>'fim', '')::date,
            coalesce((p_dados->>'renovacao_automatica')::boolean, false), coalesce(nullif(p_dados->>'aviso_dias', '')::int, 60),
            nullif(p_dados->>'valor_mensal', '')::numeric, nullif(p_dados->>'dia_vencimento', '')::int,
            nullif(trim(p_dados->>'forma_pagamento'), ''), nullif(trim(p_dados->>'indice_reajuste'), ''),
            coalesce(nullif(p_dados->>'responsavel_id', '')::uuid, eu), nullif(trim(p_dados->>'observacao'), ''), eu)
    returning id into v;
    perform pn_crm.contrato_log(v, 'Contrato criado');
    return v;
  end if;

  select * into atual from pn_crm.contrato where id = v for update;
  if atual.id is null then raise exception 'Contrato não encontrado.'; end if;
  if atual.status = 'cancelado' then raise exception 'Contrato cancelado não é editado.'; end if;

  update pn_crm.contrato set
    titulo       = coalesce(nullif(trim(p_dados->>'titulo'), ''), titulo),
    empresa_id   = case when p_dados ? 'empresa_id' then nullif(p_dados->>'empresa_id', '')::uuid else empresa_id end,
    cliente_nome = case when p_dados ? 'cliente_nome' then nullif(trim(p_dados->>'cliente_nome'), '') else cliente_nome end,
    inicio       = case when p_dados ? 'inicio' then nullif(p_dados->>'inicio', '')::date else inicio end,
    fim          = case when p_dados ? 'fim' then nullif(p_dados->>'fim', '')::date else fim end,
    renovacao_automatica = coalesce((p_dados->>'renovacao_automatica')::boolean, renovacao_automatica),
    aviso_dias   = coalesce(nullif(p_dados->>'aviso_dias', '')::int, aviso_dias),
    valor_mensal = case when p_dados ? 'valor_mensal' then nullif(p_dados->>'valor_mensal', '')::numeric else valor_mensal end,
    dia_vencimento = case when p_dados ? 'dia_vencimento' then nullif(p_dados->>'dia_vencimento', '')::int else dia_vencimento end,
    forma_pagamento = case when p_dados ? 'forma_pagamento' then nullif(trim(p_dados->>'forma_pagamento'), '') else forma_pagamento end,
    indice_reajuste = case when p_dados ? 'indice_reajuste' then nullif(trim(p_dados->>'indice_reajuste'), '') else indice_reajuste end,
    responsavel_id = case when p_dados ? 'responsavel_id' then nullif(p_dados->>'responsavel_id', '')::uuid else responsavel_id end,
    observacao   = case when p_dados ? 'observacao' then nullif(trim(p_dados->>'observacao'), '') else observacao end,

    ultimo_alerta_em = case when p_dados ? 'fim' and nullif(p_dados->>'fim', '')::date is distinct from fim then null else ultimo_alerta_em end,
    renovacao_negocio_id = case when p_dados ? 'fim' and nullif(p_dados->>'fim', '')::date > coalesce(fim, '-infinity'::date)
                                then null else renovacao_negocio_id end,
    atualizado_em = now()
  where id = v;

  if p_dados ? 'fim' and nullif(p_dados->>'fim', '')::date is distinct from atual.fim then
    perform pn_crm.contrato_log(v, 'Vigência até ' || coalesce(to_char(nullif(p_dados->>'fim', '')::date, 'DD/MM/YYYY'), 'indeterminada'));
  else
    perform pn_crm.contrato_log(v, 'Dados atualizados');
  end if;
  return v;
end $$;

CREATE FUNCTION pn.painel_contrato_status(p_id uuid, p_status text, p_motivo text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare atual pn_crm.contrato; motivo text := nullif(trim(p_motivo), '');
begin
  perform pn_crm.exige_contratos();
  if p_status not in ('rascunho','revisao','enviado','parcial','assinado','cancelado') then
    raise exception 'Status inválido.';
  end if;
  select * into atual from pn_crm.contrato where id = p_id for update;
  if atual.id is null then raise exception 'Contrato não encontrado.'; end if;
  if atual.status = p_status then return; end if;
  if p_status = 'cancelado' and motivo is null then raise exception 'Informe o motivo do cancelamento.'; end if;
  if atual.status = 'cancelado' and pn_crm.papel_atual() not in ('admin','gestor') then
    raise exception 'Só gestor reabre contrato cancelado.' using errcode = '42501';
  end if;
  if p_status = 'assinado' and (atual.inicio is null or atual.fim is null) and not atual.renovacao_automatica then
    raise exception 'Informe início e fim da vigência (ou marque renovação automática) antes de marcar como assinado.';
  end if;
  update pn_crm.contrato set status = p_status,
         assinado_em = case when p_status = 'assinado' then coalesce(assinado_em, now()) else assinado_em end,
         cancelado_motivo = case when p_status = 'cancelado' then motivo else null end,
         atualizado_em = now()
   where id = p_id;
  perform pn_crm.contrato_log(p_id, pn_crm.contrato_status_rotulo(atual.status) || ' → ' || pn_crm.contrato_status_rotulo(p_status)
                                 || coalesce(': ' || motivo, ''));
end $$;

CREATE FUNCTION pn.painel_contratos(p_busca text DEFAULT NULL::text, p_situacao text DEFAULT NULL::text) RETURNS TABLE(id uuid, numero bigint, titulo text, empresa_id uuid, cliente text, status text, situacao text, inicio date, fim date, dias_para_vencer integer, valor_mensal numeric, valor_total numeric, responsavel_id uuid, responsavel_nome text, tem_arquivo boolean, negocio_id uuid, renovacao_negocio_id uuid, atualizado_em timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  perform pn_crm.exige_contratos();
  return query
    select c.id, c.numero, c.titulo, c.empresa_id,
           coalesce(nullif(e.nome_fantasia, ''), e.razao_social, c.cliente_nome)::text,
           c.status, pn_crm.contrato_situacao(c.status, c.fim, c.aviso_dias),
           c.inicio, c.fim, (c.fim - hoje)::int, c.valor_mensal, c.valor_total,
           c.responsavel_id, p.nome::text, c.arquivo_path is not null, c.negocio_id, c.renovacao_negocio_id, c.atualizado_em
      from pn_crm.contrato c
      left join pn.empresa e on e.id = c.empresa_id
      left join pn_crm.perfil p on p.user_id = c.responsavel_id
     where (termo is null or c.titulo ilike '%' || termo || '%' or e.razao_social ilike '%' || termo || '%'
            or e.nome_fantasia ilike '%' || termo || '%' or c.cliente_nome ilike '%' || termo || '%'
            or c.numero::text = termo)
       and (p_situacao is null or pn_crm.contrato_situacao(c.status, c.fim, c.aviso_dias) = p_situacao)
     order by case pn_crm.contrato_situacao(c.status, c.fim, c.aviso_dias)
                when 'vencido' then 0 when 'a_renovar' then 1 when 'em_assinatura' then 2 when 'vigente' then 3 else 4 end,
              c.fim nulls last, c.numero desc;
end $$;

CREATE FUNCTION pn.painel_contratos_resumo() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige_contratos();
  return (
    with s as (select pn_crm.contrato_situacao(status, fim, aviso_dias) sit, valor_mensal from pn_crm.contrato)
    select jsonb_build_object(
      'vigentes', count(*) filter (where sit = 'vigente'),
      'a_renovar', count(*) filter (where sit = 'a_renovar'),
      'vencidos', count(*) filter (where sit = 'vencido'),
      'em_assinatura', count(*) filter (where sit = 'em_assinatura'),
      'receita_mensal', coalesce(sum(valor_mensal) filter (where sit in ('vigente','a_renovar')), 0))
    from s);
end $$;

CREATE FUNCTION pn.painel_crm_atividade(p_id uuid, p_tipo text, p_texto text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_funil uuid;
begin
  select funil_id into v_funil from pn_crm.negocio where id = p_id;
  if v_funil is null then raise exception 'Negócio não encontrado.'; end if;
  perform pn_crm.exige_operar(v_funil);
  if p_tipo not in ('nota','ligacao','email','whatsapp','reuniao') then
    raise exception 'Tipo de atividade inválido.';
  end if;
  if nullif(trim(p_texto), '') is null then
    raise exception 'Escreva o que aconteceu.';
  end if;
  perform pn_crm.registrar(p_id, p_tipo, trim(p_texto));
  update pn_crm.negocio set atualizado_em = now() where id = p_id;
end $$;

CREATE FUNCTION pn.painel_crm_etapa_salvar(p_id uuid, p_funil uuid, p_nome text, p_tipo text DEFAULT 'aberta'::text, p_cor text DEFAULT 'muted'::text, p_alerta_dias integer DEFAULT NULL::integer, p_ativo boolean DEFAULT true) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid; v_abertos int;
begin
  perform pn_crm.exige('gestor');
  if nullif(trim(p_nome), '') is null then raise exception 'Informe o nome da etapa.'; end if;
  if p_tipo not in ('aberta','ganho','perdido') then raise exception 'Tipo de etapa inválido.'; end if;
  if p_alerta_dias is not null and p_alerta_dias <= 0 then raise exception 'O aviso precisa ser de 1 dia ou mais.'; end if;

  if p_id is null then
    insert into pn_crm.etapa (funil_id, nome, ordem, tipo, cor, alerta_dias, ativo)
    values (p_funil, trim(p_nome),
            coalesce((select max(ordem) + 1 from pn_crm.etapa where funil_id = p_funil), 1),
            p_tipo::pn_crm.tipo_etapa, p_cor, p_alerta_dias, coalesce(p_ativo, true))
    returning id into v_id;
  else
    if p_ativo is false then
      select count(*) into v_abertos from pn_crm.negocio where etapa_id = p_id;
      if v_abertos > 0 then
        raise exception 'Há % negócio(s) nesta etapa. Mova-os antes de desativar.', v_abertos;
      end if;
    end if;
    update pn_crm.etapa set nome = trim(p_nome), tipo = p_tipo::pn_crm.tipo_etapa, cor = p_cor,
           alerta_dias = p_alerta_dias, ativo = coalesce(p_ativo, true)
     where id = p_id and funil_id = p_funil returning id into v_id;
    if v_id is null then raise exception 'Etapa não encontrada.'; end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'Já existe uma etapa com esse nome neste funil.';
end $$;

CREATE FUNCTION pn.painel_crm_etapas_reordenar(p_funil uuid, p_ids uuid[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor');
  update pn_crm.etapa e set ordem = x.pos
    from unnest(p_ids) with ordinality as x(id, pos)
   where e.id = x.id and e.funil_id = p_funil;
end $$;

CREATE FUNCTION pn.painel_crm_funis() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige_ativo();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', f.id, 'slug', f.slug, 'nome', f.nome, 'descricao', f.descricao,
             'usa_rodizio', f.usa_rodizio, 'papeis', to_jsonb(f.papeis),
             'pode_operar', pn_crm.pode_operar(f.id),
             'etapas', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'id', e.id, 'nome', e.nome, 'ordem', e.ordem, 'tipo', e.tipo,
                        'cor', e.cor, 'alerta_dias', e.alerta_dias, 'ativo', e.ativo)
                      order by e.ordem)
                 from pn_crm.etapa e where e.funil_id = f.id), '[]'::jsonb))
           order by f.ordem)
      from pn_crm.funil f where f.ativo), '[]'::jsonb);
end $$;

CREATE FUNCTION pn.painel_crm_item_adicionar(p_negocio uuid, p_produto uuid DEFAULT NULL::uuid, p_descricao text DEFAULT NULL::text, p_quantidade numeric DEFAULT 1, p_preco numeric DEFAULT NULL::numeric) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_funil uuid; pr pn_crm.produto; v_id uuid; v_desc text; v_preco numeric;
begin
  select funil_id into v_funil from pn_crm.negocio where id = p_negocio;
  if v_funil is null then raise exception 'Negócio não encontrado.'; end if;
  perform pn_crm.exige_operar(v_funil);
  if p_produto is not null then
    select * into pr from pn_crm.produto where id = p_produto;
    if pr.id is null then raise exception 'Produto não encontrado.'; end if;
  end if;
  v_desc := coalesce(nullif(trim(p_descricao), ''), pr.nome);
  if v_desc is null then raise exception 'Escolha um produto ou descreva o item.'; end if;
  v_preco := coalesce(p_preco, pr.preco, 0);
  if coalesce(p_quantidade, 0) <= 0 then raise exception 'Quantidade precisa ser maior que zero.'; end if;

  insert into pn_crm.negocio_item (negocio_id, produto_id, descricao, quantidade, preco_unitario, preco_catalogo)
  values (p_negocio, p_produto, v_desc, p_quantidade, greatest(v_preco, 0), pr.preco)
  returning id into v_id;
  perform pn_crm.recalcular_valor(p_negocio);
  perform pn_crm.registrar(p_negocio, 'item', 'Item adicionado: ' || v_desc);
  return v_id;
end $$;

CREATE FUNCTION pn.painel_crm_item_adicionar_v2(p_negocio uuid, p_produto uuid, p_descricao text, p_quantidade numeric, p_preco numeric, p_desconto numeric DEFAULT 0) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid;
begin
  v_id := pn.painel_crm_item_adicionar(p_negocio, p_produto, p_descricao, p_quantidade, p_preco);
  if coalesce(p_desconto, 0) <> 0 then
    if p_desconto < 0 or p_desconto > 100 then raise exception 'Desconto deve ficar entre 0 e 100%%.'; end if;
    update pn_crm.negocio_item set desconto_pct = p_desconto where id = v_id;
    perform pn_crm.recalcular_valor(p_negocio);
  end if;
  return v_id;
end $$;

CREATE FUNCTION pn.painel_crm_item_remover(p_item uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i pn_crm.negocio_item; v_funil uuid;
begin
  select * into i from pn_crm.negocio_item where id = p_item;
  if i.id is null then raise exception 'Item não encontrado.'; end if;
  select funil_id into v_funil from pn_crm.negocio where id = i.negocio_id;
  perform pn_crm.exige_operar(v_funil);
  delete from pn_crm.negocio_item where id = p_item;

  perform pn_crm.recalcular_valor(i.negocio_id);
  perform pn_crm.registrar(i.negocio_id, 'item', 'Item removido: ' || i.descricao);
end $$;

CREATE FUNCTION pn.painel_crm_item_salvar(p_item uuid, p_dados jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare i pn_crm.negocio_item; v_funil uuid; d jsonb := coalesce(p_dados, '{}'::jsonb);
  v_qtd numeric; v_preco numeric; v_desc numeric;
begin
  select * into i from pn_crm.negocio_item where id = p_item;
  if i.id is null then raise exception 'Item não encontrado.'; end if;
  select funil_id into v_funil from pn_crm.negocio where id = i.negocio_id;
  perform pn_crm.exige_operar(v_funil);
  if not pn_crm.ve_valores_funil(v_funil) then raise exception 'Sem permissão para alterar valores.'; end if;
  v_qtd := coalesce(nullif(d ->> 'quantidade', '')::numeric, i.quantidade);
  v_preco := coalesce(nullif(d ->> 'preco', '')::numeric, i.preco_unitario);
  v_desc := coalesce(nullif(d ->> 'desconto', '')::numeric, i.desconto_pct);
  if v_qtd <= 0 then raise exception 'Quantidade precisa ser maior que zero.'; end if;
  if v_preco < 0 then raise exception 'Preço inválido.'; end if;
  if v_desc < 0 or v_desc > 100 then raise exception 'Desconto deve ficar entre 0 e 100%%.'; end if;
  update pn_crm.negocio_item set quantidade = v_qtd, preco_unitario = v_preco, desconto_pct = v_desc where id = p_item;
  perform pn_crm.recalcular_valor(i.negocio_id);
  perform pn_crm.registrar(i.negocio_id, 'item', format('Item alterado: %s (qtd %s, R$ %s, desconto %s%%)', i.descricao,
    v_qtd, replace(to_char(v_preco, 'FM9999990.00'), '.', ','), v_desc));
end $_$;

CREATE FUNCTION pn.painel_crm_negocio(p_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r jsonb; vv boolean;
begin
  perform pn_crm.exige_ativo();
  vv := pn_crm.ve_valores_funil((select n0.funil_id from pn_crm.negocio n0 where n0.id = p_id));
  select jsonb_build_object(
           'id', n.id, 'numero', n.numero, 'funil_id', n.funil_id, 'etapa_id', n.etapa_id,
           'titulo', n.titulo, 'empresa_id', n.empresa_id,
           'empresa', case when em.id is null then null else jsonb_build_object(
               'id', em.id, 'razao_social', em.razao_social, 'nome_fantasia', em.nome_fantasia,
               'cnpj', em.cnpj, 'cidade', em.cidade, 'uf', em.uf, 'telefone', em.telefone, 'email', em.email) end,
           'cliente_nome', n.cliente_nome, 'cliente_cnpj', n.cliente_cnpj,
           'contato_nome', n.contato_nome, 'contato_telefone', n.contato_telefone, 'contato_email', n.contato_email,
           'responsavel_id', n.responsavel_id, 'responsavel_nome', p.nome,
           'vendedor_nome', (select pv.nome from pn_crm.perfil pv where pv.user_id = pn_crm.vendedor_id(n.id)),
           'desconto_pct', case when vv then n.desconto_pct end,
           'valor', case when vv then n.valor end, 've_valores', vv,
           'origem', n.origem, 'previsao_fechamento', n.previsao_fechamento,
           'motivo_perda', n.motivo_perda, 'observacao', n.observacao,
           'qtd_funcionarios', n.qtd_funcionarios, 'forma_pagamento', n.forma_pagamento, 'parcelas', n.parcelas,
           'entrou_etapa_em', n.entrou_etapa_em, 'fechado_em', n.fechado_em, 'criado_em', n.criado_em,
           'pode_operar', pn_crm.pode_operar(n.funil_id),
           'negocio_origem', (select jsonb_build_object('id', o.id, 'numero', o.numero, 'funil', fo.nome,
                                       'observacao', o.observacao, 'qtd_funcionarios', o.qtd_funcionarios,
                                       'forma_pagamento', o.forma_pagamento, 'parcelas', o.parcelas,
                                       'responsavel_nome', po.nome, 'atualizado_em', o.atualizado_em)
                                from pn_crm.negocio o join pn_crm.funil fo on fo.id = o.funil_id
                                left join pn_crm.perfil po on po.user_id = o.responsavel_id
                               where o.id = n.negocio_origem_id),
           'derivados', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'numero', d.numero,
                                          'funil', fd.nome, 'etapa', ed.nome))
                                    from pn_crm.negocio d join pn_crm.funil fd on fd.id = d.funil_id
                                    join pn_crm.etapa ed on ed.id = d.etapa_id
                                   where d.negocio_origem_id = n.id), '[]'::jsonb),
           'itens', coalesce((select jsonb_agg(jsonb_build_object(
                          'id', i.id, 'produto_id', i.produto_id, 'descricao', i.descricao,
                          'quantidade', i.quantidade,
                          'preco_unitario', case when vv then i.preco_unitario end,
                          'total', case when vv then i.total_liquido end, 'total_bruto', case when vv then i.total end,
                          'preco_catalogo', case when vv then i.preco_catalogo end,
                          'desconto_pct', case when vv then i.desconto_pct end)
                        order by i.criado_em)
                        from pn_crm.negocio_item i where i.negocio_id = n.id), '[]'::jsonb),
           'eventos', coalesce((select jsonb_agg(x order by x.criado_em desc) from (
                          select ev.id, ev.tipo, ev.texto, ev.criado_em, a.nome as autor,
                                 de.nome as de_etapa, pa.nome as para_etapa
                            from pn_crm.evento ev
                            left join pn_crm.perfil a on a.user_id = ev.autor_id
                            left join pn_crm.etapa de on de.id = ev.de_etapa_id
                            left join pn_crm.etapa pa on pa.id = ev.para_etapa_id
                           where ev.negocio_id = n.id
                           order by ev.criado_em desc limit 200) x), '[]'::jsonb))
    into r
    from pn_crm.negocio n
    left join pn.empresa em on em.id = n.empresa_id
    left join pn_crm.perfil p on p.user_id = n.responsavel_id
   where n.id = p_id and pn_crm.ve_negocio(n.responsavel_id);
  if r is null then
    raise exception 'Negócio não encontrado.';
  end if;
  return r;
end $$;

CREATE FUNCTION pn.painel_crm_negocio_atualizar(p_id uuid, p_dados jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare eu uuid; n pn_crm.negocio; v_resp uuid; tem_itens boolean; mudou text[] := '{}';
        v_func integer; v_forma text; v_parc smallint;
begin
  select * into n from pn_crm.negocio where id = p_id for update;
  if n.id is null then raise exception 'Negócio não encontrado.'; end if;
  eu := pn_crm.exige_operar(n.funil_id);

  if p_dados ? 'titulo' and nullif(trim(p_dados->>'titulo'), '') is null then
    raise exception 'O título não pode ficar vazio.';
  end if;
  select exists (select 1 from pn_crm.negocio_item i where i.negocio_id = n.id) into tem_itens;
  if p_dados ? 'valor' and tem_itens then
    raise exception 'O valor é a soma dos itens. Edite os itens do negócio.';
  end if;

  v_resp := case when p_dados ? 'responsavel_id' then nullif(p_dados->>'responsavel_id', '')::uuid else n.responsavel_id end;
  if v_resp is not null and not exists (select 1 from pn_crm.perfil where user_id = v_resp and ativo) then
    raise exception 'Responsável inválido ou inativo.';
  end if;

  if p_dados ? 'qtd_funcionarios' then
    if nullif(trim(p_dados->>'qtd_funcionarios'), '') is not null and trim(p_dados->>'qtd_funcionarios') !~ '^\d{1,6}$' then
      raise exception 'Quantidade de funcionários deve ser um número inteiro.';
    end if;
    v_func := nullif(nullif(trim(p_dados->>'qtd_funcionarios'), '')::integer, 0);
  end if;
  if p_dados ? 'forma_pagamento' then
    v_forma := nullif(trim(p_dados->>'forma_pagamento'), '');
    if v_forma is not null and v_forma not in ('boleto','pix','transferencia','cartao') then
      raise exception 'Forma de pagamento inválida.';
    end if;
  end if;
  if p_dados ? 'parcelas' then
    if nullif(trim(p_dados->>'parcelas'), '') is not null and (trim(p_dados->>'parcelas') !~ '^\d{1,2}$' or (p_dados->>'parcelas')::int not between 1 and 60) then
      raise exception 'Parcelas deve ser um número entre 1 e 60.';
    end if;
    v_parc := nullif(trim(p_dados->>'parcelas'), '')::smallint;
  end if;

  update pn_crm.negocio set
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
    qtd_funcionarios    = case when p_dados ? 'qtd_funcionarios' then v_func else qtd_funcionarios end,
    forma_pagamento     = case when p_dados ? 'forma_pagamento' then v_forma else forma_pagamento end,
    parcelas            = case when p_dados ? 'parcelas' then v_parc else parcelas end,
    atualizado_em       = now()
  where id = n.id;

  if v_resp is distinct from n.responsavel_id then
    perform pn_crm.registrar(n.id, 'responsavel',
      'Responsável: ' || coalesce((select nome from pn_crm.perfil where user_id = v_resp), 'ninguém'));
    perform pn_crm.notificar(v_resp, n.id, 'atribuido', 'Negócio atribuído a você: ' || n.titulo);
  end if;
  select array_agg(k) into mudou from jsonb_object_keys(p_dados) k where k <> 'responsavel_id';
  if mudou is not null then
    perform pn_crm.registrar(n.id, 'edicao', 'Alterado: ' || array_to_string(mudou, ', '));
  end if;
end $_$;

CREATE FUNCTION pn.painel_crm_negocio_criar(p_funil uuid, p_titulo text, p_empresa_id uuid DEFAULT NULL::uuid, p_cliente_nome text DEFAULT NULL::text, p_cliente_cnpj text DEFAULT NULL::text, p_contato_nome text DEFAULT NULL::text, p_contato_telefone text DEFAULT NULL::text, p_contato_email text DEFAULT NULL::text, p_responsavel uuid DEFAULT NULL::uuid, p_valor numeric DEFAULT 0, p_origem text DEFAULT 'manual'::text, p_observacao text DEFAULT NULL::text, p_previsao date DEFAULT NULL::date) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; v_etapa uuid; v_resp uuid := p_responsavel; v_id uuid; v_rodizio boolean;
begin
  eu := pn_crm.exige_operar(p_funil);
  if nullif(trim(p_titulo), '') is null then
    raise exception 'Informe um título para o negócio.';
  end if;
  if p_empresa_id is null and nullif(trim(p_cliente_nome), '') is null then
    raise exception 'Escolha um cliente da base ou informe o nome do cliente.';
  end if;

  select e.id into v_etapa from pn_crm.etapa e
   where e.funil_id = p_funil and e.ativo and e.tipo = 'aberta' order by e.ordem limit 1;
  if v_etapa is null then
    raise exception 'Este funil não tem etapa aberta configurada.';
  end if;

  select f.usa_rodizio into v_rodizio from pn_crm.funil f where f.id = p_funil;
  if v_resp is null and v_rodizio and coalesce(p_origem, '') = 'landing' then
    v_resp := pn_crm.proximo_rodizio(p_funil);
  end if;
  if v_resp is null and pn_crm.papel_atual() = 'comercial' then
    v_resp := eu;
  end if;

  insert into pn_crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, cliente_cnpj,
                           contato_nome, contato_telefone, contato_email, responsavel_id,
                           valor, origem, observacao, previsao_fechamento, criado_por)
  values (p_funil, v_etapa, trim(p_titulo), p_empresa_id, nullif(trim(p_cliente_nome), ''),
          nullif(trim(p_cliente_cnpj), ''), nullif(trim(p_contato_nome), ''),
          nullif(trim(p_contato_telefone), ''), nullif(trim(p_contato_email), ''), v_resp,
          greatest(coalesce(p_valor, 0), 0), coalesce(nullif(trim(p_origem), ''), 'manual'),
          nullif(trim(p_observacao), ''), p_previsao, eu)
  returning id into v_id;

  perform pn_crm.registrar(v_id, 'criado',
    case when p_responsavel is null and v_resp is not null and v_resp <> eu then 'Criado e distribuído pelo rodízio' else 'Negócio criado' end,
    null, v_etapa);
  perform pn_crm.notificar(v_resp, v_id, 'atribuido', 'Novo negócio para você: ' || trim(p_titulo));
  return v_id;
end $$;

CREATE FUNCTION pn.painel_crm_negocio_criar_v2(p_dados jsonb, p_itens jsonb DEFAULT '[]'::jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  d jsonb := coalesce(p_dados, '{}'::jsonb);
  v_emp pn.empresa;
  v_id uuid;
  v_parc int := nullif(d ->> 'parcelas', '')::int;
  v_fp text := nullif(trim(d ->> 'forma_pagamento'), '');
  it jsonb;
  v_prod pn_crm.produto;
  v_qtd numeric;
  v_preco numeric;
  tem_itens boolean := jsonb_typeof(p_itens) = 'array' and jsonb_array_length(p_itens) > 0;
begin
  select * into v_emp from pn.empresa e where e.id = nullif(d ->> 'empresa_id', '')::uuid;
  if v_emp.id is null then
    raise exception 'Escolha a empresa (razão social e CNPJ). Se ela não existir, cadastre em "Cadastrar empresa nova".';
  end if;
  if nullif(trim(v_emp.razao_social), '') is null or pn_app.digits(v_emp.cnpj) is null then
    raise exception 'A empresa % está sem razão social ou CNPJ. Complete o cadastro dela antes de criar o negócio.',
      coalesce(v_emp.nome_fantasia, v_emp.razao_social);
  end if;
  if v_parc is not null and v_parc not between 1 and 60 then raise exception 'Parcelas: de 1 a 60.'; end if;
  if v_fp is not null and v_fp not in ('boleto', 'pix', 'transferencia', 'cartao') then raise exception 'Forma de pagamento inválida.'; end if;

  v_id := pn.painel_crm_negocio_criar(
    (d ->> 'funil')::uuid,
    coalesce(nullif(trim(d ->> 'titulo'), ''), coalesce(nullif(v_emp.nome_fantasia, ''), v_emp.razao_social)),
    v_emp.id, null, null,
    d ->> 'contato_nome', d ->> 'contato_telefone', d ->> 'contato_email',
    nullif(d ->> 'responsavel', '')::uuid,
    case when tem_itens then 0 else coalesce(nullif(d ->> 'valor', '')::numeric, 0) end,
    coalesce(nullif(d ->> 'origem', ''), 'manual'),
    d ->> 'observacao',
    nullif(d ->> 'previsao', '')::date);

  update pn_crm.negocio set parcelas = v_parc, forma_pagamento = v_fp where id = v_id;

  if tem_itens then
    for it in select * from jsonb_array_elements(p_itens) loop
      select * into v_prod from pn_crm.produto pr where pr.id = nullif(it ->> 'produto', '')::uuid and pr.ativo;
      if v_prod.id is null then raise exception 'Serviço do catálogo não encontrado ou inativo.'; end if;
      v_qtd := coalesce(nullif(it ->> 'quantidade', '')::numeric, 1);
      v_preco := coalesce(nullif(it ->> 'preco', '')::numeric, v_prod.preco);
      if v_qtd <= 0 then raise exception 'Quantidade inválida em %.', v_prod.nome; end if;
      if v_preco is null then raise exception 'Informe o preço de % (o catálogo não tem valor).', v_prod.nome; end if;

      perform pn.painel_crm_item_adicionar_v2(v_id, v_prod.id, null, v_qtd, v_preco,
                                                  coalesce(nullif(it ->> 'desconto', '')::numeric, 0));
    end loop;
    if coalesce(nullif(d ->> 'desconto_pct', '')::numeric, 0) > 0 then
      perform pn.painel_crm_negocio_desconto(v_id, (d ->> 'desconto_pct')::numeric);
    end if;
  end if;
  return v_id;
end $$;

CREATE FUNCTION pn.painel_crm_negocio_desconto(p_negocio uuid, p_pct numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_funil uuid; v_pct numeric := coalesce(p_pct, 0);
begin
  select funil_id into v_funil from pn_crm.negocio where id = p_negocio;
  if v_funil is null then raise exception 'Negócio não encontrado.'; end if;
  perform pn_crm.exige_operar(v_funil);
  if not pn_crm.ve_valores_funil(v_funil) then raise exception 'Sem permissão para alterar valores.'; end if;
  if v_pct < 0 or v_pct > 100 then raise exception 'Desconto deve ficar entre 0 e 100%%.'; end if;
  update pn_crm.negocio set desconto_pct = v_pct where id = p_negocio;
  perform pn_crm.recalcular_valor(p_negocio);
  perform pn_crm.registrar(p_negocio, 'item', format('Desconto geral: %s%%', v_pct));
end $$;

CREATE FUNCTION pn.painel_crm_negocio_mover(p_id uuid, p_etapa uuid, p_motivo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  eu uuid; n pn_crm.negocio; atual pn_crm.etapa; alvo pn_crm.etapa; f pn_crm.funil;
  papel pn_crm.papel; v_fat uuid; v_etapa_fat uuid; v_novo uuid; v_gerados int := 0;
begin
  select * into n from pn_crm.negocio where id = p_id for update;
  if n.id is null then raise exception 'Negócio não encontrado.'; end if;
  eu := pn_crm.exige_operar(n.funil_id);
  select * into atual from pn_crm.etapa where id = n.etapa_id;
  select * into alvo from pn_crm.etapa where id = p_etapa;
  if alvo.id is null or alvo.funil_id <> n.funil_id then
    raise exception 'Etapa inválida para este funil.';
  end if;
  if alvo.id = atual.id then
    return jsonb_build_object('ok', true, 'sem_mudanca', true);
  end if;
  if not alvo.ativo then
    raise exception 'A etapa "%" está desativada.', alvo.nome;
  end if;

  papel := pn_crm.papel_atual();
  if atual.tipo <> 'aberta' and papel not in ('admin','gestor') then
    raise exception 'Negócio fechado (%). Só um gestor pode reabrir.', atual.nome using errcode = '42501';
  end if;
  if alvo.tipo = 'perdido' and nullif(trim(p_motivo), '') is null then
    raise exception 'Informe o motivo da perda.';
  end if;

  update pn_crm.negocio
     set etapa_id = alvo.id,
         entrou_etapa_em = now(),
         ultimo_alerta_em = null,
         fechado_em = case when alvo.tipo = 'aberta' then null else now() end,
         motivo_perda = case when alvo.tipo = 'perdido' then trim(p_motivo)
                             when alvo.tipo = 'aberta' then null else motivo_perda end,
         atualizado_em = now()
   where id = n.id;

  perform pn_crm.registrar(n.id, 'etapa',
    case when alvo.tipo = 'perdido' then 'Motivo: ' || trim(p_motivo) else nullif(trim(p_motivo), '') end,
    atual.id, alvo.id);

  if alvo.tipo = 'ganho' then
    for v_fat in
      select t.funil_destino_id from pn_crm.tunel t join pn_crm.funil d on d.id = t.funil_destino_id and d.ativo
       where t.funil_origem_id = n.funil_id
    loop
      continue when exists (select 1 from pn_crm.negocio d where d.negocio_origem_id = n.id and d.funil_id = v_fat);
      select id into v_etapa_fat from pn_crm.etapa where funil_id = v_fat and ativo and tipo = 'aberta' order by ordem limit 1;
      continue when v_etapa_fat is null;
      select * into f from pn_crm.funil where id = v_fat;
      insert into pn_crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, cliente_cnpj,
                               contato_nome, contato_telefone, contato_email, responsavel_id,
                               valor, origem, negocio_origem_id, observacao, criado_por,
                               qtd_funcionarios, forma_pagamento, parcelas)
      values (v_fat, v_etapa_fat, n.titulo, n.empresa_id, n.cliente_nome, n.cliente_cnpj,
              n.contato_nome, n.contato_telefone, n.contato_email,
              case when f.slug = 'pos-venda' then n.responsavel_id end,
              n.valor, 'ganho_comercial', n.id, n.observacao, eu,
              n.qtd_funcionarios, n.forma_pagamento, n.parcelas)
      returning id into v_novo;
      insert into pn_crm.negocio_item (negocio_id, produto_id, descricao, quantidade, preco_unitario)
      select v_novo, i.produto_id, i.descricao, i.quantidade, i.preco_unitario
        from pn_crm.negocio_item i where i.negocio_id = n.id;
      perform pn_crm.registrar(v_novo, 'criado', 'Aberto automaticamente pelo fechamento do negócio #' || n.numero, null, v_etapa_fat);
      perform pn_crm.registrar(n.id, 'nota', 'Card aberto automaticamente em ' || f.nome, null, null);
      insert into pn_crm.notificacao (user_id, negocio_id, tipo, texto)
      select p.user_id, v_novo, 'tunel', 'Novo card em ' || f.nome || ': ' || n.titulo
        from pn_crm.perfil p
       where p.ativo and p.user_id <> eu
         and (p.papel = 'gestor' or p.papel = any (f.papeis));
      v_gerados := v_gerados + 1;
    end loop;
  end if;

  if n.responsavel_id is distinct from eu then
    perform pn_crm.notificar(n.responsavel_id, n.id, 'etapa', n.titulo || ': movido para ' || alvo.nome);
  end if;

  return jsonb_build_object('ok', true, 'cards_gerados', v_gerados);
end $$;

CREATE FUNCTION pn.painel_crm_pendencias(p_so_minhas boolean DEFAULT false) RETURNS TABLE(id uuid, numero bigint, titulo text, cliente text, funil_id uuid, funil text, etapa text, responsavel_id uuid, responsavel_nome text, dias_na_etapa integer, alerta_dias integer, valor numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare eu uuid; vv boolean;
begin
  eu := pn_crm.exige_ativo();
  vv := pn_crm.ve_valores();
  return query
    select n.id, n.numero, n.titulo,
           coalesce(nullif(em.nome_fantasia, ''), em.razao_social, n.cliente_nome)::text,
           f.id, f.nome, e.nome, n.responsavel_id, p.nome,
           floor(extract(epoch from now() - n.entrou_etapa_em) / 86400)::int,
           e.alerta_dias, case when vv then n.valor end
      from pn_crm.negocio n
      join pn_crm.etapa e on e.id = n.etapa_id
      join pn_crm.funil f on f.id = n.funil_id
      left join pn.empresa em on em.id = n.empresa_id
      left join pn_crm.perfil p on p.user_id = n.responsavel_id
     where e.tipo = 'aberta' and e.alerta_dias is not null
       and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)
       and (not p_so_minhas or n.responsavel_id = eu)
       and pn_crm.ve_negocio(n.responsavel_id)
     order by n.entrou_etapa_em;
end $$;

CREATE FUNCTION pn.painel_crm_produto_salvar(p_id uuid, p_nome text, p_descricao text DEFAULT NULL::text, p_categoria text DEFAULT NULL::text, p_preco numeric DEFAULT NULL::numeric, p_unidade text DEFAULT 'un'::text, p_recorrente boolean DEFAULT false, p_ativo boolean DEFAULT true) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid;
begin
  perform pn_crm.exige('gestor');
  if nullif(trim(p_nome), '') is null then raise exception 'Informe o nome do produto.'; end if;
  if p_id is null then
    insert into pn_crm.produto (nome, descricao, categoria, preco, unidade, recorrente, ativo)
    values (trim(p_nome), nullif(trim(p_descricao), ''), nullif(trim(p_categoria), ''), p_preco,
            coalesce(nullif(trim(p_unidade), ''), 'un'), coalesce(p_recorrente, false), coalesce(p_ativo, true))
    returning id into v_id;
  else
    update pn_crm.produto set nome = trim(p_nome), descricao = nullif(trim(p_descricao), ''),
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

CREATE FUNCTION pn.painel_crm_produtos(p_todos boolean DEFAULT false) RETURNS TABLE(id uuid, nome text, descricao text, categoria text, preco numeric, unidade text, recorrente boolean, ativo boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  perform pn_crm.exige_ativo();
  return query
    select pr.id, pr.nome, pr.descricao, pr.categoria, pr.preco, pr.unidade, pr.recorrente, pr.ativo
      from pn_crm.produto pr where p_todos or pr.ativo
     order by pr.categoria nulls last, pr.nome;
end $$;

CREATE FUNCTION pn.painel_crm_quadro(p_funil uuid, p_responsavel uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text, p_dias_fechados integer DEFAULT 30) RETURNS TABLE(id uuid, numero bigint, etapa_id uuid, titulo text, cliente text, empresa_id uuid, responsavel_id uuid, responsavel_nome text, valor numeric, origem text, entrou_etapa_em timestamp with time zone, dias_na_etapa integer, atrasado boolean, qtd_itens integer, previsao_fechamento date, criado_em timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); vv boolean;
begin
  perform pn_crm.exige_ativo();
  vv := pn_crm.ve_valores();
  return query
    select n.id, n.numero, n.etapa_id, n.titulo,
           coalesce(nullif(em.nome_fantasia, ''), em.razao_social, n.cliente_nome)::text,
           n.empresa_id, n.responsavel_id, p.nome, case when vv then n.valor end, n.origem, n.entrou_etapa_em,
           floor(extract(epoch from now() - n.entrou_etapa_em) / 86400)::int,
           (e.tipo = 'aberta' and e.alerta_dias is not null
             and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)),
           (select count(*)::int from pn_crm.negocio_item i where i.negocio_id = n.id),
           n.previsao_fechamento, n.criado_em
      from pn_crm.negocio n
      join pn_crm.etapa e on e.id = n.etapa_id
      left join pn.empresa em on em.id = n.empresa_id
      left join pn_crm.perfil p on p.user_id = n.responsavel_id
     where n.funil_id = p_funil
       and pn_crm.ve_negocio(n.responsavel_id)
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

CREATE FUNCTION pn.painel_crm_quadro_v2(p_funil uuid, p_responsavel uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text, p_dias_fechados integer DEFAULT 30, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date) RETURNS TABLE(id uuid, numero bigint, etapa_id uuid, titulo text, cliente text, empresa_id uuid, responsavel_id uuid, responsavel_nome text, valor numeric, origem text, entrou_etapa_em timestamp with time zone, dias_na_etapa integer, atrasado boolean, qtd_itens integer, previsao_fechamento date, criado_em timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); vv boolean; periodo boolean := p_de is not null or p_ate is not null;
begin
  perform pn_crm.exige_ativo();
  vv := pn_crm.ve_valores();
  return query
    select n.id, n.numero, n.etapa_id, n.titulo,
           coalesce(nullif(em.nome_fantasia, ''), em.razao_social, n.cliente_nome)::text,
           n.empresa_id, n.responsavel_id, p.nome, case when vv then n.valor end, n.origem, n.entrou_etapa_em,
           floor(extract(epoch from now() - n.entrou_etapa_em) / 86400)::int,
           (e.tipo = 'aberta' and e.alerta_dias is not null
             and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)),
           (select count(*)::int from pn_crm.negocio_item i where i.negocio_id = n.id),
           n.previsao_fechamento, n.criado_em
      from pn_crm.negocio n
      join pn_crm.etapa e on e.id = n.etapa_id
      left join pn.empresa em on em.id = n.empresa_id
      left join pn_crm.perfil p on p.user_id = n.responsavel_id
     where n.funil_id = p_funil
       and pn_crm.ve_negocio(n.responsavel_id)
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

CREATE FUNCTION pn.painel_crm_quadro_v3(p_funil uuid, p_responsavel uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text, p_dias_fechados integer DEFAULT 30, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date) RETURNS TABLE(id uuid, numero bigint, etapa_id uuid, titulo text, cliente text, empresa_id uuid, responsavel_id uuid, responsavel_nome text, valor numeric, origem text, entrou_etapa_em timestamp with time zone, dias_na_etapa integer, atrasado boolean, qtd_itens integer, previsao_fechamento date, criado_em timestamp with time zone, vendedor_nome text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); vv boolean; periodo boolean := p_de is not null or p_ate is not null;
begin
  perform pn_crm.exige_ativo();
  vv := pn_crm.ve_valores_funil(p_funil);
  return query
    select n.id, n.numero, n.etapa_id, n.titulo,
           coalesce(nullif(em.nome_fantasia, ''), em.razao_social, n.cliente_nome)::text,
           n.empresa_id, n.responsavel_id, p.nome, case when vv then n.valor end, n.origem, n.entrou_etapa_em,
           floor(extract(epoch from now() - n.entrou_etapa_em) / 86400)::int,
           (e.tipo = 'aberta' and e.alerta_dias is not null
             and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)),
           (select count(*)::int from pn_crm.negocio_item i where i.negocio_id = n.id),
           n.previsao_fechamento, n.criado_em,
           case when n.negocio_origem_id is not null
                then (select pv.nome from pn_crm.perfil pv where pv.user_id = pn_crm.vendedor_id(n.id)) end::text
      from pn_crm.negocio n
      join pn_crm.etapa e on e.id = n.etapa_id
      left join pn.empresa em on em.id = n.empresa_id
      left join pn_crm.perfil p on p.user_id = n.responsavel_id
     where n.funil_id = p_funil
       and pn_crm.ve_negocio(n.responsavel_id)
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

CREATE FUNCTION pn.painel_crm_responsaveis() RETURNS TABLE(user_id uuid, nome text, papel text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  perform pn_crm.exige_ativo();
  return query
    select p.user_id, p.nome, p.papel::text from pn_crm.perfil p
     where p.ativo and p.papel <> 'leitura' order by p.nome;
end $$;

CREATE FUNCTION pn.painel_crm_rodizio(p_funil uuid) RETURNS TABLE(user_id uuid, nome text, ordem integer, ativo boolean, proximo boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare ultimo uuid; ord_ult int; prox uuid;
begin
  perform pn_crm.exige_ativo();
  select s.ultimo_user_id into ultimo from pn_crm.rodizio_estado s where s.funil_id = p_funil;
  select r.ordem into ord_ult from pn_crm.rodizio r where r.funil_id = p_funil and r.user_id = ultimo;
  select r.user_id into prox from pn_crm.rodizio r join pn_crm.perfil p on p.user_id = r.user_id and p.ativo
   where r.funil_id = p_funil and r.ativo and r.ordem > coalesce(ord_ult, -1) order by r.ordem limit 1;
  if prox is null then
    select r.user_id into prox from pn_crm.rodizio r join pn_crm.perfil p on p.user_id = r.user_id and p.ativo
     where r.funil_id = p_funil and r.ativo order by r.ordem limit 1;
  end if;
  return query
    select r.user_id, p.nome, r.ordem, r.ativo and p.ativo, coalesce(r.user_id = prox, false)
      from pn_crm.rodizio r join pn_crm.perfil p on p.user_id = r.user_id
     where r.funil_id = p_funil order by r.ordem;
end $$;

CREATE FUNCTION pn.painel_crm_rodizio_salvar(p_funil uuid, p_users uuid[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor');
  delete from pn_crm.rodizio where funil_id = p_funil and not (user_id = any (coalesce(p_users, '{}')));
  insert into pn_crm.rodizio (funil_id, user_id, ordem, ativo)
  select p_funil, x.id, x.pos, true
    from unnest(coalesce(p_users, '{}')) with ordinality as x(id, pos)
    join pn_crm.perfil p on p.user_id = x.id
  on conflict (funil_id, user_id) do update set ordem = excluded.ordem, ativo = true;
end $$;

CREATE FUNCTION pn.painel_documento_arquivo(p_id uuid, p_path text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor','operacoes');
  if p_path is not null and p_path not like 'documentos/' || p_id::text || '/%' then
    raise exception 'Caminho de arquivo inválido.';
  end if;
  update pn.documento set arquivo_path = p_path, updated_at = now() where id = p_id;
end $$;

CREATE FUNCTION pn.painel_documento_regra_salvar(p_aviso integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor');
  update pn_crm.documento_regra set aviso_dias = p_aviso where id;
end $$;

CREATE FUNCTION pn.painel_documento_salvar(p_id uuid, p_dados jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v uuid := p_id; fim_antigo date;
begin
  perform pn_crm.exige('gestor','operacoes');
  if p_dados ? 'tipo' and p_dados->>'tipo' not in ('PGR','PCMSO','LTCAT','LTIP','PPR','PCA','PPP','OUTRO') then
    raise exception 'Tipo inválido.';
  end if;
  if p_dados ? 'situacao' and p_dados->>'situacao' not in ('em_elaboracao','vigente','vencido','cancelado') then
    raise exception 'Situação inválida.';
  end if;
  if v is null then
    if nullif(p_dados->>'empresa_id', '') is null then raise exception 'Informe a empresa.'; end if;
    insert into pn.documento (empresa_id, tipo, versao, data_elaboracao, vigencia_inicio, vigencia_fim, situacao,
                                  responsavel_id, observacao, origem)
    values ((p_dados->>'empresa_id')::uuid, coalesce(nullif(p_dados->>'tipo', ''), 'PGR')::pn.tipo_documento,
            nullif(trim(p_dados->>'versao'), ''), nullif(p_dados->>'data_elaboracao', '')::date,
            nullif(p_dados->>'vigencia_inicio', '')::date, nullif(p_dados->>'vigencia_fim', '')::date,
            coalesce(nullif(p_dados->>'situacao', ''), 'vigente')::pn.situacao_documento,
            nullif(p_dados->>'responsavel_id', '')::uuid, nullif(trim(p_dados->>'observacao'), ''), 'manual')
    returning id into v;
    return v;
  end if;
  select vigencia_fim into fim_antigo from pn.documento where id = v;
  if not found then raise exception 'Documento não encontrado.'; end if;
  update pn.documento set
    tipo = coalesce(nullif(p_dados->>'tipo', ''), tipo::text)::pn.tipo_documento,
    versao = case when p_dados ? 'versao' then nullif(trim(p_dados->>'versao'), '') else versao end,
    data_elaboracao = case when p_dados ? 'data_elaboracao' then nullif(p_dados->>'data_elaboracao', '')::date else data_elaboracao end,
    vigencia_inicio = case when p_dados ? 'vigencia_inicio' then nullif(p_dados->>'vigencia_inicio', '')::date else vigencia_inicio end,
    vigencia_fim = case when p_dados ? 'vigencia_fim' then nullif(p_dados->>'vigencia_fim', '')::date else vigencia_fim end,
    situacao = coalesce(nullif(p_dados->>'situacao', ''), situacao::text)::pn.situacao_documento,
    responsavel_id = case when p_dados ? 'responsavel_id' then nullif(p_dados->>'responsavel_id', '')::uuid else responsavel_id end,
    observacao = case when p_dados ? 'observacao' then nullif(trim(p_dados->>'observacao'), '') else observacao end,
    updated_at = now()
  where id = v;

  if p_dados ? 'vigencia_fim' and nullif(p_dados->>'vigencia_fim', '')::date > coalesce(fim_antigo, '-infinity'::date) then
    delete from pn_crm.documento_renovacao where documento_id = v;
  end if;
  return v;
end $$;

CREATE FUNCTION pn.painel_documentos(p_busca text DEFAULT NULL::text, p_tipo text DEFAULT NULL::text, p_situacao text DEFAULT NULL::text, p_empresa uuid DEFAULT NULL::uuid) RETURNS TABLE(id uuid, empresa_id uuid, empresa text, cnpj text, tipo text, versao text, data_elaboracao date, vigencia_inicio date, vigencia_fim date, dias_para_vencer integer, situacao text, situacao_cadastro text, responsavel_id uuid, responsavel text, arquivo_path text, observacao text, origem text, renovacao_negocio_id uuid)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); aviso int; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        dig text := nullif(regexp_replace(coalesce(p_busca, ''), '\D', '', 'g'), '');
begin
  perform pn_crm.exige('gestor','operacoes','comercial');
  select aviso_dias into aviso from pn_crm.documento_regra where id;
  return query
    select d.id, d.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social)::text, e.cnpj::text, d.tipo::text, d.versao,
           d.data_elaboracao, d.vigencia_inicio, d.vigencia_fim, (d.vigencia_fim - hoje)::int,
           pn_crm.documento_situacao(d.situacao::text, d.vigencia_fim, aviso), d.situacao::text,
           d.responsavel_id, p.nome::text, d.arquivo_path, d.observacao, d.origem::text, x.negocio_id
      from pn.documento d
      join pn.empresa e on e.id = d.empresa_id
      left join pn.profissional p on p.id = d.responsavel_id
      left join pn_crm.documento_renovacao x on x.documento_id = d.id
     where (p_empresa is null or d.empresa_id = p_empresa)
       and (p_tipo is null or d.tipo::text = p_tipo)
       and (p_situacao is null or pn_crm.documento_situacao(d.situacao::text, d.vigencia_fim, aviso) = p_situacao)
       and (termo is null or e.razao_social ilike '%' || termo || '%' or e.nome_fantasia ilike '%' || termo || '%'
            or (dig is not null and length(dig) >= 4 and regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') like dig || '%'))
     order by case pn_crm.documento_situacao(d.situacao::text, d.vigencia_fim, aviso)
                when 'vencido' then 0 when 'a_vencer' then 1 when 'em_elaboracao' then 2 when 'vigente' then 3 else 4 end,
              d.vigencia_fim nulls last
     limit 1000;
end $$;

CREATE FUNCTION pn.painel_documentos_resumo() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare aviso int;
begin
  perform pn_crm.exige('gestor','operacoes','comercial');
  select aviso_dias into aviso from pn_crm.documento_regra where id;
  return (with s as (select pn_crm.documento_situacao(situacao::text, vigencia_fim, aviso) sit from pn.documento)
          select jsonb_build_object('vigentes', count(*) filter (where sit = 'vigente'),
                                    'a_vencer', count(*) filter (where sit = 'a_vencer'),
                                    'vencidos', count(*) filter (where sit = 'vencido'),
                                    'em_elaboracao', count(*) filter (where sit = 'em_elaboracao'),
                                    'aviso_dias', aviso,
                                    'pode_editar', pn_crm.papel_atual() in ('admin','gestor','operacoes'))
            from s);
end $$;

CREATE FUNCTION pn.painel_edicao_liberar(p_tabela text, p_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare antes text[];
begin
  perform pn_crm.exige('gestor');
  if p_tabela not in ('empresa','empresa_contato','unidade','colaborador','atendimento') then
    raise exception 'Tabela inválida.';
  end if;
  execute format('select campos_editados from public.%I where id = $1', p_tabela) into antes using p_id;
  if antes is null then raise exception 'Registro não encontrado.'; end if;
  perform set_config('crm.edicao_painel', 'on', true);
  execute format('update public.%I set campos_editados = ''{}'' where id = $1', p_tabela) using p_id;
  perform set_config('crm.edicao_painel', 'off', true);
  insert into pn_crm.edicao (tabela, registro_id, acao, mudancas, usuario_id)
  values (p_tabela, p_id, 'liberar', jsonb_build_object('campos', to_jsonb(antes)), auth.uid());
end $_$;

CREATE FUNCTION pn.painel_empresa_contatar(p_empresa uuid, p_contato uuid, p_canal text, p_destino text, p_texto text, p_assunto text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare uid uuid := pn_crm.exige('gestor','comercial','operacoes','financeiro'); tel text; sid bigint; iid bigint;
begin
  if not pn_crm.ve_empresa(p_empresa) then raise exception 'Esta empresa não está na sua carteira.' using errcode = '42501'; end if;
  if p_canal not in ('whatsapp','email') then raise exception 'Canal inválido.'; end if;
  if nullif(btrim(p_texto), '') is null and p_canal = 'whatsapp' then raise exception 'Escreva a mensagem.'; end if;
  if p_canal = 'whatsapp' then
    tel := pn_crm.so_digitos(p_destino);
    if length(tel) in (10, 11) then tel := '55' || tel; end if;
    if tel is null or length(tel) not between 12 and 13 then raise exception 'Telefone inválido para WhatsApp.'; end if;
    insert into pn_crm.wa_saida (telefone, texto, origem, ref_id, para, empresa_id, usuario_id)
    values (tel, btrim(p_texto), 'ficha_empresa', p_empresa::text, 'cliente', p_empresa, uid)
    returning id into sid;
  end if;
  insert into pn_crm.empresa_interacao (empresa_id, contato_id, canal, destino, assunto, texto, wa_saida_id, usuario_id)
  values (p_empresa, p_contato, p_canal, coalesce(tel, nullif(btrim(p_destino), '')), nullif(btrim(p_assunto), ''),
          nullif(btrim(p_texto), ''), sid, uid)
  returning id into iid;
  return jsonb_build_object('id', iid, 'wa_saida_id', sid);
end $$;

CREATE FUNCTION pn.painel_empresa_contato_excluir(p_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare c jsonb;
begin
  perform pn_crm.exige('gestor');
  delete from pn.empresa_contato t where t.id = p_id returning to_jsonb(t) into c;
  if c is null then raise exception 'Contato não encontrado.'; end if;
  insert into pn_crm.edicao (tabela, registro_id, acao, mudancas, usuario_id)
  values ('empresa_contato', p_id, 'excluir', jsonb_build_object('registro', c), auth.uid());
end $$;

CREATE FUNCTION pn.painel_empresa_contato_salvar(p_empresa uuid, p_id uuid, p_dados jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare d jsonb;
begin
  perform pn_crm.exige('gestor');
  d := pn_crm.limpar_dados(p_dados, array['nome','cargo','email','telefone','tipo','recebe_alerta_exame']);
  if coalesce(d ->> 'nome', '') = '' and p_id is null then raise exception 'Informe o nome do contato.'; end if;
  if p_id is null then
    if not exists (select 1 from pn.empresa where id = p_empresa) then raise exception 'Empresa não encontrada.'; end if;
    return pn_crm.criar('empresa_contato', d, jsonb_build_object('empresa_id', p_empresa, 'origem', 'manual'));
  end if;
  perform pn_crm.editar('empresa_contato', p_id, d);
  return p_id;
end $$;

CREATE FUNCTION pn.painel_empresa_criar(p_dados jsonb, p_contato jsonb DEFAULT NULL::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  d jsonb;
  ct jsonb;
  v_cnpj text;
  v_id uuid;
  v_nome text;
  v_ligados int := 0;
begin
  perform pn_crm.exige('gestor', 'comercial', 'operacoes');
  d := pn_crm.limpar_dados(p_dados, array['razao_social','nome_fantasia','cnpj','cnae_principal','grau_risco',
                                       'cep','logradouro','numero','complemento','bairro','cidade','uf','telefone','email']);
  if coalesce(d ->> 'razao_social', '') = '' then raise exception 'Informe a razão social.'; end if;
  v_cnpj := nullif(regexp_replace(coalesce(d ->> 'cnpj', ''), '\D', '', 'g'), '');
  if v_cnpj is not null and length(v_cnpj) not in (11, 14) then raise exception 'CNPJ (ou CPF) com número de dígitos inválido.'; end if;
  if d ->> 'uf' is not null and length(d ->> 'uf') <> 2 then raise exception 'UF deve ter 2 letras.'; end if;
  if d ->> 'grau_risco' is not null and (d ->> 'grau_risco')::int not between 1 and 4 then raise exception 'Grau de risco vai de 1 a 4.'; end if;

  if v_cnpj is not null then
    select e.id, coalesce(e.nome_fantasia, e.razao_social) into v_id, v_nome
      from pn.empresa e where pn_app.digits(e.cnpj) = v_cnpj
     order by (e.situacao = 'ativo') desc, e.updated_at desc limit 1;
    if v_id is not null then
      return jsonb_build_object('id', v_id, 'existente', true, 'nome', v_nome, 'visivel', pn_crm.ve_empresa(v_id));
    end if;
    d := jsonb_set(d, '{cnpj}', to_jsonb(v_cnpj));
  end if;

  v_id := pn_crm.criar('empresa', d, jsonb_build_object('origem', 'manual', 'cadastrado_por', auth.uid()));

  ct := pn_crm.limpar_dados(coalesce(p_contato, '{}'::jsonb), array['nome','cargo','email','telefone']);
  if coalesce(ct ->> 'nome', '') <> '' then
    perform pn_crm.criar('empresa_contato', ct, jsonb_build_object('empresa_id', v_id, 'origem', 'manual'));
  end if;

  if v_cnpj is not null then
    update pn_crm.negocio n set empresa_id = v_id, atualizado_em = now()
     where n.empresa_id is null and regexp_replace(coalesce(n.cliente_cnpj, ''), '\D', '', 'g') = v_cnpj
       and (pn_crm.papel_atual() <> 'comercial' or n.responsavel_id = auth.uid());
    get diagnostics v_ligados = row_count;
  end if;

  return jsonb_build_object('id', v_id, 'existente', false, 'nome', coalesce(d ->> 'nome_fantasia', d ->> 'razao_social'),
                            'visivel', true, 'cards_ligados', v_ligados);
end $$;

CREATE FUNCTION pn.painel_empresa_salvar(p_id uuid, p_dados jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare d jsonb; mud text[];
begin
  perform pn_crm.exige('gestor');
  d := pn_crm.limpar_dados(p_dados, array['razao_social','nome_fantasia','cnpj','situacao','cnae_principal','grau_risco',
                                       'cep','logradouro','numero','complemento','bairro','cidade','uf','telefone','email',
                                       'contrato_inicio','contrato_fim']);
  if d ? 'razao_social' and d ->> 'razao_social' is null then raise exception 'Informe a razão social.'; end if;
  if d ? 'situacao' and d ->> 'situacao' is null then d := d - 'situacao'; end if;
  if d ->> 'cnpj' is not null and length(d ->> 'cnpj') not in (11, 14) then raise exception 'CNPJ (ou CPF) com número de dígitos inválido.'; end if;
  if d ->> 'uf' is not null and length(d ->> 'uf') <> 2 then raise exception 'UF deve ter 2 letras.'; end if;
  if d ->> 'grau_risco' is not null and (d ->> 'grau_risco')::int not between 1 and 4 then raise exception 'Grau de risco vai de 1 a 4.'; end if;
  mud := pn_crm.editar('empresa', p_id, d);
  return jsonb_build_object('alterados', to_jsonb(mud));
end $$;

CREATE FUNCTION pn.painel_empresas_buscar(p_busca text) RETURNS TABLE(id uuid, nome text, razao_social text, cnpj text, cidade text, uf text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); dig text;
begin
  perform pn_crm.exige_ativo();
  if termo is null or length(termo) < 2 then return; end if;
  dig := nullif(regexp_replace(termo, '\D', '', 'g'), '');
  return query
    select e.id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social)::text, e.razao_social::text, e.cnpj::text, e.cidade::text, e.uf::text
      from pn.empresa e
     where e.razao_social ilike '%' || termo || '%'
        or e.nome_fantasia ilike '%' || termo || '%'
        or (dig is not null and length(dig) >= 4 and regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') like dig || '%')
     order by e.razao_social
     limit 20;
end $$;

CREATE FUNCTION pn.painel_fin_gerar_mes(p_competencia date) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; comp date := date_trunc('month', p_competencia)::date; fim_mes date; n int := 0; r record; venc date;
begin
  eu := pn_crm.exige_financeiro();
  fim_mes := (comp + interval '1 month - 1 day')::date;
  for r in
    select ct.* from pn_crm.contrato ct
     where ct.status = 'assinado' and ct.valor_mensal > 0
       and (ct.fim is null or ct.fim >= comp) and (ct.inicio is null or ct.inicio <= fim_mes)
       and not exists (select 1 from pn_crm.cobranca cb where cb.contrato_id = ct.id and cb.competencia = comp and not cb.cancelada)
  loop
    venc := least(comp + (coalesce(r.dia_vencimento, 10) - 1), fim_mes);
    insert into pn_crm.cobranca (empresa_id, cliente_nome, contrato_id, descricao, competencia, vencimento, valor, forma, origem, criado_por)
    values (r.empresa_id, r.cliente_nome, r.id, r.titulo || ' — ' || to_char(comp, 'MM/YYYY'), comp, venc, r.valor_mensal,
            case lower(coalesce(r.forma_pagamento, '')) when 'boleto' then 'boleto' when 'pix' then 'pix' else null end,
            'contrato', eu);
    n := n + 1;
  end loop;
  return n;
end $$;

CREATE FUNCTION pn.painel_fin_importar(p_linhas jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; l jsonb; emp uuid; dig text; venc date; ok int := 0; erros jsonb := '[]'::jsonb; i int := 0; v uuid;
begin
  eu := pn_crm.exige_financeiro();
  if jsonb_typeof(p_linhas) <> 'array' then raise exception 'Formato inválido.'; end if;
  if jsonb_array_length(p_linhas) > 5000 then raise exception 'Máximo de 5.000 linhas por importação.'; end if;
  for l in select * from jsonb_array_elements(p_linhas) loop
    i := i + 1;
    begin
      dig := nullif(regexp_replace(coalesce(l->>'cnpj', ''), '\D', '', 'g'), '');
      emp := null;
      if dig is not null then
        select e.id into emp from pn.empresa e where regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g') = dig
         order by e.situacao = 'ativo' desc limit 1;
      end if;
      if emp is null and nullif(trim(l->>'cliente'), '') is null then
        raise exception 'CNPJ não encontrado na base e sem nome de cliente';
      end if;
      venc := (l->>'vencimento')::date;
      insert into pn_crm.cobranca (empresa_id, cliente_nome, descricao, competencia, vencimento, valor, pago_em, valor_pago,
                                nota_fiscal, origem, criado_por)
      values (emp, case when emp is null then trim(l->>'cliente') end, coalesce(nullif(trim(l->>'descricao'), ''), 'Importado'),
              date_trunc('month', coalesce(nullif(l->>'competencia', '')::date, venc))::date, venc, (l->>'valor')::numeric,
              nullif(l->>'pago_em', '')::date, nullif(l->>'valor_pago', '')::numeric, nullif(trim(l->>'nota_fiscal'), ''),
              'importacao', eu)
      returning id into v;
      insert into pn_crm.cobranca_evento (cobranca_id, texto, autor_id) values (v, 'Importada de planilha', eu);
      ok := ok + 1;
    exception when others then
      erros := erros || jsonb_build_object('linha', i, 'erro', sqlerrm);
    end;
  end loop;
  perform pn_crm.fin_inadimplencia();
  return jsonb_build_object('importadas', ok, 'erros', erros);
end $$;

CREATE FUNCTION pn.painel_fin_regra() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige_financeiro();
  return (select jsonb_build_object('tolerancia_dias', tolerancia_dias) from pn_crm.fin_regra where id);
end $$;

CREATE FUNCTION pn.painel_fin_regra_salvar(p_tolerancia integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor');
  update pn_crm.fin_regra set tolerancia_dias = p_tolerancia, atualizado_em = now() where id;
  perform pn_crm.fin_inadimplencia();
end $$;

CREATE FUNCTION pn.painel_fin_resumo(p_competencia date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare comp date := date_trunc('month', coalesce(p_competencia, now()::date))::date; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        tol int;
begin
  perform pn_crm.exige_financeiro();
  select tolerancia_dias into tol from pn_crm.fin_regra where id;
  return (
    select jsonb_build_object(
      'competencia', comp,
      'previsto', coalesce(sum(valor) filter (where competencia = comp and not cancelada), 0),
      'recebido', coalesce(sum(coalesce(valor_pago, valor)) filter (where competencia = comp and pago_em is not null and not cancelada), 0),
      'a_receber', coalesce(sum(valor) filter (where competencia = comp and pago_em is null and not cancelada), 0),
      'vencido_total', coalesce(sum(valor) filter (where pago_em is null and not cancelada and vencimento < hoje), 0),
      'qtd_vencidas', count(*) filter (where pago_em is null and not cancelada and vencimento < hoje),
      'empresas_inadimplentes', count(distinct empresa_id) filter (where pago_em is null and not cancelada and vencimento < hoje - tol),
      'tolerancia_dias', tol,
      'contratos_sem_cobranca', (select count(*) from pn_crm.contrato ct
                                  where ct.status = 'assinado' and ct.valor_mensal > 0
                                    and (ct.fim is null or ct.fim >= comp) and (ct.inicio is null or ct.inicio <= (comp + interval '1 month - 1 day')::date)
                                    and not exists (select 1 from pn_crm.cobranca cb where cb.contrato_id = ct.id and cb.competencia = comp and not cb.cancelada)))
    from pn_crm.cobranca);
end $$;

CREATE FUNCTION pn.painel_meu_perfil() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sessão ausente' using errcode = '42501';
  end if;
  select jsonb_build_object('user_id', p.user_id, 'nome', p.nome, 'email', p.email,
                            'papel', p.papel, 'ativo', p.ativo)
    into r from pn_crm.perfil p where p.user_id = auth.uid();
  return r;
end $$;

CREATE FUNCTION pn.painel_minhas_tarefas() RETURNS TABLE(id uuid, quadro_id uuid, quadro text, titulo text, status text, prioridade text, prazo date, atrasada boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := pn_crm.exige_ativo();
  return query
    select t.id, t.quadro_id, q.nome, t.titulo, t.status, t.prioridade, t.prazo,
           t.prazo < (now() at time zone 'America/Sao_Paulo')::date
      from pn_crm.tarefa t join pn_crm.quadro q on q.id = t.quadro_id
     where eu = any (t.responsaveis) and t.status <> 'feito'
     order by t.prazo nulls last, t.ordem;
end $$;

CREATE FUNCTION pn.painel_notificacoes(p_limite integer DEFAULT 30) RETURNS TABLE(id bigint, negocio_id uuid, tarefa_id uuid, contrato_id uuid, tipo text, texto text, lida_em timestamp with time zone, criado_em timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := pn_crm.exige_ativo();
  return query
    select n.id, n.negocio_id, n.tarefa_id, n.contrato_id, n.tipo, n.texto, n.lida_em, n.criado_em
      from pn_crm.notificacao n where n.user_id = eu
     order by n.criado_em desc limit least(greatest(p_limite, 1), 100);
end $$;

CREATE FUNCTION pn.painel_notificacoes_marcar_lidas(p_id bigint DEFAULT NULL::bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid;
begin
  eu := pn_crm.exige_ativo();
  update pn_crm.notificacao set lida_em = now()
   where user_id = eu and lida_em is null and (p_id is null or id = p_id);
end $$;

CREATE FUNCTION pn.painel_notificacoes_nao_lidas() RETURNS integer
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid;
begin
  eu := pn_crm.exige_ativo();
  return (select count(*)::int from pn_crm.notificacao where user_id = eu and lida_em is null);
end $$;

CREATE FUNCTION pn.painel_papel_em(p_papeis text[]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select p.papel = 'admin' or p.papel::text = any (p_papeis)
                     from pn_crm.perfil p where p.user_id = auth.uid() and p.ativo), false)
$$;

CREATE FUNCTION pn.painel_pre_cadastro_excluir(p_email text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('admin');
  delete from pn_crm.pre_cadastro where email = lower(trim(p_email));
end $$;

CREATE FUNCTION pn.painel_pre_cadastro_salvar(p_email text, p_dados jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare e text := lower(trim(p_email)); t text := pn_crm.telefone_normalizado(p_dados->>'telefone');
begin
  perform pn_crm.exige('admin');
  if position('@' in e) < 2 or position('.' in split_part(e, '@', 2)) < 2 or e ~ '\s' then raise exception 'E-mail inválido.'; end if;
  if coalesce(p_dados->>'papel', '') not in ('admin','gestor','comercial','operacoes','financeiro','leitura') then
    raise exception 'Perfil inválido.';
  end if;
  if nullif(trim(p_dados->>'nome'), '') is null then raise exception 'Informe o nome.'; end if;
  if nullif(trim(coalesce(p_dados->>'telefone', '')), '') is not null and t is null then raise exception 'Telefone inválido.'; end if;
  insert into pn_crm.pre_cadastro (email, nome, cargo, papel, libera_agenda, rodizio_ordem, telefone)
  values (e, trim(p_dados->>'nome'), nullif(trim(p_dados->>'cargo'), ''), (p_dados->>'papel')::pn_crm.papel,
          coalesce((p_dados->>'libera_agenda')::boolean, false), nullif(p_dados->>'rodizio_ordem', '')::int, t)
  on conflict (email) do update set nome = excluded.nome, cargo = excluded.cargo, papel = excluded.papel,
    libera_agenda = excluded.libera_agenda, rodizio_ordem = excluded.rodizio_ordem,
    telefone = coalesce(excluded.telefone, pn_crm.pre_cadastro.telefone);

  if t is not null then update pn_crm.perfil set telefone = t where lower(email) = e and telefone is null; end if;
end $$;

CREATE FUNCTION pn.painel_pre_cadastros() RETURNS TABLE(email text, nome text, cargo text, papel text, libera_agenda boolean, rodizio_ordem integer, usado_em timestamp with time zone, cadastrado boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  perform pn_crm.exige('admin');
  return query
    select pc.email, pc.nome, pc.cargo, pc.papel::text, pc.libera_agenda, pc.rodizio_ordem, pc.usado_em,
           exists (select 1 from pn_crm.perfil p where lower(p.email) = pc.email)
      from pn_crm.pre_cadastro pc order by pc.usado_em is not null, pc.nome;
end $$;

CREATE FUNCTION pn.painel_pre_cadastros_equipe() RETURNS TABLE(email text, nome text, cargo text, papel text, libera_agenda boolean, rodizio_ordem integer, usado_em timestamp with time zone, cadastrado boolean, telefone text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  perform pn_crm.exige('admin');
  return query
    select pc.email, pc.nome, pc.cargo, pc.papel::text, pc.libera_agenda, pc.rodizio_ordem, pc.usado_em,
           exists (select 1 from pn_crm.perfil p where lower(p.email) = pc.email), pc.telefone
      from pn_crm.pre_cadastro pc order by pc.usado_em is not null, pc.nome;
end $$;

CREATE FUNCTION pn.painel_profissionais() RETURNS TABLE(id uuid, nome text, tipo text, conselho text, registro text, ativo boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  perform pn_crm.exige('gestor','operacoes','comercial');
  return query
    select p.id, p.nome::text, p.tipo::text, p.conselho::text, p.registro::text, p.ativo
      from pn.profissional p order by not p.ativo, p.nome;
end $$;

CREATE FUNCTION pn.painel_registrar_acesso() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  update pn_crm.perfil set ultimo_acesso = now() where user_id = auth.uid()
$$;

CREATE FUNCTION pn.painel_relatorio_descontos(p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date) RETURNS TABLE(negocio_id uuid, numero bigint, data date, cliente text, vendedor text, etapa text, servico text, quantidade numeric, preco_catalogo numeric, preco_praticado numeric, desconto_item numeric, desconto_geral numeric, total_catalogo numeric, total_final numeric, diferenca numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('admin', 'financeiro');
  return query
    select n.id, n.numero, (n.criado_em at time zone 'America/Sao_Paulo')::date,
           coalesce(nullif(em.nome_fantasia, ''), em.razao_social, n.cliente_nome)::text,
           pv.nome::text, e.nome::text, i.descricao, i.quantidade, i.preco_catalogo, i.preco_unitario,
           i.desconto_pct, n.desconto_pct,
           round(i.quantidade * i.preco_catalogo, 2),
           round(i.total_liquido * (1 - n.desconto_pct / 100), 2),
           round(i.quantidade * i.preco_catalogo - i.total_liquido * (1 - n.desconto_pct / 100), 2)
      from pn_crm.negocio_item i
      join pn_crm.negocio n on n.id = i.negocio_id
      join pn_crm.funil f on f.id = n.funil_id and f.slug = 'comercial'
      join pn_crm.etapa e on e.id = n.etapa_id
      left join pn.empresa em on em.id = n.empresa_id
      left join pn_crm.perfil pv on pv.user_id = n.responsavel_id
     where i.preco_catalogo is not null
       and i.total_liquido * (1 - n.desconto_pct / 100) < i.quantidade * i.preco_catalogo - 0.005
       and (p_de is null or n.criado_em >= p_de::timestamp at time zone 'America/Sao_Paulo')
       and (p_ate is null or n.criado_em < (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo')
     order by n.criado_em desc, n.numero;
end $$;

CREATE FUNCTION pn.painel_relatorio_vendas(p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_responsavel uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  de date := coalesce(p_de, ((now() at time zone 'America/Sao_Paulo')::date - interval '1 year')::date);
  ate date := coalesce(p_ate, (now() at time zone 'America/Sao_Paulo')::date);
  papel text;
  resp uuid := p_responsavel;
begin
  perform pn_crm.exige('financeiro','comercial');
  papel := pn_crm.papel_atual()::text;
  if papel = 'comercial' then resp := auth.uid(); end if;

  return (
    with g as (
      select n.id, n.valor, n.fechado_em, n.responsavel_id, n.bitrix_responsavel, n.empresa_id, n.cliente_nome
        from pn_crm.negocio n
        join pn_crm.funil f on f.id = n.funil_id and f.slug = 'comercial'
        join pn_crm.etapa e on e.id = n.etapa_id and e.tipo = 'ganho'
       where n.fechado_em >= de::timestamp at time zone 'America/Sao_Paulo'
         and n.fechado_em < (ate + 1)::timestamp at time zone 'America/Sao_Paulo'
         and (resp is null or n.responsavel_id = resp)
    ), it as (
      select g.id negocio_id, coalesce(p.nome, btrim(i.descricao)) produto, i.quantidade, i.preco_unitario, i.total
        from g join pn_crm.negocio_item i on i.negocio_id = g.id
        left join pn_crm.produto p on p.id = i.produto_id
    )
    select jsonb_build_object(
      'de', de, 'ate', ate,
      'negocios', (select count(*) from g),
      'valor_negocios', (select coalesce(sum(valor), 0) from g),
      'valor_itens', (select coalesce(sum(total), 0) from it),
      'clientes', (select count(distinct coalesce(empresa_id::text, cliente_nome)) from g),
      'sem_itens', (select count(*) from g where not exists (select 1 from pn_crm.negocio_item i where i.negocio_id = g.id)),
      'produtos', coalesce((
        select jsonb_agg(x order by x.valor desc) from (
          select it.produto, count(distinct it.negocio_id) negocios, sum(it.quantidade) quantidade, sum(it.total) valor,
                 round(sum(it.total) / nullif(sum(it.quantidade), 0), 2) preco_medio,
                 min(it.preco_unitario) preco_min, max(it.preco_unitario) preco_max
            from it group by it.produto) x), '[]'::jsonb),
      'meses', coalesce((
        select jsonb_agg(x order by x.mes) from (
          select to_char(date_trunc('month', g.fechado_em at time zone 'America/Sao_Paulo'), 'YYYY-MM') mes,
                 count(*) negocios, sum(g.valor) valor
            from g group by 1) x), '[]'::jsonb),
      'responsaveis', coalesce((
        select jsonb_agg(x order by x.valor desc) from (
          select coalesce(p.nome, bu.nome, 'Sem responsável') nome, count(*) negocios, sum(g.valor) valor
            from g left join pn_crm.perfil p on p.user_id = g.responsavel_id
                   left join pn_crm.bitrix_usuario bu on bu.bitrix_id = g.bitrix_responsavel
           group by 1) x), '[]'::jsonb)
    ));
end $$;

CREATE FUNCTION pn.painel_resumo() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  r jsonb;
  clin boolean;
  papel text;
  escopo text;
  eu uuid := auth.uid();
  carteira uuid[];
begin
  perform pn_crm.exige_ativo();
  clin := pn_crm.pode_clinico();
  papel := pn_crm.papel_atual()::text;
  escopo := case when papel in ('admin', 'financeiro') then 'empresa'
                 when papel = 'comercial' then 'meus'
                 else 'nenhum' end;

  if escopo = 'meus' then
    carteira := array(
      select n.empresa_id from pn_crm.negocio n where n.responsavel_id = eu and n.empresa_id is not null
      union select c.empresa_id from pn_crm.contrato c where c.responsavel_id = eu and c.empresa_id is not null
      union select e.id from pn.empresa e where e.cadastrado_por = eu);
  end if;

  select jsonb_build_object(
    'escopo',                escopo,
    'clientes_total',        (select count(*) from pn.empresa e where escopo <> 'meus' or e.id = any (carteira)),
    'clientes_ativos',       (select count(*) from pn.empresa e where e.situacao = 'ativo' and (escopo <> 'meus' or e.id = any (carteira))),
    'clientes_sem_contrato', (select count(*) from pn.empresa e where e.situacao = 'sem_contrato' and (escopo <> 'meus' or e.id = any (carteira))),
    'clientes_inativos',     (select count(*) from pn.empresa e where e.situacao = 'inativo' and (escopo <> 'meus' or e.id = any (carteira))),
    'clientes_a_confirmar',  (select count(*) from pn.empresa e where e.situacao is null and (escopo <> 'meus' or e.id = any (carteira))),
    'unidades',              (select count(*) from pn.unidade u where escopo <> 'meus' or u.empresa_id = any (carteira)),
    'colaboradores_ativos',  (select count(*) from pn.colaborador c where c.situacao = 'ativo' and (escopo <> 'meus' or c.empresa_id = any (carteira))),
    'negocios_abertos',      case when escopo <> 'nenhum' then
                               (select count(*) from pn_crm.negocio n join pn_crm.etapa e on e.id = n.etapa_id
                                 where e.tipo = 'aberta' and (escopo = 'empresa' or n.responsavel_id = eu)) end,
    'valor_aberto_comercial',case when escopo <> 'nenhum' then
                               (select coalesce(sum(n.valor), 0) from pn_crm.negocio n
                                  join pn_crm.etapa e on e.id = n.etapa_id join pn_crm.funil f on f.id = n.funil_id
                                 where e.tipo = 'aberta' and f.slug = 'comercial' and (escopo = 'empresa' or n.responsavel_id = eu)) end,
    'ganhos_mes',            case when escopo <> 'nenhum' then
                               (select count(*) from pn_crm.negocio n join pn_crm.etapa e on e.id = n.etapa_id
                                  join pn_crm.funil f on f.id = n.funil_id
                                 where e.tipo = 'ganho' and f.slug = 'comercial' and n.fechado_em >= date_trunc('month', now())
                                   and (escopo = 'empresa' or n.responsavel_id = eu)) end,
    'valor_ganho_mes',       case when escopo <> 'nenhum' then
                               (select coalesce(sum(n.valor), 0) from pn_crm.negocio n join pn_crm.etapa e on e.id = n.etapa_id
                                  join pn_crm.funil f on f.id = n.funil_id
                                 where e.tipo = 'ganho' and f.slug = 'comercial' and n.fechado_em >= date_trunc('month', now())
                                   and (escopo = 'empresa' or n.responsavel_id = eu)) end,
    'parados',               case when escopo <> 'nenhum' then
                               (select count(*) from pn_crm.negocio n join pn_crm.etapa e on e.id = n.etapa_id
                                 where e.tipo = 'aberta' and e.alerta_dias is not null
                                   and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)
                                   and (escopo = 'empresa' or n.responsavel_id = eu)) end,
    'acesso_clinico',        clin,
    'exames_vencidos',       case when clin then (select count(*) from pn_app.vw_aso_vencimento where status = 'vencido') end,
    'exames_30_dias',        case when clin then (select count(*) from pn_app.vw_aso_vencimento where status = 'vence_em_30_dias') end,
    'exames_60_dias',        case when clin then (select count(*) from pn_app.vw_aso_vencimento where status = 'vence_em_60_dias') end,
    'atendimentos_mes',      case when clin then (select count(*) from pn.atendimento
                                                   where data_atendimento >= date_trunc('month', now())) end
  ) into r;

  r := r || jsonb_build_object('funil_comercial', case when escopo = 'nenhum' then '[]'::jsonb else coalesce((
    select jsonb_agg(jsonb_build_object('etapa', e.nome, 'cor', e.cor, 'qtd', coalesce(c.qtd, 0), 'valor', coalesce(c.valor, 0)) order by e.ordem)
      from pn_crm.etapa e join pn_crm.funil f on f.id = e.funil_id and f.slug = 'comercial'
      left join (select n.etapa_id, count(*) qtd, sum(n.valor) valor from pn_crm.negocio n
                  where escopo = 'empresa' or n.responsavel_id = eu group by 1) c on c.etapa_id = e.id
     where e.ativo and e.tipo = 'aberta'), '[]'::jsonb) end);
  return r;
end $$;

CREATE FUNCTION pn.painel_tarefa(p_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r jsonb;
begin
  perform pn_crm.exige_ativo();
  select jsonb_build_object(
    'id', t.id, 'numero', t.numero, 'quadro_id', t.quadro_id, 'titulo', t.titulo, 'status', t.status,
    'prioridade', t.prioridade, 'prazo', t.prazo, 'responsavel_id', t.responsavel_id,
    'responsavel_nome', p.nome, 'responsaveis', pn_crm.nomes_responsaveis(t.responsaveis),
    'notas', t.notas, 'empresa_id', t.empresa_id,
    'empresa', coalesce(nullif(e.nome_fantasia, ''), e.razao_social), 'negocio_id', t.negocio_id,
    'criado_por_nome', c.nome, 'criado_em', t.criado_em, 'concluida_em', t.concluida_em,
    'pode_excluir', t.criado_por = auth.uid() or t.responsavel_id = auth.uid() or pn_crm.papel_atual() in ('admin','gestor'),
    'itens', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'texto', i.texto, 'feito', i.feito) order by i.ordem)
                         from pn_crm.tarefa_item i where i.tarefa_id = t.id), '[]'::jsonb),
    'comentarios', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'texto', m.texto, 'sistema', m.sistema,
                                                               'autor', coalesce(a.nome, 'Sistema'), 'criado_em', m.criado_em)
                                              order by m.criado_em desc, m.id desc)
                               from pn_crm.tarefa_comentario m left join pn_crm.perfil a on a.user_id = m.autor_id
                              where m.tarefa_id = t.id), '[]'::jsonb))
    into r
    from pn_crm.tarefa t
    left join pn_crm.perfil p on p.user_id = t.responsavel_id
    left join pn_crm.perfil c on c.user_id = t.criado_por
    left join pn.empresa e on e.id = t.empresa_id
   where t.id = p_id and pn_crm.ve_tarefa(t.criado_por, t.responsaveis);
  if r is null then raise exception 'Tarefa não encontrada.'; end if;
  return r;
end $$;

CREATE FUNCTION pn.painel_tarefa_comentar(p_id uuid, p_texto text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; t pn_crm.tarefa; x uuid;
begin
  eu := pn_crm.exige_editor();
  if nullif(trim(p_texto), '') is null then raise exception 'Escreva o comentário.'; end if;
  select * into t from pn_crm.tarefa where id = p_id;
  if t.id is null or not pn_crm.ve_tarefa(t.criado_por, t.responsaveis) then raise exception 'Tarefa não encontrada.'; end if;
  insert into pn_crm.tarefa_comentario (tarefa_id, autor_id, texto) values (p_id, eu, trim(p_texto));
  foreach x in array t.responsaveis loop
    perform pn_crm.notificar_tarefa(x, p_id, 'comentario', 'Comentário em: ' || t.titulo);
  end loop;
  if not (t.criado_por = any (t.responsaveis)) then
    perform pn_crm.notificar_tarefa(t.criado_por, p_id, 'comentario', 'Comentário em: ' || t.titulo);
  end if;
end $$;

CREATE FUNCTION pn.painel_tarefa_excluir(p_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; t pn_crm.tarefa;
begin
  eu := pn_crm.exige_editor();
  select * into t from pn_crm.tarefa where id = p_id;
  if t.id is null then return; end if;
  if not (t.criado_por = eu or t.responsavel_id = eu or pn_crm.papel_atual() in ('admin','gestor')) then
    raise exception 'Só quem criou, o responsável ou um gestor exclui esta tarefa.' using errcode = '42501';
  end if;
  delete from pn_crm.tarefa where id = p_id;
end $$;

CREATE FUNCTION pn.painel_tarefa_item_excluir(p_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige_editor();
  delete from pn_crm.tarefa_item where id = p_id;
end $$;

CREATE FUNCTION pn.painel_tarefa_item_salvar(p_tarefa uuid, p_id uuid, p_texto text, p_feito boolean DEFAULT false) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v uuid := p_id;
begin
  perform pn_crm.exige_editor();
  if v is null then
    if nullif(trim(p_texto), '') is null then raise exception 'Escreva o item.'; end if;
    insert into pn_crm.tarefa_item (tarefa_id, texto, feito) values (p_tarefa, trim(p_texto), coalesce(p_feito, false))
    returning id into v;
  else
    update pn_crm.tarefa_item set texto = coalesce(nullif(trim(p_texto), ''), texto), feito = coalesce(p_feito, feito)
     where id = v and tarefa_id = p_tarefa;
  end if;
  update pn_crm.tarefa set atualizado_em = now() where id = p_tarefa;
  return v;
end $$;

CREATE FUNCTION pn.painel_tarefa_mover(p_id uuid, p_status text, p_ordem double precision DEFAULT NULL::double precision) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn.painel_tarefa_salvar(p_id, jsonb_build_object('status', p_status));
  if p_ordem is not null then
    update pn_crm.tarefa set ordem = p_ordem where id = p_id;
  end if;
end $$;

CREATE FUNCTION pn.painel_tarefa_quadro_arquivar(p_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor');
  update pn_crm.quadro set arquivado = true where id = p_id;
end $$;

CREATE FUNCTION pn.painel_tarefa_quadro_salvar(p_id uuid, p_nome text, p_descricao text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; v uuid := p_id;
begin
  eu := pn_crm.exige_editor();
  if nullif(trim(p_nome), '') is null then raise exception 'Informe o nome do quadro.'; end if;
  if v is null then
    insert into pn_crm.quadro (nome, descricao, ordem, criado_por)
    values (trim(p_nome), nullif(trim(p_descricao), ''), coalesce((select max(ordem) + 1 from pn_crm.quadro), 1), eu)
    returning id into v;
  else
    update pn_crm.quadro set nome = trim(p_nome), descricao = nullif(trim(p_descricao), '') where id = v;
  end if;
  return v;
end $$;

CREATE FUNCTION pn.painel_tarefa_salvar(p_id uuid, p_dados jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  eu uuid; v uuid := p_id; atual pn_crm.tarefa; novo_status text;
  novos uuid[]; antes uuid[]; x uuid; tem_resps boolean;
begin
  eu := pn_crm.exige_editor();
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
    insert into pn_crm.tarefa (quadro_id, titulo, status, prioridade, prazo, responsavel_id, responsaveis, notas, empresa_id, negocio_id,
                            criado_por, concluida_em)
    values ((p_dados->>'quadro_id')::uuid, trim(p_dados->>'titulo'),
            coalesce(nullif(p_dados->>'status', ''), 'nao_iniciado'), coalesce(nullif(p_dados->>'prioridade', ''), 'media'),
            nullif(p_dados->>'prazo', '')::date, novos[1], coalesce(novos, '{}'),
            nullif(trim(p_dados->>'notas'), ''), nullif(p_dados->>'empresa_id', '')::uuid,
            nullif(p_dados->>'negocio_id', '')::uuid, eu,
            case when p_dados->>'status' = 'feito' then now() end)
    returning id into v;
    perform pn_crm.tarefa_log(v, 'Tarefa criada');
    select * into atual from pn_crm.tarefa where id = v;
    foreach x in array atual.responsaveis loop
      perform pn_crm.notificar_tarefa(x, v, 'tarefa', 'Nova tarefa para você: ' || atual.titulo);
    end loop;
    return v;
  end if;

  select * into atual from pn_crm.tarefa where id = v for update;
  if atual.id is null or not pn_crm.ve_tarefa(atual.criado_por, atual.responsaveis) then raise exception 'Tarefa não encontrada.'; end if;
  antes := atual.responsaveis;
  if not tem_resps then novos := antes; end if;
  novo_status := coalesce(nullif(p_dados->>'status', ''), atual.status);

  update pn_crm.tarefa set
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
    perform pn_crm.tarefa_log(v, pn_crm.status_rotulo(atual.status) || ' → ' || pn_crm.status_rotulo(novo_status));
    if novo_status = 'feito' and not (atual.criado_por = any (atual.responsaveis)) then
      perform pn_crm.notificar_tarefa(atual.criado_por, v, 'tarefa', 'Concluída: ' || atual.titulo);
    end if;
  end if;
  if tem_resps and (select array_agg(y order by y) from unnest(novos) y) is distinct from (select array_agg(y order by y) from unnest(antes) y) then
    perform pn_crm.tarefa_log(v, 'Responsáveis: ' || coalesce((select string_agg(p.nome, ', ' order by array_position(novos, p.user_id))
                                                              from pn_crm.perfil p where p.user_id = any (novos)), 'ninguém'));
    foreach x in array novos loop
      if not (x = any (antes)) then
        perform pn_crm.notificar_tarefa(x, v, 'tarefa', 'Tarefa atribuída a você: ' || atual.titulo);
      end if;
    end loop;
  end if;
  if p_dados ? 'prazo' and nullif(p_dados->>'prazo', '')::date is distinct from atual.prazo then
    perform pn_crm.tarefa_log(v, 'Prazo: ' || coalesce(to_char(nullif(p_dados->>'prazo', '')::date, 'DD/MM/YYYY'), 'sem prazo'));
  end if;
  return v;
end $$;

CREATE FUNCTION pn.painel_tarefas(p_quadro uuid, p_responsavel uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text) RETURNS TABLE(id uuid, numero bigint, titulo text, status text, prioridade text, prazo date, responsavel_id uuid, responsavel_nome text, notas text, empresa_id uuid, empresa text, negocio_id uuid, ordem double precision, itens integer, itens_feitos integer, comentarios integer, atrasada boolean, criado_em timestamp with time zone, concluida_em timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  return query
    select v.id, v.numero, v.titulo, v.status, v.prioridade, v.prazo, v.responsavel_id, v.responsavel_nome, v.notas, v.empresa_id,
           v.empresa, v.negocio_id, v.ordem, v.itens, v.itens_feitos, v.comentarios, v.atrasada, v.criado_em, v.concluida_em
      from pn.painel_tarefas_v2(p_quadro, p_responsavel, p_busca) v;
end $$;

CREATE FUNCTION pn.painel_tarefas_quadros() RETURNS TABLE(id uuid, nome text, descricao text, abertas integer, atrasadas integer)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  perform pn_crm.exige_ativo();
  return query
    select q.id, q.nome, q.descricao,
           (select count(*)::int from pn_crm.tarefa t where t.quadro_id = q.id and t.status <> 'feito'
               and pn_crm.ve_tarefa(t.criado_por, t.responsaveis)),
           (select count(*)::int from pn_crm.tarefa t where t.quadro_id = q.id and t.status <> 'feito'
               and t.prazo < (now() at time zone 'America/Sao_Paulo')::date and pn_crm.ve_tarefa(t.criado_por, t.responsaveis))
      from pn_crm.quadro q where not q.arquivado order by q.ordem, q.nome;
end $$;

CREATE FUNCTION pn.painel_tarefas_v2(p_quadro uuid, p_responsavel uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text) RETURNS TABLE(id uuid, numero bigint, titulo text, status text, prioridade text, prazo date, responsavel_id uuid, responsavel_nome text, responsaveis jsonb, criado_por_nome text, notas text, empresa_id uuid, empresa text, negocio_id uuid, ordem double precision, itens integer, itens_feitos integer, comentarios integer, atrasada boolean, criado_em timestamp with time zone, concluida_em timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform pn_crm.exige_ativo();
  return query
    select t.id, t.numero, t.titulo, t.status, t.prioridade, t.prazo, t.responsavel_id, p.nome::text,
           pn_crm.nomes_responsaveis(t.responsaveis), c.nome::text,
           t.notas, t.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social)::text, t.negocio_id, t.ordem,
           (select count(*)::int from pn_crm.tarefa_item i where i.tarefa_id = t.id),
           (select count(*)::int from pn_crm.tarefa_item i where i.tarefa_id = t.id and i.feito),
           (select count(*)::int from pn_crm.tarefa_comentario m where m.tarefa_id = t.id and not m.sistema),
           t.status <> 'feito' and t.prazo < (now() at time zone 'America/Sao_Paulo')::date,
           t.criado_em, t.concluida_em
      from pn_crm.tarefa t
      left join pn_crm.perfil p on p.user_id = t.responsavel_id
      left join pn_crm.perfil c on c.user_id = t.criado_por
      left join pn.empresa e on e.id = t.empresa_id
     where t.quadro_id = p_quadro
       and pn_crm.ve_tarefa(t.criado_por, t.responsaveis)
       and (p_responsavel is null or p_responsavel = any (t.responsaveis))
       and (termo is null or t.titulo ilike '%' || termo || '%' or t.notas ilike '%' || termo || '%')
       and (t.status <> 'feito' or t.concluida_em is null or t.concluida_em > now() - interval '60 days')
     order by t.ordem;
end $$;

CREATE FUNCTION pn.painel_unidade_salvar(p_empresa uuid, p_id uuid, p_dados jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare d jsonb;
begin
  perform pn_crm.exige('gestor');
  d := pn_crm.limpar_dados(p_dados, array['nome','cnpj','cnae','grau_risco','cidade','uf','endereco','ativa','is_matriz']);
  if d ? 'nome' and d ->> 'nome' is null then raise exception 'Informe o nome da unidade.'; end if;
  if d ->> 'cnpj' is not null and length(d ->> 'cnpj') not in (11, 14) then raise exception 'CNPJ com número de dígitos inválido.'; end if;
  if d ->> 'uf' is not null and length(d ->> 'uf') <> 2 then raise exception 'UF deve ter 2 letras.'; end if;
  if p_id is null then
    if d ->> 'nome' is null then raise exception 'Informe o nome da unidade.'; end if;
    if not exists (select 1 from pn.empresa where id = p_empresa) then raise exception 'Empresa não encontrada.'; end if;
    return pn_crm.criar('unidade', d, jsonb_build_object('empresa_id', p_empresa));
  end if;
  perform pn_crm.editar('unidade', p_id, d);
  return p_id;
end $$;

CREATE FUNCTION pn.painel_usuario_admin_checar(p_user uuid, p_acao text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid; p pn_crm.perfil; ativ jsonb;
begin
  eu := pn_crm.exige('admin');
  if p_acao not in ('excluir', 'trocar_email') then raise exception 'Ação inválida.'; end if;
  select * into p from pn_crm.perfil where user_id = p_user;
  if p.user_id is null then raise exception 'Usuário não encontrado.'; end if;
  if p_user = eu then raise exception 'Você não pode fazer isso com a sua própria conta.'; end if;
  ativ := pn_crm.usuario_atividade(p_user);
  return jsonb_build_object('user_id', p.user_id, 'nome', p.nome, 'email', p.email, 'atividade', ativ,
                            'pode_excluir', (ativ - 'chat') = '{}'::jsonb);
end $$;

CREATE FUNCTION pn.painel_usuario_encaixe(p_user uuid, p_pode boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('admin');
  update pn_crm.perfil set agenda_encaixe = coalesce(p_pode, false) where user_id = p_user;
  if not found then raise exception 'Usuário não encontrado.'; end if;
end $$;

CREATE FUNCTION pn.painel_usuario_libera_agenda(p_user uuid, p_libera boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('admin');
  update pn_crm.perfil set libera_agenda = coalesce(p_libera, false) where user_id = p_user;
  if not found then raise exception 'Usuário não encontrado.'; end if;
end $$;

CREATE FUNCTION pn.painel_usuario_salvar(p_user_id uuid, p_papel text, p_ativo boolean, p_nome text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare eu uuid;
begin
  eu := pn_crm.exige('admin');
  if p_papel not in ('admin','gestor','comercial','operacoes','financeiro','leitura') then
    raise exception 'Papel inválido: %', p_papel;
  end if;
  if p_user_id = eu and (p_ativo is false or p_papel <> 'admin') then
    raise exception 'Você não pode tirar o seu próprio acesso de administrador.';
  end if;
  update pn_crm.perfil
     set papel = p_papel::pn_crm.papel,
         ativo = p_ativo,
         nome = coalesce(nullif(trim(p_nome), ''), nome),
         telefone = coalesce(p_telefone, telefone)
   where user_id = p_user_id;
  if not found then
    raise exception 'Usuário não encontrado.';
  end if;
end $$;

CREATE FUNCTION pn.painel_usuario_telefone(p_user uuid, p_telefone text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare t text := pn_crm.telefone_normalizado(p_telefone);
begin
  if p_user is distinct from auth.uid() then perform pn_crm.exige('admin'); else perform pn_crm.exige_ativo(); end if;
  if nullif(trim(coalesce(p_telefone, '')), '') is not null and t is null then
    raise exception 'Telefone inválido. Use DDD + número, ex.: (11) 99697-1631.';
  end if;
  update pn_crm.perfil set telefone = t where user_id = p_user;
  if not found then raise exception 'Usuário não encontrado.'; end if;
end $$;

CREATE FUNCTION pn.painel_usuarios() RETURNS TABLE(user_id uuid, nome text, email text, papel text, ativo boolean, telefone text, criado_em timestamp with time zone, ultimo_acesso timestamp with time zone, libera_agenda boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('admin');
  return query
    select p.user_id, p.nome, p.email, p.papel::text, p.ativo, p.telefone, p.criado_em, p.ultimo_acesso, p.libera_agenda
      from pn_crm.perfil p
     order by p.ativo, p.nome;
end $$;

CREATE FUNCTION pn.painel_usuarios_encaixe() RETURNS uuid[]
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('admin');
  return coalesce((select array_agg(user_id) from pn_crm.perfil where agenda_encaixe), '{}');
end $$;

CREATE FUNCTION pn.painel_vencimento_detalhe(p_colaborador uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r jsonb;
begin
  perform pn_crm.exige('gestor','operacoes');
  select jsonb_build_object(
           'colaborador_id', v.colaborador_id, 'colaborador', v.colaborador, 'cpf', v.cpf, 'empresa_id', v.empresa_id,
           'empresa', v.empresa, 'unidade', v.unidade, 'setor', v.setor, 'funcao', v.funcao, 'status', v.status,
           'proximo_exame', v.proximo_exame, 'ultimo_aso', v.ultimo_aso, 'tem_pcmso', v.tem_pcmso, 'calculado_em', v.calculado_em,
           'exames', coalesce((select jsonb_agg(jsonb_build_object('exame', x.exame, 'periodicidade', x.periodicidade_texto,
                                'meses', x.periodicidade_meses, 'ultima', x.ultima, 'origem', x.origem_ultima,
                                'proxima', x.proxima, 'status', x.status) order by x.proxima nulls first, x.exame)
                               from pn_app.vencimento_exame x where x.colaborador_id = v.colaborador_id), '[]'::jsonb))
    into r from pn_app.vencimento v where v.colaborador_id = p_colaborador;
  if r is null then raise exception 'Colaborador fora do cálculo de vencimentos (inativo ou de empresa inativa).'; end if;
  return r;
end $$;

CREATE FUNCTION pn.painel_vencimentos(p_empresa uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_busca text DEFAULT NULL::text, p_limite integer DEFAULT 100, p_offset integer DEFAULT 0) RETURNS TABLE(colaborador_id uuid, colaborador text, cpf text, matricula_esocial text, empresa_id uuid, empresa text, unidade text, setor text, funcao text, proximo_exame date, dias_para_vencer integer, exames_vencidos bigint, exames_nunca_feitos bigint, status text, total bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform pn_crm.exige('gestor','operacoes');
  return query
    select v.colaborador_id, v.colaborador::text, v.cpf::text, v.matricula_esocial::text, v.empresa_id, v.empresa::text,
           v.unidade::text, v.setor::text, v.funcao::text, v.proximo_exame::date, v.dias_para_vencer::int,
           v.exames_vencidos::bigint, v.exames_nunca_feitos::bigint, v.status::text,
           count(*) over ()
      from pn_app.vw_aso_vencimento v
     where (p_empresa is null or v.empresa_id = p_empresa)
       and (p_status is null or v.status = p_status)
       and (termo is null or v.colaborador ilike '%' || termo || '%' or v.cpf like '%' || termo || '%'
            or v.empresa ilike '%' || termo || '%')
     order by (v.status = 'vencido') desc, v.dias_para_vencer nulls first, v.colaborador
     limit least(greatest(p_limite, 1), 1000) offset greatest(p_offset, 0);
end $$;

CREATE FUNCTION pn.painel_wa_config_salvar(p_dados jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor');
  if p_dados ? 'inbox_url' and coalesce(p_dados->>'inbox_url', '') !~ '^https://' then
    raise exception 'O link do Inbox precisa começar com https://';
  end if;
  if nullif(p_dados->>'funil_id', '') is not null
     and not exists (select 1 from pn_crm.funil f where f.id = (p_dados->>'funil_id')::uuid and f.ativo) then
    raise exception 'Funil inválido.';
  end if;
  update pn_crm.wa_config set
    inbox_url     = coalesce(nullif(trim(p_dados->>'inbox_url'), ''), inbox_url),
    criar_negocio = coalesce((p_dados->>'criar_negocio')::boolean, criar_negocio),
    funil_id      = coalesce(nullif(p_dados->>'funil_id', '')::uuid, funil_id)
  where id;
end $$;

CREATE FUNCTION pn.painel_wa_contato_salvar(p_contato uuid, p_dados jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor','comercial','operacoes');
  update pn_crm.wa_contato set
    empresa_id = case when p_dados ? 'empresa_id' then nullif(p_dados->>'empresa_id', '')::uuid else empresa_id end,
    ignorado   = case when p_dados ? 'ignorado' then (p_dados->>'ignorado')::boolean else ignorado end,
    atualizado_em = now()
  where id = p_contato;
  if not found then raise exception 'Contato não encontrado.'; end if;

  if nullif(p_dados->>'empresa_id', '') is not null then
    update pn_crm.negocio n set empresa_id = (p_dados->>'empresa_id')::uuid, atualizado_em = now()
      from pn_crm.wa_contato w where w.id = p_contato and n.id = w.negocio_id and n.empresa_id is null;
  end if;
end $$;

CREATE FUNCTION pn.painel_wa_contatos(p_busca text DEFAULT NULL::text, p_filtro text DEFAULT NULL::text) RETURNS TABLE(id uuid, nome text, telefone text, status text, ultima_mensagem text, ultima_direcao text, ultima_em timestamp with time zone, mensagens integer, primeiro_em timestamp with time zone, ignorado boolean, ext_lead_id uuid, ext_conversa_id uuid, empresa_id uuid, empresa text, negocio_id uuid, negocio_numero bigint, negocio_etapa text, negocio_etapa_tipo text, funil_slug text, responsavel text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); dig text := pn_crm.so_digitos(p_busca);
begin
  perform pn_crm.exige('gestor','comercial','operacoes','financeiro');
  return query
    select w.id, w.nome, w.telefone, w.status, w.ultima_mensagem, w.ultima_direcao, w.ultima_em, w.mensagens, w.primeiro_em,
           w.ignorado, w.ext_lead_id, w.ext_conversa_id, w.empresa_id,
           coalesce(nullif(e.nome_fantasia, ''), e.razao_social)::text, n.id, n.numero, et.nome, et.tipo::text, f.slug, p.nome::text
      from pn_crm.wa_contato w
      left join pn.empresa e on e.id = w.empresa_id
      left join pn_crm.negocio n on n.id = w.negocio_id
      left join pn_crm.etapa et on et.id = n.etapa_id
      left join pn_crm.funil f on f.id = n.funil_id
      left join pn_crm.perfil p on p.user_id = n.responsavel_id
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

CREATE FUNCTION pn.painel_wa_contexto(p_negocio uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige_ativo();
  return jsonb_build_object(
    'inbox_url', (select inbox_url from pn_crm.wa_config where id),
    'atendente', (select p.nome from pn_crm.perfil p where p.user_id = auth.uid()),
    'contato', (select jsonb_build_object('id', w.id, 'nome', w.nome, 'telefone', w.telefone,
                                          'ext_lead_id', w.ext_lead_id, 'ext_conversa_id', w.ext_conversa_id)
                  from pn_crm.wa_contato w where p_negocio is not null and w.negocio_id = p_negocio limit 1));
end $$;

CREATE FUNCTION pn.painel_wa_criar_negocio(p_contato uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare f uuid;
begin
  select coalesce(funil_id, (select id from pn_crm.funil where slug = 'comercial')) into f from pn_crm.wa_config where id;
  perform pn_crm.exige_operar(f);
  if (select ignorado from pn_crm.wa_contato where id = p_contato) then
    update pn_crm.wa_contato set ignorado = false where id = p_contato;
  end if;
  return pn_crm.wa_abrir_negocio(p_contato);
end $$;

CREATE FUNCTION pn.painel_wa_historico(p_busca text DEFAULT NULL::text, p_empresa uuid DEFAULT NULL::uuid, p_telefone text DEFAULT NULL::text, p_limite integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE(chat_id bigint, nome text, telefone text, empresa_id uuid, empresa text, negocio_id uuid, negocio_numero bigint, iniciada_em timestamp with time zone, ultima_em timestamp with time zone, mensagens integer, ultima_texto text, total bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); fim text := right(pn_crm.so_digitos(p_telefone), 8);
begin
  perform pn_crm.exige('gestor','comercial','operacoes','financeiro');
  return query
    select c.chat_id, c.nome, c.telefone, c.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social), c.negocio_id, n.numero,
           c.iniciada_em, c.ultima_em, c.mensagens, c.ultima_texto, count(*) over ()
      from pn_crm.wa_historico_conversa c
      left join pn.empresa e on e.id = c.empresa_id
      left join pn_crm.negocio n on n.id = c.negocio_id
     where c.mensagens > 0
       and (p_empresa is null or c.empresa_id = p_empresa)
       and (fim is null or length(fim) < 8 or right(c.telefone, 8) = fim)
       and (termo is null or c.nome ilike '%' || termo || '%' or c.telefone like '%' || pn_crm.so_digitos(termo) || '%'
            or e.razao_social ilike '%' || termo || '%' or e.nome_fantasia ilike '%' || termo || '%'
            or exists (select 1 from pn_crm.wa_historico_msg m where m.chat_id = c.chat_id and m.texto ilike '%' || termo || '%'))
     order by c.ultima_em desc nulls last
     limit least(greatest(p_limite, 1), 200) offset greatest(p_offset, 0);
end $$;

CREATE FUNCTION pn.painel_wa_historico_mensagens(p_chat bigint) RETURNS TABLE(id bigint, em timestamp with time zone, quem text, autor text, texto text, arquivos text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  perform pn_crm.exige('gestor','comercial','operacoes','financeiro');
  return query select m.id, m.em, m.quem, m.autor, m.texto, m.arquivos from pn_crm.wa_historico_msg m
                where m.chat_id = p_chat order by m.em, m.id;
end $$;

CREATE FUNCTION pn.painel_wa_modelo_excluir(p_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform pn_crm.exige('gestor');
  delete from pn_crm.wa_modelo where id = p_id;
end $$;

CREATE FUNCTION pn.painel_wa_modelo_salvar(p_id uuid, p_dados jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v uuid := p_id;
begin
  perform pn_crm.exige('gestor');
  if nullif(trim(p_dados->>'titulo'), '') is null or nullif(trim(p_dados->>'texto'), '') is null then
    raise exception 'Preencha o título e o texto.';
  end if;
  if coalesce(p_dados->>'categoria', 'geral') not in ('geral','comercial','agendamento','exames','cobranca','documentos') then
    raise exception 'Categoria inválida.';
  end if;
  if v is null then
    insert into pn_crm.wa_modelo (titulo, categoria, texto, ordem)
    values (trim(p_dados->>'titulo'), coalesce(p_dados->>'categoria', 'geral'), trim(p_dados->>'texto'),
            coalesce((select max(ordem) + 1 from pn_crm.wa_modelo), 1))
    returning id into v;
  else
    update pn_crm.wa_modelo set titulo = trim(p_dados->>'titulo'), categoria = coalesce(p_dados->>'categoria', categoria),
           texto = trim(p_dados->>'texto'), ativo = coalesce((p_dados->>'ativo')::boolean, ativo), atualizado_em = now()
     where id = v;
    if not found then raise exception 'Modelo não encontrado.'; end if;
  end if;
  return v;
end $$;

CREATE FUNCTION pn.painel_wa_modelos() RETURNS TABLE(id uuid, titulo text, categoria text, texto text, ativo boolean, ordem integer)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_column
begin
  perform pn_crm.exige_ativo();
  return query select m.id, m.titulo, m.categoria, m.texto, m.ativo, m.ordem from pn_crm.wa_modelo m order by m.ordem, m.titulo;
end $$;

CREATE FUNCTION pn.painel_wa_resumo() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare cfg pn_crm.wa_config; papel pn_crm.papel;
begin
  perform pn_crm.exige('gestor','comercial','operacoes','financeiro');
  select * into cfg from pn_crm.wa_config where id;
  papel := pn_crm.papel_atual();
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
    'funil_nome', (select f.nome from pn_crm.funil f where f.id = cfg.funil_id),
    'pode_configurar', papel in ('admin','gestor'),
    'pode_criar_negocio', pn_crm.pode_operar(cfg.funil_id))
    from pn_crm.wa_contato);
end $$;

CREATE FUNCTION pn.painel_wa_token_gerar() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare t text := 'vitalis_wa_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  perform pn_crm.exige('gestor');
  update pn_crm.wa_config set token_hash = encode(extensions.digest(t, 'sha256'), 'hex'), token_gerado_em = now() where id;
  return t;
end $$;

CREATE FUNCTION pn.sesmo_excluir_chave(p_modulo text, p_chave text, p_motivo text, p_evidencia jsonb DEFAULT '{}'::jsonb) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'pn_sesmo', 'pn'
    AS $$
  with ins as (
    insert into pn_sesmo.fila_excluida (modulo, chave, motivo, evidencia)
    values (p_modulo, p_chave, 'auto: ' || p_motivo,
            coalesce(p_evidencia, '{}'::jsonb) || jsonb_build_object('auto', true, 'em', now()))
    on conflict (modulo, chave) do nothing
    returning 1
  )
  select exists (select 1 from ins);
$$;

CREATE FUNCTION pn.sesmo_pendentes(p_modulo text, p_limite integer DEFAULT 200) RETURNS TABLE(chave text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pn_sesmo', 'pn', 'pg_catalog'
    AS $$
declare v_pai text; v_pais text[]; v_campo_pai text; v_com_pai boolean;
begin

  if exists (select 1 from pn_sesmo.fila_chave f where f.modulo = p_modulo) then
    return query
      select f.chave
      from pn_sesmo.fila_chave f
      where f.modulo = p_modulo
        and not exists (select 1 from pn_sesmo.captura x
                        where x.modulo = p_modulo and x.chave = f.chave)
        and not exists (select 1 from pn_sesmo.fila_excluida e
                        where e.modulo = p_modulo and e.chave = f.chave)
      limit p_limite;
    return;
  end if;

  select f.fonte_pai, coalesce(f.fontes_pai, array[f.fonte_pai]), coalesce(f.chave_com_pai, false)
    into v_pai, v_pais, v_com_pai
  from pn_sesmo.fonte f where f.modulo = p_modulo and f.ativo;
  if v_pai is null then raise exception 'modulo % nao tem fila configurada', p_modulo; end if;

  select f.campo_filhos into v_campo_pai from pn_sesmo.fonte f where f.modulo = v_pai;

  if v_campo_pai is null then
    return query
      select distinct c.chave
      from pn_sesmo.captura c
      where c.modulo = any(v_pais)
        and not exists (select 1 from pn_sesmo.captura x
                        where x.modulo = p_modulo and x.chave = c.chave)
        and not exists (select 1 from pn_sesmo.fila_excluida e
                        where e.modulo = p_modulo and e.chave = c.chave)
      limit p_limite;

  elsif v_com_pai then
    return query
      select c.chave || ':' || coalesce(y->>'id', y->>'Id')
      from pn_sesmo.captura c
      cross join lateral jsonb_array_elements(coalesce(c.conteudo -> v_campo_pai, '[]'::jsonb)) y
      where c.modulo = any(v_pais) and coalesce(y->>'id', y->>'Id') is not null
        and not exists (select 1 from pn_sesmo.captura x
                        where x.modulo = p_modulo
                          and x.chave = c.chave || ':' || coalesce(y->>'id', y->>'Id'))
        and not exists (select 1 from pn_sesmo.fila_excluida e
                        where e.modulo = p_modulo
                          and e.chave = c.chave || ':' || coalesce(y->>'id', y->>'Id'))
      group by 1 limit p_limite;

  else
    return query
      select coalesce(y->>'id', y->>'Id')
      from pn_sesmo.captura c
      cross join lateral jsonb_array_elements(coalesce(c.conteudo -> v_campo_pai, '[]'::jsonb)) y
      where c.modulo = any(v_pais) and coalesce(y->>'id', y->>'Id') is not null
        and not exists (select 1 from pn_sesmo.captura x
                        where x.modulo = p_modulo and x.chave = coalesce(y->>'id', y->>'Id'))
        and not exists (select 1 from pn_sesmo.fila_excluida e
                        where e.modulo = p_modulo and e.chave = coalesce(y->>'id', y->>'Id'))
      group by 1 limit p_limite;
  end if;
end $$;

CREATE FUNCTION pn_sesmo.corrigir(p text) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pn_sesmo', 'pg_catalog'
    AS $$
declare r record; t text := p;
begin
  if t is null or position(chr(65533) in t) = 0 then
    return t;
  end if;
  for r in select de, para from pn_sesmo.correcao_texto loop
    t := replace(t, r.de, r.para);
  end loop;
  return t;
end $$;

CREATE FUNCTION pn_sesmo.enriquecer_colaboradores(p_min bigint DEFAULT 0, p_max bigint DEFAULT '9223372036854775807'::bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare n int;
begin
  with d as (
    select u.chave, u.conteudo c
      from pn_sesmo.ultimas('colaborador_detalhe') u
     where u.chave ~ '^[0-9]+$' and u.chave::bigint between p_min and p_max
  ), v as (
    select d.chave,
           pn_sesmo.ts_br(d.c->>'dataNasc')::date nasc,
           case d.c->>'sexo' when '1' then 'M' when '0' then 'F' end sexo,
           pn_sesmo.corrigir(nullif(btrim(d.c->>'nomeMae'), '')) mae,
           coalesce(nullif(btrim(d.c->>'celular'), ''), nullif(btrim(d.c->>'telefone'), '')) tel,
           lower(nullif(btrim(d.c->>'email'), '')) email,
           nullif(concat_ws('/', nullif(btrim(d.c->>'ctps'), ''), nullif(btrim(d.c->>'ctpsSerie'), '')), '') ctps,
           nullif(btrim(d.c->>'rgOrgaoSigla'), '') orgao
      from d
  )
  update pn.colaborador t set
    data_nascimento = coalesce(v.nasc, t.data_nascimento),
    sexo = coalesce(v.sexo, t.sexo),
    nome_mae = coalesce(v.mae, t.nome_mae),
    telefone = coalesce(v.tel, t.telefone),
    email = coalesce(v.email, t.email),
    ctps = coalesce(v.ctps, t.ctps),
    rg_orgao_emissor = coalesce(v.orgao, t.rg_orgao_emissor)
    from v
   where t.sesmo_id = v.chave
     and (t.data_nascimento is distinct from coalesce(v.nasc, t.data_nascimento)
          or t.sexo is distinct from coalesce(v.sexo, t.sexo)
          or t.nome_mae is distinct from coalesce(v.mae, t.nome_mae)
          or t.telefone is distinct from coalesce(v.tel, t.telefone)
          or t.email is distinct from coalesce(v.email, t.email)
          or t.ctps is distinct from coalesce(v.ctps, t.ctps)
          or t.rg_orgao_emissor is distinct from coalesce(v.orgao, t.rg_orgao_emissor));
  get diagnostics n = row_count;
  return jsonb_build_object('colaboradores_enriquecidos', n, 'de', p_min, 'ate', p_max);
end $_$;

CREATE FUNCTION pn_sesmo.fila_materializar(p_modulo text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pn_sesmo', 'pn', 'pg_catalog'
    AS $$
declare v_pai text; v_pais text[]; v_campo_pai text; v_com_pai boolean; v_campo_chave text; n bigint;
begin
  select f.fonte_pai, coalesce(f.fontes_pai, array[f.fonte_pai]),
         coalesce(f.chave_com_pai, false), f.campo_chave_pai
    into v_pai, v_pais, v_com_pai, v_campo_chave
  from pn_sesmo.fonte f where f.modulo = p_modulo;
  if v_pai is null then raise exception 'modulo % nao tem fila configurada', p_modulo; end if;

  select f.campo_filhos into v_campo_pai from pn_sesmo.fonte f where f.modulo = v_pai;

  delete from pn_sesmo.fila_chave where modulo = p_modulo;

  if v_campo_chave is not null then
    insert into pn_sesmo.fila_chave (modulo, chave)
      select distinct p_modulo, c.conteudo ->> v_campo_chave
      from pn_sesmo.captura c
      where c.modulo = any(v_pais)
        and nullif(c.conteudo ->> v_campo_chave, '') is not null
        and c.conteudo ->> v_campo_chave <> '0';

  elsif v_campo_pai is null then
    insert into pn_sesmo.fila_chave (modulo, chave)
      select distinct p_modulo, c.chave
      from pn_sesmo.captura c where c.modulo = any(v_pais);

  elsif v_com_pai then
    insert into pn_sesmo.fila_chave (modulo, chave)
      select distinct p_modulo, c.chave || ':' || coalesce(y->>'id', y->>'Id')
      from pn_sesmo.captura c
      cross join lateral jsonb_array_elements(coalesce(c.conteudo -> v_campo_pai, '[]'::jsonb)) y
      where c.modulo = any(v_pais) and coalesce(y->>'id', y->>'Id') is not null;

  else
    insert into pn_sesmo.fila_chave (modulo, chave)
      select distinct p_modulo, coalesce(y->>'id', y->>'Id')
      from pn_sesmo.captura c
      cross join lateral jsonb_array_elements(coalesce(c.conteudo -> v_campo_pai, '[]'::jsonb)) y
      where c.modulo = any(v_pais) and coalesce(y->>'id', y->>'Id') is not null;
  end if;

  get diagnostics n = row_count;
  return n;
end $$;

CREATE FUNCTION pn_sesmo.itens_estrutura(p_ativos text, p_inativos text, p_lista text) RETURNS TABLE(pai text, item jsonb)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select distinct on (f.pai, f.item ->> 'id') f.pai, f.item
    from (
      select u.chave pai, x.item, 1 prioridade from pn_sesmo.ultimas(p_ativos) u, jsonb_array_elements(u.conteudo -> p_lista) x(item)
      union all
      select u.chave, x.item, 2 from pn_sesmo.ultimas(p_inativos) u, jsonb_array_elements(u.conteudo -> p_lista) x(item)
    ) f
   order by f.pai, f.item ->> 'id', f.prioridade
$$;

CREATE FUNCTION pn_sesmo.mapa_unidade_empresa() RETURNS TABLE(unidade_sesmo text, empresa_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select distinct on (x->>'unidadeId') x->>'unidadeId', e.id
    from pn_sesmo.ultimas('cargos') v, jsonb_array_elements(v.conteudo->'cargos') x
    join pn.empresa e on e.sesmo_id = x->>'clienteId'
   order by x->>'unidadeId'
$$;

CREATE FUNCTION pn_sesmo.normalizar_atendimentos(p_min bigint DEFAULT 0, p_max bigint DEFAULT '9223372036854775807'::bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare n_col int; n_at int; n_fono int;
begin
  create temp table if not exists _mapa_ue on commit drop as select * from pn_sesmo.mapa_unidade_empresa();
  create temp table _at on commit drop as
    select u.chave::bigint id, u.conteudo c,
           coalesce(m.empresa_id, un.empresa_id) empresa_id, un.id unidade_id,
           to_date(u.conteudo->>'Data', 'DD/MM/YYYY') dia
      from pn_sesmo.ultimas('atendimentos') u
      left join _mapa_ue m on m.unidade_sesmo = u.conteudo->>'UnidadeId'
      left join pn.unidade un on un.sesmo_id = u.conteudo->>'UnidadeId'
     where u.chave ~ '^[0-9]+$' and u.chave::bigint between p_min and p_max;

  insert into pn.colaborador (empresa_id, sesmo_id, nome, nome_social, cpf, situacao, sesmo_situacao_codigo, origem, extraido_em)
  select distinct on (a.empresa_id, a.c->>'IdColaborador')
         a.empresa_id, a.c->>'IdColaborador',
         pn_sesmo.corrigir(btrim(coalesce(l.conteudo->>'nome', a.c->>'NomeColaborador'))),
         nullif(btrim(a.c->>'NomeSocial'), ''), nullif(pn_app.digits(l.conteudo->>'cpfCnpj'), ''),
         'inativo', 'sem_vinculo', 'sesmo_robo', now()
    from _at a
    left join pn_sesmo.captura l on l.modulo = 'colaboradores' and l.chave = a.c->>'IdColaborador'
   where a.empresa_id is not null and nullif(a.c->>'IdColaborador', '') is not null
     and not exists (select 1 from pn.colaborador x where x.empresa_id = a.empresa_id and x.sesmo_id = a.c->>'IdColaborador')
  on conflict (empresa_id, sesmo_id) do nothing;
  get diagnostics n_col = row_count;

  insert into pn.atendimento as t (sesmo_id, empresa_id, unidade_id, colaborador_id, profissional_id, tipo,
                                       data_agendada, data_atendimento, situacao, sesmo_status_codigo,
                                       local_atendimento, origem, extraido_em)
  select a.id::text, a.empresa_id, a.unidade_id, col.id, p.id,
         (case lower(pn_sesmo.corrigir(btrim(a.c->>'TipoOcupacional')))
            when 'admissional' then 'admissional' when 'periódico' then 'periodico' when 'demissional' then 'demissional'
            when 'retorno ao trabalho' then 'retorno_ao_trabalho'
            when 'mudança de riscos ocupacionais' then 'mudanca_de_funcao'
            else 'monitoracao_pontual' end)::pn.tipo_exame_ocupacional,
         (a.dia + coalesce(nullif(a.c->>'Hora', ''), '00:00')::time) at time zone 'America/Sao_Paulo',
         a.dia,
         (case when (a.c->>'IsFinalizado')::boolean then 'finalizado'
               when a.c->>'Status' = '1' then 'agendado'
               when a.c->>'Status' = '3' then 'atendido'
               when a.c->>'Status' = '7' then 'cancelado'
               else 'agendado' end)::pn.situacao_atendimento,
         a.c->>'Status', 'clinica', 'sesmo_robo', now()
    from _at a
    join pn.colaborador col on col.empresa_id = a.empresa_id and col.sesmo_id = a.c->>'IdColaborador'
    left join pn.profissional p on lower(p.nome) = lower(pn_sesmo.corrigir(btrim(a.c->>'Medico')))
   where coalesce(a.c->>'TipoAtendimento', 'Ocupacional') <> 'Fonoaudiologico' and a.dia is not null
  on conflict (empresa_id, sesmo_id) do update set
    unidade_id = excluded.unidade_id, colaborador_id = excluded.colaborador_id, profissional_id = excluded.profissional_id,
    tipo = excluded.tipo, data_agendada = excluded.data_agendada, data_atendimento = excluded.data_atendimento,
    situacao = excluded.situacao, sesmo_status_codigo = excluded.sesmo_status_codigo,
    extraido_em = excluded.extraido_em, updated_at = now();
  get diagnostics n_at = row_count;

  insert into pn.atendimento_exame (atendimento_id, exame_tipo_id, data_realizacao, resultado)
  select distinct on (oc.id) oc.id,
         (select et.id from pn.exame_tipo et where et.nome = 'Audiometria Ocupacional' limit 1),
         a.dia, 'pendente'
    from _at a
    join pn.colaborador col on col.empresa_id = a.empresa_id and col.sesmo_id = a.c->>'IdColaborador'
    join pn.atendimento oc on oc.colaborador_id = col.id and oc.data_atendimento = a.dia
   where a.c->>'TipoAtendimento' = 'Fonoaudiologico'
     and not exists (select 1 from pn.atendimento_exame ae join pn.exame_tipo et on et.id = ae.exame_tipo_id
                      where ae.atendimento_id = oc.id and et.nome = 'Audiometria Ocupacional')
   order by oc.id;
  get diagnostics n_fono = row_count;

  drop table _at;
  return jsonb_build_object('colaboradores_sem_vinculo', n_col, 'atendimentos', n_at, 'audiometrias', n_fono,
                            'de', p_min, 'ate', p_max);
end $_$;

CREATE FUNCTION pn_sesmo.normalizar_atendimentos_por_cargo() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare n_at int; n_sem int;
begin
  create temp table _ue on commit drop as select * from pn_sesmo.mapa_unidade_empresa();
  create temp table _apc on commit drop as
    select distinct on (e->>'IdAtendimento') (e->>'IdAtendimento') id, e c,
           coalesce(m.empresa_id, un.empresa_id) empresa_id, un.id unidade_id,
           to_date(e->>'Data', 'DD/MM/YYYY') dia
      from pn_sesmo.ultimas('atendimento_por_cargo') u
      cross join lateral jsonb_array_elements(u.conteudo->'atendimentos') e
      left join _ue m on m.unidade_sesmo = e->>'UnidadeId'
      left join pn.unidade un on un.sesmo_id = e->>'UnidadeId'
     where coalesce(e->>'TipoAtendimento', 'Ocupacional') <> 'Fonoaudiologico'
       and e->>'Data' ~ '^\d\d/\d\d/\d{4}$' and nullif(e->>'IdAtendimento', '') is not null
     order by e->>'IdAtendimento', u.captura_id desc;

  insert into pn.atendimento (sesmo_id, empresa_id, unidade_id, colaborador_id, tipo,
                                  data_agendada, data_atendimento, situacao, sesmo_status_codigo,
                                  local_atendimento, origem, extraido_em)
  select a.id, a.empresa_id, a.unidade_id, col.id,
         (case lower(pn_sesmo.corrigir(btrim(a.c->>'TipoOcupacional')))
            when 'admissional' then 'admissional' when 'periódico' then 'periodico' when 'demissional' then 'demissional'
            when 'retorno ao trabalho' then 'retorno_ao_trabalho'
            when 'mudança de riscos ocupacionais' then 'mudanca_de_funcao'
            else 'monitoracao_pontual' end)::pn.tipo_exame_ocupacional,
         (a.dia + coalesce(nullif(a.c->>'Hora', ''), '00:00')::time) at time zone 'America/Sao_Paulo',
         a.dia,
         (case when (a.c->>'IsFinalizado')::boolean then 'finalizado'
               when (a.c->>'IsAtendido')::boolean then 'atendido'
               when a.c->>'StatusAgenda' = '7' then 'cancelado'
               else 'agendado' end)::pn.situacao_atendimento,
         a.c->>'StatusAgenda', 'clinica', 'sesmo_robo', now()
    from _apc a
    join pn.colaborador col on col.empresa_id = a.empresa_id and col.sesmo_id = a.c->>'IdColaborador'
  on conflict (empresa_id, sesmo_id) do nothing;
  get diagnostics n_at = row_count;

  select count(*) into n_sem from _apc a
   where not exists (select 1 from pn.colaborador col where col.empresa_id = a.empresa_id and col.sesmo_id = a.c->>'IdColaborador');

  drop table _apc; drop table _ue;
  return jsonb_build_object('atendimentos_novos', n_at, 'sem_colaborador_ou_empresa', n_sem);
end $_$;

CREATE FUNCTION pn_sesmo.normalizar_atividades() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare n_func int; n_col int; r jsonb;
begin

  drop table if exists _ev;
  create temp table _ev on commit drop as
  select l.chave,
         l.conteudo->>'IdUnidade' uni,
         lower(btrim(l.conteudo->>'NomeSetor')) setor,
         lower(regexp_replace(btrim(l.conteudo->>'NomeCargo'), '\s+', ' ', 'g')) func,
         (l.conteudo->>'IdEvento')::bigint eid,
         regexp_replace(coalesce(l.conteudo->>'CpfFuncionario', ''), '\D', '', 'g') cpf,
         left(regexp_replace(coalesce(l.conteudo->>'CnpjUnidade', ''), '\D', '', 'g'), 8) raiz,
         d.dsc
    from pn_sesmo.ultimas('esocial_evento_lista') l
    join lateral (select nullif(btrim(x.conteudo->'evento'->>'dscAtividade'), '') dsc
                    from pn_sesmo.captura x
                   where x.modulo = 'esocial_evento' and x.chave = l.chave
                   order by x.id desc limit 1) d on true
   where l.chave like 'S2240:%' and d.dsc is not null;
  create index on _ev (uni, setor, func);
  analyze _ev;

  drop table if exists _fx;
  create temp table _fx on commit drop as
  select distinct on (f.id) f.id funcao_id, ev.dsc
    from pn.funcao f
    join pn.setor s on s.id = f.setor_id
    join pn.unidade u on u.id = s.unidade_id
    join _ev ev on ev.uni = u.sesmo_id
               and ev.setor = lower(btrim(s.nome))
               and ev.func = lower(regexp_replace(btrim(f.nome), '\s+', ' ', 'g'))
   order by f.id, ev.eid desc;
  update pn.funcao f set descricao_atividades = x.dsc, descricao_atividades_origem = 'esocial_s2240'
    from _fx x
   where f.id = x.funcao_id
     and coalesce(f.descricao_atividades_origem, 'esocial_s2240') = 'esocial_s2240'
     and f.descricao_atividades is distinct from x.dsc;
  select count(*) into n_func from pn.funcao where descricao_atividades is not null;

  drop table if exists _cd;
  create temp table _cd on commit drop as
  with col as (
    select c.id, c.funcao_id, c.cpf, c.cbo_codigo,
           lower(regexp_replace(btrim(coalesce(c.funcao_nome, c.cargo_nome)), '\s+', ' ', 'g')) func,
           left(regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g'), 8) raiz
      from pn.colaborador c join pn.empresa e on e.id = c.empresa_id and e.situacao = 'ativo'
     where c.situacao = 'ativo'
  ), proprio as (
    select distinct on (cpf, raiz) cpf, raiz, dsc from _ev where cpf <> '' order by cpf, raiz, eid desc
  ), nome_emp as (
    select distinct on (raiz, func) raiz, func, dsc from _ev order by raiz, func, eid desc
  ), por_cbo as (
    select distinct on (cbo_codigo) cbo_codigo, descricao_atividades dsc
      from (select cbo_codigo, descricao_atividades, count(*) n from pn.funcao
             where cbo_codigo is not null and descricao_atividades is not null
             group by 1, 2) z
     order by cbo_codigo, n desc, descricao_atividades
  )
  select col.id,
         coalesce(f.descricao_atividades, p.dsc, ne.dsc, pc.dsc) dsc,
         case when f.descricao_atividades is not null then 'funcao'
              when p.dsc is not null then 'evento_do_colaborador'
              when ne.dsc is not null then 'funcao_mesmo_nome_empresa'
              when pc.dsc is not null then 'referencia_cbo' end origem
    from col
    left join pn.funcao f on f.id = col.funcao_id
    left join proprio p on p.cpf = col.cpf and p.raiz = col.raiz
    left join nome_emp ne on ne.raiz = col.raiz and ne.func = col.func
    left join por_cbo pc on pc.cbo_codigo = col.cbo_codigo;

  update pn.colaborador c set descricao_atividades = d.dsc, descricao_atividades_origem = d.origem
    from _cd d
   where c.id = d.id
     and (c.descricao_atividades, c.descricao_atividades_origem) is distinct from (d.dsc, d.origem);

  select jsonb_object_agg(coalesce(origem, 'sem_descricao'), n) into r
    from (select c.descricao_atividades_origem origem, count(*) n
            from pn.colaborador c join pn.empresa e on e.id = c.empresa_id and e.situacao = 'ativo'
           where c.situacao = 'ativo' group by 1) z;
  return jsonb_build_object('eventos_s2240_com_descricao', (select count(*) from _ev),
                            'funcoes_com_descricao', n_func,
                            'ativos_empresas_ativas_por_origem', r);
end $$;

CREATE FUNCTION pn_sesmo.normalizar_catalogos() RETURNS TABLE(tabela text, gravados integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pn', 'pn_sesmo', 'pg_catalog'
    AS $$
declare v int;
begin
  with g as (
    insert into epi (sesmo_id, nome, ca, descricao, ativo)
    select u.chave,
           coalesce(nullif(btrim(u.conteudo->>'descricao'),''), '(sem nome)'),
           nullif(u.conteudo->>'caEpi',''),
           nullif(btrim(u.conteudo->>'observacao'),''),
           not coalesce((u.conteudo->>'isInativo')::boolean, false)
    from pn_sesmo.ultimas('epi') u
    on conflict (sesmo_id) do update set
      nome = excluded.nome, ca = coalesce(excluded.ca, epi.ca),
      descricao = coalesce(excluded.descricao, epi.descricao), ativo = excluded.ativo
    returning 1
  ) select count(*) into v from g;
  tabela := 'epi'; gravados := v; return next;

  with g as (
    insert into epc (sesmo_id, nome, descricao, ativo)
    select u.chave,
           coalesce(nullif(btrim(u.conteudo->>'descricao'),''), '(sem nome)'),
           nullif(btrim(u.conteudo->>'observacao'),''),
           not coalesce((u.conteudo->>'isInativo')::boolean, false)
    from pn_sesmo.ultimas('epc') u
    on conflict (sesmo_id) do update set
      nome = excluded.nome, descricao = coalesce(excluded.descricao, epc.descricao),
      ativo = excluded.ativo
    returning 1
  ) select count(*) into v from g;
  tabela := 'epc'; gravados := v; return next;

  with g as (
    insert into exame_tipo (sesmo_id, nome, ativo)
    select u.chave,
           coalesce(nullif(btrim(u.conteudo->>'descricao'),''), '(sem nome)'),
           not coalesce((u.conteudo->>'isInativo')::boolean, false)
    from pn_sesmo.ultimas('exame_tipo') u
    on conflict (sesmo_id) do update set
      nome = excluded.nome, ativo = excluded.ativo
    returning 1
  ) select count(*) into v from g;
  tabela := 'exame_tipo'; gravados := v; return next;

  with g as (
    insert into vacina (sesmo_id, nome, doses, ativo)
    select u.chave,
           coalesce(nullif(btrim(u.conteudo->>'descricao'),''), '(sem nome)'),
           nullif(u.conteudo->>'numeroDoses','')::int,
           not coalesce((u.conteudo->>'isInativo')::boolean, false)
    from pn_sesmo.ultimas('vacina') u
    on conflict (sesmo_id) do update set
      nome = excluded.nome, doses = coalesce(excluded.doses, vacina.doses),
      ativo = excluded.ativo
    returning 1
  ) select count(*) into v from g;
  tabela := 'vacina'; gravados := v; return next;

  with g as (
    insert into profissional (
      sesmo_id, nome, conselho, registro, uf_registro, cpf,
      especializacao, identificador, sesmo_tipo_codigo, sesmo_situacao_codigo
    )
    select u.chave,
           coalesce(nullif(btrim(u.conteudo->>'nome'),''), '(sem nome)'),
           nullif(u.conteudo->>'conselhoSigla',''),
           nullif(u.conteudo->>'conselhoNumero',''),
           nullif(u.conteudo->>'conselhoUF',''),
           pn_app.digits(u.conteudo->>'cpfCnpj'),
           nullif(btrim(u.conteudo->>'especializacao'),''),
           nullif(u.conteudo->>'identificador',''),
           nullif(u.conteudo->>'tipoProfissional','')::int,
           nullif(u.conteudo->>'situacao','')::int
    from pn_sesmo.ultimas('profissionais') u
    on conflict (sesmo_id) do update set
      nome = excluded.nome,
      conselho = coalesce(excluded.conselho, profissional.conselho),
      registro = coalesce(excluded.registro, profissional.registro),
      uf_registro = coalesce(excluded.uf_registro, profissional.uf_registro),
      cpf = coalesce(excluded.cpf, profissional.cpf),
      especializacao = coalesce(excluded.especializacao, profissional.especializacao),
      identificador = coalesce(excluded.identificador, profissional.identificador),
      sesmo_tipo_codigo = coalesce(excluded.sesmo_tipo_codigo, profissional.sesmo_tipo_codigo),
      sesmo_situacao_codigo = coalesce(excluded.sesmo_situacao_codigo, profissional.sesmo_situacao_codigo)
    returning 1
  ) select count(*) into v from g;
  tabela := 'profissional'; gravados := v; return next;
end $$;

CREATE FUNCTION pn_sesmo.normalizar_clientes() RETURNS TABLE(inseridos integer, atualizados integer, ignorados integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pn', 'pn_sesmo', 'pg_catalog'
    AS $$
declare
  v_ins int := 0; v_upd int := 0; v_ign int := 0;
  r record; v_id uuid; v_novo boolean;
begin
  for r in
    select c.id as captura_id, c.chave, c.conteudo, c.url
    from pn_sesmo.captura c
    where c.modulo = 'clientes' and c.processado_em is null
    order by c.id
  loop
    if r.conteudo->>'id' is null or coalesce(r.conteudo->>'razaoSocial','') = '' then
      v_ign := v_ign + 1;
      update pn_sesmo.captura set processado_em = now(), erro = 'sem id ou razaoSocial'
      where id = r.captura_id;
      continue;
    end if;

    select destino_id into v_id from pn_sesmo.mapeamento
    where entidade='empresa' and sesmo_id = r.conteudo->>'id' and contexto='';
    v_novo := v_id is null;

    if v_novo then
      insert into empresa (
        sesmo_id, razao_social, nome_fantasia, cnpj, sesmo_situacao_codigo,
        origem, extraido_em, sesmo_usuario_cadastro, sesmo_data_cadastro,
        sesmo_usuario_alteracao, sesmo_data_alteracao
      ) values (
        r.conteudo->>'id', r.conteudo->>'razaoSocial',
        nullif(r.conteudo->>'nome',''), pn_app.digits(r.conteudo->>'cpfCnpj'),
        nullif(r.conteudo->>'situacao','')::int, 'sesmo_exportacao', now(),
        nullif(r.conteudo->>'usuarioCadastro',''),
        nullif(r.conteudo->>'dataCadastroDateTime','')::timestamptz,
        nullif(r.conteudo->>'usuarioAlteracao',''),
        nullif(r.conteudo->>'dataAlteracaoDateTime','')::timestamptz
      ) returning id into v_id;
      insert into pn_sesmo.mapeamento (entidade, sesmo_id, destino_id, contexto)
      values ('empresa', r.conteudo->>'id', v_id, '');
      v_ins := v_ins + 1;
    else
      update empresa set
        razao_social            = r.conteudo->>'razaoSocial',
        nome_fantasia           = coalesce(nullif(r.conteudo->>'nome',''), nome_fantasia),
        cnpj                    = coalesce(pn_app.digits(r.conteudo->>'cpfCnpj'), cnpj),
        sesmo_situacao_codigo   = coalesce(nullif(r.conteudo->>'situacao','')::int, sesmo_situacao_codigo),
        extraido_em             = now(),
        sesmo_usuario_alteracao = coalesce(nullif(r.conteudo->>'usuarioAlteracao',''), sesmo_usuario_alteracao),
        sesmo_data_alteracao    = coalesce(nullif(r.conteudo->>'dataAlteracaoDateTime','')::timestamptz, sesmo_data_alteracao)
      where id = v_id;
      v_upd := v_upd + 1;
    end if;

    update pn_sesmo.captura set processado_em = now(), erro = null where id = r.captura_id;
  end loop;

  return query select v_ins, v_upd, v_ign;
end $$;

CREATE FUNCTION pn_sesmo.normalizar_colaboradores(p_min bigint DEFAULT 0, p_max bigint DEFAULT '9223372036854775807'::bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare n int;
begin
  with lst as (
    select u.chave::bigint id, u.conteudo c
      from pn_sesmo.ultimas('colaboradores') u
     where u.chave ~ '^[0-9]+$' and u.chave::bigint between p_min and p_max
  ), vin as (
    select v.chave::bigint col, x
      from pn_sesmo.ultimas('cargos') v, jsonb_array_elements(v.conteudo->'cargos') x
     where v.chave ~ '^[0-9]+$' and v.chave::bigint between p_min and p_max
  ), escolhido as (
    select distinct on (vin.col, e.id)
           vin.col, e.id empresa_id, un.id unidade_id,
           pn_sesmo.ts_br(vin.x->>'dataAdmissao')::date adm,
           pn_sesmo.ts_br(vin.x->>'dataDemissao')::date dem,
           vin.x->>'situacao' sit,
           nullif(btrim(vin.x->>'setorNome'), '') setor_nome,
           nullif(btrim(vin.x->>'nome'), '') funcao_nome
      from vin
      join pn.empresa e on e.sesmo_id = vin.x->>'clienteId'
      left join pn.unidade un on un.empresa_id = e.id and un.sesmo_id = vin.x->>'unidadeId'
     order by vin.col, e.id,
              (vin.x->>'situacao' = '2' and nullif(vin.x->>'dataDemissao', '') is null) desc,
              pn_sesmo.ts_br(vin.x->>'dataAdmissao') desc nulls last, (vin.x->>'id')::bigint desc
  ), completo as (
    select es.*, st.id setor_id,
           (select f.id from pn.funcao f
             where f.setor_id = st.id and lower(btrim(f.nome)) = lower(es.funcao_nome)
             order by f.sesmo_situacao_codigo desc nulls last limit 1) funcao_id
      from escolhido es
      left join lateral (select s.id from pn.setor s
                          where s.unidade_id = es.unidade_id and lower(btrim(s.nome)) = lower(es.setor_nome)
                          order by s.sesmo_situacao_codigo desc nulls last limit 1) st on true
  )
  insert into pn.colaborador as t (empresa_id, unidade_id, sesmo_id, nome, nome_social, cpf, rg, pis,
                                       data_admissao, data_demissao, situacao, sesmo_situacao_codigo,
                                       setor_nome, funcao_nome, setor_id, funcao_id, origem, extraido_em)
  select es.empresa_id, es.unidade_id, lst.id::text,
         pn_sesmo.corrigir(btrim(lst.c->>'nome')), nullif(btrim(lst.c->>'nomeSocial'), ''),
         nullif(pn_app.digits(lst.c->>'cpfCnpj'), ''), nullif(btrim(lst.c->>'rg'), ''), nullif(pn_app.digits(lst.c->>'pisPasepCi'), ''),
         es.adm, es.dem,
         (case when es.dem is not null and es.dem <= current_date then 'desligado'
               when es.sit = '2' then 'ativo'
               else 'inativo' end)::pn.situacao_colaborador,
         es.sit, pn_sesmo.corrigir(es.setor_nome), pn_sesmo.corrigir(es.funcao_nome), es.setor_id, es.funcao_id, 'sesmo_robo', now()
    from completo es join lst on lst.id = es.col
   where nullif(btrim(lst.c->>'nome'), '') is not null and btrim(lst.c->>'nome') <> '0'
  on conflict (empresa_id, sesmo_id) do update set
    unidade_id = excluded.unidade_id, nome = excluded.nome, nome_social = excluded.nome_social,
    cpf = excluded.cpf, rg = excluded.rg, pis = coalesce(excluded.pis, t.pis),
    data_admissao = excluded.data_admissao, data_demissao = excluded.data_demissao,
    situacao = excluded.situacao, sesmo_situacao_codigo = excluded.sesmo_situacao_codigo,
    setor_nome = excluded.setor_nome, funcao_nome = excluded.funcao_nome,
    setor_id = excluded.setor_id, funcao_id = excluded.funcao_id,
    extraido_em = excluded.extraido_em, updated_at = now();
  get diagnostics n = row_count;
  return jsonb_build_object('colaboradores', n, 'de', p_min, 'ate', p_max);
end $_$;

CREATE FUNCTION pn_sesmo.normalizar_empresas_situacao() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare n int;
begin
  with s as (
    select c.chave::text chave, nullif(c.conteudo ->> 'situacao', '')::int cod,
           (case c.conteudo ->> 'situacao' when '2' then 'ativo' when '1' then 'inativo' end)::pn.situacao_empresa sit
      from pn_sesmo.ultimas('clientes') c
  )
  update pn.empresa e
     set sesmo_situacao_codigo = s.cod, situacao = coalesce(s.sit, e.situacao)
    from s
   where s.chave = e.sesmo_id
     and (e.sesmo_situacao_codigo is distinct from s.cod or e.situacao is distinct from coalesce(s.sit, e.situacao));
  get diagnostics n = row_count;
  return jsonb_build_object('empresas_atualizadas', n);
end $$;

CREATE FUNCTION pn_sesmo.normalizar_funcao_exames() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare n int; d int;
begin
  create temp table _fe_src on commit drop as
    select distinct on (chave) chave, exames from (
      select u.chave, u.captura_id, u.conteudo -> 'exames' exames from pn_sesmo.ultimas('funcao_exames') u
      union all
      select u.chave, u.captura_id, u.conteudo -> 'compl' -> 'Data' from pn_sesmo.ultimas('funcao_medicina') u
       where jsonb_typeof(u.conteudo -> 'compl' -> 'Data') = 'array'
    ) s order by chave, captura_id desc;

  create temp table _fe_v on commit drop as
    select f.id funcao_id, x ->> 'Id' sesmo_id,
           btrim(regexp_replace(x ->> 'Descricao', '^\s*\d+\s*-\s*', '')) nome,
           nullif(substring(x ->> 'Descricao' from '^\s*(\d+)'), '') codigo,
           lower(coalesce(x -> 'lstFaixas' -> 0 ->> 'Periodicidade', '')) per, x
      from _fe_src s
      join pn.funcao f on f.sesmo_id = s.chave
      cross join lateral jsonb_array_elements(s.exames) x;

  delete from pn.funcao_exame t
   using pn.funcao f, _fe_src s
   where f.id = t.funcao_id and s.chave = f.sesmo_id
     and not exists (select 1 from _fe_v v where v.funcao_id = t.funcao_id and v.sesmo_id = t.sesmo_id and v.nome <> '');
  get diagnostics d = row_count;

  insert into pn.funcao_exame as t (funcao_id, sesmo_id, exame_tipo_id, exame_nome, exame_codigo, obrigatorio, ocupacional,
        no_admissional, no_periodico, no_demissional, no_mudanca_funcao, no_retorno,
        periodicidade_texto, periodicidade_meses, primeira_meses, sesmo_data_alteracao)
  select v.funcao_id, v.sesmo_id,
         (select et.id from pn.exame_tipo et where lower(et.nome) = lower(v.nome) order by length(et.sesmo_id), et.sesmo_id limit 1),
         pn_sesmo.corrigir(v.nome), v.codigo,
         coalesce(v.x ->> 'ExameAso', '') ilike 'obrigat%',
         coalesce((v.x ->> 'IsExameOcupacional')::boolean, true),
         v.x ->> 'IsAdmissional' = 'x', v.x ->> 'IsPeriodico' = 'x', v.x ->> 'IsDemissional' = 'x',
         v.x ->> 'IsMudancaFuncao' = 'x', v.x ->> 'IsRetornoTrabalho' = 'x',
         nullif(v.per, ''),
         case when v.per ~ '(\d+)\s*/\s*(\d+)' then (regexp_match(v.per, '(\d+)\s*/\s*(\d+)'))[2]::int
              when v.per ~ '\d+' then (regexp_match(v.per, '(\d+)'))[1]::int end,
         case when v.per ~ '(\d+)\s*/\s*(\d+)' then (regexp_match(v.per, '(\d+)\s*/\s*(\d+)'))[1]::int end,
         pn_sesmo.ts_br(v.x ->> 'DataAlteracao')
    from _fe_v v
   where v.nome <> ''
  on conflict (funcao_id, sesmo_id) do update set
    exame_tipo_id = excluded.exame_tipo_id, exame_nome = excluded.exame_nome, exame_codigo = excluded.exame_codigo,
    obrigatorio = excluded.obrigatorio, ocupacional = excluded.ocupacional,
    no_admissional = excluded.no_admissional, no_periodico = excluded.no_periodico, no_demissional = excluded.no_demissional,
    no_mudanca_funcao = excluded.no_mudanca_funcao, no_retorno = excluded.no_retorno,
    periodicidade_texto = excluded.periodicidade_texto, periodicidade_meses = excluded.periodicidade_meses,
    primeira_meses = excluded.primeira_meses, sesmo_data_alteracao = excluded.sesmo_data_alteracao;
  get diagnostics n = row_count;
  drop table _fe_v; drop table _fe_src;
  return jsonb_build_object('exames_por_funcao', n, 'removidos', d,
                            'funcoes_com_pcmso', (select count(distinct funcao_id) from pn.funcao_exame));
end $$;

CREATE FUNCTION pn_sesmo.normalizar_funcoes() RETURNS TABLE(gravadas integer, sem_setor integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pn', 'pn_sesmo', 'pg_catalog'
    AS $$
declare v_ok int := 0; v_orfa int := 0;
begin
  with fonte as (select * from pn_sesmo.itens_estrutura('funcoes', 'funcoes_inativas', 'funcoes')),
  gravadas as (
    insert into funcao (setor_id, sesmo_id, nome, descricao_atividades, quantidade_expostos, identificador,
                        data_inicio_condicao, data_inicio_periodo_esocial, sesmo_situacao_codigo, sesmo_usuario_cadastro,
                        sesmo_data_cadastro, sesmo_usuario_alteracao, sesmo_data_alteracao)
    select m.destino_id, f.item->>'id', coalesce(nullif(btrim(f.item->>'nome'),''), '(sem nome)'),
           nullif(btrim(f.item->>'atividade'),''), nullif(f.item->>'numeroFuncionario','')::int, nullif(f.item->>'idenficador',''),
           pn_sesmo.ts_br(f.item->>'dataInicioCondicao')::date, pn_sesmo.ts_br(f.item->>'dataInicioPeriodoEsocial')::date,
           nullif(f.item->>'situacao','')::int, nullif(f.item->>'usuarioCadastro',''), pn_sesmo.ts_br(f.item->>'dataCadastro'),
           nullif(f.item->>'usuarioAlteracao',''), pn_sesmo.ts_br(f.item->>'dataAlteracao')
      from fonte f
      join pn_sesmo.mapeamento m on m.entidade = 'setor' and m.contexto = '' and m.sesmo_id = f.pai
    on conflict (setor_id, sesmo_id) do update set
      nome = excluded.nome,
      descricao_atividades = coalesce(excluded.descricao_atividades, funcao.descricao_atividades),
      quantidade_expostos = coalesce(excluded.quantidade_expostos, funcao.quantidade_expostos),
      identificador = coalesce(excluded.identificador, funcao.identificador),
      data_inicio_condicao = coalesce(excluded.data_inicio_condicao, funcao.data_inicio_condicao),
      data_inicio_periodo_esocial = coalesce(excluded.data_inicio_periodo_esocial, funcao.data_inicio_periodo_esocial),
      sesmo_situacao_codigo = coalesce(excluded.sesmo_situacao_codigo, funcao.sesmo_situacao_codigo),
      sesmo_usuario_alteracao = coalesce(excluded.sesmo_usuario_alteracao, funcao.sesmo_usuario_alteracao),
      sesmo_data_alteracao = coalesce(excluded.sesmo_data_alteracao, funcao.sesmo_data_alteracao)
    returning 1)
  select count(*) into v_ok from gravadas;

  select count(*) into v_orfa from pn_sesmo.itens_estrutura('funcoes', 'funcoes_inativas', 'funcoes') f
   where not exists (select 1 from pn_sesmo.mapeamento m where m.entidade='setor' and m.contexto='' and m.sesmo_id = f.pai);

  insert into pn_sesmo.mapeamento (entidade, sesmo_id, destino_id, contexto)
  select 'funcao', sesmo_id, id, '' from funcao where sesmo_id is not null
  on conflict (entidade, sesmo_id, contexto) do nothing;
  return query select v_ok, v_orfa;
end $$;

CREATE FUNCTION pn_sesmo.normalizar_setores() RETURNS TABLE(gravados integer, sem_unidade integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pn', 'pn_sesmo', 'pg_catalog'
    AS $$
declare v_ok int := 0; v_orfa int := 0;
begin
  with fonte as (select * from pn_sesmo.itens_estrutura('setores', 'setores_inativos', 'setores')),
  gravados as (
    insert into setor (unidade_id, sesmo_id, nome, tipo_setor, id_esocial, controla_esocial, sesmo_situacao_codigo,
                       sesmo_usuario_cadastro, sesmo_data_cadastro, sesmo_usuario_alteracao, sesmo_data_alteracao)
    select m.destino_id, f.item->>'id', coalesce(nullif(btrim(f.item->>'nome'),''), '(sem nome)'),
           nullif(f.item->>'tipoSetor',''), nullif(f.item->>'idEsocial',''), (f.item->>'isEsocial')::boolean,
           nullif(f.item->>'situacao','')::int, nullif(f.item->>'usuarioCadastro',''), pn_sesmo.ts_br(f.item->>'dataCadastro'),
           nullif(f.item->>'usuarioAlteracao',''), pn_sesmo.ts_br(f.item->>'dataAlteracao')
      from fonte f
      join pn_sesmo.mapeamento m on m.entidade = 'unidade' and m.contexto = '' and m.sesmo_id = f.pai
    on conflict (unidade_id, sesmo_id) do update set
      nome = excluded.nome, tipo_setor = coalesce(excluded.tipo_setor, setor.tipo_setor),
      id_esocial = coalesce(excluded.id_esocial, setor.id_esocial), controla_esocial = excluded.controla_esocial,
      sesmo_situacao_codigo = coalesce(excluded.sesmo_situacao_codigo, setor.sesmo_situacao_codigo),
      sesmo_usuario_alteracao = coalesce(excluded.sesmo_usuario_alteracao, setor.sesmo_usuario_alteracao),
      sesmo_data_alteracao = coalesce(excluded.sesmo_data_alteracao, setor.sesmo_data_alteracao)
    returning 1)
  select count(*) into v_ok from gravados;

  select count(*) into v_orfa from pn_sesmo.itens_estrutura('setores', 'setores_inativos', 'setores') f
   where not exists (select 1 from pn_sesmo.mapeamento m where m.entidade='unidade' and m.contexto='' and m.sesmo_id = f.pai);

  insert into pn_sesmo.mapeamento (entidade, sesmo_id, destino_id, contexto)
  select 'setor', sesmo_id, id, '' from setor where sesmo_id is not null
  on conflict (entidade, sesmo_id, contexto) do nothing;
  return query select v_ok, v_orfa;
end $$;

CREATE FUNCTION pn_sesmo.normalizar_sgg(p_etapa integer DEFAULT 0) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  n_cargos int; n_func int; n_funcid int; n_colcbo int; n_ficha int; n_nat int; n_matr int; n_pis int; n_rest int;
begin

  if p_etapa in (0, 1) then

  drop table if exists _fc;
  create temp table _fc on commit drop as
  select f.id funcao_id, e->>'Id' sesmo_id,
         pn_sesmo.corrigir(nullif(btrim(e->>'NomeCargo'), '')) nome,
         nullif(btrim(e->>'Atividade'), '') atividade,
         nullif(regexp_replace(coalesce(e->>'CodigoCbo', ''), '\D', '', 'g'), '') cbo,
         (e->>'IsPrincipal')::boolean principal, g.k grade, e->>'Situacao' sit,
         case when e->>'NumeroFuncionario' ~ '^\d+$' then (e->>'NumeroFuncionario')::int end nfunc
    from pn_sesmo.ultimas('funcao_cargo') u
    join pn.funcao f on f.sesmo_id = u.chave
   cross join lateral (values ('ativos'), ('inativos')) g(k)
   cross join lateral jsonb_array_elements(coalesce(u.conteudo->g.k->'Data', '[]'::jsonb)) e
   where e->>'Id' is not null;

  insert into pn.cbo (codigo) select distinct cbo from _fc where cbo ~ '^\d{6}$'
  on conflict (codigo) do nothing;

  insert into pn.funcao_cargo as t (funcao_id, sesmo_id, nome, atividade, cbo_codigo, principal,
                                        situacao, sesmo_situacao_codigo, numero_funcionarios, extraido_em)
  select distinct on (sesmo_id) funcao_id, sesmo_id, nome, atividade,
         case when cbo ~ '^\d{6}$' then cbo end, principal,
         case grade when 'ativos' then 'ativo' else 'inativo' end, sit, nfunc, now()
    from _fc order by sesmo_id, (grade = 'ativos') desc
  on conflict (sesmo_id) do update set
    funcao_id = excluded.funcao_id, nome = excluded.nome, atividade = excluded.atividade,
    cbo_codigo = excluded.cbo_codigo, principal = excluded.principal, situacao = excluded.situacao,
    sesmo_situacao_codigo = excluded.sesmo_situacao_codigo,
    numero_funcionarios = excluded.numero_funcionarios, extraido_em = excluded.extraido_em;
  delete from pn.funcao_cargo t where not exists (select 1 from _fc where _fc.sesmo_id = t.sesmo_id);
  select count(*) into n_cargos from pn.funcao_cargo;

  drop table if exists _fesc;
  create temp table _fesc on commit drop as
  select distinct on (funcao_id) funcao_id, cbo_codigo, nome
    from pn.funcao_cargo where cbo_codigo is not null
   order by funcao_id, (situacao = 'ativo') desc, principal desc nulls last,
            numero_funcionarios desc nulls last, sesmo_id;
  update pn.funcao f set cbo_codigo = x.cbo_codigo
    from _fesc x where f.id = x.funcao_id and f.cbo_codigo is distinct from x.cbo_codigo;
  select count(*) into n_func from pn.funcao where cbo_codigo is not null;

  end if;

  if p_etapa in (0, 2) then
  drop table if exists _fesc;
  create temp table _fesc on commit drop as
  select distinct on (funcao_id) funcao_id, cbo_codigo, nome
    from pn.funcao_cargo where cbo_codigo is not null
   order by funcao_id, (situacao = 'ativo') desc, principal desc nulls last,
            numero_funcionarios desc nulls last, sesmo_id;

  drop table if exists _fe;
  create temp table _fe on commit drop as
  select u.empresa_id, lower(regexp_replace(btrim(f.nome), '\s+', ' ', 'g')) nome, f.id funcao_id,
         lower(btrim(s.nome)) setor
    from pn.funcao f join pn.setor s on s.id = f.setor_id join pn.unidade u on u.id = s.unidade_id;
  create index on _fe (empresa_id, nome);
  analyze _fe;
  with cand as (
    select c.id, fe.funcao_id, (fe.setor = lower(btrim(c.setor_nome))) mesmo_setor
      from pn.colaborador c
      join _fe fe on fe.empresa_id = c.empresa_id
                 and fe.nome = lower(regexp_replace(btrim(c.funcao_nome), '\s+', ' ', 'g'))
     where c.funcao_id is null and c.funcao_nome is not null
  ), esc as (
    select id,
           case when count(distinct funcao_id) filter (where mesmo_setor) = 1
                  then (array_agg(funcao_id) filter (where mesmo_setor))[1]
                when count(distinct funcao_id) = 1 then (array_agg(funcao_id))[1] end funcao_id
      from cand group by id
  )
  update pn.colaborador c set funcao_id = esc.funcao_id
    from esc where c.id = esc.id and esc.funcao_id is not null;
  get diagnostics n_funcid = row_count;

  update pn.colaborador c set cbo_codigo = x.cbo_codigo, cargo_nome = x.nome, cbo_origem = 'cargo_da_funcao'
    from _fesc x
   where c.funcao_id = x.funcao_id
     and (c.cbo_codigo, c.cargo_nome, c.cbo_origem) is distinct from (x.cbo_codigo, x.nome, 'cargo_da_funcao');
  select count(*) into n_colcbo from pn.colaborador where cbo_origem = 'cargo_da_funcao';

  update pn.colaborador set cbo_origem = null where cbo_origem = 'sem_cbo';
  end if;

  if p_etapa in (0, 5) then

  drop table if exists _sem;
  create temp table _sem on commit drop as
  select c.id from pn.colaborador c join pn.empresa e on e.id = c.empresa_id and e.situacao = 'ativo'
   where c.situacao = 'ativo' and c.cbo_codigo is null and c.cbo_origem is null
   order by c.id limit 400;
  drop table if exists _fi;
  create temp table _fi on commit drop as
  with at as (
    select a.colaborador_id, a.sesmo_id, coalesce(a.data_atendimento, a.data_agendada::date) d
      from pn.atendimento a join _sem on _sem.id = a.colaborador_id where a.sesmo_id is not null
  ), k as materialized (
    select x.id, split_part(x.chave, ':', 1) atend from pn_sesmo.captura x where x.modulo = 'anamnese_conteudo'
  ), m as materialized (
    select at.colaborador_id, at.d, k.id from at join k on k.atend = at.sesmo_id
  ), v as materialized (
    select m.colaborador_id, m.d, m.id,
           regexp_replace(coalesce(y.conteudo->'retorno'->>'codigoCbo', ''), '\D', '', 'g') cbo,
           pn_sesmo.corrigir(nullif(btrim(y.conteudo->'retorno'->>'NomeCargo'), '')) cargo
      from m join pn_sesmo.captura y on y.id = m.id
  )
  select distinct on (colaborador_id) colaborador_id, cbo, cargo
    from v where cbo ~ '^\d{6}$' order by colaborador_id, d desc nulls last, id desc;
  insert into pn.cbo (codigo) select distinct cbo from _fi on conflict (codigo) do nothing;
  update pn.colaborador c set cbo_codigo = fi.cbo, cargo_nome = fi.cargo, cbo_origem = 'ficha_clinica'
    from _fi fi where c.id = fi.colaborador_id;
  update pn.colaborador c set cbo_origem = 'sem_cbo'
   where c.id in (select id from _sem) and not exists (select 1 from _fi where _fi.colaborador_id = c.id);
  select count(*) into n_ficha from pn.colaborador where cbo_origem = 'ficha_clinica';
  select count(*) into n_rest from pn.colaborador c join pn.empresa e on e.id = c.empresa_id and e.situacao = 'ativo'
   where c.situacao = 'ativo' and c.cbo_codigo is null and c.cbo_origem is null;

  end if;

  if p_etapa in (0, 3) then

  update pn.empresa e set natureza_juridica = n.conteudo->>'codigo',
                              natureza_juridica_descricao = n.conteudo->>'descricao'
    from pn_sesmo.ultimas('cliente_detalhe') d
    join pn_sesmo.ultimas('natureza_juridica') n on n.chave = d.conteudo->>'naturezaId'
   where e.sesmo_id = d.chave
     and (e.natureza_juridica, e.natureza_juridica_descricao)
         is distinct from (n.conteudo->>'codigo', n.conteudo->>'descricao');
  select count(*) into n_nat from pn.empresa where natureza_juridica is not null;

  end if;

  if p_etapa in (0, 4) then

  drop table if exists _ev;
  create temp table _ev on commit drop as
  select regexp_replace(coalesce(u.conteudo->'evento'->>'cpfColaborador', ''), '\D', '', 'g') cpf,
         left(regexp_replace(coalesce(u.conteudo->'evento'->>'numInscEmpregador', ''), '\D', '', 'g'), 8) raiz,
         nullif(btrim(u.conteudo->'evento'->>'matricula'), '') matr,
         nullif(regexp_replace(coalesce(u.conteudo->'evento'->>'pisColaborador', ''), '\D', '', 'g'), '') pis,
         (u.conteudo->'evento'->>'id')::bigint eid
    from pn_sesmo.ultimas('esocial_evento') u;

  update pn.colaborador c set matricula_esocial = m.matr
    from pn.empresa e,
         (select distinct on (cpf, raiz) cpf, raiz, matr from _ev
           where cpf <> '' and matr is not null and matr <> '0' order by cpf, raiz, eid desc) m
   where e.id = c.empresa_id and m.cpf = c.cpf
     and m.raiz = left(regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g'), 8)
     and c.matricula_esocial is distinct from m.matr;
  select count(*) into n_matr from pn.colaborador where matricula_esocial is not null;

  update pn.colaborador c set pis = p.pis
    from (select distinct on (cpf) cpf, pis from _ev
           where cpf <> '' and pis ~ '^\d{11}$' and pis !~ '^0+$' order by cpf, eid desc) p
   where c.cpf = p.cpf and (c.pis is null or c.pis ~ '^0+$');
  get diagnostics n_pis = row_count;
  end if;

  return jsonb_strip_nulls(jsonb_build_object('etapa', p_etapa, 'funcao_cargo', n_cargos, 'funcoes_com_cbo', n_func,
    'funcao_id_preenchidos', n_funcid, 'colaboradores_cbo_pela_funcao', n_colcbo,
    'colaboradores_cbo_pela_ficha', n_ficha, 'empresas_com_natureza', n_nat,
    'colaboradores_com_matricula', n_matr, 'pis_preenchidos', n_pis, 'restantes', n_rest));
end $_$;

CREATE FUNCTION pn_sesmo.normalizar_trilha_a() RETURNS TABLE(etapa text, gravados integer, orfaos integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pn', 'pn_sesmo', 'pg_catalog'
    AS $$
declare a int; b int; c int; r record;
begin

  select * into a, b, c from pn_sesmo.normalizar_clientes();
  etapa := 'clientes';  gravados := coalesce(a,0) + coalesce(b,0);  orfaos := coalesce(c,0);  return next;

  select * into a, b from pn_sesmo.normalizar_unidades();
  etapa := 'unidades';  gravados := a;  orfaos := b;  return next;

  select * into a, b from pn_sesmo.normalizar_setores();
  etapa := 'setores';   gravados := a;  orfaos := b;  return next;

  select * into a, b from pn_sesmo.normalizar_funcoes();
  etapa := 'funcoes';   gravados := a;  orfaos := b;  return next;

  for r in select * from pn_sesmo.normalizar_catalogos() loop
    etapa := r.tabela;  gravados := r.gravados;  orfaos := 0;  return next;
  end loop;
end $$;

CREATE FUNCTION pn_sesmo.normalizar_unidades() RETURNS TABLE(gravadas integer, sem_empresa integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pn', 'pn_sesmo', 'pg_catalog'
    AS $$
declare v_ok int := 0; v_orfa int := 0;
begin
  with fonte as (select * from pn_sesmo.itens_estrutura('unidades', 'unidades_inativas', 'unidades')),
  gravadas as (
    insert into unidade (
      empresa_id, sesmo_id, nome, cnpj, cnae, grau_risco, cnae_secundario, cep, telefone, identificador,
      is_matriz, tem_dir, tem_tac, ativa, sesmo_situacao_codigo, sesmo_usuario_cadastro, sesmo_data_cadastro,
      sesmo_usuario_alteracao, sesmo_data_alteracao)
    select m.destino_id, f.item->>'id',
           coalesce(nullif(btrim(f.item->>'nome'),''), f.item->>'razaoSocial', '(sem nome)'),
           pn_app.digits(f.item->>'cpfCnpj'), nullif(f.item->>'cnaeCodigoCnae',''), nullif(f.item->>'cnaeGrauRisco','')::int,
           nullif(f.item->>'cnaeSecundarioCodigoCnae',''), pn_app.digits(f.item->>'cep1'), nullif(f.item->>'telefone',''),
           nullif(f.item->>'identificador',''), (f.item->>'matriz') = 'Sim',
           (f.item->>'isPossuiDirAtiva')::boolean, (f.item->>'isPossuiTacAtiva')::boolean,
           coalesce(nullif(f.item->>'situacao','')::int, 2) <> 1,
           nullif(f.item->>'situacao','')::int, nullif(f.item->>'usuarioCadastro',''), pn_sesmo.ts_br(f.item->>'dataCadastro'),
           nullif(f.item->>'usuarioAlteracao',''), pn_sesmo.ts_br(f.item->>'dataAlteracao')
      from fonte f
      join pn_sesmo.mapeamento m on m.entidade = 'empresa' and m.contexto = '' and m.sesmo_id = f.pai
    on conflict (empresa_id, sesmo_id) do update set
      nome = excluded.nome, cnpj = coalesce(excluded.cnpj, unidade.cnpj), cnae = coalesce(excluded.cnae, unidade.cnae),
      grau_risco = coalesce(excluded.grau_risco, unidade.grau_risco),
      cnae_secundario = coalesce(excluded.cnae_secundario, unidade.cnae_secundario),
      cep = coalesce(excluded.cep, unidade.cep), telefone = coalesce(excluded.telefone, unidade.telefone),
      identificador = coalesce(excluded.identificador, unidade.identificador),
      is_matriz = excluded.is_matriz, tem_dir = excluded.tem_dir, tem_tac = excluded.tem_tac, ativa = excluded.ativa,
      sesmo_situacao_codigo = coalesce(excluded.sesmo_situacao_codigo, unidade.sesmo_situacao_codigo),
      sesmo_usuario_alteracao = coalesce(excluded.sesmo_usuario_alteracao, unidade.sesmo_usuario_alteracao),
      sesmo_data_alteracao = coalesce(excluded.sesmo_data_alteracao, unidade.sesmo_data_alteracao)
    returning 1)
  select count(*) into v_ok from gravadas;

  select count(*) into v_orfa from pn_sesmo.itens_estrutura('unidades', 'unidades_inativas', 'unidades') f
   where not exists (select 1 from pn_sesmo.mapeamento m where m.entidade='empresa' and m.contexto='' and m.sesmo_id = f.pai);

  insert into pn_sesmo.mapeamento (entidade, sesmo_id, destino_id, contexto)
  select 'unidade', sesmo_id, id, '' from unidade where sesmo_id is not null
  on conflict (entidade, sesmo_id, contexto) do nothing;
  return query select v_ok, v_orfa;
end $$;

CREATE FUNCTION pn_sesmo.ts_br(p text) RETURNS timestamp with time zone
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
declare t text := btrim(coalesce(p, ''));
begin
  if t = '' or t like '0001-01-01%' or t like '01/01/0001%' then
    return null;
  end if;
  if t ~ '^\d{4}-\d{2}-\d{2}' then
    begin return t::timestamptz; exception when others then return null; end;
  end if;
  if t ~ '^\d{2}/\d{2}/\d{4} \d{2}:\d{2}' then
    begin return to_timestamp(t, 'DD/MM/YYYY HH24:MI:SS'); exception when others then return null; end;
  end if;
  if t ~ '^\d{2}/\d{2}/\d{4}$' then
    begin return to_timestamp(t, 'DD/MM/YYYY'); exception when others then return null; end;
  end if;
  return null;
end $_$;

CREATE FUNCTION pn_sesmo.ultimas(p_modulo text) RETURNS TABLE(captura_id bigint, chave text, conteudo jsonb)
    LANGUAGE sql STABLE
    AS $$
  select distinct on (c.chave) c.id, c.chave, c.conteudo
  from pn_sesmo.captura c
  where c.modulo = p_modulo and c.conteudo is not null
  order by c.chave, c.id desc
$$;

SET default_tablespace = '';

SET default_table_access_method = heap;

CREATE TABLE pn_app.vencimento (
    colaborador_id uuid NOT NULL,
    colaborador text,
    cpf text,
    matricula_esocial text,
    empresa_id uuid,
    empresa text,
    unidade text,
    setor text,
    funcao text,
    proximo_exame date,
    dias_para_vencer integer,
    exames_vencidos bigint,
    exames_nunca_feitos bigint,
    status text,
    ultimo_aso date,
    tem_pcmso boolean,
    calculado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE pn_app.vencimento_exame (
    colaborador_id uuid NOT NULL,
    exame text NOT NULL,
    exame_tipo_id uuid,
    periodicidade_meses integer NOT NULL,
    periodicidade_texto text,
    ultima date,
    origem_ultima text,
    proxima date,
    status text NOT NULL
);

CREATE VIEW pn_app.vw_aso_vencimento AS
 SELECT colaborador_id,
    colaborador,
    cpf,
    matricula_esocial,
    empresa_id,
    empresa,
    unidade,
    setor,
    funcao,
    proximo_exame,
    dias_para_vencer,
    exames_vencidos,
    exames_nunca_feitos,
    status
   FROM pn_app.vencimento;

CREATE TABLE pn.colaborador (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    unidade_id uuid,
    sesmo_id text,
    nome text NOT NULL,
    nome_social text,
    cpf text,
    rg text,
    rg_orgao_emissor text,
    data_nascimento date,
    sexo text,
    nome_mae text,
    pis text,
    matricula_esocial text,
    ctps text,
    data_admissao date,
    data_demissao date,
    situacao pn.situacao_colaborador DEFAULT 'ativo'::pn.situacao_colaborador NOT NULL,
    telefone text,
    email text,
    origem pn.origem_registro DEFAULT 'sesmo_robo'::pn.origem_registro NOT NULL,
    extraido_em timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    sesmo_usuario_cadastro text,
    sesmo_data_cadastro timestamp with time zone,
    sesmo_usuario_alteracao text,
    sesmo_data_alteracao timestamp with time zone,
    sesmo_situacao_codigo text,
    campos_editados text[] DEFAULT '{}'::text[] NOT NULL,
    setor_nome text,
    funcao_nome text,
    setor_id uuid,
    funcao_id uuid,
    cbo_codigo text,
    cargo_nome text,
    cbo_origem text,
    descricao_atividades text,
    descricao_atividades_origem text
);

ALTER TABLE ONLY pn.colaborador FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.empresa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sesmo_id text,
    razao_social text NOT NULL,
    nome_fantasia text,
    cnpj text,
    situacao pn.situacao_empresa DEFAULT 'ativo'::pn.situacao_empresa NOT NULL,
    cnae_principal text,
    grau_risco integer,
    cidade text,
    uf text,
    cep text,
    logradouro text,
    numero text,
    complemento text,
    bairro text,
    telefone text,
    email text,
    contrato_inicio date,
    contrato_fim date,
    origem pn.origem_registro DEFAULT 'sesmo_exportacao'::pn.origem_registro NOT NULL,
    extraido_em timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    sesmo_usuario_cadastro text,
    sesmo_data_cadastro timestamp with time zone,
    sesmo_usuario_alteracao text,
    sesmo_data_alteracao timestamp with time zone,
    sesmo_situacao_codigo integer,
    campos_editados text[] DEFAULT '{}'::text[] NOT NULL,
    cadastrado_por uuid,
    natureza_juridica text,
    natureza_juridica_descricao text
);

ALTER TABLE ONLY pn.empresa FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.epc (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sesmo_id text,
    nome text NOT NULL,
    descricao text,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.epc FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.epi (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sesmo_id text,
    nome text NOT NULL,
    ca text,
    descricao text,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.epi FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.exame_tipo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sesmo_id text,
    nome text NOT NULL,
    sigla text,
    grupo text,
    periodicidade_padrao_meses integer,
    exige_laudo boolean DEFAULT false NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.exame_tipo FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.funcao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    setor_id uuid NOT NULL,
    sesmo_id text,
    nome text NOT NULL,
    cbo_codigo text,
    descricao_atividades text,
    quantidade_expostos integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    sesmo_usuario_cadastro text,
    sesmo_data_cadastro timestamp with time zone,
    sesmo_usuario_alteracao text,
    sesmo_data_alteracao timestamp with time zone,
    sesmo_situacao_codigo integer,
    identificador text,
    data_inicio_condicao date,
    data_inicio_periodo_esocial date,
    descricao_atividades_origem text
);

ALTER TABLE ONLY pn.funcao FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.profissional (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sesmo_id text,
    nome text NOT NULL,
    tipo pn.tipo_profissional DEFAULT 'outro'::pn.tipo_profissional NOT NULL,
    conselho text,
    registro text,
    uf_registro text,
    cpf text,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    sesmo_situacao_codigo integer,
    sesmo_tipo_codigo integer,
    especializacao text,
    identificador text
);

ALTER TABLE ONLY pn.profissional FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.setor (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    unidade_id uuid NOT NULL,
    sesmo_id text,
    nome text NOT NULL,
    descricao text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    controla_esocial boolean,
    identificador text,
    sesmo_usuario_cadastro text,
    sesmo_data_cadastro timestamp with time zone,
    sesmo_usuario_alteracao text,
    sesmo_data_alteracao timestamp with time zone,
    sesmo_situacao_codigo integer,
    id_esocial text,
    tipo_setor text
);

ALTER TABLE ONLY pn.setor FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.unidade (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    sesmo_id text,
    nome text NOT NULL,
    cnpj text,
    cnae text,
    grau_risco integer,
    cidade text,
    uf text,
    endereco text,
    ativa boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_matriz boolean,
    tem_tac boolean,
    tem_dir boolean,
    tem_ghe boolean,
    sesmo_usuario_cadastro text,
    sesmo_data_cadastro timestamp with time zone,
    sesmo_usuario_alteracao text,
    sesmo_data_alteracao timestamp with time zone,
    sesmo_situacao_codigo integer,
    cep text,
    telefone text,
    identificador text,
    cnae_secundario text,
    campos_editados text[] DEFAULT '{}'::text[] NOT NULL
);

ALTER TABLE ONLY pn.unidade FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.vacina (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sesmo_id text,
    nome text NOT NULL,
    doses integer,
    periodicidade_meses integer,
    ativo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.vacina FORCE ROW LEVEL SECURITY;

CREATE VIEW pn_app.vw_carga_trilha_a AS
 SELECT 'empresa'::text AS tabela,
    count(*) AS linhas
   FROM pn.empresa
UNION ALL
 SELECT 'unidade'::text AS tabela,
    count(*) AS linhas
   FROM pn.unidade
UNION ALL
 SELECT 'setor'::text AS tabela,
    count(*) AS linhas
   FROM pn.setor
UNION ALL
 SELECT 'funcao'::text AS tabela,
    count(*) AS linhas
   FROM pn.funcao
UNION ALL
 SELECT 'epi'::text AS tabela,
    count(*) AS linhas
   FROM pn.epi
UNION ALL
 SELECT 'epc'::text AS tabela,
    count(*) AS linhas
   FROM pn.epc
UNION ALL
 SELECT 'exame_tipo'::text AS tabela,
    count(*) AS linhas
   FROM pn.exame_tipo
UNION ALL
 SELECT 'vacina'::text AS tabela,
    count(*) AS linhas
   FROM pn.vacina
UNION ALL
 SELECT 'profissional'::text AS tabela,
    count(*) AS linhas
   FROM pn.profissional
UNION ALL
 SELECT 'colaborador'::text AS tabela,
    count(*) AS linhas
   FROM pn.colaborador;

CREATE TABLE pn.atendimento (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sesmo_id text,
    empresa_id uuid NOT NULL,
    unidade_id uuid,
    colaborador_id uuid NOT NULL,
    funcao_id uuid,
    profissional_id uuid,
    tipo pn.tipo_exame_ocupacional NOT NULL,
    data_agendada timestamp with time zone,
    data_atendimento date,
    situacao pn.situacao_atendimento DEFAULT 'agendado'::pn.situacao_atendimento NOT NULL,
    aso_resultado pn.resultado_aso DEFAULT 'pendente'::pn.resultado_aso NOT NULL,
    aso_emitido_em date,
    aso_arquivo_path text,
    local_atendimento text,
    observacao text,
    origem pn.origem_registro DEFAULT 'sesmo_robo'::pn.origem_registro NOT NULL,
    extraido_em timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    sesmo_usuario_cadastro text,
    sesmo_data_cadastro timestamp with time zone,
    sesmo_usuario_alteracao text,
    sesmo_data_alteracao timestamp with time zone,
    sesmo_status_codigo text,
    campos_editados text[] DEFAULT '{}'::text[] NOT NULL
);

ALTER TABLE ONLY pn.atendimento FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.esocial_evento (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sesmo_id text,
    tipo pn.evento_esocial NOT NULL,
    empresa_id uuid,
    unidade_id uuid,
    colaborador_id uuid,
    atendimento_id uuid,
    matricula_esocial text,
    lote text,
    protocolo text,
    numero_recibo text,
    data_evento date,
    data_transmissao timestamp with time zone,
    situacao pn.situacao_evento_esocial DEFAULT 'pendente'::pn.situacao_evento_esocial NOT NULL,
    mensagem_retorno text,
    xml_arquivo_id uuid,
    recibo_arquivo_id uuid,
    extraido_em timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.esocial_evento FORCE ROW LEVEL SECURITY;

CREATE TABLE pn_sesmo.baseline (
    modulo text NOT NULL,
    descricao text NOT NULL,
    esperado bigint,
    medido_em date NOT NULL,
    fonte text NOT NULL,
    observacao text
);

CREATE VIEW pn_app.vw_cobertura WITH (security_invoker='on') AS
 WITH carregado AS (
         SELECT 'clientes'::text AS modulo,
            count(*) AS n
           FROM pn.empresa
        UNION ALL
         SELECT 'atendimentos'::text,
            count(*) AS count
           FROM pn.atendimento
        UNION ALL
         SELECT 'cargos'::text,
            count(*) AS count
           FROM pn.funcao
        UNION ALL
         SELECT 'esocial_s2220'::text,
            count(*) AS count
           FROM pn.esocial_evento
          WHERE (esocial_evento.tipo = 'S-2220'::pn.evento_esocial)
        UNION ALL
         SELECT 'esocial_s2240'::text,
            count(*) AS count
           FROM pn.esocial_evento
          WHERE (esocial_evento.tipo = 'S-2240'::pn.evento_esocial)
        UNION ALL
         SELECT 'esocial_s2210'::text,
            count(*) AS count
           FROM pn.esocial_evento
          WHERE (esocial_evento.tipo = 'S-2210'::pn.evento_esocial)
        UNION ALL
         SELECT 'esocial_s2221'::text,
            count(*) AS count
           FROM pn.esocial_evento
          WHERE (esocial_evento.tipo = 'S-2221'::pn.evento_esocial)
        )
 SELECT b.modulo,
    b.descricao,
    b.esperado,
    COALESCE(c.n, (0)::bigint) AS carregado,
    (COALESCE(c.n, (0)::bigint) - b.esperado) AS diferenca,
        CASE
            WHEN (b.esperado IS NULL) THEN 'sem_referencia'::text
            WHEN (COALESCE(c.n, (0)::bigint) = 0) THEN 'nao_iniciado'::text
            WHEN (COALESCE(c.n, (0)::bigint) < b.esperado) THEN 'incompleto'::text
            WHEN (COALESCE(c.n, (0)::bigint) = b.esperado) THEN 'ok'::text
            ELSE 'acima_do_esperado'::text
        END AS status,
    b.observacao
   FROM (pn_sesmo.baseline b
     LEFT JOIN carregado c ON ((c.modulo = b.modulo)))
  ORDER BY b.modulo;

CREATE TABLE pn.arquivo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    gcs_bucket text NOT NULL,
    gcs_object text NOT NULL,
    sha256 text NOT NULL,
    bytes bigint NOT NULL,
    mime_type text,
    nome_original text,
    origem pn.origem_arquivo NOT NULL,
    origem_url text,
    assinado boolean,
    assinatura_info jsonb,
    capturado_em timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.arquivo FORCE ROW LEVEL SECURITY;

CREATE VIEW pn_app.vw_cobertura_arquivos WITH (security_invoker='on') AS
 SELECT origem,
    count(*) AS arquivos,
    count(*) FILTER (WHERE (assinado IS TRUE)) AS assinados,
    count(*) FILTER (WHERE (assinado IS NULL)) AS assinatura_nao_verificada,
    pg_size_pretty(sum(bytes)) AS volume
   FROM pn.arquivo
  GROUP BY origem;

CREATE TABLE pn.colaborador_vinculo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    colaborador_id uuid NOT NULL,
    funcao_id uuid NOT NULL,
    data_inicio date NOT NULL,
    data_fim date,
    motivo text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.colaborador_vinculo FORCE ROW LEVEL SECURITY;

CREATE VIEW pn_app.vw_colaborador_vigente WITH (security_invoker='on') AS
 SELECT c.id AS colaborador_id,
    c.nome AS colaborador,
    c.cpf,
    c.matricula_esocial,
    c.data_admissao,
    c.situacao,
    e.id AS empresa_id,
    e.razao_social AS empresa,
    e.situacao AS empresa_situacao,
    u.id AS unidade_id,
    u.nome AS unidade,
    s.id AS setor_id,
    s.nome AS setor,
    f.id AS funcao_id,
    f.nome AS funcao
   FROM (((((pn.colaborador c
     JOIN pn.empresa e ON ((e.id = c.empresa_id)))
     LEFT JOIN pn.colaborador_vinculo v ON (((v.colaborador_id = c.id) AND (v.data_fim IS NULL))))
     LEFT JOIN pn.funcao f ON ((f.id = v.funcao_id)))
     LEFT JOIN pn.setor s ON ((s.id = f.setor_id)))
     LEFT JOIN pn.unidade u ON ((u.id = s.unidade_id)));

CREATE TABLE pn.documento (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    unidade_id uuid,
    sesmo_id text,
    tipo pn.tipo_documento NOT NULL,
    versao text,
    data_elaboracao date,
    vigencia_inicio date,
    vigencia_fim date,
    situacao pn.situacao_documento DEFAULT 'vigente'::pn.situacao_documento NOT NULL,
    responsavel_id uuid,
    arquivo_path text,
    observacao text,
    origem pn.origem_registro DEFAULT 'sesmo_robo'::pn.origem_registro NOT NULL,
    extraido_em timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    sesmo_usuario_cadastro text,
    sesmo_data_cadastro timestamp with time zone,
    sesmo_usuario_alteracao text,
    sesmo_data_alteracao timestamp with time zone
);

ALTER TABLE ONLY pn.documento FORCE ROW LEVEL SECURITY;

CREATE VIEW pn_app.vw_pcmso_vigente WITH (security_invoker='on') AS
 SELECT DISTINCT ON (empresa_id) id AS documento_id,
    empresa_id,
    vigencia_inicio,
    vigencia_fim,
    situacao
   FROM pn.documento d
  WHERE (tipo = 'PCMSO'::pn.tipo_documento)
  ORDER BY empresa_id, (situacao = 'vigente'::pn.situacao_documento) DESC, vigencia_fim DESC NULLS LAST;

CREATE TABLE pn.atendimento_exame (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    atendimento_id uuid NOT NULL,
    exame_tipo_id uuid NOT NULL,
    data_realizacao date,
    resultado pn.resultado_exame DEFAULT 'pendente'::pn.resultado_exame NOT NULL,
    texto_resultado text,
    laudo_arquivo_path text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.atendimento_exame FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.pcmso_exame_funcao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    documento_id uuid NOT NULL,
    funcao_id uuid NOT NULL,
    exame_tipo_id uuid NOT NULL,
    periodicidade_meses integer,
    exigido_em pn.tipo_exame_ocupacional[] DEFAULT '{admissional,periodico,demissional}'::pn.tipo_exame_ocupacional[] NOT NULL,
    idade_minima integer,
    idade_maxima integer,
    sexo text,
    observacao text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    obrigatorio boolean DEFAULT true NOT NULL,
    is_ocupacional boolean DEFAULT true NOT NULL,
    is_assistencial boolean DEFAULT false NOT NULL,
    faixa_descricao text,
    sesmo_usuario_cadastro text,
    sesmo_data_cadastro timestamp with time zone,
    sesmo_usuario_alteracao text,
    sesmo_data_alteracao timestamp with time zone
);

ALTER TABLE ONLY pn.pcmso_exame_funcao FORCE ROW LEVEL SECURITY;

CREATE VIEW pn_app.vw_exame_vencimento WITH (security_invoker='on') AS
 WITH exigidos AS (
         SELECT cv.colaborador_id,
            cv.colaborador,
            cv.cpf,
            cv.matricula_esocial,
            cv.empresa_id,
            cv.empresa,
            cv.unidade,
            cv.setor,
            cv.funcao_id,
            cv.funcao,
            pef.exame_tipo_id,
            et.nome AS exame,
            pef.periodicidade_meses
           FROM (((pn_app.vw_colaborador_vigente cv
             JOIN pn_app.vw_pcmso_vigente p ON ((p.empresa_id = cv.empresa_id)))
             JOIN pn.pcmso_exame_funcao pef ON (((pef.documento_id = p.documento_id) AND (pef.funcao_id = cv.funcao_id))))
             JOIN pn.exame_tipo et ON ((et.id = pef.exame_tipo_id)))
          WHERE ((cv.situacao = 'ativo'::pn.situacao_colaborador) AND (pef.periodicidade_meses IS NOT NULL) AND ('periodico'::pn.tipo_exame_ocupacional = ANY (pef.exigido_em)))
        ), ultima AS (
         SELECT a.colaborador_id,
            ae.exame_tipo_id,
            max(COALESCE(ae.data_realizacao, a.data_atendimento)) AS ultima_realizacao
           FROM (pn.atendimento_exame ae
             JOIN pn.atendimento a ON ((a.id = ae.atendimento_id)))
          WHERE ((ae.resultado = ANY (ARRAY['normal'::pn.resultado_exame, 'alterado'::pn.resultado_exame])) AND (a.situacao = ANY (ARRAY['atendido'::pn.situacao_atendimento, 'finalizado'::pn.situacao_atendimento])))
          GROUP BY a.colaborador_id, ae.exame_tipo_id
        )
 SELECT x.colaborador_id,
    x.colaborador,
    x.cpf,
    x.matricula_esocial,
    x.empresa_id,
    x.empresa,
    x.unidade,
    x.setor,
    x.funcao_id,
    x.funcao,
    x.exame_tipo_id,
    x.exame,
    x.periodicidade_meses,
    u.ultima_realizacao,
    ((u.ultima_realizacao + ((x.periodicidade_meses || ' months'::text))::interval))::date AS proxima_realizacao,
    (((u.ultima_realizacao + ((x.periodicidade_meses || ' months'::text))::interval))::date - CURRENT_DATE) AS dias_para_vencer,
        CASE
            WHEN (u.ultima_realizacao IS NULL) THEN 'nunca_realizado'::text
            WHEN (((u.ultima_realizacao + ((x.periodicidade_meses || ' months'::text))::interval))::date < CURRENT_DATE) THEN 'vencido'::text
            WHEN (((u.ultima_realizacao + ((x.periodicidade_meses || ' months'::text))::interval))::date <= (CURRENT_DATE + 30)) THEN 'vence_em_30_dias'::text
            WHEN (((u.ultima_realizacao + ((x.periodicidade_meses || ' months'::text))::interval))::date <= (CURRENT_DATE + 60)) THEN 'vence_em_60_dias'::text
            ELSE 'em_dia'::text
        END AS status
   FROM (exigidos x
     LEFT JOIN ultima u ON (((u.colaborador_id = x.colaborador_id) AND (u.exame_tipo_id = x.exame_tipo_id))));

CREATE TABLE pn.ficha_clinica (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    atendimento_id uuid,
    colaborador_id uuid NOT NULL,
    data_referencia date NOT NULL,
    empresa_nome_epoca text,
    funcao_nome_epoca text,
    profissional_id uuid,
    guardar_ate date GENERATED ALWAYS AS (((data_referencia + '20 years'::interval))::date) STORED,
    origem pn.origem_registro DEFAULT 'sesmo_robo'::pn.origem_registro NOT NULL,
    extraido_em timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    sesmo_usuario_cadastro text,
    sesmo_data_cadastro timestamp with time zone,
    sesmo_usuario_alteracao text,
    sesmo_data_alteracao timestamp with time zone
);

ALTER TABLE ONLY pn.ficha_clinica FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.queixa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ficha_clinica_id uuid NOT NULL,
    texto text NOT NULL,
    registrado_por uuid,
    registrado_em timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.queixa FORCE ROW LEVEL SECURITY;

CREATE VIEW pn_app.vw_historico_colaborador WITH (security_invoker='on') AS
 SELECT c.id AS colaborador_id,
    c.nome AS colaborador,
    c.cpf,
    a.id AS atendimento_id,
    a.tipo,
    a.data_atendimento,
    a.situacao,
    a.aso_resultado,
    e.razao_social AS empresa,
    f.nome AS funcao_na_epoca,
    p.nome AS profissional,
    ( SELECT count(*) AS count
           FROM pn.atendimento_exame ae
          WHERE (ae.atendimento_id = a.id)) AS qtd_exames,
    ( SELECT count(*) AS count
           FROM (pn.queixa q
             JOIN pn.ficha_clinica fc ON ((fc.id = q.ficha_clinica_id)))
          WHERE (fc.atendimento_id = a.id)) AS qtd_queixas
   FROM ((((pn.colaborador c
     JOIN pn.atendimento a ON ((a.colaborador_id = c.id)))
     JOIN pn.empresa e ON ((e.id = a.empresa_id)))
     LEFT JOIN pn.funcao f ON ((f.id = a.funcao_id)))
     LEFT JOIN pn.profissional p ON ((p.id = a.profissional_id)))
  ORDER BY c.nome, a.data_atendimento DESC;

CREATE TABLE pn_sesmo.captura (
    id bigint NOT NULL,
    modulo text NOT NULL,
    chave text NOT NULL,
    url text,
    capturado_em timestamp with time zone DEFAULT now() NOT NULL,
    conteudo jsonb,
    html text,
    arquivo_path text,
    hash text,
    processado_em timestamp with time zone,
    erro text
);

CREATE VIEW pn_app.vw_texto_corrompido AS
 WITH ultima AS (
         SELECT DISTINCT ON (captura.modulo, captura.chave) captura.modulo,
            captura.chave,
            captura.conteudo
           FROM pn_sesmo.captura
          WHERE (captura.conteudo IS NOT NULL)
          ORDER BY captura.modulo, captura.chave, captura.id DESC
        )
 SELECT u.modulo,
    u.chave,
    k.campo,
    (u.conteudo ->> k.campo) AS valor,
    pn_sesmo.corrigir((u.conteudo ->> k.campo)) AS valor_corrigido,
    (pn_sesmo.corrigir((u.conteudo ->> k.campo)) !~~ (('%'::text || chr(65533)) || '%'::text)) AS tem_regra
   FROM ultima u,
    LATERAL jsonb_object_keys(u.conteudo) k(campo)
  WHERE ((u.conteudo ->> k.campo) ~~ (('%'::text || chr(65533)) || '%'::text));

CREATE TABLE pn_bitrix.captura (
    id bigint NOT NULL,
    modulo text,
    chave text,
    conteudo jsonb,
    hash text,
    capturado_em timestamp with time zone DEFAULT now()
);

CREATE SEQUENCE pn_bitrix.captura_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE pn_bitrix.captura_id_seq OWNED BY pn_bitrix.captura.id;

CREATE TABLE pn_crm.admin_inicial (
    email text NOT NULL
);

CREATE TABLE pn_crm.agenda (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    data date NOT NULL,
    profissional_id uuid,
    local text DEFAULT 'clinica'::text NOT NULL,
    empresa_id uuid,
    hora_inicio time without time zone,
    hora_fim time without time zone,
    vagas integer NOT NULL,
    observacao text,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT agenda_horario CHECK (((hora_inicio IS NULL) OR (hora_fim IS NULL) OR (hora_fim > hora_inicio))),
    CONSTRAINT agenda_in_company_tem_empresa CHECK (((local = 'clinica'::text) OR (empresa_id IS NOT NULL))),
    CONSTRAINT agenda_local_check CHECK ((local = ANY (ARRAY['clinica'::text, 'in_company'::text]))),
    CONSTRAINT agenda_vagas_check CHECK (((vagas >= 1) AND (vagas <= 500)))
);

CREATE TABLE pn_crm.agenda_grade (
    horario time without time zone NOT NULL,
    vagas integer NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_por uuid,
    CONSTRAINT agenda_grade_vagas_check CHECK (((vagas >= 0) AND (vagas <= 50)))
);

CREATE TABLE pn_crm.agenda_limite_empresa (
    empresa_id uuid NOT NULL,
    limite integer NOT NULL,
    motivo text,
    atualizado_por uuid,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT agenda_limite_empresa_limite_check CHECK (((limite >= 1) AND (limite <= 500)))
);

CREATE TABLE pn_crm.agenda_regra (
    id boolean DEFAULT true NOT NULL,
    limite_empresa_dia integer,
    bloquear_inadimplente boolean DEFAULT true NOT NULL,
    vagas_padrao integer DEFAULT 40 NOT NULL,
    hora_inicio_padrao time without time zone DEFAULT '08:30:00'::time without time zone NOT NULL,
    hora_fim_padrao time without time zone DEFAULT '11:30:00'::time without time zone NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_por uuid,
    CONSTRAINT agenda_regra_id_check CHECK (id),
    CONSTRAINT agenda_regra_limite_empresa_dia_check CHECK ((limite_empresa_dia > 0)),
    CONSTRAINT agenda_regra_vagas_padrao_check CHECK (((vagas_padrao >= 1) AND (vagas_padrao <= 500)))
);

CREATE TABLE pn_crm.agendamento (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    numero bigint NOT NULL,
    agenda_id uuid NOT NULL,
    horario time without time zone,
    empresa_id uuid,
    empresa_nome text,
    colaborador_id uuid,
    paciente_nome text NOT NULL,
    cpf text,
    telefone text,
    funcao text,
    tipo text DEFAULT 'periodico'::text NOT NULL,
    situacao text DEFAULT 'agendado'::text NOT NULL,
    encaixe boolean DEFAULT false NOT NULL,
    excecao_motivo text,
    cancelado_motivo text,
    negocio_id uuid,
    observacao text,
    chegou_em timestamp with time zone,
    atendido_em timestamp with time zone,
    finalizado_em timestamp with time zone,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    complementares text[] DEFAULT '{}'::text[] NOT NULL,
    criado_via text DEFAULT 'painel'::text NOT NULL,
    ia_ref text,
    CONSTRAINT agendamento_criado_via_check CHECK ((criado_via = ANY (ARRAY['painel'::text, 'ia'::text]))),
    CONSTRAINT agendamento_paciente_nome_check CHECK ((length(TRIM(BOTH FROM paciente_nome)) > 1)),
    CONSTRAINT agendamento_situacao_check CHECK ((situacao = ANY (ARRAY['agendado'::text, 'aguardando'::text, 'atendido'::text, 'finalizado'::text, 'cancelado'::text, 'faltou'::text]))),
    CONSTRAINT agendamento_tem_empresa CHECK (((empresa_id IS NOT NULL) OR (NULLIF(TRIM(BOTH FROM empresa_nome), ''::text) IS NOT NULL))),
    CONSTRAINT agendamento_tipo_check CHECK ((tipo = ANY (ARRAY['admissional'::text, 'periodico'::text, 'demissional'::text, 'mudanca_de_funcao'::text, 'retorno_ao_trabalho'::text, 'monitoracao_pontual'::text, 'outro'::text])))
);

CREATE TABLE pn_crm.agendamento_evento (
    id bigint NOT NULL,
    agendamento_id uuid NOT NULL,
    texto text NOT NULL,
    autor_id uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE pn_crm.agendamento_evento ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.agendamento_evento_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE pn_crm.agendamento ALTER COLUMN numero ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.agendamento_numero_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn_crm.atestado (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    numero bigint NOT NULL,
    empresa_id uuid,
    colaborador_id uuid,
    colaborador_nome text,
    colaborador_cpf text,
    data_emissao date,
    data_inicio date,
    dias integer,
    cid text,
    medico text,
    medico_crm text,
    arquivo_path text,
    arquivo_nome text,
    origem text DEFAULT 'painel'::text NOT NULL,
    wa_telefone text,
    wa_mensagem_id text,
    leitura_ia jsonb,
    situacao text DEFAULT 'ok'::text NOT NULL,
    observacao text,
    mes date NOT NULL,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT atestado_dias_check CHECK (((dias IS NULL) OR ((dias >= 0) AND (dias <= 3650)))),
    CONSTRAINT atestado_origem_check CHECK ((origem = ANY (ARRAY['painel'::text, 'whatsapp'::text]))),
    CONSTRAINT atestado_situacao_check CHECK ((situacao = ANY (ARRAY['ok'::text, 'revisar'::text, 'descartado'::text])))
);

CREATE TABLE pn_crm.atestado_alerta (
    empresa_id uuid NOT NULL,
    mes date NOT NULL,
    quantidade integer NOT NULL,
    responsavel_id uuid,
    tarefa_id uuid,
    negocio_id uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE pn_crm.atestado ALTER COLUMN numero ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.atestado_numero_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn_crm.atestado_regra (
    id boolean DEFAULT true NOT NULL,
    limite integer DEFAULT 5 NOT NULL,
    prazo_dias integer DEFAULT 3 NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    CONSTRAINT atestado_regra_id_check CHECK (id),
    CONSTRAINT atestado_regra_limite_check CHECK (((limite >= 1) AND (limite <= 100))),
    CONSTRAINT atestado_regra_prazo_dias_check CHECK (((prazo_dias >= 0) AND (prazo_dias <= 60)))
);

CREATE TABLE pn_crm.bitrix_empresa (
    bitrix_id bigint NOT NULL,
    nome text,
    cnpj text,
    empresa_id uuid,
    metodo text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT bitrix_empresa_metodo_check CHECK ((metodo = ANY (ARRAY['cnpj'::text, 'nome'::text, 'manual'::text])))
);

CREATE TABLE pn_crm.bitrix_etapa (
    stage_id text NOT NULL,
    funil_slug text NOT NULL,
    etapa_nome text NOT NULL
);

CREATE TABLE pn_crm.bitrix_usuario (
    bitrix_id integer NOT NULL,
    nome text NOT NULL,
    email_bitrix text,
    email_painel text
);

CREATE TABLE pn_crm.chat_membro (
    sala_id uuid NOT NULL,
    user_id uuid NOT NULL,
    dono boolean DEFAULT false NOT NULL,
    lida_em timestamp with time zone DEFAULT now() NOT NULL,
    entrou_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE pn_crm.chat_mensagem (
    id bigint NOT NULL,
    sala_id uuid NOT NULL,
    autor_id uuid,
    texto text NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    excluida boolean DEFAULT false NOT NULL,
    anexo_path text,
    anexo_tipo text,
    anexo_nome text,
    anexo_mime text,
    anexo_tamanho integer,
    anexo_duracao numeric,
    texto_auto boolean DEFAULT false NOT NULL,
    CONSTRAINT chat_mensagem_anexo_tipo_check CHECK ((anexo_tipo = ANY (ARRAY['imagem'::text, 'audio'::text, 'arquivo'::text]))),
    CONSTRAINT chat_mensagem_texto_check CHECK (((length(texto) >= 1) AND (length(texto) <= 4000)))
);

ALTER TABLE pn_crm.chat_mensagem ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.chat_mensagem_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn_crm.chat_sala (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo text NOT NULL,
    nome text,
    descricao text,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    ultima_em timestamp with time zone DEFAULT now() NOT NULL,
    arquivada boolean DEFAULT false NOT NULL,
    CONSTRAINT chat_sala_tipo_check CHECK ((tipo = ANY (ARRAY['geral'::text, 'grupo'::text, 'direto'::text])))
);

CREATE TABLE pn_crm.cobranca (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    numero bigint NOT NULL,
    empresa_id uuid,
    cliente_nome text,
    contrato_id uuid,
    descricao text NOT NULL,
    competencia date NOT NULL,
    vencimento date NOT NULL,
    valor numeric(12,2) NOT NULL,
    valor_pago numeric(12,2),
    pago_em date,
    forma text,
    nota_fiscal text,
    boleto text,
    observacao text,
    cancelada boolean DEFAULT false NOT NULL,
    cancelada_motivo text,
    origem text DEFAULT 'manual'::text NOT NULL,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT cobranca_competencia CHECK ((competencia = (date_trunc('month'::text, (competencia)::timestamp with time zone))::date)),
    CONSTRAINT cobranca_forma_check CHECK ((forma = ANY (ARRAY['boleto'::text, 'pix'::text, 'transferencia'::text, 'cartao'::text, 'dinheiro'::text, 'outro'::text]))),
    CONSTRAINT cobranca_origem_check CHECK ((origem = ANY (ARRAY['manual'::text, 'contrato'::text, 'importacao'::text]))),
    CONSTRAINT cobranca_tem_cliente CHECK (((empresa_id IS NOT NULL) OR (NULLIF(TRIM(BOTH FROM cliente_nome), ''::text) IS NOT NULL))),
    CONSTRAINT cobranca_valor_check CHECK ((valor > (0)::numeric)),
    CONSTRAINT cobranca_valor_pago_check CHECK ((valor_pago >= (0)::numeric))
);

CREATE TABLE pn_crm.cobranca_evento (
    id bigint NOT NULL,
    cobranca_id uuid NOT NULL,
    texto text NOT NULL,
    autor_id uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE pn_crm.cobranca_evento ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.cobranca_evento_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE pn_crm.cobranca ALTER COLUMN numero ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.cobranca_numero_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn_crm.contrato (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    numero bigint NOT NULL,
    empresa_id uuid,
    cliente_nome text,
    negocio_id uuid,
    titulo text NOT NULL,
    status text DEFAULT 'rascunho'::text NOT NULL,
    inicio date,
    fim date,
    renovacao_automatica boolean DEFAULT true NOT NULL,
    aviso_dias integer DEFAULT 60 NOT NULL,
    valor_mensal numeric(12,2),
    valor_total numeric(12,2) DEFAULT 0 NOT NULL,
    dia_vencimento integer DEFAULT 5,
    forma_pagamento text DEFAULT 'Boleto bancário'::text,
    indice_reajuste text DEFAULT 'IPCA'::text,
    responsavel_id uuid,
    observacao text,
    arquivo_path text,
    arquivo_nome text,
    assinado_em timestamp with time zone,
    cancelado_motivo text,
    renovacao_negocio_id uuid,
    ultimo_alerta_em date,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    representante_legal text,
    email_notificacao text,
    telefone_contato text,
    prazo_meses integer,
    CONSTRAINT contrato_aviso_dias_check CHECK (((aviso_dias >= 0) AND (aviso_dias <= 365))),
    CONSTRAINT contrato_dia_vencimento_check CHECK (((dia_vencimento >= 1) AND (dia_vencimento <= 31))),
    CONSTRAINT contrato_prazo_meses_check CHECK (((prazo_meses >= 1) AND (prazo_meses <= 120))),
    CONSTRAINT contrato_status_check CHECK ((status = ANY (ARRAY['rascunho'::text, 'revisao'::text, 'enviado'::text, 'parcial'::text, 'assinado'::text, 'cancelado'::text]))),
    CONSTRAINT contrato_tem_cliente CHECK (((empresa_id IS NOT NULL) OR (NULLIF(TRIM(BOTH FROM cliente_nome), ''::text) IS NOT NULL))),
    CONSTRAINT contrato_titulo_check CHECK ((length(TRIM(BOTH FROM titulo)) > 1)),
    CONSTRAINT contrato_valor_mensal_check CHECK ((valor_mensal >= (0)::numeric)),
    CONSTRAINT contrato_valor_total_check CHECK ((valor_total >= (0)::numeric)),
    CONSTRAINT contrato_vigencia CHECK (((inicio IS NULL) OR (fim IS NULL) OR (fim >= inicio)))
);

CREATE TABLE pn_crm.contrato_evento (
    id bigint NOT NULL,
    contrato_id uuid NOT NULL,
    texto text NOT NULL,
    autor_id uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE pn_crm.contrato_evento ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.contrato_evento_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn_crm.contrato_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    contrato_id uuid NOT NULL,
    produto_id uuid,
    descricao text NOT NULL,
    quantidade numeric(12,2) DEFAULT 1 NOT NULL,
    preco numeric(12,2) DEFAULT 0 NOT NULL,
    total numeric(14,2) GENERATED ALWAYS AS ((quantidade * preco)) STORED,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    cobranca text,
    CONSTRAINT contrato_item_preco_check CHECK ((preco >= (0)::numeric)),
    CONSTRAINT contrato_item_quantidade_check CHECK ((quantidade > (0)::numeric))
);

ALTER TABLE pn_crm.contrato ALTER COLUMN numero ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.contrato_numero_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn_crm.documento_regra (
    id boolean DEFAULT true NOT NULL,
    aviso_dias integer DEFAULT 60 NOT NULL,
    CONSTRAINT documento_regra_aviso_dias_check CHECK (((aviso_dias >= 0) AND (aviso_dias <= 365))),
    CONSTRAINT documento_regra_id_check CHECK (id)
);

CREATE TABLE pn_crm.documento_renovacao (
    documento_id uuid NOT NULL,
    negocio_id uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE pn_crm.edicao (
    id bigint NOT NULL,
    tabela text NOT NULL,
    registro_id uuid NOT NULL,
    acao text DEFAULT 'editar'::text NOT NULL,
    mudancas jsonb DEFAULT '{}'::jsonb NOT NULL,
    usuario_id uuid,
    em timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE pn_crm.edicao ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.edicao_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn_crm.empresa_interacao (
    id bigint NOT NULL,
    empresa_id uuid NOT NULL,
    contato_id uuid,
    canal text NOT NULL,
    destino text,
    assunto text,
    texto text,
    wa_saida_id bigint,
    usuario_id uuid,
    em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT empresa_interacao_canal_check CHECK ((canal = ANY (ARRAY['whatsapp'::text, 'email'::text, 'ligacao'::text, 'nota'::text])))
);

ALTER TABLE pn_crm.empresa_interacao ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.empresa_interacao_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn_crm.etapa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    funil_id uuid NOT NULL,
    nome text NOT NULL,
    ordem integer NOT NULL,
    tipo pn_crm.tipo_etapa DEFAULT 'aberta'::pn_crm.tipo_etapa NOT NULL,
    cor text DEFAULT 'muted'::text NOT NULL,
    alerta_dias integer,
    ativo boolean DEFAULT true NOT NULL,
    CONSTRAINT etapa_alerta_dias_check CHECK (((alerta_dias IS NULL) OR (alerta_dias > 0))),
    CONSTRAINT etapa_cor_check CHECK ((cor = ANY (ARRAY['muted'::text, 'info'::text, 'primary'::text, 'warning'::text, 'marca'::text, 'success'::text, 'destructive'::text])))
);

CREATE TABLE pn_crm.evento (
    id bigint NOT NULL,
    negocio_id uuid NOT NULL,
    tipo text NOT NULL,
    texto text,
    de_etapa_id uuid,
    para_etapa_id uuid,
    autor_id uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    bitrix_ref text,
    CONSTRAINT evento_tipo_check CHECK ((tipo = ANY (ARRAY['criado'::text, 'etapa'::text, 'nota'::text, 'ligacao'::text, 'email'::text, 'whatsapp'::text, 'reuniao'::text, 'responsavel'::text, 'item'::text, 'alerta'::text, 'edicao'::text])))
);

ALTER TABLE pn_crm.evento ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.evento_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn_crm.fin_regra (
    id boolean DEFAULT true NOT NULL,
    tolerancia_dias integer DEFAULT 5 NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT fin_regra_id_check CHECK (id),
    CONSTRAINT fin_regra_tolerancia_dias_check CHECK (((tolerancia_dias >= 0) AND (tolerancia_dias <= 90)))
);

CREATE TABLE pn_crm.funil (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug text NOT NULL,
    nome text NOT NULL,
    descricao text,
    ordem integer DEFAULT 0 NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    usa_rodizio boolean DEFAULT false NOT NULL,
    papeis pn_crm.papel[] DEFAULT '{comercial}'::pn_crm.papel[] NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE pn_crm.negocio (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    numero bigint NOT NULL,
    funil_id uuid NOT NULL,
    etapa_id uuid NOT NULL,
    titulo text NOT NULL,
    empresa_id uuid,
    cliente_nome text,
    cliente_cnpj text,
    contato_nome text,
    contato_telefone text,
    contato_email text,
    responsavel_id uuid,
    valor numeric(12,2) DEFAULT 0 NOT NULL,
    origem text DEFAULT 'manual'::text NOT NULL,
    negocio_origem_id uuid,
    previsao_fechamento date,
    motivo_perda text,
    observacao text,
    entrou_etapa_em timestamp with time zone DEFAULT now() NOT NULL,
    ultimo_alerta_em timestamp with time zone,
    fechado_em timestamp with time zone,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    etapa_anterior_id uuid,
    bitrix_id bigint,
    bitrix_responsavel integer,
    bitrix_sincronizado_em timestamp with time zone,
    bitrix_empresa bigint,
    qtd_funcionarios integer,
    forma_pagamento text,
    parcelas smallint,
    desconto_pct numeric(5,2) DEFAULT 0 NOT NULL,
    CONSTRAINT negocio_desconto_pct_check CHECK (((desconto_pct >= (0)::numeric) AND (desconto_pct <= (100)::numeric))),
    CONSTRAINT negocio_forma_pagamento_ck CHECK (((forma_pagamento IS NULL) OR (forma_pagamento = ANY (ARRAY['boleto'::text, 'pix'::text, 'transferencia'::text, 'cartao'::text])))),
    CONSTRAINT negocio_parcelas_ck CHECK (((parcelas IS NULL) OR ((parcelas >= 1) AND (parcelas <= 60)))),
    CONSTRAINT negocio_qtd_funcionarios_ck CHECK (((qtd_funcionarios IS NULL) OR (qtd_funcionarios > 0))),
    CONSTRAINT negocio_tem_cliente CHECK (((empresa_id IS NOT NULL) OR (NULLIF(TRIM(BOTH FROM cliente_nome), ''::text) IS NOT NULL))),
    CONSTRAINT negocio_valor_check CHECK ((valor >= (0)::numeric))
);

CREATE TABLE pn_crm.negocio_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    negocio_id uuid NOT NULL,
    produto_id uuid,
    descricao text NOT NULL,
    quantidade numeric(12,2) DEFAULT 1 NOT NULL,
    preco_unitario numeric(12,2) DEFAULT 0 NOT NULL,
    total numeric(12,2) GENERATED ALWAYS AS ((quantidade * preco_unitario)) STORED,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    bitrix_id bigint,
    preco_catalogo numeric(12,2),
    desconto_pct numeric(5,2) DEFAULT 0 NOT NULL,
    total_liquido numeric GENERATED ALWAYS AS (round(((quantidade * preco_unitario) * ((1)::numeric - (desconto_pct / (100)::numeric))), 2)) STORED,
    CONSTRAINT negocio_item_desconto_pct_check CHECK (((desconto_pct >= (0)::numeric) AND (desconto_pct <= (100)::numeric))),
    CONSTRAINT negocio_item_preco_unitario_check CHECK ((preco_unitario >= (0)::numeric)),
    CONSTRAINT negocio_item_quantidade_check CHECK ((quantidade > (0)::numeric))
);

ALTER TABLE pn_crm.negocio ALTER COLUMN numero ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.negocio_numero_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn_crm.notificacao (
    id bigint NOT NULL,
    user_id uuid NOT NULL,
    negocio_id uuid,
    tipo text NOT NULL,
    texto text NOT NULL,
    lida_em timestamp with time zone,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    tarefa_id uuid,
    contrato_id uuid
);

ALTER TABLE pn_crm.notificacao ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.notificacao_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn_crm.perfil (
    user_id uuid NOT NULL,
    nome text NOT NULL,
    email text NOT NULL,
    papel pn_crm.papel DEFAULT 'leitura'::pn_crm.papel NOT NULL,
    ativo boolean DEFAULT false NOT NULL,
    telefone text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    ultimo_acesso timestamp with time zone,
    libera_agenda boolean DEFAULT false NOT NULL,
    agenda_encaixe boolean DEFAULT false NOT NULL
);

CREATE TABLE pn_crm.posvenda_regra (
    id boolean DEFAULT true NOT NULL,
    meses integer DEFAULT 9 NOT NULL,
    max_por_execucao integer DEFAULT 30 NOT NULL,
    CONSTRAINT posvenda_regra_id_check CHECK (id),
    CONSTRAINT posvenda_regra_max_por_execucao_check CHECK (((max_por_execucao >= 1) AND (max_por_execucao <= 1000))),
    CONSTRAINT posvenda_regra_meses_check CHECK (((meses >= 1) AND (meses <= 36)))
);

CREATE TABLE pn_crm.pre_cadastro (
    email text NOT NULL,
    nome text NOT NULL,
    papel pn_crm.papel NOT NULL,
    cargo text,
    libera_agenda boolean DEFAULT false NOT NULL,
    rodizio_ordem integer,
    usado_em timestamp with time zone,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    telefone text,
    CONSTRAINT pre_cadastro_email_check CHECK ((email = lower(email)))
);

CREATE TABLE pn_crm.produto (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    descricao text,
    categoria text,
    preco numeric(12,2),
    unidade text DEFAULT 'un'::text NOT NULL,
    recorrente boolean DEFAULT false NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    codigo text,
    cobranca_padrao text,
    CONSTRAINT produto_preco_check CHECK (((preco IS NULL) OR (preco >= (0)::numeric)))
);

CREATE TABLE pn_crm.quadro (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    descricao text,
    ordem integer DEFAULT 0 NOT NULL,
    arquivado boolean DEFAULT false NOT NULL,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT quadro_nome_check CHECK ((length(TRIM(BOTH FROM nome)) > 1))
);

CREATE TABLE pn_crm.rodizio (
    funil_id uuid NOT NULL,
    user_id uuid NOT NULL,
    ordem integer NOT NULL,
    ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE pn_crm.rodizio_estado (
    funil_id uuid NOT NULL,
    ultimo_user_id uuid,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE pn_crm.tarefa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    numero bigint NOT NULL,
    quadro_id uuid NOT NULL,
    titulo text NOT NULL,
    status text DEFAULT 'nao_iniciado'::text NOT NULL,
    prioridade text DEFAULT 'media'::text NOT NULL,
    prazo date,
    responsavel_id uuid,
    notas text,
    empresa_id uuid,
    negocio_id uuid,
    ordem double precision DEFAULT EXTRACT(epoch FROM now()) NOT NULL,
    ultimo_alerta_em date,
    concluida_em timestamp with time zone,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    responsaveis uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    CONSTRAINT tarefa_prioridade_check CHECK ((prioridade = ANY (ARRAY['baixa'::text, 'media'::text, 'alta'::text, 'critica'::text]))),
    CONSTRAINT tarefa_status_check CHECK ((status = ANY (ARRAY['nao_iniciado'::text, 'em_andamento'::text, 'parado'::text, 'feito'::text]))),
    CONSTRAINT tarefa_titulo_check CHECK ((length(TRIM(BOTH FROM titulo)) > 1))
);

CREATE TABLE pn_crm.tarefa_comentario (
    id bigint NOT NULL,
    tarefa_id uuid NOT NULL,
    autor_id uuid,
    texto text NOT NULL,
    sistema boolean DEFAULT false NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tarefa_comentario_texto_check CHECK ((length(TRIM(BOTH FROM texto)) > 0))
);

ALTER TABLE pn_crm.tarefa_comentario ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.tarefa_comentario_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn_crm.tarefa_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tarefa_id uuid NOT NULL,
    texto text NOT NULL,
    feito boolean DEFAULT false NOT NULL,
    ordem double precision DEFAULT EXTRACT(epoch FROM now()) NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tarefa_item_texto_check CHECK ((length(TRIM(BOTH FROM texto)) > 0))
);

ALTER TABLE pn_crm.tarefa ALTER COLUMN numero ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.tarefa_numero_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn_crm.tunel (
    funil_origem_id uuid NOT NULL,
    funil_destino_id uuid NOT NULL,
    CONSTRAINT tunel_check CHECK ((funil_origem_id <> funil_destino_id))
);

CREATE VIEW pn_crm.vw_bitrix_negocio AS
 WITH d AS (
         SELECT (b.chave)::bigint AS id,
            b.c
           FROM pn_crm.bx_atual('crm.deal'::text) b(chave, c)
        ), ct AS (
         SELECT (x.chave)::bigint AS deal_id,
            ( SELECT ((e_1.value ->> 'CONTACT_ID'::text))::bigint AS int8
                   FROM jsonb_array_elements(x.c) e_1(value)
                  ORDER BY ((e_1.value ->> 'IS_PRIMARY'::text) = 'Y'::text) DESC, ((e_1.value ->> 'SORT'::text))::integer
                 LIMIT 1) AS contato
           FROM pn_crm.bx_atual('crm.deal.contacts'::text) x(chave, c)
          WHERE (jsonb_typeof(x.c) = 'array'::text)
        ), co AS (
         SELECT (b.chave)::bigint AS id,
            b.c
           FROM pn_crm.bx_atual('crm.contact'::text) b(chave, c)
        ), fx AS (
         SELECT DISTINCT ON ((s.value ->> 'ID'::text)) (s.value ->> 'ID'::text) AS id,
            (s.value ->> 'VALUE'::text) AS v
           FROM pn_bitrix.captura,
            LATERAL jsonb_array_elements(captura.conteudo) f_1(value),
            LATERAL jsonb_array_elements(COALESCE((f_1.value -> 'LIST'::text), '[]'::jsonb)) s(value)
          WHERE ((captura.modulo = 'meta'::text) AND (captura.chave = 'crm.deal.userfield.list'::text))
        ), src AS (
         SELECT (s.value ->> 'STATUS_ID'::text) AS id,
            (s.value ->> 'NAME'::text) AS nome
           FROM pn_bitrix.captura,
            LATERAL jsonb_array_elements(captura.conteudo) s(value)
          WHERE ((captura.modulo = 'meta'::text) AND (captura.chave = 'crm.status.list'::text) AND ((s.value ->> 'ENTITY_ID'::text) = 'SOURCE'::text))
        )
 SELECT d.id,
    f.id AS funil_id,
    e.id AS etapa_id,
    e.tipo,
    COALESCE(NULLIF(btrim((d.c ->> 'TITLE'::text)), ''::text), ('Negócio Bitrix #'::text || d.id)) AS titulo,
    be.empresa_id,
    COALESCE(NULLIF(be.nome, ''::text), NULLIF(btrim(((COALESCE((cc.c ->> 'NAME'::text), ''::text) || ' '::text) || COALESCE((cc.c ->> 'LAST_NAME'::text), ''::text))), ''::text), NULLIF(btrim((d.c ->> 'TITLE'::text)), ''::text), 'Cliente do Bitrix'::text) AS cliente_nome,
    be.cnpj AS cliente_cnpj,
    NULLIF(btrim(((COALESCE((cc.c ->> 'NAME'::text), ''::text) || ' '::text) || COALESCE((cc.c ->> 'LAST_NAME'::text), ''::text))), ''::text) AS contato_nome,
    (((cc.c -> 'PHONE'::text) -> 0) ->> 'VALUE'::text) AS contato_telefone,
    lower((((cc.c -> 'EMAIL'::text) -> 0) ->> 'VALUE'::text)) AS contato_email,
    ( SELECT p.user_id
           FROM (pn_crm.bitrix_usuario bu
             JOIN pn_crm.perfil p ON ((lower(p.email) = bu.email_painel)))
          WHERE (bu.bitrix_id = ((d.c ->> 'ASSIGNED_BY_ID'::text))::integer)) AS responsavel_id,
    ((d.c ->> 'ASSIGNED_BY_ID'::text))::integer AS bitrix_responsavel,
    GREATEST(COALESCE((NULLIF((d.c ->> 'OPPORTUNITY'::text), ''::text))::numeric, (0)::numeric), (0)::numeric) AS valor,
    (NULLIF("left"((d.c ->> 'CLOSEDATE'::text), 10), ''::text))::date AS previsao,
        CASE
            WHEN (e.tipo = 'perdido'::pn_crm.tipo_etapa) THEN ( SELECT fx.v
               FROM fx
              WHERE (fx.id = (d.c ->> 'UF_CRM_65774D897D212'::text)))
            ELSE NULL::text
        END AS motivo_perda,
    NULLIF(concat_ws('
'::text, pn_crm.bx_txt((d.c ->> 'COMMENTS'::text)), ('Origem no Bitrix: '::text || COALESCE(( SELECT src.nome
           FROM src
          WHERE (src.id = (d.c ->> 'SOURCE_ID'::text))), (d.c ->> 'SOURCE_ID'::text))), ('Tipo de contrato: '::text || ( SELECT string_agg(fx.v, ', '::text) AS string_agg
           FROM (jsonb_array_elements_text(
                CASE
                    WHEN (jsonb_typeof((d.c -> 'UF_CRM_1712256341158'::text)) = 'array'::text) THEN (d.c -> 'UF_CRM_1712256341158'::text)
                    WHEN (jsonb_typeof((d.c -> 'UF_CRM_1712256341158'::text)) = ANY (ARRAY['string'::text, 'number'::text])) THEN jsonb_build_array((d.c -> 'UF_CRM_1712256341158'::text))
                    ELSE '[]'::jsonb
                END) v(value)
             JOIN fx ON ((fx.id = v.value))))), ('Vencimento do contrato (Bitrix): '::text || to_char(((NULLIF("left"((d.c ->> 'UF_CRM_1701218046'::text), 10), ''::text))::date)::timestamp with time zone, 'DD/MM/YYYY'::text)), ('Bitrix #'::text || d.id)), ''::text) AS observacao,
    ((d.c ->> 'DATE_CREATE'::text))::timestamp with time zone AS criado_em,
    COALESCE(((d.c ->> 'MOVED_TIME'::text))::timestamp with time zone, ((d.c ->> 'DATE_MODIFY'::text))::timestamp with time zone, ((d.c ->> 'DATE_CREATE'::text))::timestamp with time zone) AS entrou_etapa_em,
        CASE
            WHEN (((d.c ->> 'CLOSED'::text) = 'Y'::text) OR (e.tipo <> 'aberta'::pn_crm.tipo_etapa)) THEN COALESCE(((d.c ->> 'MOVED_TIME'::text))::timestamp with time zone, ((d.c ->> 'DATE_MODIFY'::text))::timestamp with time zone)
            ELSE NULL::timestamp with time zone
        END AS fechado_em,
    ((d.c ->> 'DATE_MODIFY'::text))::timestamp with time zone AS modificado,
    (NULLIF((d.c ->> 'COMPANY_ID'::text), '0'::text))::bigint AS bitrix_empresa,
    pn_crm.bx_funcionarios((d.c -> 'UF_CRM_1712255766581'::text), (d.c ->> 'UF_CRM_65F2EFB719D39'::text)) AS qtd_funcionarios,
    pg.forma AS forma_pagamento,
    COALESCE(pg.parcelas, (NULLIF("substring"((d.c ->> 'UF_CRM_1709057765'::text), '(\d{1,2})\s*[xX]'::text), ''::text))::smallint) AS parcelas
   FROM (((((((d
     JOIN pn_crm.bitrix_etapa be2 ON ((be2.stage_id = (d.c ->> 'STAGE_ID'::text))))
     JOIN pn_crm.funil f ON ((f.slug = be2.funil_slug)))
     JOIN pn_crm.etapa e ON (((e.funil_id = f.id) AND (e.nome = be2.etapa_nome))))
     LEFT JOIN pn_crm.bitrix_empresa be ON ((be.bitrix_id = (NULLIF((d.c ->> 'COMPANY_ID'::text), '0'::text))::bigint)))
     LEFT JOIN ct ON ((ct.deal_id = d.id)))
     LEFT JOIN co cc ON ((cc.id = COALESCE(ct.contato, (NULLIF((d.c ->> 'CONTACT_ID'::text), '0'::text))::bigint))))
     LEFT JOIN LATERAL pn_crm.bx_pagamento(COALESCE(( SELECT fx.v
           FROM fx
          WHERE (fx.id = NULLIF((d.c ->> 'UF_CRM_1710182111'::text), ''::text))), ( SELECT fx.v
           FROM fx
          WHERE (fx.id = NULLIF((d.c ->> 'UF_CRM_65F2EFB741D5A'::text), ''::text))))) pg(forma, parcelas) ON (true));

CREATE TABLE pn_crm.wa_config (
    id boolean DEFAULT true NOT NULL,
    inbox_url text DEFAULT 'https://painel.exemplo.com.br/inbox'::text NOT NULL,
    criar_negocio boolean DEFAULT false NOT NULL,
    funil_id uuid,
    token_hash text,
    token_gerado_em timestamp with time zone,
    ultimo_recebimento timestamp with time zone,
    CONSTRAINT wa_config_id_check CHECK (id)
);

CREATE TABLE pn_crm.wa_contato (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ext_lead_id uuid NOT NULL,
    ext_conversa_id uuid,
    nome text,
    telefone text,
    status text,
    ultima_mensagem text,
    ultima_direcao text,
    ultima_em timestamp with time zone,
    mensagens integer DEFAULT 0 NOT NULL,
    primeiro_em timestamp with time zone DEFAULT now() NOT NULL,
    empresa_id uuid,
    negocio_id uuid,
    ignorado boolean DEFAULT false NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT wa_contato_ultima_direcao_check CHECK ((ultima_direcao = ANY (ARRAY['in'::text, 'out'::text])))
);

CREATE TABLE pn_crm.wa_historico_conversa (
    chat_id bigint NOT NULL,
    nome text,
    canal text,
    telefone text,
    bitrix_deal bigint,
    bitrix_contato bigint,
    bitrix_empresa bigint,
    negocio_id uuid,
    empresa_id uuid,
    iniciada_em timestamp with time zone,
    ultima_em timestamp with time zone,
    mensagens integer DEFAULT 0 NOT NULL,
    ultima_texto text
);

CREATE TABLE pn_crm.wa_historico_msg (
    id bigint NOT NULL,
    chat_id bigint NOT NULL,
    em timestamp with time zone NOT NULL,
    quem text NOT NULL,
    autor text,
    texto text,
    arquivos text,
    CONSTRAINT wa_historico_msg_quem_check CHECK ((quem = ANY (ARRAY['cliente'::text, 'equipe'::text, 'sistema'::text])))
);

CREATE TABLE pn_crm.wa_modelo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    titulo text NOT NULL,
    categoria text DEFAULT 'geral'::text NOT NULL,
    texto text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    ordem integer DEFAULT 0 NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT wa_modelo_categoria_check CHECK ((categoria = ANY (ARRAY['geral'::text, 'comercial'::text, 'agendamento'::text, 'exames'::text, 'cobranca'::text, 'documentos'::text])))
);

CREATE TABLE pn_crm.wa_saida (
    id bigint NOT NULL,
    telefone text NOT NULL,
    texto text NOT NULL,
    origem text NOT NULL,
    ref_id text,
    status text DEFAULT 'pendente'::text NOT NULL,
    tentativas integer DEFAULT 0 NOT NULL,
    erro text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    enviado_em timestamp with time zone,
    para text DEFAULT 'equipe'::text NOT NULL,
    empresa_id uuid,
    usuario_id uuid,
    CONSTRAINT wa_saida_para_check CHECK ((para = ANY (ARRAY['equipe'::text, 'cliente'::text]))),
    CONSTRAINT wa_saida_status_check CHECK ((status = ANY (ARRAY['pendente'::text, 'enviado'::text, 'erro'::text, 'cancelado'::text])))
);

ALTER TABLE pn_crm.wa_saida ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME pn_crm.wa_saida_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE pn.agente_quimico (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sesmo_id text,
    nome text NOT NULL,
    numero_cas text,
    limite_tolerancia text,
    unidade_medida text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.agente_quimico FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.anamnese_resposta (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ficha_clinica_id uuid NOT NULL,
    bloco text,
    pergunta_codigo text,
    pergunta_texto text NOT NULL,
    resposta text,
    observacao text,
    ordem integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.anamnese_resposta FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.atendimento_arquivo (
    atendimento_id uuid NOT NULL,
    arquivo_id uuid NOT NULL,
    papel text DEFAULT 'aso'::text NOT NULL
);

ALTER TABLE ONLY pn.atendimento_arquivo FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.cat (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    colaborador_id uuid,
    sesmo_id text,
    numero text,
    tipo text,
    data_acidente timestamp with time zone,
    data_emissao date,
    cid text,
    parte_corpo text,
    afastamento_dias integer,
    descricao text,
    arquivo_path text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.cat FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.cat_arquivo (
    cat_id uuid NOT NULL,
    arquivo_id uuid NOT NULL,
    papel text DEFAULT 'principal'::text NOT NULL
);

ALTER TABLE ONLY pn.cat_arquivo FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.cbo (
    codigo text NOT NULL,
    descricao text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.cbo FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.documento_arquivo (
    documento_id uuid NOT NULL,
    arquivo_id uuid NOT NULL,
    papel text DEFAULT 'principal'::text NOT NULL
);

ALTER TABLE ONLY pn.documento_arquivo FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.empresa_contato (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id uuid NOT NULL,
    nome text,
    cargo text,
    email text,
    telefone text,
    tipo text,
    recebe_alerta_exame boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    campos_editados text[] DEFAULT '{}'::text[] NOT NULL,
    origem text DEFAULT 'sesmo'::text NOT NULL
);

ALTER TABLE ONLY pn.empresa_contato FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.exame_fisico (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ficha_clinica_id uuid NOT NULL,
    pressao_sistolica integer,
    pressao_diastolica integer,
    frequencia_cardiaca integer,
    frequencia_respiratoria integer,
    peso_kg numeric(6,2),
    altura_cm numeric(5,1),
    imc numeric(5,2) GENERATED ALWAYS AS (
CASE
    WHEN (altura_cm > (0)::numeric) THEN (peso_kg / ((altura_cm / (100)::numeric) * (altura_cm / (100)::numeric)))
    ELSE NULL::numeric
END) STORED,
    temperatura_c numeric(4,1),
    achados jsonb DEFAULT '{}'::jsonb NOT NULL,
    observacao text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.exame_fisico FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.funcao_cargo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    funcao_id uuid NOT NULL,
    sesmo_id text NOT NULL,
    nome text,
    atividade text,
    cbo_codigo text,
    principal boolean,
    situacao text,
    sesmo_situacao_codigo text,
    numero_funcionarios integer,
    extraido_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE pn.funcao_exame (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    funcao_id uuid NOT NULL,
    sesmo_id text NOT NULL,
    exame_tipo_id uuid,
    exame_nome text NOT NULL,
    exame_codigo text,
    obrigatorio boolean DEFAULT true NOT NULL,
    ocupacional boolean DEFAULT true NOT NULL,
    no_admissional boolean DEFAULT false NOT NULL,
    no_periodico boolean DEFAULT false NOT NULL,
    no_demissional boolean DEFAULT false NOT NULL,
    no_mudanca_funcao boolean DEFAULT false NOT NULL,
    no_retorno boolean DEFAULT false NOT NULL,
    periodicidade_texto text,
    periodicidade_meses integer,
    primeira_meses integer,
    sesmo_data_alteracao timestamp with time zone
);

CREATE TABLE pn.funcao_risco (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    documento_id uuid NOT NULL,
    funcao_id uuid NOT NULL,
    risco_id uuid NOT NULL,
    intensidade text,
    tecnica_medicao text,
    tempo_exposicao text,
    medidas_controle text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.funcao_risco FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.funcao_risco_epc (
    funcao_risco_id uuid NOT NULL,
    epc_id uuid NOT NULL
);

ALTER TABLE ONLY pn.funcao_risco_epc FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.funcao_risco_epi (
    funcao_risco_id uuid NOT NULL,
    epi_id uuid NOT NULL
);

ALTER TABLE ONLY pn.funcao_risco_epi FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.pcmso_exame_fisico_funcao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    documento_id uuid NOT NULL,
    funcao_id uuid NOT NULL,
    exame_tipo_id uuid NOT NULL,
    obrigatorio boolean DEFAULT true NOT NULL,
    observacao text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.pcmso_exame_fisico_funcao FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.pcmso_vacina_funcao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    documento_id uuid NOT NULL,
    funcao_id uuid NOT NULL,
    vacina_id uuid NOT NULL,
    obrigatoria boolean DEFAULT true NOT NULL
);

ALTER TABLE ONLY pn.pcmso_vacina_funcao FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.plano_acao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    documento_id uuid NOT NULL,
    unidade_id uuid,
    setor_id uuid,
    sesmo_id text,
    descricao text NOT NULL,
    responsavel text,
    prazo date,
    situacao text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plano_acao_um_nivel CHECK ((num_nonnulls(unidade_id, setor_id) = 1))
);

ALTER TABLE ONLY pn.plano_acao FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.risco (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sesmo_id text,
    nome text NOT NULL,
    grupo pn.grupo_risco DEFAULT 'inespecifico'::pn.grupo_risco NOT NULL,
    agente_quimico_id uuid,
    fonte_geradora text,
    danos_a_saude text,
    limite_tolerancia text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn.risco FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.risco_epc (
    risco_id uuid NOT NULL,
    epc_id uuid NOT NULL
);

ALTER TABLE ONLY pn.risco_epc FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.risco_epi (
    risco_id uuid NOT NULL,
    epi_id uuid NOT NULL
);

ALTER TABLE ONLY pn.risco_epi FORCE ROW LEVEL SECURITY;

CREATE TABLE pn.risco_exame (
    risco_id uuid NOT NULL,
    exame_tipo_id uuid NOT NULL
);

ALTER TABLE ONLY pn.risco_exame FORCE ROW LEVEL SECURITY;

CREATE SEQUENCE pn_sesmo.captura_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE pn_sesmo.captura_id_seq OWNED BY pn_sesmo.captura.id;

CREATE TABLE pn_sesmo.conferencia (
    id bigint NOT NULL,
    modulo text NOT NULL,
    escopo text,
    esperado integer,
    carregado integer,
    conferido_em timestamp with time zone DEFAULT now() NOT NULL,
    observacao text
);

CREATE SEQUENCE pn_sesmo.conferencia_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE pn_sesmo.conferencia_id_seq OWNED BY pn_sesmo.conferencia.id;

CREATE TABLE pn_sesmo.correcao_texto (
    id bigint NOT NULL,
    de text NOT NULL,
    para text NOT NULL,
    motivo text,
    confirmado_por text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE pn_sesmo.correcao_texto_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE pn_sesmo.correcao_texto_id_seq OWNED BY pn_sesmo.correcao_texto.id;

CREATE TABLE pn_sesmo.fila_chave (
    modulo text NOT NULL,
    chave text NOT NULL
);

CREATE TABLE pn_sesmo.fila_excluida (
    modulo text NOT NULL,
    chave text NOT NULL,
    motivo text NOT NULL,
    evidencia jsonb,
    excluida_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE pn_sesmo.fonte (
    modulo text NOT NULL,
    caminho text,
    formato text,
    params jsonb DEFAULT '{}'::jsonb,
    particiona_situacao boolean DEFAULT false,
    situacoes integer[],
    param_pai text,
    fonte_pai text,
    fontes_pai text[],
    campo_filhos text,
    limite integer,
    ativo boolean DEFAULT true,
    ordem integer,
    observacao text,
    host text,
    modelo text,
    chave_com_pai boolean DEFAULT false,
    campo_chave_pai text
);

CREATE TABLE pn_sesmo.ingestao_token (
    token text NOT NULL,
    descricao text,
    criado_em timestamp with time zone DEFAULT now(),
    revogado boolean DEFAULT false,
    ultimo_uso timestamp with time zone
);

CREATE TABLE pn_sesmo.job (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    modulo text NOT NULL,
    escopo jsonb DEFAULT '{}'::jsonb NOT NULL,
    status text DEFAULT 'pendente'::text NOT NULL,
    itens_total integer,
    itens_ok integer DEFAULT 0 NOT NULL,
    itens_erro integer DEFAULT 0 NOT NULL,
    iniciado_em timestamp with time zone,
    finalizado_em timestamp with time zone,
    erro text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE pn_sesmo.job_item (
    id bigint NOT NULL,
    job_id uuid NOT NULL,
    chave text NOT NULL,
    status text DEFAULT 'pendente'::text NOT NULL,
    tentativas integer DEFAULT 0 NOT NULL,
    ultimo_erro text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE pn_sesmo.job_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE pn_sesmo.job_item_id_seq OWNED BY pn_sesmo.job_item.id;

CREATE TABLE pn_sesmo.mapeamento (
    entidade text NOT NULL,
    sesmo_id text NOT NULL,
    destino_id uuid NOT NULL,
    contexto text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY pn_bitrix.captura ALTER COLUMN id SET DEFAULT nextval('pn_bitrix.captura_id_seq'::regclass);

ALTER TABLE ONLY pn_sesmo.captura ALTER COLUMN id SET DEFAULT nextval('pn_sesmo.captura_id_seq'::regclass);

ALTER TABLE ONLY pn_sesmo.conferencia ALTER COLUMN id SET DEFAULT nextval('pn_sesmo.conferencia_id_seq'::regclass);

ALTER TABLE ONLY pn_sesmo.correcao_texto ALTER COLUMN id SET DEFAULT nextval('pn_sesmo.correcao_texto_id_seq'::regclass);

ALTER TABLE ONLY pn_sesmo.job_item ALTER COLUMN id SET DEFAULT nextval('pn_sesmo.job_item_id_seq'::regclass);

ALTER TABLE ONLY pn_app.vencimento_exame
    ADD CONSTRAINT vencimento_exame_pkey PRIMARY KEY (colaborador_id, exame);

ALTER TABLE ONLY pn_app.vencimento
    ADD CONSTRAINT vencimento_pkey PRIMARY KEY (colaborador_id);

ALTER TABLE ONLY pn_bitrix.captura
    ADD CONSTRAINT captura_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.admin_inicial
    ADD CONSTRAINT admin_inicial_pkey PRIMARY KEY (email);

ALTER TABLE ONLY pn_crm.agenda_grade
    ADD CONSTRAINT agenda_grade_pkey PRIMARY KEY (horario);

ALTER TABLE ONLY pn_crm.agenda_limite_empresa
    ADD CONSTRAINT agenda_limite_empresa_pkey PRIMARY KEY (empresa_id);

ALTER TABLE ONLY pn_crm.agenda
    ADD CONSTRAINT agenda_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.agenda_regra
    ADD CONSTRAINT agenda_regra_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.agendamento_evento
    ADD CONSTRAINT agendamento_evento_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.agendamento
    ADD CONSTRAINT agendamento_numero_key UNIQUE (numero);

ALTER TABLE ONLY pn_crm.agendamento
    ADD CONSTRAINT agendamento_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.atestado_alerta
    ADD CONSTRAINT atestado_alerta_pkey PRIMARY KEY (empresa_id, mes);

ALTER TABLE ONLY pn_crm.atestado
    ADD CONSTRAINT atestado_numero_key UNIQUE (numero);

ALTER TABLE ONLY pn_crm.atestado
    ADD CONSTRAINT atestado_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.atestado_regra
    ADD CONSTRAINT atestado_regra_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.bitrix_empresa
    ADD CONSTRAINT bitrix_empresa_pkey PRIMARY KEY (bitrix_id);

ALTER TABLE ONLY pn_crm.bitrix_etapa
    ADD CONSTRAINT bitrix_etapa_pkey PRIMARY KEY (stage_id);

ALTER TABLE ONLY pn_crm.bitrix_usuario
    ADD CONSTRAINT bitrix_usuario_pkey PRIMARY KEY (bitrix_id);

ALTER TABLE ONLY pn_crm.chat_membro
    ADD CONSTRAINT chat_membro_pkey PRIMARY KEY (sala_id, user_id);

ALTER TABLE ONLY pn_crm.chat_mensagem
    ADD CONSTRAINT chat_mensagem_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.chat_sala
    ADD CONSTRAINT chat_sala_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.cobranca_evento
    ADD CONSTRAINT cobranca_evento_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.cobranca
    ADD CONSTRAINT cobranca_numero_key UNIQUE (numero);

ALTER TABLE ONLY pn_crm.cobranca
    ADD CONSTRAINT cobranca_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.contrato_evento
    ADD CONSTRAINT contrato_evento_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.contrato_item
    ADD CONSTRAINT contrato_item_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.contrato
    ADD CONSTRAINT contrato_numero_key UNIQUE (numero);

ALTER TABLE ONLY pn_crm.contrato
    ADD CONSTRAINT contrato_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.documento_regra
    ADD CONSTRAINT documento_regra_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.documento_renovacao
    ADD CONSTRAINT documento_renovacao_pkey PRIMARY KEY (documento_id);

ALTER TABLE ONLY pn_crm.edicao
    ADD CONSTRAINT edicao_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.empresa_interacao
    ADD CONSTRAINT empresa_interacao_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.etapa
    ADD CONSTRAINT etapa_funil_id_nome_key UNIQUE (funil_id, nome);

ALTER TABLE ONLY pn_crm.etapa
    ADD CONSTRAINT etapa_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.evento
    ADD CONSTRAINT evento_bitrix_ref_key UNIQUE (bitrix_ref);

ALTER TABLE ONLY pn_crm.evento
    ADD CONSTRAINT evento_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.fin_regra
    ADD CONSTRAINT fin_regra_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.funil
    ADD CONSTRAINT funil_nome_key UNIQUE (nome);

ALTER TABLE ONLY pn_crm.funil
    ADD CONSTRAINT funil_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.funil
    ADD CONSTRAINT funil_slug_key UNIQUE (slug);

ALTER TABLE ONLY pn_crm.negocio
    ADD CONSTRAINT negocio_bitrix_id_key UNIQUE (bitrix_id);

ALTER TABLE ONLY pn_crm.negocio_item
    ADD CONSTRAINT negocio_item_bitrix_id_key UNIQUE (bitrix_id);

ALTER TABLE ONLY pn_crm.negocio_item
    ADD CONSTRAINT negocio_item_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.negocio
    ADD CONSTRAINT negocio_numero_key UNIQUE (numero);

ALTER TABLE ONLY pn_crm.negocio
    ADD CONSTRAINT negocio_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.notificacao
    ADD CONSTRAINT notificacao_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.perfil
    ADD CONSTRAINT perfil_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY pn_crm.posvenda_regra
    ADD CONSTRAINT posvenda_regra_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.pre_cadastro
    ADD CONSTRAINT pre_cadastro_pkey PRIMARY KEY (email);

ALTER TABLE ONLY pn_crm.produto
    ADD CONSTRAINT produto_codigo_key UNIQUE (codigo);

ALTER TABLE ONLY pn_crm.produto
    ADD CONSTRAINT produto_nome_key UNIQUE (nome);

ALTER TABLE ONLY pn_crm.produto
    ADD CONSTRAINT produto_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.quadro
    ADD CONSTRAINT quadro_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.rodizio_estado
    ADD CONSTRAINT rodizio_estado_pkey PRIMARY KEY (funil_id);

ALTER TABLE ONLY pn_crm.rodizio
    ADD CONSTRAINT rodizio_pkey PRIMARY KEY (funil_id, user_id);

ALTER TABLE ONLY pn_crm.tarefa_comentario
    ADD CONSTRAINT tarefa_comentario_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.tarefa_item
    ADD CONSTRAINT tarefa_item_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.tarefa
    ADD CONSTRAINT tarefa_numero_key UNIQUE (numero);

ALTER TABLE ONLY pn_crm.tarefa
    ADD CONSTRAINT tarefa_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.tunel
    ADD CONSTRAINT tunel_pkey PRIMARY KEY (funil_origem_id, funil_destino_id);

ALTER TABLE ONLY pn_crm.wa_config
    ADD CONSTRAINT wa_config_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.wa_contato
    ADD CONSTRAINT wa_contato_ext_lead_id_key UNIQUE (ext_lead_id);

ALTER TABLE ONLY pn_crm.wa_contato
    ADD CONSTRAINT wa_contato_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.wa_historico_conversa
    ADD CONSTRAINT wa_historico_conversa_pkey PRIMARY KEY (chat_id);

ALTER TABLE ONLY pn_crm.wa_historico_msg
    ADD CONSTRAINT wa_historico_msg_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.wa_modelo
    ADD CONSTRAINT wa_modelo_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_crm.wa_saida
    ADD CONSTRAINT wa_saida_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.agente_quimico
    ADD CONSTRAINT agente_quimico_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.agente_quimico
    ADD CONSTRAINT agente_quimico_sesmo_id_key UNIQUE (sesmo_id);

ALTER TABLE ONLY pn.anamnese_resposta
    ADD CONSTRAINT anamnese_resposta_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.arquivo
    ADD CONSTRAINT arquivo_gcs_bucket_gcs_object_key UNIQUE (gcs_bucket, gcs_object);

ALTER TABLE ONLY pn.arquivo
    ADD CONSTRAINT arquivo_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.atendimento_arquivo
    ADD CONSTRAINT atendimento_arquivo_pkey PRIMARY KEY (atendimento_id, arquivo_id, papel);

ALTER TABLE ONLY pn.atendimento
    ADD CONSTRAINT atendimento_empresa_id_sesmo_id_key UNIQUE (empresa_id, sesmo_id);

ALTER TABLE ONLY pn.atendimento_exame
    ADD CONSTRAINT atendimento_exame_atendimento_id_exame_tipo_id_key UNIQUE (atendimento_id, exame_tipo_id);

ALTER TABLE ONLY pn.atendimento_exame
    ADD CONSTRAINT atendimento_exame_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.atendimento
    ADD CONSTRAINT atendimento_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.cat_arquivo
    ADD CONSTRAINT cat_arquivo_pkey PRIMARY KEY (cat_id, arquivo_id, papel);

ALTER TABLE ONLY pn.cat
    ADD CONSTRAINT cat_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.cbo
    ADD CONSTRAINT cbo_pkey PRIMARY KEY (codigo);

ALTER TABLE ONLY pn.colaborador
    ADD CONSTRAINT colaborador_empresa_id_sesmo_id_key UNIQUE (empresa_id, sesmo_id);

ALTER TABLE ONLY pn.colaborador
    ADD CONSTRAINT colaborador_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.colaborador_vinculo
    ADD CONSTRAINT colaborador_vinculo_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.documento_arquivo
    ADD CONSTRAINT documento_arquivo_pkey PRIMARY KEY (documento_id, arquivo_id, papel);

ALTER TABLE ONLY pn.documento
    ADD CONSTRAINT documento_empresa_id_tipo_sesmo_id_key UNIQUE (empresa_id, tipo, sesmo_id);

ALTER TABLE ONLY pn.documento
    ADD CONSTRAINT documento_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.empresa_contato
    ADD CONSTRAINT empresa_contato_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.empresa
    ADD CONSTRAINT empresa_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.empresa
    ADD CONSTRAINT empresa_sesmo_id_key UNIQUE (sesmo_id);

ALTER TABLE ONLY pn.epc
    ADD CONSTRAINT epc_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.epc
    ADD CONSTRAINT epc_sesmo_id_key UNIQUE (sesmo_id);

ALTER TABLE ONLY pn.epi
    ADD CONSTRAINT epi_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.epi
    ADD CONSTRAINT epi_sesmo_id_key UNIQUE (sesmo_id);

ALTER TABLE ONLY pn.esocial_evento
    ADD CONSTRAINT esocial_evento_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.esocial_evento
    ADD CONSTRAINT esocial_evento_tipo_sesmo_id_key UNIQUE (tipo, sesmo_id);

ALTER TABLE ONLY pn.exame_fisico
    ADD CONSTRAINT exame_fisico_ficha_clinica_id_key UNIQUE (ficha_clinica_id);

ALTER TABLE ONLY pn.exame_fisico
    ADD CONSTRAINT exame_fisico_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.exame_tipo
    ADD CONSTRAINT exame_tipo_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.exame_tipo
    ADD CONSTRAINT exame_tipo_sesmo_id_key UNIQUE (sesmo_id);

ALTER TABLE ONLY pn.ficha_clinica
    ADD CONSTRAINT ficha_clinica_atendimento_id_key UNIQUE (atendimento_id);

ALTER TABLE ONLY pn.ficha_clinica
    ADD CONSTRAINT ficha_clinica_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.funcao_cargo
    ADD CONSTRAINT funcao_cargo_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.funcao_cargo
    ADD CONSTRAINT funcao_cargo_sesmo_id_key UNIQUE (sesmo_id);

ALTER TABLE ONLY pn.funcao_exame
    ADD CONSTRAINT funcao_exame_funcao_id_sesmo_id_key UNIQUE (funcao_id, sesmo_id);

ALTER TABLE ONLY pn.funcao_exame
    ADD CONSTRAINT funcao_exame_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.funcao
    ADD CONSTRAINT funcao_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.funcao_risco
    ADD CONSTRAINT funcao_risco_documento_id_funcao_id_risco_id_key UNIQUE (documento_id, funcao_id, risco_id);

ALTER TABLE ONLY pn.funcao_risco_epc
    ADD CONSTRAINT funcao_risco_epc_pkey PRIMARY KEY (funcao_risco_id, epc_id);

ALTER TABLE ONLY pn.funcao_risco_epi
    ADD CONSTRAINT funcao_risco_epi_pkey PRIMARY KEY (funcao_risco_id, epi_id);

ALTER TABLE ONLY pn.funcao_risco
    ADD CONSTRAINT funcao_risco_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.funcao
    ADD CONSTRAINT funcao_setor_id_sesmo_id_key UNIQUE (setor_id, sesmo_id);

ALTER TABLE ONLY pn.pcmso_exame_fisico_funcao
    ADD CONSTRAINT pcmso_exame_fisico_funcao_documento_id_funcao_id_exame_tipo_key UNIQUE (documento_id, funcao_id, exame_tipo_id);

ALTER TABLE ONLY pn.pcmso_exame_fisico_funcao
    ADD CONSTRAINT pcmso_exame_fisico_funcao_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.pcmso_exame_funcao
    ADD CONSTRAINT pcmso_exame_funcao_documento_id_funcao_id_exame_tipo_id_key UNIQUE (documento_id, funcao_id, exame_tipo_id);

ALTER TABLE ONLY pn.pcmso_exame_funcao
    ADD CONSTRAINT pcmso_exame_funcao_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.pcmso_vacina_funcao
    ADD CONSTRAINT pcmso_vacina_funcao_documento_id_funcao_id_vacina_id_key UNIQUE (documento_id, funcao_id, vacina_id);

ALTER TABLE ONLY pn.pcmso_vacina_funcao
    ADD CONSTRAINT pcmso_vacina_funcao_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.plano_acao
    ADD CONSTRAINT plano_acao_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.profissional
    ADD CONSTRAINT profissional_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.profissional
    ADD CONSTRAINT profissional_sesmo_id_key UNIQUE (sesmo_id);

ALTER TABLE ONLY pn.queixa
    ADD CONSTRAINT queixa_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.risco_epc
    ADD CONSTRAINT risco_epc_pkey PRIMARY KEY (risco_id, epc_id);

ALTER TABLE ONLY pn.risco_epi
    ADD CONSTRAINT risco_epi_pkey PRIMARY KEY (risco_id, epi_id);

ALTER TABLE ONLY pn.risco_exame
    ADD CONSTRAINT risco_exame_pkey PRIMARY KEY (risco_id, exame_tipo_id);

ALTER TABLE ONLY pn.risco
    ADD CONSTRAINT risco_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.risco
    ADD CONSTRAINT risco_sesmo_id_key UNIQUE (sesmo_id);

ALTER TABLE ONLY pn.setor
    ADD CONSTRAINT setor_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.setor
    ADD CONSTRAINT setor_unidade_id_sesmo_id_key UNIQUE (unidade_id, sesmo_id);

ALTER TABLE ONLY pn.unidade
    ADD CONSTRAINT unidade_empresa_id_sesmo_id_key UNIQUE (empresa_id, sesmo_id);

ALTER TABLE ONLY pn.unidade
    ADD CONSTRAINT unidade_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.vacina
    ADD CONSTRAINT vacina_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn.vacina
    ADD CONSTRAINT vacina_sesmo_id_key UNIQUE (sesmo_id);

ALTER TABLE ONLY pn_sesmo.baseline
    ADD CONSTRAINT baseline_pkey PRIMARY KEY (modulo);

ALTER TABLE ONLY pn_sesmo.captura
    ADD CONSTRAINT captura_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_sesmo.conferencia
    ADD CONSTRAINT conferencia_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_sesmo.correcao_texto
    ADD CONSTRAINT correcao_texto_de_key UNIQUE (de);

ALTER TABLE ONLY pn_sesmo.correcao_texto
    ADD CONSTRAINT correcao_texto_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_sesmo.fila_chave
    ADD CONSTRAINT fila_chave_pkey PRIMARY KEY (modulo, chave);

ALTER TABLE ONLY pn_sesmo.fila_excluida
    ADD CONSTRAINT fila_excluida_pkey PRIMARY KEY (modulo, chave);

ALTER TABLE ONLY pn_sesmo.fonte
    ADD CONSTRAINT fonte_pkey PRIMARY KEY (modulo);

ALTER TABLE ONLY pn_sesmo.ingestao_token
    ADD CONSTRAINT ingestao_token_pkey PRIMARY KEY (token);

ALTER TABLE ONLY pn_sesmo.job_item
    ADD CONSTRAINT job_item_job_id_chave_key UNIQUE (job_id, chave);

ALTER TABLE ONLY pn_sesmo.job_item
    ADD CONSTRAINT job_item_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_sesmo.job
    ADD CONSTRAINT job_pkey PRIMARY KEY (id);

ALTER TABLE ONLY pn_sesmo.mapeamento
    ADD CONSTRAINT mapeamento_pkey PRIMARY KEY (entidade, sesmo_id, contexto);

CREATE INDEX vencimento_empresa ON pn_app.vencimento USING btree (empresa_id, status);

CREATE INDEX vencimento_status ON pn_app.vencimento USING btree (status, dias_para_vencer);

CREATE INDEX agenda_data_idx ON pn_crm.agenda USING btree (data, profissional_id);

CREATE INDEX agendamento_agenda_idx ON pn_crm.agendamento USING btree (agenda_id, situacao);

CREATE INDEX agendamento_empresa_idx ON pn_crm.agendamento USING btree (empresa_id);

CREATE INDEX agendamento_evento_idx ON pn_crm.agendamento_evento USING btree (agendamento_id, criado_em);

CREATE INDEX atestado_empresa_mes_idx ON pn_crm.atestado USING btree (empresa_id, mes) WHERE (situacao = 'ok'::text);

CREATE INDEX atestado_situacao_idx ON pn_crm.atestado USING btree (situacao, criado_em DESC);

CREATE UNIQUE INDEX atestado_wa_msg_uq ON pn_crm.atestado USING btree (wa_mensagem_id) WHERE (wa_mensagem_id IS NOT NULL);

CREATE INDEX chat_membro_user ON pn_crm.chat_membro USING btree (user_id);

CREATE INDEX chat_mensagem_sala ON pn_crm.chat_mensagem USING btree (sala_id, id DESC);

CREATE UNIQUE INDEX chat_sala_geral ON pn_crm.chat_sala USING btree (tipo) WHERE (tipo = 'geral'::text);

CREATE INDEX cobranca_comp_idx ON pn_crm.cobranca USING btree (competencia);

CREATE UNIQUE INDEX cobranca_contrato_mes_uq ON pn_crm.cobranca USING btree (contrato_id, competencia) WHERE ((contrato_id IS NOT NULL) AND (NOT cancelada));

CREATE INDEX cobranca_empresa_idx ON pn_crm.cobranca USING btree (empresa_id);

CREATE INDEX cobranca_venc_idx ON pn_crm.cobranca USING btree (vencimento) WHERE ((pago_em IS NULL) AND (NOT cancelada));

CREATE INDEX contrato_empresa_idx ON pn_crm.contrato USING btree (empresa_id);

CREATE INDEX contrato_evento_idx ON pn_crm.contrato_evento USING btree (contrato_id, criado_em);

CREATE INDEX contrato_fim_idx ON pn_crm.contrato USING btree (fim) WHERE (status = 'assinado'::text);

CREATE INDEX contrato_item_idx ON pn_crm.contrato_item USING btree (contrato_id);

CREATE UNIQUE INDEX contrato_negocio_uq ON pn_crm.contrato USING btree (negocio_id) WHERE (negocio_id IS NOT NULL);

CREATE INDEX edicao_registro_idx ON pn_crm.edicao USING btree (tabela, registro_id, em DESC);

CREATE INDEX empresa_interacao_emp_idx ON pn_crm.empresa_interacao USING btree (empresa_id, em DESC);

CREATE INDEX etapa_funil_idx ON pn_crm.etapa USING btree (funil_id, ordem);

CREATE INDEX evento_negocio_idx ON pn_crm.evento USING btree (negocio_id, criado_em DESC);

CREATE INDEX negocio_bitrix_empresa_idx ON pn_crm.negocio USING btree (bitrix_empresa) WHERE (bitrix_empresa IS NOT NULL);

CREATE INDEX negocio_empresa_idx ON pn_crm.negocio USING btree (empresa_id);

CREATE INDEX negocio_funil_etapa_idx ON pn_crm.negocio USING btree (funil_id, etapa_id);

CREATE INDEX negocio_item_negocio_idx ON pn_crm.negocio_item USING btree (negocio_id);

CREATE UNIQUE INDEX negocio_origem_funil_uq ON pn_crm.negocio USING btree (negocio_origem_id, funil_id) WHERE (negocio_origem_id IS NOT NULL);

CREATE INDEX negocio_responsavel_idx ON pn_crm.negocio USING btree (responsavel_id);

CREATE INDEX notificacao_user_idx ON pn_crm.notificacao USING btree (user_id, lida_em, criado_em DESC);

CREATE INDEX tarefa_comentario_idx ON pn_crm.tarefa_comentario USING btree (tarefa_id, criado_em);

CREATE INDEX tarefa_item_idx ON pn_crm.tarefa_item USING btree (tarefa_id, ordem);

CREATE INDEX tarefa_quadro_idx ON pn_crm.tarefa USING btree (quadro_id, status, ordem);

CREATE INDEX tarefa_resp_idx ON pn_crm.tarefa USING btree (responsavel_id) WHERE (status <> 'feito'::text);

CREATE INDEX tarefa_responsaveis_idx ON pn_crm.tarefa USING gin (responsaveis);

CREATE INDEX wa_contato_negocio_idx ON pn_crm.wa_contato USING btree (negocio_id);

CREATE INDEX wa_contato_ultima_idx ON pn_crm.wa_contato USING btree (ultima_em DESC NULLS LAST);

CREATE INDEX wa_hist_conv_emp_idx ON pn_crm.wa_historico_conversa USING btree (empresa_id);

CREATE INDEX wa_hist_conv_tel_idx ON pn_crm.wa_historico_conversa USING btree ("right"(telefone, 8));

CREATE INDEX wa_hist_msg_chat_idx ON pn_crm.wa_historico_msg USING btree (chat_id, em);

CREATE INDEX wa_saida_pend_idx ON pn_crm.wa_saida USING btree (criado_em) WHERE (status = 'pendente'::text);

CREATE INDEX anamnese_resposta_ficha_clinica_id_ordem_idx ON pn.anamnese_resposta USING btree (ficha_clinica_id, ordem);

CREATE INDEX arquivo_origem_idx ON pn.arquivo USING btree (origem);

CREATE INDEX arquivo_sha256_idx ON pn.arquivo USING btree (sha256);

CREATE INDEX atendimento_colaborador_id_data_atendimento_idx ON pn.atendimento USING btree (colaborador_id, data_atendimento DESC);

CREATE INDEX atendimento_data_agendada_idx ON pn.atendimento USING btree (data_agendada) WHERE (situacao = ANY (ARRAY['agendado'::pn.situacao_atendimento, 'aguardando'::pn.situacao_atendimento]));

CREATE INDEX atendimento_empresa_id_data_atendimento_idx ON pn.atendimento USING btree (empresa_id, data_atendimento DESC);

CREATE INDEX atendimento_exame_exame_tipo_id_data_realizacao_idx ON pn.atendimento_exame USING btree (exame_tipo_id, data_realizacao DESC);

CREATE INDEX atendimento_sesmo_data_alteracao_idx ON pn.atendimento USING btree (sesmo_data_alteracao DESC NULLS LAST);

CREATE INDEX cat_empresa_id_data_acidente_idx ON pn.cat USING btree (empresa_id, data_acidente DESC);

CREATE INDEX colaborador_digits_idx ON pn.colaborador USING btree (pn_app.digits(cpf));

CREATE INDEX colaborador_empresa_id_situacao_idx ON pn.colaborador USING btree (empresa_id, situacao);

CREATE INDEX colaborador_funcao_idx ON pn.colaborador USING btree (funcao_id);

CREATE INDEX colaborador_norm_idx ON pn.colaborador USING gin (pn_app.norm(nome) public.gin_trgm_ops);

CREATE INDEX colaborador_sesmo_data_alteracao_idx ON pn.colaborador USING btree (sesmo_data_alteracao DESC NULLS LAST);

CREATE INDEX colaborador_vinculo_colaborador_id_data_inicio_idx ON pn.colaborador_vinculo USING btree (colaborador_id, data_inicio DESC);

CREATE UNIQUE INDEX colaborador_vinculo_colaborador_id_idx ON pn.colaborador_vinculo USING btree (colaborador_id) WHERE (data_fim IS NULL);

CREATE INDEX documento_empresa_id_tipo_idx ON pn.documento USING btree (empresa_id, tipo) WHERE (situacao = 'vigente'::pn.situacao_documento);

CREATE INDEX documento_empresa_id_tipo_vigencia_fim_idx ON pn.documento USING btree (empresa_id, tipo, vigencia_fim DESC);

CREATE INDEX documento_sesmo_data_alteracao_idx ON pn.documento USING btree (sesmo_data_alteracao DESC NULLS LAST);

CREATE INDEX empresa_contato_empresa_id_idx ON pn.empresa_contato USING btree (empresa_id);

CREATE UNIQUE INDEX empresa_digits_idx ON pn.empresa USING btree (pn_app.digits(cnpj)) WHERE (cnpj IS NOT NULL);

CREATE INDEX empresa_norm_idx ON pn.empresa USING gin (pn_app.norm(razao_social) public.gin_trgm_ops);

CREATE INDEX empresa_sesmo_data_alteracao_idx ON pn.empresa USING btree (sesmo_data_alteracao DESC NULLS LAST);

CREATE INDEX esocial_evento_colaborador_id_data_evento_idx ON pn.esocial_evento USING btree (colaborador_id, data_evento DESC);

CREATE INDEX esocial_evento_empresa_id_tipo_idx ON pn.esocial_evento USING btree (empresa_id, tipo);

CREATE INDEX esocial_evento_situacao_idx ON pn.esocial_evento USING btree (situacao) WHERE (situacao <> 'processado'::pn.situacao_evento_esocial);

CREATE INDEX exame_tipo_nome_idx ON pn.exame_tipo USING btree (pn_app.norm(nome));

CREATE INDEX ficha_clinica_colaborador_id_data_referencia_idx ON pn.ficha_clinica USING btree (colaborador_id, data_referencia DESC);

CREATE INDEX ficha_clinica_sesmo_data_alteracao_idx ON pn.ficha_clinica USING btree (sesmo_data_alteracao DESC NULLS LAST);

CREATE INDEX funcao_cargo_funcao_idx ON pn.funcao_cargo USING btree (funcao_id);

CREATE INDEX funcao_exame_funcao ON pn.funcao_exame USING btree (funcao_id);

CREATE INDEX funcao_risco_funcao_id_idx ON pn.funcao_risco USING btree (funcao_id);

CREATE INDEX funcao_sesmo_data_alteracao_idx ON pn.funcao USING btree (sesmo_data_alteracao DESC NULLS LAST);

CREATE INDEX funcao_setor_id_idx ON pn.funcao USING btree (setor_id);

CREATE INDEX pcmso_exame_funcao_documento_id_idx ON pn.pcmso_exame_funcao USING btree (documento_id);

CREATE INDEX pcmso_exame_funcao_funcao_id_idx ON pn.pcmso_exame_funcao USING btree (funcao_id);

CREATE INDEX pcmso_exame_funcao_sesmo_data_alteracao_idx ON pn.pcmso_exame_funcao USING btree (sesmo_data_alteracao DESC NULLS LAST);

CREATE INDEX plano_acao_documento_id_idx ON pn.plano_acao USING btree (documento_id);

CREATE INDEX queixa_ficha_clinica_id_idx ON pn.queixa USING btree (ficha_clinica_id);

CREATE INDEX setor_sesmo_data_alteracao_idx ON pn.setor USING btree (sesmo_data_alteracao DESC NULLS LAST);

CREATE INDEX setor_unidade_id_idx ON pn.setor USING btree (unidade_id);

CREATE INDEX unidade_empresa_id_idx ON pn.unidade USING btree (empresa_id);

CREATE INDEX unidade_sesmo_data_alteracao_idx ON pn.unidade USING btree (sesmo_data_alteracao DESC NULLS LAST);

CREATE UNIQUE INDEX captura_modulo_chave_hash_idx ON pn_sesmo.captura USING btree (modulo, chave, hash);

CREATE INDEX captura_modulo_chave_idx ON pn_sesmo.captura USING btree (modulo, chave);

CREATE INDEX captura_modulo_idx ON pn_sesmo.captura USING btree (modulo) WHERE (processado_em IS NULL);

CREATE INDEX job_item_job_id_status_idx ON pn_sesmo.job_item USING btree (job_id, status);

CREATE INDEX job_status_modulo_idx ON pn_sesmo.job USING btree (status, modulo);

CREATE TRIGGER atestado_antes BEFORE INSERT OR UPDATE ON pn_crm.atestado FOR EACH ROW EXECUTE FUNCTION pn_crm.tg_atestado_antes();

CREATE TRIGGER atestado_depois AFTER INSERT OR UPDATE ON pn_crm.atestado FOR EACH ROW EXECUTE FUNCTION pn_crm.tg_atestado_depois();

CREATE TRIGGER contrato_item_cobranca BEFORE INSERT ON pn_crm.contrato_item FOR EACH ROW EXECUTE FUNCTION pn_crm.tg_contrato_item_cobranca();

CREATE TRIGGER contrato_padroes BEFORE INSERT ON pn_crm.contrato FOR EACH ROW EXECUTE FUNCTION pn_crm.tg_contrato_padroes();

CREATE TRIGGER negocio_do_comercial BEFORE DELETE OR UPDATE ON pn_crm.negocio FOR EACH ROW EXECUTE FUNCTION pn_crm.tg_negocio_do_comercial();

CREATE TRIGGER negocio_ganho_contrato AFTER UPDATE OF etapa_id ON pn_crm.negocio FOR EACH ROW EXECUTE FUNCTION pn_crm.tg_negocio_ganho_contrato();

CREATE TRIGGER trg_tarefa_responsaveis BEFORE INSERT OR UPDATE OF responsavel_id, responsaveis ON pn_crm.tarefa FOR EACH ROW EXECUTE FUNCTION pn_crm.tg_tarefa_responsaveis();

CREATE TRIGGER trg_preserva_edicao BEFORE UPDATE ON pn.atendimento FOR EACH ROW EXECUTE FUNCTION pn_crm.tg_preserva_edicao();

CREATE TRIGGER trg_preserva_edicao BEFORE UPDATE ON pn.colaborador FOR EACH ROW EXECUTE FUNCTION pn_crm.tg_preserva_edicao();

CREATE TRIGGER trg_preserva_edicao BEFORE UPDATE ON pn.empresa FOR EACH ROW EXECUTE FUNCTION pn_crm.tg_preserva_edicao();

CREATE TRIGGER trg_preserva_edicao BEFORE UPDATE ON pn.empresa_contato FOR EACH ROW EXECUTE FUNCTION pn_crm.tg_preserva_edicao();

CREATE TRIGGER trg_preserva_edicao BEFORE UPDATE ON pn.unidade FOR EACH ROW EXECUTE FUNCTION pn_crm.tg_preserva_edicao();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.agente_quimico FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.atendimento FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.colaborador FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.documento FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.empresa FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.epc FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.epi FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.exame_tipo FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.funcao FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.profissional FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.risco FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.setor FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.unidade FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

CREATE TRIGGER trg_touch BEFORE UPDATE ON pn.vacina FOR EACH ROW EXECUTE FUNCTION pn_app.touch_updated_at();

ALTER TABLE ONLY pn_crm.agenda
    ADD CONSTRAINT agenda_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE RESTRICT;

ALTER TABLE ONLY pn_crm.agenda_limite_empresa
    ADD CONSTRAINT agenda_limite_empresa_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.agenda
    ADD CONSTRAINT agenda_profissional_id_fkey FOREIGN KEY (profissional_id) REFERENCES pn.profissional(id) ON DELETE RESTRICT;

ALTER TABLE ONLY pn_crm.agendamento
    ADD CONSTRAINT agendamento_agenda_id_fkey FOREIGN KEY (agenda_id) REFERENCES pn_crm.agenda(id) ON DELETE RESTRICT;

ALTER TABLE ONLY pn_crm.agendamento
    ADD CONSTRAINT agendamento_colaborador_id_fkey FOREIGN KEY (colaborador_id) REFERENCES pn.colaborador(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.agendamento
    ADD CONSTRAINT agendamento_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.agendamento_evento
    ADD CONSTRAINT agendamento_evento_agendamento_id_fkey FOREIGN KEY (agendamento_id) REFERENCES pn_crm.agendamento(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.agendamento
    ADD CONSTRAINT agendamento_negocio_id_fkey FOREIGN KEY (negocio_id) REFERENCES pn_crm.negocio(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.atestado_alerta
    ADD CONSTRAINT atestado_alerta_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.atestado_alerta
    ADD CONSTRAINT atestado_alerta_negocio_id_fkey FOREIGN KEY (negocio_id) REFERENCES pn_crm.negocio(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.atestado_alerta
    ADD CONSTRAINT atestado_alerta_responsavel_id_fkey FOREIGN KEY (responsavel_id) REFERENCES pn_crm.perfil(user_id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.atestado_alerta
    ADD CONSTRAINT atestado_alerta_tarefa_id_fkey FOREIGN KEY (tarefa_id) REFERENCES pn_crm.tarefa(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.atestado
    ADD CONSTRAINT atestado_colaborador_id_fkey FOREIGN KEY (colaborador_id) REFERENCES pn.colaborador(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.atestado
    ADD CONSTRAINT atestado_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.bitrix_empresa
    ADD CONSTRAINT bitrix_empresa_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.chat_membro
    ADD CONSTRAINT chat_membro_sala_id_fkey FOREIGN KEY (sala_id) REFERENCES pn_crm.chat_sala(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.chat_membro
    ADD CONSTRAINT chat_membro_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.chat_mensagem
    ADD CONSTRAINT chat_mensagem_autor_id_fkey FOREIGN KEY (autor_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.chat_mensagem
    ADD CONSTRAINT chat_mensagem_sala_id_fkey FOREIGN KEY (sala_id) REFERENCES pn_crm.chat_sala(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.chat_sala
    ADD CONSTRAINT chat_sala_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.cobranca
    ADD CONSTRAINT cobranca_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES pn_crm.contrato(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.cobranca
    ADD CONSTRAINT cobranca_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.cobranca_evento
    ADD CONSTRAINT cobranca_evento_cobranca_id_fkey FOREIGN KEY (cobranca_id) REFERENCES pn_crm.cobranca(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.contrato
    ADD CONSTRAINT contrato_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.contrato_evento
    ADD CONSTRAINT contrato_evento_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES pn_crm.contrato(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.contrato_item
    ADD CONSTRAINT contrato_item_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES pn_crm.contrato(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.contrato_item
    ADD CONSTRAINT contrato_item_produto_id_fkey FOREIGN KEY (produto_id) REFERENCES pn_crm.produto(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.contrato
    ADD CONSTRAINT contrato_negocio_id_fkey FOREIGN KEY (negocio_id) REFERENCES pn_crm.negocio(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.contrato
    ADD CONSTRAINT contrato_renovacao_negocio_id_fkey FOREIGN KEY (renovacao_negocio_id) REFERENCES pn_crm.negocio(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.contrato
    ADD CONSTRAINT contrato_responsavel_id_fkey FOREIGN KEY (responsavel_id) REFERENCES pn_crm.perfil(user_id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.documento_renovacao
    ADD CONSTRAINT documento_renovacao_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES pn.documento(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.documento_renovacao
    ADD CONSTRAINT documento_renovacao_negocio_id_fkey FOREIGN KEY (negocio_id) REFERENCES pn_crm.negocio(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.empresa_interacao
    ADD CONSTRAINT empresa_interacao_contato_id_fkey FOREIGN KEY (contato_id) REFERENCES pn.empresa_contato(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.empresa_interacao
    ADD CONSTRAINT empresa_interacao_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.etapa
    ADD CONSTRAINT etapa_funil_id_fkey FOREIGN KEY (funil_id) REFERENCES pn_crm.funil(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.evento
    ADD CONSTRAINT evento_de_etapa_id_fkey FOREIGN KEY (de_etapa_id) REFERENCES pn_crm.etapa(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.evento
    ADD CONSTRAINT evento_negocio_id_fkey FOREIGN KEY (negocio_id) REFERENCES pn_crm.negocio(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.evento
    ADD CONSTRAINT evento_para_etapa_id_fkey FOREIGN KEY (para_etapa_id) REFERENCES pn_crm.etapa(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.negocio
    ADD CONSTRAINT negocio_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.negocio
    ADD CONSTRAINT negocio_etapa_anterior_id_fkey FOREIGN KEY (etapa_anterior_id) REFERENCES pn_crm.etapa(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.negocio
    ADD CONSTRAINT negocio_etapa_id_fkey FOREIGN KEY (etapa_id) REFERENCES pn_crm.etapa(id);

ALTER TABLE ONLY pn_crm.negocio
    ADD CONSTRAINT negocio_funil_id_fkey FOREIGN KEY (funil_id) REFERENCES pn_crm.funil(id);

ALTER TABLE ONLY pn_crm.negocio_item
    ADD CONSTRAINT negocio_item_negocio_id_fkey FOREIGN KEY (negocio_id) REFERENCES pn_crm.negocio(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.negocio_item
    ADD CONSTRAINT negocio_item_produto_id_fkey FOREIGN KEY (produto_id) REFERENCES pn_crm.produto(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.negocio
    ADD CONSTRAINT negocio_negocio_origem_id_fkey FOREIGN KEY (negocio_origem_id) REFERENCES pn_crm.negocio(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.negocio
    ADD CONSTRAINT negocio_responsavel_id_fkey FOREIGN KEY (responsavel_id) REFERENCES pn_crm.perfil(user_id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.notificacao
    ADD CONSTRAINT notificacao_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES pn_crm.contrato(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.notificacao
    ADD CONSTRAINT notificacao_negocio_id_fkey FOREIGN KEY (negocio_id) REFERENCES pn_crm.negocio(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.notificacao
    ADD CONSTRAINT notificacao_tarefa_id_fkey FOREIGN KEY (tarefa_id) REFERENCES pn_crm.tarefa(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.notificacao
    ADD CONSTRAINT notificacao_user_id_fkey FOREIGN KEY (user_id) REFERENCES pn_crm.perfil(user_id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.perfil
    ADD CONSTRAINT perfil_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.rodizio_estado
    ADD CONSTRAINT rodizio_estado_funil_id_fkey FOREIGN KEY (funil_id) REFERENCES pn_crm.funil(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.rodizio
    ADD CONSTRAINT rodizio_funil_id_fkey FOREIGN KEY (funil_id) REFERENCES pn_crm.funil(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.rodizio
    ADD CONSTRAINT rodizio_user_id_fkey FOREIGN KEY (user_id) REFERENCES pn_crm.perfil(user_id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.tarefa_comentario
    ADD CONSTRAINT tarefa_comentario_tarefa_id_fkey FOREIGN KEY (tarefa_id) REFERENCES pn_crm.tarefa(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.tarefa
    ADD CONSTRAINT tarefa_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.tarefa_item
    ADD CONSTRAINT tarefa_item_tarefa_id_fkey FOREIGN KEY (tarefa_id) REFERENCES pn_crm.tarefa(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.tarefa
    ADD CONSTRAINT tarefa_negocio_id_fkey FOREIGN KEY (negocio_id) REFERENCES pn_crm.negocio(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.tarefa
    ADD CONSTRAINT tarefa_quadro_id_fkey FOREIGN KEY (quadro_id) REFERENCES pn_crm.quadro(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.tarefa
    ADD CONSTRAINT tarefa_responsavel_id_fkey FOREIGN KEY (responsavel_id) REFERENCES pn_crm.perfil(user_id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.tunel
    ADD CONSTRAINT tunel_funil_destino_id_fkey FOREIGN KEY (funil_destino_id) REFERENCES pn_crm.funil(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.tunel
    ADD CONSTRAINT tunel_funil_origem_id_fkey FOREIGN KEY (funil_origem_id) REFERENCES pn_crm.funil(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_crm.wa_config
    ADD CONSTRAINT wa_config_funil_id_fkey FOREIGN KEY (funil_id) REFERENCES pn_crm.funil(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.wa_contato
    ADD CONSTRAINT wa_contato_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.wa_contato
    ADD CONSTRAINT wa_contato_negocio_id_fkey FOREIGN KEY (negocio_id) REFERENCES pn_crm.negocio(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.wa_historico_conversa
    ADD CONSTRAINT wa_historico_conversa_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.wa_historico_conversa
    ADD CONSTRAINT wa_historico_conversa_negocio_id_fkey FOREIGN KEY (negocio_id) REFERENCES pn_crm.negocio(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn_crm.wa_historico_msg
    ADD CONSTRAINT wa_historico_msg_chat_id_fkey FOREIGN KEY (chat_id) REFERENCES pn_crm.wa_historico_conversa(chat_id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.anamnese_resposta
    ADD CONSTRAINT anamnese_resposta_ficha_clinica_id_fkey FOREIGN KEY (ficha_clinica_id) REFERENCES pn.ficha_clinica(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.atendimento_arquivo
    ADD CONSTRAINT atendimento_arquivo_arquivo_id_fkey FOREIGN KEY (arquivo_id) REFERENCES pn.arquivo(id) ON DELETE RESTRICT;

ALTER TABLE ONLY pn.atendimento_arquivo
    ADD CONSTRAINT atendimento_arquivo_atendimento_id_fkey FOREIGN KEY (atendimento_id) REFERENCES pn.atendimento(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.atendimento
    ADD CONSTRAINT atendimento_colaborador_id_fkey FOREIGN KEY (colaborador_id) REFERENCES pn.colaborador(id) ON DELETE RESTRICT;

ALTER TABLE ONLY pn.atendimento
    ADD CONSTRAINT atendimento_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE RESTRICT;

ALTER TABLE ONLY pn.atendimento_exame
    ADD CONSTRAINT atendimento_exame_atendimento_id_fkey FOREIGN KEY (atendimento_id) REFERENCES pn.atendimento(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.atendimento_exame
    ADD CONSTRAINT atendimento_exame_exame_tipo_id_fkey FOREIGN KEY (exame_tipo_id) REFERENCES pn.exame_tipo(id);

ALTER TABLE ONLY pn.atendimento
    ADD CONSTRAINT atendimento_funcao_id_fkey FOREIGN KEY (funcao_id) REFERENCES pn.funcao(id);

ALTER TABLE ONLY pn.atendimento
    ADD CONSTRAINT atendimento_profissional_id_fkey FOREIGN KEY (profissional_id) REFERENCES pn.profissional(id);

ALTER TABLE ONLY pn.atendimento
    ADD CONSTRAINT atendimento_unidade_id_fkey FOREIGN KEY (unidade_id) REFERENCES pn.unidade(id);

ALTER TABLE ONLY pn.cat_arquivo
    ADD CONSTRAINT cat_arquivo_arquivo_id_fkey FOREIGN KEY (arquivo_id) REFERENCES pn.arquivo(id) ON DELETE RESTRICT;

ALTER TABLE ONLY pn.cat_arquivo
    ADD CONSTRAINT cat_arquivo_cat_id_fkey FOREIGN KEY (cat_id) REFERENCES pn.cat(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.cat
    ADD CONSTRAINT cat_colaborador_id_fkey FOREIGN KEY (colaborador_id) REFERENCES pn.colaborador(id);

ALTER TABLE ONLY pn.cat
    ADD CONSTRAINT cat_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.colaborador
    ADD CONSTRAINT colaborador_cbo_codigo_fkey FOREIGN KEY (cbo_codigo) REFERENCES pn.cbo(codigo);

ALTER TABLE ONLY pn.colaborador
    ADD CONSTRAINT colaborador_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE RESTRICT;

ALTER TABLE ONLY pn.colaborador
    ADD CONSTRAINT colaborador_funcao_id_fkey FOREIGN KEY (funcao_id) REFERENCES pn.funcao(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn.colaborador
    ADD CONSTRAINT colaborador_setor_id_fkey FOREIGN KEY (setor_id) REFERENCES pn.setor(id) ON DELETE SET NULL;

ALTER TABLE ONLY pn.colaborador
    ADD CONSTRAINT colaborador_unidade_id_fkey FOREIGN KEY (unidade_id) REFERENCES pn.unidade(id);

ALTER TABLE ONLY pn.colaborador_vinculo
    ADD CONSTRAINT colaborador_vinculo_colaborador_id_fkey FOREIGN KEY (colaborador_id) REFERENCES pn.colaborador(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.colaborador_vinculo
    ADD CONSTRAINT colaborador_vinculo_funcao_id_fkey FOREIGN KEY (funcao_id) REFERENCES pn.funcao(id);

ALTER TABLE ONLY pn.documento_arquivo
    ADD CONSTRAINT documento_arquivo_arquivo_id_fkey FOREIGN KEY (arquivo_id) REFERENCES pn.arquivo(id) ON DELETE RESTRICT;

ALTER TABLE ONLY pn.documento_arquivo
    ADD CONSTRAINT documento_arquivo_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES pn.documento(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.documento
    ADD CONSTRAINT documento_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.documento
    ADD CONSTRAINT documento_responsavel_id_fkey FOREIGN KEY (responsavel_id) REFERENCES pn.profissional(id);

ALTER TABLE ONLY pn.documento
    ADD CONSTRAINT documento_unidade_id_fkey FOREIGN KEY (unidade_id) REFERENCES pn.unidade(id);

ALTER TABLE ONLY pn.empresa_contato
    ADD CONSTRAINT empresa_contato_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.esocial_evento
    ADD CONSTRAINT esocial_evento_atendimento_id_fkey FOREIGN KEY (atendimento_id) REFERENCES pn.atendimento(id);

ALTER TABLE ONLY pn.esocial_evento
    ADD CONSTRAINT esocial_evento_colaborador_id_fkey FOREIGN KEY (colaborador_id) REFERENCES pn.colaborador(id);

ALTER TABLE ONLY pn.esocial_evento
    ADD CONSTRAINT esocial_evento_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id);

ALTER TABLE ONLY pn.esocial_evento
    ADD CONSTRAINT esocial_evento_recibo_arquivo_id_fkey FOREIGN KEY (recibo_arquivo_id) REFERENCES pn.arquivo(id);

ALTER TABLE ONLY pn.esocial_evento
    ADD CONSTRAINT esocial_evento_unidade_id_fkey FOREIGN KEY (unidade_id) REFERENCES pn.unidade(id);

ALTER TABLE ONLY pn.esocial_evento
    ADD CONSTRAINT esocial_evento_xml_arquivo_id_fkey FOREIGN KEY (xml_arquivo_id) REFERENCES pn.arquivo(id);

ALTER TABLE ONLY pn.exame_fisico
    ADD CONSTRAINT exame_fisico_ficha_clinica_id_fkey FOREIGN KEY (ficha_clinica_id) REFERENCES pn.ficha_clinica(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.ficha_clinica
    ADD CONSTRAINT ficha_clinica_atendimento_id_fkey FOREIGN KEY (atendimento_id) REFERENCES pn.atendimento(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.ficha_clinica
    ADD CONSTRAINT ficha_clinica_colaborador_id_fkey FOREIGN KEY (colaborador_id) REFERENCES pn.colaborador(id) ON DELETE RESTRICT;

ALTER TABLE ONLY pn.ficha_clinica
    ADD CONSTRAINT ficha_clinica_profissional_id_fkey FOREIGN KEY (profissional_id) REFERENCES pn.profissional(id);

ALTER TABLE ONLY pn.funcao_cargo
    ADD CONSTRAINT funcao_cargo_cbo_codigo_fkey FOREIGN KEY (cbo_codigo) REFERENCES pn.cbo(codigo);

ALTER TABLE ONLY pn.funcao_cargo
    ADD CONSTRAINT funcao_cargo_funcao_id_fkey FOREIGN KEY (funcao_id) REFERENCES pn.funcao(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.funcao
    ADD CONSTRAINT funcao_cbo_codigo_fkey FOREIGN KEY (cbo_codigo) REFERENCES pn.cbo(codigo);

ALTER TABLE ONLY pn.funcao_exame
    ADD CONSTRAINT funcao_exame_exame_tipo_id_fkey FOREIGN KEY (exame_tipo_id) REFERENCES pn.exame_tipo(id);

ALTER TABLE ONLY pn.funcao_exame
    ADD CONSTRAINT funcao_exame_funcao_id_fkey FOREIGN KEY (funcao_id) REFERENCES pn.funcao(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.funcao_risco
    ADD CONSTRAINT funcao_risco_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES pn.documento(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.funcao_risco_epc
    ADD CONSTRAINT funcao_risco_epc_epc_id_fkey FOREIGN KEY (epc_id) REFERENCES pn.epc(id);

ALTER TABLE ONLY pn.funcao_risco_epc
    ADD CONSTRAINT funcao_risco_epc_funcao_risco_id_fkey FOREIGN KEY (funcao_risco_id) REFERENCES pn.funcao_risco(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.funcao_risco_epi
    ADD CONSTRAINT funcao_risco_epi_epi_id_fkey FOREIGN KEY (epi_id) REFERENCES pn.epi(id);

ALTER TABLE ONLY pn.funcao_risco_epi
    ADD CONSTRAINT funcao_risco_epi_funcao_risco_id_fkey FOREIGN KEY (funcao_risco_id) REFERENCES pn.funcao_risco(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.funcao_risco
    ADD CONSTRAINT funcao_risco_funcao_id_fkey FOREIGN KEY (funcao_id) REFERENCES pn.funcao(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.funcao_risco
    ADD CONSTRAINT funcao_risco_risco_id_fkey FOREIGN KEY (risco_id) REFERENCES pn.risco(id);

ALTER TABLE ONLY pn.funcao
    ADD CONSTRAINT funcao_setor_id_fkey FOREIGN KEY (setor_id) REFERENCES pn.setor(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.pcmso_exame_fisico_funcao
    ADD CONSTRAINT pcmso_exame_fisico_funcao_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES pn.documento(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.pcmso_exame_fisico_funcao
    ADD CONSTRAINT pcmso_exame_fisico_funcao_exame_tipo_id_fkey FOREIGN KEY (exame_tipo_id) REFERENCES pn.exame_tipo(id);

ALTER TABLE ONLY pn.pcmso_exame_fisico_funcao
    ADD CONSTRAINT pcmso_exame_fisico_funcao_funcao_id_fkey FOREIGN KEY (funcao_id) REFERENCES pn.funcao(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.pcmso_exame_funcao
    ADD CONSTRAINT pcmso_exame_funcao_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES pn.documento(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.pcmso_exame_funcao
    ADD CONSTRAINT pcmso_exame_funcao_exame_tipo_id_fkey FOREIGN KEY (exame_tipo_id) REFERENCES pn.exame_tipo(id);

ALTER TABLE ONLY pn.pcmso_exame_funcao
    ADD CONSTRAINT pcmso_exame_funcao_funcao_id_fkey FOREIGN KEY (funcao_id) REFERENCES pn.funcao(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.pcmso_vacina_funcao
    ADD CONSTRAINT pcmso_vacina_funcao_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES pn.documento(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.pcmso_vacina_funcao
    ADD CONSTRAINT pcmso_vacina_funcao_funcao_id_fkey FOREIGN KEY (funcao_id) REFERENCES pn.funcao(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.pcmso_vacina_funcao
    ADD CONSTRAINT pcmso_vacina_funcao_vacina_id_fkey FOREIGN KEY (vacina_id) REFERENCES pn.vacina(id);

ALTER TABLE ONLY pn.plano_acao
    ADD CONSTRAINT plano_acao_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES pn.documento(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.plano_acao
    ADD CONSTRAINT plano_acao_setor_id_fkey FOREIGN KEY (setor_id) REFERENCES pn.setor(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.plano_acao
    ADD CONSTRAINT plano_acao_unidade_id_fkey FOREIGN KEY (unidade_id) REFERENCES pn.unidade(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.queixa
    ADD CONSTRAINT queixa_ficha_clinica_id_fkey FOREIGN KEY (ficha_clinica_id) REFERENCES pn.ficha_clinica(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.queixa
    ADD CONSTRAINT queixa_registrado_por_fkey FOREIGN KEY (registrado_por) REFERENCES pn.profissional(id);

ALTER TABLE ONLY pn.risco
    ADD CONSTRAINT risco_agente_quimico_id_fkey FOREIGN KEY (agente_quimico_id) REFERENCES pn.agente_quimico(id);

ALTER TABLE ONLY pn.risco_epc
    ADD CONSTRAINT risco_epc_epc_id_fkey FOREIGN KEY (epc_id) REFERENCES pn.epc(id);

ALTER TABLE ONLY pn.risco_epc
    ADD CONSTRAINT risco_epc_risco_id_fkey FOREIGN KEY (risco_id) REFERENCES pn.risco(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.risco_epi
    ADD CONSTRAINT risco_epi_epi_id_fkey FOREIGN KEY (epi_id) REFERENCES pn.epi(id);

ALTER TABLE ONLY pn.risco_epi
    ADD CONSTRAINT risco_epi_risco_id_fkey FOREIGN KEY (risco_id) REFERENCES pn.risco(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.risco_exame
    ADD CONSTRAINT risco_exame_exame_tipo_id_fkey FOREIGN KEY (exame_tipo_id) REFERENCES pn.exame_tipo(id);

ALTER TABLE ONLY pn.risco_exame
    ADD CONSTRAINT risco_exame_risco_id_fkey FOREIGN KEY (risco_id) REFERENCES pn.risco(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.setor
    ADD CONSTRAINT setor_unidade_id_fkey FOREIGN KEY (unidade_id) REFERENCES pn.unidade(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn.unidade
    ADD CONSTRAINT unidade_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES pn.empresa(id) ON DELETE CASCADE;

ALTER TABLE ONLY pn_sesmo.job_item
    ADD CONSTRAINT job_item_job_id_fkey FOREIGN KEY (job_id) REFERENCES pn_sesmo.job(id) ON DELETE CASCADE;

ALTER TABLE pn_app.vencimento ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_app.vencimento_exame ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.admin_inicial ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.agenda ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.agenda_grade ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.agenda_limite_empresa ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.agenda_regra ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.agendamento ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.agendamento_evento ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.atestado ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.atestado_alerta ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.atestado_regra ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.bitrix_empresa ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.bitrix_etapa ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.bitrix_usuario ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.chat_membro ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.chat_mensagem ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.chat_sala ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.cobranca ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.cobranca_evento ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.contrato ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.contrato_evento ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.contrato_item ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.documento_regra ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.documento_renovacao ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.edicao ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.empresa_interacao ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.etapa ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.evento ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.fin_regra ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.funil ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.negocio ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.negocio_item ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.notificacao ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.perfil ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.posvenda_regra ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.pre_cadastro ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.produto ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.quadro ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.rodizio ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.rodizio_estado ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.tarefa ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.tarefa_comentario ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.tarefa_item ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.tunel ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.wa_config ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.wa_contato ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.wa_historico_conversa ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.wa_historico_msg ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.wa_modelo ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn_crm.wa_saida ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.agente_quimico ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.anamnese_resposta ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.arquivo ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.atendimento ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.atendimento_arquivo ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.atendimento_exame ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.cat ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.cat_arquivo ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.cbo ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.colaborador ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.colaborador_vinculo ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.documento ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.documento_arquivo ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.empresa ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.empresa_contato ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.epc ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.epi ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.esocial_evento ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.exame_fisico ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.exame_tipo ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.ficha_clinica ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.funcao ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.funcao_cargo ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.funcao_exame ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.funcao_risco ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.funcao_risco_epc ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.funcao_risco_epi ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.pcmso_exame_fisico_funcao ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.pcmso_exame_funcao ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.pcmso_vacina_funcao ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.plano_acao ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.profissional ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.queixa ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.risco ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.risco_epc ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.risco_epi ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.risco_exame ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.setor ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.unidade ENABLE ROW LEVEL SECURITY;

ALTER TABLE pn.vacina ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON FUNCTION pn_app.recalcular_vencimentos() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.abrir_renovacao(p_empresa uuid, p_titulo text, p_cliente_nome text, p_responsavel uuid, p_valor numeric, p_origem_card uuid, p_motivo text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.agenda_checar(p_agenda uuid, p_empresa uuid, p_encaixe boolean, p_ignorar uuid, p_tipo text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.agenda_registrar(p_agendamento uuid, p_texto text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.alertas_contratos() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.alertas_documentos() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.alertas_tarefas() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.aplicar_pre_cadastro(p_user uuid, p_email text, p_confirmado boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.atestado_mes(p_inicio date, p_emissao date, p_criado timestamp with time zone) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.atestado_verificar(p_empresa uuid, p_mes date) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bitrix_atribuir(p_user uuid, p_email text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bitrix_consolidar_posvenda() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bitrix_importar_historico() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bitrix_importar_negocios() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bitrix_importar_whatsapp() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bitrix_mapear_empresas() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bitrix_mapear_usuarios() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bitrix_sincronizar() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bx_atual(p_modulo text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bx_chave(p text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bx_funcionarios(p_lista jsonb, p_numero text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bx_msg(p text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bx_pagamento(p_rotulo text, OUT forma text, OUT parcelas smallint) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.bx_txt(p text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.chat_acesso(p_sala uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.chat_exige(p_sala uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.chat_pode_arquivo(p_nome text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn_crm.chat_pode_arquivo(p_nome text) TO authenticated;

REVOKE ALL ON FUNCTION pn_crm.cobranca_log(p_cobranca uuid, p_texto text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.contrato_log(p_contrato uuid, p_texto text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.contrato_recalcular(p_contrato uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.criar(p_tabela text, p_dados jsonb, p_fixos jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.editar(p_tabela text, p_id uuid, p_dados jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.empresa_inadimplente(p_empresa uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.exige(VARIADIC papeis pn_crm.papel[]) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.exige_ativo() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.exige_contratos() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.exige_editor() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.exige_financeiro() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.exige_operar(p_funil uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.fin_inadimplencia() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.fin_sincronizar_inadimplencia(p_empresa uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.gerar_alertas() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.historico_edicao(p_tabela text, p_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.integracao_token_ok(p_token text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.limpar_dados(p_dados jsonb, p_campos text[]) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.notificar(p_user uuid, p_negocio uuid, p_tipo text, p_texto text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.notificar_tarefa(p_user uuid, p_tarefa uuid, p_tipo text, p_texto text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.papel_atual() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.pode_clinico() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.pode_editar_dados() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.pode_encaixe() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.pode_liberar_agenda() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.pode_operar(p_funil uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.posvenda_card(p_empresa uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.posvenda_mover(p_card uuid, p_etapa uuid, p_texto text, p_guardar_anterior boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.posvenda_renovacao() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.proximo_rodizio(p_funil uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.recalcular_valor(p_negocio uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.registrar(p_negocio uuid, p_tipo text, p_texto text, p_de uuid, p_para uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.responsavel_cliente(p_empresa uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.tarefa_log(p_tarefa uuid, p_texto text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.telefone_normalizado(p text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.tg_atestado_antes() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.tg_atestado_depois() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.tg_contrato_item_cobranca() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.tg_contrato_padroes() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.tg_negocio_do_comercial() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.tg_negocio_ganho_contrato() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.tg_novo_usuario() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.tg_preserva_edicao() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.tg_usuario_confirmado() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.usuario_atividade(p_user uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.ve_empresa(p_empresa uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.ve_negocio(p_responsavel uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.ve_tarefa(p_criador uuid, p_resps uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION pn_crm.ve_tarefa(p_criador uuid, p_resps uuid[]) TO authenticated;

REVOKE ALL ON FUNCTION pn_crm.ve_valores() FROM PUBLIC;
GRANT ALL ON FUNCTION pn_crm.ve_valores() TO authenticated;

REVOKE ALL ON FUNCTION pn_crm.ve_valores_funil(p_funil uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.vendedor_id(p_negocio uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.wa_abrir_negocio(p_contato uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.wa_empresa_por_telefone(p_tel text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_crm.wa_receber(p_eventos jsonb, p_criar boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn.integracao_agenda_horarios(p_token text, p_data date) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.integracao_agenda_horarios(p_token text, p_data date) TO anon;
GRANT ALL ON FUNCTION pn.integracao_agenda_horarios(p_token text, p_data date) TO authenticated;
GRANT ALL ON FUNCTION pn.integracao_agenda_horarios(p_token text, p_data date) TO service_role;

REVOKE ALL ON FUNCTION pn.integracao_agendamento_criar(p_token text, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.integracao_agendamento_criar(p_token text, p_dados jsonb) TO anon;
GRANT ALL ON FUNCTION pn.integracao_agendamento_criar(p_token text, p_dados jsonb) TO authenticated;
GRANT ALL ON FUNCTION pn.integracao_agendamento_criar(p_token text, p_dados jsonb) TO service_role;

REVOKE ALL ON FUNCTION pn.integracao_atestado_receber(p_token text, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.integracao_atestado_receber(p_token text, p_dados jsonb) TO anon;
GRANT ALL ON FUNCTION pn.integracao_atestado_receber(p_token text, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.integracao_token_valido(p_token text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn.integracao_usuario_email(p_user uuid, p_email text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.integracao_usuario_email(p_user uuid, p_email text) TO service_role;

REVOKE ALL ON FUNCTION pn.integracao_wa_receber(p_token text, p_eventos jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.integracao_wa_receber(p_token text, p_eventos jsonb) TO anon;
GRANT ALL ON FUNCTION pn.integracao_wa_receber(p_token text, p_eventos jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.integracao_wa_saida(p_token text, p_resultados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.integracao_wa_saida(p_token text, p_resultados jsonb) TO anon;
GRANT ALL ON FUNCTION pn.integracao_wa_saida(p_token text, p_resultados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agenda_dia(p_data date, p_agenda uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agenda_dia(p_data date, p_agenda uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agenda_excluir(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agenda_excluir(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agenda_grade() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agenda_grade() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agenda_grade_salvar(p_grade jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agenda_grade_salvar(p_grade jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agenda_horarios(p_agenda uuid, p_ignorar uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agenda_horarios(p_agenda uuid, p_ignorar uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agenda_limite_salvar(p_empresa uuid, p_limite integer, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agenda_limite_salvar(p_empresa uuid, p_limite integer, p_motivo text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agenda_periodo(p_de date, p_ate date) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agenda_periodo(p_de date, p_ate date) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agenda_regras() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agenda_regras() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agenda_regras_salvar(p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agenda_regras_salvar(p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agenda_salvar(p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agenda_salvar(p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agendamento_checar(p_agenda uuid, p_empresa uuid, p_encaixe boolean, p_ignorar uuid, p_tipo text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agendamento_checar(p_agenda uuid, p_empresa uuid, p_encaixe boolean, p_ignorar uuid, p_tipo text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agendamento_historico(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agendamento_historico(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agendamento_salvar(p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agendamento_salvar(p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_agendamento_situacao(p_id uuid, p_situacao text, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_agendamento_situacao(p_id uuid, p_situacao text, p_motivo text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_atendimento(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_atendimento(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_atendimento_salvar(p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_atendimento_salvar(p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_atendimentos(p_empresa uuid, p_de date, p_ate date, p_situacao text, p_busca text, p_limite integer, p_offset integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_atendimentos(p_empresa uuid, p_de date, p_ate date, p_situacao text, p_busca text, p_limite integer, p_offset integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_atestado_arquivo(p_id uuid, p_path text, p_nome text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_atestado_arquivo(p_id uuid, p_path text, p_nome text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_atestado_regra_salvar(p_limite integer, p_prazo_dias integer, p_ativo boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_atestado_regra_salvar(p_limite integer, p_prazo_dias integer, p_ativo boolean) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_atestado_salvar(p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_atestado_salvar(p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_atestados(p_mes date, p_empresa uuid, p_situacao text, p_busca text, p_limite integer, p_offset integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_atestados(p_mes date, p_empresa uuid, p_situacao text, p_busca text, p_limite integer, p_offset integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_atestados_resumo(p_mes date) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_atestados_resumo(p_mes date) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_auditoria(p_origem text, p_usuario uuid, p_de date, p_ate date, p_busca text, p_limite integer, p_offset integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_auditoria(p_origem text, p_usuario uuid, p_de date, p_ate date, p_busca text, p_limite integer, p_offset integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_bitrix_empresa_vincular(p_bitrix_id bigint, p_empresa uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_bitrix_empresa_vincular(p_bitrix_id bigint, p_empresa uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_bitrix_empresas(p_busca text, p_so_sem_vinculo boolean, p_limite integer, p_offset integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_bitrix_empresas(p_busca text, p_so_sem_vinculo boolean, p_limite integer, p_offset integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_chat_apagar(p_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_chat_apagar(p_id bigint) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_chat_direto(p_user uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_chat_direto(p_user uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_chat_enviar(p_sala uuid, p_texto text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_chat_enviar(p_sala uuid, p_texto text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_chat_enviar_anexo(p_sala uuid, p_path text, p_tipo text, p_nome text, p_mime text, p_tamanho integer, p_duracao numeric, p_legenda text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_chat_enviar_anexo(p_sala uuid, p_path text, p_tipo text, p_nome text, p_mime text, p_tamanho integer, p_duracao numeric, p_legenda text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_chat_grupo_salvar(p_id uuid, p_nome text, p_descricao text, p_membros uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_chat_grupo_salvar(p_id uuid, p_nome text, p_descricao text, p_membros uuid[]) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_chat_lida(p_sala uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_chat_lida(p_sala uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_chat_mensagens(p_sala uuid, p_antes bigint, p_limite integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_chat_mensagens(p_sala uuid, p_antes bigint, p_limite integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_chat_mensagens_v2(p_sala uuid, p_antes bigint, p_limite integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_chat_mensagens_v2(p_sala uuid, p_antes bigint, p_limite integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_chat_nao_lidas() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_chat_nao_lidas() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_chat_pessoas() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_chat_pessoas() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_chat_sair(p_sala uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_chat_sair(p_sala uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_chat_sala(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_chat_sala(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_chat_salas() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_chat_salas() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_cliente(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_cliente(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_clientes(p_busca text, p_situacao text, p_limite integer, p_offset integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_clientes(p_busca text, p_situacao text, p_limite integer, p_offset integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_cobranca_baixa(p_id uuid, p_pago_em date, p_valor numeric, p_forma text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_cobranca_baixa(p_id uuid, p_pago_em date, p_valor numeric, p_forma text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_cobranca_cancelar(p_id uuid, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_cobranca_cancelar(p_id uuid, p_motivo text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_cobranca_historico(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_cobranca_historico(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_cobranca_salvar(p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_cobranca_salvar(p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_cobrancas(p_competencia date, p_situacao text, p_busca text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_cobrancas(p_competencia date, p_situacao text, p_busca text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_colaborador(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_colaborador(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_colaborador_salvar(p_id uuid, p_empresa uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_colaborador_salvar(p_id uuid, p_empresa uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_colaboradores(p_empresa uuid, p_busca text, p_situacao text, p_limite integer, p_offset integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_colaboradores(p_empresa uuid, p_busca text, p_situacao text, p_limite integer, p_offset integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_contrato(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_contrato(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_contrato_arquivo(p_id uuid, p_path text, p_nome text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_contrato_arquivo(p_id uuid, p_path text, p_nome text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_contrato_item_adicionar(p_contrato uuid, p_produto uuid, p_descricao text, p_quantidade numeric, p_preco numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_contrato_item_adicionar(p_contrato uuid, p_produto uuid, p_descricao text, p_quantidade numeric, p_preco numeric) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_contrato_item_remover(p_item uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_contrato_item_remover(p_item uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_contrato_minuta(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_contrato_minuta(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_contrato_minuta_salvar(p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_contrato_minuta_salvar(p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_contrato_salvar(p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_contrato_salvar(p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_contrato_status(p_id uuid, p_status text, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_contrato_status(p_id uuid, p_status text, p_motivo text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_contratos(p_busca text, p_situacao text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_contratos(p_busca text, p_situacao text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_contratos_resumo() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_contratos_resumo() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_atividade(p_id uuid, p_tipo text, p_texto text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_atividade(p_id uuid, p_tipo text, p_texto text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_etapa_salvar(p_id uuid, p_funil uuid, p_nome text, p_tipo text, p_cor text, p_alerta_dias integer, p_ativo boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_etapa_salvar(p_id uuid, p_funil uuid, p_nome text, p_tipo text, p_cor text, p_alerta_dias integer, p_ativo boolean) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_etapas_reordenar(p_funil uuid, p_ids uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_etapas_reordenar(p_funil uuid, p_ids uuid[]) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_funis() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_funis() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_item_adicionar(p_negocio uuid, p_produto uuid, p_descricao text, p_quantidade numeric, p_preco numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_item_adicionar(p_negocio uuid, p_produto uuid, p_descricao text, p_quantidade numeric, p_preco numeric) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_item_adicionar_v2(p_negocio uuid, p_produto uuid, p_descricao text, p_quantidade numeric, p_preco numeric, p_desconto numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_item_adicionar_v2(p_negocio uuid, p_produto uuid, p_descricao text, p_quantidade numeric, p_preco numeric, p_desconto numeric) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_item_remover(p_item uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_item_remover(p_item uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_item_salvar(p_item uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_item_salvar(p_item uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_negocio(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_negocio(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_negocio_atualizar(p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_negocio_atualizar(p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_negocio_criar(p_funil uuid, p_titulo text, p_empresa_id uuid, p_cliente_nome text, p_cliente_cnpj text, p_contato_nome text, p_contato_telefone text, p_contato_email text, p_responsavel uuid, p_valor numeric, p_origem text, p_observacao text, p_previsao date) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_negocio_criar(p_funil uuid, p_titulo text, p_empresa_id uuid, p_cliente_nome text, p_cliente_cnpj text, p_contato_nome text, p_contato_telefone text, p_contato_email text, p_responsavel uuid, p_valor numeric, p_origem text, p_observacao text, p_previsao date) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_negocio_criar_v2(p_dados jsonb, p_itens jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_negocio_criar_v2(p_dados jsonb, p_itens jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_negocio_desconto(p_negocio uuid, p_pct numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_negocio_desconto(p_negocio uuid, p_pct numeric) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_negocio_mover(p_id uuid, p_etapa uuid, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_negocio_mover(p_id uuid, p_etapa uuid, p_motivo text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_pendencias(p_so_minhas boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_pendencias(p_so_minhas boolean) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_produto_salvar(p_id uuid, p_nome text, p_descricao text, p_categoria text, p_preco numeric, p_unidade text, p_recorrente boolean, p_ativo boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_produto_salvar(p_id uuid, p_nome text, p_descricao text, p_categoria text, p_preco numeric, p_unidade text, p_recorrente boolean, p_ativo boolean) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_produtos(p_todos boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_produtos(p_todos boolean) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_quadro(p_funil uuid, p_responsavel uuid, p_busca text, p_dias_fechados integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_quadro(p_funil uuid, p_responsavel uuid, p_busca text, p_dias_fechados integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_quadro_v2(p_funil uuid, p_responsavel uuid, p_busca text, p_dias_fechados integer, p_de date, p_ate date) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_quadro_v2(p_funil uuid, p_responsavel uuid, p_busca text, p_dias_fechados integer, p_de date, p_ate date) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_quadro_v3(p_funil uuid, p_responsavel uuid, p_busca text, p_dias_fechados integer, p_de date, p_ate date) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_quadro_v3(p_funil uuid, p_responsavel uuid, p_busca text, p_dias_fechados integer, p_de date, p_ate date) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_responsaveis() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_responsaveis() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_rodizio(p_funil uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_rodizio(p_funil uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_crm_rodizio_salvar(p_funil uuid, p_users uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_crm_rodizio_salvar(p_funil uuid, p_users uuid[]) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_documento_arquivo(p_id uuid, p_path text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_documento_arquivo(p_id uuid, p_path text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_documento_regra_salvar(p_aviso integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_documento_regra_salvar(p_aviso integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_documento_salvar(p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_documento_salvar(p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_documentos(p_busca text, p_tipo text, p_situacao text, p_empresa uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_documentos(p_busca text, p_tipo text, p_situacao text, p_empresa uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_documentos_resumo() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_documentos_resumo() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_edicao_liberar(p_tabela text, p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_edicao_liberar(p_tabela text, p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_empresa_contatar(p_empresa uuid, p_contato uuid, p_canal text, p_destino text, p_texto text, p_assunto text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_empresa_contatar(p_empresa uuid, p_contato uuid, p_canal text, p_destino text, p_texto text, p_assunto text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_empresa_contato_excluir(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_empresa_contato_excluir(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_empresa_contato_salvar(p_empresa uuid, p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_empresa_contato_salvar(p_empresa uuid, p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_empresa_criar(p_dados jsonb, p_contato jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_empresa_criar(p_dados jsonb, p_contato jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_empresa_salvar(p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_empresa_salvar(p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_empresas_buscar(p_busca text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_empresas_buscar(p_busca text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_fin_gerar_mes(p_competencia date) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_fin_gerar_mes(p_competencia date) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_fin_importar(p_linhas jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_fin_importar(p_linhas jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_fin_regra() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_fin_regra() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_fin_regra_salvar(p_tolerancia integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_fin_regra_salvar(p_tolerancia integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_fin_resumo(p_competencia date) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_fin_resumo(p_competencia date) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_meu_perfil() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_meu_perfil() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_minhas_tarefas() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_minhas_tarefas() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_notificacoes(p_limite integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_notificacoes(p_limite integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_notificacoes_marcar_lidas(p_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_notificacoes_marcar_lidas(p_id bigint) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_notificacoes_nao_lidas() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_notificacoes_nao_lidas() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_papel_em(p_papeis text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_papel_em(p_papeis text[]) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_pre_cadastro_excluir(p_email text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_pre_cadastro_excluir(p_email text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_pre_cadastro_salvar(p_email text, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_pre_cadastro_salvar(p_email text, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_pre_cadastros() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_pre_cadastros() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_pre_cadastros_equipe() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_pre_cadastros_equipe() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_profissionais() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_profissionais() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_registrar_acesso() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_registrar_acesso() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_relatorio_descontos(p_de date, p_ate date) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_relatorio_descontos(p_de date, p_ate date) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_relatorio_vendas(p_de date, p_ate date, p_responsavel uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_relatorio_vendas(p_de date, p_ate date, p_responsavel uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_resumo() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_resumo() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_tarefa(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_tarefa(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_tarefa_comentar(p_id uuid, p_texto text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_tarefa_comentar(p_id uuid, p_texto text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_tarefa_excluir(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_tarefa_excluir(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_tarefa_item_excluir(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_tarefa_item_excluir(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_tarefa_item_salvar(p_tarefa uuid, p_id uuid, p_texto text, p_feito boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_tarefa_item_salvar(p_tarefa uuid, p_id uuid, p_texto text, p_feito boolean) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_tarefa_mover(p_id uuid, p_status text, p_ordem double precision) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_tarefa_mover(p_id uuid, p_status text, p_ordem double precision) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_tarefa_quadro_arquivar(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_tarefa_quadro_arquivar(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_tarefa_quadro_salvar(p_id uuid, p_nome text, p_descricao text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_tarefa_quadro_salvar(p_id uuid, p_nome text, p_descricao text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_tarefa_salvar(p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_tarefa_salvar(p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_tarefas(p_quadro uuid, p_responsavel uuid, p_busca text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_tarefas(p_quadro uuid, p_responsavel uuid, p_busca text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_tarefas_quadros() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_tarefas_quadros() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_tarefas_v2(p_quadro uuid, p_responsavel uuid, p_busca text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_tarefas_v2(p_quadro uuid, p_responsavel uuid, p_busca text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_unidade_salvar(p_empresa uuid, p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_unidade_salvar(p_empresa uuid, p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_usuario_admin_checar(p_user uuid, p_acao text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_usuario_admin_checar(p_user uuid, p_acao text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_usuario_encaixe(p_user uuid, p_pode boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_usuario_encaixe(p_user uuid, p_pode boolean) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_usuario_libera_agenda(p_user uuid, p_libera boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_usuario_libera_agenda(p_user uuid, p_libera boolean) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_usuario_salvar(p_user_id uuid, p_papel text, p_ativo boolean, p_nome text, p_telefone text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_usuario_salvar(p_user_id uuid, p_papel text, p_ativo boolean, p_nome text, p_telefone text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_usuario_telefone(p_user uuid, p_telefone text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_usuario_telefone(p_user uuid, p_telefone text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_usuarios() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_usuarios() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_usuarios_encaixe() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_usuarios_encaixe() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_vencimento_detalhe(p_colaborador uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_vencimento_detalhe(p_colaborador uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_vencimentos(p_empresa uuid, p_status text, p_busca text, p_limite integer, p_offset integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_vencimentos(p_empresa uuid, p_status text, p_busca text, p_limite integer, p_offset integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_wa_config_salvar(p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_wa_config_salvar(p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_wa_contato_salvar(p_contato uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_wa_contato_salvar(p_contato uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_wa_contatos(p_busca text, p_filtro text) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_wa_contatos(p_busca text, p_filtro text) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_wa_contexto(p_negocio uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_wa_contexto(p_negocio uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_wa_criar_negocio(p_contato uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_wa_criar_negocio(p_contato uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_wa_historico(p_busca text, p_empresa uuid, p_telefone text, p_limite integer, p_offset integer) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_wa_historico(p_busca text, p_empresa uuid, p_telefone text, p_limite integer, p_offset integer) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_wa_historico_mensagens(p_chat bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_wa_historico_mensagens(p_chat bigint) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_wa_modelo_excluir(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_wa_modelo_excluir(p_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_wa_modelo_salvar(p_id uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_wa_modelo_salvar(p_id uuid, p_dados jsonb) TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_wa_modelos() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_wa_modelos() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_wa_resumo() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_wa_resumo() TO authenticated;

REVOKE ALL ON FUNCTION pn.painel_wa_token_gerar() FROM PUBLIC;
GRANT ALL ON FUNCTION pn.painel_wa_token_gerar() TO authenticated;

REVOKE ALL ON FUNCTION pn.sesmo_excluir_chave(p_modulo text, p_chave text, p_motivo text, p_evidencia jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION pn.sesmo_excluir_chave(p_modulo text, p_chave text, p_motivo text, p_evidencia jsonb) TO service_role;

REVOKE ALL ON FUNCTION pn_sesmo.enriquecer_colaboradores(p_min bigint, p_max bigint) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_sesmo.itens_estrutura(p_ativos text, p_inativos text, p_lista text) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_sesmo.mapa_unidade_empresa() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_sesmo.normalizar_atendimentos(p_min bigint, p_max bigint) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_sesmo.normalizar_atividades() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_sesmo.normalizar_colaboradores(p_min bigint, p_max bigint) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_sesmo.normalizar_empresas_situacao() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_sesmo.normalizar_funcao_exames() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_sesmo.normalizar_funcoes() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_sesmo.normalizar_setores() FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_sesmo.normalizar_sgg(p_etapa integer) FROM PUBLIC;

REVOKE ALL ON FUNCTION pn_sesmo.normalizar_unidades() FROM PUBLIC;



-- ===================== peças do Supabase
grant usage on schema pn to anon, authenticated, service_role;
alter default privileges in schema pn grant execute on functions to authenticated, service_role;

-- login compartilhado entre projetos: só contas criadas pelo painel (metadata app = 'pn') viram perfil
drop trigger if exists pn_novo_usuario on auth.users;
create trigger pn_novo_usuario after insert on auth.users
  for each row when (new.raw_user_meta_data->>'app' = 'pn') execute function pn_crm.tg_novo_usuario();
drop trigger if exists pn_usuario_confirmado on auth.users;
create trigger pn_usuario_confirmado after update of email_confirmed_at on auth.users
  for each row when (new.raw_user_meta_data->>'app' = 'pn') execute function pn_crm.tg_usuario_confirmado();

insert into storage.buckets (id, name, public, file_size_limit) values
  ('pn-crm-arquivos', 'pn-crm-arquivos', false, 26214400),
  ('pn-atestados', 'pn-atestados', false, 15728640),
  ('pn-chat', 'pn-chat', false, 15728640)
on conflict (id) do nothing;
drop policy if exists "pn_crm_arquivos_ler" on storage.objects;
drop policy if exists "pn_crm_arquivos_enviar" on storage.objects;
drop policy if exists "pn_crm_arquivos_apagar" on storage.objects;
drop policy if exists "pn_atestados_ler" on storage.objects;
drop policy if exists "pn_atestados_enviar" on storage.objects;
drop policy if exists "pn_atestados_apagar" on storage.objects;
drop policy if exists "pn_chat_ler" on storage.objects;
drop policy if exists "pn_chat_enviar" on storage.objects;
create policy "pn_crm_arquivos_ler" on storage.objects for select to authenticated
  using (bucket_id = 'pn-crm-arquivos' and pn.painel_papel_em(array['gestor','comercial','financeiro','operacoes']));
create policy "pn_crm_arquivos_enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'pn-crm-arquivos' and case when name like 'modelos/%'
    then pn.painel_papel_em(array['gestor']) else pn.painel_papel_em(array['gestor','comercial','financeiro','operacoes']) end);
create policy "pn_crm_arquivos_apagar" on storage.objects for delete to authenticated
  using (bucket_id = 'pn-crm-arquivos' and case when name like 'modelos/%'
    then pn.painel_papel_em(array['gestor']) else pn.painel_papel_em(array['gestor','comercial','financeiro']) end);
create policy "pn_atestados_ler" on storage.objects for select to authenticated
  using (bucket_id = 'pn-atestados' and pn.painel_papel_em(array['gestor','operacoes']));
create policy "pn_atestados_enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'pn-atestados' and pn.painel_papel_em(array['gestor','operacoes']));
create policy "pn_atestados_apagar" on storage.objects for delete to authenticated
  using (bucket_id = 'pn-atestados' and pn.painel_papel_em(array['gestor']));
create policy "pn_chat_ler" on storage.objects for select to authenticated
  using (bucket_id = 'pn-chat' and pn_crm.chat_pode_arquivo(name));
create policy "pn_chat_enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'pn-chat' and pn_crm.chat_pode_arquivo(name));

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('pn-alertas',            '0 11 * * 1-5', 'select pn_crm.gerar_alertas()');
    perform cron.schedule('pn-alertas-tarefas',    '5 11 * * *',   'select pn_crm.alertas_tarefas()');
    perform cron.schedule('pn-alertas-contratos',  '10 11 * * *',  'select pn_crm.alertas_contratos()');
    perform cron.schedule('pn-posvenda-renovacao', '12 11 * * *',  'select pn_crm.posvenda_renovacao()');
    perform cron.schedule('pn-inadimplencia',      '15 11 * * *',  'select pn_crm.fin_inadimplencia()');
    perform cron.schedule('pn-alertas-documentos', '20 11 * * *',  'select pn_crm.alertas_documentos()');
  end if;
end $$;

-- worker de ingestão: só a service_role chama (sem token próprio, não pode ficar aberto à chave pública)
revoke execute on function pn.ingestao_gravar_worker(jsonb), pn.sesmo_pendentes(text, integer) from public, anon, authenticated;
