import { Link } from "react-router-dom";
import { Clock, Lock, SearchX, ServerCog } from "lucide-react";
import { useSessao } from "@/contexts/sessao";
import { Button } from "@/components/ui/button";
import { Marca } from "@/components/layout/Marca";

function Tela({ icone: Icone, titulo, texto, children }: { icone: typeof Clock; titulo: string; texto: string; children?: React.ReactNode }) {
  return (
    <div className="flex min-h-full flex-col items-center justify-center gap-4 p-6 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-full bg-primary/10 text-primary">
        <Icone className="h-7 w-7" aria-hidden />
      </div>
      <h1 className="text-xl font-semibold">{titulo}</h1>
      <p className="max-w-md text-sm text-muted-foreground">{texto}</p>
      {children}
    </div>
  );
}

export function Aguardando() {
  const { estado, perfil, erro, sair, recarregar } = useSessao();
  if (estado === "erro")
    return (
      <Tela icone={ServerCog} titulo="Não foi possível abrir o painel" texto={erro ?? "Falha ao carregar seu perfil."}>
        <div className="flex gap-2">
          <Button onClick={() => recarregar()}>Tentar de novo</Button>
          <Button variant="outline" onClick={() => sair()}>Sair</Button>
        </div>
      </Tela>
    );
  return (
    <div className="flex min-h-full flex-col">
      <div className="bg-sidebar px-6 py-4 text-sidebar-foreground">
        <Marca />
      </div>
      <Tela
        icone={Clock}
        titulo="Seu acesso está aguardando liberação"
        texto={`Olá${perfil?.nome ? `, ${perfil.nome}` : ""}! Seu cadastro foi recebido. Um administrador da Vitalis precisa liberar o acesso e definir o seu perfil. Assim que isso acontecer, é só entrar de novo.`}
      >
        <div className="flex gap-2">
          <Button onClick={() => recarregar()}>Já fui liberado</Button>
          <Button variant="outline" onClick={() => sair()}>Sair</Button>
        </div>
      </Tela>
    </div>
  );
}

export function NaoConfigurado() {
  return (
    <Tela
      icone={ServerCog}
      titulo="Painel sem conexão configurada"
      texto="As variáveis VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY não foram definidas nesta publicação. Avise a equipe da Exemplo."
    />
  );
}

export function SemPermissao() {
  return (
    <Tela icone={Lock} titulo="Sem permissão para esta área" texto="Seu perfil não tem acesso a esta tela. Se precisar, peça ao administrador da Vitalis.">
      <Button asChild variant="outline">
        <Link to="/">Voltar à visão geral</Link>
      </Button>
    </Tela>
  );
}

export function NaoEncontrada() {
  return (
    <Tela icone={SearchX} titulo="Página não encontrada" texto="O endereço não existe ou mudou.">
      <Button asChild variant="outline">
        <Link to="/">Voltar à visão geral</Link>
      </Button>
    </Tela>
  );
}
