

alter table crm.negocio add column if not exists etapa_anterior_id uuid references crm.etapa(id) on delete set null;

create or replace function crm.posvenda_card(p_empresa uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select n.id from crm.negocio n
    join crm.funil f on f.id = n.funil_id and f.slug = 'pos-venda'
    join crm.etapa e on e.id = n.etapa_id and e.tipo = 'aberta'
   where n.empresa_id = p_empresa
   order by (e.nome ilike 'contratos%') desc, n.criado_em desc
   limit 1
$$;

create or replace function crm.responsavel_cliente(p_empresa uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select c.responsavel_id from crm.contrato c where c.empresa_id = p_empresa and c.responsavel_id is not null
      order by c.criado_em desc limit 1),
    (select n.responsavel_id from crm.negocio n join crm.funil f on f.id = n.funil_id and f.slug = 'comercial'
      join crm.etapa e on e.id = n.etapa_id and e.tipo = 'ganho'
      where n.empresa_id = p_empresa and n.responsavel_id is not null order by n.fechado_em desc nulls last limit 1))
$$;

create or replace function crm.posvenda_mover(p_card uuid, p_etapa uuid, p_texto text, p_guardar_anterior boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare atual uuid; tipo crm.tipo_etapa;
begin
  select etapa_id into atual from crm.negocio where id = p_card;
  if atual is null or atual = p_etapa then return; end if;
  select e.tipo into tipo from crm.etapa e where e.id = p_etapa;
  update crm.negocio
     set etapa_id = p_etapa, entrou_etapa_em = now(), ultimo_alerta_em = null, atualizado_em = now(),
         etapa_anterior_id = case when p_guardar_anterior then atual else null end,
         fechado_em = case when tipo = 'aberta' then null else now() end
   where id = p_card;
  insert into crm.evento (negocio_id, tipo, texto, de_etapa_id, para_etapa_id) values (p_card, 'etapa', p_texto, atual, p_etapa);
end $$;

create or replace function crm.fin_sincronizar_inadimplencia(p_empresa uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  tol int; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  funil_pv uuid; etapa_inad uuid; etapa_ok uuid; etapa_base uuid; card uuid; volta uuid; atrasado numeric; nome text; origem_card text;
begin
  if p_empresa is null then return; end if;
  select tolerancia_dias into tol from crm.fin_regra where id;
  select f.id into funil_pv from crm.funil f where f.slug = 'pos-venda';
  select e.id into etapa_inad from crm.etapa e where e.funil_id = funil_pv and e.nome ilike 'inadimpl%' and e.ativo limit 1;
  select e.id into etapa_ok from crm.etapa e where e.funil_id = funil_pv and e.tipo = 'ganho' and e.ativo order by e.ordem limit 1;
  select e.id into etapa_base from crm.etapa e where e.funil_id = funil_pv and e.nome ilike 'contratos%' and e.ativo limit 1;
  if etapa_inad is null then return; end if;

  select coalesce(sum(c.valor), 0) into atrasado from crm.cobranca c
   where c.empresa_id = p_empresa and not c.cancelada and c.pago_em is null and c.vencimento < hoje - tol;
  select n.id, n.etapa_anterior_id, n.origem into card, volta, origem_card from crm.negocio n
   where n.empresa_id = p_empresa and n.etapa_id = etapa_inad order by n.criado_em desc limit 1;

  if atrasado > 0 and card is null then
    card := crm.posvenda_card(p_empresa);
    if card is not null then

      perform crm.posvenda_mover(card, etapa_inad,
        'Em atraso no Financeiro: ' || 'R$ ' || replace(to_char(atrasado, 'FM999999990.00'), '.', ',') || ' vencidos há mais de ' || tol || ' dias', true);
    else
      select coalesce(nullif(nome_fantasia, ''), razao_social) into nome from public.empresa where id = p_empresa;
      insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, valor, origem, observacao, responsavel_id)
      values (funil_pv, etapa_inad, 'Inadimplência: ' || nome, p_empresa, atrasado, 'inadimplencia',
              'Aberto pelo Financeiro: cobrança vencida há mais de ' || tol || ' dias.', crm.responsavel_cliente(p_empresa))
      returning id into card;
      insert into crm.evento (negocio_id, tipo, texto) values (card, 'criado', 'Aberto pelo Financeiro (cobrança em atraso)');
    end if;
  elsif atrasado > 0 and card is not null then
    if origem_card = 'inadimplencia' then
      update crm.negocio set valor = atrasado, atualizado_em = now() where id = card and valor <> atrasado;
    end if;
  elsif atrasado = 0 and card is not null then
    if volta is not null then
      perform crm.posvenda_mover(card, volta, 'Débitos quitados no Financeiro — voltou para a etapa anterior', false);
    elsif etapa_ok is not null then
      perform crm.posvenda_mover(card, etapa_ok, 'Débitos quitados no Financeiro', false);
    end if;
  end if;
end $$;

create or replace function crm.alertas_contratos() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; qtd int := 0; hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        etapa_ren uuid; etapa_base uuid; funil_pv uuid; neg uuid; destino uuid; etapa_card uuid;
begin
  select f.id into funil_pv from crm.funil f where f.slug = 'pos-venda';
  select e.id into etapa_ren from crm.etapa e where e.funil_id = funil_pv and e.nome ilike 'renova%' and e.ativo limit 1;
  select e.id into etapa_base from crm.etapa e where e.funil_id = funil_pv and e.nome ilike 'contratos%' and e.ativo limit 1;

  for r in
    select c.id, c.numero, c.renovacao_negocio_id, n.etapa_id
      from crm.contrato c join crm.negocio n on n.id = c.renovacao_negocio_id
     where c.status = 'assinado' and c.fim > hoje + c.aviso_dias and n.etapa_id = etapa_ren
  loop
    if etapa_base is not null then
      perform crm.posvenda_mover(r.renovacao_negocio_id, etapa_base, 'Contrato #' || r.numero || ' renovado', false);
    end if;
    update crm.contrato set renovacao_negocio_id = null, ultimo_alerta_em = null where id = r.id;
    insert into crm.contrato_evento (contrato_id, texto) values (r.id, 'Renovado: card do Pós-venda voltou para Contratos fechados');
  end loop;

  for r in
    select c.*, coalesce(nullif(em.nome_fantasia, ''), em.razao_social, c.cliente_nome) as cliente
      from crm.contrato c left join public.empresa em on em.id = c.empresa_id
     where c.status = 'assinado' and c.fim is not null and c.fim <= hoje + c.aviso_dias
       and (c.ultimo_alerta_em is null or c.ultimo_alerta_em <= hoje - 7)
  loop
    destino := coalesce(r.responsavel_id,
                        (select p.user_id from crm.perfil p where p.ativo and p.papel = 'gestor' order by p.nome limit 1));
    if destino is not null then
      insert into crm.notificacao (user_id, contrato_id, tipo, texto)
      values (destino, r.id, 'renovacao',
              case when r.fim < hoje then 'Contrato vencido: ' else 'Contrato vence em ' || to_char(r.fim, 'DD/MM') || ': ' end || r.cliente);
    end if;
    if r.renovacao_negocio_id is null and etapa_ren is not null then
      neg := crm.posvenda_card(r.empresa_id);
      select etapa_id into etapa_card from crm.negocio where id = neg;
      if neg is not null and etapa_card = etapa_base then
        perform crm.posvenda_mover(neg, etapa_ren, 'Contrato #' || r.numero || ' vence em ' || to_char(r.fim, 'DD/MM/YYYY'), false);
        insert into crm.contrato_evento (contrato_id, texto) values (r.id, 'Aviso de renovação: card do cliente foi para Pós-venda → Renovações');
      else
        insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, responsavel_id, valor, origem, observacao)
        values (funil_pv, etapa_ren, 'Renovação: ' || r.cliente, r.empresa_id, r.cliente_nome,
                coalesce(r.responsavel_id, crm.responsavel_cliente(r.empresa_id)),
                coalesce(r.valor_total, 0), 'renovacao', 'Contrato #' || r.numero || ' vence em ' || to_char(r.fim, 'DD/MM/YYYY'))
        returning id into neg;
        insert into crm.evento (negocio_id, tipo, texto) values (neg, 'criado', 'Aberto pelo aviso de renovação do contrato #' || r.numero);
        insert into crm.contrato_evento (contrato_id, texto) values (r.id, 'Aviso de renovação: card aberto em Pós-venda → Renovações');
      end if;
      update crm.contrato set renovacao_negocio_id = neg where id = r.id;
    end if;
    update crm.contrato set ultimo_alerta_em = hoje where id = r.id;
    qtd := qtd + 1;
  end loop;
  return qtd;
end $$;

revoke execute on function crm.posvenda_card(uuid), crm.responsavel_cliente(uuid), crm.posvenda_mover(uuid, uuid, text, boolean),
  crm.fin_sincronizar_inadimplencia(uuid), crm.alertas_contratos() from public, anon, authenticated;
