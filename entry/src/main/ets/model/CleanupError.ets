/**
 * Error raised by the codelab itself (state wait timeout, session released while opening).
 * It exposes a numeric code like BusinessError so callers can handle both the same way.
 */
export class CleanupError extends Error {
  code: number;

  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

/**
 * Anything that owns media resources and can give them back.
 * release() must be idempotent and must never reject.
 */
export interface Releasable {
  release(): Promise<void>;
}
