# Notion Checklist Output

Auto-create a Notion page with the complete feature analysis as structured checklists.

## Notion page structure

Create a Notion page with the following structure. Use the Notion MCP tools (`notion-create-pages`, `notion-update-page`) to create the page.

### Page title
`📋 Feature Analysis: [Feature Name]`

### Page properties (if using a database)
- Status: "New"
- Date: [Today's date]
- Priority: [Based on feature complexity]
- Feature: [Feature name]

### Page content layout

Use Notion's native checklist blocks (to_do blocks) for all checklist items. Use heading blocks for sections. Use callout blocks for key insights or warnings.

```
# 📋 Feature Analysis: [Feature Name]

> 📝 **Summary**: [One-line feature description]
> 📅 **Analyzed**: [Date]
> 🏷️ **Domain**: [Trading/Fintech or other]

---

## 🔍 Story Clarification

### Assumptions (verify with stakeholders)
- [ ] [Assumption] — Impact: [why it matters]

### Questions to ask
- [ ] [Question] — Depends on: [what decision changes]

### Missing acceptance criteria
- [ ] [Missing AC]

---

## 🏛️ Domain Analysis

### Approvals needed
- [ ] [Approval item] — Contact: [who]

### Business questions
- [ ] [Question] — Impact: [what changes]

### Domain test cases
- [ ] [Scenario]: Given [X], when [Y], then [Z]

---

## ⚙️ Tech Analysis

### Code context
- [ ] [File/module] — [What changes]

### Impact on existing features
- [ ] [Feature] — [How affected] — Severity: [H/M/L]

### Tech test cases
- [ ] [Category]: [Test] — Expected: [behavior]

### Edge cases
- [ ] [Category]: [Scenario] — Risk: [what breaks]

### Tech stack considerations
- [ ] [Component]: [Consideration]

---

## 🧪 QA Analysis

### User test cases (P0)
- [ ] [Precondition] → [Action] → [Expected]

### User test cases (P1)
- [ ] [Precondition] → [Action] → [Expected]

### QA questions
- [ ] [Question] — Why: [testing impact]

### UX edge cases
- [ ] [Category]: [Scenario] — Expected: [behavior]

---

## 🔄 Cascading Impact

### [Affected Feature 1] (Severity: High)
> **Why affected**: [explanation]

#### Domain delta
- [ ] [Change needed]

#### Tech delta
- [ ] [Change needed]

#### QA delta
- [ ] [Test needed]

> ⚠️ Regression risk: [H/M/L] | Effort: [H/M/L] | Defer: [Y/N]

### [Affected Feature 2] (if any)
[Same structure]

---

## 📊 Summary

| Category | Items | High Priority |
|----------|-------|---------------|
| Story gaps | [N] | [N] |
| Domain | [N] | [N] |
| Tech | [N] | [N] |
| QA | [N] | [N] |
| Cascade | [N features] | [N items] |
| **Total** | **[N]** | **[N]** |
```

## Notion MCP integration

Use the Notion MCP tools in this order:

1. Search for an existing "Feature Analysis" database:
   `notion-search` with query "Feature Analysis"

2. If database exists, create a page in it:
   `notion-create-pages` with the database as parent

3. If no database, create a standalone page:
   `notion-create-pages` as a standalone page

4. Structure the content using Notion block types:
   - `heading_1` for main sections
   - `heading_2` for subsections
   - `heading_3` for sub-subsections
   - `to_do` for checklist items (with checked: false)
   - `callout` for summaries and warnings
   - `divider` between major sections
   - `table` for the summary table

## Fallback

If Notion MCP is not available, output the complete analysis as a markdown file that can be manually pasted into Notion. Notion natively understands markdown checklists (`- [ ]`), headers (`#`), and callouts (`>`).
