import { useState } from "react";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";
import { supabase, traduzErro } from "@/lib/supabase";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Marca } from "@/components/layout/Marca";

type Modo = "entrar" | "cadastrar" | "recuperar";

function traduzAuth(msg: string) {
  if (/invalid login credentials/i.test(msg)) return "E-mail ou senha incorretos.";
  if (/email not confirmed/i.test(msg)) return "Confirme seu e-mail pelo link que enviamos antes de entrar.";
  if (/already registered/i.test(msg)) return "Este e-mail já tem cadastro. Use \"Entrar\" ou recupere a senha.";
  if (/password should be at least/i.test(msg)) return "A senha precisa ter pelo menos 8 caracteres.";
  if (/rate limit/i.test(msg)) return "Muitas tentativas. Aguarde alguns minutos e tente de novo.";
  return traduzErro(msg);
}

export default function Entrar() {
  const [modo, setModo] = useState<Modo>("entrar");
  const [nome, setNome] = useState("");
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [aviso, setAviso] = useState<string | null>(null);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setEnviando(true);
    setAviso(null);
    try {
      if (modo === "entrar") {
        const { error } = await supabase.auth.signInWithPassword({ email, password: senha });
        if (error) throw error;
      } else if (modo === "cadastrar") {
        if (senha.length < 8) throw new Error("A senha precisa ter pelo menos 8 caracteres.");
        const { data, error } = await supabase.auth.signUp({
          email,
          password: senha,
          options: { data: { nome, app: (import.meta.env.VITE_APP_ID as string | undefined) || "painel" }, emailRedirectTo: window.location.origin },
        });
        if (error) throw error;
        if (!data.session) setAviso("Cadastro feito. Confirme seu e-mail pelo link que enviamos; depois um administrador libera seu acesso.");
      } else {
        const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo: `${window.location.origin}/redefinir-senha` });
        if (error) throw error;
        setAviso("Se este e-mail tiver cadastro, você vai receber um link para criar uma nova senha.");
      }
    } catch (err) {
      toast.error(traduzAuth(err instanceof Error ? err.message : String(err)));
    } finally {
      setEnviando(false);
    }
  }

  return (
    <div className="grid min-h-full lg:grid-cols-2">
      <div className="relative hidden flex-col justify-between overflow-hidden bg-sidebar p-10 text-sidebar-foreground lg:flex">
        <Marca />
        <div className="relative z-10 max-w-md">
          <p className="font-display text-5xl leading-none tracking-wide">Seus clientes, contratos e exames em um só lugar.</p>
          <p className="mt-4 text-sm text-sidebar-muted">CRM, vencimento de exames e histórico de atendimentos da Vitalis — com os dados sob controle da própria Vitalis.</p>
        </div>
        <p className="text-xs text-sidebar-muted">Desenvolvido pela Exemplo Consultoria</p>
        <div className="pointer-events-none absolute -bottom-24 -right-24 h-80 w-80 rounded-full bg-marca/30 blur-3xl" aria-hidden />
      </div>

      <div className="flex items-center justify-center p-6">
        <div className="w-full max-w-sm">
          <div className="mb-8 rounded-lg bg-sidebar p-4 text-sidebar-foreground lg:hidden">
            <Marca />
          </div>
          <h1 className="text-2xl font-semibold tracking-tight">
            {modo === "entrar" ? "Entrar no painel" : modo === "cadastrar" ? "Criar acesso" : "Recuperar senha"}
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {modo === "cadastrar" ? "Depois do cadastro, um administrador da Vitalis libera o seu acesso." : "Use o e-mail cadastrado na Vitalis."}
          </p>

          {aviso ? (
            <div className="mt-6 rounded-lg border border-info/40 bg-info/10 p-4 text-sm">{aviso}</div>
          ) : (
            <form onSubmit={enviar} className="mt-6 space-y-4">
              {modo === "cadastrar" && (
                <div className="space-y-1.5">
                  <Label htmlFor="nome">Nome</Label>
                  <Input id="nome" value={nome} onChange={(e) => setNome(e.target.value)} required autoComplete="name" />
                </div>
              )}
              <div className="space-y-1.5">
                <Label htmlFor="email">E-mail</Label>
                <Input id="email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required autoComplete="email" />
              </div>
              {modo !== "recuperar" && (
                <div className="space-y-1.5">
                  <Label htmlFor="senha">Senha</Label>
                  <Input
                    id="senha"
                    type="password"
                    value={senha}
                    onChange={(e) => setSenha(e.target.value)}
                    required
                    minLength={modo === "cadastrar" ? 8 : undefined}
                    autoComplete={modo === "entrar" ? "current-password" : "new-password"}
                  />
                </div>
              )}
              <Button type="submit" className="w-full" disabled={enviando}>
                {enviando && <Loader2 className="animate-spin" />}
                {modo === "entrar" ? "Entrar" : modo === "cadastrar" ? "Criar acesso" : "Enviar link"}
              </Button>
            </form>
          )}

          <div className="mt-6 flex flex-col gap-2 text-sm">
            {modo !== "entrar" && (
              <button type="button" className="text-left text-primary hover:underline" onClick={() => { setModo("entrar"); setAviso(null); }}>
                Já tenho acesso — entrar
              </button>
            )}
            {modo !== "cadastrar" && (
              <button type="button" className="text-left text-primary hover:underline" onClick={() => { setModo("cadastrar"); setAviso(null); }}>
                Primeiro acesso? Criar cadastro
              </button>
            )}
            {modo !== "recuperar" && (
              <button type="button" className="text-left text-muted-foreground hover:underline" onClick={() => { setModo("recuperar"); setAviso(null); }}>
                Esqueci minha senha
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
