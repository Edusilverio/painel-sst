export type Papel = "admin" | "gestor" | "comercial" | "operacoes" | "financeiro" | "leitura";

export const PAPEIS: { valor: Papel; rotulo: string; descricao: string }[] = [
  { valor: "admin", rotulo: "Administrador", descricao: "Tudo, inclusive liberar usuários" },
  { valor: "gestor", rotulo: "Gestor", descricao: "Todos os funis, catálogo, etapas e dados clínicos" },
  { valor: "comercial", rotulo: "Comercial", descricao: "Opera os funis Comercial e Pós-venda" },
  { valor: "operacoes", rotulo: "Operações", descricao: "Vistoria, Laudos, vencimentos e atendimentos" },
  { valor: "financeiro", rotulo: "Financeiro", descricao: "Opera o funil de Faturamento" },
  { valor: "leitura", rotulo: "Leitura", descricao: "Só consulta, não altera nada" },
];
export const rotuloPapel = (p?: string | null) => PAPEIS.find((x) => x.valor === p)?.rotulo ?? p ?? "—";

export interface Perfil {
  user_id: string;
  nome: string;
  email: string;
  papel: Papel;
  ativo: boolean;
}

export type TipoEtapa = "aberta" | "ganho" | "perdido";
export type CorEtapa = "muted" | "info" | "primary" | "warning" | "marca" | "success" | "destructive";

export interface Etapa {
  id: string;
  nome: string;
  ordem: number;
  tipo: TipoEtapa;
  cor: CorEtapa;
  alerta_dias: number | null;
  ativo: boolean;
}

export interface Funil {
  id: string;
  slug: string;
  nome: string;
  descricao: string | null;
  usa_rodizio: boolean;
  papeis: Papel[];
  pode_operar: boolean;
  etapas: Etapa[];
}

export interface CardNegocio {
  id: string;
  numero: number;
  etapa_id: string;
  titulo: string;
  cliente: string | null;
  empresa_id: string | null;
  responsavel_id: string | null;
  responsavel_nome: string | null;
  valor: number;
  origem: string;
  entrou_etapa_em: string;
  dias_na_etapa: number;
  atrasado: boolean;
  qtd_itens: number;
  previsao_fechamento: string | null;
  criado_em: string;
  /** 0081: responsável do card do Comercial na raiz do túnel (só em cards abertos pelo túnel) */
  vendedor_nome?: string | null;
}

export interface ItemNegocio {
  id: string;
  produto_id: string | null;
  descricao: string;
  quantidade: number;
  preco_unitario: number;
  /** 0081: total já com o desconto do item */
  total: number;
  total_bruto?: number | null;
  preco_catalogo?: number | null;
  desconto_pct?: number | null;
}

export interface EventoNegocio {
  id: number;
  tipo: string;
  texto: string | null;
  criado_em: string;
  autor: string | null;
  de_etapa: string | null;
  para_etapa: string | null;
}

export type FormaPagamento = "boleto" | "pix" | "transferencia" | "cartao";
export const formasPagamento: { valor: FormaPagamento; rotulo: string }[] = [
  { valor: "boleto", rotulo: "Boleto" },
  { valor: "pix", rotulo: "PIX" },
  { valor: "transferencia", rotulo: "Transferência bancária" },
  { valor: "cartao", rotulo: "Cartão de crédito" },
];
export function rotuloPagamento(forma: FormaPagamento | null, parcelas: number | null): string | null {
  if (!forma && !parcelas) return null;
  const nome = formasPagamento.find((f) => f.valor === forma)?.rotulo;
  if (forma === "boleto") return parcelas ? `${parcelas}x no boleto` : "Boleto";
  if (nome && parcelas && parcelas > 1) return `${nome} em ${parcelas}x`;
  if (nome) return nome;
  return parcelas ? `${parcelas}x` : null;
}

