import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { Building2, FileDown, FileText, Loader2, Paperclip, Plus, RefreshCcw, Trash2, Upload } from "lucide-react";
import { GerarMinutaDialog } from "@/components/contratos/GerarMinuta";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, SheetContent } from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { EstadoErro } from "@/components/ui/estados";
import {
  abrirArquivo,
  useArquivoContrato,
  useContrato,
  useItemContrato,
  useProdutos,
  useRemoverItemContrato,
  useResponsaveis,
  useSalvarContrato,
  useStatusContrato,
} from "@/hooks/api";
import { ORDEM_STATUS_CONTRATO, situacaoContrato, statusContrato } from "@/lib/status";
import type { ContratoDetalhe as Detalhe } from "@/lib/tipos";
import { fmtCnpj, fmtData, fmtDataHora, fmtMoeda } from "@/lib/utils";

const NINGUEM = "__ninguem__";
const num = (v: string) => (v.trim() ? Number(v.replace(/\./g, "").replace(",", ".")) : null);
const txt = (v: number | null | undefined) => (v == null ? "" : String(v).replace(".", ","));

export function ContratoDetalhe({ id, onFechar }: { id: string | null; onFechar: () => void }) {
  const q = useContrato(id);
  return (
    <Dialog open={!!id} onOpenChange={(v) => !v && onFechar()}>
      <SheetContent aria-describedby={undefined} className="sm:max-w-2xl">
        {q.isLoading && (
          <div className="space-y-4 p-6">
            <DialogTitle className="sr-only">Carregando contrato</DialogTitle>
            <Skeleton className="h-7 w-2/3" />
            <Skeleton className="h-64 w-full" />
          </div>
        )}
        {q.isError && (
          <div className="p-6">
            <DialogTitle className="sr-only">Erro</DialogTitle>
            <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
          </div>
        )}
        {q.data && <Conteudo c={q.data} />}
      </SheetContent>
    </Dialog>
  );
}

