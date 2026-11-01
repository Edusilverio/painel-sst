import { supabase } from "@/lib/supabase";
import { fmtCnpj } from "@/lib/utils";

/** Onde fica o modelo (bucket privado; só gestor/admin troca). */
export const CAMINHO_MODELO = "modelos/contrato-vitalis.docx";

/** Serviços do item 3 da minuta, na ordem do Quadro Resumo. */
export const SERVICOS_MINUTA = [
  "aso", "pcmso", "pgr", "ltcat", "psicossocial", "ppp", "insalubridade", "periculosidade", "esocial",
  "cipa", "brigada", "primeiros_socorros", "nrs", "pericia", "avulso", "atualizacao_laudo",
] as const;

export interface MinutaItem {
  id: string;
  codigo: string | null;
  descricao: string;
  quantidade: number;
  preco: number;
  total: number;
  unidade: string | null;
  cobranca: string | null;
}

export interface Minuta {
  id: string;
  numero: number;
  titulo: string;
  razao_social: string | null;
  cnpj: string | null;
  endereco: string | null;
  telefone: string | null;
  email_notificacao: string | null;
  representante_legal: string | null;
  inicio: string | null;
  fim: string | null;
  prazo_meses: number | null;
  renovacao_automatica: boolean;
  dia_vencimento: number | null;
  forma_pagamento: string | null;
  indice_reajuste: string | null;
  itens: MinutaItem[];
}

const MARCADO = "☒";
const VAZIO = "☐";
const LINHA = "______________________________";
const MESES = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];

const real = (v: number) => v.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
const data = (iso: string | null) => (iso ? iso.split("-").reverse().join("/") : "____/____/______");

function mesesEntre(ini: string | null, fim: string | null) {
  if (!ini || !fim) return null;
  const [a, b] = [new Date(ini + "T12:00:00"), new Date(fim + "T12:00:00")];
  return (b.getFullYear() - a.getFullYear()) * 12 + (b.getMonth() - a.getMonth());
}

/** O que falta preencher antes de mandar para o cliente. */
export function pendenciasMinuta(m: Minuta) {
  const f: string[] = [];
  if (!m.cnpj) f.push("CNPJ do cliente");
  if (!m.endereco) f.push("endereço do cliente");
  if (!m.representante_legal) f.push("representante legal");
  if (!m.email_notificacao) f.push("e-mail oficial para notificações");
  if (!m.inicio) f.push("início da vigência");
  if (!m.itens.some((i) => i.codigo)) f.push("serviços do catálogo (aba Serviços)");
  return f;
}

export function dadosMinuta(m: Minuta) {
  const hoje = new Date();
  const d: Record<string, string> = {
    razao_social: m.razao_social ?? LINHA,
    cnpj: m.cnpj ? fmtCnpj(m.cnpj) : LINHA,
    representante_legal: m.representante_legal ?? LINHA,
    endereco: m.endereco ?? LINHA,
    telefone: m.telefone ?? LINHA,
    email_notificacao: m.email_notificacao ?? LINHA,
    inicio: data(m.inicio),
    fim: data(m.fim),
    dia_vencimento: String(m.dia_vencimento ?? 5).padStart(2, "0"),
    data_extenso: `${hoje.getDate()} de ${MESES[hoje.getMonth()]} de ${hoje.getFullYear()}`,
  };

  for (const cod of SERVICOS_MINUTA) {
    const itens = m.itens.filter((i) => i.codigo === cod);
    const it = itens[0];
    d[`x_${cod}`] = it ? MARCADO : VAZIO;
    d[`v_${cod}`] = it ? (it.preco > 0 ? `${real(it.preco)}${it.unidade && it.unidade !== "laudo" ? ` / por ${it.unidade}` : ""}` : "Conforme proposta") : "";
    d[`c_${cod}`] = it?.cobranca ?? "";
  }
  d.x_esocial_nao = m.itens.some((i) => i.codigo === "esocial") ? VAZIO : MARCADO;

  const prazo = m.prazo_meses ?? mesesEntre(m.inicio, m.fim);
  d.x_p12 = prazo === 12 ? MARCADO : VAZIO;
  d.x_p24 = prazo === 24 ? MARCADO : VAZIO;
  d.x_pout = prazo && prazo !== 12 && prazo !== 24 ? MARCADO : VAZIO;
  d.prazo_outro = prazo && prazo !== 12 && prazo !== 24 ? `${prazo} meses` : "";

  const forma = (m.forma_pagamento ?? "Boleto bancário").toLowerCase();
  const boleto = forma.includes("boleto");
  const pix = forma.includes("pix") || forma.includes("transfer");
  d.x_boleto = boleto ? MARCADO : VAZIO;
  d.x_pix = pix ? MARCADO : VAZIO;
  d.x_fout = !boleto && !pix ? MARCADO : VAZIO;
  d.forma_outro = !boleto && !pix ? (m.forma_pagamento ?? "") : "";
  return d;
}

export function baixarBlob(blob: Blob, nome: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = nome;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

export async function enviarModelo(arquivo: File) {
  await supabase.storage.from(((import.meta.env.VITE_STORAGE_PREFIX as string | undefined) ?? "") + "crm-arquivos").remove([CAMINHO_MODELO]);
  const { error } = await supabase.storage.from(((import.meta.env.VITE_STORAGE_PREFIX as string | undefined) ?? "") + "crm-arquivos").upload(CAMINHO_MODELO, arquivo, {
    contentType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  });
  if (error) throw new Error(`Não foi possível enviar o modelo: ${error.message}`);
}
