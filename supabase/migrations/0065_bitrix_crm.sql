

alter table crm.negocio add column if not exists bitrix_id bigint unique;
alter table crm.negocio add column if not exists bitrix_responsavel int;
alter table crm.negocio add column if not exists bitrix_sincronizado_em timestamptz;
alter table crm.negocio add column if not exists bitrix_empresa bigint;
create index if not exists negocio_bitrix_empresa_idx on crm.negocio (bitrix_empresa) where bitrix_empresa is not null;
alter table crm.evento add column if not exists bitrix_ref text unique;
alter table crm.negocio_item add column if not exists bitrix_id bigint unique;

create table if not exists crm.bitrix_usuario (
  bitrix_id     int primary key,
  nome          text not null,
  email_bitrix  text,
  email_painel  text
);
alter table crm.bitrix_usuario enable row level security;

create table if not exists crm.bitrix_etapa (
  stage_id    text primary key,
  funil_slug  text not null,
  etapa_nome  text not null
);
alter table crm.bitrix_etapa enable row level security;
insert into crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) values
  ('NEW','comercial','Novo negócio'), ('UC_ENTV2Y','comercial','Contato feito'), ('UC_ZR60DV','comercial','Reunião agendada'),
  ('UC_CQ8N2X','comercial','Follow-up'), ('UC_YDWWOT','comercial','Proposta'), ('UC_FGILL0','comercial','Envio de contrato'),
  ('WON','comercial','Negócio fechado'), ('LOSE','comercial','Oportunidade perdida'),
  ('C4:NEW','faturamento','Não tocado'), ('C4:PREPARATION','faturamento','Em execução'), ('C4:WON','faturamento','Concluído'), ('C4:LOSE','faturamento','Não concluído'),
  ('C6:NEW','vistoria','Não tocado'), ('C6:PREPARATION','vistoria','Em execução'), ('C6:WON','vistoria','Concluído'), ('C6:LOSE','vistoria','Não concluído'),
  ('C8:NEW','laudos','Não tocado'), ('C8:PREPARATION','laudos','Em execução'), ('C8:WON','laudos','Concluído'), ('C8:LOSE','laudos','Não concluído'),
  ('C10:NEW','pos-venda','Contratos fechados'), ('C10:PREPAYMENT_INVOIC','pos-venda','Inadimplentes'),
  ('C10:FINAL_INVOICE','comercial','Renovação'), ('C10:WON','pos-venda','Concluído'), ('C10:LOSE','pos-venda','Sem entrega')
on conflict (stage_id) do update set funil_slug = excluded.funil_slug, etapa_nome = excluded.etapa_nome;

create table if not exists crm.bitrix_empresa (
  bitrix_id   bigint primary key,
  nome        text,
  cnpj        text,
  empresa_id  uuid references public.empresa(id) on delete set null,
  metodo      text check (metodo in ('cnpj','nome','manual')),
  atualizado_em timestamptz not null default now()
);
alter table crm.bitrix_empresa enable row level security;

alter table crm.posvenda_regra add column if not exists max_por_execucao int not null default 30
  check (max_por_execucao between 1 and 1000);

create or replace function crm.bx_txt(p text) returns text
language sql immutable set search_path = '' as $$
  select nullif(btrim(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''), '\[/?[a-zA-Z*]+(=[^\]]*)?\]', '', 'g'),
                                                    '<[^>]+>', ' ', 'g'), '&nbsp;', ' ', 'g')), '')
$$;

create or replace function crm.bx_chave(p text) returns text
language sql immutable set search_path = '' as $$
  select nullif(regexp_replace(lower(coalesce(p, '')), '[^a-z0-9]+', '', 'g'), '')
$$;

create or replace function crm.bx_atual(p_modulo text) returns table (chave text, c jsonb)
language sql stable security definer set search_path = '' as $$
  select distinct on (x.chave) x.chave, x.conteudo from bitrix.captura x where x.modulo = p_modulo
   order by x.chave, x.capturado_em desc
$$;