function Conteudo({ c }: { c: Detalhe }) {
  const status = useStatusContrato();
  const [cancelar, setCancelar] = useState(false);
  const [minuta, setMinuta] = useState(false);
  const sit = situacaoContrato[c.situacao];
  const editavel = c.status !== "cancelado";

  return (
    <div className="flex h-full flex-col overflow-hidden">
      <div className="border-b p-5 pr-12">
        <p className="text-xs text-muted-foreground">
          Contrato #{c.numero}
          {c.negocio_numero && (
            <>
              {" · "}
              <Link to={`/crm?funil=comercial&negocio=${c.negocio_id}`} className="text-primary hover:underline">
                negócio #{c.negocio_numero}
              </Link>
            </>
          )}
        </p>
        <DialogTitle className="mt-1 text-lg leading-snug">{c.titulo}</DialogTitle>
        <DialogDescription className="mt-0.5 flex items-center gap-1.5">
          <Building2 className="h-3.5 w-3.5" aria-hidden />
          {c.empresa_id ? (
            <Link to={`/clientes/${c.empresa_id}`} className="hover:underline">
              {c.cliente}
            </Link>
          ) : (
            c.cliente
          )}
          {c.cnpj && <span className="text-muted-foreground">· {fmtCnpj(c.cnpj)}</span>}
        </DialogDescription>
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <Badge variant={sit.badge}>{sit.rotulo}</Badge>
          {c.fim && <span className="text-xs text-muted-foreground">vigência até {fmtData(c.fim)}</span>}
          <span className="ml-auto text-lg font-semibold tabular-nums">
            {c.valor_mensal != null ? `${fmtMoeda(c.valor_mensal)}/mês` : fmtMoeda(c.valor_total)}
          </span>
        </div>
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <Select value={c.status} onValueChange={(v) => (v === "cancelado" ? setCancelar(true) : status.mutate({ id: c.id, status: v }))}>
            <SelectTrigger className="w-[220px]" aria-label="Status da assinatura">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {[...ORDEM_STATUS_CONTRATO, "cancelado" as const].map((s) => (
                <SelectItem key={s} value={s}>
                  {statusContrato[s].rotulo}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          {editavel && (
            <Button variant="outline" size="sm" onClick={() => setMinuta(true)}>
              <FileDown /> Gerar contrato
            </Button>
          )}
          {c.renovacao_negocio_id && (
            <Button asChild variant="outline" size="sm">
              <Link to={`/crm?funil=pos-venda&negocio=${c.renovacao_negocio_id}`}>
                <RefreshCcw /> Card de renovação
              </Link>
            </Button>
          )}
        </div>
        {c.status === "cancelado" && c.cancelado_motivo && <p className="mt-2 text-sm text-destructive">Cancelado: {c.cancelado_motivo}</p>}
      </div>

      <Tabs defaultValue="dados" className="flex min-h-0 flex-1 flex-col">
        <TabsList className="mx-5 mt-4 w-fit">
          <TabsTrigger value="dados">Dados</TabsTrigger>
          <TabsTrigger value="itens">Serviços ({c.itens.length})</TabsTrigger>
          <TabsTrigger value="historico">Histórico</TabsTrigger>
        </TabsList>
        <div className="flex-1 overflow-y-auto p-5">
          <TabsContent value="dados" className="mt-0 space-y-6">
            <Arquivo c={c} editavel={editavel} />
            <Formulario c={c} editavel={editavel} />
          </TabsContent>
          <TabsContent value="itens" className="mt-0">
            <Itens c={c} editavel={editavel} />
          </TabsContent>
          <TabsContent value="historico" className="mt-0">
            <ol className="space-y-3">
              {c.eventos.map((e, i) => (
                <li key={i} className="border-l-2 border-primary/30 pl-3">
                  <p className="text-sm">{e.texto}</p>
                  <p className="text-xs text-muted-foreground">
                    {e.autor} · {fmtDataHora(e.criado_em)}
                  </p>
                </li>
              ))}
            </ol>
          </TabsContent>
        </div>
      </Tabs>

      <GerarMinutaDialog contratoId={c.id} aberto={minuta} onFechar={() => setMinuta(false)} />
      <CancelarContrato
        aberto={cancelar}
        onFechar={() => setCancelar(false)}
        onConfirmar={(m) => {
          status.mutate({ id: c.id, status: "cancelado", motivo: m });
          setCancelar(false);
        }}
      />
    </div>
  );
}

function Arquivo({ c, editavel }: { c: Detalhe; editavel: boolean }) {
  const arquivo = useArquivoContrato();
  const ref = useRef<HTMLInputElement>(null);
  return (
    <div className="flex flex-wrap items-center gap-3 rounded-lg border border-dashed p-3">
      <FileText className="h-5 w-5 text-muted-foreground" aria-hidden />
      <div className="min-w-0 flex-1">
        {c.arquivo_path ? (
          <button type="button" onClick={() => abrirArquivo(c.arquivo_path!)} className="block truncate text-sm font-medium text-primary hover:underline">
            {c.arquivo_nome ?? "Contrato.pdf"}
          </button>
        ) : (
          <p className="text-sm text-muted-foreground">Nenhum arquivo anexado</p>
        )}
        <p className="text-xs text-muted-foreground">PDF ou Word, até 25 MB. O link de download vale 2 minutos.</p>
      </div>
      {editavel && (
        <>
          <input
            ref={ref}
            type="file"
            accept=".pdf,.doc,.docx,application/pdf"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) arquivo.mutate({ contrato: c.id, arquivo: f, caminhoAtual: c.arquivo_path });
              e.target.value = "";
            }}
          />
          <Button size="sm" variant="outline" onClick={() => ref.current?.click()} disabled={arquivo.isPending}>
            {arquivo.isPending ? <Loader2 className="animate-spin" /> : c.arquivo_path ? <Paperclip /> : <Upload />}
            {c.arquivo_path ? "Trocar" : "Anexar"}
          </Button>
          {c.arquivo_path && (
            <Button size="icon" variant="ghost" aria-label="Remover arquivo" onClick={() => arquivo.mutate({ contrato: c.id, arquivo: null, caminhoAtual: c.arquivo_path })}>
              <Trash2 />
            </Button>
          )}
        </>
      )}
    </div>
  );
}

