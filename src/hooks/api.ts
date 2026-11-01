import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { rpc, supabase } from "@/lib/supabase";
import type {
  PreCadastro,
  WaContato,
  WaContexto,
  WaModelo,
  WaResumo,
  DocumentoLinha,
  DocumentosResumo,
  Cobranca,
  FinResumo,
  ContratoDetalhe,
  ContratoLinha,
  ContratosResumo,
  QuadroTarefas,
  TarefaDetalhe,
  TarefaLinha,
  AgendaLinha,
  AgendaRegras,
  Agendamento,
  ChecagemAgenda,
  Profissional,
  AtendimentoLinha,
  AtendimentoDetalhe,
  ChatAnexoTipo,
  ChatMensagem,
  ChatPessoa,
  ChatSala,
  ChatSalaDetalhe,
  ColaboradorDetalhe,
  ColaboradorLinha,
  CardNegocio,
  ClienteDetalhe,
  ClienteLinha,
  EmpresaBusca,
  Funil,
  Negocio,
  Notificacao,
  Pendencia,
  Produto,
  Responsavel,
  Resumo,
  Usuario,
  VencimentoLinha,
} from "@/lib/tipos";

/** Chaves num lugar só: invalidar é previsível. */
export const chaves = {
  resumo: ["resumo"] as const,
  funis: ["crm", "funis"] as const,
  quadro: (funil: string, resp: string | null, busca: string, dias = 30, de: string | null = null, ate: string | null = null) =>
    ["crm", "quadro", funil, resp, busca, dias, de, ate] as const,
  negocio: (id: string) => ["crm", "negocio", id] as const,
  pendencias: (minhas: boolean) => ["crm", "pendencias", minhas] as const,
  responsaveis: ["crm", "responsaveis"] as const,
  produtos: (todos: boolean) => ["crm", "produtos", todos] as const,
  rodizio: (funil: string) => ["crm", "rodizio", funil] as const,
  notificacoes: ["notificacoes"] as const,
  naoLidas: ["notificacoes", "nao-lidas"] as const,
  clientes: (busca: string, situacao: string | null, pagina: number) => ["clientes", busca, situacao, pagina] as const,
  cliente: (id: string) => ["cliente", id] as const,
  empresas: (q: string) => ["empresas-busca", q] as const,
  vencimentos: (f: object) => ["vencimentos", f] as const,
  atendimentos: (f: object) => ["atendimentos", f] as const,
  usuarios: ["usuarios"] as const,
  agendaRegras: ["agenda", "regras"] as const,
  profissionais: ["agenda", "profissionais"] as const,
  agendaPeriodo: (de: string, ate: string) => ["agenda", "periodo", de, ate] as const,
  agendaDia: (data: string) => ["agenda", "dia", data] as const,
  agendaChecar: (agenda: string, empresa: string | null, encaixe: boolean, ignorar: string | null) =>
    ["agenda", "checar", agenda, empresa, encaixe, ignorar] as const,
  agendamentoHistorico: (id: string) => ["agenda", "historico", id] as const,
};

const erroToast = (e: unknown) => toast.error(e instanceof Error ? e.message : "Não foi possível salvar.");

// ------------------------------------------------------------------ leitura

export const useResumo = () => useQuery({ queryKey: chaves.resumo, queryFn: () => rpc<Resumo>("painel_resumo"), staleTime: 60_000 });

export const useFunis = () => useQuery({ queryKey: chaves.funis, queryFn: () => rpc<Funil[]>("painel_crm_funis"), staleTime: 5 * 60_000 });

export const useQuadro = (funil: string | undefined, responsavel: string | null, busca: string, diasFechados = 30, de: string | null = null, ate: string | null = null) =>
  useQuery({
    queryKey: chaves.quadro(funil ?? "", responsavel, busca, diasFechados, de, ate),
    queryFn: () =>
      rpc<CardNegocio[]>("painel_crm_quadro_v3", {
        p_funil: funil,
        p_responsavel: responsavel,
        p_busca: busca || null,
        p_dias_fechados: diasFechados,
        p_de: de || null,
        p_ate: ate || null,
      }),
    enabled: !!funil,
    placeholderData: keepPreviousData,
    refetchInterval: 60_000,
  });

export const useNegocio = (id: string | null) =>
  useQuery({ queryKey: chaves.negocio(id ?? ""), queryFn: () => rpc<Negocio>("painel_crm_negocio", { p_id: id }), enabled: !!id });

export const usePendencias = (minhas: boolean) =>
  useQuery({ queryKey: chaves.pendencias(minhas), queryFn: () => rpc<Pendencia[]>("painel_crm_pendencias", { p_so_minhas: minhas }) });

export const useResponsaveis = () =>
  useQuery({ queryKey: chaves.responsaveis, queryFn: () => rpc<Responsavel[]>("painel_crm_responsaveis"), staleTime: 5 * 60_000 });

export const useProdutos = (todos = false) =>
  useQuery({ queryKey: chaves.produtos(todos), queryFn: () => rpc<Produto[]>("painel_crm_produtos", { p_todos: todos }), staleTime: 5 * 60_000 });

export const useRodizio = (funil: string | undefined) =>
  useQuery({
    queryKey: chaves.rodizio(funil ?? ""),
    queryFn: () => rpc<{ user_id: string; nome: string; ordem: number; ativo: boolean; proximo: boolean }[]>("painel_crm_rodizio", { p_funil: funil }),
    enabled: !!funil,
  });

export const useNotificacoes = (aberto: boolean) =>
  useQuery({ queryKey: chaves.notificacoes, queryFn: () => rpc<Notificacao[]>("painel_notificacoes", { p_limite: 30 }), enabled: aberto });

export const useNaoLidas = () =>
  useQuery({ queryKey: chaves.naoLidas, queryFn: () => rpc<number>("painel_notificacoes_nao_lidas"), refetchInterval: 60_000 });

export const useClientes = (busca: string, situacao: string | null, pagina: number, porPagina = 50) =>
  useQuery({
    queryKey: chaves.clientes(busca, situacao, pagina),
    queryFn: () =>
      rpc<ClienteLinha[]>("painel_clientes", { p_busca: busca || null, p_situacao: situacao, p_limite: porPagina, p_offset: pagina * porPagina }),
    placeholderData: keepPreviousData,
  });

export const useCliente = (id: string | undefined) =>
  useQuery({ queryKey: chaves.cliente(id ?? ""), queryFn: () => rpc<ClienteDetalhe>("painel_cliente", { p_id: id }), enabled: !!id });

