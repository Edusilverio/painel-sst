import { useMemo, useState } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { Building2, Download, Receipt, ShoppingBag, TrendingUp } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EstadoErro } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { KpiCard } from "@/components/ui/kpi-card";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useRelatorioDescontos, useResponsaveis } from "@/hooks/api";
import { useSessao } from "@/contexts/sessao";
import { rpc } from "@/lib/supabase";
import { baixarCsv, fmtMoeda, fmtNumero } from "@/lib/utils";

const TODOS = "__todos__";

interface Produto {
  produto: string;
  negocios: number;
  quantidade: number;
  valor: number;
  preco_medio: number | null;
  preco_min: number;
  preco_max: number;
}
interface Relatorio {
  de: string;
  ate: string;
  negocios: number;
  valor_negocios: number;
  valor_itens: number;
  clientes: number;
  sem_itens: number;
  produtos: Produto[];
  meses: { mes: string; negocios: number; valor: number }[];
  responsaveis: { nome: string; negocios: number; valor: number }[];
}

const hoje = () => new Date().toISOString().slice(0, 10);
const haUmAno = () => {
  const d = new Date();
  d.setFullYear(d.getFullYear() - 1);
  return d.toISOString().slice(0, 10);
};
const nomeMes = (m: string) => {
  const [a, mm] = m.split("-");
  return new Date(Number(a), Number(mm) - 1, 1).toLocaleDateString("pt-BR", { month: "short", year: "2-digit" });
};
type Ordem = "valor" | "quantidade" | "negocios" | "preco_medio";

