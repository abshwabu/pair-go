# Pair

**Pair** is an accountability app that matches two users around a shared goal (reading a book, watching a show, a fitness habit, etc.) and provides them with a shared todo list, real-time chat, and daily check-in streaks.

---

## Repository Layout

```
.
├── Dockerfile              # Multi-stage static Go binary build for backend
├── docker-compose.yml      # Service definitions (single backend + SQLite named volume)
├── README.md               # Root documentation
├── backend/                # Go API application
│   ├── cmd/server/main.go  # Server entrypoint with graceful shutdown
│   ├── internal/
│   │   ├── config/         # Environment configuration loader
│   │   ├── db/             # SQLite connection (WAL, single writer, read pool, migrations)
│   │   ├── auth/           # Opaque bearer tokens, bcrypt hashing
│   │   ├── httpapi/        # Chi router, middleware, response envelopes, /healthz
│   │   ├── users/          # Users domain & repository
│   │   ├── goals/          # Goals domain & repository
│   │   ├── matching/       # Pod request matching & repository
│   │   ├── pods/           # Pods and pod members domain & repository
│   │   ├── todos/          # Shared todos domain & repository
│   │   ├── chat/           # Chat messages domain & repository
│   │   ├── checkins/       # Daily check-ins and streaks domain & repository
│   │   ├── notifications/  # Notification dispatch & repository
│   │   ├── safety/         # Reports and blocks domain & repository
│   │   ├── storage/        # S3-compatible media storage interface
│   │   └── jobs/           # robfig/cron background jobs scheduler
│   └── migrations/         # Embedded goose SQL migration files
├── mobile/                 # Flutter mobile application
│   ├── pubspec.yaml        # Dependencies (riverpod, go_router, dio, etc.)
│   └── lib/
│       ├── main.dart       # App entrypoint with ProviderScope & GoRouter
│       ├── router.dart     # GoRouter configuration
│       ├── core/           # Core cross-cutting concerns
│       │   ├── network/    # Dio HTTP client with bearer token interceptor
│       │   ├── storage/    # FlutterSecureStorage token storage
│       │   ├── theme/      # Light & Dark Material 3 theme configurations
│       │   └── widgets/    # Shared reusable widgets (e.g., LoadingView)
│       └── features/       # Feature modules
│           ├── auth/       # Auth state & presentation
│           ├── onboarding/ # Onboarding flows
│           ├── goals/      # Goal tracking
│           ├── matching/   # Peer matching
│           ├── pods/       # Accountability pods
│           ├── todos/      # Shared todo lists
│           ├── chat/       # Real-time messaging
│           ├── checkins/   # Daily check-ins & streaks
│           └── account/    # User profile & account settings
└── web/                    # Next.js 14 web client placeholder (Phase 2+)
    └── README.md           # Phase 2 placeholder notes
```

---

## Tech Stack

