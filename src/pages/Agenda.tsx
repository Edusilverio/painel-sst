import { useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import {
  Building2,
  CalendarDays,
  CalendarPlus,
  ChevronLeft,
  ChevronRight,
  Download,
  History,
  Loader2,
  MoreHorizontal,
  Pencil,
  Search,
  Settings2,
  ShieldAlert,
  UserPlus,
} from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { AgendaDialog } from "@/components/agenda/AgendaDialog";
import { AgendamentoDialog } from "@/components/agenda/AgendamentoDialog";
import { RegrasDialog } from "@/components/agenda/RegrasDialog";
import { useSessao } from "@/contexts/sessao";
import { useAgendaDia, useAgendaPeriodo, useAgendaRegras, useAgendamentoHistorico, useSituacaoAgendamento } from "@/hooks/api";
import { situacaoAtendimento, tipoExame } from "@/lib/status";
import type { AgendaLinha, Agendamento, SituacaoAgendamento } from "@/lib/tipos";
import { baixarCsv, cn, dataDeIso, fmtCpf, fmtDataHora, fmtDataLonga, fmtDiaSemana, fmtHora, hojeIso, inicioSemana, somaDias } from "@/lib/utils";

/** Cores da legenda do SESMO, que a recepção já conhece. */
const faixa: Record<SituacaoAgendamento, string> = {
  agendado: "border-l-success",
  aguardando: "border-l-info bg-info/5",
  atendido: "border-l-warning",
  finalizado: "border-l-border",
  cancelado: "border-l-muted-foreground/30 opacity-60",
  faltou: "border-l-destructive/60 opacity-70",
};

const ORDEM_FILTRO: SituacaoAgendamento[] = ["agendado", "aguardando", "atendido", "finalizado", "faltou", "cancelado"];

export default function Agenda() {
  const [params, setParams] = useSearchParams();
  const data = params.get("data") ?? hojeIso();
  const visao = params.get("visao") === "semana" ? "semana" : "dia";
  const agendaSel = params.get("agenda");
  const muda = (novo: Record<string, string | null>) => {
    const p = new URLSearchParams(params);
    Object.entries(novo).forEach(([k, v]) => (v === null ? p.delete(k) : p.set(k, v)));
    setParams(p, { replace: true });
  };

  const regras = useAgendaRegras();
  const [dlgAgenda, setDlgAgenda] = useState<{ aberto: boolean; agenda: AgendaLinha | null }>({ aberto: false, agenda: null });
  const [dlgPaciente, setDlgPaciente] = useState<{ aberto: boolean; agendamento: Agendamento | null }>({ aberto: false, agendamento: null });
  const [dlgRegras, setDlgRegras] = useState(false);

  const passo = visao === "semana" ? 7 : 1;
  const podeConfigurar = !!regras.data?.pode_configurar;

  return (
    <div className="mx-auto max-w-7xl space-y-5 p-4 sm:p-6">
      <Cabecalho
        titulo="Agenda"
        descricao="Agenda por profissional e dia, na clínica ou in company. Substitui a planilha: vagas, limite por empresa e bloqueio de inadimplentes."
        acoes={
          <>
            {regras.data?.pode_excecao && (
              <Button variant="ghost" size="sm" onClick={() => setDlgRegras(true)}>
                <Settings2 /> Regras
              </Button>
            )}
            {podeConfigurar && (
              <Button variant="outline" size="sm" onClick={() => setDlgAgenda({ aberto: true, agenda: null })}>
                <CalendarPlus /> Nova agenda
              </Button>
            )}
            <Button size="sm" onClick={() => setDlgPaciente({ aberto: true, agendamento: null })}>
              <UserPlus /> Agendar paciente
            </Button>
          </>
        }
      />

      <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex flex-wrap items-center gap-2">
          <div className="flex items-center rounded-md border bg-card">
            <Button variant="ghost" size="icon" aria-label={visao === "semana" ? "Semana anterior" : "Dia anterior"} onClick={() => muda({ data: somaDias(data, -passo), agenda: null })}>
              <ChevronLeft />
            </Button>
            <Button variant="ghost" size="sm" onClick={() => muda({ data: hojeIso(), agenda: null })}>
              Hoje
            </Button>
            <Button variant="ghost" size="icon" aria-label={visao === "semana" ? "Próxima semana" : "Próximo dia"} onClick={() => muda({ data: somaDias(data, passo), agenda: null })}>
              <ChevronRight />
            </Button>
          </div>
          <Input type="date" value={data} onChange={(e) => e.target.value && muda({ data: e.target.value, agenda: null })} className="w-auto" aria-label="Escolher data" />
          <p className="text-sm font-medium first-letter:uppercase">
            {visao === "semana" ? `Semana de ${dataDeIso(inicioSemana(data)).toLocaleDateString("pt-BR", { day: "2-digit", month: "long" })}` : fmtDataLonga(data)}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <Legenda />
          <Tabs value={visao} onValueChange={(v) => muda({ visao: v === "semana" ? "semana" : null })}>
            <TabsList>
              <TabsTrigger value="dia">Dia</TabsTrigger>
              <TabsTrigger value="semana">Semana</TabsTrigger>
            </TabsList>
          </Tabs>
        </div>
      </div>

      {visao === "semana" ? (
        <Semana data={data} onAbrirDia={(d, ag) => muda({ data: d, visao: null, agenda: ag })} />
      ) : (
        <Dia
          data={data}
          agendaSel={agendaSel}
          onAgenda={(id) => muda({ agenda: id })}
          podeConfigurar={podeConfigurar}
          onEditarAgenda={(a) => setDlgAgenda({ aberto: true, agenda: a })}
          onNovaAgenda={() => setDlgAgenda({ aberto: true, agenda: null })}
          onEditarPaciente={(a) => setDlgPaciente({ aberto: true, agendamento: a })}
          onNovoPaciente={() => setDlgPaciente({ aberto: true, agendamento: null })}
        />
      )}

      <AgendaDialog aberto={dlgAgenda.aberto} agenda={dlgAgenda.agenda} data={data} onFechar={() => setDlgAgenda({ aberto: false, agenda: null })} />
      <AgendamentoDialog
        aberto={dlgPaciente.aberto}
        agendamento={dlgPaciente.agendamento}
        data={data}
        agendaInicial={agendaSel}
        onFechar={() => setDlgPaciente({ aberto: false, agendamento: null })}
      />
      <RegrasDialog aberto={dlgRegras} onFechar={() => setDlgRegras(false)} />
    </div>
  );
}

function Legenda() {
  const itens: { s: SituacaoAgendamento; cor: string }[] = [
    { s: "agendado", cor: "bg-success" },
    { s: "aguardando", cor: "bg-info" },
    { s: "atendido", cor: "bg-warning" },
    { s: "finalizado", cor: "bg-card border" },
  ];
  return (
    <ul className="hidden items-center gap-3 text-xs text-muted-foreground md:flex" aria-label="Legenda">
      {itens.map((i) => (
        <li key={i.s} className="flex items-center gap-1.5">
          <span className={cn("h-2.5 w-2.5 rounded-full", i.cor)} aria-hidden />
          {situacaoAtendimento(i.s).rotulo}
        </li>
      ))}
    </ul>
  );
}

// ------------------------------------------------------------------ dia

function Dia({
  data,
  agendaSel,
  onAgenda,
  podeConfigurar,
  onEditarAgenda,
  onNovaAgenda,
  onEditarPaciente,
  onNovoPaciente,
}: {
  data: string;
  agendaSel: string | null;
  onAgenda: (id: string | null) => void;
  podeConfigurar: boolean;
  onEditarAgenda: (a: AgendaLinha) => void;
  onNovaAgenda: () => void;
  onEditarPaciente: (a: Agendamento) => void;
  onNovoPaciente: () => void;
}) {
  const agendas = useAgendaPeriodo(data, data);
  const pacientes = useAgendaDia(data);
  const [filtro, setFiltro] = useState<SituacaoAgendamento | null>(null);
  const [busca, setBusca] = useState("");

  const daAgenda = useMemo(() => (pacientes.data ?? []).filter((p) => !agendaSel || p.agenda_id === agendaSel), [pacientes.data, agendaSel]);
  const contagem = useMemo(() => {
    const c = Object.fromEntries(ORDEM_FILTRO.map((s) => [s, 0])) as Record<SituacaoAgendamento, number>;
    daAgenda.forEach((p) => c[p.situacao]++);
    return c;
  }, [daAgenda]);
  const lista = useMemo(() => {
    const t = busca.trim().toLowerCase();
    const dig = t.replace(/\D/g, "");
    return daAgenda.filter(
      (p) =>
        (!filtro || p.situacao === filtro) &&
        (!t || p.paciente_nome.toLowerCase().includes(t) || (p.empresa ?? "").toLowerCase().includes(t) || (dig.length >= 3 && (p.cpf ?? "").includes(dig))),
    );
  }, [daAgenda, filtro, busca]);
  const nomeAgenda = (id: string) => {
    const a = agendas.data?.find((x) => x.id === id);
    return a ? `${a.profissional ?? "A definir"}${a.local === "in_company" ? " · in company" : ""}` : "";
  };

  function exportar() {
    baixarCsv(
      `agenda-${data}`,
      lista.map((p) => ({
        horario: p.horario ?? "",
        paciente: p.paciente_nome,
        cpf: fmtCpf(p.cpf),
        empresa: p.empresa ?? "",
        funcao: p.funcao ?? "",
        exame: tipoExame[p.tipo] ?? p.tipo,
        complementares: (p.complementares ?? []).join(" "),
        agendado_por: p.criado_por ?? "",
        agenda: nomeAgenda(p.agenda_id),
        situacao: situacaoAtendimento(p.situacao).rotulo,
        encaixe: p.encaixe ? "sim" : "",
        telefone: p.telefone ?? "",
        observacao: p.observacao ?? "",
      })),
    );
  }

  if (agendas.isError) return <EstadoErro erro={agendas.error} onTentar={() => agendas.refetch()} />;

  return (
    <div className="grid gap-5 lg:grid-cols-[290px_1fr]">
      <aside className="space-y-2" aria-label="Agendas do dia">
        <p className="px-1 text-xs font-semibold uppercase tracking-wider text-muted-foreground">Agendas do dia</p>
        {agendas.isLoading && Array.from({ length: 2 }).map((_, i) => <Skeleton key={i} className="h-24 w-full" />)}
        {agendas.data && agendas.data.length === 0 && (
          <EstadoVazio
            icone={CalendarDays}
            titulo="Nenhuma agenda aberta"
            texto={podeConfigurar ? "Crie a agenda de cada profissional para liberar as vagas do dia." : "Peça à recepção para abrir a agenda deste dia."}
            acao={
              podeConfigurar && (
                <Button size="sm" variant="outline" onClick={onNovaAgenda}>
                  <CalendarPlus /> Nova agenda
                </Button>
              )
            }
            className="p-6"
          />
        )}
        {agendas.data && agendas.data.length > 1 && (
          <button
            type="button"
            onClick={() => onAgenda(null)}
            className={cn(
              "w-full rounded-lg border px-3 py-2 text-left text-sm font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
              !agendaSel && "border-primary bg-primary/5",
            )}
          >
            Todas as agendas <span className="text-muted-foreground">· {pacientes.data?.filter((p) => !["cancelado", "faltou"].includes(p.situacao)).length ?? "…"} pacientes</span>
          </button>
        )}
        {agendas.data?.map((a) => (
          <CartaoAgenda key={a.id} a={a} ativo={agendaSel === a.id} onClick={() => onAgenda(agendaSel === a.id ? null : a.id)} onEditar={podeConfigurar ? () => onEditarAgenda(a) : undefined} />
        ))}
      </aside>

      <section className="min-w-0 space-y-3" aria-label="Pacientes">
        <div className="flex flex-wrap gap-2" role="group" aria-label="Filtrar por situação">
          {ORDEM_FILTRO.map((s) => {
            const st = situacaoAtendimento(s);
            const ativo = filtro === s;
            return (
              <button
                key={s}
                type="button"
                aria-pressed={ativo}
                onClick={() => setFiltro(ativo ? null : s)}
                className={cn(
                  "flex items-center gap-2 rounded-md border bg-card px-3 py-1.5 text-sm transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                  ativo && "border-primary ring-1 ring-primary",
                )}
              >
                <span className="text-muted-foreground">{st.rotulo}</span>
                <span className="font-semibold tabular-nums">{pacientes.isLoading ? "…" : contagem[s]}</span>
              </button>
            );
          })}
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <div className="relative min-w-[220px] flex-1">
            <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
            <Input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar paciente, empresa ou CPF" className="pl-8" aria-label="Buscar paciente" />
          </div>
          <Button variant="outline" size="sm" onClick={exportar} disabled={!lista.length}>
            <Download /> Exportar
          </Button>
        </div>

        {pacientes.isError ? (
          <EstadoErro erro={pacientes.error} onTentar={() => pacientes.refetch()} />
        ) : pacientes.isLoading ? (
          <Card className="divide-y">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="flex items-center gap-3 p-3">
                <Skeleton className="h-4 w-12" />
                <Skeleton className="h-4 flex-1" />
                <Skeleton className="h-6 w-20" />
              </div>
            ))}
          </Card>
        ) : lista.length === 0 ? (
          <EstadoVazio
            titulo={daAgenda.length ? "Nenhum paciente com esse filtro" : "Ninguém agendado"}
            texto={daAgenda.length ? "Limpe a busca ou o filtro de situação." : agendas.data?.length ? "As vagas deste dia estão livres." : "Abra uma agenda para começar a agendar."}
            acao={
              !daAgenda.length &&
              !!agendas.data?.length && (
                <Button size="sm" onClick={onNovoPaciente}>
                  <UserPlus /> Agendar paciente
                </Button>
              )
            }
          />
        ) : (
          <Card className="divide-y overflow-hidden">
            {lista.map((p) => (
              <LinhaPaciente key={p.id} p={p} data={data} agenda={agendaSel ? null : nomeAgenda(p.agenda_id)} onEditar={() => onEditarPaciente(p)} />
            ))}
          </Card>
        )}
        {pacientes.isFetching && !pacientes.isLoading && (
          <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
            <Loader2 className="h-3 w-3 animate-spin" /> Atualizando…
          </p>
        )}
      </section>
    </div>
  );
}

