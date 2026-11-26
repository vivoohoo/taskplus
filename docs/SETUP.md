# Setup

## Tools (Windows)

| Tool | Install | Check |
| --- | --- | --- |
| Node.js 20 or newer | https://nodejs.org | `node -v` |
| Git | `winget install Git.Git` | `git --version` |
| Java 17 | `winget install Microsoft.OpenJDK.17` | `java -version` |
| Android Studio (SDK, emulator) | `winget install Google.AndroidStudio`, then open it once and finish the setup wizard (SDK, platform tools, an emulator image) | `adb version` |
| Flutter (stable) | Not in winget: `git clone -b stable https://github.com/flutter/flutter.git C:\src\flutter`, add `C:\src\flutter\bin` to PATH | `flutter doctor` |
| Docker Desktop (needs WSL2) | `winget install Docker.DockerDesktop`, restart, start Docker Desktop once | `docker compose version` |

After installing, run `flutter doctor --android-licenses` and accept them, then `flutter doctor` until Android shows a tick.

## Backend

```sh
cd server
cp .env.example .env          # set JWT_SECRET (32+ random characters)
docker compose -f ../infra/docker-compose.yml up -d mssql redis
npm install
npm run migrate               # creates the taskplus database and tables
npm run seed                  # 3 departments, 10 people
npm run dev                   # http://localhost:8080/healthz
```

Sign in with any seeded phone, e.g. `9800000002` (Riya Shah, Support) or `9800000004` (Tushar Parmar, Development head), and the code in `DEV_FIXED_OTP` (`123456`).

Office server instead of Docker: create a SQL login for the app (read/write only, not owner) and point `DATABASE_URL` at it:

```sql
CREATE LOGIN taskplus_app WITH PASSWORD = '<strong password>';
-- after npm run migrate has created the database:
USE taskplus; CREATE USER taskplus_app FOR LOGIN taskplus_app;
ALTER ROLE db_datareader ADD MEMBER taskplus_app; ALTER ROLE db_datawriter ADD MEMBER taskplus_app;
```

Run migrations with an admin login, the API with `taskplus_app`. The SQL Server must allow SQL logins (mixed mode); Windows-only sign-in won't work with the Node driver.

## Tests

```sh
cd server
npm test                      # unit tests + integration tests (start a SQL Server container via Testcontainers; Docker must be running)
TEST_DATABASE_URL=mssql://... npm test   # use an existing SQL Server instead of a container
```

## Keys needed later (stubbed until then)

| Needed for | Setting | Where to get it |
| --- | --- | --- |
| M3 AI structuring | `GEMINI_API_KEY`, `GEMINI_MODEL` | Google AI Studio → API keys |
| M3 fallback, M4 speech to text | `GROQ_API_KEY`, `GROQ_LLM_MODEL` | console.groq.com → API keys |
| M4 voice notes, attachments | `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET` | Cloudflare → R2 → create bucket, then an API token with Object Read & Write on that bucket |
| M5 push | `FIREBASE_SERVICE_ACCOUNT_JSON` (base64) | Firebase console → project settings → service accounts → generate key. The app also needs `google-services.json` (Android) and `GoogleService-Info.plist` (iOS). |
| M6 iOS build | Apple Developer account | developer.apple.com (TestFlight) |

Free AI tiers may use content for training. Use made-up customer names, phones and licence numbers until a paid tier is in place.
