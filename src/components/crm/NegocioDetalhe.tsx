import { BotaoWhatsNegocio } from "@/components/whatsapp/MensagemDialog";
import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  ArrowRight,
  Building2,
  CalendarClock,
  Loader2,
  Mail,
  MessageCircle,
  NotebookPen,
  Phone,
  Plus,
  Trash2,
  Users2,
  type LucideIcon,
} from "lucide-react";
import { Dialog, DialogDescription, DialogTitle, SheetContent } from "@/components/ui/dialog";
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
  useAdicionarItem,
  useAtualizarNegocio,
  useMoverNegocio,
  useNegocio,
  useProdutos,
  useRegistrarAtividade,
  useRemoverItem,
  useSalvarItem,
  useDescontoNegocio,
  useResponsaveis,
} from "@/hooks/api";
import { corEtapa, origensNegocio, rotuloOrigem } from "@/lib/status";
import { formasPagamento, rotuloPagamento, type Funil, type FormaPagamento, type Negocio } from "@/lib/tipos";
import { cn, fmtCnpj, fmtData, fmtDataHora, fmtMoeda, tempoRelativo } from "@/lib/utils";
import { MotivoPerdaDialog } from "./MotivoPerdaDialog";

const NINGUEM = "__ninguem__";
const SEM_FORMA = "__sem_forma__";

const iconeEvento: Record<string, LucideIcon> = {
  ligacao: Phone,
  email: Mail,
  whatsapp: MessageCircle,
  reuniao: Users2,
  nota: NotebookPen,
  etapa: ArrowRight,
};

export function NegocioDetalhe({ id, funis, onFechar }: { id: string | null; funis: Funil[]; onFechar: () => void }) {
  const q = useNegocio(id);
  const n = q.data;
  const funil = funis.find((f) => f.id === n?.funil_id);

  return (
    <Dialog open={!!id} onOpenChange={(v) => !v && onFechar()}>
      <SheetContent aria-describedby={undefined}>
        {q.isLoading && (
          <div className="space-y-4 p-6">
            <DialogTitle className="sr-only">Carregando negócio</DialogTitle>
            <Skeleton className="h-6 w-2/3" />
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-64 w-full" />
          </div>
        )}
        {q.isError && (
          <div className="p-6">
            <DialogTitle className="sr-only">Erro</DialogTitle>
            <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
          </div>
        )}
        {n && funil && <Conteudo n={n} funil={funil} />}
      </SheetContent>
    </Dialog>
  );
}

