(define-constant contract-owner tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-INVALID-BENEFICIARY (err u101))
(define-constant ERR-ALREADY-REGISTERED (err u102))
(define-constant ERR-NOT-REGISTERED (err u103))
(define-constant ERR-INSUFFICIENT-SIGNATURES (err u104))
(define-constant ERR-INVALID-TIME-LOCK (err u105))
(define-constant ERR-UNAUTHORIZED (err u106))
(define-constant ERR-ALREADY-CLAIMED (err u107))
(define-constant ERR-ZERO-AMOUNT (err u108))
(define-constant ERR-TRANSFER-FAILED (err u109))
(define-constant ERR-CONTRACT-PAUSED (err u110))

(define-data-var minimum-signatures uint u2)
(define-data-var cooling-period uint u144)
(define-data-var contract-active bool true)

(define-map estates
    principal
    {
        heir: principal,
        stx-amount: uint,
        unlock-height: uint,
        required-signs: uint,
        is-claimed: bool,
    }
)

(define-map authorized-validators
    principal
    bool
)

(define-map validation-signatures
    { estate-owner: principal }
    uint
)

(define-private (is-owner)
    (is-eq tx-sender contract-owner)
)

(define-private (is-validator)
    (default-to false (map-get? authorized-validators tx-sender))
)

(define-private (check-time-lock (estate-owner principal))
    (match (map-get? estates estate-owner)
        estate (>= stacks-block-height (get unlock-height estate))
        false
    )
)

(define-private (is-contract-active)
    (var-get contract-active)
)

(define-private (is-emergency-contact
        (estate-owner principal)
        (contact principal)
    )
    (match (map-get? emergency-contacts {
        estate-owner: estate-owner,
        contact: contact,
    })
        contact-data (get is-active contact-data)
        false
    )
)

(define-private (update-owner-activity (owner principal))
    (map-set owner-activity owner stacks-block-height)
)

(define-public (register-estate
        (heir principal)
        (amount uint)
    )
    (begin
        (asserts! (> amount u0) ERR-ZERO-AMOUNT)
        (asserts! (is-none (map-get? estates tx-sender)) ERR-ALREADY-REGISTERED)
        (map-set estates tx-sender {
            heir: heir,
            stx-amount: amount,
            unlock-height: (+ stacks-block-height (var-get cooling-period)),
            required-signs: (var-get minimum-signatures),
            is-claimed: false,
        })
        (update-owner-activity tx-sender)
        (ok true)
    )
)

(define-public (add-validator (validator principal))
    (begin
        (asserts! (is-owner) ERR-OWNER-ONLY)
        (map-set authorized-validators validator true)
        (ok true)
    )
)

(define-public (remove-validator (validator principal))
    (begin
        (asserts! (is-owner) ERR-OWNER-ONLY)
        (map-delete authorized-validators validator)
        (ok true)
    )
)

(define-public (validate-estate (estate-owner principal))
    (begin
        (asserts! (is-validator) ERR-UNAUTHORIZED)
        (asserts! (is-some (map-get? estates estate-owner)) ERR-NOT-REGISTERED)
        (map-set validation-signatures { estate-owner: estate-owner }
            (+
                (default-to u0
                    (map-get? validation-signatures { estate-owner: estate-owner })
                )
                u1
            ))
        (ok true)
    )
)

(define-public (claim-estate (estate-owner principal))
    (let (
            (estate (unwrap! (map-get? estates estate-owner) ERR-NOT-REGISTERED))
            (signatures (default-to u0
                (map-get? validation-signatures { estate-owner: estate-owner })
            ))
        )
        (asserts! (is-eq tx-sender (get heir estate)) ERR-UNAUTHORIZED)
        (asserts! (not (get is-claimed estate)) ERR-ALREADY-CLAIMED)
        (asserts! (check-time-lock estate-owner) ERR-INVALID-TIME-LOCK)
        (asserts! (>= signatures (get required-signs estate))
            ERR-INSUFFICIENT-SIGNATURES
        )
        (map-set estates estate-owner (merge estate { is-claimed: true }))
        (match (stx-transfer? (get stx-amount estate) estate-owner (get heir estate))
            success (ok true)
            error
            ERR-TRANSFER-FAILED
        )
    )
)

