import { useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { AlarmClock, CalendarX2, FileCheck2, FileCog, FileSignature, KanbanSquare, Loader2, Paperclip, Plus, Search, Table2, Wallet } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { KpiCard } from "@/components/ui/kpi-card";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ContratoDetalhe } from "@/components/contratos/ContratoDetalhe";
import { ModeloMinutaDialog } from "@/components/contratos/GerarMinuta";
import { useSessao } from "@/contexts/sessao";
import { EmpresaSelect, type EmpresaEscolhida } from "@/components/crm/EmpresaSelect";
import { useDebounce } from "@/hooks/useDebounce";
import { useContratos, useContratosResumo, useSalvarContrato, useStatusContrato } from "@/hooks/api";
import { ORDEM_STATUS_CONTRATO, situacaoContrato, statusContrato } from "@/lib/status";
import type { ContratoLinha } from "@/lib/tipos";
import { baixarCsv, cn, fmtData, fmtMoeda, iniciais } from "@/lib/utils";

const FILTROS: { valor: string | null; rotulo: string }[] = [
  { valor: null, rotulo: "Todos" },
  { valor: "a_renovar", rotulo: "A renovar" },
  { valor: "vencido", rotulo: "Vencidos" },
  { valor: "em_assinatura", rotulo: "Em assinatura" },
  { valor: "vigente", rotulo: "Vigentes" },
  { valor: "cancelado", rotulo: "Cancelados" },
];

export default function Contratos() {
  const [params, setParams] = useSearchParams();
  const visao = params.get("visao") === "assinatura" ? "assinatura" : "lista";
  const aberto = params.get("contrato");
  const situacao = params.get("situacao");
  const muda = (novo: Record<string, string | null>) => {
    const p = new URLSearchParams(params);
    Object.entries(novo).forEach(([k, v]) => (v === null ? p.delete(k) : p.set(k, v)));
    setParams(p, { replace: true });
  };
  const [texto, setTexto] = useState("");
  const busca = useDebounce(texto, 300);
  const resumo = useContratosResumo();
  const lista = useContratos(busca, visao === "assinatura" ? null : situacao);
  const [novo, setNovo] = useState(false);
  const [modelo, setModelo] = useState(false);
  const { tem } = useSessao();

  function exportar() {
    baixarCsv(
      "contratos",
      (lista.data ?? []).map((c) => ({
        numero: c.numero,
        cliente: c.cliente,
        titulo: c.titulo,
        assinatura: statusContrato[c.status].rotulo,
        situacao: situacaoContrato[c.situacao].rotulo,
        inicio: fmtData(c.inicio),
        fim: fmtData(c.fim),
        valor_mensal: c.valor_mensal ?? "",
        valor_total: c.valor_total,
        responsavel: c.responsavel_nome ?? "",
      })),
    );
  }

  return (
    <div className="flex h-full flex-col">
      <div className="space-y-5 p-4 pb-3 sm:p-6 sm:pb-3">
        <Cabecalho
          titulo="Contratos"
          descricao="Contratos por cliente, do rascunho à assinatura. Avisa a renovação antes do vencimento e abre o card em Pós-venda → Renovações."
          acoes={
            <>
              {tem("gestor") && (
                <Button size="sm" variant="ghost" onClick={() => setModelo(true)}>
                  <FileCog /> Modelo da minuta
                </Button>
              )}
              <Button size="sm" onClick={() => setNovo(true)}>
                <Plus /> Novo contrato
              </Button>
            </>
          }
        />
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-6">
          <KpiCard titulo="Vigentes" valor={resumo.data?.vigentes ?? 0} icone={FileCheck2} tom="success" carregando={resumo.isLoading} onClick={() => muda({ visao: null, situacao: "vigente" })} />
          <KpiCard titulo="A renovar" valor={resumo.data?.a_renovar ?? 0} icone={AlarmClock} tom="warning" carregando={resumo.isLoading} onClick={() => muda({ visao: null, situacao: "a_renovar" })} />
          <KpiCard titulo="Vencidos" valor={resumo.data?.vencidos ?? 0} icone={CalendarX2} tom="destructive" carregando={resumo.isLoading} onClick={() => muda({ visao: null, situacao: "vencido" })} />
          <KpiCard titulo="Em assinatura" valor={resumo.data?.em_assinatura ?? 0} icone={FileSignature} tom="info" carregando={resumo.isLoading} onClick={() => muda({ visao: "assinatura", situacao: null })} />
          <div className="sm:col-span-2">
            <KpiCard titulo="Receita mensal contratada" valor={fmtMoeda(resumo.data?.receita_mensal ?? 0)} detalhe="Vigentes + a renovar" icone={Wallet} tom="marca" carregando={resumo.isLoading} />
          </div>
        </div>
        {resumo.isError && <EstadoErro erro={resumo.error} onTentar={() => resumo.refetch()} />}

        <div className="flex flex-wrap items-center gap-2">
          <Tabs value={visao} onValueChange={(v) => muda({ visao: v === "assinatura" ? "assinatura" : null })}>
            <TabsList>
              <TabsTrigger value="lista">
                <Table2 className="mr-1.5 h-4 w-4" aria-hidden /> Lista
              </TabsTrigger>
              <TabsTrigger value="assinatura">
                <KanbanSquare className="mr-1.5 h-4 w-4" aria-hidden /> Assinatura
              </TabsTrigger>
            </TabsList>
          </Tabs>
          <div className="relative min-w-[200px] flex-1 sm:max-w-xs">
            <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
            <Input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Cliente, título ou nº" className="pl-8" aria-label="Buscar contrato" />
          </div>
          {visao === "lista" && (
            <>
              <div className="flex flex-wrap gap-1.5" role="group" aria-label="Filtrar por situação">
                {FILTROS.map((f) => (
                  <Button key={f.rotulo} size="sm" variant={situacao === f.valor ? "default" : "outline"} aria-pressed={situacao === f.valor} onClick={() => muda({ situacao: f.valor })}>
                    {f.rotulo}
                  </Button>
                ))}
              </div>
              <Button size="sm" variant="ghost" className="ml-auto" onClick={exportar} disabled={!lista.data?.length}>
                Exportar
              </Button>
            </>
          )}
        </div>
      </div>

      {lista.isError ? (
        <div className="px-4 sm:px-6">
          <EstadoErro erro={lista.error} onTentar={() => lista.refetch()} />
        </div>
      ) : visao === "assinatura" ? (
        <Assinatura lista={lista.data ?? []} carregando={lista.isLoading} onAbrir={(id) => muda({ contrato: id })} />
      ) : (
        <div className="px-4 pb-6 sm:px-6">
          <Lista lista={lista.data} carregando={lista.isLoading} onAbrir={(id) => muda({ contrato: id })} onNovo={() => setNovo(true)} filtrado={!!situacao || !!busca} />
        </div>
      )}

      <ContratoDetalhe id={aberto} onFechar={() => muda({ contrato: null })} />
      <ModeloMinutaDialog aberto={modelo} onFechar={() => setModelo(false)} />
      <NovoContrato aberto={novo} onFechar={() => setNovo(false)} onCriado={(id) => muda({ contrato: id })} />
    </div>
  );
}