function Formulario({ c, editavel }: { c: Detalhe; editavel: boolean }) {
  const salvar = useSalvarContrato();
  const resp = useResponsaveis();
  const inicial = () => ({
    titulo: c.titulo,
    inicio: c.inicio ?? "",
    fim: c.fim ?? "",
    renovacao_automatica: c.renovacao_automatica,
    aviso_dias: String(c.aviso_dias),
    valor_mensal: txt(c.valor_mensal),
    dia_vencimento: c.dia_vencimento ? String(c.dia_vencimento) : "",
    forma_pagamento: c.forma_pagamento ?? "",
    indice_reajuste: c.indice_reajuste ?? "",
    responsavel_id: c.responsavel_id ?? NINGUEM,
    observacao: c.observacao ?? "",
  });
  const [f, setF] = useState(inicial);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => setF(inicial()), [c.id, c.atualizado_em]);
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF((x) => ({ ...x, [k]: e.target.value }));

  return (
    <form
      className="grid gap-4 sm:grid-cols-2"
      onSubmit={(e) => {
        e.preventDefault();
        salvar.mutate({
          id: c.id,
          dados: {
            titulo: f.titulo,
            inicio: f.inicio || null,
            fim: f.fim || null,
            renovacao_automatica: f.renovacao_automatica,
            aviso_dias: f.aviso_dias,
            valor_mensal: num(f.valor_mensal),
            dia_vencimento: f.dia_vencimento || null,
            forma_pagamento: f.forma_pagamento,
            indice_reajuste: f.indice_reajuste,
            responsavel_id: f.responsavel_id === NINGUEM ? null : f.responsavel_id,
            observacao: f.observacao,
          },
        });
      }}
    >
      <fieldset disabled={!editavel} className="contents">
        <div className="space-y-1.5 sm:col-span-2">
          <Label htmlFor="c-titulo">Título</Label>
          <Input id="c-titulo" value={f.titulo} onChange={set("titulo")} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="c-inicio">Início da vigência</Label>
          <Input id="c-inicio" type="date" value={f.inicio} onChange={set("inicio")} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="c-fim">Fim da vigência</Label>
          <Input id="c-fim" type="date" value={f.fim} onChange={set("fim")} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="c-aviso">Avisar renovação com (dias)</Label>
          <Input id="c-aviso" type="number" min={0} max={365} value={f.aviso_dias} onChange={set("aviso_dias")} />
        </div>
        <label className="flex items-center gap-2 self-end pb-2 text-sm">
          <input
            type="checkbox"
            className="h-4 w-4 accent-[hsl(var(--primary))]"
            checked={f.renovacao_automatica}
            onChange={(e) => setF((x) => ({ ...x, renovacao_automatica: e.target.checked }))}
          />
          Renovação automática
        </label>
        <div className="space-y-1.5">
          <Label htmlFor="c-mensal">Valor mensal (R$)</Label>
          <Input id="c-mensal" inputMode="decimal" value={f.valor_mensal} onChange={set("valor_mensal")} placeholder="0,00" />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="c-dia">Dia de vencimento</Label>
          <Input id="c-dia" type="number" min={1} max={31} value={f.dia_vencimento} onChange={set("dia_vencimento")} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="c-forma">Forma de pagamento</Label>
          <Input id="c-forma" value={f.forma_pagamento} onChange={set("forma_pagamento")} placeholder="Boleto, PIX…" />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="c-indice">Índice de reajuste</Label>
          <Input id="c-indice" value={f.indice_reajuste} onChange={set("indice_reajuste")} placeholder="IPCA, IGP-M…" />
        </div>
        <div className="space-y-1.5 sm:col-span-2">
          <Label>Responsável</Label>
          <Select value={f.responsavel_id} onValueChange={(v) => setF((x) => ({ ...x, responsavel_id: v }))} disabled={!editavel}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={NINGUEM}>Sem responsável</SelectItem>
              {resp.data?.map((r) => (
                <SelectItem key={r.user_id} value={r.user_id}>
                  {r.nome}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5 sm:col-span-2">
          <Label htmlFor="c-obs">Observações</Label>
          <Textarea id="c-obs" rows={3} value={f.observacao} onChange={set("observacao")} />
        </div>
      </fieldset>
      {editavel && (
        <div className="flex justify-end sm:col-span-2">
          <Button type="submit" disabled={salvar.isPending}>
            {salvar.isPending && <Loader2 className="animate-spin" />} Salvar alterações
          </Button>
        </div>
      )}
    </form>
  );
}

function Itens({ c, editavel }: { c: Detalhe; editavel: boolean }) {
  const produtos = useProdutos();
  const adicionar = useItemContrato();
  const remover = useRemoverItemContrato();
  const [produto, setProduto] = useState("");
  const [qtd, setQtd] = useState("1");
  const [preco, setPreco] = useState("");
  const escolhido = produtos.data?.find((p) => p.id === produto);

  return (
    <div className="space-y-4">
      {c.itens.length === 0 ? (
        <p className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">Nenhum serviço listado neste contrato.</p>
      ) : (
        <ul className="divide-y rounded-lg border">
          {c.itens.map((i) => (
            <li key={i.id} className="flex items-center gap-3 p-3 text-sm">
              <div className="min-w-0 flex-1">
                <p className="truncate font-medium">{i.descricao}</p>
                <p className="text-xs text-muted-foreground">
                  {i.quantidade} × {fmtMoeda(i.preco)}
                </p>
              </div>
              <span className="font-semibold tabular-nums">{fmtMoeda(i.total)}</span>
              {editavel && (
                <Button variant="ghost" size="icon" aria-label={`Remover ${i.descricao}`} onClick={() => remover.mutate(i.id)}>
                  <Trash2 className="h-4 w-4" />
                </Button>
              )}
            </li>
          ))}
          <li className="flex justify-between p-3 text-sm font-semibold">
            <span>Total do contrato</span>
            <span className="tabular-nums">{fmtMoeda(c.valor_total)}</span>
          </li>
        </ul>
      )}
      {editavel && (
        <form
          className="grid gap-2 rounded-lg border p-3 sm:grid-cols-[1fr_5rem_7rem_auto] sm:items-end"
          onSubmit={(e) => {
            e.preventDefault();
            if (!produto) return;
            adicionar.mutate(
              { contrato: c.id, produto, descricao: null, quantidade: num(qtd) ?? 1, preco: num(preco) },
              {
                onSuccess: () => {
                  setProduto("");
                  setQtd("1");
                  setPreco("");
                },
              },
            );
          }}
        >
          <div className="space-y-1.5">
            <Label>Serviço</Label>
            <Select value={produto} onValueChange={setProduto}>
              <SelectTrigger>
                <SelectValue placeholder={produtos.isLoading ? "Carregando…" : "Escolha do catálogo"} />
              </SelectTrigger>
              <SelectContent>
                {produtos.data?.map((p) => (
                  <SelectItem key={p.id} value={p.id}>
                    {p.nome} {p.preco != null && `· ${fmtMoeda(p.preco)}`}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ci-qtd">Qtd.</Label>
            <Input id="ci-qtd" value={qtd} onChange={(e) => setQtd(e.target.value)} inputMode="decimal" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ci-preco">Preço unit.</Label>
            <Input id="ci-preco" value={preco} onChange={(e) => setPreco(e.target.value)} inputMode="decimal" placeholder={escolhido?.preco != null ? txt(escolhido.preco) : "0,00"} />
          </div>
          <Button type="submit" disabled={!produto || adicionar.isPending}>
            {adicionar.isPending ? <Loader2 className="animate-spin" /> : <Plus />} Adicionar
          </Button>
        </form>
      )}
    </div>
  );
}

const MOTIVOS = ["Cliente desistiu", "Substituído por novo contrato", "Inadimplência", "Duplicado"];

function CancelarContrato({ aberto, onFechar, onConfirmar }: { aberto: boolean; onFechar: () => void; onConfirmar: (m: string) => void }) {
  const [motivo, setMotivo] = useState("");
  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Cancelar contrato</DialogTitle>
          <DialogDescription>O contrato sai da lista de vigentes e para de gerar aviso de renovação.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-wrap gap-2">
          {MOTIVOS.map((m) => (
            <Button key={m} size="sm" type="button" variant={motivo === m ? "default" : "outline"} onClick={() => setMotivo(m)}>
              {m}
            </Button>
          ))}
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="cc-motivo">Motivo</Label>
          <Textarea id="cc-motivo" rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)} />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onFechar}>
            Voltar
          </Button>
          <Button variant="destructive" disabled={!motivo.trim()} onClick={() => onConfirmar(motivo.trim())}>
            Cancelar contrato
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