function CartaoAgenda({ a, ativo, onClick, onEditar }: { a: AgendaLinha; ativo: boolean; onClick: () => void; onEditar?: () => void }) {
  const pct = Math.min(100, Math.round((a.ocupadas / a.vagas) * 100));
  return (
    <div className={cn("relative rounded-lg border bg-card transition-colors", ativo && "border-primary ring-1 ring-primary")}>
      <button type="button" onClick={onClick} className="w-full rounded-lg p-3 pr-10 text-left hover:bg-accent/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" aria-pressed={ativo}>
        <p className="truncate font-medium">{a.profissional ?? "Profissional a definir"}</p>
        <p className="mt-0.5 flex flex-wrap items-center gap-1.5 text-xs text-muted-foreground">
          {a.hora_inicio && (
            <span>
              {a.hora_inicio}
              {a.hora_fim && `–${a.hora_fim}`}
            </span>
          )}
          {a.local === "in_company" ? (
            <Badge variant="marca" className="max-w-[160px]">
              <Building2 className="h-3 w-3" aria-hidden /> <span className="truncate">{a.empresa}</span>
            </Badge>
          ) : (
            <Badge variant="muted">Clínica</Badge>
          )}
        </p>
        <div className="mt-2.5 h-1.5 overflow-hidden rounded-full bg-muted" role="progressbar" aria-valuenow={a.ocupadas} aria-valuemin={0} aria-valuemax={a.vagas} aria-label="Ocupação">
          <div className={cn("h-full rounded-full", pct >= 100 ? "bg-destructive" : pct >= 80 ? "bg-warning" : "bg-success")} style={{ width: `${pct}%` }} />
        </div>
        <p className="mt-1.5 text-xs text-muted-foreground">
          <span className="font-semibold tabular-nums text-foreground">{a.ocupadas}</span>/{a.vagas} vagas
          {a.encaixes > 0 && ` · ${a.encaixes} encaixe${a.encaixes > 1 ? "s" : ""}`}
          {a.aguardando > 0 && <span className="text-info"> · {a.aguardando} aguardando</span>}
        </p>
        {a.observacao && <p className="mt-1 line-clamp-2 text-xs italic text-muted-foreground">{a.observacao}</p>}
      </button>
      {onEditar && (
        <Button variant="ghost" size="icon" className="absolute right-1 top-1 h-8 w-8" onClick={onEditar} aria-label="Editar agenda">
          <Pencil />
        </Button>
      )}
    </div>
  );
}

