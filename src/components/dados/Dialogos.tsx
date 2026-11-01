import { useState } from "react";
import { Loader2, Pencil, Save, Search, UserPlus, Users } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { Paginacao } from "@/components/ui/paginacao";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useAtendimento, useColaborador, useColaboradores, useProfissionais, useSalvarDados } from "@/hooks/api";
import { useDebounce } from "@/hooks/useDebounce";
import { resultadoAso, situacaoAtendimento, situacaoColaborador, tipoExame } from "@/lib/status";
import type { ClienteDetalhe, ContatoEmpresa, UnidadeEmpresa } from "@/lib/tipos";
import { fmtCpf, fmtData, fmtDataHora } from "@/lib/utils";
import { AvisoTravados, Campos, FormDialog, HistoricoEdicao, valoresDe, type CampoDef, type Valores } from "./Edicao";

const UFS = "AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO".split(" ").map((u) => ({ valor: u, rotulo: u }));
const rotulos = (campos: CampoDef[]) => Object.fromEntries(campos.map((c) => [c.nome, c.rotulo]));
const opcoes = (m: Record<string, string | { rotulo: string }>) =>
  Object.entries(m).map(([valor, r]) => ({ valor, rotulo: typeof r === "string" ? r : r.rotulo }));

// ---------------------------------------------------------------- empresa

const CAMPOS_EMPRESA: CampoDef[] = [
  { nome: "razao_social", rotulo: "Razão social", largo: true, obrigatorio: true },
  { nome: "nome_fantasia", rotulo: "Nome fantasia" },
  { nome: "cnpj", rotulo: "CNPJ", placeholder: "00.000.000/0000-00" },
  {
    nome: "situacao",
    rotulo: "Situação",
    tipo: "select",
    opcoes: [
      { valor: "ativo", rotulo: "Ativo" },
      { valor: "sem_contrato", rotulo: "Sem contrato" },
      { valor: "inativo", rotulo: "Inativo" },
    ],
  },
  { nome: "grau_risco", rotulo: "Grau de risco", tipo: "select", opcoes: ["1", "2", "3", "4"].map((g) => ({ valor: g, rotulo: g })) },
  { nome: "cnae_principal", rotulo: "CNAE principal" },
  { nome: "telefone", rotulo: "Telefone" },
  { nome: "email", rotulo: "E-mail", tipo: "email" },
  { nome: "cep", rotulo: "CEP" },
  { nome: "logradouro", rotulo: "Logradouro" },
  { nome: "numero", rotulo: "Número" },
  { nome: "complemento", rotulo: "Complemento" },
  { nome: "bairro", rotulo: "Bairro" },
  { nome: "cidade", rotulo: "Cidade" },
  { nome: "uf", rotulo: "UF", tipo: "select", opcoes: UFS },
  { nome: "contrato_inicio", rotulo: "Início do contrato", tipo: "data" },
  { nome: "contrato_fim", rotulo: "Fim do contrato", tipo: "data" },
];
export const ROTULOS_EMPRESA = rotulos(CAMPOS_EMPRESA);

export function EmpresaDialog({ c, aberto, onFechar }: { c: ClienteDetalhe; aberto: boolean; onFechar: () => void }) {
  const salvar = useSalvarDados();
  const inicial = valoresDe(CAMPOS_EMPRESA, { ...c, situacao: c.situacao === "a_confirmar" ? null : c.situacao });
  return (
    <FormDialog
      titulo="Editar dados da empresa"
      descricao="O que você corrigir aqui fica valendo no painel: a atualização do SESMO não sobrescreve os campos alterados."
      campos={CAMPOS_EMPRESA}
      inicial={inicial}
      aberto={aberto}
      onFechar={onFechar}
      onSalvar={(d) => salvar("painel_empresa_salvar", { p_id: c.id, p_dados: d })}
      rodape={
        <>
          <AvisoTravados
            campos={c.campos_editados}
            rotulos={ROTULOS_EMPRESA}
            onLiberar={() => salvar("painel_edicao_liberar", { p_tabela: "empresa", p_id: c.id })}
          />
          <HistoricoEdicao itens={c.historico} rotulos={ROTULOS_EMPRESA} />
        </>
      }
    />
  );
}

// ---------------------------------------------------------------- contatos

