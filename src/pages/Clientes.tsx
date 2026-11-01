import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Building2, Plus, Search } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { NovaEmpresaDialog } from "@/components/dados/NovaEmpresa";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useSessao } from "@/contexts/sessao";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Paginacao } from "@/components/ui/paginacao";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { useClientes } from "@/hooks/api";
import { useDebounce } from "@/hooks/useDebounce";
import { situacaoCliente } from "@/lib/status";
import { fmtCnpj, fmtNumero } from "@/lib/utils";

const POR_PAGINA = 50;

export default function Clientes() {
  const [texto, setTexto] = useState("");
  const busca = useDebounce(texto.trim());
  const [situacao, setSituacao] = useState<string>("todas");
  const [pagina, setPagina] = useState(0);
  const q = useClientes(busca, situacao === "todas" ? null : situacao, pagina, POR_PAGINA);
  const total = q.data?.[0]?.total ?? 0;
  const { tem } = useSessao();
  const podeCadastrar = tem("gestor", "comercial", "operacoes");
  const [nova, setNova] = useState(false);
  const navegar = useNavigate();

  return (
    <div className="mx-auto max-w-7xl space-y-5 p-4 sm:p-6">
      <Cabecalho
        titulo="Empresas"
        descricao="Base de clientes da Vitalis (do SESMO e cadastradas no painel)."
        acoes={
          podeCadastrar && (
            <Button size="sm" onClick={() => setNova(true)}>
              <Plus /> Nova empresa
            </Button>
          )
        }
      />
      <NovaEmpresaDialog aberto={nova} onFechar={() => setNova(false)} nomeInicial={texto} onCriada={(e) => navegar(`/clientes/${e.id}`)} />
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <div className="relative w-full sm:w-80">
          <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
          <Input
            className="pl-8"
            placeholder="Nome, fantasia ou CNPJ…"
            value={texto}
            onChange={(e) => {
              setTexto(e.target.value);
              setPagina(0);
            }}
            aria-label="Buscar empresas"
          />
        </div>
        <Tabs
          value={situacao}
          onValueChange={(v) => {
            setSituacao(v);
            setPagina(0);
          }}
        >
          <TabsList className="flex-wrap">
            <TabsTrigger value="todas">Todas</TabsTrigger>
            <TabsTrigger value="ativo">Ativas</TabsTrigger>
            <TabsTrigger value="sem_contrato">Sem contrato</TabsTrigger>
            <TabsTrigger value="inativo">Inativas</TabsTrigger>
            <TabsTrigger value="a_confirmar">A confirmar</TabsTrigger>
          </TabsList>
        </Tabs>
      </div>

      {q.isError ? (
        <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
      ) : q.data && q.data.length === 0 ? (
        <EstadoVazio icone={Building2} titulo="Nenhuma empresa encontrada" texto={busca ? "Confira a grafia ou busque pelo CNPJ." : "A carga do SESMO ainda não trouxe empresas para esta situação."} />
      ) : (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Empresa</TableHead>
                <TableHead className="hidden md:table-cell">CNPJ</TableHead>
                <TableHead className="hidden lg:table-cell">Cidade</TableHead>
                <TableHead>Situação</TableHead>
                <TableHead className="hidden text-right sm:table-cell">Unidades</TableHead>
                <TableHead className="hidden text-right sm:table-cell">Colaboradores</TableHead>
                <TableHead className="hidden text-right md:table-cell">Negócios</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {q.isLoading &&
                Array.from({ length: 8 }).map((_, i) => (
                  <TableRow key={i}>
                    <TableCell colSpan={7}>
                      <Skeleton className="h-5 w-full" />
                    </TableCell>
                  </TableRow>
                ))}
              {q.data?.map((c) => {
                const s = situacaoCliente(c.situacao);
                return (
                  <TableRow key={c.id}>
                    <TableCell>
                      <Link to={`/clientes/${c.id}`} className="font-medium text-primary hover:underline">
                        {c.nome}
                      </Link>
                      {c.nome !== c.razao_social && <p className="text-xs text-muted-foreground">{c.razao_social}</p>}
                    </TableCell>
                    <TableCell className="hidden whitespace-nowrap md:table-cell">{fmtCnpj(c.cnpj)}</TableCell>
                    <TableCell className="hidden lg:table-cell">{c.cidade ? `${c.cidade}${c.uf ? `/${c.uf}` : ""}` : "—"}</TableCell>
                    <TableCell>
                      <Badge variant={s.badge}>{s.rotulo}</Badge>
                    </TableCell>
                    <TableCell className="hidden text-right tabular-nums sm:table-cell">{fmtNumero(c.unidades)}</TableCell>
                    <TableCell className="hidden text-right tabular-nums sm:table-cell">{fmtNumero(c.colaboradores)}</TableCell>
                    <TableCell className="hidden text-right tabular-nums md:table-cell">{c.negocios_abertos || "—"}</TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </Card>
      )}
      <Paginacao pagina={pagina} porPagina={POR_PAGINA} total={total} onMudar={setPagina} />
    </div>
  );
}