(define-read-only (get-estate-info (address principal))
    (map-get? estates address)
)

(define-read-only (get-validator-status (address principal))
    (map-get? authorized-validators address)
)

(define-read-only (get-signature-count (estate-owner principal))
    (ok (default-to u0
        (map-get? validation-signatures { estate-owner: estate-owner })
    ))
)
;;

(define-read-only (can-claim-estate (estate-owner principal))
    (match (map-get? estates estate-owner)
        estate (and
            (check-time-lock estate-owner)
            (>=
                (default-to u0
                    (map-get? validation-signatures { estate-owner: estate-owner })
                )
                (get required-signs estate)
            )
            (not (get is-claimed estate))
        )
        false
    )
)
(define-constant ERR-NOT-OWNER (err u200))
(define-constant ERR-RECOVERY-PERIOD-ACTIVE (err u201))
(define-constant ERR-NO-RECOVERY-NEEDED (err u202))

(define-data-var recovery-period uint u1008)

(define-map recovery-requests
    principal
    {
        requested-at: uint,
        approved: bool,
    }
)

(define-public (request-recovery)
    (let ((estate (unwrap! (map-get? estates tx-sender) ERR-NOT-REGISTERED)))
        (asserts! (not (get is-claimed estate)) ERR-ALREADY-CLAIMED)
        (map-set recovery-requests tx-sender {
            requested-at: stacks-block-height,
            approved: false,
        })
        (ok true)
    )
)

(define-public (execute-recovery)
    (let (
            (estate (unwrap! (map-get? estates tx-sender) ERR-NOT-REGISTERED))
            (recovery (unwrap! (map-get? recovery-requests tx-sender)
                ERR-NO-RECOVERY-NEEDED
            ))
        )
        (asserts! (not (get is-claimed estate)) ERR-ALREADY-CLAIMED)
        (asserts!
            (>= stacks-block-height
                (+ (get requested-at recovery) (var-get recovery-period))
            )
            ERR-RECOVERY-PERIOD-ACTIVE
        )
        (map-delete estates tx-sender)
        (map-delete recovery-requests tx-sender)
        (map-delete validation-signatures { estate-owner: tx-sender })
        (stx-transfer? (get stx-amount estate) tx-sender tx-sender)
    )
)

(define-read-only (get-recovery-status (address principal))
    (map-get? recovery-requests address)
)

(define-read-only (can-execute-recovery (address principal))
    (match (map-get? recovery-requests address)
        recovery (>= stacks-block-height
            (+ (get requested-at recovery) (var-get recovery-period))
        )
        false
    )
)
(define-constant ERR-INVALID-PERCENTAGE (err u300))
(define-constant ERR-PERCENTAGE-OVERFLOW (err u301))
(define-constant ERR-MAX-BENEFICIARIES (err u302))
(define-constant ERR-BENEFICIARY-EXISTS (err u303))

(define-data-var max-beneficiaries uint u10)

(define-map partial-estates
    principal
    {
        total-amount: uint,
        unlock-height: uint,
        required-signs: uint,
        is-active: bool,
    }
)

(define-map beneficiaries
    {
        estate-owner: principal,
        beneficiary: principal,
    }
    {
        percentage: uint,
        claimed: bool,
        amount: uint,
    }
)

(define-map estate-beneficiary-count
    principal
    uint
)

(define-public (create-partial-estate
        (total-amount uint)
        (lock-period uint)
    )
    (begin
        (asserts! (> total-amount u0) ERR-ZERO-AMOUNT)
        (asserts! (is-none (map-get? partial-estates tx-sender))
            ERR-ALREADY-REGISTERED
        )
        (map-set partial-estates tx-sender {
            total-amount: total-amount,
            unlock-height: (+ stacks-block-height lock-period),
            required-signs: (var-get minimum-signatures),
            is-active: true,
        })
        (map-set estate-beneficiary-count tx-sender u0)
        (ok true)
    )
)

