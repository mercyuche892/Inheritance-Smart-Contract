(define-constant err-not-owner (err u100))
(define-constant err-already-exists (err u101))
(define-constant err-not-found (err u102))
(define-constant err-not-eligible (err u103))
(define-constant err-time-lock (err u104))

(define-map inheritance-plans
    principal
    {
        beneficiary: principal,
        amount: uint,
        unlock-time: uint,
        claimed: bool,
    }
)

(define-map verified-deaths
    principal
    bool
)

(define-public (create-inheritance
        (beneficiary principal)
        (amount uint)
        (unlock-time uint)
    )
    (begin
        (asserts! (is-none (map-get? inheritance-plans tx-sender))
            err-already-exists
        )
        (map-set inheritance-plans tx-sender {
            beneficiary: beneficiary,
            amount: amount,
            unlock-time: unlock-time,
            claimed: false,
        })
        (ok true) ;; Return `true` to indicate success
    )
)

(define-read-only (get-inheritance (owner principal))
    (match (map-get? inheritance-plans owner)
        plan (ok plan)
        err-not-found
    )
)

(define-constant contract-owner tx-sender)

(define-public (verify-death (owner principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-not-owner)
        (map-set verified-deaths owner true)
        (ok true)
    )
)

(define-public (claim-inheritance (owner principal))
    (let ((plan (unwrap! (map-get? inheritance-plans owner) err-not-found)))
        (asserts! (is-eq (get beneficiary plan) tx-sender) err-not-eligible)
        (asserts! (not (get claimed plan)) err-not-eligible)
        (asserts!
            (or (is-some (map-get? verified-deaths owner)) (>= stacks-block-height (get unlock-time plan)))
            err-time-lock
        )
        (begin
            (map-set inheritance-plans owner (merge plan { claimed: true }))
            (try! (stx-transfer? (get amount plan) owner tx-sender))
            (ok true)
        )
    )
)