export const useBuscaEmpresas = (q: string) =>
  useQuery({
    queryKey: chaves.empresas(q),
    queryFn: () => rpc<EmpresaBusca[]>("painel_empresas_buscar", { p_busca: q }),
    enabled: q.trim().length >= 2,
    staleTime: 60_000,
  });

export interface FiltroVencimentos {
  empresa: string | null;
  status: string | null;
  busca: string;
  pagina: number;
}
export const useVencimentos = (f: FiltroVencimentos, porPagina = 100) =>
  useQuery({
    queryKey: chaves.vencimentos(f),
    queryFn: () =>
      rpc<VencimentoLinha[]>("painel_vencimentos", {
        p_empresa: f.empresa,
        p_status: f.status,
        p_busca: f.busca || null,
        p_limite: porPagina,
        p_offset: f.pagina * porPagina,
      }),
    placeholderData: keepPreviousData,
  });

export interface FiltroAtendimentos {
  empresa: string | null;
  de: string | null;
  ate: string | null;
  situacao: string | null;
  busca: string;
  pagina: number;
}
export const useAtendimentos = (f: FiltroAtendimentos, porPagina = 100) =>
  useQuery({
    queryKey: chaves.atendimentos(f),
    queryFn: () =>
      rpc<AtendimentoLinha[]>("painel_atendimentos", {
        p_empresa: f.empresa,
        p_de: f.de,
        p_ate: f.ate,
        p_situacao: f.situacao,
        p_busca: f.busca || null,
        p_limite: porPagina,
        p_offset: f.pagina * porPagina,
      }),
    placeholderData: keepPreviousData,
  });

export const useUsuarios = () => useQuery({ queryKey: chaves.usuarios, queryFn: () => rpc<Usuario[]>("painel_usuarios") });

// ------------------------------------------------------------------ escrita

function useInvalidaCrm() {
  const qc = useQueryClient();
  return (negocioId?: string) => {
    qc.invalidateQueries({ queryKey: ["crm", "quadro"] });
    qc.invalidateQueries({ queryKey: ["crm", "pendencias"] });
    qc.invalidateQueries({ queryKey: chaves.resumo });
    if (negocioId) qc.invalidateQueries({ queryKey: chaves.negocio(negocioId) });
  };
}

export interface NovoNegocio {
  p_funil: string;
  p_titulo: string;
  p_empresa_id?: string | null;
  p_cliente_nome?: string | null;
  p_cliente_cnpj?: string | null;
  p_contato_nome?: string | null;
  p_contato_telefone?: string | null;
  p_contato_email?: string | null;
  p_responsavel?: string | null;
  p_valor?: number;
  p_origem?: string;
  p_observacao?: string | null;
  p_previsao?: string | null;
}

/** 0076: criação com empresa obrigatória, parcelas e serviços do catálogo. */
export interface NovoNegocioV2 {
  dados: {
    funil: string;
    titulo?: string | null;
    empresa_id: string;
    contato_nome?: string | null;
    contato_telefone?: string | null;
    contato_email?: string | null;
    responsavel?: string | null;
    valor?: number | null;
    origem?: string;
    observacao?: string | null;
    previsao?: string | null;
    parcelas?: number | null;
    forma_pagamento?: string | null;
    desconto_pct?: number | null;
  };
  itens: { produto: string; quantidade: number; preco: number | null; desconto?: number }[];
}

export function useCriarNegocioV2() {
  const inv = useInvalidaCrm();
  return useMutation({
    mutationFn: (n: NovoNegocioV2) => rpc<string>("painel_crm_negocio_criar_v2", { p_dados: n.dados, p_itens: n.itens }),
    onSuccess: () => {
      inv();
      toast.success("Negócio criado");
    },
    onError: erroToast,
  });
}

export function useCriarNegocio() {
  const inv = useInvalidaCrm();
  return useMutation({
    mutationFn: (n: NovoNegocio) => rpc<string>("painel_crm_negocio_criar", { ...n }),
    onSuccess: () => {
      inv();
      toast.success("Negócio criado");
    },
    onError: erroToast,
  });
}

export function useMoverNegocio() {
  const inv = useInvalidaCrm();
  return useMutation({
    mutationFn: (v: { id: string; etapa: string; motivo?: string | null }) =>
      rpc<{ ok: boolean; cards_gerados?: number }>("painel_crm_negocio_mover", { p_id: v.id, p_etapa: v.etapa, p_motivo: v.motivo ?? null }),
    onSuccess: (r, v) => {
      inv(v.id);
      if (r?.cards_gerados) toast.success(`Negócio fechado. ${r.cards_gerados} card(s) aberto(s) nos funis seguintes.`);
    },
    onError: (e, v) => {
      inv(v.id);
      erroToast(e);
    },
  });
}

export function useAtualizarNegocio() {
  const inv = useInvalidaCrm();
  return useMutation({
    mutationFn: (v: { id: string; dados: Record<string, unknown> }) => rpc<void>("painel_crm_negocio_atualizar", { p_id: v.id, p_dados: v.dados }),
    onSuccess: (_r, v) => {
      inv(v.id);
      toast.success("Alterações salvas");
    },
    onError: erroToast,
  });
}

export function useRegistrarAtividade() {
  const inv = useInvalidaCrm();
  return useMutation({
    mutationFn: (v: { id: string; tipo: string; texto: string }) => rpc<void>("painel_crm_atividade", { p_id: v.id, p_tipo: v.tipo, p_texto: v.texto }),
    onSuccess: (_r, v) => inv(v.id),
    onError: erroToast,
  });
}

export function useAdicionarItem() {
  const inv = useInvalidaCrm();
  return useMutation({
    mutationFn: (v: { negocio: string; produto: string | null; descricao?: string | null; quantidade: number; preco?: number | null; desconto?: number | null }) =>
      rpc<string>("painel_crm_item_adicionar_v2", {
        p_negocio: v.negocio,
        p_produto: v.produto,
        p_descricao: v.descricao ?? null,
        p_quantidade: v.quantidade,
        p_preco: v.preco ?? null,
        p_desconto: v.desconto ?? 0,
      }),
    onSuccess: (_r, v) => inv(v.negocio),
    onError: erroToast,
  });
}

