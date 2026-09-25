// Plain-language error messages (same wording as mobile/lib/core/errors.dart).
// Technical details stay in the console, not on screen.

/** An error from Supabase (PostgREST, Auth) or the network, with its code. */
export class AppError extends Error {
  constructor(
    message: string,
    readonly code: string | null = null,
    readonly network = false,
  ) {
    super(message)
    this.name = 'AppError'
  }
}

/** Thrown before a request when the browser knows it is offline. */
export class OfflineError extends AppError {
  constructor() {
    super("There's no internet connection.", null, true)
    this.name = 'OfflineError'
  }
}

const NETWORK_HINTS = /failed to fetch|networkerror|network request failed|load failed|timeout|timed out|aborted|fetch failed/i

/** True when `e` means "couldn't reach the server" rather than "the server said no". */
export function isNetworkError(e: unknown): boolean {
  if (e instanceof AppError) return e.network
  if (e instanceof DOMException) return e.name === 'TimeoutError' || e.name === 'AbortError'
  if (e instanceof TypeError) return NETWORK_HINTS.test(e.message)
  return false
}

/** Turns a `{ message, code }` error object from supabase-js into an AppError. */
export function toAppError(err: { message?: string; code?: string | null; status?: number } | null | undefined): AppError {
  const message = err?.message ?? 'Unknown error'
  const code = err?.code ?? null
  const network = !code && NETWORK_HINTS.test(message)
  return new AppError(message, code, network)
}

/** A short explanation for the person using the app. */
export function describeError(e: unknown): string {
  if (e instanceof OfflineError) return e.message
  if (isNetworkError(e)) return "Couldn't reach the server. Check your internet connection and try again."
  if (e instanceof AppError) {
    switch (e.code) {
      case '42501':
        return "You don't have permission to do that. Try signing out and back in."
      case '23505':
        return 'That name is already used. Pick a different one.'
      case '23503':
        return 'That account or category no longer exists. Pick another one and try again.'
      case '23514':
        return 'Some values were not accepted (for example an amount of zero or a missing destination account).'
      case 'PGRST301':
      case 'PGRST303':
        return 'Your session has expired. Please sign in again.'
      case 'PGRST116':
        return 'That entry no longer exists. It may have been deleted on the phone.'
    }
    if (e.code) return `The server rejected the change (${e.code}).`
  }
  return 'Something went wrong. Please try again.'
}
