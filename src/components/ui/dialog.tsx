import * as React from "react";
import * as D from "@radix-ui/react-dialog";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

export const Dialog = D.Root;
export const DialogTrigger = D.Trigger;
export const DialogClose = D.Close;

const Overlay = React.forwardRef<React.ElementRef<typeof D.Overlay>, React.ComponentPropsWithoutRef<typeof D.Overlay>>(({ className, ...p }, ref) => (
  <D.Overlay ref={ref} className={cn("fixed inset-0 z-50 bg-black/60 data-[state=open]:animate-in data-[state=open]:fade-in-0", className)} {...p} />
));
Overlay.displayName = "DialogOverlay";

export const DialogContent = React.forwardRef<React.ElementRef<typeof D.Content>, React.ComponentPropsWithoutRef<typeof D.Content>>(
  ({ className, children, ...p }, ref) => (
    <D.Portal>
      <Overlay />
      <D.Content
        ref={ref}
        className={cn(
          "fixed left-1/2 top-1/2 z-50 grid max-h-[90vh] w-[calc(100%-2rem)] max-w-lg -translate-x-1/2 -translate-y-1/2 gap-4 overflow-y-auto rounded-lg border bg-card p-6 shadow-lg data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:zoom-in-95",
          className,
        )}
        {...p}
      >
        {children}
        <D.Close className="absolute right-4 top-4 rounded-sm opacity-70 transition-opacity hover:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" aria-label="Fechar">
          <X className="h-4 w-4" />
        </D.Close>
      </D.Content>
    </D.Portal>
  ),
);
DialogContent.displayName = "DialogContent";

export const DialogHeader = ({ className, ...p }: React.HTMLAttributes<HTMLDivElement>) => <div className={cn("flex flex-col gap-1.5 pr-6", className)} {...p} />;
export const DialogFooter = ({ className, ...p }: React.HTMLAttributes<HTMLDivElement>) => (
  <div className={cn("flex flex-col-reverse gap-2 sm:flex-row sm:justify-end", className)} {...p} />
);
export const DialogTitle = React.forwardRef<React.ElementRef<typeof D.Title>, React.ComponentPropsWithoutRef<typeof D.Title>>(({ className, ...p }, ref) => (
  <D.Title ref={ref} className={cn("text-lg font-semibold", className)} {...p} />
));
DialogTitle.displayName = "DialogTitle";
export const DialogDescription = React.forwardRef<React.ElementRef<typeof D.Description>, React.ComponentPropsWithoutRef<typeof D.Description>>(
  ({ className, ...p }, ref) => <D.Description ref={ref} className={cn("text-sm text-muted-foreground", className)} {...p} />,
);
DialogDescription.displayName = "DialogDescription";

/** Painel lateral (mesma base do Dialog), usado no detalhe do negócio. */
export const SheetContent = React.forwardRef<React.ElementRef<typeof D.Content>, React.ComponentPropsWithoutRef<typeof D.Content>>(
  ({ className, children, ...p }, ref) => (
    <D.Portal>
      <Overlay />
      <D.Content
        ref={ref}
        className={cn(
          "fixed inset-y-0 right-0 z-50 flex h-full w-full flex-col border-l bg-card shadow-xl sm:max-w-xl data-[state=open]:animate-in data-[state=open]:slide-in-from-right",
          className,
        )}
        {...p}
      >
        {children}
        <D.Close className="absolute right-4 top-4 rounded-sm opacity-70 transition-opacity hover:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" aria-label="Fechar">
          <X className="h-4 w-4" />
        </D.Close>
      </D.Content>
    </D.Portal>
  ),
);
SheetContent.displayName = "SheetContent";
