import { useEffect, useState } from "react";
import { History, Loader2, Lock, RotateCcw, Save } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { fmtDataHora } from "@/lib/utils";
import type { EdicaoHistorico } from "@/lib/tipos";

export type Valor = string | boolean | null;
export type Valores = Record<string, Valor>;

export interface CampoDef {
  nome: string;
  rotulo: string;
  tipo?: "texto" | "data" | "hora" | "numero" | "email" | "select" | "checkbox" | "textarea";
  opcoes?: { valor: string; rotulo: string }[];
  largo?: boolean;
  placeholder?: string;
  obrigatorio?: boolean;
}

const VAZIO = "__vazio__";

/** Converte o que veio do banco para o que o formulário mostra (tudo texto, exceto checkbox). */
export function valoresDe(campos: CampoDef[], origem: Record<string, unknown>): Valores {
  return Object.fromEntries(
    campos.map((c) => {
      const v = origem[c.nome];
      if (c.tipo === "checkbox") return [c.nome, !!v];
      if (v == null) return [c.nome, ""];
      if (c.tipo === "data") return [c.nome, String(v).slice(0, 10)];
      return [c.nome, String(v)];
    }),
  );
}

/** Só o que mudou vai para o banco: campo não mexido não fica marcado como "editado no painel". */
function diferencas(inicial: Valores, atual: Valores) {
  const d: Valores = {};
  for (const k of Object.keys(atual)) if (atual[k] !== inicial[k]) d[k] = atual[k];
  return d;
}

