-- Browser harness: runs the appearance browser's files against a fake client
-- and asserts what they do through their public interface.
-- Usage, from the repo root: lua5.1 dev/browser-harness/run.lua
-- Exits 1 when any test fails.
local here = (arg[0]:match("^(.*)[/\\]") or ".")
local repo = arg[1] or (here .. "/../..")
local Fake = dofile(here .. "/fake_client.lua")
local realPrint = print

local tests, failures = {}, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local function check(cond, what)
    if not cond then error("expected " .. what, 2) end
end
local function equal(actual, expected, what)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end
local function sameState(before, after, what)
    for k, v in pairs(before) do
        if after[k] ~= v then
            error(("%s: Collections' %s was %s, is %s"):format(what, k, tostring(v), tostring(after[k])), 2)
        end
    end
end

-- A fresh client with every file of the .toc loaded.
local function boot(opts)
    local c = Fake.new(opts)
    c.loaded = c.loadToc(repo)
    return c
end
local function ids(list)
    local out = {}
    for i, a in ipairs(list) do out[i] = a.id end
    return table.concat(out, ",")
end

---------------------------------------------------------------- Query queue

-- A name browse through the queue; the record counts its answers.
local function queueBrowse(text, maxPages)
    local r = { done = 0, failed = 0 }
    TC.AuctionQueue.Browse({ searchString = text, sorts = {}, filters = {} }, maxPages or 5, {
        done = function(rows, cut) r.done, r.rows, r.cut = r.done + 1, rows, cut end,
        failed = function(reason) r.failed, r.reason = r.failed + 1, reason end,
    })
    return r
end
local function listing(name, itemID, minPrice, extra)
    local l = { name = name, itemID = itemID, minPrice = minPrice, totalQuantity = 1 }
    for k, v in pairs(extra or {}) do l[k] = v end
    return l
end
local function answeredOnce(r, what)
    equal(r.done + r.failed, 1, what .. ": answers")
end