- **Backend**: Go 1.22+, [chi router](https://github.com/go-chi/chi), pure Go SQLite via [modernc.org/sqlite](https://modernc.org/sqlite) (CGO disabled), [goose](https://github.com/pressly/goose) for embedded migrations, bcrypt for password hashing, Google UUIDs, coder websocket for real-time, robfig/cron for scheduled jobs.
- **SQLite Concurrency Rules**:
  - `PRAGMA journal_mode = WAL`
  - `PRAGMA foreign_keys = ON`
  - `PRAGMA busy_timeout = 5000`
  - Single write handle (`SetMaxOpenConns(1)`) plus separate read connection pool (`SetMaxOpenConns(maxRead)`).
- **Mobile**: Flutter 3.x, `flutter_riverpod`, `go_router`, `dio`, `web_socket_channel`, `flutter_secure_storage`.
- **Web**: Next.js 14 (Phase 2+ placeholder in `/web`).

---

## API Conventions

- All REST routes prefixed with `/api/v1/...`
- Health check at `GET /healthz`
- Standard JSON envelope:
  - **Success**: `{ "data": ..., "meta": ..., "error": null }`
  - **Failure**: `{ "data": null, "meta": null, "error": { "code": ..., "message": ... } }`
- Authentication via opaque bearer token: `Authorization: Bearer <token>`

---

## Authentication API & cURL Examples

All responses follow the standard wrapped JSON envelope: `{ "data": ..., "meta": ..., "error": null }`.

### 1. Register User (`POST /api/v1/auth/register`)

Registers a new user account, validates input (RFC 5322 email, password ≥ 8 chars, valid IANA timezone name), hashes the password with bcrypt, creates an opaque bearer session token (32 random bytes, base64url-encoded), and returns the raw token and user profile.

```bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Dave Dev",
    "email": "dave@example.com",
    "password": "secretpassword123",
    "timezone": "America/Chicago"
  }'
```

**Response (`201 Created`):**
```json
{
  "data": {
    "token": "5gPuFkYhO6bhwFVTKCBhIdlMidM5JMnpwnQawF_Jo-A",
    "user": {
      "id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
      "name": "Dave Dev",
      "email": "dave@example.com",
      "timezone": "America/Chicago",
      "language": "en",
      "is_admin": false,
      "created_at": "2026-10-14T10:44:04Z",
      "updated_at": "2026-10-14T10:44:04Z"
    }
  },
  "meta": null,
  "error": null
}
```

### 2. Login User (`POST /api/v1/auth/login`)

Authenticates with email and password, creates and stores a new hashed session token, and returns the raw token and user profile.

```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "dave@example.com",
    "password": "secretpassword123"
  }'
```

**Response (`200 OK`):**
```json
{
  "data": {
    "token": "9xVATFOlgP2VKHiVSnebU3MRXt9J1WAsV_YRjguJjw8",
    "user": {
      "id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
      "name": "Dave Dev",
      "email": "dave@example.com",
      "timezone": "America/Chicago",
      "language": "en",
      "is_admin": false,
      "created_at": "2026-10-14T10:44:04Z",
      "updated_at": "2026-10-14T10:44:04Z"
    }
  },
  "meta": null,
  "error": null
}
```

### 3. Get Authenticated User Profile (`GET /api/v1/auth/me`)

Retrieves the currently authenticated user's profile. Requires a valid `Authorization: Bearer <token>` header. Password hash is never exposed.

```bash
curl -X GET http://localhost:8080/api/v1/auth/me \
  -H "Authorization: Bearer 9xVATFOlgP2VKHiVSnebU3MRXt9J1WAsV_YRjguJjw8"
```

**Response (`200 OK`):**
```json
{
  "data": {
    "id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "name": "Dave Dev",
    "email": "dave@example.com",
    "timezone": "America/Chicago",
    "language": "en",
    "is_admin": false,
    "created_at": "2026-10-14T10:44:04Z",
    "updated_at": "2026-10-14T10:44:04Z"
  },
  "meta": null,
  "error": null
}
```

### 4. Logout (`POST /api/v1/auth/logout`)

Deletes the active session token row from the database. Any subsequent requests using that token will be rejected with `401 Unauthorized`.

```bash
curl -X POST http://localhost:8080/api/v1/auth/logout \
  -H "Authorization: Bearer 9xVATFOlgP2VKHiVSnebU3MRXt9J1WAsV_YRjguJjw8"
```

**Response (`200 OK`):**
```json
{
  "data": {
    "message": "logged out successfully"
  },
  "meta": null,
  "error": null
}
```

---

## Profile API & Avatar Upload

All profile endpoints require an active `Authorization: Bearer <token>` header.

### 1. Get Profile (`GET /api/v1/profile`)

Semantic alias to `/auth/me`, returning the current user's profile.

```bash
curl -X GET http://localhost:8080/api/v1/profile \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": {
    "id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "name": "Dave Dev",
    "email": "dave@example.com",
    "avatar_url": "http://localhost:9000/pair-media/avatars/278c2e90-4b4f-47a7-9477-037dd2e91e18/744033ec-2321-4aee-b2a6-bfe0d0f2bc0e.png",
    "timezone": "America/Chicago",
    "language": "en",
    "is_admin": false,
    "created_at": "2026-10-14T10:44:04Z",
    "updated_at": "2026-10-14T10:55:00Z"
  },
  "meta": null,
  "error": null
}
```

### 2. Update Profile (`PATCH /api/v1/profile`)

Performs partial updates on user fields (`name`, `timezone`, `language`). Validates that `timezone` is a valid IANA timezone (e.g. `America/New_York`, `UTC`). Unknown fields are strictly rejected.

```bash
curl -X PATCH http://localhost:8080/api/v1/profile \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "David Developer",
    "timezone": "America/New_York",
    "language": "en"
  }'
```

**Response (`200 OK`):**
```json
{
  "data": {
    "id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "name": "David Developer",
    "email": "dave@example.com",
    "avatar_url": null,
    "timezone": "America/New_York",
    "language": "en",
    "is_admin": false,
    "created_at": "2026-10-14T10:44:04Z",
    "updated_at": "2026-10-14T11:00:15Z"
  },
  "meta": null,
  "error": null
}
```

### 3. Upload Avatar (`POST /api/v1/profile/avatar`)

Uploads a user avatar image via multipart form data (`file` field).
- **Validation**: Sniffs file content type (`image/jpeg`, `image/png`, `image/webp` only). Rejects spoofed or unsupported MIME types with `400 Bad Request`.
- **Size Limit**: Maximum 5MB (`5242880` bytes). Oversized files are rejected with `400 Bad Request` (`FILE_TOO_LARGE`).
- **S3 Key**: Stored under `avatars/{user_id}/{uuid}.{ext}`.
- **Persistence**: Sets `avatar_url` to `S3_PUBLIC_BASE_URL + key`, persists in SQLite, and returns the updated profile.

```bash
curl -X POST http://localhost:8080/api/v1/profile/avatar \
  -H "Authorization: Bearer <token>" \
  -F "file=@/path/to/profile_pic.png"
```

**Response (`200 OK`):**
```json
{
  "data": {
    "id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "name": "David Developer",
    "email": "dave@example.com",
    "avatar_url": "http://localhost:9000/pair-media/avatars/278c2e90-4b4f-47a7-9477-037dd2e91e18/744033ec-2321-4aee-b2a6-bfe0d0f2bc0e.png",
    "timezone": "America/New_York",
    "language": "en",
    "is_admin": false,
    "created_at": "2026-10-14T10:44:04Z",
    "updated_at": "2026-10-14T11:05:30Z"
  },
  "meta": null,
  "error": null
}
```

---

## Testing S3 Storage Locally with MinIO

To test real S3-compatible media uploads locally:

1. **Launch a MinIO container**:
```bash
docker run -d --name pair-minio \
  -p 9000:9000 -p 9001:9001 \
  -e "MINIO_ROOT_USER=minioadmin" \
  -e "MINIO_ROOT_PASSWORD=minioadmin" \
  minio/minio server /data --console-address ":9001"
```

2. **Create the `pair-media` bucket and set public read access**:
Using the MinIO Client (`mc`) or web console at `http://localhost:9001`:
```bash
# Add local minio alias
mc alias set local http://localhost:9000 minioadmin minioadmin

# Create the pair-media bucket
mc mb local/pair-media

# Set bucket to public download (for avatar URLs)
mc anonymous set download local/pair-media
```

3. **Configure Environment Variables**:
In `.env` or when starting the backend:
```env
S3_ENDPOINT=http://localhost:9000
S3_BUCKET=pair-media
S3_REGION=us-east-1
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin
S3_USE_SSL=false
S3_PUBLIC_BASE_URL=http://localhost:9000/pair-media
```

4. **Upload an avatar and access the public URL**:
```bash
# Upload avatar
curl -X POST http://localhost:8080/api/v1/profile/avatar \
  -H "Authorization: Bearer <token>" \
  -F "file=@avatar.png"

# The returned avatar_url can be directly fetched:
curl -I http://localhost:9000/pair-media/avatars/<user_id>/<uuid>.png
```

---

## Goals API

All goal endpoints require authentication via `Authorization: Bearer <token>`. Goal ownership is strictly enforced via `goals.AuthorizeOwner`: users can only view, update, or delete their own goals (mismatched owner returns `403 Forbidden`). Modifying or deleting a goal attached to an active pod returns `409 Conflict`.

### 1. Create Goal (`POST /api/v1/goals`)

Creates a new goal for the authenticated user.
- **Category enum**: `read`, `watch`, `fitness`, `habit`, `custom`
- **Pace enum**: `relaxed`, `steady`, `intense`
- **Title**: Required, 1–120 characters

```bash
curl -X POST http://localhost:8080/api/v1/goals \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "category": "read",
    "title": "Read Dune",
    "target_description": "Finish all 500 pages this month",
    "pace": "steady"
  }'
```

**Response (`201 Created`):**
```json
{
  "data": {
    "id": "a58c5f95-3a02-4452-a67d-ea94076a427f",
    "user_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "category": "read",
    "title": "Read Dune",
    "target_description": "Finish all 500 pages this month",
    "pace": "steady",
    "created_at": "2026-10-14T11:10:00Z",
    "updated_at": "2026-10-14T11:10:00Z"
  },
  "meta": null,
  "error": null
}
```

### 2. List Goals (`GET /api/v1/goals`)

Lists all goals belonging to the authenticated user, ordered newest first (`created_at DESC`).

```bash
curl -X GET http://localhost:8080/api/v1/goals \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": [
    {
      "id": "a58c5f95-3a02-4452-a67d-ea94076a427f",
      "user_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
      "category": "read",
      "title": "Read Dune",
      "target_description": "Finish all 500 pages this month",
      "pace": "steady",
      "created_at": "2026-10-14T11:10:00Z",
      "updated_at": "2026-10-14T11:10:00Z"
    }
  ],
  "meta": null,
  "error": null
}
```

### 3. Get Goal Details (`GET /api/v1/goals/{id}`)

Retrieves a single goal by ID.
- Returns `404 Not Found` if the goal does not exist.
- Returns `403 Forbidden` if the goal belongs to another user.

```bash
curl -X GET http://localhost:8080/api/v1/goals/a58c5f95-3a02-4452-a67d-ea94076a427f \
  -H "Authorization: Bearer <token>"
```

### 4. Update Goal (`PATCH /api/v1/goals/{id}`)

Partially updates a goal (`category`, `title`, `target_description`, `pace`).
- Returns `409 Conflict` (`ACTIVE_POD_CONFLICT`) if the goal is attached to an active pod via `pod_members`.
- Returns `403 Forbidden` if not owned by the authenticated user.
- Returns `404 Not Found` if goal does not exist.

```bash
curl -X PATCH http://localhost:8080/api/v1/goals/a58c5f95-3a02-4452-a67d-ea94076a427f \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Read Dune Messiah",
    "pace": "relaxed"
  }'
```

### 5. Delete Goal (`DELETE /api/v1/goals/{id}`)

Deletes a goal.
- Enforces the same active-pod restriction: returns `409 Conflict` if attached to an active pod.
- Returns `403 Forbidden` if not owned by the authenticated user.
- Returns `404 Not Found` if goal does not exist.

```bash
curl -X DELETE http://localhost:8080/api/v1/goals/a58c5f95-3a02-4452-a67d-ea94076a427f \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": {
    "message": "goal deleted successfully"
  },
  "meta": null,
  "error": null
}
```

---

## Matching System & Worker

The matching engine pairs users around common goals using an asynchronous, rules-based in-process worker (`matching.Worker`) backed by Go channels and a periodic sweep ticker.

### Matching Rules & Scoring Function (`matching.Score`)

Matching evaluates candidate pairs using pure scoring logic:
1. **Hard Requirements** (must all pass, else `ok = false`):
   - **Same Goal Category**: Both users must share the exact same category (`read`, `watch`, `fitness`, `habit`, `custom`).
   - **Same Language**: Normalized language match (e.g. `en` == `en`).
   - **Overlapping Timezone Tolerance**: Timezone offset difference computed from IANA names must be within **both** users' `timezone_tolerance_hours` (0–12).
   - **Block Exclusion**: Pairs where either user has blocked the other in the `blocks` table are excluded.
   - **Distinct Users**: Cannot match a user with themselves.
2. **Soft Scoring**:
   - **Pace Compatibility**: Same pace (`+40`), adjacent pace (`+20`, e.g. steady ↔ relaxed or steady ↔ intense), distant pace (`+0`).
   - **Timezone Closeness Bonus**: Up to `+12` points for closer timezones.
   - **Base Score**: `50` points.
3. **Atomic SQLite Transaction**:
   - Pairing executes inside a single write transaction that re-checks both requests are still `open` and neither user has joined an active pod.
   - Atomically inserts `pods` (`active`, capacity 2), two `pod_members`, a `streaks` row (zeros), and updates both `pod_requests` to `matched` with the shared `pod_id`.
   - If a race occurs, the transaction rolls back cleanly and retries the next best candidate.

---

### Matching API Endpoints

All matching endpoints require `Authorization: Bearer <token>`.

#### 1. Create Matching Request (`POST /api/v1/matching/request`)

Enqueues a matching request for an existing goal owned by the authenticated user.
- **Validation**: `goal_id` must belong to the user; `timezone_tolerance_hours` must be between `0` and `12`.
- **Conflicts (`409 Conflict`)**:
  - `ACTIVE_REQUEST_CONFLICT`: Rejected if the user already has an `open` request.
  - `ACTIVE_POD_CONFLICT`: Rejected if the user is already an active member of an active pod.

```bash
curl -X POST http://localhost:8080/api/v1/matching/request \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "goal_id": "a58c5f95-3a02-4452-a67d-ea94076a427f",
    "timezone_tolerance_hours": 3
  }'
```

**Response (`201 Created`):**
```json
{
  "data": {
    "id": "7b098284-b55f-477e-960d-563ad7e15ee2",
    "user_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "goal_id": "a58c5f95-3a02-4452-a67d-ea94076a427f",
    "status": "open",
    "timezone_tolerance_hours": 3,
    "language": "en",
    "pod_id": null,
    "created_at": "2026-10-14T11:20:00Z",
    "updated_at": "2026-10-14T11:20:00Z"
  },
  "meta": null,
  "error": null
}
```

#### 2. Get Request Status (`GET /api/v1/matching/request/{id}`)

Retrieves the status of a match request. Owner only (`403 Forbidden` if accessed by another user).

```bash
curl -X GET http://localhost:8080/api/v1/matching/request/7b098284-b55f-477e-960d-563ad7e15ee2 \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK` - Matched):**
```json
{
  "data": {
    "id": "7b098284-b55f-477e-960d-563ad7e15ee2",
    "user_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "goal_id": "a58c5f95-3a02-4452-a67d-ea94076a427f",
    "status": "matched",
    "timezone_tolerance_hours": 3,
    "language": "en",
    "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
    "created_at": "2026-10-14T11:20:00Z",
    "updated_at": "2026-10-14T11:20:05Z"
  },
  "meta": null,
  "error": null
}
```

