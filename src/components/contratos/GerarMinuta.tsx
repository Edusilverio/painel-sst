import { useEffect, useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, FileDown, FileUp, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { EstadoErro } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { rpc } from "@/lib/supabase";
import { baixarBlob, enviarModelo, pendenciasMinuta, type Minuta } from "@/lib/minuta";
import { fmtMoeda } from "@/lib/utils";

const OUTRO = "outro";

/** Preenche a minuta da Vitalis com os dados do contrato e baixa o .docx para revisar e mandar assinar. */
export function GerarMinutaDialog({ contratoId, aberto, onFechar }: { contratoId: string; aberto: boolean; onFechar: () => void }) {
  const qc = useQueryClient();
  const q = useQuery({
    queryKey: ["contratos", "minuta", contratoId],
    queryFn: () => rpc<Minuta>("painel_contrato_minuta", { p_id: contratoId }),
    enabled: aberto,
    staleTime: 0,
  });
  const [f, setF] = useState({ representante_legal: "", email_notificacao: "", telefone: "", prazo: "12", prazo_outro: "" });
  const [cobranca, setCobranca] = useState<Record<string, string>>({});
  const [gerando, setGerando] = useState(false);
  const carregou = useRef<string | null>(null);

  useEffect(() => {
    if (!aberto) carregou.current = null;
    const m = q.data;
    if (!aberto || !m || carregou.current === m.id) return;
    carregou.current = m.id;
    const p = m.prazo_meses;
    setF({
      representante_legal: m.representante_legal ?? "",
      email_notificacao: m.email_notificacao ?? "",
      telefone: m.telefone ?? "",
      prazo: p === 24 ? "24" : p && p !== 12 ? OUTRO : "12",
      prazo_outro: p && p !== 12 && p !== 24 ? String(p) : "",
    });
    setCobranca(Object.fromEntries(m.itens.map((i) => [i.id, i.cobranca ?? ""])));
  }, [aberto, q.data]);

  const prazoMeses = f.prazo === OUTRO ? Number(f.prazo_outro) || null : Number(f.prazo);

  async function gerar() {
    if (!q.data) return;
    setGerando(true);
    try {
      await rpc<void>("painel_contrato_minuta_salvar", {
        p_id: contratoId,
        p_dados: {
          representante_legal: f.representante_legal,
          email_notificacao: f.email_notificacao,
          telefone: f.telefone,
          prazo_meses: prazoMeses,
          itens: q.data.itens.map((i) => ({ id: i.id, cobranca: cobranca[i.id] ?? "" })),
        },
      });
      const m: Minuta = {
        ...q.data,
        representante_legal: f.representante_legal.trim() || null,
        email_notificacao: f.email_notificacao.trim() || null,
        telefone: f.telefone.trim() || null,
        prazo_meses: prazoMeses,
        itens: q.data.itens.map((i) => ({ ...i, cobranca: cobranca[i.id]?.trim() || null })),
      };
      const { gerarMinuta } = await import("@/lib/minuta-docx");
      const { blob, nome } = await gerarMinuta(m);
      baixarBlob(blob, nome);
      toast.success("Minuta gerada. Revise no Word antes de mandar para assinatura.");
      qc.invalidateQueries({ queryKey: ["contratos"] });
      onFechar();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível gerar a minuta.");
    } finally {
      setGerando(false);
    }
  }

  const faltam = q.data
    ? pendenciasMinuta({ ...q.data, representante_legal: f.representante_legal || null, email_notificacao: f.email_notificacao || null })
    : [];
  const semCodigo = q.data?.itens.filter((i) => !i.codigo) ?? [];

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-h-[92vh] max-w-xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Gerar contrato (.docx)</DialogTitle>
          <DialogDescription>
            Preenche a minuta da Vitalis com o cliente, os serviços marcados, os valores e a vigência. O que não estiver no painel sai com uma linha para completar.
          </DialogDescription>
        </DialogHeader>
        {q.isError ? (
          <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
        ) : !q.data ? (
          <div className="space-y-3">
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-24 w-full" />
          </div>
        ) : (
          <div className="space-y-4">
            <div className="rounded-md bg-muted/50 p-3 text-sm">
              <p className="font-medium">{q.data.razao_social ?? "Cliente sem razão social"}</p>
              <p className="text-xs text-muted-foreground">{q.data.endereco || "Endereço não cadastrado"}</p>
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="space-y-1.5 sm:col-span-2">
                <Label htmlFor="mn-rep">Representante legal do cliente</Label>
                <Input id="mn-rep" value={f.representante_legal} onChange={(e) => setF({ ...f, representante_legal: e.target.value })} placeholder="Nome — cargo" />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="mn-email">E-mail oficial para notificações</Label>
                <Input id="mn-email" type="email" value={f.email_notificacao} onChange={(e) => setF({ ...f, email_notificacao: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="mn-tel">Telefone</Label>
                <Input id="mn-tel" value={f.telefone} onChange={(e) => setF({ ...f, telefone: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="mn-prazo">Prazo</Label>
                <Select value={f.prazo} onValueChange={(v) => setF({ ...f, prazo: v })}>
                  <SelectTrigger id="mn-prazo">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="12">12 meses</SelectItem>
                    <SelectItem value="24">24 meses</SelectItem>
                    <SelectItem value={OUTRO}>Outro</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              {f.prazo === OUTRO && (
                <div className="space-y-1.5">
                  <Label htmlFor="mn-prazo-n">Meses</Label>
                  <Input id="mn-prazo-n" type="number" min={1} max={120} value={f.prazo_outro} onChange={(e) => setF({ ...f, prazo_outro: e.target.value })} />
                </div>
              )}
            </div>

            <fieldset className="space-y-2">
              <legend className="text-sm font-medium">Serviços marcados na minuta</legend>
              {q.data.itens.length === 0 ? (
                <p className="text-sm text-muted-foreground">Nenhum serviço. Adicione na aba Serviços antes de gerar.</p>
              ) : (
                <ul className="divide-y rounded-md border">
                  {q.data.itens.map((i) => (
                    <li key={i.id} className="grid gap-2 p-2.5 sm:grid-cols-[1fr_180px] sm:items-center">
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium">{i.descricao}</p>
                        <p className="text-xs text-muted-foreground">
                          {fmtMoeda(i.preco)}
                          {i.unidade ? ` por ${i.unidade}` : ""}
                          {!i.codigo && " · fora da tabela da minuta (não aparece no item 3)"}
                        </p>
                      </div>
                      <Input
                        aria-label={`Forma de cobrança de ${i.descricao}`}
                        value={cobranca[i.id] ?? ""}
                        onChange={(e) => setCobranca((x) => ({ ...x, [i.id]: e.target.value }))}
                        placeholder="Forma de cobrança"
                        className="h-8 text-sm"
                      />
                    </li>
                  ))}
                </ul>
              )}
              {semCodigo.length > 0 && (
                <p className="text-xs text-muted-foreground">Serviços fora da tabela da minuta entram na Proposta Comercial (Anexo A).</p>
              )}
            </fieldset>

            {faltam.length > 0 && (
              <p className="flex items-start gap-2 rounded-md border border-warning/40 bg-warning/5 p-2.5 text-sm">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" aria-hidden />
                <span>Vai sair em branco: {faltam.join(", ")}.</span>
              </p>
            )}
          </div>
        )}
        <DialogFooter>
          <Button variant="outline" onClick={onFechar}>
            Cancelar
          </Button>
          <Button onClick={gerar} disabled={!q.data || gerando || (f.prazo === OUTRO && !prazoMeses)}>
            {gerando ? <Loader2 className="animate-spin" /> : <FileDown />} Gerar .docx
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** Gestor troca o arquivo-modelo da minuta (o .docx com os campos entre chaves). */
export function ModeloMinutaDialog({ aberto, onFechar }: { aberto: boolean; onFechar: () => void }) {
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [enviando, setEnviando] = useState(false);
  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Modelo da minuta</DialogTitle>
          <DialogDescription>
            O arquivo .docx que o botão "Gerar contrato" preenche. Ao mudar o texto da minuta, edite o modelo no Word mantendo os campos entre chaves, como {"{razao_social}"} e {"{x_pgr}"}, e envie de novo aqui.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-1.5">
          <Label htmlFor="mn-modelo">Arquivo .docx</Label>
          <Input
            id="mn-modelo"
            type="file"
            accept=".docx,application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            onChange={(e) => setArquivo(e.target.files?.[0] ?? null)}
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onFechar}>
            Cancelar
          </Button>
          <Button
            disabled={!arquivo || enviando}
            onClick={async () => {
              if (!arquivo) return;
              setEnviando(true);
              try {
                await enviarModelo(arquivo);
                toast.success("Modelo da minuta atualizado");
                setArquivo(null);
                onFechar();
              } catch (e) {
                toast.error(e instanceof Error ? e.message : "Não foi possível enviar o modelo.");
              } finally {
                setEnviando(false);
              }
            }}
          >
            {enviando ? <Loader2 className="animate-spin" /> : <FileUp />} Enviar modelo
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
