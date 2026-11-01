

alter table crm.chat_mensagem
  add column if not exists anexo_path text,
  add column if not exists anexo_tipo text check (anexo_tipo in ('imagem', 'audio', 'arquivo')),
  add column if not exists anexo_nome text,
  add column if not exists anexo_mime text,
  add column if not exists anexo_tamanho integer,
  add column if not exists anexo_duracao numeric,
  add column if not exists texto_auto boolean not null default false;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat', 'chat', false, 15 * 1024 * 1024,
        array['image/png','image/jpeg','image/webp','image/gif','image/heic',
              'audio/webm','audio/ogg','audio/mpeg','audio/mp4','audio/wav','audio/x-m4a',
              'application/pdf',
              'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              'text/plain'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
                               allowed_mime_types = excluded.allowed_mime_types;

create or replace function crm.chat_pode_arquivo(p_nome text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(
           exists (select 1 from crm.perfil p where p.user_id = auth.uid() and p.ativo)
           and split_part(p_nome, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           and crm.chat_acesso(split_part(p_nome, '/', 1)::uuid), false)
$$;
revoke execute on function crm.chat_pode_arquivo(text) from public, anon;
grant execute on function crm.chat_pode_arquivo(text) to authenticated;

create policy "chat_anexo_ler" on storage.objects for select to authenticated
  using (bucket_id = 'chat' and crm.chat_pode_arquivo(name));
create policy "chat_anexo_enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat' and crm.chat_pode_arquivo(name));

create or replace function public.painel_chat_enviar_anexo(
  p_sala uuid, p_path text, p_tipo text, p_nome text, p_mime text, p_tamanho integer,
  p_duracao numeric default null, p_legenda text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare eu uuid; novo bigint; leg text := nullif(btrim(coalesce(p_legenda, '')), ''); rotulo text;
begin
  eu := crm.chat_exige(p_sala);
  if p_tipo not in ('imagem', 'audio', 'arquivo') then raise exception 'Tipo de anexo inválido.'; end if;
  if split_part(coalesce(p_path, ''), '/', 1) <> p_sala::text then raise exception 'Anexo fora da pasta da conversa.'; end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'chat' and o.name = p_path) then
    raise exception 'Arquivo não encontrado. Tente enviar de novo.';
  end if;
  if leg is not null and length(leg) > 4000 then raise exception 'Legenda muito longa.'; end if;
  rotulo := case p_tipo when 'imagem' then '📷 Imagem' when 'audio' then '🎤 Áudio'
                        else '📎 ' || left(coalesce(nullif(btrim(p_nome), ''), 'Arquivo'), 200) end;
  insert into crm.chat_mensagem (sala_id, autor_id, texto, texto_auto, anexo_path, anexo_tipo, anexo_nome, anexo_mime, anexo_tamanho, anexo_duracao)
  values (p_sala, eu, coalesce(leg, rotulo), leg is null, p_path, p_tipo, left(p_nome, 200), left(p_mime, 100), p_tamanho, p_duracao)
  returning id into novo;
  update crm.chat_sala set ultima_em = now() where id = p_sala;
  insert into crm.chat_membro (sala_id, user_id, lida_em) values (p_sala, eu, now())
  on conflict (sala_id, user_id) do update set lida_em = now();
  return novo;
end $$;
revoke execute on function public.painel_chat_enviar_anexo(uuid, text, text, text, text, integer, numeric, text) from public, anon;
grant execute on function public.painel_chat_enviar_anexo(uuid, text, text, text, text, integer, numeric, text) to authenticated;

create or replace function public.painel_chat_mensagens_v2(p_sala uuid, p_antes bigint default null, p_limite int default 60)
returns table (id bigint, autor_id uuid, autor text, texto text, texto_auto boolean, criado_em timestamptz, excluida boolean, minha boolean,
               anexo_path text, anexo_tipo text, anexo_nome text, anexo_mime text, anexo_tamanho integer, anexo_duracao numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare eu uuid;
begin
  eu := crm.chat_exige(p_sala);
  return query
    select x.id, x.autor_id, p.nome::text, case when x.excluida then null else x.texto end, x.texto_auto,
           x.criado_em, x.excluida, x.autor_id = eu,
           case when x.excluida then null else x.anexo_path end, case when x.excluida then null else x.anexo_tipo end,
           case when x.excluida then null else x.anexo_nome end, case when x.excluida then null else x.anexo_mime end,
           case when x.excluida then null else x.anexo_tamanho end, case when x.excluida then null else x.anexo_duracao end
      from (select * from crm.chat_mensagem m where m.sala_id = p_sala and (p_antes is null or m.id < p_antes)
             order by m.id desc limit least(greatest(p_limite, 1), 200)) x
      left join crm.perfil p on p.user_id = x.autor_id
     order by x.id;
end $$;
revoke execute on function public.painel_chat_mensagens_v2(uuid, bigint, int) from public, anon;
grant execute on function public.painel_chat_mensagens_v2(uuid, bigint, int) to authenticated;