/** 0081: altera quantidade, preço e desconto (%) de um item */
export function useSalvarItem() {
  const inv = useInvalidaCrm();
  return useMutation({
    mutationFn: (v: { item: string; negocio: string; quantidade?: number; preco?: number; desconto?: number }) =>
      rpc<void>("painel_crm_item_salvar", { p_item: v.item, p_dados: { quantidade: v.quantidade, preco: v.preco, desconto: v.desconto } }),
    onSuccess: (_r, v) => inv(v.negocio),
    onError: erroToast,
  });
}

/** 0081: desconto geral (%) do card */
export function useDescontoNegocio() {
  const inv = useInvalidaCrm();
  return useMutation({
    mutationFn: (v: { negocio: string; pct: number }) => rpc<void>("painel_crm_negocio_desconto", { p_negocio: v.negocio, p_pct: v.pct }),
    onSuccess: (_r, v) => inv(v.negocio),
    onError: erroToast,
  });
}

export type LinhaDesconto = {
  negocio_id: string; numero: number; data: string; cliente: string | null; vendedor: string | null; etapa: string; servico: string;
  quantidade: number; preco_catalogo: number; preco_praticado: number; desconto_item: number; desconto_geral: number;
  total_catalogo: number; total_final: number; diferenca: number;
};
export const useRelatorioDescontos = (de: string, ate: string) =>
  useQuery({ queryKey: ["relatorio", "descontos", de, ate], queryFn: () => rpc<LinhaDesconto[]>("painel_relatorio_descontos", { p_de: de || null, p_ate: ate || null }) });

export function useRemoverItem() {
  const inv = useInvalidaCrm();
  return useMutation({
    mutationFn: (v: { item: string; negocio: string }) => rpc<void>("painel_crm_item_remover", { p_item: v.item }),
    onSuccess: (_r, v) => inv(v.negocio),
    onError: erroToast,
  });
}

export function useSalvarProduto() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (p: Partial<Produto> & { nome: string }) =>
      rpc<string>("painel_crm_produto_salvar", {
        p_id: p.id ?? null,
        p_nome: p.nome,
        p_descricao: p.descricao ?? null,
        p_categoria: p.categoria ?? null,
        p_preco: p.preco ?? null,
        p_unidade: p.unidade ?? "un",
        p_recorrente: p.recorrente ?? false,
        p_ativo: p.ativo ?? true,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["crm", "produtos"] });
      toast.success("Produto salvo");
    },
    onError: erroToast,
  });
}

export function useSalvarEtapa() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (e: { id: string | null; funil: string; nome: string; tipo: string; cor: string; alerta_dias: number | null; ativo: boolean }) =>
      rpc<string>("painel_crm_etapa_salvar", {
        p_id: e.id,
        p_funil: e.funil,
        p_nome: e.nome,
        p_tipo: e.tipo,
        p_cor: e.cor,
        p_alerta_dias: e.alerta_dias,
        p_ativo: e.ativo,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: chaves.funis });
      toast.success("Etapa salva");
    },
    onError: erroToast,
  });
}

export function useReordenarEtapas() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { funil: string; ids: string[] }) => rpc<void>("painel_crm_etapas_reordenar", { p_funil: v.funil, p_ids: v.ids }),
    onSuccess: () => qc.invalidateQueries({ queryKey: chaves.funis }),
    onError: erroToast,
  });
}

export function useSalvarRodizio() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { funil: string; users: string[] }) => rpc<void>("painel_crm_rodizio_salvar", { p_funil: v.funil, p_users: v.users }),
    onSuccess: (_r, v) => {
      qc.invalidateQueries({ queryKey: chaves.rodizio(v.funil) });
      toast.success("Rodízio salvo");
    },
    onError: erroToast,
  });
}

export function useMarcarLidas() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: number | null) => rpc<void>("painel_notificacoes_marcar_lidas", { p_id: id }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["notificacoes"] }),
  });
}

export function useSalvarUsuario() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (u: { user_id: string; papel: string; ativo: boolean; nome?: string }) =>
      rpc<void>("painel_usuario_salvar", { p_user_id: u.user_id, p_papel: u.papel, p_ativo: u.ativo, p_nome: u.nome ?? null, p_telefone: null }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: chaves.usuarios });
      qc.invalidateQueries({ queryKey: chaves.responsaveis });
      toast.success("Acesso atualizado");
    },
    onError: erroToast,
  });
}

/** 0078: excluir conta (só sem histórico) ou trocar o e-mail de login — Edge Function usuario-admin. */
export function useUsuarioAdmin() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { acao: "excluir" | "trocar_email"; user_id: string; email?: string }) => {
      const { data, error } = await supabase.functions.invoke(((import.meta.env.VITE_FUNCTIONS_PREFIX as string | undefined) ?? "") + "usuario-admin", { body: v });
      if (error) {
        let msg = error.message;
        try {
          const corpo = await (error as { context?: Response }).context?.json();
          if (corpo?.erro) msg = corpo.erro;
        } catch {
          /* resposta sem JSON */
        }
        throw new Error(msg);
      }
      return data as { ok: boolean };
    },
    onSuccess: (_r, v) => {
      qc.invalidateQueries({ queryKey: chaves.usuarios });
      qc.invalidateQueries({ queryKey: chaves.responsaveis });
      toast.success(v.acao === "excluir" ? "Conta excluída" : "E-mail de acesso atualizado");
    },
    onError: erroToast,
  });
}

export function useTelefoneUsuario() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (u: { user_id: string; telefone: string }) => rpc<void>("painel_usuario_telefone", { p_user: u.user_id, p_telefone: u.telefone }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: chaves.usuarios });
      toast.success("WhatsApp salvo");
    },
    onError: (e) => {
      qc.invalidateQueries({ queryKey: chaves.usuarios });
      erroToast(e);
    },
  });
}

// ------------------------------------------------------------------ agenda

export const useAgendaRegras = () =>
  useQuery({ queryKey: chaves.agendaRegras, queryFn: () => rpc<AgendaRegras>("painel_agenda_regras"), staleTime: 5 * 60_000 });

/** Vagas por horário da grade numa agenda (0079). `p_ignorar` = o próprio agendamento, ao editar. */
export type HorarioGrade = { horario: string; vagas: number; ocupadas: number; livres: number };
export const useAgendaHorarios = (agenda: string | null, ignorar: string | null) =>
  useQuery({
    queryKey: ["agenda", "horarios", agenda, ignorar],
    queryFn: () => rpc<{ pode_encaixe: boolean; horarios: HorarioGrade[] }>("painel_agenda_horarios", { p_agenda: agenda, p_ignorar: ignorar }),
    enabled: !!agenda,
    refetchInterval: 30_000,
  });

