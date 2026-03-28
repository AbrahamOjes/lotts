"use client";

import { useReadContract } from "wagmi";
import { CONTRACTS, ABIS } from "@/lib/contracts";
import { formatUSD, shortenAddress } from "@/lib/utils";

export default function ResultsPage() {
  const { data: currentRound } = useReadContract({
    address: CONTRACTS.lottery,
    abi: ABIS.lottery,
    functionName: "currentRoundId",
  });

  const roundId = Number(currentRound ?? 1n);
  const pastRounds = Array.from({ length: Math.max(0, roundId - 1) }, (_, i) => i + 1).reverse();

  return (
    <div className="mx-auto max-w-lg px-4 pt-8 pb-12">
      <h1 className="mb-8 text-center text-2xl font-bold text-slate-900">Past Results</h1>

      {pastRounds.length === 0 ? (
        <div className="rounded-2xl bg-white border border-slate-200 p-10 text-center shadow-sm">
          <p className="text-lg font-semibold text-slate-700">No completed rounds yet.</p>
          <p className="mt-2 text-sm text-slate-400">
            The first draw will happen when the jackpot target is reached.
          </p>
        </div>
      ) : (
        <div className="space-y-4">
          {pastRounds.map((id) => (
            <RoundCard key={id} roundId={id} />
          ))}
        </div>
      )}
    </div>
  );
}

function RoundCard({ roundId }: { roundId: number }) {
  const { data } = useReadContract({
    address: CONTRACTS.lottery,
    abi: ABIS.lottery,
    functionName: "rounds",
    args: [BigInt(roundId)],
  });

  if (!data) return null;

  const [, jackpotAmount, totalTickets, , , settled, grandWinner, grandPrize] =
    data as [bigint, bigint, bigint, bigint, boolean, boolean, string, bigint];

  if (!settled) return null;

  return (
    <div className="card-hover rounded-2xl bg-white border border-slate-200 p-5 shadow-sm">
      <div className="mb-3 flex items-center justify-between">
        <span className="text-sm font-bold text-slate-400">Round #{roundId}</span>
        <span className="rounded-full bg-emerald-50 border border-emerald-200 px-3 py-1 text-xs font-semibold text-emerald-700">
          Completed
        </span>
      </div>

      <div className="mb-4 grid grid-cols-2 gap-4 text-sm">
        <div>
          <p className="text-slate-400">Jackpot</p>
          <p className="text-lg font-bold text-slate-900">{formatUSD(jackpotAmount)}</p>
        </div>
        <div>
          <p className="text-slate-400">Tickets</p>
          <p className="text-lg font-bold text-slate-900">{totalTickets.toString()}</p>
        </div>
      </div>

      <div className="border-t border-slate-100 pt-3">
        <p className="text-xs font-medium text-slate-400 mb-1">Grand Prize Winner</p>
        <div className="flex items-center justify-between">
          <span className="font-mono text-sm text-slate-600">{shortenAddress(grandWinner)}</span>
          <span className="text-lg font-bold text-emerald-600">{formatUSD(grandPrize)}</span>
        </div>
      </div>
    </div>
  );
}
