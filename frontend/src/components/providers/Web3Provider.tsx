"use client";

import { WagmiProvider, http } from "wagmi";
import { polygon, polygonAmoy, hardhat } from "wagmi/chains";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
  RainbowKitProvider,
  getDefaultConfig,
  lightTheme,
} from "@rainbow-me/rainbowkit";
import "@rainbow-me/rainbowkit/styles.css";
import { type ReactNode } from "react";

// Use local Anvil chain in development
const isDev = process.env.NODE_ENV === "development";

const config = getDefaultConfig({
  appName: "Lotto",
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "demo",
  chains: isDev ? [hardhat, polygonAmoy, polygon] : [polygon, polygonAmoy],
  transports: {
    [hardhat.id]: http("http://127.0.0.1:8545"),
    [polygon.id]: http(
      process.env.NEXT_PUBLIC_POLYGON_RPC_URL ??
        "https://polygon-rpc.com"
    ),
    [polygonAmoy.id]: http(
      process.env.NEXT_PUBLIC_AMOY_RPC_URL ??
        "https://rpc-amoy.polygon.technology"
    ),
  },
  ssr: true,
});

const queryClient = new QueryClient();

export function Web3Provider({ children }: { children: ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider
          theme={lightTheme({
            accentColor: "#0f172a",
            accentColorForeground: "white",
            borderRadius: "large",
          })}
        >
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
