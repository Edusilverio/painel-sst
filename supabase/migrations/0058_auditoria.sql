

create or replace function public.painel_auditoria(
  p_origem text default null,
  p_usuario uuid default null,
  p_de date default null,
  p_ate date default null,
  p_busca text default null,
  p_limite int default 100,
  p_offset int default 0
) returns table (em timestamptz, origem text, usuario_id uuid, usuario text, acao text, entidade text,
                 registro_id uuid, registro text, detalhe jsonb, total bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare termo text := nullif(trim(p_busca), '');
begin
  perform crm.exige('admin');
  return query
    with ed as (
      select e.em, 'cadastro'::text origem, e.usuario_id, e.acao, e.tabela entidade, e.registro_id,
             coalesce(
               case e.tabela
                 when 'empresa' then (select coalesce(nullif(x.nome_fantasia, ''), x.razao_social) from public.empresa x where x.id = e.registro_id)
                 when 'colaborador' then (select x.nome || ' — ' || coalesce(nullif(em.nome_fantasia, ''), em.razao_social)
                                            from public.colaborador x join public.empresa em on em.id = x.empresa_id where x.id = e.registro_id)
                 when 'unidade' then (select x.nome from public.unidade x where x.id = e.registro_id)
                 when 'empresa_contato' then (select coalesce(x.nome, '(contato)') from public.empresa_contato x where x.id = e.registro_id)
                 when 'atendimento' then (select c.nome || ' — ' || to_char(a.data_atendimento, 'DD/MM/YYYY')
                                            from public.atendimento a join public.colaborador c on c.id = a.colaborador_id where a.id = e.registro_id)
               end,
               e.mudancas #>> '{registro,nome}', '(registro removido)') registro,
             e.mudancas detalhe
        from crm.edicao e
       where (p_origem is null or p_origem = 'cadastro')
    ), ev as (
      select v.criado_em em, 'crm'::text, v.autor_id, v.tipo, 'negocio'::text, v.negocio_id,
             '#' || n.numero || ' ' || n.titulo || ' (' || f.nome || ')',
             jsonb_build_object('texto', v.texto, 'de', de.nome, 'para', pa.nome)
        from crm.evento v
        join crm.negocio n on n.id = v.negocio_id
        join crm.funil f on f.id = n.funil_id
        left join crm.etapa de on de.id = v.de_etapa_id
        left join crm.etapa pa on pa.id = v.para_etapa_id
       where (p_origem is null or p_origem = 'crm') and v.autor_id is not null
    ), tudo as (
      select * from ed union all select * from ev
    )
    select t.em, t.origem, t.usuario_id, coalesce(p.nome, u.email)::text, t.acao, t.entidade, t.registro_id, t.registro, t.detalhe,
           count(*) over ()
      from tudo t
      left join crm.perfil p on p.user_id = t.usuario_id
      left join auth.users u on u.id = t.usuario_id
     where (p_usuario is null or t.usuario_id = p_usuario)
       and (p_de is null or t.em >= p_de::timestamp at time zone 'America/Sao_Paulo')
       and (p_ate is null or t.em < (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo')
       and (termo is null or t.registro ilike '%' || termo || '%' or coalesce(p.nome, '') ilike '%' || termo || '%')
     order by t.em desc
     limit least(greatest(p_limite, 1), 500) offset greatest(p_offset, 0);
end $$;

revoke execute on function public.painel_auditoria(text, uuid, date, date, text, int, int) from public, anon;
grant execute on function public.painel_auditoria(text, uuid, date, date, text, int, int) to authenticated;
