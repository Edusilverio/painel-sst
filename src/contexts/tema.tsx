import { createContext, useContext, useEffect, useState } from "react";

type Tema = "claro" | "escuro";
const Ctx = createContext<{ tema: Tema; alternar: () => void }>({ tema: "claro", alternar: () => {} });

function lerTema(): Tema {
  try {
    const v = localStorage.getItem("vitalis.tema");
    if (v === "claro" || v === "escuro") return v;
  } catch {
    /* navegação privada: segue o sistema */
  }
  return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "escuro" : "claro";
}

export function ProvedorTema({ children }: { children: React.ReactNode }) {
  const [tema, setTema] = useState<Tema>(lerTema);
  useEffect(() => {
    document.documentElement.classList.toggle("dark", tema === "escuro");
    try {
      localStorage.setItem("vitalis.tema", tema);
    } catch {
      /* sem armazenamento: só não lembra */
    }
  }, [tema]);
  return <Ctx.Provider value={{ tema, alternar: () => setTema((t) => (t === "claro" ? "escuro" : "claro")) }}>{children}</Ctx.Provider>;
}

export const useTema = () => useContext(Ctx);