export interface Negocio {
  id: string;
  numero: number;
  funil_id: string;
  etapa_id: string;
  titulo: string;
  empresa_id: string | null;
  empresa: { id: string; razao_social: string; nome_fantasia: string | null; cnpj: string | null; cidade: string | null; uf: string | null; telefone: string | null; email: string | null } | null;
  cliente_nome: string | null;
  cliente_cnpj: string | null;
  contato_nome: string | null;
  contato_telefone: string | null;
  contato_email: string | null;
  responsavel_id: string | null;
  responsavel_nome: string | null;
  /** 0081: quem vendeu (card do Comercial na raiz) */
  vendedor_nome: string | null;
  /** 0081: desconto geral (%) sobre a soma dos itens */
  desconto_pct: number | null;
  valor: number;
  origem: string;
  previsao_fechamento: string | null;
  motivo_perda: string | null;
  observacao: string | null;
  qtd_funcionarios: number | null;
  forma_pagamento: FormaPagamento | null;
  parcelas: number | null;
  entrou_etapa_em: string;
  fechado_em: string | null;
  criado_em: string;
  pode_operar: boolean;
  /** 0074: valores em R$ só para admin, financeiro e comercial; para os demais valor e preços vêm nulos */
  ve_valores: boolean;
  negocio_origem: {
    id: string;
    numero: number;
    funil: string;
    observacao: string | null;
    qtd_funcionarios: number | null;
    forma_pagamento: FormaPagamento | null;
    parcelas: number | null;
    responsavel_nome: string | null;
    atualizado_em: string;
  } | null;
  derivados: { id: string; numero: number; funil: string; etapa: string }[];
  itens: ItemNegocio[];
  eventos: EventoNegocio[];
}

export interface Responsavel {
  user_id: string;
  nome: string;
  papel: Papel;
}

export interface Produto {
  id: string;
  nome: string;
  descricao: string | null;
  categoria: string | null;
  preco: number | null;
  unidade: string;
  recorrente: boolean;
  ativo: boolean;
}

export interface Pendencia {
  id: string;
  numero: number;
  titulo: string;
  cliente: string | null;
  funil_id: string;
  funil: string;
  etapa: string;
  responsavel_id: string | null;
  responsavel_nome: string | null;
  dias_na_etapa: number;
  alerta_dias: number;
  valor: number;
}

export interface EmpresaBusca {
  id: string;
  nome: string;
  razao_social: string;
  cnpj: string | null;
  cidade: string | null;
  uf: string | null;
}

export interface Notificacao {
  id: number;
  negocio_id: string | null;
  tarefa_id?: string | null;
  contrato_id?: string | null;
  tipo: string;
  texto: string;
  lida_em: string | null;
  criado_em: string;
}

export interface Resumo {
  /** 0073: empresa = tudo (admin/gestor/financeiro); meus = só o próprio comercial; nenhum = sem números do comercial */
  escopo: "empresa" | "meus" | "nenhum";
  clientes_total: number;
  clientes_ativos: number;
  clientes_sem_contrato: number;
  clientes_inativos: number;
  clientes_a_confirmar: number;
  unidades: number;
  colaboradores_ativos: number;
  negocios_abertos: number | null;
  valor_aberto_comercial: number | null;
  ganhos_mes: number | null;
  valor_ganho_mes: number | null;
  parados: number | null;
  acesso_clinico: boolean;
  exames_vencidos: number | null;
  exames_30_dias: number | null;
  exames_60_dias: number | null;
  atendimentos_mes: number | null;
  funil_comercial: { etapa: string; cor: CorEtapa; qtd: number; valor: number }[];
}

export interface ClienteLinha {
  id: string;
  nome: string;
  razao_social: string;
  cnpj: string | null;
  situacao: string;
  cidade: string | null;
  uf: string | null;
  telefone: string | null;
  email: string | null;
  unidades: number;
  colaboradores: number;
  negocios_abertos: number;
  total: number;
}

