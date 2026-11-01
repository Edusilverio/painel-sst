

create or replace function crm.usuario_atividade(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'negocios',     nullif((select count(*) from crm.negocio n where n.responsavel_id = p_user or n.criado_por = p_user), 0),
    'eventos',      nullif((select count(*) from crm.evento e where e.autor_id = p_user), 0),
    'tarefas',      nullif((select count(*) from crm.tarefa t where t.criado_por = p_user or p_user = any (t.responsaveis)), 0),
    'comentarios',  nullif((select count(*) from crm.tarefa_comentario c where c.autor_id = p_user), 0),
    'chat',         nullif((select count(*) from crm.chat_mensagem m where m.autor_id = p_user), 0),
    'agendamentos', nullif((select count(*) from crm.agendamento a where a.criado_por = p_user), 0),
    'edicoes',      nullif((select count(*) from crm.edicao d where d.usuario_id = p_user), 0),
    'contratos',    nullif((select count(*) from crm.contrato c where c.responsavel_id = p_user), 0)))
$$;
revoke execute on function crm.usuario_atividade(uuid) from public, anon, authenticated;

create or replace function public.painel_usuario_admin_checar(p_user uuid, p_acao text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare eu uuid; p crm.perfil; ativ jsonb;
begin
  eu := crm.exige('admin');
  if p_acao not in ('excluir', 'trocar_email') then raise exception 'Ação inválida.'; end if;
  select * into p from crm.perfil where user_id = p_user;
  if p.user_id is null then raise exception 'Usuário não encontrado.'; end if;
  if p_user = eu then raise exception 'Você não pode fazer isso com a sua própria conta.'; end if;
  ativ := crm.usuario_atividade(p_user);
  return jsonb_build_object('user_id', p.user_id, 'nome', p.nome, 'email', p.email, 'atividade', ativ,
                            'pode_excluir', (ativ - 'chat') = '{}'::jsonb);
end $$;
revoke execute on function public.painel_usuario_admin_checar(uuid, text) from public, anon;
grant execute on function public.painel_usuario_admin_checar(uuid, text) to authenticated;

create or replace function public.integracao_usuario_email(p_user uuid, p_email text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update crm.perfil set email = lower(btrim(p_email)) where user_id = p_user;
end $$;
revoke execute on function public.integracao_usuario_email(uuid, text) from public, anon, authenticated;
grant execute on function public.integracao_usuario_email(uuid, text) to service_role;

do $$ begin
  execute replace(pg_get_functiondef('public.painel_agendamento_salvar(uuid,jsonb)'::regprocedure),
    $x$  eu := crm.exige('gestor','operacoes','comercial');$x$,
    $x$  eu := crm.exige('gestor','operacoes','comercial');

  if v_encaixe and crm.papel_atual()::text = 'comercial'
     and not exists (select 1 from crm.agendamento g where g.id = p_id and g.encaixe) then
    raise exception 'Encaixe (fora das vagas) só o atendimento pode marcar. Escolha outro horário ou peça ao atendimento.';
  end if;$x$);
end $$;
