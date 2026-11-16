# Becoming — Coordinated Launch Readiness

Updated: 2026-11-15

## Release strategy
Prepare and test the website and mobile app privately, confirm funding and costs, then coordinate public launch. The current GitHub Pages URL is publicly reachable as a **tester preview**; it is not an access-restricted private deployment.

**One account, one membership across platforms.** Essential recovery tools remain free. Premium access, gifts and scholarships must be recognized across web and future apps. A mobile app must not charge a second membership simply because someone already paid on the web. Check platform billing requirements before implementing purchases.

## Membership decisions
- Free three-day full-access trial (new trials only; honor previously started seven-day trials). No card and no automatic charges by default.
- Optional paid conversion only with explicit consent, disclosed terms and advance reminder.
- Provisional price targets: $6.99 per month / $59.99 per year, pending cost review.
- Twelve-month scholarship codes: unique, single-use, no credit card, no automatic renewal.
- Gifts are distinct from scholarship awards.
- Expiration returns access to permanently free tools; private records and earned keepsakes stay preserved.
- Failed payment: planned three-day grace period, subject to processor/legal feasibility.

## Release work tracker

| Area | Current state | Required next verification or implementation |
| --- | --- | --- |
| Recovery website | Tester preview exists | Regression, accessibility, privacy and security audit |
| Private recovery-record storage | Working in tester | Two-account RLS/security check; backup/restore rehearsal |
| Membership SQL foundation | User reports successful Supabase installation | Verify row-level policies and registration trigger |
| Scholarship SQL foundation | User confirmed Supabase installation; practice-code first redemption succeeded | Confirm reusing the same code is blocked and verify admin redeemed count |
| Scholarship redemption screen | Committed; user visual check passed | End-to-end redemption test with a disposable account |
| Admin scholarship dashboard | Built in tester; user confirmed admin-only visibility | Audit authorization and test issuance/void end-to-end |
| Trial activation | One-time, server-authoritative SQL migration staged in repository; not installed or activated | Apply and security-test migration, then connect only after actual Premium features are available |
| Premium permissions | Not built | Apply feature rules without hiding free recovery support |
| Billing and cancellations | Not built | Payment provider, secure webhooks, receipts and self-service cancel |
| Mobile apps | Not built | App packaging, real-device testing, store requirements and review |
| Community and meetings | Planning-stage | Moderation, privacy, staffing, infrastructure and safety |
| Legal and operations | Not finalized | Terms, privacy, support processes and actual cost model |

## Important safeguards
Do not expose Supabase service-role credentials in browser code. Do not use client-only premium checks as production enforcement. Do not activate billing, start trials, remove free tools, or invite broad public use before testing and authorization. A successful SQL Editor run confirms execution, not secure runtime behavior.

## Immediate focus
1. End-to-end scholarship code redemption test with a disposable test account and funded test inventory that is not mistaken for a real funded award.
2. Audit and harden the existing admin-issued code workflow and the account-isolation rules.
3. Apply and test the staged one-time trial SQL only when ready; never start member trials before Premium access exists.
4. Build secure entitlement gating and subscriptions; payment integrations and mobile launch remain pending.

This file is a work tracker, not a claim that listed features are completed.
