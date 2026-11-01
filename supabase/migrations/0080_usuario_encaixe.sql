

create or replace function public.painel_usuarios_encaixe()
returns uuid[] language plpgsql stable security definer set search_path = '' as $$
begin
  perform crm.exige('admin');
  return coalesce((select array_agg(user_id) from crm.perfil where agenda_encaixe), '{}');
end $$;
revoke execute on function public.painel_usuarios_encaixe() from public, anon;
grant execute on function public.painel_usuarios_encaixe() to authenticated;

create or replace function public.painel_usuario_encaixe(p_user uuid, p_pode boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform crm.exige('admin');
  update crm.perfil set agenda_encaixe = coalesce(p_pode, false) where user_id = p_user;
  if not found then raise exception 'Usuário não encontrado.'; end if;
end $$;
revoke execute on function public.painel_usuario_encaixe(uuid, boolean) from public, anon;
grant execute on function public.painel_usuario_encaixe(uuid, boolean) to authenticated;
