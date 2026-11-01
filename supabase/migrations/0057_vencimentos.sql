

create table if not exists public.funcao_exame (
  id                  uuid primary key default gen_random_uuid(),
  funcao_id           uuid not null references public.funcao(id) on delete cascade,
  sesmo_id            text not null,
  exame_tipo_id       uuid references public.exame_tipo(id),
  exame_nome          text not null,
  exame_codigo        text,
  obrigatorio         boolean not null default true,
  ocupacional         boolean not null default true,
  no_admissional      boolean not null default false,
  no_periodico        boolean not null default false,
  no_demissional      boolean not null default false,
  no_mudanca_funcao   boolean not null default false,
  no_retorno          boolean not null default false,
  periodicidade_texto text,
  periodicidade_meses int,
  primeira_meses      int,
  sesmo_data_alteracao timestamptz,
  unique (funcao_id, sesmo_id)
);
create index if not exists funcao_exame_funcao on public.funcao_exame (funcao_id);
alter table public.funcao_exame enable row level security;
revoke all on public.funcao_exame from anon, authenticated;

create or replace function sesmo.normalizar_funcao_exames() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  with it as (
    select f.id funcao_id, x
      from sesmo.ultimas('funcao_exames') u
      join public.funcao f on f.sesmo_id = u.chave
      cross join lateral jsonb_array_elements(u.conteudo -> 'exames') x
  ), v as (
    select it.funcao_id, it.x ->> 'Id' sesmo_id,
           btrim(regexp_replace(it.x ->> 'Descricao', '^\s*\d+\s*-\s*', '')) nome,
           nullif(substring(it.x ->> 'Descricao' from '^\s*(\d+)'), '') codigo,
           lower(coalesce(it.x -> 'lstFaixas' -> 0 ->> 'Periodicidade', '')) per,
           it.x
      from it
  )
  insert into public.funcao_exame as t (funcao_id, sesmo_id, exame_tipo_id, exame_nome, exame_codigo, obrigatorio, ocupacional,
        no_admissional, no_periodico, no_demissional, no_mudanca_funcao, no_retorno,
        periodicidade_texto, periodicidade_meses, primeira_meses, sesmo_data_alteracao)
  select v.funcao_id, v.sesmo_id,
         (select et.id from public.exame_tipo et where lower(et.nome) = lower(v.nome) order by length(et.sesmo_id), et.sesmo_id limit 1),
         sesmo.corrigir(v.nome), v.codigo,
         coalesce(v.x ->> 'ExameAso', '') ilike 'obrigat%',
         coalesce((v.x ->> 'IsExameOcupacional')::boolean, true),
         v.x ->> 'IsAdmissional' = 'x', v.x ->> 'IsPeriodico' = 'x', v.x ->> 'IsDemissional' = 'x',
         v.x ->> 'IsMudancaFuncao' = 'x', v.x ->> 'IsRetornoTrabalho' = 'x',
         nullif(v.per, ''),
         case when v.per ~ '(\d+)\s*/\s*(\d+)' then (regexp_match(v.per, '(\d+)\s*/\s*(\d+)'))[2]::int
              when v.per ~ '\d+' then (regexp_match(v.per, '(\d+)'))[1]::int end,
         case when v.per ~ '(\d+)\s*/\s*(\d+)' then (regexp_match(v.per, '(\d+)\s*/\s*(\d+)'))[1]::int end,
         sesmo.ts_br(v.x ->> 'DataAlteracao')
    from v
   where v.nome <> ''
  on conflict (funcao_id, sesmo_id) do update set
    exame_tipo_id = excluded.exame_tipo_id, exame_nome = excluded.exame_nome, exame_codigo = excluded.exame_codigo,
    obrigatorio = excluded.obrigatorio, ocupacional = excluded.ocupacional,
    no_admissional = excluded.no_admissional, no_periodico = excluded.no_periodico, no_demissional = excluded.no_demissional,
    no_mudanca_funcao = excluded.no_mudanca_funcao, no_retorno = excluded.no_retorno,
    periodicidade_texto = excluded.periodicidade_texto, periodicidade_meses = excluded.periodicidade_meses,
    primeira_meses = excluded.primeira_meses, sesmo_data_alteracao = excluded.sesmo_data_alteracao;
  get diagnostics n = row_count;
  return jsonb_build_object('exames_por_funcao', n);
end $$;

create table if not exists app.vencimento_exame (
  colaborador_id      uuid not null,
  exame               text not null,
  exame_tipo_id       uuid,
  periodicidade_meses int not null,
  periodicidade_texto text,
  ultima              date,
  origem_ultima       text,
  proxima             date,
  status              text not null,
  primary key (colaborador_id, exame)
);

create table if not exists app.vencimento (
  colaborador_id      uuid primary key,
  colaborador         text,
  cpf                 text,
  matricula_esocial   text,
  empresa_id          uuid,
  empresa             text,
  unidade             text,
  setor               text,
  funcao              text,
  proximo_exame       date,
  dias_para_vencer    int,
  exames_vencidos     bigint,
  exames_nunca_feitos bigint,
  status              text,
  ultimo_aso          date,
  tem_pcmso           boolean,
  calculado_em        timestamptz not null default now()
);
create index if not exists vencimento_empresa on app.vencimento (empresa_id, status);
create index if not exists vencimento_status on app.vencimento (status, dias_para_vencer);
alter table app.vencimento enable row level security;
alter table app.vencimento_exame enable row level security;

