import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "sonner";
import { ProvedorTema, useTema } from "@/contexts/tema";
import { ProvedorSessao } from "@/contexts/sessao";
import App from "./App";
import "./index.css";

const qc = new QueryClient({
  defaultOptions: {
    queries: {
      retry: (n, e) => n < 1 && !(e instanceof Error && /permissão|liberado|não tem esta função/i.test(e.message)),
      refetchOnWindowFocus: false,
    },
  },
});

function Avisos() {
  const { tema } = useTema();
  return <Toaster theme={tema === "escuro" ? "dark" : "light"} richColors position="top-right" closeButton />;
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ProvedorTema>
      <QueryClientProvider client={qc}>
        <BrowserRouter>
          <ProvedorSessao>
            <App />
          </ProvedorSessao>
        </BrowserRouter>
        <Avisos />
      </QueryClientProvider>
    </ProvedorTema>
  </React.StrictMode>,
);