const CAMPOS_CONTATO: CampoDef[] = [
  { nome: "nome", rotulo: "Nome", obrigatorio: true },
  { nome: "cargo", rotulo: "Cargo" },
  { nome: "telefone", rotulo: "Telefone" },
  { nome: "email", rotulo: "E-mail", tipo: "email" },
  { nome: "tipo", rotulo: "Tipo", tipo: "select", opcoes: ["RH", "Financeiro", "Segurança do trabalho", "Diretoria", "Outro"].map((t) => ({ valor: t, rotulo: t })) },
  { nome: "recebe_alerta_exame", rotulo: "Recebe aviso de exames a vencer", tipo: "checkbox", largo: true },
];

export function ContatoDialog({ empresaId, contato, aberto, onFechar }: { empresaId: string; contato: ContatoEmpresa | null; aberto: boolean; onFechar: () => void }) {
  const salvar = useSalvarDados();
  return (
    <FormDialog
      titulo={contato ? "Editar contato" : "Novo contato"}
      campos={CAMPOS_CONTATO}
      inicial={valoresDe(CAMPOS_CONTATO, (contato ?? {}) as Record<string, unknown>)}
      aberto={aberto}
      onFechar={onFechar}
      largura="max-w-lg"
      onSalvar={(d, todos) => salvar("painel_empresa_contato_salvar", { p_empresa: empresaId, p_id: contato?.id ?? null, p_dados: contato ? d : todos })}
    />
  );
}

// ---------------------------------------------------------------- unidades

const CAMPOS_UNIDADE: CampoDef[] = [
  { nome: "nome", rotulo: "Nome da unidade", largo: true, obrigatorio: true },
  { nome: "cnpj", rotulo: "CNPJ" },
  { nome: "cnae", rotulo: "CNAE" },
  { nome: "grau_risco", rotulo: "Grau de risco", tipo: "select", opcoes: ["1", "2", "3", "4"].map((g) => ({ valor: g, rotulo: g })) },
  { nome: "cidade", rotulo: "Cidade" },
  { nome: "uf", rotulo: "UF", tipo: "select", opcoes: UFS },
  { nome: "endereco", rotulo: "Endereço", largo: true },
  { nome: "is_matriz", rotulo: "É a matriz", tipo: "checkbox" },
  { nome: "ativa", rotulo: "Unidade ativa", tipo: "checkbox" },
];

export function UnidadeDialog({ empresaId, unidade, aberto, onFechar }: { empresaId: string; unidade: UnidadeEmpresa | null; aberto: boolean; onFechar: () => void }) {
  const salvar = useSalvarDados();
  return (
    <FormDialog
      titulo={unidade ? "Editar unidade" : "Nova unidade"}
      campos={CAMPOS_UNIDADE}
      inicial={valoresDe(CAMPOS_UNIDADE, (unidade ?? { ativa: true }) as Record<string, unknown>)}
      aberto={aberto}
      onFechar={onFechar}
      largura="max-w-lg"
      onSalvar={(d, todos) => salvar("painel_unidade_salvar", { p_empresa: empresaId, p_id: unidade?.id ?? null, p_dados: unidade ? d : todos })}
      rodape={
        unidade ? (
          <AvisoTravados
            campos={unidade.campos_editados}
            rotulos={rotulos(CAMPOS_UNIDADE)}
            onLiberar={() => salvar("painel_edicao_liberar", { p_tabela: "unidade", p_id: unidade.id })}
          />
        ) : null
      }
    />
  );
}

// ---------------------------------------------------------------- colaboradores

function camposColaborador(unidades: UnidadeEmpresa[]): CampoDef[] {
  return [
    { nome: "nome", rotulo: "Nome", largo: true, obrigatorio: true },
    { nome: "nome_social", rotulo: "Nome social" },
    { nome: "cpf", rotulo: "CPF", placeholder: "000.000.000-00" },
    { nome: "situacao", rotulo: "Situação", tipo: "select", opcoes: opcoes(situacaoColaborador), obrigatorio: true },
    { nome: "unidade_id", rotulo: "Unidade", tipo: "select", opcoes: unidades.map((u) => ({ valor: u.id, rotulo: u.ativa ? u.nome : `${u.nome} (inativa)` })) },
    { nome: "data_admissao", rotulo: "Admissão", tipo: "data" },
    { nome: "data_demissao", rotulo: "Demissão", tipo: "data" },
    { nome: "data_nascimento", rotulo: "Nascimento", tipo: "data" },
    { nome: "sexo", rotulo: "Sexo", tipo: "select", opcoes: [{ valor: "M", rotulo: "Masculino" }, { valor: "F", rotulo: "Feminino" }] },
    { nome: "matricula_esocial", rotulo: "Matrícula eSocial" },
    { nome: "pis", rotulo: "PIS" },
    { nome: "rg", rotulo: "RG" },
    { nome: "rg_orgao_emissor", rotulo: "Órgão emissor" },
    { nome: "ctps", rotulo: "CTPS" },
    { nome: "nome_mae", rotulo: "Nome da mãe" },
    { nome: "telefone", rotulo: "Telefone" },
    { nome: "email", rotulo: "E-mail", tipo: "email" },
  ];
}

