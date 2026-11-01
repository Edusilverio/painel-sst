

create or replace function crm.ve_negocio(p_responsavel uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(crm.papel_atual() <> 'comercial' or p_responsavel = auth.uid(), false)
$$;

create or replace function crm.tg_negocio_do_comercial() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and crm.papel_atual() = 'comercial' and old.responsavel_id is distinct from auth.uid() then
    raise exception 'Este card é de outro responsável.' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists negocio_do_comercial on crm.negocio;
create trigger negocio_do_comercial before update or delete on crm.negocio
  for each row execute function crm.tg_negocio_do_comercial();

revoke execute on function crm.ve_negocio(uuid), crm.tg_negocio_do_comercial() from public, anon, authenticated;

create or replace function public.painel_crm_quadro(
  p_funil uuid, p_responsavel uuid default null, p_busca text default null, p_dias_fechados int default 30
) returns table (
  id uuid, numero bigint, etapa_id uuid, titulo text, cliente text, empresa_id uuid,
  responsavel_id uuid, responsavel_nome text, valor numeric, origem text,
  entrou_etapa_em timestamptz, dias_na_etapa int, atrasado boolean, qtd_itens int,
  previsao_fechamento date, criado_em timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform crm.exige_ativo();
  return query
    select n.id, n.numero, n.etapa_id, n.titulo,
           coalesce(nullif(em.nome_fantasia, ''), em.razao_social, n.cliente_nome)::text,
           n.empresa_id, n.responsavel_id, p.nome, n.valor, n.origem, n.entrou_etapa_em,
           floor(extract(epoch from now() - n.entrou_etapa_em) / 86400)::int,
           (e.tipo = 'aberta' and e.alerta_dias is not null
             and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)),
           (select count(*)::int from crm.negocio_item i where i.negocio_id = n.id),
           n.previsao_fechamento, n.criado_em
      from crm.negocio n
      join crm.etapa e on e.id = n.etapa_id
      left join public.empresa em on em.id = n.empresa_id
      left join crm.perfil p on p.user_id = n.responsavel_id
     where n.funil_id = p_funil
       and crm.ve_negocio(n.responsavel_id)
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

create or replace function public.painel_crm_pendencias(p_so_minhas boolean default false)
returns table (id uuid, numero bigint, titulo text, cliente text, funil_id uuid, funil text,
               etapa text, responsavel_id uuid, responsavel_nome text, dias_na_etapa int,
               alerta_dias int, valor numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := crm.exige_ativo();
  return query
    select n.id, n.numero, n.titulo,
           coalesce(nullif(em.nome_fantasia, ''), em.razao_social, n.cliente_nome)::text,
           f.id, f.nome, e.nome, n.responsavel_id, p.nome,
           floor(extract(epoch from now() - n.entrou_etapa_em) / 86400)::int,
           e.alerta_dias, n.valor
      from crm.negocio n
      join crm.etapa e on e.id = n.etapa_id
      join crm.funil f on f.id = n.funil_id
      left join public.empresa em on em.id = n.empresa_id
      left join crm.perfil p on p.user_id = n.responsavel_id
     where e.tipo = 'aberta' and e.alerta_dias is not null
       and now() - n.entrou_etapa_em >= make_interval(days => e.alerta_dias)
       and (not p_so_minhas or n.responsavel_id = eu)
       and crm.ve_negocio(n.responsavel_id)
     order by n.entrou_etapa_em;
end $$;

create or replace function public.painel_crm_negocio(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform crm.exige_ativo();
  select jsonb_build_object(
           'id', n.id, 'numero', n.numero, 'funil_id', n.funil_id, 'etapa_id', n.etapa_id,
           'titulo', n.titulo, 'empresa_id', n.empresa_id,
           'empresa', case when em.id is null then null else jsonb_build_object(
               'id', em.id, 'razao_social', em.razao_social, 'nome_fantasia', em.nome_fantasia,
               'cnpj', em.cnpj, 'cidade', em.cidade, 'uf', em.uf, 'telefone', em.telefone, 'email', em.email) end,
           'cliente_nome', n.cliente_nome, 'cliente_cnpj', n.cliente_cnpj,
           'contato_nome', n.contato_nome, 'contato_telefone', n.contato_telefone, 'contato_email', n.contato_email,
           'responsavel_id', n.responsavel_id, 'responsavel_nome', p.nome,
           'valor', n.valor, 'origem', n.origem, 'previsao_fechamento', n.previsao_fechamento,
           'motivo_perda', n.motivo_perda, 'observacao', n.observacao,
           'entrou_etapa_em', n.entrou_etapa_em, 'fechado_em', n.fechado_em, 'criado_em', n.criado_em,
           'pode_operar', crm.pode_operar(n.funil_id),
           'negocio_origem', (select jsonb_build_object('id', o.id, 'numero', o.numero, 'funil', fo.nome)
                                from crm.negocio o join crm.funil fo on fo.id = o.funil_id
                               where o.id = n.negocio_origem_id),
           'derivados', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'numero', d.numero,
                                          'funil', fd.nome, 'etapa', ed.nome))
                                    from crm.negocio d join crm.funil fd on fd.id = d.funil_id
                                    join crm.etapa ed on ed.id = d.etapa_id
                                   where d.negocio_origem_id = n.id), '[]'::jsonb),
           'itens', coalesce((select jsonb_agg(jsonb_build_object(
                          'id', i.id, 'produto_id', i.produto_id, 'descricao', i.descricao,
                          'quantidade', i.quantidade, 'preco_unitario', i.preco_unitario, 'total', i.total)
                        order by i.criado_em)
                        from crm.negocio_item i where i.negocio_id = n.id), '[]'::jsonb),
           'eventos', coalesce((select jsonb_agg(x order by x.criado_em desc) from (
                          select ev.id, ev.tipo, ev.texto, ev.criado_em, a.nome as autor,
                                 de.nome as de_etapa, pa.nome as para_etapa
                            from crm.evento ev
                            left join crm.perfil a on a.user_id = ev.autor_id
                            left join crm.etapa de on de.id = ev.de_etapa_id
                            left join crm.etapa pa on pa.id = ev.para_etapa_id
                           where ev.negocio_id = n.id
                           order by ev.criado_em desc limit 200) x), '[]'::jsonb))
    into r
    from crm.negocio n
    left join public.empresa em on em.id = n.empresa_id
    left join crm.perfil p on p.user_id = n.responsavel_id
   where n.id = p_id and crm.ve_negocio(n.responsavel_id);
  if r is null then
    raise exception 'Negócio não encontrado.';
  end if;
  return r;
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
                           where n.empresa_id = e.id and crm.ve_negocio(n.responsavel_id)), '[]'::jsonb),
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

