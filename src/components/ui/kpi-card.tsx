import type { LucideIcon } from "lucide-react";
import { Card } from "./card";
import { Skeleton } from "./skeleton";
import { cn } from "@/lib/utils";

type Tom = "primary" | "success" | "warning" | "destructive" | "info" | "marca";
const tons: Record<Tom, string> = {
  primary: "bg-primary/10 text-primary",
  success: "bg-success/15 text-success",
  warning: "bg-warning/15 text-warning",
  destructive: "bg-destructive/15 text-destructive",
  info: "bg-info/15 text-info",
  marca: "bg-marca/15 text-marca",
};

/** Indicador. `carregando` mostra esqueleto — nunca zero no lugar de "ainda não sei". */
export function KpiCard({
  titulo,
  valor,
  detalhe,
  icone: Icone,
  tom = "primary",
  carregando,
  onClick,
}: {
  titulo: string;
  valor: React.ReactNode;
  detalhe?: React.ReactNode;
  icone: LucideIcon;
  tom?: Tom;
  carregando?: boolean;
  onClick?: () => void;
}) {
  const Corpo = (
    <div className="flex items-start gap-4 p-5">
      <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-lg", tons[tom])}>
        <Icone className="h-5 w-5" aria-hidden />
      </div>
      <div className="min-w-0 flex-1">
        <p className="text-sm text-muted-foreground">{titulo}</p>
        {carregando ? <Skeleton className="mt-1 h-7 w-20" /> : <p className="text-2xl font-bold tabular-nums">{valor}</p>}
        {detalhe && !carregando && <p className="mt-0.5 truncate text-xs text-muted-foreground">{detalhe}</p>}
      </div>
    </div>
  );
  if (onClick)
    return (
      <Card className="transition-colors hover:border-primary/40">
        <button type="button" onClick={onClick} className="w-full rounded-lg text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
          {Corpo}
        </button>
      </Card>
    );
  return <Card>{Corpo}</Card>;
}
