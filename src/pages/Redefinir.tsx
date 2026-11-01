import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/lib/supabase";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export default function Redefinir() {
  const [senha, setSenha] = useState("");
  const [enviando, setEnviando] = useState(false);
  const navegar = useNavigate();

  async function salvar(e: React.FormEvent) {
    e.preventDefault();
    if (senha.length < 8) return toast.error("A senha precisa ter pelo menos 8 caracteres.");
    setEnviando(true);
    const { error } = await supabase.auth.updateUser({ password: senha });
    setEnviando(false);
    if (error) return toast.error("Não foi possível trocar a senha. Peça um novo link e tente de novo.");
    toast.success("Senha atualizada");
    navegar("/", { replace: true });
  }

  return (
    <div className="flex min-h-full items-center justify-center p-6">
      <form onSubmit={salvar} className="w-full max-w-sm space-y-4">
        <h1 className="text-2xl font-semibold">Criar nova senha</h1>
        <div className="space-y-1.5">
          <Label htmlFor="nova">Nova senha</Label>
          <Input id="nova" type="password" minLength={8} value={senha} onChange={(e) => setSenha(e.target.value)} required autoComplete="new-password" />
        </div>
        <Button type="submit" className="w-full" disabled={enviando}>
          {enviando && <Loader2 className="animate-spin" />} Salvar senha
        </Button>
      </form>
    </div>
  );
}
