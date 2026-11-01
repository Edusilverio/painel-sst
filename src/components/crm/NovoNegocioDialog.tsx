import { useMemo, useState } from "react";
import { AlertTriangle, Loader2, Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { useCriarNegocioV2, useProdutos, useResponsaveis } from "@/hooks/api";
import { origensNegocio } from "@/lib/status";
import { formasPagamento, type Funil } from "@/lib/tipos";
import { fmtCnpj, fmtMoeda } from "@/lib/utils";
import { EmpresaSelect, type EmpresaEscolhida } from "./EmpresaSelect";
import { useSessao } from "@/contexts/sessao";

const RODIZIO = "__rodizio__";
const NINGUEM = "__ninguem__";
const SEM = "__sem__";

interface Linha {
  chave: number;
  produto: string;
  quantidade: string;
  preco: string;
  desconto: string;
}

const numero = (v: string) => Number(v.replace(/\./g, "").replace(",", ".")) || 0;
const VAZIO = { titulo: "", contato_nome: "", contato_telefone: "", contato_email: "", valor: "", origem: "manual", observacao: "", previsao: "", parcelas: "", forma: SEM, desconto: "" };

/**
 * Novo negócio (reunião 13/10): empresa obrigatória (razão social + CNPJ; se não existir, cadastra pela busca),
 * serviços do catálogo (vários) com quantidade e preço, e parcelamento. O valor do negócio é a soma dos serviços.
 */
export function NovoNegocioDialog({
  funil,
  aberto,
  onFechar,
  onCriado,
  empresaInicial = null,
}: {
  funil: Funil;
  aberto: boolean;
  onFechar: () => void;
  onCriado?: (id: string) => void;
  empresaInicial?: EmpresaEscolhida | null;
}) {
  const criar = useCriarNegocioV2();
  const resp = useResponsaveis();
  const produtos = useProdutos();
  const veValores = useSessao().tem("financeiro", "comercial"); // 0074: quem não vê valores não lança serviço com preço
  const [empresa, setEmpresa] = useState<EmpresaEscolhida | null>(empresaInicial);
  const [f, setF] = useState(VAZIO);
  const [linhas, setLinhas] = useState<Linha[]>([]);
  const [responsavel, setResponsavel] = useState<string>(funil.usa_rodizio ? RODIZIO : NINGUEM);
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF((x) => ({ ...x, [k]: e.target.value }));

  const catalogo = useMemo(() => new Map((produtos.data ?? []).map((p) => [p.id, p])), [produtos.data]);
  const pct = (v: string) => Math.min(100, Math.max(0, Number(v.replace(",", ".")) || 0));
  const subtotal = linhas.reduce((s, l) => s + numero(l.quantidade || "1") * numero(l.preco) * (1 - pct(l.desconto) / 100), 0);
  const total = subtotal * (1 - pct(f.desconto) / 100);
  // 0081 (Renata, 20/10): o catálogo é referência; abaixo dele pode, e fica no relatório de descontos
  const abaixo = linhas.filter((l) => {
    const p = catalogo.get(l.produto);
    return p?.preco != null && l.preco.trim() && numero(l.preco) * (1 - pct(l.desconto) / 100) < p.preco;
  });
  const problemas = linhas.flatMap((l) => {
    const p = catalogo.get(l.produto);
    if (!l.produto) return ["Escolha o serviço em todas as linhas."];
    if (!l.preco.trim()) return [`Informe o preço de ${p?.nome ?? "um serviço"}.`];
    return [];
  });

  function limpar() {
    setEmpresa(empresaInicial);
    setF(VAZIO);
    setLinhas([]);
    setResponsavel(funil.usa_rodizio ? RODIZIO : NINGUEM);
  }

  function addLinha() {
    setLinhas((ls) => [...ls, { chave: Date.now() + ls.length, produto: "", quantidade: "1", preco: "", desconto: "" }]);
  }
  function mudar(chave: number, campo: keyof Omit<Linha, "chave">, valor: string) {
    setLinhas((ls) =>
      ls.map((l) => {
        if (l.chave !== chave) return l;
        const nova = { ...l, [campo]: valor };
        // ao escolher o serviço, sugere o preço do catálogo
        if (campo === "produto") {
          const p = catalogo.get(valor);
          nova.preco = p?.preco != null ? String(p.preco).replace(".", ",") : "";
        }
        return nova;
      }),
    );
  }

  async function salvar(e: React.FormEvent) {
    e.preventDefault();
    if (!empresa || problemas.length) return;
    const id = await criar
      .mutateAsync({
        dados: {
          funil: funil.id,
          titulo: f.titulo || null,
          empresa_id: empresa.id,
          contato_nome: f.contato_nome,
          contato_telefone: f.contato_telefone,
          contato_email: f.contato_email,
          responsavel: responsavel === RODIZIO || responsavel === NINGUEM ? null : responsavel,
          valor: linhas.length ? null : numero(f.valor),
          origem: f.origem,
          observacao: f.observacao,
          previsao: f.previsao || null,
          parcelas: f.parcelas ? Number(f.parcelas) : null,
          forma_pagamento: f.forma === SEM ? null : f.forma,
          desconto_pct: linhas.length ? pct(f.desconto) : null,
        },
        itens: linhas.map((l) => ({ produto: l.produto, quantidade: numero(l.quantidade || "1"), preco: numero(l.preco), desconto: pct(l.desconto) })),
      })
      .catch(() => null);
    if (id) {
      limpar();
      onFechar();
      onCriado?.(id);
    }
  }

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-h-[92vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Novo negócio · {funil.nome}</DialogTitle>
          <DialogDescription>Entra na primeira etapa do funil. Empresa com razão social e CNPJ é obrigatória.</DialogDescription>
        </DialogHeader>
        <form onSubmit={salvar} className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="empresa">
              Empresa (razão social e CNPJ) <span className="text-destructive">*</span>
            </Label>
            <EmpresaSelect id="empresa" valor={empresa} onChange={setEmpresa} />
            {empresa && !empresa.cnpj && (
              <p className="flex items-center gap-1 text-xs text-warning">
                <AlertTriangle className="h-3.5 w-3.5" /> Esta empresa está sem CNPJ no cadastro: complete na ficha dela antes de criar o negócio.
              </p>
            )}
            {!empresa && <p className="text-xs text-muted-foreground">Não achou? Na busca, use "Cadastrar empresa nova" (o CNPJ puxa os dados da Receita).</p>}
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="titulo">Título do negócio</Label>
            <Input id="titulo" placeholder={empresa ? `${empresa.nome}${empresa.cnpj ? ` · ${fmtCnpj(empresa.cnpj)}` : ""}` : "Ex.: PGR + PCMSO 2026"} value={f.titulo} onChange={set("titulo")} />
          </div>

          {veValores && (
            <fieldset className="space-y-2 rounded-lg border p-3 sm:col-span-2">
              <legend className="px-1 text-sm font-medium">Serviços do catálogo</legend>
              {linhas.length === 0 && <p className="text-xs text-muted-foreground">Nenhum serviço. Adicione os serviços vendidos: o valor do negócio será a soma.</p>}
              {linhas.map((l) => {
                const p = catalogo.get(l.produto);
                return (
                  <div key={l.chave} className="grid grid-cols-[1fr_4rem_6rem_4rem_auto] items-end gap-2">
                    <div className="space-y-1">
                      <Select value={l.produto} onValueChange={(v) => mudar(l.chave, "produto", v)}>
                        <SelectTrigger aria-label="Serviço">
                          <SelectValue placeholder={produtos.isLoading ? "Carregando…" : "Escolha o serviço"} />
                        </SelectTrigger>
                        <SelectContent>
                          {produtos.data?.map((pr) => (
                            <SelectItem key={pr.id} value={pr.id}>
                              {pr.nome} {pr.preco != null && `· ${fmtMoeda(pr.preco)}`}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <Input aria-label="Quantidade" value={l.quantidade} onChange={(e) => mudar(l.chave, "quantidade", e.target.value)} inputMode="decimal" />
                    <Input
                      aria-label="Preço unitário"
                      value={l.preco}
                      onChange={(e) => mudar(l.chave, "preco", e.target.value)}
                      inputMode="decimal"
                      placeholder={p?.preco != null ? String(p.preco).replace(".", ",") : "Preço"}
                    />
                    <Input aria-label="Desconto (%)" value={l.desconto} onChange={(e) => mudar(l.chave, "desconto", e.target.value)} inputMode="decimal" placeholder="% desc." />
                    <Button type="button" size="icon" variant="ghost" aria-label="Tirar serviço" onClick={() => setLinhas((ls) => ls.filter((x) => x.chave !== l.chave))}>
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                );
              })}
              <div className="flex items-center justify-between">
                <Button type="button" size="sm" variant="outline" onClick={addLinha}>
                  <Plus /> Adicionar serviço
                </Button>
                {linhas.length > 0 && (
                  <span className="flex items-center gap-2 text-sm">
                    <Label htmlFor="desc-geral" className="text-xs font-normal text-muted-foreground">Desconto geral</Label>
                    <Input id="desc-geral" className="h-8 w-16" value={f.desconto} onChange={set("desconto")} inputMode="decimal" placeholder="%" />
                    <span className="font-semibold tabular-nums">Total {fmtMoeda(total)}</span>
                  </span>
                )}
              </div>
              {abaixo.length > 0 && (
                <p className="text-xs text-warning">
                  Abaixo do catálogo: {abaixo.map((l) => catalogo.get(l.produto)?.nome).join(", ")}. Pode salvar; fica registrado no relatório de descontos.
                </p>
              )}
              {problemas.length > 0 && <p className="text-xs text-destructive">{problemas[0]}</p>}
            </fieldset>
          )}

          {veValores && linhas.length === 0 && (
            <div className="space-y-1.5">
              <Label htmlFor="valor">Valor estimado (R$)</Label>
              <Input id="valor" value={f.valor} onChange={set("valor")} inputMode="decimal" placeholder="0,00" />
            </div>
          )}
          <div className="space-y-1.5">
            <Label htmlFor="parcelas">Parcelas</Label>
            <Input id="parcelas" type="number" min={1} max={60} value={f.parcelas} onChange={set("parcelas")} placeholder="Ex.: 4" />
          </div>
          <div className="space-y-1.5">
            <Label>Forma de pagamento</Label>
            <Select value={f.forma} onValueChange={(v) => setF((x) => ({ ...x, forma: v }))}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={SEM}>A definir</SelectItem>
                {formasPagamento.map((fp) => (
                  <SelectItem key={fp.valor} value={fp.valor}>
                    {fp.rotulo}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="contato">Contato</Label>
            <Input id="contato" value={f.contato_nome} onChange={set("contato_nome")} autoComplete="off" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="tel">Telefone / WhatsApp</Label>
            <Input id="tel" value={f.contato_telefone} onChange={set("contato_telefone")} inputMode="tel" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="mail">E-mail</Label>
            <Input id="mail" type="email" value={f.contato_email} onChange={set("contato_email")} />
          </div>
          <div className="space-y-1.5">
            <Label>Responsável</Label>
            <Select value={responsavel} onValueChange={setResponsavel}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {funil.usa_rodizio && <SelectItem value={RODIZIO}>Próximo do rodízio</SelectItem>}
                <SelectItem value={NINGUEM}>Sem responsável</SelectItem>
                {resp.data?.map((r) => (
                  <SelectItem key={r.user_id} value={r.user_id}>
                    {r.nome}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Origem</Label>
            <Select value={f.origem} onValueChange={(v) => setF((x) => ({ ...x, origem: v }))}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {origensNegocio
                  .filter((o) => o.valor !== "ganho_comercial")
                  .map((o) => (
                    <SelectItem key={o.valor} value={o.valor}>
                      {o.rotulo}
                    </SelectItem>
                  ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="prev">Previsão de fechamento</Label>
            <Input id="prev" type="date" value={f.previsao} onChange={set("previsao")} />
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="obs">Observação</Label>
            <Textarea id="obs" value={f.observacao} onChange={set("observacao")} rows={2} />
          </div>
          <DialogFooter className="sm:col-span-2">
            <Button type="button" variant="outline" onClick={onFechar}>
              Cancelar
            </Button>
            <Button type="submit" disabled={criar.isPending || !empresa || !empresa.cnpj || problemas.length > 0}>
              {criar.isPending && <Loader2 className="animate-spin" />} Criar negócio
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
