import { useNavigate } from "react-router-dom";
import { AlertTriangle, BadgeCheck, Building2, CalendarClock, ClipboardX, HandCoins, KanbanSquare, Stethoscope, TimerReset, Users } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { KpiCard } from "@/components/ui/kpi-card";
import { Skeleton } from "@/components/ui/skeleton";
import { EstadoErro } from "@/components/ui/estados";
import { useResumo } from "@/hooks/api";
import { useSessao } from "@/contexts/sessao";
import { corEtapa } from "@/lib/status";
import { cn, fmtMoeda, fmtNumero } from "@/lib/utils";

export default function VisaoGeral() {
  const { perfil } = useSessao();
  const r = useResumo();
  const navegar = useNavigate();
  const d = r.data;
  const carregando = r.isLoading;
  const maxEtapa = Math.max(1, ...(d?.funil_comercial ?? []).map((e) => e.qtd));
  // 0073: cada perfil vê os números que lhe cabem (comercial só os próprios; operações e leitura sem comercial)
  const meus = d?.escopo === "meus";
  const comComercial = carregando || d?.escopo !== "nenhum";

  return (
    <div className="mx-auto max-w-7xl space-y-6 p-4 sm:p-6">
      <Cabecalho titulo={`Olá, ${perfil?.nome?.split(" ")[0] ?? ""}`} descricao={
          meus ? "Seus negócios, sua carteira de clientes e os exames da Vitalis." : comComercial ? "Resumo do comercial, dos clientes e dos exames da Vitalis." : "Resumo dos clientes e dos exames da Vitalis."
        }
      />

      {r.isError ? (
        <EstadoErro erro={r.error} onTentar={() => r.refetch()} />
      ) : (
        <>
          {comComercial && (
          <section aria-label="Comercial" className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <KpiCard titulo={meus ? "Seus negócios abertos" : "Negócios abertos"} valor={fmtNumero(d?.negocios_abertos)} icone={KanbanSquare} carregando={carregando} onClick={() => navegar("/crm")} />
            <KpiCard
              titulo={meus ? "Seu valor em aberto" : "Em aberto no Comercial"}
              valor={fmtMoeda(d?.valor_aberto_comercial)}
              icone={HandCoins}
              tom="marca"
              carregando={carregando}
            />
            <KpiCard
              titulo={meus ? "Você fechou no mês" : "Fechados no mês"}
              valor={fmtNumero(d?.ganhos_mes)}
              detalhe={d ? fmtMoeda(d.valor_ganho_mes) : undefined}
              icone={BadgeCheck}
              tom="success"
              carregando={carregando}
            />
            <KpiCard
              titulo={meus ? "Seus negócios parados" : "Negócios parados"}
              valor={fmtNumero(d?.parados)}
              detalhe="Passaram do prazo da etapa"
              icone={TimerReset}
              tom={d && (d.parados ?? 0) > 0 ? "warning" : "primary"}
              carregando={carregando}
              onClick={() => navegar("/crm/pendencias")}
            />
          </section>
          )}

          <div className={cn("grid gap-4", comComercial && "lg:grid-cols-3")}>
            {comComercial && (
            <Card className="lg:col-span-2">
              <CardHeader>
                <CardTitle>{meus ? "Seu funil comercial" : "Funil comercial"}</CardTitle>
                <CardDescription>{meus ? "Seus negócios abertos por etapa" : "Negócios abertos por etapa"}</CardDescription>
              </CardHeader>
              <CardContent>
                {carregando ? (
                  <div className="space-y-3">
                    {Array.from({ length: 6 }).map((_, i) => (
                      <Skeleton key={i} className="h-7 w-full" />
                    ))}
                  </div>
                ) : !d?.funil_comercial.length ? (
                  <p className="text-sm text-muted-foreground">O funil comercial ainda não tem etapas configuradas.</p>
                ) : (
                  <ul className="space-y-2.5">
                    {d.funil_comercial.map((e) => (
                      <li key={e.etapa} className="grid grid-cols-[8.5rem_1fr_auto] items-center gap-3 text-sm sm:grid-cols-[10rem_1fr_7rem]">
                        <span className="truncate text-muted-foreground">{e.etapa}</span>
                        <span className="h-6 overflow-hidden rounded bg-muted">
                          <span
                            className={cn("block h-full rounded", corEtapa[e.cor]?.ponto ?? "bg-primary")}
                            style={{ width: `${Math.max(e.qtd ? 4 : 0, (e.qtd / maxEtapa) * 100)}%` }}
                          />
                        </span>
                        <span className="text-right tabular-nums">
                          <span className="font-semibold">{fmtNumero(e.qtd)}</span>
                          <span className="hidden text-xs text-muted-foreground sm:inline"> · {fmtMoeda(e.valor)}</span>
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </CardContent>
            </Card>
            )}

            <Card>
              <CardHeader>
                <CardTitle>{meus ? "Sua carteira" : "Base de clientes"}</CardTitle>
                <CardDescription>{meus ? "Empresas em que você é responsável por negócio ou contrato" : "Empresas da Vitalis"}</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3 text-sm">
                {carregando ? (
                  <Skeleton className="h-32 w-full" />
                ) : (
                  <>
                    <Linha rotulo="Empresas cadastradas" valor={d?.clientes_total} icone={Building2} />
                    <Linha rotulo="Ativas" valor={d?.clientes_ativos} />
                    <Linha rotulo="Sem contrato" valor={d?.clientes_sem_contrato} />
                    <Linha rotulo="Inativas" valor={d?.clientes_inativos} />
                    {!!d?.clientes_a_confirmar && (
                      <p className="rounded-md bg-muted p-2 text-xs text-muted-foreground">
                        {fmtNumero(d.clientes_a_confirmar)} empresas ainda sem situação definida — aguardando a Vitalis confirmar o de/para do SESMO.
                      </p>
                    )}
                    <Linha rotulo="Unidades" valor={d?.unidades} />
                    <Linha rotulo="Colaboradores ativos" valor={d?.colaboradores_ativos} icone={Users} />
                  </>
                )}
              </CardContent>
            </Card>
          </div>

          {(carregando || d?.acesso_clinico) && (() => {
            // sem PCMSO carregado os três contadores ficam zerados: mostra "em preparação" em vez de 0
            const semCalculo = !carregando && !d?.exames_vencidos && !d?.exames_30_dias && !d?.exames_60_dias;
            const exame = (v: number | null | undefined) => (semCalculo ? "—" : fmtNumero(v));
            return (
            <section aria-label="Saúde ocupacional" className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
              <KpiCard
                titulo="Exames vencidos"
                valor={exame(d?.exames_vencidos)}
                detalhe={semCalculo ? "Em preparação: aguardando o PCMSO do SESMO" : "Colaboradores com exame vencido ou nunca feito"}
                icone={ClipboardX}
                tom="destructive"
                carregando={carregando}
                onClick={() => navegar("/vencimentos?status=vencido")}
              />
              <KpiCard
                titulo="Vencem em 30 dias"
                valor={exame(d?.exames_30_dias)}
                detalhe={semCalculo ? "Em preparação" : undefined}
                icone={AlertTriangle}
                tom="warning"
                carregando={carregando}
                onClick={() => navegar("/vencimentos?status=vence_em_30_dias")}
              />
              <KpiCard
                titulo="Vencem em 60 dias"
                valor={exame(d?.exames_60_dias)}
                detalhe={semCalculo ? "Em preparação" : undefined}
                icone={CalendarClock}
                tom="info"
                carregando={carregando}
                onClick={() => navegar("/vencimentos?status=vence_em_60_dias")}
              />
              <KpiCard
                titulo="Atendimentos no mês"
                valor={fmtNumero(d?.atendimentos_mes)}
                icone={Stethoscope}
                carregando={carregando}
                onClick={() => navegar("/atendimentos")}
              />
            </section>
            );
          })()}
        </>
      )}
    </div>
  );
}

function Linha({ rotulo, valor, icone: Icone }: { rotulo: string; valor: number | undefined | null; icone?: typeof Users }) {
  return (
    <div className="flex items-center justify-between gap-2">
      <span className="flex items-center gap-2 text-muted-foreground">
        {Icone && <Icone className="h-4 w-4" aria-hidden />}
        {rotulo}
      </span>
      <span className="font-semibold tabular-nums">{fmtNumero(valor)}</span>
    </div>
  );
}
