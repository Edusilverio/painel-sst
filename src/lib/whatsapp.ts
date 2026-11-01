import type { WaModelo } from "@/lib/tipos";

export const CATEGORIAS_WA: Record<WaModelo["categoria"], string> = {
  comercial: "Comercial",
  agendamento: "Agendamento",
  exames: "Exames",
  cobranca: "Cobrança",
  documentos: "Documentos",
  geral: "Geral",
};

export const VARIAVEIS_WA: { chave: string; descricao: string }[] = [
  { chave: "nome", descricao: "nome do contato" },
  { chave: "empresa", descricao: "empresa do cliente" },
  { chave: "atendente", descricao: "seu nome" },
  { chave: "colaborador", descricao: "quem fará o exame" },
  { chave: "data", descricao: "data" },
  { chave: "hora", descricao: "horário" },
  { chave: "valor", descricao: "valor" },
  { chave: "vencimento", descricao: "data de vencimento" },
  { chave: "competencia", descricao: "mês de referência" },
  { chave: "documento", descricao: "PGR, PCMSO…" },
];

/** Link direto para a conversa no Inbox do Exemplo Connect. */
export function linkInbox(base: string, c: { ext_conversa_id: string | null; ext_lead_id: string } | null | undefined) {
  if (!c) return null;
  const url = base.replace(/\/+$/, "");
  return c.ext_conversa_id ? `${url}?conversation=${c.ext_conversa_id}` : `${url}?lead=${c.ext_lead_id}`;
}

/** Telefone só com dígitos e com o 55 na frente (formato do WhatsApp). Null se não parece um celular/fixo do Brasil. */
export function telefoneWhats(v: string | null | undefined) {
  let d = (v ?? "").replace(/\D/g, "").replace(/^0+/, "");
  if (d.length === 10 || d.length === 11) d = `55${d}`;
  return /^55\d{10,11}$/.test(d) ? d : null;
}

/**
 * Link que abre o Inbox do Exemplo Connect já iniciando (ou reabrindo) a conversa com o número, em atendimento
 * humano, pelo canal da Vitalis. O Exemplo Connect lê `telefone`, `nome`, `empresa` e `ref` (origem no CRM).
 */
export function linkIniciarConversa(base: string, d: { telefone: string; nome?: string | null; empresa?: string | null; ref?: string | null }) {
  const p = new URLSearchParams({ telefone: d.telefone });
  if (d.nome?.trim()) p.set("nome", d.nome.trim());
  if (d.empresa?.trim()) p.set("empresa", d.empresa.trim());
  if (d.ref) p.set("ref", d.ref);
  return `${base.replace(/\/+$/, "")}?${p.toString()}`;
}

/** Troca {variavel} pelos valores conhecidos; o que não tem valor fica como está para a pessoa completar. */
export function preencher(texto: string, valores: Record<string, string | null | undefined>) {
  return texto.replace(/\{(\w+)\}/g, (m, k: string) => {
    const v = valores[k];
    return v && v.trim() ? v.trim() : m;
  });
}

export function pendentes(texto: string) {
  return [...new Set([...texto.matchAll(/\{(\w+)\}/g)].map((m) => m[1]))];
}

/** Primeiro nome, para a saudação soar natural. */
export function primeiroNome(nome: string | null | undefined) {
  return nome?.trim().split(/\s+/)[0] ?? "";
}

export function fmtTelefone(v: string | null | undefined) {
  const d = (v ?? "").replace(/\D/g, "");
  if (!d) return "—";
  const n = d.startsWith("55") && d.length >= 12 ? d.slice(2) : d;
  if (n.length === 11) return `(${n.slice(0, 2)}) ${n.slice(2, 7)}-${n.slice(7)}`;
  if (n.length === 10) return `(${n.slice(0, 2)}) ${n.slice(2, 6)}-${n.slice(6)}`;
  return `+${d}`;
}

export function tempoCurto(v: string | null | undefined) {
  if (!v) return "—";
  const min = Math.floor((Date.now() - new Date(v).getTime()) / 60_000);
  if (min < 1) return "agora";
  if (min < 60) return `há ${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `há ${h} h`;
  const d = Math.floor(h / 24);
  if (d === 1) return "ontem";
  if (d < 7) return `há ${d} dias`;
  return new Date(v).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" });
}