create or replace function crm.bitrix_mapear_usuarios() returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  insert into crm.bitrix_usuario (bitrix_id, nome, email_bitrix, email_painel)
  select (u.c->>'ID')::int, btrim(coalesce(u.c->>'NAME', '') || ' ' || coalesce(u.c->>'LAST_NAME', '')), lower(u.c->>'EMAIL'),
         (select pc.email from crm.pre_cadastro pc where pc.email = lower(u.c->>'EMAIL'))
    from crm.bx_atual('user') u
  on conflict (bitrix_id) do update set nome = excluded.nome, email_bitrix = excluded.email_bitrix,
    email_painel = coalesce(crm.bitrix_usuario.email_painel, excluded.email_painel);

  update crm.bitrix_usuario set email_painel = 'luana.prado@exemplo.com.br' where bitrix_id = 796;
  update crm.bitrix_usuario set email_painel = 'exames@exemplo.com.br' where bitrix_id = 16;
  get diagnostics n = row_count;
  return (select count(*) from crm.bitrix_usuario);
end $$;

create or replace function crm.bitrix_mapear_empresas() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  with co as (
    select b.chave::bigint id, btrim(b.c->>'TITLE') nome from crm.bx_atual('crm.company') b
  ), rq as (
    select distinct on (r.c->>'ENTITY_ID') (r.c->>'ENTITY_ID')::bigint cid, crm.so_digitos(r.c->>'RQ_CNPJ') cnpj
      from crm.bx_atual('crm.requisite') r
     where r.c->>'ENTITY_TYPE_ID' = '4' and length(crm.so_digitos(r.c->>'RQ_CNPJ')) = 14
     order by r.c->>'ENTITY_ID', r.chave desc
  ), por_cnpj as (
    select distinct on (crm.so_digitos(e.cnpj)) crm.so_digitos(e.cnpj) cnpj, e.id
      from public.empresa e where length(crm.so_digitos(e.cnpj)) = 14
     order by crm.so_digitos(e.cnpj), (e.situacao::text = 'ativo') desc, e.id
  ), nomes as (
    select k, (array_agg(id order by ativo desc, id))[1] id, count(distinct id) filter (where ativo) ativos, count(distinct id) n
      from (select crm.bx_chave(e.razao_social) k, e.id, e.situacao::text = 'ativo' ativo from public.empresa e
            union all
            select crm.bx_chave(e.nome_fantasia), e.id, e.situacao::text = 'ativo' from public.empresa e where nullif(e.nome_fantasia, '') is not null) z
     where k is not null group by k
  )
  insert into crm.bitrix_empresa as t (bitrix_id, nome, cnpj, empresa_id, metodo)
  select co.id, co.nome, rq.cnpj,
         coalesce(pc.id, case when nm.n = 1 or nm.ativos = 1 then nm.id end),
         case when pc.id is not null then 'cnpj' when nm.n = 1 or nm.ativos = 1 then 'nome' end
    from co left join rq on rq.cid = co.id
            left join por_cnpj pc on pc.cnpj = rq.cnpj
            left join nomes nm on nm.k = crm.bx_chave(co.nome)
  on conflict (bitrix_id) do update set nome = excluded.nome, cnpj = excluded.cnpj,
    empresa_id = case when t.metodo = 'manual' then t.empresa_id else excluded.empresa_id end,
    metodo = case when t.metodo = 'manual' then 'manual' else excluded.metodo end,
    atualizado_em = now();
  return (select jsonb_build_object('total', count(*), 'cnpj', count(*) filter (where metodo = 'cnpj'),
                                    'nome', count(*) filter (where metodo = 'nome'), 'manual', count(*) filter (where metodo = 'manual'),
                                    'sem_vinculo', count(*) filter (where empresa_id is null))
            from crm.bitrix_empresa);
end $$;

