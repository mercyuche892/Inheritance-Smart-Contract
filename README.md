# 🏦 Inheritance Smart Contract 🏦

A decentralized solution for digital asset inheritance and wealth transfer on the Stacks blockchain.

## 📝 Overview

This smart contract enables users to create digital wills for their STX tokens, specifying beneficiaries and conditions for asset release. The contract supports:

- ⏰ Time-locked inheritance (assets released after a specific block height)
- 🔐 Multi-signature verification by designated executors
- 👥 Multiple beneficiaries with percentage-based allocations
- 🛡️ Identity verification integration

## 🚀 Features

- **Create Will**: Define beneficiaries, their shares, time-lock period, and executors
- **Fund Will**: Add STX tokens to your inheritance contract
- **Executor Signatures**: Designated executors can sign to validate the inheritance claim
- **Claim Inheritance**: Beneficiaries can claim their share when conditions are met
- **Identity Verification**: Built-in identity verification system
- **Will Management**: Update time-locks and multi-signature requirements

## 💻 Usage

### Creating a Will

```clarity
(contract-call? .inheritance-smart-contract create-will 
  (list 
    {beneficiary: 'ST1SJ3DTE5DN7X54YDH5D64R3BCB6A2AG2ZQ8YPD5, share: u60}
    {beneficiary: 'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG, share: u40}
  )
  u100000 ;; time-lock (block height)
  u2 ;; required signatures
  (list 
    'ST2JHG361ZXG51QTKY2NQCVBPPRRE2KZB1HR05NNC
    'ST2NEB84ASENDXKYGJPQW86YXQCEFEX2ZQPG87ND
    'ST2REHHS5J3CERCRBEPMGH7921Q6PYKAADT7JP2VB
  )
)
```

### Funding a Will

```clarity
(contract-call? .inheritance-smart-contract fund-will u1000000)
```

### Signing as an Executor

```clarity
(contract-call? .inheritance-smart-contract sign-as-executor 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### Claiming Inheritance

```clarity
(contract-call? .inheritance-smart-contract claim-inheritance 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

## 🔒 Security Considerations

- Multiple executor signatures provide additional security
- Time-locks prevent premature asset distribution
- Only verified beneficiaries can claim their share
- Will owners can deactivate their will at any time

## 🧪 Testing

Use Clarinet to test the contract functionality:

```bash
clarinet test
```

## 📜 License

MIT
```