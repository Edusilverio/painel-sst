import { useEffect, useState } from "react";
import { AlarmClock, ArrowDown, ArrowUp, Loader2, Pencil, Plus, Shuffle } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { EstadoErro } from "@/components/ui/estados";
import { useFunis, useReordenarEtapas, useResponsaveis, useRodizio, useSalvarEtapa, useSalvarRodizio } from "@/hooks/api";
import { corEtapa } from "@/lib/status";
import { rotuloPapel, type CorEtapa, type Etapa, type Funil } from "@/lib/tipos";
import { cn } from "@/lib/utils";

const CORES: { valor: CorEtapa; rotulo: string }[] = [
  { valor: "info", rotulo: "Azul" },
  { valor: "primary", rotulo: "Vinho" },
  { valor: "marca", rotulo: "Laranja" },
  { valor: "warning", rotulo: "Amarelo" },
  { valor: "success", rotulo: "Verde" },
  { valor: "destructive", rotulo: "Vermelho" },
  { valor: "muted", rotulo: "Cinza" },
];

export default function ConfigFunis() {
  const funis = useFunis();
  const [sel, setSel] = useState<string | null>(null);
  const funil = funis.data?.find((f) => f.id === sel) ?? funis.data?.[0];

  return (
    <div className="mx-auto max-w-5xl space-y-5 p-4 sm:p-6">
      <Cabecalho titulo="Funis e etapas" descricao="Etapas, cores, prazo de aviso e rodízio de responsáveis. Mudanças valem na hora para todos." />
      {funis.isLoading && <Skeleton className="h-64 w-full" />}
      {funis.isError && <EstadoErro erro={funis.error} onTentar={() => funis.refetch()} />}
      {funis.data && funil && (
        <>
          <div className="flex flex-wrap gap-1">
            {funis.data.map((f) => (
              <Button key={f.id} size="sm" variant={f.id === funil.id ? "default" : "outline"} onClick={() => setSel(f.id)}>
                {f.nome}
              </Button>
            ))}
          </div>
          <Etapas funil={funil} />
          {funil.usa_rodizio && <Rodizio funil={funil} />}
        </>
      )}
    </div>
  );
}

function Etapas({ funil }: { funil: Funil }) {
  const [editando, setEditando] = useState<Partial<Etapa> | null>(null);
  const reordenar = useReordenarEtapas();
  const etapas = [...funil.etapas].sort((a, b) => a.ordem - b.ordem);

  function mover(i: number, d: -1 | 1) {
    const ids = etapas.map((e) => e.id);
    const j = i + d;
    if (j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j], ids[i]];
    reordenar.mutate({ funil: funil.id, ids });
  }

  return (
    <Card>
      <CardHeader className="flex-row items-start justify-between space-y-0">
        <div>
          <CardTitle>Etapas de {funil.nome}</CardTitle>
          <CardDescription>
            Operam este funil: {funil.papeis.map(rotuloPapel).join(", ")} (gestor e administrador sempre).
          </CardDescription>
        </div>
        <Button size="sm" onClick={() => setEditando({ tipo: "aberta", cor: "info", ativo: true, alerta_dias: null })}>
          <Plus /> Etapa
        </Button>
      </CardHeader>
      <CardContent>
        <ul className="divide-y rounded-lg border">
          {etapas.map((e, i) => (
            <li key={e.id} className={cn("flex items-center gap-3 p-3 text-sm", !e.ativo && "opacity-50")}>
              <span className={cn("h-3 w-3 shrink-0 rounded-full", corEtapa[e.cor].ponto)} aria-hidden />
              <span className="flex-1 font-medium">
                {e.nome} {!e.ativo && <Badge variant="muted">desativada</Badge>}
              </span>
              {e.tipo !== "aberta" && <Badge variant={e.tipo === "ganho" ? "success" : "destructive"}>{e.tipo === "ganho" ? "ganho" : "perdido"}</Badge>}
              {e.alerta_dias && (
                <Badge variant="warning">
                  <AlarmClock className="h-3 w-3" /> {e.alerta_dias}d
                </Badge>
              )}
              <div className="flex">
                <Button variant="ghost" size="icon" onClick={() => mover(i, -1)} disabled={i === 0 || reordenar.isPending} aria-label={`Subir ${e.nome}`}>
                  <ArrowUp className="h-4 w-4" />
                </Button>
                <Button variant="ghost" size="icon" onClick={() => mover(i, 1)} disabled={i === etapas.length - 1 || reordenar.isPending} aria-label={`Descer ${e.nome}`}>
                  <ArrowDown className="h-4 w-4" />
                </Button>
                <Button variant="ghost" size="icon" onClick={() => setEditando(e)} aria-label={`Editar ${e.nome}`}>
                  <Pencil className="h-4 w-4" />
                </Button>
              </div>
            </li>
          ))}
        </ul>
      </CardContent>
      {editando && <EditarEtapa funil={funil} inicial={editando} onFechar={() => setEditando(null)} />}
    </Card>
  );
}

