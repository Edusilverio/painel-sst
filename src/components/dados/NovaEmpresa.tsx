import { useEffect, useState } from "react";
import { Building2, Loader2, Search } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useSalvarDados } from "@/hooks/api";
import { fmtCnpj } from "@/lib/utils";

export interface EmpresaCriada {
  id: string;
  nome: string;
  cnpj: string | null;
}

interface Resultado {
  id: string;
  nome: string;
  existente: boolean;
  visivel: boolean;
  cards_ligados?: number;
}

const VAZIO = {
  cnpj: "",
  razao_social: "",
  nome_fantasia: "",
  telefone: "",
  email: "",
  cep: "",
  logradouro: "",
  numero: "",
  complemento: "",
  bairro: "",
  cidade: "",
  uf: "",
  cnae_principal: "",
};
const CONTATO = { nome: "", cargo: "", telefone: "", email: "" };

const digitos = (v: string) => v.replace(/\D/g, "");

/** Telefone da Receita vem como "1133334444" (DDD + número). */
function telReceita(v: unknown) {
  const d = digitos(String(v ?? ""));
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
  return d;
}

/**
 * Cadastro de empresa nova direto no painel (pedido do Jorge, 08/10), sem precisar de card no CRM.
 * Com o CNPJ, busca os dados públicos na Receita (BrasilAPI) para não digitar tudo.
 */
