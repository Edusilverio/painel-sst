import { useEffect, useState } from "react";
import { AlertTriangle, Info, Loader2, ShieldAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { EmpresaSelect, type EmpresaEscolhida } from "@/components/crm/EmpresaSelect";
import { useAgendaChecar, useAgendaHorarios, useAgendaPeriodo, useAgendaRegras, useSalvarAgendamento } from "@/hooks/api";
import { tipoExame } from "@/lib/status";
import type { AgendaLinha, Agendamento } from "@/lib/tipos";
import { fmtCpf } from "@/lib/utils";

const vazio = { agenda_id: "", horario: "", paciente_nome: "", cpf: "", telefone: "", funcao: "", tipo: "periodico", empresa_nome: "", observacao: "", excecao_motivo: "" };

/** Os que aparecem na planilha da agenda (coluna OBS) e os mais comuns do PCMSO. */
const COMPLEMENTARES = ["AUDIO", "ACUIDADE", "ALTURA", "BETA", "FEZES", "HEMOGRAMA", "GLICEMIA", "ESPIROMETRIA", "RX TÓRAX", "ECG", "EEG", "TOXICOLÓGICO"];

/**
 * Agenda (ou edita) um paciente. As regras moram no banco; aqui só se mostra o resultado
 * da checagem enquanto a pessoa preenche, para ela não descobrir o bloqueio no fim.
 */
export function AgendamentoDialog({
  aberto,
  onFechar,
  data,
  agendaInicial,
  agendamento,
}: {
  aberto: boolean;
  onFechar: () => void;
  data: string;
  agendaInicial: string | null;
  agendamento: Agendamento | null;
}) {
  const regras = useAgendaRegras();
  // Remarcar para outro dia: o diálogo carrega as agendas da data escolhida nele.
  const [dia, setDia] = useState(data);
  const periodo = useAgendaPeriodo(dia, dia);
  const agendas = periodo.data ?? [];
  const salvar = useSalvarAgendamento();
  const [f, setF] = useState(vazio);
  const [empresa, setEmpresa] = useState<EmpresaEscolhida | null>(null);
  const [particular, setParticular] = useState(false);
  const [encaixe, setEncaixe] = useState(false);
  const [comp, setComp] = useState<string[]>([]);
  const [outroComp, setOutroComp] = useState("");

  // Abriu: preenche o formulário uma vez (o refetch das agendas não pode apagar o que se digita).
  useEffect(() => {
    if (!aberto) return;
    setDia(data);
    if (agendamento) {
      setF({
        agenda_id: agendamento.agenda_id,
        horario: (agendamento.horario ?? "").slice(0, 5),
        paciente_nome: agendamento.paciente_nome,
        cpf: fmtCpf(agendamento.cpf),
        telefone: agendamento.telefone ?? "",
        funcao: agendamento.funcao ?? "",
        tipo: agendamento.tipo,
        empresa_nome: agendamento.empresa_id ? "" : (agendamento.empresa ?? ""),
        observacao: agendamento.observacao ?? "",
        excecao_motivo: "",
      });
      setEmpresa(agendamento.empresa_id ? { id: agendamento.empresa_id, nome: agendamento.empresa ?? "", cnpj: null } : null);
      setParticular(!agendamento.empresa_id);
      setEncaixe(agendamento.encaixe);
      setComp(agendamento.complementares ?? []);
    } else {
      setF({ ...vazio, agenda_id: agendaInicial ?? "" });
      setEmpresa(null);
      setParticular(false);
      setEncaixe(false);
      setComp([]);
    }
    setOutroComp("");
  }, [aberto, agendamento, agendaInicial, data]);

  // Agendas do dia escolhido chegaram: se a selecionada não é deste dia, sugere uma.
  useEffect(() => {
    if (!aberto || !periodo.data || periodo.isPlaceholderData) return;
    if (periodo.data.some((a) => a.id === f.agenda_id)) return;
    const ag = periodo.data.find((a) => a.id === agendaInicial) ?? (periodo.data.length === 1 ? periodo.data[0] : null);
    setF((x) => ({ ...x, agenda_id: ag?.id ?? "" }));
    // In company: a empresa já é a da agenda.
    if (!agendamento && ag?.local === "in_company" && ag.empresa_id) setEmpresa({ id: ag.empresa_id, nome: ag.empresa ?? "", cnpj: null });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [aberto, periodo.data, periodo.isPlaceholderData]);

  // Grade (0079): horários com vagas; encaixe (fora das vagas) só quem tem permissão — vem do banco.
  const grade = useAgendaHorarios(aberto ? f.agenda_id || null : null, agendamento?.id ?? null);
  const horarios = grade.data?.horarios ?? [];
  const podeEncaixe = grade.data?.pode_encaixe ?? false;
  const chk = useAgendaChecar(aberto ? f.agenda_id || null : null, particular ? null : (empresa?.id ?? null), encaixe, agendamento?.id ?? null, f.tipo);
  const bloqueios = chk.data?.bloqueios ?? [];
  const avisos = chk.data?.avisos ?? [];
  // Editar sem mexer em agenda/empresa/encaixe não reavalia a regra no banco.
  const mudouVaga = !agendamento || agendamento.agenda_id !== f.agenda_id || agendamento.empresa_id !== (particular ? null : (empresa?.id ?? null)) || agendamento.encaixe !== encaixe || (agendamento.horario ?? "").slice(0, 5) !== f.horario;
  const bloqueado = mudouVaga && bloqueios.length > 0;
  const podeExcecao = !!regras.data?.pode_excecao;
  const lotada = chk.data ? chk.data.ocupadas >= chk.data.vagas : false;

  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF((x) => ({ ...x, [k]: e.target.value }));
  const cpfDig = f.cpf.replace(/\D/g, "");
  const invalido =
    !f.agenda_id ||
    f.paciente_nome.trim().length < 2 ||
    (particular ? !f.empresa_nome.trim() : !empresa) ||
    (cpfDig.length > 0 && cpfDig.length !== 11) ||
    (bloqueado && (!podeExcecao || !f.excecao_motivo.trim()));

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    const r = await salvar
      .mutateAsync({
        id: agendamento?.id ?? null,
        dados: {
          agenda_id: f.agenda_id,
          horario: f.horario || null,
          paciente_nome: f.paciente_nome,
          cpf: cpfDig || null,
          telefone: f.telefone,
          funcao: f.funcao,
          tipo: f.tipo,
          empresa_id: particular ? null : empresa?.id,
          empresa_nome: particular ? f.empresa_nome : null,
          encaixe,
          observacao: f.observacao,
          complementares: comp,
          excecao_motivo: bloqueado ? f.excecao_motivo : null,
          negocio_id: agendamento?.negocio_id ?? null,
        },
      })
      .catch(() => null);
    if (r) onFechar();
  }

  const rotuloAgenda = (a: AgendaLinha) =>
    `${a.hora_inicio ?? "--:--"} · ${a.profissional ?? "Profissional a definir"} · ${a.local === "in_company" ? `In company (${a.empresa})` : "Clínica"} · ${a.ocupadas}/${a.vagas}`;

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-h-[92vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{agendamento ? `Agendamento #${agendamento.numero}` : "Agendar paciente"}</DialogTitle>
          <DialogDescription>Nome e empresa bastam para reservar a vaga. CPF e função podem vir depois, na recepção.</DialogDescription>
        </DialogHeader>
        <form onSubmit={enviar} className="grid gap-4 sm:grid-cols-6">
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="am-dia">Dia</Label>
              <Input id="am-dia" type="date" value={dia} onChange={(e) => e.target.value && setDia(e.target.value)} />
            </div>
            <div className="space-y-1.5 sm:col-span-3">
              <Label>Agenda</Label>
              <Select value={f.agenda_id} onValueChange={(v) => setF((x) => ({ ...x, agenda_id: v }))} disabled={agendas.length === 0}>
                <SelectTrigger>
                  <SelectValue placeholder={periodo.isFetching ? "Carregando…" : agendas.length ? "Escolha a agenda" : "Nenhuma agenda neste dia"} />
                </SelectTrigger>
                <SelectContent>
                  {agendas.map((a) => (
                    <SelectItem key={a.id} value={a.id}>
                      {rotuloAgenda(a)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5 sm:col-span-1">
              <Label htmlFor="am-hora">Horário</Label>
              {encaixe || horarios.length === 0 ? (
                <Input id="am-hora" type="time" value={f.horario} onChange={set("horario")} aria-describedby="am-hora-dica" />
              ) : (
                <Select value={f.horario} onValueChange={(v) => setF((x) => ({ ...x, horario: v }))}>
                  <SelectTrigger id="am-hora" aria-describedby="am-hora-dica">
                    <SelectValue placeholder="Escolha" />
                  </SelectTrigger>
                  <SelectContent>
                    {horarios.map((h) => (
                      <SelectItem key={h.horario} value={h.horario} disabled={h.livres <= 0 && h.horario !== (agendamento?.horario ?? "").slice(0, 5)}>
                        {h.horario} · {h.livres > 0 ? `${h.livres} ${h.livres === 1 ? "vaga" : "vagas"}` : "lotado"}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
              <p id="am-hora-dica" className="sr-only">
                {encaixe ? "Encaixe: horário livre" : "Horários da grade com vagas"}
              </p>
            </div>

            {!periodo.isFetching && agendas.length === 0 && (
              <p className="rounded-md border border-dashed p-3 text-sm text-muted-foreground sm:col-span-6">Não há agenda aberta neste dia. Crie a agenda do profissional antes de agendar.</p>
            )}
            <div className="space-y-1.5 sm:col-span-4">
              <Label htmlFor="am-nome">Paciente</Label>
              <Input id="am-nome" value={f.paciente_nome} onChange={set("paciente_nome")} placeholder="Nome completo" required autoFocus />
            </div>
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="am-cpf">CPF</Label>
              <Input
                id="am-cpf"
                inputMode="numeric"
                value={f.cpf}
                onChange={(e) => setF((x) => ({ ...x, cpf: e.target.value }))}
                onBlur={() => setF((x) => ({ ...x, cpf: fmtCpf(x.cpf) }))}
                placeholder="000.000.000-00"
                aria-invalid={cpfDig.length > 0 && cpfDig.length !== 11}
              />
            </div>

            <div className="space-y-1.5 sm:col-span-6">
              <div className="flex items-center justify-between">
                <Label htmlFor="am-empresa">Empresa</Label>
                <button
                  type="button"
                  className="text-xs text-primary hover:underline"
                  onClick={() => {
                    setParticular((p) => !p);
                    setEmpresa(null);
                  }}
                >
                  {particular ? "Buscar na base de clientes" : "Particular / empresa sem cadastro"}
                </button>
              </div>
              {particular ? (
                <Input id="am-empresa" value={f.empresa_nome} onChange={set("empresa_nome")} placeholder='Ex.: "Particular" ou nome da empresa' />
              ) : (
                <EmpresaSelect id="am-empresa" valor={empresa} onChange={setEmpresa} />
              )}
            </div>

            <div className="space-y-1.5 sm:col-span-2">
              <Label>Tipo de exame</Label>
              <Select value={f.tipo} onValueChange={(v) => setF((x) => ({ ...x, tipo: v }))}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {Object.entries(tipoExame).map(([v, r]) => (
                    <SelectItem key={v} value={v}>
                      {r}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="am-funcao">Função</Label>
              <Input id="am-funcao" value={f.funcao} onChange={set("funcao")} />
            </div>
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="am-tel">Telefone</Label>
              <Input id="am-tel" type="tel" value={f.telefone} onChange={set("telefone")} placeholder="(11) 90000-0000" />
            </div>
            <fieldset className="space-y-1.5 sm:col-span-6">
              <legend className="text-sm font-medium">Exames complementares</legend>
              <div className="flex flex-wrap gap-1.5">
                {[...COMPLEMENTARES, ...comp.filter((c) => !COMPLEMENTARES.includes(c))].map((c) => {
                  const on = comp.includes(c);
                  return (
                    <button
                      key={c}
                      type="button"
                      aria-pressed={on}
                      onClick={() => setComp((x) => (on ? x.filter((y) => y !== c) : [...x, c]))}
                      className={
                        "rounded-full border px-2.5 py-0.5 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring " +
                        (on ? "border-primary bg-primary text-primary-foreground" : "text-muted-foreground hover:bg-accent")
                      }
                    >
                      {c}
                    </button>
                  );
                })}
                <Input
                  aria-label="Outro exame complementar"
                  value={outroComp}
                  onChange={(e) => setOutroComp(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && outroComp.trim()) {
                      e.preventDefault();
                      const v = outroComp.trim().toUpperCase();
                      setComp((x) => (x.includes(v) ? x : [...x, v]));
                      setOutroComp("");
                    }
                  }}
                  placeholder="Outro + Enter"
                  className="h-7 w-32 text-xs"
                />
              </div>
            </fieldset>
            <div className="space-y-1.5 sm:col-span-6">
              <Label htmlFor="am-obs">Observação</Label>
              <Textarea id="am-obs" rows={2} value={f.observacao} onChange={set("observacao")} />
            </div>

            {/* 0078: encaixe só o atendimento marca (comercial não) */}
            {(podeEncaixe || encaixe) && (
            <label className="flex items-start gap-2 text-sm sm:col-span-6">
              <input type="checkbox" className="mt-0.5 h-4 w-4 accent-[hsl(var(--primary))]" checked={encaixe} disabled={!podeEncaixe} onChange={(e) => setEncaixe(e.target.checked)} />
              <span>
                <span className="font-medium">Encaixe</span>
                <span className="block text-xs text-muted-foreground">Fora das vagas da agenda (quem aparece na porta, urgência).{lotada && !encaixe && " A agenda está lotada."}</span>
              </span>
            </label>
            )}

            {(bloqueado || avisos.length > 0 || chk.isFetching) && (
              <div className="space-y-2 sm:col-span-6" aria-live="polite">
                {chk.isFetching && (
                  <p className="flex items-center gap-2 text-xs text-muted-foreground">
                    <Loader2 className="h-3 w-3 animate-spin" /> Conferindo vagas e regras…
                  </p>
                )}
                {bloqueado &&
                  bloqueios.map((b) => (
                    <p key={b} className="flex items-start gap-2 rounded-md border border-destructive/40 bg-destructive/5 p-2.5 text-sm text-destructive">
                      <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0" aria-hidden /> {b}
                    </p>
                  ))}
                {avisos.map((a) => (
                  <p key={a} className="flex items-start gap-2 rounded-md border border-warning/40 bg-warning/5 p-2.5 text-sm">
                    <Info className="mt-0.5 h-4 w-4 shrink-0 text-warning" aria-hidden /> {a}
                  </p>
                ))}
                {bloqueado &&
                  (podeExcecao ? (
                    <div className="space-y-1.5">
                      <Label htmlFor="am-exc">Liberar mesmo assim — motivo (fica no histórico)</Label>
                      <Input id="am-exc" value={f.excecao_motivo} onChange={set("excecao_motivo")} placeholder="Ex.: pagamento confirmado hoje pelo financeiro" />
                    </div>
                  ) : (
                    <p className="flex items-start gap-2 text-xs text-muted-foreground">
                      <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden /> {regras.data?.liberam?.length ? `Só ${regras.data.liberam.join(" ou ")} libera fora da regra.` : "Só quem tem permissão de liberar a agenda pode passar por cima da regra."}
                    </p>
                  ))}
              </div>
            )}

            <DialogFooter className="sm:col-span-6">
              <Button type="button" variant="outline" onClick={onFechar}>
                Cancelar
              </Button>
              <Button type="submit" disabled={invalido || salvar.isPending}>
                {salvar.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
                {agendamento ? "Salvar" : "Agendar"}
              </Button>
            </DialogFooter>
          </form>
      </DialogContent>
    </Dialog>
  );
}
