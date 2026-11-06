# Project: Real-World Family Governance System (FHub)

## Architecture
- **Paradigm**: No-Backend Architecture (Pure Flutter 3.13+ + Google Cloud Firestore + Firebase Auth + Google Generative AI Gemini)
- **Data Model**: 8 Top-Level Firestore Collections (`users`, `families`, `family_members`, `join_requests`, `reminders`, `star_ledger`, `check_in_feeds`, `family_memories`). Deterministic composite docIds: `${familyId}_${userId}`.
- **Cultural Role Hierarchy**:
  - `GRANDPARENT` (Level 3 - Trưởng bối): Guardian authority, reviews join requests, assigns chores (`ASSIGN`), approves proofs, grants stars, receives `CARE`.
  - `PARENT` / `OWNER` (Level 2 - Quản lý điều phối): Guardian authority, reviews join requests, assigns chores, delegates favors down.
  - `CHILD` with `isKid == false` (Level 1 - Con lớn đi làm xa): Sends `FAVOR` requests, creates `CARE` schedules for elders.
  - `CHILD` with `isKid == true` (Level 1 - Trẻ nhỏ ở nhà): Completes `ASSIGN` chores, takes photo proofs, earns stars, redeems Wishlist gifts, shakes jackpot.
- **Transactions & Concurrency**: Atomic Firestore `runTransaction` with deterministic idempotent keys (`reward_${taskId}` for chore approvals, `claim_${claimId}` for Wishlist redemption) to eliminate race conditions and double-spending.
- **Peripherals & Accessibility**: Accelerometer (3s debounce, $g > 15.0$, $\Delta g > 4.5$), Camera (proof image submit/rejection reset), Microphone (speech-to-text time extension requests), Loudspeaker/TTS (Vietnamese TTS + `CARE_CHANNEL` audio ringtone), Vibration/Haptics (3-tier escalation alerts).

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Git Branch Setup & Remote Safety | Checkout `feature/realworld-family-governance-implementation`, block remote push | M1 | ORIGINAL_REQUEST R1 |
| 2 | Top-Level Cloud Firestore Rules | Security rules for 8 top-level collections, Guardian authorization, immutable `star_ledger` | M1 | PLAN §4 C6, ORIGINAL_REQUEST R3 |
| 3 | Enhanced User & Family Member Models | Add `familyIds` to users, `isKid`, `rewardStarsTotal`, `isGuardian` to family members | M1 | PLAN §4 C1, C6 |
| 4 | Fast Multi-Family Switcher | Read `familyIds` array from `users/{uid}` to instantly render multi-family switcher | M1 | PLAN §4 C1, ORIGINAL_REQUEST R3 |
| 5 | Unified Join Handshake (`join_requests`) | Create pending join requests in `join_requests/{familyId}_{userId}`, unified discovery flow | M1 | PLAN §4 C1, ORIGINAL_REQUEST R3 |
| 6 | Guardian Join Review & Role/isKid Assignment | Grandparent/Parent reviews join requests, sets `relationshipRole` and `isKid` flag | M1 | PLAN §4 C1, ORIGINAL_REQUEST R3 |
| 7 | Role Escalation Lockdown | Prevent child accounts from mutating `role` or `hierarchyRole` in `family_members` | M1 | PLAN §4 C1, C6 |
| 8 | Tri-Modal Task Types | Implement `TaskType` (`ASSIGN`, `FAVOR`, `CARE`) and `TaskStatus` state machines | M2 | PLAN §4 C2, ORIGINAL_REQUEST R3 |
| 9 | Top-Down Assignment Hierarchy | Guardians create `ASSIGN`; child cannot assign chores with stars/penalties to elders | M2 | PLAN §4 C2, ORIGINAL_REQUEST R3 |
| 10 | Cross-Generational Favor Requests | Child can request `FAVOR` to elders; elders can accept or politely decline | M2 | PLAN §4 C2, ORIGINAL_REQUEST R3 |
| 11 | Favor Delegation Constraint | Parents can delegate grandparent favor to child (count=1); child cannot delegate up; no CARE delegation | M2 | PLAN §3, §4 C2 |
| 12 | Rejection Reset with Proof Image Wipe | On submission rejection, clear `proofImageUrl = null` and reset status to `PENDING` | M2 | PLAN §4 C2, ORIGINAL_REQUEST R3 |
| 13 | Elderly Care Audio & Vietnamese TTS | `CARE_CHANNEL` high-priority audio ringtone on lock screen; Vietnamese TTS reading title | M2 | PLAN §4 C2, ORIGINAL_REQUEST R3 |
| 14 | Care Quiet-Hours Immunity | Medication and elderly care tasks are strictly exempt from quiet-hours postponement | M2 & M4 | PLAN §4 C2, C4 |
| 15 | Double-Approval Race Protection | Atomic transaction with idempotent key `reward_${taskId}` ensuring single reward | M3 | PLAN §4 C3, ORIGINAL_REQUEST R3 |
| 16 | Wishlist Double-Spending Protection | Atomic balance verification and immediate deduction with `claim_${claimId}` | M3 | PLAN §4 C3, ORIGINAL_REQUEST R3 |
| 17 | Real-World Gift Rejection Refund | Refund deducted stars if physical gift is rejected by Guardian | M3 | PLAN §4 C3 |
| 18 | Accelerometer Shake Debounce | Cooldown 3.0s, mutex lock `_isProcessingShake`, thresholds $g > 15.0$ and $\Delta g > 4.5$ | M3 | PLAN §4 C3, ORIGINAL_REQUEST R3 |
| 19 | Cash Gift Two-Way Handshake | Cash prize handshake: VietQR/Cash given by Guardian -> Child taps `[Đã nhận tiền]` | M3 | PLAN §4 C3, ORIGINAL_REQUEST R3 |
| 20 | 3-Tier Overdue Escalation Engine | 0h due chime, +2h overdue vibration alert, +6h Guardian red alert with actions | M4 | PLAN §4 C4, ORIGINAL_REQUEST R3 |
| 21 | Voice Mic Time Extension Request | At +2h, child taps mic to record spoken Vietnamese extension request | M4 | PLAN §4 C4, ORIGINAL_REQUEST R3 |
| 22 | Guardian Overdue Action Trio | At +6h, Guardian can Extend, Delegate, or Close without stars | M4 | PLAN §4 C4 |
| 23 | 15-Second Test Simulation Mode | Fast-forward 0h -> +2h -> +6h to 15 seconds (0s -> 7s -> 15s) for live evaluation | M4 | PLAN §4 C4, ORIGINAL_REQUEST R3 |
| 24 | Night-Time Quiet Hours Rules | 22:00-06:00 quiet hours auto-defer regular chores to 07:00, protecting CARE tasks | M4 | PLAN §4 C4, ORIGINAL_REQUEST R3 |
| 25 | Scoped Multi-Family AI Context | AI operates strictly within active `currentFamilyId` without cross-family data leakage | M4 | PLAN §4 C5 |
| 26 | AI Memory Recall from `family_memories` | AI recalls stored family habits (e.g. Vinamilk) into Draft Task Card | M4 | PLAN §4 C5, ORIGINAL_REQUEST R3 |
| 27 | Draft Task Card User Confirmation Gate | AI generates draft task card; user must click `[Xác nhận tạo việc]` before Firestore write | M4 | PLAN §4 C5, ORIGINAL_REQUEST R3 |
| 28 | Dynamic Vietnamese Salutations | AI dynamically addresses user by role/name, never generic fallback | M4 | PLAN §4 C5 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Foundation, Security & Multi-Family | Git branch `feature/realworld-family-governance-implementation`, `firestore.rules`, user/member models, `JoinRequestService`, multi-family switcher | none | DONE |
| M2 | Task Engine & Elderly Care UX | `TaskType` (`ASSIGN`, `FAVOR`, `CARE`), `TaskStatus`, hierarchy validation, rejection reset proof wipe, Vietnamese TTS & CARE channel | M1 | DONE |
| M3 | Star Economy, Double-Approval & Jackpot | `StarEconomyService` idempotent transaction `reward_${taskId}`, Wishlist double-spending prevention, 3s accelerometer debounce, 2-way cash gift handshake | M1, M2 | PLANNED |
| M4 | Escalation & AI Memory Scoping | 3-tier escalation (0h/+2h/+6h), quiet hours with CARE exemption, 15s simulation, voice mic, AI `family_memories` recall into Draft Card with confirmation gate | M2 | PLANNED |
| M5 | Final Milestone: 100% E2E Test & Hardening | Phase 1: 100% pass E2E tests in `family_governance_test.dart` and `reminder_test.dart`<br>Phase 2: Tier 5 Adversarial coverage hardening | M1, M2, M3, M4, E2E | PLANNED |
| E2E | E2E Testing Track | Requirement-driven test suite (Tiers 1-4) covering all 28 features in `test/family_governance_test.dart` & `test/reminder_test.dart`, publish `TEST_READY.md` | M1 | DONE |

