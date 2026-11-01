import { useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { Copy, ExternalLink, KeyRound, Loader2, MessageCircle, Pencil, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Cabecalho } from "@/components/layout/AppLayout";
import { HistoricoBitrix } from "@/components/whatsapp/HistoricoBitrix";
import { MensagemDialog } from "@/components/whatsapp/MensagemDialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { EstadoErro, EstadoVazio } from "@/components/ui/estados";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { useFunis, useWaConfigSalvar, useWaModeloExcluir, useWaModeloSalvar, useWaModelos, useWaResumo, useWaTokenGerar } from "@/hooks/api";
import type { WaModelo, WaResumo } from "@/lib/tipos";
import { cn, fmtDataHora } from "@/lib/utils";
import { CATEGORIAS_WA, VARIAVEIS_WA, tempoCurto } from "@/lib/whatsapp";

/**
 * Configurações › WhatsApp. A tela de conversas espelhadas saiu (07/10): o atendimento acontece no Inbox do
 * Exemplo Connect e a conversa com um cliente começa pelo botão "Iniciar conversa" no card do CRM.
 * Aqui ficam os modelos de mensagem, o histórico importado do Bitrix e a conexão com o Exemplo Connect.
 */
export default function WhatsApp() {
  const resumo = useWaResumo();
  const [params, setParams] = useSearchParams();
  const aba = params.get("aba") ?? "modelos";
  const r = resumo.data;

  return (
    <div className="mx-auto max-w-7xl space-y-5 p-4 sm:p-6">
      <Cabecalho
        titulo="WhatsApp"
        descricao="O atendimento acontece no Exemplo Connect, pelo número da Vitalis. Para falar com um cliente, abra o card no CRM e use Iniciar conversa."
        acoes={
          r && (
            <Button size="sm" variant="outline" asChild>
              <a href={r.inbox_url} target="_blank" rel="noopener noreferrer">
                <ExternalLink /> Abrir Inbox
              </a>
            </Button>
          )
        }
      />

      {resumo.isError && <EstadoErro erro={resumo.error} onTentar={() => resumo.refetch()} />}

      <Tabs value={aba} onValueChange={(v) => setParams({ aba: v })}>
        <TabsList>
          <TabsTrigger value="modelos">Modelos de mensagem</TabsTrigger>
          <TabsTrigger value="historico">Histórico do Bitrix</TabsTrigger>
          {r?.pode_configurar && <TabsTrigger value="configuracao">Conexão com o Exemplo Connect</TabsTrigger>}
        </TabsList>
        <TabsContent value="modelos" className="mt-4">
          <Modelos pode={!!r?.pode_configurar} />
        </TabsContent>
        <TabsContent value="historico" className="mt-4">
          <HistoricoBitrix key={params.get("tel") ?? ""} telefone={params.get("tel")} />
        </TabsContent>
        {r?.pode_configurar && (
          <TabsContent value="configuracao" className="mt-4">
            <Configuracao r={r} />
          </TabsContent>
        )}
      </Tabs>
    </div>
  );
}

function Modelos({ pode }: { pode: boolean }) {
  const modelos = useWaModelos();
  const excluir = useWaModeloExcluir();
  const [editar, setEditar] = useState<{ aberto: boolean; m: WaModelo | null }>({ aberto: false, m: null });
  const [usar, setUsar] = useState<string | null>(null);

  if (modelos.isError) return <EstadoErro erro={modelos.error} onTentar={() => modelos.refetch()} />;
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-muted-foreground">
          Textos prontos para o dia a dia. Os campos entre chaves, como {"{nome}"} e {"{empresa}"}, são preenchidos com os dados do contato.
        </p>
        {pode && (
          <Button size="sm" onClick={() => setEditar({ aberto: true, m: null })}>
            <Plus /> Novo modelo
          </Button>
        )}
      </div>
      {modelos.isLoading ? (
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-40" />
          ))}
        </div>
      ) : !modelos.data?.length ? (
        <EstadoVazio
          icone={MessageCircle}
          titulo="Nenhum modelo cadastrado"
          texto="Cadastre as mensagens que a equipe mais manda: confirmação de exame, lembrete de pagamento, envio de proposta."
        />
      ) : (
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {modelos.data.map((m) => (
            <Card key={m.id} className={cn("flex flex-col", !m.ativo && "opacity-60")}>
              <CardContent className="flex flex-1 flex-col gap-3 pt-5">
                <div className="flex items-start justify-between gap-2">
                  <p className="font-medium leading-snug">{m.titulo}</p>
                  <div className="flex shrink-0 gap-1">
                    {!m.ativo && <Badge variant="muted">Inativo</Badge>}
                    <Badge variant="secondary">{CATEGORIAS_WA[m.categoria]}</Badge>
                  </div>
                </div>
                <p className="line-clamp-5 flex-1 whitespace-pre-line text-sm text-muted-foreground">{m.texto}</p>
                <div className="flex gap-1">
                  <Button size="sm" variant="outline" onClick={() => setUsar(m.id)} disabled={!m.ativo}>
                    <Copy /> Usar
                  </Button>
                  {pode && (
                    <>
                      <Button size="sm" variant="ghost" onClick={() => setEditar({ aberto: true, m })}>
                        <Pencil /> Editar
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        className="ml-auto text-muted-foreground hover:text-destructive"
                        aria-label={`Excluir ${m.titulo}`}
                        onClick={() => {
                          if (window.confirm(`Excluir o modelo "${m.titulo}"?`)) excluir.mutate(m.id);
                        }}
                      >
                        <Trash2 />
                      </Button>
                    </>
                  )}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
      <ModeloDialog estado={editar} onFechar={() => setEditar({ aberto: false, m: null })} />
      <MensagemDialog aberto={!!usar} onFechar={() => setUsar(null)} dados={{}} modeloInicial={usar} />
    </div>
  );
}

function ModeloDialog({ estado, onFechar }: { estado: { aberto: boolean; m: WaModelo | null }; onFechar: () => void }) {
  const salvar = useWaModeloSalvar();
  const [f, setF] = useState({ titulo: "", categoria: "geral" as WaModelo["categoria"], texto: "", ativo: true });
  const [chave, setChave] = useState<string | null>(null);
  const atual = estado.aberto ? (estado.m?.id ?? "novo") : null;
  if (atual !== chave) {
    setChave(atual);
    if (atual) setF(estado.m ? { titulo: estado.m.titulo, categoria: estado.m.categoria, texto: estado.m.texto, ativo: estado.m.ativo } : { titulo: "", categoria: "geral", texto: "", ativo: true });
  }

  return (
    <Dialog open={estado.aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{estado.m ? "Editar modelo" : "Novo modelo"}</DialogTitle>
          <DialogDescription>Use os campos entre chaves para o painel preencher sozinho.</DialogDescription>
        </DialogHeader>
        <form
          className="space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            salvar.mutateAsync({ id: estado.m?.id ?? null, dados: f }).then(onFechar).catch(() => null);
          }}
        >
          <div className="grid gap-4 sm:grid-cols-[1fr_170px]">
            <div className="space-y-1.5">
              <Label htmlFor="m-titulo">Título</Label>
              <Input id="m-titulo" value={f.titulo} onChange={(e) => setF({ ...f, titulo: e.target.value })} placeholder="Ex.: Segunda via de boleto" required />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="m-cat">Categoria</Label>
              <Select value={f.categoria} onValueChange={(v) => setF({ ...f, categoria: v as WaModelo["categoria"] })}>
                <SelectTrigger id="m-cat">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {Object.entries(CATEGORIAS_WA).map(([k, v]) => (
                    <SelectItem key={k} value={k}>
                      {v}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="m-texto">Texto</Label>
            <Textarea id="m-texto" rows={6} value={f.texto} onChange={(e) => setF({ ...f, texto: e.target.value })} required />
            <div className="flex flex-wrap gap-1">
              {VARIAVEIS_WA.map((v) => (
                <button
                  key={v.chave}
                  type="button"
                  title={v.descricao}
                  onClick={() => setF((x) => ({ ...x, texto: `${x.texto}{${v.chave}}` }))}
                  className="rounded-full border px-2 py-0.5 text-xs text-muted-foreground hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                  {`{${v.chave}}`}
                </button>
              ))}
            </div>
          </div>
          {estado.m && (
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" className="h-4 w-4 accent-primary" checked={f.ativo} onChange={(e) => setF({ ...f, ativo: e.target.checked })} />
              Ativo (aparece na lista para a equipe)
            </label>
          )}
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

// ------------------------------------------------------------------ configuração

function Configuracao({ r }: { r: WaResumo }) {
  const funis = useFunis();
  const salvar = useWaConfigSalvar();
  const gerar = useWaTokenGerar();
  const [inbox, setInbox] = useState(r.inbox_url);
  const [token, setToken] = useState<string | null>(null);

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card>
        <CardContent className="space-y-4 pt-5">
          <div>
            <h2 className="font-semibold">Entrada de leads</h2>
            <p className="text-sm text-muted-foreground">O que acontece quando um número novo manda mensagem.</p>
          </div>
          <label className="flex items-start gap-3 text-sm">
            <input
              type="checkbox"
              className="mt-0.5 h-4 w-4 accent-primary"
              checked={r.criar_negocio}
              disabled={salvar.isPending}
              onChange={(e) => salvar.mutate({ criar_negocio: e.target.checked })}
            />
            <span>
              <span className="font-medium">Criar negócio automaticamente</span>
              <span className="block text-muted-foreground">
                Contato novo vira card na primeira etapa do funil, com responsável pelo rodízio. Desligado, a equipe cria pelo botão "Criar negócio".
              </span>
            </span>
          </label>
          <div className="space-y-1.5">
            <Label htmlFor="wa-funil">Funil de destino</Label>
            <Select value={r.funil_id ?? ""} onValueChange={(v) => salvar.mutate({ funil_id: v })} disabled={funis.isLoading || salvar.isPending}>
              <SelectTrigger id="wa-funil" className="sm:w-64">
                <SelectValue placeholder="Escolha o funil" />
              </SelectTrigger>
              <SelectContent>
                {(funis.data ?? []).map((f) => (
                  <SelectItem key={f.id} value={f.id}>
                    {f.nome} {f.usa_rodizio ? "· rodízio" : ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground">
              Quem entra no rodízio é definido em{" "}
              <Link to="/configuracoes/funis" className="text-primary hover:underline">
                Configurações › Funis e etapas
              </Link>
              .
            </p>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="wa-inbox">Link do Inbox</Label>
            <div className="flex gap-2">
              <Input id="wa-inbox" value={inbox} onChange={(e) => setInbox(e.target.value)} />
              <Button variant="outline" disabled={inbox === r.inbox_url || salvar.isPending} onClick={() => salvar.mutate({ inbox_url: inbox })}>
                Salvar
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="space-y-4 pt-5">
          <div>
            <h2 className="font-semibold">Conexão com o Exemplo Connect</h2>
            <p className="text-sm text-muted-foreground">
              {r.integracao_ativa
                ? `Token gerado em ${fmtDataHora(r.token_gerado_em)}. ${r.ultimo_recebimento ? `Último recebimento ${tempoCurto(r.ultimo_recebimento)}.` : "Nada recebido ainda."}`
                : "O Exemplo Connect envia cada mensagem da Vitalis para cá usando um token. Gere o token e passe para a equipe da Exemplo aplicar."}
            </p>
          </div>
          {token ? (
            <div className="space-y-2 rounded-lg border border-warning/40 bg-warning/5 p-3">
              <p className="text-sm font-medium">Copie agora — este token não aparece de novo.</p>
              <code className="block break-all rounded bg-muted px-2 py-1.5 text-xs">{token}</code>
              <Button
                size="sm"
                variant="outline"
                onClick={() =>
                  navigator.clipboard.writeText(token).then(
                    () => toast.success("Token copiado"),
                    () => toast.error("Não foi possível copiar"),
                  )
                }
              >
                <Copy /> Copiar token
              </Button>
            </div>
          ) : (
            <Button
              variant={r.integracao_ativa ? "outline" : "default"}
              disabled={gerar.isPending}
              onClick={() => {
                if (r.integracao_ativa && !window.confirm("Gerar um token novo desliga o atual até ele ser trocado no Exemplo Connect. Continuar?")) return;
                gerar.mutateAsync(undefined).then(setToken).catch(() => null);
              }}
            >
              {gerar.isPending ? <Loader2 className="animate-spin" /> : <KeyRound />} {r.integracao_ativa ? "Gerar novo token" : "Gerar token"}
            </Button>
          )}
          <p className="text-xs text-muted-foreground">
            O painel não envia mensagens: o atendimento, o robô e o histórico continuam no Inbox do Exemplo Connect, pelo número da Vitalis.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
