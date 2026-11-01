import { useRef, useState } from "react";
import { Link } from "react-router-dom";
import { CalendarClock, CalendarX2, FileCheck2, FilePen, FileText, Loader2, Paperclip, Plus, RefreshCcw, Search, Upload } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { KpiCard } from "@/components/ui/kpi-card";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Textarea } from "@/components/ui/textarea";
import { EmpresaSelect, type EmpresaEscolhida } from "@/components/crm/EmpresaSelect";
import { useDebounce } from "@/hooks/useDebounce";
import { abrirArquivo, useDocumentos, useDocumentosResumo, useProfissionais, useSalvarDocumento } from "@/hooks/api";
import { TIPOS_DOCUMENTO, situacaoDocumento } from "@/lib/status";
import type { DocumentoLinha } from "@/lib/tipos";
import { baixarCsv, cn, fmtCnpj, fmtData } from "@/lib/utils";

const TODOS = "__todos__";
const NINGUEM = "__ninguem__";

export default function Documentos() {
  const resumo = useDocumentosResumo();
  const [texto, setTexto] = useState("");
  const busca = useDebounce(texto, 300);
  const [tipo, setTipo] = useState<string>(TODOS);
  const [situacao, setSituacao] = useState<string | null>(null);
  const lista = useDocumentos(busca, tipo === TODOS ? null : tipo, situacao);
  const [editar, setEditar] = useState<{ aberto: boolean; d: DocumentoLinha | null }>({ aberto: false, d: null });
  const pode = !!resumo.data?.pode_editar;
  const aviso = resumo.data?.aviso_dias ?? 60;

  return (
    <div className="mx-auto max-w-7xl space-y-5 p-4 sm:p-6">
      <Cabecalho
        titulo="Documentos técnicos"
        descricao={`PGR, PCMSO, LTCAT e demais laudos por empresa. ${aviso} dias antes de vencer, o documento abre um card de renovação no funil Laudos.`}
        acoes={
          pode && (
            <Button size="sm" onClick={() => setEditar({ aberto: true, d: null })}>
              <Plus /> Novo documento
            </Button>
          )
        }
      />
      {resumo.isError ? (
        <EstadoErro erro={resumo.error} onTentar={() => resumo.refetch()} />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <KpiCard titulo="Vencidos" valor={resumo.data?.vencidos ?? 0} icone={CalendarX2} tom="destructive" carregando={resumo.isLoading} onClick={() => setSituacao("vencido")} />
          <KpiCard titulo={`A vencer (${aviso} dias)`} valor={resumo.data?.a_vencer ?? 0} icone={CalendarClock} tom="warning" carregando={resumo.isLoading} onClick={() => setSituacao("a_vencer")} />
          <KpiCard titulo="Em elaboração" valor={resumo.data?.em_elaboracao ?? 0} icone={FilePen} tom="info" carregando={resumo.isLoading} onClick={() => setSituacao("em_elaboracao")} />
          <KpiCard titulo="Vigentes" valor={resumo.data?.vigentes ?? 0} icone={FileCheck2} tom="success" carregando={resumo.isLoading} onClick={() => setSituacao("vigente")} />
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative min-w-[220px] flex-1 sm:max-w-xs">
          <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
          <Input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Empresa ou CNPJ" className="pl-8" aria-label="Buscar documento" />
        </div>
        <Select value={tipo} onValueChange={setTipo}>
          <SelectTrigger className="w-[150px]" aria-label="Tipo de documento">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value={TODOS}>Todos os tipos</SelectItem>
            {TIPOS_DOCUMENTO.map((t) => (
              <SelectItem key={t} value={t}>
                {t === "OUTRO" ? "Outro" : t}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        {situacao && (
          <Button size="sm" variant="outline" onClick={() => setSituacao(null)}>
            {situacaoDocumento[situacao].rotulo} ✕
          </Button>
        )}
        <Button
          size="sm"
          variant="ghost"
          className="ml-auto"
          disabled={!lista.data?.length}
          onClick={() =>
            baixarCsv(
              "documentos-tecnicos",
              (lista.data ?? []).map((d) => ({
                empresa: d.empresa,
                cnpj: fmtCnpj(d.cnpj),
                tipo: d.tipo,
                versao: d.versao ?? "",
                inicio: fmtData(d.vigencia_inicio),
                fim: fmtData(d.vigencia_fim),
                situacao: situacaoDocumento[d.situacao].rotulo,
                responsavel: d.responsavel ?? "",
              })),
            )
          }
        >
          Exportar
        </Button>
      </div>

      {lista.isError ? (
        <EstadoErro erro={lista.error} onTentar={() => lista.refetch()} />
      ) : lista.data && lista.data.length === 0 ? (
        <EstadoVazio
          icone={FileText}
          titulo={busca || situacao || tipo !== TODOS ? "Nenhum documento com esse filtro" : "Nenhum documento cadastrado"}
          texto="Os documentos do SESMO entram aqui quando a extração deles terminar. Até lá, cadastre os que estão vigentes para receber o aviso de renovação."
        />
      ) : (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Empresa</TableHead>
                <TableHead>Documento</TableHead>
                <TableHead>Vigência</TableHead>
                <TableHead>Situação</TableHead>
                <TableHead className="hidden lg:table-cell">Responsável técnico</TableHead>
                <TableHead className="text-right">
                  <span className="sr-only">Ações</span>
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {lista.isLoading &&
                Array.from({ length: 5 }).map((_, i) => (
                  <TableRow key={i}>
                    {Array.from({ length: 6 }).map((__, j) => (
                      <TableCell key={j}>
                        <Skeleton className="h-4 w-full" />
                      </TableCell>
                    ))}
                  </TableRow>
                ))}
              {lista.data?.map((d) => (
                <TableRow key={d.id}>
                  <TableCell>
                    <Link to={`/clientes/${d.empresa_id}`} className="font-medium hover:underline">
                      {d.empresa}
                    </Link>
                    {d.cnpj && <span className="block text-xs text-muted-foreground">{fmtCnpj(d.cnpj)}</span>}
                  </TableCell>
                  <TableCell>
                    <span className="font-medium">{d.tipo}</span>
                    {d.versao && <span className="text-muted-foreground"> · v{d.versao}</span>}
                    {d.arquivo_path && (
                      <button type="button" onClick={() => abrirArquivo(d.arquivo_path!)} className="ml-2 inline-flex items-center gap-1 text-xs text-primary hover:underline">
                        <Paperclip className="h-3 w-3" aria-hidden /> arquivo
                      </button>
                    )}
                  </TableCell>
                  <TableCell>
                    <span className={cn("tabular-nums", d.situacao === "vencido" && "font-medium text-destructive", d.situacao === "a_vencer" && "font-medium text-warning")}>
                      {d.vigencia_fim ? `até ${fmtData(d.vigencia_fim)}` : "—"}
                    </span>
                    {d.dias_para_vencer != null && (d.situacao === "a_vencer" || d.situacao === "vencido") && (
                      <span className="block text-xs">{d.dias_para_vencer < 0 ? `venceu há ${-d.dias_para_vencer} dias` : `em ${d.dias_para_vencer} dias`}</span>
                    )}
                  </TableCell>
                  <TableCell>
                    <div className="flex flex-wrap items-center gap-1.5">
                      <Badge variant={situacaoDocumento[d.situacao].badge}>{situacaoDocumento[d.situacao].rotulo}</Badge>
                      {d.renovacao_negocio_id && (
                        <Link to={`/crm?funil=laudos&negocio=${d.renovacao_negocio_id}`} title="Card de renovação no funil Laudos" className="text-primary">
                          <RefreshCcw className="h-3.5 w-3.5" aria-label="Card de renovação" />
                        </Link>
                      )}
                    </div>
                  </TableCell>
                  <TableCell className="hidden lg:table-cell">{d.responsavel ?? <span className="text-muted-foreground">—</span>}</TableCell>
                  <TableCell className="text-right">
                    {pode && (
                      <Button size="sm" variant="ghost" onClick={() => setEditar({ aberto: true, d })}>
                        Editar
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Card>
      )}

      <DocumentoDialog aberto={editar.aberto} d={editar.d} onFechar={() => setEditar({ aberto: false, d: null })} />
    </div>
  );
}

function DocumentoDialog({ aberto, d, onFechar }: { aberto: boolean; d: DocumentoLinha | null; onFechar: () => void }) {
  const salvar = useSalvarDocumento();
  const profs = useProfissionais();
  const ref = useRef<HTMLInputElement>(null);
  const [empresa, setEmpresa] = useState<EmpresaEscolhida | null>(null);
  const [arquivo, setArquivo] = useState<File | null>(null);
  const vazio = { tipo: "PGR", versao: "", data_elaboracao: "", vigencia_inicio: "", vigencia_fim: "", situacao: "vigente", responsavel_id: NINGUEM, observacao: "" };
  const [f, setF] = useState(vazio);
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF((x) => ({ ...x, [k]: e.target.value }));

  function preencher() {
    setArquivo(null);
    if (d) {
      setEmpresa({ id: d.empresa_id, nome: d.empresa, cnpj: d.cnpj });
      setF({
        tipo: d.tipo,
        versao: d.versao ?? "",
        data_elaboracao: d.data_elaboracao ?? "",
        vigencia_inicio: d.vigencia_inicio ?? "",
        vigencia_fim: d.vigencia_fim ?? "",
        situacao: d.situacao_cadastro,
        responsavel_id: d.responsavel_id ?? NINGUEM,
        observacao: d.observacao ?? "",
      });
    } else {
      setEmpresa(null);
      setF(vazio);
    }
  }

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-lg" onOpenAutoFocus={preencher}>
        <DialogHeader>
          <DialogTitle>{d ? `${d.tipo} · ${d.empresa}` : "Novo documento técnico"}</DialogTitle>
          <DialogDescription>Renovou? Atualize o fim da vigência: o aviso volta a contar a partir da nova data.</DialogDescription>
        </DialogHeader>
        <form
          className="grid gap-4 sm:grid-cols-2"
          onSubmit={(e) => {
            e.preventDefault();
            salvar
              .mutateAsync({
                id: d?.id ?? null,
                dados: {
                  empresa_id: empresa?.id,
                  tipo: f.tipo,
                  versao: f.versao,
                  data_elaboracao: f.data_elaboracao || null,
                  vigencia_inicio: f.vigencia_inicio || null,
                  vigencia_fim: f.vigencia_fim || null,
                  situacao: f.situacao,
                  responsavel_id: f.responsavel_id === NINGUEM ? null : f.responsavel_id,
                  observacao: f.observacao,
                },
                arquivo,
                caminhoAtual: d?.arquivo_path ?? null,
              })
              .then(onFechar)
              .catch(() => null);
          }}
        >
          {!d && (
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="doc-empresa">Empresa</Label>
              <EmpresaSelect id="doc-empresa" valor={empresa} onChange={setEmpresa} />
            </div>
          )}
          <div className="space-y-1.5">
            <Label>Tipo</Label>
            <Select value={f.tipo} onValueChange={(v) => setF((x) => ({ ...x, tipo: v }))}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {TIPOS_DOCUMENTO.map((t) => (
                  <SelectItem key={t} value={t}>
                    {t === "OUTRO" ? "Outro" : t}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="doc-versao">Versão / revisão</Label>
            <Input id="doc-versao" value={f.versao} onChange={set("versao")} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="doc-ini">Início da vigência</Label>
            <Input id="doc-ini" type="date" value={f.vigencia_inicio} onChange={set("vigencia_inicio")} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="doc-fim">Fim da vigência</Label>
            <Input id="doc-fim" type="date" value={f.vigencia_fim} onChange={set("vigencia_fim")} />
          </div>
          <div className="space-y-1.5">
            <Label>Situação</Label>
            <Select value={f.situacao} onValueChange={(v) => setF((x) => ({ ...x, situacao: v }))}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="em_elaboracao">Em elaboração</SelectItem>
                <SelectItem value="vigente">Vigente</SelectItem>
                <SelectItem value="cancelado">Cancelado</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="doc-elab">Elaborado em</Label>
            <Input id="doc-elab" type="date" value={f.data_elaboracao} onChange={set("data_elaboracao")} />
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <Label>Responsável técnico</Label>
            <Select value={f.responsavel_id} onValueChange={(v) => setF((x) => ({ ...x, responsavel_id: v }))}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={NINGUEM}>Não informado</SelectItem>
                {profs.data?.map((p) => (
                  <SelectItem key={p.id} value={p.id}>
                    {p.nome}
                    {p.conselho && p.registro ? ` · ${p.conselho} ${p.registro}` : ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="doc-obs">Observação</Label>
            <Textarea id="doc-obs" rows={2} value={f.observacao} onChange={set("observacao")} />
          </div>
          <div className="flex flex-wrap items-center gap-2 sm:col-span-2">
            <input ref={ref} type="file" accept=".pdf,.doc,.docx,application/pdf" className="hidden" onChange={(e) => setArquivo(e.target.files?.[0] ?? null)} />
            <Button type="button" variant="outline" size="sm" onClick={() => ref.current?.click()}>
              <Upload /> {d?.arquivo_path ? "Trocar arquivo" : "Anexar arquivo"}
            </Button>
            <span className="truncate text-xs text-muted-foreground">{arquivo?.name ?? (d?.arquivo_path ? "Já tem arquivo anexado" : "PDF ou Word, até 25 MB")}</span>
          </div>
          <DialogFooter className="sm:col-span-2">
            <Button type="button" variant="outline" onClick={onFechar}>
              Cancelar
            </Button>
            <Button type="submit" disabled={salvar.isPending || !empresa}>
              {salvar.isPending && <Loader2 className="animate-spin" />} Salvar
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
