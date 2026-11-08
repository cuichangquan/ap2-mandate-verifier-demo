[English](LOCALIZATION.md) | [日本語](LOCALIZATION.ja.md)

# Localization: behavior, maintenance and compatibility

The normal browser demo and the A2A × AP2 purchase UI share their existing business flows across **English (`en`) and Japanese (`ja`)**. The default is English. This document describes the implementation contract and how to verify changes; it is not a claim that every listed check has run on every platform.

## Language selection and presentation-only navigation

- An explicit `locale` parameter wins over the session preference. Only `en` and `ja` are accepted. Missing preferences and unsupported or malformed values resolve to `en`.
- Controllers apply `I18n.with_locale` around each request and restore the previous locale afterward. They do not set a process-wide mutable language for other requests.
- Navigation, forms and redirect URLs carry the selected locale; the session also preserves it when a subsequent request omits the parameter.
- The document's `lang`, navigation labels, notices, application validation errors and result explanations use the selected language. Language links retain the self-identifying names **English / 日本語**. Browser-native required-field bubbles follow the browser/OS language and are not application translations; server-side consent and CSRF errors are translated.
- A language link is a safe GET to a display page. It never targets approval, run or recovery actions, and never includes a refresh/rerun flag.

### Standard demo result snapshots

`DemoController` stores presentation snapshots in a bounded **16 MiB, process-local Rails MemoryStore**, with a **30-minute TTL**. Session cookies hold opaque snapshot IDs, not signed documents. Verification POST redirects to a result GET. Merchant and multi-item language links include `view=1` and only read saved results. Ordinary reloads also reuse stored results while the same session and process-local cache remain valid, preserving signatures, hashes, diagnostics and Receipt outcomes.

Language/display URLs with `view=1` never regenerate expired, evicted or missing snapshots; they ask for an explicit run instead. This guarantee does not apply to every merchant/multi-item URL: after a server restart invalidates the session, or after other session loss, directly visiting or reloading `/merchant` or `/multi-item` is treated as a first visit and runs the synthetic demo again. An explicit rerun URL containing `run=1` also reruns when reloaded. Use the language/display links when you only want to inspect a saved result.

These snapshots support the documented **single-process local demo**, not a durable or shared multi-worker result service. Restarting the server discards them. Displaying an earlier verification result does not establish current order state, current authorization or new permission to execute.

### Purchase summaries

Purchase pages and history read saved summaries belonging to the current browser session. **Refresh status** explicitly polls services (`refresh=1`). Ordinary navigation, reload and language switching do not poll agents, approve, run or recover a purchase. **Run Agent / retry the same purchase** and **Recover the saved result** remain separate CSRF-protected actions.

The original purchase ID, approval conditions, offer, simulated execution count and signed documents are independent of display language. Request-scoped language handling does not weaken ownership checks, explicit consent, CSRF, secret filtering or replay protection.

## Where translations live

| Area | Files and key namespace |
| --- | --- |
| Standard screens | `config/locales/demo.en.yml`, `config/locales/demo.ja.yml`; `demo.*` |
| Purchase screens and dynamic results | `purchase_demo/locales/en.yml`, `purchase_demo/locales/ja.yml`; `purchase.ui`, `scenarios`, `stages`, `statuses`, `reasons`, `flash` |
| Stable purchase display codes and legacy compatibility | `purchase_demo/summary_codes.rb` |
| Standard locale regression tests | `test/demo_locale_test.rb` |
| Purchase locale and legacy-data tests | `test/purchase_locale_test.rb` |

Both languages use the same ERB template for each application. Standard service outcomes provide stable `title_key`/`reason_key` values; SDK diagnostics are obtained for each supported locale without changing their machine-readable fields. Purchase summaries contain stable codes such as `receipt_success`, `not_started` and `response_timeout`, which the view resolves into text.

## Add or update a translation

1. Add the same semantic key to both language files. Keep interpolation names (such as `%{quantity}`, `%{amount}` and `%{currency}`) identical.
2. Use the existing I18n helpers from the shared template/controller. Keep full sentences in the catalog instead of joining fragments whose grammar differs between languages.
3. Keep business decisions independent of prose. Add a stable code to `SummaryCodes::STATUS_CODES` or `REASON_CODES` when a new purchase state or reason is needed; add both translations and tests. Never compare translated strings to decide whether execution may start or repeat.
4. Translate human-readable product names only in the presentation layer. Preserve product IDs, quantities, amounts, currency codes, approval conditions, scenario IDs and machine-readable diagnostics.
5. Do not translate or rewrite signed Mandate/Receipt content, raw SD-JWT/JWS, protocol keys or values, hashes, identifiers or stored proof bytes. Do not expose secrets or unknown raw error text as a shortcut to a translated explanation.
6. Update both README files and the paired Quick Start/Purchase guides when commands, ports, features or workflow change. Keep code blocks synchronized. Label links to historical Japanese-only documents rather than implying an English translation exists.
7. Run locale and existing regression tests, then inspect both languages at desktop and narrow mobile widths. Long English text must wrap without hiding controls or currencies.

