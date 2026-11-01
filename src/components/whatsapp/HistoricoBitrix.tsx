import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { Building2, History, Paperclip, Search } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { Paginacao } from "@/components/ui/paginacao";
import { Skeleton } from "@/components/ui/skeleton";
import { useDebounce } from "@/hooks/useDebounce";
import { rpc } from "@/lib/supabase";
import { cn, fmtData, fmtDataHora } from "@/lib/utils";
import { fmtTelefone } from "@/lib/whatsapp";

const POR_PAGINA = 50;

export interface ConversaBitrix {
  chat_id: number;
  nome: string | null;
  telefone: string | null;
  empresa_id: string | null;
  empresa: string | null;
  negocio_id: string | null;
  negocio_numero: number | null;
  iniciada_em: string | null;
  ultima_em: string | null;
  mensagens: number;
  ultima_texto: string | null;
  total: number;
}
interface Mensagem {
  id: number;
  em: string;
  quem: "cliente" | "equipe" | "sistema";
  autor: string | null;
  texto: string | null;
  arquivos: string | null;
}

/** Histórico das conversas de WhatsApp do Bitrix (somente leitura, até 05/10/2026). */
export function HistoricoBitrix({ telefone, empresaId, compacto }: { telefone?: string | null; empresaId?: string; compacto?: boolean }) {
  const [texto, setTexto] = useState("");
  const busca = useDebounce(texto.trim(), 350);
  const [pagina, setPagina] = useState(0);
  const [aberta, setAberta] = useState<ConversaBitrix | null>(null);
  useEffect(() => setPagina(0), [busca, telefone, empresaId]);
  const q = useQuery({
    queryKey: ["wa-historico", busca, telefone ?? null, empresaId ?? null, pagina],
    queryFn: () =>
      rpc<ConversaBitrix[]>("painel_wa_historico", {
        p_busca: busca || null,
        p_empresa: empresaId ?? null,
        p_telefone: telefone ?? null,
        p_limite: POR_PAGINA,
        p_offset: pagina * POR_PAGINA,
      }),
    placeholderData: keepPreviousData,
  });
  const total = q.data?.[0]?.total ?? 0;

  return (
    <div className="space-y-3">
      {!compacto && (
        <div className="flex flex-wrap items-center gap-2">
          <div className="relative min-w-[220px] flex-1 sm:max-w-sm">
            <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
            <Input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Nome, telefone, empresa ou palavra da conversa" className="pl-8" aria-label="Buscar no histórico" />
          </div>
          {telefone && <Badge variant="info">Telefone {fmtTelefone(telefone)}</Badge>}
          <span className="ml-auto text-sm text-muted-foreground">
            {total} conversa{total === 1 ? "" : "s"} · somente leitura, até 05/10/2026
          </span>
        </div>
      )}
      {q.isError ? (
        <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
      ) : q.data && q.data.length === 0 ? (
        <EstadoVazio icone={History} titulo="Nenhuma conversa no Bitrix" texto={busca ? "Mude a busca." : "Não há conversas de WhatsApp do Bitrix para este filtro."} />
      ) : (
        <Card className="divide-y">
          {q.isLoading &&
            Array.from({ length: 5 }).map((_, i) => (
              <div key={i} className="p-3">
                <Skeleton className="h-10 w-full" />
              </div>
            ))}
          {q.data?.map((c) => (
            <button key={c.chat_id} type="button" onClick={() => setAberta(c)} className="flex w-full items-start gap-3 p-3 text-left hover:bg-muted/50">
              <div className="min-w-0 flex-1">
                <p className="flex items-center gap-2 text-sm font-medium">
                  <span className="truncate">{c.nome || "Sem nome"}</span>
                  {c.telefone && <span className="text-xs font-normal tabular-nums text-muted-foreground">{fmtTelefone(c.telefone)}</span>}
                </p>
                {c.empresa && (
                  <p className="flex items-center gap-1 truncate text-xs text-muted-foreground">
                    <Building2 className="h-3 w-3 shrink-0" aria-hidden /> {c.empresa}
                    {c.negocio_numero && <span> · negócio #{c.negocio_numero}</span>}
                  </p>
                )}
                {c.ultima_texto && <p className="mt-0.5 line-clamp-1 text-sm text-muted-foreground">{c.ultima_texto}</p>}
              </div>
              <div className="shrink-0 text-right text-xs text-muted-foreground">
                <p>{fmtData(c.ultima_em)}</p>
                <p>{c.mensagens} msg</p>
              </div>
            </button>
          ))}
        </Card>
      )}
      {total > POR_PAGINA && <Paginacao pagina={pagina} porPagina={POR_PAGINA} total={total} onMudar={setPagina} />}
      {aberta && <ConversaBitrixDialog conversa={aberta} onFechar={() => setAberta(null)} />}
    </div>
  );
}

export function ConversaBitrixDialog({ conversa: c, onFechar }: { conversa: ConversaBitrix; onFechar: () => void }) {
  const q = useQuery({
    queryKey: ["wa-historico", "msgs", c.chat_id],
    queryFn: () => rpc<Mensagem[]>("painel_wa_historico_mensagens", { p_chat: c.chat_id }),
  });
  const fim = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (q.data) fim.current?.scrollIntoView({ block: "end" });
  }, [q.data]);
  let dia = "";

  return (
    <Dialog open onOpenChange={(o) => !o && onFechar()}>
      <DialogContent className="flex max-h-[90vh] flex-col sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>{c.nome || "Conversa"}</DialogTitle>
          <DialogDescription>
            WhatsApp no Bitrix{c.telefone ? ` · ${fmtTelefone(c.telefone)}` : ""} · {fmtData(c.iniciada_em)} a {fmtData(c.ultima_em)}. Mídias não foram migradas: aparece só o nome do arquivo.
          </DialogDescription>
          {(c.empresa_id || c.negocio_id) && (
            <div className="flex flex-wrap gap-2 pt-1">
              {c.empresa_id && (
                <Button size="sm" variant="outline" asChild>
                  <Link to={`/clientes/${c.empresa_id}`}>
                    <Building2 /> {c.empresa}
                  </Link>
                </Button>
              )}
              {c.negocio_id && (
                <Button size="sm" variant="outline" asChild>
                  <Link to={`/crm?negocio=${c.negocio_id}`}>Negócio #{c.negocio_numero}</Link>
                </Button>
              )}
            </div>
          )}
        </DialogHeader>
        <div className="-mx-6 flex-1 overflow-y-auto bg-muted/30 px-4 py-3">
          {q.isError ? (
            <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
          ) : q.isLoading ? (
            <Skeleton className="h-40 w-full" />
          ) : (
            <div className="space-y-1.5">
              {q.data?.map((m) => {
                const d = fmtData(m.em);
                const novoDia = d !== dia;
                dia = d;
                return (
                  <div key={m.id}>
                    {novoDia && <p className="py-2 text-center text-xs font-medium text-muted-foreground">{d}</p>}
                    {m.quem === "sistema" ? (
                      <p className="px-6 text-center text-xs italic text-muted-foreground">{m.texto}</p>
                    ) : (
                      <div className={cn("flex", m.quem === "equipe" ? "justify-end" : "justify-start")}>
                        <div className={cn("max-w-[80%] rounded-lg px-3 py-1.5 text-sm shadow-sm", m.quem === "equipe" ? "bg-primary/10" : "bg-card")}>
                          {m.quem === "equipe" && m.autor && <p className="text-xs font-medium text-primary">{m.autor}</p>}
                          {m.texto && <p className="whitespace-pre-wrap break-words">{m.texto}</p>}
                          {m.arquivos && (
                            <p className="flex items-center gap-1 text-xs text-muted-foreground">
                              <Paperclip className="h-3 w-3" aria-hidden /> {m.arquivos}
                            </p>
                          )}
                          <p className="text-right text-[10px] text-muted-foreground">{fmtDataHora(m.em).slice(-5)}</p>
                        </div>
                      </div>
                    )}
                  </div>
                );
              })}
              <div ref={fim} />
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
