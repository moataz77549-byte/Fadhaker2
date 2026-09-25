# @fadhkur/radio-engine

24/7 radio playlist scheduler and Liquidsoap stream orchestrator for **Fadhkur (فذكر)**.

## Architecture
- Dynamically queries scheduled recitations from Supabase PostgreSQL.
- Pushes audio track references into Liquidsoap's live buffer via telnet control socket.
- Handles automated cross-fading and seamless fallback to canonical recitations during connectivity drops.
