import { useState } from "react";
import { Loader2, Pencil, Plus, Trash2, UserCheck, Users } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { Button } from "@/components/ui/button";
import { useLiberaAgenda, useUsuarioEncaixe, useUsuariosEncaixe, usePreCadastroExcluir, usePreCadastroSalvar, usePreCadastros, useSalvarUsuario, useTelefoneUsuario, useUsuarioAdmin, useUsuarios } from "@/hooks/api";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useSessao } from "@/contexts/sessao";
import { PAPEIS, type Papel } from "@/lib/tipos";
import { tempoRelativo } from "@/lib/utils";

const fmtTelefone = (t: string) => {
  const d = t.replace(/\D/g, "").replace(/^55(?=\d{10,11}$)/, "");
  return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : d.length === 10 ? `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}` : t;
};

export default function Usuarios() {
  const q = useUsuarios();
  const salvar = useSalvarUsuario();
  const agenda = useLiberaAgenda();
  const encaixes = useUsuariosEncaixe();
  const encaixe = useUsuarioEncaixe();
  const telefone = useTelefoneUsuario();
  const { perfil } = useSessao();
  const adminAcao = useUsuarioAdmin();
  const [editar, setEditar] = useState<{ user_id: string; nome: string; email: string; papel: string; ativo: boolean } | null>(null);
  const pendentes = q.data?.filter((u) => !u.ativo).length ?? 0;

  return (
    <div className="mx-auto max-w-5xl space-y-5 p-4 sm:p-6">
      <Cabecalho
        titulo="Usuários"
        descricao="Quem cria conta no painel fica aguardando. Aqui você libera o acesso e define o perfil."
        selo={pendentes ? `${pendentes} aguardando` : undefined}
      />
      <div className="grid gap-2 text-sm sm:grid-cols-2 lg:grid-cols-3">
        {PAPEIS.map((p) => (
          <div key={p.valor} className="rounded-md border bg-card p-3">
            <p className="font-medium">{p.rotulo}</p>
            <p className="text-xs text-muted-foreground">{p.descricao}</p>
          </div>
        ))}
      </div>
      {q.isError ? (
        <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
      ) : q.data && q.data.length === 0 ? (
        <EstadoVazio icone={Users} titulo="Nenhum usuário" />
      ) : (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Pessoa</TableHead>
                <TableHead>Perfil</TableHead>
                <TableHead>Acesso</TableHead>
                <TableHead className="hidden sm:table-cell">WhatsApp</TableHead>
                <TableHead className="hidden sm:table-cell">Libera agenda</TableHead>
                <TableHead className="hidden sm:table-cell">Encaixe</TableHead>
                <TableHead className="hidden md:table-cell">Último acesso</TableHead>
                <TableHead className="w-20 text-right">
                  <span className="sr-only">Ações</span>
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {q.isLoading &&
                Array.from({ length: 4 }).map((_, i) => (
                  <TableRow key={i}>
                    <TableCell colSpan={8}>
                      <Skeleton className="h-5 w-full" />
                    </TableCell>
                  </TableRow>
                ))}
              {q.data?.map((u) => {
                const eu = u.user_id === perfil?.user_id;
                return (
                  <TableRow key={u.user_id}>
                    <TableCell>
                      <p className="font-medium">
                        {u.nome} {eu && <Badge variant="muted">você</Badge>}
                      </p>
                      <p className="text-xs text-muted-foreground">{u.email}</p>
                    </TableCell>
                    <TableCell className="w-48">
                      <Select value={u.papel} disabled={eu || salvar.isPending} onValueChange={(v) => salvar.mutate({ user_id: u.user_id, papel: v, ativo: u.ativo })}>
                        <SelectTrigger aria-label={`Perfil de ${u.nome}`}>
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {PAPEIS.map((p) => (
                            <SelectItem key={p.valor} value={p.valor}>
                              {p.rotulo}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </TableCell>
                    <TableCell>
                      {u.ativo ? (
                        <Button size="sm" variant="outline" disabled={eu || salvar.isPending} onClick={() => salvar.mutate({ user_id: u.user_id, papel: u.papel, ativo: false })}>
                          Bloquear
                        </Button>
                      ) : (
                        <Button size="sm" variant="marca" disabled={salvar.isPending} onClick={() => salvar.mutate({ user_id: u.user_id, papel: u.papel, ativo: true })}>
                          Liberar acesso
                        </Button>
                      )}
                    </TableCell>
                    <TableCell className="hidden w-44 sm:table-cell">
                      <Input
                        key={u.telefone ?? "vazio"}
                        defaultValue={u.telefone ? fmtTelefone(u.telefone) : ""}
                        placeholder="(11) 99697-1631"
                        inputMode="tel"
                        aria-label={`WhatsApp de ${u.nome}`}
                        title="Recebe os avisos do painel pelo WhatsApp (ex.: alerta de atestados)"
                        className="h-8"
                        onBlur={(e) => {
                          const v = e.target.value.replace(/\D/g, "");
                          if (v !== (u.telefone ?? "").replace(/^55/, "") && v !== (u.telefone ?? "")) telefone.mutate({ user_id: u.user_id, telefone: e.target.value });
                        }}
                      />
                    </TableCell>
                    <TableCell className="hidden sm:table-cell">
                      <input
                        type="checkbox"
                        className="h-4 w-4 accent-[hsl(var(--primary))]"
                        aria-label={`${u.nome} libera exceções da agenda`}
                        title="Pode agendar acima do limite, em agenda lotada ou para inadimplente, com motivo"
                        checked={u.libera_agenda || u.papel === "admin"}
                        disabled={u.papel === "admin" || agenda.isPending}
                        onChange={(e) => agenda.mutate({ user_id: u.user_id, libera: e.target.checked })}
                      />
                    </TableCell>
                    <TableCell className="hidden sm:table-cell">
                      <input
                        type="checkbox"
                        className="h-4 w-4 accent-[hsl(var(--primary))]"
                        aria-label={`${u.nome} agenda encaixe`}
                        title="Pode agendar encaixe, acima das vagas da grade (atendimento)"
                        checked={u.papel === "admin" || (encaixes.data ?? []).includes(u.user_id)}
                        disabled={u.papel === "admin" || encaixe.isPending || !encaixes.data}
                        onChange={(e) => encaixe.mutate({ user_id: u.user_id, pode: e.target.checked })}
                      />
                    </TableCell>
                    <TableCell className="hidden text-muted-foreground md:table-cell">{u.ultimo_acesso ? tempoRelativo(u.ultimo_acesso) : "nunca entrou"}</TableCell>
                    <TableCell className="text-right">
                      {!eu && (
                        <div className="flex justify-end gap-0.5">
                          <Button size="icon" variant="ghost" className="h-8 w-8" aria-label={`Editar ${u.nome}`} title="Editar nome e e-mail" onClick={() => setEditar({ user_id: u.user_id, nome: u.nome, email: u.email, papel: u.papel, ativo: u.ativo })}>
                            <Pencil className="h-4 w-4" />
                          </Button>
                          <Button
                            size="icon"
                            variant="ghost"
                            className="h-8 w-8 text-muted-foreground hover:text-destructive"
                            aria-label={`Excluir ${u.nome}`}
                            title="Excluir conta (só conta sem histórico; com histórico, use Bloquear)"
                            disabled={adminAcao.isPending}
                            onClick={() => {
                              if (window.confirm(`Excluir a conta de ${u.nome} (${u.email})? Não dá para desfazer.`)) adminAcao.mutate({ acao: "excluir", user_id: u.user_id });
                            }}
                          >
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        </div>
                      )}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </Card>
      )}
      <EditarUsuarioDialog alvo={editar} onFechar={() => setEditar(null)} />
      <PreCadastros />
    </div>
  );
}

/** E-mails combinados com a Vitalis: quem se cadastra com eles entra com o perfil certo ao confirmar o e-mail. */
function PreCadastros() {
  const q = usePreCadastros();
  const excluir = usePreCadastroExcluir();
  const [novo, setNovo] = useState(false);
  const faltam = q.data?.filter((p) => !p.usado_em).length ?? 0;
  return (
    <section className="space-y-3" aria-labelledby="pre-titulo">
      <div className="flex flex-wrap items-end justify-between gap-2">
        <div>
          <h2 id="pre-titulo" className="text-lg font-semibold">Equipe pré-cadastrada</h2>
          <p className="text-sm text-muted-foreground">
            Quem criar conta com um destes e-mails recebe o perfil ao confirmar o e-mail — sem precisar liberar aqui.
            {faltam > 0 && ` ${faltam} ainda não entraram.`}
          </p>
        </div>
        <Button size="sm" variant="outline" onClick={() => setNovo(true)}>
          <Plus /> Adicionar
        </Button>
      </div>
      {q.isError ? (
        <EstadoErro erro={q.error} onTentar={() => q.refetch()} />
      ) : (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Pessoa</TableHead>
                <TableHead>Perfil</TableHead>
                <TableHead>Situação</TableHead>
                <TableHead className="text-right">
                  <span className="sr-only">Ações</span>
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {q.isLoading && (
                <TableRow>
                  <TableCell colSpan={4}>
                    <Skeleton className="h-5 w-full" />
                  </TableCell>
                </TableRow>
              )}
              {q.data?.map((p) => (
                <TableRow key={p.email}>
                  <TableCell>
                    <p className="font-medium">{p.nome}</p>
                    <p className="text-xs text-muted-foreground">
                      {p.email}
                      {p.cargo && ` · ${p.cargo}`}
                      {p.telefone && ` · ${fmtTelefone(p.telefone)}`}
                    </p>
                  </TableCell>
                  <TableCell className="text-sm">
                    {PAPEIS.find((x) => x.valor === p.papel)?.rotulo ?? p.papel}
                    {p.libera_agenda && <Badge variant="info" className="ml-1">libera agenda</Badge>}
                    {p.rodizio_ordem != null && <Badge variant="muted" className="ml-1">rodízio {p.rodizio_ordem}º</Badge>}
                  </TableCell>
                  <TableCell>
                    {p.usado_em ? (
                      <Badge variant="success">
                        <UserCheck className="h-3 w-3" aria-hidden /> Entrou
                      </Badge>
                    ) : p.cadastrado ? (
                      <Badge variant="warning">Falta confirmar o e-mail</Badge>
                    ) : (
                      <Badge variant="muted">Ainda não criou conta</Badge>
                    )}
                  </TableCell>
                  <TableCell className="text-right">
                    {!p.usado_em && (
                      <Button
                        size="icon"
                        variant="ghost"
                        className="text-muted-foreground hover:text-destructive"
                        aria-label={`Remover pré-cadastro de ${p.nome}`}
                        onClick={() => window.confirm(`Remover o pré-cadastro de ${p.email}?`) && excluir.mutate(p.email)}
                      >
                        <Trash2 />
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Card>
      )}
      <NovoPreCadastro aberto={novo} onFechar={() => setNovo(false)} />
    </section>
  );
}

function NovoPreCadastro({ aberto, onFechar }: { aberto: boolean; onFechar: () => void }) {
  const salvar = usePreCadastroSalvar();
  const vazio = { email: "", nome: "", cargo: "", telefone: "", papel: "operacoes" as Papel, libera_agenda: false };
  const [f, setF] = useState(vazio);
  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Pré-cadastrar pessoa</DialogTitle>
          <DialogDescription>Ela cria a conta com este e-mail em "Criar conta" e entra direto com o perfil abaixo.</DialogDescription>
        </DialogHeader>
        <form
          className="space-y-3"
          onSubmit={(e) => {
            e.preventDefault();
            salvar
              .mutateAsync({ email: f.email, dados: { nome: f.nome, cargo: f.cargo, telefone: f.telefone, papel: f.papel, libera_agenda: f.libera_agenda } })
              .then(() => {
                setF(vazio);
                onFechar();
              })
              .catch(() => null);
          }}
        >
          <div className="space-y-1.5">
            <Label htmlFor="pc-nome">Nome</Label>
            <Input id="pc-nome" value={f.nome} onChange={(e) => setF({ ...f, nome: e.target.value })} required />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pc-email">E-mail</Label>
            <Input id="pc-email" type="email" value={f.email} onChange={(e) => setF({ ...f, email: e.target.value })} required />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pc-tel">WhatsApp (avisos do painel)</Label>
            <Input id="pc-tel" inputMode="tel" placeholder="(11) 99697-1631" value={f.telefone} onChange={(e) => setF({ ...f, telefone: e.target.value })} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="pc-cargo">Cargo</Label>
              <Input id="pc-cargo" value={f.cargo} onChange={(e) => setF({ ...f, cargo: e.target.value })} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="pc-papel">Perfil</Label>
              <Select value={f.papel} onValueChange={(v) => setF({ ...f, papel: v as Papel })}>
                <SelectTrigger id="pc-papel">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {PAPEIS.map((p) => (
                    <SelectItem key={p.valor} value={p.valor}>
                      {p.rotulo}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" checked={f.libera_agenda} onChange={(e) => setF({ ...f, libera_agenda: e.target.checked })} />
            Libera exceções da agenda
          </label>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={onFechar}>
              Cancelar
            </Button>
            <Button type="submit" disabled={salvar.isPending}>
              {salvar.isPending && <Loader2 className="animate-spin" />} Salvar
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** 0078: editar nome e e-mail de acesso. O e-mail troca no login (Auth) pela Edge Function usuario-admin. */
function EditarUsuarioDialog({ alvo, onFechar }: { alvo: { user_id: string; nome: string; email: string; papel: string; ativo: boolean } | null; onFechar: () => void }) {
  const salvar = useSalvarUsuario();
  const adminAcao = useUsuarioAdmin();
  const [nome, setNome] = useState("");
  const [email, setEmail] = useState("");
  const [chave, setChave] = useState<string | null>(null);
  if ((alvo?.user_id ?? null) !== chave) {
    setChave(alvo?.user_id ?? null);
    setNome(alvo?.nome ?? "");
    setEmail(alvo?.email ?? "");
  }
  const ocupado = salvar.isPending || adminAcao.isPending;

  async function gravar(e: React.FormEvent) {
    e.preventDefault();
    if (!alvo) return;
    try {
      if (nome.trim() && nome.trim() !== alvo.nome) await salvar.mutateAsync({ user_id: alvo.user_id, papel: alvo.papel, ativo: alvo.ativo, nome: nome.trim() });
      if (email.trim().toLowerCase() !== alvo.email.toLowerCase()) await adminAcao.mutateAsync({ acao: "trocar_email", user_id: alvo.user_id, email: email.trim() });
      onFechar();
    } catch {
      /* o toast de erro já apareceu */
    }
  }

  return (
    <Dialog open={!!alvo} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={gravar}>
          <DialogHeader>
            <DialogTitle>Editar usuário</DialogTitle>
            <DialogDescription>Trocar o e-mail muda o login: a pessoa entra com o e-mail novo e a mesma senha.</DialogDescription>
          </DialogHeader>
          <div className="mt-4 space-y-3">
            <div className="space-y-1.5">
              <Label htmlFor="eu-nome">Nome</Label>
              <Input id="eu-nome" value={nome} onChange={(e) => setNome(e.target.value)} required />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="eu-email">E-mail de acesso</Label>
              <Input id="eu-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
              {!/@vitalis\.com\.br$/i.test(email) && <p className="text-xs text-warning">Use o e-mail da Vitalis (@exemplo.com.br).</p>}
            </div>
          </div>
          <DialogFooter className="mt-5">
            <Button type="button" variant="outline" onClick={onFechar}>
              Cancelar
            </Button>
            <Button type="submit" disabled={ocupado}>
              {ocupado && <Loader2 className="animate-spin" />} Salvar
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
