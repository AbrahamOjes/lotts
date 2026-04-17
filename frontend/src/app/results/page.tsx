"use client";

import { useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { CONTRACTS, ABIS } from "@/lib/contracts";
import { formatUSD, shortenAddress } from "@/lib/utils";
import { WinCard } from "@/components/WinCard";

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
      <h1 className="mb-8 text-center text-2xl font-bold text-slate-900">Results</h1>

      {/* My Wins section */}
      <MyWins pastRounds={pastRounds} />

      {pastRounds.length === 0 ? (
        <div className="rounded-2xl bg-white border border-slate-200 p-10 text-center shadow-sm">
          <p className="text-lg font-semibold text-slate-700">No completed rounds yet.</p>
          <p className="mt-2 text-sm text-slate-400">
            The first draw happens daily once the minimum pot is reached.
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

function MyWins({ pastRounds }: { pastRounds: number[] }) {
  const { address, isConnected } = useAccount();

  if (!isConnected || !address || pastRounds.length === 0) return null;

  return (
    <div className="mb-8">
      <h2 className="mb-4 text-lg font-bold text-slate-900">My Wins</h2>
      <div className="space-y-4">
        {pastRounds.map((id) => (
          <MyWinForRound key={id} roundId={id} userAddress={address} />
        ))}
      </div>
    </div>
  );
}

function MyWinForRound({ roundId, userAddress }: { roundId: number; userAddress: string }) {
  const { data: claimableAmount } = useReadContract({
    address: CONTRACTS.lottery,
    abi: ABIS.lottery,
    functionName: "claimable",
    args: [BigInt(roundId), userAddress as `0x${string}`],
  });

  const { data: hasClaimed } = useReadContract({
    address: CONTRACTS.lottery,
    abi: ABIS.lottery,
    functionName: "claimed",
    args: [BigInt(roundId), userAddress as `0x${string}`],
  });

  const { data: winnersData } = useReadContract({
    address: CONTRACTS.lottery,
    abi: ABIS.lottery,
    functionName: "getRoundWinners",
    args: [BigInt(roundId)],
  });

  const { writeContract: claimPrize, isPending: isClaiming } = useWriteContract();

  const claimable = (claimableAmount as bigint) ?? 0n;
  const claimed = (hasClaimed as boolean) ?? false;

  // Find the user's best tier in this round
  const [winners, prizes, tierIndices] = (winnersData as [string[], bigint[], bigint[]]) ?? [[], [], []];
  let bestTier = -1;
  let totalPrize = 0n;
  for (let i = 0; i < winners.length; i++) {
    if (winners[i].toLowerCase() === userAddress.toLowerCase()) {
      totalPrize += prizes[i];
      if (bestTier === -1 || Number(tierIndices[i]) < bestTier) {
        bestTier = Number(tierIndices[i]);
      }
    }
  }

  if (totalPrize === 0n && claimable === 0n && !claimed) return null;

  return (
    <div className="space-y-3">
      <WinCard
        roundId={roundId}
        winner={userAddress}
        prize={totalPrize > 0n ? totalPrize : claimable}
        tier={bestTier >= 0 ? bestTier : 7}
      />
      {claimable > 0n && !claimed && (
        <button
          onClick={() =>
            claimPrize({
              address: CONTRACTS.lottery,
              abi: ABIS.lottery,
              functionName: "claimPrize",
              args: [BigInt(roundId)],
            })
          }
          disabled={isClaiming}
          className="btn-primary w-full"
        >
          {isClaiming ? "Claiming..." : `Claim ${formatUSD(claimable)}`}
        </button>
      )}
      {claimed && (
        <p className="text-center text-xs text-emerald-600 font-medium">Claimed</p>
      )}
    </div>
  );
}

function RoundCard({ roundId }: { roundId: number }) {
  const [expanded, setExpanded] = useState(false);

  const { data } = useReadContract({
    address: CONTRACTS.lottery,
    abi: ABIS.lottery,
    functionName: "rounds",
    args: [BigInt(roundId)],
  });

  const { data: winnersData } = useReadContract({
    address: CONTRACTS.lottery,
    abi: ABIS.lottery,
    functionName: "getRoundWinners",
    args: [BigInt(roundId)],
  });

  if (!data) return null;

  const [prizePool, totalTickets, , , , settled, grandWinner, grandPrize] =
    data as [bigint, bigint, bigint, bigint, boolean, boolean, string, bigint];

  if (!settled) return null;

  const [winners, prizes, tierIndices] = (winnersData as [string[], bigint[], bigint[]]) ?? [
    [],
    [],
    [],
  ];

  return (
    <div className="rounded-2xl bg-white border border-slate-200 shadow-sm overflow-hidden">
      <div className="p-5">
        <div className="mb-3 flex items-center justify-between">
          <span className="text-sm font-bold text-slate-400">Round #{roundId}</span>
          <span className="rounded-full bg-emerald-50 border border-emerald-200 px-3 py-1 text-xs font-semibold text-emerald-700">
            Completed
          </span>
        </div>

        <div className="mb-4 grid grid-cols-2 gap-4 text-sm">
          <div>
            <p className="text-slate-400">Prize Pool</p>
            <p className="text-lg font-bold text-slate-900">{formatUSD(prizePool)}</p>
          </div>
          <div>
            <p className="text-slate-400">Tickets</p>
            <p className="text-lg font-bold text-slate-900">{totalTickets.toString()}</p>
          </div>
        </div>

        <div className="border-t border-slate-100 pt-3">
          <p className="text-xs font-medium text-slate-400 mb-1">Grand Prize Winner</p>
          <div className="flex items-center justify-between">
            <span className="font-mono text-sm text-slate-600">
              {shortenAddress(grandWinner)}
            </span>
            <span className="text-lg font-bold text-emerald-600">{formatUSD(grandPrize)}</span>
          </div>
        </div>

        {winners.length > 0 && (
          <button
            onClick={() => setExpanded(!expanded)}
            className="mt-3 w-full text-center text-xs font-semibold text-indigo-600 hover:text-indigo-700"
          >
            {expanded ? "Hide all winners" : `Show all ${winners.length} winners`}
          </button>
        )}
      </div>

      {expanded && winners.length > 0 && (
        <div className="border-t border-slate-100 bg-slate-50 p-4 space-y-2">
          {winners.map((winner, i) => (
            <div
              key={`${roundId}-${i}`}
              className="flex items-center justify-between text-sm"
            >
              <div className="flex items-center gap-2">
                <span className="rounded bg-indigo-50 px-2 py-0.5 text-[10px] font-bold text-indigo-600">
                  {TIER_NAMES[Number(tierIndices[i])] ?? `Tier ${Number(tierIndices[i]) + 1}`}
                </span>
                <span className="font-mono text-slate-500">{shortenAddress(winner)}</span>
              </div>
              <span className="font-semibold text-slate-700">{formatUSD(prizes[i])}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