export const useAgendaGrade = () =>
  useQuery({ queryKey: ["agenda", "grade"], queryFn: () => rpc<{ horario: string; vagas: number }[]>("painel_agenda_grade"), staleTime: 60_000 });

export function useSalvarGrade() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (grade: { horario: string; vagas: number }[]) => rpc<unknown>("painel_agenda_grade_salvar", { p_grade: grade }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["agenda"] });
      toast.success("Grade de horários salva");
    },
    onError: erroToast,
  });
}

export const useProfissionais = () =>
  useQuery({ queryKey: chaves.profissionais, queryFn: () => rpc<Profissional[]>("painel_profissionais"), staleTime: 10 * 60_000 });

export const useAgendaPeriodo = (de: string, ate: string) =>
  useQuery({
    queryKey: chaves.agendaPeriodo(de, ate),
    queryFn: () => rpc<AgendaLinha[]>("painel_agenda_periodo", { p_de: de, p_ate: ate }),
    placeholderData: keepPreviousData,
    refetchInterval: 30_000,
  });

/** Recepção: a lista do dia se atualiza sozinha (outra pessoa pode estar marcando chegadas). */
export const useAgendaDia = (data: string) =>
  useQuery({
    queryKey: chaves.agendaDia(data),
    queryFn: () => rpc<Agendamento[]>("painel_agenda_dia", { p_data: data, p_agenda: null }),
    placeholderData: keepPreviousData,
    refetchInterval: 20_000,
  });

export const useAgendaChecar = (agenda: string | null, empresa: string | null, encaixe: boolean, ignorar: string | null, tipo: string | null = null) =>
  useQuery({
    queryKey: [...chaves.agendaChecar(agenda ?? "", empresa, encaixe, ignorar), tipo],
    queryFn: () => rpc<ChecagemAgenda>("painel_agendamento_checar", { p_agenda: agenda, p_empresa: empresa, p_encaixe: encaixe, p_ignorar: ignorar, p_tipo: tipo }),
    enabled: !!agenda,
    staleTime: 0,
  });

export const useAgendamentoHistorico = (id: string | null) =>
  useQuery({
    queryKey: chaves.agendamentoHistorico(id ?? ""),
    queryFn: () => rpc<{ texto: string; autor: string; criado_em: string }[]>("painel_agendamento_historico", { p_id: id }),
    enabled: !!id,
  });

function useInvalidaAgenda() {
  const qc = useQueryClient();
  return () => qc.invalidateQueries({ queryKey: ["agenda"] });
}

export function useSalvarAgenda() {
  const inv = useInvalidaAgenda();
  return useMutation({
    mutationFn: (v: { id: string | null; dados: Record<string, unknown> }) => rpc<string>("painel_agenda_salvar", { p_id: v.id, p_dados: v.dados }),
    onSuccess: (_r, v) => {
      inv();
      toast.success(v.id ? "Agenda atualizada" : "Agenda criada");
    },
    onError: erroToast,
  });
}

export function useExcluirAgenda() {
  const inv = useInvalidaAgenda();
  return useMutation({
    mutationFn: (id: string) => rpc<void>("painel_agenda_excluir", { p_id: id }),
    onSuccess: () => {
      inv();
      toast.success("Agenda excluída");
    },
    onError: erroToast,
  });
}

export function useSalvarAgendamento() {
  const inv = useInvalidaAgenda();
  return useMutation({
    mutationFn: (v: { id: string | null; dados: Record<string, unknown> }) =>
      rpc<{ id: string; avisos: string[] }>("painel_agendamento_salvar", { p_id: v.id, p_dados: v.dados }),
    onSuccess: (r, v) => {
      inv();
      toast.success(v.id ? "Agendamento atualizado" : "Paciente agendado", r?.avisos?.length ? { description: r.avisos.join(" ") } : undefined);
    },
    onError: erroToast,
  });
}

export function useSituacaoAgendamento() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { id: string; situacao: string; motivo?: string | null; data: string }) =>
      rpc<void>("painel_agendamento_situacao", { p_id: v.id, p_situacao: v.situacao, p_motivo: v.motivo ?? null }),
    // Otimista: na recepção o clique tem que responder na hora.
    onMutate: async (v) => {
      const chave = chaves.agendaDia(v.data);
      await qc.cancelQueries({ queryKey: chave });
      const antes = qc.getQueryData<Agendamento[]>(chave);
      qc.setQueryData<Agendamento[]>(chave, (l) => l?.map((a) => (a.id === v.id ? { ...a, situacao: v.situacao as Agendamento["situacao"] } : a)));
      return { antes, chave };
    },
    onError: (e, _v, ctx) => {
      if (ctx?.antes) qc.setQueryData(ctx.chave, ctx.antes);
      erroToast(e);
    },
    onSettled: () => qc.invalidateQueries({ queryKey: ["agenda"] }),
  });
}

export function useSalvarRegrasAgenda() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (dados: Record<string, unknown>) => rpc<void>("painel_agenda_regras_salvar", { p_dados: dados }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["agenda"] });
      toast.success("Regras da agenda salvas");
    },
    onError: erroToast,
  });
}

// ------------------------------------------------------------------ tarefas (Fluxo de Trabalho)

export const useQuadrosTarefas = () =>
  useQuery({ queryKey: ["tarefas", "quadros"], queryFn: () => rpc<QuadroTarefas[]>("painel_tarefas_quadros"), staleTime: 60_000 });

export const useTarefas = (quadro: string | undefined, responsavel: string | null, busca: string) =>
  useQuery({
    queryKey: ["tarefas", "lista", quadro ?? "", responsavel, busca],
    queryFn: () => rpc<TarefaLinha[]>("painel_tarefas_v2", { p_quadro: quadro, p_responsavel: responsavel, p_busca: busca || null }),
    enabled: !!quadro,
    placeholderData: keepPreviousData,
    refetchInterval: 60_000,
  });

export const useTarefa = (id: string | null) =>
  useQuery({ queryKey: ["tarefas", "detalhe", id ?? ""], queryFn: () => rpc<TarefaDetalhe>("painel_tarefa", { p_id: id }), enabled: !!id });

export const useMinhasTarefas = () =>
  useQuery({
    queryKey: ["tarefas", "minhas"],
    queryFn: () =>
      rpc<{ id: string; quadro_id: string; quadro: string; titulo: string; status: string; prioridade: string; prazo: string | null; atrasada: boolean }[]>(
        "painel_minhas_tarefas",
      ),
  });