#### 3. Cancel Matching Request (`DELETE /api/v1/matching/request/{id}`)

Cancels an open matching request.
- Owner only (`403 Forbidden` if not owner).
- Returns `409 Conflict` (`ALREADY_MATCHED`) if the request has already been matched into a pod.

```bash
curl -X DELETE http://localhost:8080/api/v1/matching/request/7b098284-b55f-477e-960d-563ad7e15ee2 \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": {
    "message": "request cancelled successfully"
  },
  "meta": null,
  "error": null
}
```

---

## Pods API

All pod endpoints require authentication via `Authorization: Bearer <token>`. Pod detail and leave actions strictly require the user to be an active member of the target pod (`left_at IS NULL`). Non-members receive `403 Forbidden` (`FORBIDDEN`), and non-existent pods return `404 Not Found` (`NOT_FOUND`).

### 1. List Active Pods (`GET /api/v1/pods`)

Lists all pods where the authenticated user is currently an active member (`left_at IS NULL`), ordered by creation date newest first.

```bash
curl -X GET http://localhost:8080/api/v1/pods \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": [
    {
      "id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
      "goal_category": "read",
      "status": "active",
      "capacity": 2,
      "created_at": "2026-10-14T11:20:05Z",
      "updated_at": "2026-10-14T11:20:05Z",
      "members": [
        {
          "user": {
            "id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
            "name": "Alice Developer",
            "avatar_url": "http://localhost:9000/pair-media/avatars/278c2e90-4b4f-47a7-9477-037dd2e91e18/avatar.png"
          },
          "goal": {
            "id": "a58c5f95-3a02-4452-a67d-ea94076a427f",
            "title": "Read 20 pages of Dune daily",
            "category": "read",
            "pace": "steady"
          },
          "joined_at": "2026-10-14T11:20:05Z"
        },
        {
          "user": {
            "id": "512a80f1-419b-44fa-9043-9828461ab102",
            "name": "Bob Reader",
            "avatar_url": null
          },
          "goal": {
            "id": "bc839d01-6101-49a3-a719-7561849aee01",
            "title": "Read Foundation trilogy",
            "category": "read",
            "pace": "steady"
          },
          "joined_at": "2026-10-14T11:20:05Z"
        }
      ],
      "streak": {
        "current_streak": 5,
        "best_streak": 12,
        "last_check_in_date": "2026-10-14"
      }
    }
  ],
  "meta": null,
  "error": null
}
```

