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

(define-data-var minimum-signatures uint u2)
(define-data-var cooling-period uint u144)

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
