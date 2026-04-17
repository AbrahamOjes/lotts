"use client";

import { useRef, useState } from "react";
import { formatUSD, shortenAddress } from "@/lib/utils";

const TIER_NAMES = [
  "Grand Prize",
  "Tier 2",
  "Tier 3",
  "Tier 4",
  "Tier 5",
  "Tier 6",
  "Tier 7",
  "Tier 8",
];

interface WinCardProps {
  roundId: number;
  winner: string;
  prize: bigint;
  tier: number;
}

export function WinCard({ roundId, winner, prize, tier }: WinCardProps) {
  const cardRef = useRef<HTMLDivElement>(null);
  const [shared, setShared] = useState(false);

  async function shareCard() {
    if (!cardRef.current) return;

    // Try native share first (mobile)
    if (navigator.share) {
      try {
        await navigator.share({
          title: `I won ${formatUSD(prize)} on LOTTO!`,
          text: `I just won ${formatUSD(prize)} (${TIER_NAMES[tier]}) in Round #${roundId} on LOTTO — the on-chain daily lottery! 🎉`,
          url: typeof window !== "undefined" ? window.location.origin : "",
        });
        setShared(true);
        setTimeout(() => setShared(false), 2000);
        return;
      } catch {
        // User cancelled or share not available — fall through to clipboard
      }
    }

    // Fallback: copy text to clipboard
    const text = `🎉 I won ${formatUSD(prize)} (${TIER_NAMES[tier]}) in LOTTO Round #${roundId}! Play at ${typeof window !== "undefined" ? window.location.origin : ""}`;
    await navigator.clipboard.writeText(text);
    setShared(true);
    setTimeout(() => setShared(false), 2000);
  }

  return (
    <div className="space-y-3">
      <div
        ref={cardRef}
        className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-indigo-600 via-violet-600 to-purple-700 p-6 text-white shadow-lg"
      >
        {/* Decorative circles */}
        <div className="absolute -top-8 -right-8 h-32 w-32 rounded-full bg-white/10" />
        <div className="absolute -bottom-6 -left-6 h-24 w-24 rounded-full bg-white/10" />

        <div className="relative">
          <p className="text-xs font-bold uppercase tracking-widest text-white/60 mb-1">
            LOTTO &middot; Round #{roundId}
          </p>

          <div className="mb-4">
            <span className="inline-block rounded-full bg-white/20 px-3 py-1 text-xs font-bold">
              {TIER_NAMES[tier]}
            </span>
          </div>

          <p className="text-4xl font-black leading-none mb-2">
            {formatUSD(prize)}
          </p>

          <p className="text-sm text-white/70">
            Won by {shortenAddress(winner)}
          </p>
        </div>
      </div>

      <button
        onClick={shareCard}
        className="w-full rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white hover:bg-slate-800 transition-colors"
      >
        {shared ? "Copied!" : "Share your win"}
      </button>
    </div>
  );
}