### 2. Get Pod Detail (`GET /api/v1/pods/{id}`)

Returns the full details of a pod, including both members' public profiles (`id`, `name`, `avatar_url`), their respective goals (`id`, `title`, `category`, `pace`), and streak summary (`current_streak`, `best_streak`, `last_check_in_date`).
- Returns `404 Not Found` if the pod does not exist.
- Returns `403 Forbidden` if the requester is not an active member (`left_at IS NULL`).

```bash
curl -X GET http://localhost:8080/api/v1/pods/346ed098-efc0-4ec1-96a0-6dfd4da3ae39 \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": {
    "id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
    "goal_category": "read",
    "status": "active",
    "capacity": 2,
    "created_at": "2026-10-14T11:20:05Z",
    "updated_at": "2026-10-14T11:20:05Z",
    "members": [
      {
        "user": {
          "id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
          "name": "Alice Developer",
          "avatar_url": null
        },
        "goal": {
          "id": "a58c5f95-3a02-4452-a67d-ea94076a427f",
          "title": "Read 20 pages of Dune daily",
          "category": "read",
          "pace": "steady"
        },
        "joined_at": "2026-10-14T11:20:05Z"
      },
      {
        "user": {
          "id": "512a80f1-419b-44fa-9043-9828461ab102",
          "name": "Bob Reader",
          "avatar_url": null
        },
        "goal": {
          "id": "bc839d01-6101-49a3-a719-7561849aee01",
          "title": "Read Foundation trilogy",
          "category": "read",
          "pace": "steady"
        },
        "joined_at": "2026-10-14T11:20:05Z"
      }
    ],
    "streak": {
      "current_streak": 5,
      "best_streak": 12,
      "last_check_in_date": "2026-10-14"
    }
  },
  "meta": null,
  "error": null
}
```

### 3. Leave Pod (`POST /api/v1/pods/{id}/leave`)

Allows an active member to leave the pod.
- Executed atomically in a single SQLite transaction.
- Sets `pod_members.left_at` to the current RFC3339 UTC timestamp.
- If remaining active members in the pod drop below 2, automatically sets `pods.status` to `dissolved`.
- Returns `404 Not Found` if the pod does not exist.
- Returns `403 Forbidden` if the user is not an active member or has already left.

