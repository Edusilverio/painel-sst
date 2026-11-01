import { useState } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { History, Search } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Paginacao } from "@/components/ui/paginacao";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useResponsaveis } from "@/hooks/api";
import { useDebounce } from "@/hooks/useDebounce";
import { rpc } from "@/lib/supabase";
import { fmtDataHora } from "@/lib/utils";

const POR_PAGINA = 100;
const TODOS = "__todos__";

interface Linha {
  em: string;
  origem: "cadastro" | "crm";
  usuario_id: string | null;
  usuario: string | null;
  acao: string;
  entidade: string;
  registro_id: string;
  registro: string | null;
  detalhe: Record<string, unknown>;
  total: number;
}

const ENTIDADE: Record<string, string> = {
  empresa: "Empresa",
  empresa_contato: "Contato",
  unidade: "Unidade",
  colaborador: "Colaborador",
  atendimento: "Atendimento",
  atestado: "Atestado",
  negocio: "Card do CRM",
};
const ACAO: Record<string, string> = {
  editar: "alterou",
  criar: "incluiu",
  excluir: "excluiu",
  liberar: "voltou a seguir o SESMO",
  criado: "criou",
  etapa: "moveu",
  nota: "anotou",
  ligacao: "registrou ligação",
  email: "registrou e-mail",
  reuniao: "registrou reunião",
  whatsapp: "registrou WhatsApp",
  atribuido: "atribuiu",
};

const fmtValor = (v: unknown) => {
  if (v == null || v === "") return "vazio";
  if (typeof v === "boolean") return v ? "sim" : "não";
  const s = String(v);
  if (/^\d{4}-\d{2}-\d{2}T/.test(s)) return fmtDataHora(s);
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s.split("-").reverse().join("/");
  return s;
};

function Detalhe({ l }: { l: Linha }) {
  const d = l.detalhe ?? {};
  if (l.origem === "crm") {
    const de = d.de as string | null;
    const para = d.para as string | null;
    return (
      <div className="text-sm">
        {(de || para) && (
          <p>
            {de ?? "—"} → {para ?? "—"}
          </p>
        )}
        {typeof d.texto === "string" && d.texto && <p className="text-muted-foreground">{d.texto}</p>}
      </div>
    );
  }
  if (l.acao === "editar" || l.acao === "criar")
    return (
      <ul className="space-y-0.5 text-sm">
        {Object.entries(d).map(([k, m]) => (
          <li key={k}>
            <span className="text-muted-foreground">{k.replace(/_/g, " ")}:</span>{" "}
            {l.acao === "editar" && <span className="text-muted-foreground line-through">{fmtValor((m as { de: unknown }).de)}</span>}
            {l.acao === "editar" && " → "}
            {fmtValor((m as { para: unknown }).para)}
          </li>
        ))}
      </ul>
    );
  if (l.acao === "liberar") return <p className="text-sm text-muted-foreground">Campos: {((d.campos as string[]) ?? []).join(", ")}</p>;
  return null;
}

export default function Auditoria() {
  const [origem, setOrigem] = useState(TODOS);
  const [usuario, setUsuario] = useState(TODOS);
  const [de, setDe] = useState("");
  const [ate, setAte] = useState("");
  const [texto, setTexto] = useState("");
  const busca = useDebounce(texto.trim());
  const [pagina, setPagina] = useState(0);
  const pessoas = useResponsaveis();
  const f = { origem, usuario, de, ate, busca, pagina };
  const q = useQuery({
    queryKey: ["auditoria", f],
    queryFn: () =>
      rpc<Linha[]>("painel_auditoria", {
        p_origem: origem === TODOS ? null : origem,
        p_usuario: usuario === TODOS ? null : usuario,
        p_de: de || null,
        p_ate: ate || null,
        p_busca: busca || null,
        p_limite: POR_PAGINA,
        p_offset: pagina * POR_PAGINA,
      }),
    placeholderData: keepPreviousData,
  });
  const total = q.data?.[0]?.total ?? 0;
  const reset = () => setPagina(0);

  return (
    <div className="mx-auto max-w-7xl space-y-5 p-4 sm:p-6">
      <Cabecalho
        titulo="Registro de alterações"
        descricao="Quem mudou o quê, e quando: cadastros de empresas, contatos, unidades, colaboradores e atendimentos, e a movimentação dos cards do CRM. Visível só para administradores."
      />
      <Card className="grid gap-3 p-4 md:grid-cols-2 xl:grid-cols-[1.3fr_10rem_12rem_9rem_9rem]">
        <div className="space-y-1.5">
          <Label htmlFor="au-busca">Buscar</Label>
          <div className="relative">
            <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
            <Input id="au-busca" className="pl-8" placeholder="Empresa, colaborador, card ou pessoa" value={texto} onChange={(e) => { setTexto(e.target.value); reset(); }} />
          </div>
        </div>
        <div className="space-y-1.5">
          <Label>Onde</Label>
          <Select value={origem} onValueChange={(v) => { setOrigem(v); reset(); }}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={TODOS}>Tudo</SelectItem>
              <SelectItem value="cadastro">Cadastros</SelectItem>
              <SelectItem value="crm">CRM</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label>Pessoa</Label>
          <Select value={usuario} onValueChange={(v) => { setUsuario(v); reset(); }}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={TODOS}>Todas</SelectItem>
              {pessoas.data?.map((p) => (
                <SelectItem key={p.user_id} value={p.user_id}>
                  {p.nome}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="au-de">De</Label>
          <Input id="au-de" type="date" value={de} onChange={(e) => { setDe(e.target.value); reset(); }} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="au-ate">Até</Label>
          <Input id="au-ate" type="date" value={ate} onChange={(e) => { setAte(e.target.value); reset(); }} />
        </div>
      </Card>

      {q.isError ? (
        <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
      ) : q.data && q.data.length === 0 ? (
        <EstadoVazio icone={History} titulo="Nenhuma alteração encontrada" texto="Mude os filtros ou o período." />
      ) : (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-40">Quando</TableHead>
                <TableHead>Quem</TableHead>
                <TableHead>O quê</TableHead>
                <TableHead className="hidden lg:table-cell">Detalhe</TableHead>
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
              {q.data?.map((l, i) => (
                <TableRow key={`${l.em}-${i}`}>
                  <TableCell className="whitespace-nowrap text-sm">{fmtDataHora(l.em)}</TableCell>
                  <TableCell className="text-sm font-medium">{l.usuario ?? "Sistema"}</TableCell>
                  <TableCell>
                    <p className="text-sm">
                      <Badge variant={l.origem === "crm" ? "info" : "secondary"} className="mr-1.5">
                        {ENTIDADE[l.entidade] ?? l.entidade}
                      </Badge>
                      {ACAO[l.acao] ?? l.acao}
                    </p>
                    <p className="text-sm text-muted-foreground">{l.registro ?? "—"}</p>
                    <div className="mt-1 lg:hidden">
                      <Detalhe l={l} />
                    </div>
                  </TableCell>
                  <TableCell className="hidden align-top lg:table-cell">
                    <Detalhe l={l} />
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
