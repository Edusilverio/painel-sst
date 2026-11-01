// atestado-receber — porta de entrada dos atestados enviados pelo WhatsApp (0063).
//
// Quem chama: o Exemplo Connect (agente da Vitalis), depois que a IA leu o atestado.
// Autenticação: header `x-integracao-token` = token gerado em Painel › WhatsApp › Configuração
// (o mesmo da integração do WhatsApp). verify_jwt fica DESLIGADO: quem protege é o token.
//
// Corpo (JSON):
// {
//   "telefone": "5511999999999",          // quem enviou (identifica a empresa)
//   "cnpj": "...", "empresa": "...",       // opcionais, se a IA leu do atestado/conversa
//   "colaborador_nome": "...", "colaborador_cpf": "...",
//   "data_emissao": "AAAA-MM-DD", "data_inicio": "AAAA-MM-DD", "dias": 2,
//   "cid": "J11", "medico": "...", "medico_crm": "...",
//   "mensagem_id": "id da mensagem no WhatsApp (evita duplicar)",
//   "leitura_ia": { ... },                  // o que a IA extraiu, livre
//   "arquivo_base64": "...", "arquivo_url": "https://...",  // um dos dois (imagem ou PDF)
//   "arquivo_nome": "atestado.jpg", "arquivo_tipo": "image/jpeg"
// }
// Resposta: { id, numero, situacao: "ok" | "revisar", empresa_identificada, atestados_no_mes }
import { createClient } from "jsr:@supabase/supabase-js@2";

const TIPOS = ["image/jpeg", "image/png", "image/webp", "image/heic", "application/pdf"];
const MAX = 15 * 1024 * 1024;

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { erro: "Use POST." });
  const token = req.headers.get("x-integracao-token") ?? "";
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    db: { schema: Deno.env.get("DB_SCHEMA") ?? "public" }, auth: { persistSession: false },
  });

  const { data: valido } = await db.rpc("integracao_token_valido", { p_token: token });
  if (valido !== true) return json(401, { erro: "Token inválido." });

  let d: Record<string, unknown>;
  try {
    d = await req.json();
  } catch {
    return json(400, { erro: "Corpo precisa ser JSON." });
  }

  // arquivo (opcional, mas esperado)
  let caminho: string | null = null;
  let nome: string | null = null;
  try {
    let bytes: Uint8Array | null = null;
    let tipo = String(d.arquivo_tipo ?? "");
    if (typeof d.arquivo_base64 === "string" && d.arquivo_base64) {
      const b64 = d.arquivo_base64.replace(/^data:[^;]+;base64,/, "");
      bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    } else if (typeof d.arquivo_url === "string" && /^https:\/\//.test(d.arquivo_url)) {
      const r = await fetch(d.arquivo_url, { signal: AbortSignal.timeout(20000) });
      if (!r.ok) throw new Error(`download ${r.status}`);
      tipo = tipo || (r.headers.get("content-type") ?? "").split(";")[0];
      bytes = new Uint8Array(await r.arrayBuffer());
    }
    if (bytes) {
      if (bytes.byteLength > MAX) return json(413, { erro: "Arquivo maior que 15 MB." });
      if (!TIPOS.includes(tipo)) tipo = bytes[0] === 0x25 ? "application/pdf" : "image/jpeg";
      nome = String(d.arquivo_nome ?? "") || `atestado.${tipo === "application/pdf" ? "pdf" : tipo.split("/")[1]}`;
      const limpo = nome.normalize("NFD").replace(/[^\w.-]+/g, "_");
      const hoje = new Date().toISOString().slice(0, 7);
      caminho = `whatsapp/${hoje}/${crypto.randomUUID()}-${limpo}`;
      const { error } = await db.storage.from("atestados").upload(caminho, bytes, { contentType: tipo });
      if (error) throw new Error(error.message);
    }
  } catch (e) {
    // sem arquivo o atestado ainda entra (para revisão), mas avisamos quem chamou
    caminho = null;
    d.observacao_arquivo = `Falha ao guardar o arquivo: ${(e as Error).message}`;
  }

  const dados = { ...d, arquivo_path: caminho, arquivo_nome: nome };
  delete (dados as Record<string, unknown>).arquivo_base64;
  const { data, error } = await db.rpc("integracao_atestado_receber", { p_token: token, p_dados: dados });
  if (error) return json(400, { erro: error.message });
  return json(200, { ...(data as object), arquivo_guardado: caminho !== null, aviso: d.observacao_arquivo ?? null });
});