export interface ClienteDetalhe {
  id: string;
  razao_social: string;
  nome_fantasia: string | null;
  cnpj: string | null;
  situacao: string;
  cnae_principal: string | null;
  grau_risco: number | null;
  cidade: string | null;
  uf: string | null;
  cep: string | null;
  endereco: string | null;
  telefone: string | null;
  email: string | null;
  contrato_inicio: string | null;
  contrato_fim: string | null;
  logradouro: string | null;
  numero: string | null;
  complemento: string | null;
  bairro: string | null;
  sesmo_id: string | null;
  campos_editados: string[];
  pode_editar: boolean;
  colaboradores_ativos: number;
  historico: EdicaoHistorico[];
  contatos: ContatoEmpresa[];
  unidades: UnidadeEmpresa[];
  documentos: { tipo: string; versao: string | null; vigencia_inicio: string | null; vigencia_fim: string | null; situacao: string }[];
  negocios: { id: string; numero: number; titulo: string; funil: string; etapa: string; tipo: TipoEtapa; valor: number; criado_em: string }[];
  acesso_clinico: boolean;
  vencimentos: { vencido: number; vence_em_30_dias: number; vence_em_60_dias: number; em_dia: number } | null;
  ultimo_atendimento: string | null;
  atendimentos_12m: number | null;
  interacoes: import("@/components/dados/ContatarEmpresa").Interacao[];
}

export interface VencimentoLinha {
  colaborador_id: string;
  colaborador: string;
  cpf: string | null;
  matricula_esocial: string | null;
  empresa_id: string;
  empresa: string;
  unidade: string | null;
  setor: string | null;
  funcao: string | null;
  proximo_exame: string | null;
  dias_para_vencer: number | null;
  exames_vencidos: number;
  exames_nunca_feitos: number;
  status: "vencido" | "vence_em_30_dias" | "vence_em_60_dias" | "em_dia";
  total: number;
}

export interface AtendimentoLinha {
  id: string;
  data_atendimento: string | null;
  data_agendada: string | null;
  tipo: string;
  situacao: string;
  aso_resultado: string | null;
  colaborador: string | null;
  cpf: string | null;
  empresa_id: string | null;
  empresa: string | null;
  funcao: string | null;
  profissional: string | null;
  qtd_exames: number;
  total: number;
}

export interface Usuario {
  user_id: string;
  nome: string;
  email: string;
  papel: Papel;
  ativo: boolean;
  telefone: string | null;
  criado_em: string;
  ultimo_acesso: string | null;
  libera_agenda: boolean;
}

export interface PreCadastro {
  email: string;
  nome: string;
  cargo: string | null;
  papel: Papel;
  libera_agenda: boolean;
  rodizio_ordem: number | null;
  usado_em: string | null;
  cadastrado: boolean;
  telefone: string | null;
}

// ------------------------------------------------------------------ agenda

export type SituacaoAgendamento = "agendado" | "aguardando" | "atendido" | "finalizado" | "cancelado" | "faltou";

export interface AgendaRegras {
  limite_empresa_dia: number | null;
  bloquear_inadimplente: boolean;
  vagas_padrao: number;
  hora_inicio_padrao: string;
  hora_fim_padrao: string;
  pode_configurar: boolean;
  pode_excecao: boolean;
  liberam: string[];
  limites: { empresa_id: string; empresa: string; cnpj: string | null; limite: number; motivo: string | null }[];
}

export interface Profissional {
  id: string;
  nome: string;
  tipo: string;
  conselho: string | null;
  registro: string | null;
  ativo: boolean;
}

export interface AgendaLinha {
  id: string;
  data: string;
  profissional_id: string | null;
  profissional: string | null;
  local: "clinica" | "in_company";
  empresa_id: string | null;
  empresa: string | null;
  hora_inicio: string | null;
  hora_fim: string | null;
  vagas: number;
  ocupadas: number;
  encaixes: number;
  agendados: number;
  aguardando: number;
  atendidos: number;
  finalizados: number;
  faltas: number;
  cancelados: number;
  observacao: string | null;
}

export interface Agendamento {
  id: string;
  numero: number;
  agenda_id: string;
  horario: string | null;
  situacao: SituacaoAgendamento;
  tipo: string;
  paciente_nome: string;
  cpf: string | null;
  telefone: string | null;
  funcao: string | null;
  empresa_id: string | null;
  empresa: string | null;
  encaixe: boolean;
  inadimplente: boolean;
  excecao_motivo: string | null;
  cancelado_motivo: string | null;
  observacao: string | null;
  negocio_id: string | null;
  chegou_em: string | null;
  atendido_em: string | null;
  finalizado_em: string | null;
  criado_por: string | null;
  criado_em: string;
  complementares: string[];
}