(define-public (add-beneficiary
        (beneficiary principal)
        (percentage uint)
    )
    (let (
            (current-count (default-to u0 (map-get? estate-beneficiary-count tx-sender)))
            (estate (unwrap! (map-get? partial-estates tx-sender) ERR-NOT-REGISTERED))
        )
        (asserts! (< current-count (var-get max-beneficiaries))
            ERR-MAX-BENEFICIARIES
        )
        (asserts! (and (> percentage u0) (<= percentage u100))
            ERR-INVALID-PERCENTAGE
        )
        (asserts!
            (is-none (map-get? beneficiaries {
                estate-owner: tx-sender,
                beneficiary: beneficiary,
            }))
            ERR-BENEFICIARY-EXISTS
        )
        (let ((amount (/ (* (get total-amount estate) percentage) u100)))
            (map-set beneficiaries {
                estate-owner: tx-sender,
                beneficiary: beneficiary,
            } {
                percentage: percentage,
                claimed: false,
                amount: amount,
            })
            (map-set estate-beneficiary-count tx-sender (+ current-count u1))
            (ok true)
        )
    )
)

(define-public (claim-partial-inheritance (estate-owner principal))
    (let (
            (estate (unwrap! (map-get? partial-estates estate-owner) ERR-NOT-REGISTERED))
            (beneficiary-data (unwrap!
                (map-get? beneficiaries {
                    estate-owner: estate-owner,
                    beneficiary: tx-sender,
                })
                ERR-UNAUTHORIZED
            ))
            (signatures (default-to u0
                (map-get? validation-signatures { estate-owner: estate-owner })
            ))
        )
        (asserts! (get is-active estate) ERR-ALREADY-CLAIMED)
        (asserts! (not (get claimed beneficiary-data)) ERR-ALREADY-CLAIMED)
        (asserts! (>= stacks-block-height (get unlock-height estate))
            ERR-INVALID-TIME-LOCK
        )
        (asserts! (>= signatures (get required-signs estate))
            ERR-INSUFFICIENT-SIGNATURES
        )
        (map-set beneficiaries {
            estate-owner: estate-owner,
            beneficiary: tx-sender,
        }
            (merge beneficiary-data { claimed: true })
        )
        (match (stx-transfer? (get amount beneficiary-data) estate-owner tx-sender)
            success (ok true)
            error
            ERR-TRANSFER-FAILED
        )
    )
)

(define-read-only (get-partial-estate-info (address principal))
    (map-get? partial-estates address)
)

(define-read-only (get-beneficiary-info
        (estate-owner principal)
        (beneficiary principal)
    )
    (map-get? beneficiaries {
        estate-owner: estate-owner,
        beneficiary: beneficiary,
    })
)

(define-read-only (get-beneficiary-count (estate-owner principal))
    (default-to u0 (map-get? estate-beneficiary-count estate-owner))
)

(define-constant ERR-CANNOT-UPDATE-CLAIMED (err u500))
(define-constant ERR-UPDATE-COOLDOWN-ACTIVE (err u501))
(define-constant ERR-NO-CHANGES-DETECTED (err u502))
(define-constant ERR-EMERGENCY-CONTACT-EXISTS (err u600))
(define-constant ERR-NOT-EMERGENCY-CONTACT (err u601))
(define-constant ERR-EMERGENCY-COOLDOWN-ACTIVE (err u602))
(define-constant ERR-NO-EMERGENCY-DECLARED (err u603))
(define-constant ERR-EMERGENCY-ALREADY-ACTIVE (err u604))
(define-constant ERR-DELEGATION-EXISTS (err u700))
(define-constant ERR-NOT-DELEGATED (err u701))
(define-constant ERR-INVALID-DELEGATION-PERIOD (err u702))
(define-constant ERR-DELEGATION-EXPIRED (err u703))
(define-constant ERR-CANNOT-DELEGATE-TO-SELF (err u704))

(define-data-var update-cooldown uint u144)
(define-data-var emergency-response-period uint u288)
(define-data-var inactivity-threshold uint u2016)
(define-data-var max-delegation-period uint u4032)

(define-map last-update-height
    principal
    uint
)

