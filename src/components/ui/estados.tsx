import type { LucideIcon } from "lucide-react";
import { AlertTriangle, Inbox } from "lucide-react";
import { Button } from "./button";
import { cn } from "@/lib/utils";

/** Vazio: explica por que está vazio e, quando houver, oferece a ação. */
export function EstadoVazio({
  icone: Icone = Inbox,
  titulo,
  texto,
  acao,
  className,
}: {
  icone?: LucideIcon;
  titulo: string;
  texto?: string;
  acao?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col items-center justify-center gap-2 rounded-lg border border-dashed p-10 text-center", className)}>
      <Icone className="h-8 w-8 text-muted-foreground" aria-hidden />
      <p className="font-medium">{titulo}</p>
      {texto && <p className="max-w-md text-sm text-muted-foreground">{texto}</p>}
      {acao && <div className="mt-2">{acao}</div>}
    </div>
  );
}

/** Erro de carregamento de seção: visível, em português, com como sair dele. */
export function EstadoErro({ erro, onTentar, className }: { erro: unknown; onTentar?: () => void; className?: string }) {
  const msg = erro instanceof Error ? erro.message : "Não foi possível carregar.";
  return (
    <div className={cn("flex flex-col items-start gap-3 rounded-lg border border-destructive/40 bg-destructive/5 p-5 sm:flex-row sm:items-center", className)} role="alert">
      <AlertTriangle className="h-5 w-5 shrink-0 text-destructive" aria-hidden />
      <div className="flex-1">
        <p className="font-medium text-destructive">Não foi possível carregar esta seção</p>
        <p className="text-sm text-muted-foreground">{msg}</p>
      </div>
      {onTentar && (
        <Button variant="outline" size="sm" onClick={onTentar}>
          Tentar de novo
        </Button>
      )}
    </div>
  );
}
