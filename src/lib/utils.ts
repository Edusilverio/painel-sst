import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

const moeda = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const numero = new Intl.NumberFormat("pt-BR");

export const fmtMoeda = (v: number | null | undefined) => (v == null ? "—" : moeda.format(v));
export const fmtNumero = (v: number | null | undefined) => (v == null ? "—" : numero.format(v));

/** Datas vindas do Postgres como 'AAAA-MM-DD' não podem passar por new Date() cru: viram UTC e voltam um dia. */
export function fmtData(v: string | null | undefined) {
  if (!v) return "—";
  const [a, m, d] = v.slice(0, 10).split("-");
  return `${d}/${m}/${a}`;
}

export function fmtDataHora(v: string | null | undefined) {
  if (!v) return "—";
  return new Date(v).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

export function tempoRelativo(v: string | null | undefined) {
  if (!v) return "—";
  const dias = Math.floor((Date.now() - new Date(v).getTime()) / 86_400_000);
  if (dias <= 0) return "hoje";
  if (dias === 1) return "há 1 dia";
  return `há ${dias} dias`;
}

export function iniciais(nome: string | null | undefined) {
  if (!nome) return "?";
  const partes = nome.split(/\s+/).filter((p) => p && !/^(de|da|do|dos|das|e)$/i.test(p));
  return ((partes[0]?.[0] ?? "") + (partes.length > 1 ? partes[partes.length - 1][0] : "")).toUpperCase() || "?";
}

export function fmtCnpj(v: string | null | undefined) {
  if (!v) return "—";
  const d = v.replace(/\D/g, "");
  if (d.length !== 14) return v;
  return d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5");
}

/** Exporta linhas para CSV (separador ; e BOM, para abrir certo no Excel em pt-BR). */
export function baixarCsv(nome: string, linhas: Record<string, unknown>[]) {
  if (!linhas.length) return;
  const cols = Object.keys(linhas[0]);
  const esc = (x: unknown) => {
    const s = x == null ? "" : String(x);
    return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const csv = [cols.join(";"), ...linhas.map((l) => cols.map((c) => esc(l[c])).join(";"))].join("\n");
  const url = URL.createObjectURL(new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = nome.endsWith(".csv") ? nome : `${nome}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

// ------------------------------------------------------------------ datas da agenda (sempre 'AAAA-MM-DD' local)

const pad = (n: number) => String(n).padStart(2, "0");
export const isoLocal = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
export const hojeIso = () => isoLocal(new Date());
/** Meio-dia local: somar dias nunca pula por causa de horário de verão. */
export const dataDeIso = (iso: string) => {
  const [a, m, d] = iso.split("-").map(Number);
  return new Date(a, m - 1, d, 12);
};
export const somaDias = (iso: string, n: number) => {
  const d = dataDeIso(iso);
  d.setDate(d.getDate() + n);
  return isoLocal(d);
};
/** Segunda-feira da semana da data. */
export const inicioSemana = (iso: string) => somaDias(iso, -((dataDeIso(iso).getDay() + 6) % 7));
export const fmtDiaSemana = (iso: string, estilo: "long" | "short" = "long") =>
  dataDeIso(iso).toLocaleDateString("pt-BR", { weekday: estilo });
export const fmtDataLonga = (iso: string) =>
  dataDeIso(iso).toLocaleDateString("pt-BR", { weekday: "long", day: "2-digit", month: "long", year: "numeric" });
export const fmtHora = (v: string | null | undefined) => (v ? new Date(v).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }) : "—");

export function fmtCpf(v: string | null | undefined) {
  if (!v) return "";
  const d = v.replace(/\D/g, "");
  return d.length === 11 ? d.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, "$1.$2.$3-$4") : v;
}
