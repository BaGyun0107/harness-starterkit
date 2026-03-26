// Claude Code Hook Types for oh-my-agent
// Shared across Claude Code, Codex CLI, Gemini CLI, and Qwen Code

// --- Vendor Detection ---

export type Vendor = "claude" | "codex" | "gemini" | "qwen";

// --- Hook Input (unified) ---

export interface HookInput {
  prompt?: string;
  sessionId?: string;
  session_id?: string;
  hook_event_name?: string;
  cwd?: string;
  // Gemini: AfterAgent fields
  prompt_response?: string;
  stop_hook_active?: boolean;
  // Claude/Qwen: Stop fields
  stopReason?: string;
}

// --- Hook Output Builders ---

export function makePromptOutput(
  vendor: Vendor,
  additionalContext: string,
): string {
  switch (vendor) {
    case "claude":
      return JSON.stringify({ additionalContext });
    case "codex":
      return JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext,
        },
      });
    case "gemini":
      return JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "BeforeAgent",
          additionalContext,
        },
      });
    case "qwen":
      // Qwen Code fork uses hookSpecificOutput (same as Codex)
      return JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext,
        },
      });
  }
}

export function makeBlockOutput(vendor: Vendor, reason: string): string {
  switch (vendor) {
    case "claude":
    case "codex":
    case "qwen":
      return JSON.stringify({ decision: "block", reason });
    case "gemini":
      // Gemini AfterAgent uses "deny" to reject response and force retry
      return JSON.stringify({ decision: "deny", reason });
  }
}

// --- Shared Types ---

export interface ModeState {
  workflow: string;
  sessionId: string;
  activatedAt: string;
  reinforcementCount: number;
}