```bash
curl -X POST http://localhost:8080/api/v1/pods/346ed098-efc0-4ec1-96a0-6dfd4da3ae39/leave \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": {
    "message": "left pod successfully"
  },
  "meta": null,
  "error": null
}
```

### 4. Reusable Middleware & Helpers for Domain Extensions

The `internal/pods` package exports reusable utilities to enforce pod membership and handle lifecycle transitions across all future pod-scoped features (todos, chat, check-ins, safety):

- `pods.RequireMember(podID ...string) func(http.Handler) http.Handler`: Chi middleware that checks authentication, validates pod existence (`404`), verifies active membership (`403`), and injects verified `*pods.Pod` and `*pods.PodMember` into the request context (`pods.PodFromContext` / `pods.PodMemberFromContext`). It extracts pod ID from route params (`id`, `podID`, `pod_id`) or query params (`pod_id`, `podId`).
- `pods.RequireMemberUser(ctx context.Context, podID, userID string) (*pods.PodMember, error)`: Package helper verifying user membership programmatically.
- `pods.LeaveUser(ctx context.Context, podID, userID string) error`: Package function exported for safety, blocking, or moderation handlers to dissolve pods when members block each other.

---

## Todos API

All todo endpoints are nested under a pod (`/api/v1/pods/{pod}/todos`) and require authentication and active pod membership via `pods.RequireMember()`. Non-members receive `403 Forbidden` (`FORBIDDEN`), and cross-pod access or unknown pod IDs return `404 Not Found` (`NOT_FOUND`).

In all responses, `assigned_to` returns the assigned user ID (string) or `null` for shared tasks, allowing the mobile app to cleanly render `"Me / Partner / Shared"`.

### 1. List Pod Todos (`GET /api/v1/pods/{pod}/todos`)

Lists todos for the pod.
- **Query parameters**:
  - `assigned_to`: a user ID string, or `"shared"` for unassigned/shared tasks (`assigned_to IS NULL`).
  - `is_done`: `true` or `false`.
  - `sort`: `due_date` (sorts by due date with `NULL`s last).
- **Default order**: open tasks first (`is_done = 0`), then by due date (`NULL`s last), then by creation date (`created_at ASC`).

```bash
curl -X GET "http://localhost:8080/api/v1/pods/346ed098-efc0-4ec1-96a0-6dfd4da3ae39/todos?assigned_to=shared&is_done=false" \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": [
    {
      "id": "78174fb0-5d68-4509-9fc6-f089dcbfb15b",
      "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
      "created_by": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
      "assigned_to": null,
      "title": "Read Chapter 4 together",
      "notes": "Discuss plot twists at 8pm",
      "due_date": "2026-10-20",
      "is_done": false,
      "completed_at": null,
      "created_at": "2026-10-14T11:30:00Z",
      "updated_at": "2026-10-14T11:30:00Z"
    }
  ],
  "meta": null,
  "error": null
}
```

### 2. Create Todo (`POST /api/v1/pods/{pod}/todos`)

Creates a new todo in the pod.
- `title`: required, trimmed non-empty string.
- `notes`: optional string (or null).
- `due_date`: optional string in `YYYY-MM-DD` format (or null).
- `assigned_to`: optional user ID. If provided, must be an active member of the pod (rejected with `400 Bad Request` otherwise). Omit, leave empty, or specify `"shared"` for shared tasks.

```bash
curl -X POST http://localhost:8080/api/v1/pods/346ed098-efc0-4ec1-96a0-6dfd4da3ae39/todos \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Finish Dune Part 1",
    "notes": "Read through page 200",
    "due_date": "2026-10-25",
    "assigned_to": "512a80f1-419b-44fa-9043-9828461ab102"
  }'
```

**Response (`201 Created`):**
```json
{
  "data": {
    "id": "78174fb0-5d68-4509-9fc6-f089dcbfb15b",
    "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
    "created_by": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "assigned_to": "512a80f1-419b-44fa-9043-9828461ab102",
    "title": "Finish Dune Part 1",
    "notes": "Read through page 200",
    "due_date": "2026-10-25",
    "is_done": false,
    "completed_at": null,
    "created_at": "2026-10-14T11:30:00Z",
    "updated_at": "2026-10-14T11:30:00Z"
  },
  "meta": null,
  "error": null
}
```

### 3. Update Todo (`PATCH /api/v1/pods/{pod}/todos/{todo}`)

Applies partial updates to a todo.
- Toggling `is_done: true` automatically sets `completed_at` to the current RFC3339 UTC timestamp.
- Toggling `is_done: false` automatically clears `completed_at` to `null`.
- Updating `assigned_to` requires the assignee to be an active member of the pod (or `null`/`"shared"` to make it shared).
- The todo must belong to the pod in the URL (`404 Not Found` otherwise).

```bash
curl -X PATCH http://localhost:8080/api/v1/pods/346ed098-efc0-4ec1-96a0-6dfd4da3ae39/todos/78174fb0-5d68-4509-9fc6-f089dcbfb15b \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "is_done": true
  }'
```

**Response (`200 OK`):**
```json
{
  "data": {
    "id": "78174fb0-5d68-4509-9fc6-f089dcbfb15b",
    "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
    "created_by": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "assigned_to": "512a80f1-419b-44fa-9043-9828461ab102",
    "title": "Finish Dune Part 1",
    "notes": "Read through page 200",
    "due_date": "2026-10-25",
    "is_done": true,
    "completed_at": "2026-10-14T11:35:00Z",
    "created_at": "2026-10-14T11:30:00Z",
    "updated_at": "2026-10-14T11:35:00Z"
  },
  "meta": null,
  "error": null
}
```

### 4. Delete Todo (`DELETE /api/v1/pods/{pod}/todos/{todo}`)

Deletes a todo from the pod.
- **Authorization rules**: Allowed if the requester is the creator (`created_by`), or the todo is shared (`assigned_to` is `null`).
- Returns `403 Forbidden` (`FORBIDDEN`) if a non-creator attempts to delete a todo assigned to another member.
- Returns `404 Not Found` (`NOT_FOUND`) if the todo does not exist or does not belong to the pod.