function Conteudo({ n, funil }: { n: Negocio; funil: Funil }) {
  const etapa = funil.etapas.find((e) => e.id === n.etapa_id);
  const mover = useMoverNegocio();
  const [perda, setPerda] = useState<string | null>(null);
  const pode = n.pode_operar;
  const cliente = n.empresa ? n.empresa.nome_fantasia || n.empresa.razao_social : n.cliente_nome;

  function escolherEtapa(etapaId: string) {
    const alvo = funil.etapas.find((e) => e.id === etapaId);
    if (!alvo || alvo.id === n.etapa_id) return;
    if (alvo.tipo === "perdido") setPerda(alvo.id);
    else mover.mutate({ id: n.id, etapa: alvo.id });
  }

  return (
    <>
      <div className="border-b p-5 pr-12">
        <p className="text-xs text-muted-foreground">
          #{n.numero} · {funil.nome} · criado {tempoRelativo(n.criado_em)}
        </p>
        <DialogTitle className="mt-1 text-lg leading-snug">{n.titulo}</DialogTitle>
        <DialogDescription className="mt-0.5 flex items-center gap-1.5">
          <Building2 className="h-3.5 w-3.5" aria-hidden /> {cliente ?? "Cliente não informado"}
        </DialogDescription>
        <div className="mt-4 flex flex-wrap items-center gap-2">
          {etapa && <Badge variant={corEtapa[etapa.cor].badge}>{etapa.nome}</Badge>}
          <span className="text-xs text-muted-foreground">nesta etapa {tempoRelativo(n.entrou_etapa_em)}</span>
          {n.vendedor_nome && n.vendedor_nome !== n.responsavel_nome && (
            <Badge variant="outline" title="Responsável pela venda no Comercial">Vendedor: {n.vendedor_nome}</Badge>
          )}
          {n.ve_valores && <span className="ml-auto text-lg font-semibold tabular-nums">{fmtMoeda(n.valor)}</span>}
        </div>
        {pode && (
          <div className="mt-4 flex items-center gap-2">
            <Label htmlFor="mover" className="shrink-0 text-xs text-muted-foreground">
              Mover para
            </Label>
            <Select value={n.etapa_id} onValueChange={escolherEtapa} disabled={mover.isPending}>
              <SelectTrigger id="mover" className="h-8">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {funil.etapas
                  .filter((e) => e.ativo)
                  .map((e) => (
                    <SelectItem key={e.id} value={e.id}>
                      <span className="flex items-center gap-2">
                        <span className={cn("h-2 w-2 rounded-full", corEtapa[e.cor].ponto)} aria-hidden />
                        {e.nome}
                      </span>
                    </SelectItem>
                  ))}
              </SelectContent>
            </Select>
            {mover.isPending && <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />}
          </div>
        )}
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <BotaoWhatsNegocio negocioId={n.id} numero={n.numero} telefone={n.contato_telefone || n.empresa?.telefone} podeRegistrar={pode} dados={{ nome: n.contato_nome, empresa: cliente }} />
        </div>
        {n.motivo_perda && <p className="mt-3 rounded-md bg-destructive/10 p-2 text-sm text-destructive">Motivo da perda: {n.motivo_perda}</p>}
        {(n.negocio_origem || n.derivados.length > 0) && (
          <div className="mt-3 flex flex-wrap gap-2 text-xs">
            {n.negocio_origem && (
              <Link className="rounded-md border px-2 py-1 hover:bg-accent" to={`/crm?negocio=${n.negocio_origem.id}`}>
                Veio de #{n.negocio_origem.numero} ({n.negocio_origem.funil})
              </Link>
            )}
            {n.derivados.map((d) => (
              <Link key={d.id} className="rounded-md border px-2 py-1 hover:bg-accent" to={`/crm?negocio=${d.id}`}>
                → #{d.numero} em {d.funil}: {d.etapa}
              </Link>
            ))}
          </div>
        )}
      </div>

      <Tabs defaultValue="dados" className="flex min-h-0 flex-1 flex-col">
        <TabsList className="mx-5 mt-4 self-start">
          <TabsTrigger value="dados">Dados</TabsTrigger>
          <TabsTrigger value="obs">Observação</TabsTrigger>
          <TabsTrigger value="itens">Itens ({n.itens.length})</TabsTrigger>
          <TabsTrigger value="historico">Histórico</TabsTrigger>
        </TabsList>
        <div className="flex-1 overflow-y-auto px-5 pb-6">
          <TabsContent value="dados">
            <Dados n={n} pode={pode} />
          </TabsContent>
          <TabsContent value="obs">
            <Observacao n={n} pode={pode} />
          </TabsContent>
          <TabsContent value="itens">
            <Itens n={n} pode={pode} />
          </TabsContent>
          <TabsContent value="historico">
            <Historico n={n} pode={pode} />
          </TabsContent>
        </div>
      </Tabs>

      <MotivoPerdaDialog
        aberto={!!perda}
        titulo={n.titulo}
        onCancelar={() => setPerda(null)}
        onConfirmar={(motivo) => {
          if (perda) mover.mutate({ id: n.id, etapa: perda, motivo });
          setPerda(null);
        }}
      />
    </>
  );
}

