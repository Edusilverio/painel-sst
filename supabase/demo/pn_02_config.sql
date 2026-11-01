-- Painel SST — configuração inicial (funis, etapas, catálogo, modelos). Anonimizada.



SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('09:10:00', 0, '2026-10-26 22:40:06.741184+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('09:30:00', 0, '2026-10-26 22:40:06.741184+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('10:10:00', 0, '2026-10-26 22:40:06.741184+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('08:30:00', 4, '2026-10-26 22:40:06.742163+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('08:50:00', 3, '2026-10-26 22:40:06.742163+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('09:00:00', 4, '2026-10-26 22:40:06.742163+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('09:20:00', 4, '2026-10-26 22:40:06.742163+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('09:40:00', 4, '2026-10-26 22:40:06.742163+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('09:50:00', 4, '2026-10-26 22:40:06.742163+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('10:00:00', 4, '2026-10-26 22:40:06.742163+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('10:20:00', 3, '2026-10-26 22:40:06.742163+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('10:30:00', 4, '2026-10-26 22:40:06.742163+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('10:50:00', 4, '2026-10-26 22:40:06.742163+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('11:10:00', 3, '2026-10-26 22:40:06.742163+00', NULL);
INSERT INTO pn_crm.agenda_grade (horario, vagas, atualizado_em, atualizado_por) VALUES ('11:30:00', 4, '2026-10-26 22:40:06.742163+00', NULL);

INSERT INTO pn_crm.agenda_regra (id, limite_empresa_dia, bloquear_inadimplente, vagas_padrao, hora_inicio_padrao, hora_fim_padrao, atualizado_em, atualizado_por) VALUES (true, 2, true, 40, '08:30:00', '11:30:00', '2026-10-26 22:40:06.742567+00', NULL);

INSERT INTO pn_crm.atestado_regra (id, limite, prazo_dias, ativo) VALUES (true, 5, 3, true);

INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('NEW', 'comercial', 'Novo negócio');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('UC_ENTV2Y', 'comercial', 'Contato feito');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('UC_ZR60DV', 'comercial', 'Reunião agendada');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('UC_CQ8N2X', 'comercial', 'Follow-up');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('UC_YDWWOT', 'comercial', 'Proposta');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('UC_FGILL0', 'comercial', 'Envio de contrato');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('WON', 'comercial', 'Negócio fechado');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('LOSE', 'comercial', 'Oportunidade perdida');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C4:NEW', 'faturamento', 'Não tocado');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C4:PREPARATION', 'faturamento', 'Em execução');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C4:WON', 'faturamento', 'Concluído');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C4:LOSE', 'faturamento', 'Não concluído');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C6:NEW', 'vistoria', 'Não tocado');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C6:PREPARATION', 'vistoria', 'Em execução');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C6:WON', 'vistoria', 'Concluído');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C6:LOSE', 'vistoria', 'Não concluído');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C8:NEW', 'laudos', 'Não tocado');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C8:PREPARATION', 'laudos', 'Em execução');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C8:WON', 'laudos', 'Concluído');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C8:LOSE', 'laudos', 'Não concluído');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C10:NEW', 'pos-venda', 'Contratos fechados');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C10:PREPAYMENT_INVOIC', 'pos-venda', 'Inadimplentes');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C10:FINAL_INVOICE', 'comercial', 'Renovação');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C10:WON', 'pos-venda', 'Concluído');
INSERT INTO pn_crm.bitrix_etapa (stage_id, funil_slug, etapa_nome) VALUES ('C10:LOSE', 'pos-venda', 'Sem entrega');

INSERT INTO pn_crm.chat_sala (id, tipo, nome, descricao, criado_por, criado_em, ultima_em, arquivada) VALUES ('e36de269-51a1-4511-b818-63a46c3511ce', 'geral', 'Geral', 'Toda a equipe Vitalis', NULL, '2026-10-26 22:40:05.820726+00', '2026-10-26 22:40:05.820726+00', false);

