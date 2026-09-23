# Journey: remove a saved item and keep shopping

**Goal:** remove one product from the saved list and get back to the list to keep browsing.

App: `example/ux_demo_app`. No backend and no login, so there is no
`setup:` block — the app opens straight onto step 1.

## 1. Open a saved product

From the list screen, tap the product named **Walnut Side Table**.

**Expected:** the detail screen for that product opens, showing its price and description.

## 2. Remove it from the list

On the detail screen, tap **Remove from list**.

**Expected:** the app asks the user to confirm before anything is destroyed, and removes the
product only after the user confirms.

## 3. Return to the list

Get back to the saved list to keep browsing.

**Expected:** the list screen is shown again, with Walnut Side Table gone and the other two
products still there.

---

Steps 2 and 3 are expected to fail on this app — it is a fixture with six deliberately seeded
defects. Two of them (a destructive action with no confirmation, and a dead-end screen with no
way back) are only visible at this journey level: every widget on the screen that ends the
journey passes every per-screen accessibility check.
