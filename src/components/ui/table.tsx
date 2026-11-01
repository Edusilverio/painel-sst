import * as React from "react";
import { cn } from "@/lib/utils";

export const Table = React.forwardRef<HTMLTableElement, React.HTMLAttributes<HTMLTableElement>>(({ className, ...p }, ref) => (
  <div className="relative w-full overflow-auto">
    <table ref={ref} className={cn("w-full caption-bottom text-sm", className)} {...p} />
  </div>
));
Table.displayName = "Table";
export const TableHeader = React.forwardRef<HTMLTableSectionElement, React.HTMLAttributes<HTMLTableSectionElement>>(({ className, ...p }, ref) => (
  <thead ref={ref} className={cn("[&_tr]:border-b", className)} {...p} />
));
TableHeader.displayName = "TableHeader";
export const TableBody = React.forwardRef<HTMLTableSectionElement, React.HTMLAttributes<HTMLTableSectionElement>>(({ className, ...p }, ref) => (
  <tbody ref={ref} className={cn("[&_tr:last-child]:border-0", className)} {...p} />
));
TableBody.displayName = "TableBody";
export const TableRow = React.forwardRef<HTMLTableRowElement, React.HTMLAttributes<HTMLTableRowElement>>(({ className, ...p }, ref) => (
  <tr ref={ref} className={cn("border-b transition-colors hover:bg-muted/50", className)} {...p} />
));
TableRow.displayName = "TableRow";
export const TableHead = React.forwardRef<HTMLTableCellElement, React.ThHTMLAttributes<HTMLTableCellElement>>(({ className, ...p }, ref) => (
  <th ref={ref} className={cn("h-10 px-3 text-left align-middle text-xs font-medium uppercase tracking-wide text-muted-foreground", className)} {...p} />
));
TableHead.displayName = "TableHead";
export const TableCell = React.forwardRef<HTMLTableCellElement, React.TdHTMLAttributes<HTMLTableCellElement>>(({ className, ...p }, ref) => (
  <td ref={ref} className={cn("px-3 py-2.5 align-middle", className)} {...p} />
));
TableCell.displayName = "TableCell";
