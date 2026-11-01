import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { AlarmClock, KanbanSquare, Plus, Search, Shuffle } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { NovoNegocioDialog } from "@/components/crm/NovoNegocioDialog";
import { NegocioDetalhe } from "@/components/crm/NegocioDetalhe";
import { MotivoPerdaDialog } from "@/components/crm/MotivoPerdaDialog";
import { chaves, useFunis, useMoverNegocio, useQuadro, useResponsaveis } from "@/hooks/api";
import { useSessao } from "@/contexts/sessao";
import { corEtapa } from "@/lib/status";
import type { CardNegocio, Etapa, Funil } from "@/lib/tipos";
import { cn, fmtMoeda, iniciais } from "@/lib/utils";

const TODOS = "__todos__";

export default function Funis() {
  const funis = useFunis();
  const [params, setParams] = useSearchParams();
  const slug = params.get("funil") ?? "comercial";
  const negocioAberto = params.get("negocio");
  const funil = funis.data?.find((f) => f.slug === slug) ?? funis.data?.[0];

  function setParam(k: string, v: string | null) {
    const p = new URLSearchParams(params);
    if (v) p.set(k, v);
    else p.delete(k);
    setParams(p, { replace: k === "negocio" ? false : true });
  }

  return (
    <div className="flex h-full flex-col">
      <div className="space-y-4 p-4 pb-3 sm:p-6 sm:pb-3">
        <Cabecalho titulo="Funis" descricao="Arraste os cards entre as etapas ou abra o negócio para ver tudo." />
        {funis.isLoading ? (
          <Skeleton className="h-9 w-full max-w-xl" />
        ) : funis.isError ? (
          <EstadoErro erro={funis.error} onTentar={() => funis.refetch()} />
        ) : (
          <div className="-mx-1 flex gap-1 overflow-x-auto px-1 pb-1" role="tablist" aria-label="Funis">
            {funis.data?.map((f) => (
              <button
                key={f.id}
                role="tab"
                aria-selected={f.id === funil?.id}
                onClick={() => setParam("funil", f.slug)}
                className={cn(
                  "whitespace-nowrap rounded-full border px-4 py-1.5 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                  f.id === funil?.id ? "border-primary bg-primary text-primary-foreground" : "bg-card hover:bg-accent",
                )}
              >
                {f.nome}
              </button>
            ))}
          </div>
        )}
      </div>
      {funil && <Quadro funil={funil} onAbrir={(id) => setParam("negocio", id)} />}
      {funis.data && <NegocioDetalhe id={negocioAberto} funis={funis.data} onFechar={() => setParam("negocio", null)} />}
    </div>
  );
}

