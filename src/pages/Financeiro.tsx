import { useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import {
  AlertTriangle,
  Banknote,
  CalendarClock,
  ChevronLeft,
  ChevronRight,
  CircleDollarSign,
  Download,
  FileUp,
  History,
  Loader2,
  MoreHorizontal,
  Plus,
  Search,
  Settings2,
  Sparkles,
  Wallet,
} from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { KpiCard } from "@/components/ui/kpi-card";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Textarea } from "@/components/ui/textarea";
import { EmpresaSelect, type EmpresaEscolhida } from "@/components/crm/EmpresaSelect";
import { useSessao } from "@/contexts/sessao";
import { useDebounce } from "@/hooks/useDebounce";
import {
  useBaixaCobranca,
  useCancelarCobranca,
  useCobrancaHistorico,
  useCobrancas,
  useFinResumo,
  useGerarMes,
  useImportarCobrancas,
  useSalvarCobranca,
  useSalvarRegraFin,
} from "@/hooks/api";
import { formasPagamento, situacaoCobranca } from "@/lib/status";
import type { Cobranca } from "@/lib/tipos";
import { baixarCsv, cn, dataDeIso, fmtCnpj, fmtData, fmtDataHora, fmtMoeda, hojeIso } from "@/lib/utils";

const FILTROS: { valor: string | null; rotulo: string }[] = [
  { valor: null, rotulo: "Todas" },
  { valor: "vencida", rotulo: "Vencidas" },
  { valor: "aberta", rotulo: "Em aberto" },
  { valor: "paga", rotulo: "Pagas" },
  { valor: "cancelada", rotulo: "Canceladas" },
];

