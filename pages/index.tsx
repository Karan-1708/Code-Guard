import { useState } from "react";
import Link from "next/link";
import { Show, SignInButton, UserButton } from "@clerk/nextjs";

// ─── Static data ───────────────────────────────────────────────────────────────

const FEATURES = [
  {
    badge: "DETECT",
    badgeColor: "bg-red-900/40 text-red-400 border-red-800/50",
    title: "Severity-Graded Vulnerability Detection",
    description:
      "Every finding is classified as Critical, High, Medium, or Low — with CWE identifiers " +
      "and the exact line where the issue lives. No generic warnings, no noise. " +
      "Just a prioritised list of what to fix first.",
  },
  {
    badge: "FIX",
    badgeColor: "bg-emerald-900/40 text-emerald-400 border-emerald-800/50",
    title: "Auto-Corrected Code with Inline Fix Comments",
    description:
      "CodeGuard doesn't just flag problems — it hands you a fully corrected version of your " +
      "code with a # SECURITY FIX: comment on every change. You see exactly what was fixed and why, " +
      "so you learn while you ship.",
  },
  {
    badge: "LEARN",
    badgeColor: "bg-blue-900/40 text-blue-400 border-blue-800/50",
    title: "Developer Briefing Tuned to Your Experience",
    description:
      "Junior developers get plain-language explanations and real-world attack scenarios. " +
      "Senior engineers get the full technical breakdown. The same review, " +
      "calibrated to actually teach you something instead of talking over your head.",
  },
  {
    badge: "FAST",
    badgeColor: "bg-yellow-900/40 text-yellow-400 border-yellow-800/50",
    title: "10+ Languages, Results in Seconds",
    description:
      "Python, JavaScript, TypeScript, Java, C, C++, Rust, Go, PHP, Ruby — paste code in " +
      "any mainstream language and receive a structured three-section security review " +
      "in under 30 seconds.",
  },
];

interface PricingPlan {
  name: string;
  clerkPlan: string;
  price: string;
  period: string;
  tagline: string;
  features: string[];
  cta: string;
  ctaHref: string;
  highlighted: boolean;
  savings: string | null;
}

const FREE_PLAN: PricingPlan = {
  name: "Free",
  clerkPlan: "free_user",
  price: "$0",
  period: "forever",
  tagline: "Explore CodeGuard with no commitment.",
  features: [
    "5 code reviews per month",
    "Security Vulnerability Report",
    "Python and JavaScript only",
    "Community support",
  ],
  cta: "Get Started Free",
  ctaHref: "/sign-up",
  highlighted: false,
  savings: null,
};

const PREMIUM_MONTHLY: PricingPlan = {
  name: "Premium",
  clerkPlan: "paid_subscription",
  price: "$30",
  period: "/ month",
  tagline: "Full security coverage for developers who ship.",
  features: [
    "Unlimited code reviews",
    "All three output sections",
    "10+ languages supported",
    "Severity threshold filtering",
    "Experience-level briefings",
    "Conversation history across sessions",
    "Priority support",
  ],
  cta: "Start Premium →",
  ctaHref: "/upgrade",
  highlighted: true,
  savings: null,
};

const PREMIUM_ANNUAL: PricingPlan = {
  ...PREMIUM_MONTHLY,
  price: "$24",
  period: "/ month",
  tagline: "Full security coverage — billed annually.",
  cta: "Start Premium →",
  savings: "Save $72/year vs monthly",
};

// ─── Sub-components ────────────────────────────────────────────────────────────

function FeatureCard({
  badge,
  badgeColor,
  title,
  description,
}: {
  badge: string;
  badgeColor: string;
  title: string;
  description: string;
}) {
  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 hover:border-emerald-800 transition-colors">
      <div className={`inline-flex items-center border text-xs font-bold px-2.5 py-1 rounded-md mb-4 tracking-wider ${badgeColor}`}>
        {badge}
      </div>
      <h3 className="text-base font-semibold text-gray-100 mb-2">{title}</h3>
      <p className="text-sm text-gray-400 leading-relaxed">{description}</p>
    </div>
  );
}