Use **AP2 verification**, **application execution decision**, **mock payment result** and **Receipt verification** consistently. A passed verifier or authentic Receipt is not, on its own, payment success. Unknown outcomes remain unknown, and an authentic Error remains failure.

## Existing stored Japanese data

No destructive data migration or volume reset is needed for localization.

- `SummaryCodes` has exact maps from previously emitted Japanese status/reason strings to stable codes. Read paths normalize **copies** for display or comparison; viewing a record does not rewrite its stored data.
- Newly produced summary status/reason fields use stable codes. Business decisions use codes and protocol state, not current translation text. Recognized historical values are normalized where they participate in an existing decision, preserving behavior after upgrade.
- Unknown historical free text receives a conservative localized fallback. It is not guessed from substrings, treated as success or rendered as untrusted diagnostic text. Its original stored value remains intact.
- Original approvals, offers, Mandates, Receipts, wire data, hashes and ledger records are not translated. Normal authorized workflow operations may still update their ordinary summary state; a display/language request does not.

When adding compatibility for another historical value, add only its exact, known mapping and a fixture test. Do not broadly replace Japanese text in the database. Test both displayed languages and assert that reading/translation leaves the saved record and original signed bytes unchanged.

## Automated checks

Build images from the final source before testing. The normal and purchase validation scripts include their respective locale test files and existing regressions.

```sh
# Standard image: existing regressions plus locale behavior and catalog checks.
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 900 sh test/docker_validation.sh normal
# Focused standard locale tests.
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby test/demo_locale_test.rb
# Purchase stack must be running. This creates synthetic purchases and restarts agents.
sh test/purchase_docker_validation.sh
# Focused purchase locale tests in the running authority container.
docker compose -f compose.purchase.yml exec -T authority \
  timeout 120 bundle exec ruby test/purchase_locale_test.rb
```

Check catalog-key/interpolation parity, English text without untranslated Japanese (except the language selector), localized success/rejection/errors, default/fallback/persistence, separate sessions and request threads, and read-only handling of known/unknown legacy records. Locale tests also assert that language/display links and reloads within the same valid session do not call verification or purchase side-effect paths, and preserve IDs, amounts, codes and results. The standard demo’s first-visit and explicit-rerun URLs have the separate behavior described above. Focused UI tests are not a substitute for live TLS, A2A, timeout, concurrency and restart checks.

## Browser checklist and evidence

1. Standard demo in both languages: all four verification cases, merchant Success/Error and multi-item success/shortage; confirm status/code/Evidence distinctions.
2. Purchase demo in both languages: all eight scenarios, explicit consent, missing consent, stale/invalid form, results, refresh, recovery and browser-owned history.
3. Submit in Japanese, follow the redirect, switch to English, reload, navigate through history and Back/Forward. Confirm the same ID, terms, original outcome and execution count. Retry the same completed purchase and confirm one mock execution.
4. After a timeout, switch languages before recovery. Confirm the state stays unknown and no new approval or dispatch occurs. Recover the same saved result and verify its original Receipt with a count of one.
5. Try an unsupported locale after choosing Japanese and confirm English fallback. Use two separate sessions with different languages and check that they remain independent.
6. Check desktop and approximately **390 × 844** mobile layouts, keyboard focus, long labels, page `lang`, navigation labels and visible USD/JPY. Check that confidential values remain absent.
7. Repeat the affected checks after any implementation changes. Record the exact revision/environment, passed/failed/not-run stages and screenshot paths. Historical successful tests do not establish current-commit success.

The current change's environment and results are recorded in [Localization validation](LOCALIZATION_VALIDATION.md). Earlier evidence remains in [purchase validation (English)](PURCHASE_VALIDATION.md), [published-gem validation (Japanese)](PUBLISHED_160.md) and [Docker portability (English/Japanese)](DOCKER_PORTABILITY_160.md). Final remote commit checks and independent review are recorded on the pull request.
