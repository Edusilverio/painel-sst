import { useState } from "react";
import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Link2, Search } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { Paginacao } from "@/components/ui/paginacao";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { EmpresaSelect, type EmpresaEscolhida } from "@/components/crm/EmpresaSelect";
import { useDebounce } from "@/hooks/useDebounce";
import { rpc } from "@/lib/supabase";
import { fmtCnpj } from "@/lib/utils";

const POR_PAGINA = 50;

interface Linha {
  bitrix_id: number;
  nome: string | null;
  cnpj: string | null;
  empresa_id: string | null;
  empresa: string | null;
  metodo: "cnpj" | "nome" | "manual" | null;
  negocios: number;
  abertos: number;
  total: number;
}

const METODO: Record<string, string> = { cnpj: "pelo CNPJ", nome: "pelo nome", manual: "manual" };

export default function BitrixEmpresas() {
  const qc = useQueryClient();
  const [texto, setTexto] = useState("");
  const busca = useDebounce(texto.trim(), 300);
  const [todas, setTodas] = useState(false);
  const [pagina, setPagina] = useState(0);
  const q = useQuery({
    queryKey: ["bitrix-empresas", busca, todas, pagina],
    queryFn: () =>
      rpc<Linha[]>("painel_bitrix_empresas", { p_busca: busca || null, p_so_sem_vinculo: !todas, p_limite: POR_PAGINA, p_offset: pagina * POR_PAGINA }),
    placeholderData: keepPreviousData,
  });
  const vincular = useMutation({
    mutationFn: (v: { bitrix_id: number; empresa: EmpresaEscolhida }) =>
      rpc<number>("painel_bitrix_empresa_vincular", { p_bitrix_id: v.bitrix_id, p_empresa: v.empresa.id }),
    onSuccess: (n, v) => {
      qc.invalidateQueries({ queryKey: ["bitrix-empresas"] });
      qc.invalidateQueries({ queryKey: ["crm"] });
      toast.success(`${v.empresa.nome}: ${n} card${n === 1 ? "" : "s"} vinculado${n === 1 ? "" : "s"}`);
    },
    onError: (e) => toast.error(e instanceof Error ? e.message : "Não foi possível vincular."),
  });
  const total = q.data?.[0]?.total ?? 0;

  return (
    <div className="mx-auto max-w-6xl space-y-5 p-4 sm:p-6">
      <Cabecalho
        titulo="Empresas do Bitrix"
        descricao="Os negócios do Bitrix já estão nos funis. Aqui ficam as empresas do Bitrix que não bateram com o cadastro do SESMO (nem por CNPJ nem pelo nome). Escolha a empresa certa e todos os cards dela passam a apontar para o cadastro."
      />
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative min-w-[220px] flex-1 sm:max-w-sm">
          <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
          <Input value={texto} onChange={(e) => { setTexto(e.target.value); setPagina(0); }} placeholder="Nome ou CNPJ no Bitrix" className="pl-8" aria-label="Buscar empresa do Bitrix" />
        </div>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" checked={todas} onChange={(e) => { setTodas(e.target.checked); setPagina(0); }} />
          Mostrar também as já vinculadas
        </label>
        <span className="ml-auto text-sm text-muted-foreground">{total} empresa{total === 1 ? "" : "s"}</span>
      </div>
      {q.isError ? (
        <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
      ) : q.data && q.data.length === 0 ? (
        <EstadoVazio icone={Link2} titulo="Nada para vincular" texto="Todas as empresas do Bitrix com esse filtro já estão ligadas ao cadastro." />
      ) : (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>No Bitrix</TableHead>
                <TableHead className="w-24 text-right">Cards</TableHead>
                <TableHead className="w-[26rem]">Empresa no cadastro</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {q.isLoading &&
                Array.from({ length: 6 }).map((_, i) => (
                  <TableRow key={i}>
                    <TableCell colSpan={3}>
                      <Skeleton className="h-5 w-full" />
                    </TableCell>
                  </TableRow>
                ))}
              {q.data?.map((l) => (
                <TableRow key={l.bitrix_id}>
                  <TableCell>
                    <p className="text-sm font-medium">{l.nome ?? `Empresa #${l.bitrix_id}`}</p>
                    <p className="text-xs text-muted-foreground">
                      {l.cnpj ? fmtCnpj(l.cnpj) : "sem CNPJ no Bitrix"} · Bitrix #{l.bitrix_id}
                    </p>
                  </TableCell>
                  <TableCell className="text-right text-sm">
                    {l.negocios}
                    {l.abertos > 0 && <Badge variant="warning" className="ml-1.5">{l.abertos} aberto{l.abertos === 1 ? "" : "s"}</Badge>}
                  </TableCell>
                  <TableCell>
                    <Vincular linha={l} pendente={vincular.isPending} onVincular={(empresa) => vincular.mutate({ bitrix_id: l.bitrix_id, empresa })} />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Card>
      )}
      <Paginacao pagina={pagina} porPagina={POR_PAGINA} total={total} onMudar={setPagina} />
    </div>
  );
}

function Vincular({ linha, pendente, onVincular }: { linha: Linha; pendente: boolean; onVincular: (e: EmpresaEscolhida) => void }) {
  const [escolha, setEscolha] = useState<EmpresaEscolhida | null>(null);
  if (linha.empresa_id && !escolha)
    return (
      <div className="flex items-center gap-2 text-sm">
        <span className="flex-1 truncate">{linha.empresa}</span>
        {linha.metodo && <Badge variant="muted">{METODO[linha.metodo]}</Badge>}
        <Button size="sm" variant="ghost" onClick={() => setEscolha({ id: "", nome: "", cnpj: null })}>
          Trocar
        </Button>
      </div>
    );
  return (
    <div className="flex items-center gap-2">
      <div className="flex-1">
        <EmpresaSelect valor={escolha?.id ? escolha : null} onChange={setEscolha} />
      </div>
      <Button size="sm" disabled={!escolha?.id || pendente} onClick={() => escolha?.id && onVincular(escolha)}>
        Vincular
      </Button>
    </div>
  );
}
