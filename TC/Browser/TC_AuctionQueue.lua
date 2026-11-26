-- The query queue: the only code in the addon that sends a browse or a
-- search to the auction house. It keeps one message in flight, waits for the
-- client's throttle by event and by polling, reads later pages, and answers
-- every Browse and every Search exactly once: with its rows, or with a
-- failure reason. A failure also fails every browse and search queued
-- behind it. Browse events that arrive with nothing in flight
-- are not ours and are ignored. The client holds one browse result at a time
-- and its events do not say who asked (spec, open point 11), so a browse
-- anyone else sends while ours is in flight fails ours.
TC = TC or {}
TC.AuctionQueue = {}

local Queue = TC.AuctionQueue

-- Spec Assumption A5: an answer or a ready client within 5 seconds.
local LIMIT = 5
-- The "throttle ready" event is unreliable (spec 4.5), so the client is also
-- polled; the probe polled every 0.25 s in game.
local POLL = 0.25
-- A search sorted by buyout, cheapest first, as the probe sent it in game
-- (spec 4.2; Enum.AuctionHouseSortOrder.Buyout is 4,
-- AuctionHouseEnumsDocumentation.lua:122-135).
local SortOrder = Enum and Enum.AuctionHouseSortOrder
local BUYOUT = { { sortOrder = SortOrder and SortOrder.Buyout or 4, reverseSort = false } }

