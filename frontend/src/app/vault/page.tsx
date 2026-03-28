"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useVault } from "@/hooks/useVault";
import { formatUSD, parseUSDC, formatUSDC } from "@/lib/utils";

export default function VaultPage() {
  const { isConnected } = useAccount();
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const {
    userDeposit,
    totalDeposited,
    pendingYield,
    doApprove,
    doDeposit,
    doWithdraw,
    doClaimYield,
    isDepositing,
    isWithdrawing,
    isClaiming,
  } = useVault();

  return (
    <div className="mx-auto max-w-lg px-4 pt-8 pb-12">
      <div className="mb-8 text-center">
        <h1 className="text-2xl font-bold text-slate-900">LP Vault</h1>
        <p className="mt-2 text-sm text-slate-400">
          Deposit USDC to back the prize pool and earn 20% of all ticket sales.
        </p>
      </div>

      {/* TVL */}
      <div className="card-hover mb-6 rounded-2xl bg-white border border-slate-200 p-8 text-center shadow-sm">
        <p className="text-sm font-medium text-slate-400 mb-1">Total Value Locked</p>
        <p className="text-4xl font-bold text-slate-900">{formatUSD(totalDeposited)}</p>
      </div>

      {!isConnected ? (
        <div className="flex flex-col items-center gap-4 rounded-2xl bg-white border border-slate-200 p-10 shadow-sm">
          <p className="text-slate-400">Connect wallet to deposit</p>
          <ConnectButton />
        </div>
      ) : (
        <div className="space-y-4">
          {/* Your position */}
          <div className="grid grid-cols-2 gap-4">
            <div className="rounded-2xl bg-white border border-slate-200 p-5 text-center shadow-sm">
              <p className="text-sm text-slate-400 mb-1">Your Deposit</p>
              <p className="text-xl font-bold text-slate-900">{formatUSD(userDeposit)}</p>
            </div>
            <div className="rounded-2xl bg-white border border-slate-200 p-5 text-center shadow-sm">
              <p className="text-sm text-slate-400 mb-1">Pending Yield</p>
              <p className="text-xl font-bold text-emerald-600">{formatUSD(pendingYield)}</p>
            </div>
          </div>

          {/* Claim yield */}
          {pendingYield > 0n && (
            <button
              onClick={doClaimYield}
              disabled={isClaiming}
              className="btn-primary w-full"
            >
              {isClaiming ? "Claiming..." : `Claim ${formatUSD(pendingYield)} Yield`}
            </button>
          )}

          {/* Deposit */}
          <div className="rounded-2xl bg-white border border-slate-200 p-5 shadow-sm">
            <h3 className="mb-3 font-semibold text-slate-900">Deposit USDC</h3>
            <div className="flex gap-2">
              <input
                type="number"
                placeholder="Amount"
                value={depositAmount}
                onChange={(e) => setDepositAmount(e.target.value)}
                className="flex-1 rounded-xl border border-slate-200 bg-slate-50 px-4 py-3 text-slate-900 outline-none focus:border-slate-400 transition-colors [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
              />
              <button
                onClick={() => {
                  if (!depositAmount) return;
                  const amount = parseUSDC(depositAmount);
                  doApprove(amount);
                  setTimeout(() => doDeposit(amount), 500);
                }}
                disabled={isDepositing || !depositAmount}
                className="btn-primary !py-3 !px-6"
              >
                {isDepositing ? "..." : "Deposit"}
              </button>
            </div>
          </div>

          {/* Withdraw */}
          {userDeposit > 0n && (
            <div className="rounded-2xl bg-white border border-slate-200 p-5 shadow-sm">
              <h3 className="mb-3 font-semibold text-slate-900">Withdraw USDC</h3>
              <div className="flex gap-2">
                <input
                  type="number"
                  placeholder="Amount"
                  value={withdrawAmount}
                  onChange={(e) => setWithdrawAmount(e.target.value)}
                  className="flex-1 rounded-xl border border-slate-200 bg-slate-50 px-4 py-3 text-slate-900 outline-none focus:border-slate-400 transition-colors [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
                />
                <button
                  onClick={() => {
                    if (!withdrawAmount) return;
                    doWithdraw(parseUSDC(withdrawAmount));
                  }}
                  disabled={isWithdrawing || !withdrawAmount}
                  className="btn-secondary !py-3 !px-6 !font-bold"
                >
                  {isWithdrawing ? "..." : "Withdraw"}
                </button>
              </div>
              <button
                onClick={() => setWithdrawAmount(formatUSDC(userDeposit))}
                className="mt-2 text-xs text-slate-400 hover:text-slate-600"
              >
                Max: {formatUSDC(userDeposit)} USDC
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