function useInvalidaTarefas() {
  const qc = useQueryClient();
  return () => qc.invalidateQueries({ queryKey: ["tarefas"] });
}

export function useSalvarTarefa() {
  const inv = useInvalidaTarefas();
  return useMutation({
    mutationFn: (v: { id: string | null; dados: Record<string, unknown> }) => rpc<string>("painel_tarefa_salvar", { p_id: v.id, p_dados: v.dados }),
    onSuccess: () => inv(),
    onError: erroToast,
  });
}

export function useMoverTarefa() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { id: string; status: string; ordem: number | null }) => rpc<void>("painel_tarefa_mover", { p_id: v.id, p_status: v.status, p_ordem: v.ordem }),
    // Otimista: o card já fica onde foi solto.
    onMutate: async (v) => {
      await qc.cancelQueries({ queryKey: ["tarefas", "lista"] });
      const antes = qc.getQueriesData<TarefaLinha[]>({ queryKey: ["tarefas", "lista"] });
      qc.setQueriesData<TarefaLinha[]>({ queryKey: ["tarefas", "lista"] }, (l) =>
        l?.map((t) => (t.id === v.id ? { ...t, status: v.status as TarefaLinha["status"], ordem: v.ordem ?? t.ordem } : t)),
      );
      return { antes };
    },
    onError: (e, _v, ctx) => {
      ctx?.antes.forEach(([k, d]) => qc.setQueryData(k, d));
      erroToast(e);
    },
    onSettled: () => qc.invalidateQueries({ queryKey: ["tarefas"] }),
  });
}

export function useExcluirTarefa() {
  const inv = useInvalidaTarefas();
  return useMutation({
    mutationFn: (id: string) => rpc<void>("painel_tarefa_excluir", { p_id: id }),
    onSuccess: () => {
      inv();
      toast.success("Tarefa excluída");
    },
    onError: erroToast,
  });
}

export function useItemTarefa() {
  const inv = useInvalidaTarefas();
  return useMutation({
    mutationFn: (v: { tarefa: string; id: string | null; texto: string | null; feito: boolean | null }) =>
      rpc<string>("painel_tarefa_item_salvar", { p_tarefa: v.tarefa, p_id: v.id, p_texto: v.texto, p_feito: v.feito }),
    onSuccess: () => inv(),
    onError: erroToast,
  });
}

export function useExcluirItemTarefa() {
  const inv = useInvalidaTarefas();
  return useMutation({ mutationFn: (id: string) => rpc<void>("painel_tarefa_item_excluir", { p_id: id }), onSuccess: () => inv(), onError: erroToast });
}

export function useComentarTarefa() {
  const inv = useInvalidaTarefas();
  return useMutation({
    mutationFn: (v: { id: string; texto: string }) => rpc<void>("painel_tarefa_comentar", { p_id: v.id, p_texto: v.texto }),
    onSuccess: () => inv(),
    onError: erroToast,
  });
}

export function useSalvarQuadroTarefas() {
  const inv = useInvalidaTarefas();
  return useMutation({
    mutationFn: (v: { id: string | null; nome: string; descricao?: string | null }) =>
      rpc<string>("painel_tarefa_quadro_salvar", { p_id: v.id, p_nome: v.nome, p_descricao: v.descricao ?? null }),
    onSuccess: () => {
      inv();
      toast.success("Quadro salvo");
    },
    onError: erroToast,
  });
}

// ------------------------------------------------------------------ contratos

export const useContratosResumo = () =>
  useQuery({ queryKey: ["contratos", "resumo"], queryFn: () => rpc<ContratosResumo>("painel_contratos_resumo") });

export const useContratos = (busca: string, situacao: string | null) =>
  useQuery({
    queryKey: ["contratos", "lista", busca, situacao],
    queryFn: () => rpc<ContratoLinha[]>("painel_contratos", { p_busca: busca || null, p_situacao: situacao }),
    placeholderData: keepPreviousData,
  });

export const useContrato = (id: string | null) =>
  useQuery({ queryKey: ["contratos", "detalhe", id ?? ""], queryFn: () => rpc<ContratoDetalhe>("painel_contrato", { p_id: id }), enabled: !!id });

function useInvalidaContratos() {
  const qc = useQueryClient();
  return () => {
    qc.invalidateQueries({ queryKey: ["contratos"] });
    qc.invalidateQueries({ queryKey: ["crm"] });
  };
}

export function useSalvarContrato() {
  const inv = useInvalidaContratos();
  return useMutation({
    mutationFn: (v: { id: string | null; dados: Record<string, unknown> }) => rpc<string>("painel_contrato_salvar", { p_id: v.id, p_dados: v.dados }),
    onSuccess: (_r, v) => {
      inv();
      toast.success(v.id ? "Contrato atualizado" : "Contrato criado");
    },
    onError: erroToast,
  });
}

export function useStatusContrato() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { id: string; status: string; motivo?: string | null }) => rpc<void>("painel_contrato_status", { p_id: v.id, p_status: v.status, p_motivo: v.motivo ?? null }),
    onMutate: async (v) => {
      await qc.cancelQueries({ queryKey: ["contratos", "lista"] });
      const antes = qc.getQueriesData<ContratoLinha[]>({ queryKey: ["contratos", "lista"] });
      qc.setQueriesData<ContratoLinha[]>({ queryKey: ["contratos", "lista"] }, (l) => l?.map((c) => (c.id === v.id ? { ...c, status: v.status as ContratoLinha["status"] } : c)));
      return { antes };
    },
    onError: (e, _v, ctx) => {
      ctx?.antes.forEach(([k, d]) => qc.setQueryData(k, d));
      erroToast(e);
    },
    onSettled: () => qc.invalidateQueries({ queryKey: ["contratos"] }),
  });
}

export function useItemContrato() {
  const inv = useInvalidaContratos();
  return useMutation({
    mutationFn: (v: { contrato: string; produto: string | null; descricao: string | null; quantidade: number; preco: number | null }) =>
      rpc<string>("painel_contrato_item_adicionar", { p_contrato: v.contrato, p_produto: v.produto, p_descricao: v.descricao, p_quantidade: v.quantidade, p_preco: v.preco }),
    onSuccess: () => inv(),
    onError: erroToast,
  });
}

export function useRemoverItemContrato() {
  const inv = useInvalidaContratos();
  return useMutation({ mutationFn: (id: string) => rpc<void>("painel_contrato_item_remover", { p_item: id }), onSuccess: () => inv(), onError: erroToast });
}

