"use client";

import { useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { CONTRACTS, ABIS } from "@/lib/contracts";
import { formatUSD } from "@/lib/utils";

export default function ReferralsPage() {
  const { address, isConnected } = useAccount();
  const [copied, setCopied] = useState(false);

  const { data: statsData } = useReadContract({
    address: CONTRACTS.referralManager,
    abi: ABIS.referralManager,
    functionName: "getReferrerStats",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 15_000 },
  });

  const [pending, earnedPurchases, earnedWinShare, directRefs, tier2Refs] =
    (statsData as [bigint, bigint, bigint, bigint, bigint]) ?? [0n, 0n, 0n, 0n, 0n];

  const totalEarned = earnedPurchases + earnedWinShare;

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
          Earn from ticket sales <strong>and</strong> when your referrals win.
          Two-tier system: earn from your direct referrals and their referrals too.
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

          {/* Network Stats */}
          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-2xl bg-white border border-slate-200 p-4 text-center shadow-sm">
              <p className="text-2xl font-bold text-slate-900">{directRefs.toString()}</p>
              <p className="text-xs text-slate-400">Direct Referrals</p>
            </div>
            <div className="rounded-2xl bg-white border border-slate-200 p-4 text-center shadow-sm">
              <p className="text-2xl font-bold text-slate-900">{tier2Refs.toString()}</p>
              <p className="text-xs text-slate-400">Tier 2 Referrals</p>
            </div>
          </div>

          {/* Earnings breakdown */}
          <div className="rounded-2xl bg-white border border-slate-200 p-5 shadow-sm space-y-3">
            <div className="flex justify-between text-sm">
              <span className="text-slate-500">From ticket sales</span>
              <span className="font-semibold text-slate-900">{formatUSD(earnedPurchases)}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-slate-500">From winner prizes</span>
              <span className="font-semibold text-slate-900">{formatUSD(earnedWinShare)}</span>
            </div>
            <div className="border-t border-slate-100 pt-3 flex justify-between text-sm">
              <span className="font-semibold text-slate-700">Total earned</span>
              <span className="font-bold text-slate-900">{formatUSD(totalEarned)}</span>
            </div>
          </div>

          {/* Claimable */}
          <div className="rounded-2xl bg-gradient-to-br from-indigo-50 to-violet-50 border border-indigo-100 p-5 text-center shadow-sm">
            <p className="text-xs font-bold uppercase tracking-widest text-indigo-400 mb-1">
              Claimable
            </p>
            <p className="text-3xl font-bold text-indigo-700">{formatUSD(pending)}</p>
          </div>

          {/* Claim */}
          {pending > 0n && (
            <button
              onClick={claimCommission}
              disabled={isClaiming}
              className="btn-primary w-full"
            >
              {isClaiming ? "Claiming..." : `Claim ${formatUSD(pending)}`}
            </button>
          )}

          {/* How it works */}
          <div className="rounded-2xl bg-white border border-slate-200 p-5 shadow-sm">
            <p className="text-sm font-semibold text-slate-700 mb-3">How referral earnings work</p>
            <div className="space-y-2 text-xs text-slate-500">
              <p><strong className="text-slate-700">Ticket sales:</strong> Earn 8% (tier 1) or 2% (tier 2) of ticket revenue from your network.</p>
              <p><strong className="text-slate-700">Winner prizes:</strong> When someone you referred wins, earn 8% (tier 1) or 2% (tier 2) of their prize.</p>
              <p><strong className="text-slate-700">Sticky referrals:</strong> Once someone is your referral, they stay your referral forever.</p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
