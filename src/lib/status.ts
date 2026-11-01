import type { BadgeVariant } from "@/components/ui/badge";
import type { CorEtapa } from "./tipos";

/** Mapas de status: um lugar só, classes por token (valem nos dois temas). */

export const corEtapa: Record<CorEtapa, { borda: string; ponto: string; badge: BadgeVariant }> = {
  muted: { borda: "border-t-muted-foreground/40", ponto: "bg-muted-foreground", badge: "muted" },
  info: { borda: "border-t-info", ponto: "bg-info", badge: "info" },
  primary: { borda: "border-t-primary", ponto: "bg-primary", badge: "default" },
  warning: { borda: "border-t-warning", ponto: "bg-warning", badge: "warning" },
  marca: { borda: "border-t-marca", ponto: "bg-marca", badge: "marca" },
  success: { borda: "border-t-success", ponto: "bg-success", badge: "success" },
  destructive: { borda: "border-t-destructive", ponto: "bg-destructive", badge: "destructive" },
};

export function situacaoCliente(s: string): { rotulo: string; badge: BadgeVariant } {
  switch (s) {
    case "ativo":
      return { rotulo: "Ativo", badge: "success" };
    case "sem_contrato":
      return { rotulo: "Sem contrato", badge: "destructive" };
    case "inativo":
      return { rotulo: "Inativo", badge: "muted" };
    default:
      return { rotulo: "A confirmar", badge: "outline" };
  }
}

export function statusVencimento(s: string): { rotulo: string; badge: BadgeVariant } {
  switch (s) {
    case "vencido":
      return { rotulo: "Vencido", badge: "destructive" };
    case "vence_em_30_dias":
      return { rotulo: "Vence em 30 dias", badge: "warning" };
    case "vence_em_60_dias":
      return { rotulo: "Vence em 60 dias", badge: "info" };
    default:
      return { rotulo: "Em dia", badge: "success" };
  }
}

/** Legenda do SESMO que a Vitalis já conhece: agendado verde, aguardando azul, finalizado branco. */
export function situacaoAtendimento(s: string): { rotulo: string; badge: BadgeVariant } {
  switch (s) {
    case "agendado":
      return { rotulo: "Agendado", badge: "success" };
    case "aguardando":
      return { rotulo: "Aguardando", badge: "info" };
    case "atendido":
      return { rotulo: "Atendido", badge: "warning" };
    case "finalizado":
      return { rotulo: "Finalizado", badge: "outline" };
    case "cancelado":
      return { rotulo: "Cancelado", badge: "muted" };
    case "faltou":
      return { rotulo: "Faltou", badge: "destructive" };
    default:
      return { rotulo: s, badge: "muted" };
  }
}

export const tipoExame: Record<string, string> = {
  admissional: "Admissional",
  periodico: "Periódico",
  demissional: "Demissional",
  mudanca_de_funcao: "Mudança de função",
  retorno_ao_trabalho: "Retorno ao trabalho",
  monitoracao_pontual: "Monitoração pontual",
  mudanca_de_riscos: "Mudança de riscos",
  outro: "Outro",
};

export const origensNegocio: { valor: string; rotulo: string }[] = [
  { valor: "manual", rotulo: "Cadastro manual" },
  { valor: "indicacao", rotulo: "Indicação" },
  { valor: "whatsapp", rotulo: "WhatsApp" },
  { valor: "landing", rotulo: "Site / Google Ads" },
  { valor: "telefone", rotulo: "Telefone" },
  { valor: "renovacao", rotulo: "Renovação" },
  { valor: "ganho_comercial", rotulo: "Ganho no Comercial" },
];
export const rotuloOrigem = (v: string) => origensNegocio.find((o) => o.valor === v)?.rotulo ?? v;

