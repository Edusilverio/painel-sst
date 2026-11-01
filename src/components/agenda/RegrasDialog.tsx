import { useEffect, useRef, useState } from "react";
import { useSessao } from "@/contexts/sessao";
import { Loader2, Plus, Trash2 } from "lucide-react";
import { EmpresaSelect, type EmpresaEscolhida } from "@/components/crm/EmpresaSelect";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useAgendaGrade, useAgendaLimiteSalvar, useAgendaRegras, useSalvarGrade, useSalvarRegrasAgenda } from "@/hooks/api";

/** Regras da agenda (gestor). Combinado com a Vitalis em 24/09: 40 vagas, limite 2 por empresa, exceção com a Helena. */
export function RegrasDialog({ aberto, onFechar }: { aberto: boolean; onFechar: () => void }) {
  const regras = useAgendaRegras();
  const salvar = useSalvarRegrasAgenda();
  const gestor = useSessao().tem("gestor");
  const [f, setF] = useState({ limite: "", bloquear: true, vagas: "40", ini: "08:30", fim: "11:30" });
  const carregou = useRef(false);

  useEffect(() => {
    if (!aberto) carregou.current = false;
    if (aberto && regras.data && !carregou.current) {
      carregou.current = true;
      setF({
        limite: regras.data.limite_empresa_dia ? String(regras.data.limite_empresa_dia) : "",
        bloquear: regras.data.bloquear_inadimplente,
        vagas: String(regras.data.vagas_padrao),
        ini: regras.data.hora_inicio_padrao,
        fim: regras.data.hora_fim_padrao,
      });
    }
  }, [aberto, regras.data]);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    const ok = await salvar
      .mutateAsync({ limite_empresa_dia: f.limite || "", bloquear_inadimplente: f.bloquear, vagas_padrao: f.vagas, hora_inicio_padrao: f.ini, hora_fim_padrao: f.fim })
      .then(() => true)
      .catch(() => false);
    if (ok) onFechar();
  }

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-h-[92vh] max-w-lg overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Regras da agenda</DialogTitle>
          <DialogDescription>Valem para quem agenda (recepção e comercial). {regras.data?.liberam?.length ? `Exceções com motivo: ${regras.data.liberam.join(", ")}.` : ""}</DialogDescription>
        </DialogHeader>
        <form onSubmit={enviar} className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="rg-limite">Limite de colaboradores por empresa por dia (clínica)</Label>
            <Input id="rg-limite" type="number" min={1} value={f.limite} onChange={(e) => setF((x) => ({ ...x, limite: e.target.value }))} placeholder="Sem limite" />
            <p className="text-xs text-muted-foreground">Combinado: 2. Vazio = sem limite. Não vale para agenda in company. Empresas com limite próprio ficam abaixo.</p>
          </div>
          <label className="flex items-start gap-2 text-sm">
            <input type="checkbox" className="mt-0.5 h-4 w-4 accent-[hsl(var(--primary))]" checked={f.bloquear} onChange={(e) => setF((x) => ({ ...x, bloquear: e.target.checked }))} />
            <span>
              <span className="font-medium">Bloquear empresa inadimplente</span>
              <span className="block text-xs text-muted-foreground">Empresa com card aberto em Pós-venda → Inadimplentes. Desmarcado, só avisa.</span>
            </span>
          </label>
          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="rg-vagas">Vagas padrão</Label>
              <Input id="rg-vagas" type="number" min={1} max={500} value={f.vagas} onChange={(e) => setF((x) => ({ ...x, vagas: e.target.value }))} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="rg-ini">Início</Label>
              <Input id="rg-ini" type="time" value={f.ini} onChange={(e) => setF((x) => ({ ...x, ini: e.target.value }))} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="rg-fim">Fim</Label>
              <Input id="rg-fim" type="time" value={f.fim} onChange={(e) => setF((x) => ({ ...x, fim: e.target.value }))} />
            </div>
          </div>
          {regras.data?.pode_excecao && <LimitesEmpresa />}
          {gestor && <GradeHorarios aberto={aberto} />}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={onFechar}>
              Cancelar
            </Button>
            <Button type="submit" disabled={salvar.isPending}>
              {salvar.isPending && <Loader2 className="h-4 w-4 animate-spin" />} Salvar regras
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Clientes com limite diferente do padrão (ex.: contratos grandes). Só quem libera exceções mexe. */
function LimitesEmpresa() {
  const regras = useAgendaRegras();
  const salvar = useAgendaLimiteSalvar();
  const [empresa, setEmpresa] = useState<EmpresaEscolhida | null>(null);
  const [limite, setLimite] = useState("");
  const limites = regras.data?.limites ?? [];
  return (
    <fieldset className="space-y-2 rounded-lg border p-3">
      <legend className="px-1 text-sm font-medium">Limite próprio por empresa</legend>
      {limites.length === 0 ? (
        <p className="text-xs text-muted-foreground">Nenhuma empresa com limite diferente do padrão.</p>
      ) : (
        <ul className="divide-y text-sm">
          {limites.map((l) => (
            <li key={l.empresa_id} className="flex items-center gap-2 py-1.5">
              <span className="min-w-0 flex-1 truncate">{l.empresa}</span>
              <span className="tabular-nums font-medium">{l.limite}/dia</span>
              <Button
                type="button"
                size="icon"
                variant="ghost"
                className="h-7 w-7 text-muted-foreground hover:text-destructive"
                aria-label={`Remover limite de ${l.empresa}`}
                onClick={() => salvar.mutate({ empresa: l.empresa_id, limite: null })}
              >
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            </li>
          ))}
        </ul>
      )}
      <div className="grid gap-2 sm:grid-cols-[1fr_90px_auto] sm:items-end">
        <div className="space-y-1">
          <Label htmlFor="lim-emp" className="text-xs">Empresa</Label>
          <EmpresaSelect id="lim-emp" valor={empresa} onChange={setEmpresa} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="lim-n" className="text-xs">Por dia</Label>
          <Input id="lim-n" type="number" min={1} value={limite} onChange={(e) => setLimite(e.target.value)} />
        </div>
        <Button
          type="button"
          variant="outline"
          disabled={!empresa || !Number(limite) || salvar.isPending}
          onClick={() =>
            empresa &&
            salvar.mutateAsync({ empresa: empresa.id, limite: Number(limite) }).then(() => {
              setEmpresa(null);
              setLimite("");
            }).catch(() => null)
          }
        >
          Adicionar
        </Button>
      </div>
    </fieldset>
  );
}

