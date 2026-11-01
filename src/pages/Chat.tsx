import { useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { ArrowLeft, Hash, Loader2, LogOut, MessageSquarePlus, Pencil, Search, Send, Trash2, Users, UsersRound } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { EstadoErro } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { useChatAcoes, useChatMensagens, useChatPessoas, useChatSala, useChatSalas } from "@/hooks/api";
import type { ChatMensagem, ChatSala } from "@/lib/tipos";
import { cn, iniciais } from "@/lib/utils";
import { AnexoMensagem, BotaoAnexar, GravadorAudio, tipoDoArquivo } from "@/components/chat/Anexos";

const hora = (iso: string) => new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
function quando(iso: string | null) {
  if (!iso) return "";
  const d = new Date(iso);
  const hoje = new Date();
  if (d.toDateString() === hoje.toDateString()) return hora(iso);
  const ontem = new Date(hoje.getTime() - 86_400_000);
  if (d.toDateString() === ontem.toDateString()) return "ontem";
  return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" });
}
const dia = (iso: string) => new Date(iso).toLocaleDateString("pt-BR", { weekday: "long", day: "2-digit", month: "long" });

function IconeSala({ s }: { s: Pick<ChatSala, "tipo" | "nome"> }) {
  if (s.tipo === "geral")
    return (
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-marca text-white">
        <Hash className="h-4 w-4" />
      </span>
    );
  if (s.tipo === "grupo")
    return (
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-primary/15 text-primary">
        <UsersRound className="h-4 w-4" />
      </span>
    );
  return <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-muted text-xs font-semibold">{iniciais(s.nome)}</span>;
}

export default function Chat() {
  const [params, setParams] = useSearchParams();
  const salaId = params.get("sala");
  const abrir = (id: string | null) => {
    const p = new URLSearchParams(params);
    if (id) p.set("sala", id);
    else p.delete("sala");
    setParams(p, { replace: true });
  };
  const salas = useChatSalas(true);
  const [busca, setBusca] = useState("");
  const [grupo, setGrupo] = useState<{ id: string | null } | null>(null);
  const [nova, setNova] = useState(false);
  const atual = salas.data?.find((s) => s.id === salaId) ?? null;

  const lista = useMemo(() => {
    const t = busca.trim().toLowerCase();
    return (salas.data ?? []).filter((s) => !t || (s.nome ?? "").toLowerCase().includes(t));
  }, [salas.data, busca]);

  return (
    <div className="flex h-full min-h-0">
      {/* lista de conversas */}
      <section aria-label="Conversas" className={cn("flex w-full flex-col border-r md:w-80 md:shrink-0", salaId && "hidden md:flex")}>
        <div className="space-y-3 border-b p-3">
          <div className="flex items-center justify-between">
            <h1 className="text-lg font-semibold">Chat da equipe</h1>
            <div className="flex gap-1">
              <Button size="icon" variant="ghost" aria-label="Nova conversa" title="Nova conversa" onClick={() => setNova(true)}>
                <MessageSquarePlus />
              </Button>
              <Button size="icon" variant="ghost" aria-label="Novo grupo" title="Novo grupo" onClick={() => setGrupo({ id: null })}>
                <Users />
              </Button>
            </div>
          </div>
          <div className="relative">
            <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
            <Input className="pl-8" placeholder="Buscar conversa" aria-label="Buscar conversa" value={busca} onChange={(e) => setBusca(e.target.value)} />
          </div>
        </div>
        <div className="flex-1 overflow-y-auto">
          {salas.isError ? (
            <EstadoErro erro={salas.error} onTentar={() => salas.refetch()} className="m-3" />
          ) : salas.isLoading ? (
            <div className="space-y-2 p-3">
              {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-12 w-full" />
              ))}
            </div>
          ) : (
            <ul>
              {lista.map((s) => (
                <li key={s.id}>
                  <button
                    type="button"
                    onClick={() => abrir(s.id)}
                    className={cn("flex w-full items-center gap-3 px-3 py-2.5 text-left hover:bg-accent", s.id === salaId && "bg-accent")}
                  >
                    <IconeSala s={s} />
                    <span className="min-w-0 flex-1">
                      <span className="flex items-baseline justify-between gap-2">
                        <span className={cn("truncate text-sm", s.nao_lidas ? "font-semibold" : "font-medium")}>{s.nome ?? "Conversa"}</span>
                        <span className="shrink-0 text-[11px] text-muted-foreground">{quando(s.ultima_em)}</span>
                      </span>
                      <span className="flex items-center justify-between gap-2">
                        <span className="truncate text-xs text-muted-foreground">
                          {s.ultima_texto ? `${s.tipo !== "direto" && s.ultima_autor ? `${s.ultima_autor.split(" ")[0]}: ` : ""}${s.ultima_texto}` : s.descricao ?? "Nenhuma mensagem ainda"}
                        </span>
                        {s.nao_lidas > 0 && <Badge className="h-5 min-w-5 justify-center px-1.5">{s.nao_lidas}</Badge>}
                      </span>
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </section>

      {/* conversa aberta */}
      <section aria-label="Conversa" className={cn("min-w-0 flex-1 flex-col", salaId ? "flex" : "hidden md:flex")}>
        {atual ? (
          <Conversa sala={atual} onVoltar={() => abrir(null)} onEditar={() => setGrupo({ id: atual.id })} onSaiu={() => abrir(null)} />
        ) : (
          <div className="flex flex-1 flex-col items-center justify-center gap-2 p-6 text-center text-muted-foreground">
            <UsersRound className="h-8 w-8" />
            <p className="text-sm">Escolha uma conversa ao lado, comece uma conversa direta ou crie um grupo de trabalho.</p>
          </div>
        )}
      </section>

      <GrupoDialog id={grupo?.id ?? null} aberto={!!grupo} onFechar={() => setGrupo(null)} onCriado={abrir} />
      <NovaConversaDialog aberto={nova} onFechar={() => setNova(false)} onAberta={abrir} />
    </div>
  );
}

function Conversa({ sala, onVoltar, onEditar, onSaiu }: { sala: ChatSala; onVoltar: () => void; onEditar: () => void; onSaiu: () => void }) {
  const msgs = useChatMensagens(sala.id);
  const det = useChatSala(sala.id);
  const acoes = useChatAcoes();
  const [texto, setTexto] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [gravando, setGravando] = useState(false);
  const fim = useRef<HTMLDivElement>(null);
  const ultimo = msgs.data?.[msgs.data.length - 1]?.id;

  // rola para o fim e marca como lida quando chega mensagem nova
  useEffect(() => {
    fim.current?.scrollIntoView({ block: "end" });
    if (ultimo !== undefined || sala.nao_lidas) acoes.lida(sala.id).catch(() => undefined);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sala.id, ultimo]);

  async function enviar() {
    const t = texto.trim();
    if (!t) return;
    setEnviando(true);
    try {
      await acoes.enviar(sala.id, t);
      setTexto("");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível enviar.");
    } finally {
      setEnviando(false);
    }
  }

  // 0075: imagem, áudio e arquivo. O texto já digitado vai como legenda.
  async function mandarAnexo(arquivo: Blob, nome: string, duracao?: number) {
    const mime = (arquivo.type || "").split(";")[0];
    setEnviando(true);
    try {
      await acoes.enviarAnexo(sala.id, arquivo, { tipo: tipoDoArquivo(mime), nome, duracao, legenda: texto.trim() || null });
      setTexto("");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível enviar o anexo.");
    } finally {
      setEnviando(false);
    }
  }

  const subtitulo =
    sala.tipo === "geral" ? `Toda a equipe · ${sala.membros} pessoas` : sala.tipo === "grupo" ? `${sala.membros} participantes${sala.descricao ? ` · ${sala.descricao}` : ""}` : "Conversa direta";

  return (
    <>
      <div className="flex h-14 shrink-0 items-center gap-2 border-b px-3">
        <Button size="icon" variant="ghost" className="md:hidden" onClick={onVoltar} aria-label="Voltar para as conversas">
          <ArrowLeft />
        </Button>
        <IconeSala s={sala} />
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold">{sala.nome}</p>
          <p className="truncate text-xs text-muted-foreground" title={det.data?.membros.map((m) => m.nome).join(", ")}>
            {subtitulo}
          </p>
        </div>
        {det.data?.pode_editar && (
          <Button size="icon" variant="ghost" onClick={onEditar} aria-label="Editar grupo" title="Editar grupo">
            <Pencil />
          </Button>
        )}
        {sala.tipo === "grupo" && (
          <Button
            size="icon"
            variant="ghost"
            aria-label="Sair do grupo"
            title="Sair do grupo"
            onClick={async () => {
              if (!window.confirm(`Sair do grupo ${sala.nome}?`)) return;
              try {
                await acoes.sair(sala.id);
                onSaiu();
              } catch (e) {
                toast.error(e instanceof Error ? e.message : "Não foi possível sair.");
              }
            }}
          >
            <LogOut />
          </Button>
        )}
      </div>

      <div className="flex-1 overflow-y-auto px-3 py-4 sm:px-6" aria-live="polite">
        {msgs.isError ? (
          <EstadoErro erro={msgs.error} onTentar={() => msgs.refetch()} />
        ) : msgs.isLoading ? (
          <div className="space-y-3">
            <Skeleton className="h-10 w-2/3" />
            <Skeleton className="ml-auto h-10 w-1/2" />
          </div>
        ) : msgs.data?.length === 0 ? (
          <p className="py-10 text-center text-sm text-muted-foreground">Nenhuma mensagem ainda. Diga olá!</p>
        ) : (
          <Mensagens itens={msgs.data ?? []} mostrarAutor={sala.tipo !== "direto"} onApagar={(id) => acoes.apagar(id).catch((e) => toast.error(e.message))} />
        )}
        <div ref={fim} />
      </div>

      <form
        className="flex shrink-0 items-end gap-2 border-t p-3"
        onSubmit={(e) => {
          e.preventDefault();
          enviar();
        }}
      >
        {!gravando && <BotaoAnexar disabled={enviando} onArquivo={(f) => mandarAnexo(f, f.name)} />}
        <GravadorAudio
          disabled={enviando}
          onGravando={setGravando}
          onPronto={(b, dur) => mandarAnexo(b, `audio.${b.type.includes("mp4") ? "m4a" : b.type.includes("ogg") ? "ogg" : "webm"}`, dur)}
        />
        {!gravando && (
        <>
        <Textarea
          rows={1}
          value={texto}
          onChange={(e) => setTexto(e.target.value)}
          onPaste={(e) => {
            const img = Array.from(e.clipboardData.files).find((f) => f.type.startsWith("image/"));
            if (img) {
              e.preventDefault();
              mandarAnexo(img, img.name || "imagem.png");
            }
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              enviar();
            }
          }}
          placeholder="Escreva uma mensagem (Enter envia). Cole uma imagem com Ctrl+V"
          aria-label="Mensagem"
          className="max-h-40 min-h-10 resize-none"
        />
        <Button type="submit" size="icon" disabled={enviando || !texto.trim()} aria-label="Enviar">
          {enviando ? <Loader2 className="animate-spin" /> : <Send />}
        </Button>
        </>
        )}
      </form>
    </>
  );
}

function Mensagens({ itens, mostrarAutor, onApagar }: { itens: ChatMensagem[]; mostrarAutor: boolean; onApagar: (id: number) => void }) {
  return (
    <ol className="space-y-1">
      {itens.map((m, i) => {
        const ant = itens[i - 1];
        const novoDia = !ant || new Date(ant.criado_em).toDateString() !== new Date(m.criado_em).toDateString();
        const agrupada = !novoDia && ant && ant.autor_id === m.autor_id && new Date(m.criado_em).getTime() - new Date(ant.criado_em).getTime() < 5 * 60_000;
        return (
          <li key={m.id}>
            {novoDia && <p className="my-3 text-center text-xs capitalize text-muted-foreground">{dia(m.criado_em)}</p>}
            <div className={cn("group flex", m.minha ? "justify-end" : "justify-start", !agrupada && "mt-2")}>
              <div className={cn("max-w-[85%] sm:max-w-[70%]")}>
                {!m.minha && mostrarAutor && !agrupada && <p className="mb-0.5 px-1 text-xs font-medium text-muted-foreground">{m.autor ?? "Ex-usuário"}</p>}
                <div className="flex items-end gap-1">
                  {m.minha && !m.excluida && (
                    <button
                      type="button"
                      className="rounded p-1 text-muted-foreground opacity-0 hover:text-destructive focus:opacity-100 group-hover:opacity-100"
                      aria-label="Apagar mensagem"
                      onClick={() => window.confirm("Apagar esta mensagem?") && onApagar(m.id)}
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  )}
                  <div
                    className={cn(
                      "whitespace-pre-wrap break-words rounded-2xl px-3 py-1.5 text-sm",
                      m.minha ? "bg-primary text-primary-foreground" : "bg-muted",
                      m.excluida && "italic opacity-60",
                    )}
                  >
                    {!m.excluida && <AnexoMensagem m={m} />}
                    {m.excluida ? "Mensagem apagada" : m.texto_auto && m.anexo_path ? null : m.texto}
                    <span className={cn("ml-2 align-bottom text-[10px]", m.minha ? "text-primary-foreground/70" : "text-muted-foreground")}>{hora(m.criado_em)}</span>
                  </div>
                </div>
              </div>
            </div>
          </li>
        );
      })}
    </ol>
  );
}

function SeletorPessoas({ marcados, onMudar, excluir }: { marcados: string[]; onMudar: (ids: string[]) => void; excluir?: string[] }) {
  const pessoas = useChatPessoas();
  const [t, setT] = useState("");
  const lista = (pessoas.data ?? []).filter((p) => !excluir?.includes(p.user_id) && (!t || p.nome.toLowerCase().includes(t.toLowerCase())));
  return (
    <div className="space-y-2">
      <Input placeholder="Buscar pessoa" aria-label="Buscar pessoa" value={t} onChange={(e) => setT(e.target.value)} />
      <ul className="max-h-60 divide-y overflow-y-auto rounded-md border">
        {pessoas.isLoading && <li className="p-3 text-sm text-muted-foreground">Carregando…</li>}
        {lista.map((p) => (
          <li key={p.user_id}>
            <label className="flex cursor-pointer items-center gap-3 px-3 py-2 text-sm hover:bg-accent">
              <input
                type="checkbox"
                className="h-4 w-4 accent-[hsl(var(--primary))]"
                checked={marcados.includes(p.user_id)}
                onChange={(e) => onMudar(e.target.checked ? [...marcados, p.user_id] : marcados.filter((x) => x !== p.user_id))}
              />
              <span className="flex-1">{p.nome}</span>
              <span className="text-xs text-muted-foreground">{p.cargo ?? p.papel}</span>
            </label>
          </li>
        ))}
      </ul>
    </div>
  );
}

function GrupoDialog({ id, aberto, onFechar, onCriado }: { id: string | null; aberto: boolean; onFechar: () => void; onCriado: (id: string) => void }) {
  const det = useChatSala(aberto ? id : null);
  const acoes = useChatAcoes();
  const [nome, setNome] = useState("");
  const [descricao, setDescricao] = useState("");
  const [membros, setMembros] = useState<string[]>([]);
  const [salvando, setSalvando] = useState(false);
  const dono = det.data?.membros.find((m) => m.dono)?.user_id;

  useEffect(() => {
    if (!aberto) return;
    if (!id) {
      setNome("");
      setDescricao("");
      setMembros([]);
    } else if (det.data) {
      setNome(det.data.nome ?? "");
      setDescricao(det.data.descricao ?? "");
      setMembros(det.data.membros.filter((m) => !m.dono).map((m) => m.user_id));
    }
  }, [aberto, id, det.data]);

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{id ? "Editar grupo" : "Novo grupo de trabalho"}</DialogTitle>
          <DialogDescription>Só os participantes veem as mensagens do grupo. Você entra automaticamente.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="g-nome">Nome</Label>
            <Input id="g-nome" value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Ex.: Laudos, Recepção, Comercial" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="g-desc">Descrição (opcional)</Label>
            <Input id="g-desc" value={descricao} onChange={(e) => setDescricao(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label>Participantes</Label>
            <SeletorPessoas marcados={membros} onMudar={setMembros} excluir={dono ? [dono] : undefined} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onFechar}>
            Cancelar
          </Button>
          <Button
            disabled={salvando || !nome.trim()}
            onClick={async () => {
              setSalvando(true);
              try {
                const r = await acoes.grupo(id, nome, descricao, membros);
                toast.success(id ? "Grupo atualizado" : "Grupo criado");
                onFechar();
                if (!id) onCriado(r);
              } catch (e) {
                toast.error(e instanceof Error ? e.message : "Não foi possível salvar o grupo.");
              } finally {
                setSalvando(false);
              }
            }}
          >
            {salvando && <Loader2 className="animate-spin" />} {id ? "Salvar" : "Criar grupo"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function NovaConversaDialog({ aberto, onFechar, onAberta }: { aberto: boolean; onFechar: () => void; onAberta: (id: string) => void }) {
  const pessoas = useChatPessoas();
  const acoes = useChatAcoes();
  const [t, setT] = useState("");
  const lista = (pessoas.data ?? []).filter((p) => !t || p.nome.toLowerCase().includes(t.toLowerCase()));
  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Nova conversa</DialogTitle>
          <DialogDescription>Conversa direta, só entre vocês dois.</DialogDescription>
        </DialogHeader>
        <Input placeholder="Buscar pessoa" aria-label="Buscar pessoa" value={t} onChange={(e) => setT(e.target.value)} />
        <ul className="max-h-72 divide-y overflow-y-auto rounded-md border">
          {lista.map((p) => (
            <li key={p.user_id}>
              <button
                type="button"
                className="flex w-full items-center gap-3 px-3 py-2 text-left text-sm hover:bg-accent"
                onClick={async () => {
                  try {
                    const id = await acoes.direto(p.user_id);
                    onFechar();
                    onAberta(id);
                  } catch (e) {
                    toast.error(e instanceof Error ? e.message : "Não foi possível abrir a conversa.");
                  }
                }}
              >
                <span className="flex h-8 w-8 items-center justify-center rounded-full bg-muted text-xs font-semibold">{iniciais(p.nome)}</span>
                <span className="flex-1">{p.nome}</span>
                <span className="text-xs text-muted-foreground">{p.cargo ?? p.papel}</span>
              </button>
            </li>
          ))}
        </ul>
      </DialogContent>
    </Dialog>
  );
}
