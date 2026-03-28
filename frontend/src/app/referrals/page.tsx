"use client";

import { useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { CONTRACTS, ABIS } from "@/lib/contracts";
import { formatUSD } from "@/lib/utils";

export default function ReferralsPage() {
  const { address, isConnected } = useAccount();
  const [copied, setCopied] = useState(false);

  const { data: pendingCommission } = useReadContract({
    address: CONTRACTS.referralManager,
    abi: ABIS.referralManager,
    functionName: "pendingCommission",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 15_000 },
  });

  const { data: totalEarned } = useReadContract({
    address: CONTRACTS.referralManager,
    abi: ABIS.referralManager,
    functionName: "totalEarned",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: referralCount } = useReadContract({
    address: CONTRACTS.referralManager,
    abi: ABIS.referralManager,
    functionName: "referralCount",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { writeContract: claim, isPending: isClaiming } = useWriteContract();

  const referralLink = address
    ? `${typeof window !== "undefined" ? window.location.origin : ""}/play?ref=${address}`
    : "";

  function copyLink() {
    navigator.clipboard.writeText(referralLink);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  function claimCommission() {
    claim({
      address: CONTRACTS.referralManager,
      abi: ABIS.referralManager,
      functionName: "claimCommission",
    });
  }

  return (
    <div className="mx-auto max-w-lg px-4 pt-8 pb-12">
      <div className="mb-8 text-center">
        <h1 className="text-2xl font-bold text-slate-900">Referrals</h1>
        <p className="mt-2 text-sm text-slate-400">
          Earn 10% of every ticket purchased through your referral link.
        </p>
      </div>

      {!isConnected ? (
        <div className="flex flex-col items-center gap-4 rounded-2xl bg-white border border-slate-200 p-10 shadow-sm">
          <p className="text-slate-400">Connect wallet to get your referral link</p>
          <ConnectButton />
        </div>
      ) : (
        <div className="space-y-4">
          {/* Referral link */}
          <div className="rounded-2xl bg-white border border-slate-200 p-5 shadow-sm">
            <p className="mb-2 text-sm font-semibold text-slate-700">Your referral link</p>
            <div className="flex gap-2">
              <input
                readOnly
                value={referralLink}
                className="flex-1 truncate rounded-xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-600"
              />
              <button
                onClick={copyLink}
                className="btn-primary !py-3 !px-5 !text-sm"
              >
                {copied ? "Copied!" : "Copy"}
              </button>
            </div>
          </div>

          {/* Stats */}
          <div className="grid grid-cols-3 gap-3">
            <div className="rounded-2xl bg-white border border-slate-200 p-4 text-center shadow-sm">
              <p className="text-2xl font-bold text-slate-900">
                {(referralCount as bigint)?.toString() ?? "0"}
              </p>
              <p className="text-xs text-slate-400">Referrals</p>
            </div>
            <div className="rounded-2xl bg-white border border-slate-200 p-4 text-center shadow-sm">
              <p className="text-2xl font-bold text-slate-900">
                {formatUSD((totalEarned as bigint) ?? 0n)}
              </p>
              <p className="text-xs text-slate-400">Total Earned</p>
            </div>
            <div className="rounded-2xl bg-white border border-slate-200 p-4 text-center shadow-sm">
              <p className="text-2xl font-bold text-emerald-600">
                {formatUSD((pendingCommission as bigint) ?? 0n)}
              </p>
              <p className="text-xs text-slate-400">Claimable</p>
            </div>
          </div>

          {/* Claim */}
          {(pendingCommission as bigint) > 0n && (
            <button
              onClick={claimCommission}
              disabled={isClaiming}
              className="btn-primary w-full"
            >
              {isClaiming
                ? "Claiming..."
                : `Claim ${formatUSD((pendingCommission as bigint) ?? 0n)}`}
            </button>
          )}
        </div>
      )}
    </div>
  );
}