const paraMin = (h: string) => Number(h.slice(0, 2)) * 60 + Number(h.slice(3, 5));
const deMin = (m: number) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;

/**
 * Grade de horários (Renata, 14/10): a mesma para todos os profissionais. Cada horário tem N vagas; a soma é o
 * total do dia (40). Fora da grade, só o encaixe do atendimento. A IA agenda em qualquer horário com vaga.
 */
function GradeHorarios({ aberto }: { aberto: boolean }) {
  const grade = useAgendaGrade();
  const salvar = useSalvarGrade();
  const [linhas, setLinhas] = useState<{ horario: string; vagas: number }[]>([]);
  const [ger, setGer] = useState({ ini: "08:30", fim: "11:30", passo: "20", vagas: "4" });
  const carregou = useRef(false);

  useEffect(() => {
    if (!aberto) carregou.current = false;
    if (aberto && grade.data && !carregou.current) {
      carregou.current = true;
      setLinhas(grade.data);
    }
  }, [aberto, grade.data]);

  const total = linhas.reduce((t, l) => t + (Number(l.vagas) || 0), 0);
  const ordenar = (ls: { horario: string; vagas: number }[]) => [...ls].sort((a, b) => a.horario.localeCompare(b.horario));

  function gerar() {
    const ini = paraMin(ger.ini), fim = paraMin(ger.fim), passo = Number(ger.passo), vagas = Number(ger.vagas);
    if (!passo || passo < 5 || fim < ini || !vagas) return;
    const ls: { horario: string; vagas: number }[] = [];
    for (let m = ini; m <= fim; m += passo) ls.push({ horario: deMin(m), vagas });
    setLinhas(ls);
  }

  return (
    <fieldset className="space-y-2 rounded-lg border p-3">
      <legend className="px-1 text-sm font-medium">Grade de horários (todos os profissionais)</legend>
      <p className="text-xs text-muted-foreground">
        Posições por horário: <span className="font-semibold tabular-nums text-foreground">{total}</span> no dia. O teto de agendamentos é o campo "Vagas padrão" acima; passou dele, só encaixe do atendimento.
      </p>
      <div className="grid grid-cols-4 gap-2 rounded-md bg-muted/50 p-2">
        <div className="space-y-1">
          <Label htmlFor="gr-ini" className="text-xs">De</Label>
          <Input id="gr-ini" type="time" value={ger.ini} onChange={(e) => setGer((x) => ({ ...x, ini: e.target.value }))} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="gr-fim" className="text-xs">Até</Label>
          <Input id="gr-fim" type="time" value={ger.fim} onChange={(e) => setGer((x) => ({ ...x, fim: e.target.value }))} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="gr-passo" className="text-xs">A cada (min)</Label>
          <Input id="gr-passo" type="number" min={5} step={5} value={ger.passo} onChange={(e) => setGer((x) => ({ ...x, passo: e.target.value }))} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="gr-vagas" className="text-xs">Vagas cada</Label>
          <Input id="gr-vagas" type="number" min={1} value={ger.vagas} onChange={(e) => setGer((x) => ({ ...x, vagas: e.target.value }))} />
        </div>
        <Button type="button" variant="outline" size="sm" className="col-span-4" onClick={gerar}>
          Gerar grade
        </Button>
      </div>
      <ul className="grid max-h-56 gap-1 overflow-y-auto sm:grid-cols-2">
        {linhas.map((l, i) => (
          <li key={i} className="flex items-center gap-1.5">
            <Input
              type="time"
              aria-label="Horário"
              className="h-8"
              value={l.horario}
              onChange={(e) => setLinhas((ls) => ls.map((x, j) => (j === i ? { ...x, horario: e.target.value } : x)))}
            />
            <Input
              type="number"
              min={0}
              aria-label={`Vagas às ${l.horario}`}
              className="h-8 w-16"
              value={l.vagas}
              onChange={(e) => setLinhas((ls) => ls.map((x, j) => (j === i ? { ...x, vagas: Number(e.target.value) } : x)))}
            />
            <Button type="button" size="icon" variant="ghost" className="h-7 w-7 shrink-0 text-muted-foreground hover:text-destructive" aria-label={`Remover ${l.horario}`} onClick={() => setLinhas((ls) => ls.filter((_, j) => j !== i))}>
              <Trash2 className="h-3.5 w-3.5" />
            </Button>
          </li>
        ))}
      </ul>
      <div className="flex justify-between gap-2">
        <Button
          type="button"
          variant="ghost"
          size="sm"
          onClick={() => setLinhas((ls) => [...ls, { horario: ls.length ? deMin(paraMin(ls[ls.length - 1].horario) + 10) : "08:30", vagas: 1 }])}
        >
          <Plus className="h-4 w-4" /> Horário
        </Button>
        <Button
          type="button"
          size="sm"
          disabled={salvar.isPending || linhas.length === 0 || linhas.some((l) => !/^\d{2}:\d{2}/.test(l.horario))}
          onClick={() => salvar.mutateAsync(ordenar(linhas.filter((l) => l.vagas > 0))).then((g) => setLinhas(g as typeof linhas)).catch(() => null)}
        >
          {salvar.isPending && <Loader2 className="h-4 w-4 animate-spin" />} Salvar grade
        </Button>
      </div>
    </fieldset>
  );
}
