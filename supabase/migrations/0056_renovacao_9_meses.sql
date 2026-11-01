

create table if not exists crm.posvenda_regra (
  id     boolean primary key default true check (id),
  meses  int not null default 9 check (meses between 1 and 36)
);
insert into crm.posvenda_regra (id) values (true) on conflict do nothing;
alter table crm.posvenda_regra enable row level security;

do $$
declare fc uuid;
begin
  select id into fc from crm.funil where slug = 'comercial';
  if not exists (select 1 from crm.etapa where funil_id = fc and nome = 'Renovação') then
    update crm.etapa set ordem = ordem + 1 where funil_id = fc and ordem >= 2;
    insert into crm.etapa (funil_id, nome, ordem, tipo, cor, alerta_dias) values (fc, 'Renovação', 2, 'aberta', 'marca', 5);
  end if;
end $$;

update crm.etapa e set ativo = false
  from crm.funil f
 where f.id = e.funil_id and f.slug = 'pos-venda' and e.nome ilike 'renova%'
   and not exists (select 1 from crm.negocio n where n.etapa_id = e.id);

update crm.funil set usa_rodizio = false where slug = 'comercial';

create or replace function crm.abrir_renovacao(p_empresa uuid, p_titulo text, p_cliente_nome text, p_responsavel uuid,
                                              p_valor numeric, p_origem_card uuid, p_motivo text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare fc uuid; et uuid; novo uuid; t text;
begin
  select f.id, e.id into fc, et from crm.funil f join crm.etapa e on e.funil_id = f.id and e.nome = 'Renovação' and e.ativo
   where f.slug = 'comercial';
  if et is null then return null; end if;

  select n.id into novo from crm.negocio n join crm.etapa e on e.id = n.etapa_id and e.tipo = 'aberta'
   where n.funil_id = fc and n.origem = 'renovacao' and p_empresa is not null and n.empresa_id = p_empresa
   order by n.criado_em desc limit 1;
  if novo is not null then
    insert into crm.evento (negocio_id, tipo, texto) values (novo, 'nota', p_motivo);
    return novo;
  end if;
  t := 'Renovação: ' || regexp_replace(coalesce(p_titulo, p_cliente_nome, 'cliente'), '^(Renovação|Inadimplência): ', '');
  insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, responsavel_id, valor, origem,
                           negocio_origem_id, observacao)
  values (fc, et, t, p_empresa, p_cliente_nome, coalesce(p_responsavel, crm.responsavel_cliente(p_empresa)),
          coalesce(p_valor, 0), 'renovacao', p_origem_card, p_motivo)
  returning id into novo;
  if p_origem_card is not null then
    insert into crm.negocio_item (negocio_id, produto_id, descricao, quantidade, preco_unitario)
    select novo, i.produto_id, i.descricao, i.quantidade, i.preco_unitario from crm.negocio_item i where i.negocio_id = p_origem_card;
  end if;
  insert into crm.evento (negocio_id, tipo, texto) values (novo, 'criado', p_motivo);
  insert into crm.notificacao (user_id, negocio_id, tipo, texto)
  select r, novo, 'renovacao', 'Renovação para fazer: ' || t
    from (select coalesce(p_responsavel, crm.responsavel_cliente(p_empresa)) r) x where r is not null;
  return novo;
end $$;

create or replace function crm.posvenda_renovacao() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; qtd int := 0; meses int; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        etapa_base uuid; etapa_ok uuid; neg uuid; num bigint;
begin
  select p.meses into meses from crm.posvenda_regra p where p.id;
  select e.id into etapa_base from crm.etapa e join crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda'
   where e.nome ilike 'contratos%' and e.ativo limit 1;
  select e.id into etapa_ok from crm.etapa e join crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda'
   where e.tipo = 'ganho' and e.ativo order by e.ordem limit 1;
  if etapa_base is null then return 0; end if;
  for r in
    select n.*, coalesce((select max(c.inicio) from crm.contrato c where c.empresa_id = n.empresa_id and c.status = 'assinado'),
                         n.criado_em::date) base
      from crm.negocio n where n.etapa_id = etapa_base
  loop
    continue when r.base > hoje - make_interval(months => meses);
    neg := crm.abrir_renovacao(r.empresa_id, r.titulo, r.cliente_nome, r.responsavel_id, r.valor, r.id,
             'Cliente completou ' || meses || ' meses no Pós-venda (desde ' || to_char(r.base, 'DD/MM/YYYY') || ')');
    continue when neg is null;
    select numero into num from crm.negocio where id = neg;
    if etapa_ok is not null then
      perform crm.posvenda_mover(r.id, etapa_ok, 'Completou ' || meses || ' meses: enviado ao Comercial › Renovação (#' || num || ')', false);
    end if;
    qtd := qtd + 1;
  end loop;
  return qtd;
end $$;

