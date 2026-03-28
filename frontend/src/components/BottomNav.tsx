"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const NAV_ITEMS = [
  { href: "/", label: "Home" },
  { href: "/play", label: "Play" },
  { href: "/vault", label: "Vault" },
  { href: "/results", label: "Results" },
  { href: "/referrals", label: "Refer" },
];

export function BottomNav() {
  const pathname = usePathname();

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-50 border-t border-slate-200 bg-white/95 backdrop-blur-md sm:hidden">
      <div className="mx-auto flex max-w-lg items-center justify-around">
        {NAV_ITEMS.map(({ href, label }) => {
          const isActive = pathname === href;
          return (
            <Link
              key={href}
              href={href}
              className={`flex flex-col items-center gap-0.5 py-3 px-3 text-xs font-medium transition-colors ${
                isActive ? "text-slate-900" : "text-slate-400 hover:text-slate-600"
              }`}
            >
              <div
                className={`h-1 w-4 rounded-full mb-1 transition-colors ${
                  isActive ? "bg-slate-900" : "bg-transparent"
                }`}
              />
              <span>{label}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
