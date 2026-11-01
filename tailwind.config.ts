import type { Config } from "tailwindcss";
import animate from "tailwindcss-animate";

const tok = (n: string) => `hsl(var(--${n}))`;
const par = (n: string) => ({ DEFAULT: tok(n), foreground: tok(`${n}-foreground`) });

export default {
  darkMode: ["class"],
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    container: { center: true, padding: "1.5rem" },
    extend: {
      fontFamily: {
        sans: ["Inter", "system-ui", "sans-serif"],
        display: ["'Bebas Neue'", "Inter", "sans-serif"],
      },
      colors: {
        border: tok("border"),
        input: tok("input"),
        ring: tok("ring"),
        background: tok("background"),
        foreground: tok("foreground"),
        primary: par("primary"),
        secondary: par("secondary"),
        destructive: par("destructive"),
        muted: par("muted"),
        accent: par("accent"),
        popover: par("popover"),
        card: par("card"),
        success: par("success"),
        warning: par("warning"),
        info: par("info"),
        marca: par("marca"),
        sidebar: {
          DEFAULT: tok("sidebar"),
          foreground: tok("sidebar-foreground"),
          accent: tok("sidebar-accent"),
          "accent-foreground": tok("sidebar-accent-foreground"),
          border: tok("sidebar-border"),
          muted: tok("sidebar-muted"),
        },
      },
      borderRadius: {
        lg: "var(--radius)",
        md: "calc(var(--radius) - 2px)",
        sm: "calc(var(--radius) - 4px)",
      },
    },
  },
  plugins: [animate],
} satisfies Config;
