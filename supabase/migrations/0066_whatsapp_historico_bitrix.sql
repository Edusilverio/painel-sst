

create table if not exists crm.wa_historico_conversa (
  chat_id        bigint primary key,
  nome           text,
  canal          text,
  telefone       text,
  bitrix_deal    bigint,
  bitrix_contato bigint,
  bitrix_empresa bigint,
  negocio_id     uuid references crm.negocio(id) on delete set null,
  empresa_id     uuid references public.empresa(id) on delete set null,
  iniciada_em    timestamptz,
  ultima_em      timestamptz,
  mensagens      int not null default 0,
  ultima_texto   text
);
create index if not exists wa_hist_conv_tel_idx on crm.wa_historico_conversa (right(telefone, 8));
create index if not exists wa_hist_conv_emp_idx on crm.wa_historico_conversa (empresa_id);

create table if not exists crm.wa_historico_msg (
  id          bigint primary key,
  chat_id     bigint not null references crm.wa_historico_conversa(chat_id) on delete cascade,
  em          timestamptz not null,
  quem        text not null check (quem in ('cliente','equipe','sistema')),
  autor       text,
  texto       text,
  arquivos    text
);
create index if not exists wa_hist_msg_chat_idx on crm.wa_historico_msg (chat_id, em);

alter table crm.wa_historico_conversa enable row level security;
alter table crm.wa_historico_msg enable row level security;

create or replace function crm.bx_msg(p text) returns text
language sql immutable set search_path = '' as $$
  select nullif(btrim(
    regexp_replace(
      regexp_replace(
        regexp_replace(replace(replace(coalesce(p, ''), '[br]', E'\n'), '[BR]', E'\n'),
                       '\[(USER|CHAT|URL|DISK|PCH|CALL|SEND|PUT|ICON|ATTACH)[^\]]*\]', '', 'gi'),
        '\[/?(USER|CHAT|URL|DISK|PCH|CALL|SEND|PUT|ICON|ATTACH|b|i|u|s|quote|code|size|color)[^\]]*\]', '', 'gi'),
      '-{20,}', '—', 'g')), '')
$$;

