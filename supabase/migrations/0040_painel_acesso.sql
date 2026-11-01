

create schema if not exists crm;
revoke all on schema crm from public, anon, authenticated;

do $$ begin
  create type crm.papel as enum ('admin','gestor','comercial','operacoes','financeiro','leitura');
exception when duplicate_object then null; end $$;

create table if not exists crm.perfil (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  nome           text not null,
  email          text not null,
  papel          crm.papel not null default 'leitura',
  ativo          boolean not null default false,
  telefone       text,
  criado_em      timestamptz not null default now(),
  ultimo_acesso  timestamptz
);
alter table crm.perfil enable row level security;

create table if not exists crm.admin_inicial (email text primary key);
alter table crm.admin_inicial enable row level security;
insert into crm.admin_inicial (email) values ('eduardo.oliveira@exemplo.com.br') on conflict do nothing;

create or replace function crm.tg_novo_usuario() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  begin
    insert into crm.perfil (user_id, nome, email, papel, ativo)
    select new.id,
           coalesce(nullif(trim(new.raw_user_meta_data->>'nome'), ''), split_part(new.email, '@', 1)),
           coalesce(new.email, ''),
           case when a.email is not null then 'admin'::crm.papel else 'leitura'::crm.papel end,
           a.email is not null
      from (select 1) x
      left join crm.admin_inicial a on lower(a.email) = lower(new.email)
    on conflict (user_id) do nothing;
  exception when others then
    raise warning 'crm.tg_novo_usuario: %', sqlerrm;
  end;
  return new;
end $$;
revoke execute on function crm.tg_novo_usuario() from public, anon, authenticated;

drop trigger if exists vitalis_novo_usuario on auth.users;
create trigger vitalis_novo_usuario after insert on auth.users
  for each row execute function crm.tg_novo_usuario();

create or replace function crm.papel_atual() returns crm.papel
language sql stable security definer set search_path = '' as $$
  select p.papel from crm.perfil p where p.user_id = auth.uid() and p.ativo
$$;

create or replace function crm.exige(variadic papeis crm.papel[]) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare v crm.papel;
begin
  if auth.uid() is null then
    raise exception 'Sessão ausente' using errcode = '42501';
  end if;
  select p.papel into v from crm.perfil p where p.user_id = auth.uid() and p.ativo;
  if v is null then
    raise exception 'Seu acesso ainda não foi liberado' using errcode = '42501';
  end if;
  if v <> 'admin' and not (v = any (papeis)) then
    raise exception 'Seu perfil (%) não tem acesso a esta função', v using errcode = '42501';
  end if;
  return auth.uid();
end $$;

create or replace function crm.exige_ativo() returns uuid
language sql stable security definer set search_path = '' as $$
  select crm.exige('admin','gestor','comercial','operacoes','financeiro','leitura')
$$;

revoke execute on function crm.papel_atual(), crm.exige(crm.papel[]), crm.exige_ativo() from public, anon, authenticated;

create or replace function public.painel_meu_perfil() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sessão ausente' using errcode = '42501';
  end if;
  select jsonb_build_object('user_id', p.user_id, 'nome', p.nome, 'email', p.email,
                            'papel', p.papel, 'ativo', p.ativo)
    into r from crm.perfil p where p.user_id = auth.uid();
  return r;
end $$;

create or replace function public.painel_registrar_acesso() returns void
language sql security definer set search_path = '' as $$
  update crm.perfil set ultimo_acesso = now() where user_id = auth.uid()
$$;

create or replace function public.painel_usuarios()
returns table (user_id uuid, nome text, email text, papel text, ativo boolean,
               telefone text, criado_em timestamptz, ultimo_acesso timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform crm.exige('admin');
  return query
    select p.user_id, p.nome, p.email, p.papel::text, p.ativo, p.telefone, p.criado_em, p.ultimo_acesso
      from crm.perfil p
     order by p.ativo, p.nome;
end $$;

create or replace function public.painel_usuario_salvar(
  p_user_id uuid, p_papel text, p_ativo boolean, p_nome text default null, p_telefone text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare eu uuid;
begin
  eu := crm.exige('admin');
  if p_papel not in ('admin','gestor','comercial','operacoes','financeiro','leitura') then
    raise exception 'Papel inválido: %', p_papel;
  end if;
  if p_user_id = eu and (p_ativo is false or p_papel <> 'admin') then
    raise exception 'Você não pode tirar o seu próprio acesso de administrador.';
  end if;
  update crm.perfil
     set papel = p_papel::crm.papel,
         ativo = p_ativo,
         nome = coalesce(nullif(trim(p_nome), ''), nome),
         telefone = coalesce(p_telefone, telefone)
   where user_id = p_user_id;
  if not found then
    raise exception 'Usuário não encontrado.';
  end if;
end $$;

revoke execute on function public.painel_meu_perfil(), public.painel_registrar_acesso(),
  public.painel_usuarios(), public.painel_usuario_salvar(uuid, text, boolean, text, text)
  from public, anon;
grant execute on function public.painel_meu_perfil(), public.painel_registrar_acesso(),
  public.painel_usuarios(), public.painel_usuario_salvar(uuid, text, boolean, text, text)
  to authenticated;

insert into crm.perfil (user_id, nome, email, papel, ativo)
select u.id, coalesce(nullif(trim(u.raw_user_meta_data->>'nome'), ''), split_part(u.email, '@', 1)), coalesce(u.email, ''),
       case when a.email is not null then 'admin'::crm.papel else 'leitura'::crm.papel end, a.email is not null
  from auth.users u left join crm.admin_inicial a on lower(a.email) = lower(u.email)
on conflict (user_id) do update set papel = excluded.papel, ativo = true
 where excluded.ativo;
