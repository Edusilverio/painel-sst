import { Navigate, Route, Routes, useLocation } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { configurado } from "@/lib/supabase";
import { useSessao } from "@/contexts/sessao";
import { AppLayout } from "@/components/layout/AppLayout";
import type { Papel } from "@/lib/tipos";
import Entrar from "@/pages/Entrar";
import Redefinir from "@/pages/Redefinir";
import { Aguardando, NaoConfigurado, NaoEncontrada, SemPermissao } from "@/pages/Avisos";
import VisaoGeral from "@/pages/VisaoGeral";
import Funis from "@/pages/Funis";
import Pendencias from "@/pages/Pendencias";
import Catalogo from "@/pages/Catalogo";
import Clientes from "@/pages/Clientes";
import Cliente from "@/pages/Cliente";
import Vencimentos from "@/pages/Vencimentos";
import Atestados from "@/pages/Atestados";
import BitrixEmpresas from "@/pages/BitrixEmpresas";
import RelatorioVendas from "@/pages/RelatorioVendas";
import Atendimentos from "@/pages/Atendimentos";
import ConfigFunis from "@/pages/ConfigFunis";
import Usuarios from "@/pages/Usuarios";
import EmBreve from "@/pages/EmBreve";
import WhatsApp from "@/pages/WhatsApp";
import Agenda from "@/pages/Agenda";
import Tarefas from "@/pages/Tarefas";
import Chat from "@/pages/Chat";
import Auditoria from "@/pages/Auditoria";
import Contratos from "@/pages/Contratos";
import Financeiro from "@/pages/Financeiro";
import Documentos from "@/pages/Documentos";

function Exige({ papeis, children }: { papeis: Papel[]; children: React.ReactNode }) {
  const { tem } = useSessao();
  return tem(...papeis) ? <>{children}</> : <SemPermissao />;
}

export default function App() {
  const { estado } = useSessao();
  if (!configurado) return <NaoConfigurado />;

  if (estado === "carregando")
    return (
      <div className="flex h-full items-center justify-center" role="status" aria-label="Carregando">
        <Loader2 className="h-6 w-6 animate-spin text-primary" />
      </div>
    );

  if (estado !== "ativo")
    return (
      <Routes>
        <Route path="/redefinir-senha" element={<Redefinir />} />
        <Route path="*" element={estado === "sem_sessao" ? <Entrar /> : <Aguardando />} />
      </Routes>
    );

  return (
    <Routes>
      <Route path="/redefinir-senha" element={<Redefinir />} />
      <Route path="/entrar" element={<Navigate to="/" replace />} />
      <Route element={<AppLayout />}>
        <Route index element={<VisaoGeral />} />
        <Route path="crm" element={<Funis />} />
        <Route path="crm/pendencias" element={<Pendencias />} />
        <Route path="crm/catalogo" element={<Catalogo />} />
        <Route path="clientes" element={<Clientes />} />
        <Route path="clientes/:id" element={<Cliente />} />
        <Route path="crm/relatorio" element={<Exige papeis={["financeiro", "comercial"]}><RelatorioVendas /></Exige>} />
        <Route path="contratos" element={<Exige papeis={["gestor", "comercial", "financeiro"]}><Contratos /></Exige>} />
        <Route path="documentos" element={<Exige papeis={["gestor", "operacoes", "comercial"]}><Documentos /></Exige>} />
        <Route path="financeiro" element={<Exige papeis={["gestor", "financeiro"]}><Financeiro /></Exige>} />
        <Route path="tarefas" element={<Tarefas />} />
        <Route path="chat" element={<Chat />} />
        <Route path="agenda" element={<Exige papeis={["gestor", "operacoes", "comercial"]}><Agenda /></Exige>} />
        <Route path="atestados" element={<Exige papeis={["gestor", "operacoes"]}><Atestados /></Exige>} />
        <Route path="vencimentos" element={<Exige papeis={["gestor", "operacoes"]}><Vencimentos /></Exige>} />
        <Route path="atendimentos" element={<Exige papeis={["gestor", "operacoes"]}><Atendimentos /></Exige>} />
        <Route path="configuracoes/funis" element={<Exige papeis={["gestor"]}><ConfigFunis /></Exige>} />
        <Route path="configuracoes/usuarios" element={<Exige papeis={["admin"]}><Usuarios /></Exige>} />
        <Route path="configuracoes/bitrix" element={<Exige papeis={["gestor"]}><BitrixEmpresas /></Exige>} />
        <Route path="configuracoes/registro" element={<Exige papeis={["admin"]}><Auditoria /></Exige>} />
        <Route path="configuracoes/whatsapp" element={<Exige papeis={["gestor", "comercial", "operacoes", "financeiro"]}><WhatsApp /></Exige>} />
        {/* a tela de conversas espelhadas saiu em 07/10; links antigos caem nos modelos/histórico */}
        <Route path="whatsapp" element={<ParaWhatsApp />} />
        <Route path="em-breve/whatsapp" element={<ParaWhatsApp />} />
        <Route path="em-breve/:modulo" element={<EmBreve />} />
        <Route path="*" element={<NaoEncontrada />} />
      </Route>
    </Routes>
  );
}

function ParaWhatsApp() {
  const { search } = useLocation();
  return <Navigate to={`/configuracoes/whatsapp${search}`} replace />;
}
