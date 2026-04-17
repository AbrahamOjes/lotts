"use client";

import { useState } from "react";
import { useAccount } from "wagmi";

type FiatCurrency = { code: string; label: string; flag: string };

const FIAT_CURRENCIES: FiatCurrency[] = [
  { code: "NGN", label: "Nigerian Naira", flag: "NG" },
  { code: "KES", label: "Kenyan Shilling", flag: "KE" },
  { code: "GHS", label: "Ghanaian Cedi", flag: "GH" },
  { code: "INR", label: "Indian Rupee", flag: "IN" },
  { code: "PHP", label: "Philippine Peso", flag: "PH" },
  { code: "BRL", label: "Brazilian Real", flag: "BR" },
  { code: "USD", label: "US Dollar", flag: "US" },
];

function flagEmoji(countryCode: string) {
  return countryCode
    .toUpperCase()
    .split("")
    .map((c) => String.fromCodePoint(0x1f1e6 + c.charCodeAt(0) - 65))
    .join("");
}

export function TransakButton() {
  const { address } = useAccount();
  const [selected, setSelected] = useState(FIAT_CURRENCIES[0]);
  const [open, setOpen] = useState(false);

  function openTransak() {
    const apiKey = process.env.NEXT_PUBLIC_TRANSAK_API_KEY ?? "demo";
    const params = new URLSearchParams({
      apiKey,
      environment: "PRODUCTION",
      cryptoCurrencyCode: "USDC",
      network: "polygon",
      defaultFiatCurrency: selected.code,
      fiatCurrency: selected.code,
      ...(address ? { walletAddress: address } : {}),
      themeColor: "0f172a",
    });

    window.open(
      `https://global.transak.com/?${params.toString()}`,
      "transak",
      "width=450,height=700"
    );
  }

  return (
    <div className="space-y-2">
      {/* Currency selector */}
      <div className="relative">
        <button
          onClick={() => setOpen(!open)}
          className="w-full flex items-center justify-between rounded-xl border border-slate-200 bg-slate-50 px-4 py-2.5 text-sm text-slate-700 hover:bg-slate-100 transition-colors"
        >
          <span>
            {flagEmoji(selected.flag)} {selected.code} — {selected.label}
          </span>
          <svg
            className={`h-4 w-4 text-slate-400 transition-transform ${open ? "rotate-180" : ""}`}
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
          </svg>
        </button>

        {open && (
          <div className="absolute z-10 mt-1 w-full rounded-xl border border-slate-200 bg-white shadow-lg overflow-hidden">
            {FIAT_CURRENCIES.map((cur) => (
              <button
                key={cur.code}
                onClick={() => {
                  setSelected(cur);
                  setOpen(false);
                }}
                className={`w-full flex items-center gap-2 px-4 py-2.5 text-sm text-left hover:bg-slate-50 transition-colors ${
                  cur.code === selected.code ? "bg-indigo-50 text-indigo-700 font-medium" : "text-slate-700"
                }`}
              >
                {flagEmoji(cur.flag)} {cur.code} — {cur.label}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Buy button */}
      <button
        onClick={openTransak}
        className="btn-secondary w-full"
      >
        Buy USDC with {selected.code}
      </button>
    </div>
  );
}
