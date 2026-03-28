"use client";

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { CONTRACTS, ABIS, ERC20_ABI } from "@/lib/contracts";

export function useVault() {
  const { address } = useAccount();

  const { data: userDeposit } = useReadContract({
    address: CONTRACTS.lpVault,
    abi: ABIS.lpVault,
    functionName: "userDeposits",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 15_000 },
  });

  const { data: totalDeposited } = useReadContract({
    address: CONTRACTS.lpVault,
    abi: ABIS.lpVault,
    functionName: "totalDeposited",
    query: { refetchInterval: 15_000 },
  });

  const { data: pendingYield } = useReadContract({
    address: CONTRACTS.lpVault,
    abi: ABIS.lpVault,
    functionName: "pendingYield",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 15_000 },
  });

  const { writeContract: approveVault, data: approveTxHash } = useWriteContract();
  const { writeContract: deposit, data: depositTxHash, isPending: isDepositing } = useWriteContract();
  const { writeContract: withdraw, data: withdrawTxHash, isPending: isWithdrawing } = useWriteContract();
  const { writeContract: claimYield, data: claimTxHash, isPending: isClaiming } = useWriteContract();

  const depositReceipt = useWaitForTransactionReceipt({ hash: depositTxHash });
  const withdrawReceipt = useWaitForTransactionReceipt({ hash: withdrawTxHash });
  const claimReceipt = useWaitForTransactionReceipt({ hash: claimTxHash });

  function doApprove(amount: bigint) {
    approveVault({
      address: CONTRACTS.usdc,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [CONTRACTS.lpVault, amount],
    });
  }

  function doDeposit(amount: bigint) {
    deposit({
      address: CONTRACTS.lpVault,
      abi: ABIS.lpVault,
      functionName: "deposit",
      args: [amount],
    });
  }

  function doWithdraw(amount: bigint) {
    withdraw({
      address: CONTRACTS.lpVault,
      abi: ABIS.lpVault,
      functionName: "withdraw",
      args: [amount],
    });
  }

  function doClaimYield() {
    claimYield({
      address: CONTRACTS.lpVault,
      abi: ABIS.lpVault,
      functionName: "claimYield",
    });
  }

  return {
    userDeposit: (userDeposit as bigint) ?? 0n,
    totalDeposited: (totalDeposited as bigint) ?? 0n,
    pendingYield: (pendingYield as bigint) ?? 0n,
    doApprove,
    doDeposit,
    doWithdraw,
    doClaimYield,
    isDepositing: isDepositing || depositReceipt.isLoading,
    isWithdrawing: isWithdrawing || withdrawReceipt.isLoading,
    isClaiming: isClaiming || claimReceipt.isLoading,
  };
}