```bash
curl -X DELETE http://localhost:8080/api/v1/pods/346ed098-efc0-4ec1-96a0-6dfd4da3ae39/todos/78174fb0-5d68-4509-9fc6-f089dcbfb15b \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": {
    "message": "todo deleted successfully"
  },
  "meta": null,
  "error": null
}
```

---

## Real-Time Chat & WebSocket API

Pair pods feature real-time messaging powered by an in-memory Go WebSocket hub (`coder/websocket`), with message persistence in SQLite.

All chat endpoints are nested under a pod (`/api/v1/pods/{pod}/...`) and require authentication and active pod membership via `pods.RequireMember()`. Non-members receive `403 Forbidden` (`FORBIDDEN`), and cross-pod or invalid pod IDs return `404 Not Found` (`NOT_FOUND`).

### 1. WebSocket Endpoint (`GET /api/v1/pods/{pod}/ws`)

Establishes a persistent, bidirectional WebSocket connection for live pod communication.

- **Authentication**:
  - `Authorization: Bearer <token>` header (standard HTTP handshake).
  - `?token=<token>` query parameter (recommended for web/mobile WebSocket clients that cannot set custom upgrade headers).
- **Access Control**: Validates authentication and active pod membership *before* upgrading the HTTP connection to WebSocket. Non-members are rejected immediately with standard `403 Forbidden` JSON.
- **Heartbeat**: The server issues a WebSocket ping every 30 seconds. Clients must respond with pong within the timeout window or the connection is cleanly closed.
- **Event Wire Format**: All WebSocket events are JSON frames conforming to:
  ```json
  {
    "type": "message" | "typing" | "presence",
    "data": { ... }
  }
  ```

#### WebSocket Event Types

1. **`message` Event**
   Broadcast to all connected pod members whenever a new message is posted:
   ```json
   {
     "type": "message",
     "data": {
       "id": "c1f7a242-99d6-444a-97bb-25d27b91129b",
       "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
       "sender_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
       "body": "Hey, did you read chapter 3 today?",
       "attachment_url": null,
       "created_at": "2026-10-14T11:45:00.000000Z"
     }
   }
   ```

2. **`typing` Event**
   Broadcast to other pod members when a partner starts typing (excludes the sender; not persisted):
   ```json
   {
     "type": "typing",
     "data": {
       "user_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18"
     }
   }
   ```

3. **`presence` Event**
   Broadcast to pod members when a partner connects or disconnects:
   ```json
   {
     "type": "presence",
     "data": {
       "user_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
       "online": true
     }
   }
   ```

---

### 2. List Messages (`GET /api/v1/pods/{pod}/messages`)

Fetches message history for the pod using cursor-based pagination. Messages within each returned page are ordered **oldest-to-newest** for easy chronological rendering in UI message lists.

- **Query parameters**:
  - `before`: Cursor message ID. When provided, returns messages older than this message.
  - `limit`: Number of messages to return per page (default `50`, maximum `100`).
- **Pagination metadata**:
  - `meta.next_cursor`: ID of the oldest message in the current page, to use as `before` for the next older page. Returns `null` when the beginning of the pod chat history has been reached.

```bash
curl -X GET "http://localhost:8080/api/v1/pods/346ed098-efc0-4ec1-96a0-6dfd4da3ae39/messages?limit=50" \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": [
    {
      "id": "1c7414cb-20bb-4d7a-b5bc-696ebfe2281a",
      "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
      "sender_id": "512a80f1-419b-44fa-9043-9828461ab102",
      "body": "Good morning! Ready for our daily check-in?",
      "attachment_url": null,
      "created_at": "2026-10-14T08:30:00.000000Z"
    },
    {
      "id": "c1f7a242-99d6-444a-97bb-25d27b91129b",
      "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
      "sender_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
      "body": "Yes! Just finished reading chapter 3.",
      "attachment_url": "https://s3.example.com/uploads/notes.png",
      "created_at": "2026-10-14T08:35:12.123456Z"
    }
  ],
  "meta": {
    "next_cursor": "1c7414cb-20bb-4d7a-b5bc-696ebfe2281a"
  },
  "error": null
}
```

---

### 3. Send Message (`POST /api/v1/pods/{pod}/messages`)

Persists a new message in SQLite and broadcasts it via WebSocket to all connected pod members.

- **Request Fields**:
  - `body`: Message text string (up to 4000 characters).
  - `attachment_url`: Optional S3 or public URL to media attachment.
  - At least one of `body` or `attachment_url` is required.

```bash
curl -X POST http://localhost:8080/api/v1/pods/346ed098-efc0-4ec1-96a0-6dfd4da3ae39/messages \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "body": "Just finished today'\''s workout session! Here is my progress pic.",
    "attachment_url": "https://s3.example.com/uploads/progress.jpg"
  }'
```

**Response (`201 Created`):**
```json
{
  "data": {
    "id": "39da42b9-e759-40f0-8413-1935fafa9be9",
    "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
    "sender_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "body": "Just finished today'\''s workout session! Here is my progress pic.",
    "attachment_url": "https://s3.example.com/uploads/progress.jpg",
    "created_at": "2026-10-14T09:15:00.000000Z"
  },
  "meta": null,
  "error": null
}
```

---

### 4. Send Typing Notification (`POST /api/v1/pods/{pod}/typing`)

Broadcasts a transient `typing` event to all other connected pod members over WebSocket (excluding the sender). Does not persist anything to SQLite.

```bash
curl -X POST http://localhost:8080/api/v1/pods/346ed098-efc0-4ec1-96a0-6dfd4da3ae39/typing \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": {
    "message": "typing event broadcasted"
  },
  "meta": null,
  "error": null
}
```

---

## Daily Check-Ins & Streaks API

Pair pods track daily accountability through synchronized check-ins and streaks.

