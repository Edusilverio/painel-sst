

create table if not exists crm.empresa_interacao (
  id          bigint generated always as identity primary key,
  empresa_id  uuid not null references public.empresa(id) on delete cascade,
  contato_id  uuid references public.empresa_contato(id) on delete set null,
  canal       text not null check (canal in ('whatsapp','email','ligacao','nota')),
  destino     text,
  assunto     text,
  texto       text,
  wa_saida_id bigint,
  usuario_id  uuid,
  em          timestamptz not null default now()
);
create index if not exists empresa_interacao_emp_idx on crm.empresa_interacao (empresa_id, em desc);
alter table crm.empresa_interacao enable row level security;

alter table crm.wa_saida add column if not exists para text not null default 'equipe' check (para in ('equipe','cliente'));
alter table crm.wa_saida add column if not exists empresa_id uuid;
alter table crm.wa_saida add column if not exists usuario_id uuid;

create or replace function crm.ve_empresa(p_empresa uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(crm.papel_atual() <> 'comercial', false)
      or exists (select 1 from crm.negocio n where n.empresa_id = p_empresa and n.responsavel_id = auth.uid())
      or exists (select 1 from crm.contrato c where c.empresa_id = p_empresa and c.responsavel_id = auth.uid())
$$;

create or replace function public.painel_clientes(p_busca text default null, p_situacao text default null, p_limite integer default 50, p_offset integer default 0)
returns table (id uuid, nome text, razao_social text, cnpj text, situacao text, cidade text, uf text, telefone text, email text,
               unidades integer, colaboradores integer, negocios_abertos integer, total bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); dig text; so_minhas boolean;
begin
  perform crm.exige_ativo();
  so_minhas := crm.papel_atual() = 'comercial';
  dig := nullif(regexp_replace(coalesce(termo, ''), '\D', '', 'g'), '');
  return query
    with minhas as (
      select n.empresa_id from crm.negocio n where so_minhas and n.responsavel_id = auth.uid() and n.empresa_id is not null
      union
      select c.empresa_id from crm.contrato c where so_minhas and c.responsavel_id = auth.uid() and c.empresa_id is not null
    ), base as (
      select e.*
        from public.empresa e
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
           (select count(*)::int from public.unidade u where u.empresa_id = pg.id),
           (select count(*)::int from public.colaborador c where c.empresa_id = pg.id and c.situacao = 'ativo'),
           (select count(*)::int from crm.negocio n join crm.etapa et on et.id = n.etapa_id
             where n.empresa_id = pg.id and et.tipo = 'aberta'),
           pg.total_linhas
      from pagina pg
     order by pg.razao_social;
end $$;

create or replace function public.painel_cliente(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb; clin boolean;
begin
  perform crm.exige_ativo();
  if not crm.ve_empresa(p_id) then
    raise exception 'Esta empresa não está na sua carteira.' using errcode = '42501';
  end if;
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
                           where n.empresa_id = e.id and crm.ve_negocio(n.responsavel_id)), '[]'::jsonb),
    'interacoes', coalesce((select jsonb_agg(x order by x.em desc) from (
                              select i.id, i.canal, i.destino, i.assunto, left(i.texto, 300) texto, i.em,
                                     coalesce(p.nome, 'Sistema') usuario, ec.nome contato,
                                     (select s.status from crm.wa_saida s where s.id = i.wa_saida_id) status_wa
                                from crm.empresa_interacao i
                                left join crm.perfil p on p.user_id = i.usuario_id
                                left join public.empresa_contato ec on ec.id = i.contato_id
                               where i.empresa_id = e.id order by i.em desc limit 30) x), '[]'::jsonb),
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

create or replace function public.painel_empresa_contatar(p_empresa uuid, p_contato uuid, p_canal text, p_destino text,
                                                          p_texto text, p_assunto text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := crm.exige('gestor','comercial','operacoes','financeiro'); tel text; sid bigint; iid bigint;
begin
  if not crm.ve_empresa(p_empresa) then raise exception 'Esta empresa não está na sua carteira.' using errcode = '42501'; end if;
  if p_canal not in ('whatsapp','email') then raise exception 'Canal inválido.'; end if;
  if nullif(btrim(p_texto), '') is null and p_canal = 'whatsapp' then raise exception 'Escreva a mensagem.'; end if;
  if p_canal = 'whatsapp' then
    tel := crm.so_digitos(p_destino);
    if length(tel) in (10, 11) then tel := '55' || tel; end if;
    if tel is null or length(tel) not between 12 and 13 then raise exception 'Telefone inválido para WhatsApp.'; end if;
    insert into crm.wa_saida (telefone, texto, origem, ref_id, para, empresa_id, usuario_id)
    values (tel, btrim(p_texto), 'ficha_empresa', p_empresa::text, 'cliente', p_empresa, uid)
    returning id into sid;
  end if;
  insert into crm.empresa_interacao (empresa_id, contato_id, canal, destino, assunto, texto, wa_saida_id, usuario_id)
  values (p_empresa, p_contato, p_canal, coalesce(tel, nullif(btrim(p_destino), '')), nullif(btrim(p_assunto), ''),
          nullif(btrim(p_texto), ''), sid, uid)
  returning id into iid;
  return jsonb_build_object('id', iid, 'wa_saida_id', sid);
end $$;

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
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'telefone', s.telefone, 'texto', s.texto, 'para', s.para,
                                                       'origem', s.origem,
                                                       'atendente', (select p.nome from crm.perfil p where p.user_id = s.usuario_id)) order by s.id)
                     from (select * from crm.wa_saida where status = 'pendente' order by id limit 20) s), '[]'::jsonb);
end $$;

revoke execute on function crm.ve_empresa(uuid) from public, anon, authenticated;
revoke execute on function public.painel_empresa_contatar(uuid, uuid, text, text, text, text) from public, anon;
grant execute on function public.painel_empresa_contatar(uuid, uuid, text, text, text, text) to authenticated;