insert into crm.tunel (funil_origem_id, funil_destino_id)
select o.id, d.id from crm.funil o, crm.funil d
 where (o.slug = 'comercial' and d.slug = 'vistoria') or (o.slug = 'vistoria' and d.slug = 'laudos')
on conflict do nothing;

create table if not exists crm.chat_sala (
  id           uuid primary key default gen_random_uuid(),
  tipo         text not null check (tipo in ('geral','grupo','direto')),
  nome         text,
  descricao    text,
  criado_por   uuid references auth.users(id) on delete set null,
  criado_em    timestamptz not null default now(),
  ultima_em    timestamptz not null default now(),
  arquivada    boolean not null default false
);
create unique index if not exists chat_sala_geral on crm.chat_sala (tipo) where tipo = 'geral';

create table if not exists crm.chat_membro (
  sala_id   uuid not null references crm.chat_sala(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  dono      boolean not null default false,
  lida_em   timestamptz not null default now(),
  entrou_em timestamptz not null default now(),
  primary key (sala_id, user_id)
);
create index if not exists chat_membro_user on crm.chat_membro (user_id);

create table if not exists crm.chat_mensagem (
  id         bigint generated always as identity primary key,
  sala_id    uuid not null references crm.chat_sala(id) on delete cascade,
  autor_id   uuid references auth.users(id) on delete set null,
  texto      text not null check (length(texto) between 1 and 4000),
  criado_em  timestamptz not null default now(),
  excluida   boolean not null default false
);
create index if not exists chat_mensagem_sala on crm.chat_mensagem (sala_id, id desc);

alter table crm.chat_sala enable row level security;
alter table crm.chat_membro enable row level security;
alter table crm.chat_mensagem enable row level security;

insert into crm.chat_sala (tipo, nome, descricao) values ('geral', 'Geral', 'Toda a equipe Vitalis')
on conflict do nothing;

create or replace function crm.chat_acesso(p_sala uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from crm.chat_sala s where s.id = p_sala and not s.arquivada
                   and (s.tipo = 'geral' or exists (select 1 from crm.chat_membro m where m.sala_id = s.id and m.user_id = auth.uid())))
$$;

create or replace function crm.chat_exige(p_sala uuid) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare eu uuid;
begin
  eu := crm.exige_ativo();
  if not crm.chat_acesso(p_sala) then raise exception 'Você não participa desta conversa.' using errcode = '42501'; end if;
  return eu;
end $$;

revoke execute on function crm.chat_acesso(uuid), crm.chat_exige(uuid) from public, anon, authenticated;

create or replace function public.painel_chat_pessoas()
returns table (user_id uuid, nome text, papel text, cargo text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige_ativo();
  return query select p.user_id, p.nome::text, p.papel::text, pc.cargo::text
    from crm.perfil p
    left join auth.users u on u.id = p.user_id
    left join crm.pre_cadastro pc on lower(pc.email) = lower(u.email)
   where p.ativo and p.user_id <> auth.uid() order by p.nome;
end $$;

create or replace function public.painel_chat_salas()
returns table (id uuid, tipo text, nome text, descricao text, membros int, ultima_texto text, ultima_autor text,
               ultima_em timestamptz, nao_lidas int, dono boolean, outro_id uuid)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := crm.exige_ativo();
  return query
    with minhas as (
      select s.* from crm.chat_sala s
       where not s.arquivada
         and (s.tipo = 'geral' or exists (select 1 from crm.chat_membro m where m.sala_id = s.id and m.user_id = eu))
    )
    select s.id, s.tipo,
           case when s.tipo = 'direto' then (select p.nome from crm.chat_membro m join crm.perfil p on p.user_id = m.user_id
                                               where m.sala_id = s.id and m.user_id <> eu limit 1)
                else s.nome end::text,
           s.descricao::text,
           case when s.tipo = 'geral' then (select count(*)::int from crm.perfil p where p.ativo)
                else (select count(*)::int from crm.chat_membro m where m.sala_id = s.id) end,
           ul.texto::text, ul.autor::text, ul.criado_em,
           (select count(*)::int from crm.chat_mensagem x
             where x.sala_id = s.id and not x.excluida and x.autor_id is distinct from eu
               and x.criado_em > coalesce((select m.lida_em from crm.chat_membro m where m.sala_id = s.id and m.user_id = eu),
                                          (select p.criado_em from crm.perfil p where p.user_id = eu))),
           coalesce((select m.dono from crm.chat_membro m where m.sala_id = s.id and m.user_id = eu), false),
           case when s.tipo = 'direto' then (select m.user_id from crm.chat_membro m where m.sala_id = s.id and m.user_id <> eu limit 1) end
      from minhas s
      left join lateral (select case when x.excluida then 'Mensagem apagada' else x.texto end texto, p.nome autor, x.criado_em
                           from crm.chat_mensagem x left join crm.perfil p on p.user_id = x.autor_id
                          where x.sala_id = s.id order by x.id desc limit 1) ul on true
     order by (s.tipo = 'geral') desc, coalesce(ul.criado_em, s.criado_em) desc;
end $$;

create or replace function public.painel_chat_nao_lidas() returns int
language sql stable security definer set search_path = '' as $$
  select coalesce(sum(nao_lidas), 0)::int from public.painel_chat_salas()
$$;

create or replace function public.painel_chat_mensagens(p_sala uuid, p_antes bigint default null, p_limite int default 60)
returns table (id bigint, autor_id uuid, autor text, texto text, criado_em timestamptz, excluida boolean, minha boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := crm.chat_exige(p_sala);
  return query
    select x.id, x.autor_id, p.nome::text, case when x.excluida then null else x.texto end, x.criado_em, x.excluida, x.autor_id = eu
      from (select * from crm.chat_mensagem m where m.sala_id = p_sala and (p_antes is null or m.id < p_antes)
             order by m.id desc limit least(greatest(p_limite, 1), 200)) x
      left join crm.perfil p on p.user_id = x.autor_id
     order by x.id;
end $$;

create or replace function public.painel_chat_lida(p_sala uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare eu uuid;
begin
  eu := crm.chat_exige(p_sala);
  insert into crm.chat_membro (sala_id, user_id, lida_em) values (p_sala, eu, now())
  on conflict (sala_id, user_id) do update set lida_em = now();
end $$;

create or replace function public.painel_chat_enviar(p_sala uuid, p_texto text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare eu uuid; novo bigint; t text := btrim(coalesce(p_texto, ''));
begin
  eu := crm.chat_exige(p_sala);
  if t = '' then raise exception 'Escreva uma mensagem.'; end if;
  if length(t) > 4000 then raise exception 'Mensagem muito longa (máximo 4.000 caracteres).'; end if;
  insert into crm.chat_mensagem (sala_id, autor_id, texto) values (p_sala, eu, t) returning id into novo;
  update crm.chat_sala set ultima_em = now() where id = p_sala;
  insert into crm.chat_membro (sala_id, user_id, lida_em) values (p_sala, eu, now())
  on conflict (sala_id, user_id) do update set lida_em = now();
  return novo;
end $$;

create or replace function public.painel_chat_apagar(p_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare eu uuid;
begin
  eu := crm.exige_ativo();
  update crm.chat_mensagem set excluida = true
   where id = p_id and (autor_id = eu or crm.papel_atual() = 'admin');
  if not found then raise exception 'Só dá para apagar as próprias mensagens.'; end if;
end $$;

create or replace function public.painel_chat_direto(p_user uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare eu uuid; s uuid;
begin
  eu := crm.exige_ativo();
  if p_user = eu then raise exception 'Escolha outra pessoa.'; end if;
  if not exists (select 1 from crm.perfil where user_id = p_user and ativo) then raise exception 'Pessoa não encontrada.'; end if;
  select a.sala_id into s from crm.chat_membro a join crm.chat_membro b on b.sala_id = a.sala_id and b.user_id = p_user
    join crm.chat_sala x on x.id = a.sala_id and x.tipo = 'direto'
   where a.user_id = eu limit 1;
  if s is null then
    insert into crm.chat_sala (tipo, criado_por) values ('direto', eu) returning id into s;
    insert into crm.chat_membro (sala_id, user_id) values (s, eu), (s, p_user);
  end if;
  return s;
end $$;

create or replace function public.painel_chat_grupo_salvar(p_id uuid, p_nome text, p_descricao text, p_membros uuid[])
returns uuid language plpgsql security definer set search_path = '' as $$
declare eu uuid; s uuid := p_id; nm text := btrim(coalesce(p_nome, ''));
begin
  eu := crm.exige_ativo();
  if nm = '' then raise exception 'Dê um nome ao grupo.'; end if;
  if s is null then
    insert into crm.chat_sala (tipo, nome, descricao, criado_por) values ('grupo', nm, nullif(btrim(p_descricao), ''), eu) returning id into s;
    insert into crm.chat_membro (sala_id, user_id, dono) values (s, eu, true);
  else
    if not exists (select 1 from crm.chat_sala where id = s and tipo = 'grupo' and not arquivada) then raise exception 'Grupo não encontrado.'; end if;
    if not (crm.papel_atual() in ('admin','gestor')
            or exists (select 1 from crm.chat_membro where sala_id = s and user_id = eu and dono)) then
      raise exception 'Só quem criou o grupo (ou um gestor) pode alterá-lo.' using errcode = '42501';
    end if;
    update crm.chat_sala set nome = nm, descricao = nullif(btrim(p_descricao), '') where id = s;
    delete from crm.chat_membro m where m.sala_id = s and not m.dono and not (m.user_id = any (coalesce(p_membros, '{}')));
  end if;
  insert into crm.chat_membro (sala_id, user_id)
  select s, p.user_id from crm.perfil p where p.ativo and p.user_id = any (coalesce(p_membros, '{}'))
  on conflict do nothing;
  return s;
end $$;

create or replace function public.painel_chat_sala(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform crm.chat_exige(p_id);
  select jsonb_build_object('id', s.id, 'tipo', s.tipo, 'nome', s.nome, 'descricao', s.descricao,
           'pode_editar', s.tipo = 'grupo' and (crm.papel_atual() in ('admin','gestor')
                            or exists (select 1 from crm.chat_membro m where m.sala_id = s.id and m.user_id = auth.uid() and m.dono)),
           'membros', case when s.tipo = 'geral' then '[]'::jsonb else coalesce((
               select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'nome', p.nome, 'dono', m.dono) order by m.dono desc, p.nome)
                 from crm.chat_membro m join crm.perfil p on p.user_id = m.user_id where m.sala_id = s.id), '[]'::jsonb) end)
    into r from crm.chat_sala s where s.id = p_id;
  return r;
end $$;

create or replace function public.painel_chat_sair(p_sala uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare eu uuid;
begin
  eu := crm.chat_exige(p_sala);
  if exists (select 1 from crm.chat_sala where id = p_sala and tipo <> 'grupo') then raise exception 'Só dá para sair de grupos.'; end if;
  delete from crm.chat_membro where sala_id = p_sala and user_id = eu;

  if not exists (select 1 from crm.chat_membro where sala_id = p_sala and dono) then
    update crm.chat_membro set dono = true
     where (sala_id, user_id) = (select sala_id, user_id from crm.chat_membro where sala_id = p_sala order by entrou_em limit 1);
  end if;
  if not exists (select 1 from crm.chat_membro where sala_id = p_sala) then
    update crm.chat_sala set arquivada = true where id = p_sala;
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