function Vencimento({ c }: { c: ContratoLinha }) {
  if (!c.fim) return <span className="text-muted-foreground">—</span>;
  const d = c.dias_para_vencer ?? 0;
  return (
    <span className={cn("tabular-nums", c.situacao === "vencido" && "font-medium text-destructive", c.situacao === "a_renovar" && "font-medium text-warning")}>
      {fmtData(c.fim)}
      {c.status === "assinado" && (c.situacao === "a_renovar" || c.situacao === "vencido") && (
        <span className="block text-xs font-normal">{d < 0 ? `venceu há ${-d} dia${d === -1 ? "" : "s"}` : d === 0 ? "vence hoje" : `em ${d} dia${d === 1 ? "" : "s"}`}</span>
      )}
    </span>
  );
}

function Lista({ lista, carregando, onAbrir, onNovo, filtrado }: { lista?: ContratoLinha[]; carregando: boolean; onAbrir: (id: string) => void; onNovo: () => void; filtrado: boolean }) {
  if (lista && lista.length === 0)
    return (
      <EstadoVazio
        icone={FileSignature}
        titulo={filtrado ? "Nenhum contrato com esse filtro" : "Nenhum contrato ainda"}
        texto={filtrado ? "Tente outro filtro ou limpe a busca." : "Contratos nascem sozinhos quando um negócio é ganho no Comercial, ou você cadastra os vigentes aqui."}
        acao={
          !filtrado && (
            <Button size="sm" onClick={onNovo}>
              <Plus /> Novo contrato
            </Button>
          )
        }
      />
    );
  return (
    <Card>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Cliente / contrato</TableHead>
            <TableHead>Situação</TableHead>
            <TableHead>Assinatura</TableHead>
            <TableHead>Vigência até</TableHead>
            <TableHead className="text-right">Mensal</TableHead>
            <TableHead className="hidden lg:table-cell">Responsável</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {carregando &&
            Array.from({ length: 5 }).map((_, i) => (
              <TableRow key={i}>
                {Array.from({ length: 6 }).map((__, j) => (
                  <TableCell key={j}>
                    <Skeleton className="h-4 w-full" />
                  </TableCell>
                ))}
              </TableRow>
            ))}
          {lista?.map((c) => (
            <TableRow key={c.id} className="cursor-pointer" onClick={() => onAbrir(c.id)}>
              <TableCell>
                <button type="button" onClick={() => onAbrir(c.id)} className="text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                  <span className="block font-medium">{c.cliente}</span>
                  <span className="flex items-center gap-1 text-xs text-muted-foreground">
                    #{c.numero} · {c.titulo}
                    {c.tem_arquivo && <Paperclip className="h-3 w-3" aria-label="Com arquivo" />}
                  </span>
                </button>
              </TableCell>
              <TableCell>
                <Badge variant={situacaoContrato[c.situacao].badge}>{situacaoContrato[c.situacao].rotulo}</Badge>
              </TableCell>
              <TableCell className="text-sm">{statusContrato[c.status].rotulo}</TableCell>
              <TableCell>
                <Vencimento c={c} />
              </TableCell>
              <TableCell className="text-right tabular-nums">{c.valor_mensal != null ? fmtMoeda(c.valor_mensal) : <span className="text-muted-foreground">—</span>}</TableCell>
              <TableCell className="hidden lg:table-cell">{c.responsavel_nome ?? <span className="text-muted-foreground">—</span>}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </Card>
  );
}

function Assinatura({ lista, carregando, onAbrir }: { lista: ContratoLinha[]; carregando: boolean; onAbrir: (id: string) => void }) {
  const status = useStatusContrato();
  const [arrastando, setArrastando] = useState<string | null>(null);
  const [sobre, setSobre] = useState<string | null>(null);
  const porStatus = useMemo(() => {
    const m = new Map<string, ContratoLinha[]>(ORDEM_STATUS_CONTRATO.map((s) => [s, []]));
    // Assinado só entra no quadro nos 30 dias depois da assinatura: o resto fica na lista.
    lista.forEach((c) => {
      if (c.status === "assinado" && Date.now() - new Date(c.atualizado_em).getTime() > 30 * 86_400_000) return;
      m.get(c.status)?.push(c);
    });
    return m;
  }, [lista]);

  return (
    <div className="flex min-h-0 flex-1 gap-3 overflow-x-auto px-4 pb-4 sm:px-6">
      {ORDEM_STATUS_CONTRATO.map((s) => {
        const st = statusContrato[s];
        const cards = porStatus.get(s) ?? [];
        return (
          <section
            key={s}
            aria-label={st.rotulo}
            onDragOver={(e) => {
              if (!arrastando) return;
              e.preventDefault();
              setSobre(s);
            }}
            onDragLeave={() => setSobre((x) => (x === s ? null : x))}
            onDrop={(e) => {
              e.preventDefault();
              setSobre(null);
              const id = arrastando;
              setArrastando(null);
              const c = lista.find((x) => x.id === id);
              if (c && c.status !== s) status.mutate({ id: c.id, status: s });
            }}
            className={cn("flex w-72 shrink-0 flex-col rounded-lg border border-t-4 bg-muted/40", st.faixa, sobre === s && "bg-accent")}
          >
            <header className="flex items-center justify-between p-3 pb-2">
              <h2 className="text-sm font-semibold">{st.rotulo}</h2>
              <Badge variant={st.badge}>{carregando ? "…" : cards.length}</Badge>
            </header>
            <div className="flex-1 space-y-2 overflow-y-auto p-2 pt-0">
              {carregando && <Skeleton className="h-20 w-full" />}
              {!carregando && cards.length === 0 && <p className="rounded-md border border-dashed p-3 text-center text-xs text-muted-foreground">Nenhum contrato</p>}
              {cards.map((c) => (
                <button
                  key={c.id}
                  type="button"
                  draggable
                  onDragStart={(e) => {
                    e.dataTransfer.setData("text/plain", c.id);
                    setArrastando(c.id);
                  }}
                  onDragEnd={() => setArrastando(null)}
                  onClick={() => onAbrir(c.id)}
                  className="block w-full cursor-grab rounded-md border bg-card p-3 text-left shadow-sm hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring active:cursor-grabbing"
                >
                  <p className="line-clamp-2 text-sm font-medium">{c.cliente}</p>
                  <p className="mt-0.5 truncate text-xs text-muted-foreground">
                    #{c.numero} · {c.titulo}
                  </p>
                  <div className="mt-2 flex items-center gap-2 text-xs">
                    <span className="font-semibold tabular-nums">{c.valor_mensal != null ? `${fmtMoeda(c.valor_mensal)}/mês` : fmtMoeda(c.valor_total)}</span>
                    <span className="flex-1" />
                    {c.tem_arquivo && <Paperclip className="h-3.5 w-3.5 text-muted-foreground" aria-label="Com arquivo" />}
                    <span
                      className={cn(
                        "flex h-6 w-6 items-center justify-center rounded-full text-[10px] font-semibold",
                        c.responsavel_nome ? "bg-primary/15 text-primary" : "border border-dashed text-muted-foreground",
                      )}
                      title={c.responsavel_nome ?? "Sem responsável"}
                    >
                      {c.responsavel_nome ? iniciais(c.responsavel_nome) : "?"}
                    </span>
                  </div>
                </button>
              ))}
            </div>
          </section>
        );
      })}
    </div>
  );
}

function NovoContrato({ aberto, onFechar, onCriado }: { aberto: boolean; onFechar: () => void; onCriado: (id: string) => void }) {
  const salvar = useSalvarContrato();
  const [empresa, setEmpresa] = useState<EmpresaEscolhida | null>(null);
  const [f, setF] = useState({ titulo: "", cliente_nome: "", inicio: "", fim: "", valor_mensal: "" });
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF((x) => ({ ...x, [k]: e.target.value }));
  const [semCadastro, setSemCadastro] = useState(false);

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Novo contrato</DialogTitle>
          <DialogDescription>Para cadastrar os contratos que já estão vigentes. Os novos nascem sozinhos quando o Comercial ganha o negócio.</DialogDescription>
        </DialogHeader>
        <form
          className="grid gap-4 sm:grid-cols-2"
          onSubmit={(e) => {
            e.preventDefault();
            salvar
              .mutateAsync({
                id: null,
                dados: {
                  titulo: f.titulo || `Contrato — ${empresa?.nome ?? f.cliente_nome}`,
                  empresa_id: semCadastro ? null : empresa?.id,
                  cliente_nome: semCadastro ? f.cliente_nome : null,
                  inicio: f.inicio || null,
                  fim: f.fim || null,
                  valor_mensal: f.valor_mensal ? Number(f.valor_mensal.replace(/\./g, "").replace(",", ".")) : null,
                },
              })
              .then((id) => {
                setF({ titulo: "", cliente_nome: "", inicio: "", fim: "", valor_mensal: "" });
                setEmpresa(null);
                onFechar();
                onCriado(id);
              })
              .catch(() => null);
          }}
        >
          <div className="space-y-1.5 sm:col-span-2">
            <div className="flex items-center justify-between">
              <Label htmlFor="nc-empresa">Cliente</Label>
              <button type="button" className="text-xs text-primary hover:underline" onClick={() => setSemCadastro((x) => !x)}>
                {semCadastro ? "Buscar na base" : "Cliente sem cadastro"}
              </button>
            </div>
            {semCadastro ? <Input id="nc-empresa" value={f.cliente_nome} onChange={set("cliente_nome")} /> : <EmpresaSelect id="nc-empresa" valor={empresa} onChange={setEmpresa} />}
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="nc-titulo">Título</Label>
            <Input id="nc-titulo" value={f.titulo} onChange={set("titulo")} placeholder="Ex.: PGR + PCMSO 2026" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="nc-inicio">Início</Label>
            <Input id="nc-inicio" type="date" value={f.inicio} onChange={set("inicio")} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="nc-fim">Fim</Label>
            <Input id="nc-fim" type="date" value={f.fim} onChange={set("fim")} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="nc-mensal">Valor mensal (R$)</Label>
            <Input id="nc-mensal" inputMode="decimal" value={f.valor_mensal} onChange={set("valor_mensal")} placeholder="0,00" />
          </div>
          <DialogFooter className="sm:col-span-2">
            <Button type="button" variant="outline" onClick={onFechar}>
              Cancelar
            </Button>
            <Button type="submit" disabled={salvar.isPending || (semCadastro ? f.cliente_nome.trim().length < 2 : !empresa)}>
              {salvar.isPending && <Loader2 className="animate-spin" />} Criar contrato
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