create or replace view crm.vw_bitrix_negocio as
  with d as (select b.chave::bigint id, b.c from crm.bx_atual('crm.deal') b),
  ct as (select x.chave::bigint deal_id, (select (e->>'CONTACT_ID')::bigint from jsonb_array_elements(x.c) e
                                           order by (e->>'IS_PRIMARY' = 'Y') desc, (e->>'SORT')::int limit 1) contato
           from crm.bx_atual('crm.deal.contacts') x where jsonb_typeof(x.c) = 'array'),
  co as (select b.chave::bigint id, b.c from crm.bx_atual('crm.contact') b),
  fx as (select distinct on (s->>'ID') s->>'ID' id, s->>'VALUE' v
           from bitrix.captura, jsonb_array_elements(conteudo) f, jsonb_array_elements(coalesce(f->'LIST', '[]'::jsonb)) s
          where modulo = 'meta' and chave = 'crm.deal.userfield.list'),
  src as (select s->>'STATUS_ID' id, s->>'NAME' nome from bitrix.captura, jsonb_array_elements(conteudo) s
           where modulo = 'meta' and chave = 'crm.status.list' and s->>'ENTITY_ID' = 'SOURCE')
  select d.id, f.id funil_id, e.id etapa_id, e.tipo,
         coalesce(nullif(btrim(d.c->>'TITLE'), ''), 'Negócio Bitrix #' || d.id) titulo,
         be.empresa_id, coalesce(nullif(be.nome, ''), nullif(btrim(coalesce(cc.c->>'NAME', '') || ' ' || coalesce(cc.c->>'LAST_NAME', '')), ''),
                                 nullif(btrim(d.c->>'TITLE'), ''), 'Cliente do Bitrix') cliente_nome,
         be.cnpj cliente_cnpj,
         nullif(btrim(coalesce(cc.c->>'NAME', '') || ' ' || coalesce(cc.c->>'LAST_NAME', '')), '') contato_nome,
         cc.c->'PHONE'->0->>'VALUE' contato_telefone, lower(cc.c->'EMAIL'->0->>'VALUE') contato_email,
         (select p.user_id from crm.bitrix_usuario bu join crm.perfil p on lower(p.email) = bu.email_painel
           where bu.bitrix_id = (d.c->>'ASSIGNED_BY_ID')::int) responsavel_id,
         (d.c->>'ASSIGNED_BY_ID')::int bitrix_responsavel,
         greatest(coalesce(nullif(d.c->>'OPPORTUNITY', '')::numeric, 0), 0) valor,
         nullif(left(d.c->>'CLOSEDATE', 10), '')::date previsao,
         case when e.tipo = 'perdido' then (select fx.v from fx where fx.id = d.c->>'UF_CRM_65774D897D212') end motivo_perda,
         nullif(concat_ws(E'\n',
           crm.bx_txt(d.c->>'COMMENTS'),
           'Origem no Bitrix: ' || coalesce((select src.nome from src where src.id = d.c->>'SOURCE_ID'), d.c->>'SOURCE_ID'),
           'Tipo de contrato: ' || (select string_agg(fx.v, ', ') from fx, jsonb_array_elements_text(case when jsonb_typeof(d.c->'UF_CRM_1712256341158') = 'array'
                                     then d.c->'UF_CRM_1712256341158' else '[]'::jsonb end) v where fx.id = v),
           'Vencimento do contrato (Bitrix): ' || to_char(nullif(left(d.c->>'UF_CRM_1701218046', 10), '')::date, 'DD/MM/YYYY'),
           'Bitrix #' || d.id), '') observacao,
         (d.c->>'DATE_CREATE')::timestamptz criado_em,
         coalesce((d.c->>'MOVED_TIME')::timestamptz, (d.c->>'DATE_MODIFY')::timestamptz, (d.c->>'DATE_CREATE')::timestamptz) entrou_etapa_em,
         case when d.c->>'CLOSED' = 'Y' or e.tipo <> 'aberta'
              then coalesce((d.c->>'MOVED_TIME')::timestamptz, (d.c->>'DATE_MODIFY')::timestamptz) end fechado_em,
         (d.c->>'DATE_MODIFY')::timestamptz modificado,
         nullif(d.c->>'COMPANY_ID', '0')::bigint bitrix_empresa
    from d
    join crm.bitrix_etapa be2 on be2.stage_id = d.c->>'STAGE_ID'
    join crm.funil f on f.slug = be2.funil_slug
    join crm.etapa e on e.funil_id = f.id and e.nome = be2.etapa_nome
    left join crm.bitrix_empresa be on be.bitrix_id = nullif(d.c->>'COMPANY_ID', '0')::bigint
    left join ct on ct.deal_id = d.id
    left join co cc on cc.id = coalesce(ct.contato, nullif(d.c->>'CONTACT_ID', '0')::bigint);

