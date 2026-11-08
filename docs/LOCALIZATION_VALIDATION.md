# Localization validation / 多言語化の検証記録

This record separates documentation checks, automated checks, browser observations and remote CI. A checklist or historical result is not proof that the final commit passed. / 文書確認、自動検証、ブラウザ実測、remote CIを区別します。チェック項目や過去の成功は、最終commitの成功を示しません。

## Documentation / ドキュメント

- English and Japanese entrance documents: `README.md` / `README.ja.md`, `docs/QUICK_START.md` / `docs/QUICK_START.ja.md`, `docs/PURCHASE_DEMO.md` / `docs/PURCHASE_DEMO.ja.md`.
- Translation and compatibility guidance: `docs/LOCALIZATION.md` / `docs/LOCALIZATION.ja.md`.
- Standard UI: host port 3000 → container port 3000. Purchase UI: host port 3100 → authority port 3100. Both interfaces default to English.
- 2026-11-08 UTC, documentation working tree over implementation commit `6116843`: all four English/Japanese pairs have identical executable code blocks (README 6, Quick Start 6, Purchase guide 7, Localization guide 1). / 四組すべての実行用コードブロックが英日で一致しました。
- Relative file links in all nine entrance/maintenance/validation documents resolve in the checkout; `git diff --check` passes. / 九つの文書の相対ファイルリンクと空白検査に合格しました。
- English entrance/maintenance documents contain no Japanese explanation other than intentional `日本語` language-link labels. Historical document language labels were checked against their contents. / 英語文書に意図した言語リンク以外の日本語説明はなく、歴史資料の言語表示も実文書で確認しました。
- SDK contract links were read from the upstream repository; the linked support, long-Payment, multi-item, interoperability, Direct and merchant contracts are English. / SDK契約のリンク先も実際に読み、英語であることを確認しました。

## Current implementation checks / 今回の実装検証

Pending final implementation and validation results. / 最終実装に対する検証結果を記録予定です。

## Browser evidence / ブラウザ実測

Pending verified captures and observations. / 確認済みの画像と実測結果を記録予定です。

## CI and review / CI・レビュー

Read the relevant pull request's Checks and review thread for the exact remote commit. Earlier portability and purchase results remain historical evidence, not a pass for a newer revision. / 対応するPRのChecksとレビューで正確なremote commitを確認してください。以前のDocker・購入デモの結果を後続revisionの成功として扱いません。