/** Fluxo de Trabalho: as mesmas cores do quadro do Monday que a equipe já usa. */
export const statusTarefa: Record<string, { rotulo: string; badge: BadgeVariant; faixa: string; lateral: string; fundo: string }> = {
  nao_iniciado: { rotulo: "Não iniciado", badge: "muted", faixa: "border-t-muted-foreground/40", lateral: "border-l-muted-foreground/40", fundo: "bg-muted-foreground" },
  em_andamento: { rotulo: "Em andamento", badge: "warning", faixa: "border-t-warning", lateral: "border-l-warning", fundo: "bg-warning" },
  parado: { rotulo: "Parado", badge: "destructive", faixa: "border-t-destructive", lateral: "border-l-destructive", fundo: "bg-destructive" },
  feito: { rotulo: "Feito", badge: "success", faixa: "border-t-success", lateral: "border-l-success", fundo: "bg-success" },
};
export const ORDEM_STATUS_TAREFA = ["nao_iniciado", "em_andamento", "parado", "feito"] as const;

export const prioridadeTarefa: Record<string, { rotulo: string; badge: BadgeVariant }> = {
  baixa: { rotulo: "Baixa", badge: "info" },
  media: { rotulo: "Média", badge: "default" },
  alta: { rotulo: "Alta", badge: "warning" },
  critica: { rotulo: "Crítica", badge: "destructive" },
};

/** Assinatura: o mesmo kanban do Bitrix Sign. */
export const statusContrato: Record<string, { rotulo: string; badge: BadgeVariant; faixa: string }> = {
  rascunho: { rotulo: "Rascunho", badge: "muted", faixa: "border-t-muted-foreground/40" },
  revisao: { rotulo: "Sob revisão", badge: "info", faixa: "border-t-info" },
  enviado: { rotulo: "Enviado", badge: "warning", faixa: "border-t-warning" },
  parcial: { rotulo: "Parcialmente assinado", badge: "marca", faixa: "border-t-marca" },
  assinado: { rotulo: "Assinado", badge: "success", faixa: "border-t-success" },
  cancelado: { rotulo: "Cancelado", badge: "destructive", faixa: "border-t-destructive" },
};
export const ORDEM_STATUS_CONTRATO = ["rascunho", "revisao", "enviado", "parcial", "assinado"] as const;

export const situacaoContrato: Record<string, { rotulo: string; badge: BadgeVariant }> = {
  em_assinatura: { rotulo: "Em assinatura", badge: "info" },
  vigente: { rotulo: "Vigente", badge: "success" },
  a_renovar: { rotulo: "A renovar", badge: "warning" },
  vencido: { rotulo: "Vencido", badge: "destructive" },
  cancelado: { rotulo: "Cancelado", badge: "muted" },
};

export const situacaoCobranca: Record<string, { rotulo: string; badge: BadgeVariant }> = {
  aberta: { rotulo: "Em aberto", badge: "info" },
  vencida: { rotulo: "Vencida", badge: "destructive" },
  paga: { rotulo: "Paga", badge: "success" },
  cancelada: { rotulo: "Cancelada", badge: "muted" },
};

export const formasPagamento: { valor: string; rotulo: string }[] = [
  { valor: "boleto", rotulo: "Boleto" },
  { valor: "pix", rotulo: "PIX" },
  { valor: "transferencia", rotulo: "Transferência" },
  { valor: "cartao", rotulo: "Cartão" },
  { valor: "dinheiro", rotulo: "Dinheiro" },
  { valor: "outro", rotulo: "Outro" },
];

export const situacaoDocumento: Record<string, { rotulo: string; badge: BadgeVariant }> = {
  em_elaboracao: { rotulo: "Em elaboração", badge: "info" },
  vigente: { rotulo: "Vigente", badge: "success" },
  a_vencer: { rotulo: "A vencer", badge: "warning" },
  vencido: { rotulo: "Vencido", badge: "destructive" },
  cancelado: { rotulo: "Cancelado", badge: "muted" },
};
export const TIPOS_DOCUMENTO = ["PGR", "PCMSO", "LTCAT", "LTIP", "PPR", "PCA", "PPP", "OUTRO"] as const;

export const situacaoColaborador: Record<string, { rotulo: string; badge: BadgeVariant }> = {
  ativo: { rotulo: "Ativo", badge: "success" },
  afastado: { rotulo: "Afastado", badge: "warning" },
  desligado: { rotulo: "Desligado", badge: "muted" },
  inativo: { rotulo: "Inativo", badge: "outline" },
};

export const resultadoAso: Record<string, string> = {
  pendente: "Pendente",
  apto: "Apto",
  apto_com_restricao: "Apto com restrição",
  inapto: "Inapto",
};
