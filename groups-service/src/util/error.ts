export class AppError extends Error {
  constructor(
    public statusCode: number,
    public message: string
  ) {
    super(message);
  }
}

export class BadRequest extends AppError {
  constructor(message: string) {
    super(400, message);
  }
}

export class NotFound extends AppError {
  constructor(message: string) {
    super(404, message);
  }
}

export class Forbidden extends AppError {
  constructor(message: string) {
    super(403, message);
  }
}

export class Conflict extends AppError {
  constructor(message: string) {
    super(409, message);
  }
}