function PricingCard({
  name,
  price,
  period,
  tagline,
  features,
  cta,
  ctaHref,
  highlighted,
  savings,
}: PricingPlan) {
  return (
    <div
      className={`relative rounded-xl border p-8 flex flex-col ${
        highlighted
          ? "border-emerald-500 bg-gray-900 shadow-lg shadow-emerald-900/20"
          : "border-gray-800 bg-gray-900/60"
      }`}
    >
      {highlighted && (
        <span className="absolute -top-3 left-1/2 -translate-x-1/2 bg-emerald-500 text-gray-950 text-xs font-bold px-3 py-1 rounded-full">
          MOST POPULAR
        </span>
      )}

      <div className="mb-6">
        <h3 className="text-lg font-semibold text-gray-100 mb-1">{name}</h3>
        <p className="text-gray-500 text-sm mb-4">{tagline}</p>
        <div className="flex items-end gap-1">
          <span className="text-4xl font-bold text-gray-100">{price}</span>
          <span className="text-gray-500 text-sm mb-1">{period}</span>
        </div>
        {savings && (
          <p className="mt-2 text-xs font-semibold text-emerald-400 bg-emerald-900/30 border border-emerald-800/40 px-2.5 py-1 rounded-full inline-block">
            {savings}
          </p>
        )}
      </div>

      <ul className="space-y-3 mb-8 flex-1">
        {features.map((f) => (
          <li key={f} className="flex items-start gap-2 text-sm text-gray-300">
            <span className="text-emerald-400 mt-0.5 shrink-0">✓</span>
            {f}
          </li>
        ))}
      </ul>

      <Link
        href={ctaHref}
        className={`block text-center py-2.5 rounded-lg font-semibold text-sm transition-colors ${
          highlighted
            ? "bg-emerald-600 hover:bg-emerald-500 text-white"
            : "bg-gray-800 hover:bg-gray-700 text-gray-200"
        }`}
      >
        {cta}
      </Link>
    </div>
  );
}

// ─── Main page ─────────────────────────────────────────────────────────────────