local waiting = {}
-- The browse or search being worked on: sent (its answer is due) or not yet
-- sent (waiting for the client, or a search for its item key's info); nil
-- when the queue is idle. A search is the job with an itemKey.
local current
local ticker
-- Whether the hook on SendBrowseQuery is installed.
local hooked

local function stopTicker()
    if ticker then ticker:Cancel() end
    ticker = nil
end

-- An error in a handler goes to the client's error handler and stops
-- nothing here.
local function report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end

local function finish(job, ok, value, cut)
    local handler = ok and job.handlers.done or job.handlers.failed
    xpcall(function() handler(value, cut) end, report)
end

local startNext

-- Fails the current browse and everything queued behind it.
local function failAll(reason)
    local jobs = { current }
    for _, job in ipairs(waiting) do jobs[#jobs + 1] = job end
    current, waiting = nil, {}
    stopTicker()
    for _, job in ipairs(jobs) do finish(job, false, reason) end
end

-- The calls the queue needs, through feature detection; a missing one is a
-- failure of the browse, never an error.
local BROWSE_CALLS = { "SendBrowseQuery", "RequestMoreBrowseResults", "GetBrowseResults", "HasFullBrowseResults",
    "IsThrottledMessageSystemReady" }
-- AuctionHouseDocumentation.lua:326-340, 374-388, 519-532, 825-832, 1031-1044.
local SEARCH_CALLS = { "SendSearchQuery", "GetItemKeyInfo", "GetNumItemSearchResults", "GetItemSearchResultInfo",
    "IsThrottledMessageSystemReady" }
local function missing(job)
    local AH = C_AuctionHouse
    if not AH then return "C_AuctionHouse is missing" end
    for _, name in ipairs(job.itemKey and SEARCH_CALLS or BROWSE_CALLS) do
        if not AH[name] then return "C_AuctionHouse." .. name .. " is missing" end
    end
    if not (C_Timer and C_Timer.NewTicker and GetTime) then return "C_Timer.NewTicker or GetTime is missing" end
end

-- The client repeats a search's result event 0.28 to 0.43 s after the first
-- (spec 4.5): a new search of the same item key waits this long after the
-- last send of that key and after the last result event for it, so the
-- repeat comes before it and is ignored, also when the answer was slow.
local SAME_KEY_GAP = 1
-- A search the client drops this many times answers as failed.
local MAX_SENDS = 3
-- The time of the last send of each item key, or of the last result event
-- for it when that came later, by keyText.
local lastSend = {}

local function keyText(key)
    return (key.itemID or 0) .. ":" .. (key.itemLevel or 0) .. ":" .. (key.itemSuffix or 0) .. ":"
        .. (key.battlePetSpeciesID or 0)
end

-- A search is sent only once GetItemKeyInfo(itemKey) has returned a table:
-- the client drops it silently otherwise (spec 4.5). Asking is also what
-- makes the client fetch the info. A send after which the client still
-- reports ready was dropped too: it goes out again on a later poll or ready
-- event, never in the same call, at most MAX_SENDS times in all.
local function trySearch(job)
    local AH = C_AuctionHouse
    if not job.keyReady then
        if type(AH.GetItemKeyInfo(job.itemKey)) ~= "table" then return end
        -- the 5 seconds for a ready client start now
        job.keyReady, job.since = true, GetTime()
    end
    if not AH.IsThrottledMessageSystemReady() then return end
    local text = keyText(job.itemKey)
    if job.sends == 0 and lastSend[text] and GetTime() - lastSend[text] < SAME_KEY_GAP then return end
    job.sentAt, job.sends, lastSend[text] = GetTime(), job.sends + 1, GetTime()
    AH.SendSearchQuery(job.itemKey, BUYOUT, false)
    if AH.IsThrottledMessageSystemReady() then
        job.sentAt, job.dropped = nil, true
        if job.sends >= MAX_SENDS then failAll("the search was dropped by the client " .. MAX_SENDS .. " times") end
    end
end

-- Sends the current job's next message when the client is ready. Every
-- browse, every further page and every search takes one throttle slot
-- (spec 4.1).
local function trySend()
    local job = current
    if job.sentAt then return end
    if job.itemKey then return trySearch(job) end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
    job.sentAt = GetTime()
    if job.pages == 0 then
        C_AuctionHouse.SendBrowseQuery(job.query)
    else
        C_AuctionHouse.RequestMoreBrowseResults()
    end
end

local function tick()
    local job = current
    if not job then return stopTicker() end
    local now = GetTime()
    if job.sentAt then
        if now - job.sentAt >= LIMIT then failAll("no answer within 5 seconds of the send") end
    elseif job.itemKey and not job.keyReady and now - job.keySince >= LIMIT then
        failAll("no item key info within 5 seconds")
    elseif now - job.since >= LIMIT then
        failAll(job.dropped and "the search was dropped by the client for 5 seconds" or "not ready to send for 5 seconds")
    else
        trySend()
    end
end

-- The next message of the current browse waits for the client from now.
local function await()
    current.sentAt, current.since, current.keySince = nil, GetTime(), GetTime()
    trySend()
end

-- Every SendBrowseQuery, ours and anyone else's. Ours sends its own query
-- table. Another one sent from our first send until our answer, also between
-- pages, replaces the result we wait for: ours fails, with no retry.
local function onAnySend(query)
    local job = current
    if job and not job.itemKey and query ~= job.query and (job.sentAt or job.pages > 0) then
        failAll("another browse was sent while ours was in flight")
    end
end

startNext = function()
    current = table.remove(waiting, 1)
    if not current then return stopTicker() end
    local problem = missing(current)
    if problem then return failAll(problem) end
    -- Installed once, before our first send. hooksecurefunc on a
    -- C_AuctionHouse function is unverified in game, and so is whether every
    -- other addon calls it through the table (a copy taken earlier is not
    -- hooked); Blizzard's own UI does (Blizzard_AuctionHouseFrame.lua:823).
    if not hooked and hooksecurefunc then
        hooked = true
        hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", onAnySend)
    end
    if not ticker then ticker = C_Timer.NewTicker(POLL, tick) end
    await()
end

-- added is the payload of AUCTION_HOUSE_BROWSE_RESULTS_ADDED; without it the
-- client replaced its whole result list (UPDATED), as Blizzard's own list
-- reads them (Blizzard_AuctionHouseBrowseResultsFrame.lua:101-114).
local function onPage(added)
    local job = current
    if not (job and job.sentAt) or job.itemKey then return end
    if added then
        for _, row in ipairs(added) do job.rows[#job.rows + 1] = row end
    else
        local rows = C_AuctionHouse.GetBrowseResults()
        job.rows = {}
        for _, row in ipairs(type(rows) == "table" and rows or {}) do job.rows[#job.rows + 1] = row end
    end
    job.pages = job.pages + 1
    if job.handlers.page then
        xpcall(function() job.handlers.page(job.rows, job.pages) end, report)
        -- the handler may have cancelled
        if current ~= job then return end
    end
    local full = C_AuctionHouse.HasFullBrowseResults()
    if full or job.pages >= job.maxPages then
        current = nil
        -- cut: stopped at maxPages before the client had the full result
        finish(job, true, job.rows, not full)
        -- a handler may have cancelled or queued; go on only when idle
        if not current then startNext() end
    else
        await()
    end
end

local function sameKey(a, b)
    return type(a) == "table" and a.itemID == b.itemID and (a.itemLevel or 0) == (b.itemLevel or 0)
        and (a.itemSuffix or 0) == (b.itemSuffix or 0) and (a.battlePetSpeciesID or 0) == (b.battlePetSpeciesID or 0)
end

-- ITEM_SEARCH_RESULTS_UPDATED(itemKey): the answer of the search in flight
-- when its item key is ours. The client sends this event twice for most
-- searches (spec 4.5); the first finishes the search and the repeat finds
-- nothing in flight, or a job that is not this search, and is ignored.
local function onSearchResults(itemKey)
    local job = current
    if not (job and job.itemKey and job.sentAt and sameKey(itemKey, job.itemKey)) then return end
    local AH, rows = C_AuctionHouse, {}
    local count = AH.GetNumItemSearchResults(job.itemKey)
    for i = 1, type(count) == "number" and count or 0 do
        local row = AH.GetItemSearchResultInfo(job.itemKey, i)
        if type(row) == "table" then rows[#rows + 1] = row end
    end
    current = nil
    finish(job, true, rows)
    if not current then startNext() end
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_CLOSED",
    "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_KEY_ITEM_INFO_RECEIVED" }) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, payload)
    -- every result event of a key, ours or not, in flight or not, moves the
    -- wait before its next search
    if event == "ITEM_SEARCH_RESULTS_UPDATED" and type(payload) == "table" and GetTime then
        lastSend[keyText(payload)] = GetTime()
    end
    if event == "AUCTION_HOUSE_CLOSED" then
        Queue.CancelAll()
    elseif not current then
        return
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        trySend()
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        onSearchResults(payload)
    elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
        -- the key info of the search that waits for it may be there now
        if current.itemKey and current.itemKey.itemID == payload then trySend() end
    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        if current.sentAt and not current.itemKey then failAll("browse failure (AUCTION_HOUSE_BROWSE_FAILURE)") end
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        if type(payload) == "table" then onPage(payload) end
    else
        onPage(nil)
    end
end)

-- Queues one browse of at most maxPages pages. handlers.done(rows, cut) or
-- handlers.failed(reason) is called once, unless CancelAll comes first; cut
-- is true when the browse stopped at maxPages before the client had the full
-- result. handlers.page(rows, pages), optional, follows every page with the
-- rows so far and the pages read.
function Queue.Browse(query, maxPages, handlers)
    waiting[#waiting + 1] = { query = query, maxPages = maxPages, handlers = handlers, rows = {}, pages = 0 }
    if not current then startNext() end
end

-- Queues one search for an item variant, by the itemKey its browse row
-- gives. handlers.done(rows) gets the client's ItemSearchResultInfo tables
-- (auctionID, buyoutAmount, containsOwnerItem, ...) in the client's order,
-- or handlers.failed(reason) a failure; one of them is called once, unless
-- CancelAll comes first. Only the first page of results is read: the search
-- is sorted by buyout, cheapest first.
function Queue.Search(itemKey, handlers)
    waiting[#waiting + 1] = { itemKey = itemKey, handlers = handlers, pages = 0, sends = 0 }
    if not current then startNext() end
end

-- Whether the client has every call a Search needs.
function Queue.CanSearch()
    return missing({ itemKey = true }) == nil
end

-- True when nothing is in flight or queued.
function Queue.IsIdle()
    return current == nil and not waiting[1]
end

-- Drops everything in flight and queued; no handler is called for them, and
-- their late answers find nothing in flight.
function Queue.CancelAll()
    current, waiting = nil, {}
    stopTicker()
end