(define-map emergency-contacts
    {
        estate-owner: principal,
        contact: principal,
    }
    {
        relationship: (string-ascii 50),
        added-at: uint,
        is-active: bool,
    }
)

(define-map emergency-alerts
    principal
    {
        declared-at: uint,
        declared-by: principal,
        reason: (string-ascii 100),
        is-active: bool,
        response-deadline: uint,
    }
)

(define-map owner-activity
    principal
    uint
)

(define-map estate-delegations
    {
        estate-owner: principal,
        delegate: principal,
    }
    {
        granted-at: uint,
        expires-at: uint,
        permissions: uint,
        is-active: bool,
    }
)

(define-private (can-update-estate (estate-owner principal))
    (let ((last-update (default-to u0 (map-get? last-update-height estate-owner))))
        (>= stacks-block-height (+ last-update (var-get update-cooldown)))
    )
)

(define-private (is-delegate
        (estate-owner principal)
        (delegate principal)
    )
    (match (map-get? estate-delegations {
        estate-owner: estate-owner,
        delegate: delegate,
    })
        delegation (and
            (get is-active delegation)
            (>= (get expires-at delegation) stacks-block-height)
        )
        false
    )
)

(define-private (has-delegation-permission
        (estate-owner principal)
        (permission uint)
    )
    (or
        (is-eq tx-sender estate-owner)
        (match (map-get? estate-delegations {
            estate-owner: estate-owner,
            delegate: tx-sender,
        })
            delegation (and
                (get is-active delegation)
                (>= (get expires-at delegation) stacks-block-height)
                (> (bit-and (get permissions delegation) permission) u0)
            )
            false
        )
    )
)

(define-public (delegate-estate-management
        (delegate principal)
        (permissions uint)
        (duration-blocks uint)
    )
    (begin
        (asserts! (is-some (map-get? estates tx-sender)) ERR-NOT-REGISTERED)
        (asserts! (not (is-eq tx-sender delegate)) ERR-CANNOT-DELEGATE-TO-SELF)
        (asserts!
            (and (> duration-blocks u0) (<= duration-blocks (var-get max-delegation-period)))
            ERR-INVALID-DELEGATION-PERIOD
        )
        (asserts!
            (is-none (map-get? estate-delegations {
                estate-owner: tx-sender,
                delegate: delegate,
            }))
            ERR-DELEGATION-EXISTS
        )
        (map-set estate-delegations {
            estate-owner: tx-sender,
            delegate: delegate,
        } {
            granted-at: stacks-block-height,
            expires-at: (+ stacks-block-height duration-blocks),
            permissions: permissions,
            is-active: true,
        })
        (ok true)
    )
)

(define-public (revoke-delegation (delegate principal))
    (begin
        (asserts!
            (is-some (map-get? estate-delegations {
                estate-owner: tx-sender,
                delegate: delegate,
            }))
            ERR-NOT-DELEGATED
        )
        (map-delete estate-delegations {
            estate-owner: tx-sender,
            delegate: delegate,
        })
        (ok true)
    )
)

(define-public (delegate-update-heir
        (estate-owner principal)
        (new-heir principal)
    )
    (let ((estate (unwrap! (map-get? estates estate-owner) ERR-NOT-REGISTERED)))
        (asserts! (is-contract-active) ERR-CONTRACT-PAUSED)
        (asserts! (not (get is-claimed estate)) ERR-CANNOT-UPDATE-CLAIMED)
        (asserts! (can-update-estate estate-owner) ERR-UPDATE-COOLDOWN-ACTIVE)
        (asserts! (has-delegation-permission estate-owner u1) ERR-UNAUTHORIZED)
        (asserts! (not (is-eq (get heir estate) new-heir))
            ERR-NO-CHANGES-DETECTED
        )
        (map-set estates estate-owner (merge estate { heir: new-heir }))
        (map-set last-update-height estate-owner stacks-block-height)
        (ok true)
    )
)

