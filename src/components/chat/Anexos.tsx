import { useEffect, useRef, useState } from "react";
import { FileText, Loader2, Mic, Paperclip, Send, X } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { useChatAnexoUrl } from "@/hooks/api";
import type { ChatAnexoTipo, ChatMensagem } from "@/lib/tipos";

export const ACEITOS = "image/*,audio/*,application/pdf,.doc,.docx,.xls,.xlsx,.txt";

export function tipoDoArquivo(mime: string): ChatAnexoTipo {
  if (mime.startsWith("image/")) return "imagem";
  if (mime.startsWith("audio/")) return "audio";
  return "arquivo";
}

function tamanho(b: number | null) {
  if (!b) return "";
  return b < 1024 * 1024 ? `${Math.max(1, Math.round(b / 1024))} KB` : `${(b / 1024 / 1024).toFixed(1).replace(".", ",")} MB`;
}

/** Mostra o anexo de uma mensagem: imagem, player de áudio ou link do arquivo. */
export function AnexoMensagem({ m }: { m: ChatMensagem }) {
  const url = useChatAnexoUrl(m.anexo_path);
  if (!m.anexo_path || !m.anexo_tipo) return null;
  if (url.isLoading) return <Loader2 className="my-2 h-4 w-4 animate-spin opacity-70" aria-label="Carregando anexo" />;
  if (url.isError || !url.data) return <p className="text-xs opacity-80">Anexo indisponível.</p>;

  if (m.anexo_tipo === "imagem")
    return (
      <a href={url.data} target="_blank" rel="noopener noreferrer" className="mb-1 block" title="Abrir imagem">
        <img src={url.data} alt={m.anexo_nome ?? "Imagem"} className="max-h-64 max-w-full rounded-lg object-contain" loading="lazy" />
      </a>
    );
  if (m.anexo_tipo === "audio") return <audio controls preload="metadata" src={url.data} className="my-1 h-10 w-64 max-w-full" aria-label="Mensagem de áudio" />;
  return (
    <a
      href={url.data}
      target="_blank"
      rel="noopener noreferrer"
      download={m.anexo_nome ?? undefined}
      className="my-1 flex items-center gap-2 rounded-lg bg-background/20 px-2 py-1.5 underline-offset-2 hover:underline"
    >
      <FileText className="h-4 w-4 shrink-0" aria-hidden />
      <span className="truncate">{m.anexo_nome ?? "Arquivo"}</span>
      <span className="shrink-0 text-[10px] opacity-75">{tamanho(m.anexo_tamanho)}</span>
    </a>
  );
}

/** Botão de anexar arquivo (imagem, PDF, documento ou áudio já gravado). */
export function BotaoAnexar({ disabled, onArquivo }: { disabled?: boolean; onArquivo: (f: File) => void }) {
  const input = useRef<HTMLInputElement>(null);
  return (
    <>
      <input
        ref={input}
        type="file"
        accept={ACEITOS}
        className="hidden"
        onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          if (f) onArquivo(f);
        }}
      />
      <Button type="button" size="icon" variant="ghost" disabled={disabled} onClick={() => input.current?.click()} aria-label="Anexar imagem ou arquivo" title="Anexar imagem ou arquivo">
        <Paperclip />
      </Button>
    </>
  );
}

function formatoGravacao() {
  if (typeof MediaRecorder === "undefined") return null;
  for (const t of ["audio/webm;codecs=opus", "audio/webm", "audio/mp4", "audio/ogg;codecs=opus"]) if (MediaRecorder.isTypeSupported(t)) return t;
  return "";
}

/**
 * Gravação de áudio no navegador. Clica no microfone para começar; enquanto grava, aparece o tempo,
 * o botão de cancelar e o de enviar.
 */
export function GravadorAudio({ disabled, onPronto, onGravando }: { disabled?: boolean; onPronto: (b: Blob, duracao: number) => void; onGravando: (v: boolean) => void }) {
  const [gravando, setGravando] = useState(false);
  const [seg, setSeg] = useState(0);
  const rec = useRef<MediaRecorder | null>(null);
  const partes = useRef<Blob[]>([]);
  const inicio = useRef(0);
  const cancelado = useRef(false);

  useEffect(() => {
    if (!gravando) return;
    const t = setInterval(() => setSeg(Math.floor((Date.now() - inicio.current) / 1000)), 250);
    return () => clearInterval(t);
  }, [gravando]);
  useEffect(() => () => rec.current?.stream.getTracks().forEach((t) => t.stop()), []);

  async function comecar() {
    const formato = formatoGravacao();
    if (formato === null || !navigator.mediaDevices?.getUserMedia) return toast.error("Este navegador não grava áudio.");
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const r = new MediaRecorder(stream, formato ? { mimeType: formato } : undefined);
      partes.current = [];
      cancelado.current = false;
      r.ondataavailable = (e) => e.data.size && partes.current.push(e.data);
      r.onstop = () => {
        stream.getTracks().forEach((t) => t.stop());
        const dur = (Date.now() - inicio.current) / 1000;
        setGravando(false);
        onGravando(false);
        if (cancelado.current || dur < 0.7) return;
        onPronto(new Blob(partes.current, { type: (r.mimeType || formato || "audio/webm").split(";")[0] }), Math.round(dur * 10) / 10);
      };
      rec.current = r;
      inicio.current = Date.now();
      setSeg(0);
      r.start();
      setGravando(true);
      onGravando(true);
    } catch {
      toast.error("Não foi possível usar o microfone. Libere o acesso no navegador.");
    }
  }

  function parar(cancelar: boolean) {
    cancelado.current = cancelar;
    rec.current?.stop();
  }

  if (!gravando)
    return (
      <Button type="button" size="icon" variant="ghost" disabled={disabled} onClick={comecar} aria-label="Gravar áudio" title="Gravar áudio">
        <Mic />
      </Button>
    );
  return (
    <div className="flex flex-1 items-center gap-2 rounded-md border border-destructive/40 bg-destructive/5 px-2 py-1.5" role="status">
      <span className="h-2.5 w-2.5 animate-pulse rounded-full bg-destructive" aria-hidden />
      <span className="flex-1 text-sm tabular-nums">
        Gravando… {Math.floor(seg / 60)}:{String(seg % 60).padStart(2, "0")}
      </span>
      <Button type="button" size="icon" variant="ghost" onClick={() => parar(true)} aria-label="Cancelar gravação" title="Cancelar">
        <X />
      </Button>
      <Button type="button" size="icon" onClick={() => parar(false)} aria-label="Parar e enviar áudio" title="Enviar áudio" className="bg-destructive text-destructive-foreground hover:bg-destructive/90">
        <Send />
      </Button>
    </div>
  );
}
