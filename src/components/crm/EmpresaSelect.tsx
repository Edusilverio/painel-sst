import { useEffect, useState } from "react";
import { Building2, Loader2, Plus, X } from "lucide-react";
import { NovaEmpresaDialog } from "@/components/dados/NovaEmpresa";
import { useSessao } from "@/contexts/sessao";
import { Input } from "@/components/ui/input";
import { useBuscaEmpresas } from "@/hooks/api";
import { fmtCnpj } from "@/lib/utils";

export interface EmpresaEscolhida {
  id: string;
  nome: string;
  cnpj: string | null;
}

/** Busca uma empresa da base (SESMO) por nome ou CNPJ. */
export function EmpresaSelect({ valor, onChange, id }: { valor: EmpresaEscolhida | null; onChange: (e: EmpresaEscolhida | null) => void; id?: string }) {
  const [texto, setTexto] = useState("");
  const [debounced, setDebounced] = useState("");
  const [aberto, setAberto] = useState(false);
  useEffect(() => {
    const t = setTimeout(() => setDebounced(texto), 300);
    return () => clearTimeout(t);
  }, [texto]);
  const busca = useBuscaEmpresas(debounced);
  const { tem } = useSessao();
  const podeCadastrar = tem("gestor", "comercial", "operacoes");
  const [nova, setNova] = useState(false);

  if (valor)
    return (
      <div className="flex items-center gap-2 rounded-md border bg-muted/40 px-3 py-2 text-sm">
        <Building2 className="h-4 w-4 text-primary" aria-hidden />
        <span className="flex-1 truncate">
          {valor.nome} {valor.cnpj && <span className="text-muted-foreground">· {fmtCnpj(valor.cnpj)}</span>}
        </span>
        <button type="button" onClick={() => onChange(null)} className="rounded p-0.5 hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" aria-label="Trocar empresa">
          <X className="h-4 w-4" />
        </button>
      </div>
    );

  return (
    <div className="relative">
      <Input
        id={id}
        placeholder="Buscar por nome ou CNPJ…"
        value={texto}
        onChange={(e) => {
          setTexto(e.target.value);
          setAberto(true);
        }}
        onFocus={() => setAberto(true)}
        onBlur={() => setTimeout(() => setAberto(false), 150)}
        autoComplete="off"
        role="combobox"
        aria-expanded={aberto}
      />
      {aberto && debounced.trim().length >= 2 && (
        <div className="absolute z-50 mt-1 max-h-64 w-full overflow-y-auto rounded-md border bg-popover p-1 shadow-md" role="listbox">
          {busca.isFetching && (
            <p className="flex items-center gap-2 px-2 py-2 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" /> Buscando…
            </p>
          )}
          {busca.isError && <p className="px-2 py-2 text-sm text-destructive">Falha na busca. Tente de novo.</p>}
          {busca.data && busca.data.length === 0 && !busca.isFetching && (
            <p className="px-2 py-2 text-sm text-muted-foreground">
              Nenhuma empresa encontrada.{podeCadastrar ? " Cadastre abaixo ou use \"Cliente novo\" se ainda é só um contato." : ' Use "Cliente novo".'}
            </p>
          )}
          {busca.data?.map((e) => (
            <button
              key={e.id}
              type="button"
              role="option"
              aria-selected={false}
              onMouseDown={(ev) => ev.preventDefault()}
              onClick={() => {
                onChange({ id: e.id, nome: e.nome, cnpj: e.cnpj });
                setTexto("");
                setAberto(false);
              }}
              className="block w-full rounded-sm px-2 py-1.5 text-left text-sm hover:bg-accent focus-visible:bg-accent focus-visible:outline-none"
            >
              <span className="block truncate font-medium">{e.nome}</span>
              <span className="block truncate text-xs text-muted-foreground">
                {fmtCnpj(e.cnpj)} {e.cidade && `· ${e.cidade}${e.uf ? `/${e.uf}` : ""}`}
              </span>
            </button>
          ))}
          {podeCadastrar && !busca.isFetching && (
            <button
              type="button"
              onMouseDown={(ev) => ev.preventDefault()}
              onClick={() => {
                setAberto(false);
                setNova(true);
              }}
              className="mt-1 flex w-full items-center gap-2 rounded-sm border-t px-2 py-2 text-left text-sm font-medium text-primary hover:bg-accent"
            >
              <Plus className="h-4 w-4" /> Cadastrar empresa nova
            </button>
          )}
        </div>
      )}
      <NovaEmpresaDialog
        aberto={nova}
        onFechar={() => setNova(false)}
        nomeInicial={texto}
        onCriada={(e) => {
          onChange({ id: e.id, nome: e.nome, cnpj: e.cnpj });
          setTexto("");
        }}
      />
    </div>
  );
}
