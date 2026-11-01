/**
 * Aviso sonoro do painel (pedido da Renata, 09/10): toca quando chega mensagem nova no Chat ou um aviso
 * novo no sininho. O som é gerado no navegador (sem arquivo). A preferência fica neste navegador.
 */
const CHAVE = "vitalis.aviso_sonoro";

export function somLigado() {
  try {
    return localStorage.getItem(CHAVE) !== "off";
  } catch {
    return true;
  }
}

export function definirSom(ligado: boolean) {
  try {
    localStorage.setItem(CHAVE, ligado ? "on" : "off");
  } catch {
    /* navegador sem armazenamento: fica o padrão (ligado) */
  }
}

let ctx: AudioContext | null = null;

/** O navegador só libera áudio depois de um clique na página: prepara o contexto no primeiro gesto. */
export function prepararAudio() {
  const liberar = () => {
    try {
      const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!AC) return;
      ctx ??= new AC();
      if (ctx.state === "suspended") void ctx.resume();
    } catch {
      /* sem áudio neste navegador */
    }
  };
  window.addEventListener("pointerdown", liberar, { once: true });
  window.addEventListener("keydown", liberar, { once: true });
}

/** Dois toques curtos ("plim-plim"). */
export function tocarAviso() {
  if (!somLigado() || !ctx || ctx.state !== "running") return;
  const agora = ctx.currentTime;
  [
    [880, 0],
    [1320, 0.16],
  ].forEach(([freq, atraso]) => {
    const o = ctx!.createOscillator();
    const g = ctx!.createGain();
    o.type = "sine";
    o.frequency.value = freq;
    g.gain.setValueAtTime(0.0001, agora + atraso);
    g.gain.exponentialRampToValueAtTime(0.18, agora + atraso + 0.02);
    g.gain.exponentialRampToValueAtTime(0.0001, agora + atraso + 0.28);
    o.connect(g).connect(ctx!.destination);
    o.start(agora + atraso);
    o.stop(agora + atraso + 0.3);
  });
}

/** Aviso na área de trabalho, só quando a aba do painel não está na frente e a pessoa autorizou. */
export function avisoDesktop(titulo: string, texto: string, aoClicar?: () => void) {
  try {
    if (!("Notification" in window) || Notification.permission !== "granted" || !document.hidden) return;
    const n = new Notification(titulo, { body: texto, icon: "/favicon.svg", tag: titulo });
    n.onclick = () => {
      window.focus();
      aoClicar?.();
      n.close();
    };
  } catch {
    /* sem suporte */
  }
}