create or replace function crm.bitrix_importar_whatsapp() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare conv int; msgs int;
begin

  with d as (
    select b.chave::bigint chat_id, b.c->'dialog' g from crm.bx_atual('im.dialog') b
  ), u as (
    select distinct on ((m.c->>'chat_id')::bigint, (us->>'id')::int) (m.c->>'chat_id')::bigint chat_id, (us->>'id')::int uid,
           crm.so_digitos(coalesce(us->'phones'->>'personal_mobile', us->'phones'->>'work_phone', us->'phones'->>'personal_phone')) fone
      from crm.bx_atual('im.messages') m, jsonb_array_elements(coalesce(m.c->'users', '[]'::jsonb)) us
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
  insert into crm.wa_historico_conversa as t (chat_id, nome, canal, telefone, bitrix_deal, bitrix_contato, bitrix_empresa,
                                              negocio_id, empresa_id, iniciada_em)
  select b.chat_id, regexp_replace(coalesce(b.nome, ''), ' - (WhatsApp|Comercial).*$', ''), b.canal,
         coalesce(case when b.ident ~ '^\+?\d{10,13}$' then crm.so_digitos(b.ident) end,
                  (select u.fone from u where u.chat_id = b.chat_id and u.uid = b.uid and length(u.fone) >= 10),
                  (select crm.so_digitos(ct.c->'PHONE'->0->>'VALUE') from crm.bx_atual('crm.contact') ct where ct.chave::bigint = b.contato)),
         b.deal, b.contato, coalesce(b.empresa_bx, n.bitrix_empresa),
         n.id, coalesce(n.empresa_id, (select be.empresa_id from crm.bitrix_empresa be where be.bitrix_id = b.empresa_bx)),
         b.criada
    from base b left join crm.negocio n on n.bitrix_id = b.deal
  on conflict (chat_id) do update set nome = excluded.nome, telefone = coalesce(excluded.telefone, t.telefone),
    bitrix_deal = excluded.bitrix_deal, bitrix_contato = excluded.bitrix_contato, bitrix_empresa = excluded.bitrix_empresa,
    negocio_id = coalesce(excluded.negocio_id, t.negocio_id), empresa_id = coalesce(t.empresa_id, excluded.empresa_id);
  get diagnostics conv = row_count;

  with p as (
    select (m.c->>'chat_id')::bigint chat_id, m.c from crm.bx_atual('im.messages') m
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
     where exists (select 1 from crm.wa_historico_conversa c where c.chat_id = p.chat_id)
     order by (x->>'id')::bigint
  )
  insert into crm.wa_historico_msg as t (id, chat_id, em, quem, autor, texto, arquivos)
  select ms.id, ms.chat_id, ms.em,
         case when ms.autor_id = 0 then 'sistema' when ms.externo then 'cliente' else 'equipe' end,
         case when ms.autor_id = 0 then null
              else coalesce((select bu.nome from crm.bitrix_usuario bu where bu.bitrix_id = ms.autor_id), ms.nome_autor) end,
         case when ms.autor_id <> 0 and not coalesce(ms.externo, false)
              then nullif(regexp_replace(coalesce(crm.bx_msg(ms.texto), ''), '^[^\n]{1,60}:\n', ''), '')
              else crm.bx_msg(ms.texto) end,
         coalesce(ms.arquivos, case when ms.n_arq > 0 then ms.n_arq || ' arquivo(s) não migrado(s)' end)
    from ms
  on conflict (id) do nothing;
  get diagnostics msgs = row_count;

  update crm.wa_historico_conversa c set mensagens = x.n, ultima_em = x.ult, iniciada_em = least(c.iniciada_em, x.pri),
         ultima_texto = left(x.txt, 200)
    from (select m.chat_id, count(*) filter (where m.quem <> 'sistema') n, max(m.em) ult, min(m.em) pri,
                 (array_agg(coalesce(m.texto, m.arquivos) order by m.em desc) filter (where m.quem <> 'sistema'))[1] txt
            from crm.wa_historico_msg m group by m.chat_id) x
   where x.chat_id = c.chat_id;
  return jsonb_build_object('conversas', conv, 'mensagens_novas', msgs,
    'com_telefone', (select count(*) from crm.wa_historico_conversa where telefone is not null),
    'com_empresa', (select count(*) from crm.wa_historico_conversa where empresa_id is not null),
    'com_negocio', (select count(*) from crm.wa_historico_conversa where negocio_id is not null));
end $$;

create or replace function public.painel_wa_historico(p_busca text default null, p_empresa uuid default null, p_telefone text default null,
                                                      p_limite int default 50, p_offset int default 0)
returns table (chat_id bigint, nome text, telefone text, empresa_id uuid, empresa text, negocio_id uuid, negocio_numero bigint,
               iniciada_em timestamptz, ultima_em timestamptz, mensagens int, ultima_texto text, total bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), ''); fim text := right(crm.so_digitos(p_telefone), 8);
begin
  perform crm.exige('gestor','comercial','operacoes','financeiro');
  return query
    select c.chat_id, c.nome, c.telefone, c.empresa_id, coalesce(nullif(e.nome_fantasia, ''), e.razao_social), c.negocio_id, n.numero,
           c.iniciada_em, c.ultima_em, c.mensagens, c.ultima_texto, count(*) over ()
      from crm.wa_historico_conversa c
      left join public.empresa e on e.id = c.empresa_id
      left join crm.negocio n on n.id = c.negocio_id
     where c.mensagens > 0
       and (p_empresa is null or c.empresa_id = p_empresa)
       and (fim is null or length(fim) < 8 or right(c.telefone, 8) = fim)
       and (termo is null or c.nome ilike '%' || termo || '%' or c.telefone like '%' || crm.so_digitos(termo) || '%'
            or e.razao_social ilike '%' || termo || '%' or e.nome_fantasia ilike '%' || termo || '%'
            or exists (select 1 from crm.wa_historico_msg m where m.chat_id = c.chat_id and m.texto ilike '%' || termo || '%'))
     order by c.ultima_em desc nulls last
     limit least(greatest(p_limite, 1), 200) offset greatest(p_offset, 0);
end $$;

create or replace function public.painel_wa_historico_mensagens(p_chat bigint)
returns table (id bigint, em timestamptz, quem text, autor text, texto text, arquivos text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige('gestor','comercial','operacoes','financeiro');
  return query select m.id, m.em, m.quem, m.autor, m.texto, m.arquivos from crm.wa_historico_msg m
                where m.chat_id = p_chat order by m.em, m.id;
end $$;

revoke execute on function crm.bx_msg(text), crm.bitrix_importar_whatsapp() from public, anon, authenticated;
revoke execute on function public.painel_wa_historico(text, uuid, text, int, int), public.painel_wa_historico_mensagens(bigint) from public, anon;
grant execute on function public.painel_wa_historico(text, uuid, text, int, int), public.painel_wa_historico_mensagens(bigint) to authenticated;