export interface ChecagemAgenda {
  vagas: number;
  ocupadas: number;
  empresa_no_dia: number;
  limite_empresa_dia: number | null;
  limite_proprio?: boolean;
  inadimplente: boolean;
  bloqueios: string[];
  avisos: string[];
}

// ------------------------------------------------------------------ tarefas (Fluxo de Trabalho)

export type StatusTarefa = "nao_iniciado" | "em_andamento" | "parado" | "feito";
export type PrioridadeTarefa = "baixa" | "media" | "alta" | "critica";

export interface QuadroTarefas {
  id: string;
  nome: string;
  descricao: string | null;
  abertas: number;
  atrasadas: number;
}

export interface TarefaLinha {
  id: string;
  numero: number;
  titulo: string;
  status: StatusTarefa;
  prioridade: PrioridadeTarefa;
  prazo: string | null;
  responsavel_id: string | null;
  responsavel_nome: string | null;
  /** 0077: todos os responsáveis (o primeiro é o principal) */
  responsaveis: { id: string; nome: string }[];
  criado_por_nome: string | null;
  notas: string | null;
  empresa_id: string | null;
  empresa: string | null;
  negocio_id: string | null;
  ordem: number;
  itens: number;
  itens_feitos: number;
  comentarios: number;
  atrasada: boolean;
  criado_em: string;
  concluida_em: string | null;
}

export interface TarefaDetalhe {
  id: string;
  numero: number;
  quadro_id: string;
  titulo: string;
  status: StatusTarefa;
  prioridade: PrioridadeTarefa;
  prazo: string | null;
  responsavel_id: string | null;
  responsavel_nome: string | null;
  responsaveis: { id: string; nome: string }[];
  notas: string | null;
  empresa_id: string | null;
  empresa: string | null;
  negocio_id: string | null;
  criado_por_nome: string | null;
  criado_em: string;
  concluida_em: string | null;
  pode_excluir: boolean;
  itens: { id: string; texto: string; feito: boolean }[];
  comentarios: { id: number; texto: string; sistema: boolean; autor: string; criado_em: string }[];
}

// ------------------------------------------------------------------ contratos

export type StatusContrato = "rascunho" | "revisao" | "enviado" | "parcial" | "assinado" | "cancelado";
export type SituacaoContrato = "em_assinatura" | "vigente" | "a_renovar" | "vencido" | "cancelado";

export interface ContratoLinha {
  id: string;
  numero: number;
  titulo: string;
  empresa_id: string | null;
  cliente: string | null;
  status: StatusContrato;
  situacao: SituacaoContrato;
  inicio: string | null;
  fim: string | null;
  dias_para_vencer: number | null;
  valor_mensal: number | null;
  valor_total: number;
  responsavel_id: string | null;
  responsavel_nome: string | null;
  tem_arquivo: boolean;
  negocio_id: string | null;
  renovacao_negocio_id: string | null;
  atualizado_em: string;
}

export interface ContratosResumo {
  vigentes: number;
  a_renovar: number;
  vencidos: number;
  em_assinatura: number;
  receita_mensal: number;
}

export interface ContratoDetalhe {
  id: string;
  numero: number;
  titulo: string;
  empresa_id: string | null;
  cliente_nome: string | null;
  cliente: string | null;
  cnpj: string | null;
  negocio_id: string | null;
  negocio_numero: number | null;
  status: StatusContrato;
  situacao: SituacaoContrato;
  inicio: string | null;
  fim: string | null;
  renovacao_automatica: boolean;
  aviso_dias: number;
  valor_mensal: number | null;
  valor_total: number;
  dia_vencimento: number | null;
  forma_pagamento: string | null;
  indice_reajuste: string | null;
  responsavel_id: string | null;
  responsavel_nome: string | null;
  observacao: string | null;
  arquivo_path: string | null;
  arquivo_nome: string | null;
  assinado_em: string | null;
  cancelado_motivo: string | null;
  renovacao_negocio_id: string | null;
  criado_em: string;
  atualizado_em: string;
  itens: { id: string; produto_id: string | null; descricao: string; quantidade: number; preco: number; total: number }[];
  eventos: { texto: string; autor: string; criado_em: string }[];
}

