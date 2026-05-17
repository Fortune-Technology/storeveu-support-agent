# Corresponding Source Offer (AGPL-3.0)

"Storeveu Support" is built from a modified version of
[RustDesk](https://github.com/rustdesk/rustdesk), which is licensed under the
**GNU Affero General Public License v3.0**.

In accordance with AGPL-3.0 §13 and §6, the **complete corresponding source
code** of this modified client — including the branding/configuration patch and
the exact upstream revision it is based on — is publicly available at:

> https://github.com/Fortune-Technology/storeveu-support-agent  *(PUBLIC)*

The build is pinned to upstream revision `RUSTDESK_REF` (recorded in the fork's
CI workflow), with the Storeveu branding/server-pin patch applied on top. No
proprietary RustDesk commercial license is used; this is the open-source path,
so this offer is a hard requirement, not optional.

This notice must be:
- Shipped inside the installer (a readable `LICENSE` + this offer),
- Linkable from the agent's About screen,
- Kept accurate whenever `RUSTDESK_REF` or the patch changes.

Upstream license: AGPL-3.0. Storeveu's patch inherits AGPL-3.0. Distributing the
signed binary without the source being available at the URL above is a license
violation — CI must fail the release if the fork source is not published.
