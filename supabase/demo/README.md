# Base de demonstração (dados fictícios)

O painel roda sobre uma base Supabase **100% fictícia**: clínica "Vitalis", 48 empresas clientes,
~1.000 colaboradores, histórico de ASO e exames, CRM com 5 funis, contratos, cobranças, agenda,
atestados, tarefas, chat e WhatsApp. Nenhum dado real.

A base usa **schemas próprios**, o que permite dividir um mesmo projeto Supabase com outras aplicações:

| Schema | Conteúdo |
|---|---|
| `pn` | funções `painel_*` (a API que o navegador chama) e cadastros clínicos |
| `pn_crm` | CRM, agenda, contratos, financeiro, tarefas, chat, WhatsApp |
| `pn_app` | vencimentos de exames e utilitários |
| `pn_sesmo`, `pn_bitrix` | camadas de integração (vazias na demo) |

Buckets do Storage: `pn-crm-arquivos`, `pn-atestados`, `pn-chat`.

## Como subir

1. Crie um projeto no Supabase (ou use um existente).
2. Rode os arquivos na ordem, no SQL Editor ou com `psql`:
   ```bash
   psql "$DATABASE_URL" -f pn_01_estrutura.sql   # tabelas, 300+ funções, buckets, policies, gatilhos de login
   psql "$DATABASE_URL" -f pn_02_config.sql      # funis, etapas, catálogo, modelos de mensagem
   ```
3. Em **Project Settings → Data API → Exposed schemas**, adicione `pn`.
4. Crie as contas da equipe. O cadastro pelo próprio painel já marca a conta com o app
   (`VITE_APP_ID=pn`). Para que o primeiro login vire administrador:
   ```sql
   insert into pn_crm.admin_inicial (email) values ('seu-email@exemplo.com');
   ```
5. Rode `pn_03_seed.sql` para carregar os dados fictícios. Ele espera os usuários da equipe demo
   (`*@exemplo.com.br`), que podem ser criados pelo painel ou pelo Auth. Pode rodar de novo a qualquer momento:
   ele limpa e recria os dados, com datas relativas ao dia atual.
6. Copie `.env.example` para `.env` e preencha URL e chave anon do projeto.

## Gatilhos de login compartilhado

Os gatilhos em `auth.users` só criam perfil no painel para contas com `raw_user_meta_data.app = 'pn'`.
Assim, outras aplicações no mesmo projeto Supabase não geram usuários no CRM.

## Rotinas agendadas

Se a extensão `pg_cron` estiver ativa, a estrutura agenda os alertas diários (negócios parados, tarefas,
contratos a vencer, inadimplência, documentos e renovações) com o prefixo `pn-`.
