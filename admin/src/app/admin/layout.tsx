import type { Metadata } from "next";
import type { ReactNode } from "react";

export const metadata: Metadata = { title: "Bytebox Admin", robots: { index: false, follow: false } };

export default function AdminRoot({ children }: { children: ReactNode }) {
  return <div className="min-h-screen bg-gray-50 text-gray-900">{children}</div>;
}
