import * as React from "react";
import * as M from "@radix-ui/react-dropdown-menu";
import { cn } from "@/lib/utils";

export const DropdownMenu = M.Root;
export const DropdownMenuTrigger = M.Trigger;

export const DropdownMenuContent = React.forwardRef<React.ElementRef<typeof M.Content>, React.ComponentPropsWithoutRef<typeof M.Content>>(
  ({ className, sideOffset = 6, ...p }, ref) => (
    <M.Portal>
      <M.Content
        ref={ref}
        sideOffset={sideOffset}
        className={cn("z-50 min-w-[10rem] overflow-hidden rounded-md border bg-popover p-1 text-popover-foreground shadow-md", className)}
        {...p}
      />
    </M.Portal>
  ),
);
DropdownMenuContent.displayName = "DropdownMenuContent";

export const DropdownMenuItem = React.forwardRef<React.ElementRef<typeof M.Item>, React.ComponentPropsWithoutRef<typeof M.Item>>(({ className, ...p }, ref) => (
  <M.Item
    ref={ref}
    className={cn(
      "relative flex cursor-default select-none items-center gap-2 rounded-sm px-2 py-1.5 text-sm outline-none focus:bg-accent focus:text-accent-foreground data-[disabled]:pointer-events-none data-[disabled]:opacity-50 [&_svg]:size-4",
      className,
    )}
    {...p}
  />
));
DropdownMenuItem.displayName = "DropdownMenuItem";

export const DropdownMenuLabel = ({ className, ...p }: React.HTMLAttributes<HTMLDivElement>) => (
  <div className={cn("px-2 py-1.5 text-xs font-medium text-muted-foreground", className)} {...p} />
);
export const DropdownMenuSeparator = React.forwardRef<React.ElementRef<typeof M.Separator>, React.ComponentPropsWithoutRef<typeof M.Separator>>(
  ({ className, ...p }, ref) => <M.Separator ref={ref} className={cn("-mx-1 my-1 h-px bg-border", className)} {...p} />,
);
DropdownMenuSeparator.displayName = "DropdownMenuSeparator";