create or replace function crm.alertas_contratos() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; qtd int := 0; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        etapa_base uuid; etapa_ok uuid; destino uuid; neg uuid; pv uuid;
begin
  select e.id into etapa_base from crm.etapa e join crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda'
   where e.nome ilike 'contratos%' and e.ativo limit 1;
  select e.id into etapa_ok from crm.etapa e join crm.funil f on f.id = e.funil_id and f.slug = 'pos-venda'
   where e.tipo = 'ganho' and e.ativo order by e.ordem limit 1;

  update crm.contrato c set renovacao_negocio_id = null
    from crm.negocio n join crm.etapa e on e.id = n.etapa_id
   where n.id = c.renovacao_negocio_id and e.tipo <> 'aberta';

  for r in
    select c.*, coalesce(nullif(em.nome_fantasia, ''), em.razao_social, c.cliente_nome) as cliente
      from crm.contrato c left join public.empresa em on em.id = c.empresa_id
     where c.status = 'assinado' and c.fim is not null and c.fim <= hoje + c.aviso_dias
       and (c.ultimo_alerta_em is null or c.ultimo_alerta_em <= hoje - 7)
  loop
    destino := coalesce(r.responsavel_id, crm.responsavel_cliente(r.empresa_id),
                        (select p.user_id from crm.perfil p where p.ativo and p.papel = 'gestor' order by p.nome limit 1));
    if destino is not null then
      insert into crm.notificacao (user_id, contrato_id, tipo, texto)
      values (destino, r.id, 'renovacao',
              case when r.fim < hoje then 'Contrato vencido: ' else 'Contrato vence em ' || to_char(r.fim, 'DD/MM') || ': ' end || r.cliente);
    end if;
    if r.renovacao_negocio_id is null then
      pv := null;
      if r.empresa_id is not null then
        select n.id into pv from crm.negocio n where n.empresa_id = r.empresa_id and n.etapa_id = etapa_base order by n.criado_em desc limit 1;
      end if;
      neg := crm.abrir_renovacao(r.empresa_id, coalesce((select titulo from crm.negocio where id = pv), r.cliente), r.cliente_nome,
               r.responsavel_id, coalesce(r.valor_total, 0), pv,
               'Contrato #' || r.numero || ' vence em ' || to_char(r.fim, 'DD/MM/YYYY'));
      if neg is not null then
        update crm.contrato set renovacao_negocio_id = neg where id = r.id;
        insert into crm.contrato_evento (contrato_id, texto) values (r.id, 'Aviso de renovação: card em Comercial › Renovação');
        if pv is not null and etapa_ok is not null then
          perform crm.posvenda_mover(pv, etapa_ok, 'Contrato #' || r.numero || ' perto do fim: enviado ao Comercial › Renovação', false);
        end if;
      end if;
    end if;
    update crm.contrato set ultimo_alerta_em = hoje where id = r.id;
    qtd := qtd + 1;
  end loop;
  return qtd;
end $$;

revoke execute on function crm.abrir_renovacao(uuid, text, text, uuid, numeric, uuid, text), crm.posvenda_renovacao(),
  crm.alertas_contratos() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('crm-posvenda-renovacao', '12 11 * * *', 'select crm.posvenda_renovacao()');
  end if;
end $$;

create or replace function public.painel_crm_negocio_criar(
  p_funil uuid,
  p_titulo text,
  p_empresa_id uuid default null,
  p_cliente_nome text default null,
  p_cliente_cnpj text default null,
  p_contato_nome text default null,
  p_contato_telefone text default null,
  p_contato_email text default null,
  p_responsavel uuid default null,
  p_valor numeric default 0,
  p_origem text default 'manual',
  p_observacao text default null,
  p_previsao date default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare eu uuid; v_etapa uuid; v_resp uuid := p_responsavel; v_id uuid; v_rodizio boolean;
begin
  eu := crm.exige_operar(p_funil);
  if nullif(trim(p_titulo), '') is null then
    raise exception 'Informe um título para o negócio.';
  end if;
  if p_empresa_id is null and nullif(trim(p_cliente_nome), '') is null then
    raise exception 'Escolha um cliente da base ou informe o nome do cliente.';
  end if;

  select e.id into v_etapa from crm.etapa e
   where e.funil_id = p_funil and e.ativo and e.tipo = 'aberta' order by e.ordem limit 1;
  if v_etapa is null then
    raise exception 'Este funil não tem etapa aberta configurada.';
  end if;

  select f.usa_rodizio into v_rodizio from crm.funil f where f.id = p_funil;
  if v_resp is null and v_rodizio and coalesce(p_origem, '') = 'landing' then
    v_resp := crm.proximo_rodizio(p_funil);
  end if;
  if v_resp is null and crm.papel_atual() = 'comercial' then
    v_resp := eu;
  end if;

  insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, cliente_cnpj,
                           contato_nome, contato_telefone, contato_email, responsavel_id,
                           valor, origem, observacao, previsao_fechamento, criado_por)
  values (p_funil, v_etapa, trim(p_titulo), p_empresa_id, nullif(trim(p_cliente_nome), ''),
          nullif(trim(p_cliente_cnpj), ''), nullif(trim(p_contato_nome), ''),
          nullif(trim(p_contato_telefone), ''), nullif(trim(p_contato_email), ''), v_resp,
          greatest(coalesce(p_valor, 0), 0), coalesce(nullif(trim(p_origem), ''), 'manual'),
          nullif(trim(p_observacao), ''), p_previsao, eu)
  returning id into v_id;

  perform crm.registrar(v_id, 'criado',
    case when p_responsavel is null and v_resp is not null and v_resp <> eu then 'Criado e distribuído pelo rodízio' else 'Negócio criado' end,
    null, v_etapa);
  perform crm.notificar(v_resp, v_id, 'atribuido', 'Novo negócio para você: ' || trim(p_titulo));
  return v_id;
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