function EditarEtapa({ funil, inicial, onFechar }: { funil: Funil; inicial: Partial<Etapa>; onFechar: () => void }) {
  const salvar = useSalvarEtapa();
  const [e, setE] = useState({
    nome: inicial.nome ?? "",
    tipo: inicial.tipo ?? "aberta",
    cor: inicial.cor ?? "info",
    alerta: inicial.alerta_dias ? String(inicial.alerta_dias) : "",
    ativo: inicial.ativo ?? true,
  });
  return (
    <Dialog open onOpenChange={(v) => !v && onFechar()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{inicial.id ? "Editar etapa" : "Nova etapa"}</DialogTitle>
        </DialogHeader>
        <form
          className="grid gap-3 sm:grid-cols-2"
          onSubmit={(ev) => {
            ev.preventDefault();
            salvar.mutate(
              { id: inicial.id ?? null, funil: funil.id, nome: e.nome, tipo: e.tipo, cor: e.cor, alerta_dias: e.alerta ? Number(e.alerta) : null, ativo: e.ativo },
              { onSuccess: onFechar },
            );
          }}
        >
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="e-nome">Nome</Label>
            <Input id="e-nome" value={e.nome} onChange={(x) => setE({ ...e, nome: x.target.value })} required />
          </div>
          <div className="space-y-1.5">
            <Label>Tipo</Label>
            <Select value={e.tipo} onValueChange={(v) => setE({ ...e, tipo: v as Etapa["tipo"] })}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="aberta">Em andamento</SelectItem>
                <SelectItem value="ganho">Fechamento: ganho</SelectItem>
                <SelectItem value="perdido">Fechamento: perdido</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Cor</Label>
            <Select value={e.cor} onValueChange={(v) => setE({ ...e, cor: v as CorEtapa })}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {CORES.map((c) => (
                  <SelectItem key={c.valor} value={c.valor}>
                    <span className="flex items-center gap-2">
                      <span className={cn("h-3 w-3 rounded-full", corEtapa[c.valor].ponto)} /> {c.rotulo}
                    </span>
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="e-alerta">Avisar se parado por (dias)</Label>
            <Input id="e-alerta" type="number" min={1} value={e.alerta} onChange={(x) => setE({ ...e, alerta: x.target.value })} placeholder="sem aviso" disabled={e.tipo !== "aberta"} />
          </div>
          <label className="flex items-center gap-2 self-end pb-2 text-sm">
            <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" checked={e.ativo} onChange={(x) => setE({ ...e, ativo: x.target.checked })} />
            Etapa ativa
          </label>
          <DialogFooter className="sm:col-span-2">
            <Button type="button" variant="outline" onClick={onFechar}>
              Cancelar
            </Button>
            <Button type="submit" disabled={salvar.isPending}>
              {salvar.isPending && <Loader2 className="animate-spin" />} Salvar
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function Rodizio({ funil }: { funil: Funil }) {
  const atual = useRodizio(funil.id);
  const resp = useResponsaveis();
  const salvar = useSalvarRodizio();
  const [lista, setLista] = useState<string[]>([]);
  useEffect(() => {
    if (atual.data) setLista(atual.data.map((r) => r.user_id));
  }, [atual.data]);
  const nome = (id: string) => resp.data?.find((r) => r.user_id === id)?.nome ?? atual.data?.find((r) => r.user_id === id)?.nome ?? "—";
  const fora = resp.data?.filter((r) => !lista.includes(r.user_id)) ?? [];
  const proximo = atual.data?.find((r) => r.proximo)?.user_id;
  const mudou = JSON.stringify(lista) !== JSON.stringify(atual.data?.map((r) => r.user_id) ?? []);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Shuffle className="h-4 w-4" /> Rodízio de responsáveis
        </CardTitle>
        <CardDescription>Negócio criado sem responsável vai para o próximo da fila, na ordem abaixo (como o carrossel do Bitrix).</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {atual.isLoading ? (
          <Skeleton className="h-24 w-full" />
        ) : (
          <>
            {lista.length === 0 ? (
              <p className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">Ninguém no rodízio. Adicione os vendedores abaixo.</p>
            ) : (
              <ol className="divide-y rounded-lg border">
                {lista.map((id, i) => (
                  <li key={id} className="flex items-center gap-3 p-2.5 text-sm">
                    <span className="w-5 text-right text-muted-foreground">{i + 1}.</span>
                    <span className="flex-1">{nome(id)}</span>
                    {id === proximo && !mudou && <Badge variant="marca">próximo</Badge>}
                    <Button variant="ghost" size="icon" aria-label="Subir" disabled={i === 0} onClick={() => setLista((l) => { const c = [...l]; [c[i - 1], c[i]] = [c[i], c[i - 1]]; return c; })}>
                      <ArrowUp className="h-4 w-4" />
                    </Button>
                    <Button variant="ghost" size="sm" onClick={() => setLista((l) => l.filter((x) => x !== id))}>
                      Tirar
                    </Button>
                  </li>
                ))}
              </ol>
            )}
            {fora.length > 0 && (
              <div className="flex flex-wrap gap-2">
                {fora.map((r) => (
                  <Button key={r.user_id} size="sm" variant="outline" onClick={() => setLista((l) => [...l, r.user_id])}>
                    <Plus /> {r.nome}
                  </Button>
                ))}
              </div>
            )}
            <div className="flex justify-end">
              <Button disabled={!mudou || salvar.isPending} onClick={() => salvar.mutate({ funil: funil.id, users: lista })}>
                {salvar.isPending && <Loader2 className="animate-spin" />} Salvar rodízio
              </Button>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}
