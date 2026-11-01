import { useParams } from "react-router-dom";
import { CalendarDays, FileSignature, MessageCircle, Wallet, type LucideIcon } from "lucide-react";
import { Cabecalho } from "@/components/layout/AppLayout";
import { Card, CardContent } from "@/components/ui/card";

const MODULOS: Record<string, { titulo: string; icone: LucideIcon; itens: string[] }> = {
  agenda: {
    titulo: "Agenda",
    icone: CalendarDays,
    itens: [
      "Agenda por profissional e por dia, substituindo a planilha de agendamento",
      "Regra de agendamento por empresa (limite por dia e bloqueio de inadimplente)",
      "Legenda que a equipe já conhece: agendado, aguardando, atendido, finalizado",
      "Integração com Google Agenda",
    ],
  },
  whatsapp: {
    titulo: "WhatsApp",
    icone: MessageCircle,
    itens: [
      "Atendimento do número 5575 com triagem por IA",
      "Encaminhamento para comercial, faturamento, área técnica, atendimento e eSocial",
      "Respostas padrão: atraso, segunda via de boleto/nota, pedido de documento",
      "Lead que chega pelo WhatsApp vira negócio no funil Comercial",
    ],
  },
  financeiro: {
    titulo: "Financeiro",
    icone: Wallet,
    itens: ["Contas a receber e boletos (histórico desde 2020)", "Notas fiscais em PDF", "Contratos: valor fixo e por colaborador", "Alerta de renovação e reajuste 30–60 dias antes"],
  },
  contratos: {
    titulo: "Contratos e assinatura",
    icone: FileSignature,
    itens: ["Modelos de contrato", "Envio para assinatura e acompanhamento (rascunho, enviado, parcialmente assinado, assinado)", "Contrato assinado arquivado no cliente"],
  },
};

export default function EmBreve() {
  const { modulo = "" } = useParams();
  const m = MODULOS[modulo] ?? { titulo: "Módulo", icone: CalendarDays, itens: [] };
  return (
    <div className="mx-auto max-w-3xl space-y-6 p-4 sm:p-6">
      <Cabecalho titulo={m.titulo} selo="Em construção" descricao="Este módulo está nas próximas etapas. O que está previsto:" />
      <Card>
        <CardContent className="pt-5">
          <ul className="space-y-3">
            {m.itens.map((it) => (
              <li key={it} className="flex gap-3 text-sm">
                <m.icone className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
                {it}
              </li>
            ))}
          </ul>
          <p className="mt-6 text-sm text-muted-foreground">Tem algo que precisa entrar aqui? Fale com a equipe da Exemplo — este painel é construído com a Vitalis, etapa por etapa.</p>
        </CardContent>
      </Card>
    </div>
  );
}