(define-public (update-estate-heir (new-heir principal))
    (let ((estate (unwrap! (map-get? estates tx-sender) ERR-NOT-REGISTERED)))
        (asserts! (is-contract-active) ERR-CONTRACT-PAUSED)
        (asserts! (not (get is-claimed estate)) ERR-CANNOT-UPDATE-CLAIMED)
        (asserts! (can-update-estate tx-sender) ERR-UPDATE-COOLDOWN-ACTIVE)
        (asserts! (not (is-eq (get heir estate) new-heir))
            ERR-NO-CHANGES-DETECTED
        )
        (map-set estates tx-sender (merge estate { heir: new-heir }))
        (map-set last-update-height tx-sender stacks-block-height)
        (ok true)
    )
)

(define-public (update-estate-amount (new-amount uint))
    (let ((estate (unwrap! (map-get? estates tx-sender) ERR-NOT-REGISTERED)))
        (asserts! (is-contract-active) ERR-CONTRACT-PAUSED)
        (asserts! (> new-amount u0) ERR-ZERO-AMOUNT)
        (asserts! (not (get is-claimed estate)) ERR-CANNOT-UPDATE-CLAIMED)
        (asserts! (can-update-estate tx-sender) ERR-UPDATE-COOLDOWN-ACTIVE)
        (asserts! (not (is-eq (get stx-amount estate) new-amount))
            ERR-NO-CHANGES-DETECTED
        )
        (map-set estates tx-sender (merge estate { stx-amount: new-amount }))
        (map-set last-update-height tx-sender stacks-block-height)
        (ok true)
    )
)

(define-public (extend-estate-lock (additional-blocks uint))
    (let ((estate (unwrap! (map-get? estates tx-sender) ERR-NOT-REGISTERED)))
        (asserts! (is-contract-active) ERR-CONTRACT-PAUSED)
        (asserts! (> additional-blocks u0) ERR-ZERO-AMOUNT)
        (asserts! (not (get is-claimed estate)) ERR-CANNOT-UPDATE-CLAIMED)
        (asserts! (can-update-estate tx-sender) ERR-UPDATE-COOLDOWN-ACTIVE)
        (map-set estates tx-sender
            (merge estate { unlock-height: (+ (get unlock-height estate) additional-blocks) })
        )
        (map-set last-update-height tx-sender stacks-block-height)
        (ok true)
    )
)

(define-public (update-required-signatures (new-signature-count uint))
    (let ((estate (unwrap! (map-get? estates tx-sender) ERR-NOT-REGISTERED)))
        (asserts! (is-contract-active) ERR-CONTRACT-PAUSED)
        (asserts! (> new-signature-count u0) ERR-ZERO-AMOUNT)
        (asserts! (not (get is-claimed estate)) ERR-CANNOT-UPDATE-CLAIMED)
        (asserts! (can-update-estate tx-sender) ERR-UPDATE-COOLDOWN-ACTIVE)
        (asserts! (not (is-eq (get required-signs estate) new-signature-count))
            ERR-NO-CHANGES-DETECTED
        )
        (map-set estates tx-sender
            (merge estate { required-signs: new-signature-count })
        )
        (map-set last-update-height tx-sender stacks-block-height)
        (ok true)
    )
)

(define-read-only (get-last-update-height (estate-owner principal))
    (map-get? last-update-height estate-owner)
)

(define-read-only (can-update-now (estate-owner principal))
    (can-update-estate estate-owner)
)

(define-read-only (blocks-until-next-update (estate-owner principal))
    (let (
            (last-update (default-to u0 (map-get? last-update-height estate-owner)))
            (required-height (+ last-update (var-get update-cooldown)))
        )
        (if (>= stacks-block-height required-height)
            u0
            (- required-height stacks-block-height)
        )
    )
)

(define-public (add-emergency-contact
        (contact principal)
        (relationship (string-ascii 50))
    )
    (begin
        (asserts! (is-some (map-get? estates tx-sender)) ERR-NOT-REGISTERED)
        (asserts!
            (is-none (map-get? emergency-contacts {
                estate-owner: tx-sender,
                contact: contact,
            }))
            ERR-EMERGENCY-CONTACT-EXISTS
        )
        (map-set emergency-contacts {
            estate-owner: tx-sender,
            contact: contact,
        } {
            relationship: relationship,
            added-at: stacks-block-height,
            is-active: true,
        })
        (update-owner-activity tx-sender)
        (ok true)
    )
)

