# Painel Vitalis

CRM e painel operacional da Vitalis (Medicina e Engenharia do Trabalho). Construído pela Exemplo
Consultoria sobre o banco próprio da Vitalis (`vitalis-data-lake`, Supabase). Substitui o Bitrix
(CRM) e dá à Vitalis acesso direto aos dados que hoje estão presos no SESMO.

## O que tem nesta primeira versão

| Área | Telas |
|---|---|
| CRM | Funis em quadro (arrastar e soltar), detalhe do negócio (dados, itens, histórico), pendências, catálogo |
| Clientes | Lista de empresas (SESMO) com busca e situação; ficha 360 (unidades, contatos, documentos, negócios, exames) |
| Saúde ocupacional | Vencimento de exames (exporta para o RH) e consulta de atendimentos |
| Configurações | Funis e etapas (cor, ordem, prazo de aviso), rodízio de responsáveis, usuários e perfis |
| Em construção | Agenda, WhatsApp, Financeiro, Contratos — telas de "próximas etapas" para a Vitalis acompanhar |

### Funis (réplica do Bitrix, conferida na gravação de 31/08/2026)
- **Comercial:** Novo negócio → Contato feito → Reunião agendada → Follow-up → Proposta → Envio de contrato → Negócio fechado | Oportunidade perdida
- **Faturamento, Vistoria, Laudos:** Não tocado → Em execução → Concluído | Não concluído
- **Pós-venda:** Contratos fechados → Inadimplentes → Renovações → Concluído | Sem entrega
- **Túnel:** negócio fechado no Comercial abre card em Faturamento e Pós-venda (itens copiados).
- **Avisos:** Novo negócio 3 dias, Contato feito 5 dias, Proposta 3 dias (repete a cada 3 dias até andar).
- **Rodízio:** negócio sem responsável vai para o próximo da fila (Ana → Luana → Moura, configurável).

## Stack
React 18 + Vite 5 + TypeScript estrito + Tailwind + componentes no padrão shadcn/ui (Radix) +
TanStack Query + sonner + lucide. Mesmo método do Exemplo Connect, com a identidade da Vitalis:
vinho `#870028` (primária) e laranja `#F08827` (chamada para ação), tema claro e escuro.

Regras de tela: todo dado tem os três estados (carregando com esqueleto, vazio explicado, erro
visível em português); nunca zero no lugar de "ainda não sei"; cores só por token.

## Segurança
- O navegador **não lê tabela nenhuma**. Todo acesso é por funções `public.painel_*`
  (`security definer`) que conferem o papel do usuário antes de responder.
- Tabelas do CRM ficam no schema `crm`, que não é exposto pelo PostgREST; as do SESMO seguem com
  RLS ligada e sem policy.
- Cadastro novo nasce **inativo**; um administrador libera e define o perfil.
- Perfis: `admin`, `gestor`, `comercial`, `operacoes`, `financeiro`, `leitura`. Dado clínico
  (vencimentos, atendimentos) só para admin, gestor e operações.
- `anon` não executa nenhuma função `painel_*` (conferido no teste).

## Banco — ordem das migrations
As migrations `0001`–`0032` (base do SESMO) ficam em `vitalis-db/` na pasta do projeto. Este
repositório traz as do painel, que rodam **depois** delas:

```
supabase/migrations/0040_painel_acesso.sql   perfis, papéis, gatilho de cadastro, usuários
supabase/migrations/0041_crm_modelo.sql      funis, etapas, negócios, itens, eventos, rodízio, túneis, avisos + sementes
supabase/migrations/0042_crm_api.sql         funções do CRM + pg_cron dos avisos (dias úteis 08:00)
supabase/migrations/0043_painel_leitura.sql  visão geral, clientes, vencimentos, atendimentos
```
Todas são reexecutáveis.

**Primeiro administrador** (não há quem libere o primeiro): depois que a pessoa criar a conta no
painel, rodar no SQL Editor:
```sql
update crm.perfil set papel = 'admin', ativo = true where email = 'email@exemplo.com.br';
```

### Teste local do banco
`supabase/tests/` tem um stub mínimo do Supabase e o teste de fumaça do CRM (rodízio, túnel,
motivo de perda obrigatório, trava de reabertura, permissões por papel, avisos). Com Postgres 16:
aplicar o stub, as migrations base (0001–0010) e as 0040–0043, e depois `smoke_crm.sql`.

## Rodar local
```bash
cp .env.example .env.local   # URL e chave pública (anon) do vitalis-data-lake
npm install
npm run dev
```

## Publicar
É um site estático (`npm run build` → `dist/`). Serve em qualquer hospedagem estática; o
redirecionamento de SPA já está pronto (`public/_redirects` para Netlify/Cloudflare,
`vercel.json` para Vercel). Na VPS com nginx: `try_files $uri /index.html;`.
Variáveis de build: `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` (nunca a service_role).

## Pendências abertas com a Vitalis
- Confirmar se Vistoria e Laudos também nascem do fechamento no Comercial (hoje só Faturamento e Pós-venda).
- Preços do catálogo (o PGR é por faixa de funcionários).
- De/para da situação das empresas no SESMO (ativo / sem contrato / inativo).
- Cadência de follow-up com e-mail e WhatsApp (TouchPoints do 1º ao 7º dia) — entra com o módulo de WhatsApp.

---

> **Nota:** projeto adaptado de um trabalho profissional para fins de portfólio. Nomes de clientes, credenciais e dados foram substituídos por valores fictícios.