### Streak Logic & Invariants
- **UTC Date Standardization**: Check-in dates are calculated strictly in UTC (`YYYY-MM-DD`). Since paired partners may reside in different timezones, using a uniform UTC date ensures unambiguous daily synchronization.
- **Both Members Required**: A pod's streak increments by 1 only when **both active members** have checked in for the same UTC date.
- **Streak Continuity**:
  - If both active members check in today and `last_check_in_date` is yesterday (or `null`), `current_streak` increments by 1.
  - If a UTC calendar day passes without both members checking in, `current_streak` resets to 0 (scheduled daily cron job at 00:05 UTC resets stale streaks and emits `streak_broken` notification events).
  - When members resume checking in after a skipped day, `current_streak` restarts at 1 while `best_streak` is preserved.
  - Recalculation is idempotent for the same date.
- **Single Check-In Per Day**: Users can only check in once per UTC date. Duplicate check-in attempts return `409 Conflict`.
- **Atomic Execution**: Creating a check-in and updating the streak executes within a single write transaction.

---

### 1. Record Check-In (`POST /api/v1/pods/{pod}/check-ins`)

Records a daily check-in for the authenticated member.

- **Request Fields**:
  - `note`: Optional string up to 500 characters.
- **Access Control**: Requires authentication and active pod membership (`pods.RequireMember()`).
- **Conflict Handling**: Returns `409 Conflict` (`CONFLICT`) if the member has already checked in for today's UTC date.

```bash
curl -X POST http://localhost:8080/api/v1/pods/346ed098-efc0-4ec1-96a0-6dfd4da3ae39/check-ins \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "note": "Read pages 50 to 80 of Dune"
  }'
```

**Response (`201 Created`):**
```json
{
  "data": {
    "id": "e2c36eb9-9132-4752-944a-38411b95b871",
    "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
    "user_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "check_in_date": "2026-10-14",
    "note": "Read pages 50 to 80 of Dune",
    "created_at": "2026-10-14T20:15:00Z",
    "current_streak": 3,
    "best_streak": 5,
    "last_check_in_date": "2026-10-14",
    "checked_in_today_by_both": true,
    "check_in": {
      "id": "e2c36eb9-9132-4752-944a-38411b95b871",
      "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
      "user_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
      "check_in_date": "2026-10-14",
      "note": "Read pages 50 to 80 of Dune",
      "created_at": "2026-10-14T20:15:00Z"
    },
    "streak": {
      "current_streak": 3,
      "best_streak": 5,
      "last_check_in_date": "2026-10-14",
      "checked_in_today_by_both": true
    }
  },
  "meta": null,
  "error": null
}
```

---

### 2. Get Pod Streak Details (`GET /api/v1/pods/{pod}/streak`)

Returns the current streak, best streak, and today's check-in status for both the authenticated user (`me_checked_in_today`) and their partner (`partner_checked_in_today`).

```bash
curl -X GET http://localhost:8080/api/v1/pods/346ed098-efc0-4ec1-96a0-6dfd4da3ae39/streak \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": {
    "current_streak": 3,
    "best_streak": 5,
    "last_check_in_date": "2026-10-14",
    "me_checked_in_today": true,
    "partner_checked_in_today": true,
    "both_checked_in_today": true
  },
  "meta": null,
  "error": null
}
```

---

### 3. List Check-Ins History (`GET /api/v1/pods/{pod}/check-ins`)

Returns recent daily check-in participation for the pod, ordered most recent first.

- **Query Parameters**:
  - `limit`: Maximum number of distinct dates to return (default: `60`).
- **Response Items**:
  - `date`: UTC date string (`YYYY-MM-DD`).
  - `member_ids`: Array of member user IDs who checked in on this date.
  - `both_checked_in`: Boolean indicating if both active members checked in.

```bash
curl -X GET "http://localhost:8080/api/v1/pods/346ed098-efc0-4ec1-96a0-6dfd4da3ae39/check-ins?limit=60" \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": [
    {
      "date": "2026-10-14",
      "member_ids": [
        "278c2e90-4b4f-47a7-9477-037dd2e91e18",
        "512a80f1-419b-44fa-9043-9828461ab102"
      ],
      "both_checked_in": true
    },
    {
      "date": "2026-10-13",
      "member_ids": [
        "278c2e90-4b4f-47a7-9477-037dd2e91e18"
      ],
      "both_checked_in": false
    }
  ],
  "meta": null,
  "error": null
}
```

---

### 4. Scheduled Jobs (Daily Stale Streak Reset)

The backend runs a daily background cron job (`robfig/cron`) at **00:05 UTC**:
- Queries active pods (`pods.status = 'active'`) with an active streak (`current_streak > 0`) whose `last_check_in_date` is older than yesterday.
- Sets `current_streak = 0` in SQLite while preserving `best_streak`.
- Emits a `streak_broken` event to the notification service.

---

## Safety & Moderation API

Pair provides safety tools for reporting users and blocking peers. Reports can be audited and resolved by system administrators, and blocking a user immediately dissolves any shared pod and terminates active real-time sessions.

### 1. Submit a Report (`POST /api/v1/reports`)

Authenticated users can file a report against another user.
- `reported_user_id` (required UUID): The user being reported. Cannot report yourself (`400 Bad Request`).
- `pod_id` (optional UUID): Pod where the issue occurred. If supplied, the reporting user must be an active or past member of the pod.
- `reason` (required string): Explanation of the issue (10 to 1,000 characters).

```bash
curl -X POST http://localhost:8080/api/v1/reports \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "reported_user_id": "512a80f1-419b-44fa-9043-9828461ab102",
    "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
    "reason": "Repeated inappropriate messages during check-ins."
  }'
```

**Response (`201 Created`):**
```json
{
  "data": {
    "id": "7649b7da-a3b0-4dbb-8b5e-ca6ef621ce62",
    "reporter_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "reported_user_id": "512a80f1-419b-44fa-9043-9828461ab102",
    "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
    "reason": "Repeated inappropriate messages during check-ins.",
    "status": "open",
    "created_at": "2026-10-14T21:40:00Z",
    "updated_at": "2026-10-14T21:40:00Z"
  },
  "meta": null,
  "error": null
}
```

