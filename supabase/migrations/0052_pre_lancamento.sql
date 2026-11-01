

create or replace function sesmo.normalizar_empresas_situacao() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  with s as (
    select c.chave::text chave, nullif(c.conteudo ->> 'situacao', '')::int cod,
           (case c.conteudo ->> 'situacao' when '2' then 'ativo' when '1' then 'inativo' end)::public.situacao_empresa sit
      from sesmo.ultimas('clientes') c
  )
  update public.empresa e
     set sesmo_situacao_codigo = s.cod, situacao = coalesce(s.sit, e.situacao)
    from s
   where s.chave = e.sesmo_id
     and (e.sesmo_situacao_codigo is distinct from s.cod or e.situacao is distinct from coalesce(s.sit, e.situacao));
  get diagnostics n = row_count;
  return jsonb_build_object('empresas_atualizadas', n);
end $$;
revoke execute on function sesmo.normalizar_empresas_situacao() from public, anon, authenticated;

select sesmo.normalizar_empresas_situacao();

do $$
declare t record;
begin
  for t in select c.oid::regclass nome from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r','v','m','p','f')
  loop
    execute format('revoke all on %s from anon, authenticated', t.nome);
  end loop;
  for t in select c.oid::regclass nome from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'S'
  loop
    execute format('revoke all on sequence %s from anon, authenticated', t.nome);
  end loop;
end $$;
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