/** Ficha do colaborador: dados, atendimentos e (admin/gestor) edição. id = null com empresa = novo colaborador. */
export function ColaboradorDialog({
  id,
  empresaId,
  unidades,
  aberto,
  onFechar,
  onAbrirAtendimento,
}: {
  id: string | null;
  empresaId: string;
  unidades: UnidadeEmpresa[];
  aberto: boolean;
  onFechar: () => void;
  onAbrirAtendimento: (id: string) => void;
}) {
  const q = useColaborador(aberto ? id : null);
  const salvar = useSalvarDados();
  const campos = camposColaborador(unidades);
  const rot = rotulos(campos);

  if (!id)
    return (
      <FormDialog
        titulo="Novo colaborador"
        descricao="Cadastro feito no painel. Se o mesmo colaborador vier depois do SESMO, confira para não duplicar."
        campos={campos}
        inicial={valoresDe(campos, { situacao: "ativo" })}
        aberto={aberto}
        onFechar={onFechar}
        onSalvar={(_, todos) => salvar("painel_colaborador_salvar", { p_id: null, p_empresa: empresaId, p_dados: todos })}
      />
    );

  const c = q.data;
  return (
    <FichaDialog
      aberto={aberto}
      onFechar={onFechar}
      titulo={c?.nome ?? "Colaborador"}
      subtitulo={
        c
          ? `${c.empresa}${c.cpf ? ` · CPF ${fmtCpf(c.cpf)}` : ""} · ${c.setor_nome ?? "Setor não informado"} / ${c.funcao_nome ?? "Função não informada"}${c.sesmo_id ? ` · SESMO ${c.sesmo_id}` : " · cadastrado no painel"}`
          : ""
      }
      carregando={q.isLoading}
      erro={q.isError ? q.error : null}
      pode={!!c?.pode_editar}
      campos={campos}
      inicial={c ? valoresDe(campos, c as unknown as Record<string, unknown>) : {}}
      onSalvar={(d) => salvar("painel_colaborador_salvar", { p_id: id, p_empresa: null, p_dados: d })}
      extra={
        c && (
          <>
            <AvisoTravados campos={c.campos_editados} rotulos={rot} onLiberar={c.pode_editar ? () => salvar("painel_edicao_liberar", { p_tabela: "colaborador", p_id: id }) : undefined} />
            <div className="space-y-1.5">
              <p className="text-sm font-medium">Atendimentos ({c.atendimentos.length})</p>
              {c.atendimentos.length === 0 ? (
                <p className="text-sm text-muted-foreground">Nenhum atendimento registrado.</p>
              ) : (
                <ul className="max-h-48 divide-y overflow-y-auto rounded-md border text-sm">
                  {c.atendimentos.map((a) => (
                    <li key={a.id}>
                      <button type="button" className="flex w-full items-center gap-3 px-3 py-2 text-left hover:bg-accent" onClick={() => onAbrirAtendimento(a.id)}>
                        <span className="w-24 tabular-nums">{fmtData(a.data)}</span>
                        <span className="flex-1">{tipoExame[a.tipo] ?? a.tipo}</span>
                        <Badge variant={situacaoAtendimento(a.situacao).badge}>{situacaoAtendimento(a.situacao).rotulo}</Badge>
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </div>
            <HistoricoEdicao itens={c.historico} rotulos={rot} />
          </>
        )
      }
    />
  );
}

/** Aba Colaboradores da empresa: busca, filtro e ficha. */
export function ColaboradoresAba({ empresaId, unidades, pode, onAbrirAtendimento }: { empresaId: string; unidades: UnidadeEmpresa[]; pode: boolean; onAbrirAtendimento: (id: string) => void }) {
  const [texto, setTexto] = useState("");
  const busca = useDebounce(texto.trim());
  const [situacao, setSituacao] = useState("ativo");
  const [pagina, setPagina] = useState(0);
  const [aberto, setAberto] = useState<{ id: string | null } | null>(null);
  const q = useColaboradores({ empresa: empresaId, busca, situacao: situacao === "todas" ? null : situacao, pagina });
  const total = q.data?.[0]?.total ?? 0;

  return (
    <div className="space-y-3">
      <div className="flex flex-col gap-2 sm:flex-row">
        <div className="relative flex-1">
          <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
          <Input className="pl-8" placeholder="Nome ou CPF" aria-label="Buscar colaborador" value={texto} onChange={(e) => { setTexto(e.target.value); setPagina(0); }} />
        </div>
        <Select value={situacao} onValueChange={(v) => { setSituacao(v); setPagina(0); }}>
          <SelectTrigger className="sm:w-44" aria-label="Situação">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="todas">Todas as situações</SelectItem>
            {opcoes(situacaoColaborador).map((o) => (
              <SelectItem key={o.valor} value={o.valor}>
                {o.rotulo}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        {pode && (
          <Button onClick={() => setAberto({ id: null })}>
            <UserPlus /> Novo colaborador
          </Button>
        )}
      </div>
      {q.isError ? (
        <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
      ) : q.data && q.data.length === 0 ? (
        <EstadoVazio icone={Users} titulo="Nenhum colaborador encontrado" texto="Mude a situação para “Todas” ou confira a busca." />
      ) : (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead className="hidden md:table-cell">Unidade</TableHead>
                <TableHead className="hidden sm:table-cell">Admissão</TableHead>
                <TableHead className="hidden lg:table-cell">Último atendimento</TableHead>
                <TableHead>Situação</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {q.isLoading &&
                Array.from({ length: 6 }).map((_, i) => (
                  <TableRow key={i}>
                    <TableCell colSpan={5}>
                      <Skeleton className="h-5 w-full" />
                    </TableCell>
                  </TableRow>
                ))}
              {q.data?.map((l) => {
                const s = situacaoColaborador[l.situacao] ?? { rotulo: l.situacao, badge: "muted" as const };
                return (
                  <TableRow key={l.id} className="cursor-pointer" onClick={() => setAberto({ id: l.id })}>
                    <TableCell>
                      <p className="font-medium">
                        {l.nome} {l.editado && <Pencil className="inline h-3 w-3 text-info" aria-label="corrigido no painel" />}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {l.cpf ? fmtCpf(l.cpf) : "sem CPF"} · {l.funcao ?? "Função não informada"}
                      </p>
                    </TableCell>
                    <TableCell className="hidden md:table-cell">
                      <p>{l.unidade ?? "—"}</p>
                      <p className="text-xs text-muted-foreground">{l.setor ?? "Setor não informado"}</p>
                    </TableCell>
                    <TableCell className="hidden sm:table-cell">{fmtData(l.data_admissao)}</TableCell>
                    <TableCell className="hidden lg:table-cell">{fmtData(l.ultimo_atendimento)}</TableCell>
                    <TableCell>
                      <Badge variant={s.badge}>{s.rotulo}</Badge>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </Card>
      )}
      <Paginacao pagina={pagina} porPagina={50} total={total} onMudar={setPagina} />
      <ColaboradorDialog
        id={aberto?.id ?? null}
        empresaId={empresaId}
        unidades={unidades}
        aberto={!!aberto}
        onFechar={() => setAberto(null)}
        onAbrirAtendimento={onAbrirAtendimento}
      />
    </div>
  );
}

// ---------------------------------------------------------------- atendimentos

export function AtendimentoDialog({ id, onFechar }: { id: string | null; onFechar: () => void }) {
  const q = useAtendimento(id);
  const prof = useProfissionais();
  const salvar = useSalvarDados();
  const campos: CampoDef[] = [
    { nome: "data_atendimento", rotulo: "Data", tipo: "data", obrigatorio: true },
    { nome: "hora", rotulo: "Hora", tipo: "hora" },
    { nome: "tipo", rotulo: "Tipo de exame", tipo: "select", opcoes: opcoes(tipoExame).filter((o) => o.valor !== "outro"), obrigatorio: true },
    { nome: "situacao", rotulo: "Situação", tipo: "select", obrigatorio: true, opcoes: ["agendado", "aguardando", "atendido", "finalizado", "cancelado", "faltou"].map((s) => ({ valor: s, rotulo: situacaoAtendimento(s).rotulo })) },
    { nome: "profissional_id", rotulo: "Médico / profissional", tipo: "select", opcoes: (prof.data ?? []).map((p) => ({ valor: p.id, rotulo: p.ativo ? p.nome : `${p.nome} (inativo)` })) },
    { nome: "aso_resultado", rotulo: "Resultado do ASO", tipo: "select", opcoes: opcoes(resultadoAso), obrigatorio: true },
    { nome: "aso_emitido_em", rotulo: "ASO emitido em", tipo: "data" },
    { nome: "local_atendimento", rotulo: "Local" },
    { nome: "observacao", rotulo: "Observação", tipo: "textarea" },
  ];
  const rot = { ...rotulos(campos), data_agendada: "Data e hora" };
  const a = q.data;
  return (
    <FichaDialog
      aberto={!!id}
      onFechar={onFechar}
      titulo={a ? `Atendimento de ${a.colaborador}` : "Atendimento"}
      subtitulo={a ? `${a.empresa}${a.funcao ? ` · ${a.funcao}` : ""}${a.sesmo_id ? ` · SESMO ${a.sesmo_id}` : ""}` : ""}
      carregando={q.isLoading}
      erro={q.isError ? q.error : null}
      pode={!!a?.pode_editar}
      campos={campos}
      inicial={a ? valoresDe(campos, a as unknown as Record<string, unknown>) : {}}
      onSalvar={(d, todos) =>
        // data e hora andam juntas: mudou uma, vão as duas
        salvar("painel_atendimento_salvar", {
          p_id: id,
          p_dados: "data_atendimento" in d || "hora" in d ? { ...d, data_atendimento: todos.data_atendimento, hora: todos.hora } : d,
        })
      }
      extra={
        a && (
          <>
            <AvisoTravados campos={a.campos_editados} rotulos={rot} onLiberar={a.pode_editar ? () => salvar("painel_edicao_liberar", { p_tabela: "atendimento", p_id: a.id }) : undefined} />
            {a.exames.length > 0 && (
              <div className="text-sm">
                <p className="font-medium">Exames complementares</p>
                <ul className="mt-1 list-inside list-disc text-muted-foreground">
                  {a.exames.map((e, i) => (
                    <li key={i}>
                      {e.nome} {e.data && `· ${fmtData(e.data)}`}
                    </li>
                  ))}
                </ul>
              </div>
            )}
            <p className="text-xs text-muted-foreground">Agendado para {fmtDataHora(a.data_agendada)}</p>
            <HistoricoEdicao itens={a.historico} rotulos={rot} />
          </>
        )
      }
    />
  );
}

// ---------------------------------------------------------------- ficha genérica (ver e, se puder, editar)

function FichaDialog({
  aberto,
  onFechar,
  titulo,
  subtitulo,
  carregando,
  erro,
  pode,
  campos,
  inicial,
  onSalvar,
  extra,
}: {
  aberto: boolean;
  onFechar: () => void;
  titulo: string;
  subtitulo: string;
  carregando: boolean;
  erro: unknown;
  pode: boolean;
  campos: CampoDef[];
  inicial: Valores;
  onSalvar: (mudou: Valores, todos: Valores) => Promise<unknown>;
  extra?: React.ReactNode;
}) {
  const [editando, setEditando] = useState(false);
  const [v, setV] = useState<Valores>({});
  const [salvando, setSalvando] = useState(false);

  function fechar() {
    setEditando(false);
    onFechar();
  }

  async function salvar() {
    const faltando = campos.filter((c) => c.obrigatorio && !v[c.nome]).map((c) => c.rotulo);
    if (faltando.length) return toast.error(`Preencha: ${faltando.join(", ")}.`);
    const mudou = Object.fromEntries(Object.entries(v).filter(([k, x]) => x !== inicial[k]));
    if (Object.keys(mudou).length === 0) return setEditando(false);
    setSalvando(true);
    try {
      await onSalvar(mudou, v);
      toast.success("Alterações salvas");
      setEditando(false);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível salvar.");
    } finally {
      setSalvando(false);
    }
  }

  return (
    <Dialog open={aberto} onOpenChange={(x) => !x && fechar()}>
      <DialogContent className="max-h-[92vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{titulo}</DialogTitle>
          <DialogDescription>{subtitulo}</DialogDescription>
        </DialogHeader>
        {erro ? (
          <EstadoErro erro={erro} />
        ) : carregando ? (
          <div className="space-y-3">
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-24 w-full" />
          </div>
        ) : (
          <div className="space-y-4">
            <Campos campos={campos} valores={editando ? v : inicial} onMudar={setV} desabilitado={!editando} />
            {extra}
          </div>
        )}
        <DialogFooter>
          {editando ? (
            <>
              <Button variant="outline" onClick={() => setEditando(false)}>
                Cancelar
              </Button>
              <Button onClick={salvar} disabled={salvando}>
                {salvando ? <Loader2 className="animate-spin" /> : <Save />} Salvar
              </Button>
            </>
          ) : (
            <>
              <Button variant="outline" onClick={fechar}>
                Fechar
              </Button>
              {pode && !carregando && !erro && (
                <Button
                  onClick={() => {
                    setV(inicial);
                    setEditando(true);
                  }}
                >
                  <Pencil /> Editar
                </Button>
              )}
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
