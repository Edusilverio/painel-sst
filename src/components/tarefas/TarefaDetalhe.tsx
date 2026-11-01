import { useEffect, useState } from "react";
import { CalendarClock, Loader2, MessageSquare, Plus, Trash2, UserRound, X } from "lucide-react";
import { Dialog, DialogDescription, DialogTitle, SheetContent } from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { EstadoErro } from "@/components/ui/estados";
import { EmpresaSelect } from "@/components/crm/EmpresaSelect";
import { useSessao } from "@/contexts/sessao";
import { useComentarTarefa, useExcluirItemTarefa, useExcluirTarefa, useItemTarefa, useResponsaveis, useSalvarTarefa, useTarefa } from "@/hooks/api";
import { ORDEM_STATUS_TAREFA, prioridadeTarefa, statusTarefa } from "@/lib/status";
import type { TarefaDetalhe as Detalhe } from "@/lib/tipos";
import { cn, fmtDataHora, tempoRelativo } from "@/lib/utils";

const NINGUEM = "__ninguem__";

export function TarefaDetalhe({ id, onFechar }: { id: string | null; onFechar: () => void }) {
  const q = useTarefa(id);
  return (
    <Dialog open={!!id} onOpenChange={(v) => !v && onFechar()}>
      <SheetContent aria-describedby={undefined}>
        {q.isLoading && (
          <div className="space-y-4 p-6">
            <DialogTitle className="sr-only">Carregando tarefa</DialogTitle>
            <Skeleton className="h-7 w-2/3" />
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-48 w-full" />
          </div>
        )}
        {q.isError && (
          <div className="p-6">
            <DialogTitle className="sr-only">Erro</DialogTitle>
            <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
          </div>
        )}
        {q.data && <Conteudo t={q.data} onFechar={onFechar} />}
      </SheetContent>
    </Dialog>
  );
}

