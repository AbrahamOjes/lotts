"use client";

import { useState } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { type Address } from "viem";
import { CONTRACTS, ABIS, ERC20_ABI } from "@/lib/contracts";

export function useBuyTicket() {
  const { address } = useAccount();
  const [step, setStep] = useState<"idle" | "approving" | "buying" | "done">("idle");

  // Check current USDC allowance
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: CONTRACTS.usdc,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: address ? [address, CONTRACTS.lottery] : undefined,
    query: { enabled: !!address },
  });

  // USDC balance
  const { data: balance } = useReadContract({
    address: CONTRACTS.usdc,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { writeContract: approve, data: approveTxHash, isPending: isApproving } = useWriteContract();
  const { writeContract: buy, data: buyTxHash, isPending: isBuying } = useWriteContract();

  const approveReceipt = useWaitForTransactionReceipt({ hash: approveTxHash });
  const buyReceipt = useWaitForTransactionReceipt({ hash: buyTxHash });

  async function buyTickets(quantity: number, referrer: Address = "0x0000000000000000000000000000000000000000") {
    if (!address) return;

    const ticketPrice = 1_000_000n; // $1 USDC
    const totalCost = BigInt(quantity) * ticketPrice;
    const currentAllowance = (allowance as bigint) ?? 0n;

    // Step 1: Approve if needed
    if (currentAllowance < totalCost) {
      setStep("approving");
      approve({
        address: CONTRACTS.usdc,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [CONTRACTS.lottery, totalCost],
      });
      // Wait for approval to be confirmed before buying
      // The UI should show approval status and user triggers buy after
      return;
    }

    // Step 2: Buy tickets
    setStep("buying");
    buy({
      address: CONTRACTS.lottery,
      abi: ABIS.lottery,
      functionName: "buyTicket",
      args: [BigInt(quantity), referrer],
    });
  }

  function executeBuy(quantity: number, referrer: Address = "0x0000000000000000000000000000000000000000") {
    setStep("buying");
    buy({
      address: CONTRACTS.lottery,
      abi: ABIS.lottery,
      functionName: "buyTicket",
      args: [BigInt(quantity), referrer],
    });
  }

  const needsApproval = (quantity: number) => {
    const totalCost = BigInt(quantity) * 1_000_000n;
    return ((allowance as bigint) ?? 0n) < totalCost;
  };

  return {
    buyTickets,
    executeBuy,
    needsApproval,
    step,
    setStep,
    isApproving: isApproving || approveReceipt.isLoading,
    isBuying: isBuying || buyReceipt.isLoading,
    isApproved: approveReceipt.isSuccess,
    isBought: buyReceipt.isSuccess,
    approveTxHash,
    buyTxHash,
    balance: (balance as bigint) ?? 0n,
    error: approveReceipt.error || buyReceipt.error,
  };
}
