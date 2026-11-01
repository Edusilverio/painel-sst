import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const chave = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const configurado = Boolean(url && chave);

// Todo acesso a dado passa por funções (RPC) com guarda de papel no banco.
// As tabelas ficam com RLS sem policy: nada é lido direto pelo navegador.
export const supabase = createClient(url ?? "http://localhost", chave ?? "sem-chave", {
  db: { schema: (import.meta.env.VITE_SUPABASE_SCHEMA as string | undefined) || "public" },
  auth: { persistSession: true, autoRefreshToken: true, storageKey: "vitalis.auth" },
});

/** Chama uma RPC e transforma erro do Postgres em mensagem em português. */
export async function rpc<T>(nome: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(nome, args ?? {});
  if (error) throw new Error(traduzErro(error.message, error.code));
  return data as T;
}

export function traduzErro(msg: string, code?: string) {
  // 42501 com mensagem nossa (em português) passa direto; o genérico é para o "permission denied" do Postgres.
  if (/permission denied/i.test(msg) || (code === "42501" && !/[ãçéêíóôõú]/i.test(msg))) return "Seu perfil não tem permissão para isso. Fale com o administrador.";
  if (code === "PGRST202" || /could not find the function/i.test(msg)) return "O banco ainda não tem esta função publicada. Avise a equipe da Exemplo.";
  if (/JWT|not authenticated/i.test(msg)) return "Sua sessão expirou. Entre de novo.";
  if (/Failed to fetch|NetworkError/i.test(msg)) return "Sem conexão com o servidor. Confira sua internet e tente de novo.";
  return msg;
}
