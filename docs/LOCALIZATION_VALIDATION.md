# Localization validation / 多言語化の検証記録

This record separates documentation checks, automated checks, browser observations and remote CI. A checklist or historical result is not proof that the final commit passed. / 文書確認、自動検証、ブラウザ実測、remote CIを区別します。チェック項目や過去の成功は、最終commitの成功を示しません。

## Documentation / ドキュメント

- English and Japanese entrance documents: `README.md` / `README.ja.md`, `docs/QUICK_START.md` / `docs/QUICK_START.ja.md`, `docs/PURCHASE_DEMO.md` / `docs/PURCHASE_DEMO.ja.md`.
- Translation and compatibility guidance: `docs/LOCALIZATION.md` / `docs/LOCALIZATION.ja.md`.
- Standard UI: host port 3000 → container port 3000. Purchase UI: host port 3100 → authority port 3100. Both interfaces default to English.
- 2026-11-08 UTC, final onboarding-document checks: all four English/Japanese pairs have identical executable code blocks (README 6, Quick Start 6, Purchase guide 7, Localization guide 1). / 四組すべての実行用コードブロックが英日で一致しました。
- Relative file and screenshot links in all nine entrance/maintenance/validation documents resolve in the checkout; all eight screenshot JPEGs decode successfully and were visually inspected; `git diff --check` passes. / 九つの文書の相対ファイル・画像リンク、八つのJPEG画像の読取りと目視確認、空白検査に合格しました。
- English entrance/maintenance documents contain no Japanese explanation other than intentional `日本語` language-link labels. Historical document language labels were checked against their contents. / 英語文書に意図した言語リンク以外の日本語説明はなく、歴史資料の言語表示も実文書で確認しました。
- SDK contract links were read from the upstream repository; the linked support, long-Payment, multi-item, interoperability, Direct and merchant contracts are English. / SDK契約のリンク先も実際に読み、英語であることを確認しました。

## Environment / 実行環境

- Host: MacBook Air, Apple Silicon ARM64; Docker **29.9.2**, Docker Desktop **4.96.3**, Compose **5.6.1**. / ホストはApple Silicon ARM64のMacBook Airです。
- Containers: Debian **13.7**, Ruby **4.0.9**, native **aarch64 Linux**, verified published AP2 gem **1.6.0**. / コンテナはネイティブARM64で、公開Gemを検査しました。
- Isolated browser-validation ports: standard **127.0.0.1:13000**, purchase **127.0.0.1:13100**. The existing purchase service on 3100 was not replaced. README startup ports remain **3000 / 3100**. / 検証は分離した13000／13100番を使い、既存3100番サービスを置換していません。READMEの起動ポートは3000／3100のままです。
- These are local Docker observations, not native AMD64 or production evidence. / ローカルDockerの実測であり、ネイティブAMD64や本番環境の証拠ではありません。
- Browser checks used Chrome, including a 390 px mobile viewport. A physical phone, Safari and Firefox were not tested. / ブラウザ確認はChromeと幅390pxのmobile viewportで行い、実機スマートフォン・Safari・Firefoxは未検証です。
- Task-owned QA containers were stopped after testing; ports 13000/13100 were closed. Existing user services on 3100 still returned HTTP 200. QA volumes/images were retained, and no software was installed directly on the Mac. / 検証専用コンテナは停止し、13000／13100番を閉じました。既存3100番サービスのHTTP 200を確認し、検証用volume／imageは保持しました。Macへの直接インストールはありません。

## Current implementation checks / 今回の実装検証

The final purchase checks below ran against **`b18d7fca307259bf9d4046bed385cec6ba450206`**, including the pre-upgrade session-flash fix. Standard and acceptance results were obtained at **`1ea75e3`**; their application/test code is unchanged in `b18d7fc`. These revisions are stated separately rather than counting an earlier run as a new run. / 購入の最終検証は旧セッションflash修正を含む **`b18d7fca307259bf9d4046bed385cec6ba450206`** で実行しました。通常・受理の結果は **`1ea75e3`** の実測で、そのアプリ／テストコードは`b18d7fc`でも変わっていません。以前の実行を新たな実行として数えず、revisionを区別します。

| Check / 確認 | Observed result / 実測結果 |
| --- | --- |
| Standard regression and localization suites at `1ea75e3` / 通常回帰・多言語化 | **PASS: 21 runs / 1,168 assertions**, plus all **five** standard Ruby wrappers. / 通常Ruby wrapper五つも成功。 |
| Final purchase regression and localization suites at `b18d7fc` / 最終購入回帰・多言語化 | **PASS: 83 runs / 3,739 assertions; zero failures, errors or skips**. / 失敗・エラー・skipなし。 |
| Pending-cookie flash compatibility at `b18d7fc` / 旧cookieの未表示flash互換 | **PASS: 1 run / 740 assertions** in the targeted check. This test is already included in the full purchase suite above and is **not added again**. / 個別確認にも成功。このテストは上の購入全体に含まれるため**二重加算しません**。 |
| Live purchase boundaries at `b18d7fc` / 最終実通信の境界 | **PASS:** TLS verification, role/token separation, production SSRF checks, concurrent A2A calls, real response-timeout recovery and buyer/seller restart recovery. / TLS検証・役割とtoken分離・本番SSRF検査・A2A並行呼出し・実応答timeout復旧・buyer/seller再起動復旧に成功。 |
| Optional acceptance image at `1ea75e3` / 任意の受理image | **PASS:** all **three** acceptance/long-Payment examples. / 受理・長期Paymentの三つの例に成功。 |
| Legacy persisted Japanese summaries / 既存の日本語保存summary | **PASS:** at `1ea75e3`, persisted-row hashes stayed unchanged through **en → ja → en**, with the same purchase ID and execution count **1**. After screenshots and upgrade to `b18d7fc`, the final row SHA256 comparison still matched the pre-upgrade values in **all three role databases**. / `1ea75e3`の英日往復で保存行hash・購入ID・実行回数1を維持。画像撮影と`b18d7fc`への更新後も、**三役すべてのDB**の最終行SHA256が更新前と一致。 |