export default function LandingPage() {
  const [annual, setAnnual] = useState(false);
  const premiumPlan = annual ? PREMIUM_ANNUAL : PREMIUM_MONTHLY;

  return (
    <div className="w-full min-h-screen bg-gray-950 text-gray-100 font-sans">

      {/* ── Header ──────────────────────────────────────────────────────────── */}
      <header className="sticky top-0 z-10 border-b border-gray-800 bg-gray-950/90 backdrop-blur">
        <div className="max-w-6xl mx-auto px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <span className="text-xl font-bold tracking-tight text-emerald-400">
              CodeGuard
            </span>
            <span className="hidden sm:inline text-xs text-gray-500 bg-gray-800 px-2 py-0.5 rounded-full">
              AI Security Review
            </span>
          </div>

          <div className="flex items-center gap-6">
            <nav className="hidden md:flex items-center gap-5 text-sm text-gray-400">
              <a href="#features" className="hover:text-gray-200 transition-colors">Features</a>
              <a href="#pricing"  className="hover:text-gray-200 transition-colors">Pricing</a>
            </nav>

            <Show when="signed-out">
              <SignInButton mode="modal">
                <button className="bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-semibold px-4 py-2 rounded-lg transition-colors">
                  Sign In
                </button>
              </SignInButton>
            </Show>

            <Show when="signed-in">
              <div className="flex items-center gap-3">
                <Link
                  href="/product"
                  className="text-sm text-emerald-400 hover:text-emerald-300 transition-colors font-medium"
                >
                  Go to App →
                </Link>
                <UserButton showName={true} />
              </div>
            </Show>
          </div>
        </div>
      </header>

      <main className="w-full">
        {/* ── Hero ──────────────────────────────────────────────────────────── */}
        <section className="w-full max-w-4xl mx-auto px-6 pt-24 pb-16 text-center">
          <div className="inline-flex items-center gap-2 bg-emerald-900/30 border border-emerald-800/50 text-emerald-400 text-xs font-medium px-3 py-1.5 rounded-full mb-8">
            <span className="w-1.5 h-1.5 bg-emerald-400 rounded-full animate-pulse" />
            Powered by AWS Bedrock · Built for developers
          </div>

          <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold tracking-tight text-gray-100 leading-tight mb-6">
            Catch the Vulnerabilities{" "}
            <span className="text-emerald-400">Your Team Misses</span>
          </h1>

          <p className="text-lg sm:text-xl text-gray-400 max-w-2xl mx-auto mb-10 leading-relaxed">
            Paste your code. Get an instant, severity-graded security review — complete with a
            corrected version and a plain-language briefing tailored to your experience level.
            No security team required.
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 mb-10">
            <Show when="signed-out">
              <SignInButton mode="modal">
                <button className="bg-emerald-600 hover:bg-emerald-500 text-white font-semibold px-8 py-3.5 rounded-xl text-base transition-colors shadow-lg shadow-emerald-900/30">
                  Scan Your First File Free →
                </button>
              </SignInButton>
            </Show>

            <Show when="signed-in">
              <Link
                href="/product"
                className="bg-emerald-600 hover:bg-emerald-500 text-white font-semibold px-8 py-3.5 rounded-xl text-base transition-colors shadow-lg shadow-emerald-900/30"
              >
                Go to CodeGuard →
              </Link>
            </Show>

            <a
              href="#features"
              className="text-gray-400 hover:text-gray-200 text-base font-medium transition-colors"
            >
              See how it works ↓
            </a>
          </div>

          <p className="text-xs text-gray-600">
            Detects SQL Injection · XSS · Insecure Deserialisation · Hardcoded Secrets ·
            Path Traversal · Command Injection · and more
          </p>
        </section>

        {/* ── Demo preview strip ────────────────────────────────────────────── */}
        <section className="w-full max-w-5xl mx-auto px-6 pb-24">
          <div className="bg-gray-900 border border-gray-800 rounded-2xl overflow-hidden">
            <div className="flex items-center gap-2 px-4 py-3 border-b border-gray-800 bg-gray-900/80">
              <span className="w-3 h-3 rounded-full bg-red-500/70" />
              <span className="w-3 h-3 rounded-full bg-yellow-500/70" />
              <span className="w-3 h-3 rounded-full bg-green-500/70" />
              <span className="ml-3 text-xs text-gray-600">CodeGuard — Security Review Output</span>
            </div>
            <div className="p-6 font-mono text-sm space-y-3 text-gray-300">
              <p className="text-emerald-400 font-semibold text-base">## Security Vulnerability Report</p>
              <div className="border-l-2 border-red-500 pl-4 space-y-1">
                <p><span className="text-red-400 font-semibold">● CRITICAL</span> — CWE-89: SQL Injection</p>
                <p className="text-gray-500">Line 14: f-string used to build SQL query with unsanitised user input.</p>
              </div>
              <div className="border-l-2 border-orange-500 pl-4 space-y-1">
                <p><span className="text-orange-400 font-semibold">● HIGH</span> — CWE-798: Hardcoded Credentials</p>
                <p className="text-gray-500">Line 3: API key stored as a string literal — exposed in version control.</p>
              </div>
              <p className="text-emerald-400 font-semibold text-base pt-2">## Corrected Code</p>
              <div className="bg-gray-800 rounded-lg p-3 text-xs text-gray-400 space-y-1">
                <p><span className="text-emerald-400"># SECURITY FIX:</span> Use parameterised query to prevent SQL injection</p>
                <p className="text-gray-300">cursor.execute(<span className="text-yellow-300">"SELECT * FROM users WHERE id = %s"</span>, (user_id,))</p>
              </div>
              <p className="text-gray-600 text-xs pt-1">▌ streaming…</p>
            </div>
          </div>
        </section>

        {/* ── Features ──────────────────────────────────────────────────────── */}
        <section id="features" className="w-full max-w-6xl mx-auto px-6 pb-24">
          <div className="text-center mb-12">
            <h2 className="text-2xl sm:text-3xl font-bold text-gray-100 mb-3">
              Everything a security review should include
            </h2>
            <p className="text-gray-400 max-w-xl mx-auto text-sm">
              CodeGuard produces structured, actionable output — not a wall of AI text.
              Three labelled sections, every time.
            </p>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
            {FEATURES.map((f) => (
              <FeatureCard key={f.title} {...f} />
            ))}
          </div>
        </section>

        {/* ── Pricing ───────────────────────────────────────────────────────── */}
        <section id="pricing" className="w-full max-w-4xl mx-auto px-6 pb-28">
          <div className="text-center mb-10">
            <h2 className="text-2xl sm:text-3xl font-bold text-gray-100 mb-3">
              Simple, transparent pricing
            </h2>
            <p className="text-gray-400 max-w-lg mx-auto text-sm mb-8">
              Start free with no credit card. Upgrade when you need unlimited reviews
              and full language support.
            </p>

            {/* ── Billing toggle ── */}
            <div className="inline-flex items-center gap-3 bg-gray-900 border border-gray-800 rounded-full px-2 py-1.5">
              <button
                onClick={() => setAnnual(false)}
                className={`px-4 py-1.5 rounded-full text-sm font-medium transition-colors ${
                  !annual
                    ? "bg-emerald-600 text-white"
                    : "text-gray-400 hover:text-gray-200"
                }`}
              >
                Monthly
              </button>
              <button
                onClick={() => setAnnual(true)}
                className={`px-4 py-1.5 rounded-full text-sm font-medium transition-colors flex items-center gap-2 ${
                  annual
                    ? "bg-emerald-600 text-white"
                    : "text-gray-400 hover:text-gray-200"
                }`}
              >
                Annual
                <span className={`text-xs font-bold px-1.5 py-0.5 rounded ${
                  annual ? "bg-emerald-500 text-white" : "bg-emerald-900/50 text-emerald-400"
                }`}>
                  −20%
                </span>
              </button>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
            <PricingCard {...FREE_PLAN} />
            <PricingCard {...premiumPlan} />
          </div>

          {annual && (
            <p className="text-center text-xs text-gray-600 mt-4">
              Billed as $288/year · Cancel anytime
            </p>
          )}
        </section>
      </main>

      {/* ── Footer ─────────────────────────────────────────────────────────── */}
      <footer className="border-t border-gray-800 py-8 px-6 text-center">
        <p className="text-xs text-gray-600">
          © 2026 CodeGuard · Built for AIE1018 · Cambrian College ·{" "}
          <a href="/product" className="text-emerald-700 hover:text-emerald-500 transition-colors">
            Open App
          </a>
        </p>
      </footer>
    </div>
  );
}