/** Sobe o PDF para o Storage (bucket privado) e grava o caminho no contrato. */
export function useArquivoContrato() {
  const inv = useInvalidaContratos();
  return useMutation({
    mutationFn: async (v: { contrato: string; arquivo: File | null; caminhoAtual: string | null }) => {
      if (v.caminhoAtual) await supabase.storage.from(((import.meta.env.VITE_STORAGE_PREFIX as string | undefined) ?? "") + "crm-arquivos").remove([v.caminhoAtual]);
      if (!v.arquivo) return rpc<void>("painel_contrato_arquivo", { p_id: v.contrato, p_path: null, p_nome: null });
      const limpo = v.arquivo.name.normalize("NFD").replace(/[^\w.-]+/g, "_");
      const caminho = `contratos/${v.contrato}/${Date.now()}-${limpo}`;
      const { error } = await supabase.storage.from(((import.meta.env.VITE_STORAGE_PREFIX as string | undefined) ?? "") + "crm-arquivos").upload(caminho, v.arquivo, { contentType: v.arquivo.type || "application/pdf" });
      if (error) throw new Error(`Não foi possível enviar o arquivo: ${error.message}`);
      return rpc<void>("painel_contrato_arquivo", { p_id: v.contrato, p_path: caminho, p_nome: v.arquivo.name });
    },
    onSuccess: (_r, v) => {
      inv();
      toast.success(v.arquivo ? "Arquivo anexado" : "Arquivo removido");
    },
    onError: erroToast,
  });
}

export async function abrirArquivo(caminho: string) {
  const { data, error } = await supabase.storage.from(((import.meta.env.VITE_STORAGE_PREFIX as string | undefined) ?? "") + "crm-arquivos").createSignedUrl(caminho, 120);
  if (error || !data) {
    toast.error("Não foi possível abrir o arquivo.");
    return;
  }
  window.open(data.signedUrl, "_blank", "noopener");
}

// ------------------------------------------------------------------ financeiro

export const useFinResumo = (competencia: string) =>
  useQuery({ queryKey: ["financeiro", "resumo", competencia], queryFn: () => rpc<FinResumo>("painel_fin_resumo", { p_competencia: competencia }), placeholderData: keepPreviousData });

export const useCobrancas = (competencia: string | null, situacao: string | null, busca: string) =>
  useQuery({
    queryKey: ["financeiro", "lista", competencia, situacao, busca],
    queryFn: () => rpc<Cobranca[]>("painel_cobrancas", { p_competencia: competencia, p_situacao: situacao, p_busca: busca || null }),
    placeholderData: keepPreviousData,
  });

export const useCobrancaHistorico = (id: string | null) =>
  useQuery({
    queryKey: ["financeiro", "historico", id ?? ""],
    queryFn: () => rpc<{ texto: string; autor: string; criado_em: string }[]>("painel_cobranca_historico", { p_id: id }),
    enabled: !!id,
  });

function useInvalidaFin() {
  const qc = useQueryClient();
  return () => {
    qc.invalidateQueries({ queryKey: ["financeiro"] });
    qc.invalidateQueries({ queryKey: ["crm"] });
    qc.invalidateQueries({ queryKey: ["agenda"] });
  };
}

export function useSalvarCobranca() {
  const inv = useInvalidaFin();
  return useMutation({
    mutationFn: (v: { id: string | null; dados: Record<string, unknown> }) => rpc<string>("painel_cobranca_salvar", { p_id: v.id, p_dados: v.dados }),
    onSuccess: (_r, v) => {
      inv();
      toast.success(v.id ? "Cobrança atualizada" : "Cobrança lançada");
    },
    onError: erroToast,
  });
}

export function useBaixaCobranca() {
  const inv = useInvalidaFin();
  return useMutation({
    mutationFn: (v: { id: string; pago_em: string | null; valor?: number | null; forma?: string | null }) =>
      rpc<void>("painel_cobranca_baixa", { p_id: v.id, p_pago_em: v.pago_em, p_valor: v.valor ?? null, p_forma: v.forma ?? null }),
    onSuccess: (_r, v) => {
      inv();
      toast.success(v.pago_em ? "Pagamento registrado" : "Pagamento desfeito");
    },
    onError: erroToast,
  });
}

export function useCancelarCobranca() {
  const inv = useInvalidaFin();
  return useMutation({
    mutationFn: (v: { id: string; motivo: string }) => rpc<void>("painel_cobranca_cancelar", { p_id: v.id, p_motivo: v.motivo }),
    onSuccess: () => {
      inv();
      toast.success("Cobrança cancelada");
    },
    onError: erroToast,
  });
}

export function useGerarMes() {
  const inv = useInvalidaFin();
  return useMutation({
    mutationFn: (competencia: string) => rpc<number>("painel_fin_gerar_mes", { p_competencia: competencia }),
    onSuccess: (n) => {
      inv();
      toast.success(n ? `${n} cobrança(s) gerada(s) a partir dos contratos` : "Nenhum contrato pendente neste mês");
    },
    onError: erroToast,
  });
}

export function useImportarCobrancas() {
  const inv = useInvalidaFin();
  return useMutation({
    mutationFn: (linhas: Record<string, unknown>[]) => rpc<{ importadas: number; erros: { linha: number; erro: string }[] }>("painel_fin_importar", { p_linhas: linhas }),
    onSuccess: () => inv(),
    onError: erroToast,
  });
}

export function useSalvarRegraFin() {
  const inv = useInvalidaFin();
  return useMutation({
    mutationFn: (tolerancia: number) => rpc<void>("painel_fin_regra_salvar", { p_tolerancia: tolerancia }),
    onSuccess: () => {
      inv();
      toast.success("Regra de inadimplência salva");
    },
    onError: erroToast,
  });
}

// ------------------------------------------------------------------ documentos técnicos

export const useDocumentosResumo = () =>
  useQuery({ queryKey: ["documentos", "resumo"], queryFn: () => rpc<DocumentosResumo>("painel_documentos_resumo") });

export const useDocumentos = (busca: string, tipo: string | null, situacao: string | null, empresa: string | null = null) =>
  useQuery({
    queryKey: ["documentos", "lista", busca, tipo, situacao, empresa],
    queryFn: () => rpc<DocumentoLinha[]>("painel_documentos", { p_busca: busca || null, p_tipo: tipo, p_situacao: situacao, p_empresa: empresa }),
    placeholderData: keepPreviousData,
  });

