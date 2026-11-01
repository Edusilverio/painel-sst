import { cn } from "@/lib/utils";

/** Marca Vitalis em texto (sem depender de imagem): selo vinho + nome. */
export function Marca({ compacta, className }: { compacta?: boolean; className?: string }) {
  return (
    <div className={cn("flex items-center gap-3", className)}>
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-white/95 text-[hsl(342_100%_26%)] shadow-sm ring-2 ring-white/20">
        <span className="font-display text-lg leading-none tracking-wide">V</span>
      </div>
      {!compacta && (
        <div className="leading-tight">
          <p className="font-display text-2xl leading-none tracking-wider">Vitalis</p>
          <p className="text-[10px] uppercase tracking-[0.12em] opacity-80">Medicina e Engenharia do Trabalho</p>
        </div>
      )}
    </div>
  );
}