(define-public (remove-emergency-contact (contact principal))
    (begin
        (asserts! (is-emergency-contact tx-sender contact)
            ERR-NOT-EMERGENCY-CONTACT
        )
        (map-delete emergency-contacts {
            estate-owner: tx-sender,
            contact: contact,
        })
        (update-owner-activity tx-sender)
        (ok true)
    )
)

(define-public (declare-emergency
        (estate-owner principal)
        (reason (string-ascii 100))
    )
    (begin
        (asserts! (is-emergency-contact estate-owner tx-sender)
            ERR-NOT-EMERGENCY-CONTACT
        )
        (asserts! (is-some (map-get? estates estate-owner)) ERR-NOT-REGISTERED)
        (asserts! (is-none (map-get? emergency-alerts estate-owner))
            ERR-EMERGENCY-ALREADY-ACTIVE
        )
        (map-set emergency-alerts estate-owner {
            declared-at: stacks-block-height,
            declared-by: tx-sender,
            reason: reason,
            is-active: true,
            response-deadline: (+ stacks-block-height (var-get emergency-response-period)),
        })
        (ok true)
    )
)

(define-public (respond-to-emergency)
    (let ((alert (unwrap! (map-get? emergency-alerts tx-sender) ERR-NO-EMERGENCY-DECLARED)))
        (asserts! (get is-active alert) ERR-NO-EMERGENCY-DECLARED)
        (asserts! (< stacks-block-height (get response-deadline alert))
            ERR-EMERGENCY-COOLDOWN-ACTIVE
        )
        (map-delete emergency-alerts tx-sender)
        (update-owner-activity tx-sender)
        (ok true)
    )
)

(define-public (execute-emergency-inheritance (estate-owner principal))
    (let (
            (estate (unwrap! (map-get? estates estate-owner) ERR-NOT-REGISTERED))
            (alert (unwrap! (map-get? emergency-alerts estate-owner)
                ERR-NO-EMERGENCY-DECLARED
            ))
        )
        (asserts! (is-emergency-contact estate-owner tx-sender)
            ERR-NOT-EMERGENCY-CONTACT
        )
        (asserts! (get is-active alert) ERR-NO-EMERGENCY-DECLARED)
        (asserts! (>= stacks-block-height (get response-deadline alert))
            ERR-EMERGENCY-COOLDOWN-ACTIVE
        )
        (asserts! (not (get is-claimed estate)) ERR-ALREADY-CLAIMED)
        (map-set estates estate-owner (merge estate { is-claimed: true }))
        (map-delete emergency-alerts estate-owner)
        (match (stx-transfer? (get stx-amount estate) estate-owner (get heir estate))
            success (ok true)
            error
            ERR-TRANSFER-FAILED
        )
    )
)

(define-read-only (get-emergency-contact-info
        (estate-owner principal)
        (contact principal)
    )
    (map-get? emergency-contacts {
        estate-owner: estate-owner,
        contact: contact,
    })
)

(define-read-only (get-emergency-alert-info (estate-owner principal))
    (map-get? emergency-alerts estate-owner)
)

(define-read-only (get-owner-activity (owner principal))
    (map-get? owner-activity owner)
)

(define-read-only (is-owner-inactive (owner principal))
    (let ((last-activity (default-to u0 (map-get? owner-activity owner))))
        (>= (- stacks-block-height last-activity) (var-get inactivity-threshold))
    )
)

(define-read-only (can-execute-emergency (estate-owner principal))
    (match (map-get? emergency-alerts estate-owner)
        alert (and
            (get is-active alert)
            (>= stacks-block-height (get response-deadline alert))
        )
        false
    )
)

(define-read-only (get-delegation-info
        (estate-owner principal)
        (delegate principal)
    )
    (map-get? estate-delegations {
        estate-owner: estate-owner,
        delegate: delegate,
    })
)

(define-read-only (is-delegation-active
        (estate-owner principal)
        (delegate principal)
    )
    (is-delegate estate-owner delegate)
)

