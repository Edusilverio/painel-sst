import Docxtemplater from "docxtemplater";
import PizZip from "pizzip";
import { supabase } from "@/lib/supabase";
import { CAMINHO_MODELO, dadosMinuta, type Minuta } from "@/lib/minuta";

/** Baixa o modelo, preenche e devolve o .docx. */
export async function gerarMinuta(m: Minuta): Promise<{ blob: Blob; nome: string }> {
  const { data: arq, error } = await supabase.storage.from(((import.meta.env.VITE_STORAGE_PREFIX as string | undefined) ?? "") + "crm-arquivos").download(CAMINHO_MODELO);
  if (error || !arq) throw new Error("Modelo da minuta não encontrado. Um gestor precisa enviar o arquivo em Contratos › Modelo da minuta.");
  const zip = new PizZip(await arq.arrayBuffer());
  const doc = new Docxtemplater(zip, { paragraphLoop: true, linebreaks: true, nullGetter: () => "" });
  doc.render(dadosMinuta(m));
  const blob = doc.getZip().generate({ type: "blob", mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document" }) as Blob;
  const cliente = (m.razao_social ?? "cliente").normalize("NFD").replace(/[^\w]+/g, "-").replace(/^-|-$/g, "").slice(0, 40);
  return { blob, nome: `Contrato-${m.numero}-${cliente}.docx` };
}

