# E2E Test Infra: Real-World Family Governance System (FHub)

## Test Philosophy
- **Requirement-Driven & Opaque-Box**: Tests derived strictly from `ORIGINAL_REQUEST.md` and `PLAN_REALWORLD_FAMILY_GOVERNANCE_SYSTEM.md`, not internal implementation details.
- **Methodology**: 4-Tier Test Matrix: Category-Partition (Tier 1) + Boundary Value Analysis (Tier 2) + Pairwise Combinations (Tier 3) + Real-World Workload Scenarios (Tier 4).
- **Execution Target**: Automated tests in `test/family_governance_test.dart` and `test/reminder_test.dart` executing via `flutter test`.

## Feature Inventory & Test Coverage
| # | Feature | Source (Requirement) | Tier 1 (Feature) | Tier 2 (Boundary) | Tier 3 (Pairwise) | Tier 4 (Scenario) |
|---|---------|---------------------|:----------------:|:-----------------:|:-----------------:|:-----------------:|
| 1 | Multi-Family Switcher (`familyIds`) | PLAN §4 C1, R3 | 5 | 5 | ✓ | ✓ |
| 2 | Unified Join Handshake (`join_requests`) | PLAN §4 C1, R3 | 5 | 5 | ✓ | ✓ |
| 3 | Guardian Join Approval & `isKid` Flagging | PLAN §4 C1, R3 | 5 | 5 | ✓ | ✓ |
| 4 | Role Escalation Lockdown | PLAN §4 C6, R3 | 5 | 5 | ✓ | ✓ |
| 5 | Tri-Modal Task Types (`ASSIGN`, `FAVOR`, `CARE`) | PLAN §4 C2, R3 | 5 | 5 | ✓ | ✓ |
| 6 | Top-Down Assignment Hierarchy | PLAN §2, §4 C2, R3 | 5 | 5 | ✓ | ✓ |
| 7 | Cross-Generation Favor Requests | PLAN §2, §4 C2, R3 | 5 | 5 | ✓ | ✓ |
| 8 | Favor Delegation Constraint (Max 1) | PLAN §3, §4 C2, R3 | 5 | 5 | ✓ | ✓ |
| 9 | Rejection Reset with Proof Image Wipe | PLAN §4 C2, R3 | 5 | 5 | ✓ | ✓ |
| 10 | Elderly Care Audio & Vietnamese TTS | PLAN §4 C2, R3 | 5 | 5 | ✓ | ✓ |
| 11 | Double-Approval Race Protection (`reward_${taskId}`) | PLAN §4 C3, R3 | 5 | 5 | ✓ | ✓ |
| 12 | Wishlist Double-Spending Protection | PLAN §4 C3, R3 | 5 | 5 | ✓ | ✓ |
| 13 | Accelerometer Shake Debounce (3.0s) | PLAN §4 C3, R3 | 5 | 5 | ✓ | ✓ |
| 14 | Cash Gift Two-Way Handshake | PLAN §2, §4 C3, R3 | 5 | 5 | ✓ | ✓ |
| 15 | 3-Tier Overdue Escalation (0h/+2h/+6h) | PLAN §4 C4, R3 | 5 | 5 | ✓ | ✓ |
| 16 | Voice Mic Time Extension Request | PLAN §4 C4, R3 | 5 | 5 | ✓ | ✓ |
| 17 | Care Quiet-Hours Immunity (22:00-06:00) | PLAN §4 C4, R3 | 5 | 5 | ✓ | ✓ |
| 18 | 15-Second Test Simulation Mode | PLAN §4 C4, R3 | 5 | 5 | ✓ | ✓ |
| 19 | Scoped AI Context & `family_memories` Recall | PLAN §4 C5, R3 | 5 | 5 | ✓ | ✓ |
| 20 | Draft Task Card User Confirmation Gate | PLAN §4 C5, R3 | 5 | 5 | ✓ | ✓ |
| 21 | Top-Level Cloud Firestore Rules | PLAN §4 C6, R3 | 5 | 5 | ✓ | ✓ |
| 22 | Immutable Star Ledger (`star_ledger`) | PLAN §4 C6, R3 | 5 | 5 | ✓ | ✓ |

## Test Architecture
- **Runner**: `flutter test test/family_governance_test.dart test/reminder_test.dart`
- **Output**: Pass with exit code 0, 0 failures, 0 exceptions.
- **Harness Structure**:
  - `test/family_governance_test.dart`: Dedicated standalone suite for governance, multi-family, star economy, transactions, sensor debounce, and AI scoping.
  - `test/reminder_test.dart`: Core reminder state machine, assignment hierarchy, rejection reset, quiet hours protection.

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | Grandparent approves join request, assigns chore to grandchild, rejects incomplete proof, grandchild retakes and grandparent approves earning stars | F2, F3, F5, F6, F9, F11 | High |
| 2 | Grandparent & Parent simultaneously approve same chore; idempotent transaction prevents duplicate stars | F11, F21, F22 | High |
| 3 | Minor child requests 2 expensive Wishlist rewards concurrently; balance drops to 0, second is rejected | F12, F21, F22 | High |
| 4 | Night-time (23:30) scheduled medication reminder rings immediately; regular chore alarm deferred to 07:00 | F5, F10, F17, F18 | High |
| 5 | AI recalls habit "Vinamilk" into Draft Card; user confirms; Guardian assigns; child requests voice extension at +2h | F15, F16, F19, F20 | High |
| 6 | Family jackpot shaken rapidly; debounce registers single shake; cash prize awarded via 2-way handshake | F13, F14 | Medium |

## Coverage Thresholds
- **Tier 1 (Feature Coverage)**: >=5 test cases per feature
- **Tier 2 (Boundary & Corner Cases)**: >=5 boundary tests per feature
- **Tier 3 (Cross-Feature Combinations)**: Major pairwise feature interactions
- **Tier 4 (Real-World Application Scenarios)**: >=6 realistic end-to-end multi-generation family scenarios
