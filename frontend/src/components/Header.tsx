"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import Link from "next/link";

export function Header() {
  return (
    <header className="sticky top-0 z-50 bg-white/80 backdrop-blur-md border-b border-slate-100">
      <div className="mx-auto flex h-16 max-w-5xl items-center justify-between px-4">
        <Link href="/" className="text-xl font-black tracking-tight text-slate-900 uppercase">
          LOTTO
        </Link>
        <div className="flex items-center gap-3">
          <Link href="/play" className="btn-primary !py-2.5 !px-6 !text-sm hidden sm:inline-flex">
            Play
          </Link>
          <ConnectButton
            accountStatus="avatar"
            chainStatus="icon"
            showBalance={false}
          />
        </div>
      </div>
    </header>
  );
}
