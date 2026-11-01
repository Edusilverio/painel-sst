import { useState } from "react";
import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { AlertTriangle, BellRing, Building2, FileHeart, Loader2, MessageCircle, Paperclip, Plus, Search, Settings2 } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { KpiCard } from "@/components/ui/kpi-card";
import { Label } from "@/components/ui/label";
import { Paginacao } from "@/components/ui/paginacao";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Textarea } from "@/components/ui/textarea";
import { EmpresaSelect, type EmpresaEscolhida } from "@/components/crm/EmpresaSelect";
import { useDebounce } from "@/hooks/useDebounce";
import { useSessao } from "@/contexts/sessao";
import { rpc, supabase } from "@/lib/supabase";
import { fmtData } from "@/lib/utils";

const POR_PAGINA = 100;
const TODOS = "__todos__";

interface Resumo {
  mes: string;
  limite: number;
  prazo_dias: number;
  ativo: boolean;
  total: number;
  empresas: number;
  alertas: number;
  revisar: number;
  ranking: { empresa_id: string; nome: string; quantidade: number; dias: number; alertado: boolean }[];
}
interface Linha {
  id: string;
  numero: number;
  empresa_id: string | null;
  empresa: string | null;
  colaborador_id: string | null;
  colaborador: string | null;
  cpf: string | null;
  data_emissao: string | null;
  data_inicio: string | null;
  dias: number | null;
  cid: string | null;
  medico: string | null;
  medico_crm: string | null;
  origem: "painel" | "whatsapp";
  wa_telefone: string | null;
  situacao: "ok" | "revisar" | "descartado";
  observacao: string | null;
  arquivo_path: string | null;
  arquivo_nome: string | null;
  mes: string;
  criado_em: string;
  total: number;
}

const mesAtual = () => new Date().toISOString().slice(0, 7);
const mesRotulo = (m: string) => {
  const [a, mm] = m.split("-");
  return new Date(Number(a), Number(mm) - 1, 1).toLocaleDateString("pt-BR", { month: "long", year: "numeric" });
};
const erro = (e: unknown) => toast.error(e instanceof Error ? e.message : "Não foi possível salvar.");

async function abrir(caminho: string) {
  const { data, error } = await supabase.storage.from(((import.meta.env.VITE_STORAGE_PREFIX as string | undefined) ?? "") + "atestados").createSignedUrl(caminho, 120);
  if (error || !data) return toast.error("Não foi possível abrir o arquivo.");
  window.open(data.signedUrl, "_blank", "noopener");
}

