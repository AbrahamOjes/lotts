"use client";

import Link from "next/link";
import { useLottery } from "@/hooks/useLottery";
import { formatUSD, progressPercent } from "@/lib/utils";

export default function HomePage() {
  const { roundId, jackpotAmount, targetPot, totalTickets, drawInProgress, isLoading } =
    useLottery();

  const progress = progressPercent(jackpotAmount, targetPot);

  return (
    <div className="mx-auto max-w-2xl px-4">
      {/* Hero */}
      <section className="pt-16 pb-12 text-center">
        <p className="mb-4 text-sm font-bold uppercase tracking-[0.2em] text-slate-500">
          The Internet Lottery
        </p>

        <h1 className="jackpot-number text-7xl sm:text-8xl md:text-9xl leading-none mb-6">
          {isLoading ? "..." : formatUSD(jackpotAmount)}
        </h1>

        <div className="mb-8">
          <Link href="/play" className="btn-primary inline-block text-lg">
            Play to Win
          </Link>
          <p className="mt-3 text-sm text-slate-400">
            Play for $1 &middot; Round #{roundId.toString()}
          </p>
        </div>

        {drawInProgress && (
          <div className="mx-auto max-w-sm animate-pulse rounded-full bg-amber-50 border border-amber-200 px-6 py-3 text-sm font-medium text-amber-700">
            Draw in progress...
          </div>
        )}

        {/* Progress */}
        <div className="mx-auto mt-8 max-w-md">
          <div className="mb-2 flex justify-between text-xs font-medium text-slate-400">
            <span>{progress}% filled</span>
            <span>Target: {formatUSD(targetPot)}</span>
          </div>
          <div className="h-2 overflow-hidden rounded-full bg-slate-200">
            <div
              className="h-full rounded-full bg-gradient-to-r from-indigo-400 to-violet-400 transition-all duration-700 ease-out"
              style={{ width: `${progress}%` }}
            />
          </div>
        </div>
      </section>

      {/* Stats strip */}
      <section className="mb-16">
        <div className="grid grid-cols-2 gap-4">
          <div className="card-hover rounded-2xl bg-white border border-slate-150 p-6 text-center shadow-sm">
            <p className="text-3xl font-bold text-slate-900">{totalTickets.toString()}</p>
            <p className="mt-1 text-sm text-slate-400">Tickets Sold</p>
          </div>
          <div className="card-hover rounded-2xl bg-white border border-slate-150 p-6 text-center shadow-sm">
            <p className="text-3xl font-bold text-slate-900">$1</p>
            <p className="mt-1 text-sm text-slate-400">Per Ticket</p>
          </div>
        </div>
      </section>

      {/* How it works */}
      <section className="pb-16">
        <h2 className="mb-8 text-center text-2xl font-bold text-slate-900">How it works</h2>
        <div className="grid gap-6 sm:grid-cols-3">
          {[
            {
              step: "01",
              title: "Buy tickets",
              desc: "$1 USDC each. The more you buy, the better your odds.",
            },
            {
              step: "02",
              title: "Pot fills up",
              desc: "When the jackpot reaches the target, a draw triggers automatically.",
            },
            {
              step: "03",
              title: "Win instantly",
              desc: "Chainlink VRF picks winners on-chain. Provably fair, always.",
            },
          ].map(({ step, title, desc }) => (
            <div
              key={step}
              className="card-hover rounded-2xl bg-white border border-slate-100 p-6 shadow-sm"
            >
              <p className="mb-3 text-xs font-bold text-slate-300">{step}</p>
              <h3 className="mb-2 text-lg font-bold text-slate-900">{title}</h3>
              <p className="text-sm leading-relaxed text-slate-500">{desc}</p>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