function Quadro({ funil, onAbrir }: { funil: Funil; onAbrir: (id: string) => void }) {
  const { perfil, tem } = useSessao();
  const veValores = tem("financeiro", "comercial"); // 0074
  // comercial só enxerga os próprios negócios (crm.ve_negocio): listar os colegas no filtro dava quadro vazio
  const soMeus = perfil?.papel === "comercial";
  const [resp, setResp] = useState<string>(TODOS);
  const [texto, setTexto] = useState("");
  const [busca, setBusca] = useState("");
  const [dias, setDias] = useState("30");
  // 0076: "periodo" = negócios criados entre as datas (abertos e fechados)
  const [de, setDe] = useState("");
  const [ate, setAte] = useState("");
  const porPeriodo = dias === "periodo";
  const [novo, setNovo] = useState(false);
  const [arrastando, setArrastando] = useState<string | null>(null);
  const [sobre, setSobre] = useState<string | null>(null);
  const [perda, setPerda] = useState<{ card: CardNegocio; etapa: string } | null>(null);
  useEffect(() => {
    const t = setTimeout(() => setBusca(texto.trim()), 350);
    return () => clearTimeout(t);
  }, [texto]);

  const responsaveis = useResponsaveis();
  const respId = resp === TODOS ? null : resp;
  const diasNum = porPeriodo ? 30 : Number(dias);
  const deQ = porPeriodo ? de || null : null;
  const ateQ = porPeriodo ? ate || null : null;
  const quadro = useQuadro(funil.id, respId, busca, diasNum, deQ, ateQ);
  const mover = useMoverNegocio();
  const qc = useQueryClient();

  const etapas = funil.etapas.filter((e) => e.ativo);
  const porEtapa = useMemo(() => {
    const m = new Map<string, CardNegocio[]>();
    etapas.forEach((e) => m.set(e.id, []));
    quadro.data?.forEach((c) => m.get(c.etapa_id)?.push(c));
    return m;
  }, [quadro.data, etapas]);

  function soltar(card: CardNegocio, etapa: Etapa, motivo?: string) {
    if (card.etapa_id === etapa.id) return;
    if (etapa.tipo === "perdido" && !motivo) {
      setPerda({ card, etapa: etapa.id });
      return;
    }
    // Otimista: move o card na hora; se o banco recusar, a lista é recarregada.
    const chave = chaves.quadro(funil.id, respId, busca, diasNum, deQ, ateQ);
    qc.setQueryData<CardNegocio[]>(chave, (old) =>
      old?.map((c) => (c.id === card.id ? { ...c, etapa_id: etapa.id, dias_na_etapa: 0, atrasado: false, entrou_etapa_em: new Date().toISOString() } : c)),
    );
    mover.mutate({ id: card.id, etapa: etapa.id, motivo });
  }

  return (
    <>
      <div className="flex flex-wrap items-center gap-2 px-4 pb-3 sm:px-6">
        <div className="relative w-full sm:w-72">
          <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
          <Input className="pl-8" placeholder="Buscar cliente, título ou nº…" value={texto} onChange={(e) => setTexto(e.target.value)} aria-label="Buscar negócios" />
        </div>
        {soMeus ? (
          <span className="rounded-md border bg-muted/40 px-3 py-2 text-sm text-muted-foreground">Mostrando os seus negócios</span>
        ) : (
          <Select value={resp} onValueChange={setResp}>
            <SelectTrigger className="w-full sm:w-56" aria-label="Filtrar por responsável">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={TODOS}>Todos os responsáveis</SelectItem>
              {perfil && <SelectItem value={perfil.user_id}>Só os meus</SelectItem>}
              {responsaveis.data
                ?.filter((r) => r.user_id !== perfil?.user_id)
                .map((r) => (
                  <SelectItem key={r.user_id} value={r.user_id}>
                    {r.nome}
                  </SelectItem>
                ))}
            </SelectContent>
          </Select>
        )}
        <Select
          value={dias}
          onValueChange={(v) => {
            setDias(v);
            if (v === "periodo" && !de) {
              const hoje = new Date();
              const ini = new Date(hoje.getFullYear(), hoje.getMonth(), 1);
              const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
              setDe(iso(ini));
              setAte(iso(hoje));
            }
          }}
        >
          <SelectTrigger className="w-full sm:w-52" aria-label="Período dos negócios">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="30">Fechados: últimos 30 dias</SelectItem>
            <SelectItem value="90">Fechados: últimos 90 dias</SelectItem>
            <SelectItem value="365">Fechados: últimos 12 meses</SelectItem>
            <SelectItem value="36500">Fechados: todos (inclui Bitrix)</SelectItem>
            <SelectItem value="periodo">Criados em um período…</SelectItem>
          </SelectContent>
        </Select>
        {porPeriodo && (
          <div className="flex items-center gap-1.5">
            <Input type="date" value={de} onChange={(e) => setDe(e.target.value)} className="w-[9.5rem]" aria-label="Criados a partir de" />
            <span className="text-xs text-muted-foreground">até</span>
            <Input type="date" value={ate} onChange={(e) => setAte(e.target.value)} className="w-[9.5rem]" aria-label="Criados até" />
          </div>
        )}
        {funil.usa_rodizio && (
          <Badge variant="info" className="hidden sm:inline-flex">
            <Shuffle className="h-3 w-3" /> Rodízio ligado
          </Badge>
        )}
        <div className="flex-1" />
        {funil.pode_operar ? (
          <Button onClick={() => setNovo(true)}>
            <Plus /> Novo negócio
          </Button>
        ) : (
          <Badge variant="muted">Somente consulta</Badge>
        )}
      </div>

      {quadro.isError ? (
        <div className="px-4 sm:px-6">
          <EstadoErro erro={quadro.error} onTentar={() => quadro.refetch()} />
        </div>
      ) : (
        <div className="flex min-h-0 flex-1 gap-3 overflow-x-auto px-4 pb-4 sm:px-6" aria-busy={quadro.isLoading}>
          {etapas.map((e) => {
            const cards = porEtapa.get(e.id) ?? [];
            const total = cards.reduce((s, c) => s + Number(c.valor || 0), 0);
            return (
              <section
                key={e.id}
                aria-label={`Etapa ${e.nome}`}
                onDragOver={(ev) => {
                  if (!funil.pode_operar || !arrastando) return;
                  ev.preventDefault();
                  setSobre(e.id);
                }}
                onDragLeave={() => setSobre((s) => (s === e.id ? null : s))}
                onDrop={(ev) => {
                  ev.preventDefault();
                  setSobre(null);
                  const card = quadro.data?.find((c) => c.id === ev.dataTransfer.getData("text/plain"));
                  if (card) soltar(card, e);
                }}
                className={cn(
                  "flex w-72 shrink-0 flex-col rounded-lg border border-t-4 bg-muted/40 transition-colors",
                  corEtapa[e.cor].borda,
                  sobre === e.id && "bg-accent ring-2 ring-primary/40",
                )}
              >
                <header className="flex items-start justify-between gap-2 p-3 pb-2">
                  <div className="min-w-0">
                    <h2 className="truncate text-sm font-semibold">{e.nome}</h2>
                    {veValores && <p className="text-xs text-muted-foreground tabular-nums">{fmtMoeda(total)}</p>}
                  </div>
                  <div className="flex items-center gap-1">
                    {e.alerta_dias && (
                      <span title={`Aviso após ${e.alerta_dias} dia(s) parado`} className="text-muted-foreground">
                        <AlarmClock className="h-3.5 w-3.5" aria-label={`Aviso após ${e.alerta_dias} dias`} />
                      </span>
                    )}
                    <Badge variant={corEtapa[e.cor].badge}>{quadro.isLoading ? "…" : cards.length}</Badge>
                  </div>
                </header>
                <div className="flex-1 space-y-2 overflow-y-auto p-2 pt-0">
                  {quadro.isLoading &&
                    Array.from({ length: 2 }).map((_, i) => <Skeleton key={i} className="h-24 w-full rounded-md" />)}
                  {!quadro.isLoading && cards.length === 0 && (
                    <p className="rounded-md border border-dashed p-3 text-center text-xs text-muted-foreground">
                      {porPeriodo ? "Nenhum negócio criado no período" : e.tipo === "aberta" ? "Nenhum negócio aqui" : `Nada fechado ${dias === "36500" ? "" : dias === "365" ? "nos últimos 12 meses" : `nos últimos ${dias} dias`}`}
                    </p>
                  )}
                  {cards.map((c) => (
                    <Cartao
                      key={c.id}
                      c={c}
                      arrastavel={funil.pode_operar}
                      onAbrir={() => onAbrir(c.id)}
                      onArrastar={(v) => setArrastando(v ? c.id : null)}
                    />
                  ))}
                </div>
              </section>
            );
          })}
          {!quadro.isLoading && quadro.data?.length === 0 && !busca && respId === null && (
            <div className="flex min-w-[18rem] flex-1 items-start">
              <EstadoVazio
                icone={KanbanSquare}
                titulo={`O funil ${funil.nome} está vazio`}
                texto={funil.pode_operar ? "Crie o primeiro negócio para começar." : "Ainda não há negócios neste funil."}
                acao={
                  funil.pode_operar && (
                    <Button onClick={() => setNovo(true)}>
                      <Plus /> Novo negócio
                    </Button>
                  )
                }
              />
            </div>
          )}
        </div>
      )}

      <NovoNegocioDialog funil={funil} aberto={novo} onFechar={() => setNovo(false)} onCriado={onAbrir} />
      <MotivoPerdaDialog
        aberto={!!perda}
        titulo={perda?.card.titulo ?? ""}
        onCancelar={() => setPerda(null)}
        onConfirmar={(motivo) => {
          const etapa = etapas.find((x) => x.id === perda?.etapa);
          if (perda && etapa) soltar(perda.card, etapa, motivo);
          setPerda(null);
        }}
      />
    </>
  );
}

