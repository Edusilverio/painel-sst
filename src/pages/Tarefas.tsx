import { useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { CalendarClock, CheckSquare, KanbanSquare, MessageSquare, Plus, Search, Table2 } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { TarefaDetalhe } from "@/components/tarefas/TarefaDetalhe";
import { useSessao } from "@/contexts/sessao";
import { useDebounce } from "@/hooks/useDebounce";
import { useMoverTarefa, useQuadrosTarefas, useResponsaveis, useSalvarQuadroTarefas, useSalvarTarefa, useTarefas } from "@/hooks/api";
import { ORDEM_STATUS_TAREFA, prioridadeTarefa, statusTarefa } from "@/lib/status";
import type { StatusTarefa, TarefaLinha } from "@/lib/tipos";
import { cn, fmtData, iniciais } from "@/lib/utils";

const TODOS = "__todos__";

export default function Tarefas() {
  const { perfil, tem } = useSessao();
  const pode = tem("gestor", "comercial", "operacoes", "financeiro");
  const [params, setParams] = useSearchParams();
  const quadros = useQuadrosTarefas();
  const quadroId = params.get("quadro") ?? quadros.data?.[0]?.id;
  const visao = params.get("visao") === "tabela" ? "tabela" : "kanban";
  const aberta = params.get("tarefa");
  const muda = (novo: Record<string, string | null>) => {
    const p = new URLSearchParams(params);
    Object.entries(novo).forEach(([k, v]) => (v === null ? p.delete(k) : p.set(k, v)));
    setParams(p, { replace: true });
  };

  const [resp, setResp] = useState<string>(TODOS);
  const [texto, setTexto] = useState("");
  const busca = useDebounce(texto, 300);
  const responsaveis = useResponsaveis();
  const lista = useTarefas(quadroId, resp === TODOS ? null : resp, busca);
  const [novoQuadro, setNovoQuadro] = useState(false);

  const porStatus = useMemo(() => {
    const m = new Map<StatusTarefa, TarefaLinha[]>(ORDEM_STATUS_TAREFA.map((s) => [s, []]));
    (lista.data ?? []).forEach((t) => m.get(t.status)?.push(t));
    m.forEach((l) => l.sort((a, b) => a.ordem - b.ordem));
    return m;
  }, [lista.data]);

  const quadro = quadros.data?.find((q) => q.id === quadroId);

  return (
    <div className="flex h-full flex-col">
      <div className="space-y-4 p-4 pb-3 sm:p-6 sm:pb-3">
        <Cabecalho
          titulo={quadro?.nome ?? "Fluxo de Trabalho"}
          descricao={quadro?.descricao ?? "Tarefas da equipe com responsável, prazo e prioridade. Quem recebe uma tarefa é avisado no sino."}
          acoes={
            pode && (
              <Button variant="outline" size="sm" onClick={() => setNovoQuadro(true)}>
                <Plus /> Novo quadro
              </Button>
            )
          }
        />

        {quadros.data && quadros.data.length > 1 && (
          <Tabs value={quadroId} onValueChange={(v) => muda({ quadro: v })}>
            <TabsList className="h-auto flex-wrap">
              {quadros.data.map((q) => (
                <TabsTrigger key={q.id} value={q.id}>
                  {q.nome}
                  {q.atrasadas > 0 && <Badge variant="destructive" className="ml-1.5 px-1.5">{q.atrasadas}</Badge>}
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
        )}

        <div className="flex flex-wrap items-center gap-2">
          <Tabs value={visao} onValueChange={(v) => muda({ visao: v === "tabela" ? "tabela" : null })}>
            <TabsList>
              <TabsTrigger value="tabela">
                <Table2 className="mr-1.5 h-4 w-4" aria-hidden /> Quadro principal
              </TabsTrigger>
              <TabsTrigger value="kanban">
                <KanbanSquare className="mr-1.5 h-4 w-4" aria-hidden /> Kanban
              </TabsTrigger>
            </TabsList>
          </Tabs>
          <div className="relative min-w-[200px] flex-1 sm:max-w-xs">
            <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
            <Input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Pesquisar tarefa" className="pl-8" aria-label="Pesquisar tarefa" />
          </div>
          <Select value={resp} onValueChange={setResp}>
            <SelectTrigger className="w-[190px]" aria-label="Filtrar por pessoa">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={TODOS}>Todas as pessoas</SelectItem>
              {perfil && <SelectItem value={perfil.user_id}>Minhas tarefas</SelectItem>}
              {responsaveis.data
                ?.filter((r) => r.user_id !== perfil?.user_id)
                .map((r) => (
                  <SelectItem key={r.user_id} value={r.user_id}>
                    {r.nome}
                  </SelectItem>
                ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      {quadros.isError || lista.isError ? (
        <div className="px-4 sm:px-6">
          <EstadoErro erro={quadros.error ?? lista.error} onTentar={() => (quadros.isError ? quadros.refetch() : lista.refetch())} />
        </div>
      ) : quadros.data && quadros.data.length === 0 ? (
        <div className="px-4 sm:px-6">
          <EstadoVazio titulo="Nenhum quadro ainda" texto="Crie o primeiro quadro para organizar as tarefas da equipe." />
        </div>
      ) : visao === "kanban" ? (
        <Kanban porStatus={porStatus} carregando={lista.isLoading || quadros.isLoading} pode={pode} quadroId={quadroId} onAbrir={(id) => muda({ tarefa: id })} />
      ) : (
        <Tabela porStatus={porStatus} carregando={lista.isLoading || quadros.isLoading} pode={pode} quadroId={quadroId} onAbrir={(id) => muda({ tarefa: id })} />
      )}

      <TarefaDetalhe id={aberta} onFechar={() => muda({ tarefa: null })} />
      <NovoQuadroDialog aberto={novoQuadro} onFechar={() => setNovoQuadro(false)} onCriado={(id) => muda({ quadro: id })} />
    </div>
  );
}

// ------------------------------------------------------------------ kanban

function Kanban({
  porStatus,
  carregando,
  pode,
  quadroId,
  onAbrir,
}: {
  porStatus: Map<StatusTarefa, TarefaLinha[]>;
  carregando: boolean;
  pode: boolean;
  quadroId: string | undefined;
  onAbrir: (id: string) => void;
}) {
  const mover = useMoverTarefa();
  const [arrastando, setArrastando] = useState<string | null>(null);
  const [sobre, setSobre] = useState<{ status: StatusTarefa; antes: string | null } | null>(null);

  function soltar(status: StatusTarefa, antesDe: string | null) {
    const id = arrastando;
    setArrastando(null);
    setSobre(null);
    if (!id) return;
    const col = (porStatus.get(status) ?? []).filter((t) => t.id !== id);
    const idx = antesDe ? col.findIndex((t) => t.id === antesDe) : col.length;
    const anterior = col[idx - 1]?.ordem;
    const proxima = col[idx]?.ordem;
    // Posição entre as vizinhas; sem vizinha, abre um espaço de 1000.
    const ordem =
      anterior !== undefined && proxima !== undefined ? (anterior + proxima) / 2 : anterior !== undefined ? anterior + 1000 : proxima !== undefined ? proxima - 1000 : Date.now() / 1000;
    mover.mutate({ id, status, ordem });
  }

  return (
    <div className="flex min-h-0 flex-1 gap-3 overflow-x-auto px-4 pb-4 sm:px-6" aria-busy={carregando}>
      {ORDEM_STATUS_TAREFA.map((s) => {
        const st = statusTarefa[s];
        const cards = porStatus.get(s) ?? [];
        return (
          <section
            key={s}
            aria-label={st.rotulo}
            onDragOver={(e) => {
              if (!arrastando) return;
              e.preventDefault();
              if (sobre?.status !== s) setSobre({ status: s, antes: null });
            }}
            onDrop={(e) => {
              e.preventDefault();
              soltar(s, sobre?.status === s ? sobre.antes : null);
            }}
            className={cn("flex w-72 shrink-0 flex-col rounded-lg border border-t-4 bg-muted/40", st.faixa, sobre?.status === s && "bg-accent")}
          >
            <header className="flex items-center justify-between p-3 pb-2">
              <h2 className="text-sm font-semibold">{st.rotulo}</h2>
              <Badge variant={st.badge}>{carregando ? "…" : cards.length}</Badge>
            </header>
            <div className="flex-1 space-y-2 overflow-y-auto p-2 pt-0">
              {carregando && <Skeleton className="h-24 w-full" />}
              {cards.map((t) => (
                <div
                  key={t.id}
                  onDragOver={(e) => {
                    if (!arrastando || arrastando === t.id) return;
                    e.preventDefault();
                    e.stopPropagation();
                    setSobre({ status: s, antes: t.id });
                  }}
                  onDrop={(e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    soltar(s, t.id);
                  }}
                >
                  {sobre?.status === s && sobre.antes === t.id && <div className="mb-2 h-1 rounded bg-primary" aria-hidden />}
                  <Cartao t={t} arrastavel={pode} onAbrir={() => onAbrir(t.id)} onArrastar={(v) => setArrastando(v ? t.id : null)} />
                </div>
              ))}
              {!carregando && cards.length === 0 && <p className="rounded-md border border-dashed p-3 text-center text-xs text-muted-foreground">Nenhuma tarefa</p>}
              {pode && quadroId && <AdicionarRapido quadroId={quadroId} status={s} />}
            </div>
          </section>
        );
      })}
    </div>
  );
}

function Cartao({ t, arrastavel, onAbrir, onArrastar }: { t: TarefaLinha; arrastavel: boolean; onAbrir: () => void; onArrastar: (v: boolean) => void }) {
  const pr = prioridadeTarefa[t.prioridade];
  return (
    <button
      type="button"
      draggable={arrastavel}
      onDragStart={(e) => {
        e.dataTransfer.setData("text/plain", t.id);
        e.dataTransfer.effectAllowed = "move";
        onArrastar(true);
      }}
      onDragEnd={() => onArrastar(false)}
      onClick={onAbrir}
      className={cn(
        "block w-full rounded-md border bg-card p-3 text-left shadow-sm transition-shadow hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        arrastavel && "cursor-grab active:cursor-grabbing",
        t.atrasada && "border-destructive/50",
      )}
    >
      <p className={cn("line-clamp-3 text-sm font-medium leading-snug", t.status === "feito" && "text-muted-foreground line-through")}>{t.titulo}</p>
      <div className="mt-2 flex flex-wrap items-center gap-1.5">
        {t.prazo && (
          <Badge variant={t.atrasada ? "destructive" : "outline"}>
            <CalendarClock className="h-3 w-3" aria-hidden /> {fmtData(t.prazo).slice(0, 5)}
          </Badge>
        )}
        <Badge variant={pr.badge}>{pr.rotulo}</Badge>
        {t.empresa && <span className="max-w-[140px] truncate text-xs text-muted-foreground">{t.empresa}</span>}
      </div>
      {t.notas && <p className="mt-2 line-clamp-2 text-xs text-muted-foreground">{t.notas}</p>}
      <div className="mt-2.5 flex items-center gap-3 text-xs text-muted-foreground">
        <Avatares t={t} />
        <span className="flex-1" />
        {t.itens > 0 && (
          <span className={cn("flex items-center gap-1", t.itens_feitos === t.itens && "text-success")} title="Elementos de ação">
            <CheckSquare className="h-3.5 w-3.5" aria-hidden /> {t.itens_feitos}/{t.itens}
          </span>
        )}
        {t.comentarios > 0 && (
          <span className="flex items-center gap-1" title="Atualizações">
            <MessageSquare className="h-3.5 w-3.5" aria-hidden /> {t.comentarios}
          </span>
        )}
      </div>
    </button>
  );
}

/** 0077: até 3 avatares dos responsáveis; o resto vira "+n". */
function Avatares({ t }: { t: { responsaveis: { id: string; nome: string }[]; responsavel_nome: string | null } }) {
  const lista = t.responsaveis?.length ? t.responsaveis : t.responsavel_nome ? [{ id: "r", nome: t.responsavel_nome }] : [];
  if (!lista.length) return <Avatar nome={null} />;
  return (
    <span className="flex -space-x-1.5" title={lista.map((r) => r.nome).join(", ")}>
      {lista.slice(0, 3).map((r) => (
        <Avatar key={r.id} nome={r.nome} />
      ))}
      {lista.length > 3 && <span className="flex h-6 w-6 items-center justify-center rounded-full bg-muted text-[10px] font-semibold">+{lista.length - 3}</span>}
    </span>
  );
}

function Avatar({ nome }: { nome: string | null }) {
  return (
    <span
      className={cn(
        "flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-[10px] font-semibold ring-2 ring-card",
        nome ? "bg-primary/15 text-primary" : "border border-dashed text-muted-foreground",
      )}
      title={nome ?? "Sem responsável"}
    >
      {nome ? iniciais(nome) : "?"}
    </span>
  );
}

function AdicionarRapido({ quadroId, status }: { quadroId: string; status: StatusTarefa }) {
  const salvar = useSalvarTarefa();
  const [aberto, setAberto] = useState(false);
  const [titulo, setTitulo] = useState("");
  if (!aberto)
    return (
      <button type="button" onClick={() => setAberto(true)} className="flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-sm text-muted-foreground hover:bg-accent hover:text-foreground">
        <Plus className="h-4 w-4" /> Adicionar tarefa
      </button>
    );
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        if (titulo.trim().length < 2) return;
        salvar.mutate({ id: null, dados: { quadro_id: quadroId, titulo: titulo.trim(), status } });
        setTitulo("");
      }}
    >
      <Input
        autoFocus
        value={titulo}
        onChange={(e) => setTitulo(e.target.value)}
        onBlur={() => !titulo && setAberto(false)}
        onKeyDown={(e) => e.key === "Escape" && setAberto(false)}
        placeholder="Nome da tarefa e Enter"
        aria-label="Nome da nova tarefa"
      />
    </form>
  );
}

// ------------------------------------------------------------------ quadro principal (tabela agrupada, como no Monday)

function Tabela({
  porStatus,
  carregando,
  pode,
  quadroId,
  onAbrir,
}: {
  porStatus: Map<StatusTarefa, TarefaLinha[]>;
  carregando: boolean;
  pode: boolean;
  quadroId: string | undefined;
  onAbrir: (id: string) => void;
}) {
  const salvar = useSalvarTarefa();
  return (
    <div className="flex-1 space-y-5 overflow-y-auto px-4 pb-6 sm:px-6">
      {ORDEM_STATUS_TAREFA.map((s) => {
        const st = statusTarefa[s];
        const linhas = porStatus.get(s) ?? [];
        return (
          <section key={s} aria-label={st.rotulo}>
            <h2 className="mb-2 flex items-center gap-2 text-sm font-semibold">
              <span className={cn("h-3 w-3 rounded-sm", st.fundo)} aria-hidden /> {st.rotulo}
              <span className="font-normal text-muted-foreground">{carregando ? "" : `${linhas.length} tarefa${linhas.length === 1 ? "" : "s"}`}</span>
            </h2>
            <Card className={cn("overflow-hidden border-l-4", st.lateral)}>
              <div className="hidden grid-cols-[1fr_130px_160px_110px_100px_70px] gap-3 border-b bg-muted/40 px-3 py-2 text-xs font-medium text-muted-foreground md:grid">
                <span>Tarefa</span>
                <span>Responsável</span>
                <span>Status</span>
                <span>Prazo</span>
                <span>Prioridade</span>
                <span className="text-right">Itens</span>
              </div>
              {carregando && <Skeleton className="m-3 h-8" />}
              {linhas.map((t) => (
                <div key={t.id} className="grid grid-cols-1 gap-2 border-b px-3 py-2 last:border-b-0 hover:bg-muted/30 md:grid-cols-[1fr_130px_160px_110px_100px_70px] md:items-center md:gap-3">
                  <button type="button" onClick={() => onAbrir(t.id)} className="min-w-0 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                    <span className={cn("block truncate text-sm font-medium hover:underline", t.status === "feito" && "text-muted-foreground line-through")}>{t.titulo}</span>
                    {(t.empresa || t.comentarios > 0) && (
                      <span className="flex items-center gap-2 text-xs text-muted-foreground">
                        {t.empresa}
                        {t.comentarios > 0 && (
                          <span className="flex items-center gap-0.5">
                            <MessageSquare className="h-3 w-3" aria-hidden /> {t.comentarios}
                          </span>
                        )}
                      </span>
                    )}
                  </button>
                  <span className="flex items-center gap-2 text-sm">
                    <Avatares t={t} />
                    <span className="truncate">
                      {t.responsavel_nome?.split(" ")[0] ?? "—"}
                      {t.responsaveis?.length > 1 && <span className="text-muted-foreground"> +{t.responsaveis.length - 1}</span>}
                    </span>
                  </span>
                  <Select value={t.status} onValueChange={(v) => salvar.mutate({ id: t.id, dados: { status: v } })} disabled={!pode}>
                    <SelectTrigger className="h-8 text-xs" aria-label={`Status de ${t.titulo}`}>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {ORDEM_STATUS_TAREFA.map((x) => (
                        <SelectItem key={x} value={x}>
                          <span className="flex items-center gap-2">
                            <span className={cn("h-2.5 w-2.5 rounded-full", statusTarefa[x].fundo)} aria-hidden />
                            {statusTarefa[x].rotulo}
                          </span>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <span className={cn("text-sm tabular-nums", t.atrasada && "font-medium text-destructive")}>{t.prazo ? fmtData(t.prazo) : "—"}</span>
                  <span>
                    <Badge variant={prioridadeTarefa[t.prioridade].badge}>{prioridadeTarefa[t.prioridade].rotulo}</Badge>
                  </span>
                  <span className="text-right text-xs tabular-nums text-muted-foreground">{t.itens ? `${t.itens_feitos}/${t.itens}` : "—"}</span>
                </div>
              ))}
              {pode && quadroId && (
                <div className="px-2 py-1">
                  <AdicionarRapido quadroId={quadroId} status={s} />
                </div>
              )}
            </Card>
          </section>
        );
      })}
    </div>
  );
}

function NovoQuadroDialog({ aberto, onFechar, onCriado }: { aberto: boolean; onFechar: () => void; onCriado: (id: string) => void }) {
  const salvar = useSalvarQuadroTarefas();
  const [nome, setNome] = useState("");
  const [descricao, setDescricao] = useState("");
  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Novo quadro</DialogTitle>
          <DialogDescription>Um quadro por área ou projeto (ex.: Marketing, Técnico, Implantação de cliente).</DialogDescription>
        </DialogHeader>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            salvar
              .mutateAsync({ id: null, nome, descricao })
              .then((id) => {
                setNome("");
                setDescricao("");
                onFechar();
                onCriado(id);
              })
              .catch(() => null);
          }}
          className="space-y-4"
        >
          <div className="space-y-1.5">
            <Label htmlFor="q-nome">Nome</Label>
            <Input id="q-nome" value={nome} onChange={(e) => setNome(e.target.value)} required autoFocus />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="q-desc">Descrição</Label>
            <Input id="q-desc" value={descricao} onChange={(e) => setDescricao(e.target.value)} />
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={onFechar}>
              Cancelar
            </Button>
            <Button type="submit" disabled={nome.trim().length < 2 || salvar.isPending}>
              Criar quadro
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
