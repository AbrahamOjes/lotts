"use client";

import { useAccount } from "wagmi";

export function TransakButton() {
  const { address } = useAccount();

  function openTransak() {
    const apiKey = process.env.NEXT_PUBLIC_TRANSAK_API_KEY ?? "demo";
    const params = new URLSearchParams({
      apiKey,
      environment: "PRODUCTION",
      cryptoCurrencyCode: "USDC",
      network: "polygon",
      defaultFiatCurrency: "NGN",
      fiatCurrency: "NGN",
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
    <button
      onClick={openTransak}
      className="btn-secondary w-full"
    >
      Buy USDC with Naira (NGN)
    </button>
  );
}