The pending-flash test covers current codes, exact known legacy messages, unknown text, localized fallback without raw disclosure, ordinary one-request consumption and unchanged purchase data. It is an automated cookie/session test, not a claim that every pending-flash variant was manually exercised in the browser. / flashテストは現行コード、既知の旧文言、未知文言、原文を出さない翻訳済み代替案内、一度のリクエストでの消費、購入データ不変を確認します。cookie／sessionの自動テストであり、全flashパターンを手動ブラウザ操作したという主張ではありません。

## Browser evidence / ブラウザ実測

The following paths were manually observed in Chrome. The broader all-state, legacy-data and CSRF matrices are covered by automated tests; this manual list does not claim every matrix case was clicked through. / 以下はChromeで手動確認した経路です。全状態・旧データ・CSRFの広い組み合わせは自動テストで確認しており、すべてを手動操作したという主張ではありません。

- Approval saved before execution retained count **0** across language switches. The required-consent checkbox was enforced. / 承認保存後・実行前は言語を切り替えても回数 **0** で、必須の承認チェックも強制されました。
- Unknown outcome before explicit recovery: both Japanese and English retained the same purchase with count **1**. / 明示復旧前の結果不明を日英で表示し、同じ購入と回数 **1** を維持。
- Recovery, retry and status refresh retained the same purchase ID and count **1**. History navigation retained the chosen locale. / 復旧・再実行・状態更新で同じ購入IDと回数 **1** を維持し、履歴遷移でも選択言語を維持。
- Budget refusal retained count **0**. An authentic Error Receipt remained a failed payment with count **1**; an invalid Receipt was never shown as success. / 予算拒否は回数 **0**、真正なError Receiptは失敗のままで回数 **1**、不正なReceiptも成功にはなりませんでした。
- All three standard screens were checked: bilingual valid/missing-currency results, preserved merchant hashes, and multi-item quantity mismatch with explicit **USD**. The expired-snapshot state and unsupported-locale fallback were also observed. / 通常の三画面で英日の正常・通貨不足、販売者hash不変、複数明細の数量不足と**USD**表記を確認し、snapshot期限切れと未対応localeのfallbackも実測しました。
- Desktop **1440 px** and mobile **390 px** layouts were visually checked without horizontal overflow. The corrected mobile headline and history wrap correctly. / PC**幅1440px**とスマートフォン**幅390px**を目視確認し、横はみ出しはありません。修正後のスマートフォンの見出しと履歴も適切に折り返します。
- Eight English/Japanese desktop/mobile screenshots have been captured. Standard captures use `28fcb34`; purchase captures use the mobile-layout fix in `1ea75e3`. The `b18d7fc` flash-compatibility change does not change these ordinary rendered screens. / 英日・PC／スマートフォンの計八画像を撮影しました。通常画面は`28fcb34`、購入画面はmobile修正後の`1ea75e3`です。`b18d7fc`のflash互換修正はこれら通常表示を変えません。

### Screen comparison / 画面比較

The eight verified full-page captures are stored in image-only commit `1474c8f079aa171531c62a86bd2514462476f7c5`. Desktop captures are 1440 px wide; mobile captures are 390 px wide. / 確認済みの全ページ画像八つは、画像のみのcommit `1474c8f079aa171531c62a86bd2514462476f7c5` に保存しています。PC画像は幅1440px、スマートフォン画像は幅390pxです。

| Screen / 画面 | English desktop | 日本語 PC | English mobile | 日本語 スマートフォン |
| --- | --- | --- | --- | --- |
| Standard verification / 通常検証 | [View](images/standard-en.jpg) | [表示](images/standard-ja.jpg) | [View](images/standard-en-mobile.jpg) | [表示](images/standard-ja-mobile.jpg) |
| Purchase results and history / 購入結果・履歴 | [View](images/purchase-en.jpg) | [表示](images/purchase-ja.jpg) | [View](images/purchase-en-mobile.jpg) | [表示](images/purchase-ja-mobile.jpg) |

Both standard captures show the same successful verification code and Evidence boundary. Both purchase captures show the same synthetic purchase ID, JPY terms, four result stages and execution count of one. Language changes the presentation, not those facts. / 通常画面は同じ成功コードとEvidenceの意味、購入画面は同じ合成購入ID・JPY条件・四段階・実行回数1を示します。言語変更は表示だけを変え、これらの事実を変えません。

## CI and review / CI・レビュー

Consult this change's pull request **Checks and review discussion for the exact final HEAD**, including verified CI and independent-review outcomes. This repository record documents local evidence at the revisions named above; it does not assert remote CI or review success. Earlier portability and purchase results remain historical evidence, not a pass for a newer revision. / この変更のPRの**Checksとレビュー記録で、正確な最終HEADに対するCI・独立レビューの結果**を確認してください。本書は上記revisionでのローカル実測を記録し、remote CIやレビューの成功を主張しません。以前のDocker・購入デモの結果を後続revisionの成功として扱いません。
