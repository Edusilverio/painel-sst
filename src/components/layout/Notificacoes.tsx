import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Bell, BellRing, CheckCheck, Volume2, VolumeX } from "lucide-react";
import { definirSom, somLigado, tocarAviso } from "@/lib/som";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { useMarcarLidas, useNaoLidas, useNotificacoes } from "@/hooks/api";
import { cn, tempoRelativo } from "@/lib/utils";

export function Notificacoes() {
  const [aberto, setAberto] = useState(false);
  const naoLidas = useNaoLidas();
  const lista = useNotificacoes(aberto);
  const marcar = useMarcarLidas();
  const navegar = useNavigate();
  const qtd = naoLidas.data ?? 0;
  const [som, setSom] = useState(somLigado);
  const [permissao, setPermissao] = useState(() => ("Notification" in window ? Notification.permission : "denied"));

  return (
    <DropdownMenu open={aberto} onOpenChange={setAberto}>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="relative" aria-label={qtd ? `Avisos: ${qtd} não lidos` : "Avisos"}>
          <Bell className="h-5 w-5" />
          {qtd > 0 && (
            <span className="absolute right-1 top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-marca px-1 text-[10px] font-bold text-marca-foreground">
              {qtd > 99 ? "99+" : qtd}
            </span>
          )}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-[22rem] p-0">
        <div className="flex items-center justify-between border-b px-4 py-3">
          <div className="flex items-center gap-1">
            <p className="text-sm font-semibold">Avisos</p>
            <Button
              variant="ghost"
              size="icon"
              className="h-7 w-7"
              title={som ? "Som dos avisos e do Chat: ligado" : "Som dos avisos e do Chat: desligado"}
              aria-label={som ? "Desligar som dos avisos" : "Ligar som dos avisos"}
              onClick={() => {
                definirSom(!som);
                setSom(!som);
                if (!som) setTimeout(tocarAviso, 50);
              }}
            >
              {som ? <Volume2 className="h-4 w-4" /> : <VolumeX className="h-4 w-4 text-muted-foreground" />}
            </Button>
            {permissao === "default" && (
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                title="Receber aviso na área de trabalho quando o painel estiver em segundo plano"
                aria-label="Ativar avisos na área de trabalho"
                onClick={() => Notification.requestPermission().then(setPermissao)}
              >
                <BellRing className="h-4 w-4" />
              </Button>
            )}
          </div>
          {qtd > 0 && (
            <Button variant="ghost" size="sm" onClick={() => marcar.mutate(null)}>
              <CheckCheck /> Marcar todos como lidos
            </Button>
          )}
        </div>
        <div className="max-h-96 overflow-y-auto">
          {lista.isLoading && (
            <div className="space-y-2 p-4">
              <Skeleton className="h-10 w-full" />
              <Skeleton className="h-10 w-full" />
            </div>
          )}
          {lista.isError && <p className="p-4 text-sm text-destructive">Não foi possível carregar os avisos.</p>}
          {lista.data && lista.data.length === 0 && <p className="p-6 text-center text-sm text-muted-foreground">Nenhum aviso por enquanto.</p>}
          {lista.data?.map((n) => (
            <button
              key={n.id}
              type="button"
              onClick={() => {
                if (!n.lida_em) marcar.mutate(n.id);
                setAberto(false);
                if (n.tarefa_id) navegar(`/tarefas?tarefa=${n.tarefa_id}`);
                else if (n.contrato_id) navegar(`/contratos?contrato=${n.contrato_id}`);
                else if (n.negocio_id) navegar(`/crm?negocio=${n.negocio_id}`);
              }}
              className={cn(
                "flex w-full gap-3 border-b px-4 py-3 text-left text-sm last:border-0 hover:bg-accent focus-visible:bg-accent focus-visible:outline-none",
                !n.lida_em && "bg-primary/5",
              )}
            >
              <span className={cn("mt-1.5 h-2 w-2 shrink-0 rounded-full", n.lida_em ? "bg-transparent" : "bg-marca")} aria-hidden />
              <span className="flex-1">
                <span className="block">{n.texto}</span>
                <span className="text-xs text-muted-foreground">{tempoRelativo(n.criado_em)}</span>
              </span>
            </button>
          ))}
        </div>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
