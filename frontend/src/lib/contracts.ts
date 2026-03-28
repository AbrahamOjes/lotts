import { type Address } from "viem";
import LotteryABI from "./abi/Lottery.json";
import LPVaultABI from "./abi/LPVault.json";
import ReferralManagerABI from "./abi/ReferralManager.json";

// Contract addresses — update after deployment
export const CONTRACTS = {
  lottery: (process.env.NEXT_PUBLIC_LOTTERY_ADDRESS ?? "0x0000000000000000000000000000000000000000") as Address,
  lpVault: (process.env.NEXT_PUBLIC_LP_VAULT_ADDRESS ?? "0x0000000000000000000000000000000000000000") as Address,
  referralManager: (process.env.NEXT_PUBLIC_REFERRAL_MANAGER_ADDRESS ?? "0x0000000000000000000000000000000000000000") as Address,
  usdc: (process.env.NEXT_PUBLIC_USDC_ADDRESS ?? "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359") as Address,
} as const;

export const ABIS = {
  lottery: LotteryABI,
  lpVault: LPVaultABI,
  referralManager: ReferralManagerABI,
} as const;

// USDC has 6 decimals
export const USDC_DECIMALS = 6;

// ERC20 minimal ABI for approve/allowance
export const ERC20_ABI = [
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
  },
  {
    name: "allowance",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
] as const;