function esperaDesde(v: string | null) {
  if (!v) return null;
  const min = Math.max(0, Math.round((Date.now() - new Date(v).getTime()) / 60_000));
  return min < 60 ? `${min} min` : `${Math.floor(min / 60)}h${String(min % 60).padStart(2, "0")}`;
}

function LinhaPaciente({ p, data, agenda, onEditar }: { p: Agendamento; data: string; agenda: string | null; onEditar: () => void }) {
  const { tem } = useSessao();
  const recepcao = tem("gestor", "operacoes");
  const situacao = useSituacaoAgendamento();
  const [cancelar, setCancelar] = useState(false);
  const [historico, setHistorico] = useState(false);
  const st = situacaoAtendimento(p.situacao);
  const muda = (s: SituacaoAgendamento, motivo?: string) => situacao.mutate({ id: p.id, situacao: s, motivo, data });

  const principal: { rotulo: string; para: SituacaoAgendamento } | null = !recepcao
    ? null
    : p.situacao === "agendado"
      ? { rotulo: "Chegou", para: "aguardando" }
      : p.situacao === "aguardando"
        ? { rotulo: "Atender", para: "atendido" }
        : p.situacao === "atendido"
          ? { rotulo: "Finalizar", para: "finalizado" }
          : null;

  return (
    <div className={cn("flex flex-col gap-2 border-l-4 p-3 sm:flex-row sm:items-center sm:gap-4", faixa[p.situacao])}>
      <div className="w-14 shrink-0 text-sm tabular-nums text-muted-foreground">{p.horario ? p.horario.slice(0, 5) : p.chegou_em ? fmtHora(p.chegou_em) : "—"}</div>
      <div className="min-w-0 flex-1">
        <p className="flex flex-wrap items-center gap-1.5">
          <span className={cn("font-medium", p.situacao === "cancelado" && "line-through")}>{p.paciente_nome}</span>
          {p.encaixe && <Badge variant="outline">Encaixe</Badge>}
          {p.inadimplente && (
            <Badge variant="destructive">
              <ShieldAlert className="h-3 w-3" aria-hidden /> Inadimplente
            </Badge>
          )}
          {p.excecao_motivo && (
            <Badge variant="warning" title={p.excecao_motivo}>
              Liberado fora da regra
            </Badge>
          )}
          {(p.complementares ?? []).map((c) => (
            <Badge key={c} variant="info">
              {c}
            </Badge>
          ))}
        </p>
        <p className="truncate text-xs text-muted-foreground">
          {p.empresa ?? "—"}
          {p.cpf && ` · CPF ${fmtCpf(p.cpf)}`} · {tipoExame[p.tipo] ?? p.tipo}
          {p.funcao && ` · ${p.funcao}`}
          {agenda && ` · ${agenda}`}
        </p>
        {p.situacao === "cancelado" && p.cancelado_motivo && <p className="text-xs text-muted-foreground">Motivo: {p.cancelado_motivo}</p>}
        {p.observacao && <p className="text-xs italic text-muted-foreground">{p.observacao}</p>}
        {(p.criado_por || p.chegou_em) && (
          <p className="text-xs text-muted-foreground">
            {p.criado_por && <>Agendado por <span className={cn(p.criado_por.startsWith("IA") && "font-medium text-primary")}>{p.criado_por}</span></>}
            {p.criado_por && p.chegou_em && " · "}
            {p.chegou_em && <>Chegou {fmtHora(p.chegou_em)}</>}
          </p>
        )}
      </div>
      <div className="flex shrink-0 items-center gap-2">
        {p.situacao === "aguardando" && p.chegou_em && <span className="text-xs text-info">espera {esperaDesde(p.chegou_em)}</span>}
        <Badge variant={st.badge}>{st.rotulo}</Badge>
        {principal && (
          <Button size="sm" variant={p.situacao === "agendado" ? "default" : "outline"} onClick={() => muda(principal.para)} disabled={situacao.isPending}>
            {principal.rotulo}
          </Button>
        )}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon" className="h-8 w-8" aria-label={`Ações de ${p.paciente_nome}`}>
              <MoreHorizontal />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuLabel>#{p.numero}</DropdownMenuLabel>
            {!["finalizado", "cancelado"].includes(p.situacao) && <DropdownMenuItem onSelect={onEditar}>Editar / remarcar</DropdownMenuItem>}
            {recepcao && p.situacao === "agendado" && <DropdownMenuItem onSelect={() => muda("faltou")}>Faltou</DropdownMenuItem>}
            {recepcao && p.situacao === "aguardando" && <DropdownMenuItem onSelect={() => muda("agendado")}>Desfazer chegada</DropdownMenuItem>}
            {recepcao && p.situacao === "atendido" && <DropdownMenuItem onSelect={() => muda("aguardando")}>Voltar para aguardando</DropdownMenuItem>}
            {recepcao && p.situacao === "finalizado" && <DropdownMenuItem onSelect={() => muda("atendido")}>Reabrir</DropdownMenuItem>}
            {recepcao && ["cancelado", "faltou"].includes(p.situacao) && (
              <DropdownMenuItem onSelect={() => muda("agendado")}>Voltar para agendado</DropdownMenuItem>
            )}
            <DropdownMenuItem onSelect={() => setHistorico(true)}>
              <History className="h-4 w-4" /> Histórico
            </DropdownMenuItem>
            {["agendado", "aguardando"].includes(p.situacao) && (
              <>
                <DropdownMenuSeparator />
                <DropdownMenuItem className="text-destructive focus:text-destructive" onSelect={() => setCancelar(true)}>
                  Cancelar agendamento
                </DropdownMenuItem>
              </>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
      <CancelarDialog
        aberto={cancelar}
        nome={p.paciente_nome}
        onFechar={() => setCancelar(false)}
        onConfirmar={(m) => {
          muda("cancelado", m);
          setCancelar(false);
        }}
      />
      <HistoricoDialog id={historico ? p.id : null} nome={p.paciente_nome} onFechar={() => setHistorico(false)} />
    </div>
  );
}

const MOTIVOS = ["Pedido da empresa", "Pedido do colaborador", "Remarcado", "Empresa inadimplente", "Duplicado"];

function CancelarDialog({ aberto, nome, onFechar, onConfirmar }: { aberto: boolean; nome: string; onFechar: () => void; onConfirmar: (m: string) => void }) {
  const [motivo, setMotivo] = useState("");
  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Cancelar agendamento</DialogTitle>
          <DialogDescription>{nome} — a vaga volta a ficar livre.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-wrap gap-2">
          {MOTIVOS.map((m) => (
            <Button key={m} type="button" size="sm" variant={motivo === m ? "default" : "outline"} onClick={() => setMotivo(m)}>
              {m}
            </Button>
          ))}
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="cancel-motivo">Motivo</Label>
          <Textarea id="cancel-motivo" rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)} />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onFechar}>
            Voltar
          </Button>
          <Button
            variant="destructive"
            disabled={!motivo.trim()}
            onClick={() => {
              onConfirmar(motivo.trim());
              setMotivo("");
            }}
          >
            Cancelar agendamento
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function HistoricoDialog({ id, nome, onFechar }: { id: string | null; nome: string; onFechar: () => void }) {
  const q = useAgendamentoHistorico(id);
  return (
    <Dialog open={!!id} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Histórico</DialogTitle>
          <DialogDescription>{nome}</DialogDescription>
        </DialogHeader>
        {q.isError ? (
          <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
        ) : q.isLoading ? (
          <Skeleton className="h-24 w-full" />
        ) : (
          <ol className="space-y-3">
            {q.data?.map((e, i) => (
              <li key={i} className="border-l-2 border-primary/30 pl-3">
                <p className="text-sm">{e.texto}</p>
                <p className="text-xs text-muted-foreground">
                  {e.autor} · {fmtDataHora(e.criado_em)}
                </p>
              </li>
            ))}
          </ol>
        )}
      </DialogContent>
    </Dialog>
  );
}