export function useSalvarDocumento() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { id: string | null; dados: Record<string, unknown>; arquivo?: File | null; caminhoAtual?: string | null }) => {
      const id = await rpc<string>("painel_documento_salvar", { p_id: v.id, p_dados: v.dados });
      if (v.arquivo) {
        if (v.caminhoAtual) await supabase.storage.from(((import.meta.env.VITE_STORAGE_PREFIX as string | undefined) ?? "") + "crm-arquivos").remove([v.caminhoAtual]);
        const limpo = v.arquivo.name.normalize("NFD").replace(/[^\w.-]+/g, "_");
        const caminho = `documentos/${id}/${Date.now()}-${limpo}`;
        const { error } = await supabase.storage.from(((import.meta.env.VITE_STORAGE_PREFIX as string | undefined) ?? "") + "crm-arquivos").upload(caminho, v.arquivo, { contentType: v.arquivo.type || "application/pdf" });
        if (error) throw new Error(`Documento salvo, mas o arquivo não subiu: ${error.message}`);
        await rpc<void>("painel_documento_arquivo", { p_id: id, p_path: caminho });
      }
      return id;
    },
    onSuccess: (_r, v) => {
      qc.invalidateQueries({ queryKey: ["documentos"] });
      qc.invalidateQueries({ queryKey: ["cliente"] });
      toast.success(v.id ? "Documento atualizado" : "Documento cadastrado");
    },
    onError: erroToast,
  });
}

// ------------------------------------------------------------------ whatsapp

export const useWaResumo = () =>
  useQuery({ queryKey: ["whatsapp", "resumo"], queryFn: () => rpc<WaResumo>("painel_wa_resumo"), refetchInterval: 60_000 });

export const useWaContatos = (busca: string, filtro: string) =>
  useQuery({
    queryKey: ["whatsapp", "contatos", busca, filtro],
    queryFn: () => rpc<WaContato[]>("painel_wa_contatos", { p_busca: busca || null, p_filtro: filtro }),
    placeholderData: keepPreviousData,
    refetchInterval: 60_000,
  });

export const useWaModelos = () => useQuery({ queryKey: ["whatsapp", "modelos"], queryFn: () => rpc<WaModelo[]>("painel_wa_modelos"), staleTime: 60_000 });

export const useWaContexto = (negocio: string | null) =>
  useQuery({ queryKey: ["whatsapp", "contexto", negocio], queryFn: () => rpc<WaContexto>("painel_wa_contexto", { p_negocio: negocio }), staleTime: 60_000 });

function useWaMutacao<V, R>(fn: (v: V) => Promise<R>, ok?: string | ((r: R, v: V) => string)) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: (r, v) => {
      qc.invalidateQueries({ queryKey: ["whatsapp"] });
      qc.invalidateQueries({ queryKey: ["crm"] });
      if (ok) toast.success(typeof ok === "function" ? ok(r, v) : ok);
    },
    onError: erroToast,
  });
}

export const useWaCriarNegocio = () =>
  useWaMutacao((contato: string) => rpc<string>("painel_wa_criar_negocio", { p_contato: contato }), "Negócio criado no funil");

export const useWaContatoSalvar = () =>
  useWaMutacao(
    (v: { id: string; dados: { empresa_id?: string | null; ignorado?: boolean } }) => rpc<void>("painel_wa_contato_salvar", { p_contato: v.id, p_dados: v.dados }),
    (_r, v) => (v.dados.ignorado === true ? "Marcado como não é lead" : v.dados.ignorado === false ? "Contato de volta à lista" : "Empresa vinculada"),
  );

export const useWaModeloSalvar = () =>
  useWaMutacao((v: { id: string | null; dados: Partial<WaModelo> }) => rpc<string>("painel_wa_modelo_salvar", { p_id: v.id, p_dados: v.dados }), "Modelo salvo");

export const useWaModeloExcluir = () => useWaMutacao((id: string) => rpc<void>("painel_wa_modelo_excluir", { p_id: id }), "Modelo excluído");

export const useWaConfigSalvar = () =>
  useWaMutacao((dados: { inbox_url?: string; criar_negocio?: boolean; funil_id?: string }) => rpc<void>("painel_wa_config_salvar", { p_dados: dados }), "Configuração salva");

export const useWaTokenGerar = () => useWaMutacao(() => rpc<string>("painel_wa_token_gerar"));

export function useAgendaLimiteSalvar() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { empresa: string; limite: number | null; motivo?: string | null }) =>
      rpc<void>("painel_agenda_limite_salvar", { p_empresa: v.empresa, p_limite: v.limite, p_motivo: v.motivo ?? null }),
    onSuccess: (_r, v) => {
      qc.invalidateQueries({ queryKey: chaves.agendaRegras });
      toast.success(v.limite == null ? "Limite próprio removido" : "Limite da empresa salvo");
    },
    onError: erroToast,
  });
}

// ------------------------------------------------------------------ equipe (pré-cadastro)

export const usePreCadastros = () => useQuery({ queryKey: ["pre-cadastros"], queryFn: () => rpc<PreCadastro[]>("painel_pre_cadastros_equipe") });

export function usePreCadastroSalvar() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { email: string; dados: Partial<PreCadastro> }) => rpc<void>("painel_pre_cadastro_salvar", { p_email: v.email, p_dados: v.dados }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["pre-cadastros"] });
      toast.success("Pré-cadastro salvo");
    },
    onError: erroToast,
  });
}

export function usePreCadastroExcluir() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (email: string) => rpc<void>("painel_pre_cadastro_excluir", { p_email: email }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["pre-cadastros"] });
      toast.success("Pré-cadastro removido");
    },
    onError: erroToast,
  });
}

export function useLiberaAgenda() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { user_id: string; libera: boolean }) => rpc<void>("painel_usuario_libera_agenda", { p_user: v.user_id, p_libera: v.libera }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: chaves.usuarios });
      qc.invalidateQueries({ queryKey: chaves.agendaRegras });
      toast.success("Permissão da agenda atualizada");
    },
    onError: erroToast,
  });
}

/** Quem agenda encaixe (acima das vagas da grade) — 0080. */
export const useUsuariosEncaixe = (ativo = true) =>
  useQuery({ queryKey: ["usuarios", "encaixe"], queryFn: () => rpc<string[]>("painel_usuarios_encaixe"), enabled: ativo });

