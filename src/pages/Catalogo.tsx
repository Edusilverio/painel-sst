import { useState } from "react";
import { Loader2, Package, Pencil, Plus } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Textarea } from "@/components/ui/textarea";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { useProdutos, useSalvarProduto } from "@/hooks/api";
import { useSessao } from "@/contexts/sessao";
import type { Produto } from "@/lib/tipos";
import { fmtMoeda } from "@/lib/utils";

export default function Catalogo() {
  const { tem } = useSessao();
  const gestor = tem("gestor");
  const q = useProdutos(gestor);
  const [editando, setEditando] = useState<Partial<Produto> | null>(null);

  return (
    <div className="mx-auto max-w-5xl space-y-5 p-4 sm:p-6">
      <Cabecalho
        titulo="Catálogo"
        descricao="Produtos e serviços que entram nos negócios. O valor do negócio passa a ser a soma dos itens."
        acoes={
          gestor && (
            <Button onClick={() => setEditando({ unidade: "un", ativo: true, recorrente: false })}>
              <Plus /> Novo produto
            </Button>
          )
        }
      />
      {q.isError ? (
        <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
      ) : q.data && q.data.length === 0 ? (
        <EstadoVazio icone={Package} titulo="Catálogo vazio" texto="Cadastre os serviços que a Vitalis vende." />
      ) : (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Produto</TableHead>
                <TableHead>Categoria</TableHead>
                <TableHead className="text-right">Preço</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {q.isLoading &&
                Array.from({ length: 5 }).map((_, i) => (
                  <TableRow key={i}>
                    <TableCell colSpan={4}>
                      <Skeleton className="h-5 w-full" />
                    </TableCell>
                  </TableRow>
                ))}
              {q.data?.map((p) => (
                <TableRow key={p.id} className={p.ativo ? "" : "opacity-60"}>
                  <TableCell>
                    <p className="font-medium">
                      {p.nome} {!p.ativo && <Badge variant="muted">inativo</Badge>} {p.recorrente && <Badge variant="info">recorrente</Badge>}
                    </p>
                    {p.descricao && <p className="text-xs text-muted-foreground">{p.descricao}</p>}
                  </TableCell>
                  <TableCell>{p.categoria ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">
                    {p.preco == null ? <span className="text-muted-foreground">a definir</span> : `${fmtMoeda(p.preco)} / ${p.unidade}`}
                  </TableCell>
                  <TableCell className="w-12">
                    {gestor && (
                      <Button variant="ghost" size="icon" onClick={() => setEditando(p)} aria-label={`Editar ${p.nome}`}>
                        <Pencil className="h-4 w-4" />
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Card>
      )}
      {editando && <EditarProduto inicial={editando} onFechar={() => setEditando(null)} />}
    </div>
  );
}

function EditarProduto({ inicial, onFechar }: { inicial: Partial<Produto>; onFechar: () => void }) {
  const salvar = useSalvarProduto();
  const [p, setP] = useState({
    nome: inicial.nome ?? "",
    descricao: inicial.descricao ?? "",
    categoria: inicial.categoria ?? "",
    preco: inicial.preco != null ? String(inicial.preco).replace(".", ",") : "",
    unidade: inicial.unidade ?? "un",
    recorrente: inicial.recorrente ?? false,
    ativo: inicial.ativo ?? true,
  });
  return (
    <Dialog open onOpenChange={(v) => !v && onFechar()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{inicial.id ? "Editar produto" : "Novo produto"}</DialogTitle>
        </DialogHeader>
        <form
          className="grid gap-3 sm:grid-cols-2"
          onSubmit={(e) => {
            e.preventDefault();
            salvar.mutate(
              {
                id: inicial.id,
                nome: p.nome,
                descricao: p.descricao || null,
                categoria: p.categoria || null,
                preco: p.preco.trim() ? Number(p.preco.replace(/\./g, "").replace(",", ".")) : null,
                unidade: p.unidade,
                recorrente: p.recorrente,
                ativo: p.ativo,
              },
              { onSuccess: onFechar },
            );
          }}
        >
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="p-nome">Nome</Label>
            <Input id="p-nome" value={p.nome} onChange={(e) => setP({ ...p, nome: e.target.value })} required />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="p-cat">Categoria</Label>
            <Input id="p-cat" value={p.categoria} onChange={(e) => setP({ ...p, categoria: e.target.value })} />
          </div>
          <div className="grid grid-cols-[1fr_5rem] gap-2">
            <div className="space-y-1.5">
              <Label htmlFor="p-preco">Preço (R$)</Label>
              <Input id="p-preco" value={p.preco} onChange={(e) => setP({ ...p, preco: e.target.value })} inputMode="decimal" placeholder="a definir" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="p-un">Unidade</Label>
              <Input id="p-un" value={p.unidade} onChange={(e) => setP({ ...p, unidade: e.target.value })} />
            </div>
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="p-desc">Descrição</Label>
            <Textarea id="p-desc" value={p.descricao} onChange={(e) => setP({ ...p, descricao: e.target.value })} rows={2} />
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" checked={p.recorrente} onChange={(e) => setP({ ...p, recorrente: e.target.checked })} />
            Cobrança recorrente
          </label>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" checked={p.ativo} onChange={(e) => setP({ ...p, ativo: e.target.checked })} />
            Ativo (aparece nos negócios)
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
