# Feature Questions (QA Perspective)

Questions a QA engineer would ask the developer BEFORE testing. These uncover gaps between what the spec says and what was actually built.

## Question categories

### Implementation clarity
- [ ] Is this feature behind a feature flag? If yes, what's the default state?
- [ ] Are there any A/B test variants for this feature?
- [ ] What analytics events are being tracked? What triggers them?
- [ ] Is there a kill switch if this feature causes issues in production?
- [ ] What's the rollback plan if this feature breaks after release?

### Behavior specification
- [ ] What exactly happens when [specific error] occurs? (for each error type)
- [ ] What's the retry behavior? Automatic or manual? How many times?
- [ ] Is there a debounce/throttle on user actions? What's the interval?
- [ ] Does this feature work in offline mode? What's cached?
- [ ] What's the maximum response time before showing a timeout?

### Data and state
- [ ] Where does the data come from? (API, cache, local DB, combination)
- [ ] What's the cache invalidation strategy?
- [ ] Is there optimistic UI? If yes, what happens on server rejection?
- [ ] Does this feature persist data across app restarts?
- [ ] Is there any data that's user-specific vs device-specific?

### Integration points
- [ ] Does this feature depend on any background service / worker?
- [ ] Does this feature send push notifications?
- [ ] Does this feature interact with system features (camera, location, contacts)?
- [ ] Does this feature require any new permissions?
- [ ] Does this feature write to any shared location (files, clipboard, system settings)?

### Boundary conditions
- [ ] What's the maximum number of items this feature handles?
- [ ] What's the maximum text length for input fields?
- [ ] What's the minimum screen size this feature supports?
- [ ] Is there a rate limit on the underlying API?
- [ ] What happens at midnight / end of day / end of month?

### Trading-specific QA questions
- [ ] Does this feature auto-refresh during market hours?
- [ ] What's the refresh interval for real-time data?
- [ ] Does the feature differentiate between BSE and NSE data?
- [ ] How does this feature handle corporate action adjustments?
- [ ] Is this feature accessible during maintenance windows?

## Output format

```
### QA questions
- [ ] [Question] — Why it matters: [testing impact]
```

Focus on questions whose answers change HOW you'd test the feature. Skip obvious questions.