// ------------------------------------------------------------------ financeiro

export type SituacaoCobranca = "aberta" | "vencida" | "paga" | "cancelada";

export interface FinResumo {
  competencia: string;
  previsto: number;
  recebido: number;
  a_receber: number;
  vencido_total: number;
  qtd_vencidas: number;
  empresas_inadimplentes: number;
  tolerancia_dias: number;
  contratos_sem_cobranca: number;
}

export interface Cobranca {
  id: string;
  numero: number;
  empresa_id: string | null;
  cliente: string | null;
  cnpj: string | null;
  contrato_id: string | null;
  contrato_numero: number | null;
  descricao: string;
  competencia: string;
  vencimento: string;
  valor: number;
  valor_pago: number | null;
  pago_em: string | null;
  forma: string | null;
  nota_fiscal: string | null;
  boleto: string | null;
  observacao: string | null;
  situacao: SituacaoCobranca;
  dias_atraso: number;
  origem: string;
  encargos: number;
}

// ------------------------------------------------------------------ documentos técnicos

export interface DocumentoLinha {
  id: string;
  empresa_id: string;
  empresa: string;
  cnpj: string | null;
  tipo: string;
  versao: string | null;
  data_elaboracao: string | null;
  vigencia_inicio: string | null;
  vigencia_fim: string | null;
  dias_para_vencer: number | null;
  situacao: "em_elaboracao" | "vigente" | "a_vencer" | "vencido" | "cancelado";
  situacao_cadastro: string;
  responsavel_id: string | null;
  responsavel: string | null;
  arquivo_path: string | null;
  observacao: string | null;
  origem: string;
  renovacao_negocio_id: string | null;
}

export interface DocumentosResumo {
  vigentes: number;
  a_vencer: number;
  vencidos: number;
  em_elaboracao: number;
  aviso_dias: number;
  pode_editar: boolean;
}

// ------------------------------------------------------------------ WhatsApp (Exemplo Connect)

export interface WaResumo {
  contatos: number;
  novos_7d: number;
  sem_negocio: number;
  com_negocio: number;
  humano: number;
  ativos_24h: number;
  ultimo_recebimento: string | null;
  integracao_ativa: boolean;
  token_gerado_em: string | null;
  criar_negocio: boolean;
  inbox_url: string;
  funil_id: string | null;
  funil_nome: string | null;
  pode_configurar: boolean;
  pode_criar_negocio: boolean;
}

export interface WaContato {
  id: string;
  nome: string | null;
  telefone: string | null;
  status: string | null;
  ultima_mensagem: string | null;
  ultima_direcao: "in" | "out" | null;
  ultima_em: string | null;
  mensagens: number;
  primeiro_em: string;
  ignorado: boolean;
  ext_lead_id: string;
  ext_conversa_id: string | null;
  empresa_id: string | null;
  empresa: string | null;
  negocio_id: string | null;
  negocio_numero: number | null;
  negocio_etapa: string | null;
  negocio_etapa_tipo: "aberta" | "ganho" | "perdido" | null;
  funil_slug: string | null;
  responsavel: string | null;
}

export interface WaModelo {
  id: string;
  titulo: string;
  categoria: "geral" | "comercial" | "agendamento" | "exames" | "cobranca" | "documentos";
  texto: string;
  ativo: boolean;
  ordem: number;
}

export interface WaContexto {
  inbox_url: string;
  atendente: string | null;
  contato: { id: string; nome: string | null; telefone: string | null; ext_lead_id: string; ext_conversa_id: string | null } | null;
}

export interface EdicaoHistorico {
  em: string;
  acao: "criar" | "editar" | "excluir" | "liberar";
  usuario: string | null;
  mudancas: Record<string, unknown>;
}

