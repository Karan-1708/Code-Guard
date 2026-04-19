import { useState } from "react";
import { useAuth, useUser, Show, UserButton } from "@clerk/nextjs";
import ReactMarkdown from "react-markdown";
import { PricingTable } from "@clerk/nextjs";

// ─── Constants for dropdown options ───────────────────────────────────────────

const LANGUAGES = [
  "Python",
  "JavaScript",
  "TypeScript",
  "Java",
  "C",
  "C++",
  "Rust",
  "Go",
  "PHP",
  "Ruby",
];

const EXPERIENCE_LEVELS = [
  { value: "Junior", label: "Junior — I'm still learning" },
  { value: "Mid",    label: "Mid — I know the basics" },
  { value: "Senior", label: "Senior — I want the technical details" },
];

const SEVERITY_THRESHOLDS = [
  { value: "Critical", label: "Critical only" },
  { value: "High",     label: "High and above" },
  { value: "Medium",   label: "Medium and above" },
  { value: "Low",      label: "All severities (Low and above)" },
];

// ─── API base URL — set NEXT_PUBLIC_API_URL in .env.local for local dev ───────
const API_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";

// ─── Severity badge helper ─────────────────────────────────────────────────────
function SeverityLegend() {
  return (
    <div className="flex flex-wrap gap-4 text-xs text-gray-400 mt-4">
      {[
        { label: "Critical", color: "bg-red-500" },
        { label: "High",     color: "bg-orange-500" },
        { label: "Medium",   color: "bg-yellow-500" },
        { label: "Low",      color: "bg-blue-400" },
      ].map(({ label, color }) => (
        <span key={label} className="flex items-center gap-1.5">
          <span className={`w-2 h-2 rounded-full ${color} inline-block`} />
          {label}
        </span>
      ))}
    </div>
  );
}

