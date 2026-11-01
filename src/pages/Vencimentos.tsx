import { useState } from "react";
import { useSearchParams } from "react-router-dom";
import { ClipboardCheck, Download, Loader2, Search, X } from "lucide-react";
import { toast } from "sonner";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Paginacao } from "@/components/ui/paginacao";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { EmpresaSelect, type EmpresaEscolhida } from "@/components/crm/EmpresaSelect";
import { useVencimentos } from "@/hooks/api";
import { useQuery } from "@tanstack/react-query";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useDebounce } from "@/hooks/useDebounce";
import { rpc } from "@/lib/supabase";
import { statusVencimento } from "@/lib/status";
import type { VencimentoLinha } from "@/lib/tipos";
import { baixarCsv, fmtData } from "@/lib/utils";

const POR_PAGINA = 100;

export default function Vencimentos() {
  const [params] = useSearchParams();
  const [status, setStatus] = useState<string>(params.get("status") ?? "vencido");
  const [empresa, setEmpresa] = useState<EmpresaEscolhida | null>(params.get("empresa") ? { id: params.get("empresa")!, nome: "Empresa selecionada", cnpj: null } : null);
  const [texto, setTexto] = useState("");
  const busca = useDebounce(texto.trim());
  const [pagina, setPagina] = useState(0);
  const [exportando, setExportando] = useState(false);
  const [aberto, setAberto] = useState<string | null>(null);
  const filtro = { empresa: empresa?.id ?? null, status: status === "todos" ? null : status, busca, pagina };
  const q = useVencimentos(filtro, POR_PAGINA);
  const total = q.data?.[0]?.total ?? 0;
  const nomeEmpresa = empresa && empresa.nome !== "Empresa selecionada" ? empresa.nome : q.data?.[0]?.empresa;

  async function exportar() {
    setExportando(true);
    try {
      const linhas: VencimentoLinha[] = [];
      for (let off = 0; off < Math.max(total, 1); off += 1000) {
        const parte = await rpc<VencimentoLinha[]>("painel_vencimentos", { p_empresa: filtro.empresa, p_status: filtro.status, p_busca: busca || null, p_limite: 1000, p_offset: off });
        linhas.push(...parte);
        if (parte.length < 1000) break;
      }
      baixarCsv(
        `vencimentos-${nomeEmpresa ?? "todas-empresas"}-${new Date().toISOString().slice(0, 10)}`,
        linhas.map((l) => ({
          Empresa: l.empresa,
          Unidade: l.unidade,
          Setor: l.setor,
          Função: l.funcao,
          Colaborador: l.colaborador,
          CPF: l.cpf,
          "Matrícula eSocial": l.matricula_esocial,
          "Próximo exame": fmtData(l.proximo_exame),
          "Dias para vencer": l.dias_para_vencer,
          Situação: statusVencimento(l.status).rotulo,
          "Exames vencidos": l.exames_vencidos,
          "Exames nunca feitos": l.exames_nunca_feitos,
        })),
      );
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível exportar.");
    } finally {
      setExportando(false);
    }
  }

  return (
    <div className="mx-auto max-w-7xl space-y-5 p-4 sm:p-6">
      <Cabecalho
        titulo="Vencimento de exames"
        descricao="Colaboradores ativos das empresas ativas, pela periodicidade do PCMSO de cada função (ex.: cozinha 6 meses, obra 12 meses). Um colaborador por linha, com o exame que vence primeiro — clique para ver todos os exames. Recalculado todo dia às 07:50."
        acoes={
          <Button variant="outline" onClick={exportar} disabled={exportando || total === 0}>
            {exportando ? <Loader2 className="animate-spin" /> : <Download />} Exportar para o RH (Excel)
          </Button>
        }
      />
      <div className="grid gap-2 lg:grid-cols-[1fr_20rem_auto]">
        <div className="relative">
          <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
          <Input className="pl-8" placeholder="Colaborador, CPF ou empresa…" value={texto} onChange={(e) => { setTexto(e.target.value); setPagina(0); }} aria-label="Buscar" />
        </div>
        {empresa ? (
          <div className="flex items-center gap-2 rounded-md border bg-muted/40 px-3 text-sm">
            <span className="flex-1 truncate">{nomeEmpresa ?? "Empresa selecionada"}</span>
            <button type="button" onClick={() => { setEmpresa(null); setPagina(0); }} aria-label="Limpar empresa" className="rounded p-0.5 hover:bg-accent">
              <X className="h-4 w-4" />
            </button>
          </div>
        ) : (
          <EmpresaSelect valor={null} onChange={(e) => { setEmpresa(e); setPagina(0); }} />
        )}
        <Tabs value={status} onValueChange={(v) => { setStatus(v); setPagina(0); }}>
          <TabsList className="flex-wrap">
            <TabsTrigger value="vencido">Vencidos</TabsTrigger>
            <TabsTrigger value="vence_em_30_dias">30 dias</TabsTrigger>
            <TabsTrigger value="vence_em_60_dias">60 dias</TabsTrigger>
            <TabsTrigger value="todos">Todos</TabsTrigger>
          </TabsList>
        </Tabs>
      </div>

      {q.isError ? (
        <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
      ) : q.data && q.data.length === 0 ? (
        <EstadoVazio
          icone={ClipboardCheck}
          titulo={status === "todos" && !busca && !empresa ? "Em preparação" : "Nada para mostrar com estes filtros"}
          texto={
            status === "todos" && !busca && !empresa
              ? "O cálculo de vencimentos depende dos exames e da periodicidade de cada função no PCMSO, que estão sendo carregados do SESMO. Esta lista passa a funcionar assim que a carga terminar."
              : "Se a aba “Todos” também estiver vazia, o cálculo ainda está em preparação: faltam os exames e a periodicidade do PCMSO, que estão sendo carregados do SESMO."
          }
        />
      ) : (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead className="hidden md:table-cell">Empresa / função</TableHead>
                <TableHead>Próximo exame</TableHead>
                <TableHead>Situação</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {q.isLoading &&
                Array.from({ length: 8 }).map((_, i) => (
                  <TableRow key={i}>
                    <TableCell colSpan={4}>
                      <Skeleton className="h-5 w-full" />
                    </TableCell>
                  </TableRow>
                ))}
              {q.data?.map((l) => {
                const s = statusVencimento(l.status);
                return (
                  <TableRow key={l.colaborador_id} className="cursor-pointer" onClick={() => setAberto(l.colaborador_id)}>
                    <TableCell>
                      <p className="font-medium">{l.colaborador}</p>
                      <p className="text-xs text-muted-foreground">
                        {l.cpf ?? "sem CPF"} {l.matricula_esocial && `· matr. ${l.matricula_esocial}`}
                      </p>
                    </TableCell>
                    <TableCell className="hidden md:table-cell">
                      <p>{l.empresa}</p>
                      <p className="text-xs text-muted-foreground">{[l.unidade, l.setor, l.funcao].filter(Boolean).join(" › ")}</p>
                    </TableCell>
                    <TableCell className="whitespace-nowrap">
                      {l.proximo_exame ? fmtData(l.proximo_exame) : <span className="text-muted-foreground">nunca feito</span>}
                      {l.dias_para_vencer != null && (
                        <p className="text-xs text-muted-foreground">{l.dias_para_vencer < 0 ? `vencido há ${-l.dias_para_vencer} dias` : `em ${l.dias_para_vencer} dias`}</p>
                      )}
                    </TableCell>
                    <TableCell>
                      <Badge variant={s.badge}>{s.rotulo}</Badge>
                      {l.exames_vencidos + l.exames_nunca_feitos > 1 && (
                        <p className="mt-1 text-xs text-muted-foreground">{l.exames_vencidos + l.exames_nunca_feitos} exames pendentes</p>
                      )}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </Card>
      )}
      <Paginacao pagina={pagina} porPagina={POR_PAGINA} total={total} onMudar={setPagina} />
      <DetalheVencimento id={aberto} onFechar={() => setAberto(null)} />
    </div>
  );
}

interface Detalhe {
  colaborador: string;
  cpf: string | null;
  empresa: string;
  unidade: string | null;
  setor: string | null;
  funcao: string | null;
  status: string;
  ultimo_aso: string | null;
  tem_pcmso: boolean;
  calculado_em: string;
  exames: { exame: string; periodicidade: string | null; meses: number; ultima: string | null; origem: "exame" | "aso" | null; proxima: string | null; status: string }[];
}

const rotuloExame = (st: string) => (st === "nunca_realizado" ? { rotulo: "Sem registro", badge: "destructive" as const } : statusVencimento(st));

function DetalheVencimento({ id, onFechar }: { id: string | null; onFechar: () => void }) {
  const q = useQuery({ queryKey: ["vencimento", id], queryFn: () => rpc<Detalhe>("painel_vencimento_detalhe", { p_colaborador: id }), enabled: !!id });
  const d = q.data;
  return (
    <Dialog open={!!id} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-h-[92vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{d?.colaborador ?? "Exames do colaborador"}</DialogTitle>
          <DialogDescription>
            {d ? `${d.empresa} · ${[d.setor, d.funcao].filter(Boolean).join(" / ") || "função não informada"}` : ""}
          </DialogDescription>
        </DialogHeader>
        {q.isError ? (
          <EstadoErro erro={q.error} />
        ) : !d ? (
          <Skeleton className="h-40 w-full" />
        ) : (
          <div className="space-y-3">
            <div className="flex flex-wrap gap-x-6 gap-y-1 text-sm">
              <span>
                Último ASO: <strong>{d.ultimo_aso ? fmtData(d.ultimo_aso) : "nenhum no histórico"}</strong>
              </span>
              {!d.tem_pcmso && <span className="text-warning">Função sem PCMSO no SESMO — usando Exame Clínico a cada 12 meses</span>}
            </div>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Exame</TableHead>
                  <TableHead>Periodicidade</TableHead>
                  <TableHead>Último</TableHead>
                  <TableHead>Próximo</TableHead>
                  <TableHead>Situação</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {d.exames.map((e) => {
                  const st = rotuloExame(e.status);
                  return (
                    <TableRow key={e.exame}>
                      <TableCell className="font-medium">{e.exame}</TableCell>
                      <TableCell className="text-sm">{e.periodicidade ?? `${e.meses} meses`}</TableCell>
                      <TableCell className="whitespace-nowrap text-sm">
                        {e.ultima ? fmtData(e.ultima) : "—"}
                        {e.origem === "aso" && <p className="text-[11px] text-muted-foreground">data do ASO</p>}
                      </TableCell>
                      <TableCell className="whitespace-nowrap text-sm">{e.proxima ? fmtData(e.proxima) : "—"}</TableCell>
                      <TableCell>
                        <Badge variant={st.badge}>{st.rotulo}</Badge>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
            <p className="text-xs text-muted-foreground">
              "Data do ASO": o exame complementar ainda não tem a data própria carregada, então vale a data do último ASO. Periodicidade "6/12": 6 meses depois da admissão, depois a cada 12.
            </p>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