export function useUsuarioEncaixe() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { user_id: string; pode: boolean }) => rpc<void>("painel_usuario_encaixe", { p_user: v.user_id, p_pode: v.pode }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["usuarios", "encaixe"] });
      qc.invalidateQueries({ queryKey: ["agenda"] });
      toast.success("Permissão de encaixe atualizada");
    },
    onError: erroToast,
  });
}

// ---------------------------------------------------------------- edição de dados do SESMO (0051)

export interface FiltroColaboradores {
  empresa: string;
  busca: string;
  situacao: string | null;
  pagina: number;
}

export const useColaboradores = (f: FiltroColaboradores, porPagina = 50) =>
  useQuery({
    queryKey: ["colaboradores", f],
    queryFn: () =>
      rpc<ColaboradorLinha[]>("painel_colaboradores", {
        p_empresa: f.empresa,
        p_busca: f.busca || null,
        p_situacao: f.situacao,
        p_limite: porPagina,
        p_offset: f.pagina * porPagina,
      }),
    placeholderData: keepPreviousData,
  });

export const useColaborador = (id: string | null) =>
  useQuery({ queryKey: ["colaborador", id], queryFn: () => rpc<ColaboradorDetalhe>("painel_colaborador", { p_id: id }), enabled: !!id });

export const useAtendimento = (id: string | null) =>
  useQuery({ queryKey: ["atendimento", id], queryFn: () => rpc<AtendimentoDetalhe>("painel_atendimento", { p_id: id }), enabled: !!id });

/** Toda gravação de dado cadastral recarrega as telas que mostram esse dado. */
export function useSalvarDados() {
  const qc = useQueryClient();
  return async <T,>(funcao: string, args: Record<string, unknown>) => {
    const r = await rpc<T>(funcao, args);
    for (const k of ["cliente", "clientes", "colaboradores", "colaborador", "atendimentos", "atendimento", "resumo"]) qc.invalidateQueries({ queryKey: [k] });
    return r;
  };
}

// ---------------------------------------------------------------- chat interno (0054)

export const useChatSalas = (ativo: boolean) =>
  useQuery({ queryKey: ["chat", "salas"], queryFn: () => rpc<ChatSala[]>("painel_chat_salas"), refetchInterval: ativo ? 5_000 : 30_000 });

export const useChatNaoLidas = () =>
  useQuery({ queryKey: ["chat", "nao-lidas"], queryFn: () => rpc<number>("painel_chat_nao_lidas"), refetchInterval: 20_000 });

export const useChatMensagens = (sala: string | null) =>
  useQuery({
    queryKey: ["chat", "mensagens", sala],
    queryFn: () => rpc<ChatMensagem[]>("painel_chat_mensagens_v2", { p_sala: sala, p_limite: 200 }),
    enabled: !!sala,
    refetchInterval: 4_000,
  });

/** Link temporário (1 h) para exibir um anexo do chat. Fora da chave "chat" para não recarregar a cada mensagem. */
export const useChatAnexoUrl = (caminho: string | null) =>
  useQuery({
    queryKey: ["chat-anexo-url", caminho],
    queryFn: async () => {
      const { data, error } = await supabase.storage.from(((import.meta.env.VITE_STORAGE_PREFIX as string | undefined) ?? "") + "chat").createSignedUrl(caminho!, 3600);
      if (error) throw error;
      return data.signedUrl;
    },
    enabled: !!caminho,
    staleTime: 50 * 60_000,
  });

export const useChatSala = (sala: string | null) =>
  useQuery({ queryKey: ["chat", "sala", sala], queryFn: () => rpc<ChatSalaDetalhe>("painel_chat_sala", { p_id: sala }), enabled: !!sala });

export const useChatPessoas = () =>
  useQuery({ queryKey: ["chat", "pessoas"], queryFn: () => rpc<ChatPessoa[]>("painel_chat_pessoas"), staleTime: 5 * 60_000 });

export function useChatAcoes() {
  const qc = useQueryClient();
  const recarregar = () => qc.invalidateQueries({ queryKey: ["chat"] });
  return {
    enviar: async (sala: string, texto: string) => {
      await rpc<number>("painel_chat_enviar", { p_sala: sala, p_texto: texto });
      recarregar();
    },
    /** 0075: sobe o arquivo para o bucket `chat` (pasta da sala) e registra a mensagem. */
    enviarAnexo: async (sala: string, arquivo: Blob, a: { tipo: ChatAnexoTipo; nome: string; duracao?: number | null; legenda?: string | null }) => {
      if (arquivo.size > 15 * 1024 * 1024) throw new Error("Arquivo maior que 15 MB.");
      const mime = (arquivo.type || "application/octet-stream").split(";")[0];
      const ext = (a.nome.includes(".") ? a.nome.split(".").pop() : mime.split("/")[1] || "bin")!.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 8) || "bin";
      const caminho = `${sala}/${crypto.randomUUID()}.${ext}`;
      const { error } = await supabase.storage.from(((import.meta.env.VITE_STORAGE_PREFIX as string | undefined) ?? "") + "chat").upload(caminho, arquivo, { contentType: mime });
      if (error) throw new Error(error.message.includes("mime") ? "Tipo de arquivo não permitido no chat." : error.message);
      await rpc<number>("painel_chat_enviar_anexo", {
        p_sala: sala,
        p_path: caminho,
        p_tipo: a.tipo,
        p_nome: a.nome,
        p_mime: mime,
        p_tamanho: arquivo.size,
        p_duracao: a.duracao ?? null,
        p_legenda: a.legenda ?? null,
      });
      recarregar();
    },
    lida: async (sala: string) => {
      await rpc<void>("painel_chat_lida", { p_sala: sala });
      qc.invalidateQueries({ queryKey: ["chat", "salas"] });
      qc.invalidateQueries({ queryKey: ["chat", "nao-lidas"] });
    },
    apagar: async (id: number) => {
      await rpc<void>("painel_chat_apagar", { p_id: id });
      recarregar();
    },
    direto: async (user: string) => {
      const id = await rpc<string>("painel_chat_direto", { p_user: user });
      recarregar();
      return id;
    },
    grupo: async (id: string | null, nome: string, descricao: string, membros: string[]) => {
      const r = await rpc<string>("painel_chat_grupo_salvar", { p_id: id, p_nome: nome, p_descricao: descricao, p_membros: membros });
      recarregar();
      return r;
    },
    sair: async (sala: string) => {
      await rpc<void>("painel_chat_sair", { p_sala: sala });
      recarregar();
    },
  };
}
