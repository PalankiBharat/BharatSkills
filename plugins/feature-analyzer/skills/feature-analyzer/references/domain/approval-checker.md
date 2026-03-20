# Approval Checker

Identify all approvals, sign-offs, and compliance requirements before development starts.

## Trading/fintech approval categories

### Exchange approvals
- Does this feature interact with exchange APIs (NSE, BSE, MCX)?
- Does it introduce a new order type or modify order flow?
- Does it change how market data is displayed (exchange display rules)?
- Does it affect trade execution, modification, or cancellation?
- Does it touch margin calculation or risk management?
- Any new instrument type support (equity, F&O, commodity, currency)?

### Regulatory (SEBI/RBI)
- Does this feature handle financial transactions?
- Does it display financial advice or recommendations?
- Does it involve customer KYC data?
- Does it affect audit trail / trade logging?
- Does it change risk disclosure or consent flows?
- Privacy implications (data collection, storage, sharing)?

### Broker API approvals
- Does this need new broker API permissions (Zerodha Kite, etc.)?
- Rate limiting implications of the new feature?
- API versioning — is the current API version sufficient?
- Sandbox vs production API differences?

### Internal approvals
- Product owner sign-off on business logic
- Design team approval on UI/UX changes
- Backend team coordination (if API changes needed)
- DevOps/infra for new services or increased load
- Legal/compliance review (if feature touches financial data)

## For non-trading apps

### General approval categories
- Data privacy (GDPR, local regulations)
- Third-party API terms of service
- App store guidelines compliance (Google Play policies)
- Accessibility requirements
- Security review (if handling sensitive data)
- Backend API readiness

## Output format

```
### Approvals needed
- [ ] [Approval type]: [Specific approval needed] — [Who to contact]
- [ ] [Approval type]: [Specific approval needed] — [Who to contact]

### No approval needed (confirmed)
- [Category]: [Why no approval is needed]
```

Generate at least the categories that are clearly relevant. For categories that MIGHT be relevant, flag them as "verify if needed."
