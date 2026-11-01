import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

const SUGESTOES = ["Preço", "Sem retorno do cliente", "Fechou com concorrente", "Desistiu do serviço", "Fora do perfil / região", "Duplicado"];

export function MotivoPerdaDialog({ aberto, titulo, onCancelar, onConfirmar }: { aberto: boolean; titulo: string; onCancelar: () => void; onConfirmar: (motivo: string) => void }) {
  const [motivo, setMotivo] = useState("");
  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onCancelar()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Por que o negócio foi perdido?</DialogTitle>
          <DialogDescription>{titulo}</DialogDescription>
        </DialogHeader>
        <div className="flex flex-wrap gap-2">
          {SUGESTOES.map((s) => (
            <Button key={s} type="button" size="sm" variant={motivo === s ? "default" : "outline"} onClick={() => setMotivo(s)}>
              {s}
            </Button>
          ))}
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="motivo">Motivo</Label>
          <Textarea id="motivo" value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Descreva o motivo" />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onCancelar}>
            Cancelar
          </Button>
          <Button
            variant="destructive"
            disabled={!motivo.trim()}
            onClick={() => {
              onConfirmar(motivo.trim());
              setMotivo("");
            }}
          >
            Marcar como perdido
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
