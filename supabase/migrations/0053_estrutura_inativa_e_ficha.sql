

create or replace function sesmo.itens_estrutura(p_ativos text, p_inativos text, p_lista text)
returns table (pai text, item jsonb)
language sql stable set search_path = '' as $$
  select distinct on (f.pai, f.item ->> 'id') f.pai, f.item
    from (
      select u.chave pai, x.item, 1 prioridade from sesmo.ultimas(p_ativos) u, jsonb_array_elements(u.conteudo -> p_lista) x(item)
      union all
      select u.chave, x.item, 2 from sesmo.ultimas(p_inativos) u, jsonb_array_elements(u.conteudo -> p_lista) x(item)
    ) f
   order by f.pai, f.item ->> 'id', f.prioridade
$$;

create or replace function sesmo.normalizar_unidades()
returns table (gravadas integer, sem_empresa integer)
language plpgsql security definer set search_path = 'public', 'sesmo', 'pg_catalog' as $$
declare v_ok int := 0; v_orfa int := 0;
begin
  with fonte as (select * from sesmo.itens_estrutura('unidades', 'unidades_inativas', 'unidades')),
  gravadas as (
    insert into unidade (
      empresa_id, sesmo_id, nome, cnpj, cnae, grau_risco, cnae_secundario, cep, telefone, identificador,
      is_matriz, tem_dir, tem_tac, ativa, sesmo_situacao_codigo, sesmo_usuario_cadastro, sesmo_data_cadastro,
      sesmo_usuario_alteracao, sesmo_data_alteracao)
    select m.destino_id, f.item->>'id',
           coalesce(nullif(btrim(f.item->>'nome'),''), f.item->>'razaoSocial', '(sem nome)'),
           app.digits(f.item->>'cpfCnpj'), nullif(f.item->>'cnaeCodigoCnae',''), nullif(f.item->>'cnaeGrauRisco','')::int,
           nullif(f.item->>'cnaeSecundarioCodigoCnae',''), app.digits(f.item->>'cep1'), nullif(f.item->>'telefone',''),
           nullif(f.item->>'identificador',''), (f.item->>'matriz') = 'Sim',
           (f.item->>'isPossuiDirAtiva')::boolean, (f.item->>'isPossuiTacAtiva')::boolean,
           coalesce(nullif(f.item->>'situacao','')::int, 2) <> 1,
           nullif(f.item->>'situacao','')::int, nullif(f.item->>'usuarioCadastro',''), sesmo.ts_br(f.item->>'dataCadastro'),
           nullif(f.item->>'usuarioAlteracao',''), sesmo.ts_br(f.item->>'dataAlteracao')
      from fonte f
      join sesmo.mapeamento m on m.entidade = 'empresa' and m.contexto = '' and m.sesmo_id = f.pai
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

  select count(*) into v_orfa from sesmo.itens_estrutura('unidades', 'unidades_inativas', 'unidades') f
   where not exists (select 1 from sesmo.mapeamento m where m.entidade='empresa' and m.contexto='' and m.sesmo_id = f.pai);

  insert into sesmo.mapeamento (entidade, sesmo_id, destino_id, contexto)
  select 'unidade', sesmo_id, id, '' from unidade where sesmo_id is not null
  on conflict (entidade, sesmo_id, contexto) do nothing;
  return query select v_ok, v_orfa;
end $$;

create or replace function sesmo.normalizar_setores()
returns table (gravados integer, sem_unidade integer)
language plpgsql security definer set search_path = 'public', 'sesmo', 'pg_catalog' as $$
declare v_ok int := 0; v_orfa int := 0;
begin
  with fonte as (select * from sesmo.itens_estrutura('setores', 'setores_inativos', 'setores')),
  gravados as (
    insert into setor (unidade_id, sesmo_id, nome, tipo_setor, id_esocial, controla_esocial, sesmo_situacao_codigo,
                       sesmo_usuario_cadastro, sesmo_data_cadastro, sesmo_usuario_alteracao, sesmo_data_alteracao)
    select m.destino_id, f.item->>'id', coalesce(nullif(btrim(f.item->>'nome'),''), '(sem nome)'),
           nullif(f.item->>'tipoSetor',''), nullif(f.item->>'idEsocial',''), (f.item->>'isEsocial')::boolean,
           nullif(f.item->>'situacao','')::int, nullif(f.item->>'usuarioCadastro',''), sesmo.ts_br(f.item->>'dataCadastro'),
           nullif(f.item->>'usuarioAlteracao',''), sesmo.ts_br(f.item->>'dataAlteracao')
      from fonte f
      join sesmo.mapeamento m on m.entidade = 'unidade' and m.contexto = '' and m.sesmo_id = f.pai
    on conflict (unidade_id, sesmo_id) do update set
      nome = excluded.nome, tipo_setor = coalesce(excluded.tipo_setor, setor.tipo_setor),
      id_esocial = coalesce(excluded.id_esocial, setor.id_esocial), controla_esocial = excluded.controla_esocial,
      sesmo_situacao_codigo = coalesce(excluded.sesmo_situacao_codigo, setor.sesmo_situacao_codigo),
      sesmo_usuario_alteracao = coalesce(excluded.sesmo_usuario_alteracao, setor.sesmo_usuario_alteracao),
      sesmo_data_alteracao = coalesce(excluded.sesmo_data_alteracao, setor.sesmo_data_alteracao)
    returning 1)
  select count(*) into v_ok from gravados;

  select count(*) into v_orfa from sesmo.itens_estrutura('setores', 'setores_inativos', 'setores') f
   where not exists (select 1 from sesmo.mapeamento m where m.entidade='unidade' and m.contexto='' and m.sesmo_id = f.pai);

  insert into sesmo.mapeamento (entidade, sesmo_id, destino_id, contexto)
  select 'setor', sesmo_id, id, '' from setor where sesmo_id is not null
  on conflict (entidade, sesmo_id, contexto) do nothing;
  return query select v_ok, v_orfa;
end $$;

create or replace function sesmo.normalizar_funcoes()
returns table (gravadas integer, sem_setor integer)
language plpgsql security definer set search_path = 'public', 'sesmo', 'pg_catalog' as $$
declare v_ok int := 0; v_orfa int := 0;
begin
  with fonte as (select * from sesmo.itens_estrutura('funcoes', 'funcoes_inativas', 'funcoes')),
  gravadas as (
    insert into funcao (setor_id, sesmo_id, nome, descricao_atividades, quantidade_expostos, identificador,
                        data_inicio_condicao, data_inicio_periodo_esocial, sesmo_situacao_codigo, sesmo_usuario_cadastro,
                        sesmo_data_cadastro, sesmo_usuario_alteracao, sesmo_data_alteracao)
    select m.destino_id, f.item->>'id', coalesce(nullif(btrim(f.item->>'nome'),''), '(sem nome)'),
           nullif(btrim(f.item->>'atividade'),''), nullif(f.item->>'numeroFuncionario','')::int, nullif(f.item->>'idenficador',''),
           sesmo.ts_br(f.item->>'dataInicioCondicao')::date, sesmo.ts_br(f.item->>'dataInicioPeriodoEsocial')::date,
           nullif(f.item->>'situacao','')::int, nullif(f.item->>'usuarioCadastro',''), sesmo.ts_br(f.item->>'dataCadastro'),
           nullif(f.item->>'usuarioAlteracao',''), sesmo.ts_br(f.item->>'dataAlteracao')
      from fonte f
      join sesmo.mapeamento m on m.entidade = 'setor' and m.contexto = '' and m.sesmo_id = f.pai
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

  select count(*) into v_orfa from sesmo.itens_estrutura('funcoes', 'funcoes_inativas', 'funcoes') f
   where not exists (select 1 from sesmo.mapeamento m where m.entidade='setor' and m.contexto='' and m.sesmo_id = f.pai);

  insert into sesmo.mapeamento (entidade, sesmo_id, destino_id, contexto)
  select 'funcao', sesmo_id, id, '' from funcao where sesmo_id is not null
  on conflict (entidade, sesmo_id, contexto) do nothing;
  return query select v_ok, v_orfa;
end $$;

alter table public.colaborador add column if not exists setor_nome text;
alter table public.colaborador add column if not exists funcao_nome text;
alter table public.colaborador add column if not exists setor_id uuid references public.setor(id) on delete set null;
alter table public.colaborador add column if not exists funcao_id uuid references public.funcao(id) on delete set null;
create index if not exists colaborador_funcao_idx on public.colaborador (funcao_id);

create or replace function sesmo.normalizar_colaboradores(p_min bigint default 0, p_max bigint default 9223372036854775807)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  with lst as (
    select u.chave::bigint id, u.conteudo c
      from sesmo.ultimas('colaboradores') u
     where u.chave ~ '^[0-9]+$' and u.chave::bigint between p_min and p_max
  ), vin as (
    select v.chave::bigint col, x
      from sesmo.ultimas('cargos') v, jsonb_array_elements(v.conteudo->'cargos') x
     where v.chave ~ '^[0-9]+$' and v.chave::bigint between p_min and p_max
  ), escolhido as (
    select distinct on (vin.col, e.id)
           vin.col, e.id empresa_id, un.id unidade_id,
           sesmo.ts_br(vin.x->>'dataAdmissao')::date adm,
           sesmo.ts_br(vin.x->>'dataDemissao')::date dem,
           vin.x->>'situacao' sit,
           nullif(btrim(vin.x->>'setorNome'), '') setor_nome,
           nullif(btrim(vin.x->>'nome'), '') funcao_nome
      from vin
      join public.empresa e on e.sesmo_id = vin.x->>'clienteId'
      left join public.unidade un on un.empresa_id = e.id and un.sesmo_id = vin.x->>'unidadeId'
     order by vin.col, e.id,
              (vin.x->>'situacao' = '2' and nullif(vin.x->>'dataDemissao', '') is null) desc,
              sesmo.ts_br(vin.x->>'dataAdmissao') desc nulls last, (vin.x->>'id')::bigint desc
  ), completo as (
    select es.*, st.id setor_id,
           (select f.id from public.funcao f
             where f.setor_id = st.id and lower(btrim(f.nome)) = lower(es.funcao_nome)
             order by f.sesmo_situacao_codigo desc nulls last limit 1) funcao_id
      from escolhido es
      left join lateral (select s.id from public.setor s
                          where s.unidade_id = es.unidade_id and lower(btrim(s.nome)) = lower(es.setor_nome)
                          order by s.sesmo_situacao_codigo desc nulls last limit 1) st on true
  )
  insert into public.colaborador as t (empresa_id, unidade_id, sesmo_id, nome, nome_social, cpf, rg, pis,
                                       data_admissao, data_demissao, situacao, sesmo_situacao_codigo,
                                       setor_nome, funcao_nome, setor_id, funcao_id, origem, extraido_em)
  select es.empresa_id, es.unidade_id, lst.id::text,
         sesmo.corrigir(btrim(lst.c->>'nome')), nullif(btrim(lst.c->>'nomeSocial'), ''),
         nullif(app.digits(lst.c->>'cpfCnpj'), ''), nullif(btrim(lst.c->>'rg'), ''), nullif(app.digits(lst.c->>'pisPasepCi'), ''),
         es.adm, es.dem,
         (case when es.dem is not null and es.dem <= current_date then 'desligado'
               when es.sit = '2' then 'ativo'
               else 'inativo' end)::public.situacao_colaborador,
         es.sit, sesmo.corrigir(es.setor_nome), sesmo.corrigir(es.funcao_nome), es.setor_id, es.funcao_id, 'sesmo_robo', now()
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
end $$;

create or replace function sesmo.enriquecer_colaboradores(p_min bigint default 0, p_max bigint default 9223372036854775807)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  with d as (
    select u.chave, u.conteudo c
      from sesmo.ultimas('colaborador_detalhe') u
     where u.chave ~ '^[0-9]+$' and u.chave::bigint between p_min and p_max
  ), v as (
    select d.chave,
           sesmo.ts_br(d.c->>'dataNasc')::date nasc,
           case d.c->>'sexo' when '1' then 'M' when '0' then 'F' end sexo,
           sesmo.corrigir(nullif(btrim(d.c->>'nomeMae'), '')) mae,
           coalesce(nullif(btrim(d.c->>'celular'), ''), nullif(btrim(d.c->>'telefone'), '')) tel,
           lower(nullif(btrim(d.c->>'email'), '')) email,
           nullif(concat_ws('/', nullif(btrim(d.c->>'ctps'), ''), nullif(btrim(d.c->>'ctpsSerie'), '')), '') ctps,
           nullif(btrim(d.c->>'rgOrgaoSigla'), '') orgao
      from d
  )
  update public.colaborador t set
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
end $$;

revoke execute on function sesmo.itens_estrutura(text, text, text), sesmo.normalizar_unidades(), sesmo.normalizar_setores(),
  sesmo.normalizar_funcoes(), sesmo.normalizar_colaboradores(bigint, bigint), sesmo.enriquecer_colaboradores(bigint, bigint)
  from public, anon, authenticated;

drop function if exists public.painel_colaboradores(uuid, text, text, int, int);
create function public.painel_colaboradores(
  p_empresa uuid, p_busca text default null, p_situacao text default null, p_limite int default 50, p_offset int default 0
) returns table (id uuid, nome text, cpf text, unidade text, setor text, funcao text, data_admissao date, data_demissao date,
                 situacao text, editado boolean, ultimo_atendimento date, total bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); dig text;
begin
  perform crm.exige('gestor','operacoes');
  dig := nullif(regexp_replace(coalesce(termo, ''), '\D', '', 'g'), '');
  return query
    with base as (
      select c.* from public.colaborador c
       where c.empresa_id = p_empresa
         and (p_situacao is null or c.situacao::text = p_situacao)
         and (termo is null or app.norm(c.nome) like '%' || app.norm(termo) || '%'
              or (dig is not null and length(dig) >= 3 and c.cpf like '%' || dig || '%'))
    ), pagina as (
      select b.*, count(*) over () total_linhas from base b
       order by (b.situacao = 'ativo') desc, b.nome
       limit least(greatest(p_limite, 1), 200) offset greatest(p_offset, 0)
    )
    select pg.id, pg.nome::text, pg.cpf::text, u.nome::text, coalesce(s.nome, pg.setor_nome)::text, coalesce(f.nome, pg.funcao_nome)::text,
           pg.data_admissao, pg.data_demissao, pg.situacao::text,
           cardinality(pg.campos_editados) > 0,
           (select max(a.data_atendimento) from public.atendimento a where a.colaborador_id = pg.id),
           pg.total_linhas
      from pagina pg
      left join public.unidade u on u.id = pg.unidade_id
      left join public.setor s on s.id = pg.setor_id
      left join public.funcao f on f.id = pg.funcao_id
     order by (pg.situacao = 'ativo') desc, pg.nome;
end $$;
revoke execute on function public.painel_colaboradores(uuid, text, text, int, int) from public, anon;
grant execute on function public.painel_colaboradores(uuid, text, text, int, int) to authenticated;
