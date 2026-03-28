"use client";

import { useReadContract } from "wagmi";
import { CONTRACTS, ABIS } from "@/lib/contracts";

export function useLottery() {
  const { data, isLoading, refetch } = useReadContract({
    address: CONTRACTS.lottery,
    abi: ABIS.lottery,
    functionName: "getCurrentRound",
    query: { refetchInterval: 10_000 },
  });

  const [roundId, jackpotAmount, targetPot, totalTickets, drawInProgress] =
    (data as [bigint, bigint, bigint, bigint, boolean]) ?? [0n, 0n, 0n, 0n, false];

  const ticketPrice = useReadContract({
    address: CONTRACTS.lottery,
    abi: ABIS.lottery,
    functionName: "ticketPrice",
  });

  return {
    roundId,
    jackpotAmount,
    targetPot,
    totalTickets,
    drawInProgress,
    ticketPrice: (ticketPrice.data as bigint) ?? 1_000_000n,
    isLoading,
    refetch,
  };
}