---

### 2. List Reports (Admin Only: `GET /api/v1/reports`)

Protected by `RequireAdmin` middleware. Non-admin users receive `403 Forbidden` (`FORBIDDEN`).
- **Query Parameters**:
  - `status`: Filter by status (`open`, `reviewed`, `dismissed`). Defaults to `open`.
- Returns reports ordered by `created_at DESC`.

```bash
curl -X GET "http://localhost:8080/api/v1/reports?status=open" \
  -H "Authorization: Bearer <admin-token>"
```

**Response (`200 OK`):**
```json
{
  "data": [
    {
      "id": "7649b7da-a3b0-4dbb-8b5e-ca6ef621ce62",
      "reporter_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
      "reported_user_id": "512a80f1-419b-44fa-9043-9828461ab102",
      "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
      "reason": "Repeated inappropriate messages during check-ins.",
      "status": "open",
      "created_at": "2026-10-14T21:40:00Z",
      "updated_at": "2026-10-14T21:40:00Z"
    }
  ],
  "meta": null,
  "error": null
}
```

---

### 3. Update Report Status (Admin Only: `PATCH /api/v1/reports/{id}`)

Protected by `RequireAdmin`. Allows administrators to review or dismiss a report.
- Body: `{"status": "reviewed"}` or `{"status": "dismissed"}`.

```bash
curl -X PATCH http://localhost:8080/api/v1/reports/7649b7da-a3b0-4dbb-8b5e-ca6ef621ce62 \
  -H "Authorization: Bearer <admin-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "reviewed"
  }'
```

**Response (`200 OK`):**
```json
{
  "data": {
    "id": "7649b7da-a3b0-4dbb-8b5e-ca6ef621ce62",
    "reporter_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "reported_user_id": "512a80f1-419b-44fa-9043-9828461ab102",
    "pod_id": "346ed098-efc0-4ec1-96a0-6dfd4da3ae39",
    "reason": "Repeated inappropriate messages during check-ins.",
    "status": "reviewed",
    "created_at": "2026-10-14T21:40:00Z",
    "updated_at": "2026-10-14T21:45:00Z"
  },
  "meta": null,
  "error": null
}
```

---

### 4. Block a User (`POST /api/v1/blocks`)

Blocks another user.
- `blocked_user_id` (required UUID): User to block. Cannot block self (`400 Bad Request`). Duplicate block returns `409 Conflict` (`ALREADY_BLOCKED`).
- **Immediate Side Effects**:
  - In the **same database transaction**, if the two users currently share an active pod, the pod is dissolved (`status = 'dissolved'`) and both users are recorded with `left_at = CURRENT_TIMESTAMP`.
  - Active WebSocket connections for that pod are immediately closed via the chat hub.
  - Future pod matching requests exclude blocked pairs in candidate evaluation.

```bash
curl -X POST http://localhost:8080/api/v1/blocks \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "blocked_user_id": "512a80f1-419b-44fa-9043-9828461ab102"
  }'
```

**Response (`201 Created`):**
```json
{
  "data": {
    "id": "8f395719-74d1-4b11-a8ce-164789d6e81f",
    "user_id": "278c2e90-4b4f-47a7-9477-037dd2e91e18",
    "blocked_user_id": "512a80f1-419b-44fa-9043-9828461ab102",
    "created_at": "2026-10-14T21:50:00Z"
  },
  "meta": null,
  "error": null
}
```

---

### 5. List Blocks (`GET /api/v1/blocks`)

Retrieves the list of users blocked by the authenticated user, joined with profile information (`name`, `avatar_url`).

```bash
curl -X GET http://localhost:8080/api/v1/blocks \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": [
    {
      "id": "8f395719-74d1-4b11-a8ce-164789d6e81f",
      "blocked_user_id": "512a80f1-419b-44fa-9043-9828461ab102",
      "name": "Jane Doe",
      "avatar_url": "http://localhost:9000/pair-media/avatars/512a80f1-419b-44fa-9043-9828461ab102/avatar.png",
      "created_at": "2026-10-14T21:50:00Z"
    }
  ],
  "meta": null,
  "error": null
}
```

---

### 6. Unblock a User (`DELETE /api/v1/blocks/{id}`)

Removes a block. Only the creator of the block can delete it (attempting to delete another user's block returns `403 Forbidden`).

```bash
curl -X DELETE http://localhost:8080/api/v1/blocks/8f395719-74d1-4b11-a8ce-164789d6e81f \
  -H "Authorization: Bearer <token>"
```

**Response (`200 OK`):**
```json
{
  "data": {
    "message": "unblocked successfully"
  },
  "meta": null,
  "error": null
}
```

---

## Running the Backend

### Option 1: Docker Compose (Recommended)

Start the backend service with persistent SQLite volume storage:

```bash
docker compose up -d
```

> **Note**: The container listens on container port `8080`. The host port defaults to `8080` (or configure via `PORT` environment variable, e.g., `PORT=8082 docker compose up -d`).

Check backend health:

```bash
curl http://localhost:8080/healthz
```

Expected response:
```json
{
  "data": {
    "database": "ok",
    "status": "ok",
    "time": "2026-10-14T10:17:05Z"
  },
  "meta": null,
  "error": null
}
```

Stop the containers:

```bash
docker compose down
```

### Option 2: Local Go Server

Run directly with Go:

```bash
cd backend
go run cmd/server/main.go
```

To promote a user to administrator via CLI:

```bash
cd backend
go run cmd/server/main.go --make-admin admin@example.com
```

To run unit tests:

```bash
cd backend
go test -v ./...
```

---

## Running the Mobile App

Ensure Flutter 3.x is installed:

```bash
cd mobile

# Fetch dependencies
flutter pub get

# Run tests & analyzer
flutter analyze
flutter test

# Run application on an available device/emulator (e.g. Linux desktop, Android emulator, iOS simulator)
flutter run
```

---

## License

MIT