export interface ContatoEmpresa {
  id: string;
  nome: string | null;
  cargo: string | null;
  email: string | null;
  telefone: string | null;
  tipo: string | null;
  recebe_alerta_exame: boolean;
  origem: string;
}

export interface UnidadeEmpresa {
  id: string;
  nome: string;
  cnpj: string | null;
  cidade: string | null;
  uf: string | null;
  endereco: string | null;
  cnae: string | null;
  grau_risco: number | null;
  is_matriz: boolean | null;
  ativa: boolean;
  editado: boolean;
  campos_editados: string[];
  setores: number;
  colaboradores: number;
}

export interface ColaboradorLinha {
  id: string;
  nome: string;
  cpf: string | null;
  unidade: string | null;
  setor: string | null;
  funcao: string | null;
  data_admissao: string | null;
  data_demissao: string | null;
  situacao: string;
  editado: boolean;
  ultimo_atendimento: string | null;
  total: number;
}

export interface ColaboradorDetalhe {
  id: string;
  empresa_id: string;
  empresa: string;
  unidade_id: string | null;
  unidade: string | null;
  setor_nome: string | null;
  funcao_nome: string | null;
  sesmo_id: string | null;
  nome: string;
  nome_social: string | null;
  cpf: string | null;
  rg: string | null;
  rg_orgao_emissor: string | null;
  data_nascimento: string | null;
  sexo: string | null;
  nome_mae: string | null;
  pis: string | null;
  matricula_esocial: string | null;
  ctps: string | null;
  data_admissao: string | null;
  data_demissao: string | null;
  situacao: string;
  telefone: string | null;
  email: string | null;
  origem: string;
  campos_editados: string[];
  atendimentos: { id: string; data: string | null; tipo: string; situacao: string; aso_resultado: string }[];
  historico: EdicaoHistorico[];
  pode_editar: boolean;
}

export interface AtendimentoDetalhe {
  id: string;
  sesmo_id: string | null;
  tipo: string;
  situacao: string;
  data_agendada: string | null;
  data_atendimento: string | null;
  hora: string | null;
  aso_resultado: string;
  aso_emitido_em: string | null;
  profissional_id: string | null;
  profissional: string | null;
  local_atendimento: string | null;
  observacao: string | null;
  origem: string;
  colaborador_id: string;
  colaborador: string;
  cpf: string | null;
  empresa_id: string;
  empresa: string;
  funcao: string | null;
  campos_editados: string[];
  exames: { nome: string; data: string | null; resultado: string | null }[];
  historico: EdicaoHistorico[];
  pode_editar: boolean;
}

// ---------------------------------------------------------------- chat interno (0054)

export interface ChatSala {
  id: string;
  tipo: "geral" | "grupo" | "direto";
  nome: string | null;
  descricao: string | null;
  membros: number;
  ultima_texto: string | null;
  ultima_autor: string | null;
  ultima_em: string | null;
  nao_lidas: number;
  dono: boolean;
  outro_id: string | null;
}

export type ChatAnexoTipo = "imagem" | "audio" | "arquivo";

export interface ChatMensagem {
  id: number;
  autor_id: string | null;
  autor: string | null;
  texto: string | null;
  /** 0075: texto é só o rótulo do anexo ("📷 Imagem"), não mostrar embaixo dele */
  texto_auto: boolean;
  criado_em: string;
  excluida: boolean;
  minha: boolean;
  anexo_path: string | null;
  anexo_tipo: ChatAnexoTipo | null;
  anexo_nome: string | null;
  anexo_mime: string | null;
  anexo_tamanho: number | null;
  anexo_duracao: number | null;
}

export interface ChatSalaDetalhe {
  id: string;
  tipo: ChatSala["tipo"];
  nome: string | null;
  descricao: string | null;
  pode_editar: boolean;
  membros: { user_id: string; nome: string; dono: boolean }[];
}

export interface ChatPessoa {
  user_id: string;
  nome: string;
  papel: string;
  cargo: string | null;
}
