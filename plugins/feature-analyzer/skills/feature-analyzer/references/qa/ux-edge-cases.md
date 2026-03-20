# UX Edge Cases

Identify edge cases that affect the user experience — platform behaviors, device states, and interaction patterns that developers often forget to test.

## Android platform edge cases

### Configuration changes
- [ ] Screen rotation during operation — UI rebuilt, state preserved
- [ ] Dark mode toggle — colors correct, no flash of wrong theme
- [ ] Font size change (accessibility) — layout doesn't break, text not clipped
- [ ] Display size change — elements still tappable, layout intact
- [ ] Language/locale change — strings updated, RTL handled if applicable
- [ ] Keyboard appearance — content not hidden behind keyboard, scroll behavior correct

### Navigation edge cases
- [ ] Back press — correct behavior (close dialog? go back? exit feature?)
- [ ] System back gesture (Android 13+ predictive back) — animation correct
- [ ] Deep link into the feature — correct state even without prior navigation
- [ ] Deep link with invalid parameters — graceful fallback
- [ ] App link from notification — navigates to correct screen
- [ ] Multi-instance launch from recent apps — no duplicate state

### Gesture and interaction
- [ ] Long press on any text — system text selection, no conflict with feature
- [ ] Swipe gestures — no conflict with system back gesture
- [ ] Multi-touch — feature handles correctly (no duplicate actions)
- [ ] Scroll inside scroll — nested scrolling behaves correctly
- [ ] Pull-to-refresh — doesn't conflict with other scroll gestures
- [ ] Keyboard submit vs button tap — same behavior

### Multi-window and display
- [ ] Split screen mode — layout adapts, no crash
- [ ] Foldable device fold/unfold — layout transitions smoothly
- [ ] Pop-up / floating window — minimum size renders correctly
- [ ] External display / casting — content visible and correct
- [ ] Landscape mode — layout handles or gracefully locks to portrait

### Accessibility
- [ ] TalkBack / screen reader — all elements have content descriptions
- [ ] Switch Access — all interactive elements reachable
- [ ] Color contrast — meets WCAG AA minimum (4.5:1 for text)
- [ ] Touch target size — minimum 48dp for all interactive elements
- [ ] Custom actions — complex gestures have accessible alternatives
- [ ] Live regions — dynamic content announced to screen readers

### System interaction
- [ ] Do Not Disturb mode — notifications/alerts still work (or intentionally suppressed)
- [ ] Battery saver mode — background work restricted, feature still usable
- [ ] Data saver mode — large content downloads respect user preference
- [ ] Storage full — graceful handling, no crash
- [ ] Permission revoked while app is in background — feature degrades gracefully
- [ ] App pinned (screen pinning) — feature still functional

### Timing and animation
- [ ] Rapid tap (user taps button 5 times quickly) — only one action fires
- [ ] Animation completion — no interaction allowed during transition
- [ ] Snackbar/toast timing — doesn't overlap with other messages
- [ ] Loading to content transition — no layout jump/flash

### Trading-specific UX edge cases
- [ ] Real-time price update during user interaction (typing order quantity while price changes)
- [ ] Market close during active feature usage — graceful transition
- [ ] Multiple watchlist items updating simultaneously — smooth scrolling maintained
- [ ] Large portfolio rendering — no UI jank on initial load

## Output format

```
### UX edge cases
- [ ] **[Category]**: [Scenario] — Expected behavior: [what should happen]
```

Only include edge cases RELEVANT to the feature. A simple settings screen doesn't need all the multi-window and accessibility edge cases — focus on what matters.