create or replace function crm.bitrix_importar_negocios() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ins int; upd int;
begin
  insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, cliente_cnpj, contato_nome, contato_telefone,
                           contato_email, responsavel_id, valor, origem, previsao_fechamento, motivo_perda, observacao,
                           entrou_etapa_em, fechado_em, criado_em, atualizado_em, bitrix_id, bitrix_responsavel, bitrix_sincronizado_em, bitrix_empresa)
  select funil_id, etapa_id, titulo, empresa_id, cliente_nome, cliente_cnpj, contato_nome, contato_telefone, contato_email,
         responsavel_id, valor, 'bitrix', previsao, motivo_perda, observacao, entrou_etapa_em, fechado_em, criado_em, now(),
         id, bitrix_responsavel, now(), bitrix_empresa
    from crm.vw_bitrix_negocio x where not exists (select 1 from crm.negocio n where n.bitrix_id = x.id);
  get diagnostics ins = row_count;

  update crm.negocio n set
    funil_id = x.funil_id, etapa_id = x.etapa_id, titulo = x.titulo, empresa_id = coalesce(n.empresa_id, x.empresa_id),
    cliente_nome = x.cliente_nome, cliente_cnpj = x.cliente_cnpj, contato_nome = x.contato_nome,
    contato_telefone = x.contato_telefone, contato_email = x.contato_email,
    responsavel_id = coalesce(n.responsavel_id, x.responsavel_id), bitrix_responsavel = x.bitrix_responsavel, bitrix_empresa = x.bitrix_empresa,
    valor = x.valor, previsao_fechamento = x.previsao, motivo_perda = x.motivo_perda, observacao = x.observacao,
    entrou_etapa_em = x.entrou_etapa_em, fechado_em = x.fechado_em, atualizado_em = now(), bitrix_sincronizado_em = now()
    from crm.vw_bitrix_negocio x
   where n.bitrix_id = x.id and n.atualizado_em <= n.bitrix_sincronizado_em + interval '1 second'
     and (n.etapa_id, n.titulo, n.valor, coalesce(n.observacao, '')) is distinct from (x.etapa_id, x.titulo, x.valor, coalesce(x.observacao, ''));
  get diagnostics upd = row_count;
  return jsonb_build_object('novos', ins, 'atualizados', upd, 'bitrix', (select count(*) from crm.vw_bitrix_negocio));
end $$;