export function NovaEmpresaDialog({
  aberto,
  onFechar,
  onCriada,
  nomeInicial,
}: {
  aberto: boolean;
  onFechar: () => void;
  onCriada: (e: EmpresaCriada) => void;
  nomeInicial?: string;
}) {
  const salvar = useSalvarDados();
  const [f, setF] = useState(VAZIO);
  const [ct, setCt] = useState(CONTATO);
  const [buscando, setBuscando] = useState(false);
  const [situacaoReceita, setSituacaoReceita] = useState<string | null>(null);
  const [gravando, setGravando] = useState(false);

  useEffect(() => {
    if (!aberto) return;
    const n = (nomeInicial ?? "").trim();
    const soNumero = digitos(n).length >= 11 && /^[\d./\-\s]+$/.test(n);
    setF({ ...VAZIO, ...(soNumero ? { cnpj: n } : { razao_social: n }) });
    setCt(CONTATO);
    setSituacaoReceita(null);
  }, [aberto, nomeInicial]);

  const set = (k: keyof typeof VAZIO) => (e: React.ChangeEvent<HTMLInputElement>) => setF((x) => ({ ...x, [k]: e.target.value }));
  const setC = (k: keyof typeof CONTATO) => (e: React.ChangeEvent<HTMLInputElement>) => setCt((x) => ({ ...x, [k]: e.target.value }));
  const cnpj = digitos(f.cnpj);

  async function buscarReceita() {
    if (cnpj.length !== 14) return toast.error("Digite os 14 números do CNPJ.");
    setBuscando(true);
    try {
      const r = await fetch(`https://brasilapi.com.br/api/cnpj/v1/${cnpj}`);
      if (r.status === 404) throw new Error("CNPJ não encontrado na Receita.");
      if (!r.ok) throw new Error("A consulta à Receita não respondeu. Preencha à mão.");
      const d = await r.json();
      const rua = [d.descricao_tipo_de_logradouro, d.logradouro].filter(Boolean).join(" ");
      setF((x) => ({
        ...x,
        razao_social: d.razao_social ?? x.razao_social,
        nome_fantasia: d.nome_fantasia || x.nome_fantasia,
        telefone: telReceita(d.ddd_telefone_1) || x.telefone,
        email: (d.email ?? "").toLowerCase() || x.email,
        cep: d.cep ? String(d.cep) : x.cep,
        logradouro: rua || x.logradouro,
        numero: d.numero ?? x.numero,
        complemento: d.complemento ?? x.complemento,
        bairro: d.bairro ?? x.bairro,
        cidade: d.municipio ?? x.cidade,
        uf: d.uf ?? x.uf,
        cnae_principal: d.cnae_fiscal ? `${d.cnae_fiscal}${d.cnae_fiscal_descricao ? ` - ${d.cnae_fiscal_descricao}` : ""}` : x.cnae_principal,
      }));
      setSituacaoReceita(d.descricao_situacao_cadastral ?? null);
      toast.success("Dados da Receita preenchidos. Confira antes de salvar.");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Falha na consulta.");
    } finally {
      setBuscando(false);
    }
  }

  async function gravar(e: React.FormEvent) {
    e.preventDefault();
    e.stopPropagation(); // o diálogo pode abrir de dentro do formulário de novo negócio (eventos do React atravessam o portal)
    if (!f.razao_social.trim()) return toast.error("Informe a razão social.");
    setGravando(true);
    try {
      const r = await salvar<Resultado>("painel_empresa_criar", { p_dados: f, p_contato: ct.nome.trim() ? ct : null });
      if (r.existente) {
        if (!r.visivel) {
          toast.error(`Esse CNPJ já está cadastrado (${r.nome}) na carteira de outro consultor. Fale com o gestor.`);
          return;
        }
        toast.info(`Essa empresa já estava cadastrada: ${r.nome}.`);
      } else {
        toast.success(
          `Empresa cadastrada${r.cards_ligados ? ` e ligada a ${r.cards_ligados} card${r.cards_ligados > 1 ? "s" : ""} do CRM com o mesmo CNPJ` : ""}.`,
        );
      }
      onCriada({ id: r.id, nome: r.nome, cnpj: cnpj || null });
      onFechar();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Não foi possível cadastrar.");
    } finally {
      setGravando(false);
    }
  }

  const campo = (k: keyof typeof VAZIO, rotulo: string, extra?: { classe?: string; tipo?: string; ph?: string; obrig?: boolean }) => (
    <div className={`space-y-1.5 ${extra?.classe ?? ""}`}>
      <Label htmlFor={`ne-${k}`}>
        {rotulo}
        {extra?.obrig && <span className="text-destructive"> *</span>}
      </Label>
      <Input id={`ne-${k}`} type={extra?.tipo ?? "text"} value={f[k]} onChange={set(k)} placeholder={extra?.ph} required={extra?.obrig} />
    </div>
  );

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
        <form onSubmit={gravar}>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Building2 className="h-5 w-5 text-primary" aria-hidden /> Nova empresa
            </DialogTitle>
            <DialogDescription>
              Cadastro direto na base de clientes, sem precisar criar card. Comece pelo CNPJ: os dados da Receita vêm preenchidos.
            </DialogDescription>
          </DialogHeader>

          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="ne-cnpj">CNPJ</Label>
              <div className="flex gap-2">
                <Input
                  id="ne-cnpj"
                  value={f.cnpj}
                  onChange={set("cnpj")}
                  onBlur={() => cnpj.length === 14 && setF((x) => ({ ...x, cnpj: fmtCnpj(cnpj) }))}
                  placeholder="00.000.000/0000-00"
                  inputMode="numeric"
                  className="sm:w-56"
                />
                <Button type="button" variant="outline" onClick={buscarReceita} disabled={buscando || cnpj.length !== 14}>
                  {buscando ? <Loader2 className="animate-spin" /> : <Search />} Buscar na Receita
                </Button>
                {situacaoReceita && (
                  <Badge variant={situacaoReceita.toUpperCase() === "ATIVA" ? "success" : "destructive"} className="self-center">
                    Receita: {situacaoReceita}
                  </Badge>
                )}
              </div>
            </div>
            {campo("razao_social", "Razão social", { classe: "sm:col-span-2", obrig: true })}
            {campo("nome_fantasia", "Nome fantasia")}
            {campo("cnae_principal", "CNAE principal")}
            {campo("telefone", "Telefone")}
            {campo("email", "E-mail", { tipo: "email" })}
            {campo("cep", "CEP")}
            {campo("logradouro", "Logradouro")}
            {campo("numero", "Número")}
            {campo("complemento", "Complemento")}
            {campo("bairro", "Bairro")}
            <div className="grid grid-cols-[1fr_5rem] gap-3">
              {campo("cidade", "Cidade")}
              {campo("uf", "UF", { ph: "SP" })}
            </div>
          </div>

          <fieldset className="mt-5 grid gap-3 rounded-lg border p-3 sm:grid-cols-2">
            <legend className="px-1 text-sm font-medium">Contato principal (opcional)</legend>
            <div className="space-y-1.5">
              <Label htmlFor="ne-ct-nome">Nome</Label>
              <Input id="ne-ct-nome" value={ct.nome} onChange={setC("nome")} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ne-ct-cargo">Cargo</Label>
              <Input id="ne-ct-cargo" value={ct.cargo} onChange={setC("cargo")} placeholder="RH, financeiro…" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ne-ct-tel">Telefone / WhatsApp</Label>
              <Input id="ne-ct-tel" value={ct.telefone} onChange={setC("telefone")} inputMode="tel" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ne-ct-mail">E-mail</Label>
              <Input id="ne-ct-mail" type="email" value={ct.email} onChange={setC("email")} />
            </div>
          </fieldset>

          <DialogFooter className="mt-5">
            <Button type="button" variant="outline" onClick={onFechar}>
              Cancelar
            </Button>
            <Button type="submit" disabled={gravando || !f.razao_social.trim()}>
              {gravando && <Loader2 className="animate-spin" />} Cadastrar empresa
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