function Conteudo({ t, onFechar }: { t: Detalhe; onFechar: () => void }) {
  const { tem } = useSessao();
  const pode = tem("gestor", "comercial", "operacoes", "financeiro");
  const salvar = useSalvarTarefa();
  const excluir = useExcluirTarefa();
  const resp = useResponsaveis();
  const [titulo, setTitulo] = useState(t.titulo);
  const [notas, setNotas] = useState(t.notas ?? "");
  const [confirma, setConfirma] = useState(false);
  useEffect(() => {
    setTitulo(t.titulo);
    setNotas(t.notas ?? "");
  }, [t.id, t.titulo, t.notas]);

  const muda = (dados: Record<string, unknown>) => salvar.mutate({ id: t.id, dados });

  return (
    <div className="flex h-full flex-col overflow-hidden">
      <div className="border-b p-5 pr-12">
        <p className="text-xs text-muted-foreground">
          #{t.numero} · criada {tempoRelativo(t.criado_em)}
          {t.criado_por_nome && ` por ${t.criado_por_nome}`}
        </p>
        <DialogTitle className="sr-only">{t.titulo}</DialogTitle>
        <DialogDescription className="sr-only">Detalhes da tarefa</DialogDescription>
        <Input
          aria-label="Título da tarefa"
          value={titulo}
          disabled={!pode}
          onChange={(e) => setTitulo(e.target.value)}
          onBlur={() => titulo.trim().length > 1 && titulo !== t.titulo && muda({ titulo })}
          onKeyDown={(e) => e.key === "Enter" && (e.target as HTMLInputElement).blur()}
          className="mt-1 h-auto border-transparent px-1 text-lg font-semibold shadow-none hover:border-input focus-visible:border-input"
        />
      </div>

      <div className="flex-1 space-y-6 overflow-y-auto p-5">
        <div className="grid gap-4 sm:grid-cols-2">
          <Campo rotulo="Status">
            <Select value={t.status} onValueChange={(v) => muda({ status: v })} disabled={!pode}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {ORDEM_STATUS_TAREFA.map((s) => (
                  <SelectItem key={s} value={s}>
                    <span className="flex items-center gap-2">
                      <span className={cn("h-2.5 w-2.5 rounded-full", statusTarefa[s].fundo)} aria-hidden />
                      {statusTarefa[s].rotulo}
                    </span>
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Campo>
          <Campo rotulo="Prioridade">
            <Select value={t.prioridade} onValueChange={(v) => muda({ prioridade: v })} disabled={!pode}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {Object.entries(prioridadeTarefa).map(([v, p]) => (
                  <SelectItem key={v} value={v}>
                    {p.rotulo}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Campo>
          <div className="space-y-1.5 sm:col-span-2">
            <Label className="flex items-center gap-1.5">
              <UserRound className="h-3.5 w-3.5 text-muted-foreground" aria-hidden /> Responsáveis
            </Label>
            {/* 0077: vários responsáveis; quem criou continua registrado como "criada por" */}
            <div className="flex flex-wrap items-center gap-1.5">
              {t.responsaveis.length === 0 && <span className="text-sm text-muted-foreground">Ninguém ainda.</span>}
              {t.responsaveis.map((r) => (
                <Badge key={r.id} variant="outline" className="gap-1 py-1 pl-2 pr-1 text-xs font-normal">
                  {r.nome}
                  {pode && (
                    <button
                      type="button"
                      className="rounded p-0.5 hover:bg-accent"
                      aria-label={`Tirar ${r.nome}`}
                      onClick={() => muda({ responsaveis: t.responsaveis.filter((x) => x.id !== r.id).map((x) => x.id) })}
                    >
                      <X className="h-3 w-3" />
                    </button>
                  )}
                </Badge>
              ))}
              {pode && (
                <Select value={NINGUEM} onValueChange={(v) => v !== NINGUEM && muda({ responsaveis: [...t.responsaveis.map((x) => x.id), v] })}>
                  <SelectTrigger className="h-8 w-48 text-xs" aria-label="Adicionar responsável">
                    <SelectValue placeholder="Adicionar responsável" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value={NINGUEM} disabled>
                      Adicionar responsável…
                    </SelectItem>
                    {resp.data
                      ?.filter((r) => !t.responsaveis.some((x) => x.id === r.user_id))
                      .map((r) => (
                        <SelectItem key={r.user_id} value={r.user_id}>
                          {r.nome}
                        </SelectItem>
                      ))}
                  </SelectContent>
                </Select>
              )}
            </div>
          </div>
          <Campo rotulo="Prazo" icone={CalendarClock}>
            <Input type="date" value={t.prazo ?? ""} disabled={!pode} onChange={(e) => muda({ prazo: e.target.value || null })} />
          </Campo>
          <div className="space-y-1.5 sm:col-span-2">
            <Label>Cliente (opcional)</Label>
            {pode ? (
              <EmpresaSelect
                valor={t.empresa_id ? { id: t.empresa_id, nome: t.empresa ?? "", cnpj: null } : null}
                onChange={(e) => muda({ empresa_id: e?.id ?? null })}
              />
            ) : (
              <p className="text-sm">{t.empresa ?? "—"}</p>
            )}
          </div>
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="tarefa-notas">Notas</Label>
          <Textarea
            id="tarefa-notas"
            rows={4}
            value={notas}
            disabled={!pode}
            onChange={(e) => setNotas(e.target.value)}
            onBlur={() => notas !== (t.notas ?? "") && muda({ notas })}
            placeholder="Notas de reunião, contexto, links…"
          />
        </div>

        <Checklist t={t} pode={pode} />
        <Comentarios t={t} pode={pode} />
      </div>

      {t.pode_excluir && (
        <div className="flex items-center justify-between border-t p-4">
          {confirma ? (
            <div className="flex items-center gap-2">
              <span className="text-sm">Excluir de vez?</span>
              <Button size="sm" variant="destructive" disabled={excluir.isPending} onClick={() => excluir.mutateAsync(t.id).then(onFechar).catch(() => null)}>
                Excluir
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setConfirma(false)}>
                Voltar
              </Button>
            </div>
          ) : (
            <Button size="sm" variant="ghost" className="text-destructive" onClick={() => setConfirma(true)}>
              <Trash2 /> Excluir tarefa
            </Button>
          )}
          {salvar.isPending && <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" aria-label="Salvando" />}
        </div>
      )}
    </div>
  );
}

function Campo({ rotulo, icone: Icone, children }: { rotulo: string; icone?: typeof UserRound; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label className="flex items-center gap-1.5">
        {Icone && <Icone className="h-3.5 w-3.5 text-muted-foreground" aria-hidden />}
        {rotulo}
      </Label>
      {children}
    </div>
  );
}

function Checklist({ t, pode }: { t: Detalhe; pode: boolean }) {
  const item = useItemTarefa();
  const apagar = useExcluirItemTarefa();
  const [novo, setNovo] = useState("");
  const feitos = t.itens.filter((i) => i.feito).length;

  function adicionar(e: React.FormEvent) {
    e.preventDefault();
    if (!novo.trim()) return;
    item.mutate({ tarefa: t.id, id: null, texto: novo.trim(), feito: false });
    setNovo("");
  }

  return (
    <section aria-labelledby="checklist-titulo" className="space-y-2">
      <div className="flex items-center justify-between">
        <h3 id="checklist-titulo" className="text-sm font-semibold">
          Elementos de ação
        </h3>
        {t.itens.length > 0 && (
          <Badge variant={feitos === t.itens.length ? "success" : "muted"}>
            {feitos}/{t.itens.length}
          </Badge>
        )}
      </div>
      {t.itens.length > 0 && (
        <div className="h-1.5 overflow-hidden rounded-full bg-muted">
          <div className="h-full bg-success transition-all" style={{ width: `${(feitos / t.itens.length) * 100}%` }} />
        </div>
      )}
      <ul className="space-y-1">
        {t.itens.map((i) => (
          <li key={i.id} className="group flex items-center gap-2 rounded-md px-1 py-1 hover:bg-muted/50">
            <input
              type="checkbox"
              className="h-4 w-4 accent-[hsl(var(--primary))]"
              checked={i.feito}
              disabled={!pode}
              onChange={(e) => item.mutate({ tarefa: t.id, id: i.id, texto: null, feito: e.target.checked })}
              aria-label={i.texto}
            />
            <span className={cn("flex-1 text-sm", i.feito && "text-muted-foreground line-through")}>{i.texto}</span>
            {pode && (
              <button
                type="button"
                onClick={() => apagar.mutate(i.id)}
                className="rounded p-1 text-muted-foreground opacity-0 hover:text-destructive focus-visible:opacity-100 group-hover:opacity-100"
                aria-label={`Remover ${i.texto}`}
              >
                <Trash2 className="h-3.5 w-3.5" />
              </button>
            )}
          </li>
        ))}
      </ul>
      {pode && (
        <form onSubmit={adicionar} className="flex gap-2">
          <Input value={novo} onChange={(e) => setNovo(e.target.value)} placeholder="Adicionar item" aria-label="Novo item" />
          <Button type="submit" size="icon" variant="outline" disabled={!novo.trim()} aria-label="Adicionar item">
            <Plus />
          </Button>
        </form>
      )}
    </section>
  );
}

function Comentarios({ t, pode }: { t: Detalhe; pode: boolean }) {
  const comentar = useComentarTarefa();
  const [texto, setTexto] = useState("");
  return (
    <section aria-labelledby="coment-titulo" className="space-y-3">
      <h3 id="coment-titulo" className="flex items-center gap-1.5 text-sm font-semibold">
        <MessageSquare className="h-4 w-4" aria-hidden /> Atualizações
      </h3>
      {pode && (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (!texto.trim()) return;
            comentar.mutateAsync({ id: t.id, texto: texto.trim() }).then(() => setTexto("")).catch(() => null);
          }}
          className="space-y-2"
        >
          <Textarea rows={2} value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Escreva uma atualização (o responsável é avisado)" aria-label="Nova atualização" />
          <div className="flex justify-end">
            <Button type="submit" size="sm" disabled={!texto.trim() || comentar.isPending}>
              {comentar.isPending && <Loader2 className="animate-spin" />} Publicar
            </Button>
          </div>
        </form>
      )}
      <ol className="space-y-3">
        {t.comentarios.map((c) =>
          c.sistema ? (
            <li key={c.id} className="text-xs text-muted-foreground">
              {c.autor} · {c.texto} · {fmtDataHora(c.criado_em)}
            </li>
          ) : (
            <li key={c.id} className="rounded-md border bg-card p-3">
              <p className="text-xs text-muted-foreground">
                <span className="font-medium text-foreground">{c.autor}</span> · {fmtDataHora(c.criado_em)}
              </p>
              <p className="mt-1 whitespace-pre-wrap text-sm">{c.texto}</p>
            </li>
          ),
        )}
      </ol>
    </section>
  );
}
