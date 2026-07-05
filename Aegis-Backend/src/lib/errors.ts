export type ErrorCode =
  | 'invalid_request'
  | 'invalid_credentials'
  | 'invalid_grant'
  | 'unauthorized'
  | 'forbidden'
  | 'not_found'
  | 'too_many_requests'
  | 'internal_error';

const STATUS: Record<ErrorCode, number> = {
  invalid_request: 400,
  invalid_credentials: 401,
  invalid_grant: 401,
  unauthorized: 401,
  forbidden: 403,
  not_found: 404,
  too_many_requests: 429,
  internal_error: 500,
};

const DEFAULT_MESSAGE: Record<ErrorCode, string> = {
  invalid_request: 'The request is malformed or missing required fields',
  invalid_credentials: 'Username or password is incorrect',
  invalid_grant: 'The refresh token is invalid, expired, or already used',
  unauthorized: 'Authentication is required',
  forbidden: 'You do not have permission to access this resource',
  not_found: 'The requested resource does not exist',
  too_many_requests: 'Too many requests — please try again later',
  internal_error: 'An unexpected error occurred',
};

export class AppError extends Error {
  readonly code: ErrorCode;
  readonly status: number;

  constructor(code: ErrorCode, message?: string) {
    super(message ?? DEFAULT_MESSAGE[code]);
    this.code = code;
    this.status = STATUS[code];
    this.name = 'AppError';
  }
}
