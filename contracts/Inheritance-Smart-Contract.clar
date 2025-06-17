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
