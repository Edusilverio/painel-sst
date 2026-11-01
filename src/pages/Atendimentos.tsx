import { useState } from "react";
import { Download, Loader2, Search, Stethoscope, X } from "lucide-react";
import { toast } from "sonner";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Paginacao } from "@/components/ui/paginacao";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { EmpresaSelect, type EmpresaEscolhida } from "@/components/crm/EmpresaSelect";
import { AtendimentoDialog } from "@/components/dados/Dialogos";
import { useAtendimentos } from "@/hooks/api";
import { useDebounce } from "@/hooks/useDebounce";
import { rpc } from "@/lib/supabase";
import { situacaoAtendimento, tipoExame } from "@/lib/status";
import type { AtendimentoLinha } from "@/lib/tipos";
import { baixarCsv, fmtDataHora } from "@/lib/utils";

const POR_PAGINA = 100;
const TODAS = "__todas__";
const SITUACOES = ["agendado", "aguardando", "atendido", "finalizado", "cancelado", "faltou"];

function inicioDoAno() {
  return `${new Date().getFullYear()}-01-01`;
}

export default function Atendimentos() {
  const [empresa, setEmpresa] = useState<EmpresaEscolhida | null>(null);
  const [de, setDe] = useState(inicioDoAno());
  const [ate, setAte] = useState("");
  const [situacao, setSituacao] = useState(TODAS);
  const [texto, setTexto] = useState("");
  const busca = useDebounce(texto.trim());
  const [pagina, setPagina] = useState(0);
  const [exportando, setExportando] = useState(false);
  const [aberto, setAberto] = useState<string | null>(null);
  const filtro = { empresa: empresa?.id ?? null, de: de || null, ate: ate || null, situacao: situacao === TODAS ? null : situacao, busca, pagina };
  const q = useAtendimentos(filtro, POR_PAGINA);
  const total = q.data?.[0]?.total ?? 0;
  const reset = () => setPagina(0);

  async function exportar() {
    setExportando(true);
    try {
      const linhas: AtendimentoLinha[] = [];
      for (let off = 0; off < Math.max(total, 1); off += 1000) {
        const parte = await rpc<AtendimentoLinha[]>("painel_atendimentos", {
          p_empresa: filtro.empresa, p_de: filtro.de, p_ate: filtro.ate, p_situacao: filtro.situacao, p_busca: busca || null, p_limite: 1000, p_offset: off,
        });
        linhas.push(...parte);
        if (parte.length < 1000) break;
      }
      baixarCsv(
        `atendimentos-${new Date().toISOString().slice(0, 10)}`,
        linhas.map((l) => ({
          Data: fmtDataHora(l.data_atendimento ?? l.data_agendada),
          Tipo: tipoExame[l.tipo] ?? l.tipo,
          Situação: situacaoAtendimento(l.situacao).rotulo,
          ASO: l.aso_resultado,
          Colaborador: l.colaborador,
          CPF: l.cpf,
          Empresa: l.empresa,
          Função: l.funcao,
          Profissional: l.profissional,
          Exames: l.qtd_exames,
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
        titulo="Atendimentos"
        descricao="Consulta de atendimentos por empresa e período — o equivalente à tela Consultar Atendimento do SESMO. Clique num atendimento para ver os detalhes ou corrigir."
        acoes={
          <Button variant="outline" onClick={exportar} disabled={exportando || total === 0}>
            {exportando ? <Loader2 className="animate-spin" /> : <Download />} Exportar
          </Button>
        }
      />
      <Card className="grid gap-3 p-4 md:grid-cols-2 xl:grid-cols-[1.4fr_1fr_9rem_9rem_10rem]">
        <div className="space-y-1.5">
          <Label>Empresa</Label>
          {empresa ? (
            <div className="flex h-9 items-center gap-2 rounded-md border bg-muted/40 px-3 text-sm">
              <span className="flex-1 truncate">{empresa.nome}</span>
              <button type="button" onClick={() => { setEmpresa(null); reset(); }} aria-label="Limpar empresa" className="rounded p-0.5 hover:bg-accent">
                <X className="h-4 w-4" />
              </button>
            </div>
          ) : (
            <EmpresaSelect valor={null} onChange={(e) => { setEmpresa(e); reset(); }} />
          )}
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="a-busca">Colaborador</Label>
          <div className="relative">
            <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
            <Input id="a-busca" className="pl-8" placeholder="Nome ou CPF" value={texto} onChange={(e) => { setTexto(e.target.value); reset(); }} />
          </div>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="a-de">De</Label>
          <Input id="a-de" type="date" value={de} onChange={(e) => { setDe(e.target.value); reset(); }} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="a-ate">Até</Label>
          <Input id="a-ate" type="date" value={ate} onChange={(e) => { setAte(e.target.value); reset(); }} />
        </div>
        <div className="space-y-1.5">
          <Label>Situação</Label>
          <Select value={situacao} onValueChange={(v) => { setSituacao(v); reset(); }}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={TODAS}>Todas</SelectItem>
              {SITUACOES.map((s) => (
                <SelectItem key={s} value={s}>
                  {situacaoAtendimento(s).rotulo}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </Card>

      {q.isError ? (
        <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
      ) : q.data && q.data.length === 0 ? (
        <EstadoVazio icone={Stethoscope} titulo="Nenhum atendimento no período" texto="Amplie o período ou tire filtros. Para ver o histórico inteiro, apague a data inicial." />
      ) : (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Data</TableHead>
                <TableHead>Colaborador</TableHead>
                <TableHead className="hidden lg:table-cell">Empresa</TableHead>
                <TableHead className="hidden md:table-cell">Tipo</TableHead>
                <TableHead>Situação</TableHead>
                <TableHead className="hidden xl:table-cell">Profissional</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {q.isLoading &&
                Array.from({ length: 8 }).map((_, i) => (
                  <TableRow key={i}>
                    <TableCell colSpan={6}>
                      <Skeleton className="h-5 w-full" />
                    </TableCell>
                  </TableRow>
                ))}
              {q.data?.map((l) => {
                const s = situacaoAtendimento(l.situacao);
                return (
                  <TableRow key={l.id} className="cursor-pointer" onClick={() => setAberto(l.id)}>
                    <TableCell className="whitespace-nowrap">{fmtDataHora(l.data_atendimento ?? l.data_agendada)}</TableCell>
                    <TableCell>
                      <p className="font-medium">{l.colaborador ?? "—"}</p>
                      <p className="text-xs text-muted-foreground">{l.funcao ?? ""}</p>
                    </TableCell>
                    <TableCell className="hidden lg:table-cell">{l.empresa}</TableCell>
                    <TableCell className="hidden md:table-cell">
                      {tipoExame[l.tipo] ?? l.tipo}
                      {l.qtd_exames > 0 && <p className="text-xs text-muted-foreground">{l.qtd_exames} exame(s)</p>}
                    </TableCell>
                    <TableCell>
                      <Badge variant={s.badge}>{s.rotulo}</Badge>
                    </TableCell>
                    <TableCell className="hidden xl:table-cell">{l.profissional ?? "—"}</TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </Card>
      )}
      <Paginacao pagina={pagina} porPagina={POR_PAGINA} total={total} onMudar={setPagina} />
      <AtendimentoDialog id={aberto} onFechar={() => setAberto(null)} />
    </div>
  );
}
