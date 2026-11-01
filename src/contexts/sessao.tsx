import { createContext, useCallback, useContext, useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase, rpc } from "@/lib/supabase";
import type { Papel, Perfil } from "@/lib/tipos";

/**
 * Estados distintos de propósito: "sem perfil" e "aguardando liberação" não são
 * "sem acesso" — tratar tudo igual faz a pessoa achar que errou a senha.
 */
export type EstadoSessao = "carregando" | "sem_sessao" | "sem_perfil" | "inativo" | "ativo" | "erro";

interface SessaoCtx {
  estado: EstadoSessao;
  sessao: Session | null;
  perfil: Perfil | null;
  erro: string | null;
  sair: () => Promise<void>;
  recarregar: () => Promise<void>;
  tem: (...papeis: Papel[]) => boolean;
}

const Ctx = createContext<SessaoCtx | null>(null);

export function ProvedorSessao({ children }: { children: React.ReactNode }) {
  const [sessao, setSessao] = useState<Session | null>(null);
  const [perfil, setPerfil] = useState<Perfil | null>(null);
  const [estado, setEstado] = useState<EstadoSessao>("carregando");
  const [erro, setErro] = useState<string | null>(null);

  const carregarPerfil = useCallback(async (s: Session | null) => {
    setSessao(s);
    if (!s) {
      setPerfil(null);
      setEstado("sem_sessao");
      return;
    }
    try {
      const p = await rpc<Perfil | null>("painel_meu_perfil");
      setPerfil(p);
      setErro(null);
      if (!p) setEstado("sem_perfil");
      else if (!p.ativo) setEstado("inativo");
      else {
        setEstado("ativo");
        rpc("painel_registrar_acesso").catch(() => undefined);
      }
    } catch (e) {
      setErro(e instanceof Error ? e.message : "Falha ao carregar seu perfil.");
      setEstado("erro");
    }
  }, []);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => carregarPerfil(data.session));
    const { data } = supabase.auth.onAuthStateChange((evento, s) => {
      if (evento === "SIGNED_IN" || evento === "SIGNED_OUT" || evento === "USER_UPDATED") carregarPerfil(s);
      else if (evento === "TOKEN_REFRESHED") setSessao(s);
    });
    return () => data.subscription.unsubscribe();
  }, [carregarPerfil]);

  const valor: SessaoCtx = {
    estado,
    sessao,
    perfil,
    erro,
    sair: async () => {
      await supabase.auth.signOut();
    },
    recarregar: () => carregarPerfil(sessao),
    tem: (...papeis) => !!perfil?.ativo && (perfil.papel === "admin" || papeis.includes(perfil.papel)),
  };
  return <Ctx.Provider value={valor}>{children}</Ctx.Provider>;
}

export function useSessao() {
  const c = useContext(Ctx);
  if (!c) throw new Error("useSessao fora do ProvedorSessao");
  return c;
}
