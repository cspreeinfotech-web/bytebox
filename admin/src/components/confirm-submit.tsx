"use client";
import type { ReactNode } from "react";
import { useFormStatus } from "react-dom";

/** Submit button that asks for confirmation before destructive actions. */
export function ConfirmSubmit({ children, message, className, name, value }: {
  children: ReactNode; message?: string; className?: string; name?: string; value?: string;
}) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      name={name}
      value={value}
      disabled={pending}
      className={className}
      onClick={(e) => {
        if (message && !window.confirm(message)) e.preventDefault();
      }}
    >
      {pending ? "Working…" : children}
    </button>
  );
}
