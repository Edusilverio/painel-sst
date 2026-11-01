import { useEffect, useMemo, useState } from "react";
import { Loader2, Mail, MessageCircle, Send } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { useSalvarDados, useWaContexto, useWaModelos } from "@/hooks/api";
import type { ClienteDetalhe } from "@/lib/tipos";
import { fmtDataHora } from "@/lib/utils";
import { fmtTelefone, preencher, primeiroNome } from "@/lib/whatsapp";

export type Canal = "whatsapp" | "email";

interface Destino {
  chave: string;
  contato_id: string | null;
  nome: string;
  valor: string;
}

/** Contato com a empresa direto da ficha, sem criar card no CRM (pedido do Jorge, 06/10). */
export function ContatarEmpresaDialog({ empresa: c, canal, onFechar }: { empresa: ClienteDetalhe; canal: Canal; onFechar: () => void }) {
  const salvar = useSalvarDados();
  const modelos = useWaModelos();
  const ctx = useWaContexto(null);
  const destinos = useMemo<Destino[]>(() => {
    const lista: Destino[] = [];
    for (const ct of c.contatos) {
      const v = canal === "whatsapp" ? ct.telefone : ct.email;
      if (v && v.trim()) lista.push({ chave: ct.id, contato_id: ct.id, nome: `${ct.nome ?? "Contato"}${ct.cargo ? ` (${ct.cargo})` : ""}`, valor: v.trim() });
    }
    const geral = canal === "whatsapp" ? c.telefone : c.email;
    if (geral && geral.trim() && !lista.some((d) => d.valor === geral.trim())) lista.push({ chave: "empresa", contato_id: null, nome: "Da empresa", valor: geral.trim() });
    return lista;
  }, [c, canal]);

  const [destino, setDestino] = useState<string>("");
  const [outro, setOutro] = useState("");
  const [assunto, setAssunto] = useState("");
  const [texto, setTexto] = useState("");
  const [modeloId, setModeloId] = useState("");
  const [enviando, setEnviando] = useState(false);
  useEffect(() => setDestino(destinos[0]?.chave ?? "outro"), [destinos]);

  const escolhido = destinos.find((d) => d.chave === destino);
  const valor = destino === "outro" ? outro.trim() : escolhido?.valor ?? "";
  const nomeContato = destino === "outro" ? null : escolhido?.contato_id ? c.contatos.find((x) => x.id === escolhido.contato_id)?.nome : null;
  const ativos = (modelos.data ?? []).filter((m) => m.ativo);

  function aplicarModelo(id: string) {
    setModeloId(id);
    const m = ativos.find((x) => x.id === id);
    if (m)
      setTexto(
        preencher(m.texto, {
          nome: primeiroNome(nomeContato),
          empresa: c.nome_fantasia || c.razao_social,
          atendente: primeiroNome(ctx.data?.atendente),
        }),
      );
  }

  async function enviar() {
    if (!valor) return toast.error(canal === "whatsapp" ? "Informe o telefone." : "Informe o e-mail.");
    setEnviando(true);
    try {
      if (canal === "email") {
        const url = `mailto:${encodeURIComponent(valor)}?subject=${encodeURIComponent(assunto)}&body=${encodeURIComponent(texto)}`;
        window.location.href = url;
      }
      await salvar("painel_empresa_contatar", {
        p_empresa: c.id,
        p_contato: escolhido?.contato_id ?? null,
        p_canal: canal,
        p_destino: valor,
        p_texto: texto,
        p_assunto: canal === "email" ? assunto : null,
      });
      toast.success(canal === "whatsapp" ? "Mensagem na fila de envio do WhatsApp da Vitalis" : "E-mail aberto no seu programa de e-mail e registrado na ficha");
      onFechar();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível registrar.");
    } finally {
      setEnviando(false);
    }
  }

  const Icone = canal === "whatsapp" ? MessageCircle : Mail;
  return (
    <Dialog open onOpenChange={(o) => !o && onFechar()}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Icone className="h-5 w-5 text-primary" /> {canal === "whatsapp" ? "WhatsApp" : "E-mail"} para {c.nome_fantasia || c.razao_social}
          </DialogTitle>
          <DialogDescription>
            {canal === "whatsapp"
              ? "Sai pelo número da Vitalis no Exemplo Connect e a conversa aparece no Inbox. Não cria card no CRM."
              : "Abre o seu e-mail (Outlook) já preenchido. O contato fica registrado na ficha da empresa. Não cria card no CRM."}
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-3">
          <div className="space-y-1.5">
            <Label>Para</Label>
            <Select value={destino} onValueChange={setDestino}>
              <SelectTrigger>
                <SelectValue placeholder="Escolha" />
              </SelectTrigger>
              <SelectContent>
                {destinos.map((d) => (
                  <SelectItem key={d.chave} value={d.chave}>
                    {d.nome} · {canal === "whatsapp" ? fmtTelefone(d.valor) : d.valor}
                  </SelectItem>
                ))}
                <SelectItem value="outro">Outro {canal === "whatsapp" ? "número" : "e-mail"}…</SelectItem>
              </SelectContent>
            </Select>
            {destino === "outro" && (
              <Input
                value={outro}
                onChange={(e) => setOutro(e.target.value)}
                placeholder={canal === "whatsapp" ? "(11) 99697-1631" : "bryan.goncalves@exemplo.com.br"}
                inputMode={canal === "whatsapp" ? "tel" : "email"}
                autoFocus
              />
            )}
          </div>
          {canal === "whatsapp" && ativos.length > 0 && (
            <div className="space-y-1.5">
              <Label>Modelo (opcional)</Label>
              <Select value={modeloId} onValueChange={aplicarModelo}>
                <SelectTrigger>
                  <SelectValue placeholder="Começar de um modelo de mensagem" />
                </SelectTrigger>
                <SelectContent>
                  {ativos.map((m) => (
                    <SelectItem key={m.id} value={m.id}>
                      {m.titulo}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
          {canal === "email" && (
            <div className="space-y-1.5">
              <Label htmlFor="ct-assunto">Assunto</Label>
              <Input id="ct-assunto" value={assunto} onChange={(e) => setAssunto(e.target.value)} />
            </div>
          )}
          <div className="space-y-1.5">
            <Label htmlFor="ct-texto">Mensagem</Label>
            <Textarea id="ct-texto" rows={6} value={texto} onChange={(e) => setTexto(e.target.value)} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onFechar}>
            Cancelar
          </Button>
          <Button onClick={enviar} disabled={enviando || !valor || (canal === "whatsapp" && !texto.trim())}>
            {enviando ? <Loader2 className="animate-spin" /> : <Send />} {canal === "whatsapp" ? "Enviar" : "Abrir e-mail"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export interface Interacao {
  id: number;
  canal: "whatsapp" | "email" | "ligacao" | "nota";
  destino: string | null;
  assunto: string | null;
  texto: string | null;
  em: string;
  usuario: string;
  contato: string | null;
  status_wa: "pendente" | "enviado" | "erro" | "cancelado" | null;
}

const STATUS_WA: Record<string, { rotulo: string; variante: "warning" | "success" | "destructive" | "muted" }> = {
  pendente: { rotulo: "na fila", variante: "warning" },
  enviado: { rotulo: "enviado", variante: "success" },
  erro: { rotulo: "falhou", variante: "destructive" },
  cancelado: { rotulo: "cancelado", variante: "muted" },
};

export function ListaInteracoes({ itens }: { itens: Interacao[] }) {
  if (!itens.length) return <p className="p-6 text-center text-sm text-muted-foreground">Nenhum contato feito pela ficha ainda.</p>;
  return (
    <ul className="divide-y">
      {itens.map((i) => {
        const Ic = i.canal === "whatsapp" ? MessageCircle : Mail;
        const st = i.status_wa ? STATUS_WA[i.status_wa] : null;
        return (
          <li key={i.id} className="flex gap-3 p-3 text-sm">
            <Ic className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
            <div className="min-w-0 flex-1">
              <p>
                <span className="font-medium">{i.usuario}</span> → {i.contato ?? (i.canal === "whatsapp" ? fmtTelefone(i.destino) : i.destino)}
                {st && (
                  <Badge variant={st.variante} className="ml-1.5">
                    {st.rotulo}
                  </Badge>
                )}
              </p>
              {i.assunto && <p className="font-medium">{i.assunto}</p>}
              {i.texto && <p className="line-clamp-3 whitespace-pre-wrap text-muted-foreground">{i.texto}</p>}
            </div>
            <span className="shrink-0 text-xs text-muted-foreground">{fmtDataHora(i.em)}</span>
          </li>
        );
      })}
    </ul>
  );
}
