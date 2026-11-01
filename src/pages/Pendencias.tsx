import { useState } from "react";
import { Link } from "react-router-dom";
import { CheckCircle2 } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { useFunis, usePendencias } from "@/hooks/api";
import { fmtMoeda } from "@/lib/utils";
import { useSessao } from "@/contexts/sessao";

export default function Pendencias() {
  const [minhas, setMinhas] = useState(true);
  const q = usePendencias(minhas);
  const funis = useFunis();
  const slug = (id: string) => funis.data?.find((f) => f.id === id)?.slug ?? "comercial";
  const veValores = useSessao().tem("financeiro", "comercial"); // 0074

  return (
    <div className="mx-auto max-w-6xl space-y-5 p-4 sm:p-6">
      <Cabecalho
        titulo="Pendências"
        descricao="Negócios parados além do prazo da etapa (ex.: proposta sem movimento há 3 dias). O aviso se repete a cada ciclo até o card andar."
        acoes={
          <Tabs value={minhas ? "minhas" : "todas"} onValueChange={(v) => setMinhas(v === "minhas")}>
            <TabsList>
              <TabsTrigger value="minhas">Minhas</TabsTrigger>
              <TabsTrigger value="todas">Todas</TabsTrigger>
            </TabsList>
          </Tabs>
        }
      />
      {q.isError ? (
        <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
      ) : q.data && q.data.length === 0 ? (
        <EstadoVazio icone={CheckCircle2} titulo="Nenhum negócio parado" texto={minhas ? "Tudo em dia com os seus negócios." : "Nenhum negócio passou do prazo da etapa."} />
      ) : (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Negócio</TableHead>
                <TableHead>Funil / etapa</TableHead>
                <TableHead>Responsável</TableHead>
                <TableHead className="text-right">Parado há</TableHead>
                {veValores && <TableHead className="text-right">Valor</TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {q.isLoading &&
                Array.from({ length: 5 }).map((_, i) => (
                  <TableRow key={i}>
                    {Array.from({ length: veValores ? 5 : 4 }).map((__, j) => (
                      <TableCell key={j}>
                        <Skeleton className="h-4 w-full" />
                      </TableCell>
                    ))}
                  </TableRow>
                ))}
              {q.data?.map((p) => (
                <TableRow key={p.id}>
                  <TableCell>
                    <Link to={`/crm?funil=${slug(p.funil_id)}&negocio=${p.id}`} className="font-medium text-primary hover:underline">
                      #{p.numero} {p.titulo}
                    </Link>
                    {p.cliente && p.cliente !== p.titulo && <p className="text-xs text-muted-foreground">{p.cliente}</p>}
                  </TableCell>
                  <TableCell>
                    {p.funil} · {p.etapa}
                  </TableCell>
                  <TableCell>{p.responsavel_nome ?? <span className="text-muted-foreground">Sem responsável</span>}</TableCell>
                  <TableCell className="text-right">
                    <Badge variant={p.dias_na_etapa >= p.alerta_dias * 2 ? "destructive" : "warning"}>
                      {p.dias_na_etapa} dias <span className="font-normal opacity-80">(prazo {p.alerta_dias})</span>
                    </Badge>
                  </TableCell>
                  {veValores && <TableCell className="text-right tabular-nums">{fmtMoeda(p.valor)}</TableCell>}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Card>
      )}
    </div>
  );
}