## Interface Contracts
### `JoinRequestService` (`lib/Long/services/join_request_service.dart`)
- `Future<void> sendJoinRequest({required String familyId, required String suggestedRole})`
- `Stream<List<JoinRequestModel>> watchPendingRequests(String familyId)`
- `Future<void> approveJoinRequest({required String requestId, required String assignedRole, required bool isKid})`
- `Future<void> rejectJoinRequest(String requestId)`

### `StarEconomyService` (`lib/Vinh/services/star_economy_service.dart`)
- `Future<void> approveTaskWithDoubleAwardProtection({required String taskId, required String reviewerId, required String reviewerName})`
- `Future<void> claimWishlistItem({required String claimId, required String familyId, required String userId, required int cost, required String itemName})`
- `Future<void> refundWishlistClaim({required String claimId, required String familyId, required String userId, required int refundStars})`

### `ReminderRepository` / `TaskEngine` (`lib/Vinh/services/`)
- `Future<void> submitTaskWithProof({required String taskId, required String proofImageUrl})`
- `Future<void> rejectTaskSubmission({required String taskId, required String reason})`
- `Future<ReminderModel> createReminder(ReminderModel reminder)` -> validates creator hierarchy vs target hierarchy

## Code Layout
- `firestore.rules`: Project root security rules
- `lib/Long/models/user_model.dart`, `lib/Khoa/models/user_profile.dart`: User profiles with `familyIds`
- `lib/Long/models/family_member_model.dart`, `lib/Khoa/models/family_member.dart`: Family members with `isKid`, `rewardStarsTotal`
- `lib/Long/services/join_request_service.dart`: Join request handshake service
- `lib/Long/services/family_data_service.dart`, `lib/Khoa/services/family_service.dart`: Multi-family caching & switcher
- `lib/Vinh/models/reminder_model.dart`: Task types, statuses, and audit fields
- `lib/Vinh/services/star_economy_service.dart`: Idempotent star ledger transactions
- `lib/Vinh/services/multi_tier_escalation_service.dart`: 3-tier escalation, quiet hours, 15s simulation
- `lib/Danh/services/family_jackpot_service.dart`: Accelerometer 3s debounce, 2-way cash gift handshake
- `lib/Ai/services/gemini_chat_service.dart`: Draft task card with `family_memories` recall
- `test/family_governance_test.dart`: Isolated governance test suite
- `test/reminder_test.dart`: Extended reminder and state machine test suite