INSERT INTO pn_crm.documento_regra (id, aviso_dias) VALUES (true, 60);

INSERT INTO pn_crm.funil (id, slug, nome, descricao, ordem, ativo, usa_rodizio, papeis, criado_em) VALUES ('55dcf70b-e61d-4a04-9925-b5caffeb79ae', 'faturamento', 'Faturamento', 'Faturar o que foi vendido', 2, true, false, '{financeiro}', '2026-10-26 22:40:05.12966+00');
INSERT INTO pn_crm.funil (id, slug, nome, descricao, ordem, ativo, usa_rodizio, papeis, criado_em) VALUES ('9edd19ff-06f1-417e-885e-7d8151e6f08d', 'vistoria', 'Vistoria', 'Visitas técnicas aos clientes', 3, true, false, '{operacoes}', '2026-10-26 22:40:05.12966+00');
INSERT INTO pn_crm.funil (id, slug, nome, descricao, ordem, ativo, usa_rodizio, papeis, criado_em) VALUES ('dd51875f-49ab-4e60-8a63-335a54111c02', 'laudos', 'Laudos', 'Elaboração e entrega de laudos', 4, true, false, '{operacoes}', '2026-10-26 22:40:05.12966+00');
INSERT INTO pn_crm.funil (id, slug, nome, descricao, ordem, ativo, usa_rodizio, papeis, criado_em) VALUES ('2e865f7d-1526-44ab-949f-ddf4f1e9d0cc', 'pos-venda', 'Pós-venda', 'Contratos ativos, inadimplência e renovação', 5, true, false, '{comercial,financeiro}', '2026-10-26 22:40:05.12966+00');
INSERT INTO pn_crm.funil (id, slug, nome, descricao, ordem, ativo, usa_rodizio, papeis, criado_em) VALUES ('42e9e0db-5508-46dc-8107-3ea0e79ff44b', 'comercial', 'Comercial', 'Venda de novos serviços e contratos', 1, true, false, '{comercial}', '2026-10-26 22:40:05.12966+00');

INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('2ac2d400-74e6-42c4-9b02-d1bae23cbfc3', '42e9e0db-5508-46dc-8107-3ea0e79ff44b', 'Novo negócio', 1, 'aberta', 'destructive', 3, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('1692ee8d-c0bb-40be-849e-c221812e10f6', '55dcf70b-e61d-4a04-9925-b5caffeb79ae', 'Não concluído', 4, 'perdido', 'destructive', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('6b50e4bf-ac1f-4afc-981a-72fb06fb27ab', '55dcf70b-e61d-4a04-9925-b5caffeb79ae', 'Concluído', 3, 'ganho', 'success', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('7020ce39-7b70-46da-bbae-feb9f855c49c', '55dcf70b-e61d-4a04-9925-b5caffeb79ae', 'Em execução', 2, 'aberta', 'warning', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('662b2f8e-1818-4d7c-ab81-24c3a444561e', '55dcf70b-e61d-4a04-9925-b5caffeb79ae', 'Não tocado', 1, 'aberta', 'destructive', 2, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('fbd9e19f-96e1-4c96-a9d5-e1ce099213df', '9edd19ff-06f1-417e-885e-7d8151e6f08d', 'Não concluído', 4, 'perdido', 'destructive', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('368e6477-c893-42aa-a1de-eb93a7fbae32', '9edd19ff-06f1-417e-885e-7d8151e6f08d', 'Concluído', 3, 'ganho', 'success', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('03e2c606-ed09-4751-99a3-0dc0404ff149', '9edd19ff-06f1-417e-885e-7d8151e6f08d', 'Em execução', 2, 'aberta', 'warning', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('65fe89e4-b203-4e0a-8cb4-79a6f9f714c5', '9edd19ff-06f1-417e-885e-7d8151e6f08d', 'Não tocado', 1, 'aberta', 'destructive', 3, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('190f9ca1-d17d-42ef-ae72-b200518134c4', 'dd51875f-49ab-4e60-8a63-335a54111c02', 'Não concluído', 4, 'perdido', 'destructive', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('6e2351c9-b84a-4c4c-a30b-a8ccaddf0e68', 'dd51875f-49ab-4e60-8a63-335a54111c02', 'Concluído', 3, 'ganho', 'success', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('c40cd875-9612-415e-9456-18c2d53421ba', 'dd51875f-49ab-4e60-8a63-335a54111c02', 'Em execução', 2, 'aberta', 'warning', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('aec4bde2-68b8-4f7a-8b91-7bc0ae53537a', 'dd51875f-49ab-4e60-8a63-335a54111c02', 'Não tocado', 1, 'aberta', 'destructive', 3, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('f81f1ac9-0cac-4e6d-8a4f-9fb7fac4e730', '2e865f7d-1526-44ab-949f-ddf4f1e9d0cc', 'Sem entrega', 5, 'perdido', 'destructive', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('f66f290d-a18d-480c-ace9-b010a4261e3e', '2e865f7d-1526-44ab-949f-ddf4f1e9d0cc', 'Concluído', 4, 'ganho', 'success', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('a5ca4d0f-effb-4984-90a4-ee62e98ee851', '2e865f7d-1526-44ab-949f-ddf4f1e9d0cc', 'Inadimplentes', 2, 'aberta', 'destructive', 3, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('85c46dd0-b945-4708-9e3c-787725630803', '2e865f7d-1526-44ab-949f-ddf4f1e9d0cc', 'Contratos fechados', 1, 'aberta', 'info', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('6daed3f8-8d75-4459-b497-77961ff10c75', '42e9e0db-5508-46dc-8107-3ea0e79ff44b', 'Contato feito', 3, 'aberta', 'warning', 5, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('f630c72b-3ba0-4b89-8664-b4ddfcbfd83f', '42e9e0db-5508-46dc-8107-3ea0e79ff44b', 'Reunião agendada', 4, 'aberta', 'primary', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('0978b1a6-9fe7-47ef-8101-4f905ac7d853', '42e9e0db-5508-46dc-8107-3ea0e79ff44b', 'Follow-up', 5, 'aberta', 'info', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('7a307d3d-a2ac-4494-a549-02139c85a6f2', '42e9e0db-5508-46dc-8107-3ea0e79ff44b', 'Proposta', 6, 'aberta', 'marca', 3, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('72fd2175-e495-4694-8c7a-6091dc38afd0', '42e9e0db-5508-46dc-8107-3ea0e79ff44b', 'Envio de contrato', 7, 'aberta', 'success', 3, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('c7ddb8a9-01ff-4dd4-91ab-a0b16ef6ac96', '42e9e0db-5508-46dc-8107-3ea0e79ff44b', 'Negócio fechado', 8, 'ganho', 'success', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('d6cf48d2-4fb5-4827-b783-8d6fcbc54590', '42e9e0db-5508-46dc-8107-3ea0e79ff44b', 'Oportunidade perdida', 9, 'perdido', 'destructive', NULL, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('a5781e11-52ef-4f63-8a2c-e36943b45ede', '42e9e0db-5508-46dc-8107-3ea0e79ff44b', 'Renovação', 2, 'aberta', 'marca', 5, true);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('41a39783-aa16-41b7-bad9-704941535be3', '2e865f7d-1526-44ab-949f-ddf4f1e9d0cc', 'Renovações', 3, 'aberta', 'marca', 3, false);
INSERT INTO pn_crm.etapa (id, funil_id, nome, ordem, tipo, cor, alerta_dias, ativo) VALUES ('33d0e6a9-0cd2-43fc-aa3e-1bd617f1c579', '2e865f7d-1526-44ab-949f-ddf4f1e9d0cc', 'Agendar consulta', 3, 'aberta', 'warning', 3, true);

INSERT INTO pn_crm.fin_regra (id, tolerancia_dias, atualizado_em) VALUES (true, 10, '2026-10-26 22:40:05.430112+00');

INSERT INTO pn_crm.posvenda_regra (id, meses, max_por_execucao) VALUES (true, 9, 30);

INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('40a7184e-9a54-4d59-bc84-d705893035d1', 'Exames clínicos + laudo PCMSO', 'Por colaborador', 'Medicina', NULL, 'un', false, true, '2026-10-26 22:40:05.132824+00', NULL, NULL);
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('9c7c95a9-d878-4d0f-9cc2-776b228b1b8a', 'Treinamentos e palestras', NULL, 'Treinamento', NULL, 'un', false, true, '2026-10-26 22:40:05.132824+00', NULL, NULL);
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('445a6f70-1284-4827-83ad-14de45de9b9a', 'Implantação', NULL, 'Consultoria', NULL, 'un', false, true, '2026-10-26 22:40:05.132824+00', NULL, NULL);
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('f9e44665-e55f-4c6e-84ce-9e97561d191a', 'Vistoria técnica', NULL, 'Engenharia', NULL, 'un', false, true, '2026-10-26 22:40:05.132824+00', NULL, NULL);
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('adf79226-d9f1-4f6b-8d3c-c3fb40a45df8', 'Plano mensal', 'Contrato fixo mensal', 'Contrato', NULL, 'un', true, true, '2026-10-26 22:40:05.132824+00', NULL, NULL);
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('2b3f548a-07ed-494e-9652-7245ec0e5239', 'PGR — Programa de Gerenciamento de Riscos (NR-1)', 'NR-01. Validade de 2 anos; renovação automática quando contratada.', 'B · Documentos e laudos', 420.00, 'laudo', false, true, '2026-10-26 22:40:05.132824+00', 'pgr', 'Parcelado em 12 meses');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('e798e3dd-7b3f-4930-ab6e-b4db6b7cbb0c', 'PCMSO — Programa de Controle Médico', 'NR-7. Elaboração, implantação e manutenção.', 'A · Mensalidade por vida ativa', 560.00, 'laudo', false, true, '2026-10-26 22:40:05.132824+00', 'pcmso', 'Parcelado em 12 meses');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('c85586ea-d6f7-4515-a57b-b9aa27a1ab15', 'LTCAT', 'Laudo Técnico das Condições Ambientais do Trabalho.', 'B · Documentos e laudos', 420.00, 'laudo', false, true, '2026-10-26 22:40:05.132824+00', 'ltcat', 'Parcelado em 12 meses');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('df72bc3c-f045-41cc-86f3-c05446e8ca63', 'Mensageria eSocial (SST)', 'S-2220 e S-2240. Inclui gestão da procuração no eCAC.', 'C · Mensageria eSocial', 400.00, 'un', false, true, '2026-10-26 22:40:05.132824+00', 'esocial', 'Parcelas: 05');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('6e8e05c3-0c24-459e-9c92-f4d9a8580d48', 'Exame ocupacional (ASO)', 'Admissional, periódico, retorno ao trabalho, mudança de função e demissional.', 'A · Mensalidade por vida ativa', 50.00, 'exame', false, true, '2026-10-26 22:40:05.614099+00', 'aso', 'Por exame');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('2879c56b-9547-4520-b100-cef4ea80d2e7', 'Mapeamento psicossocial (NR-01)', NULL, 'B · Documentos e laudos', NULL, 'emissão', false, true, '2026-10-26 22:40:05.614099+00', 'psicossocial', 'Parcelas');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('c463288f-c051-48a5-8f97-1ed9c776db55', 'PPP — Perfil Profissiográfico Previdenciário', NULL, 'B · Documentos e laudos', NULL, 'emissão', false, true, '2026-10-26 22:40:05.614099+00', 'ppp', 'Por emissão');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('f5be7727-e6bb-4998-b513-aa7b7c69d9f0', 'Laudo de insalubridade', NULL, 'B · Documentos e laudos', NULL, 'laudo', false, true, '2026-10-26 22:40:05.614099+00', 'insalubridade', 'Parcelas');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('7a5e2d18-4f50-4a14-8ddb-a7ab3edc1cf6', 'Laudo de periculosidade', NULL, 'B · Documentos e laudos', NULL, 'laudo', false, true, '2026-10-26 22:40:05.614099+00', 'periculosidade', 'Parcelas');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('386e1942-b067-463c-929d-560d0348ff09', 'Implantação e gestão de CIPA (NR-05)', NULL, 'D · Treinamentos e outros', NULL, 'evento', false, true, '2026-10-26 22:40:05.614099+00', 'cipa', 'Por evento');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('950865a7-3497-43c7-adb0-64cf0c0c206d', 'Treinamento de brigada de incêndio', NULL, 'D · Treinamentos e outros', NULL, 'evento', false, true, '2026-10-26 22:40:05.614099+00', 'brigada', 'Por evento');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('3edce0a7-e69c-4433-a91e-3b4bcb483aa7', 'Treinamento de primeiros socorros', NULL, 'D · Treinamentos e outros', NULL, 'evento', false, true, '2026-10-26 22:40:05.614099+00', 'primeiros_socorros', 'Por evento');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('960b45f7-eef1-4cb5-991a-4813b2a755ab', 'Treinamentos NR-10, NR-35 e outras NRs', 'Especificar na proposta comercial.', 'D · Treinamentos e outros', NULL, 'evento', false, true, '2026-10-26 22:40:05.614099+00', 'nrs', 'Por evento');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('5c1f515b-a879-4210-ada5-0043d262977c', 'Perícia judicial em medicina do trabalho', NULL, 'D · Treinamentos e outros', NULL, 'perícia', false, true, '2026-10-26 22:40:05.614099+00', 'pericia', 'Conforme proposta');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('0133fd43-2dcb-44b9-b822-65d4ea177331', 'Exame admissional/demissional avulso', 'Fora da mensalidade.', 'E · Avulsos e sob demanda', NULL, 'exame', false, true, '2026-10-26 22:40:05.614099+00', 'avulso', 'Por solicitação');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('2fb55762-07fb-4ada-b755-419d553602c9', 'Atualização de laudo por alteração de atividade ou função', NULL, 'E · Avulsos e sob demanda', NULL, 'evento', false, true, '2026-10-26 22:40:05.614099+00', 'atualizacao_laudo', 'Por evento');
INSERT INTO pn_crm.produto (id, nome, descricao, categoria, preco, unidade, recorrente, ativo, criado_em, codigo, cobranca_padrao) VALUES ('f8f0ad9d-56db-40f8-b156-cdbf692e3fc8', 'Custódia de prontuários', 'Cobrada 60 dias após o fim do contrato, se o cliente não indicar quem recebe os prontuários.', 'E · Avulsos e sob demanda', 150.00, 'mês', true, true, '2026-10-26 22:40:05.614099+00', 'custodia', 'Mensal');

INSERT INTO pn_crm.quadro (id, nome, descricao, ordem, arquivado, criado_por, criado_em) VALUES ('6768ae5c-19bf-4dd2-b525-72a3e5e60331', 'Fluxo de Trabalho', 'Tarefas da equipe Vitalis', 1, false, NULL, '2026-10-26 22:40:05.326829+00');
INSERT INTO pn_crm.quadro (id, nome, descricao, ordem, arquivado, criado_por, criado_em) VALUES ('f806d28b-88b2-47fa-af73-a6f5e4f15535', 'Atestados', 'Tarefas abertas pelo alerta de atestados (5 no mês por empresa).', 10, false, NULL, '2026-10-26 22:40:06.043678+00');

INSERT INTO pn_crm.tunel (funil_origem_id, funil_destino_id) VALUES ('42e9e0db-5508-46dc-8107-3ea0e79ff44b', '55dcf70b-e61d-4a04-9925-b5caffeb79ae');
INSERT INTO pn_crm.tunel (funil_origem_id, funil_destino_id) VALUES ('42e9e0db-5508-46dc-8107-3ea0e79ff44b', '2e865f7d-1526-44ab-949f-ddf4f1e9d0cc');
INSERT INTO pn_crm.tunel (funil_origem_id, funil_destino_id) VALUES ('42e9e0db-5508-46dc-8107-3ea0e79ff44b', '9edd19ff-06f1-417e-885e-7d8151e6f08d');
INSERT INTO pn_crm.tunel (funil_origem_id, funil_destino_id) VALUES ('9edd19ff-06f1-417e-885e-7d8151e6f08d', 'dd51875f-49ab-4e60-8a63-335a54111c02');

INSERT INTO pn_crm.wa_config (id, inbox_url, criar_negocio, funil_id, token_hash, token_gerado_em, ultimo_recebimento) VALUES (true, 'https://painel.exemplo.com.br/inbox', false, '42e9e0db-5508-46dc-8107-3ea0e79ff44b', NULL, NULL, NULL);

INSERT INTO pn_crm.wa_modelo (id, titulo, categoria, texto, ativo, ordem, atualizado_em) VALUES ('dc8f7858-8620-4c04-aadd-24512b9e4ab1', 'Primeiro contato', 'comercial', 'Olá, {nome}! Aqui é {atendente}, da Vitalis Medicina e Engenharia do Trabalho. Recebemos seu contato e quero entender melhor o que a {empresa} precisa. Podemos conversar agora?', true, 1, '2026-10-26 22:40:05.535956+00');
INSERT INTO pn_crm.wa_modelo (id, titulo, categoria, texto, ativo, ordem, atualizado_em) VALUES ('26f05bf1-bb25-4fc9-9a00-8cb309d1a9ae', 'Envio de proposta', 'comercial', '{nome}, conforme conversamos, segue a proposta da Vitalis para a {empresa}. Fico à disposição para qualquer dúvida.', true, 2, '2026-10-26 22:40:05.535956+00');
INSERT INTO pn_crm.wa_modelo (id, titulo, categoria, texto, ativo, ordem, atualizado_em) VALUES ('3eb10c30-4ba7-4db6-bb82-89599f118eb3', 'Confirmação de exame', 'agendamento', 'Olá, {nome}! Confirmamos o exame de {colaborador} no dia {data} às {hora}, na Vitalis. Levar documento com foto. Qualquer dúvida, é só responder esta mensagem.', true, 3, '2026-10-26 22:40:05.535956+00');
INSERT INTO pn_crm.wa_modelo (id, titulo, categoria, texto, ativo, ordem, atualizado_em) VALUES ('38373236-ac88-42a1-ab2b-c63a863620aa', 'Exames a vencer', 'exames', 'Olá, {nome}! Os exames periódicos de alguns colaboradores da {empresa} vencem nos próximos dias. Vamos agendar?', true, 4, '2026-10-26 22:40:05.535956+00');
INSERT INTO pn_crm.wa_modelo (id, titulo, categoria, texto, ativo, ordem, atualizado_em) VALUES ('7d520e2c-d296-4098-be03-fa380ad1519c', 'Lembrete de pagamento', 'cobranca', 'Olá, {nome}! Consta em aberto a mensalidade de {competencia} da {empresa}, no valor de {valor}, vencida em {vencimento}. Se já pagou, pode desconsiderar. Quer que eu envie a segunda via?', true, 5, '2026-10-26 22:40:05.535956+00');
INSERT INTO pn_crm.wa_modelo (id, titulo, categoria, texto, ativo, ordem, atualizado_em) VALUES ('aa5748f1-34bc-4c9a-863d-59d0a9baf05a', 'Renovação de documento', 'documentos', 'Olá, {nome}! O {documento} da {empresa} vence em {vencimento}. Vamos iniciar a renovação?', true, 6, '2026-10-26 22:40:05.535956+00');


