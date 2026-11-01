import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { ArrowLeft, Building2, ClipboardList, FileText, KanbanSquare, Mail, MapPin, MessageCircle, Pencil, Phone, Plus, Trash2, Users } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { EstadoErro } from "@/components/ui/estados";
import { NovoNegocioDialog } from "@/components/crm/NovoNegocioDialog";
import { HistoricoBitrix } from "@/components/whatsapp/HistoricoBitrix";
import { ContatarEmpresaDialog, ListaInteracoes, type Canal } from "@/components/dados/ContatarEmpresa";
import { useSessao } from "@/contexts/sessao";
import { AtendimentoDialog, ColaboradoresAba, ContatoDialog, EmpresaDialog, UnidadeDialog } from "@/components/dados/Dialogos";
import type { ContatoEmpresa, UnidadeEmpresa } from "@/lib/tipos";
import { useCliente, useFunis, useSalvarDados } from "@/hooks/api";
import { situacaoCliente } from "@/lib/status";
import { fmtCnpj, fmtData, fmtMoeda, fmtNumero } from "@/lib/utils";

export default function Cliente() {
  const { id } = useParams();
  const q = useCliente(id);
  const { tem } = useSessao();
  const veWhats = tem("gestor", "comercial", "operacoes", "financeiro");
  const funis = useFunis();
  const comercial = funis.data?.find((f) => f.slug === "comercial");
  const [novo, setNovo] = useState(false);
  const [editarEmpresa, setEditarEmpresa] = useState(false);
  const [contato, setContato] = useState<{ c: ContatoEmpresa | null } | null>(null);
  const [unidade, setUnidade] = useState<{ u: UnidadeEmpresa | null } | null>(null);
  const [atendimento, setAtendimento] = useState<string | null>(null);
  const [contatar, setContatar] = useState<Canal | null>(null);
  const salvar = useSalvarDados();
  const navegar = useNavigate();
  const c = q.data;

  if (q.isLoading)
    return (
      <div className="mx-auto max-w-6xl space-y-4 p-4 sm:p-6">
        <Skeleton className="h-8 w-1/2" />
        <Skeleton className="h-28 w-full" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  if (q.isError || !c)
    return (
      <div className="mx-auto max-w-6xl p-4 sm:p-6">
        <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
      </div>
    );

  const s = situacaoCliente(c.situacao);
  const colaboradores = c.colaboradores_ativos;

  async function excluirContato(ct: ContatoEmpresa) {
    if (!window.confirm(`Excluir o contato ${ct.nome ?? ""}?`)) return;
    try {
      await salvar("painel_empresa_contato_excluir", { p_id: ct.id });
      toast.success("Contato excluído");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível excluir.");
    }
  }

  return (
    <div className="mx-auto max-w-6xl space-y-5 p-4 sm:p-6">
      <Link to="/clientes" className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
        <ArrowLeft className="h-4 w-4" /> Empresas
      </Link>
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="text-2xl font-semibold tracking-tight">{c.nome_fantasia || c.razao_social}</h1>
            <Badge variant={s.badge}>{s.rotulo}</Badge>
          </div>
          <p className="text-sm text-muted-foreground">
            {c.razao_social} · {fmtCnpj(c.cnpj)}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {veWhats && (
            <>
              <Button variant="outline" onClick={() => setContatar("whatsapp")}>
                <MessageCircle /> WhatsApp
              </Button>
              <Button variant="outline" onClick={() => setContatar("email")}>
                <Mail /> E-mail
              </Button>
            </>
          )}
          {c.pode_editar && (
            <Button variant="outline" onClick={() => setEditarEmpresa(true)}>
              <Pencil /> Editar dados
            </Button>
          )}
          {comercial?.pode_operar && (
            <Button onClick={() => setNovo(true)}>
              <Plus /> Novo negócio
            </Button>
          )}
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardContent className="space-y-2 pt-5 text-sm">
            {c.endereco && (
              <p className="flex gap-2">
                <MapPin className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" /> {c.endereco}
                {c.cidade && ` — ${c.cidade}/${c.uf ?? ""}`}
              </p>
            )}
            {c.telefone && (
              <p className="flex gap-2">
                <Phone className="h-4 w-4 text-muted-foreground" /> {c.telefone}
              </p>
            )}
            {c.email && (
              <p className="flex gap-2 break-all">
                <Mail className="h-4 w-4 shrink-0 text-muted-foreground" /> {c.email}
              </p>
            )}
            {c.grau_risco != null && <p className="text-muted-foreground">Grau de risco {c.grau_risco}{c.cnae_principal && ` · CNAE ${c.cnae_principal}`}</p>}
            {(c.contrato_inicio || c.contrato_fim) && (
              <p className="text-muted-foreground">
                Contrato: {fmtData(c.contrato_inicio)} a {fmtData(c.contrato_fim)}
              </p>
            )}
          </CardContent>
        </Card>
        <Card>
          <CardContent className="grid grid-cols-2 gap-4 pt-5 text-sm">
            <Numero rotulo="Unidades" valor={c.unidades.length} icone={Building2} />
            <Numero rotulo="Colaboradores ativos" valor={colaboradores} icone={Users} />
            <Numero rotulo="Negócios" valor={c.negocios.length} icone={KanbanSquare} />
            <Numero rotulo="Documentos" valor={c.documentos.length} icone={FileText} />
          </CardContent>
        </Card>
        {c.acesso_clinico && c.vencimentos ? (
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm">Exames dos colaboradores</CardTitle>
            </CardHeader>
            <CardContent className="space-y-1.5 text-sm">
              <Faixa rotulo="Vencidos" valor={c.vencimentos.vencido} variante="destructive" />
              <Faixa rotulo="Vencem em 30 dias" valor={c.vencimentos.vence_em_30_dias} variante="warning" />
              <Faixa rotulo="Vencem em 60 dias" valor={c.vencimentos.vence_em_60_dias} variante="info" />
              <Faixa rotulo="Em dia" valor={c.vencimentos.em_dia} variante="success" />
              <Button asChild variant="link" className="h-auto p-0">
                <Link to={`/vencimentos?empresa=${c.id}`}>
                  <ClipboardList /> Ver lista para o RH
                </Link>
              </Button>
            </CardContent>
          </Card>
        ) : (
          <Card>
            <CardContent className="pt-5 text-sm text-muted-foreground">Dados de exames visíveis apenas para gestão e operações.</CardContent>
          </Card>
        )}
      </div>

      <Tabs defaultValue="negocios">
        <TabsList>
          <TabsTrigger value="negocios">Negócios</TabsTrigger>
          {c.acesso_clinico && <TabsTrigger value="colaboradores">Colaboradores</TabsTrigger>}
          <TabsTrigger value="unidades">Unidades</TabsTrigger>
          <TabsTrigger value="contatos">Contatos</TabsTrigger>
          <TabsTrigger value="documentos">Documentos</TabsTrigger>
          {veWhats && <TabsTrigger value="interacoes">Contatos feitos{c.interacoes?.length ? ` (${c.interacoes.length})` : ""}</TabsTrigger>}
          {veWhats && <TabsTrigger value="whatsapp">WhatsApp (Bitrix)</TabsTrigger>}
        </TabsList>
        {veWhats && (
          <TabsContent value="interacoes">
            <Card>
              <ListaInteracoes itens={c.interacoes ?? []} />
            </Card>
          </TabsContent>
        )}
        {veWhats && id && (
          <TabsContent value="whatsapp">
            <HistoricoBitrix empresaId={id} />
          </TabsContent>
        )}
        <TabsContent value="negocios">
          <Card>
            {c.negocios.length === 0 ? (
              <p className="p-6 text-center text-sm text-muted-foreground">Nenhum negócio com esta empresa ainda.</p>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Negócio</TableHead>
                    <TableHead>Funil</TableHead>
                    <TableHead>Etapa</TableHead>
                    <TableHead className="text-right">Valor</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {c.negocios.map((n) => (
                    <TableRow key={n.id} className="cursor-pointer" onClick={() => navegar(`/crm?funil=${funis.data?.find((f) => f.nome === n.funil)?.slug ?? "comercial"}&negocio=${n.id}`)}>
                      <TableCell className="font-medium">
                        #{n.numero} {n.titulo}
                      </TableCell>
                      <TableCell>{n.funil}</TableCell>
                      <TableCell>
                        <Badge variant={n.tipo === "ganho" ? "success" : n.tipo === "perdido" ? "destructive" : "secondary"}>{n.etapa}</Badge>
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{fmtMoeda(n.valor)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </Card>
        </TabsContent>
        {c.acesso_clinico && (
          <TabsContent value="colaboradores">
            <ColaboradoresAba empresaId={c.id} unidades={c.unidades} pode={c.pode_editar} onAbrirAtendimento={setAtendimento} />
          </TabsContent>
        )}
        <TabsContent value="unidades">
          {c.pode_editar && (
            <div className="mb-2 flex justify-end">
              <Button size="sm" variant="outline" onClick={() => setUnidade({ u: null })}>
                <Plus /> Nova unidade
              </Button>
            </div>
          )}
          <Card>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Unidade</TableHead>
                  <TableHead className="hidden sm:table-cell">CNPJ</TableHead>
                  <TableHead className="hidden sm:table-cell">Cidade</TableHead>
                  <TableHead className="text-right">Setores</TableHead>
                  <TableHead className="text-right">Colaboradores</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {c.unidades.map((u) => (
                  <TableRow key={u.id} className={`${u.ativa ? "" : "opacity-60"} ${c.pode_editar ? "cursor-pointer" : ""}`} onClick={() => c.pode_editar && setUnidade({ u })}>
                    <TableCell className="font-medium">
                      {u.nome} {u.editado && <Pencil className="inline h-3 w-3 text-info" aria-label="corrigida no painel" />}
                    </TableCell>
                    <TableCell className="hidden sm:table-cell">{fmtCnpj(u.cnpj)}</TableCell>
                    <TableCell className="hidden sm:table-cell">{u.cidade ? `${u.cidade}/${u.uf ?? ""}` : "—"}</TableCell>
                    <TableCell className="text-right tabular-nums">{fmtNumero(u.setores)}</TableCell>
                    <TableCell className="text-right tabular-nums">{fmtNumero(u.colaboradores)}</TableCell>
                  </TableRow>
                ))}
                {c.unidades.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={5} className="text-center text-muted-foreground">
                      Nenhuma unidade cadastrada.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </Card>
        </TabsContent>
        <TabsContent value="contatos">
          {c.pode_editar && (
            <div className="mb-2 flex justify-end">
              <Button size="sm" variant="outline" onClick={() => setContato({ c: null })}>
                <Plus /> Novo contato
              </Button>
            </div>
          )}
          <Card>
            {c.contatos.length === 0 ? (
              <p className="p-6 text-center text-sm text-muted-foreground">Nenhum contato cadastrado.</p>
            ) : (
              <ul className="divide-y">
                {c.contatos.map((ct) => (
                  <li key={ct.id} className="flex flex-col gap-0.5 p-4 text-sm sm:flex-row sm:items-center sm:gap-4">
                    <span className="font-medium sm:w-56">{ct.nome}</span>
                    <span className="text-muted-foreground sm:w-40">{ct.cargo ?? ct.tipo ?? "—"}</span>
                    <span className="flex-1 text-muted-foreground">{[ct.telefone, ct.email].filter(Boolean).join(" · ")}</span>
                    {ct.recebe_alerta_exame && <Badge variant="info">recebe aviso de exames</Badge>}
                    {c.pode_editar && (
                      <span className="flex gap-1">
                        <Button size="icon" variant="ghost" className="h-8 w-8" aria-label={`Editar ${ct.nome ?? "contato"}`} onClick={() => setContato({ c: ct })}>
                          <Pencil />
                        </Button>
                        <Button size="icon" variant="ghost" className="h-8 w-8 text-destructive" aria-label={`Excluir ${ct.nome ?? "contato"}`} onClick={() => excluirContato(ct)}>
                          <Trash2 />
                        </Button>
                      </span>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </TabsContent>
        <TabsContent value="documentos">
          <Card>
            {c.documentos.length === 0 ? (
              <p className="p-6 text-center text-sm text-muted-foreground">Nenhum documento (PGR, PCMSO…) carregado ainda.</p>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Documento</TableHead>
                    <TableHead>Vigência</TableHead>
                    <TableHead>Situação</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {c.documentos.map((d, i) => (
                    <TableRow key={i}>
                      <TableCell className="font-medium">
                        {d.tipo} {d.versao && <span className="text-muted-foreground">v{d.versao}</span>}
                      </TableCell>
                      <TableCell>
                        {fmtData(d.vigencia_inicio)} a {fmtData(d.vigencia_fim)}
                      </TableCell>
                      <TableCell>
                        <Badge variant={d.situacao === "vigente" ? "success" : d.situacao === "vencido" ? "destructive" : "muted"}>{d.situacao}</Badge>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </Card>
        </TabsContent>
      </Tabs>

      {c.pode_editar && (
        <>
          <EmpresaDialog c={c} aberto={editarEmpresa} onFechar={() => setEditarEmpresa(false)} />
          <ContatoDialog empresaId={c.id} contato={contato?.c ?? null} aberto={!!contato} onFechar={() => setContato(null)} />
          <UnidadeDialog empresaId={c.id} unidade={unidade?.u ?? null} aberto={!!unidade} onFechar={() => setUnidade(null)} />
        </>
      )}
      <AtendimentoDialog id={atendimento} onFechar={() => setAtendimento(null)} />
      {comercial && (
        <NovoNegocioDialog
          funil={comercial}
          aberto={novo}
          onFechar={() => setNovo(false)}
          empresaInicial={{ id: c.id, nome: c.nome_fantasia || c.razao_social, cnpj: c.cnpj }}
          onCriado={(nid) => navegar(`/crm?funil=${comercial.slug}&negocio=${nid}`)}
        />
      )}
      {contatar && <ContatarEmpresaDialog empresa={c} canal={contatar} onFechar={() => setContatar(null)} />}
    </div>
  );
}

function Numero({ rotulo, valor, icone: Icone }: { rotulo: string; valor: number; icone: typeof Users }) {
  return (
    <div>
      <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
        <Icone className="h-3.5 w-3.5" /> {rotulo}
      </p>
      <p className="text-xl font-semibold tabular-nums">{fmtNumero(valor)}</p>
    </div>
  );
}

function Faixa({ rotulo, valor, variante }: { rotulo: string; valor: number; variante: "destructive" | "warning" | "info" | "success" }) {
  return (
    <div className="flex items-center justify-between">
      <span>{rotulo}</span>
      <Badge variant={variante}>{fmtNumero(valor)}</Badge>
    </div>
  );
}
