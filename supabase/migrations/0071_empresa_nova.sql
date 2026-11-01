

alter table public.empresa add column if not exists cadastrado_por uuid;

create or replace function crm.ve_empresa(p_empresa uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(crm.papel_atual() <> 'comercial', false)
      or exists (select 1 from crm.negocio n where n.empresa_id = p_empresa and n.responsavel_id = auth.uid())
      or exists (select 1 from crm.contrato c where c.empresa_id = p_empresa and c.responsavel_id = auth.uid())
      or exists (select 1 from public.empresa e where e.id = p_empresa and e.cadastrado_por = auth.uid())
$$;

create or replace function public.painel_empresa_criar(p_dados jsonb, p_contato jsonb default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  d jsonb;
  ct jsonb;
  v_cnpj text;
  v_id uuid;
  v_nome text;
  v_ligados int := 0;
begin
  perform crm.exige('gestor', 'comercial', 'operacoes');
  d := crm.limpar_dados(p_dados, array['razao_social','nome_fantasia','cnpj','cnae_principal','grau_risco',
                                       'cep','logradouro','numero','complemento','bairro','cidade','uf','telefone','email']);
  if coalesce(d ->> 'razao_social', '') = '' then raise exception 'Informe a razão social.'; end if;
  v_cnpj := nullif(regexp_replace(coalesce(d ->> 'cnpj', ''), '\D', '', 'g'), '');
  if v_cnpj is not null and length(v_cnpj) not in (11, 14) then raise exception 'CNPJ (ou CPF) com número de dígitos inválido.'; end if;
  if d ->> 'uf' is not null and length(d ->> 'uf') <> 2 then raise exception 'UF deve ter 2 letras.'; end if;
  if d ->> 'grau_risco' is not null and (d ->> 'grau_risco')::int not between 1 and 4 then raise exception 'Grau de risco vai de 1 a 4.'; end if;

  if v_cnpj is not null then
    select e.id, coalesce(e.nome_fantasia, e.razao_social) into v_id, v_nome
      from public.empresa e where app.digits(e.cnpj) = v_cnpj
     order by (e.situacao = 'ativo') desc, e.updated_at desc limit 1;
    if v_id is not null then
      return jsonb_build_object('id', v_id, 'existente', true, 'nome', v_nome, 'visivel', crm.ve_empresa(v_id));
    end if;
    d := jsonb_set(d, '{cnpj}', to_jsonb(v_cnpj));
  end if;

  v_id := crm.criar('empresa', d, jsonb_build_object('origem', 'manual', 'cadastrado_por', auth.uid()));

  ct := crm.limpar_dados(coalesce(p_contato, '{}'::jsonb), array['nome','cargo','email','telefone']);
  if coalesce(ct ->> 'nome', '') <> '' then
    perform crm.criar('empresa_contato', ct, jsonb_build_object('empresa_id', v_id, 'origem', 'manual'));
  end if;

  if v_cnpj is not null then
    update crm.negocio n set empresa_id = v_id, atualizado_em = now()
     where n.empresa_id is null and regexp_replace(coalesce(n.cliente_cnpj, ''), '\D', '', 'g') = v_cnpj
       and (crm.papel_atual() <> 'comercial' or n.responsavel_id = auth.uid());
    get diagnostics v_ligados = row_count;
  end if;

  return jsonb_build_object('id', v_id, 'existente', false, 'nome', coalesce(d ->> 'nome_fantasia', d ->> 'razao_social'),
                            'visivel', true, 'cards_ligados', v_ligados);
end $$;

revoke execute on function public.painel_empresa_criar(jsonb, jsonb) from public, anon;
grant execute on function public.painel_empresa_criar(jsonb, jsonb) to authenticated;