/** Campos do formulário, em grade de duas colunas. */
export function Campos({ campos, valores, onMudar, desabilitado }: { campos: CampoDef[]; valores: Valores; onMudar: (v: Valores) => void; desabilitado?: boolean }) {
  const set = (k: string, v: Valor) => onMudar({ ...valores, [k]: v });
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {campos.map((c) => {
        const id = `cp-${c.nome}`;
        const v = valores[c.nome];
        if (c.tipo === "checkbox")
          return (
            <label key={c.nome} className={`flex items-center gap-2 text-sm ${c.largo ? "sm:col-span-2" : ""}`}>
              <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" checked={!!v} disabled={desabilitado} onChange={(e) => set(c.nome, e.target.checked)} />
              {c.rotulo}
            </label>
          );
        return (
          <div key={c.nome} className={`space-y-1.5 ${c.largo || c.tipo === "textarea" ? "sm:col-span-2" : ""}`}>
            <Label htmlFor={id}>
              {c.rotulo}
              {c.obrigatorio && <span className="text-destructive"> *</span>}
            </Label>
            {c.tipo === "select" ? (
              <Select value={(v as string) || VAZIO} onValueChange={(x) => set(c.nome, x === VAZIO ? "" : x)} disabled={desabilitado}>
                <SelectTrigger id={id}>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {!c.obrigatorio && <SelectItem value={VAZIO}>—</SelectItem>}
                  {c.opcoes?.map((o) => (
                    <SelectItem key={o.valor} value={o.valor}>
                      {o.rotulo}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            ) : c.tipo === "textarea" ? (
              <Textarea id={id} rows={3} value={(v as string) ?? ""} disabled={desabilitado} onChange={(e) => set(c.nome, e.target.value)} />
            ) : (
              <Input
                id={id}
                type={c.tipo === "data" ? "date" : c.tipo === "hora" ? "time" : c.tipo === "numero" ? "number" : c.tipo === "email" ? "email" : "text"}
                value={(v as string) ?? ""}
                placeholder={c.placeholder}
                disabled={desabilitado}
                onChange={(e) => set(c.nome, e.target.value)}
              />
            )}
          </div>
        );
      })}
    </div>
  );
}

/** Aviso de campos corrigidos à mão: a carga do SESMO não mexe neles até alguém liberar. */
export function AvisoTravados({ campos, rotulos, onLiberar }: { campos: string[]; rotulos: Record<string, string>; onLiberar?: () => Promise<void> }) {
  const [liberando, setLiberando] = useState(false);
  if (campos.length === 0) return null;
  return (
    <div className="flex flex-col gap-2 rounded-md border border-info/40 bg-info/5 p-2.5 text-sm sm:flex-row sm:items-center">
      <Lock className="h-4 w-4 shrink-0 text-info" aria-hidden />
      <p className="flex-1">
        Corrigido no painel: <strong>{campos.map((c) => rotulos[c] ?? c).join(", ")}</strong>. A atualização do SESMO não sobrescreve esses campos.
      </p>
      {onLiberar && (
        <Button
          size="sm"
          variant="outline"
          disabled={liberando}
          onClick={async () => {
            setLiberando(true);
            try {
              await onLiberar();
              toast.success("Voltou a seguir o SESMO na próxima atualização");
            } catch (e) {
              toast.error(e instanceof Error ? e.message : "Não foi possível liberar.");
            } finally {
              setLiberando(false);
            }
          }}
        >
          {liberando ? <Loader2 className="animate-spin" /> : <RotateCcw />} Voltar a seguir o SESMO
        </Button>
      )}
    </div>
  );
}

const fmtValor = (v: unknown) => {
  if (v == null || v === "") return "vazio";
  if (typeof v === "boolean") return v ? "sim" : "não";
  const s = String(v);
  if (/^\d{4}-\d{2}-\d{2}T/.test(s)) return fmtDataHora(s);
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s.split("-").reverse().join("/");
  return s;
};

const ACOES: Record<string, string> = { criar: "incluiu", editar: "alterou", excluir: "excluiu", liberar: "voltou a seguir o SESMO" };

export function HistoricoEdicao({ itens, rotulos }: { itens: EdicaoHistorico[]; rotulos: Record<string, string> }) {
  if (itens.length === 0) return null;
  return (
    <details className="rounded-md border p-2.5 text-sm">
      <summary className="flex cursor-pointer items-center gap-1.5 font-medium">
        <History className="h-4 w-4 text-muted-foreground" aria-hidden /> Histórico de alterações ({itens.length})
      </summary>
      <ul className="mt-2 space-y-2">
        {itens.map((h, i) => (
          <li key={i} className="border-l-2 pl-2.5">
            <p className="text-xs text-muted-foreground">
              {fmtDataHora(h.em)} · {h.usuario ?? "sistema"} {ACOES[h.acao] ?? h.acao}
            </p>
            {h.acao === "editar" &&
              Object.entries(h.mudancas).map(([k, m]) => (
                <p key={k}>
                  {rotulos[k] ?? k}: <span className="text-muted-foreground line-through">{fmtValor((m as { de: unknown }).de)}</span> → {fmtValor((m as { para: unknown }).para)}
                </p>
              ))}
          </li>
        ))}
      </ul>
    </details>
  );
}

/** Formulário de edição em janela. Manda só os campos alterados. */
export function FormDialog({
  titulo,
  descricao,
  campos,
  inicial,
  aberto,
  onFechar,
  onSalvar,
  rodape,
  largura = "max-w-2xl",
}: {
  titulo: string;
  descricao?: string;
  campos: CampoDef[];
  inicial: Valores;
  aberto: boolean;
  onFechar: () => void;
  onSalvar: (mudou: Valores, todos: Valores) => Promise<unknown>;
  rodape?: React.ReactNode;
  largura?: string;
}) {
  const [v, setV] = useState<Valores>(inicial);
  const [salvando, setSalvando] = useState(false);
  useEffect(() => {
    if (aberto) setV(inicial);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [aberto]);

  async function salvar() {
    const faltando = campos.filter((c) => c.obrigatorio && !v[c.nome]).map((c) => c.rotulo);
    if (faltando.length) return toast.error(`Preencha: ${faltando.join(", ")}.`);
    const mudou = diferencas(inicial, v);
    if (Object.keys(mudou).length === 0) return onFechar();
    setSalvando(true);
    try {
      await onSalvar(mudou, v);
      toast.success("Alterações salvas");
      onFechar();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível salvar.");
    } finally {
      setSalvando(false);
    }
  }

  return (
    <Dialog open={aberto} onOpenChange={(x) => !x && onFechar()}>
      <DialogContent className={`max-h-[92vh] overflow-y-auto ${largura}`}>
        <DialogHeader>
          <DialogTitle>{titulo}</DialogTitle>
          {descricao && <DialogDescription>{descricao}</DialogDescription>}
        </DialogHeader>
        <Campos campos={campos} valores={v} onMudar={setV} />
        {rodape}
        <DialogFooter>
          <Button variant="outline" onClick={onFechar}>
            Cancelar
          </Button>
          <Button onClick={salvar} disabled={salvando}>
            {salvando ? <Loader2 className="animate-spin" /> : <Save />} Salvar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
