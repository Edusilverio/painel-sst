import { useEffect, useState } from "react";
import { NavLink, Outlet, useLocation } from "react-router-dom";
import {
  BarChart3,
  Building2,
  CalendarDays,
  ClipboardList,
  FileSignature,
  FileText,
  FileHeart,
  Link2,
  History,
  KanbanSquare,
  ListTodo,
  LogOut,
  Menu,
  MessageCircle,
  MessagesSquare,
  Moon,
  Package,
  Settings2,
  Stethoscope,
  Sun,
  TimerReset,
  TrendingUp,
  Users,
  Wallet,
  X,
  type LucideIcon,
} from "lucide-react";
import { useSessao } from "@/contexts/sessao";
import { useChatNaoLidas } from "@/hooks/api";
import { useTema } from "@/contexts/tema";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Marca } from "./Marca";
import { Notificacoes } from "./Notificacoes";
import { AvisosSonoros } from "./AvisosSonoros";
import { cn, iniciais } from "@/lib/utils";
import { rotuloPapel, type Papel } from "@/lib/tipos";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

interface Item {
  para: string;
  rotulo: string;
  icone: LucideIcon;
  papeis?: Papel[];
  emBreve?: boolean;
}
interface Grupo {
  titulo?: string;
  itens: Item[];
}

const CLINICO: Papel[] = ["gestor", "operacoes"];

export const NAVEGACAO: Grupo[] = [
  { itens: [{ para: "/", rotulo: "Visão geral", icone: BarChart3 }] },
  {
    titulo: "CRM",
    itens: [
      { para: "/crm", rotulo: "Funis", icone: KanbanSquare },
      { para: "/crm/pendencias", rotulo: "Pendências", icone: TimerReset },
      { para: "/contratos", rotulo: "Contratos", icone: FileSignature, papeis: ["gestor", "comercial", "financeiro"] },
      { para: "/crm/catalogo", rotulo: "Catálogo", icone: Package },
      { para: "/crm/relatorio", rotulo: "Relatório de vendas", icone: TrendingUp, papeis: ["financeiro", "comercial"] },
    ],
  },
  { titulo: "Clientes", itens: [{ para: "/clientes", rotulo: "Empresas", icone: Building2 }] },
  { titulo: "Financeiro", itens: [{ para: "/financeiro", rotulo: "Contas a receber", icone: Wallet, papeis: ["gestor", "financeiro"] }] },
  {
    titulo: "Equipe",
    itens: [
      { para: "/chat", rotulo: "Chat", icone: MessagesSquare },
      { para: "/tarefas", rotulo: "Fluxo de trabalho", icone: ListTodo },
    ],
  },
  {
    titulo: "Saúde ocupacional",
    itens: [
      { para: "/agenda", rotulo: "Agenda", icone: CalendarDays, papeis: ["gestor", "operacoes", "comercial"] },
      { para: "/documentos", rotulo: "Documentos técnicos", icone: FileText, papeis: ["gestor", "operacoes", "comercial"] },
      { para: "/atestados", rotulo: "Atestados", icone: FileHeart, papeis: CLINICO },
      { para: "/vencimentos", rotulo: "Vencimento de exames", icone: ClipboardList, papeis: CLINICO },
      { para: "/atendimentos", rotulo: "Atendimentos", icone: Stethoscope, papeis: CLINICO },
    ],
  },
  {
    titulo: "Configurações",
    itens: [
      { para: "/configuracoes/funis", rotulo: "Funis e etapas", icone: Settings2, papeis: ["gestor"] },
      { para: "/configuracoes/whatsapp", rotulo: "WhatsApp", icone: MessageCircle, papeis: ["gestor", "comercial", "operacoes", "financeiro"] },
      { para: "/configuracoes/bitrix", rotulo: "Empresas do Bitrix", icone: Link2, papeis: ["gestor"] },
      { para: "/configuracoes/usuarios", rotulo: "Usuários", icone: Users, papeis: ["admin"] },
      { para: "/configuracoes/registro", rotulo: "Registro de alterações", icone: History, papeis: ["admin"] },
    ],
  },
];

