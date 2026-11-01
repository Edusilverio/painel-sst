

alter table public.empresa         add column if not exists campos_editados text[] not null default '{}';
alter table public.empresa_contato add column if not exists campos_editados text[] not null default '{}';
alter table public.empresa_contato add column if not exists origem text not null default 'sesmo';
alter table public.unidade         add column if not exists campos_editados text[] not null default '{}';
alter table public.colaborador     add column if not exists campos_editados text[] not null default '{}';
alter table public.atendimento     add column if not exists campos_editados text[] not null default '{}';

create table if not exists crm.edicao (
  id          bigint generated always as identity primary key,
  tabela      text not null,
  registro_id uuid not null,
  acao        text not null default 'editar',
  mudancas    jsonb not null default '{}',
  usuario_id  uuid,
  em          timestamptz not null default now()
);
create index if not exists edicao_registro_idx on crm.edicao (tabela, registro_id, em desc);
alter table crm.edicao enable row level security;

create or replace function crm.tg_preserva_edicao() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_setting('crm.edicao_painel', true) = 'on' or cardinality(old.campos_editados) = 0 then
    return new;
  end if;
  new := jsonb_populate_record(new, (select jsonb_object_agg(k, to_jsonb(old) -> k)
                                        from unnest(old.campos_editados) k));
  new.campos_editados := old.campos_editados;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['empresa','empresa_contato','unidade','colaborador','atendimento'] loop
    execute format('drop trigger if exists trg_preserva_edicao on public.%I', t);
    execute format('create trigger trg_preserva_edicao before update on public.%I
                      for each row execute function crm.tg_preserva_edicao()', t);
  end loop;
end $$;

create or replace function crm.limpar_dados(p_dados jsonb, p_campos text[]) returns jsonb
language sql immutable set search_path = '' as $$
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

create or replace function crm.editar(p_tabela text, p_id uuid, p_dados jsonb) returns text[]
language plpgsql security definer set search_path = '' as $$
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
    insert into crm.edicao (tabela, registro_id, mudancas, usuario_id)
    values (p_tabela, p_id, (select jsonb_object_agg(k, jsonb_build_object('de', antes -> k, 'para', depois -> k)) from unnest(mud) k),
            auth.uid());
  end if;
  perform set_config('crm.edicao_painel', 'off', true);
  return coalesce(mud, '{}');
end $$;

create or replace function crm.criar(p_tabela text, p_dados jsonb, p_fixos jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare d jsonb := p_dados || p_fixos; cols text; novo uuid;
begin
  select string_agg(quote_ident(k), ', ') into cols from jsonb_object_keys(d) k;
  perform set_config('crm.edicao_painel', 'on', true);
  execute format('insert into public.%1$I (%2$s) select %2$s from jsonb_populate_record(null::public.%1$I, $1) returning id',
                 p_tabela, cols) into novo using d;
  insert into crm.edicao (tabela, registro_id, acao, mudancas, usuario_id)
  values (p_tabela, novo, 'criar', (select jsonb_object_agg(k, jsonb_build_object('de', null, 'para', v)) from jsonb_each(p_dados) e(k, v)), auth.uid());
  perform set_config('crm.edicao_painel', 'off', true);
  return novo;
end $$;

create or replace function crm.historico_edicao(p_tabela text, p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('em', e.em, 'acao', e.acao, 'mudancas', e.mudancas,
                                               'usuario', coalesce(p.nome, u.email)) order by e.em desc), '[]'::jsonb)
    from (select * from crm.edicao where tabela = p_tabela and registro_id = p_id order by em desc limit 30) e
    left join crm.perfil p on p.user_id = e.usuario_id
    left join auth.users u on u.id = e.usuario_id
$$;

create or replace function crm.pode_editar_dados() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(crm.papel_atual() in ('admin','gestor'), false)
$$;

revoke execute on function crm.tg_preserva_edicao(), crm.limpar_dados(jsonb, text[]), crm.editar(text, uuid, jsonb),
  crm.criar(text, jsonb, jsonb), crm.historico_edicao(text, uuid), crm.pode_editar_dados() from public, anon, authenticated;

create or replace function public.painel_empresa_salvar(p_id uuid, p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare d jsonb; mud text[];
begin
  perform crm.exige('gestor');
  d := crm.limpar_dados(p_dados, array['razao_social','nome_fantasia','cnpj','situacao','cnae_principal','grau_risco',
                                       'cep','logradouro','numero','complemento','bairro','cidade','uf','telefone','email',
                                       'contrato_inicio','contrato_fim']);
  if d ? 'razao_social' and d ->> 'razao_social' is null then raise exception 'Informe a razão social.'; end if;
  if d ? 'situacao' and d ->> 'situacao' is null then d := d - 'situacao'; end if;
  if d ->> 'cnpj' is not null and length(d ->> 'cnpj') not in (11, 14) then raise exception 'CNPJ (ou CPF) com número de dígitos inválido.'; end if;
  if d ->> 'uf' is not null and length(d ->> 'uf') <> 2 then raise exception 'UF deve ter 2 letras.'; end if;
  if d ->> 'grau_risco' is not null and (d ->> 'grau_risco')::int not between 1 and 4 then raise exception 'Grau de risco vai de 1 a 4.'; end if;
  mud := crm.editar('empresa', p_id, d);
  return jsonb_build_object('alterados', to_jsonb(mud));
end $$;

create or replace function public.painel_empresa_contato_salvar(p_empresa uuid, p_id uuid, p_dados jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare d jsonb;
begin
  perform crm.exige('gestor');
  d := crm.limpar_dados(p_dados, array['nome','cargo','email','telefone','tipo','recebe_alerta_exame']);
  if coalesce(d ->> 'nome', '') = '' and p_id is null then raise exception 'Informe o nome do contato.'; end if;
  if p_id is null then
    if not exists (select 1 from public.empresa where id = p_empresa) then raise exception 'Empresa não encontrada.'; end if;
    return crm.criar('empresa_contato', d, jsonb_build_object('empresa_id', p_empresa, 'origem', 'manual'));
  end if;
  perform crm.editar('empresa_contato', p_id, d);
  return p_id;
end $$;

create or replace function public.painel_empresa_contato_excluir(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare c jsonb;
begin
  perform crm.exige('gestor');
  delete from public.empresa_contato t where t.id = p_id returning to_jsonb(t) into c;
  if c is null then raise exception 'Contato não encontrado.'; end if;
  insert into crm.edicao (tabela, registro_id, acao, mudancas, usuario_id)
  values ('empresa_contato', p_id, 'excluir', jsonb_build_object('registro', c), auth.uid());
end $$;

create or replace function public.painel_unidade_salvar(p_empresa uuid, p_id uuid, p_dados jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare d jsonb;
begin
  perform crm.exige('gestor');
  d := crm.limpar_dados(p_dados, array['nome','cnpj','cnae','grau_risco','cidade','uf','endereco','ativa','is_matriz']);
  if d ? 'nome' and d ->> 'nome' is null then raise exception 'Informe o nome da unidade.'; end if;
  if d ->> 'cnpj' is not null and length(d ->> 'cnpj') not in (11, 14) then raise exception 'CNPJ com número de dígitos inválido.'; end if;
  if d ->> 'uf' is not null and length(d ->> 'uf') <> 2 then raise exception 'UF deve ter 2 letras.'; end if;
  if p_id is null then
    if d ->> 'nome' is null then raise exception 'Informe o nome da unidade.'; end if;
    if not exists (select 1 from public.empresa where id = p_empresa) then raise exception 'Empresa não encontrada.'; end if;
    return crm.criar('unidade', d, jsonb_build_object('empresa_id', p_empresa));
  end if;
  perform crm.editar('unidade', p_id, d);
  return p_id;
end $$;

create or replace function public.painel_colaboradores(
  p_empresa uuid, p_busca text default null, p_situacao text default null, p_limite int default 50, p_offset int default 0
) returns table (id uuid, nome text, cpf text, unidade text, data_admissao date, data_demissao date,
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
    select pg.id, pg.nome::text, pg.cpf::text, u.nome::text, pg.data_admissao, pg.data_demissao, pg.situacao::text,
           cardinality(pg.campos_editados) > 0,
           (select max(a.data_atendimento) from public.atendimento a where a.colaborador_id = pg.id),
           pg.total_linhas
      from pagina pg left join public.unidade u on u.id = pg.unidade_id
     order by (pg.situacao = 'ativo') desc, pg.nome;
end $$;

create or replace function public.painel_colaborador(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform crm.exige('gestor','operacoes');
  select to_jsonb(c) - 'sesmo_usuario_cadastro' - 'sesmo_usuario_alteracao'
         || jsonb_build_object(
              'empresa', coalesce(nullif(e.nome_fantasia, ''), e.razao_social),
              'unidade', u.nome,
              'origem', c.origem::text,
              'atendimentos', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'data', coalesce(a.data_atendimento, a.data_agendada::date),
                                         'tipo', a.tipo, 'situacao', a.situacao, 'aso_resultado', a.aso_resultado) order by coalesce(a.data_atendimento, a.data_agendada::date) desc)
                                         from public.atendimento a where a.colaborador_id = c.id), '[]'::jsonb),
              'historico', crm.historico_edicao('colaborador', c.id),
              'pode_editar', crm.pode_editar_dados())
    into r
    from public.colaborador c
    join public.empresa e on e.id = c.empresa_id
    left join public.unidade u on u.id = c.unidade_id
   where c.id = p_id;
  if r is null then raise exception 'Colaborador não encontrado.'; end if;
  return r;
end $$;

create or replace function public.painel_colaborador_salvar(p_id uuid, p_empresa uuid, p_dados jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare d jsonb; emp uuid;
begin
  perform crm.exige('gestor');
  d := crm.limpar_dados(p_dados, array['nome','nome_social','cpf','rg','rg_orgao_emissor','data_nascimento','sexo','nome_mae',
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

  emp := coalesce(p_empresa, (select empresa_id from public.colaborador where id = p_id));
  if d ->> 'unidade_id' is not null and not exists (select 1 from public.unidade u where u.id = (d ->> 'unidade_id')::uuid and u.empresa_id = emp) then
    raise exception 'A unidade escolhida não é desta empresa.';
  end if;
  if d ->> 'cpf' is not null and exists (select 1 from public.colaborador c where c.empresa_id = emp and c.cpf = d ->> 'cpf'
                                           and c.id is distinct from p_id and c.situacao = 'ativo') then
    raise exception 'Já existe colaborador ativo com este CPF nesta empresa.';
  end if;

  if p_id is null then
    if d ->> 'nome' is null then raise exception 'Informe o nome do colaborador.'; end if;
    if not exists (select 1 from public.empresa where id = p_empresa) then raise exception 'Empresa não encontrada.'; end if;
    return crm.criar('colaborador', d, jsonb_build_object('empresa_id', p_empresa, 'origem', 'manual'));
  end if;
  perform crm.editar('colaborador', p_id, d);
  return p_id;
end $$;

create or replace function public.painel_atendimento(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform crm.exige('gestor','operacoes');
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
                                 from public.atendimento_exame ae join public.exame_tipo et on et.id = ae.exame_tipo_id
                                where ae.atendimento_id = a.id), '[]'::jsonb),
           'historico', crm.historico_edicao('atendimento', a.id),
           'pode_editar', crm.pode_editar_dados())
    into r
    from public.atendimento a
    join public.colaborador c on c.id = a.colaborador_id
    join public.empresa e on e.id = a.empresa_id
    left join public.funcao f on f.id = a.funcao_id
    left join public.profissional p on p.id = a.profissional_id
   where a.id = p_id;
  if r is null then raise exception 'Atendimento não encontrado.'; end if;
  return r;
end $$;

create or replace function public.painel_atendimento_salvar(p_id uuid, p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare d jsonb; mud text[]; dia date; hora time;
begin
  perform crm.exige('gestor');
  d := crm.limpar_dados(p_dados, array['tipo','situacao','data_atendimento','profissional_id','aso_resultado','aso_emitido_em',
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
  mud := crm.editar('atendimento', p_id, d);
  return jsonb_build_object('alterados', to_jsonb(mud));
end $$;

create or replace function public.painel_edicao_liberar(p_tabela text, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare antes text[];
begin
  perform crm.exige('gestor');
  if p_tabela not in ('empresa','empresa_contato','unidade','colaborador','atendimento') then
    raise exception 'Tabela inválida.';
  end if;
  execute format('select campos_editados from public.%I where id = $1', p_tabela) into antes using p_id;
  if antes is null then raise exception 'Registro não encontrado.'; end if;
  perform set_config('crm.edicao_painel', 'on', true);
  execute format('update public.%I set campos_editados = ''{}'' where id = $1', p_tabela) using p_id;
  perform set_config('crm.edicao_painel', 'off', true);
  insert into crm.edicao (tabela, registro_id, acao, mudancas, usuario_id)
  values (p_tabela, p_id, 'liberar', jsonb_build_object('campos', to_jsonb(antes)), auth.uid());
end $$;

create or replace function public.painel_cliente(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb; clin boolean;
begin
  perform crm.exige_ativo();
  clin := crm.pode_clinico();
  select jsonb_build_object(
    'id', e.id, 'razao_social', e.razao_social, 'nome_fantasia', e.nome_fantasia, 'cnpj', e.cnpj,
    'situacao', coalesce(e.situacao::text, 'a_confirmar'), 'cnae_principal', e.cnae_principal,
    'grau_risco', e.grau_risco, 'cidade', e.cidade, 'uf', e.uf, 'cep', e.cep,
    'logradouro', e.logradouro, 'numero', e.numero, 'complemento', e.complemento, 'bairro', e.bairro,
    'endereco', concat_ws(', ', nullif(e.logradouro, ''), nullif(e.numero, ''), nullif(e.complemento, ''), nullif(e.bairro, '')),
    'telefone', e.telefone, 'email', e.email,
    'contrato_inicio', e.contrato_inicio, 'contrato_fim', e.contrato_fim,
    'sesmo_id', e.sesmo_id, 'campos_editados', to_jsonb(e.campos_editados),
    'pode_editar', crm.pode_editar_dados(),
    'contatos', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'cargo', c.cargo, 'email', c.email,
                              'telefone', c.telefone, 'tipo', c.tipo, 'recebe_alerta_exame', c.recebe_alerta_exame,
                              'origem', c.origem) order by c.nome)
                            from public.empresa_contato c where c.empresa_id = e.id), '[]'::jsonb),
    'unidades', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'nome', u.nome, 'cnpj', u.cnpj,
                              'cidade', u.cidade, 'uf', u.uf, 'ativa', u.ativa, 'endereco', u.endereco,
                              'cnae', u.cnae, 'grau_risco', u.grau_risco, 'is_matriz', u.is_matriz,
                              'editado', cardinality(u.campos_editados) > 0, 'campos_editados', to_jsonb(u.campos_editados),
                              'setores', (select count(*) from public.setor s where s.unidade_id = u.id),
                              'colaboradores', (select count(*) from public.colaborador c where c.unidade_id = u.id and c.situacao = 'ativo'))
                            order by u.nome)
                            from public.unidade u where u.empresa_id = e.id), '[]'::jsonb),
    'colaboradores_ativos', (select count(*) from public.colaborador c where c.empresa_id = e.id and c.situacao = 'ativo'),
    'documentos', coalesce((select jsonb_agg(jsonb_build_object('tipo', d.tipo, 'versao', d.versao,
                              'vigencia_inicio', d.vigencia_inicio, 'vigencia_fim', d.vigencia_fim, 'situacao', d.situacao)
                            order by d.vigencia_fim desc nulls last)
                            from public.documento d where d.empresa_id = e.id), '[]'::jsonb),
    'negocios', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'numero', n.numero, 'titulo', n.titulo,
                              'funil', f.nome, 'etapa', et.nome, 'tipo', et.tipo, 'valor', n.valor, 'criado_em', n.criado_em)
                            order by n.criado_em desc)
                            from crm.negocio n join crm.funil f on f.id = n.funil_id join crm.etapa et on et.id = n.etapa_id
                           where n.empresa_id = e.id), '[]'::jsonb),
    'historico', case when crm.pode_editar_dados() then crm.historico_edicao('empresa', e.id) else '[]'::jsonb end,
    'acesso_clinico', clin,
    'vencimentos', case when clin then (
        select jsonb_build_object(
          'vencido', count(*) filter (where v.status = 'vencido'),
          'vence_em_30_dias', count(*) filter (where v.status = 'vence_em_30_dias'),
          'vence_em_60_dias', count(*) filter (where v.status = 'vence_em_60_dias'),
          'em_dia', count(*) filter (where v.status = 'em_dia'))
          from app.vw_aso_vencimento v where v.empresa_id = e.id) end,
    'ultimo_atendimento', case when clin then (select max(a.data_atendimento) from public.atendimento a where a.empresa_id = e.id) end,
    'atendimentos_12m', case when clin then (select count(*) from public.atendimento a
                                              where a.empresa_id = e.id and a.data_atendimento >= now() - interval '12 months') end
  ) into r
  from public.empresa e where e.id = p_id;
  if r is null then raise exception 'Cliente não encontrado.'; end if;
  return r;
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
