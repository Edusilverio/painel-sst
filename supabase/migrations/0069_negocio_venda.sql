

alter table crm.negocio
  add column if not exists qtd_funcionarios integer,
  add column if not exists forma_pagamento  text,
  add column if not exists parcelas         smallint;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'negocio_qtd_funcionarios_ck') then
    alter table crm.negocio add constraint negocio_qtd_funcionarios_ck check (qtd_funcionarios is null or qtd_funcionarios > 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'negocio_forma_pagamento_ck') then
    alter table crm.negocio add constraint negocio_forma_pagamento_ck
      check (forma_pagamento is null or forma_pagamento in ('boleto','pix','transferencia','cartao'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'negocio_parcelas_ck') then
    alter table crm.negocio add constraint negocio_parcelas_ck check (parcelas is null or parcelas between 1 and 60);
  end if;
end $$;

create or replace function crm.bx_pagamento(p_rotulo text, out forma text, out parcelas smallint)
language sql immutable set search_path = '' as $$
  select case when p_rotulo ~* 'boleto' then 'boleto'
              when p_rotulo ~* 'pix' then 'pix'
              when p_rotulo ~* 'transfer' then 'transferencia'
              when p_rotulo ~* 'cart' then 'cartao' end,
         case when p_rotulo ~* '^\s*\d+\s*x' then substring(p_rotulo from '^\s*(\d+)')::smallint
              when p_rotulo ~* 'pix|transfer' then 1::smallint end
$$;

create or replace function crm.bx_funcionarios(p_lista jsonb, p_numero text)
returns integer language sql immutable set search_path = '' as $$
  select coalesce(
    nullif(substring((case when jsonb_typeof(p_lista) = 'array' then p_lista->>0
                           when jsonb_typeof(p_lista) = 'string' then p_lista #>> '{}' end)
                     from '^\s*(\d{1,6})(?!\s*/)')::integer, 0),
    nullif(floor(nullif(p_numero, '')::numeric)::integer, 0))
$$;

create or replace view crm.vw_bitrix_negocio as
 WITH d AS (
         SELECT b.chave::bigint AS id, b.c
           FROM crm.bx_atual('crm.deal'::text) b(chave, c)
        ), ct AS (
         SELECT x.chave::bigint AS deal_id,
            ( SELECT (e_1.value ->> 'CONTACT_ID'::text)::bigint AS int8
                   FROM jsonb_array_elements(x.c) e_1(value)
                  ORDER BY ((e_1.value ->> 'IS_PRIMARY'::text) = 'Y'::text) DESC, ((e_1.value ->> 'SORT'::text)::integer)
                 LIMIT 1) AS contato
           FROM crm.bx_atual('crm.deal.contacts'::text) x(chave, c)
          WHERE jsonb_typeof(x.c) = 'array'::text
        ), co AS (
         SELECT b.chave::bigint AS id, b.c
           FROM crm.bx_atual('crm.contact'::text) b(chave, c)
        ), fx AS (
         SELECT DISTINCT ON ((s.value ->> 'ID'::text)) s.value ->> 'ID'::text AS id,
            s.value ->> 'VALUE'::text AS v
           FROM bitrix.captura,
            LATERAL jsonb_array_elements(captura.conteudo) f_1(value),
            LATERAL jsonb_array_elements(COALESCE(f_1.value -> 'LIST'::text, '[]'::jsonb)) s(value)
          WHERE captura.modulo = 'meta'::text AND captura.chave = 'crm.deal.userfield.list'::text
        ), src AS (
         SELECT s.value ->> 'STATUS_ID'::text AS id, s.value ->> 'NAME'::text AS nome
           FROM bitrix.captura,
            LATERAL jsonb_array_elements(captura.conteudo) s(value)
          WHERE captura.modulo = 'meta'::text AND captura.chave = 'crm.status.list'::text AND (s.value ->> 'ENTITY_ID'::text) = 'SOURCE'::text
        )
 SELECT d.id,
    f.id AS funil_id,
    e.id AS etapa_id,
    e.tipo,
    COALESCE(NULLIF(btrim(d.c ->> 'TITLE'::text), ''::text), 'Negócio Bitrix #'::text || d.id) AS titulo,
    be.empresa_id,
    COALESCE(NULLIF(be.nome, ''::text), NULLIF(btrim((COALESCE(cc.c ->> 'NAME'::text, ''::text) || ' '::text) || COALESCE(cc.c ->> 'LAST_NAME'::text, ''::text)), ''::text), NULLIF(btrim(d.c ->> 'TITLE'::text), ''::text), 'Cliente do Bitrix'::text) AS cliente_nome,
    be.cnpj AS cliente_cnpj,
    NULLIF(btrim((COALESCE(cc.c ->> 'NAME'::text, ''::text) || ' '::text) || COALESCE(cc.c ->> 'LAST_NAME'::text, ''::text)), ''::text) AS contato_nome,
    ((cc.c -> 'PHONE'::text) -> 0) ->> 'VALUE'::text AS contato_telefone,
    lower(((cc.c -> 'EMAIL'::text) -> 0) ->> 'VALUE'::text) AS contato_email,
    ( SELECT p.user_id
           FROM crm.bitrix_usuario bu
             JOIN crm.perfil p ON lower(p.email) = bu.email_painel
          WHERE bu.bitrix_id = ((d.c ->> 'ASSIGNED_BY_ID'::text)::integer)) AS responsavel_id,
    (d.c ->> 'ASSIGNED_BY_ID'::text)::integer AS bitrix_responsavel,
    GREATEST(COALESCE(NULLIF(d.c ->> 'OPPORTUNITY'::text, ''::text)::numeric, 0::numeric), 0::numeric) AS valor,
    NULLIF("left"(d.c ->> 'CLOSEDATE'::text, 10), ''::text)::date AS previsao,
        CASE
            WHEN e.tipo = 'perdido'::crm.tipo_etapa THEN ( SELECT fx.v FROM fx WHERE fx.id = (d.c ->> 'UF_CRM_65774D897D212'::text))
            ELSE NULL::text
        END AS motivo_perda,
    NULLIF(concat_ws('
'::text, crm.bx_txt(d.c ->> 'COMMENTS'::text),
       'Origem no Bitrix: '::text || COALESCE(( SELECT src.nome FROM src WHERE src.id = (d.c ->> 'SOURCE_ID'::text)), d.c ->> 'SOURCE_ID'::text),
       'Tipo de contrato: '::text || (( SELECT string_agg(fx.v, ', '::text)
           FROM jsonb_array_elements_text(
                CASE WHEN jsonb_typeof(d.c -> 'UF_CRM_1712256341158'::text) = 'array'::text THEN d.c -> 'UF_CRM_1712256341158'::text
                     WHEN jsonb_typeof(d.c -> 'UF_CRM_1712256341158'::text) IN ('string','number') THEN jsonb_build_array(d.c -> 'UF_CRM_1712256341158'::text)
                     ELSE '[]'::jsonb END) v(value)
           JOIN fx ON fx.id = v.value)),
       'Vencimento do contrato (Bitrix): '::text || to_char(NULLIF("left"(d.c ->> 'UF_CRM_1701218046'::text, 10), ''::text)::date::timestamp with time zone, 'DD/MM/YYYY'::text),
       'Bitrix #'::text || d.id), ''::text) AS observacao,
    (d.c ->> 'DATE_CREATE'::text)::timestamp with time zone AS criado_em,
    COALESCE((d.c ->> 'MOVED_TIME'::text)::timestamp with time zone, (d.c ->> 'DATE_MODIFY'::text)::timestamp with time zone, (d.c ->> 'DATE_CREATE'::text)::timestamp with time zone) AS entrou_etapa_em,
        CASE
            WHEN (d.c ->> 'CLOSED'::text) = 'Y'::text OR e.tipo <> 'aberta'::crm.tipo_etapa THEN COALESCE((d.c ->> 'MOVED_TIME'::text)::timestamp with time zone, (d.c ->> 'DATE_MODIFY'::text)::timestamp with time zone)
            ELSE NULL::timestamp with time zone
        END AS fechado_em,
    (d.c ->> 'DATE_MODIFY'::text)::timestamp with time zone AS modificado,
    NULLIF(d.c ->> 'COMPANY_ID'::text, '0'::text)::bigint AS bitrix_empresa,
    crm.bx_funcionarios(d.c -> 'UF_CRM_1712255766581', d.c ->> 'UF_CRM_65F2EFB719D39') AS qtd_funcionarios,
    pg.forma AS forma_pagamento,
    COALESCE(pg.parcelas, NULLIF(substring(d.c ->> 'UF_CRM_1709057765' from '(\d{1,2})\s*[xX]'), '')::smallint) AS parcelas
   FROM d
     JOIN crm.bitrix_etapa be2 ON be2.stage_id = (d.c ->> 'STAGE_ID'::text)
     JOIN crm.funil f ON f.slug = be2.funil_slug
     JOIN crm.etapa e ON e.funil_id = f.id AND e.nome = be2.etapa_nome
     LEFT JOIN crm.bitrix_empresa be ON be.bitrix_id = NULLIF(d.c ->> 'COMPANY_ID'::text, '0'::text)::bigint
     LEFT JOIN ct ON ct.deal_id = d.id
     LEFT JOIN co cc ON cc.id = COALESCE(ct.contato, NULLIF(d.c ->> 'CONTACT_ID'::text, '0'::text)::bigint)

     LEFT JOIN LATERAL crm.bx_pagamento(COALESCE(
         (SELECT fx.v FROM fx WHERE fx.id = NULLIF(d.c ->> 'UF_CRM_1710182111', '')),
         (SELECT fx.v FROM fx WHERE fx.id = NULLIF(d.c ->> 'UF_CRM_65F2EFB741D5A', '')))) pg ON true;

create or replace function crm.bitrix_importar_negocios()
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare ins int; upd int;
begin
  insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, cliente_cnpj, contato_nome, contato_telefone,
                           contato_email, responsavel_id, valor, origem, previsao_fechamento, motivo_perda, observacao,
                           entrou_etapa_em, fechado_em, criado_em, atualizado_em, bitrix_id, bitrix_responsavel, bitrix_sincronizado_em, bitrix_empresa,
                           qtd_funcionarios, forma_pagamento, parcelas)
  select funil_id, etapa_id, titulo, empresa_id, cliente_nome, cliente_cnpj, contato_nome, contato_telefone, contato_email,
         responsavel_id, valor, 'bitrix', previsao, motivo_perda, observacao, entrou_etapa_em, fechado_em, criado_em, now(),
         id, bitrix_responsavel, now(), bitrix_empresa, qtd_funcionarios, forma_pagamento, parcelas
    from crm.vw_bitrix_negocio x where not exists (select 1 from crm.negocio n where n.bitrix_id = x.id);
  get diagnostics ins = row_count;
  update crm.negocio n set
    funil_id = x.funil_id, etapa_id = x.etapa_id, titulo = x.titulo, empresa_id = coalesce(n.empresa_id, x.empresa_id),
    cliente_nome = x.cliente_nome, cliente_cnpj = x.cliente_cnpj, contato_nome = x.contato_nome,
    contato_telefone = x.contato_telefone, contato_email = x.contato_email,
    responsavel_id = coalesce(n.responsavel_id, x.responsavel_id), bitrix_responsavel = x.bitrix_responsavel, bitrix_empresa = x.bitrix_empresa,
    valor = x.valor, previsao_fechamento = x.previsao, motivo_perda = x.motivo_perda, observacao = x.observacao,
    entrou_etapa_em = x.entrou_etapa_em, fechado_em = x.fechado_em,
    qtd_funcionarios = x.qtd_funcionarios, forma_pagamento = x.forma_pagamento, parcelas = x.parcelas,
    atualizado_em = now(), bitrix_sincronizado_em = now()
    from crm.vw_bitrix_negocio x
   where n.bitrix_id = x.id and n.atualizado_em <= n.bitrix_sincronizado_em + interval '1 second'
     and (n.etapa_id, n.titulo, n.valor, coalesce(n.observacao, ''), n.qtd_funcionarios, n.forma_pagamento, n.parcelas)
         is distinct from (x.etapa_id, x.titulo, x.valor, coalesce(x.observacao, ''), x.qtd_funcionarios, x.forma_pagamento, x.parcelas);
  get diagnostics upd = row_count;
  return jsonb_build_object('novos', ins, 'atualizados', upd, 'bitrix', (select count(*) from crm.vw_bitrix_negocio));
end $function$;

update crm.negocio n set
  qtd_funcionarios = coalesce(n.qtd_funcionarios, x.qtd_funcionarios),
  forma_pagamento  = coalesce(n.forma_pagamento, x.forma_pagamento),
  parcelas         = coalesce(n.parcelas, x.parcelas),
  observacao       = case when n.atualizado_em <= n.bitrix_sincronizado_em + interval '1 second' then x.observacao else n.observacao end
  from crm.vw_bitrix_negocio x
 where n.bitrix_id = x.id
   and (n.qtd_funcionarios is null and x.qtd_funcionarios is not null
     or n.forma_pagamento is null and x.forma_pagamento is not null
     or n.parcelas is null and x.parcelas is not null
     or n.atualizado_em <= n.bitrix_sincronizado_em + interval '1 second' and coalesce(n.observacao,'') <> coalesce(x.observacao,''));

create or replace function public.painel_crm_negocio_mover(p_id uuid, p_etapa uuid, p_motivo text default null::text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  eu uuid; n crm.negocio; atual crm.etapa; alvo crm.etapa; f crm.funil;
  papel crm.papel; v_fat uuid; v_etapa_fat uuid; v_novo uuid; v_gerados int := 0;
begin
  select * into n from crm.negocio where id = p_id for update;
  if n.id is null then raise exception 'Negócio não encontrado.'; end if;
  eu := crm.exige_operar(n.funil_id);
  select * into atual from crm.etapa where id = n.etapa_id;
  select * into alvo from crm.etapa where id = p_etapa;
  if alvo.id is null or alvo.funil_id <> n.funil_id then
    raise exception 'Etapa inválida para este funil.';
  end if;
  if alvo.id = atual.id then
    return jsonb_build_object('ok', true, 'sem_mudanca', true);
  end if;
  if not alvo.ativo then
    raise exception 'A etapa "%" está desativada.', alvo.nome;
  end if;

  papel := crm.papel_atual();
  if atual.tipo <> 'aberta' and papel not in ('admin','gestor') then
    raise exception 'Negócio fechado (%). Só um gestor pode reabrir.', atual.nome using errcode = '42501';
  end if;
  if alvo.tipo = 'perdido' and nullif(trim(p_motivo), '') is null then
    raise exception 'Informe o motivo da perda.';
  end if;

  update crm.negocio
     set etapa_id = alvo.id,
         entrou_etapa_em = now(),
         ultimo_alerta_em = null,
         fechado_em = case when alvo.tipo = 'aberta' then null else now() end,
         motivo_perda = case when alvo.tipo = 'perdido' then trim(p_motivo)
                             when alvo.tipo = 'aberta' then null else motivo_perda end,
         atualizado_em = now()
   where id = n.id;

  perform crm.registrar(n.id, 'etapa',
    case when alvo.tipo = 'perdido' then 'Motivo: ' || trim(p_motivo) else nullif(trim(p_motivo), '') end,
    atual.id, alvo.id);

  if alvo.tipo = 'ganho' then
    for v_fat in
      select t.funil_destino_id from crm.tunel t join crm.funil d on d.id = t.funil_destino_id and d.ativo
       where t.funil_origem_id = n.funil_id
    loop
      continue when exists (select 1 from crm.negocio d where d.negocio_origem_id = n.id and d.funil_id = v_fat);
      select id into v_etapa_fat from crm.etapa where funil_id = v_fat and ativo and tipo = 'aberta' order by ordem limit 1;
      continue when v_etapa_fat is null;
      select * into f from crm.funil where id = v_fat;
      insert into crm.negocio (funil_id, etapa_id, titulo, empresa_id, cliente_nome, cliente_cnpj,
                               contato_nome, contato_telefone, contato_email, responsavel_id,
                               valor, origem, negocio_origem_id, observacao, criado_por,
                               qtd_funcionarios, forma_pagamento, parcelas)
      values (v_fat, v_etapa_fat, n.titulo, n.empresa_id, n.cliente_nome, n.cliente_cnpj,
              n.contato_nome, n.contato_telefone, n.contato_email,
              case when f.slug = 'pos-venda' then n.responsavel_id end,
              n.valor, 'ganho_comercial', n.id, n.observacao, eu,
              n.qtd_funcionarios, n.forma_pagamento, n.parcelas)
      returning id into v_novo;
      insert into crm.negocio_item (negocio_id, produto_id, descricao, quantidade, preco_unitario)
      select v_novo, i.produto_id, i.descricao, i.quantidade, i.preco_unitario
        from crm.negocio_item i where i.negocio_id = n.id;
      perform crm.registrar(v_novo, 'criado', 'Aberto automaticamente pelo fechamento do negócio #' || n.numero, null, v_etapa_fat);
      perform crm.registrar(n.id, 'nota', 'Card aberto automaticamente em ' || f.nome, null, null);
      insert into crm.notificacao (user_id, negocio_id, tipo, texto)
      select p.user_id, v_novo, 'tunel', 'Novo card em ' || f.nome || ': ' || n.titulo
        from crm.perfil p
       where p.ativo and p.user_id <> eu
         and (p.papel = 'gestor' or p.papel = any (f.papeis));
      v_gerados := v_gerados + 1;
    end loop;
  end if;

  if n.responsavel_id is distinct from eu then
    perform crm.notificar(n.responsavel_id, n.id, 'etapa', n.titulo || ': movido para ' || alvo.nome);
  end if;

  return jsonb_build_object('ok', true, 'cards_gerados', v_gerados);
end $function$;

create or replace function public.painel_crm_negocio_atualizar(p_id uuid, p_dados jsonb)
returns void language plpgsql security definer set search_path = '' as $function$
declare eu uuid; n crm.negocio; v_resp uuid; tem_itens boolean; mudou text[] := '{}';
        v_func integer; v_forma text; v_parc smallint;
begin
  select * into n from crm.negocio where id = p_id for update;
  if n.id is null then raise exception 'Negócio não encontrado.'; end if;
  eu := crm.exige_operar(n.funil_id);

  if p_dados ? 'titulo' and nullif(trim(p_dados->>'titulo'), '') is null then
    raise exception 'O título não pode ficar vazio.';
  end if;
  select exists (select 1 from crm.negocio_item i where i.negocio_id = n.id) into tem_itens;
  if p_dados ? 'valor' and tem_itens then
    raise exception 'O valor é a soma dos itens. Edite os itens do negócio.';
  end if;

  v_resp := case when p_dados ? 'responsavel_id' then nullif(p_dados->>'responsavel_id', '')::uuid else n.responsavel_id end;
  if v_resp is not null and not exists (select 1 from crm.perfil where user_id = v_resp and ativo) then
    raise exception 'Responsável inválido ou inativo.';
  end if;

  if p_dados ? 'qtd_funcionarios' then
    if nullif(trim(p_dados->>'qtd_funcionarios'), '') is not null and trim(p_dados->>'qtd_funcionarios') !~ '^\d{1,6}$' then
      raise exception 'Quantidade de funcionários deve ser um número inteiro.';
    end if;
    v_func := nullif(nullif(trim(p_dados->>'qtd_funcionarios'), '')::integer, 0);
  end if;
  if p_dados ? 'forma_pagamento' then
    v_forma := nullif(trim(p_dados->>'forma_pagamento'), '');
    if v_forma is not null and v_forma not in ('boleto','pix','transferencia','cartao') then
      raise exception 'Forma de pagamento inválida.';
    end if;
  end if;
  if p_dados ? 'parcelas' then
    if nullif(trim(p_dados->>'parcelas'), '') is not null and (trim(p_dados->>'parcelas') !~ '^\d{1,2}$' or (p_dados->>'parcelas')::int not between 1 and 60) then
      raise exception 'Parcelas deve ser um número entre 1 e 60.';
    end if;
    v_parc := nullif(trim(p_dados->>'parcelas'), '')::smallint;
  end if;

  update crm.negocio set
    titulo              = case when p_dados ? 'titulo' then trim(p_dados->>'titulo') else titulo end,
    empresa_id          = case when p_dados ? 'empresa_id' then nullif(p_dados->>'empresa_id', '')::uuid else empresa_id end,
    cliente_nome        = case when p_dados ? 'cliente_nome' then nullif(trim(p_dados->>'cliente_nome'), '') else cliente_nome end,
    cliente_cnpj        = case when p_dados ? 'cliente_cnpj' then nullif(trim(p_dados->>'cliente_cnpj'), '') else cliente_cnpj end,
    contato_nome        = case when p_dados ? 'contato_nome' then nullif(trim(p_dados->>'contato_nome'), '') else contato_nome end,
    contato_telefone    = case when p_dados ? 'contato_telefone' then nullif(trim(p_dados->>'contato_telefone'), '') else contato_telefone end,
    contato_email       = case when p_dados ? 'contato_email' then nullif(trim(p_dados->>'contato_email'), '') else contato_email end,
    responsavel_id      = v_resp,
    valor               = case when p_dados ? 'valor' then greatest(coalesce((p_dados->>'valor')::numeric, 0), 0) else valor end,
    origem              = case when p_dados ? 'origem' then coalesce(nullif(trim(p_dados->>'origem'), ''), 'manual') else origem end,
    previsao_fechamento = case when p_dados ? 'previsao_fechamento' then nullif(p_dados->>'previsao_fechamento', '')::date else previsao_fechamento end,
    observacao          = case when p_dados ? 'observacao' then nullif(trim(p_dados->>'observacao'), '') else observacao end,
    qtd_funcionarios    = case when p_dados ? 'qtd_funcionarios' then v_func else qtd_funcionarios end,
    forma_pagamento     = case when p_dados ? 'forma_pagamento' then v_forma else forma_pagamento end,
    parcelas            = case when p_dados ? 'parcelas' then v_parc else parcelas end,
    atualizado_em       = now()
  where id = n.id;

  if v_resp is distinct from n.responsavel_id then
    perform crm.registrar(n.id, 'responsavel',
      'Responsável: ' || coalesce((select nome from crm.perfil where user_id = v_resp), 'ninguém'));
    perform crm.notificar(v_resp, n.id, 'atribuido', 'Negócio atribuído a você: ' || n.titulo);
  end if;
  select array_agg(k) into mudou from jsonb_object_keys(p_dados) k where k <> 'responsavel_id';
  if mudou is not null then
    perform crm.registrar(n.id, 'edicao', 'Alterado: ' || array_to_string(mudou, ', '));
  end if;
end $function$;

create or replace function public.painel_crm_negocio(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare r jsonb;
begin
  perform crm.exige_ativo();
  select jsonb_build_object(
           'id', n.id, 'numero', n.numero, 'funil_id', n.funil_id, 'etapa_id', n.etapa_id,
           'titulo', n.titulo, 'empresa_id', n.empresa_id,
           'empresa', case when em.id is null then null else jsonb_build_object(
               'id', em.id, 'razao_social', em.razao_social, 'nome_fantasia', em.nome_fantasia,
               'cnpj', em.cnpj, 'cidade', em.cidade, 'uf', em.uf, 'telefone', em.telefone, 'email', em.email) end,
           'cliente_nome', n.cliente_nome, 'cliente_cnpj', n.cliente_cnpj,
           'contato_nome', n.contato_nome, 'contato_telefone', n.contato_telefone, 'contato_email', n.contato_email,
           'responsavel_id', n.responsavel_id, 'responsavel_nome', p.nome,
           'valor', n.valor, 'origem', n.origem, 'previsao_fechamento', n.previsao_fechamento,
           'motivo_perda', n.motivo_perda, 'observacao', n.observacao,
           'qtd_funcionarios', n.qtd_funcionarios, 'forma_pagamento', n.forma_pagamento, 'parcelas', n.parcelas,
           'entrou_etapa_em', n.entrou_etapa_em, 'fechado_em', n.fechado_em, 'criado_em', n.criado_em,
           'pode_operar', crm.pode_operar(n.funil_id),
           'negocio_origem', (select jsonb_build_object('id', o.id, 'numero', o.numero, 'funil', fo.nome,
                                       'observacao', o.observacao, 'qtd_funcionarios', o.qtd_funcionarios,
                                       'forma_pagamento', o.forma_pagamento, 'parcelas', o.parcelas,
                                       'responsavel_nome', po.nome, 'atualizado_em', o.atualizado_em)
                                from crm.negocio o join crm.funil fo on fo.id = o.funil_id
                                left join crm.perfil po on po.user_id = o.responsavel_id
                               where o.id = n.negocio_origem_id),
           'derivados', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'numero', d.numero,
                                          'funil', fd.nome, 'etapa', ed.nome))
                                    from crm.negocio d join crm.funil fd on fd.id = d.funil_id
                                    join crm.etapa ed on ed.id = d.etapa_id
                                   where d.negocio_origem_id = n.id), '[]'::jsonb),
           'itens', coalesce((select jsonb_agg(jsonb_build_object(
                          'id', i.id, 'produto_id', i.produto_id, 'descricao', i.descricao,
                          'quantidade', i.quantidade, 'preco_unitario', i.preco_unitario, 'total', i.total)
                        order by i.criado_em)
                        from crm.negocio_item i where i.negocio_id = n.id), '[]'::jsonb),
           'eventos', coalesce((select jsonb_agg(x order by x.criado_em desc) from (
                          select ev.id, ev.tipo, ev.texto, ev.criado_em, a.nome as autor,
                                 de.nome as de_etapa, pa.nome as para_etapa
                            from crm.evento ev
                            left join crm.perfil a on a.user_id = ev.autor_id
                            left join crm.etapa de on de.id = ev.de_etapa_id
                            left join crm.etapa pa on pa.id = ev.para_etapa_id
                           where ev.negocio_id = n.id
                           order by ev.criado_em desc limit 200) x), '[]'::jsonb))
    into r
    from crm.negocio n
    left join public.empresa em on em.id = n.empresa_id
    left join crm.perfil p on p.user_id = n.responsavel_id
   where n.id = p_id and crm.ve_negocio(n.responsavel_id);
  if r is null then
    raise exception 'Negócio não encontrado.';
  end if;
  return r;
end $function$;

revoke execute on function crm.bx_pagamento(text), crm.bx_funcionarios(jsonb, text) from public, anon, authenticated;