create or replace function crm.bitrix_importar_historico() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare etapas int; ativ int; itens int;
begin

  with h as (
    select s.c, n.id negocio_id, (s.c->>'OWNER_ID')::bigint deal, (s.c->>'CREATED_TIME')::timestamptz em,
           e.id etapa_id,
           lag(e.id) over (partition by s.c->>'OWNER_ID' order by (s.c->>'CREATED_TIME')::timestamptz, (s.c->>'ID')::bigint) de_id
      from crm.bx_atual('crm.stagehistory.2') s
      join crm.negocio n on n.bitrix_id = (s.c->>'OWNER_ID')::bigint
      left join crm.bitrix_etapa be on be.stage_id = s.c->>'STAGE_ID'
      left join crm.funil f on f.slug = be.funil_slug
      left join crm.etapa e on e.funil_id = f.id and e.nome = be.etapa_nome
  )
  insert into crm.evento (negocio_id, tipo, texto, de_etapa_id, para_etapa_id, criado_em, bitrix_ref)
  select h.negocio_id, case when h.c->>'TYPE_ID' = '1' then 'criado' else 'etapa' end,
         case when h.c->>'TYPE_ID' = '1' then 'Criado no Bitrix' else 'Bitrix' end,
         case when h.c->>'TYPE_ID' = '1' then null else h.de_id end, h.etapa_id, h.em, 'sh:' || (h.c->>'ID')
    from h
  on conflict (bitrix_ref) do nothing;
  get diagnostics etapas = row_count;

  insert into crm.evento (negocio_id, tipo, texto, criado_em, bitrix_ref)
  select n.id,
         case when a.c->>'TYPE_ID' = '1' then 'reuniao' when a.c->>'TYPE_ID' = '2' then 'ligacao'
              when a.c->>'TYPE_ID' = '4' then 'email' when a.c->>'PROVIDER_ID' = 'IMOPENLINES_SESSION' then 'whatsapp'
              else 'nota' end,
         left(concat_ws(E'\n',
           case a.c->>'PROVIDER_ID' when 'CRM_TASKS_TASK' then 'Tarefa: ' when 'CRM_TODO' then 'A fazer: '
                                    when 'CRM_WEBFORM' then 'Formulário: ' else '' end || coalesce(crm.bx_txt(a.c->>'SUBJECT'), ''),
           crm.bx_txt(a.c->>'DESCRIPTION'),
           case when a.c->>'COMPLETED' = 'Y' then '(concluída no Bitrix)' end,
           '— ' || coalesce((select bu.nome from crm.bitrix_usuario bu where bu.bitrix_id = (a.c->>'RESPONSIBLE_ID')::int), 'Bitrix')), 4000),
         coalesce((a.c->>'CREATED')::timestamptz, now()), 'act:' || a.chave
    from crm.bx_atual('crm.activity') a
    join crm.negocio n on n.bitrix_id = (a.c->>'OWNER_ID')::bigint
   where a.c->>'OWNER_TYPE_ID' = '2'
  on conflict (bitrix_ref) do nothing;
  get diagnostics ativ = row_count;

  insert into crm.negocio_item as t (negocio_id, produto_id, descricao, quantidade, preco_unitario, bitrix_id)
  select n.id,
         (select p.id from crm.produto p where crm.bx_chave(p.nome) = crm.bx_chave(r->>'PRODUCT_NAME') limit 1),
         coalesce(nullif(btrim(r->>'PRODUCT_NAME'), ''), 'Item do Bitrix'),
         greatest(coalesce((r->>'QUANTITY')::numeric, 1), 0.01), greatest(coalesce((r->>'PRICE')::numeric, 0), 0), (r->>'ID')::bigint
    from crm.bx_atual('crm.deal.productrows') x
    join crm.negocio n on n.bitrix_id = x.chave::bigint
    cross join lateral jsonb_array_elements(case when jsonb_typeof(x.c) = 'array' then x.c else '[]'::jsonb end) r
  on conflict (bitrix_id) do update set descricao = excluded.descricao, quantidade = excluded.quantidade, preco_unitario = excluded.preco_unitario
   where (t.descricao, t.quantidade, t.preco_unitario) is distinct from (excluded.descricao, excluded.quantidade, excluded.preco_unitario);
  get diagnostics itens = row_count;
  return jsonb_build_object('etapas', etapas, 'atividades', ativ, 'itens', itens);
end $$;