const primeiroDia = (iso: string) => `${iso.slice(0, 7)}-01`;
const somaMes = (iso: string, n: number) => {
  const d = dataDeIso(primeiroDia(iso));
  d.setMonth(d.getMonth() + n);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-01`;
};
const nomeMes = (iso: string) => dataDeIso(iso).toLocaleDateString("pt-BR", { month: "long", year: "numeric" });
/** "1.234,56" ou "1234.56" → número. */
const numero = (v: unknown) => {
  const s = String(v ?? "").trim().replace(/[R$\s]/g, "");
  if (!s) return null;
  const n = s.includes(",") ? Number(s.replace(/\./g, "").replace(",", ".")) : Number(s);
  return Number.isFinite(n) ? n : null;
};
/** "10/01/2026" ou "2026-01-10" → ISO. */
const dataIso = (v: unknown) => {
  const s = String(v ?? "").trim();
  const br = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (br) return `${br[3]}-${br[2].padStart(2, "0")}-${br[1].padStart(2, "0")}`;
  return /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : null;
};

export default function Financeiro() {
  const { tem } = useSessao();
  const [mes, setMes] = useState(primeiroDia(hojeIso()));
  const [situacao, setSituacao] = useState<string | null>(null);
  const [texto, setTexto] = useState("");
  const busca = useDebounce(texto, 300);
  const resumo = useFinResumo(mes);
  const lista = useCobrancas(mes, situacao, busca);
  const gerar = useGerarMes();
  const [editar, setEditar] = useState<{ aberto: boolean; c: Cobranca | null }>({ aberto: false, c: null });
  const [receber, setReceber] = useState<Cobranca | null>(null);
  const [importar, setImportar] = useState(false);
  const [regras, setRegras] = useState(false);
  const r = resumo.data;

  function exportar() {
    baixarCsv(
      `cobrancas-${mes.slice(0, 7)}`,
      (lista.data ?? []).map((c) => ({
        numero: c.numero,
        cliente: c.cliente,
        cnpj: fmtCnpj(c.cnpj),
        descricao: c.descricao,
        competencia: c.competencia.slice(0, 7),
        vencimento: fmtData(c.vencimento),
        valor: String(c.valor).replace(".", ","),
        situacao: situacaoCobranca[c.situacao].rotulo,
        pago_em: fmtData(c.pago_em),
        valor_pago: c.valor_pago != null ? String(c.valor_pago).replace(".", ",") : "",
        forma: c.forma ?? "",
        nota_fiscal: c.nota_fiscal ?? "",
      })),
    );
  }

  return (
    <div className="mx-auto max-w-7xl space-y-5 p-4 sm:p-6">
      <Cabecalho
        titulo="Financeiro"
        descricao="Contas a receber por cliente. Cobrança vencida além da tolerância abre o card em Pós-venda → Inadimplentes, que bloqueia a Agenda; quitou, o card fecha sozinho."
        acoes={
          <>
            {tem("gestor") && (
              <Button variant="ghost" size="sm" onClick={() => setRegras(true)}>
                <Settings2 /> Regras
              </Button>
            )}
            <Button variant="outline" size="sm" onClick={() => setImportar(true)}>
              <FileUp /> Importar planilha
            </Button>
            <Button size="sm" onClick={() => setEditar({ aberto: true, c: null })}>
              <Plus /> Nova cobrança
            </Button>
          </>
        }
      />

      <div className="flex flex-wrap items-center gap-2">
        <div className="flex items-center rounded-md border bg-card">
          <Button variant="ghost" size="icon" aria-label="Mês anterior" onClick={() => setMes(somaMes(mes, -1))}>
            <ChevronLeft />
          </Button>
          <span className="min-w-[150px] text-center text-sm font-medium first-letter:uppercase">{nomeMes(mes)}</span>
          <Button variant="ghost" size="icon" aria-label="Próximo mês" onClick={() => setMes(somaMes(mes, 1))}>
            <ChevronRight />
          </Button>
        </div>
        {r && r.contratos_sem_cobranca > 0 && (
          <Button size="sm" variant="marca" onClick={() => gerar.mutate(mes)} disabled={gerar.isPending}>
            {gerar.isPending ? <Loader2 className="animate-spin" /> : <Sparkles />}
            Gerar {r.contratos_sem_cobranca} cobrança{r.contratos_sem_cobranca > 1 ? "s" : ""} dos contratos
          </Button>
        )}
      </div>

      {resumo.isError ? (
        <EstadoErro erro={resumo.error} onTentar={() => resumo.refetch()} />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <KpiCard titulo="Previsto no mês" valor={fmtMoeda(r?.previsto)} icone={CircleDollarSign} carregando={resumo.isLoading} />
          <KpiCard titulo="Recebido no mês" valor={fmtMoeda(r?.recebido)} detalhe={r ? `falta ${fmtMoeda(r.a_receber)}` : undefined} icone={Banknote} tom="success" carregando={resumo.isLoading} />
          <KpiCard
            titulo="Vencido (todos os meses)"
            valor={fmtMoeda(r?.vencido_total)}
            detalhe={r ? `${r.qtd_vencidas} cobrança${r.qtd_vencidas === 1 ? "" : "s"}` : undefined}
            icone={CalendarClock}
            tom="destructive"
            carregando={resumo.isLoading}
            onClick={() => setSituacao("vencida")}
          />
          <KpiCard
            titulo="Empresas inadimplentes"
            valor={r?.empresas_inadimplentes ?? 0}
            detalhe={r ? `atraso acima de ${r.tolerancia_dias} dia${r.tolerancia_dias === 1 ? "" : "s"}` : undefined}
            icone={AlertTriangle}
            tom="warning"
            carregando={resumo.isLoading}
          />
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative min-w-[220px] flex-1 sm:max-w-xs">
          <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
          <Input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Cliente, CNPJ, descrição ou NF" className="pl-8" aria-label="Buscar cobrança" />
        </div>
        <div className="flex flex-wrap gap-1.5" role="group" aria-label="Filtrar por situação">
          {FILTROS.map((f) => (
            <Button key={f.rotulo} size="sm" variant={situacao === f.valor ? "default" : "outline"} aria-pressed={situacao === f.valor} onClick={() => setSituacao(f.valor)}>
              {f.rotulo}
            </Button>
          ))}
        </div>
        <Button size="sm" variant="ghost" className="ml-auto" onClick={exportar} disabled={!lista.data?.length}>
          <Download /> Exportar
        </Button>
      </div>

      {lista.isError ? (
        <EstadoErro erro={lista.error} onTentar={() => lista.refetch()} />
      ) : lista.data && lista.data.length === 0 ? (
        <EstadoVazio
          icone={Wallet}
          titulo={situacao || busca ? "Nenhuma cobrança com esse filtro" : "Nenhuma cobrança neste mês"}
          texto={situacao || busca ? "Tente outro filtro." : "Gere as cobranças a partir dos contratos, importe a planilha atual ou lance uma cobrança avulsa."}
        />
      ) : (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Cliente</TableHead>
                <TableHead>Descrição</TableHead>
                <TableHead>Vencimento</TableHead>
                <TableHead className="text-right">Valor</TableHead>
                <TableHead>Situação</TableHead>
                <TableHead className="w-[150px] text-right">
                  <span className="sr-only">Ações</span>
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {lista.isLoading &&
                Array.from({ length: 6 }).map((_, i) => (
                  <TableRow key={i}>
                    {Array.from({ length: 6 }).map((__, j) => (
                      <TableCell key={j}>
                        <Skeleton className="h-4 w-full" />
                      </TableCell>
                    ))}
                  </TableRow>
                ))}
              {lista.data?.map((c) => (
                <Linha key={c.id} c={c} onReceber={() => setReceber(c)} onEditar={() => setEditar({ aberto: true, c })} />
              ))}
            </TableBody>
          </Table>
        </Card>
      )}

      <CobrancaDialog aberto={editar.aberto} c={editar.c} mes={mes} onFechar={() => setEditar({ aberto: false, c: null })} />
      <ReceberDialog c={receber} onFechar={() => setReceber(null)} />
      <ImportarDialog aberto={importar} onFechar={() => setImportar(false)} />
      <RegrasDialog aberto={regras} tolerancia={r?.tolerancia_dias ?? 5} onFechar={() => setRegras(false)} />
    </div>
  );
}

function Linha({ c, onReceber, onEditar }: { c: Cobranca; onReceber: () => void; onEditar: () => void }) {
  const baixa = useBaixaCobranca();
  const cancelar = useCancelarCobranca();
  const [historico, setHistorico] = useState(false);
  const [motivo, setMotivo] = useState<string | null>(null);
  const st = situacaoCobranca[c.situacao];
  const aberta = c.situacao === "aberta" || c.situacao === "vencida";
  return (
    <TableRow className={cn(c.situacao === "cancelada" && "opacity-60")}>
      <TableCell>
        {c.empresa_id ? (
          <Link to={`/clientes/${c.empresa_id}`} className="font-medium hover:underline">
            {c.cliente}
          </Link>
        ) : (
          <span className="font-medium">{c.cliente}</span>
        )}
        {c.cnpj && <span className="block text-xs text-muted-foreground">{fmtCnpj(c.cnpj)}</span>}
      </TableCell>
      <TableCell>
        <span className="block max-w-[280px] truncate text-sm">{c.descricao}</span>
        <span className="text-xs text-muted-foreground">
          {c.nota_fiscal && `NF ${c.nota_fiscal}`}
          {c.nota_fiscal && c.contrato_numero && " · "}
          {c.contrato_numero && (
            <Link to={`/contratos?contrato=${c.contrato_id}`} className="hover:underline">
              contrato #{c.contrato_numero}
            </Link>
          )}
        </span>
      </TableCell>
      <TableCell>
        <span className={cn("tabular-nums", c.situacao === "vencida" && "font-medium text-destructive")}>{fmtData(c.vencimento)}</span>
        {c.dias_atraso > 0 && <span className="block text-xs text-destructive">{c.dias_atraso} dia{c.dias_atraso === 1 ? "" : "s"} de atraso</span>}
        {c.encargos > 0 && (
          <span className="block text-xs text-muted-foreground" title="Cláusula 8ª: multa de 10% + juros de 1% ao mês, a partir de 30 dias de atraso">
            atualizado {fmtMoeda(Number(c.valor) + Number(c.encargos))}
          </span>
        )}
        {c.pago_em && <span className="block text-xs text-success">pago {fmtData(c.pago_em)}</span>}
      </TableCell>
      <TableCell className="text-right tabular-nums">
        {fmtMoeda(c.valor)}
        {c.valor_pago != null && c.valor_pago !== c.valor && <span className="block text-xs text-muted-foreground">recebido {fmtMoeda(c.valor_pago)}</span>}
      </TableCell>
      <TableCell>
        <Badge variant={st.badge}>{st.rotulo}</Badge>
      </TableCell>
      <TableCell className="text-right">
        <div className="flex items-center justify-end gap-1">
          {aberta && (
            <Button size="sm" variant={c.situacao === "vencida" ? "default" : "outline"} onClick={onReceber}>
              Receber
            </Button>
          )}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon" className="h-8 w-8" aria-label={`Ações da cobrança ${c.numero}`}>
                <MoreHorizontal />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              {c.situacao !== "cancelada" && <DropdownMenuItem onSelect={onEditar}>Editar</DropdownMenuItem>}
              {c.situacao === "paga" && <DropdownMenuItem onSelect={() => baixa.mutate({ id: c.id, pago_em: null })}>Desfazer pagamento</DropdownMenuItem>}
              {c.boleto && <DropdownMenuItem onSelect={() => navigator.clipboard?.writeText(c.boleto ?? "")}>Copiar boleto</DropdownMenuItem>}
              <DropdownMenuItem onSelect={() => setHistorico(true)}>
                <History className="h-4 w-4" /> Histórico
              </DropdownMenuItem>
              {aberta && (
                <>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem className="text-destructive focus:text-destructive" onSelect={() => setMotivo("")}>
                    Cancelar cobrança
                  </DropdownMenuItem>
                </>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
        <HistoricoDialog id={historico ? c.id : null} onFechar={() => setHistorico(false)} />
        <Dialog open={motivo !== null} onOpenChange={(v) => !v && setMotivo(null)}>
          <DialogContent className="max-w-md text-left">
            <DialogHeader>
              <DialogTitle>Cancelar cobrança #{c.numero}</DialogTitle>
              <DialogDescription>{c.cliente} · {fmtMoeda(c.valor)}</DialogDescription>
            </DialogHeader>
            <div className="space-y-1.5">
              <Label htmlFor={`cm-${c.id}`}>Motivo</Label>
              <Textarea id={`cm-${c.id}`} rows={2} value={motivo ?? ""} onChange={(e) => setMotivo(e.target.value)} placeholder="Ex.: lançada em duplicidade, renegociada" />
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setMotivo(null)}>
                Voltar
              </Button>
              <Button
                variant="destructive"
                disabled={!motivo?.trim() || cancelar.isPending}
                onClick={() => cancelar.mutateAsync({ id: c.id, motivo: motivo!.trim() }).then(() => setMotivo(null)).catch(() => null)}
              >
                Cancelar cobrança
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </TableCell>
    </TableRow>
  );
}

function ReceberDialog({ c, onFechar }: { c: Cobranca | null; onFechar: () => void }) {
  const baixa = useBaixaCobranca();
  const [f, setF] = useState({ data: hojeIso(), valor: "", forma: "" });
  const aberto = !!c;
  return (
    <Dialog
      open={aberto}
      onOpenChange={(v) => {
        if (!v) onFechar();
      }}
    >
      <DialogContent className="max-w-md" onOpenAutoFocus={() => c && setF({ data: hojeIso(), valor: String(c.valor).replace(".", ","), forma: c.forma ?? "" })}>
        <DialogHeader>
          <DialogTitle>Registrar pagamento</DialogTitle>
          <DialogDescription>
            {c?.cliente} · {c && fmtMoeda(c.valor)} · venc. {c && fmtData(c.vencimento)}
          </DialogDescription>
        </DialogHeader>
        <form
          className="grid gap-4 sm:grid-cols-2"
          onSubmit={(e) => {
            e.preventDefault();
            if (!c) return;
            baixa
              .mutateAsync({ id: c.id, pago_em: f.data, valor: numero(f.valor), forma: f.forma || null })
              .then(onFechar)
              .catch(() => null);
          }}
        >
          <div className="space-y-1.5">
            <Label htmlFor="rb-data">Pago em</Label>
            <Input id="rb-data" type="date" max={hojeIso()} value={f.data} onChange={(e) => setF((x) => ({ ...x, data: e.target.value }))} required />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="rb-valor">Valor recebido (R$)</Label>
            <Input id="rb-valor" inputMode="decimal" value={f.valor} onChange={(e) => setF((x) => ({ ...x, valor: e.target.value }))} />
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <Label>Forma</Label>
            <Select value={f.forma} onValueChange={(v) => setF((x) => ({ ...x, forma: v }))}>
              <SelectTrigger>
                <SelectValue placeholder="Escolha" />
              </SelectTrigger>
              <SelectContent>
                {formasPagamento.map((fp) => (
                  <SelectItem key={fp.valor} value={fp.valor}>
                    {fp.rotulo}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <DialogFooter className="sm:col-span-2">
            <Button type="button" variant="outline" onClick={onFechar}>
              Cancelar
            </Button>
            <Button type="submit" disabled={baixa.isPending || !f.data}>
              {baixa.isPending && <Loader2 className="animate-spin" />} Confirmar recebimento
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function CobrancaDialog({ aberto, c, mes, onFechar }: { aberto: boolean; c: Cobranca | null; mes: string; onFechar: () => void }) {
  const salvar = useSalvarCobranca();
  const [empresa, setEmpresa] = useState<EmpresaEscolhida | null>(null);
  const [semCadastro, setSemCadastro] = useState(false);
  const vazio = { cliente_nome: "", descricao: "", vencimento: "", valor: "", nota_fiscal: "", boleto: "", forma: "", observacao: "" };
  const [f, setF] = useState(vazio);
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF((x) => ({ ...x, [k]: e.target.value }));

  function preencher() {
    if (c) {
      setF({
        cliente_nome: "",
        descricao: c.descricao,
        vencimento: c.vencimento,
        valor: String(c.valor).replace(".", ","),
        nota_fiscal: c.nota_fiscal ?? "",
        boleto: c.boleto ?? "",
        forma: c.forma ?? "",
        observacao: c.observacao ?? "",
      });
    } else {
      setF({ ...vazio, vencimento: `${mes.slice(0, 7)}-10` });
      setEmpresa(null);
      setSemCadastro(false);
    }
  }

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-lg" onOpenAutoFocus={preencher}>
        <DialogHeader>
          <DialogTitle>{c ? `Cobrança #${c.numero}` : "Nova cobrança"}</DialogTitle>
          <DialogDescription>{c ? c.cliente : "Cobrança avulsa (exames, laudos, serviços fora de contrato)."}</DialogDescription>
        </DialogHeader>
        <form
          className="grid gap-4 sm:grid-cols-2"
          onSubmit={(e) => {
            e.preventDefault();
            const dados: Record<string, unknown> = {
              descricao: f.descricao,
              vencimento: f.vencimento,
              valor: numero(f.valor),
              nota_fiscal: f.nota_fiscal,
              boleto: f.boleto,
              forma: f.forma || null,
              observacao: f.observacao,
            };
            if (!c) {
              dados.empresa_id = semCadastro ? null : empresa?.id;
              dados.cliente_nome = semCadastro ? f.cliente_nome : null;
            }
            salvar.mutateAsync({ id: c?.id ?? null, dados }).then(onFechar).catch(() => null);
          }}
        >
          {!c && (
            <div className="space-y-1.5 sm:col-span-2">
              <div className="flex items-center justify-between">
                <Label htmlFor="cb-empresa">Cliente</Label>
                <button type="button" className="text-xs text-primary hover:underline" onClick={() => setSemCadastro((x) => !x)}>
                  {semCadastro ? "Buscar na base" : "Cliente sem cadastro"}
                </button>
              </div>
              {semCadastro ? <Input id="cb-empresa" value={f.cliente_nome} onChange={set("cliente_nome")} /> : <EmpresaSelect id="cb-empresa" valor={empresa} onChange={setEmpresa} />}
            </div>
          )}
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="cb-desc">Descrição</Label>
            <Input id="cb-desc" value={f.descricao} onChange={set("descricao")} placeholder="Ex.: Exames admissionais — setembro" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cb-venc">Vencimento</Label>
            <Input id="cb-venc" type="date" value={f.vencimento} onChange={set("vencimento")} required />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cb-valor">Valor (R$)</Label>
            <Input id="cb-valor" inputMode="decimal" value={f.valor} onChange={set("valor")} required />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cb-nf">Nota fiscal</Label>
            <Input id="cb-nf" value={f.nota_fiscal} onChange={set("nota_fiscal")} />
          </div>
          <div className="space-y-1.5">
            <Label>Forma prevista</Label>
            <Select value={f.forma} onValueChange={(v) => setF((x) => ({ ...x, forma: v }))}>
              <SelectTrigger>
                <SelectValue placeholder="—" />
              </SelectTrigger>
              <SelectContent>
                {formasPagamento.map((fp) => (
                  <SelectItem key={fp.valor} value={fp.valor}>
                    {fp.rotulo}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="cb-boleto">Boleto (linha digitável ou link)</Label>
            <Input id="cb-boleto" value={f.boleto} onChange={set("boleto")} />
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="cb-obs">Observação</Label>
            <Textarea id="cb-obs" rows={2} value={f.observacao} onChange={set("observacao")} />
          </div>
          <DialogFooter className="sm:col-span-2">
            <Button type="button" variant="outline" onClick={onFechar}>
              Cancelar
            </Button>
            <Button type="submit" disabled={salvar.isPending || !f.vencimento || !numero(f.valor) || (!c && (semCadastro ? f.cliente_nome.trim().length < 2 : !empresa))}>
              {salvar.isPending && <Loader2 className="animate-spin" />} Salvar
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

const COLUNAS = ["cnpj", "cliente", "descricao", "vencimento", "valor", "pago_em", "valor_pago", "nota_fiscal"] as const;

function ImportarDialog({ aberto, onFechar }: { aberto: boolean; onFechar: () => void }) {
  const importar = useImportarCobrancas();
  const ref = useRef<HTMLInputElement>(null);
  const [linhas, setLinhas] = useState<Record<string, unknown>[] | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [resultado, setResultado] = useState<{ importadas: number; erros: { linha: number; erro: string }[] } | null>(null);

  function ler(arquivo: File) {
    setResultado(null);
    const leitor = new FileReader();
    leitor.onload = () => {
      const txt = String(leitor.result ?? "").replace(/^﻿/, "");
      const brutas = txt.split(/\r?\n/).filter((l) => l.trim());
      if (brutas.length < 2) return setAviso("A planilha precisa de um cabeçalho e ao menos uma linha.");
      const sep = (brutas[0].match(/;/g)?.length ?? 0) >= (brutas[0].match(/,/g)?.length ?? 0) ? ";" : ",";
      const cab = brutas[0].split(sep).map((c) => c.trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/\s+/g, "_"));
      const faltam = ["vencimento", "valor"].filter((c) => !cab.includes(c));
      if (faltam.length) return setAviso(`Faltam as colunas: ${faltam.join(", ")}.`);
      if (!cab.includes("cnpj") && !cab.includes("cliente")) return setAviso("A planilha precisa da coluna cnpj ou cliente.");
      const out = brutas.slice(1).map((l) => {
        const v = l.split(sep).map((x) => x.trim().replace(/^"|"$/g, ""));
        const o: Record<string, unknown> = {};
        cab.forEach((c, i) => {
          if ((COLUNAS as readonly string[]).includes(c)) o[c] = v[i] ?? "";
        });
        o.vencimento = dataIso(o.vencimento);
        o.pago_em = dataIso(o.pago_em);
        o.valor = numero(o.valor);
        o.valor_pago = numero(o.valor_pago);
        return o;
      });
      const invalidas = out.filter((o) => !o.vencimento || !o.valor).length;
      setAviso(invalidas ? `${invalidas} linha(s) sem vencimento ou valor válidos serão recusadas.` : null);
      setLinhas(out);
    };
    leitor.readAsText(arquivo, "utf-8");
  }

  const previa = useMemo(() => linhas?.slice(0, 5) ?? [], [linhas]);

  return (
    <Dialog
      open={aberto}
      onOpenChange={(v) => {
        if (!v) {
          onFechar();
          setLinhas(null);
          setAviso(null);
          setResultado(null);
        }
      }}
    >
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Importar planilha de contas a receber</DialogTitle>
          <DialogDescription>
            CSV (separado por ; ou ,) com as colunas <code>cnpj</code> ou <code>cliente</code>, <code>vencimento</code>, <code>valor</code> e, se tiver, <code>descricao</code>, <code>pago_em</code>,{" "}
            <code>valor_pago</code>, <code>nota_fiscal</code>. Datas em dd/mm/aaaa. O CNPJ liga a cobrança ao cliente da base.
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-wrap items-center gap-2">
          <input ref={ref} type="file" accept=".csv,text/csv" className="hidden" onChange={(e) => e.target.files?.[0] && ler(e.target.files[0])} />
          <Button variant="outline" onClick={() => ref.current?.click()}>
            <FileUp /> Escolher arquivo
          </Button>
          <Button
            variant="ghost"
            onClick={() =>
              baixarCsv("modelo-contas-a-receber", [
                { cnpj: "31.508.294/0001-90", cliente: "", descricao: "Exames periódicos — setembro", vencimento: "10/10/2026", valor: "1.250,00", pago_em: "", valor_pago: "", nota_fiscal: "1234" },
              ])
            }
          >
            <Download /> Baixar modelo
          </Button>
          {linhas && <span className="text-sm text-muted-foreground">{linhas.length} linha(s) lidas</span>}
        </div>
        {aviso && (
          <p className="flex items-start gap-2 rounded-md border border-warning/40 bg-warning/5 p-2.5 text-sm">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" aria-hidden /> {aviso}
          </p>
        )}
        {previa.length > 0 && !resultado && (
          <div className="overflow-x-auto rounded-md border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>CNPJ / cliente</TableHead>
                  <TableHead>Descrição</TableHead>
                  <TableHead>Vencimento</TableHead>
                  <TableHead className="text-right">Valor</TableHead>
                  <TableHead>Pago em</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {previa.map((l, i) => (
                  <TableRow key={i}>
                    <TableCell className="text-xs">{String(l.cnpj || l.cliente || "—")}</TableCell>
                    <TableCell className="text-xs">{String(l.descricao ?? "")}</TableCell>
                    <TableCell className="text-xs">{l.vencimento ? fmtData(String(l.vencimento)) : <span className="text-destructive">inválido</span>}</TableCell>
                    <TableCell className="text-right text-xs">{l.valor ? fmtMoeda(Number(l.valor)) : <span className="text-destructive">inválido</span>}</TableCell>
                    <TableCell className="text-xs">{l.pago_em ? fmtData(String(l.pago_em)) : "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
        {resultado && (
          <div className="space-y-2 text-sm">
            <p className="font-medium text-success">{resultado.importadas} cobrança(s) importada(s).</p>
            {resultado.erros.length > 0 && (
              <div className="max-h-40 overflow-y-auto rounded-md border border-destructive/40 p-2">
                <p className="mb-1 font-medium text-destructive">{resultado.erros.length} linha(s) recusada(s):</p>
                <ul className="space-y-0.5 text-xs">
                  {resultado.erros.map((e) => (
                    <li key={e.linha}>
                      Linha {e.linha + 1}: {e.erro}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}
        <DialogFooter>
          <Button variant="outline" onClick={onFechar}>
            Fechar
          </Button>
          {!resultado && (
            <Button disabled={!linhas?.length || importar.isPending} onClick={() => linhas && importar.mutateAsync(linhas).then(setResultado).catch(() => null)}>
              {importar.isPending && <Loader2 className="animate-spin" />} Importar {linhas?.length ?? 0} linha(s)
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function RegrasDialog({ aberto, tolerancia, onFechar }: { aberto: boolean; tolerancia: number; onFechar: () => void }) {
  const salvar = useSalvarRegraFin();
  const [v, setV] = useState(String(tolerancia));
  return (
    <Dialog open={aberto} onOpenChange={(x) => !x && onFechar()}>
      <DialogContent className="max-w-md" onOpenAutoFocus={() => setV(String(tolerancia))}>
        <DialogHeader>
          <DialogTitle>Regra de inadimplência</DialogTitle>
          <DialogDescription>Depois de quantos dias de atraso a empresa vira inadimplente (card em Pós-venda e bloqueio na Agenda).</DialogDescription>
        </DialogHeader>
        <div className="space-y-1.5">
          <Label htmlFor="rg-tol">Tolerância (dias)</Label>
          <Input id="rg-tol" type="number" min={0} max={90} value={v} onChange={(e) => setV(e.target.value)} />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onFechar}>
            Cancelar
          </Button>
          <Button disabled={salvar.isPending || v === ""} onClick={() => salvar.mutateAsync(Number(v)).then(onFechar).catch(() => null)}>
            Salvar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function HistoricoDialog({ id, onFechar }: { id: string | null; onFechar: () => void }) {
  const q = useCobrancaHistorico(id);
  return (
    <Dialog open={!!id} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-md text-left">
        <DialogHeader>
          <DialogTitle>Histórico da cobrança</DialogTitle>
          <DialogDescription className="sr-only">Eventos da cobrança</DialogDescription>
        </DialogHeader>
        {q.isLoading ? (
          <Skeleton className="h-20 w-full" />
        ) : q.isError ? (
          <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
        ) : (
          <ol className="space-y-3">
            {q.data?.map((e, i) => (
              <li key={i} className="border-l-2 border-primary/30 pl-3">
                <p className="text-sm">{e.texto}</p>
                <p className="text-xs text-muted-foreground">
                  {e.autor} · {fmtDataHora(e.criado_em)}
                </p>
              </li>
            ))}
          </ol>
        )}
      </DialogContent>
    </Dialog>
  );
}
