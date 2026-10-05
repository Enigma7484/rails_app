RubyonRails frontend/backend for BillsAgent.

## Introduction

Open `/` or `/intro` for the public BillsAgent introduction. Signed-in users can
revisit it through **Discover** in the navigation. The primary CTA opens registration
for visitors and the dashboard for signed-in users; workflow links use existing
protected upload, manual-entry, and dashboard routes.

The four-tab tour uses explicitly fictional CAD data. It makes no network requests
and does not save demo decisions. It supports keyboard tab navigation, existing
appearance settings, and a readable fallback when JavaScript is unavailable.
OCR for scanned PDFs is marked as planned; cancellations are tracked manually.

With Ruby and Postgres configured, run `bin/rails server` and open
`http://localhost:3000/intro`. Verify with `bin/rails test`, `bin/rubocop`, and
`bin/rails assets:precompile`.

## Production database

Production uses Postgres through `DATABASE_URL`.

For the Render-to-Neon migration notes, see `docs/render-to-neon.md`.