create or replace function crm.bitrix_atribuir(p_user uuid, p_email text) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update crm.negocio n set responsavel_id = p_user, bitrix_sincronizado_em = now(), atualizado_em = now()
    from crm.bitrix_usuario bu
   where bu.email_painel = lower(trim(p_email)) and n.bitrix_responsavel = bu.bitrix_id and n.responsavel_id is null;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function crm.aplicar_pre_cadastro(p_user uuid, p_email text, p_confirmado boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare pc crm.pre_cadastro; f uuid;
begin
  select * into pc from crm.pre_cadastro where email = lower(trim(p_email));
  if pc.email is null then return; end if;
  update crm.perfil set nome = pc.nome, papel = pc.papel, libera_agenda = pc.libera_agenda,
                        telefone = coalesce(telefone, pc.telefone),
                        ativo = ativo or p_confirmado
   where user_id = p_user and (not ativo or p_confirmado);
  if p_confirmado then
    update crm.pre_cadastro set usado_em = coalesce(usado_em, now()) where email = pc.email;
    if pc.rodizio_ordem is not null then
      select id into f from crm.funil where slug = 'comercial';
      insert into crm.rodizio (funil_id, user_id, ordem, ativo) values (f, p_user, pc.rodizio_ordem, true)
      on conflict (funil_id, user_id) do nothing;
    end if;
    perform crm.bitrix_atribuir(p_user, pc.email);
  end if;
end $$;

create or replace function crm.posvenda_renovacao() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; qtd int := 0; meses int; lim int; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        etapa_base uuid; etapa_ok uuid; neg uuid; num bigint;
begin
  select p.meses, p.max_por_execucao into meses, lim from crm.posvenda_regra p where p.id;
  select e.id into etapa_base from crm.etapa e join crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda'
   where e.nome ilike 'contratos%' and e.ativo limit 1;
  select e.id into etapa_ok from crm.etapa e join crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda'
   where e.tipo = 'ganho' and e.ativo order by e.ordem limit 1;
  if etapa_base is null then return 0; end if;
  for r in
    select * from (
      select n.*, greatest(
               n.criado_em::date,
               (select max(c.inicio) from crm.contrato c where c.empresa_id = n.empresa_id and c.status = 'assinado'),

               (select max(g.fechado_em)::date from crm.negocio g join crm.etapa ge on ge.id = g.etapa_id and ge.tipo = 'ganho'
                  join crm.funil gf on gf.id = g.funil_id and gf.slug = 'comercial'
                 where (n.empresa_id is not null and g.empresa_id = n.empresa_id)
                    or (n.bitrix_empresa is not null and g.bitrix_empresa = n.bitrix_empresa))) base
        from crm.negocio n where n.etapa_id = etapa_base) x
     where x.base <= hoje - make_interval(months => meses)
     order by x.base, x.numero
  loop
    exit when qtd >= coalesce(lim, 30);
    neg := crm.abrir_renovacao(r.empresa_id, r.titulo, r.cliente_nome, r.responsavel_id, r.valor, r.id,
             'Cliente completou ' || meses || ' meses no Pós-venda (desde ' || to_char(r.base, 'DD/MM/YYYY') || ')');
    continue when neg is null;
    update crm.negocio set bitrix_responsavel = r.bitrix_responsavel where id = neg and responsavel_id is null and bitrix_responsavel is null;
    select numero into num from crm.negocio where id = neg;
    if etapa_ok is not null then
      perform crm.posvenda_mover(r.id, etapa_ok, 'Completou ' || meses || ' meses: enviado ao Comercial › Renovação (#' || num || ')', false);
    end if;
    qtd := qtd + 1;
  end loop;
  return qtd;
end $$;

create or replace function crm.bitrix_consolidar_posvenda() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; qtd int := 0; base uuid; ok uuid;
begin
  select e.id into base from crm.etapa e join crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda' where e.nome = 'Contratos fechados';
  select e.id into ok from crm.etapa e join crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda' where e.nome = 'Concluído';
  if base is null or ok is null then return 0; end if;
  for r in
    select n.id, x.mais_novo, x.quando from crm.negocio n
      join lateral (select m.numero mais_novo, m.criado_em quando from crm.negocio m
                     where m.etapa_id = base and m.bitrix_empresa = n.bitrix_empresa and m.criado_em > n.criado_em
                     order by m.criado_em desc limit 1) x on true
     where n.etapa_id = base and n.bitrix_id is not null and n.bitrix_empresa is not null
  loop
    perform crm.posvenda_mover(r.id, ok, 'Importação do Bitrix: substituído pelo card mais recente do cliente (#' || r.mais_novo || ')', false);

    update crm.negocio set fechado_em = r.quando, entrou_etapa_em = r.quando, bitrix_sincronizado_em = now(), atualizado_em = now() where id = r.id;
    qtd := qtd + 1;
  end loop;
  return qtd;
end $$;

create or replace function crm.bitrix_sincronizar() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u int; e jsonb; n jsonb; h jsonb; c int; a int := 0; p record;
begin
  u := crm.bitrix_mapear_usuarios();
  e := crm.bitrix_mapear_empresas();
  n := crm.bitrix_importar_negocios();
  h := crm.bitrix_importar_historico();
  c := crm.bitrix_consolidar_posvenda();
  for p in select user_id, email from crm.perfil where ativo loop
    a := a + crm.bitrix_atribuir(p.user_id, p.email);
  end loop;
  return jsonb_build_object('usuarios', u, 'empresas', e, 'negocios', n, 'historico', h, 'posvenda_consolidados', c, 'atribuidos_agora', a);
end $$;

create or replace function public.painel_bitrix_empresas(p_busca text default null, p_so_sem_vinculo boolean default true,
                                                         p_limite int default 100, p_offset int default 0)
returns table (bitrix_id bigint, nome text, cnpj text, empresa_id uuid, empresa text, metodo text, negocios bigint, abertos bigint, total bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform crm.exige('gestor');
  return query
    select b.bitrix_id, b.nome, b.cnpj, b.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social), b.metodo,
           (select count(*) from crm.negocio n where n.bitrix_empresa = b.bitrix_id),
           (select count(*) from crm.negocio n join crm.etapa et on et.id = n.etapa_id and et.tipo = 'aberta'
             where n.bitrix_empresa = b.bitrix_id),
           count(*) over ()
      from crm.bitrix_empresa b left join public.empresa e on e.id = b.empresa_id
     where (not p_so_sem_vinculo or b.empresa_id is null)
       and (termo is null or b.nome ilike '%' || termo || '%' or b.cnpj like '%' || crm.so_digitos(termo) || '%')
     order by b.nome
     limit least(greatest(p_limite, 1), 500) offset greatest(p_offset, 0);
end $$;

create or replace function public.painel_bitrix_empresa_vincular(p_bitrix_id bigint, p_empresa uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare b crm.bitrix_empresa; n int;
begin
  perform crm.exige('gestor');
  select * into b from crm.bitrix_empresa where bitrix_id = p_bitrix_id;
  if b.bitrix_id is null then raise exception 'Empresa do Bitrix não encontrada.'; end if;
  update crm.bitrix_empresa set empresa_id = p_empresa, metodo = case when p_empresa is null then null else 'manual' end, atualizado_em = now()
   where bitrix_id = p_bitrix_id;

  update crm.negocio n set empresa_id = p_empresa where n.bitrix_empresa = p_bitrix_id;
  get diagnostics n = row_count;
  insert into crm.edicao (tabela, registro_id, usuario_id, acao, mudancas)
  select 'empresa', p_empresa, auth.uid(), 'editar',
         jsonb_build_object('vinculo_bitrix', jsonb_build_object('de', b.empresa_id, 'para', b.nome || ' (Bitrix #' || p_bitrix_id || ', ' || n || ' cards)'))
   where p_empresa is not null;
  return n;
end $$;

revoke all on crm.vw_bitrix_negocio from public, anon, authenticated;
revoke execute on function crm.bx_txt(text), crm.bx_chave(text), crm.bx_atual(text), crm.bitrix_mapear_usuarios(),
  crm.bitrix_mapear_empresas(), crm.bitrix_importar_negocios(), crm.bitrix_importar_historico(), crm.bitrix_atribuir(uuid, text),
  crm.aplicar_pre_cadastro(uuid, text, boolean), crm.posvenda_renovacao(), crm.bitrix_consolidar_posvenda(), crm.bitrix_sincronizar() from public, anon, authenticated;
revoke execute on function public.painel_bitrix_empresas(text, boolean, int, int), public.painel_bitrix_empresa_vincular(bigint, uuid) from public, anon;
grant execute on function public.painel_bitrix_empresas(text, boolean, int, int), public.painel_bitrix_empresa_vincular(bigint, uuid) to authenticated;
