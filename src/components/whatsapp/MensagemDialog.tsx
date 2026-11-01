import { useEffect, useMemo, useState } from "react";
import { Copy, ExternalLink, MessageCircle } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { EstadoErro } from "@/components/ui/estados";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { useRegistrarAtividade, useWaContexto, useWaModelos } from "@/hooks/api";
import { CATEGORIAS_WA, fmtTelefone, linkIniciarConversa, linkInbox, pendentes, preencher, primeiroNome, telefoneWhats } from "@/lib/whatsapp";
import { toast } from "sonner";

export interface DadosMensagem {
  nome?: string | null;
  empresa?: string | null;
  [chave: string]: string | null | undefined;
}

/**
 * Escolhe um modelo, preenche com os dados do contato e copia. O envio acontece no Inbox do
 * Exemplo Connect — o painel não envia mensagem sozinho.
 */
export function MensagemDialog({
  aberto,
  onFechar,
  dados,
  inbox,
  modeloInicial,
  onAbrir,
}: {
  onAbrir?: () => void;
  aberto: boolean;
  onFechar: () => void;
  dados: DadosMensagem;
  inbox?: string | null;
  modeloInicial?: string | null;
}) {
  const modelos = useWaModelos();
  const ctx = useWaContexto(null);
  const ativos = useMemo(() => (modelos.data ?? []).filter((m) => m.ativo), [modelos.data]);
  const [modeloId, setModeloId] = useState<string>("");
  const [texto, setTexto] = useState("");

  // chave estável: quem chama costuma criar o objeto `dados` a cada render, e isso não pode apagar o que a pessoa editou
  const chaveDados = JSON.stringify(dados);
  const valores = useMemo(() => {
    const d = JSON.parse(chaveDados) as DadosMensagem;
    return { ...d, nome: primeiroNome(d.nome), atendente: primeiroNome(ctx.data?.atendente) };
  }, [chaveDados, ctx.data?.atendente]);

  useEffect(() => {
    if (!aberto) return;
    const id = modeloInicial && ativos.some((m) => m.id === modeloInicial) ? modeloInicial : ativos[0]?.id ?? "";
    setModeloId(id);
  }, [aberto, modeloInicial, ativos]);

  useEffect(() => {
    const m = ativos.find((x) => x.id === modeloId);
    setTexto(m ? preencher(m.texto, valores) : "");
  }, [modeloId, ativos, valores]);

  const faltam = pendentes(texto);

  async function copiar(abrir: boolean) {
    try {
      await navigator.clipboard.writeText(texto);
      toast.success(abrir ? "Mensagem copiada — cole no Inbox" : "Mensagem copiada");
    } catch {
      toast.error("Não foi possível copiar. Selecione o texto e copie manualmente.");
      return;
    }
    if (abrir && inbox) {
      window.open(inbox, "_blank", "noopener");
      onAbrir?.();
    }
    onFechar();
  }

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <MessageCircle className="h-5 w-5 text-success" aria-hidden /> Mensagem pronta
          </DialogTitle>
          <DialogDescription>
            Escolha o modelo, confira o texto e copie. O envio é feito no Inbox do Exemplo Connect, pelo número da Vitalis.
          </DialogDescription>
        </DialogHeader>

        {modelos.isError ? (
          <EstadoErro erro={modelos.error} onTentar={() => modelos.refetch()} />
        ) : modelos.isLoading ? (
          <div className="space-y-3">
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-32 w-full" />
          </div>
        ) : ativos.length === 0 ? (
          <p className="rounded-md border border-dashed p-4 text-sm text-muted-foreground">
            Nenhum modelo ativo. Um gestor pode cadastrar em Configurações › WhatsApp.
          </p>
        ) : (
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="wa-modelo">Modelo</Label>
              <Select value={modeloId} onValueChange={setModeloId}>
                <SelectTrigger id="wa-modelo">
                  <SelectValue placeholder="Escolha um modelo" />
                </SelectTrigger>
                <SelectContent>
                  {ativos.map((m) => (
                    <SelectItem key={m.id} value={m.id}>
                      {CATEGORIAS_WA[m.categoria]} · {m.titulo}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="wa-texto">Texto</Label>
              <Textarea id="wa-texto" rows={7} value={texto} onChange={(e) => setTexto(e.target.value)} />
              {faltam.length > 0 && (
                <p className="flex flex-wrap items-center gap-1 text-xs text-warning">
                  Complete antes de enviar:
                  {faltam.map((f) => (
                    <Badge key={f} variant="warning">{`{${f}}`}</Badge>
                  ))}
                </p>
              )}
            </div>
          </div>
        )}

        <DialogFooter className="gap-2 sm:gap-0">
          <Button variant="outline" onClick={() => copiar(false)} disabled={!texto}>
            <Copy /> Copiar
          </Button>
          {inbox && (
            <Button onClick={() => copiar(true)} disabled={!texto}>
              <ExternalLink /> Copiar e abrir no Inbox
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/**
 * Botões do card do CRM (pedido de 07/10): a conversa com o cliente começa no Exemplo Connect, em atendimento
 * humano. Se o contato já conversou com a Vitalis, abre a conversa existente; senão abre o Inbox iniciando uma nova
 * com o telefone do card. O painel não envia nada sozinho; registra no histórico do card que a conversa foi aberta.
 */
export function BotaoWhatsNegocio({
  negocioId,
  numero,
  telefone,
  dados,
  podeRegistrar,
}: {
  podeRegistrar: boolean;
  negocioId: string;
  numero: number;
  telefone: string | null | undefined;
  dados: DadosMensagem;
}) {
  const ctx = useWaContexto(negocioId);
  const registrar = useRegistrarAtividade();
  const [aberto, setAberto] = useState(false);
  const base = ctx.data?.inbox_url;
  const existente = ctx.data ? linkInbox(ctx.data.inbox_url, ctx.data.contato) : null;
  const fone = telefoneWhats(telefone);
  const iniciar = base && fone ? linkIniciarConversa(base, { telefone: fone, nome: dados.nome, empresa: dados.empresa, ref: `vitalis-crm:${numero}` }) : null;
  const destino = existente ?? iniciar;

  function registrarInicio() {
    if (podeRegistrar && !existente && fone)
      registrar.mutate({ id: negocioId, tipo: "whatsapp", texto: `Conversa iniciada no Exemplo Connect com ${fmtTelefone(fone)}` });
  }

  function abrir() {
    if (!destino) return;
    window.open(destino, "_blank", "noopener");
    registrarInicio();
  }

  return (
    <>
      <Button size="sm" className="bg-success text-success-foreground hover:bg-success/90" onClick={abrir} disabled={!destino}>
        <MessageCircle /> {existente ? "Abrir conversa no WhatsApp" : "Iniciar conversa no WhatsApp"}
      </Button>
      <Button size="sm" variant="outline" onClick={() => setAberto(true)}>
        <Copy /> Modelo de mensagem
      </Button>
      {!destino && !ctx.isLoading && (
        <p className="w-full text-xs text-muted-foreground">
          {telefone?.trim() ? "Telefone inválido para WhatsApp. Corrija na aba Dados (com DDD)." : "Cadastre o telefone do contato na aba Dados para iniciar a conversa."}
        </p>
      )}
      <MensagemDialog aberto={aberto} onFechar={() => setAberto(false)} dados={dados} inbox={destino ?? base} onAbrir={destino ? registrarInicio : undefined} />
    </>
  );
}