test("queue: one message in flight; the next goes out only once the first is answered and the client is ready", function()
    local c = boot()
    c.ah.listings = { listing("Willow Boots", 1, 100), listing("Linen Boots", 2, 200) }
    local a, b = queueBrowse("Willow"), queueBrowse("Linen")
    equal(#c.ah.sends, 1, "sends at once")
    c.advance(0.26)
    equal(a.done, 1, "first answered")
    equal(#a.rows, 1, "first rows")
    equal(#c.ah.sends, 1, "sends after the answer, throttle still closed")
    c.advance(0.05)
    equal(#c.ah.sends, 2, "sends once the client is ready")
    c.advance(0.3)
    equal(b.done, 1, "second answered")
    equal(b.rows[1].itemKey.itemID, 2, "second rows")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

test("queue: nothing is sent while the client is not ready; the ready event sends it", function()
    local c = boot()
    c.ah.ready = false
    local r = queueBrowse("Boots")
    c.advance(1)
    equal(#c.ah.sends, 0, "sends while not ready")
    c.ah.ready = true
    c.fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    equal(#c.ah.sends, 1, "sends after the ready event")
    c.advance(0.3)
    equal(r.done, 1, "answered")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

test("queue: polling sees the client ready when no event comes", function()
    local c = boot()
    c.ah.ready, c.ah.readyEvent = false, false
    local a, b = queueBrowse("Boots"), queueBrowse("Shoes")
    c.advance(1)
    c.ah.ready = true
    c.advance(0.3)
    equal(#c.ah.sends, 1, "first sent by polling")
    c.advance(1)
    equal(a.done, 1, "first answered")
    equal(#c.ah.sends, 2, "second sent by polling, without the ready event")
    c.advance(1)
    equal(b.done, 1, "second answered")
end)

test("queue: later pages are read until the client has the full result or maxPages is reached", function()
    local c = boot()
    c.ah.pageSize = 2
    for i = 1, 5 do c.ah.listings[i] = listing("Boots " .. i, i, i * 10) end
    local r = queueBrowse("Boots", 5)
    c.advance(5)
    equal(r.done, 1, "answered")
    equal(#r.rows, 5, "rows of all three pages")
    equal(#c.ah.more, 2, "requests for more")
    c = boot()
    c.ah.pageSize = 2
    for i = 1, 5 do c.ah.listings[i] = listing("Boots " .. i, i, i * 10) end
    r = queueBrowse("Boots", 2)
    c.advance(5)
    equal(#r.rows, 4, "rows of two pages")
    equal(#c.ah.more, 1, "requests for more with maxPages 2")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

test("queue: each failure answers once with its reason and fails what is queued behind it", function()
    local cases = {
        { set = function(ah) ah.fail = true end, at = 0.3, reason = "browse failure" },
        { set = function(ah) ah.silent = true end, at = 5.3, reason = "no answer" },
        { set = function(ah) ah.ready, ah.neverReady = false, true end, at = 5.3, reason = "not ready" },
    }
    for _, case in ipairs(cases) do
        local c = boot()
        case.set(c.ah)
        local a, b = queueBrowse("Boots"), queueBrowse("Shoes")
        c.advance(case.at - 0.6)
        equal(a.failed + b.failed, 0, case.reason .. ": failures before the limit")
        c.advance(0.6)
        answeredOnce(a, case.reason .. ", first")
        answeredOnce(b, case.reason .. ", queued")
        equal(a.failed, 1, case.reason .. ": first failed")
        equal(b.failed, 1, case.reason .. ": queued failed")
        check(tostring(a.reason):find(case.reason, 1, true), case.reason .. " in the reason, got " .. tostring(a.reason))
        check(#c.ah.sends <= 1, case.reason .. ": the queued browse not sent")
        c.advance(20)
        answeredOnce(a, case.reason .. ", first, later")
        answeredOnce(b, case.reason .. ", queued, later")
    end
end)

test("queue: after CancelAll no handler is called, late events change nothing, and the queue works again", function()
    local c = boot()
    c.ah.listings = { listing("Willow Boots", 1, 100) }
    local a, b = queueBrowse("Willow"), queueBrowse("Willow")
    TC.AuctionQueue.CancelAll()
    c.advance(10)
    c.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    c.fire("AUCTION_HOUSE_BROWSE_FAILURE")
    equal(a.done + a.failed + b.done + b.failed, 0, "handler calls after CancelAll")
    equal(#c.ah.sends, 1, "sends: only the one in flight before CancelAll")
    local r = queueBrowse("Willow")
    c.advance(1)
    equal(r.done, 1, "a browse after CancelAll")
    equal(c.pendingTimers(), 0, "timers left running")
end)

test("queue: browse events with nothing in flight are ignored", function()
    local c = boot()
    c.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    c.fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {})
    c.fire("AUCTION_HOUSE_BROWSE_FAILURE")
    c.fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    equal(#c.ah.sends, 0, "sends")
    -- an answer that comes while the next browse still waits for the client
    c.ah.ready = false
    local r = queueBrowse("Boots")
    c.fire("AUCTION_HOUSE_BROWSE_FAILURE")
    c.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    equal(r.done + r.failed, 0, "answers before the send")
    c.ah.ready = true
    c.advance(1)
    equal(r.done, 1, "answered after its own send")
end)

test("queue: a missing auction call answers as a failure, with no error and no send", function()
    for _, opts in ipairs({ { noAuctionHouse = true }, { noAuction = { "SendBrowseQuery" } },
        { noAuction = { "IsThrottledMessageSystemReady" } }, { noAuction = { "RequestMoreBrowseResults" } },
        { noTimer = true } }) do
        local c = boot(opts)
        local ok, r = pcall(queueBrowse, "Boots")
        check(ok, "no error: " .. tostring(r))
        if not opts.noAuctionHouse then c.advance(10) end
        answeredOnce(r, "missing call")
        equal(r.failed, 1, "failed")
        equal(#c.ah.sends, 0, "sends")
    end
end)

test("queue: a browse stopped at maxPages says it was cut off; one with the full result does not", function()
    local c = boot()
    c.ah.pageSize = 2
    for i = 1, 5 do c.ah.listings[i] = listing("Boots " .. i, i, i * 10) end
    local cut, full = queueBrowse("Boots", 2), queueBrowse("Boots", 3)
    c.advance(10)
    equal(#cut.rows, 4, "rows of two pages")
    equal(cut.cut, true, "cut off at maxPages")
    equal(#full.rows, 5, "rows of all three pages")
    check(not full.cut, "the full result not cut off")
end)

local function rawBrowse(text, handlers)
    TC.AuctionQueue.Browse({ searchString = text, sorts = {}, filters = {} }, 5, handlers)
end

test("queue: a handler that raises is reported once and the browses behind it are still sent and answered", function()
    local c = boot()
    c.ah.listings = { listing("A", 1, 1), listing("B", 2, 2) }
    rawBrowse("A", { done = function() error("done boom") end, failed = function() end })
    local b = queueBrowse("B")
    local ok, err = pcall(c.advance, 5)
    check(ok, "no error out of the client's event: " .. tostring(err))
    equal(#c.ah.sends, 2, "sends")
    equal(b.done, 1, "the browse behind answered")
    equal(#c.errors, 1, "errors reported")
    check(c.errors[1]:find("done boom", 1, true), "the error reported, got " .. tostring(c.errors[1]))
    -- a failed handler that raises: what is queued behind still fails once
    c = boot()
    c.ah.silent = true
    rawBrowse("A", { done = function() end, failed = function() error("failed boom") end })
    b = queueBrowse("B")
    ok, err = pcall(c.advance, 10)
    check(ok, "no error from a raising failed handler: " .. tostring(err))
    equal(b.failed, 1, "the browse behind failed once")
    equal(#c.errors, 1, "errors reported for the failed handler")
    -- without the client's error handler nothing breaks either
    c = boot()
    c.ah.listings = { listing("A", 1, 1), listing("B", 2, 2) }
    geterrorhandler = nil
    rawBrowse("A", { done = function() error("unreported") end, failed = function() end })
    b = queueBrowse("B")
    ok, err = pcall(c.advance, 5)
    check(ok, "no error without geterrorhandler: " .. tostring(err))
    equal(b.done, 1, "the browse behind answered without geterrorhandler")
end)

local function ownSends(c)
    local n = 0
    for _, s in ipairs(c.ah.sends) do if not s.foreign then n = n + 1 end end
    return n
end

test("queue: a browse another addon sends while ours is in flight fails ours and what is queued behind", function()
    local c = boot()
    c.ah.listings = { listing("Willow Boots", 1, 100), listing("Linen Boots", 2, 200) }
    local a, b = queueBrowse("Willow"), queueBrowse("Linen")
    c.advance(0.1)
    c.foreignBrowse({ searchString = "Linen", sorts = {}, filters = {} })
    equal(a.failed, 1, "ours failed")
    check(tostring(a.reason):find("another browse", 1, true), "the reason, got " .. tostring(a.reason))
    equal(b.failed, 1, "the queued browse failed")
    c.advance(5)
    answeredOnce(a, "ours after both result events")
    answeredOnce(b, "queued after both result events")
    equal(ownSends(c), 1, "our sends: no retry, the queued one not sent")
    -- nothing of ours in flight: a foreign browse changes nothing
    c.foreignBrowse()
    local r = queueBrowse("Willow")
    c.advance(0.1)
    c.advance(2)
    equal(r.done, 1, "a browse after the foreign one")
    equal(r.rows[1].itemKey.itemID, 1, "its own rows")
    -- a foreign browse while ours still waits for the client: no reaction
    c = boot()
    c.ah.ready = false
    r = queueBrowse("Willow")
    c.foreignBrowse()
    equal(r.failed, 0, "not failed before our send")
    -- the foreign answer comes at 0.25 s, the client is ready at 0.3 s
    c.advance(2)
    equal(r.done, 1, "answered after its own send")
end)

---------------------------------------------------------------- Query queue: Search (step 7)

local KEY = { itemID = 501, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
local function auction(id, buyout, extra)
    local r = { auctionID = id, buyoutAmount = buyout, quantity = 1, timeLeft = 1, owners = {}, totalNumberOfOwners = 1,
        containsOwnerItem = false, containsAccountItem = false, containsSocketedItem = false }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end
local function queueSearch(key)
    local r = { done = 0, failed = 0 }
    TC.AuctionQueue.Search(key or KEY, {
        done = function(rows) r.done, r.rows = r.done + 1, rows end,
        failed = function(reason) r.failed, r.reason = r.failed + 1, reason end,
    })
    return r
end

test("queue Search: nothing is sent until the key info is there; it is sent when the info arrives by event", function()
    local c = boot()
    c.ah.searchListings["501:0"] = { auction(7, 500) }
    -- the event comes at 12 ms; the poll would only come at 250 ms
    local r = queueSearch()
    equal(#c.ah.searches, 0, "searches before the key info")
    c.advance(0.013)
    equal(#c.ah.searches, 1, "searches once the event came")
    equal(c.ah.searches[1].dropped, nil, "the search was not dropped")
    equal(c.ah.searches[1].sorts[1].sortOrder, 4, "sorted by buyout")
    equal(c.ah.searches[1].sorts[1].reverseSort, false, "cheapest first")
    equal(c.ah.searches[1].separate, false, "separateOwnerItems false, as the probe sent it")
    c.advance(0.3)
    equal(r.done, 1, "answered")
    equal(r.rows[1].auctionID, 7, "the result rows")
    equal(r.rows[1].buyoutAmount, 500, "the result's buyout")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

test("queue Search: the key info seen only by polling sends it", function()
    local c = boot()
    c.ah.keyEvent = false
    local r = queueSearch()
    c.advance(0.2)
    equal(#c.ah.searches, 0, "searches before the poll")
    c.advance(0.1)
    equal(#c.ah.searches, 1, "sent at the poll")
    c.advance(0.3)
    equal(r.done, 1, "answered")
end)

test("queue Search: a send the client dropped (ready still true right after) is sent again", function()
    local c = boot()
    c.ah.keyKnown["501:0"] = true
    c.ah.dropSearches = 1
    c.ah.searchListings["501:0"] = { auction(7, 500) }
    local r = queueSearch()
    equal(#c.ah.searches, 1, "the first send at once")
    equal(c.ah.searches[1].dropped, true, "the first send dropped")
    c.advance(0.26)
    equal(#c.ah.searches, 2, "sent again at the next poll")
    c.advance(0.3)
    equal(r.done, 1, "answered")
    equal(#c.ah.searches, 2, "no further send")
end)

test("queue Search: the repeated result event finishes the search once and changes nothing after", function()
    local c = boot()
    c.ah.keyKnown["501:0"] = true
    c.ah.searchListings["501:0"] = { auction(7, 500) }
    c.ah.listings = { listing("Willow Boots", 501, 100) }
    local r = queueSearch()
    local b = queueBrowse("Willow")
    c.advance(0.26)
    equal(r.done, 1, "search answered")
    equal(#c.ah.sends, 0, "the browse waits for the client")
    -- the repeat comes at 0.55 s, while the browse is in flight
    c.advance(0.6)
    equal(r.done + r.failed, 1, "the search answered once")
    equal(b.done, 1, "the browse answered, not disturbed by the repeat")
    c.fire("ITEM_SEARCH_RESULTS_UPDATED", KEY)
    equal(r.done + r.failed, 1, "a late event changes nothing")
end)

test("queue Search: an answer for another item key does not finish ours", function()
    local c = boot()
    c.ah.keyKnown["501:0"] = true
    c.ah.silent = true
    local r = queueSearch()
    c.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 501, itemLevel = 0, itemSuffix = 9, battlePetSpeciesID = 0 })
    c.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 502, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
    equal(r.done + r.failed, 0, "answers")
end)

test("queue Search: each failure answers once with its reason", function()
    local cases = {
        { set = function(ah) ah.keyNever["501:0"] = true end, at = 5.3, reason = "no item key info" },
        { set = function(ah) ah.keyKnown["501:0"] = true; ah.silent = true end, at = 5.3, reason = "no answer" },
        { set = function(ah) ah.keyKnown["501:0"] = true; ah.ready, ah.neverReady = false, true end, at = 5.3,
            reason = "not ready" },
        -- three sends, at 0, 0.25 and 0.5 s (fix F5)
        { set = function(ah) ah.keyKnown["501:0"] = true; ah.dropSearches = 1000 end, at = 0.75, reason = "dropped" },
    }
    for _, case in ipairs(cases) do
        local c = boot()
        case.set(c.ah)
        local r = queueSearch()
        c.advance(case.at - 0.6)
        equal(r.failed, 0, case.reason .. ": failures before the limit")
        c.advance(0.6)
        answeredOnce(r, case.reason)
        equal(r.failed, 1, case.reason .. ": failed")
        check(tostring(r.reason):find(case.reason, 1, true), case.reason .. " in the reason, got " .. tostring(r.reason))
        local sent = #c.ah.searches
        c.advance(20)
        answeredOnce(r, case.reason .. ", later")
        equal(#c.ah.searches, sent, case.reason .. ": sends after the failure")
        equal(c.pendingTimers(), 0, case.reason .. ": timers left running")
    end
end)

test("queue Search: a search and a browse are never in flight together, in either order", function()
    local c = boot()
    c.ah.keyKnown["501:0"] = true
    local b = queueBrowse("Willow")
    local r = queueSearch()
    equal(#c.ah.sends, 1, "the browse sent")
    equal(#c.ah.searches, 0, "the search waits behind the browse")
    c.advance(0.26)
    equal(#c.ah.searches, 0, "the search waits for the client")
    -- the client is ready at 0.3 s; the search answers at 0.55 s
    c.advance(0.05)
    equal(#c.ah.searches, 1, "the search sent once the browse was answered and the client ready")
    local b2 = queueBrowse("Linen")
    c.advance(0.2)
    equal(#c.ah.sends, 1, "the next browse waits behind the search")
    equal(r.done, 0, "the search not answered yet")
    c.advance(2)
    equal(b.done + r.done + b2.done, 3, "all answered")
    equal(#c.ah.sends, 2, "two browses")
end)

test("queue Search: CancelAll stops a search before and after its send", function()
    local c = boot()
    local r = queueSearch()
    TC.AuctionQueue.CancelAll()
    c.advance(10)
    equal(#c.ah.searches, 0, "no send after CancelAll")
    equal(r.done + r.failed, 0, "no answer after CancelAll")
    c = boot()
    c.ah.keyKnown["501:0"] = true
    r = queueSearch()
    equal(#c.ah.searches, 1, "sent")
    TC.AuctionQueue.CancelAll()
    c.advance(10)
    equal(r.done + r.failed, 0, "no answer after CancelAll")
    equal(TC.AuctionQueue.IsIdle(), true, "idle")
    equal(c.pendingTimers(), 0, "timers left running")
end)

test("queue Search: a foreign browse does not fail a search; a missing search call fails with no error", function()
    local c = boot()
    c.ah.keyKnown["501:0"] = true
    local r = queueSearch()
    c.foreignBrowse()
    c.advance(1)
    equal(r.done, 1, "the search answered")
    for _, missing in ipairs({ "SendSearchQuery", "GetItemKeyInfo", "GetNumItemSearchResults", "GetItemSearchResultInfo" }) do
        c = boot({ noAuction = { missing } })
        local ok, res = pcall(queueSearch)
        check(ok, missing .. ": no error " .. tostring(res))
        c.advance(10)
        equal(res.failed, 1, missing .. ": failed")
        equal(#c.ah.searches, 0, missing .. ": no search")
    end
end)

test("queue IsIdle: idle with nothing queued, busy while a browse or a search is in flight or waiting", function()
    local c = boot()
    equal(TC.AuctionQueue.IsIdle(), true, "idle at the start")
    queueSearch()
    equal(TC.AuctionQueue.IsIdle(), false, "busy while the search waits for key info")
    c.advance(1)
    equal(TC.AuctionQueue.IsIdle(), true, "idle once answered")
    queueBrowse("Willow")
    equal(TC.AuctionQueue.IsIdle(), false, "busy while a browse is in flight")
end)

---------------------------------------------------------------- Scan

-- A scan of feet; the record keeps every onProgress and the done answer.
-- In the default fixture item <id>*10+n carries appearance <id>.
local function runScan(c, seconds)
    local r = { progress = {}, done = 0 }
    TC.Scan.Run("feet", function(found, pages)
        r.progress[#r.progress + 1] = pages
        r.lastFound = found
    end, function(result, reason)
        r.done, r.result, r.reason = r.done + 1, result, reason
    end)
    c.advance(seconds or 30)
    return r
end

test("scan: one browse with the feet filter entries, the sort pair, no search text and no uncollected-only filter", function()
    local c = boot()
    c.ah.listings = { listing("Item 10011", 10011, 100) }
    local r = runScan(c)
    equal(#c.ah.sends, 1, "browses")
    local q = c.ah.sends[1].query
    equal(q.searchString, "", "search text")
    equal(#q.sorts, 2, "sort entries")
    equal(q.sorts[1].sortOrder, 0, "first sort Price")
    equal(q.sorts[2].sortOrder, 1, "second sort Name")
    equal(q.sorts[1].reverseSort, false, "price ascending")
    equal(type(q.filters), "table", "filters")
    equal(#q.filters, 0, "filters (no uncollected only)")
    equal(#q.itemClassFilters, 4, "filter entries")
    for i, entry in ipairs(q.itemClassFilters) do
        equal(entry.classID, 4, "entry " .. i .. " class Armor")
        equal(entry.subClassID, i, "entry " .. i .. " subclass Cloth, Leather, Mail, Plate")
        equal(entry.inventoryType, 8, "entry " .. i .. " IndexFeetType")
    end
    equal(r.done, 1, "done calls")
    check(r.result, "a result, got the failure " .. tostring(r.reason))
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

test("scan: every page is read to the end and onProgress follows each page with the pages read", function()
    local c = boot()
    c.ah.pageSize = 2
    for i = 1, 5 do c.ah.listings[i] = listing("Item " .. (10001 + i * 10), 10001 + i * 10, i * 100) end
    local r = runScan(c)
    equal(#c.ah.sends, 1, "browses")
    equal(#c.ah.more, 2, "requests for more")
    equal(table.concat(r.progress, ","), "1,2,3", "pages read at each onProgress")
    equal(r.result.pages, 3, "pages of the result")
    local n = 0
    for _ in pairs(r.result.appearances) do n = n + 1 end
    equal(n, 5, "appearances found")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

test("scan: rows group by appearance with the lowest price by comparing; rows without an appearance are dropped; a repeated row counts once", function()
    local c = boot()
    c.ah.pageSize = 2
    c.ah.listings = {
        listing("Item 10011", 10011, 300, { totalQuantity = 2 }),
        listing("Item 10021", 10021, 400),
        -- page 2: the row at the seam again, a cheaper variant of 1001's other item, a row without appearance
        listing("Item 10021", 10021, 400),
        listing("Item 10012", 10012, 250, { itemSuffix = 7 }),
        listing("Unknown", 999, 10),
    }
    local r = runScan(c)
    local found = r.result.appearances
    equal(found[999], nil, "no group for the row without appearance")
    local n = 0
    for _ in pairs(found) do n = n + 1 end
    equal(n, 2, "appearances found")
    equal(found[1001].minPrice, 250, "1001's lowest price, from the later page")
    equal(#found[1001].rows, 2, "1001's item variants")
    equal(found[1001].rows[1].minPrice, 250, "1001's rows cheapest first")
    equal(found[1001].rows[2].totalQuantity, 2, "quantity kept")
    equal(#found[1002].rows, 1, "the repeated row counted once")
    equal(found[1002].minPrice, 400, "1002's price")
end)

test("scan: a failure, a cut-off at 60 pages and a missing call answer as failed", function()
    local c = boot()
    c.ah.fail = true
    local r = runScan(c)
    equal(r.done, 1, "done calls on failure")
    equal(r.result, nil, "no result on failure")
    check(tostring(r.reason):find("browse failure"), "failure reason, got " .. tostring(r.reason))

    c = boot()
    c.ah.pageSize = 1
    for i = 1, 61 do c.ah.listings[i] = listing("Item 10011", 10011, i, { itemSuffix = i }) end
    r = runScan(c, 120)
    equal(1 + #c.ah.more, 60, "pages read before the cut")
    equal(r.done, 1, "done calls on a cut-off")
    equal(r.result, nil, "no result on a cut-off")
    check(tostring(r.reason):find("60 pages"), "cut-off reason, got " .. tostring(r.reason))

    for _, opts in ipairs({ { noItemTransmog = true }, { noScanEnums = true }, { noAuctionHouse = true } }) do
        c = boot(opts)
        local ok, res = pcall(runScan, c)
        check(ok, "no error with " .. next(opts) .. ": " .. tostring(res))
        equal(res.done, 1, "done calls with " .. next(opts))
        equal(res.result, nil, "no result with " .. next(opts))
        equal(#c.ah.sends, 0, "browses with " .. next(opts))
    end
end)

test("scan: reads no item data, and resolves each row's appearance once", function()
    local c = boot()
    c.ah.pageSize = 2
    for i = 1, 8 do c.ah.listings[i] = listing("Item " .. (10001 + i * 10), 10001 + i * 10, i * 100) end
    local info, loads, resolved = c.itemInfoCalls, #c.loadRequests, c.transmogInfoCalls
    local r = runScan(c)
    equal(table.concat(r.progress, ","), "1,2,3,4", "four pages")
    equal(c.itemInfoCalls - info, 0, "C_Item.GetItemInfo calls during the scan")
    equal(#c.loadRequests - loads, 0, "RequestLoadItemDataByID calls during the scan")
    equal(c.transmogInfoCalls - resolved, 8, "C_TransmogCollection.GetItemInfo calls for 8 rows")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

test("scan: the grouped result persists across pages", function()
    local c = boot()
    c.ah.pageSize = 2
    for i = 1, 4 do c.ah.listings[i] = listing("Item " .. (10001 + i * 10), 10001 + i * 10, i * 100) end
    local tables = {}
    TC.Scan.Run("feet", function(found) tables[#tables + 1] = found end, function() end)
    c.advance(30)
    equal(#tables, 2, "pages")
    check(tables[1] == tables[2], "the same grouped table on every page")
end)

test("scan: a row without a buyout price is dropped; an appearance with only such rows is not for sale", function()
    local c = boot()
    c.ah.listings = {
        listing("Item 10011", 10011, 0),
        listing("Item 10012", 10012, 500, { itemSuffix = 1 }),
        listing("Item 10021", 10021, 0),
    }
    local found = runScan(c).result.appearances
    equal(found[1001].minPrice, 500, "1001's price is the buyout one")
    equal(#found[1001].rows, 1, "1001's item variants")
    equal(found[1002], nil, "1002 has only a row at 0")
end)

---------------------------------------------------------------- Appearance source

test("List gives head for the player's class in Collections' order, without hidden visuals", function()
    local c = boot({ appearances = {
        { id = 1, uiOrder = 3, sources = { 11 }, classes = { [9] = true } },
        { id = 2, uiOrder = 1, sources = { 21 }, classes = { [9] = true } },
        { id = 3, uiOrder = 5, sources = { 31 }, collectedSource = 31, classes = { [9] = true } },
        { id = 4, uiOrder = 2, sources = { 41 }, classes = { [9] = true }, hide = true },
        { id = 5, uiOrder = 4, sources = { 51, 52 }, collectedSource = 52, classes = { [9] = true } },
        { id = 6, uiOrder = 0, sources = { 61 }, classes = { [8] = true } },
    } })
    local list = TC.Appearances.List("head", 9)
    -- without minIlvl: collected first, then uiOrder descending
    equal(ids(list), "3,5,1,2", "order")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

test("List orders by minIlvl ascending when the client gives it, as this client's comparator does", function()
    boot({ appearances = {
        { id = 1, uiOrder = 1, minIlvl = 30, sources = { 11 }, classes = { [9] = true } },
        { id = 2, uiOrder = 9, minIlvl = 10, sources = { 21 }, classes = { [9] = true } },
        { id = 3, uiOrder = 5, minIlvl = 20, sources = { 31 }, classes = { [9] = true } },
        { id = 4, uiOrder = 0, minIlvl = 40, sources = { 41 }, collectedSource = 41, classes = { [9] = true } },
    } })
    equal(ids(TC.Appearances.List("head", 9)), "4,2,3,1", "order")
end)

test("List keeps the client's order when CollectionWardrobeUtil is absent", function()
    boot({ noCompare = true, appearances = {
        { id = 1, uiOrder = 3, sources = { 11 }, classes = { [9] = true } },
        { id = 2, uiOrder = 1, sources = { 21 }, collectedSource = 21, classes = { [9] = true } },
        { id = 3, uiOrder = 5, sources = { 31 }, classes = { [9] = true } },
    } })
    -- the fake client gives them by id, descending
    equal(ids(TC.Appearances.List("head", 9)), "3,2,1", "order")
end)

test("List for the player's class reads the list when Collections shows another class, and puts it back", function()
    local c = boot({ classFilter = 8 })
    local list = TC.Appearances.List("head", 9)
    equal(#list, 370, "appearances for class 9")
    equal(c.collections.classFilter, 8, "class filter after List")
end)

test("List leaves every Collections setting as it found it, for every starting value and failure", function()
    local failures = { {}, { listRaises = true }, { listNil = true }, { setClassRaises = true } }
    for _, classFilter in ipairs({ 9, 8, 1 }) do
        for _, uncollected in ipairs({ false, true }) do
            for _, collected in ipairs({ false, true }) do
                for _, search in ipairs({ "", "owl" }) do
                    for _, failure in ipairs(failures) do
                        local opts = { classFilter = classFilter, uncollectedShown = uncollected,
                            collectedShown = collected, search = search }
                        for k, v in pairs(failure) do opts[k] = v end
                        local c = boot(opts)
                        local before = c.snapshot()
                        pcall(TC.Appearances.List, "head", 9)
                        sameState(before, c.snapshot(), ("start %d/%s/%s/%q, failure %s"):format(classFilter,
                            tostring(uncollected), tostring(collected), search, next(failure) or "none"))
                    end
                end
            end
        end
    end
end)

test("List with a missing API gives an empty list and no error", function()
    for _, opts in ipairs({ { noTransmog = true }, { noList = true }, { listNil = true } }) do
        boot(opts)
        local ok, list = pcall(TC.Appearances.List, "head", 9)
        check(ok, "no error with " .. next(opts) .. ": " .. tostring(list))
        equal(#list, 0, "appearances with " .. next(opts))
    end
end)

test("an appearance is collected when any of its sources is, and not otherwise", function()
    local c = boot({ appearances = {
        { id = 1, sources = { 11, 12, 13 }, collectedSource = 13, uiOrder = 1, classes = { [9] = true } },
        { id = 2, sources = { 21, 22, 23 }, uiOrder = 2, classes = { [9] = true } },
        { id = 3, sources = {}, uiOrder = 3, classes = { [9] = true } },
    } })
    local list = TC.Appearances.List("head", 9)
    local byID = {}
    for _, a in ipairs(list) do byID[a.id] = a end
    equal(TC.Appearances.IsCollected(byID[1]), true, "appearance 1 (third source collected)")
    equal(TC.Appearances.IsCollected(byID[2]), false, "appearance 2 (no source collected)")
    equal(TC.Appearances.IsCollected(byID[3]), false, "appearance 3 (no sources)")
    equal(#c.forbidden, 0, "forbidden calls: " .. table.concat(c.forbidden, ", "))
end)

test("DisplaySource gives the first source after Collections' sort", function()
    boot()
    local list = TC.Appearances.List("head", 9)
    local a = list[1]
    -- the fake's SortSources puts the highest source id first
    equal(TC.Appearances.DisplaySource(a), a.id * 10 + 3, "display source")
end)

test("DisplaySource falls back when the sorted source list is unavailable", function()
    boot({ noSortSources = true })
    local a = TC.Appearances.List("head", 9)[1]
    equal(TC.Appearances.DisplaySource(a), a.id * 10 + 1, "first category source without SortSources")
    boot({ sourcesNil = true })
    a = TC.Appearances.List("head", 9)[1]
    equal(TC.Appearances.DisplaySource(a), a.id * 10 + 1, "first of all sources without category sources")
end)

-- One appearance (id 1) with three sources; the items are the test's.
local function itemsFixture(opts)
    opts.appearances = { { id = 1, uiOrder = 1, sources = { 11, 12, 13 }, classes = { [9] = true } } }
    local c = boot(opts)
    local r = { calls = 0 }
    r.call = function()
        TC.Appearances.Items({ id = 1, slot = "feet" }, function(items)
            r.calls, r.items, r.at = r.calls + 1, items, c.now
        end)
    end
    return c, r
end

test("Items drops duplicate items and gives name, quality and bind type", function()
    local c, r = itemsFixture({ sourceItems = { [11] = 501, [12] = 501, [13] = 502 }, items = {
        [501] = { name = "Willow Boots", quality = 1, bindType = 2, subType = "Cloth" },
        [502] = { name = "Ivy Boots", quality = 3, bindType = 1, subType = "Cloth" },
    } })
    r.call()
    c.advance(3)
    equal(r.calls, 1, "done calls")
    equal(#r.items, 2, "items")
    equal(r.items[1].itemID, 501, "first item")
    equal(r.items[1].name, "Willow Boots", "first name")
    equal(r.items[2].quality, 3, "second quality")
    equal(r.items[2].bindType, 1, "second bind type")
    check(r.items[1].loaded and r.items[2].loaded, "both loaded")
    equal(#c.forbidden, 0, "forbidden calls: " .. table.concat(c.forbidden, ", "))
end)

test("Items waits for a name that loads late and answers as soon as it is in", function()
    local c, r = itemsFixture({ items = {
        [11] = { name = "A", quality = 2, bindType = 2 }, [12] = { name = "B", quality = 2, bindType = 2, load = 1.2 },
        [13] = { name = "C", quality = 2, bindType = 0 },
    } })
    local start = c.now
    r.call()
    c.advance(1)
    equal(r.calls, 0, "done before the late name loaded")
    c.advance(0.5)
    equal(r.calls, 1, "done once it loaded")
    check(r.at - start < 1.3, "answered when the name came, at " .. (r.at - start))
    equal(r.items[2].name, "B", "the late name")
    check(r.items[2].loaded, "the late item marked loaded")
end)

test("Items answers once, at most 2 s after the call, and marks the items that never loaded", function()
    local c, r = itemsFixture({ items = {
        [11] = { name = "A", quality = 2, bindType = 2 }, [12] = { load = "never" }, [13] = { load = 30 },
    } })
    local start = c.now
    r.call()
    c.advance(1.9)
    equal(r.calls, 0, "done before 2 s")
    c.advance(0.2)
    equal(r.calls, 1, "done by 2 s")
    check(r.at - start <= 2, "answered within 2 s, at " .. (r.at - start))
    equal(r.items[1].loaded, true, "loaded item")
    equal(r.items[2].loaded, false, "item that never loads")
    equal(r.items[3].loaded, false, "item that loads too late")
    equal(r.items[2].name, nil, "no name for it")
    c.advance(60)
    equal(r.calls, 1, "done calls after the late item loaded")
end)

---------------------------------------------------------------- Check

local BOE, BOP, QUEST = 2, 1, 4
-- An appearance (id 1) whose sources carry the given items, one source each:
-- defs is a list of { itemID, name, bindType, load }.
local function checkClient(defs, listings, opts)
    opts = opts or {}
    local sources, sourceItems, items = {}, {}, {}
    for i, d in ipairs(defs) do
        sources[i] = 100 + i
        sourceItems[100 + i] = d[1]
        items[d[1]] = { name = d[2], quality = 2, bindType = d[3], subType = "Cloth", load = d[4] }
    end
    opts.appearances = opts.appearances or { { id = 1, uiOrder = 1, sources = sources, classes = { [9] = true } } }
    opts.sourceItems, opts.items = sourceItems, items
    local c = boot(opts)
    c.ah.listings = listings or {}
    return c
end
local function runCheck(c, seconds)
    local r = { calls = 0 }
    TC.Check.Run({ id = 1, slot = "feet" }, function(result) r.calls, r.result = r.calls + 1, result end)
    c.advance(seconds or 10)
    return r
end
local function sentNames(c)
    local out = {}
    for i, s in ipairs(c.ah.sends) do out[i] = s.query.searchString end
    return table.concat(out, "|")
end

test("check: bind-on-pickup and quest items are not looked up", function()
    local c = checkClient({ { 501, "Willow Boots", BOE }, { 502, "Bound Boots", BOP }, { 503, "Quest Boots", QUEST } })
    local r = runCheck(c)
    equal(sentNames(c), "Willow Boots", "names browsed")
    equal(r.calls, 1, "done calls")
    equal(#r.result.items, 1, "tradeable items")
    equal(r.result.outcome, "not for sale", "outcome")
end)

test("check: an appearance with no tradeable item sends nothing and cannot be sold", function()
    local c = checkClient({ { 502, "Bound Boots", BOP }, { 503, "Quest Boots", QUEST } })
    local r = runCheck(c)
    equal(#c.ah.sends, 0, "sends")
    equal(r.calls, 1, "done calls")
    equal(r.result.outcome, "cannot be sold", "outcome")
end)

test("check: one browse per distinct name, sorted by price then name, with no category filter", function()
    local c = checkClient({ { 501, "Willow Boots", BOE }, { 502, "Willow Boots", 0 }, { 503, "Ivy Boots", BOE } })
    runCheck(c)
    equal(sentNames(c), "Willow Boots|Ivy Boots", "names browsed")
    for _, s in ipairs(c.ah.sends) do
        local q = s.query
        equal(#q.sorts, 2, "sort entries")
        equal(q.sorts[1].sortOrder, 0, "first sort Price")
        equal(q.sorts[2].sortOrder, 1, "second sort Name")
        equal(q.sorts[1].reverseSort, false, "price ascending")
        equal(type(q.filters), "table", "filters")
        equal(q.itemClassFilters, nil, "itemClassFilters field")
    end
end)

test("check: rows of other items are dropped, a repeated row counts once, cheapest first", function()
    local c = checkClient({ { 501, "Willow Boots", BOE }, { 502, "Boots", BOE } }, {
        listing("Willow Boots", 501, 300, { totalQuantity = 3 }),
        listing("Willow Boots of the Owl", 501, 100, { itemSuffix = 7 }),
        listing("Simple Willow Boots", 999, 50),
        listing("Boots", 502, 200),
    })
    local r = runCheck(c)
    -- "Boots" matches every listing, so 501's rows come back twice
    equal(#c.ah.sends, 2, "browses")
    local result = r.result
    equal(result.outcome, "found", "outcome")
    equal(#result.rows, 3, "rows kept")
    local prices = {}
    for i, row in ipairs(result.rows) do prices[i] = row.minPrice end
    equal(table.concat(prices, ","), "100,200,300", "prices, cheapest first")
    equal(result.rows[1].itemKey.itemSuffix, 7, "cheapest variant")
    equal(result.rows[3].totalQuantity, 3, "quantity")
    equal(result.rows[1].name, "Willow Boots", "the item's own name on a row")
    equal(result.leftOut, 0, "items left out")
end)

test("check: a row without a buyout price is dropped", function()
    local c = checkClient({ { 501, "Willow Boots", BOE } }, {
        listing("Willow Boots", 501, 0),
        listing("Willow Boots of the Owl", 501, 500, { itemSuffix = 7 }),
    })
    local result = runCheck(c).result
    equal(result.outcome, "found", "outcome")
    equal(#result.rows, 1, "rows kept")
    equal(result.rows[1].minPrice, 500, "the buyout price")
    c = checkClient({ { 501, "Willow Boots", BOE } }, { listing("Willow Boots", 501, 0) })
    equal(runCheck(c).result.outcome, "not for sale", "only a row at 0")
end)

test("check: the outcomes of A7", function()
    -- not for sale: every tradeable item looked up, no row
    local c = checkClient({ { 501, "Willow Boots", BOE } }, { listing("Other", 7, 1) })
    equal(runCheck(c).result.outcome, "not for sale", "nothing listed")

    -- could not check: a query failed and nothing was found
    c = checkClient({ { 501, "Willow Boots", BOE } })
    c.ah.silent = true
    local r = runCheck(c)
    equal(r.result.outcome, "could not check", "silent server")
    equal(r.result.queryFailed, true, "query failed")
    check(r.result.error and r.result.error:find("no answer"), "the error text, got " .. tostring(r.result.error))

    -- could not check: an item's name never loaded and nothing was found
    c = checkClient({ { 501, "Willow Boots", BOE }, { 502, "Ivy Boots", BOE, "never" } })
    r = runCheck(c)
    equal(r.result.outcome, "could not check", "an item never loaded")
    equal(r.result.queryFailed, false, "no query failed")
    equal(r.result.leftOut, 1, "items left out")
    equal(r.result.total, 2, "tradeable items")
    equal(sentNames(c), "Willow Boots", "the loaded name still looked up")

    -- found, with items left out
    c = checkClient({ { 501, "Willow Boots", BOE }, { 502, "Ivy Boots", BOE, "never" } },
        { listing("Willow Boots", 501, 500) })
    r = runCheck(c)
    equal(r.result.outcome, "found", "found with an item left out")
    equal(r.result.leftOut, 1, "items left out")

    -- found, though a later browse failed
    c = checkClient({ { 501, "Willow Boots", BOE }, { 502, "Ivy Boots", BOE } }, { listing("Willow Boots", 501, 500) })
    TC.Check.Run({ id = 1, slot = "feet" }, function(result) r.result = result end)
    c.advance(0.3)
    c.ah.fail = true
    c.advance(10)
    equal(r.result.outcome, "found", "found, second browse failed")
    equal(r.result.leftOut, 1, "items left out after the failure")
end)

test("check: more than 10 tradeable names sends 10 and reports the rest", function()
    local defs = {}
    for i = 1, 12 do defs[i] = { 500 + i, "Boots " .. string.char(64 + i), BOE } end
    local c = checkClient(defs)
    local r = runCheck(c, 30)
    equal(#c.ah.sends, 10, "browses")
    equal(r.result.leftOut, 2, "items left out")
    equal(r.result.total, 12, "tradeable items")
    equal(r.result.outcome, "could not check", "outcome with nothing found")
end)

test("check: a missing auction call ends as could not check with no error", function()
    local c = checkClient({ { 501, "Willow Boots", BOE } }, nil, { noAuctionHouse = true })
    local ok, r = pcall(runCheck, c)
    check(ok, "no error: " .. tostring(r))
    equal(r.result.outcome, "could not check", "outcome")
end)

test("check: CancelAll stops a check before its browses and after", function()
    local c = checkClient({ { 501, "Willow Boots", BOE, 1 } }, { listing("Willow Boots", 501, 500) })
    local r = { calls = 0 }
    TC.Check.Run({ id = 1, slot = "feet" }, function() r.calls = r.calls + 1 end)
    TC.Check.CancelAll()
    TC.AuctionQueue.CancelAll()
    c.advance(10)
    equal(#c.ah.sends, 0, "sends after a cancel while items load")
    equal(r.calls, 0, "done calls")
end)

test("check: a name browse cut off at 5 pages counts its items as not looked up unless a row of theirs matched", function()
    -- the item's row is on page 7 of 7
    local listings = {}
    for i = 1, 6 do listings[i] = listing("Boots filler " .. i, 600 + i, i) end
    listings[7] = listing("Boots", 501, 100)
    local c = checkClient({ { 501, "Boots", BOE } }, listings)
    c.ah.pageSize = 1
    local r = runCheck(c, 30)
    equal(1 + #c.ah.more, 5, "pages read")
    equal(r.result.outcome, "could not check", "outcome with the row beyond page 5")
    equal(r.result.leftOut, 1, "items left out")
    -- two items of one name: one has a row on page 1, the other none in 5 pages
    listings = { listing("Boots", 501, 100) }
    for i = 1, 6 do listings[#listings + 1] = listing("Boots filler " .. i, 600 + i, 200 + i) end
    c = checkClient({ { 501, "Boots", BOE }, { 502, "Boots", BOE } }, listings)
    c.ah.pageSize = 1
    r = runCheck(c, 30)
    equal(r.result.outcome, "found", "found with a row in the pages read")
    equal(r.result.leftOut, 1, "the item without a row left out")
end)

test("check: a foreign browse 0.1 s after ours ends as could not check and fails what is queued behind", function()
    local c = checkClient({ { 501, "Willow Boots", BOE }, { 502, "Ivy Boots", BOE } },
        { listing("Willow Boots", 501, 500), listing("Ivy Boots", 502, 600) })
    local r = { calls = 0 }
    TC.Check.Run({ id = 1, slot = "feet" }, function(result) r.calls, r.result = r.calls + 1, result end)
    c.advance(0.1)
    -- another addon browses for the same name, so its result event carries our item's row
    c.foreignBrowse({ searchString = "Willow Boots", sorts = {}, filters = {} })
    c.advance(10)
    equal(r.calls, 1, "done calls")
    equal(r.result.outcome, "could not check", "outcome")
    equal(r.result.queryFailed, true, "query failed")
    equal(ownSends(c), 1, "our browses: the queued name not sent, no retry")
end)

test("check: an item whose data fails to load does not hold the check for 2 s and is not looked up", function()
    local c = checkClient({ { 501, "Willow Boots", BOE }, { 502, "Ivy Boots", BOE, "fail" } })
    local start = c.now
    local r = runCheck(c, 0.5)
    equal(#c.ah.sends, 1, "browses within 0.5 s")
    check(c.ah.sends[1].at - start < 0.2, "sent after the failed load, at " .. (c.ah.sends[1].at - start))
    equal(r.calls, 1, "done calls")
    -- TC-32: an item that failed to load is not on this server, not "could not check"
    equal(r.result.outcome, "not for sale", "outcome")
    equal(r.result.leftOut, 0, "items left out")
    -- another item still loading: the check waits for it
    c = checkClient({ { 501, "Willow Boots", BOE }, { 502, "Ivy Boots", BOE, "fail" }, { 503, "Oak Boots", BOE, 1 } })
    start = c.now
    runCheck(c, 0.5)
    equal(#c.ah.sends, 0, "browses while an item still loads")
    c.advance(1)
    check(c.ah.sends[1], "a browse once it loaded")
    equal(c.ah.sends[1].at - start, 1, "the first browse when the last item loaded")
end)

---------------------------------------------------------------- Browser state

-- A client with the state's change notifications counted.
local function bootState(opts)
    local c = boot(opts)
    c.changes = 0
    TC.BrowserState.SetListener(function() c.changes = c.changes + 1 end)
    return c
end
-- The name of the slot the view's slot row marks (layout B has no slot title).
local function chosenSlot(v)
    for _, slot in ipairs(v.slots) do
        if slot.selected then return slot.name end
    end
end

test("start state: All, Head, Filter Not collected, page 1", function()
    local c = bootState()
    TC.BrowserState.Refresh()
    local v = TC.BrowserState.View()
    equal(v.mode, "All", "mode")
    equal(chosenSlot(v), "Head", "slot title")
    equal(v.filter, "Not collected", "Filter")
    equal(v.page, 1, "page")
    equal(v.status, "Click an appearance to check the auction house.", "status line")
    equal(#v.tiles, 24, "tiles on page 1")
    for _, tile in ipairs(v.tiles) do
        check(tile.collected == false, "no collected tile under Not collected")
        equal(tile.strip, "not checked", "strip state")
    end
    equal(c.changes, 1, "notifications for the first Refresh")
end)

test("each Filter value narrows as specified and returns to page 1", function()
    local c = bootState()
    TC.BrowserState.Refresh()
    TC.BrowserState.NextPage()
    local v = TC.BrowserState.View()
    equal(v.page, 2, "page after NextPage")
    equal(v.count, "365 of 370 appearances", "count under Not collected")
    equal(v.pageText, "Page 2 / 16", "page text under Not collected")

    TC.BrowserState.SetFilter("Collected")
    v = TC.BrowserState.View()
    equal(v.page, 1, "page after the Filter changed")
    equal(v.count, "5 of 370 appearances", "count under Collected")
    equal(#v.tiles, 5, "tiles under Collected")
    for _, tile in ipairs(v.tiles) do check(tile.collected == true, "every tile collected under Collected") end
    equal(v.paging, false, "paging with one page")

    TC.BrowserState.NextPage()
    TC.BrowserState.SetFilter("All")
    v = TC.BrowserState.View()
    equal(v.page, 1, "page after the Filter changed to All")
    equal(v.count, "370 appearances", "count under All")
    equal(v.pageText, "Page 1 / 16", "page text under All (370 / 24 rounds up)")
    equal(v.paging, true, "paging with 16 pages")
    -- Collections' order puts the collected ones first
    for i = 1, 5 do check(v.tiles[i].collected, "tile " .. i .. " collected and first") end
    check(not v.tiles[6].collected, "tile 6 not collected")
end)

test("24 tiles a page, the last page holds the rest, and paging stops at both ends", function()
    local c = bootState()
    TC.BrowserState.Refresh()
    local before = c.changes
    TC.BrowserState.PreviousPage()
    equal(TC.BrowserState.View().page, 1, "previous on page 1")
    equal(c.changes, before, "no notification for previous on page 1")
    for _ = 1, 20 do TC.BrowserState.NextPage() end
    local v = TC.BrowserState.View()
    equal(v.page, 16, "next stops on the last page")
    equal(#v.tiles, 365 - 15 * 24, "tiles on the last page")
    equal(c.changes, before + 15, "one notification per page actually turned")
    TC.BrowserState.PreviousPage()
    equal(TC.BrowserState.View().page, 15, "previous from the last page")
end)

test("count text is singular for one appearance", function()
    bootState({ appearances = { { id = 1, uiOrder = 1, sources = { 11 }, classes = { [9] = true } } } })
    TC.BrowserState.Refresh()
    TC.BrowserState.SetFilter("All")
    equal(TC.BrowserState.View().count, "1 appearance", "count of one")
    TC.BrowserState.SetFilter("Collected")
    equal(TC.BrowserState.View().count, "0 of 1 appearance", "count of none of one")
end)

test("Filter Collected with nothing collected gives the Filter's empty state", function()
    bootState({ appearances = Fake.appearances(30, 0) })
    TC.BrowserState.Refresh()
    TC.BrowserState.SetFilter("Collected")
    local v = TC.BrowserState.View()
    equal(#v.tiles, 0, "tiles")
    equal(v.count, "0 of 30 appearances", "count")
    equal(v.paging, false, "paging")
    check(v.empty, "an empty state")
    equal(v.empty.title, "No matches", "empty title")
    equal(v.empty.text, "No collected head appearances for Warlock.", "empty text")
    equal(v.empty.button, "Show all", "empty button")
    TC.BrowserState.SetFilter("All")
    equal(TC.BrowserState.View().empty, nil, "Show all (Filter All) ends the empty state")
end)

test("Filter Not collected with every appearance collected gives that empty state", function()
    bootState({ appearances = Fake.appearances(30, 30) })
    TC.BrowserState.Refresh()
    local v = TC.BrowserState.View()
    equal(#v.tiles, 0, "tiles")
    equal(v.count, "0 of 30 appearances", "count")
    equal(v.empty.title, "No matches", "empty title")
    equal(v.empty.text, "Every head appearance for Warlock is collected.", "empty text")
    equal(v.empty.button, "Show all", "empty button")
end)

-- No tiles and nothing that claims the slot is empty.
local function unavailable(v, what)
    equal(#v.tiles, 0, what .. ": tiles")
    equal(v.count, "", what .. ": count text")
    equal(v.empty, nil, what .. ": empty state")
    equal(v.paging, false, what .. ": paging")
    equal(v.pageText, "", what .. ": page text")
    equal(chosenSlot(v), "Head", what .. ": slot title")
end

test("a list that could not be read is shown as unavailable, not as an empty slot", function()
    for _, opts in ipairs({ { noTransmog = true }, { noList = true }, { listNil = true }, { appearances = {} },
        { listRaises = true } }) do
        bootState(opts)
        local ok, err = pcall(TC.BrowserState.Refresh)
        check(ok, "no error from Refresh with " .. next(opts) .. ": " .. tostring(err))
        unavailable(TC.BrowserState.View(), next(opts))
    end
end)

test("an empty first read is not kept: the next Refresh reads again", function()
    local c = bootState({ listEmpty = 1 })
    TC.BrowserState.Refresh()
    unavailable(TC.BrowserState.View(), "after the empty read")
    TC.BrowserState.Refresh()
    equal(c.listCalls, 2, "list reads")
    equal(TC.BrowserState.View().count, "365 of 370 appearances", "count after the second read")
end)

test("a raised error from the appearance source is no list yet, and a later read fills it", function()
    local c = bootState({ listRaises = 1 })
    local ok, err = pcall(TC.BrowserState.Refresh)
    check(ok, "no error from Refresh: " .. tostring(err))
    unavailable(TC.BrowserState.View(), "after the failed read")
    TC.BrowserState.Refresh()
    equal(c.listCalls, 2, "list reads")
    equal(#TC.BrowserState.View().tiles, 24, "tiles after the later read")
end)

test("a Refresh that arrives during a Refresh reads and notifies nothing more", function()
    local c = bootState({ classFilter = 8 })
    local inner = 0
    local set = C_TransmogCollection.SetClassFilter
    C_TransmogCollection.SetClassFilter = function(id)
        set(id)
        inner = inner + 1
        TC.BrowserState.Refresh()
    end
    TC.BrowserState.Refresh()
    equal(inner, 2, "class filter set and restored")
    equal(c.listCalls, 1, "list reads")
    equal(c.changes, 1, "notifications")
    equal(c.collections.classFilter, 8, "class filter after Refresh")
    TC.BrowserState.Refresh()
    c.collectedSources[1370 * 10 + 1] = true
    TC.BrowserState.Refresh()
    equal(c.changes, 2, "a later Refresh still works")
end)

test("View answers the Filter text, the arrows and the empty-state action", function()
    bootState({ appearances = Fake.appearances(60, 0) })
    TC.BrowserState.Refresh()
    local v = TC.BrowserState.View()
    equal(v.filter, "Not collected", "Filter text")
    equal(v.previousEnabled, false, "previous on page 1")
    equal(v.nextEnabled, true, "next on page 1 of 3")
    TC.BrowserState.NextPage()
    TC.BrowserState.NextPage()
    v = TC.BrowserState.View()
    equal(v.previousEnabled, true, "previous on page 3")
    equal(v.nextEnabled, false, "next on the last page")
    TC.BrowserState.SetFilter("Collected")
    v = TC.BrowserState.View()
    equal(v.filter, "Collected", "Filter text after the change")
    equal(type(v.empty.action), "function", "empty-state action")
    v.empty.action()
    equal(TC.BrowserState.View().filter, "All", "Filter after the empty-state action")
end)

test("the change notification fires once per change and not without one", function()
    local c = bootState()
    TC.BrowserState.Refresh()
    equal(c.changes, 1, "first Refresh")
    TC.BrowserState.Refresh()
    equal(c.changes, 1, "Refresh with nothing changed")
    TC.BrowserState.SetFilter("Not collected")
    equal(c.changes, 1, "Filter set to its own value")
    TC.BrowserState.SetFilter("Collected")
    equal(c.changes, 2, "Filter changed")
    -- an appearance becomes collected
    c.collectedSources[1370 * 10 + 1] = true
    TC.BrowserState.Refresh()
    equal(c.changes, 3, "Refresh after a collection change")
    equal(TC.BrowserState.View().count, "6 of 370 appearances", "count after the collection change")
    TC.BrowserState.Reset()
    equal(c.changes, 4, "Reset")
    local v = TC.BrowserState.View()
    equal(v.filter, "Not collected", "Filter after Reset")
    equal(#v.tiles, 0, "no tiles until the next Refresh")
end)

test("the state reads the list once per visit and recomputes collected on Refresh", function()
    local c = bootState()
    TC.BrowserState.Refresh()
    TC.BrowserState.Refresh()
    equal(c.listCalls, 1, "list reads in one visit")
    TC.BrowserState.Reset()
    TC.BrowserState.Refresh()
    equal(c.listCalls, 2, "list reads after a new visit")
end)

---------------------------------------------------------------- Browser state: checks

-- The default 370 Head appearances; every item is a loaded bind-on-equip
-- green named "Item <itemID>", one item per source (three per appearance).
-- prices puts listings up: { [tile index on page 1] = { price, ... } }, one
-- listing per price on the appearance's first item, suffix 1, 2, ...
local function checkState(prices, opts)
    local c = bootState(opts)
    TC.BrowserState.Refresh()
    local tiles = TC.BrowserState.View().tiles
    for index, list in pairs(prices or {}) do
        local itemID = tiles[index].appearance.id * 10 + 1
        for n, price in ipairs(list) do
            c.ah.listings[#c.ah.listings + 1] = listing("Item " .. itemID, itemID, price,
                { itemSuffix = n, totalQuantity = n })
        end
    end
    return c, tiles
end
local function tileOf(id)
    for _, tile in ipairs(TC.BrowserState.View().tiles) do
        if tile.appearance.id == id then return tile end
    end
end
local function click(tile) TC.BrowserState.ClickTile(tile.appearance) end
-- A click on an unchecked tile checks it; once the check ends, a second click
-- opens the kept result.
local function openChecked(c, tile)
    click(tile)
    c.advance(10)
    click(tile)
end

test("state: a click on a tile with nothing kept opens no flyout and starts one check; the strip reads, then prices", function()
    local c, tiles = checkState({ [1] = { 500 } })
    click(tiles[1])
    local v = TC.BrowserState.View()
    equal(v.list, nil, "no flyout")
    equal(tileOf(tiles[1].appearance.id).strip, "bar", "the strip shows the reading state")
    equal(tileOf(tiles[1].appearance.id).open, false, "no gold border while it checks")
    equal(#c.ah.sends, 1, "browses sent at once (one in flight)")
    c.advance(5)
    equal(#c.ah.sends, 3, "browses: one per item name")
    v = TC.BrowserState.View()
    equal(v.list, nil, "no flyout after the check")
    equal(v.tiles[1].strip, "price", "the strip prices")
    equal(v.tiles[1].price, "5s", "the price")
    click(tiles[1])
    v = TC.BrowserState.View()
    equal(v.list.state, "found", "the second click opens the list")
    equal(v.list.title, "1 item variant, cheapest first", "found title")
    equal(v.list.rows[1].forSale, "x1", "for sale text")
    equal(v.list.typeText, "Head, cloth", "head type")
    equal(#c.ah.sends, 3, "opening a kept result sends nothing")
end)

test("state: five unchecked tiles clicked in a row open no flyout and all get results, one check at a time", function()
    local c, tiles = checkState({ [1] = { 500 }, [3] = { 900 } })
    for i = 1, 5 do
        click(tiles[i])
        equal(TC.BrowserState.View().list, nil, "no flyout after click " .. i)
    end
    equal(#c.ah.sends, 1, "one browse in flight")
    equal(tileOf(tiles[5].appearance.id).strip, "bar", "a waiting tile reads too")
    c.advance(30)
    local v = TC.BrowserState.View()
    equal(v.list, nil, "no flyout at the end")
    for i = 1, 5 do check(v.tiles[i].strip == "price" or v.tiles[i].strip == "not for sale", "tile " .. i .. " has a result") end
    equal(v.tiles[1].price, "5s", "tile 1")
    equal(v.tiles[3].price, "9s", "tile 3")
    equal(v.tiles[2].strip, "not for sale", "tile 2")
end)

test("state: a click on a tile whose check runs does nothing", function()
    local c, tiles = checkState({ [1] = { 500 } })
    click(tiles[1])
    click(tiles[1])
    equal(TC.BrowserState.View().list, nil, "no flyout")
    c.advance(5)
    equal(#c.ah.sends, 3, "one check, not two")
end)

test("state: a click on a kept result opens the flyout (gold border only then); closes it, moves it, or closes it for a check", function()
    local c, tiles = checkState({ [1] = { 500 }, [2] = { 600 } })
    click(tiles[1])
    click(tiles[2])
    c.advance(10)
    local sends = #c.ah.sends
    click(tiles[1])
    local v = TC.BrowserState.View()
    equal(v.list.appearance.id, tiles[1].appearance.id, "opened on a kept result")
    check(v.tiles[1].open and not v.tiles[2].open, "the border on the open tile only")
    equal(#c.ah.sends, sends, "sends nothing")
    click(tiles[2])
    equal(TC.BrowserState.View().list.appearance.id, tiles[2].appearance.id, "moved to another kept tile")
    click(tiles[3])
    v = TC.BrowserState.View()
    equal(v.list, nil, "a click on an unchecked tile closes the flyout")
    equal(v.tiles[3].strip, "bar", "and starts its check")
    check(not v.tiles[3].open and not v.tiles[2].open, "no gold border anywhere")
    equal(#c.ah.sends, sends + 1, "its check went out")
    click(tiles[3])
    equal(TC.BrowserState.View().list, nil, "a click while it checks does nothing")
    c.advance(10)
    click(tiles[2])
    check(TC.BrowserState.View().list, "open on tile 2")
    click(tiles[2])
    equal(TC.BrowserState.View().list, nil, "a click on the open tile closes it")
end)

test("state: could not check shows No answer on the strip, opens nothing, and the next click checks again", function()
    local c, tiles = checkState({ [1] = { 500 } })
    c.ah.fail = true
    click(tiles[1])
    c.advance(10)
    local v = TC.BrowserState.View()
    equal(v.list, nil, "no flyout opens by itself")
    equal(v.tiles[1].strip, "no answer", "the strip")
    equal(v.tiles[1].price, "No answer", "the strip's text")
    c.ah.fail = false
    local sends = #c.ah.sends
    click(tiles[1])
    v = TC.BrowserState.View()
    equal(v.list, nil, "no flyout")
    equal(v.tiles[1].strip, "bar", "reading again")
    check(#c.ah.sends > sends, "the check went out again")
    c.advance(10)
    v = TC.BrowserState.View()
    equal(v.tiles[1].price, "5s", "a result replaces No answer")
end)

test("state: after Price this slot every click opens the flyout and sends nothing", function()
    local c = bootState()
    TC.BrowserState.Refresh()
    local listed = TC.BrowserState.View().tiles[3].appearance.id * 10 + 1
    c.ah.listings = { listing("Item " .. listed, listed, 700) }
    TC.BrowserState.View().statusAction()
    c.advance(10)
    local sends = #c.ah.sends
    for i = 1, 3 do
        click(TC.BrowserState.View().tiles[i])
        equal(TC.BrowserState.View().list.appearance.id, TC.BrowserState.View().tiles[i].appearance.id, "tile " .. i .. " opens")
    end
    equal(#c.ah.sends, sends, "nothing sent")
    TC.BrowserState.SelectMode("For sale")
    click(TC.BrowserState.View().tiles[1])
    equal(TC.BrowserState.View().list.appearance.id, TC.BrowserState.View().tiles[1].appearance.id, "the sweep view opens too")
    equal(#c.ah.sends, sends, "nothing sent in the sweep view")
end)

test("state: a kept result is shown again without a new check", function()
    local c, tiles = checkState({ [1] = { 500 } })
    click(tiles[1])
    c.advance(5)
    click(tiles[2])
    c.advance(5)
    local sends = #c.ah.sends
    click(tiles[1])
    c.advance(5)
    equal(#c.ah.sends, sends, "browses for a tile with a kept result")
    local v = TC.BrowserState.View()
    equal(v.list.state, "found", "the kept result in the list")
    equal(v.list.appearance.id, tiles[1].appearance.id, "the list on the clicked tile")
    equal(v.tiles[2].strip, "not for sale", "the other tile's strip")
    equal(v.tiles[2].price, "Not for sale", "the other tile's strip text")
end)

test("state: money text on the tile and in the list, with zero parts left out", function()
    local c, tiles = checkState({ [1] = { 4876312 }, [2] = { 10005, 500000, 4876312 }, [3] = { 1000000 }, [4] = { 880075 },
        [5] = { 0 }, [6] = { 1000050 } })
    for i = 1, 6 do click(tiles[i]); c.advance(5) end
    local v = TC.BrowserState.View()
    equal(v.tiles[5].price, "Not for sale", "a row at 0 is not for sale")
    equal(v.tiles[6].price, "100g", "100g 0s 50c on a tile")
    equal(v.tiles[1].price, "487g 63s", "487g 63s 12c on a tile")
    equal(v.tiles[2].price, "1g 5c", "1g 0s 5c on a tile")
    equal(v.tiles[3].price, "100g", "exactly 100 gold on a tile")
    equal(v.tiles[4].price, "88g 75c", "88g 0s 75c on a tile keeps copper below 100 gold")
    click(tiles[2])
    v = TC.BrowserState.View()
    equal(v.list.title, "3 item variants, cheapest first", "found title")
    equal(v.list.rows[1].price, "1g 5c", "row 1")
    equal(v.list.rows[2].price, "50g", "row 2")
    equal(v.list.rows[3].price, "487g 63s 12c", "487g 63s 12c in full in the list")
    equal(v.list.rows[3].forSale, "x3", "row 3 quantity")
    local parts = v.tiles[1].money
    equal(#parts, 2, "coin parts on the tile")
    equal(parts[1].amount .. parts[1].coin .. parts[2].amount .. parts[2].coin, "487gold63silver", "coin parts")
end)

test("state: could not check leaves the strip as it was and keeps the error text", function()
    local c, tiles = checkState({ [1] = { 500 } })
    click(tiles[1])
    c.advance(5)
    click(tiles[1])
    c.ah.silent = true
    TC.BrowserState.CheckAgain()
    c.advance(20)
    local v = TC.BrowserState.View()
    equal(v.list.state, "could not check", "list state")
    equal(v.list.title, "The auction house did not answer.", "list text")
    equal(v.list.foot.button, "Check again", "Check again kept")
    equal(v.tiles[1].price, "5s", "strip kept from the earlier check")
    check(tostring(TC.BrowserState.lastError):find("no answer"), "last error, got " .. tostring(TC.BrowserState.lastError))
    click(tiles[2])
    c.advance(20)
    equal(TC.BrowserState.View().tiles[2].strip, "no answer", "a failed first check keeps nothing: the strip says No answer")
end)

test("state: a first check whose items never load keeps nothing, opens nothing and sends nothing", function()
    local c, tiles = checkState(nil, { items = { [10061] = { load = "never" }, [10062] = { load = "never" },
        [10063] = { load = "never" } } })
    check(tiles[1].appearance.id == 1006, "fixture: tile 1 is appearance 1006")
    click(tiles[1])
    c.advance(5)
    local v = TC.BrowserState.View()
    equal(v.list, nil, "no flyout for a check that kept nothing")
    equal(v.tiles[1].strip, "no answer", "the strip says No answer")
    equal(#c.ah.sends, 0, "browses without names")
end)

test("state: found with items left out says so in the foot; not for sale lists the names", function()
    local c, tiles = checkState({ [1] = { 700 } }, { items = { [10062] = { load = "never" } } })
    click(tiles[1])
    c.advance(5)
    click(tiles[1])
    local v = TC.BrowserState.View()
    equal(v.list.state, "found", "list state")
    equal(v.list.foot.note, "Could not check 1 of 3 items.", "foot note")
    click(tiles[2])
    c.advance(5)
    click(tiles[2])
    v = TC.BrowserState.View()
    equal(v.list.state, "not for sale", "list state")
    equal(v.list.title, "Not for sale right now", "title")
    equal(v.list.text, "No item with this appearance is on the auction house.", "text")
    equal(#v.list.rows, 3, "names of the items looked up")
end)

test("state: a click on the open tile closes it and reads nothing; a click on another tile moves the list", function()
    local c, tiles = checkState()
    click(tiles[1])
    click(tiles[2])
    c.advance(10)
    click(tiles[1])
    local changes, sends = c.changes, #c.ah.sends
    click(tiles[1])
    equal(c.changes, changes + 1, "one notification for a click on the open tile")
    equal(TC.BrowserState.View().list, nil, "the flyout closed")
    equal(#c.ah.sends, sends, "browses for a click on the open tile")
    click(tiles[1])
    click(tiles[2])
    local v = TC.BrowserState.View()
    equal(v.list.appearance.id, tiles[2].appearance.id, "the list moved")
    check(v.tiles[2].open and not v.tiles[1].open, "the open marker moved")
end)

test("state: Check again reads again and replaces the result", function()
    local c, tiles = checkState({ [1] = { 500 } })
    click(tiles[1])
    c.advance(5)
    click(tiles[1])
    c.ah.listings[1].minPrice = 900
    local sends = #c.ah.sends
    TC.BrowserState.CheckAgain()
    equal(TC.BrowserState.View().list.state, "checking", "list state during Check again")
    c.advance(5)
    equal(#c.ah.sends, sends + 3, "browses for Check again")
    equal(TC.BrowserState.View().tiles[1].price, "9s", "strip after Check again")
end)

test("state: the list closes when the Filter removes its appearance", function()
    local c, tiles = checkState()
    click(tiles[1])
    c.advance(5)
    click(tiles[1])
    TC.BrowserState.SetFilter("All")
    check(TC.BrowserState.View().list, "still open: All keeps it")
    TC.BrowserState.SetFilter("Collected")
    equal(TC.BrowserState.View().list, nil, "closed by Collected")
    -- a collection change that removes it from Not collected
    TC.BrowserState.SetFilter("Not collected")
    click(TC.BrowserState.View().tiles[1])
    local id = TC.BrowserState.View().list.appearance.id
    c.collectedSources[id * 10 + 1] = true
    TC.BrowserState.Refresh()
    equal(TC.BrowserState.View().list, nil, "closed when it became collected")
end)

test("state: the foot's two age forms", function()
    local c, tiles = checkState({ [1] = { 500 } })
    click(tiles[1])
    c.advance(5)
    click(tiles[1])
    equal(TC.BrowserState.View().list.foot.age, "Checked just now", "age under a minute")
    c.advance(4 * 60)
    equal(TC.BrowserState.View().list.foot.age, "Checked 4 min ago", "age after four minutes")
end)

test("state: leaving the tab during a check discards the unfinished result and keeps finished ones", function()
    local c, tiles = checkState({ [1] = { 500 }, [2] = { 600 } })
    click(tiles[1])
    c.advance(5)
    click(tiles[2])
    c.advance(0.3)
    TC.BrowserState.Leave()
    local sends = #c.ah.sends
    c.advance(20)
    equal(#c.ah.sends, sends, "browses after leaving")
    local v = TC.BrowserState.View()
    equal(v.tiles[1].price, "5s", "finished result kept")
    equal(v.tiles[2].strip, "not checked", "unfinished result discarded")
    equal(v.list, nil, "no flyout")
    click(tiles[1])
    equal(#c.ah.sends, sends, "no browse for the kept tile after coming back")
end)

test("state: closing the auction window discards everything and cancels the queue", function()
    local c, tiles = checkState({ [1] = { 500 } })
    click(tiles[1])
    c.advance(5)
    click(tiles[2])
    c.advance(0.3)
    local sends = #c.ah.sends
    c.fire("AUCTION_HOUSE_CLOSED")
    TC.BrowserState.Reset()
    c.advance(20)
    equal(#c.ah.sends, sends, "browses after closing")
    TC.BrowserState.Refresh()
    local v = TC.BrowserState.View()
    equal(v.list, nil, "no list")
    for _, tile in ipairs(v.tiles) do equal(tile.strip, "not checked", "strip after closing") end
end)

test("state: the change notification fires once per change", function()
    local c, tiles = checkState({ [1] = { 500 } })
    local before = c.changes
    click(tiles[1])
    equal(c.changes, before + 1, "one notification for the click")
    c.advance(5)
    equal(c.changes, before + 2, "one more when the result arrives")
    click(tiles[1])
    equal(c.changes, before + 3, "one for opening it")
    TC.BrowserState.CheckAgain()
    equal(c.changes, before + 4, "one for Check again")
    c.advance(5)
    equal(c.changes, before + 5, "one for its result")
    TC.BrowserState.CloseList()
    equal(c.changes, before + 6, "one for closing")
    TC.BrowserState.CloseList()
    TC.BrowserState.CheckAgain()
    equal(c.changes, before + 6, "none for closing a closed list or Check again without one")
end)

test("state: a second click while a check runs waits behind it; both results are kept", function()
    local c, tiles = checkState({ [1] = { 500 }, [2] = { 600 } })
    click(tiles[1])
    click(tiles[2])
    equal(TC.BrowserState.View().list, nil, "no flyout for either")
    equal(TC.BrowserState.View().tiles[2].strip, "bar", "the second tile waits and reads")
    c.advance(0.9)
    -- tile 1's three names go first
    local first = tiles[1].appearance.id * 10
    for i = 1, 3 do equal(c.ah.sends[i].query.searchString, "Item " .. (first + i), "send " .. i) end
    c.advance(10)
    equal(#c.ah.sends, 6, "browses")
    local v = TC.BrowserState.View()
    equal(v.tiles[1].price, "5s", "first result kept")
    equal(v.tiles[2].price, "6s", "second result kept")
end)

test("state: the last error of a failed list read is kept", function()
    bootState({ listRaises = 1 })
    TC.BrowserState.Refresh()
    check(tostring(TC.BrowserState.lastError):find("GetCategoryAppearances failed"),
        "last error, got " .. tostring(TC.BrowserState.lastError))
end)

test("state: an item whose row sits beyond page 5 could not check, and the tile's strip stays as it was", function()
    local c, tiles = checkState({ [1] = { 500 } })
    click(tiles[1])
    c.advance(5)
    equal(TC.BrowserState.View().tiles[1].price, "5s", "strip after the first check")
    click(tiles[1])
    local itemID = tiles[1].appearance.id * 10 + 1
    c.ah.listings = {}
    for i = 1, 6 do c.ah.listings[i] = listing("Item " .. itemID .. " filler " .. i, 1, i) end
    c.ah.listings[7] = listing("Item " .. itemID, itemID, 900)
    c.ah.pageSize = 1
    TC.BrowserState.CheckAgain()
    c.advance(60)
    local v = TC.BrowserState.View()
    equal(v.list.state, "could not check", "list state")
    equal(v.list.title, "Could not check 1 of 3 items.", "list text")
    equal(v.tiles[1].price, "5s", "strip kept")
    -- a first check cut off the same way leaves the strip empty
    c, tiles = checkState()
    itemID = tiles[1].appearance.id * 10 + 1
    for i = 1, 6 do c.ah.listings[i] = listing("Item " .. itemID .. " filler " .. i, 1, i) end
    c.ah.listings[7] = listing("Item " .. itemID, itemID, 900)
    c.ah.pageSize = 1
    click(tiles[1])
    c.advance(60)
    v = TC.BrowserState.View()
    equal(v.list, nil, "no flyout for a first check cut off")
    equal(v.tiles[1].strip, "no answer", "strip of a first check")
end)

test("state: a listener that raises on one notification still lets the waiting check run", function()
    local c, tiles = checkState({ [1] = { 500 }, [2] = { 600 } })
    click(tiles[1])
    click(tiles[2])
    local raised = false
    TC.BrowserState.SetListener(function()
        if not raised then
            raised = true
            error("draw failed")
        end
    end)
    for _ = 1, 20 do pcall(c.advance, 1) end
    check(raised, "the listener raised")
    equal(#c.ah.sends, 6, "browses of both checks")
    local v = TC.BrowserState.View()
    equal(v.tiles[1].price, "5s", "first result kept")
    equal(v.tiles[2].price, "6s", "second result kept")
    equal(#c.errors, 1, "errors reported")
end)

test("state: a variant's name, once known, is not asked for again; an unknown one once, and once more after its event", function()
    local c, tiles = checkState({ [1] = { 500, 700 } })
    local itemID = tiles[1].appearance.id * 10 + 1
    c.ah.keyNames[itemID .. ":1"] = "Item of the Owl"
    click(tiles[1])
    c.advance(5)
    click(tiles[1])
    local v = TC.BrowserState.View()
    equal(v.list.rows[1].name, "Item of the Owl", "the variant's name")
    equal(v.list.rows[2].name, "Item " .. itemID, "the item's name while the variant's is unknown")
    local calls = c.ah.keyInfoCalls
    TC.BrowserState.View()
    TC.BrowserState.View()
    equal(c.ah.keyInfoCalls, calls, "GetItemKeyInfo calls for two Views: none, each key was asked once")
    TC.BrowserState.KeyInfoReceived(itemID)
    TC.BrowserState.View()
    equal(c.ah.keyInfoCalls, calls + 1, "the one more read after the item's event, for the unknown key")
    TC.BrowserState.View()
    TC.BrowserState.KeyInfoReceived(itemID)
    TC.BrowserState.View()
    equal(c.ah.keyInfoCalls, calls + 1, "no third read of that key")
end)

test("state: a Check again stopped by leaving the tab keeps the result, the head and Check again", function()
    local c, tiles = checkState({ [1] = { 500 } })
    click(tiles[1])
    c.advance(5)
    click(tiles[1])
    TC.BrowserState.CheckAgain()
    c.advance(0.1)
    TC.BrowserState.Leave()
    local sends = #c.ah.sends
    local v = TC.BrowserState.View()
    local l = v.list
    equal(l.state, "found", "the kept result stays")
    equal(l.typeText, "Head, cloth", "head type")
    equal(l.collected, false, "head: not collected")
    equal(#l.rows, 1, "its row")
    equal(l.foot.button, "Check again", "Check again")
    equal(l.foot.enabled, true, "on again")
    c.advance(20)
    TC.BrowserState.Refresh()
    TC.BrowserState.View()
    equal(#c.ah.sends, sends, "browses after coming back")
    equal(v.tiles[1].strip, "price", "strip")
end)

---------------------------------------------------------------- Browser state: scans and For sale

-- The default 370 Head appearances (1001 to 1005 collected); prices puts one
-- listing of item <id>*10+1 up per appearance id. After Refresh.
local function scanState(prices, opts)
    local c = bootState(opts)
    TC.BrowserState.Refresh()
    for id, price in pairs(prices or {}) do
        c.ah.listings[#c.ah.listings + 1] = listing("Item " .. (id * 10 + 1), id * 10 + 1, price)
    end
    table.sort(c.ah.listings, function(a, b) return a.minPrice < b.minPrice end)
    return c
end
local function tileIDs(v)
    local out = {}
    for i, tile in ipairs(v.tiles) do out[i] = tile.appearance and tile.appearance.id or "placeholder" end
    return table.concat(out, ",")
end
local SAMPLE = { [1010] = 500, [1020] = 300, [1030] = 300, [1001] = 100 }

test("state: For sale on an unscanned slot starts one scan; selecting it again starts none", function()
    local c = scanState(SAMPLE)
    TC.BrowserState.SelectMode("For sale")
    equal(#c.ah.sends, 1, "browses on selecting For sale")
    TC.BrowserState.SelectMode("All")
    TC.BrowserState.SelectMode("For sale")
    equal(#c.ah.sends, 1, "browses on selecting For sale again while the scan runs")
    c.advance(10)
    TC.BrowserState.SelectMode("All")
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    equal(#c.ah.sends, 1, "browses on selecting For sale after the scan")
end)

test("state: For sale is All narrowed to not collected and for sale, cheapest first, ties by id, with the count text", function()
    local c = scanState(SAMPLE)
    c.ah.listings[#c.ah.listings + 1] = listing("Unknown", 999, 1)
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    local v = TC.BrowserState.View()
    equal(v.mode, "For sale", "mode")
    equal(tileIDs(v), "1020,1030,1010", "tiles")
    equal(v.tiles[1].price, "3s", "price on the first tile")
    equal(v.count, "3 of 370 appearances", "count text")
    equal(v.empty, nil, "no empty state")
end)

test("state: in For sale the Filter shows Not collected and is fixed; All gets the player's choice back", function()
    local c = scanState(SAMPLE)
    TC.BrowserState.SetFilter("All")
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    local v = TC.BrowserState.View()
    equal(v.filter, "Not collected", "Filter text in For sale")
    equal(v.filterFixed, true, "Filter fixed in For sale")
    TC.BrowserState.SetFilter("Collected")
    equal(TC.BrowserState.View().filter, "Not collected", "Filter after a change in For sale")
    equal(tileIDs(TC.BrowserState.View()), "1020,1030,1010", "tiles after a change in For sale")
    TC.BrowserState.SelectMode("All")
    v = TC.BrowserState.View()
    equal(v.filter, "All", "Filter back in All")
    equal(v.filterFixed, false, "Filter free in All")
end)

test("state: while the first scan runs, the tiles found so far are followed by placeholders to fill the page", function()
    local c = scanState({ [1010] = 500, [1020] = 300, [1030] = 700 })
    c.ah.pageSize = 2
    TC.BrowserState.SelectMode("For sale")
    c.advance(0.26)
    local v = TC.BrowserState.View()
    equal(#v.tiles, 24, "tiles on the page")
    equal(tileIDs(v):sub(1, 21), "1020,1010,placeholder", "found tiles first, then placeholders")
    equal(v.tiles[3].strip, "bar", "a placeholder's strip")
    equal(v.tiles[1].strip, "price", "a found tile's strip")
    equal(v.count, "2 of 370 appearances", "count while scanning")
    c.advance(10)
    v = TC.BrowserState.View()
    equal(tileIDs(v), "1020,1010,1030", "tiles after the scan, no placeholder")
end)

test("state: after a scan every tile in All has a price or Not for sale, collected ones too", function()
    local c = scanState(SAMPLE)
    TC.BrowserState.SetFilter("All")
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    TC.BrowserState.SelectMode("All")
    local v = TC.BrowserState.View()
    for i, tile in ipairs(v.tiles) do check(tile.strip ~= "not checked", "tile " .. i .. " has a strip state") end
    local collectedTile = tileOf(1001)
    equal(collectedTile.collected, true, "1001 collected")
    equal(collectedTile.price, "1s", "the collected tile's price")
    equal(tileOf(1002).price, "Not for sale", "a tile the scan did not find")
    equal(v.status, "Scanned just now", "status line in All after the scan")
    equal(v.statusButton, "Scan again", "status button in All after the scan")
end)

test("state: a scan replaces the slot's earlier check results; a later check replaces that one appearance's", function()
    local c = scanState({ [1010] = 500 })
    TC.BrowserState.SetFilter("All")
    TC.BrowserState.ClickTile(tileOf(1010).appearance)
    c.advance(10)
    equal(tileOf(1010).price, "5s", "the check's price")
    c.ah.listings[1].minPrice = 700
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    TC.BrowserState.SelectMode("All")
    equal(tileOf(1010).price, "7s", "the scan's price replaces the check's")
    -- a toggle change closed the flyout; opened again it shows the scan
    TC.BrowserState.ClickTile(tileOf(1010).appearance)
    equal(TC.BrowserState.View().list.foot.age, "Scanned just now", "the open list shows the scan")
    c.ah.listings[1].minPrice = 900
    TC.BrowserState.CheckAgain()
    c.advance(10)
    equal(tileOf(1010).price, "9s", "the later check replaces the scan's price")
    equal(tileOf(1002).price, "Not for sale", "the scan's result of the others stays")
end)

test("state: a click on a tile after a scan opens the list from the scan's rows and sends nothing", function()
    local c = scanState(SAMPLE)
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    local sends, more = #c.ah.sends, #c.ah.more
    click(TC.BrowserState.View().tiles[1])
    c.advance(5)
    equal(#c.ah.sends, sends, "browses for the click")
    equal(#c.ah.more, more, "page requests for the click")
    local l = TC.BrowserState.View().list
    equal(l.appearance.id, 1020, "the list on the clicked tile")
    equal(l.state, "found", "list state")
    equal(l.title, "1 item variant, cheapest first", "found title")
    equal(l.rows[1].price, "3s", "the row's price")
    equal(l.foot.age, "Scanned just now", "foot age")
    equal(l.foot.button, "Check again", "foot button")
    equal(l.typeText, "Head, cloth", "head type")
    c.advance(4 * 60)
    equal(TC.BrowserState.View().list.foot.age, "Scanned 4 min ago", "foot age later")
end)

test("state: a click on a tile found while the first scan runs reads nothing; the list follows the scan", function()
    local c = scanState({ [1010] = 500, [1020] = 300 })
    c.ah.listings[#c.ah.listings + 1] = listing("Item 10202", 10202, 900, { itemSuffix = 2 })
    c.ah.pageSize = 2
    TC.BrowserState.SelectMode("For sale")
    c.advance(0.26)
    click(TC.BrowserState.View().tiles[1])
    equal(#c.ah.sends, 1, "browses: the scan's only")
    equal(TC.BrowserState.View().list.title, "1 item variant, cheapest first", "rows known so far")
    c.advance(10)
    equal(#c.ah.sends, 1, "browses after the scan")
    equal(TC.BrowserState.View().list.title, "2 item variants, cheapest first", "rows after the scan")
end)

test("state: the status line in each state of 2.8, and the progress never above 95 percent before the last page", function()
    local c = scanState()
    for i = 1, 8 do c.ah.listings[i] = listing("Item " .. (10001 + i * 10), 10001 + i * 10, i * 100) end
    c.ah.pageSize = 1
    local v = TC.BrowserState.View()
    equal(v.status, "Click an appearance to check the auction house.", "All, not scanned")
    equal(v.statusButton, "Price this slot", "Price this slot in All, not scanned")
    TC.BrowserState.SelectMode("For sale")
    v = TC.BrowserState.View()
    equal(v.status, "Scanning head", "scanning")
    equal(v.statusButton, nil, "no button while scanning")
    equal(v.progress, 0, "progress before the first page")
    -- every distinct progress value while the scan runs, in order
    local seen = {}
    while TC.BrowserState.View().status == "Scanning head" do
        local p = TC.BrowserState.View().progress
        if p ~= seen[#seen] then seen[#seen + 1] = p end
        check(p <= 0.95, "progress at most 95 percent, got " .. tostring(p))
        c.advance(0.05)
    end
    equal(table.concat(seen, ","), "0,0.2,0.4,0.6,0.8,0.95", "progress by pages against an expected 5")
    c.advance(10)
    v = TC.BrowserState.View()
    equal(v.status, "Scanned just now", "scanned")
    equal(v.statusButton, "Scan again", "button after the scan")
    equal(v.progress, nil, "no progress after the scan")
    c.advance(4 * 60)
    equal(TC.BrowserState.View().status, "Scanned 4 min ago", "scanned 4 min ago")
    -- a second scan expects the first one's 8 pages
    v.statusAction()
    c.advance(0.26)
    equal(TC.BrowserState.View().progress, 1 / 8, "progress after page 1 of an expected 8")
    c.ah.silent = true
    c.advance(30)
    v = TC.BrowserState.View()
    equal(v.status, "The auction house did not answer.", "failed")
    equal(v.statusButton, "Scan again", "button after a failure")
end)

test("state: Scan again keeps the old tiles on screen until the new scan ends", function()
    local c = scanState(SAMPLE)
    c.ah.pageSize = 1
    TC.BrowserState.SelectMode("For sale")
    c.advance(30)
    c.ah.listings = { listing("Item 10401", 10401, 50), listing("Item 10101", 10101, 800) }
    TC.BrowserState.ScanAgain()
    c.advance(0.26)
    local v = TC.BrowserState.View()
    equal(v.status, "Scanning head", "status while scanning again")
    equal(tileIDs(v), "1020,1030,1010", "old tiles while scanning again")
    c.advance(30)
    v = TC.BrowserState.View()
    equal(tileIDs(v), "1040,1010", "new tiles after the scan")
    equal(v.tiles[2].price, "8s", "new price")
end)

test("state: a scan that finds nothing not collected shows Nothing for sale with a button that selects All", function()
    local c = scanState({ [1001] = 100, [1002] = 100 })
    c.collectedSources[10023] = true
    TC.BrowserState.Refresh()
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    local v = TC.BrowserState.View()
    equal(#v.tiles, 0, "tiles")
    equal(v.empty.title, "Nothing for sale", "empty title")
    equal(v.empty.text, "No head appearance you have not collected is on the auction house right now.", "empty text")
    equal(v.empty.button, "Show all appearances", "empty button")
    equal(v.count, "0 of 370 appearances", "count")
    equal(v.status, "Scanned just now", "status")
    equal(v.statusButton, "Scan again", "status button")
    v.empty.action()
    equal(TC.BrowserState.View().mode, "All", "mode after the button")
    equal(#c.ah.sends, 1, "browses")
end)

test("state: a failed scan is not kept: the failure text with Scan again, tiles found stay, For sale scans again", function()
    local c = scanState(SAMPLE)
    c.ah.pageSize = 2
    TC.BrowserState.SelectMode("For sale")
    c.advance(0.26)
    c.ah.fail = true
    c.advance(10)
    local v = TC.BrowserState.View()
    equal(v.status, "The auction house did not answer.", "status")
    equal(v.statusButton, "Scan again", "status button")
    equal(tileIDs(v), "1020", "the tile found before the failure stays")
    equal(v.empty, nil, "no empty state")
    TC.BrowserState.SelectMode("All")
    equal(tileOf(1020).strip, "not checked", "nothing kept for All")
    c.ah.fail = false
    TC.BrowserState.SelectMode("For sale")
    equal(#c.ah.sends, 2, "For sale scans again")
    c.advance(10)
    equal(TC.BrowserState.View().status, "Scanned just now", "the new scan kept")
end)

test("state: a scan of 4 pages reads no item data; a list opened from a scan result shows the names", function()
    local c = scanState({ [1010] = 500, [1020] = 300, [1030] = 700, [1040] = 900 })
    c.ah.pageSize = 1
    local info, loads = c.itemInfoCalls, #c.loadRequests
    TC.BrowserState.SelectMode("For sale")
    c.advance(30)
    equal(tileIDs(TC.BrowserState.View()), "1020,1010,1030,1040", "tiles after 4 pages")
    equal(c.itemInfoCalls - info, 0, "C_Item.GetItemInfo calls during the scan and the draw")
    equal(#c.loadRequests - loads, 0, "item data requests during the scan and the draw")
    click(TC.BrowserState.View().tiles[1])
    c.advance(1)
    local row = TC.BrowserState.View().list.rows[1]
    equal(row.name, "Item 10201", "the item's name on the row")
    equal(row.quality, 2, "the item's quality on the row")
end)

test("state: a Scan again that fails keeps the good result, its tiles and prices", function()
    local c = scanState(SAMPLE)
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    TC.BrowserState.ScanAgain()
    c.ah.fail = true
    c.advance(10)
    local v = TC.BrowserState.View()
    equal(v.status, "The auction house did not answer.", "failure text")
    equal(v.statusButton, "Scan again", "status button")
    equal(tileIDs(v), "1020,1030,1010", "tiles stay")
    equal(v.tiles[1].price, "3s", "price stays")
    TC.BrowserState.SelectMode("All")
    equal(tileOf(1010).price, "5s", "the good scan is still kept")
end)

test("state: an appearance collected after a scan leaves For sale and sends nothing", function()
    local c = scanState(SAMPLE)
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    local sends, more = #c.ah.sends, #c.ah.more
    c.collectedSources[10203] = true
    c.fire("TRANSMOG_COLLECTION_UPDATED")
    TC.BrowserState.Refresh()
    equal(tileIDs(TC.BrowserState.View()), "1030,1010", "tiles after collecting 1020")
    c.advance(10)
    equal(#c.ah.sends, sends, "browses")
    equal(#c.ah.more, more, "page requests")
end)

test("state: leaving the tab during a scan cancels it; coming back in For sale scans once", function()
    local c = scanState(SAMPLE)
    c.ah.pageSize = 1
    TC.BrowserState.SelectMode("For sale")
    c.advance(0.26)
    TC.BrowserState.Leave()
    local sends, more = #c.ah.sends, #c.ah.more
    c.advance(30)
    equal(#c.ah.sends + #c.ah.more, sends + more, "messages after leaving")
    local v = TC.BrowserState.View()
    equal(v.mode, "For sale", "the view as it was")
    TC.BrowserState.Enter()
    equal(#c.ah.sends, sends + 1, "a new scan on coming back")
    TC.BrowserState.Enter()
    equal(#c.ah.sends, sends + 1, "no second scan on entering again")
    c.advance(30)
    equal(tileIDs(TC.BrowserState.View()), "1020,1030,1010", "tiles after the new scan")
    -- in All, coming back starts nothing
    TC.BrowserState.SelectMode("All")
    TC.BrowserState.ScanAgain()
    TC.BrowserState.Leave()
    sends = #c.ah.sends
    TC.BrowserState.Enter()
    equal(#c.ah.sends, sends, "no scan on coming back in All")
end)

test("state: closing the auction window discards the scan result and the mode", function()
    local c = scanState(SAMPLE)
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    TC.BrowserState.Reset()
    TC.BrowserState.Refresh()
    local v = TC.BrowserState.View()
    equal(v.mode, "All", "mode")
    equal(v.status, "Click an appearance to check the auction house.", "status")
    for _, tile in ipairs(v.tiles) do equal(tile.strip, "not checked", "strip after closing") end
    TC.BrowserState.SelectMode("For sale")
    equal(#c.ah.sends, 2, "For sale scans again in the new visit")
    -- closing during a scan: late answers change nothing
    TC.BrowserState.Reset()
    c.advance(10)
    TC.BrowserState.Refresh()
    equal(TC.BrowserState.View().status, "Click an appearance to check the auction house.", "status after a late answer")
end)

---------------------------------------------------------------- Follow-ups of step 3

test("follow-up 1: an error inside a check's answer handler ends it as could not check, reported once, and the next check runs", function()
    local c, tiles = checkState({ [2] = { 600 } })
    local itemID = tiles[1].appearance.id * 10 + 1
    -- the second row's item level is not a number: formatting its key raises in the loop over rows
    c.ah.listings[#c.ah.listings + 1] = listing("Item " .. itemID, itemID, 100)
    c.ah.listings[#c.ah.listings + 1] = listing("Item " .. itemID, itemID, 100, { itemLevel = "broken" })
    click(tiles[1])
    local ok, err = pcall(c.advance, 30)
    check(ok, "no error out of the client: " .. tostring(err))
    local v = TC.BrowserState.View()
    equal(v.list, nil, "no flyout for the broken check")
    equal(v.tiles[1].strip, "no answer", "its strip")
    equal(#c.errors, 1, "errors reported")
    check(c.errors[1]:find("number expected", 1, true), "the error reported, got " .. tostring(c.errors[1]))
    -- a check waiting behind a broken one
    c.errors = {}
    click(tiles[1])
    click(tiles[2])
    ok, err = pcall(c.advance, 30)
    check(ok, "no error out of the client: " .. tostring(err))
    equal(#c.errors, 1, "errors reported for the second broken check")
    equal(TC.BrowserState.View().tiles[2].price, "6s", "the check behind it ran")
end)

test("follow-up 2: a check stopped by leaving the tab before its items loaded keeps nothing and sends nothing", function()
    local c, tiles = checkState(nil, { items = { [10061] = { name = "A", quality = 2, bindType = 2, subType = "Cloth", load = 1 },
        [10062] = { name = "B", quality = 2, bindType = 2, subType = "Cloth", load = 1 },
        [10063] = { name = "C", quality = 2, bindType = 2, subType = "Cloth", load = 1 } } })
    check(tiles[1].appearance.id == 1006, "fixture: tile 1 is appearance 1006")
    click(tiles[1])
    c.advance(0.1)
    TC.BrowserState.Leave()
    c.advance(3)
    local v = TC.BrowserState.View()
    equal(v.list, nil, "no flyout")
    equal(v.tiles[1].strip, "not checked", "the stopped check kept nothing")
    equal(#c.ah.sends, 0, "browses")
end)

test("follow-up 3: cannot be sold only when an item is known and every item binds; no item known could not check", function()
    -- no source at all
    local c = checkClient({})
    local r = runCheck(c)
    equal(r.result.outcome, "could not check", "an appearance without sources")
    equal(#c.ah.sends, 0, "browses without sources")
    -- GetSourceInfo answers nothing
    c = checkClient({ { 501, "Willow Boots", BOE } }, nil, { sourceInfoNil = true })
    r = runCheck(c)
    equal(r.result.outcome, "could not check", "GetSourceInfo answering nothing")
    -- items that fail to load are not on this server (TC-32)
    c = checkClient({ { 501, "Bound Boots", BOP, "fail" } })
    equal(runCheck(c).result.outcome, "cannot be sold", "an item that failed to load")
    -- every item known to bind
    c = checkClient({ { 502, "Bound Boots", BOP }, { 503, "Quest Boots", QUEST } })
    equal(runCheck(c).result.outcome, "cannot be sold", "every item binds")
    -- in the item list
    local s = bootState({ appearances = { { id = 1, uiOrder = 1, sources = {}, classes = { [9] = true } } } })
    TC.BrowserState.Refresh()
    TC.BrowserState.SetFilter("All")
    click(TC.BrowserState.View().tiles[1])
    s.advance(5)
    local v = TC.BrowserState.View()
    equal(v.list, nil, "no flyout")
    equal(v.tiles[1].strip, "no answer", "strip")
end)

test("follow-up 4: the head's type comes from any item of the appearance, also one that cannot be traded", function()
    local c = bootState({ appearances = { { id = 1, uiOrder = 1, sources = { 11, 12 }, classes = { [9] = true } } },
        items = { [11] = { name = "Bound Boots", quality = 2, bindType = 1, subType = "Leather" },
            [12] = { name = "Plain Boots", quality = 2, bindType = 2 } } })
    TC.BrowserState.Refresh()
    click(TC.BrowserState.View().tiles[1])
    c.advance(5)
    click(TC.BrowserState.View().tiles[1])
    local l = TC.BrowserState.View().list
    equal(l.typeText, "Head, leather", "head type")
end)

---------------------------------------------------------------- Whole addon

local function find(c, pred)
    for _, w in ipairs(c.widgets) do
        if pred(w) then return w end
    end
end
local function findAll(c, pred)
    local out = {}
    for _, w in ipairs(c.widgets) do
        if pred(w) then out[#out + 1] = w end
    end
    return out
end
-- Shown, and every parent shown.
local function visible(w)
    while w do
        if not w.shown then return false end
        w = w.parent
    end
    return true
end
local function textShown(c, text)
    return find(c, function(w) return w.text == text and visible(w) end) ~= nil
end
-- A selector (class, weapon type, Filter) of that width: Blizzard's
-- dropdown or the panel's own button. A dropdown that was made and hidden
-- before it got a place (a half-made one the panel gave up on) is not one.
local function selector(c, width)
    return find(c, function(w)
        if w.kind == "DropdownButton" and #w.points == 0 then return false end
        return (w.kind == "DropdownButton" or w.kind == "Button") and w.width == width
    end)
end
-- Opens a selector's menu as a press does; answers its entries' texts in
-- order ("-" for the line Blizzard's menu draws) and a function choosing an
-- entry by its text.
local function openMenu(c, button)
    local texts = {}
    if button.kind == "DropdownButton" then
        button.scripts.OnMouseDown(button, "LeftButton")
        for i, e in ipairs(c.menuEntries()) do texts[i] = e == "-" and "-" or e.text end
        return texts, c.choose
    end
    button.scripts.OnClick(button)
    local entries = findAll(c, function(w) return w.kind == "Button" and w.parent == button.menu and visible(w) end)
    for i, e in ipairs(entries) do texts[i] = e.text end
    return texts, function(text)
        for _, e in ipairs(entries) do
            if e.text == text then e.scripts.OnClick(e) return true end
        end
        return false
    end
end

-- Loads every file, logs in, and opens the auction house twice. Returns the
-- tab button.
local function login(opts)
    local c = boot(opts)
    c.fire("ADDON_LOADED", "TransmogChecker")
    c.fire("PLAYER_LOGIN")
    return c
end
local function tabsOf(c)
    return findAll(c, function(w) return w.name and w.name:find("^LibAHFrame%-1%.0%-") end)
end
local function visitTwice(opts)
    local c = login(opts)
    c.openAuction()
    c.closeAuction()
    c.openAuction()
    return c, tabsOf(c)
end
-- Under w, at any depth.
local function under(w, root)
    w = w.parent
    while w do
        if w == root then return true end
        w = w.parent
    end
    return false
end
local function setUnitCalls(c)
    local n = 0
    for _, w in ipairs(c.widgets) do n = n + (w.callCount.SetUnit or 0) end
    return n
end
-- Blizzard's Buy tab: the window goes back to its own display mode.
local function selectBuy()
    AuctionHouseFrame:SetDisplayMode({ "BuyTab" })
end
-- The funnel: Blizzard's filter dropdown, or the panel's own 30 square
-- button with its own menu.
local function funnelOf(c)
    return find(c, function(w)
        if w.kind == "DropdownButton" then return w.template == "WowStyle1FilterDropdownTemplate" and #w.points > 0 end
        return w.kind == "Button" and w.width == 30 and w.height == 30 and w.menu ~= nil
    end)
end
-- The Show entry the funnel's menu marks, read by opening it and closing it.
local function markedShow(c)
    local funnel = funnelOf(c)
    openMenu(c, funnel)
    local marked
    for _, e in ipairs(c.menuEntries()) do
        if e ~= "-" and e.selected and not marked then marked = e.text end
    end
    funnel:CloseMenu()
    return marked
end
local function countShown(c)
    return find(c, function(w) return w.kind == "FontString" and w.text and w.text:find("^%d+ .*appearance") and visible(w) end)
end

test("opening the auction window creates the tab and the bare panel, and builds and dresses nothing", function()
    local c = login()
    local before = #c.widgets
    c.loadAuctionUI()
    local blizzard = #c.widgets - before
    c.openAuction()
    local tab = tabsOf(c)[1]
    local panel = tab.frameRef
    -- the library's root frame and tab button, and the panel
    equal(#c.widgets - before - blizzard, 3, "widgets made on the first AUCTION_HOUSE_SHOW")
    equal(#findAll(c, function(w) return under(w, panel) end), 0, "widgets inside the panel")
    equal(setUnitCalls(c), 0, "SetUnit calls")
    c.closeAuction()
    c.openAuction()
    equal(#findAll(c, function(w) return under(w, panel) end), 0, "widgets inside the panel after a second visit")
    equal(setUnitCalls(c), 0, "SetUnit calls after a second visit")
    equal(c.listCalls, 0, "list reads")
end)

test("selecting the tab builds the browser once", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local built = #c.widgets
    equal(#findAll(c, function(w) return w.kind == "DressUpModel" end), 24, "models")
    equal(setUnitCalls(c), 24, "SetUnit calls")
    selectBuy()
    tabs[1].scripts.OnClick(tabs[1])
    c.closeAuction()
    c.openAuction()
    tabs[1].scripts.OnClick(tabs[1])
    equal(#c.widgets, built, "widgets after leaving, re-entering and a new visit")
    equal(setUnitCalls(c), 24, "SetUnit calls after re-entering")
end)

test("closing with the tab selected and opening again reads and dresses nothing until the tab is selected", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local reads, dressed, units = c.listCalls, #c.tryOn, setUnitCalls(c)
    c.closeAuction()
    c.openAuction()
    c.fire("TRANSMOG_COLLECTION_UPDATED")
    equal(c.listCalls, reads, "list reads after reopening")
    equal(#c.tryOn, dressed, "models dressed after reopening")
    equal(setUnitCalls(c), units, "SetUnit calls after reopening")
    check(not tabs[1].frameRef:IsShown(), "the panel hidden after reopening")
    tabs[1].scripts.OnClick(tabs[1])
    equal(c.listCalls, reads + 1, "list reads after selecting the tab again")
end)

test("login and two auction house visits make one tab and no C_AuctionHouse call", function()
    local c, tabs = visitTwice()
    equal(#tabs, 1, "tabs created")
    equal(tabs[1].text, "Appearances", "tab text")
    equal(#c.auctionTouches, 0, "C_AuctionHouse accesses (" .. table.concat(c.auctionTouches, ", ") .. ")")
    equal(c.listCalls, 0, "appearance list reads before the tab is selected")
end)

test("selecting the tab asks the state for one page and draws it", function()
    local c, tabs = visitTwice()
    local views, realView = 0, TC.BrowserState.View
    TC.BrowserState.View = function() views = views + 1; return realView() end
    tabs[1].scripts.OnClick(tabs[1])
    equal(views, 1, "View calls on selecting the tab")
    equal(AuctionHouseFrame.title, "Appearance Browser", "window title")
    equal(#c.tryOn, 24, "models dressed")
    equal(#c.cameras, 24, "cameras applied")
    for _, text in ipairs({ "365 of 370 appearances", "Price this slot", "Page 1 / 16",
        "Click an appearance to check the auction house." }) do
        check(textShown(c, text), "the text \"" .. text .. "\" on screen")
    end
    equal(#c.auctionTouches, 0, "C_AuctionHouse accesses")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

test("the panel forwards the wheel, the arrows and the Filter menu to the state", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local wheel = find(c, function(w) return w.scripts.OnMouseWheel end)
    wheel.scripts.OnMouseWheel(wheel, -1)
    check(textShown(c, "Page 2 / 16"), "page 2 after the wheel turned down")
    wheel.scripts.OnMouseWheel(wheel, 1)
    check(textShown(c, "Page 1 / 16"), "page 1 after the wheel turned up")
    local _, choose = openMenu(c, funnelOf(c))
    check(choose("Collected"), "a \"Collected\" entry in the funnel's menu")
    check(textShown(c, "5 of 370 appearances"), "count after choosing Collected")
    equal(markedShow(c), "Collected", "the funnel marks Collected")
    local arrows = findAll(c, function(w) return w.kind == "Button" and visible(w) and w.width == 22 end)
    equal(#arrows, 0, "paging arrows shown with one page")
end)

test("closing the auction house starts the next visit fresh", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    TC.BrowserState.SetFilter("All")
    c.closeAuction()
    c.openAuction()
    tabs[1].scripts.OnClick(tabs[1])
    equal(markedShow(c), "Not collected", "Show back on Not collected")
    equal(c.listCalls, 2, "list read again in the new visit")
end)

-- Nothing on screen that claims the slot has no appearance.
local function unavailableOnScreen(c, what)
    equal(countShown(c), nil, what .. ": count text shown")
    check(not textShown(c, "No matches"), what .. ": no empty-state title")
    check(not find(c, function(w) return w.text and w.text:find("^Page ") and visible(w) end), what .. ": no page text")
    equal(#findAll(c, function(w) return w.kind == "DressUpModel" and visible(w) end), 0, what .. ": tiles shown")
    local head = find(c, function(w) return w.slot == "head" and w.ring end)
    check(head and visible(head.ring), what .. ": Head chosen in the slot row")
end

test("a missing collections API leaves the panel without tiles or empty-slot text and raises no error", function()
    local c, tabs = visitTwice({ noTransmog = true })
    local ok, err = pcall(tabs[1].scripts.OnClick, tabs[1])
    check(ok, "no error: " .. tostring(err))
    equal(#c.tryOn, 0, "models dressed")
    unavailableOnScreen(c, "missing API")
    equal(#c.auctionTouches, 0, "C_AuctionHouse accesses")
end)

test("a failing list call raises nothing to the player, and a later read fills the grid", function()
    local c, tabs = visitTwice({ listRaises = 1 })
    local ok, err = pcall(tabs[1].scripts.OnClick, tabs[1])
    check(ok, "no error: " .. tostring(err))
    unavailableOnScreen(c, "failed read")
    c.fire("TRANSMOG_COLLECTION_UPDATED")
    equal(#c.tryOn, 24, "models dressed after a later read")
    check(textShown(c, "365 of 370 appearances"), "count after a later read")
end)

test("an empty first read does not stick: the collection event and re-entering the tab read again", function()
    local c, tabs = visitTwice({ listEmpty = 1 })
    tabs[1].scripts.OnClick(tabs[1])
    unavailableOnScreen(c, "empty read")
    c.fire("TRANSMOG_COLLECTION_UPDATED")
    check(textShown(c, "365 of 370 appearances"), "count after the collection event")

    c, tabs = visitTwice({ listEmpty = 1 })
    tabs[1].scripts.OnClick(tabs[1])
    unavailableOnScreen(c, "empty read")
    selectBuy()
    tabs[1].scripts.OnClick(tabs[1])
    check(textShown(c, "365 of 370 appearances"), "count after re-entering the tab")
end)

test("the class filter switch firing the collection event inside List gives one read and one draw", function()
    local c, tabs = visitTwice({ classFilter = 8, setClassFires = true })
    local views, realView = 0, TC.BrowserState.View
    TC.BrowserState.View = function() views = views + 1; return realView() end
    local ok, err = pcall(tabs[1].scripts.OnClick, tabs[1])
    check(ok, "no error: " .. tostring(err))
    equal(c.setClassCalls, 2, "class filter set and restored")
    equal(c.listCalls, 1, "list reads")
    equal(views, 1, "draws")
    equal(c.collections.classFilter, 8, "class filter after selecting the tab")
end)

test("the empty-state button forwards its action through the panel", function()
    local c, tabs = visitTwice({ appearances = Fake.appearances(30, 0) })
    tabs[1].scripts.OnClick(tabs[1])
    TC.BrowserState.SetFilter("Collected")
    check(textShown(c, "No collected head appearances for Warlock."), "the empty-state text")
    local button = find(c, function(w) return w.kind == "Button" and w.text == "Show all" and visible(w) end)
    check(button, "a shown \"Show all\" button")
    button.scripts.OnClick(button)
    equal(markedShow(c), "All", "Show All after the button")
    check(textShown(c, "30 appearances"), "count after the button")
    check(not textShown(c, "Show all"), "the button gone")
end)

test("the panel draws the arrows' state from the view", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local arrows = findAll(c, function(w) return w.kind == "Button" and w.width == 22 and visible(w) end)
    equal(#arrows, 2, "arrows shown")
    local v = TC.BrowserState.View()
    equal(arrows[1].enabled, v.previousEnabled, "previous arrow")
    equal(arrows[2].enabled, v.nextEnabled, "next arrow")
    equal(arrows[1].enabled, false, "previous on page 1")
end)

test("the collection event refreshes collected while the panel is shown and not while it is hidden", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    c.collectedSources[1370 * 10 + 1] = true
    c.fire("TRANSMOG_COLLECTION_UPDATED")
    check(textShown(c, "364 of 370 appearances"), "count after the event while shown")
    selectBuy()
    local views, realView = 0, TC.BrowserState.View
    TC.BrowserState.View = function() views = views + 1; return realView() end
    c.collectedSources[1369 * 10 + 1] = true
    c.fire("TRANSMOG_COLLECTION_UPDATED")
    equal(views, 0, "draws while hidden")
    tabs[1].scripts.OnClick(tabs[1])
    check(textShown(c, "363 of 370 appearances"), "count on coming back")
end)

test("buttons without Blizzard's template get a font object, or none when it is missing", function()
    for _, opts in ipairs({ { noButtonTemplate = true }, { noButtonTemplate = true, noFontObjects = true } }) do
        local c, tabs = visitTwice(opts)
        local ok, err = pcall(tabs[1].scripts.OnClick, tabs[1])
        check(ok, "no error: " .. tostring(err))
        equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
        check(funnelOf(c) and visible(funnelOf(c)), "the funnel")
    end
end)

---------------------------------------------------------------- Whole addon: checks

test("whole: login, the auction window, the tab, paging and the Filter send nothing to the auction house", function()
    local c, tabs = visitTwice()
    c.ah.listings = { listing("Item 10061", 10061, 500) }
    tabs[1].scripts.OnClick(tabs[1])
    local wheel = find(c, function(w) return w.scripts.OnMouseWheel and w.kind == "Frame" end)
    wheel.scripts.OnMouseWheel(wheel, -1)
    wheel.scripts.OnMouseWheel(wheel, 1)
    TC.BrowserState.SetFilter("All")
    TC.BrowserState.SetFilter("Collected")
    c.fire("TRANSMOG_COLLECTION_UPDATED")
    selectBuy()
    tabs[1].scripts.OnClick(tabs[1])
    c.advance(120)
    equal(#c.ah.sends, 0, "browses")
    equal(#c.ah.more, 0, "requests for more")
    equal(#c.auctionTouches, 0, "C_AuctionHouse accesses (" .. table.concat(c.auctionTouches, ", ") .. ")")
end)

-- The tile frames of the grid, in order.
local function tileFrames(c)
    return findAll(c, function(w) return w.model and w.button end)
end

test("whole: a click on a tile whose appearance has two tradeable names makes exactly two browses", function()
    local c, tabs = visitTwice({
        appearances = { { id = 1, uiOrder = 1, sources = { 11, 12, 13 }, classes = { [9] = true } },
            { id = 2, uiOrder = 2, sources = { 21 }, classes = { [9] = true } } },
        sourceItems = { [11] = 501, [12] = 502, [13] = 503, [21] = 601 },
        items = { [501] = { name = "Willow Boots", quality = 2, bindType = 2, subType = "Cloth" },
            [502] = { name = "Ivy Boots", quality = 3, bindType = 0, subType = "Cloth" },
            [503] = { name = "Bound Boots", quality = 4, bindType = 1, subType = "Cloth" } },
    })
    c.ah.listings = { listing("Willow Boots", 501, 4876312, { totalQuantity = 2 }), listing("Ivy Boots", 502, 990000) }
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    -- Collections' order: uiOrder descending
    frames[2].button.scripts.OnClick(frames[2].button)
    check(not textShown(c, "Checking the auction house"), "no flyout while it checks")
    c.advance(10)
    equal(#c.ah.sends, 2, "browses")
    frames[2].button.scripts.OnClick(frames[2].button)
    check(textShown(c, "Head, cloth"), "head type on screen")
    check(textShown(c, "2 item variants, cheapest first"), "found title on screen")
    check(textShown(c, "Willow Boots"), "a found row's name")
    check(textShown(c, "x2"), "a found row's quantity")
    check(textShown(c, "Checked just now"), "the foot's age")
    check(textShown(c, "Check again"), "the foot's button")
    equal(frames[2].border.color[2], 0.82, "gold open marker")
    -- the strip shows the cheapest, 99g, with coin icons
    check(frames[2].price.text:find("^99"), "strip price drawn, got " .. tostring(frames[2].price.text))
    -- the found row's name follows the variant's own name once it arrives
    c.ah.keyNames["501:0"] = "Willow Boots of the Owl"
    c.fire("ITEM_KEY_ITEM_INFO_RECEIVED", 501)
    -- the panel redraws for item key info once per frame (TC-32)
    c.frame()
    check(textShown(c, "Willow Boots of the Owl"), "the variant's name")
    -- the close mark closes the flyout
    local close = find(c, function(w) return w.kind == "Button" and w.width == 20 and w.height == 20 and visible(w) end)
    close.scripts.OnClick(close)
    check(not textShown(c, "Check again"), "the list closed")
    equal(#c.ah.sends, 2, "browses after closing")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
    equal(#c.forbidden, 0, "forbidden calls: " .. table.concat(c.forbidden, ", "))
end)

test("whole: leaving the tab during a check sends nothing more", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    frames[1].button.scripts.OnClick(frames[1].button)
    c.advance(0.1)
    selectBuy()
    tabs[1].frameRef:Hide()
    local sends = #c.ah.sends
    c.advance(30)
    equal(#c.ah.sends, sends, "browses after leaving")
    tabs[1].scripts.OnClick(tabs[1])
    c.advance(30)
    equal(#c.ah.sends, sends, "browses after coming back")
end)

test("whole: the collection event during a check and with the list open ends the check normally and sends nothing twice", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    local id = frames[1].appearance.id
    c.ah.listings = { listing("Item " .. (id * 10 + 1), id * 10 + 1, 500) }
    frames[1].button.scripts.OnClick(frames[1].button)
    c.advance(0.1)
    -- another appearance becomes collected while the check runs
    c.collectedSources[frames[10].appearance.id * 10 + 1] = true
    c.fire("TRANSMOG_COLLECTION_UPDATED")
    c.advance(10)
    equal(#c.ah.sends, 3, "browses: one per item name")
    frames[1].button.scripts.OnClick(frames[1].button)
    check(textShown(c, "1 item variant, cheapest first"), "the check ended as found")
    c.fire("TRANSMOG_COLLECTION_UPDATED")
    c.advance(10)
    check(textShown(c, "Check again"), "the list still open after an event that changes nothing")
    equal(#c.ah.sends, 3, "browses after the event with the list open")
    -- the open appearance itself becomes collected: Not collected removes it
    c.collectedSources[id * 10 + 1] = true
    c.fire("TRANSMOG_COLLECTION_UPDATED")
    check(not textShown(c, "Check again"), "the list closed when the Filter removed its appearance")
    c.advance(10)
    equal(#c.ah.sends, 3, "browses after the list closed")
end)

-- One appearance with one item, Willow Boots (501), listed at 5s.
local function oneItemWhole()
    local c, tabs = visitTwice({ appearances = { { id = 1, uiOrder = 1, sources = { 11 }, classes = { [9] = true } } },
        sourceItems = { [11] = 501 },
        items = { [501] = { name = "Willow Boots", quality = 2, bindType = 2, subType = "Cloth" } } })
    c.ah.listings = { listing("Willow Boots", 501, 500) }
    tabs[1].scripts.OnClick(tabs[1])
    return c, tileFrames(c)
end

test("whole: a found row's name follows the variant's name the client sends by itself", function()
    local c, frames = oneItemWhole()
    c.ah.keyNames["501:0"] = "Willow Boots of the Owl"
    frames[1].button.scripts.OnClick(frames[1].button)
    c.advance(0.26)
    frames[1].button.scripts.OnClick(frames[1].button)
    check(textShown(c, "1 item variant, cheapest first"), "found")
    check(textShown(c, "Willow Boots"), "the item's name before the variant's arrives")
    -- the event at 0.012 s; the panel redraws on the next frame (TC-32)
    c.advance(0.012 + c.FRAME)
    check(textShown(c, "Willow Boots of the Owl"), "the variant's name after the client's own event")
end)

-- The flyout frame, 232 wide (layout B), and its widgets.
local function itemListFrame(c)
    return find(c, function(w) return w.kind == "Frame" and w.width == 232 end)
end
-- The same two clicks on a tile's frame; answers the flyout.
local function openTile(c, frame)
    c.click(frame.button)
    c.advance(10)
    c.click(frame.button)
    return itemListFrame(c)
end

test("whole: the head's Collected line has the check and is green; a look not collected has neither", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    TC.BrowserState.SetFilter("Collected")
    local frames = tileFrames(c)
    frames[1].button.scripts.OnClick(frames[1].button)
    c.advance(10)
    frames[1].button.scripts.OnClick(frames[1].button)
    local list = itemListFrame(c)
    local collected = find(c, function(w) return w.text == "Collected" and w.kind == "FontString" and under(w, list) end)
    check(collected and visible(collected), "the Collected line")
    equal(collected.textColor[2], 0.8, "Collected in green")
    local tileCheck = frames[1].check.calls.SetTexture[1]
    local icon = find(c, function(w)
        return w.kind == "Texture" and under(w, list) and w.calls.SetTexture and w.calls.SetTexture[1] == tileCheck
    end)
    check(icon and visible(icon), "the check beside Collected, the tile's check texture")
    TC.BrowserState.SetFilter("All")
    TC.BrowserState.CloseList()
    local notCollected
    for _, f in ipairs(frames) do
        if f.appearance and not TC.Appearances.IsCollected(f.appearance) then notCollected = f break end
    end
    notCollected.button.scripts.OnClick(notCollected.button)
    c.advance(10)
    notCollected.button.scripts.OnClick(notCollected.button)
    check(not visible(collected), "no Collected line")
    check(not visible(icon), "no check")
end)

test("whole: while the flyout is open the wheel over it scrolls its four rows; the grid never moves", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    local itemID = frames[1].appearance.id * 10 + 1
    for n = 1, 9 do
        c.ah.listings[n] = listing("Item " .. itemID, itemID, n * 100, { itemSuffix = n })
    end
    local grid = frames[1]:GetParent()
    equal(grid.width, 736, "grid width with 8 columns")
    frames[1].button.scripts.OnClick(frames[1].button)
    c.advance(10)
    frames[1].button.scripts.OnClick(frames[1].button)
    local list = itemListFrame(c)
    equal(grid.width, 736, "grid width with the flyout open")
    local function inList(text)
        return find(c, function(w) return w.text == text and under(w, list) and visible(w) end) ~= nil
    end
    check(inList("1s") and inList("4s") and not inList("5s"), "rows 1 to 4 shown")
    local page = TC.BrowserState.View().page
    list.scripts.OnMouseWheel(list, -1)
    check(not inList("1s") and inList("5s"), "the rows scrolled by one")
    equal(TC.BrowserState.View().page, page, "the grid's page")
    TC.BrowserState.CloseList()
    equal(grid.width, 736, "grid width after closing")
end)

---------------------------------------------------------------- Whole addon: scans

-- The catalogue (All) or sweep (For sale) toggle.
local function modeTab(c, mode)
    return find(c, function(w) return w.kind == "Button" and w.mode == mode end)
end

test("whole: the files in .toc order, login, the window, the tab, paging, the Filter and All send nothing", function()
    local c, tabs = visitTwice()
    local order = table.concat(c.loaded, "|")
    check(order:find("TC_Check.lua|TC/Browser/TC_Scan.lua|TC/Browser/TC_BrowserState.lua", 1, true),
        "TC_Scan.lua loads after TC_Check.lua and before the state, got " .. order)
    for id = 1010, 1030, 10 do c.ah.listings[#c.ah.listings + 1] = listing("Item " .. (id * 10 + 1), id * 10 + 1, id) end
    tabs[1].scripts.OnClick(tabs[1])
    local wheel = find(c, function(w) return w.scripts.OnMouseWheel and w.kind == "Frame" end)
    wheel.scripts.OnMouseWheel(wheel, -1)
    wheel.scripts.OnMouseWheel(wheel, 1)
    TC.BrowserState.SetFilter("All")
    local all = modeTab(c, "All")
    all.scripts.OnClick(all)
    c.fire("TRANSMOG_COLLECTION_UPDATED")
    selectBuy()
    tabs[1].scripts.OnClick(tabs[1])
    c.advance(120)
    equal(#c.ah.sends, 0, "browses")
    equal(#c.ah.more, 0, "requests for more")
    equal(#c.auctionTouches, 0, "C_AuctionHouse accesses (" .. table.concat(c.auctionTouches, ", ") .. ")")
end)

test("whole: selecting For sale makes one browse and a page request per further page, and draws the scan", function()
    local c, tabs = visitTwice()
    c.ah.pageSize = 2
    for id = 1010, 1050, 10 do c.ah.listings[#c.ah.listings + 1] = listing("Item " .. (id * 10 + 1), id * 10 + 1, id) end
    tabs[1].scripts.OnClick(tabs[1])
    local forSale = modeTab(c, "For sale")
    check(forSale and visible(forSale), "a shown sweep toggle")
    forSale.scripts.OnClick(forSale)
    c.advance(0.26)
    check(textShown(c, "Scanning head"), "the status line while scanning")
    local bars = findAll(c, function(w) return w.kind == "Texture" and w.width == 30 and w.height == 4 and visible(w) end)
    equal(#bars, 22, "placeholder bars after the first page")
    c.advance(30)
    equal(#c.ah.sends, 1, "browses")
    equal(#c.ah.more, 2, "requests for more: 3 pages")
    check(textShown(c, "Scanned just now"), "the status line after the scan")
    check(textShown(c, "Scan again"), "the Scan again button")
    check(textShown(c, "5 of 370 appearances"), "count text")
    openMenu(c, funnelOf(c))
    local fixed = c.menuEntries()[3]
    equal(fixed.text .. tostring(fixed.selected) .. tostring(fixed.enabled), "Not collectedtruefalse",
        "Show fixed on Not collected and greyed")
    funnelOf(c):CloseMenu()
    equal(#findAll(c, function(w) return w.model and w.button and visible(w) end), 5, "tiles shown")
    -- leaving the tab and coming back in For sale after a finished scan reads nothing
    selectBuy()
    tabs[1].frameRef:Hide()
    tabs[1].scripts.OnClick(tabs[1])
    c.advance(30)
    equal(#c.ah.sends, 1, "browses after coming back")
    -- Scan again through the panel
    local again = find(c, function(w) return w.kind == "Button" and w.text == "Scan again" and visible(w) end)
    again.scripts.OnClick(again)
    c.advance(0.1)
    -- leaving during it and coming back scans once
    selectBuy()
    tabs[1].frameRef:Hide()
    c.advance(30)
    equal(#c.ah.sends, 2, "browses after leaving during Scan again")
    tabs[1].scripts.OnClick(tabs[1])
    c.advance(30)
    equal(#c.ah.sends, 3, "browses after coming back")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
    equal(#c.forbidden, 0, "forbidden calls: " .. table.concat(c.forbidden, ", "))
end)

---------------------------------------------------------------- All 14 slots (step 5)

local CAT = Fake.CATEGORIES
local SLOT_KEYS = { "head", "shoulder", "back", "chest", "shirt", "tabard", "wrist", "hands", "waist", "legs", "feet",
    "mainhand", "offhand", "ranged" }

-- Head (370, 5 collected, ids 1001+), legs (30, ids 2001+), daggers (10,
-- ids 3001+), one-handed swords (8, ids 4001+), bows (5, ids 5001+) and
-- shields (4, ids 6001+).
local function manySlots()
    local list = Fake.appearances(370, 5)
    local function add(more) for _, a in ipairs(more) do list[#list + 1] = a end end
    add(Fake.appearances(30, 0, CAT.Legs, 2000))
    add(Fake.appearances(10, 0, CAT.Dagger, 3000))
    add(Fake.appearances(8, 0, CAT.OneHSword, 4000))
    add(Fake.appearances(5, 0, CAT.Bow, 5000))
    add(Fake.appearances(4, 0, CAT.Shield, 6000))
    return list
end

local function listedText(c)
    local out = {}
    for i, l in ipairs(c.listed) do out[i] = l.category .. "@" .. tostring(l.slotID) end
    return table.concat(out, ",")
end

test("slots: each of the 14 slots reads the categories and the inventory slot of spec 4.3", function()
    -- spec 4.3, the categories by their numbers and the inventory slots
    local expected = { head = "1@1", shoulder = "2@3", back = "3@15", chest = "4@5", shirt = "5@4", tabard = "6@19",
        wrist = "7@9", hands = "8@10", waist = "9@6", legs = "10@7", feet = "11@8",
        mainhand = "13@16,14@16,15@16,16@16,17@16,20@16,21@16,22@16,23@16,24@16",
        offhand = "18@17,19@17", ranged = "12@18,25@18,26@18,27@18" }
    for _, opts in ipairs({ {}, { noCategoryInfo = true } }) do
        for _, key in ipairs(SLOT_KEYS) do
            local c = boot(opts)
            TC.Appearances.List(key, 9)
            equal(listedText(c), expected[key], key .. " read with " .. (next(opts) or "category info"))
        end
    end
    equal(#TC.Slots, 14, "slots in the row")
    local names = {}
    for i, s in ipairs(TC.Slots) do names[i] = s.name .. ":" .. s.group end
    equal(table.concat(names, ","), "Head:1,Shoulder:1,Back:1,Chest:1,Shirt:1,Tabard:1,Wrist:1,Hands:2,Waist:2,"
        .. "Legs:2,Feet:2,Main hand:3,Off hand:3,Ranged:3", "the row's order and groups")
end)

test("slots: a weapon slot is the union of its categories without duplicates; a weapon type narrows to one", function()
    local list = manySlots()
    -- appearance 3001 is listed under one-handed swords too
    list[#list + 1] = { id = 3001, uiOrder = 9, minIlvl = 0, sources = { 30011 }, category = CAT.OneHSword, classes = { [9] = true } }
    local c = boot({ appearances = list })
    local all = TC.Appearances.List("mainhand", 9)
    equal(#all, 18, "nine swords with 3001 and nine more daggers, 3001 once")
    -- swords (14) come before daggers (16), each in Collections' order (minIlvl)
    equal(ids(all):sub(1, 30), "3001,4001,4002,4003,4004,4005,", "swords first, 3001 from its first category")
    equal(all[1].category, CAT.OneHSword, "3001's category is the first that lists it")
    equal(all[10].id, 3002, "then the daggers")
    equal(all[10].category, CAT.Dagger, "a dagger's category")
    c.listed = {}
    local daggers = TC.Appearances.List("mainhand", 9, CAT.Dagger)
    equal(#daggers, 10, "daggers only")
    equal(listedText(c), "16@16", "one category read for the weapon type")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

test("slots: weapon types come from GetCategoryInfo flags when it answers, else the fixed split", function()
    -- the client also lets daggers into the off hand
    local info = { [16] = { "Daggers", true, false, true, true, false }, [18] = { "Shields", true, false, false, true, false },
        [19] = { "Held In Off-hand", true, false, false, true, false }, [5] = { "Shirt", false, false, false, false, false } }
    boot({ categoryInfo = info })
    local function text(types)
        local out = {}
        for i, t in ipairs(types) do out[i] = t.category .. "=" .. t.name end
        return table.concat(out, ",")
    end
    equal(text(TC.Appearances.WeaponTypes("offhand")), "16=Daggers,18=Shields,19=Held In Off-hand", "off hand by flags")
    equal(text(TC.Appearances.WeaponTypes("mainhand")), "16=Daggers", "main hand by flags")
    -- no flag fits Ranged: the fixed split (F4)
    equal(text(TC.Appearances.WeaponTypes("ranged")), "12=Subclass 2.19,25=Subclass 2.2,26=Subclass 2.3,27=Subclass 2.18", "ranged by flags")
    equal(text(TC.Appearances.WeaponTypes("head")), "", "an armor slot has none")
    boot({ noCategoryInfo = true })
    -- the client's subclass names (the fake's "Subclass class.subclass")
    equal(text(TC.Appearances.WeaponTypes("offhand")), "18=Subclass 4.6,19=Subclass 4.0", "off hand, fixed split")
    equal(text(TC.Appearances.WeaponTypes("ranged")), "12=Subclass 2.19,25=Subclass 2.2,26=Subclass 2.3,27=Subclass 2.18",
        "ranged, fixed split")
end)

test("slots: Collections' class filter is restored after a weapon slot's several reads, also when one raises", function()
    for _, opts in ipairs({ { classFilter = 8 }, { classFilter = 8, listRaisesFor = CAT.Dagger } }) do
        local c = boot(opts)
        local before = c.snapshot()
        local ok = pcall(TC.Appearances.List, "mainhand", 9)
        equal(ok, opts.listRaisesFor == nil, "List succeeds unless a read raises")
        sameState(before, c.snapshot(), "after main hand with " .. tostring(opts.listRaisesFor))
        equal(c.setClassCalls, 2, "one switch and one restore for ten reads")
    end
end)

test("slots: DisplaySource of a weapon uses the category it was listed from", function()
    local c = boot({ appearances = manySlots() })
    local dagger = TC.Appearances.List("mainhand", 9, CAT.Dagger)[1]
    equal(TC.Appearances.DisplaySource(dagger), dagger.id * 10 + 3, "display source")
    equal(TC.Appearances.IsCollected(dagger), false, "collected rule for a weapon")
    c.collectedSources[dagger.id * 10 + 2] = true
    equal(TC.Appearances.IsCollected(dagger), true, "collected rule after collecting a weapon")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

-- One scan of the slot; answers the query sent and the done answer.
local function scanSlot(c, slot)
    local r = {}
    TC.Scan.Run(slot, function() end, function(result, reason) r.result, r.reason = result, reason end)
    c.advance(30)
    r.query = c.ah.sends[#c.ah.sends] and c.ah.sends[#c.ah.sends].query
    return r
end

test("slots: every slot's scan sends the filter entries of spec 4.3, each with its subclass; chest has eight", function()
    -- spec 4.3 in numbers: class.subclass.inventoryType (- when none)
    local four = function(inv) return ("4.1.%d,4.2.%d,4.3.%d,4.4.%d"):format(inv, inv, inv, inv) end
    local expected = { head = four(1), shoulder = four(3), back = "4.1.16", chest = four(5) .. "," .. four(20),
        shirt = "4.0.4", tabard = "4.0.19", wrist = four(9), hands = four(10), waist = four(6), legs = four(7),
        feet = four(8), mainhand = "2.0.-,2.7.-,2.4.-,2.15.-,2.13.-,2.1.-,2.8.-,2.5.-,2.10.-,2.6.-",
        offhand = "4.6.-,4.0.23", ranged = "2.19.-,2.2.-,2.3.-,2.18.-" }
    for _, key in ipairs(SLOT_KEYS) do
        local c = boot()
        local r = scanSlot(c, key)
        check(r.result, key .. ": a result, got " .. tostring(r.reason))
        local out = {}
        for i, e in ipairs(r.query.itemClassFilters) do
            check(type(e.subClassID) == "number", key .. " entry " .. i .. " has a subclass")
            out[i] = e.classID .. "." .. e.subClassID .. "." .. (e.inventoryType or "-")
        end
        equal(table.concat(out, ","), expected[key], key .. " filter entries")
        if key == "chest" then equal(#out, 8, "chest entries") end
    end
end)

test("slots: a slot whose filter needs a missing enum member fails alone", function()
    local c = boot({ noEnumMembers = { { "InventoryType", "IndexCloakType" } } })
    local r = scanSlot(c, "back")
    equal(r.result, nil, "back fails")
    check(tostring(r.reason):find("Enum"), "the reason, got " .. tostring(r.reason))
    equal(#c.ah.sends, 0, "nothing sent for back")
    for _, key in ipairs({ "head", "chest", "mainhand", "offhand", "ranged" }) do
        check(scanSlot(c, key).result, key .. " still scans")
    end
end)

-- The state on the many-slot fixture, after the first Refresh.
local function slotState(opts)
    opts = opts or {}
    opts.appearances = opts.appearances or manySlots()
    local c = bootState(opts)
    TC.BrowserState.Refresh()
    return c
end
local function state() return TC.BrowserState end

test("state: the slot row answers the 14 slots in their groups with the chosen one; the start slot is Head", function()
    slotState()
    local v = state().View()
    equal(#v.slots, 14, "slots")
    equal(v.slots[1].key, "head", "first slot")
    equal(v.slots[1].selected, true, "Head chosen at the start")
    equal(v.slots[12].name, "Main hand", "twelfth slot")
    equal(v.slots[12].group, 3, "its group")
    state().SelectSlot("legs")
    v = state().View()
    equal(v.slots[1].selected, false, "Head no longer chosen")
    equal(v.slots[10].selected, true, "Legs chosen")
    equal(chosenSlot(v), "Legs", "slot title")
    equal(v.count, "30 appearances", "legs count under Not collected")
end)

test("state: a slot click in All goes to page 1, closes the list, keeps the Filter and sends nothing", function()
    local c = slotState()
    state().SetFilter("All")
    state().NextPage()
    state().ClickTile(state().View().tiles[1].appearance)
    c.advance(10)
    local sends = #c.ah.sends
    state().SelectSlot("legs")
    local v = state().View()
    equal(v.page, 1, "page")
    equal(v.list, nil, "item list closed")
    equal(v.filter, "All", "Filter kept")
    equal(v.mode, "All", "mode kept")
    equal(v.status, "Click an appearance to check the auction house.", "status line")
    c.advance(30)
    equal(#c.ah.sends, sends, "browses after the slot click")
end)

test("state: in For sale a slot click scans once; back on a scanned slot its kept result shows and nothing is sent", function()
    local c = slotState()
    c.ah.listings = { listing("Item 10101", 10101, 500), listing("Item 20011", 20011, 300) }
    state().SelectMode("For sale")
    c.advance(10)
    equal(#c.ah.sends, 1, "browses for head")
    equal(tileIDs(state().View()), "1010", "head's tile")
    state().SelectSlot("legs")
    equal(#c.ah.sends, 2, "legs scanned at once")
    equal(state().View().status, "Scanning legs", "status while scanning legs")
    c.advance(10)
    equal(tileIDs(state().View()), "2001", "legs' tile, never head's")
    c.advance(4 * 60)
    state().SelectSlot("head")
    local v = state().View()
    equal(#c.ah.sends, 2, "no browse on going back to head")
    equal(tileIDs(v), "1010", "head's kept result")
    equal(v.status, "Scanned 4 min ago", "with its age")
    state().SelectSlot("legs")
    equal(tileIDs(state().View()), "2001", "legs' kept result")
    equal(#c.ah.sends, 2, "no browse on going back to legs")
end)

test("state: the weapon type dropdown is answered on weapon slots only, starts on All weapon types and narrows without sending", function()
    local c = slotState()
    c.ah.listings = { listing("Item 30011", 30011, 500), listing("Item 40011", 40011, 300) }
    equal(state().View().weaponTypes, nil, "no dropdown on head")
    state().SetFilter("All")
    state().SelectSlot("mainhand")
    local v = state().View()
    check(v.weaponTypes, "a dropdown on main hand")
    equal(v.weaponTypes.text, "All weapon types", "starts on All weapon types")
    equal(v.weaponTypes.entries[1].name, "All weapon types", "first entry")
    equal(v.weaponTypes.entries[1].value, nil, "its value")
    equal(#v.weaponTypes.entries, 11, "All weapon types and the ten main hand types")
    equal(v.weaponTypes.entries[5].name, "Daggers", "the client's name of the fourth type")
    equal(v.count, "18 appearances", "daggers and swords")
    state().NextPage()
    state().SelectWeaponType(CAT.Dagger)
    v = state().View()
    equal(v.weaponTypes.text, "Daggers", "the chosen type")
    equal(v.page, 1, "page after the weapon type")
    equal(v.count, "10 appearances", "daggers only")
    for _, tile in ipairs(v.tiles) do equal(tile.appearance.category, CAT.Dagger, "every tile a dagger") end
    equal(v.tiles[1].weapon, true, "a weapon tile")
    -- For sale narrows by it without a new scan
    state().SelectMode("For sale")
    c.advance(10)
    equal(#c.ah.sends, 1, "one scan of main hand")
    equal(tileIDs(state().View()), "3001", "the dagger for sale only")
    state().SelectWeaponType(nil)
    equal(tileIDs(state().View()), "4001,3001", "both, cheapest first")
    state().SelectWeaponType(CAT.OneHSword)
    equal(tileIDs(state().View()), "4001", "the sword only")
    equal(#c.ah.sends, 1, "no scan for a weapon type")
    -- each slot starts on All weapon types
    state().SelectSlot("ranged")
    equal(state().View().weaponTypes.text, "All weapon types", "ranged starts on All weapon types")
    state().SelectSlot("mainhand")
    equal(state().View().weaponTypes.text, "All weapon types", "main hand starts again on All weapon types")
    -- a weapon type with nothing
    state().SelectMode("All")
    state().SelectWeaponType(CAT.Staff)
    v = state().View()
    equal(v.count, "0 appearances", "count with no staff")
    equal(v.empty.title, "No matches", "empty title")
    equal(v.empty.text, "No main hand appearances for Warlock.", "empty text")
end)

test("state: a slot change during a scan leaves at most one scan in flight and no result under the wrong slot", function()
    local c = slotState()
    c.ah.pageSize = 1
    for i = 1, 4 do c.ah.listings[i] = listing("Item " .. (10001 + i * 10), 10001 + i * 10, i * 100) end
    c.ah.listings[5] = listing("Item 20011", 20011, 50)
    state().SelectMode("For sale")
    c.advance(0.26)
    -- head's scan has its first page; legs needs a scan: head's is stopped
    state().SelectSlot("legs")
    local v = state().View()
    equal(v.status, "Scanning legs", "legs scanning")
    for _, tile in ipairs(v.tiles) do check(tile.placeholder, "only placeholders under legs while it scans") end
    c.advance(60)
    equal(#c.ah.sends, 2, "two browses, one after the other")
    -- the fake server ignores filters: legs gets all five rows, one a page
    equal(#c.ah.more, 4, "page requests: the four of legs, none of the stopped head scan")
    equal(tileIDs(state().View()), "2001", "legs' result only")
    state().SelectSlot("head")
    equal(#c.ah.sends, 3, "head was not kept and scans again")
    equal(state().View().status, "Scanning head", "head scanning")
    -- a slot change in All during a scan: it finishes and is kept under its slot
    c.advance(60)
    state().SelectMode("All")
    state().ScanAgain()
    c.advance(0.26)
    state().SelectSlot("legs")
    check(state().View().status:find("^Scanned "), "legs shows its own scan")
    c.advance(60)
    equal(#c.ah.sends, 4, "no browse for the slot change in All")
    state().SelectSlot("head")
    equal(state().View().status, "Scanned just now", "head's Scan again finished and kept")
    check(state().View().tiles[1].strip ~= "not checked", "head's tiles carry its result")
end)

test("state: titles, status texts and empty states carry the slot's name; a check result is kept when the player returns", function()
    local c = slotState({ appearances = (function()
        local list = manySlots()
        for _, a in ipairs(Fake.appearances(3, 3, CAT.Shirt, 7000)) do list[#list + 1] = a end
        return list
    end)() })
    c.ah.listings = { listing("Item 20011", 20011, 500) }
    state().SelectSlot("shirt")
    local v = state().View()
    equal(chosenSlot(v), "Shirt", "title")
    equal(v.empty.text, "Every shirt appearance for Warlock is collected.", "empty state")
    state().SelectMode("For sale")
    equal(state().View().status, "Scanning shirt", "status while scanning")
    c.advance(10)
    equal(state().View().empty.text, "No shirt appearance you have not collected is on the auction house right now.",
        "For sale empty state")
    state().SelectMode("All")
    state().SelectSlot("legs")
    state().ClickTile(state().View().tiles[1].appearance)
    c.advance(10)
    equal(state().View().tiles[1].price, "5s", "the check's price")
    state().SelectSlot("head")
    equal(state().View().tiles[1].strip, "not checked", "nothing of legs under head")
    state().SelectSlot("legs")
    local sends = #c.ah.sends
    equal(state().View().tiles[1].price, "5s", "the check kept on returning")
    state().ClickTile(state().View().tiles[1].appearance)
    equal(#c.ah.sends, sends, "no new check for the kept result")
    equal(state().View().list.foot.age, "Checked just now", "the list shows the check")
end)

test("state: the head's type line of a weapon is its weapon type", function()
    local c = slotState()
    state().SetFilter("All")
    state().SelectSlot("mainhand")
    state().SelectWeaponType(CAT.Dagger)
    state().ClickTile(state().View().tiles[1].appearance)
    c.advance(10)
    state().ClickTile(state().View().tiles[1].appearance)
    local l = state().View().list
    equal(l.typeText, "Daggers", "type line")
    equal(l.weapon, true, "a weapon list")
end)

test("state: a list opened from a scan names an item once its data is in, in its quality, and says Scanned until a check", function()
    local c = slotState({ items = { [10101] = { name = "Late Helm", quality = 3, bindType = 2, subType = "Cloth", load = 1 } } })
    c.ah.listings = { listing("Late Helm", 10101, 500) }
    state().SelectMode("For sale")
    c.advance(10)
    state().ClickTile(state().View().tiles[1].appearance)
    local row = state().View().list.rows[1]
    equal(row.name, nil, "no name before the item's data")
    c.advance(1.5)
    local l = state().View().list
    equal(l.rows[1].name, "Late Helm", "the name once the data is in")
    equal(l.rows[1].quality, 3, "its quality")
    equal(l.foot.age, "Scanned just now", "foot after the scan")
    state().CheckAgain()
    c.advance(10)
    equal(state().View().list.foot.age, "Checked just now", "foot after a check")
end)

-- The panel's slot buttons, in the row's order.
local function slotButtons(c)
    return findAll(c, function(w) return w.kind == "Button" and w.slot and w.ring end)
end

test("whole: the slot row's 14 buttons sit at x 136, y 4, 31 wide, 2 apart and 19 between groups, with the ring on the chosen", function()
    local c, tabs = visitTwice({ appearances = manySlots() })
    tabs[1].scripts.OnClick(tabs[1])
    local buttons = slotButtons(c)
    equal(#buttons, 14, "slot buttons")
    local xs = {}
    for i, b in ipairs(buttons) do xs[i] = b.points[1].x end
    equal(table.concat(xs, ","), "136,169,202,235,268,301,334,384,417,450,483,533,566,599", "x positions")
    equal(buttons[14].points[1].x + 31 - 136, 494, "the row is 494 wide")
    equal(buttons[1].points[1].y, -4, "y")
    check(visible(buttons[1].ring) and not visible(buttons[2].ring), "the ring on Head only")
    buttons[2].scripts.OnEnter(buttons[2])
    equal(GameTooltip.text, "Shoulder", "the slot's name on hover")
    buttons[10].scripts.OnClick(buttons[10])
    check(visible(buttons[10].ring) and not visible(buttons[1].ring), "the ring on Legs")
    check(not textShown(c, "Legs"), "no slot title")
end)

test("whole: clicking through all 14 slots in All sends nothing; in For sale exactly 14 browses", function()
    local c, tabs = visitTwice({ appearances = manySlots() })
    tabs[1].scripts.OnClick(tabs[1])
    local buttons = slotButtons(c)
    for _, b in ipairs(buttons) do b.scripts.OnClick(b); c.advance(1) end
    c.advance(30)
    equal(#c.ah.sends, 0, "browses in All")
    equal(#c.auctionTouches, 0, "C_AuctionHouse accesses in All")
    buttons[1].scripts.OnClick(buttons[1])
    local forSale = modeTab(c, "For sale")
    forSale.scripts.OnClick(forSale)
    c.advance(10)
    for i = 2, 14 do buttons[i].scripts.OnClick(buttons[i]); c.advance(10) end
    -- and back through them all: every result is kept
    for _, b in ipairs(buttons) do b.scripts.OnClick(b); c.advance(1) end
    equal(#c.ah.sends, 14, "browses in For sale")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
    equal(#c.forbidden, 0, "forbidden calls: " .. table.concat(c.forbidden, ", "))
end)

test("whole: weapon tiles show on their own 24 model frames, made on the first weapon slot, and the dropdown on weapon slots only", function()
    local c, tabs = visitTwice({ appearances = manySlots() })
    tabs[1].scripts.OnClick(tabs[1])
    local function models() return #findAll(c, function(w) return w.kind == "DressUpModel" end) end
    local dropdown = selector(c, 157)
    check(dropdown and not visible(dropdown), "no weapon type dropdown on head")
    equal(models(), 24, "armor models only")
    local buttons = slotButtons(c)
    buttons[10].scripts.OnClick(buttons[10])
    equal(models(), 24, "still no weapon model on legs")
    buttons[12].scripts.OnClick(buttons[12])
    check(visible(dropdown), "the dropdown on main hand")
    equal(dropdown.text, "All weapon types", "its text")
    equal(models(), 24 + 18, "a weapon model per weapon tile shown")
    equal(#c.itemAppearances, 18, "weapons set on their models")
    local frames = tileFrames(c)
    check(visible(frames[1].weaponModel) and not visible(frames[1].model), "the weapon model shown, the armor one hidden")
    equal(c.itemAppearances[1].model, frames[1].weaponModel, "the weapon on the tile's weapon model")
    local _, choose = openMenu(c, dropdown)
    local sends = #c.ah.sends
    check(choose("Daggers"), "a Daggers entry")
    check(textShown(c, "10 appearances"), "count after choosing daggers")
    equal(dropdown.text, "Daggers", "dropdown text")
    equal(#c.ah.sends, sends, "no browse for the weapon type")
    -- the head's small model is a weapon model too
    frames[1].button.scripts.OnClick(frames[1].button)
    c.advance(10)
    frames[1].button.scripts.OnClick(frames[1].button)
    check(find(c, function(w) return w.text == "Daggers" and visible(w) and under(w, itemListFrame(c)) end),
        "the head's type line")
    local list = itemListFrame(c)
    check(list.weaponModel and visible(list.weaponModel), "the head's weapon model")
    buttons[1].scripts.OnClick(buttons[1])
    check(not visible(dropdown), "the dropdown hidden on head")
    check(visible(frames[1].model) and not visible(frames[1].weaponModel), "armor model back on head")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

---------------------------------------------------------------- Fixes after review (F1 to F5)

-- What a model carries, as "inventory slot=source" in slot order.
local function carried(model)
    local keys, out = {}, {}
    for slotID in pairs(model.worn or {}) do keys[#keys + 1] = slotID end
    table.sort(keys)
    for i, slotID in ipairs(keys) do out[i] = slotID .. "=" .. model.worn[slotID] end
    return table.concat(out, ",")
end
local function undressCalls(c)
    local n = 0
    for _, w in ipairs(c.widgets) do n = n + (w.callCount.Undress or 0) end
    return n
end

test("F1: after Head, the Legs page carries only the Legs piece, in the tiles and in the item list's head", function()
    local c, tabs = visitTwice({ appearances = manySlots() })
    tabs[1].scripts.OnClick(tabs[1])
    local buttons = slotButtons(c)
    local frames = tileFrames(c)
    check(carried(frames[1].model):find("^1="), "Head's piece on tile 1, got " .. carried(frames[1].model))
    frames[1].button.scripts.OnClick(frames[1].button)
    c.advance(10)
    frames[1].button.scripts.OnClick(frames[1].button)
    local headModel = find(c, function(w) return w.kind == "DressUpModel" and w.parent == itemListFrame(c) end)
    check(carried(headModel):find("^1="), "Head's piece on the list's head model, got " .. carried(headModel))
    buttons[10].scripts.OnClick(buttons[10])
    local legs = TC.BrowserState.View().tiles[1].appearance
    check(carried(frames[1].model):find("^7=%d+$"), "only a Legs piece on tile 1, got " .. carried(frames[1].model))
    for i = 1, 24 do
        check(not carried(frames[i].model):find("1="), "no Head piece left on tile " .. i)
    end
    frames[1].button.scripts.OnClick(frames[1].button)
    c.advance(10)
    frames[1].button.scripts.OnClick(frames[1].button)
    check(carried(headModel):find("^7=%d+$"), "only a Legs piece on the list's head model, got " .. carried(headModel))
    equal(legs.slot, "legs", "the slot of the tile")
end)

test("F1: two pages of one slot make no Undress call", function()
    local c, tabs = visitTwice({ appearances = manySlots() })
    tabs[1].scripts.OnClick(tabs[1])
    local buttons = slotButtons(c)
    buttons[10].scripts.OnClick(buttons[10])
    TC.BrowserState.SetFilter("All")
    local before = undressCalls(c)
    TC.BrowserState.NextPage()
    TC.BrowserState.PreviousPage()
    local frames = tileFrames(c)
    frames[1].button.scripts.OnClick(frames[1].button)
    equal(undressCalls(c), before, "Undress calls while paging within Legs")
    check(carried(frames[1].model):find("^7=%d+$"), "a Legs piece, got " .. carried(frames[1].model))
end)

-- Flags that put the one-hand weapons in the off hand too.
local function offhandFlags()
    local info = { [5] = { "Shirt", false, false, false, false, false } }
    for category = 13, 17 do info[category] = { "W" .. category, true, false, true, true, false } end
    info[18] = { "Shields", true, false, false, true, false }
    info[19] = { "Held In Off-hand", true, false, false, true, false }
    return info
end

test("F2: the off-hand scan reads every weapon type the flags list, with the fixed split unchanged", function()
    local c = boot({ categoryInfo = offhandFlags() })
    local r = scanSlot(c, "offhand")
    check(r.result, "a result, got " .. tostring(r.reason))
    local out = {}
    for i, e in ipairs(r.query.itemClassFilters) do out[i] = e.classID .. "." .. e.subClassID .. "." .. (e.inventoryType or "-") end
    equal(table.concat(out, ","), "2.0.-,2.7.-,2.4.-,2.15.-,2.13.-,4.6.-,4.0.23", "off hand entries by flags")
    c = boot({ noCategoryInfo = true })
    r = scanSlot(c, "offhand")
    out = {}
    for i, e in ipairs(r.query.itemClassFilters) do out[i] = e.classID .. "." .. e.subClassID .. "." .. (e.inventoryType or "-") end
    equal(table.concat(out, ","), "4.6.-,4.0.23", "off hand entries without an answer")
    -- a category the table has no entry for is left out and the scan runs
    local info = offhandFlags()
    info[28] = { "Warglaives", true, false, true, true, false }
    c = boot({ categoryInfo = info })
    r = scanSlot(c, "offhand")
    check(r.result, "a scan with an unknown category, got " .. tostring(r.reason))
    equal(#r.query.itemClassFilters, 7, "entries without the unknown category")
end)

test("F3: an appearance listed in two weapon categories shows under each, once under all weapon types, in both modes", function()
    local list = manySlots()
    list[#list + 1] = { id = 3001, uiOrder = 9, minIlvl = 0, sources = { 30011 }, category = CAT.OneHSword, classes = { [9] = true } }
    local c = slotState({ appearances = list })
    state().SetFilter("All")
    state().SelectSlot("mainhand")
    local function shownIDs() return tileIDs(state().View()) end
    equal(state().View().count, "18 appearances", "all weapon types")
    for _, category in ipairs({ CAT.Dagger, CAT.OneHSword }) do
        state().SelectWeaponType(category)
        local expected = #TC.Appearances.List("mainhand", 9, category)
        equal(state().View().count, expected .. " appearances", "count for " .. category)
        local want = ids(TC.Appearances.List("mainhand", 9, category))
        equal(table.concat((function() local t = {} for _, tile in ipairs(state().View().tiles) do t[#t + 1] = tile.appearance.id end return t end)(), ","),
            want, "tiles for " .. category)
    end
    state().SelectWeaponType(nil)
    c.ah.listings = { listing("Item 30011", 30011, 500), listing("Item 30021", 30021, 300) }
    state().SelectMode("For sale")
    c.advance(10)
    equal(shownIDs(), "3002,3001", "for sale, all weapon types, 3001 once")
    state().SelectWeaponType(CAT.OneHSword)
    equal(shownIDs(), "3001", "for sale under swords")
    state().SelectWeaponType(CAT.Dagger)
    equal(shownIDs(), "3002,3001", "for sale under daggers")
end)

test("F4: flags that fit nothing for a weapon slot leave it the fixed split", function()
    local info = { [16] = { "Daggers", true, false, true, false, false } }
    boot({ categoryInfo = info })
    local out = {}
    for i, t in ipairs(TC.Appearances.WeaponTypes("ranged")) do out[i] = t.category end
    equal(table.concat(out, ","), "12,25,26,27", "ranged by the fixed split")
    equal(#TC.Appearances.WeaponTypes("mainhand"), 1, "main hand still by flags")
    local c = slotState({ categoryInfo = info })
    state().SelectSlot("ranged")
    equal(#state().View().weaponTypes.entries, 5, "All weapon types and the four ranged types")
    equal(state().View().count, "5 appearances", "bows are listed")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

test("a weapon slot click asks GetCategoryInfo once per weapon category", function()
    local c = slotState()
    local before = c.categoryInfoCalls
    state().SelectSlot("mainhand")
    local per = c.categoryInfoCalls - before
    equal(per, 18, "calls for Main hand (categories 12 to 29), once")
end)

---------------------------------------------------------------- Class filter (TC-32)

local ARMOR, WEAPON = 4, 2
local CLOTH, LEATHER, MAIL, PLATE, GENERIC = 1, 2, 3, 4, 0
-- Head appearances 101 to 107, in that order, one item per source (item id
-- = source id): 101 cloth, 102 leather, 103 mail, 104 plate, 105 an item
-- that gives no armor type, 106 Generic, 107 a plate and a leather item.
-- filler: that many more cloth appearances (ids 2001+, default items).
local function classFixture(filler, extraItems)
    local defs = {
        [1011] = { CLOTH, "Cloth Hood" }, [1021] = { LEATHER, "Leather Cap" }, [1031] = { MAIL, "Mail Coif" },
        [1041] = { PLATE, "Plate Helm" }, [1051] = { nil, "Odd Hat" }, [1061] = { GENERIC, "Generic Circlet" },
        [1071] = { PLATE, "Mixed Helm" }, [1072] = { LEATHER, "Mixed Cap" },
    }
    local items = {}
    for itemID, d in pairs(defs) do
        items[itemID] = { name = d[2], quality = 2, bindType = 2, subType = "Armor",
            classID = d[1] and ARMOR or nil, subClassID = d[1] }
    end
    for k, v in pairs(extraItems or {}) do items[k] = v end
    local list = {}
    for i = 1, 7 do
        local id = 100 + i
        list[i] = { id = id, uiOrder = 100 - i, sources = id == 107 and { 1071, 1072 } or { id * 10 + 1 },
            classes = { [9] = true } }
    end
    for _, a in ipairs(filler and filler > 0 and Fake.appearances(filler, 0, nil, 2000) or {}) do
        if not a.hide and a.classes[9] then a.uiOrder = -a.id; list[#list + 1] = a end
    end
    return { appearances = list, items = items }
end
local function shownIDs()
    local out = {}
    for i, tile in ipairs(TC.BrowserState.View().tiles) do out[i] = tile.appearance.id end
    return table.concat(out, ",")
end
local function classState(filler, opts)
    local o = classFixture(filler)
    for k, v in pairs(opts or {}) do o[k] = v end
    local c = bootState(o)
    TC.BrowserState.Refresh()
    TC.BrowserState.SetFilter("All")
    return c
end

test("class: All classes, then the client's nine classes in its order, the character's own marked and chosen", function()
    classState()
    local d = TC.BrowserState.View().classes
    check(d, "a class dropdown in the view")
    local names, values = {}, {}
    for i, e in ipairs(d.entries) do names[i], values[i] = e.name, tostring(e.value) end
    equal(table.concat(names, "|"), "All classes|Warrior|Paladin|Hunter|Rogue|Priest|Shaman|Mage|"
        .. "Warlock (this character)|Druid", "entries")
    equal(table.concat(values, ","), "all,1,2,3,4,5,7,8,9,11", "values")
    equal(d.text, "Warlock", "the chosen class")
    equal(d.classFile, "WARLOCK", "its class file, for the colour")
    equal(d.entries[9].selected, true, "the own class selected at the start")
    equal(d.entries[1].selected, false, "All classes not selected")
    TC.BrowserState.SelectClass("all")
    d = TC.BrowserState.View().classes
    equal(d.text, "All classes", "text for All classes")
    equal(d.classFile, nil, "no class colour for All classes")
    TC.BrowserState.Reset()
    TC.BrowserState.Refresh()
    equal(TC.BrowserState.View().classes.text, "Warlock", "a new visit starts on the own class")
end)

test("class: on an armor slot each class sees the armor types it wears; no armor type and Generic show for every class", function()
    classState()
    local expected = {
        [1] = "101,102,103,104,105,106,107", [2] = "101,102,103,104,105,106,107",
        [3] = "101,102,103,105,106,107", [7] = "101,102,103,105,106,107",
        [4] = "101,102,105,106,107", [11] = "101,102,105,106,107",
        [5] = "101,105,106", [8] = "101,105,106", [9] = "101,105,106",
    }
    equal(shownIDs(), expected[9], "the own class at the start")
    for _, classID in ipairs(Fake.CLASS_IDS) do
        TC.BrowserState.SelectClass(classID)
        equal(shownIDs(), expected[classID], "class " .. classID)
    end
    TC.BrowserState.SelectClass("all")
    equal(shownIDs(), "101,102,103,104,105,106,107", "All classes")
end)

test("class: without GetItemInfoInstant nothing is hidden", function()
    classState(0, { noItemInstant = true })
    TC.BrowserState.SelectClass(5)
    equal(shownIDs(), "101,102,103,104,105,106,107", "Priest without the call")
end)

test("class: Back, Shirt, Tabard and the weapon slots are not narrowed", function()
    local list, items = {}, {}
    for n, cat in ipairs({ CAT.Back, CAT.Shirt, CAT.Tabard, CAT.Dagger, CAT.Shield, CAT.Bow, CAT.Head }) do
        for _, a in ipairs(Fake.appearances(3, 0, cat, n * 1000)) do
            if not a.hide and a.classes[9] then
                list[#list + 1] = a
                for _, s in ipairs(a.sources) do
                    items[s] = { name = "Plate " .. s, quality = 2, bindType = 2, subType = "Plate",
                        classID = ARMOR, subClassID = PLATE }
                end
            end
        end
    end
    bootState({ appearances = list, items = items })
    TC.BrowserState.Refresh()
    TC.BrowserState.SetFilter("All")
    TC.BrowserState.SelectClass(9)
    equal(#TC.BrowserState.View().tiles, 0, "plate head is narrowed for a Warlock")
    for _, slot in ipairs({ "back", "shirt", "tabard", "mainhand", "offhand", "ranged" }) do
        TC.BrowserState.SelectSlot(slot)
        equal(#TC.BrowserState.View().tiles, 3, slot .. " under Warlock")
    end
end)

test("class: the count text's total follows the class", function()
    classState()
    equal(TC.BrowserState.View().count, "3 appearances", "Warlock")
    TC.BrowserState.SelectClass("all")
    equal(TC.BrowserState.View().count, "7 appearances", "All classes")
    TC.BrowserState.SelectClass(3)
    TC.BrowserState.SetFilter("Collected")
    local v = TC.BrowserState.View()
    equal(v.count, "0 of 6 appearances", "Hunter, Filter Collected")
    equal(v.empty.text, "No collected head appearances for Hunter.", "the empty state names the chosen class")
end)

test("class: a change keeps slot, mode, Filter and search, goes to page 1, closes the list only when its appearance left, sends nothing", function()
    local c = classState(50)
    -- the filler's items are the fake's cloth default
    TC.BrowserState.SelectClass(1)
    local plate
    for _, tile in ipairs(TC.BrowserState.View().tiles) do if tile.appearance.id == 104 then plate = tile end end
    click(plate)
    c.advance(10)
    TC.BrowserState.SetSearch("e")
    local sends, more, changes = #c.ah.sends, #c.ah.more, c.changes
    TC.BrowserState.NextPage()
    equal(TC.BrowserState.View().page, 2, "page 2 before the change")
    TC.BrowserState.SelectClass(4)
    local v = TC.BrowserState.View()
    equal(v.page, 1, "page after the change")
    equal(v.list, nil, "the plate appearance's list closed under Rogue")
    equal(chosenSlot(v), "Head", "slot kept")
    equal(v.mode, "All", "mode kept")
    equal(v.filter, "All", "Filter kept")
    equal(v.search, "e", "search text kept")
    check(c.changes > changes, "the change notification fired")
    local leather
    for _, tile in ipairs(v.tiles) do if tile.appearance.id == 102 then leather = tile end end
    click(leather)
    c.advance(10)
    click(leather)
    sends, more = #c.ah.sends, #c.ah.more
    TC.BrowserState.SelectClass(11)
    v = TC.BrowserState.View()
    check(v.list and v.list.appearance.id == 102, "the leather appearance's list stays open under Druid")
    TC.BrowserState.SelectClass(11)
    c.advance(10)
    equal(#c.ah.sends, sends, "browses for class changes")
    equal(#c.ah.more, more, "page requests for class changes")
end)

test("class: a change keeps the weapon type", function()
    slotState()
    state().SelectSlot("mainhand")
    local daggers
    for _, e in ipairs(state().View().weaponTypes.entries) do if e.name == "Daggers" then daggers = e.value end end
    state().SelectWeaponType(daggers)
    state().SelectClass(1)
    equal(state().View().weaponTypes.text, "Daggers", "weapon type after the class change")
    equal(chosenSlot(state().View()), "Main hand", "slot after the class change")
end)

test("class: in For sale a class change narrows on the client without a scan", function()
    local o = classFixture(0)
    local c = bootState(o)
    TC.BrowserState.Refresh()
    for _, itemID in ipairs({ 1011, 1021, 1041 }) do
        c.ah.listings[#c.ah.listings + 1] = listing(o.items[itemID].name, itemID, itemID)
    end
    TC.BrowserState.SelectClass("all")
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    equal(shownIDs(), "101,102,104", "for sale under All classes, cheapest first")
    local sends = #c.ah.sends
    TC.BrowserState.SelectClass(5)
    equal(shownIDs(), "101", "for sale under Priest")
    equal(TC.BrowserState.View().count, "1 of 3 appearances", "count under Priest")
    TC.BrowserState.SelectClass(4)
    equal(shownIDs(), "101,102", "for sale under Rogue")
    equal(TC.BrowserState.View().mode, "For sale", "mode kept")
    c.advance(10)
    equal(#c.ah.sends, sends, "browses for the class changes")
end)

test("class: no class filter write for another class, and no list read again", function()
    local c = classState()
    local reads = c.listCalls
    for _, classID in ipairs(Fake.CLASS_IDS) do TC.BrowserState.SelectClass(classID) end
    TC.BrowserState.SelectClass("all")
    TC.BrowserState.SelectSlot("legs")
    TC.BrowserState.SelectSlot("head")
    equal(c.setClassCalls, nil, "SetClassFilter calls")
    equal(c.listCalls, reads + 1, "list reads: legs once")
    equal(c.collections.classFilter, 9, "Collections' class filter")
end)

test("class: without the class list calls the dropdown holds All classes and the own class", function()
    classState(0, { noClassList = true })
    local d = TC.BrowserState.View().classes
    local names = {}
    for i, e in ipairs(d.entries) do names[i] = e.name end
    equal(table.concat(names, "|"), "All classes|Warlock (this character)", "entries")
    equal(d.text, "Warlock", "chosen")
end)

---------------------------------------------------------------- Search (TC-32)

-- Head appearances: 201 (items 2011 "Willow Hood", cached, and 2012 "Owl
-- Mask", loading 0.5 s after the request), 202 ("Linen Cap", cached), 203
-- ("Silk Cowl", whose load fails), 204 ("Shadow Hood", never loads).
local function searchState(opts)
    opts = opts or {}
    opts.appearances = opts.appearances or {
        { id = 201, uiOrder = 9, sources = { 2011, 2012 }, classes = { [9] = true } },
        { id = 202, uiOrder = 8, sources = { 2021 }, classes = { [9] = true } },
        { id = 203, uiOrder = 7, sources = { 2031 }, classes = { [9] = true } },
        { id = 204, uiOrder = 6, sources = { 2041 }, classes = { [9] = true } },
    }
    opts.items = opts.items or {
        [2011] = { name = "Willow Hood", quality = 2, bindType = 2 },
        [2012] = { name = "Owl Mask", quality = 2, bindType = 2, load = 0.5 },
        [2021] = { name = "Linen Cap", quality = 2, bindType = 2 },
        [2031] = { name = "Silk Cowl", quality = 2, bindType = 2, load = "fail" },
        [2041] = { name = "Shadow Hood", quality = 2, bindType = 2, load = "never" },
    }
    local c = bootState(opts)
    TC.BrowserState.Refresh()
    TC.BrowserState.SetFilter("All")
    return c
end
local function requestsOf(c, itemID)
    local n = 0
    for _, id in ipairs(c.loadRequests) do if id == itemID then n = n + 1 end end
    return n
end

test("search: case does not matter and any part of a name matches", function()
    searchState()
    TC.BrowserState.SetSearch("HOOD")
    equal(shownIDs(), "201", "HOOD (Shadow Hood never loaded)")
    TC.BrowserState.SetSearch("inen c")
    equal(shownIDs(), "202", "a middle part")
    TC.BrowserState.SetSearch("")
    equal(shownIDs(), "201,202,203,204", "empty text")
    equal(TC.BrowserState.View().count, "4 appearances", "count without search")
    TC.BrowserState.SetSearch("cap")
    equal(TC.BrowserState.View().count, "1 of 4 appearances", "count with search")
end)

test("search: an appearance of two items matches by either, also by a name that loads later, and the view is told", function()
    local c = searchState()
    TC.BrowserState.SetSearch("willow")
    equal(shownIDs(), "201", "by the first item")
    TC.BrowserState.SetSearch("owl m")
    equal(shownIDs(), "", "the second item's name not loaded yet")
    local changes = c.changes
    c.advance(1)
    equal(shownIDs(), "201", "by the second item once it loaded")
    check(c.changes > changes, "the change notification fired for the name")
end)

test("search: the first keystroke on a slot asks for the missing names, 20 per frame; a later one asks nothing", function()
    local list, items = {}, {}
    for i = 1, 45 do
        list[i] = { id = 300 + i, uiOrder = -i, sources = { 3000 + i }, classes = { [9] = true } }
        items[3000 + i] = { name = "Name " .. i, quality = 2, bindType = 2, load = 5 }
    end
    list[46] = { id = 400, uiOrder = -50, sources = { 4000 }, classes = { [9] = true } }
    local c = searchState({ appearances = list, items = items })
    TC.BrowserState.SelectClass(5)
    TC.BrowserState.SelectSlot("legs")
    TC.BrowserState.SelectSlot("head")
    c.advance(3)
    equal(#c.loadRequests, 0, "item data requests before any search")
    TC.BrowserState.SetSearch("n")
    equal(#c.loadRequests, 20, "requests on the first keystroke")
    c.frame()
    equal(#c.loadRequests, 40, "after one frame")
    c.frame()
    equal(#c.loadRequests, 45, "after two frames: every missing name, the cached one not")
    TC.BrowserState.SetSearch("na")
    TC.BrowserState.SetSearch("")
    TC.BrowserState.SetSearch("nam")
    c.advance(10)
    equal(#c.loadRequests, 45, "requests after later keystrokes")
    equal(shownIDs(), "301,302,303,304,305,306,307,308,309,310,311,312,313,314,315,316,317,318,319,320,321,322,323,324",
        "page 1 once the names loaded")
end)

test("search: an item whose load failed is not asked again in the visit, also not by a check", function()
    local c = searchState()
    TC.BrowserState.SetSearch("s")
    c.advance(1)
    equal(requestsOf(c, 2031), 1, "the failing item asked once")
    TC.BrowserState.SelectSlot("legs")
    TC.BrowserState.SelectSlot("head")
    TC.BrowserState.SetSearch("si")
    TC.BrowserState.SetSearch("")
    for _, tile in ipairs(TC.BrowserState.View().tiles) do
        if tile.appearance.id == 203 then click(tile) end
    end
    c.advance(5)
    equal(requestsOf(c, 2031), 1, "asked again after the failure")
    for _, tile in ipairs(TC.BrowserState.View().tiles) do
        if tile.appearance.id == 203 then click(tile) end
    end
    equal(TC.BrowserState.View().list.state, "cannot be sold", "its only item is not on this server")
    equal(#c.ah.sends, 0, "browses for it")
end)

test("search: For sale also matches the name of an item variant the scan found; All does not", function()
    local c = scanState(SAMPLE)
    c.ah.listings[#c.ah.listings + 1] = listing("Item 10501", 10501, 900, { itemSuffix = 7 })
    c.ah.keyNames["10501:7"] = "Item 10501 of the Owl"
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    TC.BrowserState.SetSearch("OWL")
    -- the keystroke asks for the variant's name; it is not known yet
    equal(shownIDs(), "", "before the client has the variant's name")
    c.advance(1)
    -- the client's event for the item (the panel forwards it)
    TC.BrowserState.KeyInfoReceived(10501)
    c.advance(1)
    equal(shownIDs(), "1050", "the variant's name matches in For sale")
    TC.BrowserState.SetSearch("item 1010")
    equal(shownIDs(), "1010", "an item name matches in For sale")
    TC.BrowserState.SetSearch("owl")
    TC.BrowserState.SelectMode("All")
    equal(shownIDs(), "", "All matches item names only")
end)

test("search: typing goes to page 1; Clear search ends the empty state", function()
    local c = bootState()
    TC.BrowserState.Refresh()
    TC.BrowserState.NextPage()
    TC.BrowserState.SetSearch("item 1")
    equal(TC.BrowserState.View().page, 1, "page after typing")
    TC.BrowserState.SetSearch("owl")
    local v = TC.BrowserState.View()
    equal(#v.tiles, 0, "tiles")
    equal(v.empty.title, "No matches", "empty title")
    equal(v.empty.text, "No head appearance has an item named like \"owl\".", "empty text")
    equal(v.empty.button, "Clear search", "empty button")
    v.empty.action()
    v = TC.BrowserState.View()
    equal(v.search, "", "search after Clear search")
    equal(#v.tiles, 24, "tiles after Clear search")
    equal(v.empty, nil, "no empty state")
    equal(#c.ah.sends, 0, "browses")
end)

test("search: the text is kept across slot, class and mode changes and cleared when the auction window closes", function()
    local c = scanState(SAMPLE)
    TC.BrowserState.SetSearch("Item 1")
    TC.BrowserState.SelectSlot("legs")
    TC.BrowserState.SelectClass(1)
    TC.BrowserState.SelectMode("For sale")
    TC.BrowserState.SelectSlot("head")
    c.advance(10)
    equal(TC.BrowserState.View().search, "Item 1", "kept")
    TC.BrowserState.Reset()
    TC.BrowserState.Refresh()
    equal(TC.BrowserState.View().search, "", "cleared by a new visit")
end)

test("search: typing and clearing send nothing to the auction house", function()
    local c = searchState()
    for _, text in ipairs({ "w", "wi", "wil", "", "owl", "zzz", "" }) do
        TC.BrowserState.SetSearch(text)
        c.advance(1)
    end
    equal(#c.ah.sends, 0, "browses")
    equal(#c.ah.more, 0, "page requests")
    equal(#c.forbidden, 0, "forbidden calls")
end)

---------------------------------------------------------------- Check: items not on this server (TC-32)

local function failedState(defs, listings)
    local items, sources = {}, {}
    for i, d in ipairs(defs) do
        sources[i] = d[1]
        items[d[1]] = { name = d[2], quality = 2, bindType = BOE, subType = "Cloth", load = d[3] }
    end
    local c = bootState({ appearances = { { id = 1, uiOrder = 1, sources = sources, classes = { [9] = true } } },
        items = items })
    c.ah.listings = listings or {}
    TC.BrowserState.Refresh()
    TC.BrowserState.SetFilter("All")
    click(TC.BrowserState.View().tiles[1])
    c.advance(10)
    return c, TC.BrowserState.View()
end

test("check: an item whose load failed is not looked up and not counted; with one found the list is Found, 1 item", function()
    local c, v = failedState({ { 11, "Willow Boots" }, { 12, "Ivy Boots", "fail" } }, { listing("Willow Boots", 11, 500) })
    equal(sentNames(c), "Willow Boots", "names browsed")
    click(v.tiles[1])
    v = TC.BrowserState.View()
    equal(v.list.state, "found", "list state")
    equal(v.list.foot.note, nil, "no Could not check line")
    c, v = failedState({ { 11, "Willow Boots" }, { 12, "Ivy Boots", "fail" } })
    click(v.tiles[1])
    v = TC.BrowserState.View()
    equal(v.list.state, "not for sale", "the found item not listed")
    equal(v.tiles[1].strip, "not for sale", "strip")
end)

test("check: every item failed to load gives Cannot be sold and sends nothing", function()
    local c, v = failedState({ { 11, "Willow Boots", "fail" }, { 12, "Ivy Boots", "fail" } })
    equal(#c.ah.sends, 0, "browses")
    click(v.tiles[1])
    v = TC.BrowserState.View()
    equal(v.list.state, "cannot be sold", "list state")
    equal(v.tiles[1].strip, "not for sale", "strip")
end)

test("check: an item that never answers still gives Could not check", function()
    local c, v = failedState({ { 11, "Willow Boots" }, { 12, "Ivy Boots", "never" } })
    equal(v.list, nil, "no flyout for a check that kept nothing")
    equal(v.tiles[1].strip, "no answer", "the strip says so")
    equal(sentNames(c), "Willow Boots", "names browsed")
end)

---------------------------------------------------------------- Whole: class and Search (TC-32)

local function searchBox(c)
    return find(c, function(w) return w.kind == "EditBox" end)
end
-- Opens the funnel's menu; answers the texts of its class submenu, without
-- the line, and a function choosing an entry by its text.
local function classEntries(c)
    openMenu(c, funnelOf(c))
    for _, e in ipairs(c.menuEntries()) do
        if e ~= "-" and e.submenu then
            local names = {}
            for _, s in ipairs(e.submenu) do if s ~= "-" then names[#names + 1] = s.text end end
            return names, c.choose, e.text
        end
    end
end

test("whole: Search at x 642, y 9, 108 x 20 with its placeholder; Escape in it keeps the window", function()
    local c, tabs = visitTwice(classFixture(0))
    tabs[1].scripts.OnClick(tabs[1])
    local box = searchBox(c)
    check(box and visible(box), "a shown search box")
    equal(box.width, 108, "search width")
    equal(box.height, 20, "search height")
    equal(box.points[1].x .. "," .. box.points[1].y, "642,-9", "search position")
    check(textShown(c, "Search"), "the placeholder")
    c.type(box, "x")
    check(not textShown(c, "Search"), "no placeholder while there is text")
    check(box.scripts.OnEscapePressed, "Escape has a handler")
    box.scripts.OnEscapePressed(box)
    equal(box.focus, false, "Escape clears the focus")
    check(AuctionHouseFrame:IsShown(), "the auction window stays open")
end)

test("whole: opening the tab, every class entry and typing send nothing and request no item data", function()
    local c, tabs = visitTwice(classFixture(0))
    tabs[1].scripts.OnClick(tabs[1])
    local labels, title = {}, nil
    for i = 1, 10 do
        local names, choose = classEntries(c)
        equal(#names, 10, "entries shown")
        labels[i] = names[i]
        choose(names[i])
        c.advance(1)
    end
    labels[11], labels[12], title = classEntries(c)
    equal(labels[9], "|cffWARLOCKWarlock (this character)|r", "the own entry, in its colour")
    equal(labels[1], "All classes", "the first entry")
    equal(title, "Class: |cffDRUIDDruid|r", "the submenu names Druid")
    check(textShown(c, "5 appearances"), "count under Druid")
    equal(#c.loadRequests, 0, "item data requests before typing")
    local box = searchBox(c)
    c.type(box, "cap")
    c.advance(3)
    check(textShown(c, "2 of 5 appearances"), "count after typing")
    c.type(box, "")
    c.advance(3)
    equal(#c.ah.sends, 0, "browses")
    equal(#c.ah.more, 0, "page requests")
    equal(#c.auctionTouches, 0, "C_AuctionHouse accesses (" .. table.concat(c.auctionTouches, ", ") .. ")")
end)

test("whole: Clear search empties the box; closing the window clears the search text", function()
    local c, tabs = visitTwice(classFixture(0))
    tabs[1].scripts.OnClick(tabs[1])
    local box = searchBox(c)
    c.type(box, "zzz")
    local clear = find(c, function(w) return w.kind == "Button" and w.text == "Clear search" and visible(w) end)
    check(clear, "a shown Clear search button")
    clear.scripts.OnClick(clear)
    equal(box.text, "", "box after Clear search")
    check(textShown(c, "3 appearances"), "count after Clear search")
    c.type(box, "cap")
    c.closeAuction()
    c.openAuction()
    tabs[1].scripts.OnClick(tabs[1])
    equal(box.text, "", "box after a new visit")
    equal(TC.BrowserState.View().search, "", "state after a new visit")
end)

test("whole: a weapon model's camera is never moved out", function()
    local c, tabs = visitTwice({ appearances = manySlots() })
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    local buttons = slotButtons(c)
    buttons[12].scripts.OnClick(buttons[12])
    equal(frames[1].weaponModel.calls.SetCameraPosition, nil, "the weapon model's camera untouched")
end)

---------------------------------------------------------------- Fixes after review (TC-32)

-- The default 370 Head appearances, each source for sale as two item
-- variants (suffix 1 has a name, suffix 2 never does), the tab open, For
-- sale scanned.
local function keyRun()
    local apps = Fake.appearances(370, 5)
    local c, tabs = visitTwice({ appearances = apps })
    c.ah.pageSize = 500
    local n = 0
    for _, a in ipairs(apps) do
        if not a.hide then
            for _, s in ipairs(a.sources) do
                for suffix = 1, 2 do
                    n = n + 1
                    c.ah.listings[#c.ah.listings + 1] = listing("Item " .. s, s, 1000 + n, { itemSuffix = suffix })
                    if suffix == 1 then c.ah.keyNames[s .. ":1"] = "Item " .. s .. " of the Bear" end
                end
            end
        end
    end
    table.sort(c.ah.listings, function(a, b) return a.minPrice < b.minPrice end)
    tabs[1].scripts.OnClick(tabs[1])
    local forSale = modeTab(c, "For sale")
    forSale.scripts.OnClick(forSale)
    c.advance(20)
    return c, tabs, searchBox(c)
end

test("fix F1: Search in For sale asks each item key at most twice, 20 per frame, and View asks none", function()
    local c, _, box = keyRun()
    local base = c.ah.keyInfoCalls
    c.type(box, "z")
    equal(c.ah.keyInfoCalls - base, 20, "calls in the keystroke's frame")
    local most = 0
    for _ = 1, 400 do
        local before = c.ah.keyInfoCalls
        c.frame()
        most = math.max(most, c.ah.keyInfoCalls - before)
    end
    check(most <= 20, "at most 20 calls in a later frame, got " .. most)
    local keys, worst = 0, 0
    for _, count in pairs(c.ah.keyCount) do keys, worst = keys + 1, math.max(worst, count) end
    check(keys > 700, "the run asked for many keys, got " .. keys)
    check(worst <= 2, "no key asked more than twice, got " .. worst)
    local before = c.ah.keyInfoCalls
    for _ = 1, 10 do TC.BrowserState.View() end
    equal(c.ah.keyInfoCalls, before, "calls by ten Views")
    c.type(box, "bear")
    c.advance(2)
    check(#TC.BrowserState.View().tiles > 0, "a variant name that arrived makes its appearances match")
    equal(c.ah.keyInfoCalls, before, "calls by a keystroke over names already asked")
end)

test("fix F1: nothing is asked after leaving the tab or closing the window; coming back does not resume", function()
    local c, tabs, box = keyRun()
    c.type(box, "z")
    c.frame()
    selectBuy()
    tabs[1].frameRef:Hide()
    local base = c.ah.keyInfoCalls
    c.advance(5)
    c.fire("ITEM_KEY_ITEM_INFO_RECEIVED", 10011)
    c.advance(5)
    equal(c.ah.keyInfoCalls, base, "calls while the tab is left")
    tabs[1].scripts.OnClick(tabs[1])
    c.advance(5)
    equal(c.ah.keyInfoCalls, base, "calls after coming back, with no keystroke")
    c.type(box, "zq")
    check(c.ah.keyInfoCalls > base, "the next keystroke asks again")
    c.frame()
    c.closeAuction()
    base = c.ah.keyInfoCalls
    c.advance(5)
    equal(c.ah.keyInfoCalls, base, "calls after the window closed")
end)

-- 45 Head appearances whose items load after 5 s, then 30 Legs ones likewise.
local function loaderFixture()
    local apps, items = {}, {}
    for i = 1, 45 do
        apps[i] = { id = 300 + i, uiOrder = -i, sources = { 3000 + i }, classes = { [9] = true } }
        items[3000 + i] = { name = "Name " .. i, quality = 2, bindType = 2, load = 5 }
    end
    for _, a in ipairs(Fake.appearances(30, 0, CAT.Legs, 2000)) do
        apps[#apps + 1] = a
        for _, s in ipairs(a.sources) do items[s] = { name = "Leg " .. s, quality = 2, bindType = 2, load = 5 } end
    end
    return searchState({ appearances = apps, items = items })
end
local function legRequests(c)
    local n = 0
    for _, id in ipairs(c.loadRequests) do if id > 20000 then n = n + 1 end end
    return n
end

test("fix F3: the name loader stops on leaving the tab, on closing, and for the old slot on a slot change", function()
    local c = loaderFixture()
    TC.BrowserState.SetSearch("n")
    equal(#c.loadRequests, 20, "requests on the keystroke")
    TC.BrowserState.Leave()
    c.advance(3)
    equal(#c.loadRequests, 20, "requests after leaving the tab")
    c = loaderFixture()
    TC.BrowserState.SetSearch("n")
    TC.BrowserState.Reset()
    c.advance(3)
    equal(#c.loadRequests, 20, "requests after the window closed")
    c = loaderFixture()
    TC.BrowserState.SetSearch("n")
    TC.BrowserState.SelectSlot("legs")
    c.advance(3)
    for id = 3021, 3045 do equal(requestsOf(c, id), 0, "the old slot's item " .. id .. " asked after the change") end
end)

test("fix F4: a kept search text is live on a new slot, 20 names per frame; with no text nothing is asked", function()
    local c = loaderFixture()
    TC.BrowserState.SetSearch("leg")
    TC.BrowserState.SelectSlot("legs")
    equal(legRequests(c), 20, "legs requests on the slot change")
    c.frame()
    equal(legRequests(c), 40, "after one frame")
    c.advance(1)
    equal(legRequests(c), 90, "every legs item once")
    c.advance(6)
    check(#TC.BrowserState.View().tiles > 0, "tiles appear as the names load")
    c = loaderFixture()
    TC.BrowserState.SelectSlot("legs")
    c.advance(3)
    equal(#c.loadRequests, 0, "requests on a slot change with empty text")
end)

test("fix F2: an appearance with a Cosmetic and a Leather item shows under a cloth class", function()
    local apps = { { id = 1, uiOrder = 1, sources = { 11, 12 }, classes = { [9] = true } },
        { id = 2, uiOrder = 2, sources = { 21 }, classes = { [9] = true } },
        { id = 3, uiOrder = 3, sources = { 31 }, classes = { [9] = true } } }
    local items = { [11] = { name = "Cos", quality = 2, bindType = 2, classID = 4, subClassID = 5 },
        [12] = { name = "Lea", quality = 2, bindType = 2, classID = 4, subClassID = 2 },
        [21] = { name = "Cos2", quality = 2, bindType = 2, classID = 4, subClassID = 5 },
        [31] = { name = "Lea2", quality = 2, bindType = 2, classID = 4, subClassID = 2 } }
    bootState({ appearances = apps, items = items })
    TC.BrowserState.Refresh()
    TC.BrowserState.SetFilter("All")
    local shown = {}
    for _, tile in ipairs(TC.BrowserState.View().tiles) do shown[#shown + 1] = tile.appearance.id end
    table.sort(shown)
    equal(table.concat(shown, ","), "1,2", "Warlock sees Cosmetic plus Leather and Cosmetic alone, not Leather alone")
end)

test("search: pattern characters and edge spaces in the text match literally and never raise", function()
    searchState({ items = {
        [2011] = { name = "Fire%Hood", quality = 2, bindType = 2 }, [2012] = { name = "Owl Mask", quality = 2, bindType = 2 },
        [2021] = { name = "Cap (Red)", quality = 2, bindType = 2 }, [2031] = { name = "Wool-Cap", quality = 2, bindType = 2 },
        [2041] = { name = "Hood [II]", quality = 2, bindType = 2 } } })
    local cases = { { "%", "201" }, { "(", "202" }, { "-", "203" }, { "[", "204" }, { "%a", "" }, { "%", "201" },
        { " (red", "202" }, { "red) ", "" }, { "fire%h", "201" }, { " ", "201,202,204" }, { "[ii]", "204" },
        { "owl mask ", "" }, { ".", "" }, { "^", "" }, { "$", "" } }
    for _, case in ipairs(cases) do
        local ok, err = pcall(TC.BrowserState.SetSearch, case[1])
        check(ok, "SetSearch(" .. case[1] .. ") raised: " .. tostring(err))
        equal(shownIDs(), case[2], "text '" .. case[1] .. "'")
    end
end)

---------------------------------------------------------------- Fixes after the in-game check of step 6 (TC-32)

-- Head's listings are 1001 to 1005, all collected, so a finished scan of
-- For sale finds nothing to show, unless extra adds an uncollected one; pages
-- of 2 keep the scan running a while.
local function collectedOnly(extra)
    local prices = { [1001] = 100, [1002] = 110, [1003] = 120, [1004] = 130, [1005] = 140 }
    for id, price in pairs(extra or {}) do prices[id] = price end
    local c = scanState(prices)
    c.ah.pageSize = 2
    return c
end

test("fix2 F1: a scan running with a search text that matches nothing shows placeholders and no empty state; the scan ends: the Search empty state, no tile", function()
    local c = collectedOnly({ [1010] = 50 })
    TC.BrowserState.SelectMode("For sale")
    TC.BrowserState.SetSearch("zzz")
    c.advance(0.26)
    local v = TC.BrowserState.View()
    equal(v.status, "Scanning head", "status")
    equal(v.empty, nil, "no empty state while the scan runs")
    equal(#v.tiles, 24, "placeholders fill the page")
    for _, tile in ipairs(v.tiles) do check(tile.placeholder, "only placeholders") end
    c.advance(30)
    v = TC.BrowserState.View()
    check(v.empty, "an empty state after the scan")
    equal(v.empty.title, "No matches", "title")
    equal(v.empty.button, "Clear search", "the Search empty state")
    equal(#v.tiles, 0, "no tile beside the empty state")
end)

test("fix2 F1: without a search text the same scan ends in Nothing for sale, with no tile and no placeholder", function()
    local c = collectedOnly()
    TC.BrowserState.SelectMode("For sale")
    c.advance(0.26)
    local v = TC.BrowserState.View()
    equal(v.empty, nil, "no empty state while the scan runs")
    equal(#v.tiles, 24, "placeholders while it runs")
    c.advance(30)
    v = TC.BrowserState.View()
    check(v.empty, "an empty state after the scan")
    equal(v.empty.title, "Nothing for sale", "title")
    equal(#v.tiles, 0, "no tile beside the empty state")
end)

test("fix2 F2: every placeholder of a page is framed with the same camera", function()
    local c, tabs = visitTwice({ appearances = Fake.appearances(370, 5) })
    -- every appearance has its own camera, so tiles last used differ
    C_TransmogCollection.GetAppearanceCameraID = function(id) return 100 + id % 7 end
    c.ah.pageSize = 2
    for id = 1010, 1050, 10 do c.ah.listings[#c.ah.listings + 1] = listing("Item " .. (id * 10 + 1), id * 10 + 1, id) end
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    local before = {}
    for i = 3, 24 do before[frames[i].model.uiCamera or 0] = true end
    local distinct = 0
    for _ in pairs(before) do distinct = distinct + 1 end
    check(distinct > 1, "the tiles differ in camera before the scan, got " .. distinct)
    local forSale = modeTab(c, "For sale")
    forSale.scripts.OnClick(forSale)
    c.advance(0.26)
    local cameras, n = {}, 0
    for _, frame in ipairs(frames) do
        if visible(frame.bar) then
            n = n + 1
            check(visible(frame.model), "a placeholder's figure is shown")
            cameras[frame.model.uiCamera or 0] = true
        end
    end
    equal(n, 22, "placeholders")
    local kinds = 0
    for camera in pairs(cameras) do kinds = kinds + 1; check(camera ~= 0, "a camera was applied") end
    equal(kinds, 1, "cameras among the placeholders")
end)

test("fix2 F3: the zoom is a value of the slot table: Back 1.236, every other slot none", function()
    equal(TC.Slots.back.zoom, 1.236, "Back's zoom")
    for _, slot in ipairs(TC.Slots) do
        if slot.key ~= "back" then equal(slot.zoom, nil, slot.key .. " has no zoom") end
    end
end)

test("fix2 F3: a Back tile and the item list's model get 1.236; a Head and a Feet tile get 1", function()
    local apps = Fake.appearances(370, 5)
    for _, a in ipairs(Fake.appearances(10, 0, CAT.Feet, 2000)) do apps[#apps + 1] = a end
    for _, a in ipairs(Fake.appearances(10, 0, CAT.Back, 8000)) do apps[#apps + 1] = a end
    local c, tabs = visitTwice({ appearances = apps })
    tabs[1].scripts.OnClick(tabs[1])
    local frames, buttons = tileFrames(c), slotButtons(c)
    equal(frames[1].model.calls.SetCameraPosition, nil, "Head: the camera is not moved")
    buttons[11].scripts.OnClick(buttons[11])
    equal(frames[1].model.calls.SetCameraPosition, nil, "Feet: the camera is not moved")
    buttons[3].scripts.OnClick(buttons[3])
    local p = frames[1].model.calls.SetCameraPosition
    check(p and math.abs(p[1] - 4 * 1.236) < 1e-9, "Back: camera distance 4 x 1.236, got " .. tostring(p and p[1]))
    frames[1].button.scripts.OnClick(frames[1].button)
    c.advance(10)
    frames[1].button.scripts.OnClick(frames[1].button)
    local list, listModel = itemListFrame(c)
    for _, w in ipairs(list.children) do if w.kind == "DressUpModel" and w ~= list.weaponModel then listModel = w end end
    local q = listModel.calls.SetCameraPosition
    check(q and math.abs(q[1] - 4 * 1.236) < 1e-9, "Back's list model: 4 x 1.236, got " .. tostring(q and q[1]))
end)

---------------------------------------------------------------- Buy and confirm (step 7, TC-33): state

test("buy state: a found row of a check list can be bought; checking and not-for-sale rows cannot", function()
    local c, tiles = checkState({ [1] = { 500, 700 } })
    click(tiles[1])
    c.advance(5)
    click(tiles[1])
    TC.BrowserState.CheckAgain()
    local v = TC.BrowserState.View()
    equal(v.list.state, "checking", "checking")
    for i, row in ipairs(v.list.rows) do equal(row.buy, nil, "no Buy on checking row " .. i) end
    c.advance(5)
    v = TC.BrowserState.View()
    equal(v.list.state, "found", "found")
    equal(#v.list.rows, 2, "two item variants")
    for i, row in ipairs(v.list.rows) do
        check(row.buy, "Buy on found row " .. i)
        equal(row.buy.enabled, true, "Buy enabled on found row " .. i)
    end
    click(tiles[2])
    c.advance(5)
    click(tiles[2])
    v = TC.BrowserState.View()
    equal(v.list.state, "not for sale", "not for sale")
    for i, row in ipairs(v.list.rows) do equal(row.buy, nil, "no Buy on a not-for-sale row " .. i) end
    equal(#c.ah.searches, 0, "searches")
    equal(#c.ah.bids, 0, "bids")
end)

test("buy state: a found row of a scan list can be bought; while a read runs its Buy is off", function()
    local c = scanState(SAMPLE)
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    local v = TC.BrowserState.View()
    TC.BrowserState.ClickTile(v.tiles[1].appearance)
    v = TC.BrowserState.View()
    equal(v.list.state, "found", "a list from the scan")
    check(v.list.rows[1].buy, "Buy on a scan row")
    equal(v.list.rows[1].buy.enabled, true, "Buy enabled")
    TC.BrowserState.ScanAgain()
    v = TC.BrowserState.View()
    check(v.list.rows[1].buy, "Buy shown while the scan runs")
    equal(v.list.rows[1].buy.enabled, false, "Buy off while the scan runs")
    c.advance(10)
    TC.BrowserState.CheckAgain()
    equal(TC.BrowserState.View().list.state, "checking", "checking")
    c.advance(10)
    equal(TC.BrowserState.View().list.rows[1].buy.enabled, true, "Buy on again once the reads ended")
    equal(#c.ah.searches, 0, "searches")
    equal(#c.ah.bids, 0, "bids")
end)

test("buy state: without a buy call of the client the rows have no Buy", function()
    for _, opts in ipairs({ { noAuction = { "PlaceBid" } }, { noAuction = { "SendSearchQuery" } }, { noMoney = true } }) do
        local c, tiles = checkState({ [1] = { 500 } }, opts)
        click(tiles[1])
        c.advance(5)
        click(tiles[1])
        local v = TC.BrowserState.View()
        equal(v.list.state, "found", "found")
        equal(v.list.rows[1].buy, nil, "no Buy")
    end
end)

---------------------------------------------------------------- Buy and confirm (step 7, TC-33): whole

-- Appearance 1 with one item, Willow Boots (501, bind on equip unless
-- bindType says otherwise), listed at 5s; appearance 2 with item 601. The
-- tab is open and appearance 1's list found. results: the search results of
-- item variant 501:0 (default one auction, id 7, at 5s).
local function buyWhole(opts)
    opts = opts or {}
    local base = { appearances = { { id = 1, uiOrder = 2, sources = { 11 }, classes = { [9] = true } },
            { id = 2, uiOrder = 1, sources = { 21 }, classes = { [9] = true } } },
        sourceItems = { [11] = 501, [21] = 601 },
        items = { [501] = { name = "Willow Boots", quality = 2, bindType = opts.bindType or 2, subType = "Cloth" },
            [601] = { name = "Ivy Boots", quality = 2, bindType = 2, subType = "Cloth" } } }
    for k, v in pairs(opts.client or {}) do base[k] = v end
    local c, tabs = visitTwice(base)
    c.ah.listings = { listing("Willow Boots", 501, opts.listed or 500), listing("Ivy Boots", 601, 900) }
    c.ah.searchListings["501:0"] = opts.results or { auction(7, opts.listed or 500) }
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    c.click(frames[1].button)
    c.advance(1)
    -- the check ended; a second click opens the kept result
    c.click(frames[1].button)
    c.tabs, c.frames = tabs, frames
    return c
end
local function dialogOf(c)
    return find(c, function(w) return w.buyButton ~= nil end)
end
local function rowBuy(c, n)
    local list = itemListFrame(c)
    local buttons = findAll(c, function(w) return w.kind == "Button" and w.text == "Buy" and under(w, list) end)
    return buttons[n or 1]
end
local function inDialog(c, text)
    local d = dialogOf(c)
    return d ~= nil and find(c, function(w) return w.text == text and under(w, d) and visible(w) end) ~= nil
end
local function dialogShown(c)
    local d = dialogOf(c)
    return d ~= nil and visible(d)
end
-- Row Buy, then the search's answer and the client ready again (the key
-- info at 12 ms, the answer 0.25 s and the throttle 0.3 s after the send).
local function openDialog(c)
    check(c.click(rowBuy(c)), "the row's Buy took the click")
    c.advance(0.6)
end

test("buy whole: one row Buy opens the dialog with the name and Finding, makes one search, then shows the price", function()
    local c = buyWhole()
    local button = rowBuy(c)
    check(button and visible(button) and button:IsEnabled(), "a shown, enabled Buy in the found row")
    local browses = #c.ah.sends
    c.click(button)
    check(dialogShown(c), "the dialog is open")
    check(inDialog(c, "Willow Boots"), "the variant's name")
    check(inDialog(c, "Finding the cheapest auction"), "Finding")
    equal(dialogOf(c).buyButton.shown, false, "no Buy before the answer")
    c.advance(0.6)
    equal(#c.ah.searches, 1, "searches")
    check(inDialog(c, "5s"), "the price of the auction")
    check(inDialog(c, "Cancel"), "Cancel")
    check(visible(dialogOf(c).buyButton) and dialogOf(c).buyButton:IsEnabled(), "Buy on")
    equal(#c.ah.sends, browses, "no browse")
    equal(#c.ah.bids, 0, "bids")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

test("buy whole: the happy path makes exactly one search, one PlaceBid and then one check", function()
    local c = buyWhole()
    local browses = #c.ah.sends
    openDialog(c)
    local d = dialogOf(c)
    c.click(d.buyButton)
    equal(#c.ah.bids, 1, "bids")
    equal(c.ah.bids[1].auctionID, 7, "the auction id")
    equal(c.ah.bids[1].amount, 500, "the amount")
    check(inDialog(c, "Buying"), "Buying")
    equal(d.buyButton:IsEnabled(), false, "Buy off while buying")
    equal(d.closeButton:IsEnabled(), false, "Cancel off while buying")
    equal(#c.ah.sends, browses, "no check before the outcome")
    c.advance(0.25)
    check(not dialogShown(c), "the dialog closed on completion")
    c.advance(5)
    equal(#c.ah.searches, 1, "searches")
    equal(#c.ah.bids, 1, "bids")
    equal(#c.ah.sends, browses + 1, "the check ran again: one browse for its one name")
    equal(TC.BrowserState.View().list.state, "found", "the list after the new check")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
end)

test("buy safety 1: PlaceBid is called in one place only, inside the dialog Buy button's click", function()
    -- in the source: one call in the addon, in TC_Buy.lua
    local calls, files = {}, {}
    for line in io.lines(repo .. "/TransmogChecker.toc") do
        line = line:gsub("\r", ""):gsub("\\", "/")
        if line ~= "" and line:sub(1, 2) ~= "##" then files[#files + 1] = line end
    end
    for _, file in ipairs(files) do
        local n = 0
        for line in io.lines(repo .. "/" .. file) do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            if code:find("PlaceBid%s*%(") then calls[#calls + 1] = file .. ":" .. n end
        end
    end
    equal(#calls, 1, "PlaceBid calls in the source (" .. table.concat(calls, ", ") .. ")")
    check(calls[1]:find("^TC/Browser/TC_Buy.lua:"), "the call is in TC_Buy.lua, got " .. calls[1])
    -- in use: every event, timer and outcome without the click places nothing
    local c = buyWhole()
    openDialog(c)
    for _, event in ipairs({ "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR", "ITEM_SEARCH_RESULTS_UPDATED",
        "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "ITEM_KEY_ITEM_INFO_RECEIVED", "TRANSMOG_COLLECTION_UPDATED" }) do
        c.fire(event, 7)
    end
    c.advance(60)
    equal(#c.ah.bids, 0, "bids without the click")
    -- the click: the call is made inside it, from the dialog's Buy button
    c.click(dialogOf(c).buyButton)
    c.advance(10)
    equal(#c.ah.bids, 1, "bids after the click")
    equal(c.ah.bids[1].inClick, true, "PlaceBid inside the click")
    equal(c.ah.bids[1].button, dialogOf(c).buyButton, "inside the dialog's Buy button's click")
end)

test("buy safety 2: one click places at most one PlaceBid; a second click, a double click or a direct call place nothing", function()
    local c = buyWhole()
    c.ah.bidOutcome = "silent"
    openDialog(c)
    local d = dialogOf(c)
    c.click(d.buyButton)
    c.click(d.buyButton)
    c.click(d.buyButton, "LeftButton")
    -- even a click handler run on a disabled button (Enter held, a stray
    -- script) places nothing
    d.buyButton.scripts.OnClick(d.buyButton, "LeftButton", false)
    d.buyButton.scripts.OnClick(d.buyButton, "LeftButton", true)
    equal(#c.ah.bids, 1, "bids while buying")
    equal(d.buyButton:IsEnabled(), false, "Buy off until the outcome")
    equal(d.closeButton:IsEnabled(), false, "Cancel off until the outcome")
    -- Enter held down: passed on, places nothing
    for _ = 1, 3 do check(c.key("ENTER").passed, "Enter passed on") end
    equal(#c.ah.bids, 1, "bids after Enter")
    c.advance(6)
    check(inDialog(c, "The purchase did not go through."), "failed after 5 s")
    d.buyButton.scripts.OnClick(d.buyButton, "LeftButton", false)
    c.click(d.buyButton)
    equal(#c.ah.bids, 1, "bids after the outcome")
end)

test("buy safety 3: the amount and id are the chosen result's, the price shown is that number; nil, 0 or no id keep Buy off", function()
    -- the list says 1g 20s; the auction the search found costs 1g 23s 45c
    local c = buyWhole({ listed = 12000, results = { auction(70, 12345) } })
    openDialog(c)
    check(inDialog(c, "1g 23s 45c"), "the price in full, the search's")
    c.click(dialogOf(c).buyButton)
    equal(c.ah.bids[1].auctionID, 70, "auction id")
    equal(c.ah.bids[1].amount, 12345, "amount, to the copper")
    for _, results in ipairs({ { auction(7, nil) }, { auction(7, 0) }, { auction(nil, 500) },
        { auction(7, nil), auction(8, 0), auction(nil, 300) } }) do
        c = buyWhole({ results = results })
        openDialog(c)
        local d = dialogOf(c)
        check(not (d.buyButton.shown and d.buyButton:IsEnabled()), "Buy off")
        check(inDialog(c, "That auction is gone."), "nothing to buy")
        d.buyButton.scripts.OnClick(d.buyButton)
        c.click(d.buyButton)
        equal(#c.ah.bids, 0, "bids")
    end
end)

test("buy: the lowest buyout is chosen by comparing, not by position; a result without a buyout is skipped", function()
    local c = buyWhole({ results = { auction(9, 900), auction(8, nil), auction(7, 300), auction(6, 500) } })
    openDialog(c)
    check(inDialog(c, "3s"), "the lowest price")
    c.click(dialogOf(c).buyButton)
    equal(c.ah.bids[1].auctionID, 7, "the cheapest auction")
    equal(c.ah.bids[1].amount, 300, "its buyout")
end)

test("buy safety 4: never the player's own auction", function()
    local c = buyWhole({ results = { auction(5, 100, { containsOwnerItem = true }), auction(7, 500) } })
    openDialog(c)
    check(inDialog(c, "5s"), "the own cheaper auction skipped")
    c.click(dialogOf(c).buyButton)
    equal(c.ah.bids[1].auctionID, 7, "not the own auction")
    c = buyWhole({ results = { auction(5, 100, { containsOwnerItem = true }) } })
    openDialog(c)
    check(inDialog(c, "That auction is gone."), "only the own auction: nothing to buy")
    c.click(dialogOf(c).buyButton)
    equal(#c.ah.bids, 0, "bids")
end)

test("buy safety 5: Cancel, Escape, leaving the tab, closing the window, a failed or empty search end with no PlaceBid", function()
    local ways = {
        cancel = function(c) c.click(dialogOf(c).closeButton) end,
        escape = function(c)
            equal(c.key("ESCAPE").passed, false, "Escape taken by the dialog")
            check(AuctionHouseFrame:IsShown(), "the auction window stays open")
        end,
        leave = function(c) selectBuy(); c.tabs[1].frameRef:Hide() end,
        close = function(c) c.closeAuction() end,
    }
    for name, way in pairs(ways) do
        for _, early in ipairs({ true, false }) do
            local c = buyWhole()
            c.click(rowBuy(c))
            if not early then c.advance(0.6) end
            way(c)
            check(not dialogShown(c), name .. ": the dialog closed")
            c.advance(30)
            equal(#c.ah.bids, 0, name .. ": bids")
            -- the item list asked the key info already, so the search went
            -- out in the row click; early, it was dropped before its answer
            equal(#c.ah.searches, 1, name .. ": searches")
        end
    end
    -- a search that is never answered fails after 5 s and reads nothing more
    local c = buyWhole()
    c.ah.silent = true
    local browses = #c.ah.sends
    c.click(rowBuy(c))
    c.advance(4.9)
    check(inDialog(c, "Finding the cheapest auction"), "still finding before 5 s")
    c.advance(0.2)
    check(inDialog(c, "The purchase did not go through."), "a failed search")
    check(inDialog(c, "Close"), "Close")
    c.click(dialogOf(c).buyButton)
    c.advance(10)
    equal(#c.ah.bids, 0, "bids after a failed search")
    equal(#c.ah.searches, 1, "one search")
    equal(#c.ah.sends, browses, "no check after a failed search")
    -- a search that finds nothing: gone, and the check runs again
    c = buyWhole({ results = {} })
    local browses = #c.ah.sends
    openDialog(c)
    check(inDialog(c, "That auction is gone."), "gone")
    check(inDialog(c, "Close"), "Close")
    c.advance(5)
    equal(#c.ah.sends, browses + 1, "the check ran again")
    c.click(dialogOf(c).closeButton)
    check(not dialogShown(c), "closed")
    equal(#c.ah.bids, 0, "bids after gone")
end)

test("buy safety 6: the dialog's Buy is on only when answered, chosen, affordable, the queue idle and the client ready", function()
    -- not answered yet
    local c = buyWhole()
    c.click(rowBuy(c))
    local d = dialogOf(c)
    equal(d.buyButton.shown, false, "no Buy before the answer")
    d.buyButton.scripts.OnClick(d.buyButton)
    equal(#c.ah.bids, 0, "bids before the answer")
    -- not enough money
    c = buyWhole()
    c.money = 499
    openDialog(c)
    d = dialogOf(c)
    check(inDialog(c, "5s"), "the price")
    check(find(c, function(w) return w.text and w.text:find("You do not have enough money.", 1, true) and under(w, d) end),
        "the money line")
    equal(d.buyButton:IsEnabled(), false, "Buy off without the money")
    d.buyButton.scripts.OnClick(d.buyButton)
    equal(#c.ah.bids, 0, "bids without the money")
    -- the client not ready, then ready: the button follows within a poll
    c = buyWhole()
    openDialog(c)
    d = dialogOf(c)
    c.ah.ready = false
    c.advance(0.26)
    equal(d.buyButton:IsEnabled(), false, "Buy off while the client is not ready")
    d.buyButton.scripts.OnClick(d.buyButton)
    equal(#c.ah.bids, 0, "bids while not ready")
    c.ah.ready = true
    c.advance(0.26)
    equal(d.buyButton:IsEnabled(), true, "Buy on once ready")
    -- the queue busy
    TC.AuctionQueue.Browse({ searchString = "x", sorts = {}, filters = {} }, 1, { done = function() end, failed = function() end })
    c.advance(0.26)
    equal(d.buyButton:IsEnabled(), false, "Buy off while the queue is busy")
    d.buyButton.scripts.OnClick(d.buyButton)
    equal(#c.ah.bids, 0, "bids while the queue is busy")
    c.advance(2)
    equal(d.buyButton:IsEnabled(), true, "Buy on once the queue is idle")
    c.click(d.buyButton)
    equal(#c.ah.bids, 1, "bids once every condition holds")
end)

test("buy safety 7: the tab, lists, scans and checks make no search and no PlaceBid; one row click makes one search", function()
    local c, tabs = visitTwice()
    for id = 1010, 1030, 10 do c.ah.listings[#c.ah.listings + 1] = listing("Item " .. (id * 10 + 1), id * 10 + 1, id) end
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    c.click(frames[1].button)
    c.advance(5)
    TC.BrowserState.CheckAgain()
    c.advance(5)
    c.click(modeTab(c, "For sale"))
    c.advance(10)
    local v = TC.BrowserState.View()
    TC.BrowserState.ClickTile(v.tiles[1].appearance)
    c.advance(5)
    selectBuy()
    tabs[1].frameRef:Hide()
    tabs[1].scripts.OnClick(tabs[1])
    c.advance(10)
    equal(#c.ah.searches, 0, "searches")
    equal(#c.ah.bids, 0, "bids")
    check(rowBuy(c) and visible(rowBuy(c)), "a found row of the scan's list offers Buy")
    c.click(rowBuy(c))
    c.advance(10)
    equal(#c.ah.searches, 1, "one search for one row click")
    equal(#c.ah.bids, 0, "bids")
end)

test("buy whole: a found row in a list from a check and from a scan has a Buy button; other rows have none", function()
    local c = buyWhole()
    check(rowBuy(c) and visible(rowBuy(c)), "found row of a check")
    local list = itemListFrame(c)
    TC.BrowserState.CheckAgain()
    local shown = findAll(c, function(w) return w.kind == "Button" and w.text == "Buy" and under(w, list) and visible(w) end)
    equal(#shown, 0, "no Buy while checking")
    c.advance(5)
    c.ah.listings = {}
    c.click(c.frames[2].button)
    c.advance(5)
    c.click(c.frames[2].button)
    equal(TC.BrowserState.View().list.state, "not for sale", "not for sale")
    shown = findAll(c, function(w) return w.kind == "Button" and w.text == "Buy" and under(w, list) and visible(w) end)
    equal(#shown, 0, "no Buy on a not-for-sale list")
end)

test("buy: the price changed line, and the bind-on-equip hint only for such an item", function()
    local hint = "This item binds when equipped. Its appearance is collected when you equip it or sell it to a vendor."
    local function lines(c)
        local d = dialogOf(c)
        return d.linesText.text or ""
    end
    local c = buyWhole({ results = { auction(7, 650) } })
    openDialog(c)
    check(lines(c):find("The price changed since the check.", 1, true), "price changed, got " .. lines(c))
    check(lines(c):find(hint, 1, true), "the hint for a bind-on-equip item")
    check(inDialog(c, "6s 50c"), "the search's price, not the list's")
    c = buyWhole({ bindType = 0 })
    openDialog(c)
    equal(lines(c), "", "no line for an unchanged price and an item that does not bind")
end)

test("buy: the client's error and no outcome in 5 s read The purchase did not go through. and the check runs again", function()
    for _, outcome in ipairs({ "error", "silent" }) do
        local c = buyWhole()
        c.ah.bidOutcome = outcome
        local browses = #c.ah.sends
        openDialog(c)
        c.click(dialogOf(c).buyButton)
        c.advance(outcome == "error" and 0.25 or 4.9)
        if outcome == "silent" then
            check(inDialog(c, "Buying"), "still Buying before 5 s")
            c.advance(0.2)
        end
        check(inDialog(c, "The purchase did not go through."), outcome .. ": failed")
        check(inDialog(c, "Close"), outcome .. ": Close")
        c.advance(5)
        equal(#c.ah.sends, browses + 1, outcome .. ": the check ran again")
        c.click(dialogOf(c).closeButton)
        check(not dialogShown(c), outcome .. ": closed")
        equal(#c.ah.bids, 1, outcome .. ": bids")
    end
end)

test("buy: a completion for another auction id does not finish ours", function()
    local c = buyWhole()
    c.ah.bidOutcome = "other"
    local browses = #c.ah.sends
    openDialog(c)
    c.click(dialogOf(c).buyButton)
    c.advance(1)
    check(inDialog(c, "Buying"), "still Buying")
    equal(#c.ah.sends, browses, "no check yet")
    c.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 7)
    check(not dialogShown(c), "ours finishes it")
    c.advance(5)
    equal(#c.ah.sends, browses + 1, "the check ran again")
end)

test("buy: while the dialog is open the browser starts no read; it does once the dialog is closed", function()
    local c = buyWhole()
    local browses = #c.ah.sends
    openDialog(c)
    TC.BrowserState.CheckAgain()
    TC.BrowserState.ClickTile(TC.BrowserState.View().tiles[2].appearance)
    TC.BrowserState.SelectMode("For sale")
    TC.BrowserState.ScanAgain()
    TC.BrowserState.BuyRow(1)
    c.advance(10)
    equal(#c.ah.sends, browses, "browses while the dialog is open")
    equal(#c.ah.searches, 1, "searches while the dialog is open")
    check(dialogShown(c), "the dialog stays")
    c.click(dialogOf(c).closeButton)
    TC.BrowserState.CheckAgain()
    c.advance(5)
    equal(#c.ah.sends, browses + 1, "a check once the dialog is closed")
    equal(#c.ah.bids, 0, "bids")
end)

test("buy whole: a client without a buy call has no Buy buttons and no error", function()
    for _, missing in ipairs({ "PlaceBid", "SendSearchQuery", "GetItemSearchResultInfo" }) do
        local c = buyWhole({ client = { noAuction = { missing } } })
        equal(TC.BrowserState.View().list.state, "found", missing .. ": found")
        check(not rowBuy(c) or not visible(rowBuy(c)), missing .. ": no Buy button")
        equal(#c.errors, 0, missing .. ": errors")
    end
end)

---------------------------------------------------------------- Buy: fixes after QA

test("buy fix F1: Escape closes the dialog and is not passed on; other keys are; no game menu Escape handler", function()
    local c = buyWhole()
    openDialog(c)
    equal(#c.escHandlers, 0, "RegisterGameMenuEscHandler calls")
    local d = dialogOf(c)
    local k = c.key("W")
    equal(k.frame, d, "the dialog gets the key")
    equal(k.passed, true, "another key is passed on")
    check(dialogShown(c), "the dialog stays on another key")
    k = c.key("ESCAPE")
    equal(k.frame, d, "the dialog gets Escape")
    equal(k.passed, false, "Escape is not passed on")
    check(not dialogShown(c), "Escape closed the dialog")
    check(AuctionHouseFrame:IsShown(), "the auction window stays open")
    c.advance(30)
    equal(#c.ah.bids, 0, "bids")
    equal(#c.misuse, 0, "misuse of the fake: " .. table.concat(c.misuse, "; "))
    -- in combat the key is left alone: Escape goes on and closes the window,
    -- which closes the dialog
    c = buyWhole()
    openDialog(c)
    c.combat = true
    k = c.key("ESCAPE")
    equal(k.passed, true, "in combat Escape is passed on")
    check(not AuctionHouseFrame:IsShown(), "in combat Escape closed the auction window")
    check(not dialogShown(c), "and the dialog")
    c.advance(30)
    equal(#c.ah.bids, 0, "bids in combat")
    equal(#c.misuse, 0, "misuse of the fake in combat: " .. table.concat(c.misuse, "; "))
end)

test("buy fix F2: an auction of the player's account is never chosen", function()
    local c = buyWhole({ results = { auction(5, 100, { containsAccountItem = true }), auction(7, 500) } })
    openDialog(c)
    check(inDialog(c, "5s"), "the account's cheaper auction skipped")
    c.click(dialogOf(c).buyButton)
    equal(c.ah.bids[1].auctionID, 7, "the next one")
    c = buyWhole({ results = { auction(5, 100, { containsAccountItem = true }),
        auction(6, 200, { containsAccountItem = true, containsOwnerItem = true }) } })
    openDialog(c)
    check(inDialog(c, "That auction is gone."), "only the account's auctions: gone")
    c.click(dialogOf(c).buyButton)
    c.advance(10)
    equal(#c.ah.bids, 0, "bids")
end)

test("queue fix F3: a new search of an item key waits 1 s after its last send; the repeated answer is not taken for it", function()
    local c = boot()
    c.ah.keyKnown["501:0"] = true
    c.ah.searchListings["501:0"] = { auction(7, 500) }
    local start = c.now
    local r1 = queueSearch()
    c.advance(0.26)
    equal(r1.done, 1, "the first search answered")
    TC.AuctionQueue.CancelAll()
    c.advance(0.05)
    local r2 = { done = 0, failed = 0 }
    TC.AuctionQueue.Search(KEY, {
        done = function() r2.done, r2.at = r2.done + 1, c.now end,
        failed = function() r2.failed = r2.failed + 1 end,
    })
    equal(#c.ah.searches, 1, "not sent at +0.31 s")
    -- the repeat of the first answer comes at +0.55 s
    c.advance(0.26)
    equal(r2.done + r2.failed, 0, "the repeat is not the second search's answer")
    c.advance(0.42)
    equal(#c.ah.searches, 1, "not sent before +1.0 s")
    -- since the second round (F4) the wait also counts from the repeat at
    -- +0.55 s: sent from +1.55 s on
    c.advance(0.6)
    equal(#c.ah.searches, 2, "sent after +1.55 s")
    local sentAt = c.ah.searches[2].at
    check(sentAt - start >= 1.55 - 1e-9, "sent 1 s or more after the repeat, got " .. (sentAt - start))
    c.advance(0.3)
    equal(r2.done, 1, "answered")
    check(r2.at >= sentAt + c.ah.answerDelay, "by its own answer")
    c.advance(5)
    equal(r2.done + r2.failed, 1, "answered once")
end)

test("buy fix F4: Escape while buying changes nothing; the outcome then closes the dialog and one check runs", function()
    local c = buyWhole()
    c.ah.bidOutcome = "silent"
    local browses = #c.ah.sends
    openDialog(c)
    c.click(dialogOf(c).buyButton)
    local k = c.key("ESCAPE")
    equal(k.passed, false, "Escape swallowed while buying")
    check(dialogShown(c), "the dialog stays")
    check(inDialog(c, "Buying"), "still Buying")
    check(AuctionHouseFrame:IsShown(), "the auction window stays open")
    c.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 7)
    check(not dialogShown(c), "the outcome closed the dialog")
    c.advance(5)
    equal(#c.ah.sends, browses + 1, "one check")
    equal(#c.ah.bids, 1, "bids")
    -- leaving the tab or closing the window while buying closes the dialog;
    -- the outcome then runs no check, the player is not on the tab
    for _, way in ipairs({ "leave", "close" }) do
        for _, outcome in ipairs({ "completed", "silent" }) do
            c = buyWhole()
            c.ah.bidOutcome = outcome
            browses = #c.ah.sends
            openDialog(c)
            c.click(dialogOf(c).buyButton)
            if way == "leave" then selectBuy(); c.tabs[1].frameRef:Hide() else c.closeAuction() end
            check(not dialogShown(c), way .. ", " .. outcome .. ": the dialog closed")
            c.advance(10)
            equal(#c.ah.sends, browses, way .. ", " .. outcome .. ": no check")
            equal(#c.ah.bids, 1, way .. ", " .. outcome .. ": bids")
            equal(#c.errors, 0, way .. ", " .. outcome .. ": errors")
        end
    end
end)

test("queue fix F5: a search the client drops every time is sent 3 times, then answers once as failed", function()
    local c = boot()
    c.ah.keyKnown["501:0"] = true
    c.ah.dropSearches = 1000
    local r = queueSearch()
    c.advance(10)
    equal(#c.ah.searches, 3, "sends")
    answeredOnce(r, "dropped")
    equal(r.failed, 1, "failed")
    check(tostring(r.reason):find("dropped", 1, true), "dropped in the reason, got " .. tostring(r.reason))
    equal(c.pendingTimers(), 0, "timers left running")
end)

test("buy fix F6: a draw that raises in Start still ends the flow; no PlaceBid", function()
    local c = buyWhole()
    c.qualityColorRaises = 1
    local errors = #c.errors
    pcall(c.click, rowBuy(c))
    c.advance(0.6)
    equal(#c.ah.searches, 1, "the search was sent")
    check(not dialogShown(c) or inDialog(c, "5s"), "answered or closed")
    check(not (dialogShown(c) and inDialog(c, "Finding the cheapest auction")), "not left in Finding")
    equal(#c.errors, errors + 1, "the error reported once")
    c.advance(30)
    equal(#c.ah.bids, 0, "bids")
end)

---------------------------------------------------------------- Buy: second round of fixes

-- Presses each key and checks that no frame kept it.
local function allPassed(c, keys, what)
    for _, key in ipairs(keys) do
        local k = c.key(key)
        equal(k.kept, false, what .. ": " .. key .. " kept")
    end
end

test("buy fix2 F1: a dialog shown in combat keeps no key; W, 1 and Escape go on, Escape closes the window", function()
    local c = buyWhole()
    c.enterCombat()
    openDialog(c)
    check(dialogShown(c), "the dialog is open")
    local d = dialogOf(c)
    equal(d:IsKeyboardEnabled(), false, "the dialog takes no keyboard in combat")
    allPassed(c, { "W", "1" }, "in combat")
    check(dialogShown(c), "the dialog stays on other keys")
    allPassed(c, { "ESCAPE" }, "in combat")
    check(not AuctionHouseFrame:IsShown(), "Escape went to the game and closed the auction window")
    check(not dialogShown(c), "and the dialog")
    c.advance(30)
    equal(#c.ah.bids, 0, "bids")
    equal(#c.kept, 0, "keys kept")
    equal(c.propagateInCombat, 0, "SetPropagateKeyboardInput calls in combat")
end)

test("buy fix2 F1: out of combat the dialog keeps only Escape, propagating from the moment it is shown", function()
    local c = buyWhole()
    c.click(rowBuy(c))
    local d = dialogOf(c)
    equal(d:IsKeyboardEnabled(), true, "the dialog takes the keyboard out of combat")
    equal(d.propagate, true, "propagation is on before any key")
    c.advance(0.6)
    allPassed(c, { "W", "1", "ENTER" }, "out of combat")
    local k = c.key("ESCAPE")
    equal(k.kept, true, "Escape kept")
    equal(k.frame, d, "by the dialog")
    check(not dialogShown(c), "Escape closed the dialog")
    check(AuctionHouseFrame:IsShown(), "the auction window stays open")
    equal(d:IsKeyboardEnabled(), false, "a hidden dialog gives the keyboard up")
    equal(#c.kept, 1, "keys kept")
    -- shown again after that Escape: out of combat W still goes on; in
    -- combat no key is kept
    c.advance(2)
    openDialog(c)
    check(dialogShown(c), "open again")
    allPassed(c, { "W" }, "again, out of combat")
    equal(c.key("ESCAPE").kept, true, "Escape closes it again")
    check(not dialogShown(c), "closed by Escape")
    c.advance(2)
    c.enterCombat()
    openDialog(c)
    check(dialogShown(c), "open in combat")
    allPassed(c, { "W", "1" }, "again, in combat")
    c.advance(30)
    equal(#c.ah.bids, 0, "bids")
    equal(c.propagateInCombat, 0, "SetPropagateKeyboardInput calls in combat")
end)

test("buy fix2 F1: combat starting while the dialog is shown releases the keyboard, also after combat ends", function()
    local c = buyWhole()
    openDialog(c)
    local d = dialogOf(c)
    c.key("ESCAPE")
    c.advance(2)
    openDialog(c)
    equal(d:IsKeyboardEnabled(), true, "out of combat the dialog has the keyboard")
    c.enterCombat()
    equal(d:IsKeyboardEnabled(), false, "combat released it")
    local k = c.key("W")
    equal(k.frame, nil, "no frame of the dialog gets W in combat")
    allPassed(c, { "W", "1" }, "combat started")
    c.leaveCombat()
    equal(d:IsKeyboardEnabled(), false, "not taken back when combat ends")
    allPassed(c, { "W" }, "after combat")
    check(dialogShown(c), "the dialog stays")
    -- a held buy: Buying, then combat; the outcome still ends it
    c = buyWhole()
    c.ah.bidOutcome = "silent"
    openDialog(c)
    d = dialogOf(c)
    c.click(d.buyButton)
    c.enterCombat()
    allPassed(c, { "W" }, "buying, in combat")
    c.advance(6)
    check(inDialog(c, "The purchase did not go through."), "the 5-second limit ended it")
    equal(#c.ah.bids, 1, "bids")
    equal(c.propagateInCombat, 0, "SetPropagateKeyboardInput calls in combat")
end)

test("buy fix2 F2: a draw that raises inside the Buy click: one PlaceBid, the flow ends, a later Start works", function()
    for _, outcome in ipairs({ "completed", "silent" }) do
        local c = buyWhole()
        c.ah.bidOutcome = outcome
        openDialog(c)
        local d = dialogOf(c)
        local errors = #c.errors
        c.qualityColorRaises = 1
        pcall(c.click, d.buyButton)
        equal(#c.ah.bids, 1, outcome .. ": bids from the click")
        equal(c.ah.bids[1].inClick, true, outcome .. ": inside the click")
        equal(#c.errors, errors + 1, outcome .. ": the error reported once")
        c.click(d.buyButton)
        d.buyButton.scripts.OnClick(d.buyButton, "LeftButton", false)
        equal(#c.ah.bids, 1, outcome .. ": no second PlaceBid")
        c.advance(6)
        if outcome == "completed" then
            check(not dialogShown(c), "completed: the outcome closed the dialog")
        else
            check(inDialog(c, "The purchase did not go through."), "silent: the 5-second limit ended it")
            c.click(d.closeButton)
        end
        c.advance(5)
        check(c.click(rowBuy(c)), outcome .. ": the row's Buy took the click")
        check(dialogShown(c), outcome .. ": a later Start opens the dialog")
        c.advance(2)
        equal(#c.ah.searches, 2, outcome .. ": the later Start searched")
        check(inDialog(c, "5s"), outcome .. ": and offers the auction")
        equal(#c.ah.bids, 1, outcome .. ": bids")
    end
end)

test("buy fix2 F3: Buy on a row while a placed bid's outcome is pending sends nothing; after the outcome it works", function()
    for _, outcome in ipairs({ "completed", "silent" }) do
        local c = buyWhole()
        c.ah.bidOutcome = "silent"
        openDialog(c)
        c.click(dialogOf(c).buyButton)
        equal(#c.ah.bids, 1, outcome .. ": bids")
        selectBuy()
        c.tabs[1].frameRef:Hide()
        check(not dialogShown(c), outcome .. ": leaving the tab closed the dialog")
        c.tabs[1].scripts.OnClick(c.tabs[1])
        c.advance(0.5)
        local button = rowBuy(c)
        check(button and visible(button), outcome .. ": the row offers Buy again")
        c.click(button)
        c.advance(1.5)
        equal(#c.ah.searches, 1, outcome .. ": no new search while the outcome is pending")
        check(not dialogShown(c), outcome .. ": no dialog")
        equal(#c.ah.bids, 1, outcome .. ": no second PlaceBid")
        if outcome == "completed" then
            c.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 7)
        else
            c.advance(4)
        end
        c.advance(5)
        check(c.click(rowBuy(c)), outcome .. ": the row's Buy took the click")
        check(dialogShown(c), outcome .. ": Buy works again")
        c.advance(2)
        equal(#c.ah.searches, 2, outcome .. ": one new search")
        equal(#c.ah.bids, 1, outcome .. ": bids")
    end
end)

test("queue fix2 F4: a new search of an item key waits 1 s after the last result event for it as well", function()
    local c = boot()
    c.ah.keyKnown["501:0"] = true
    c.ah.searchListings["501:0"] = { auction(7, 500) }
    c.ah.answerDelay, c.ah.repeatDelay = 0.82, 0.38
    local start = c.now
    local r1 = queueSearch()
    c.advance(0.83)
    equal(r1.done, 1, "the first search answered at +0.82 s")
    TC.AuctionQueue.CancelAll()
    c.advance(0.07)
    local r2 = { done = 0, failed = 0 }
    TC.AuctionQueue.Search(KEY, {
        done = function() r2.done, r2.at = r2.done + 1, c.now end,
        failed = function() r2.failed = r2.failed + 1 end,
    })
    -- the repeat of the first answer comes at +1.2 s
    c.advance(0.31)
    equal(r2.done + r2.failed, 0, "the repeat at +1.2 s is not the second search's answer")
    c.advance(5)
    equal(#c.ah.searches, 2, "the second search was sent")
    local sentAt = c.ah.searches[2].at
    check(sentAt - start >= 2.2 - 1e-9, "sent 1 s or more after the last result event (+1.2 s), got +" .. (sentAt - start))
    equal(r2.done, 1, "answered")
    check(r2.at >= sentAt + c.ah.answerDelay - 1e-9, "by its own answer")
    c.advance(5)
    equal(r2.done + r2.failed, 1, "answered once")
end)

---------------------------------------------------------------- Visual pass: control styles (TC-36)

local function noErrors(c, what)
    equal(#c.misuse, 0, what .. ": misuse of the fake: " .. table.concat(c.misuse, "; "))
    equal(#c.errors, 0, what .. ": errors: " .. table.concat(c.errors, "; "))
end
local function sentNothing(c, what)
    equal(#c.ah.sends, 0, what .. ": browses")
    equal(#c.ah.searches, 0, what .. ": searches")
    equal(#c.auctionTouches, 0, what .. ": C_AuctionHouse accesses (" .. table.concat(c.auctionTouches, ", ") .. ")")
end
-- The view's entries as the menu's texts: the first, a line, the rest.
local function expectedTexts(answer)
    local out = {}
    for i, e in ipairs(answer.entries) do
        out[#out + 1] = e.name
        if i == 1 then out[#out + 1] = "-" end
    end
    return table.concat(out, "|")
end
local function selectedTexts(c)
    local out = {}
    for _, e in ipairs(c.menuEntries()) do if e ~= "-" and e.selected then out[#out + 1] = e.text end end
    return table.concat(out, "|")
end

test("styles: nothing of the browser, no dropdown and no menu, is made before the tab is selected", function()
    local c = visitTwice({ appearances = manySlots() })
    equal(#findAll(c, function(w) return w.kind == "DropdownButton" end), 0, "dropdowns before the tab")
    equal(c.menuOpens, 0, "menus opened")
    equal(modeTab(c, "All"), nil, "the catalogue toggle")
    local tabs = tabsOf(c)
    tabs[1].scripts.OnClick(tabs[1])
    equal(#findAll(c, function(w) return w.kind == "DropdownButton" end), 2,
        "dropdowns once the tab is selected: weapon type and funnel")
end)

test("styles: with Blizzard's menu templates the weapon type and the funnel are its dropdowns in the page's boxes", function()
    local c, tabs = visitTwice({ appearances = manySlots() })
    tabs[1].scripts.OnClick(tabs[1])
    local weapon, funnel = selector(c, 157), funnelOf(c)
    equal(weapon.template, "WowStyle1DropdownTemplate", "weapon type template")
    equal(funnel.template, "WowStyle1FilterDropdownTemplate", "funnel template")
    for _, d in ipairs({ weapon, funnel }) do
        equal(d.kind, "DropdownButton", d.template .. " kind")
        equal(d.resizeToText, false, d.template .. " does not resize to its text")
    end
    equal(weapon.width, 157, "weapon type width")
    equal(weapon.height, 25, "weapon type height is the template's own, not forced")
    equal(weapon.points[1].point .. " " .. weapon.points[1].x .. "," .. weapon.points[1].y, "LEFT 598,-58",
        "weapon type at x 598, centred on y 58")
    equal(funnel.width .. "x" .. funnel.height, "30x30", "funnel size")
    equal(funnel.points[1].x .. "," .. funnel.points[1].y, "757,-4", "funnel at x 757, y 4")
    equal(funnel.Text.text, "", "the funnel has no text with its art")
    check(visible(funnel) and not visible(weapon), "funnel shown, weapon type not on head")
    equal(#findAll(c, function(w) return w.kind == "Button" and (w.width == 150 or w.width == 157 or w.width == 138) end),
        0, "no fallback selector buttons, no class dropdown, no Filter button")
    noErrors(c, "templates")
end)

-- The class entries as the funnel's submenu shows them, in the fake's colours.
local CLASS_MENU = "All classes|-||cffWARRIORWarrior|r||cffPALADINPaladin|r||cffHUNTERHunter|r||cffROGUERogue|r|"
    .. "|cffPRIESTPriest|r||cffSHAMANShaman|r||cffMAGEMage|r||cffWARLOCKWarlock (this character)|r||cffDRUIDDruid|r"

test("styles: the funnel's class submenu lists All classes, a line, the classes in order, the chosen marked; a choice sends nothing", function()
    local c, tabs = visitTwice(classFixture(0))
    tabs[1].scripts.OnClick(tabs[1])
    local function submenu()
        openMenu(c, funnelOf(c))
        for _, e in ipairs(c.menuEntries()) do if e ~= "-" and e.submenu then return e end end
    end
    local function texts(e)
        local out, marked = {}, {}
        for _, s in ipairs(e.submenu) do
            out[#out + 1] = s == "-" and "-" or s.text
            if s ~= "-" and s.selected then marked[#marked + 1] = s.text end
        end
        return table.concat(out, "|"), table.concat(marked, "|")
    end
    local e = submenu()
    equal(e.text, "Class: |cffWARLOCKWarlock|r", "the submenu names the class in its colour")
    local all, marked = texts(e)
    equal(all, CLASS_MENU, "entries")
    equal(marked, "|cffWARLOCKWarlock (this character)|r", "the chosen entry marked")
    check(c.choose("|cffDRUIDDruid|r"), "a Druid entry")
    equal(c.menu, nil, "the menu closed after the choice")
    equal(TC.BrowserState.View().classes.text, "Druid", "the state's class")
    check(textShown(c, "5 appearances"), "count under Druid")
    e = submenu()
    equal(e.text, "Class: |cffDRUIDDruid|r", "Druid named on the next opening")
    all, marked = texts(e)
    equal(marked, "|cffDRUIDDruid|r", "Druid marked")
    c.choose("All classes")
    equal(submenu().text, "Class: All classes", "All classes without a colour")
    funnelOf(c):CloseMenu()
    c.advance(5)
    sentNothing(c, "class")
    equal(#c.loadRequests, 0, "item data requests")
    noErrors(c, "class")
end)

test("styles: the weapon type dropdown shows the state's text, not the chosen radio's (OverrideText, not SetText)", function()
    local c, tabs = visitTwice({ appearances = manySlots() })
    tabs[1].scripts.OnClick(tabs[1])
    local weapon = selector(c, 157)
    slotButtons(c)[12].scripts.OnClick(slotButtons(c)[12])
    check(weapon.disableSelectionText, "the text is set with OverrideText")
    equal(weapon.Text.text, "All weapon types", "the state's text")
    weapon:Hide()
    weapon:Show()
    openMenu(c, weapon)
    weapon:CloseMenu()
    equal(weapon.Text.text, "All weapon types", "still the state's text")
    noErrors(c, "weapon text")
end)

test("styles: the weapon type menu lists the slot's types, the chosen marked; a choice narrows and sends nothing", function()
    local c, tabs = visitTwice({ appearances = manySlots() })
    tabs[1].scripts.OnClick(tabs[1])
    local weapon = selector(c, 157)
    slotButtons(c)[12].scripts.OnClick(slotButtons(c)[12])
    check(visible(weapon), "shown on main hand")
    equal(weapon.Text.text, "All weapon types", "its text")
    local texts = openMenu(c, weapon)
    equal(table.concat(texts, "|"), expectedTexts(TC.BrowserState.View().weaponTypes), "entries")
    equal(texts[1] .. texts[2], "All weapon types-", "All weapon types, then a line")
    equal(selectedTexts(c), "All weapon types", "All weapon types marked")
    check(c.choose("Daggers"), "a Daggers entry")
    equal(weapon.Text.text, "Daggers", "the chosen type")
    check(textShown(c, "10 appearances"), "count after choosing daggers")
    openMenu(c, weapon)
    equal(selectedTexts(c), "Daggers", "Daggers marked")
    -- an armor slot hides the dropdown and closes its menu
    slotButtons(c)[1].scripts.OnClick(slotButtons(c)[1])
    check(not visible(weapon), "hidden on head")
    equal(c.menu, nil, "its menu closed")
    c.advance(5)
    sentNothing(c, "weapon type")
    noErrors(c, "weapon type")
end)

test("styles: the funnel lists All, Collected, Not collected with the chosen marked; in For sale they are greyed and the class still works", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local funnel = funnelOf(c)
    local texts = openMenu(c, funnel)
    equal(table.concat(texts, "|"), "All|Collected|Not collected|-|Class: |cffWARLOCKWarlock|r", "entries at the start")
    equal(selectedTexts(c), "Not collected", "Not collected marked")
    check(c.choose("Collected"), "a Collected entry")
    check(textShown(c, "5 of 370 appearances"), "count after Collected")
    texts = openMenu(c, funnel)
    equal(selectedTexts(c), "Collected", "Collected marked")
    equal(texts[#texts], "Reset filters", "Reset filters once a choice differs")
    funnel:CloseMenu()
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    openMenu(c, funnel)
    local entries = c.menuEntries()
    for i = 1, 3 do equal(entries[i].enabled, false, entries[i].text .. " greyed in For sale") end
    equal(selectedTexts(c), "Not collected", "fixed on Not collected")
    equal(c.choose("All"), false, "a greyed entry takes no pick")
    check(c.choose("|cffMAGEMage|r"), "the class still works")
    equal(TC.BrowserState.View().classes.text, "Mage", "Mage chosen in For sale")
    equal(#c.ah.sends, 1, "browses: only the sweep toggle's scan")
    noErrors(c, "funnel")
end)

test("styles: leaving the tab closes an open menu", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    openMenu(c, funnelOf(c))
    check(c.menu ~= nil, "the funnel's menu open")
    selectBuy()
    tabs[1].frameRef:Hide()
    equal(c.menu, nil, "closed with the panel")
end)

-- The same choices through each path; answers what the state shows after
-- each, and the auction house traffic.
local function choicesThrough(opts)
    local all = { appearances = manySlots() }
    for k, v in pairs(opts) do all[k] = v end
    local c, tabs = visitTwice(all)
    tabs[1].scripts.OnClick(tabs[1])
    local out = {}
    local function note()
        local v = TC.BrowserState.View()
        out[#out + 1] = table.concat({ v.count, v.classes.text, v.filter, v.weaponTypes and v.weaponTypes.text or "-",
            tostring(v.page), tostring(v.filtersChanged) }, "/")
    end
    local _, choose = openMenu(c, funnelOf(c))
    choose("All")
    note()
    _, choose = openMenu(c, funnelOf(c))
    choose("|cffMAGEMage|r")
    note()
    slotButtons(c)[12].scripts.OnClick(slotButtons(c)[12])
    _, choose = openMenu(c, selector(c, 157))
    choose("Daggers")
    note()
    _, choose = openMenu(c, selector(c, 157))
    choose("All weapon types")
    note()
    _, choose = openMenu(c, funnelOf(c))
    choose("Reset filters")
    note()
    c.advance(5)
    return table.concat(out, " ; "), c
end

test("styles: without the menu templates, or without the menu API, the funnel and the weapon type are buttons with their own lists and act as before", function()
    local expected, tc = choicesThrough({})
    sentNothing(tc, "templates")
    for _, opts in ipairs({ { noMenuTemplates = true }, { noMenuAPI = true } }) do
        local what = next(opts)
        local got, c = choicesThrough(opts)
        equal(got, expected, what .. ": the same effects as the template path")
        local funnel, weapon = funnelOf(c), selector(c, 157)
        for _, b in ipairs({ funnel, weapon }) do
            equal(b.kind, "Button", what .. ": kind")
            equal(b.template, "UIPanelButtonTemplate", what .. ": template")
            check(b.menu, what .. ": its own menu")
        end
        equal(funnel.points[1].x .. "," .. funnel.points[1].y, "757,-4", what .. ": funnel position")
        equal(weapon.height, 22, what .. ": the fallback weapon type button keeps its own height")
        local texts = openMenu(c, funnel)
        equal(texts[1] .. "|" .. texts[4], "All|All classes", what .. ": Show, then the classes")
        funnel.close()
        sentNothing(c, what)
        TC.BrowserState.SelectMode("For sale")
        openMenu(c, funnel)
        local show = findAll(c, function(w) return w.kind == "Button" and w.parent == funnel.menu and visible(w) end)
        equal(show[1].enabled, false, what .. ": Show greyed in For sale")
        noErrors(c, what)
    end
end)

-- Every action button of the panel, with an item list open: the status
-- line's 90 x 20 (Scan again) or 110 x 20 (Price this slot), the empty
-- state's 160 x 22, Check again 90 x 20, a row's Buy 40 x 18.
local function actionButtons(c)
    return findAll(c, function(w) return w.kind == "Button" and w.scripts.OnClick and w.width and
        ((w.width == 90 and w.height == 20) or (w.width == 110 and w.height == 20) or (w.width == 160 and w.height == 22)
            or (w.width == 40 and w.height == 18)) end)
end

test("styles: the action buttons are the auction house's UIPanelButtonTemplate, or bare buttons without it", function()
    for _, opts in ipairs({ {}, { noButtonTemplate = true } }) do
        local what = opts.noButtonTemplate and "without the template" or "with the template"
        local c, tabs = visitTwice({ appearances = Fake.appearances(30, 0), noButtonTemplate = opts.noButtonTemplate })
        tabs[1].scripts.OnClick(tabs[1])
        local frames = tileFrames(c)
        frames[1].button.scripts.OnClick(frames[1].button)
        c.advance(10)
        frames[1].button.scripts.OnClick(frames[1].button)
        local buttons = actionButtons(c)
        local sizes = {}
        for _, b in ipairs(buttons) do
            local key = b.width .. "x" .. b.height
            sizes[key] = (sizes[key] or 0) + 1
            equal(b.template, not opts.noButtonTemplate and "UIPanelButtonTemplate" or nil, what .. ": " .. key .. " template")
        end
        equal(sizes["110x20"], 1, what .. ": Price this slot")
        equal(sizes["90x20"], 1, what .. ": Check again")
        equal(sizes["160x22"], 1, what .. ": the empty state's button")
        equal(sizes["40x18"], 4, what .. ": a Buy per row")
        -- the empty state's button still forwards its action
        TC.BrowserState.CloseList()
        TC.BrowserState.SetFilter("Collected")
        local button = find(c, function(w) return w.kind == "Button" and w.text == "Show all" and visible(w) end)
        check(button and c.click(button), what .. ": Show all clicked")
        equal(TC.BrowserState.View().filter, "All", what .. ": Show All after Show all")
        noErrors(c, what)
    end
end)

---------------------------------------------------------------- Layout B, steps 1 to 5 (TC-37): state

local function openID()
    local l = TC.BrowserState.View().list
    return l and l.appearance.id
end

test("B state: 24 tiles a page with a tile open and closed; opening and closing never change the page", function()
    local c = checkState()
    TC.BrowserState.NextPage()
    local v = TC.BrowserState.View()
    local last = v.tiles[24]
    openChecked(c, last)
    v = TC.BrowserState.View()
    equal(#v.tiles, 24, "tiles a page with a tile open")
    equal(v.page, 2, "page after opening the 48th tile")
    equal(v.pageText, "Page 2 / 16", "page text with a tile open")
    check(v.tiles[24].open, "the open tile keeps its place")
    TC.BrowserState.CloseList()
    v = TC.BrowserState.View()
    equal(#v.tiles, 24, "tiles a page after closing")
    equal(v.page, 2, "page after closing")
    equal(c.ah.sends[1] ~= nil, true, "the click on an unchecked tile checked it")
end)

test("B state: a second click on the open tile closes it, another tile moves it, the close mark closes it", function()
    local c, tiles = checkState()
    click(tiles[1])
    click(tiles[2])
    c.advance(10)
    local sends = #c.ah.sends
    click(tiles[1])
    equal(openID(), tiles[1].appearance.id, "a click on a kept result opens it")
    click(tiles[1])
    equal(openID(), nil, "a second click on the open tile closes the flyout")
    click(tiles[1])
    equal(openID(), tiles[1].appearance.id, "a third click opens it again")
    equal(#c.ah.sends, sends, "no read for a kept result")
    click(tiles[2])
    equal(openID(), tiles[2].appearance.id, "another tile moves it")
    TC.BrowserState.CloseList()
    equal(openID(), nil, "CloseList closes it")
end)

test("B state: a page turn by arrow or wheel, a slot change and a toggle change close the flyout", function()
    local c, tiles = checkState()
    local function reopen()
        click(TC.BrowserState.View().tiles[1])
        if not openID() then
            c.advance(10)
            click(TC.BrowserState.View().tiles[1])
        end
        check(openID(), "open")
    end
    reopen()
    TC.BrowserState.NextPage()
    equal(openID(), nil, "closed by the next arrow")
    reopen()
    TC.BrowserState.PreviousPage()
    equal(openID(), nil, "closed by the previous arrow")
    reopen()
    TC.BrowserState.Wheel(-1)
    equal(TC.BrowserState.View().page, 2, "the wheel down turns to the next page")
    equal(openID(), nil, "closed by the wheel")
    reopen()
    TC.BrowserState.Wheel(1)
    equal(TC.BrowserState.View().page, 1, "the wheel up turns back")
    equal(openID(), nil, "closed by the wheel up")
    reopen()
    TC.BrowserState.SelectMode("For sale")
    equal(openID(), nil, "closed by the sweep toggle")
    c.advance(10)
    TC.BrowserState.SelectMode("All")
    reopen()
    TC.BrowserState.SelectMode("For sale")
    TC.BrowserState.SelectMode("All")
    equal(openID(), nil, "closed by the catalogue toggle")
    reopen()
    TC.BrowserState.SelectSlot("legs")
    equal(openID(), nil, "closed by a slot change")
end)

test("B state: a Show or class change closes the flyout only when its tile leaves the page", function()
    local c = classState(50)
    openChecked(c, TC.BrowserState.View().tiles[1])
    local id = openID()
    check(id, "open")
    TC.BrowserState.SetFilter("Not collected")
    equal(openID(), id, "a Show change that keeps the tile on page 1 keeps it")
    TC.BrowserState.SetFilter("Collected")
    equal(openID(), nil, "a Show change that removes the tile closes it")
    TC.BrowserState.SetFilter("All")
    TC.BrowserState.NextPage()
    openChecked(c, TC.BrowserState.View().tiles[1])
    check(openID(), "open on page 2")
    c.advance(10)
    local sends = #c.ah.sends
    TC.BrowserState.SelectClass(1)
    equal(TC.BrowserState.View().page, 1, "the class change goes to page 1")
    equal(openID(), nil, "the tile is not on page 1: closed")
    c.advance(10)
    equal(#c.ah.sends, sends, "the class change reads nothing")
end)

test("B state: arrows and the wheel turn pages and read nothing; the view carries no wheel glow", function()
    local c = checkState()
    local v = TC.BrowserState.View()
    equal(v.wheelGlow, nil, "no wheel glow in the view")
    TC.BrowserState.NextPage()
    TC.BrowserState.NextPage()
    equal(TC.BrowserState.View().page, 3, "two arrow clicks: page 3")
    TC.BrowserState.Wheel(-1)
    equal(TC.BrowserState.View().page, 4, "the wheel turns on")
    TC.BrowserState.Wheel(1)
    TC.BrowserState.PreviousPage()
    equal(TC.BrowserState.View().page, 2, "back by the wheel and the arrow")
    equal(#c.ah.sends, 0, "paging reads nothing")
end)

test("B state: the funnel's Show and class choices, the changed mark and Reset filters; nothing is read", function()
    local c = checkState()
    local v = TC.BrowserState.View()
    equal(v.filtersChanged, false, "at the start nothing differs")
    local names = {}
    for i, e in ipairs(v.filters) do names[i] = e.name .. (e.selected and "*" or "") end
    equal(table.concat(names, "|"), "All|Collected|Not collected*", "the Show entries, the chosen marked")
    equal(v.filterFixed, false, "Show is free in the catalogue")
    TC.BrowserState.SelectClass("all")
    equal(TC.BrowserState.View().filtersChanged, true, "All classes differs from the start")
    TC.BrowserState.SelectClass(9)
    equal(TC.BrowserState.View().filtersChanged, false, "the own class chosen again is the start")
    TC.BrowserState.SetFilter("All")
    v = TC.BrowserState.View()
    equal(v.filtersChanged, true, "Show All differs from the start")
    TC.BrowserState.SelectClass(1)
    TC.BrowserState.NextPage()
    TC.BrowserState.ResetFilters()
    v = TC.BrowserState.View()
    equal(v.filter, "Not collected", "Show back on Not collected")
    equal(v.classes.text, "Warlock", "the class back on the character's")
    equal(v.page, 1, "page 1 after the reset")
    equal(v.filtersChanged, false, "nothing differs after the reset")
    TC.BrowserState.SelectMode("For sale")
    c.advance(10)
    v = TC.BrowserState.View()
    equal(v.filterFixed, true, "Show fixed in the sweep view")
    equal(v.filter, "Not collected", "fixed on Not collected")
    equal(v.filtersChanged, false, "the fixed Show is not a change")
    TC.BrowserState.SelectMode("All")
    TC.BrowserState.SetFilter("All")
    TC.BrowserState.SelectMode("For sale")
    equal(TC.BrowserState.View().filtersChanged, false, "Show All set in the catalogue is no mark in the sweep view")
    TC.BrowserState.SelectClass(1)
    equal(TC.BrowserState.View().filtersChanged, true, "another class is the mark in the sweep view")
    equal(#c.ah.sends, 1, "only the sweep toggle's scan was read")
end)

test("B state: Price this slot starts one scan from the catalogue; then every tile has a price or Not for sale", function()
    local c = bootState()
    TC.BrowserState.Refresh()
    local tiles = TC.BrowserState.View().tiles
    c.ah.listings = { listing("Item " .. (tiles[3].appearance.id * 10 + 1), tiles[3].appearance.id * 10 + 1, 700) }
    local v = TC.BrowserState.View()
    equal(v.statusButton, "Price this slot", "offered in the catalogue")
    equal(v.status, "Click an appearance to check the auction house.", "the hint beside it")
    equal(#c.ah.sends, 0, "being shown reads nothing")
    v.statusAction()
    equal(#c.ah.sends, 1, "one scan")
    equal(TC.BrowserState.View().status, "Scanning head", "the status while it runs")
    equal(TC.BrowserState.View().statusButton, nil, "no offer while it runs")
    c.advance(10)
    v = TC.BrowserState.View()
    equal(v.mode, "All", "still the catalogue")
    for i, tile in ipairs(v.tiles) do
        check(tile.strip == "price" or tile.strip == "not for sale", "tile " .. i .. " priced, got " .. tile.strip)
    end
    equal(v.tiles[3].price, "7s", "the listed tile's price")
    equal(v.status, "Scanned just now", "the age")
    equal(v.statusButton, "Scan again", "Scan again once scanned")
    equal(#c.ah.sends, 1, "browses")
    TC.BrowserState.SelectMode("For sale")
    equal(TC.BrowserState.View().statusButton, "Scan again", "the sweep view of a scanned slot")
    TC.BrowserState.SelectSlot("legs")
    equal(TC.BrowserState.View().statusButton, nil, "never offered in the sweep view")
end)

test("B state: the flyout's head and body states keep their texts; a found row carries its Buy", function()
    local c, tiles = checkState({ [1] = { 500, 900 } }, { items = { [10062] = { load = "never" } } })
    click(tiles[1])
    c.advance(5)
    click(tiles[1])
    TC.BrowserState.CheckAgain()
    local l = TC.BrowserState.View().list
    equal(l.state, "checking", "checking")
    equal(l.title, "Checking the auction house", "checking title")
    equal(l.foot.age, "Checking", "the foot while checking")
    equal(l.foot.button, "Check again", "Check again shown while checking")
    equal(l.foot.enabled, false, "and off")
    equal(l.collected, false, "not collected")
    c.advance(5)
    l = TC.BrowserState.View().list
    equal(l.title, "2 item variants, cheapest first", "found summary")
    equal(l.rows[1].forSale, "x1", "the count of a row")
    equal(l.rows[2].forSale, "x2", "the count of the second row")
    check(l.rows[1].buy and l.rows[1].buy.enabled, "a found row's Buy")
    equal(l.foot.enabled, true, "Check again on once checked")
    equal(l.foot.note, "Could not check 1 of 3 items.", "items left out")
    click(tiles[2])
    c.advance(5)
    click(tiles[2])
    l = TC.BrowserState.View().list
    equal(l.state, "not for sale", "not for sale")
    equal(l.text, "No item with this appearance is on the auction house.", "not for sale text")
end)

---------------------------------------------------------------- Layout B, steps 1 to 5 (TC-37): the panel

local function point(w) local p = w.points[1] return p and (p.x .. "," .. p.y) end
local function hover(w)
    GameTooltip.text, GameTooltip.calls.AddLine = nil, nil
    w.scripts.OnEnter(w)
    return GameTooltip.text, GameTooltip.calls.AddLine and GameTooltip.calls.AddLine[1]
end
local function texturePath(w) return w.calls.SetTexture and w.calls.SetTexture[1] end
-- The funnel's reset mark: the 14 square button on it.
local function markOf(c)
    local funnel = funnelOf(c)
    return find(c, function(w) return w.kind == "Button" and w.parent == funnel and w.width == 14 end)
end
local function arrowsOf(c)
    return findAll(c, function(w) return w.kind == "Button" and w.width == 22 and w.height == 22 and w.calls.SetNormalTexture end)
end
local function wheelMarkOf(c)
    return find(c, function(w) return w.kind == "Frame" and w.width == 16 and w.height == 16 and w.scripts.OnEnter end)
end
-- The wheel mark's textures: the art alone.
local function wheelArts(c)
    local mark = wheelMarkOf(c)
    return findAll(c, function(w) return w.kind == "Texture" and w.parent == mark end)
end

test("B whole: the header row: two glyph toggles at x 60 and 94, the slot row, Search, the funnel; the count in the band", function()
    local c, tabs = visitTwice({ appearances = manySlots() })
    tabs[1].scripts.OnClick(tabs[1])
    local all, sale = modeTab(c, "All"), modeTab(c, "For sale")
    for _, t in ipairs({ { all, "60,-4", "catalogue", "All appearances" }, { sale, "94,-4", "sweep", "For sale, cheapest first" } }) do
        local b = t[1]
        equal(b.template, "SquareIconButtonTemplate", t[3] .. " template")
        equal(b.width .. "x" .. b.height, "30x30", t[3] .. " size")
        equal(point(b), t[2], t[3] .. " position")
        equal(texturePath(b.Icon), "Interface\\AddOns\\TransmogChecker\\Media\\" .. t[3], t[3] .. " art")
        equal(b.Icon.width .. "x" .. b.Icon.height, "16x16", t[3] .. " glyph size")
        local title, line = hover(b)
        equal(title, t[4], t[3] .. " tooltip names it")
        check(line, t[3] .. " tooltip line")
    end
    check(all.ring and visible(all.ring) and not visible(sale.ring), "the catalogue ringed at the start")
    equal(point(slotButtons(c)[1]), "136,-4", "the slot row at x 136, y 4")
    local count = countShown(c)
    equal(point(count), "28,-50", "the count at x 28, y 50")
    equal(point(funnelOf(c)), "757,-4", "the funnel at x 757, y 4")
    -- nothing of the old header
    equal(#findAll(c, function(w) return w.template == "PanelTopTabButtonTemplate" end), 0, "no text tabs")
    equal(#findAll(c, function(w) return (w.kind == "Button" or w.kind == "DropdownButton") and (w.width == 150 or w.width == 138) end),
        0, "no class dropdown and no Filter button")
    check(not find(c, function(w) return w.text and w.text:find("^Filter: ") end), "no Filter text")
    check(not textShown(c, "Head"), "no slot title")
    noErrors(c, "header")
end)

test("B whole: the toggles select the views and send what All and For sale sent: nothing, or one scan", function()
    local c, tabs = visitTwice()
    for id = 1010, 1030, 10 do c.ah.listings[#c.ah.listings + 1] = listing("Item " .. (id * 10 + 1), id * 10 + 1, id) end
    tabs[1].scripts.OnClick(tabs[1])
    local all, sale = modeTab(c, "All"), modeTab(c, "For sale")
    check(c.click(all), "the catalogue toggle clicked")
    c.advance(10)
    equal(#c.ah.sends, 0, "the catalogue toggle on the catalogue sends nothing")
    check(c.click(sale), "the sweep toggle clicked")
    c.advance(10)
    equal(#c.ah.sends, 1, "the sweep toggle on a slot not scanned: one scan")
    check(visible(sale.ring) and not visible(all.ring), "the sweep toggle ringed, the catalogue not")
    check(sale.Icon.calls.SetAlpha[1] == 1 and all.Icon.calls.SetAlpha[1] < 1, "the catalogue glyph dimmed")
    equal(sale.Icon.calls.SetDesaturated[1], false, "the selected glyph in colour")
    equal(all.Icon.calls.SetDesaturated[1], true, "the other glyph desaturated")
    equal(sale.ring.calls.SetAtlas[1], "transmog-nav-slot-selected", "the slot row's ring art")
    check(not sale.highlightLocked, "the ring replaces the lit highlight")
    check(textShown(c, "3 of 370 appearances"), "the sweep view's count")
    c.click(all)
    c.click(sale)
    c.click(all)
    c.advance(10)
    equal(#c.ah.sends, 1, "both toggles on a scanned slot: nothing more")
    check(visible(all.ring) and not visible(sale.ring), "the catalogue ringed again, exactly one ring")
    check(all.Icon.calls.SetAlpha[1] == 1 and sale.Icon.calls.SetAlpha[1] < 1, "the sweep glyph dimmed")
    noErrors(c, "toggles")
end)

test("B whole: the funnel's mark shows while a choice differs; the mark and Reset filters reset; nothing is sent", function()
    local c, tabs = visitTwice(classFixture(0))
    tabs[1].scripts.OnClick(tabs[1])
    local mark = markOf(c)
    local funnel = funnelOf(c)
    check(mark and not visible(mark), "no mark at the start")
    check(not funnel.highlightLocked, "the funnel's highlight is not held at the start")
    equal(mark.width .. "x" .. mark.height, "14x14", "the mark's size")
    equal(mark.points[1].relativePoint, "TOPLEFT", "the mark at the funnel's top left")
    local names, choose = classEntries(c)
    choose(names[1])
    check(visible(mark), "the mark after All classes")
    check(funnel.highlightLocked, "the funnel's highlight is held while another class is chosen")
    check(textShown(c, "7 appearances"), "count under All classes")
    check(c.click(mark), "the mark clicked")
    check(not visible(mark), "the mark gone after the reset")
    check(not funnel.highlightLocked, "the funnel's highlight released after the reset")
    check(textShown(c, "3 appearances"), "count back on Warlock")
    local _, pick = openMenu(c, funnelOf(c))
    pick("All")
    check(visible(mark), "the mark after Show All")
    check(funnel.highlightLocked, "the highlight held after Show All")
    local texts
    texts, pick = openMenu(c, funnelOf(c))
    equal(texts[#texts], "Reset filters", "the menu's last entry")
    check(pick("Reset filters"), "Reset filters chosen")
    check(not visible(mark), "no mark after Reset filters")
    check(not funnel.highlightLocked, "the highlight released after Reset filters")
    equal(markedShow(c), "Not collected", "Show back on Not collected")
    c.advance(5)
    sentNothing(c, "funnel")
    noErrors(c, "funnel")
end)

test("B whole: 24 tiles that never move; the flyout is built on the first tile click and opens beside its tile", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    local before = {}
    for i, f in ipairs(frames) do before[i] = point(f) end
    equal(before[9], "0,-128", "tile 9 starts the second row")
    equal(point(frames[1]:GetParent()), "28,-80", "the grid at x 28, y 80")
    equal(itemListFrame(c), nil, "no flyout before the first tile click")
    local function open(i) return openTile(c, frames[i]) end
    local fly = open(1)
    check(fly and visible(fly), "the flyout after the first click")
    equal(fly.width, 232, "232 wide")
    equal(point(fly), "114,-80", "column 1: right of the tile, 8 from it, held at the grid top")
    local notch = findAll(c, function(w) return w.kind == "Texture" and w.parent == fly and w.calls.SetRotation end)
    equal(#notch, 2, "the notch's two parts")
    equal(notch[1].points[1].relativePoint .. "," .. notch[1].points[1].y, "TOPLEFT,-52", "the notch on the left edge at the tile's middle")
    open(5)
    equal(point(fly), "490,-80", "column 5: still right")
    open(6)
    equal(point(fly), "258,-80", "column 6: left of the tile")
    equal(notch[1].points[1].relativePoint, "TOPRIGHT", "the notch on the right edge")
    open(8)
    equal(point(fly), "446,-80", "column 8: left")
    open(9)
    equal(point(fly), "114,-180", "row 2: 28 above the tile")
    local after = {}
    for i, f in ipairs(frames) do after[i] = point(f) end
    equal(table.concat(after, " "), table.concat(before, " "), "no tile moved")
    equal(#findAll(c, function(w) return w.model and w.button and visible(w) end), 24, "24 tiles with the flyout open")
    equal(#findAll(c, function(w) return w.kind == "Frame" and w.width == 232 end), 1, "one flyout frame")
    noErrors(c, "flyout")
end)

test("B whole: a top-row flyout stays below the band of the count text and the weapon type dropdown", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    local countText = find(c, function(w) return w.kind == "FontString" and w.points[1] and w.points[1].x == 28 and w.points[1].y == -50 end)
    local weaponBox = find(c, function(w) return w.points[1] and w.points[1].x == 598 and w.points[1].y == -58 end)
    check(countText and weaponBox, "the count text and the weapon type dropdown found")
    -- the count text has no width of its own: it may run to the flyout's far edge
    local bands = { { 28, 50, 1000, 50 + 14 }, { 598, 58 - (weaponBox and weaponBox.height or 22) / 2, 598 + 157, 58 + (weaponBox and weaponBox.height or 22) / 2 } }
    for _, i in ipairs({ 1, 4, 8 }) do
        local fly = openTile(c, frames[i])
        local fx, fy = fly.points[1].x, -fly.points[1].y
        local fx2, fy2 = fx + fly.width, fy + fly.height
        for n, b in ipairs(bands) do
            check(not (fx < b[3] and b[1] < fx2 and fy < b[4] and b[2] < fy2), "column " .. i .. ": the flyout misses band " .. n)
        end
        check(fy >= 80, "column " .. i .. ": the top is not above the grid")
        c.click(frames[i].button)
    end
    noErrors(c, "top row")
end)

test("B whole: the click event is registered only while the flyout is shown", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    local function registered() return #findAll(c, function(w) return w.events.GLOBAL_MOUSE_DOWN end) end
    equal(registered(), 0, "none before the first tile click")
    c.click(frames[2].button)
    equal(registered(), 0, "none while only a check runs")
    c.advance(10)
    c.click(frames[2].button)
    equal(registered(), 1, "one while the flyout is shown")
    c.click(frames[2].button)
    equal(registered(), 0, "none after the flyout closes")
    c.click(frames[2].button)
    equal(registered(), 1, "one again when it reopens")
    c.closeAuction()
    equal(registered(), 0, "none after the auction window closes")
    noErrors(c, "event")
end)

test("B whole: a bottom-row flyout is moved up to end at the grid's bottom; four rows show, the rest scroll", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    local itemID = frames[24].appearance.id * 10 + 1
    for n = 1, 6 do c.ah.listings[n] = listing("Item " .. itemID, itemID, n * 100, { itemSuffix = n }) end
    c.click(frames[24].button)
    c.advance(10)
    c.click(frames[24].button)
    local fly = itemListFrame(c)
    equal(fly.height, 66 + 4 * 40 + 28, "head, four rows, foot")
    equal(point(fly), "446,-" .. (440 - fly.height), "column 8, row 3: left, its bottom at y 440")
    local notch = findAll(c, function(w) return w.kind == "Texture" and w.parent == fly and w.calls.SetRotation end)
    equal(notch[1].points[1].y, -(336 + 52 - (440 - fly.height)), "the notch still on the tile's middle")
    local function inFlyout(text)
        return find(c, function(w) return w.text == text and under(w, fly) and visible(w) end) ~= nil
    end
    check(inFlyout("6 item variants, cheapest first"), "the summary")
    check(inFlyout("1s") and inFlyout("4s") and not inFlyout("5s"), "four rows")
    fly.scripts.OnMouseWheel(fly, -1)
    check(not inFlyout("1s") and inFlyout("5s"), "the wheel over it scrolls its rows")
    equal(TC.BrowserState.View().page, 1, "not the page")
    noErrors(c, "bottom row")
end)

test("B whole: a second click on the open tile, the close mark, Escape, a click outside, an arrow and the wheel close the flyout", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    local function open()
        c.click(frames[2].button)
        local fly = itemListFrame(c)
        check(fly and visible(fly), "open")
        return fly
    end
    c.click(frames[2].button)
    c.advance(10)
    local sends = #c.ah.sends
    local fly = open()
    c.click(frames[2].button)
    check(not visible(fly), "closed by a second click on its tile")
    open()
    local close = find(c, function(w) return w.kind == "Button" and w.parent == fly and w.width == 20 end)
    c.click(close)
    check(not visible(fly), "closed by the close mark")
    open()
    local key = c.key("W")
    equal(key.passed, true, "another key passes on")
    key = c.key("ESCAPE")
    check(not visible(fly), "closed by Escape")
    equal(key.kept, true, "Escape kept by the flyout")
    check(AuctionHouseFrame:IsShown(), "the auction window stays open")
    equal(#c.escHandlers, 0, "no game menu Escape handler")
    open()
    fly.mouseOver = true
    c.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    check(visible(fly), "a click on the flyout keeps it")
    fly.mouseOver = false
    frames[5].button.mouseOver = true
    c.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    check(visible(fly), "a press on a tile is the tile's")
    frames[5].button.mouseOver = false
    c.fire("GLOBAL_MOUSE_DOWN", "RightButton")
    check(visible(fly), "a right-button press outside keeps it")
    c.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    check(not visible(fly), "closed by a left click outside")
    open()
    local arrows = arrowsOf(c)
    c.click(arrows[2])
    check(not visible(fly), "closed by the next arrow")
    c.click(arrows[1])
    open()
    frames[1]:GetParent().scripts.OnMouseWheel(frames[1]:GetParent(), -1)
    check(not visible(fly), "closed by the wheel")
    equal(#c.ah.sends, sends, "closing and opening on a kept result read nothing")
    noErrors(c, "closing")
end)

test("B whole: in combat the flyout takes no key, so Escape goes to the game", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local fly = openTile(c, tileFrames(c)[1])
    c.enterCombat()
    equal(fly.keyboard, false, "keyboard released when combat starts")
    local key = c.key("ESCAPE")
    equal(key.passed, true, "Escape passed on")
    equal(c.propagateInCombat, 0, "no propagation call in combat")
    noErrors(c, "combat")
end)

test("B whole: the flyout's rows carry the price beside Buy; every body state answers its texts on screen", function()
    local c = buyWhole()
    local fly = itemListFrame(c)
    local buy = rowBuy(c)
    check(buy and visible(buy), "Buy on the found row")
    local price = find(c, function(w) return w.kind == "FontString" and w.parent == buy:GetParent() and w.text == "5s" end)
    check(price, "the row's price")
    equal(price.points[1].point .. ">" .. price.points[1].relativePoint, "RIGHT>LEFT", "the price's right edge on Buy's left")
    equal(price.points[1].relativeTo, buy, "the price beside Buy")
    check(textShown(c, "x1"), "the row's count")
    check(textShown(c, "1 item variant, cheapest first"), "found")
    check(textShown(c, "Checked just now") and textShown(c, "Check again"), "the foot")
    local again = find(c, function(w) return w.kind == "Button" and w.text == "Check again" and visible(w) end)
    c.click(again)
    check(textShown(c, "Checking the auction house") and textShown(c, "Checking"), "checking, in the summary and the foot")
    equal(again.enabled, false, "Check again off while checking")
    c.advance(10)
    c.ah.listings = {}
    c.click(c.frames[2].button)
    c.advance(10)
    c.click(c.frames[2].button)
    check(textShown(c, "Not for sale right now"), "not for sale")
    check(textShown(c, "No item with this appearance is on the auction house."), "its text")
    check(textShown(c, "Ivy Boots"), "the item looked up")
    c.ah.silent = true
    c.click(find(c, function(w) return w.kind == "Button" and w.text == "Check again" and visible(w) end))
    c.advance(20)
    check(textShown(c, "The auction house did not answer."), "could not check")
    equal(fly.width, 232, "the same flyout")
    noErrors(c, "bodies")
end)

test("B whole: the wheel mark before the page text with its tooltip, the arrows' tooltip; no hint with one page", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local mark = wheelMarkOf(c)
    check(mark and visible(mark), "the wheel mark shown")
    local pageText = find(c, function(w) return w.text == "Page 1 / 16" end)
    equal(mark.points[1].relativeTo, pageText, "beside the page text")
    equal(mark.points[1].point .. ">" .. mark.points[1].relativePoint, "RIGHT>LEFT", "before it")
    local arts = wheelArts(c)
    equal(#arts, 1, "the art alone")
    equal(texturePath(arts[1]), "Interface\\AddOns\\TransmogChecker\\Media\\wheel", "the wheel art")
    equal((hover(mark)), "Mouse wheel over the tiles turns pages", "the mark's tooltip")
    local arrows = arrowsOf(c)
    local title, line = hover(arrows[2])
    equal(title .. " / " .. line, "Next page / Mouse wheel over the tiles turns pages too.", "the next arrow's tooltip")
    equal((hover(arrows[1])), "Previous page", "the previous arrow's tooltip")
    c.click(arrows[2])
    c.click(arrows[2])
    check(textShown(c, "Page 3 / 16"), "the arrows turned the pages")
    local grid = tileFrames(c)[1]:GetParent()
    grid.scripts.OnMouseWheel(grid, -1)
    check(textShown(c, "Page 4 / 16"), "the wheel still turns pages")
    TC.BrowserState.SetFilter("Collected")
    check(not visible(mark), "no hint with one page")
    c.advance(5)
    sentNothing(c, "paging")
    noErrors(c, "wheel")
end)

test("B whole: Price this slot at x 28 starts one scan from the catalogue; every tile then has a price or Not for sale", function()
    local c, tabs = visitTwice()
    for id = 1010, 1030, 10 do c.ah.listings[#c.ah.listings + 1] = listing("Item " .. (id * 10 + 1), id * 10 + 1, id) end
    tabs[1].scripts.OnClick(tabs[1])
    TC.BrowserState.SetFilter("All")
    c.advance(5)
    equal(#c.ah.sends, 0, "shown, it sends nothing")
    local offer = find(c, function(w) return w.kind == "Button" and w.text == "Price this slot" and visible(w) end)
    check(offer, "Price this slot shown")
    equal(offer.width .. "x" .. offer.height, "110x20", "its size")
    equal(point(offer), "28,-447", "at the grid's left edge on the status line")
    local hint = find(c, function(w) return w.text == "Click an appearance to check the auction house." end)
    equal(point(hint), "144,-445", "the hint after it")
    check(c.click(offer), "clicked")
    c.advance(30)
    equal(#c.ah.sends, 1, "one scan")
    check(visible(modeTab(c, "All").ring), "still the catalogue")
    for i, f in ipairs(tileFrames(c)) do
        if visible(f) then
            check((f.price.text or "") ~= "" or f.notForSale.text == "Not for sale", "tile " .. i .. " priced")
        end
    end
    check(not textShown(c, "Price this slot"), "not offered once scanned")
    check(textShown(c, "Scanned just now") and textShown(c, "Scan again"), "the age and Scan again")
    equal(point(find(c, function(w) return w.text == "Scanned just now" end)), "144,-445", "the age after the button")
    noErrors(c, "price this slot")
end)

test("C1: the status row: its button on the grid's left edge, in one place and one width in every state; the text after it", function()
    local c, tabs = visitTwice()
    for id = 1010, 1030, 10 do c.ah.listings[#c.ah.listings + 1] = listing("Item " .. (id * 10 + 1), id * 10 + 1, id) end
    tabs[1].scripts.OnClick(tabs[1])
    local grid = tileFrames(c)[1]:GetParent()
    local gridX = grid.points[1].x
    local function textAt(text)
        local w = find(c, function(w) return w.kind == "FontString" and w.text == text end)
        return w and w.points[1].x
    end
    local function buttonNamed(text)
        return find(c, function(w) return w.kind == "Button" and w.text == text and visible(w) end)
    end
    local offer = buttonNamed("Price this slot")
    local where, width = point(offer), offer.width
    equal(offer.points[1].x, gridX, "before a scan: the button at the grid's left edge")
    equal(point(countShown(c)), gridX .. ",-50", "the count text at the same x")
    equal(textAt("Click an appearance to check the auction house."), gridX + width + 6, "before a scan: the text after the button")
    c.click(offer)
    c.advance(30)
    local again = buttonNamed("Scan again")
    equal(point(again), where, "after a scan: the same place")
    equal(again.width, width, "after a scan: the same width")
    check(textAt("Scanned just now") > gridX + width, "after a scan: the text after the button")
    c.click(modeTab(c, "For sale"))
    again = buttonNamed("Scan again")
    equal(point(again), where, "in the sweep view after a scan: the same place")
    equal(again.width, width, "in the sweep view after a scan: the same width")
    check(textAt("Scanned just now") > gridX + width, "in the sweep view: the text after the button")
    -- a state without a button: the text starts at the grid's left edge
    TC.BrowserState.SelectSlot("legs")
    check(not buttonNamed("Scan again") and not buttonNamed("Price this slot"), "no button while the scan runs")
    equal(textAt("Scanning legs"), gridX, "without a button the text starts at the grid's left edge")
    noErrors(c, "status row")
end)

test("C2: the page text keeps the width of its widest form, so turning from page 9 to page 10 of 11 moves nothing", function()
    local c, tabs = visitTwice({ appearances = Fake.appearances(250, 0) })
    tabs[1].scripts.OnClick(tabs[1])
    local function pageText()
        return find(c, function(w) return w.kind == "FontString" and w.text and w.text:find("^Page %d") end)
    end
    local text, mark = pageText(), wheelMarkOf(c)
    check(textShown(c, "Page 1 / 11"), "eleven pages")
    for _ = 1, 8 do TC.BrowserState.NextPage() end
    check(textShown(c, "Page 9 / 11"), "page 9")
    local width, textPoint, markPoint = text.width, point(text), point(mark)
    local probe = text:GetParent():CreateFontString()
    probe:SetText("Page 11 / 11")
    equal(width, probe:GetStringWidth(), "the width is that of the widest form")
    TC.BrowserState.NextPage()
    check(textShown(c, "Page 10 / 11"), "page 10")
    equal(text.width, width, "the page text's width is unchanged")
    equal(point(text), textPoint, "its place is unchanged")
    equal(point(mark), markPoint, "the wheel mark's place is unchanged")
    equal(mark.points[1].relativeTo, text, "the mark stays on the text")
    noErrors(c, "page text")
end)

test("C3: the paging group ends at the grid's right edge, in the catalogue and in the sweep view", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local grid = tileFrames(c)[1]:GetParent()
    local function ends(what)
        local paging = find(c, function(w) return w.kind == "Frame" and w.width == 200 and w.height == 24 end)
        equal(paging.points[1].point .. ">" .. paging.points[1].relativePoint, "TOPRIGHT>TOPRIGHT", what .. ": anchored by its right edge")
        equal(paging.points[1].x, -grid.points[1].x, what .. ": the panel's right inset is the grid's left inset")
        local arrow = arrowsOf(c)[2]
        equal(arrow.points[1].relativeTo, paging, what .. ": the last arrow on the group")
        equal(arrow.points[1].point .. ">" .. arrow.points[1].relativePoint .. " " .. arrow.points[1].x, "RIGHT>RIGHT 0",
            what .. ": its right edge on the group's")
    end
    ends("catalogue")
    c.click(modeTab(c, "For sale"))
    c.advance(10)
    ends("sweep view")
    noErrors(c, "paging edge")
end)

test("head: the summary line sits right of the model under the type line, in the head, and the first row starts under the head", function()
    local c = buyWhole()
    local fly = itemListFrame(c)
    local function inFly(text)
        return find(c, function(w) return w.text == text and w.kind == "FontString" and under(w, fly) and visible(w) end)
    end
    local summary, typeText = inFly("1 item variant, cheapest first"), inFly("Head, cloth")
    check(summary and typeText, "the summary and the type line")
    local anchor = summary.points[1]
    equal(anchor.relativeTo, typeText, "anchored to the type line")
    equal(anchor.point .. ">" .. anchor.relativePoint, "TOPLEFT>BOTTOMLEFT", "under it")
    equal(anchor.x, 0, "at its left edge")
    check(typeText.points[1].x >= 10 + 44, "right of the 44 wide model")
    equal(summary.width, 232 - typeText.points[1].x - 28, "wrapping before the close mark")
    local row = rowBuy(c):GetParent()
    equal(point(row), "10,-66", "the first row starts right under the 66 high head")
    equal(fly.height, 66 + 40 + 28, "head, one row, foot: 134 high, 18 less than with the summary band")
    noErrors(c, "head")
end)

test("B whole: a click checks without opening; the strip reads, then prices; the gold border marks the open tile only; No answer", function()
    local c, tabs = visitTwice()
    local id = 1006 * 10 + 1
    c.ah.listings = { listing("Item " .. id, id, 500) }
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    local function gold(f) return f.border.color[2] == 0.82 end
    c.click(frames[1].button)
    equal(itemListFrame(c), nil, "no flyout")
    check(visible(frames[1].bar), "the strip shows the reading state")
    check(not gold(frames[1]), "no gold border while it checks")
    c.click(frames[1].button)
    check(visible(frames[1].bar), "a click while it checks does nothing")
    c.advance(10)
    check(not visible(frames[1].bar), "the reading state ends")
    equal(itemListFrame(c), nil, "no flyout after the check")
    check((frames[1].price.text or "") ~= "", "the strip prices")
    check(not gold(frames[1]), "no gold border without the flyout")
    c.click(frames[1].button)
    check(visible(itemListFrame(c)) and gold(frames[1]), "a click on the result opens the flyout, with the gold border")
    c.ah.fail = true
    c.click(frames[2].button)
    check(not visible(itemListFrame(c)) and not gold(frames[1]) and not gold(frames[2]), "a click on an unchecked tile closes it, no gold border")
    c.advance(10)
    equal(frames[2].notForSale.text, "No answer", "could not check: No answer on the strip")
    equal(itemListFrame(c) ~= nil and visible(itemListFrame(c)), false, "no flyout by itself")
    c.ah.fail = false
    c.click(frames[2].button)
    check(visible(frames[2].bar) and frames[2].notForSale.text == "", "a click on it checks again")
    noErrors(c, "click rules")
end)

test("B whole: the tab, both toggles on a scanned slot, the funnel, paging and flyouts on kept results send nothing", function()
    local c, tabs = visitTwice()
    tabs[1].scripts.OnClick(tabs[1])
    local frames = tileFrames(c)
    c.click(frames[1].button)
    c.advance(10)
    c.click(modeTab(c, "For sale"))
    c.advance(10)
    local sends, searches, more = #c.ah.sends, #c.ah.searches, #c.ah.more
    c.click(modeTab(c, "All"))
    c.click(modeTab(c, "For sale"))
    c.click(modeTab(c, "All"))
    local _, choose = openMenu(c, funnelOf(c))
    choose("All")
    local names
    names, choose = classEntries(c)
    choose(names[1])
    local arrows = arrowsOf(c)
    c.click(arrows[2])
    c.click(arrows[1])
    local grid = frames[1]:GetParent()
    grid.scripts.OnMouseWheel(grid, -1)
    grid.scripts.OnMouseWheel(grid, 1)
    TC.BrowserState.ResetFilters()
    c.click(frames[1].button)
    c.click(frames[1].button)
    c.click(frames[1].button)
    c.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    c.advance(60)
    equal(#c.ah.sends, sends, "browses")
    equal(#c.ah.more, more, "page requests")
    equal(#c.ah.searches, searches, "searches")
    noErrors(c, "zero sends")
end)

test("B whole: without the icon and menu templates and the atlases every control is still there and works", function()
    local c, tabs = visitTwice({ appearances = manySlots(), noMenuTemplates = true, noAtlases = true,
        noTemplates = { SquareIconButtonTemplate = true, UIPanelCloseButton = true, SpinnerTemplate = true } })
    tabs[1].scripts.OnClick(tabs[1])
    local all, sale = modeTab(c, "All"), modeTab(c, "For sale")
    check(all and sale and visible(all) and visible(sale), "both toggles")
    equal(all.template, nil, "a bare catalogue toggle")
    check(not all.ring and not sale.ring, "no atlas: no ring")
    check(all.highlightLocked and not sale.highlightLocked, "no ring art: the catalogue toggle lit by its highlight")
    equal(texturePath(all.Icon), "Interface\\AddOns\\TransmogChecker\\Media\\catalogue", "its glyph")
    equal((hover(sale)), "For sale, cheapest first", "its tooltip")
    local funnel = funnelOf(c)
    check(funnel and visible(funnel), "the funnel")
    equal(funnel.text, "Filter", "without the art it reads Filter")
    local _, choose = openMenu(c, funnel)
    check(choose("All"), "Show All through the list")
    local mark = markOf(c)
    check(visible(mark), "the mark")
    c.click(mark)
    check(not visible(mark), "the mark resets")
    check(wheelMarkOf(c) and visible(wheelMarkOf(c)), "the wheel mark")
    local frames = tileFrames(c)
    local fly = openTile(c, frames[1])
    check(fly and visible(fly), "the flyout")
    local close = find(c, function(w) return w.kind == "Button" and w.parent == fly and w.width == 20 end)
    c.click(close)
    check(not visible(fly), "its bare close mark closes it")
    c.advance(10)
    local sends = #c.ah.sends
    c.click(sale)
    c.advance(10)
    equal(#c.ah.sends, sends + 1, "the sweep toggle scans")
    check(sale.highlightLocked and not all.highlightLocked, "no ring art: the sweep toggle lit, the catalogue not")
    noErrors(c, "fallbacks")
end)

---------------------------------------------------------------- run

for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    print = realPrint
    if ok then
        realPrint("  ok    " .. t.name)
    else
        failures = failures + 1
        realPrint("  FAIL  " .. t.name .. "\n        " .. tostring(err))
    end
end
realPrint(("%d tests, %d failed"):format(#tests, failures))
os.exit(failures == 0 and 0 or 1)
