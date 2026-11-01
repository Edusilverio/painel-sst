import { useEffect, useRef } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { useChatNaoLidas, useNaoLidas } from "@/hooks/api";
import { avisoDesktop, prepararAudio, tocarAviso } from "@/lib/som";

/** Toca o aviso quando sobe o número de mensagens do Chat ou de avisos do sininho (não toca na primeira carga). */
function useQuandoSobe(valor: number | undefined, disparar: () => void) {
  const anterior = useRef<number | null>(null);
  useEffect(() => {
    if (valor === undefined) return;
    if (anterior.current !== null && valor > anterior.current) disparar();
    anterior.current = valor;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [valor]);
}

export function AvisosSonoros() {
  const chat = useChatNaoLidas();
  const avisos = useNaoLidas();
  const navegar = useNavigate();
  const { pathname } = useLocation();

  useEffect(() => prepararAudio(), []);

  useQuandoSobe(chat.data, () => {
    // com o Chat aberto e na frente, a própria conversa já mostra a mensagem
    if (pathname.startsWith("/chat") && !document.hidden) return;
    tocarAviso();
    avisoDesktop("Nova mensagem no Chat", "Você tem mensagens não lidas no Chat da equipe.", () => navegar("/chat"));
  });
  useQuandoSobe(avisos.data, () => {
    tocarAviso();
    avisoDesktop("Novo aviso no painel", "Abra o sininho para ver.", () => navegar("/"));
  });
  return null;
}
