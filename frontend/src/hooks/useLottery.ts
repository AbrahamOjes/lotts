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

  const [roundId, prizePool, totalTickets, drawTime, drawInProgress] =
    (data as [bigint, bigint, bigint, bigint, boolean]) ?? [0n, 0n, 0n, 0n, false];

  const ticketPrice = useReadContract({
    address: CONTRACTS.lottery,
    abi: ABIS.lottery,
    functionName: "ticketPrice",
  });

  const timeUntilDraw = useReadContract({
    address: CONTRACTS.lottery,
    abi: ABIS.lottery,
    functionName: "timeUntilDraw",
    query: { refetchInterval: 5_000 },
  });

  const drawInterval = useReadContract({
    address: CONTRACTS.lottery,
    abi: ABIS.lottery,
    functionName: "drawInterval",
  });

  return {
    roundId,
    prizePool,
    totalTickets,
    drawTime,
    drawInProgress,
    ticketPrice: (ticketPrice.data as bigint) ?? 1_000_000n,
    timeUntilDraw: (timeUntilDraw.data as bigint) ?? 0n,
    drawInterval: (drawInterval.data as bigint) ?? 86400n,
    isLoading,
    refetch,
  };
}