function Dados({ n, pode }: { n: Negocio; pode: boolean }) {
  const salvar = useAtualizarNegocio();
  const resp = useResponsaveis();
  const inicial = useMemo(
    () => ({
      titulo: n.titulo,
      contato_nome: n.contato_nome ?? "",
      contato_telefone: n.contato_telefone ?? "",
      contato_email: n.contato_email ?? "",
      valor: Number(n.valor ?? 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }),
      previsao_fechamento: n.previsao_fechamento ?? "",
      origem: n.origem,
      responsavel_id: n.responsavel_id ?? NINGUEM,
      qtd_funcionarios: n.qtd_funcionarios ? String(n.qtd_funcionarios) : "",
      forma_pagamento: (n.forma_pagamento ?? SEM_FORMA) as string,
      parcelas: n.parcelas ? String(n.parcelas) : "",
    }),
    [n],
  );
  const [f, setF] = useState(inicial);
  useEffect(() => setF(inicial), [inicial]);
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF((x) => ({ ...x, [k]: e.target.value }));
  const mudou = JSON.stringify(f) !== JSON.stringify(inicial);

  function gravar(e: React.FormEvent) {
    e.preventDefault();
    const dados: Record<string, unknown> = {};
    (Object.keys(f) as (keyof typeof f)[]).forEach((k) => {
      if (f[k] === inicial[k]) return;
      if (k === "valor") dados.valor = Number(f.valor.replace(/\./g, "").replace(",", ".")) || 0;
      else if (k === "responsavel_id") dados.responsavel_id = f.responsavel_id === NINGUEM ? null : f.responsavel_id;
      else if (k === "forma_pagamento") dados.forma_pagamento = f.forma_pagamento === SEM_FORMA ? null : f.forma_pagamento;
      else if (k === "qtd_funcionarios" || k === "parcelas") dados[k] = f[k].trim() === "" ? null : Number(f[k]);
      else dados[k] = f[k];
    });
    salvar.mutate({ id: n.id, dados });
  }

  return (
    <form onSubmit={gravar} className="space-y-4">
      {n.empresa && (
        <div className="rounded-lg border p-3 text-sm">
          <Link to={`/clientes/${n.empresa.id}`} className="font-medium text-primary hover:underline">
            {n.empresa.razao_social}
          </Link>
          <p className="text-muted-foreground">
            {fmtCnpj(n.empresa.cnpj)} {n.empresa.cidade && `· ${n.empresa.cidade}/${n.empresa.uf ?? ""}`}
          </p>
          {(n.empresa.telefone || n.empresa.email) && (
            <p className="text-muted-foreground">{[n.empresa.telefone, n.empresa.email].filter(Boolean).join(" · ")}</p>
          )}
        </div>
      )}
      {!n.empresa && n.cliente_cnpj && <p className="text-sm text-muted-foreground">CNPJ informado: {fmtCnpj(n.cliente_cnpj)}</p>}

      <fieldset disabled={!pode} className="grid gap-3 sm:grid-cols-2">
        <div className="space-y-1.5 sm:col-span-2">
          <Label htmlFor="d-titulo">Título</Label>
          <Input id="d-titulo" value={f.titulo} onChange={set("titulo")} required />
        </div>
        <div className="space-y-1.5">
          <Label>Responsável</Label>
          <Select value={f.responsavel_id} onValueChange={(v) => setF((x) => ({ ...x, responsavel_id: v }))} disabled={!pode}>
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
        {n.ve_valores && (
          <div className="space-y-1.5">
            <Label htmlFor="d-valor">Valor (R$)</Label>
            <Input id="d-valor" value={f.valor} onChange={set("valor")} inputMode="decimal" disabled={!pode || n.itens.length > 0} />
            {n.itens.length > 0 && <p className="text-xs text-muted-foreground">Soma dos itens.</p>}
          </div>
        )}
        <div className="space-y-1.5">
          <Label htmlFor="d-contato">Contato</Label>
          <Input id="d-contato" value={f.contato_nome} onChange={set("contato_nome")} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="d-tel">Telefone / WhatsApp</Label>
          <Input id="d-tel" value={f.contato_telefone} onChange={set("contato_telefone")} inputMode="tel" />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="d-mail">E-mail</Label>
          <Input id="d-mail" type="email" value={f.contato_email} onChange={set("contato_email")} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="d-prev">Previsão de fechamento</Label>
          <Input id="d-prev" type="date" value={f.previsao_fechamento} onChange={set("previsao_fechamento")} />
        </div>
        <div className="space-y-1.5">
          <Label>Origem</Label>
          <Select value={f.origem} onValueChange={(v) => setF((x) => ({ ...x, origem: v }))} disabled={!pode}>
            <SelectTrigger>
              <SelectValue>{rotuloOrigem(f.origem)}</SelectValue>
            </SelectTrigger>
            <SelectContent>
              {origensNegocio.map((o) => (
                <SelectItem key={o.valor} value={o.valor}>
                  {o.rotulo}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="d-func">Nº de funcionários</Label>
          <Input id="d-func" type="number" min={1} step={1} value={f.qtd_funcionarios} onChange={set("qtd_funcionarios")} inputMode="numeric" />
        </div>
        <div className="space-y-1.5">
          <Label>Forma de pagamento</Label>
          <Select value={f.forma_pagamento} onValueChange={(v) => setF((x) => ({ ...x, forma_pagamento: v }))} disabled={!pode}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={SEM_FORMA}>Não informada</SelectItem>
              {formasPagamento.map((o) => (
                <SelectItem key={o.valor} value={o.valor}>
                  {o.rotulo}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="d-parc">Parcelas</Label>
          <Input id="d-parc" type="number" min={1} max={60} step={1} value={f.parcelas} onChange={set("parcelas")} inputMode="numeric" placeholder="ex.: 12" />
        </div>
      </fieldset>
      {pode && (
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" disabled={!mudou} onClick={() => setF(inicial)}>
            Descartar
          </Button>
          <Button type="submit" disabled={!mudou || salvar.isPending}>
            {salvar.isPending && <Loader2 className="animate-spin" />} Salvar
          </Button>
        </div>
      )}
      {!pode && <p className="text-xs text-muted-foreground">Seu perfil pode consultar este funil, mas não alterar.</p>}
    </form>
  );
}

function Observacao({ n, pode }: { n: Negocio; pode: boolean }) {
  const salvar = useAtualizarNegocio();
  const [texto, setTexto] = useState(n.observacao ?? "");
  useEffect(() => setTexto(n.observacao ?? ""), [n.observacao]);
  const mudou = texto !== (n.observacao ?? "");
  const o = n.negocio_origem;
  const pagOrigem = o ? rotuloPagamento(o.forma_pagamento as FormaPagamento | null, o.parcelas) : null;

  return (
    <div className="space-y-4">
      {o && (
        <div className="space-y-2 rounded-lg border bg-muted/40 p-3 text-sm">
          <p className="font-medium">
            Do {o.funil} — negócio #{o.numero}
            {o.responsavel_nome && <span className="font-normal text-muted-foreground"> · {o.responsavel_nome}</span>}
          </p>
          {(o.qtd_funcionarios || pagOrigem) && (
            <p className="text-muted-foreground">
              {[o.qtd_funcionarios ? `${o.qtd_funcionarios} funcionários` : null, pagOrigem].filter(Boolean).join(" · ")}
            </p>
          )}
          {o.observacao ? (
            <p className="whitespace-pre-wrap">{o.observacao}</p>
          ) : (
            <p className="text-muted-foreground">Sem observação no {o.funil}.</p>
          )}
          <p className="text-xs text-muted-foreground">Atualizado {tempoRelativo(o.atualizado_em)} · somente leitura aqui; quem edita é o {o.funil}.</p>
        </div>
      )}
      <div className="space-y-1.5">
        <Label htmlFor="o-obs">{o ? "Observação deste funil" : "Observação"}</Label>
        <Textarea id="o-obs" value={texto} onChange={(e) => setTexto(e.target.value)} rows={10} disabled={!pode} />
        {!o && (
          <p className="text-xs text-muted-foreground">
            Ao ganhar o negócio, esta observação vai junto para o Faturamento e o Pós-venda — e o que for alterado aqui depois também aparece lá.
          </p>
        )}
      </div>
      {pode && (
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" disabled={!mudou} onClick={() => setTexto(n.observacao ?? "")}>
            Descartar
          </Button>
          <Button type="button" disabled={!mudou || salvar.isPending} onClick={() => salvar.mutate({ id: n.id, dados: { observacao: texto } })}>
            {salvar.isPending && <Loader2 className="animate-spin" />} Salvar
          </Button>
        </div>
      )}
    </div>
  );
}

function Itens({ n, pode }: { n: Negocio; pode: boolean }) {
  const produtos = useProdutos();
  const adicionar = useAdicionarItem();
  const remover = useRemoverItem();
  const salvarItem = useSalvarItem();
  const descontoGeral = useDescontoNegocio();
  const [produto, setProduto] = useState<string>("");
  const [qtd, setQtd] = useState("1");
  const [preco, setPreco] = useState("");
  const [desc, setDesc] = useState("");
  const escolhido = produtos.data?.find((p) => p.id === produto);
  const num = (v: string) => Number(v.replace(/\./g, "").replace(",", ".")) || 0;
  const pct = (v: string) => Math.min(100, Math.max(0, Number(v.replace(",", ".")) || 0));
  const editaValores = pode && n.ve_valores;
  const subtotal = n.itens.reduce((t, i) => t + (Number(i.total) || 0), 0);
  const precoDigitado = preco ? num(preco) : escolhido?.preco ?? null;

  return (
    <div className="space-y-4">
      {n.itens.length === 0 ? (
        <p className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">
          Nenhum item. Adicione os serviços do catálogo para o valor do negócio ser a soma deles.
        </p>
      ) : (
        <ul className="divide-y rounded-lg border">
          {n.itens.map((i) => {
            const abaixo = n.ve_valores && i.preco_catalogo != null && Number(i.preco_unitario) < Number(i.preco_catalogo);
            return (
              <li key={i.id} className="flex flex-wrap items-center gap-3 p-3 text-sm">
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium">{i.descricao}</p>
                  <p className="text-xs text-muted-foreground">
                    {n.ve_valores ? `${i.quantidade} × ${fmtMoeda(i.preco_unitario)}` : `Quantidade: ${i.quantidade}`}
                    {abaixo && <span className="text-warning"> · catálogo {fmtMoeda(i.preco_catalogo!)}</span>}
                  </p>
                </div>
                {editaValores ? (
                  <label className="flex items-center gap-1 text-xs text-muted-foreground">
                    Desc.
                    <Input
                      key={`${i.id}-${i.desconto_pct}`}
                      className="h-8 w-16 text-right tabular-nums"
                      inputMode="decimal"
                      defaultValue={i.desconto_pct ? String(i.desconto_pct).replace(".", ",") : ""}
                      placeholder="0"
                      aria-label={`Desconto (%) de ${i.descricao}`}
                      onBlur={(e) => {
                        const v = pct(e.target.value);
                        if (v !== Number(i.desconto_pct ?? 0)) salvarItem.mutate({ item: i.id, negocio: n.id, desconto: v });
                      }}
                    />
                    %
                  </label>
                ) : (
                  n.ve_valores && !!Number(i.desconto_pct) && <Badge variant="outline">-{String(i.desconto_pct).replace(".", ",")}%</Badge>
                )}
                {n.ve_valores && <span className="w-24 text-right font-semibold tabular-nums">{fmtMoeda(i.total)}</span>}
                {pode && (
                  <Button variant="ghost" size="icon" aria-label={`Remover ${i.descricao}`} onClick={() => remover.mutate({ item: i.id, negocio: n.id })}>
                    <Trash2 className="h-4 w-4" />
                  </Button>
                )}
              </li>
            );
          })}
          {n.ve_valores && (
            <>
              <li className="flex items-center justify-between gap-3 p-3 text-sm">
                <span className="text-muted-foreground">Subtotal</span>
                <span className="tabular-nums">{fmtMoeda(subtotal)}</span>
              </li>
              <li className="flex items-center justify-between gap-3 p-3 text-sm">
                <span className="text-muted-foreground">Desconto geral</span>
                {editaValores ? (
                  <span className="flex items-center gap-1">
                    <Input
                      key={`geral-${n.desconto_pct}`}
                      className="h-8 w-16 text-right tabular-nums"
                      inputMode="decimal"
                      defaultValue={n.desconto_pct ? String(n.desconto_pct).replace(".", ",") : ""}
                      placeholder="0"
                      aria-label="Desconto geral (%)"
                      onBlur={(e) => {
                        const v = pct(e.target.value);
                        if (v !== Number(n.desconto_pct ?? 0)) descontoGeral.mutate({ negocio: n.id, pct: v });
                      }}
                    />
                    %
                  </span>
                ) : (
                  <span className="tabular-nums">{String(n.desconto_pct ?? 0).replace(".", ",")}%</span>
                )}
              </li>
              <li className="flex justify-between p-3 text-sm font-semibold">
                <span>Total</span>
                <span className="tabular-nums">{fmtMoeda(n.valor)}</span>
              </li>
            </>
          )}
        </ul>
      )}
      {editaValores && (
        <form
          className="grid gap-2 rounded-lg border p-3 sm:grid-cols-[1fr_4.5rem_6.5rem_4.5rem_auto] sm:items-end"
          onSubmit={(e) => {
            e.preventDefault();
            if (!produto) return;
            adicionar.mutate(
              { negocio: n.id, produto, quantidade: num(qtd) || 1, preco: preco ? num(preco) : null, desconto: pct(desc) },
              { onSuccess: () => { setProduto(""); setQtd("1"); setPreco(""); setDesc(""); } },
            );
          }}
        >
          <div className="space-y-1.5">
            <Label>Produto / serviço</Label>
            <Select value={produto} onValueChange={(v) => { setProduto(v); setPreco(""); }}>
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
            <Label htmlFor="i-qtd">Qtd.</Label>
            <Input id="i-qtd" value={qtd} onChange={(e) => setQtd(e.target.value)} inputMode="decimal" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="i-preco">Preço unit.</Label>
            <Input
              id="i-preco"
              value={preco}
              onChange={(e) => setPreco(e.target.value)}
              inputMode="decimal"
              placeholder={escolhido?.preco != null ? String(escolhido.preco).replace(".", ",") : "0,00"}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="i-desc">Desc. %</Label>
            <Input id="i-desc" value={desc} onChange={(e) => setDesc(e.target.value)} inputMode="decimal" placeholder="0" />
          </div>
          <Button type="submit" disabled={!produto || adicionar.isPending}>
            {adicionar.isPending ? <Loader2 className="animate-spin" /> : <Plus />} Adicionar
          </Button>
          {escolhido?.preco != null && precoDigitado != null && precoDigitado < escolhido.preco && (
            <p className="text-xs text-warning sm:col-span-5">Abaixo do catálogo ({fmtMoeda(escolhido.preco)}): fica registrado como desconto no relatório.</p>
          )}
        </form>
      )}
    </div>
  );
}

const TIPOS_ATIVIDADE = [
  { valor: "nota", rotulo: "Nota" },
  { valor: "ligacao", rotulo: "Ligação" },
  { valor: "whatsapp", rotulo: "WhatsApp" },
  { valor: "email", rotulo: "E-mail" },
  { valor: "reuniao", rotulo: "Reunião" },
];

function Historico({ n, pode }: { n: Negocio; pode: boolean }) {
  const registrar = useRegistrarAtividade();
  const [tipo, setTipo] = useState("nota");
  const [texto, setTexto] = useState("");

  return (
    <div className="space-y-5">
      {pode && (
        <form
          className="space-y-2 rounded-lg border p-3"
          onSubmit={(e) => {
            e.preventDefault();
            registrar.mutate({ id: n.id, tipo, texto }, { onSuccess: () => setTexto("") });
          }}
        >
          <div className="flex flex-wrap gap-1.5">
            {TIPOS_ATIVIDADE.map((t) => (
              <Button key={t.valor} type="button" size="sm" variant={tipo === t.valor ? "default" : "outline"} onClick={() => setTipo(t.valor)}>
                {t.rotulo}
              </Button>
            ))}
          </div>
          <Textarea value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="O que aconteceu? Ex.: liguei, pediu proposta para 40 colaboradores." rows={2} aria-label="Descrição da atividade" />
          <div className="flex justify-end">
            <Button type="submit" size="sm" disabled={!texto.trim() || registrar.isPending}>
              {registrar.isPending && <Loader2 className="animate-spin" />} Registrar
            </Button>
          </div>
        </form>
      )}
      <ol className="relative space-y-4 border-l pl-5">
        {n.eventos.map((ev) => {
          const Icone = iconeEvento[ev.tipo] ?? CalendarClock;
          return (
            <li key={ev.id} className="relative">
              <span className="absolute -left-[1.85rem] flex h-6 w-6 items-center justify-center rounded-full border bg-card">
                <Icone className="h-3.5 w-3.5 text-muted-foreground" aria-hidden />
              </span>
              <p className="text-sm">
                {ev.tipo === "etapa" ? (
                  <>
                    {ev.de_etapa ?? "—"} <ArrowRight className="inline h-3 w-3" aria-label="para" /> <strong>{ev.para_etapa}</strong>
                    {ev.texto && <span className="block text-muted-foreground">{ev.texto}</span>}
                  </>
                ) : (
                  ev.texto
                )}
              </p>
              <p className="text-xs text-muted-foreground">
                {ev.autor ?? "Sistema"} · {fmtDataHora(ev.criado_em)}
              </p>
            </li>
          );
        })}
      </ol>
      {n.previsao_fechamento && <p className="text-xs text-muted-foreground">Previsão de fechamento: {fmtData(n.previsao_fechamento)}</p>}
    </div>
  );
}
