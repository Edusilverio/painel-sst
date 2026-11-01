import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "./button";
import { fmtNumero } from "@/lib/utils";

export function Paginacao({ pagina, porPagina, total, onMudar }: { pagina: number; porPagina: number; total: number; onMudar: (p: number) => void }) {
  if (total <= porPagina) return total > 0 ? <p className="text-sm text-muted-foreground">{fmtNumero(total)} registro(s)</p> : null;
  const paginas = Math.ceil(total / porPagina);
  return (
    <div className="flex items-center justify-between gap-2 text-sm">
      <p className="text-muted-foreground">
        {fmtNumero(pagina * porPagina + 1)}–{fmtNumero(Math.min(total, (pagina + 1) * porPagina))} de {fmtNumero(total)}
      </p>
      <div className="flex items-center gap-1">
        <Button variant="outline" size="icon" disabled={pagina === 0} onClick={() => onMudar(pagina - 1)} aria-label="Página anterior">
          <ChevronLeft />
        </Button>
        <span className="px-2 tabular-nums">
          {pagina + 1} / {paginas}
        </span>
        <Button variant="outline" size="icon" disabled={pagina + 1 >= paginas} onClick={() => onMudar(pagina + 1)} aria-label="Próxima página">
          <ChevronRight />
        </Button>
      </div>
    </div>
  );
}