function Cartao({ c, arrastavel, onAbrir, onArrastar }: { c: CardNegocio; arrastavel: boolean; onAbrir: () => void; onArrastar: (v: boolean) => void }) {
  return (
    <button
      type="button"
      draggable={arrastavel}
      onDragStart={(e) => {
        e.dataTransfer.setData("text/plain", c.id);
        e.dataTransfer.effectAllowed = "move";
        onArrastar(true);
      }}
      onDragEnd={() => onArrastar(false)}
      onClick={onAbrir}
      className={cn(
        "block w-full rounded-md border bg-card p-3 text-left shadow-sm transition-shadow hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        arrastavel && "cursor-grab active:cursor-grabbing",
        c.atrasado && "border-warning/60",
      )}
    >
      <p className="line-clamp-2 text-sm font-medium leading-snug">{c.titulo}</p>
      {c.cliente && c.cliente !== c.titulo && <p className="mt-0.5 truncate text-xs text-muted-foreground">{c.cliente}</p>}
      {c.vendedor_nome && <p className="mt-0.5 truncate text-xs text-muted-foreground">Vendedor: {c.vendedor_nome}</p>}
      <div className="mt-2 flex items-center gap-2">
        {c.valor != null && <span className="text-sm font-semibold tabular-nums">{fmtMoeda(c.valor)}</span>}
        <span className="flex-1" />
        {c.atrasado ? (
          <Badge variant="warning" title="Passou do prazo desta etapa">
            <AlarmClock className="h-3 w-3" /> {c.dias_na_etapa}d
          </Badge>
        ) : (
          <span className="text-xs text-muted-foreground">{c.dias_na_etapa}d</span>
        )}
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
  );
}