(define-read-only (get-delegation-expiry
        (estate-owner principal)
        (delegate principal)
    )
    (match (map-get? estate-delegations {
        estate-owner: estate-owner,
        delegate: delegate,
    })
        delegation (some (get expires-at delegation))
        none
    )
)

;; =============================================================================
;; ESTATE AUDIT TRAIL FEATURE
;; =============================================================================

;; Error constants for audit trail
(define-constant ERR-AUDIT-LIMIT-EXCEEDED (err u800))
(define-constant ERR-INVALID-ACTION-TYPE (err u801))
(define-constant ERR-AUDIT-DISABLED (err u802))

;; Data variables for audit configuration
(define-data-var audit-enabled bool true)
(define-data-var max-audit-entries uint u100)
(define-data-var audit-retention-blocks uint u52560) ;; ~1 year at 10min blocks

;; Action type constants for audit trail
(define-constant ACTION-ESTATE-REGISTERED u1)
(define-constant ACTION-ESTATE-CLAIMED u2)
(define-constant ACTION-HEIR-UPDATED u3)
(define-constant ACTION-AMOUNT-UPDATED u4)
(define-constant ACTION-VALIDATOR-ADDED u5)
(define-constant ACTION-EMERGENCY-DECLARED u6)
(define-constant ACTION-RECOVERY-REQUESTED u7)
(define-constant ACTION-DELEGATION-GRANTED u8)

;; Audit trail entry structure
(define-map audit-trail
    {
        estate-owner: principal,
        entry-id: uint
    }
    {
        action-type: uint,
        actor: principal,
        block-height: uint,
        details: (string-ascii 200),
        stx-amount: (optional uint),
        related-principal: (optional principal)
    }
)

;; Track entry count per estate
(define-map audit-entry-count
    principal
    uint
)

;; Track global audit statistics
(define-map audit-stats
    uint ;; action-type
    uint ;; count
)

;; Private function to log audit entry
(define-private (log-audit-entry
        (estate-owner principal)
        (action-type uint)
        (details (string-ascii 200))
        (stx-amount (optional uint))
        (related-principal (optional principal))
    )
    (if (var-get audit-enabled)
        (let (
                (current-count (default-to u0 (map-get? audit-entry-count estate-owner)))
                (next-entry-id (+ current-count u1))
            )
            (if (< current-count (var-get max-audit-entries))
                (begin
                    ;; Add audit entry
                    (map-set audit-trail {
                        estate-owner: estate-owner,
                        entry-id: next-entry-id
                    } {
                        action-type: action-type,
                        actor: tx-sender,
                        block-height: stacks-block-height,
                        details: details,
                        stx-amount: stx-amount,
                        related-principal: related-principal
                    })
                    ;; Update entry count
                    (map-set audit-entry-count estate-owner next-entry-id)
                    ;; Update global stats
                    (map-set audit-stats action-type
                        (+ (default-to u0 (map-get? audit-stats action-type)) u1)
                    )
                    (ok true)
                )
                ERR-AUDIT-LIMIT-EXCEEDED
            )
        )
        ERR-AUDIT-DISABLED
    )
)

;; Enhanced estate registration with audit logging
(define-public (register-estate-with-audit
        (heir principal)
        (amount uint)
        (memo (string-ascii 200))
    )
    (begin
        (asserts! (> amount u0) ERR-ZERO-AMOUNT)
        (asserts! (is-none (map-get? estates tx-sender)) ERR-ALREADY-REGISTERED)
        (map-set estates tx-sender {
            heir: heir,
            stx-amount: amount,
            unlock-height: (+ stacks-block-height (var-get cooling-period)),
            required-signs: (var-get minimum-signatures),
            is-claimed: false,
        })
        (update-owner-activity tx-sender)
        ;; Log audit entry
        (try! (log-audit-entry
            tx-sender
            ACTION-ESTATE-REGISTERED
            memo
            (some amount)
            (some heir)
        ))
        (ok true)
    )
)