// ------------------------------------------------------------------ semana

function Semana({ data, onAbrirDia }: { data: string; onAbrirDia: (d: string, agenda: string | null) => void }) {
  const ini = inicioSemana(data);
  const dias = Array.from({ length: 7 }, (_, i) => somaDias(ini, i));
  const q = useAgendaPeriodo(ini, dias[6]);
  const hoje = hojeIso();

  if (q.isError) return <EstadoErro erro={q.error} onTentar={() => q.refetch()} />;

  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-7">
      {dias.map((d) => {
        const doDia = q.data?.filter((a) => a.data === d) ?? [];
        const total = doDia.reduce((s, a) => s + a.ocupadas + a.encaixes, 0);
        const vagas = doDia.reduce((s, a) => s + a.vagas, 0);
        const fimDeSemana = [0, 6].includes(dataDeIso(d).getDay());
        return (
          <Card key={d} className={cn("flex min-h-[160px] flex-col", d === hoje && "border-primary ring-1 ring-primary", fimDeSemana && !doDia.length && "opacity-60")}>
            <button
              type="button"
              onClick={() => onAbrirDia(d, null)}
              className="flex items-baseline justify-between gap-2 rounded-t-lg border-b px-3 py-2 text-left hover:bg-accent/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <span className="text-sm font-semibold capitalize">{fmtDiaSemana(d, "short").replace(".", "")}</span>
              <span className="text-xs text-muted-foreground">{d.slice(8, 10) + "/" + d.slice(5, 7)}</span>
            </button>
            <div className="flex-1 space-y-2 p-2">
              {q.isLoading ? (
                <Skeleton className="h-14 w-full" />
              ) : doDia.length === 0 ? (
                <p className="px-1 py-2 text-xs text-muted-foreground">Sem agenda</p>
              ) : (
                doDia.map((a) => {
                  const pct = Math.min(100, Math.round((a.ocupadas / a.vagas) * 100));
                  return (
                    <button
                      key={a.id}
                      type="button"
                      onClick={() => onAbrirDia(d, a.id)}
                      className="w-full rounded-md border bg-background p-2 text-left text-xs hover:border-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                      <p className="truncate font-medium">{a.profissional ?? "A definir"}</p>
                      <p className="truncate text-muted-foreground">
                        {a.hora_inicio ?? ""} {a.local === "in_company" ? `· ${a.empresa}` : "· Clínica"}
                      </p>
                      <div className="mt-1.5 h-1 overflow-hidden rounded-full bg-muted">
                        <div className={cn("h-full", pct >= 100 ? "bg-destructive" : pct >= 80 ? "bg-warning" : "bg-success")} style={{ width: `${pct}%` }} />
                      </div>
                      <p className="mt-1 tabular-nums text-muted-foreground">
                        {a.ocupadas}/{a.vagas}
                        {a.encaixes > 0 && ` +${a.encaixes}`}
                      </p>
                    </button>
                  );
                })
              )}
            </div>
            {doDia.length > 0 && (
              <p className="border-t px-3 py-1.5 text-xs text-muted-foreground">
                <span className="font-semibold tabular-nums text-foreground">{total}</span> pacientes · {Math.max(0, vagas - doDia.reduce((s, a) => s + a.ocupadas, 0))} vagas livres
              </p>
            )}
          </Card>
        );
      })}
    </div>
  );
}