// ─── Main page component ───────────────────────────────────────────────────────
export default function ProductPage() {
  const { getToken } = useAuth();
  const { user } = useUser();

  // ── Form state (camelCase — mapped to snake_case in JSON.stringify below) ────
  const [codeSnippet,       setCodeSnippet]       = useState("");
  const [language,          setLanguage]           = useState("Python");
  const [context,           setContext]            = useState("");
  const [experienceLevel,   setExperienceLevel]   = useState("Junior");
  const [severityThreshold, setSeverityThreshold] = useState("Low");
  const [githubUrl,         setGithubUrl]          = useState("");

  // ── Output / UI state ─────────────────────────────────────────────────────────
  const [output,    setOutput]    = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [error,     setError]     = useState("");
  // session_id is returned by the backend on every response and sent back on
  // the next request so the DynamoDB memory layer can load conversation history.
  const [sessionId, setSessionId] = useState<string | null>(null);

  // ─── Submit handler ────────────────────────────────────────────────────────────
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    setOutput("");
    setError("");

    try {
      const token = await getToken();

      // ⚠️  camelCase → snake_case mapping happens here.
      // Every key must match the Pydantic InputRecord field name exactly
      // or FastAPI returns 422 Unprocessable Entity.
      const res = await fetch(`${API_URL}/api`, {
        method: "POST",
        headers: {
          "Content-Type":  "application/json",
          "Authorization": `Bearer ${token}`,
        },
        body: JSON.stringify({
          code_snippet:       codeSnippet,
          language:           language,
          context:            context,
          experience_level:   experienceLevel,
          severity_threshold: severityThreshold,
          github_url:         githubUrl.trim() || null,
          // Pass back the session_id from the previous response so the backend
          // can load conversation history from DynamoDB. null on the first request.
          session_id:         sessionId,
        }),
      });

      if (!res.ok) {
        const msg = res.status === 401
          ? "Authentication failed. Please sign in again."
          : `Server error ${res.status}. Please try again.`;
        setError(msg);
        setIsLoading(false);
        return;
      }

      const data = await res.json();
      setOutput(data.response);
      // Persist the session_id so follow-up requests use the same DynamoDB item.
      setSessionId(data.session_id);
    } catch {
      setError("Failed to connect to the CodeGuard API. Please check your connection.");
    } finally {
      setIsLoading(false);
    }
  };

  // ─── Render ────────────────────────────────────────────────────────────────────
  return (
    <div className="min-h-screen bg-gray-950 text-gray-100 font-sans">

      {/* ── Header ─────────────────────────────────────────────────────────────── */}
      <header className="sticky top-0 z-10 border-b border-gray-800 bg-gray-950/90 backdrop-blur px-6 py-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <span className="text-xl font-bold tracking-tight text-emerald-400">
            CodeGuard
          </span>
          <span className="hidden sm:inline text-xs text-gray-500 bg-gray-800 px-2 py-0.5 rounded-full">
            AI Security Review
          </span>
        </div>

        {/* UserButton in top-right corner as required */}
        <UserButton showName={true} />
      </header>

      {/* ── Subscription gate ────────────────────────────────────────────────────
           <Protect> shows PricingTable to users without an active subscription.
           The real enforcement is on the backend — Clerk JWT verification in
           FastAPI ensures unauthenticated or non-subscribed calls return 401.
      ──────────────────────────────────────────────────────────────────────────── */}
      <Show
        when={{ plan: "paid_subscription" }}
        fallback={
          <div className="flex flex-col items-center justify-center py-24 px-4 text-center">
            <div className="mb-6">
              <h2 className="text-2xl font-semibold mb-2">Premium Access Required</h2>
              <p className="text-gray-400 max-w-md mx-auto">
                CodeGuard's AI-powered security review is a premium feature.
                Subscribe below to get instant, unlimited access.
              </p>
            </div>
            <PricingTable />
          </div>
        }
      >
        {/* ── Main two-column layout ──────────────────────────────────────────── */}
        <main className="max-w-6xl mx-auto px-4 sm:px-6 py-10 grid grid-cols-1 lg:grid-cols-2 gap-10">

          {/* ── LEFT — Input Form ──────────────────────────────────────────────── */}
          <section>
            <h1 className="text-lg font-semibold mb-1">Submit Code for Review</h1>
            <p className="text-sm text-gray-400 mb-6">
              Paste your code, configure the review options, and let CodeGuard identify
              vulnerabilities, provide a corrected version, and explain the risks.
            </p>

            <form onSubmit={handleSubmit} className="space-y-5">

              {/* Code Snippet ─────────────────────────────────────────────────── */}
              <div>
                <label className="block text-sm font-medium text-gray-300 mb-1">
                  Code Snippet <span className="text-red-400">*</span>
                </label>
                <textarea
                  value={codeSnippet}
                  onChange={(e) => setCodeSnippet(e.target.value)}
                  rows={14}
                  required
                  minLength={10}
                  placeholder={"# Paste your code here...\n# Minimum 10 characters required."}
                  className="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2.5
                             text-sm font-mono text-gray-100 placeholder-gray-600
                             focus:outline-none focus:border-emerald-500 focus:ring-1
                             focus:ring-emerald-500/30 resize-y transition-colors"
                />
                <p className="text-xs text-gray-500 mt-1">
                  {codeSnippet.length} characters
                </p>
              </div>

              {/* Language ─────────────────────────────────────────────────────── */}
              <div>
                <label className="block text-sm font-medium text-gray-300 mb-1">
                  Programming Language <span className="text-red-400">*</span>
                </label>
                <select
                  value={language}
                  onChange={(e) => setLanguage(e.target.value)}
                  className="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2.5
                             text-sm text-gray-100 focus:outline-none focus:border-emerald-500
                             focus:ring-1 focus:ring-emerald-500/30 transition-colors"
                >
                  {LANGUAGES.map((lang) => (
                    <option key={lang} value={lang}>{lang}</option>
                  ))}
                </select>
              </div>

              {/* Code Context ────────────────────────────────────────────────── */}
              <div>
                <label className="block text-sm font-medium text-gray-300 mb-1">
                  Code Context <span className="text-red-400">*</span>
                </label>
                <textarea
                  value={context}
                  onChange={(e) => setContext(e.target.value)}
                  rows={3}
                  required
                  maxLength={500}
                  placeholder="Briefly describe what this code does and how it is used in the application — e.g., 'User login endpoint that queries a PostgreSQL database and returns a JWT.'"
                  className="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2.5
                             text-sm text-gray-100 placeholder-gray-600 focus:outline-none
                             focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500/30
                             resize-none transition-colors"
                />
                <p className="text-xs text-gray-500 mt-1">
                  {context.length} / 500 characters
                </p>
              </div>

              {/* Experience Level + Severity Threshold ── side by side ─────────── */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-300 mb-1">
                    Your Experience Level
                  </label>
                  <select
                    value={experienceLevel}
                    onChange={(e) => setExperienceLevel(e.target.value)}
                    className="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2.5
                               text-sm text-gray-100 focus:outline-none focus:border-emerald-500
                               focus:ring-1 focus:ring-emerald-500/30 transition-colors"
                  >
                    {EXPERIENCE_LEVELS.map(({ value, label }) => (
                      <option key={value} value={value}>{label}</option>
                    ))}
                  </select>
                  <p className="text-xs text-gray-500 mt-1">
                    Controls the tone of the Developer Briefing.
                  </p>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-300 mb-1">
                    Minimum Severity to Report
                  </label>
                  <select
                    value={severityThreshold}
                    onChange={(e) => setSeverityThreshold(e.target.value)}
                    className="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2.5
                               text-sm text-gray-100 focus:outline-none focus:border-emerald-500
                               focus:ring-1 focus:ring-emerald-500/30 transition-colors"
                  >
                    {SEVERITY_THRESHOLDS.map(({ value, label }) => (
                      <option key={value} value={value}>{label}</option>
                    ))}
                  </select>
                  <p className="text-xs text-gray-500 mt-1">
                    Filters findings in the Vulnerability Report.
                  </p>
                </div>
              </div>

              {/* GitHub URL ── optional ─────────────────────────────────────── */}
              <div>
                <label className="block text-sm font-medium text-gray-300 mb-1">
                  GitHub URL{" "}
                  <span className="text-gray-500 font-normal text-xs">(optional)</span>
                </label>
                <input
                  type="url"
                  value={githubUrl}
                  onChange={(e) => setGithubUrl(e.target.value)}
                  placeholder="https://github.com/your-username/repo/blob/main/path/to/file.py"
                  pattern="https://github\.com/.+"
                  title="Must be a valid GitHub URL starting with https://github.com/"
                  className="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2.5
                             text-sm text-gray-100 placeholder-gray-600 focus:outline-none
                             focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500/30
                             transition-colors"
                />
                <p className="text-xs text-gray-500 mt-1">
                  Format: https://github.com/username/repo/...
                </p>
              </div>

              {/* Submit Button ──────────────────────────────────────────────── */}
              <button
                type="submit"
                disabled={isLoading || codeSnippet.trim().length < 10}
                className="w-full bg-emerald-600 hover:bg-emerald-500 active:bg-emerald-700
                           disabled:bg-gray-700 disabled:cursor-not-allowed
                           text-white font-semibold py-2.5 rounded-lg
                           transition-colors text-sm tracking-wide"
              >
                {isLoading
                  ? "Analysing code — please wait..."
                  : "Run Security Review →"}
              </button>

              {/* Error message ──────────────────────────────────────────────── */}
              {error && (
                <div className="text-sm text-red-400 bg-red-900/20 border border-red-800/50
                                rounded-lg px-3 py-2.5">
                  {error}
                </div>
              )}
            </form>
          </section>

          {/* ── RIGHT — Output ─────────────────────────────────────────────────── */}
          <section className="flex flex-col">
            <h2 className="text-lg font-semibold mb-1">Review Output</h2>
            <p className="text-sm text-gray-400 mb-6">
              CodeGuard's structured security analysis appears here. Results stream in
              real time as the AI processes your code.
            </p>

            {/* Output area */}
            <div className="flex-1 bg-gray-900 border border-gray-700 rounded-lg
                            min-h-[520px] p-5 overflow-y-auto">

              {/* Loading placeholder — before any output arrives */}
              {isLoading && !output && (
                <div className="flex items-center gap-2 text-emerald-400 text-sm">
                  <span className="animate-pulse text-lg">●</span>
                  <span>CodeGuard is reviewing your code…</span>
                </div>
              )}

              {/* Empty state */}
              {!isLoading && !output && (
                <div className="flex flex-col items-center justify-center h-full
                                text-center py-16">
                  <div className="text-4xl mb-3 opacity-30">🛡️</div>
                  <p className="text-gray-500 text-sm">
                    Your security review will appear here after submission.
                  </p>
                  <p className="text-gray-600 text-xs mt-2">
                    Results include a Vulnerability Report, Corrected Code,
                    and a Developer Briefing.
                  </p>
                </div>
              )}

              {/* Streamed Markdown output */}
              {output && (
                <div
                  className="
                    prose prose-invert prose-sm max-w-none

                    prose-h2:text-emerald-400 prose-h2:font-semibold
                    prose-h2:border-b prose-h2:border-gray-700 prose-h2:pb-1 prose-h2:mb-3

                    prose-h3:text-gray-200 prose-h3:font-medium

                    prose-p:text-gray-300 prose-p:leading-relaxed

                    prose-code:text-emerald-300 prose-code:bg-gray-800
                    prose-code:px-1.5 prose-code:py-0.5 prose-code:rounded
                    prose-code:text-xs prose-code:font-mono

                    prose-pre:bg-gray-800 prose-pre:border prose-pre:border-gray-700
                    prose-pre:rounded-lg prose-pre:text-xs

                    prose-strong:text-gray-100

                    prose-li:text-gray-300
                    prose-ul:space-y-1
                    prose-ol:space-y-1

                    prose-a:text-emerald-400 prose-a:underline-offset-2
                  "
                >
                  <ReactMarkdown>{output}</ReactMarkdown>
                </div>
              )}
            </div>

            {/* Severity legend — shown only when there is output */}
            {output && <SeverityLegend />}

            {/* Loading indicator — while waiting for Bedrock response */}
            {isLoading && output && (
              <p className="text-xs text-emerald-500 mt-2 animate-pulse">
                ● Analysing…
              </p>
            )}
          </section>

        </main>
      </Show>
    </div>
  );
}