;; Enhanced claim estate with audit logging
(define-public (claim-estate-with-audit
        (estate-owner principal)
        (memo (string-ascii 200))
    )
    (let (
            (estate (unwrap! (map-get? estates estate-owner) ERR-NOT-REGISTERED))
            (signatures (default-to u0
                (map-get? validation-signatures { estate-owner: estate-owner })
            ))
        )
        (asserts! (is-eq tx-sender (get heir estate)) ERR-UNAUTHORIZED)
        (asserts! (not (get is-claimed estate)) ERR-ALREADY-CLAIMED)
        (asserts! (check-time-lock estate-owner) ERR-INVALID-TIME-LOCK)
        (asserts! (>= signatures (get required-signs estate))
            ERR-INSUFFICIENT-SIGNATURES
        )
        (map-set estates estate-owner (merge estate { is-claimed: true }))
        ;; Log audit entry before transfer
        (try! (log-audit-entry
            estate-owner
            ACTION-ESTATE-CLAIMED
            memo
            (some (get stx-amount estate))
            (some (get heir estate))
        ))
        (match (stx-transfer? (get stx-amount estate) estate-owner (get heir estate))
            success (ok true)
            error
            ERR-TRANSFER-FAILED
        )
    )
)

;; Public function to enable/disable audit trail (owner only)
(define-public (set-audit-status (enabled bool))
    (begin
        (asserts! (is-owner) ERR-OWNER-ONLY)
        (var-set audit-enabled enabled)
        (ok true)
    )
)

;; Public function to update audit configuration (owner only)
(define-public (update-audit-config
        (max-entries uint)
        (retention-blocks uint)
    )
    (begin
        (asserts! (is-owner) ERR-OWNER-ONLY)
        (asserts! (> max-entries u0) ERR-ZERO-AMOUNT)
        (asserts! (> retention-blocks u0) ERR-ZERO-AMOUNT)
        (var-set max-audit-entries max-entries)
        (var-set audit-retention-blocks retention-blocks)
        (ok true)
    )
)

;; Public function to clean a specific audit entry (simplified)
(define-public (cleanup-audit-entry (estate-owner principal) (entry-id uint))
    (let (
            (retention-threshold (- stacks-block-height (var-get audit-retention-blocks)))
        )
        (match (map-get? audit-trail { estate-owner: estate-owner, entry-id: entry-id })
            entry
            (if (< (get block-height entry) retention-threshold)
                (begin
                    (map-delete audit-trail { estate-owner: estate-owner, entry-id: entry-id })
                    (ok true)
                )
                (ok false) ;; Entry is not old enough
            )
            (ok false) ;; Entry does not exist
        )
    )
)

;; Read-only functions for audit trail
(define-read-only (get-audit-entry
        (estate-owner principal)
        (entry-id uint)
    )
    (map-get? audit-trail {
        estate-owner: estate-owner,
        entry-id: entry-id
    })
)

(define-read-only (get-estate-audit-count (estate-owner principal))
    (default-to u0 (map-get? audit-entry-count estate-owner))
)

(define-read-only (get-audit-stats-for-action (action-type uint))
    (default-to u0 (map-get? audit-stats action-type))
)

(define-read-only (is-audit-enabled)
    (var-get audit-enabled)
)

(define-read-only (get-audit-config)
    (ok {
        enabled: (var-get audit-enabled),
        max-entries: (var-get max-audit-entries),
        retention-blocks: (var-get audit-retention-blocks)
    })
)

;; Get basic audit trail summary for an estate
(define-read-only (get-audit-trail-summary (estate-owner principal))
    (let (
            (total-entries (get-estate-audit-count estate-owner))
            (max-entry-id total-entries)
        )
        (ok {
            total-entries: total-entries,
            has-entries: (> total-entries u0),
            last-entry-id: max-entry-id,
            last-activity: (if (> max-entry-id u0)
                (match (map-get? audit-trail { estate-owner: estate-owner, entry-id: max-entry-id })
                    entry (some (get block-height entry))
                    none
                )
                none
            )
        })
    )
)

;; Check if a specific audit entry matches an action type
(define-read-only (check-audit-entry-type
        (estate-owner principal)
        (entry-id uint)
        (action-type uint)
    )
    (match (map-get? audit-trail { estate-owner: estate-owner, entry-id: entry-id })
        entry (is-eq (get action-type entry) action-type)
        false
    )
)
