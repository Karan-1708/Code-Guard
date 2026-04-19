import { PricingTable, UserButton } from "@clerk/nextjs";
import Link from "next/link";

export default function UpgradePage() {
  return (
    <div className="min-h-screen bg-gray-950 text-gray-100 font-sans">
      <header className="sticky top-0 z-10 border-b border-gray-800 bg-gray-950/90 backdrop-blur px-6 py-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Link href="/product" className="text-xl font-bold tracking-tight text-emerald-400">CodeGuard</Link>
          <span className="hidden sm:inline text-xs text-gray-500 bg-gray-800 px-2 py-0.5 rounded-full">AI Security Review</span>
        </div>
        <div className="flex items-center gap-4">
          <Link href="/product" className="text-sm text-gray-400 hover:text-gray-200 transition-colors">Back to App</Link>
          <UserButton showName={true} />
        </div>
      </header>

      <main className="max-w-4xl mx-auto px-6 py-16 text-center">
        <div className="mb-12">
          <h1 className="text-3xl font-bold mb-3">Upgrade to Premium</h1>
          <p className="text-gray-400">
            Get unlimited reviews, all 10+ languages, and senior-level briefings.
          </p>
        </div>

        <div className="bg-gray-900 border border-gray-800 rounded-2xl p-4 sm:p-8">
          <PricingTable />
        </div>
      </main>
    </div>
  );
}