export default function RelatorioVendas() {
  const { tem } = useSessao();
  const gestor = tem("financeiro"); // 0074: vê todos os responsáveis (admin e financeiro)
  const [de, setDe] = useState(haUmAno());
  const [ate, setAte] = useState(hoje());
  const [resp, setResp] = useState(TODOS);
  const [ordem, setOrdem] = useState<Ordem>("valor");
  const responsaveis = useResponsaveis();
  const q = useQuery({
    queryKey: ["relatorio-vendas", de, ate, resp],
    queryFn: () => rpc<Relatorio>("painel_relatorio_vendas", { p_de: de || null, p_ate: ate || null, p_responsavel: resp === TODOS ? null : resp }),
    placeholderData: keepPreviousData,
  });
  const r = q.data;
  const produtos = useMemo(() => [...(r?.produtos ?? [])].sort((a, b) => (b[ordem] ?? 0) - (a[ordem] ?? 0)), [r, ordem]);
  const maxMes = Math.max(1, ...(r?.meses ?? []).map((m) => m.valor));

  return (
    <div className="mx-auto max-w-7xl space-y-5 p-4 sm:p-6">
      <Cabecalho
        titulo="Relatório de vendas"
        descricao="Negócios ganhos no funil Comercial (inclui o histórico do Bitrix), pela data de fechamento. Produtos e serviços vendidos, quantidades e preços praticados."
        acoes={
          <Button
            size="sm"
            variant="outline"
            disabled={!produtos.length}
            onClick={() =>
              baixarCsv(
                `vendas-produtos-${de}-a-${ate}`,
                produtos.map((p) => ({
                  produto: p.produto,
                  negocios: p.negocios,
                  quantidade: p.quantidade,
                  valor_total: p.valor,
                  preco_medio: p.preco_medio ?? "",
                  preco_minimo: p.preco_min,
                  preco_maximo: p.preco_max,
                })),
              )
            }
          >
            <Download /> Exportar produtos
          </Button>
        }
      />

      <Card className="grid gap-3 p-4 sm:grid-cols-[10rem_10rem_1fr]">
        <div className="space-y-1.5">
          <Label htmlFor="rv-de">De</Label>
          <Input id="rv-de" type="date" value={de} onChange={(e) => setDe(e.target.value)} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="rv-ate">Até</Label>
          <Input id="rv-ate" type="date" value={ate} onChange={(e) => setAte(e.target.value)} />
        </div>
        {gestor && (
          <div className="space-y-1.5">
            <Label>Responsável</Label>
            <Select value={resp} onValueChange={setResp}>
              <SelectTrigger className="sm:max-w-xs">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={TODOS}>Todos</SelectItem>
                {responsaveis.data?.map((p) => (
                  <SelectItem key={p.user_id} value={p.user_id}>
                    {p.nome}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        )}
      </Card>

      {q.isError ? (
        <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
      ) : (
        <>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <KpiCard titulo="Negócios ganhos" valor={fmtNumero(r?.negocios ?? 0)} icone={TrendingUp} carregando={q.isLoading} />
            <KpiCard titulo="Valor vendido" valor={fmtMoeda(r?.valor_negocios ?? 0)} icone={Receipt} tom="success" carregando={q.isLoading} />
            <KpiCard
              titulo="Ticket médio"
              valor={fmtMoeda(r && r.negocios ? r.valor_negocios / r.negocios : 0)}
              icone={ShoppingBag}
              tom="info"
              carregando={q.isLoading}
            />
            <KpiCard titulo="Clientes" valor={fmtNumero(r?.clientes ?? 0)} detalhe={r?.sem_itens ? `${r.sem_itens} negócios sem itens` : undefined} icone={Building2} carregando={q.isLoading} />
          </div>

          <div className="grid gap-5 lg:grid-cols-[1fr_20rem]">
            <Card>
              <CardHeader className="flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-base">Produtos e serviços</CardTitle>
                <Select value={ordem} onValueChange={(v) => setOrdem(v as Ordem)}>
                  <SelectTrigger className="h-8 w-44" aria-label="Ordenar por">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="valor">Maior valor</SelectItem>
                    <SelectItem value="quantidade">Mais vendidos</SelectItem>
                    <SelectItem value="negocios">Em mais negócios</SelectItem>
                    <SelectItem value="preco_medio">Maior preço médio</SelectItem>
                  </SelectContent>
                </Select>
              </CardHeader>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Produto / serviço</TableHead>
                    <TableHead className="text-right">Qtd.</TableHead>
                    <TableHead className="text-right">Valor total</TableHead>
                    <TableHead className="hidden text-right md:table-cell">Preço médio</TableHead>
                    <TableHead className="hidden text-right lg:table-cell">Mín. – máx.</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {q.isLoading &&
                    Array.from({ length: 8 }).map((_, i) => (
                      <TableRow key={i}>
                        <TableCell colSpan={5}>
                          <Skeleton className="h-5 w-full" />
                        </TableCell>
                      </TableRow>
                    ))}
                  {produtos.map((p) => (
                    <TableRow key={p.produto}>
                      <TableCell>
                        <p className="text-sm font-medium">{p.produto}</p>
                        <p className="text-xs text-muted-foreground">
                          {p.negocios} negócio{p.negocios === 1 ? "" : "s"}
                        </p>
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{fmtNumero(p.quantidade)}</TableCell>
                      <TableCell className="text-right tabular-nums">{fmtMoeda(p.valor)}</TableCell>
                      <TableCell className="hidden text-right tabular-nums md:table-cell">{fmtMoeda(p.preco_medio)}</TableCell>
                      <TableCell className="hidden text-right text-xs tabular-nums text-muted-foreground lg:table-cell">
                        {fmtMoeda(p.preco_min)} – {fmtMoeda(p.preco_max)}
                      </TableCell>
                    </TableRow>
                  ))}
                  {!q.isLoading && produtos.length === 0 && (
                    <TableRow>
                      <TableCell colSpan={5} className="py-6 text-center text-sm text-muted-foreground">
                        Nenhuma venda no período.
                      </TableCell>
                    </TableRow>
                  )}
                </TableBody>
              </Table>
            </Card>

            <div className="space-y-5">
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base">Por mês</CardTitle>
                </CardHeader>
                <CardContent className="space-y-1.5">
                  {(r?.meses ?? []).map((m) => (
                    <div key={m.mes} className="grid grid-cols-[3.5rem_1fr_6.5rem] items-center gap-2 text-sm">
                      <span className="text-muted-foreground">{nomeMes(m.mes)}</span>
                      <div className="h-2 rounded bg-muted" title={`${m.negocios} negócios`}>
                        <div className="h-2 rounded bg-primary" style={{ width: `${(m.valor / maxMes) * 100}%` }} />
                      </div>
                      <span className="text-right tabular-nums">{fmtMoeda(m.valor)}</span>
                    </div>
                  ))}
                  {!q.isLoading && !r?.meses.length && <p className="text-sm text-muted-foreground">Sem vendas.</p>}
                </CardContent>
              </Card>
              {gestor && (
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Por responsável</CardTitle>
                  </CardHeader>
                  <CardContent className="space-y-1.5">
                    {(r?.responsaveis ?? []).map((p) => (
                      <div key={p.nome} className="flex items-center justify-between gap-2 text-sm">
                        <span className="truncate">
                          {p.nome} <span className="text-xs text-muted-foreground">· {p.negocios}</span>
                        </span>
                        <span className="tabular-nums">{fmtMoeda(p.valor)}</span>
                      </div>
                    ))}
                  </CardContent>
                </Card>
              )}
            </div>
          </div>
        </>
      )}
      {gestor && <Descontos de={de} ate={ate} />}
    </div>
  );
}

/** 0081 (Renata, 20/10): vendas abaixo do preço do catálogo, por vendedor ("devia ser 500, vendeu a 450"). */
function Descontos({ de, ate }: { de: string; ate: string }) {
  const q = useRelatorioDescontos(de, ate);
  const linhas = q.data ?? [];
  const porVendedor = useMemo(() => {
    const m = new Map<string, { vendedor: string; itens: number; diferenca: number }>();
    for (const l of linhas) {
      const k = l.vendedor ?? "Sem responsável";
      const x = m.get(k) ?? { vendedor: k, itens: 0, diferenca: 0 };
      x.itens += 1;
      x.diferenca += Number(l.diferenca) || 0;
      m.set(k, x);
    }
    return [...m.values()].sort((a, b) => b.diferenca - a.diferenca);
  }, [linhas]);
  const pct = (v: number) => `${String(Number(v) || 0).replace(".", ",")}%`;

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0">
        <CardTitle className="text-base">Vendas abaixo do catálogo</CardTitle>
        <Button
          size="sm"
          variant="outline"
          disabled={!linhas.length}
          onClick={() =>
            baixarCsv(
              `descontos-${de}-a-${ate}`,
              linhas.map((l) => ({
                negocio: l.numero,
                data: l.data,
                cliente: l.cliente ?? "",
                vendedor: l.vendedor ?? "",
                etapa: l.etapa,
                servico: l.servico,
                quantidade: l.quantidade,
                preco_catalogo: l.preco_catalogo,
                preco_praticado: l.preco_praticado,
                desconto_item_pct: l.desconto_item,
                desconto_geral_pct: l.desconto_geral,
                total_catalogo: l.total_catalogo,
                total_final: l.total_final,
                diferenca: l.diferenca,
              })),
            )
          }
        >
          <Download /> Exportar
        </Button>
      </CardHeader>
      <CardContent className="space-y-4">
        <p className="text-xs text-muted-foreground">
          Itens do Comercial criados no período com valor final abaixo do preço do catálogo (preço digitado menor e/ou desconto por item e geral). Vale a partir de 20/10/2026.
        </p>
        {q.isLoading ? (
          <Skeleton className="h-24 w-full" />
        ) : q.isError ? (
          <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
        ) : linhas.length === 0 ? (
          <p className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">Nenhuma venda abaixo do catálogo no período.</p>
        ) : (
          <>
            <div className="flex flex-wrap gap-2">
              {porVendedor.map((v) => (
                <span key={v.vendedor} className="rounded-md border px-2.5 py-1 text-xs">
                  <span className="font-medium">{v.vendedor}</span> · {v.itens} {v.itens === 1 ? "item" : "itens"} · {fmtMoeda(v.diferenca)} abaixo
                </span>
              ))}
            </div>
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Negócio</TableHead>
                    <TableHead>Vendedor</TableHead>
                    <TableHead>Serviço</TableHead>
                    <TableHead className="text-right">Catálogo</TableHead>
                    <TableHead className="text-right">Praticado</TableHead>
                    <TableHead className="text-right">Desc.</TableHead>
                    <TableHead className="text-right">Final</TableHead>
                    <TableHead className="text-right">Diferença</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {linhas.map((l, i) => (
                    <TableRow key={`${l.negocio_id}-${i}`}>
                      <TableCell className="whitespace-nowrap">
                        #{l.numero} <span className="text-xs text-muted-foreground">· {l.cliente ?? "—"}</span>
                      </TableCell>
                      <TableCell>{l.vendedor ?? "—"}</TableCell>
                      <TableCell>
                        {l.servico} {Number(l.quantidade) !== 1 && <span className="text-xs text-muted-foreground">× {String(l.quantidade).replace(".", ",")}</span>}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{fmtMoeda(l.preco_catalogo)}</TableCell>
                      <TableCell className="text-right tabular-nums">{fmtMoeda(l.preco_praticado)}</TableCell>
                      <TableCell className="whitespace-nowrap text-right tabular-nums text-xs">
                        {Number(l.desconto_item) ? pct(l.desconto_item) : "—"}
                        {Number(l.desconto_geral) ? ` + ${pct(l.desconto_geral)}` : ""}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{fmtMoeda(l.total_final)}</TableCell>
                      <TableCell className="text-right font-medium tabular-nums text-warning">{fmtMoeda(l.diferenca)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}
