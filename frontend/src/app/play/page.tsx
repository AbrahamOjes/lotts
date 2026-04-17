"use client";

import { Suspense, useState, useEffect } from "react";
import { useSearchParams } from "next/navigation";
import { useAccount } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { type Address } from "viem";
import { useLottery } from "@/hooks/useLottery";
import { useBuyTicket } from "@/hooks/useBuyTicket";
import { formatUSD, formatUSDC } from "@/lib/utils";
import { TransakButton } from "@/components/TransakButton";

export default function PlayPage() {
  return (
    <Suspense fallback={<div className="pt-20 text-center text-slate-400">Loading...</div>}>
      <PlayPageInner />
    </Suspense>
  );
}

function PlayPageInner() {
  const { isConnected } = useAccount();
  const searchParams = useSearchParams();
  const [quantity, setQuantity] = useState(10);
  const { prizePool, drawInProgress, ticketPrice } = useLottery();
  const {
    buyTickets,
    executeBuy,
    needsApproval,
    step,
    setStep,
    isApproving,
    isBuying,
    isApproved,
    isBought,
    balance,
    error,
  } = useBuyTicket();

  const referrer = (searchParams.get("ref") ?? "0x0000000000000000000000000000000000000000") as Address;
  const totalCost = BigInt(quantity) * ticketPrice;
  const hasEnough = balance >= totalCost;

  useEffect(() => {
    if (isApproved && step === "approving") {
      executeBuy(quantity, referrer);
    }
  }, [isApproved, step]);

  useEffect(() => {
    if (isBought) setStep("done");
  }, [isBought]);

  return (
    <div className="mx-auto max-w-lg px-4 pt-8 pb-12">
      {/* Prize pool header */}
      <div className="mb-8 text-center">
        <p className="text-sm font-bold uppercase tracking-[0.15em] text-slate-400 mb-2">
          Prize Pool
        </p>
        <h1 className="jackpot-number text-5xl sm:text-6xl font-black leading-none">
          {formatUSD(prizePool)}
        </h1>
      </div>

      {drawInProgress ? (
        <div className="rounded-2xl bg-amber-50 border border-amber-200 p-8 text-center">
          <p className="text-lg font-bold text-amber-800">Draw in progress</p>
          <p className="mt-2 text-sm text-amber-600">
            Ticket sales paused while the winner is being selected.
          </p>
        </div>
      ) : (
        <div className="rounded-2xl bg-white border border-slate-200 shadow-sm overflow-hidden">
          {/* Ticket card top — decorative ticket feel */}
          <div className="bg-gradient-to-br from-indigo-50 to-violet-50 p-6 pb-4 border-b border-dashed border-slate-200 relative">
            <div className="absolute -left-3 bottom-0 w-6 h-6 bg-[var(--color-background)] rounded-full translate-y-1/2" />
            <div className="absolute -right-3 bottom-0 w-6 h-6 bg-[var(--color-background)] rounded-full translate-y-1/2" />
            <p className="text-center text-xs font-bold uppercase tracking-widest text-slate-400 mb-1">
              Lotto Ticket
            </p>
            <p className="text-center text-2xl font-bold text-slate-900">
              ${quantity}.00
            </p>
          </div>

          <div className="p-6 space-y-6">
            {/* Quantity */}
            <div>
              <div className="flex items-center justify-between mb-3">
                <span className="text-sm font-semibold text-slate-700">Tickets</span>
                <div className="flex gap-2">
                  {[5, 10, 50, 100].map((n) => (
                    <button
                      key={n}
                      onClick={() => setQuantity(n)}
                      className={`h-9 w-12 rounded-full text-sm font-semibold transition-all ${
                        quantity === n
                          ? "bg-slate-900 text-white"
                          : "bg-slate-100 text-slate-500 hover:bg-slate-200"
                      }`}
                    >
                      {n}
                    </button>
                  ))}
                </div>
              </div>

              <div className="flex items-center rounded-xl border border-slate-200 bg-slate-50">
                <button
                  onClick={() => setQuantity(Math.max(1, quantity - 1))}
                  className="h-12 w-14 text-xl text-slate-400 hover:text-slate-700 transition-colors"
                >
                  -
                </button>
                <input
                  type="number"
                  min={1}
                  max={1000}
                  value={quantity}
                  onChange={(e) => setQuantity(Math.max(1, Math.min(1000, Number(e.target.value) || 1)))}
                  className="h-12 flex-1 bg-transparent text-center text-xl font-bold text-slate-900 outline-none [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
                />
                <button
                  onClick={() => setQuantity(Math.min(1000, quantity + 1))}
                  className="h-12 w-14 text-xl text-slate-400 hover:text-slate-700 transition-colors"
                >
                  +
                </button>
              </div>
            </div>

            {!isConnected ? (
              <div className="flex flex-col items-center gap-3 py-4">
                <p className="text-sm text-slate-400">Connect wallet to play</p>
                <ConnectButton />
              </div>
            ) : step === "done" ? (
              <div className="text-center py-4">
                <div className="inline-flex items-center gap-2 rounded-full bg-emerald-50 border border-emerald-200 px-6 py-3 text-sm font-semibold text-emerald-700 mb-3">
                  Tickets purchased!
                </div>
                <p className="text-sm text-slate-400">Good luck in the draw.</p>
                <button
                  onClick={() => { setStep("idle"); setQuantity(10); }}
                  className="mt-3 text-sm font-semibold text-slate-500 underline underline-offset-2 hover:text-slate-700"
                >
                  Buy more
                </button>
              </div>
            ) : (
              <>
                <button
                  onClick={() => buyTickets(quantity, referrer)}
                  disabled={!hasEnough || isApproving || isBuying}
                  className="btn-primary w-full"
                >
                  {isApproving
                    ? "Approving USDC..."
                    : isBuying
                      ? "Buying tickets..."
                      : !hasEnough
                        ? "Insufficient USDC"
                        : needsApproval(quantity)
                          ? `Approve & Buy ${quantity} Ticket${quantity > 1 ? "s" : ""}`
                          : `Buy ${quantity} Ticket${quantity > 1 ? "s" : ""}`}
                </button>

                {isConnected && (
                  <p className="text-center text-xs text-slate-400">
                    Balance: {formatUSDC(balance)} USDC
                  </p>
                )}
              </>
            )}

            {error && (
              <p className="text-center text-sm text-red-500">{error.message}</p>
            )}

            {isConnected && !hasEnough && <TransakButton />}
          </div>
        </div>
      )}

      {/* Referral info */}
      {referrer !== "0x0000000000000000000000000000000000000000" && (
        <p className="mt-4 text-center text-xs text-slate-400">
          Referred by {referrer.slice(0, 8)}...
        </p>
      )}
    </div>
  );
}