function Navegacao({ onNavegar }: { onNavegar?: () => void }) {
  const { tem } = useSessao();
  const chat = useChatNaoLidas();
  return (
    <nav className="flex-1 space-y-5 overflow-y-auto px-3 py-4" aria-label="Menu principal">
      {NAVEGACAO.map((g, i) => {
        const itens = g.itens.filter((it) => !it.papeis || tem(...it.papeis));
        if (!itens.length) return null;
        return (
          <div key={i}>
            {g.titulo && <p className="mb-1.5 px-3 text-[11px] font-semibold uppercase tracking-wider text-sidebar-muted">{g.titulo}</p>}
            <ul className="space-y-0.5">
              {itens.map((it) => (
                <li key={it.para}>
                  <NavLink
                    to={it.para}
                    end={it.para === "/" || it.para === "/crm"}
                    onClick={onNavegar}
                    className={({ isActive }) =>
                      cn(
                        "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60",
                        isActive ? "bg-sidebar-accent text-sidebar-accent-foreground shadow-sm" : "text-sidebar-foreground/85 hover:bg-sidebar-accent/60 hover:text-sidebar-accent-foreground",
                        it.emBreve && "opacity-70",
                      )
                    }
                  >
                    <it.icone className="h-4 w-4 shrink-0" aria-hidden />
                    <span className="flex-1 truncate">{it.rotulo}</span>
                    {it.para === "/chat" && !!chat.data && (
                      <span className="rounded-full bg-marca px-1.5 py-0.5 text-[10px] font-semibold text-white" aria-label={`${chat.data} mensagens não lidas`}>
                        {chat.data > 99 ? "99+" : chat.data}
                      </span>
                    )}
                    {it.emBreve && <span className="rounded bg-white/10 px-1.5 py-0.5 text-[10px] uppercase tracking-wide">breve</span>}
                  </NavLink>
                </li>
              ))}
            </ul>
          </div>
        );
      })}
    </nav>
  );
}

export function AppLayout() {
  const { perfil, sair } = useSessao();
  const { tema, alternar } = useTema();
  const [menuAberto, setMenuAberto] = useState(false);
  const local = useLocation();
  useEffect(() => setMenuAberto(false), [local.pathname]);

  return (
    <div className="flex h-full">
      {/* Sidebar: fixa no desktop, gaveta no celular */}
      <div
        className={cn("fixed inset-0 z-40 bg-black/50 transition-opacity md:hidden", menuAberto ? "opacity-100" : "pointer-events-none opacity-0")}
        onClick={() => setMenuAberto(false)}
        aria-hidden
      />
      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-50 flex w-64 flex-col bg-sidebar pt-[env(safe-area-inset-top)] text-sidebar-foreground transition-transform md:static md:translate-x-0",
          menuAberto ? "translate-x-0" : "-translate-x-full",
        )}
      >
        <div className="flex h-16 items-center justify-between border-b border-sidebar-border px-4">
          <Marca />
          <button
            type="button"
            className="rounded-md p-1.5 hover:bg-sidebar-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60 md:hidden"
            onClick={() => setMenuAberto(false)}
            aria-label="Fechar menu"
          >
            <X className="h-5 w-5" />
          </button>
        </div>
        <Navegacao onNavegar={() => setMenuAberto(false)} />
        <div className="border-t border-sidebar-border p-3 text-[11px] text-sidebar-muted">Painel Vitalis · Exemplo Consultoria</div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 flex h-16 items-center gap-2 border-b bg-background/90 px-4 pt-[env(safe-area-inset-top)] backdrop-blur sm:px-6">
          <Button variant="ghost" size="icon" className="md:hidden" onClick={() => setMenuAberto(true)} aria-label="Abrir menu">
            <Menu className="h-5 w-5" />
          </Button>
          <div className="flex-1" />
          <Notificacoes />
          <AvisosSonoros />
          <Button variant="ghost" size="icon" onClick={alternar} aria-label={tema === "claro" ? "Usar tema escuro" : "Usar tema claro"}>
            {tema === "claro" ? <Moon className="h-5 w-5" /> : <Sun className="h-5 w-5" />}
          </Button>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button
                type="button"
                className="flex items-center gap-2 rounded-full p-0.5 pr-2 hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                aria-label="Menu da conta"
              >
                <span className="flex h-8 w-8 items-center justify-center rounded-full bg-primary text-xs font-semibold text-primary-foreground">{iniciais(perfil?.nome)}</span>
                <span className="hidden text-left text-sm leading-tight sm:block">
                  <span className="block max-w-[10rem] truncate font-medium">{perfil?.nome}</span>
                  <span className="block text-xs text-muted-foreground">{rotuloPapel(perfil?.papel)}</span>
                </span>
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-56">
              <DropdownMenuLabel>
                <span className="block truncate text-foreground">{perfil?.nome}</span>
                <span className="block truncate font-normal">{perfil?.email}</span>
              </DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuItem onSelect={() => sair()}>
                <LogOut /> Sair
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </header>
        <main className="flex-1 overflow-y-auto">
          <Outlet />
        </main>
      </div>
    </div>
  );
}

/** Cabeçalho padrão das telas. */
export function Cabecalho({ titulo, descricao, acoes, selo }: { titulo: string; descricao?: string; acoes?: React.ReactNode; selo?: string }) {
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <div className="flex items-center gap-2">
          <h1 className="text-2xl font-semibold tracking-tight">{titulo}</h1>
          {selo && <Badge variant="marca">{selo}</Badge>}
        </div>
        {descricao && <p className="mt-1 text-sm text-muted-foreground">{descricao}</p>}
      </div>
      {acoes && <div className="flex flex-wrap items-center gap-2">{acoes}</div>}
    </div>
  );
}

