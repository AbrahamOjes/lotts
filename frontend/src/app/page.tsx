"use client";

import { useState, useEffect } from "react";
import Link from "next/link";
import { useLottery } from "@/hooks/useLottery";
import { formatUSD } from "@/lib/utils";

function CountdownTimer({ seconds }: { seconds: bigint }) {
  const [remaining, setRemaining] = useState(Number(seconds));

  useEffect(() => {
    setRemaining(Number(seconds));
  }, [seconds]);

  useEffect(() => {
    if (remaining <= 0) return;
    const timer = setInterval(() => setRemaining((r) => Math.max(0, r - 1)), 1000);
    return () => clearInterval(timer);
  }, [remaining]);

  const h = Math.floor(remaining / 3600);
  const m = Math.floor((remaining % 3600) / 60);
  const s = remaining % 60;

  return (
    <div className="flex items-center justify-center gap-3 text-center">
      {[
        { value: h, label: "HRS" },
        { value: m, label: "MIN" },
        { value: s, label: "SEC" },
      ].map(({ value, label }) => (
        <div key={label}>
          <p className="text-3xl font-bold tabular-nums text-slate-900">
            {String(value).padStart(2, "0")}
          </p>
          <p className="text-[10px] font-bold tracking-widest text-slate-400">{label}</p>
        </div>
      ))}
    </div>
  );
}

export default function HomePage() {
  const { roundId, prizePool, totalTickets, drawInProgress, timeUntilDraw, isLoading } =
    useLottery();

  return (
    <div className="mx-auto max-w-2xl px-4">
      {/* Hero */}
      <section className="pt-16 pb-12 text-center">
        <p className="mb-4 text-sm font-bold uppercase tracking-[0.2em] text-slate-500">
          Daily Lottery
        </p>

        <h1 className="jackpot-number text-7xl sm:text-8xl md:text-9xl leading-none mb-6">
          {isLoading ? "..." : formatUSD(prizePool)}
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

        {/* Countdown Timer */}
        {!drawInProgress && timeUntilDraw > 0n && (
          <div className="mx-auto mt-8 max-w-xs">
            <p className="mb-3 text-xs font-bold uppercase tracking-widest text-slate-400">
              Next Draw In
            </p>
            <CountdownTimer seconds={timeUntilDraw} />
          </div>
        )}
      </section>

      {/* Stats strip */}
      <section className="mb-16">
        <div className="grid grid-cols-3 gap-4">
          <div className="card-hover rounded-2xl bg-white border border-slate-150 p-6 text-center shadow-sm">
            <p className="text-3xl font-bold text-slate-900">{totalTickets.toString()}</p>
            <p className="mt-1 text-sm text-slate-400">Tickets Sold</p>
          </div>
          <div className="card-hover rounded-2xl bg-white border border-slate-150 p-6 text-center shadow-sm">
            <p className="text-3xl font-bold text-slate-900">34</p>
            <p className="mt-1 text-sm text-slate-400">Winners / Draw</p>
          </div>
          <div className="card-hover rounded-2xl bg-white border border-slate-150 p-6 text-center shadow-sm">
            <p className="text-3xl font-bold text-slate-900">$1</p>
            <p className="mt-1 text-sm text-slate-400">Per Ticket</p>
          </div>
        </div>
      </section>

      {/* Prize Tiers */}
      <section className="mb-16">
        <h2 className="mb-6 text-center text-2xl font-bold text-slate-900">Prize Tiers</h2>
        <div className="grid gap-3">
          {[
            { tier: "Grand Prize", pool: "40%", winners: 1 },
            { tier: "Tier 2", pool: "15%", winners: 1 },
            { tier: "Tier 3", pool: "10%", winners: 2 },
            { tier: "Tier 4", pool: "10%", winners: 2 },
            { tier: "Tier 5", pool: "8%", winners: 3 },
            { tier: "Tier 6", pool: "7%", winners: 5 },
            { tier: "Tier 7", pool: "5%", winners: 7 },
            { tier: "Tier 8", pool: "5%", winners: 13 },
          ].map(({ tier, pool, winners }) => (
            <div
              key={tier}
              className="flex items-center justify-between rounded-xl bg-white border border-slate-100 px-5 py-3 shadow-sm"
            >
              <span className="font-semibold text-slate-900">{tier}</span>
              <div className="flex items-center gap-4 text-sm text-slate-500">
                <span>{pool} of pot</span>
                <span className="rounded-full bg-indigo-50 px-2.5 py-0.5 text-xs font-bold text-indigo-600">
                  {winners} winner{winners > 1 ? "s" : ""}
                </span>
              </div>
            </div>
          ))}
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
              title: "Daily draws",
              desc: "Every 24 hours, a draw triggers automatically. 34 winners picked!",
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
