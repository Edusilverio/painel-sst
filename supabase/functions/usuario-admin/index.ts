// usuario-admin — excluir conta ou trocar o e-mail de login de um usuário do painel (reunião 13/10, 0078).
//
// Quem chama: o painel, com o JWT de quem está logado (verify_jwt ligado).
// Antes de mexer no Auth, confere no banco (com o JWT de quem chamou) se é admin e se a ação é permitida:
// public.painel_usuario_admin_checar. Excluir só vale para conta sem histórico de trabalho.
//
// Corpo: { "acao": "excluir" | "trocar_email", "user_id": "<uuid>", "email": "novo@exemplo.com.br" }
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { erro: "Use POST." });

  const url = Deno.env.get("SUPABASE_URL")!;
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { erro: "Sessão ausente." });

  let d: { acao?: string; user_id?: string; email?: string };
  try {
    d = await req.json();
  } catch {
    return json(400, { erro: "Corpo precisa ser JSON." });
  }
  const acao = d.acao;
  const alvo = d.user_id ?? "";
  if (acao !== "excluir" && acao !== "trocar_email") return json(400, { erro: "Ação inválida." });
  if (!/^[0-9a-f-]{36}$/.test(alvo)) return json(400, { erro: "Usuário inválido." });

  // 1) checagem com o JWT de quem chamou: precisa ser admin (a função levanta erro se não for)
  const comoQuemChamou = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    db: { schema: Deno.env.get("DB_SCHEMA") ?? "public" }, auth: { persistSession: false },
  });
  const { data: chk, error: errChk } = await comoQuemChamou.rpc("painel_usuario_admin_checar", { p_user: alvo, p_acao: acao });
  if (errChk) return json(403, { erro: errChk.message });

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { db: { schema: Deno.env.get("DB_SCHEMA") ?? "public" }, auth: { persistSession: false } });

  if (acao === "excluir") {
    if (!chk?.pode_excluir) {
      return json(409, {
        erro: "Esta conta já tem histórico no painel (negócios, tarefas, agenda…). Em vez de excluir, desative o acesso.",
        atividade: chk?.atividade ?? {},
      });
    }
    const { error } = await admin.auth.admin.deleteUser(alvo);
    if (error) return json(500, { erro: error.message });
    return json(200, { ok: true, excluido: chk.email });
  }

  const email = String(d.email ?? "").trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json(400, { erro: "E-mail inválido." });
  const { error } = await admin.auth.admin.updateUserById(alvo, { email, email_confirm: true });
  if (error) return json(400, { erro: error.message.includes("already") ? "Este e-mail já é de outra conta." : error.message });
  const { error: e2 } = await admin.rpc("integracao_usuario_email", { p_user: alvo, p_email: email });
  if (e2) return json(500, { erro: e2.message });
  return json(200, { ok: true, email });
});
