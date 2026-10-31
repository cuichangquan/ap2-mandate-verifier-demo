# Synthetic fixture provenance

The signed Strings and public-registration material in `fixtures/input_builder/` derive from the FULL entry extracted from
[AP2 Mandate Verifier INPUTS.json at f6d4f83](https://github.com/cuichangquan/ap2-mandate-verifier/blob/f6d4f83d396b75505256dba5769a54a8f065eeea/research/stage15/results/R3/INPUTS.json).

The source repository's [MIT license at that same commit](https://github.com/cuichangquan/ap2-mandate-verifier/blob/f6d4f83d396b75505256dba5769a54a8f065eeea/LICENSE)
is preserved in this repository's LICENSE, including:
Copyright (c) 2026 AP2 Mandate Verifier contributors.

Original INPUTS.json SHA256:
`41ad845a7ea82a9c7316c9ef11fb8ee5281453afafe2b4932c7217c1936562c1`.

The legacy full.json (removed when the business-input workflow became default) had SHA256:
`ac98f3b0c475365e2e7416cbb1838f1692a0ff2693c71dba0cb664c52b9ad42f`.

The fixtures contain public keys and synthetic signed data, not private signing keys. See fixtures/input_builder/NOTICE.md for the explicit business mapping.
Synthetic Issuer/Agent/Merchant/Host assertions do not establish real-world trust.
Screenshots show this demo's actual localhost UI with the same synthetic fixture.

Ruby, Rails, Puma, the verifier and other dependencies are acquired separately;
their packages and local execution records are not redistributed in this repository.
