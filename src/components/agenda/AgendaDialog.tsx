import { useEffect, useState } from "react";
import { Loader2, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { EmpresaSelect, type EmpresaEscolhida } from "@/components/crm/EmpresaSelect";
import { useAgendaRegras, useExcluirAgenda, useProfissionais, useSalvarAgenda } from "@/hooks/api";
import type { AgendaLinha } from "@/lib/tipos";

const SEM = "__sem__";

/** Cria ou edita a agenda de um profissional num dia (clínica ou in company). */
export function AgendaDialog({ aberto, onFechar, data, agenda }: { aberto: boolean; onFechar: () => void; data: string; agenda: AgendaLinha | null }) {
  const regras = useAgendaRegras();
  const profs = useProfissionais();
  const salvar = useSalvarAgenda();
  const excluir = useExcluirAgenda();
  const [f, setF] = useState({ data, profissional_id: SEM, local: "clinica", hora_inicio: "", hora_fim: "", vagas: "", observacao: "" });
  const [empresa, setEmpresa] = useState<EmpresaEscolhida | null>(null);
  const [confirmaExcluir, setConfirmaExcluir] = useState(false);

  useEffect(() => {
    if (!aberto) return;
    setConfirmaExcluir(false);
    if (agenda) {
      setF({
        data: agenda.data,
        profissional_id: agenda.profissional_id ?? SEM,
        local: agenda.local,
        hora_inicio: agenda.hora_inicio ?? "",
        hora_fim: agenda.hora_fim ?? "",
        vagas: String(agenda.vagas),
        observacao: agenda.observacao ?? "",
      });
      setEmpresa(agenda.empresa_id ? { id: agenda.empresa_id, nome: agenda.empresa ?? "", cnpj: null } : null);
    } else {
      setF({
        data,
        profissional_id: SEM,
        local: "clinica",
        hora_inicio: regras.data?.hora_inicio_padrao ?? "",
        hora_fim: regras.data?.hora_fim_padrao ?? "",
        vagas: String(regras.data?.vagas_padrao ?? 40),
        observacao: "",
      });
      setEmpresa(null);
    }
  }, [aberto, agenda, data, regras.data]);

  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF((x) => ({ ...x, [k]: e.target.value }));
  const ativos = profs.data?.filter((p) => p.ativo || p.id === f.profissional_id) ?? [];
  const invalido = !f.data || !Number(f.vagas) || (f.local === "in_company" && !empresa);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    const ok = await salvar
      .mutateAsync({
        id: agenda?.id ?? null,
        dados: {
          data: f.data,
          profissional_id: f.profissional_id === SEM ? null : f.profissional_id,
          local: f.local,
          empresa_id: f.local === "in_company" ? empresa?.id : null,
          hora_inicio: f.hora_inicio || null,
          hora_fim: f.hora_fim || null,
          vagas: Number(f.vagas),
          observacao: f.observacao,
        },
      })
      .catch(() => null);
    if (ok) onFechar();
  }

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{agenda ? "Editar agenda" : "Nova agenda"}</DialogTitle>
          <DialogDescription>Uma agenda por profissional e turno, como a planilha de hoje. In company: o profissional vai até a empresa.</DialogDescription>
        </DialogHeader>
        <form onSubmit={enviar} className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="ag-data">Data</Label>
            <Input id="ag-data" type="date" value={f.data} onChange={set("data")} required />
          </div>
          <div className="space-y-1.5">
            <Label>Local</Label>
            <Select value={f.local} onValueChange={(v) => setF((x) => ({ ...x, local: v }))}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="clinica">Clínica</SelectItem>
                <SelectItem value="in_company">In company</SelectItem>
              </SelectContent>
            </Select>
          </div>
          {f.local === "in_company" && (
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="ag-empresa">Empresa atendida</Label>
              <EmpresaSelect id="ag-empresa" valor={empresa} onChange={setEmpresa} />
            </div>
          )}
          <div className="space-y-1.5 sm:col-span-2">
            <Label>Profissional</Label>
            <Select value={f.profissional_id} onValueChange={(v) => setF((x) => ({ ...x, profissional_id: v }))}>
              <SelectTrigger>
                <SelectValue placeholder={profs.isLoading ? "Carregando…" : "Escolha"} />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={SEM}>A definir</SelectItem>
                {ativos.map((p) => (
                  <SelectItem key={p.id} value={p.id}>
                    {p.nome}
                    {p.conselho && p.registro ? ` · ${p.conselho} ${p.registro}` : ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-3 gap-3 sm:col-span-2">
            <div className="space-y-1.5">
              <Label htmlFor="ag-ini">Início</Label>
              <Input id="ag-ini" type="time" value={f.hora_inicio} onChange={set("hora_inicio")} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ag-fim">Fim</Label>
              <Input id="ag-fim" type="time" value={f.hora_fim} onChange={set("hora_fim")} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ag-vagas">Vagas</Label>
              <Input id="ag-vagas" type="number" min={1} max={500} value={f.vagas} onChange={set("vagas")} required />
            </div>
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="ag-obs">Observação</Label>
            <Textarea id="ag-obs" rows={2} value={f.observacao} onChange={set("observacao")} placeholder="Ex.: levar audiômetro; jejum para exames laboratoriais" />
          </div>
          <DialogFooter className="sm:col-span-2">
            {agenda &&
              (confirmaExcluir ? (
                <Button
                  type="button"
                  variant="destructive"
                  className="sm:mr-auto"
                  disabled={excluir.isPending}
                  onClick={() => excluir.mutateAsync(agenda.id).then(onFechar).catch(() => null)}
                >
                  Confirmar exclusão
                </Button>
              ) : (
                <Button type="button" variant="ghost" className="text-destructive sm:mr-auto" onClick={() => setConfirmaExcluir(true)}>
                  <Trash2 className="h-4 w-4" /> Excluir
                </Button>
              ))}
            <Button type="button" variant="outline" onClick={onFechar}>
              Cancelar
            </Button>
            <Button type="submit" disabled={invalido || salvar.isPending}>
              {salvar.isPending && <Loader2 className="h-4 w-4 animate-spin" />} Salvar
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