create or replace function app.recalcular_vencimentos() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare hoje date := (now() at time zone 'America/Sao_Paulo')::date; n int;
begin
  create temp table _col on commit drop as
    select c.id, c.nome, c.cpf, c.matricula_esocial, c.empresa_id, c.data_admissao,
           coalesce(nullif(e.nome_fantasia, ''), e.razao_social) empresa, un.nome unidade,
           coalesce(c.funcao_id, (select f.id from public.funcao f join public.setor s on s.id = f.setor_id
                                   where s.unidade_id = c.unidade_id and lower(btrim(f.nome)) = lower(btrim(c.funcao_nome))
                                   order by f.sesmo_situacao_codigo desc nulls last limit 1)) funcao_id,
           c.setor_id, c.setor_nome, c.funcao_nome,
           (select max(a.data_atendimento) from public.atendimento a
             where a.colaborador_id = c.id and a.situacao in ('atendido','finalizado') and a.tipo <> 'demissional') ultimo_aso
      from public.colaborador c
      join public.empresa e on e.id = c.empresa_id and e.situacao = 'ativo'
      left join public.unidade un on un.id = c.unidade_id
     where c.situacao = 'ativo';
  create index on _col (id);

  create temp table _req on commit drop as
    select c.id colaborador_id, fe.exame_nome exame, fe.exame_tipo_id, fe.periodicidade_meses, fe.periodicidade_texto, fe.primeira_meses
      from _col c join public.funcao_exame fe on fe.funcao_id = c.funcao_id
     where fe.no_periodico and fe.ocupacional and fe.periodicidade_meses is not null
    union all

    select c.id, 'Exame Clínico', (select et.id from public.exame_tipo et where et.nome = 'Exame Clínico' order by et.sesmo_id limit 1),
           12, 'padrão (função sem PCMSO)', null
      from _col c
     where not exists (select 1 from public.funcao_exame fe where fe.funcao_id = c.funcao_id and fe.no_periodico and fe.periodicidade_meses is not null);

  truncate app.vencimento_exame;
  insert into app.vencimento_exame (colaborador_id, exame, exame_tipo_id, periodicidade_meses, periodicidade_texto,
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
                         from public.atendimento_exame ae join public.atendimento a on a.id = ae.atendimento_id
                        where a.colaborador_id = r.colaborador_id and ae.exame_tipo_id = r.exame_tipo_id
                          and ae.resultado <> 'nao_realizado') ex on r.exame_tipo_id is not null
    cross join lateral (select (coalesce(ex.d, c.ultimo_aso)
             + make_interval(months => case when r.primeira_meses is not null and c.data_admissao is not null
                                             and coalesce(ex.d, c.ultimo_aso) <= c.data_admissao + 30
                                            then r.primeira_meses else r.periodicidade_meses end))::date proxima) p
   order by r.colaborador_id, r.exame, r.periodicidade_meses;

  truncate app.vencimento;
  insert into app.vencimento (colaborador_id, colaborador, cpf, matricula_esocial, empresa_id, empresa, unidade, setor, funcao,
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
         exists (select 1 from public.funcao_exame fe where fe.funcao_id = c.funcao_id)
    from _col c
    join app.vencimento_exame v on v.colaborador_id = c.id
    left join public.setor s on s.id = c.setor_id
    left join public.funcao f on f.id = c.funcao_id
   group by c.id, c.nome, c.cpf, c.matricula_esocial, c.empresa_id, c.empresa, c.unidade, s.nome, c.setor_nome, f.nome, c.funcao_nome,
            c.ultimo_aso, c.funcao_id;
  get diagnostics n = row_count;
  return jsonb_build_object('colaboradores', n, 'exames', (select count(*) from app.vencimento_exame));
end $$;

revoke execute on function sesmo.normalizar_funcao_exames(), app.recalcular_vencimentos() from public, anon, authenticated;

create or replace view app.vw_aso_vencimento as
  select colaborador_id, colaborador, cpf, matricula_esocial, empresa_id, empresa, unidade, setor, funcao,
         proximo_exame, dias_para_vencer, exames_vencidos, exames_nunca_feitos, status
    from app.vencimento;

create or replace function public.painel_vencimento_detalhe(p_colaborador uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform crm.exige('gestor','operacoes');
  select jsonb_build_object(
           'colaborador_id', v.colaborador_id, 'colaborador', v.colaborador, 'cpf', v.cpf, 'empresa_id', v.empresa_id,
           'empresa', v.empresa, 'unidade', v.unidade, 'setor', v.setor, 'funcao', v.funcao, 'status', v.status,
           'proximo_exame', v.proximo_exame, 'ultimo_aso', v.ultimo_aso, 'tem_pcmso', v.tem_pcmso, 'calculado_em', v.calculado_em,
           'exames', coalesce((select jsonb_agg(jsonb_build_object('exame', x.exame, 'periodicidade', x.periodicidade_texto,
                                'meses', x.periodicidade_meses, 'ultima', x.ultima, 'origem', x.origem_ultima,
                                'proxima', x.proxima, 'status', x.status) order by x.proxima nulls first, x.exame)
                               from app.vencimento_exame x where x.colaborador_id = v.colaborador_id), '[]'::jsonb))
    into r from app.vencimento v where v.colaborador_id = p_colaborador;
  if r is null then raise exception 'Colaborador fora do cálculo de vencimentos (inativo ou de empresa inativa).'; end if;
  return r;
end $$;
revoke execute on function public.painel_vencimento_detalhe(uuid) from public, anon;
grant execute on function public.painel_vencimento_detalhe(uuid) to authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('app-vencimentos', '50 10 * * *', 'select app.recalcular_vencimentos()');
  end if;
end $$;