export default function Atestados() {
  const { tem } = useSessao();
  const qc = useQueryClient();
  const [mes, setMes] = useState(mesAtual());
  const [situacao, setSituacao] = useState<string>(TODOS);
  const [empresa, setEmpresa] = useState<{ id: string; nome: string } | null>(null);
  const [texto, setTexto] = useState("");
  const busca = useDebounce(texto.trim(), 300);
  const [pagina, setPagina] = useState(0);
  const [editar, setEditar] = useState<{ aberto: boolean; a: Linha | null }>({ aberto: false, a: null });
  const [regra, setRegra] = useState(false);
  const mesData = mes ? `${mes}-01` : null;

  const resumo = useQuery({
    queryKey: ["atestados", "resumo", mesData],
    queryFn: () => rpc<Resumo>("painel_atestados_resumo", { p_mes: mesData }),
  });
  const lista = useQuery({
    queryKey: ["atestados", "lista", mesData, situacao, empresa?.id, busca, pagina],
    queryFn: () =>
      rpc<Linha[]>("painel_atestados", {
        p_mes: situacao === "revisar" ? null : mesData,
        p_empresa: empresa?.id ?? null,
        p_situacao: situacao === TODOS ? null : situacao,
        p_busca: busca || null,
        p_limite: POR_PAGINA,
        p_offset: pagina * POR_PAGINA,
      }),
    placeholderData: keepPreviousData,
  });
  const r = resumo.data;
  const total = lista.data?.[0]?.total ?? 0;
  const reset = () => setPagina(0);

  return (
    <div className="mx-auto max-w-7xl space-y-5 p-4 sm:p-6">
      <Cabecalho
        titulo="Atestados"
        descricao={`Atestados recebidos das empresas (WhatsApp ou cadastro manual). Quando uma empresa chega a ${r?.limite ?? 5} atestados no mês, o responsável pelo cliente recebe um aviso, uma tarefa e um card no Pós-venda para agendar consulta médica.`}
        acoes={
          <div className="flex gap-2">
            {tem("gestor") && (
              <Button size="sm" variant="outline" onClick={() => setRegra(true)}>
                <Settings2 /> Regra
              </Button>
            )}
            <Button size="sm" onClick={() => setEditar({ aberto: true, a: null })}>
              <Plus /> Novo atestado
            </Button>
          </div>
        }
      />

      {resumo.isError ? (
        <EstadoErro erro={resumo.error} onTentar={() => resumo.refetch()} />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <KpiCard titulo={`Atestados em ${mes ? mesRotulo(mes) : "—"}`} valor={r?.total ?? 0} icone={FileHeart} carregando={resumo.isLoading} />
          <KpiCard titulo="Empresas com atestado" valor={r?.empresas ?? 0} icone={Building2} tom="info" carregando={resumo.isLoading} />
          <KpiCard titulo={`Alertas (${r?.limite ?? 5}+ no mês)`} valor={r?.alertas ?? 0} icone={BellRing} tom="warning" carregando={resumo.isLoading} />
          <KpiCard
            titulo="Para revisar"
            valor={r?.revisar ?? 0}
            detalhe="sem empresa ou colaborador identificado"
            icone={AlertTriangle}
            tom="destructive"
            carregando={resumo.isLoading}
            onClick={() => { setSituacao("revisar"); reset(); }}
          />
        </div>
      )}

      {!!r?.ranking?.length && (
        <Card className="p-4">
          <p className="mb-2 text-sm font-medium">Empresas no mês</p>
          <div className="flex flex-wrap gap-2">
            {r.ranking.map((e) => (
              <button
                key={e.empresa_id}
                type="button"
                onClick={() => { setEmpresa({ id: e.empresa_id, nome: e.nome }); reset(); }}
                className="rounded-md border px-2.5 py-1 text-left text-sm hover:bg-muted"
              >
                <span className="font-medium">{e.nome}</span>{" "}
                <Badge variant={e.quantidade >= r.limite ? "destructive" : "secondary"}>{e.quantidade}</Badge>
                {e.alertado && <BellRing className="ml-1 inline h-3.5 w-3.5 text-warning" aria-label="alerta enviado" />}
              </button>
            ))}
          </div>
        </Card>
      )}

      <div className="flex flex-wrap items-end gap-2">
        <div className="relative min-w-[220px] flex-1 sm:max-w-xs">
          <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
          <Input value={texto} onChange={(e) => { setTexto(e.target.value); reset(); }} placeholder="Colaborador, CPF ou empresa" className="pl-8" aria-label="Buscar atestado" />
        </div>
        <Input type="month" value={mes} onChange={(e) => { setMes(e.target.value); reset(); }} className="w-[170px]" aria-label="Mês" />
        <Select value={situacao} onValueChange={(v) => { setSituacao(v); reset(); }}>
          <SelectTrigger className="w-[160px]" aria-label="Situação">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value={TODOS}>Todos</SelectItem>
            <SelectItem value="ok">Contabilizados</SelectItem>
            <SelectItem value="revisar">Para revisar</SelectItem>
            <SelectItem value="descartado">Descartados</SelectItem>
          </SelectContent>
        </Select>
        {empresa && (
          <Button size="sm" variant="outline" onClick={() => { setEmpresa(null); reset(); }}>
            {empresa.nome} ✕
          </Button>
        )}
      </div>

      {lista.isError ? (
        <EstadoErro erro={lista.error} onTentar={() => lista.refetch()} />
      ) : lista.data && lista.data.length === 0 ? (
        <EstadoVazio
          icone={FileHeart}
          titulo="Nenhum atestado com esse filtro"
          texto="Os atestados chegam aqui quando a empresa envia pelo WhatsApp da Vitalis, ou quando alguém cadastra manualmente."
        />
      ) : (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead>Empresa</TableHead>
                <TableHead className="hidden md:table-cell">Afastamento</TableHead>
                <TableHead className="hidden lg:table-cell">CID</TableHead>
                <TableHead className="hidden md:table-cell">Origem</TableHead>
                <TableHead className="w-10" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {lista.isLoading &&
                Array.from({ length: 6 }).map((_, i) => (
                  <TableRow key={i}>
                    <TableCell colSpan={6}>
                      <Skeleton className="h-5 w-full" />
                    </TableCell>
                  </TableRow>
                ))}
              {lista.data?.map((a) => (
                <TableRow key={a.id} className="cursor-pointer" onClick={() => setEditar({ aberto: true, a })}>
                  <TableCell>
                    <p className="text-sm font-medium">{a.colaborador ?? "(sem nome)"}</p>
                    <p className="text-xs text-muted-foreground">
                      #{a.numero}
                      {a.situacao === "revisar" && <Badge variant="destructive" className="ml-1.5">revisar</Badge>}
                      {a.situacao === "descartado" && <Badge variant="secondary" className="ml-1.5">descartado</Badge>}
                    </p>
                  </TableCell>
                  <TableCell className="text-sm">{a.empresa ?? <span className="text-muted-foreground">não identificada</span>}</TableCell>
                  <TableCell className="hidden text-sm md:table-cell">
                    {fmtData(a.data_inicio ?? a.data_emissao)}
                    {a.dias != null && <span className="text-muted-foreground"> · {a.dias} dia{a.dias === 1 ? "" : "s"}</span>}
                  </TableCell>
                  <TableCell className="hidden text-sm lg:table-cell">{a.cid ?? "—"}</TableCell>
                  <TableCell className="hidden md:table-cell">
                    {a.origem === "whatsapp" ? (
                      <Badge variant="info"><MessageCircle className="mr-1 h-3 w-3" />WhatsApp</Badge>
                    ) : (
                      <Badge variant="secondary">Painel</Badge>
                    )}
                  </TableCell>
                  <TableCell onClick={(e) => e.stopPropagation()}>
                    {a.arquivo_path && (
                      <Button size="icon" variant="ghost" aria-label="Abrir arquivo" onClick={() => abrir(a.arquivo_path!)}>
                        <Paperclip />
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Card>
      )}
      <Paginacao pagina={pagina} porPagina={POR_PAGINA} total={total} onMudar={setPagina} />

      {editar.aberto && (
        <AtestadoDialog
          atestado={editar.a}
          onFechar={() => setEditar({ aberto: false, a: null })}
          onSalvo={() => qc.invalidateQueries({ queryKey: ["atestados"] })}
        />
      )}
      {regra && r && <RegraDialog r={r} onFechar={() => setRegra(false)} onSalvo={() => qc.invalidateQueries({ queryKey: ["atestados"] })} />}
    </div>
  );
}

function AtestadoDialog({ atestado: a, onFechar, onSalvo }: { atestado: Linha | null; onFechar: () => void; onSalvo: () => void }) {
  const [empresa, setEmpresa] = useState<EmpresaEscolhida | null>(a?.empresa_id ? { id: a.empresa_id, nome: a.empresa ?? "", cnpj: null } : null);
  const [f, setF] = useState({
    colaborador_nome: a?.colaborador ?? "",
    colaborador_cpf: a?.cpf ?? "",
    data_emissao: a?.data_emissao ?? "",
    data_inicio: a?.data_inicio ?? "",
    dias: a?.dias?.toString() ?? "",
    cid: a?.cid ?? "",
    medico: a?.medico ?? "",
    medico_crm: a?.medico_crm ?? "",
    observacao: a?.observacao ?? "",
    situacao: a?.situacao ?? "ok",
  });
  const [arquivo, setArquivo] = useState<File | null>(null);
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });

  const salvar = useMutation({
    mutationFn: async () => {
      const dados = { ...f, empresa_id: empresa?.id ?? null, situacao: a?.situacao === "revisar" && empresa && f.situacao === "revisar" ? "ok" : f.situacao };
      const id = await rpc<string>("painel_atestado_salvar", { p_id: a?.id ?? null, p_dados: dados });
      if (arquivo) {
        const limpo = arquivo.name.normalize("NFD").replace(/[^\w.-]+/g, "_");
        const caminho = `painel/${new Date().toISOString().slice(0, 7)}/${id}-${limpo}`;
        const { error } = await supabase.storage.from(((import.meta.env.VITE_STORAGE_PREFIX as string | undefined) ?? "") + "atestados").upload(caminho, arquivo, { contentType: arquivo.type || "application/pdf" });
        if (error) throw new Error(`Atestado salvo, mas o arquivo não subiu: ${error.message}`);
        await rpc<void>("painel_atestado_arquivo", { p_id: id, p_path: caminho, p_nome: arquivo.name });
      }
    },
    onSuccess: () => {
      onSalvo();
      toast.success(a ? "Atestado atualizado" : "Atestado cadastrado");
      onFechar();
    },
    onError: erro,
  });

  return (
    <Dialog open onOpenChange={(o) => !o && onFechar()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-xl">
        <DialogHeader>
          <DialogTitle>{a ? `Atestado #${a.numero}` : "Novo atestado"}</DialogTitle>
          <DialogDescription>
            {a?.origem === "whatsapp"
              ? `Recebido pelo WhatsApp${a.wa_telefone ? ` (${a.wa_telefone})` : ""} em ${fmtData(a.criado_em)}. Confira o que a IA leu.`
              : "Dados do atestado. O mês conta pela data de início do afastamento."}
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-3">
          {a?.arquivo_path && (
            <Button variant="outline" size="sm" className="justify-start" onClick={() => abrir(a.arquivo_path!)}>
              <Paperclip /> {a.arquivo_nome ?? "Abrir arquivo"}
            </Button>
          )}
          <div className="space-y-1.5">
            <Label>Empresa</Label>
            <EmpresaSelect valor={empresa} onChange={setEmpresa} />
          </div>
          <div className="grid gap-3 sm:grid-cols-[1fr_11rem]">
            <div className="space-y-1.5">
              <Label htmlFor="at-nome">Colaborador</Label>
              <Input id="at-nome" value={f.colaborador_nome} onChange={set("colaborador_nome")} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="at-cpf">CPF</Label>
              <Input id="at-cpf" value={f.colaborador_cpf} onChange={set("colaborador_cpf")} inputMode="numeric" />
            </div>
          </div>
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="space-y-1.5">
              <Label htmlFor="at-ini">Início do afastamento</Label>
              <Input id="at-ini" type="date" value={f.data_inicio} onChange={set("data_inicio")} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="at-dias">Dias</Label>
              <Input id="at-dias" type="number" min={0} value={f.dias} onChange={set("dias")} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="at-emi">Emissão</Label>
              <Input id="at-emi" type="date" value={f.data_emissao} onChange={set("data_emissao")} />
            </div>
          </div>
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="space-y-1.5">
              <Label htmlFor="at-cid">CID</Label>
              <Input id="at-cid" value={f.cid} onChange={set("cid")} placeholder="opcional" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="at-med">Médico</Label>
              <Input id="at-med" value={f.medico} onChange={set("medico")} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="at-crm">CRM</Label>
              <Input id="at-crm" value={f.medico_crm} onChange={set("medico_crm")} />
            </div>
          </div>
          <div className="grid gap-3 sm:grid-cols-[1fr_12rem]">
            <div className="space-y-1.5">
              <Label htmlFor="at-arq">{a?.arquivo_path ? "Trocar arquivo" : "Arquivo (foto ou PDF)"}</Label>
              <Input id="at-arq" type="file" accept="image/*,application/pdf" onChange={(e) => setArquivo(e.target.files?.[0] ?? null)} />
            </div>
            <div className="space-y-1.5">
              <Label>Situação</Label>
              <Select value={f.situacao} onValueChange={(v) => setF({ ...f, situacao: v as Linha["situacao"] })}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="ok">Contabilizar</SelectItem>
                  <SelectItem value="revisar">Revisar</SelectItem>
                  <SelectItem value="descartado">Descartar</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="at-obs">Observação</Label>
            <Textarea id="at-obs" rows={2} value={f.observacao} onChange={set("observacao")} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onFechar}>Cancelar</Button>
          <Button onClick={() => salvar.mutate()} disabled={salvar.isPending || (!empresa && f.situacao === "ok")}>
            {salvar.isPending && <Loader2 className="animate-spin" />} Salvar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function RegraDialog({ r, onFechar, onSalvo }: { r: Resumo; onFechar: () => void; onSalvo: () => void }) {
  const [limite, setLimite] = useState(String(r.limite));
  const [prazo, setPrazo] = useState(String(r.prazo_dias));
  const [ativo, setAtivo] = useState(r.ativo ? "sim" : "nao");
  const salvar = useMutation({
    mutationFn: () => rpc<void>("painel_atestado_regra_salvar", { p_limite: Number(limite), p_prazo_dias: Number(prazo), p_ativo: ativo === "sim" }),
    onSuccess: () => { onSalvo(); toast.success("Regra salva"); onFechar(); },
    onError: erro,
  });
  return (
    <Dialog open onOpenChange={(o) => !o && onFechar()}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>Regra do alerta</DialogTitle>
          <DialogDescription>Um alerta por empresa por mês, para o responsável pelo cliente.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-3">
          <div className="space-y-1.5">
            <Label htmlFor="rg-lim">Atestados no mês para alertar</Label>
            <Input id="rg-lim" type="number" min={1} max={100} value={limite} onChange={(e) => setLimite(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="rg-prazo">Prazo da tarefa (dias)</Label>
            <Input id="rg-prazo" type="number" min={0} max={60} value={prazo} onChange={(e) => setPrazo(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label>Alerta ligado</Label>
            <Select value={ativo} onValueChange={setAtivo}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="sim">Sim</SelectItem>
                <SelectItem value="nao">Não</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onFechar}>Cancelar</Button>
          <Button onClick={() => salvar.mutate()} disabled={salvar.isPending}>Salvar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
