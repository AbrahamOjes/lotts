import { formatUnits, parseUnits } from "viem";
import { USDC_DECIMALS } from "./contracts";

export function formatUSDC(amount: bigint): string {
  return formatUnits(amount, USDC_DECIMALS);
}

export function parseUSDC(amount: string): bigint {
  return parseUnits(amount, USDC_DECIMALS);
}

export function formatUSD(amount: bigint): string {
  const num = Number(formatUnits(amount, USDC_DECIMALS));
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(num);
}

export function shortenAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function progressPercent(current: bigint, target: bigint): number {
  if (target === 0n) return 0;
  return Math.min(100, Number((current * 100n) / target));
}
