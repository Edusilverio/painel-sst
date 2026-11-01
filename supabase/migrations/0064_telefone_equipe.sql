

alter table crm.pre_cadastro add column if not exists telefone text;

create or replace function crm.telefone_normalizado(p text) returns text
language sql immutable set search_path = '' as $$
  select case when length(d) in (10, 11) then '55' || d when length(d) between 12 and 13 then d end
    from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') d) x
$$;

create or replace function public.painel_usuario_telefone(p_user uuid, p_telefone text) returns void
language plpgsql security definer set search_path = '' as $$
declare t text := crm.telefone_normalizado(p_telefone);
begin
  if p_user is distinct from auth.uid() then perform crm.exige('admin'); else perform crm.exige_ativo(); end if;
  if nullif(trim(coalesce(p_telefone, '')), '') is not null and t is null then
    raise exception 'Telefone inválido. Use DDD + número, ex.: (11) 99697-1631.';
  end if;
  update crm.perfil set telefone = t where user_id = p_user;
  if not found then raise exception 'Usuário não encontrado.'; end if;
end $$;

create or replace function public.painel_pre_cadastros_equipe()
returns table (email text, nome text, cargo text, papel text, libera_agenda boolean, rodizio_ordem int, usado_em timestamptz,
               cadastrado boolean, telefone text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform crm.exige('admin');
  return query
    select pc.email, pc.nome, pc.cargo, pc.papel::text, pc.libera_agenda, pc.rodizio_ordem, pc.usado_em,
           exists (select 1 from crm.perfil p where lower(p.email) = pc.email), pc.telefone
      from crm.pre_cadastro pc order by pc.usado_em is not null, pc.nome;
end $$;

create or replace function public.painel_pre_cadastro_salvar(p_email text, p_dados jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare e text := lower(trim(p_email)); t text := crm.telefone_normalizado(p_dados->>'telefone');
begin
  perform crm.exige('admin');
  if position('@' in e) < 2 or position('.' in split_part(e, '@', 2)) < 2 or e ~ '\s' then raise exception 'E-mail inválido.'; end if;
  if coalesce(p_dados->>'papel', '') not in ('admin','gestor','comercial','operacoes','financeiro','leitura') then
    raise exception 'Perfil inválido.';
  end if;
  if nullif(trim(p_dados->>'nome'), '') is null then raise exception 'Informe o nome.'; end if;
  if nullif(trim(coalesce(p_dados->>'telefone', '')), '') is not null and t is null then raise exception 'Telefone inválido.'; end if;
  insert into crm.pre_cadastro (email, nome, cargo, papel, libera_agenda, rodizio_ordem, telefone)
  values (e, trim(p_dados->>'nome'), nullif(trim(p_dados->>'cargo'), ''), (p_dados->>'papel')::crm.papel,
          coalesce((p_dados->>'libera_agenda')::boolean, false), nullif(p_dados->>'rodizio_ordem', '')::int, t)
  on conflict (email) do update set nome = excluded.nome, cargo = excluded.cargo, papel = excluded.papel,
    libera_agenda = excluded.libera_agenda, rodizio_ordem = excluded.rodizio_ordem,
    telefone = coalesce(excluded.telefone, crm.pre_cadastro.telefone);

  if t is not null then update crm.perfil set telefone = t where lower(email) = e and telefone is null; end if;
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
  end if;
end $$;

revoke execute on function crm.telefone_normalizado(text), crm.aplicar_pre_cadastro(uuid, text, boolean) from public, anon, authenticated;
revoke execute on function public.painel_usuario_telefone(uuid, text), public.painel_pre_cadastros_equipe(),
  public.painel_pre_cadastro_salvar(text, jsonb) from public, anon;
grant execute on function public.painel_usuario_telefone(uuid, text), public.painel_pre_cadastros_equipe(),
  public.painel_pre_cadastro_salvar(text, jsonb) to authenticated;
