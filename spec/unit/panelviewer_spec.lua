describe("PanelViewer widget", function()
    local BD, Blitbuffer, Device, Geom, ImageViewer, PanelViewer, Screen, Size, UIManager

    setup(function()
        require("commonrequire")
        BD = require("ui/bidi")
        Blitbuffer = require("ffi/blitbuffer")
        Device = require("device")
        Geom = require("ui/geometry")
        ImageViewer = require("ui/widget/imageviewer")
        PanelViewer = require("ui/widget/panelviewer")
        Screen = Device.screen
        Size = require("ui/size")
        UIManager = require("ui/uimanager")
    end)

    -- Device capabilities, restored after each test
    local device_caps = { "hasKeys", "hasDPad", "useDPadAsActionKeys", "hasFewKeys", "isTouchDevice" }
    local saved_caps
    local function setDevice(caps)
        for _, cap in ipairs(device_caps) do
            if caps[cap] ~= nil then
                local value = caps[cap]
                Device[cap] = function() return value end
            end
        end
    end

    before_each(function()
        saved_caps = {}
        for _, cap in ipairs(device_caps) do
            saved_caps[cap] = Device[cap]
        end
        setDevice{ hasKeys = true, hasDPad = false, useDPadAsActionKeys = false, hasFewKeys = false, isTouchDevice = true }
    end)

    after_each(function()
        for _, cap in ipairs(device_caps) do
            Device[cap] = saved_caps[cap]
        end
        G_reader_settings:delSetting("left_right_keys_turn_pages")
        G_reader_settings:delSetting("page_turns_disable_tap")
        G_reader_settings:delSetting("page_turns_disable_swipe")
        G_reader_settings:delSetting("panel_nav_one_hand")
        G_reader_settings:delSetting("page_turns_tap_zones")
        G_reader_settings:delSetting("page_turns_tap_zone_backward_size_ratio")
        G_reader_settings:delSetting("page_turns_tap_zone_forward_size_ratio")
    end)

    -- Both views: the input is the same, but over the page there is no zooming nor panning
    local views = { { overlay = false, name = "fullscreen" }, { overlay = true, name = "over the page" } }

    local calls
    local function newViewer(options)
        options = options or {}
        calls = { next = 0, prev = 0, close = 0, closed = 0 }
        local viewer = PanelViewer:new{
            image = options.image or Blitbuffer.new(200, 100, Blitbuffer.TYPE_BBRGB32),
            rotated = options.rotated,
            overlay = options.overlay,
            panel_rect = options.panel_rect,
            overlay_bottom_height = options.overlay_bottom_height,
            paint_background_callback = options.paint_background_callback,
            next_callback = function() calls.next = calls.next + 1 end,
            prev_callback = function() calls.prev = calls.prev + 1 end,
            close_callback = function() calls.closed = calls.closed + 1 end,
            forward_zone = options.forward_zone,
            backward_zone = options.backward_zone,
            inverse_reading_order = options.inverse_reading_order,
            reserved_bottom_height = options.reserved_bottom_height,
            paint_bottom_callback = options.paint_bottom_callback,
            rotation_callback = options.rotation_callback,
            image_disposable = options.image_disposable,
        }
        -- don't close for real, count it
        viewer.onClose = function()
            calls.close = calls.close + 1
            return true
        end
        return viewer
    end

    local function point(ratio_x, ratio_y)
        return Geom:new{ x = math.floor(Screen:getWidth() * ratio_x), y = math.floor(Screen:getHeight() * ratio_y), w = 0, h = 0 }
    end

    local function tap(viewer, ratio_x, ratio_y)
        return viewer:onTap(nil, { ges = "tap", pos = point(ratio_x, ratio_y) })
    end

    -- What taps across the screen at ratio_y do: "n" next panel, "p" previous panel, "-" nothing
    local function tapAcross(viewer, ratio_y, ratios_x)
        local result = ""
        for _, ratio_x in ipairs(ratios_x) do
            local next_count, prev_count = calls.next, calls.prev
            assert.is_true(tap(viewer, ratio_x, ratio_y))
            result = result .. (calls.next > next_count and "n" or calls.prev > prev_count and "p" or "-")
        end
        assert.are.equal(0, calls.close)
        return result
    end

    local function swipe(viewer, direction, ratio_x)
        return viewer:onSwipe(nil, {
            ges = "swipe",
            direction = direction,
            distance = 100,
            pos = point(ratio_x or 0.5, 0.5),
        })
    end

    -- The key names of a key_events entry: its sequences are single keys, or lists of
    -- alternative keys (e.g. Device.input.group.PgFwd).
    local function getKeyNames(entry)
        local names = {}
        for _, sequence in ipairs(entry) do
            assert.are.equal(1, #sequence, "only single key sequences expected")
            local key = sequence[1]
            if type(key) == "table" then
                for _, name in ipairs(key) do
                    table.insert(names, name)
                end
            else
                table.insert(names, key)
            end
        end
        return names
    end

    -- Map each key name to the key_events entry it is in, failing if it is in two of them
    local function getKeyEntries(viewer)
        local entries = {}
        for event, entry in pairs(viewer.key_events) do
            for _, name in ipairs(getKeyNames(entry)) do
                assert.is_nil(entries[name], name .. " is in both " .. tostring(entries[name]) .. " and " .. event)
                entries[name] = event
            end
        end
        return entries
    end

    -- Count the pans, as ImageViewer:panBy() gets them, and the full refreshes
    local orig_pan_by, orig_set_dirty, pans, full_refreshes
    local function spyPansAndRefreshes()
        pans, full_refreshes = {}, 0
        orig_pan_by, orig_set_dirty = ImageViewer.panBy, UIManager.setDirty
        ImageViewer.panBy = function(_, x, y) table.insert(pans, { x, y }) end
        UIManager.setDirty = function(_, _, refreshtype)
            if refreshtype == "full" then
                full_refreshes = full_refreshes + 1
            end
        end
    end
    local function restorePansAndRefreshes()
        ImageViewer.panBy, UIManager.setDirty = orig_pan_by, orig_set_dirty
    end

    describe("keys", function()
        for _, view in ipairs(views) do
            for _, dpad in ipairs({ true, false }) do
                for _, left_right_turn_pages in ipairs({ true, false }) do
                    local case = (dpad and "with" or "without") .. " D-pad action keys, "
                        .. (left_right_turn_pages and "with" or "without") .. " left_right_keys_turn_pages, " .. view.name
                    it("should bind each key once, " .. case, function()
                        setDevice{ hasDPad = dpad, useDPadAsActionKeys = dpad }
                        G_reader_settings:saveSetting("left_right_keys_turn_pages", left_right_turn_pages)
                        local entries = getKeyEntries(newViewer{ overlay = view.overlay })

                        assert.are.equal("Close", entries.Back)
                        assert.are.equal("NextPanel", entries.RPgFwd)
                        assert.are.equal("NextPanel", entries.LPgFwd)
                        assert.are.equal("PrevPanel", entries.RPgBack)
                        assert.are.equal("PrevPanel", entries.LPgBack)
                        assert.are.equal("Home", entries.Home)
                        assert.are.equal("PanUp", entries.Up)
                        assert.are.equal("PanDown", entries.Down)
                        -- left and right turn pages without D-pad action keys, or with left_right_keys_turn_pages
                        if not dpad or left_right_turn_pages then
                            assert.are.equal("NextPanel", entries.Right)
                            assert.are.equal("PrevPanel", entries.Left)
                        else
                            assert.are.equal("PanRight", entries.Right)
                            assert.are.equal("PanLeft", entries.Left)
                        end
                    end)
                end
            end
        end

        it("should go to panels with left and right where ReaderPaging turns pages with them", function()
            local ReaderPaging = require("apps/reader/modules/readerpaging")
            for _, dpad in ipairs({ true, false }) do
                for _, action_keys in ipairs({ true, false }) do
                    for _, few_keys in ipairs({ true, false }) do
                        for _, left_right_turn_pages in ipairs({ true, false }) do
                            setDevice{ hasDPad = dpad, useDPadAsActionKeys = action_keys, hasFewKeys = few_keys }
                            G_reader_settings:saveSetting("left_right_keys_turn_pages", left_right_turn_pages)
                            local paging = { key_events = {} }
                            ReaderPaging.registerKeyEvents(paging)
                            local turns = {}
                            for _, name in ipairs(getKeyNames(paging.key_events.GotoNextPage)) do
                                turns[name] = "NextPanel"
                            end
                            for _, name in ipairs(getKeyNames(paging.key_events.GotoPrevPage)) do
                                turns[name] = "PrevPanel"
                            end
                            local entries = getKeyEntries(newViewer())
                            for _, key in ipairs({ "Left", "Right" }) do
                                if turns[key] then
                                    assert.are.equal(turns[key], entries[key])
                                else
                                    assert.are_not.equal("NextPanel", entries[key])
                                    assert.are_not.equal("PrevPanel", entries[key])
                                end
                            end
                        end
                    end
                end
            end
        end)

        it("should not zoom with the page turn keys", function()
            local viewer = newViewer()
            assert.is_nil(viewer.key_events.ZoomIn)
            assert.is_nil(viewer.key_events.ZoomOut)
        end)

        it("should swap the left and right keys with a mirrored UI", function()
            setDevice{ hasDPad = true, useDPadAsActionKeys = true }
            G_reader_settings:makeTrue("left_right_keys_turn_pages")
            local orig_mirrored = BD.mirroredUILayout
            BD.mirroredUILayout = function() return true end
            local ok, entries = pcall(function() return getKeyEntries(newViewer()) end)
            BD.mirroredUILayout = orig_mirrored
            assert.is_true(ok, entries)
            assert.are.equal("NextPanel", entries.Left)
            assert.are.equal("PrevPanel", entries.Right)
        end)

        it("should not pan with the cursor keys on devices with few keys, and close with left", function()
            setDevice{ hasDPad = true, hasFewKeys = true }
            local entries = getKeyEntries(newViewer())
            assert.are.equal("Close", entries.Back)
            assert.are.equal("Close", entries.Left)
            assert.are.equal("NextPanel", entries.RPgFwd)
            assert.are.equal("PrevPanel", entries.LPgBack)
            assert.is_nil(entries.Right)
            assert.is_nil(entries.Up)
            assert.is_nil(entries.Down)
        end)

        it("should bind no key on devices without keys", function()
            setDevice{ hasKeys = false }
            local viewer = newViewer()
            assert.are.same({}, viewer.key_events)
        end)

        for _, view in ipairs(views) do
            it("should call the callbacks on the panel events, " .. view.name, function()
                local viewer = newViewer{ overlay = view.overlay }
                assert.is_true(viewer:onNextPanel())
                assert.is_true(viewer:onPrevPanel())
                assert.is_true(viewer:onNextPanel())
                assert.are.same({ next = 2, prev = 1, close = 0, closed = 0 }, calls)
            end)
        end

        it("should pan with the cursor keys fullscreen, not over the page", function()
            spyPansAndRefreshes()
            local ok, err = pcall(function()
                assert.is_true(newViewer():onCursorPan("down"))
                assert.are.equal(1, #pans)
                assert.is_true(newViewer{ overlay = true }:onCursorPan("down"))
                assert.are.equal(1, #pans)
            end)
            restorePansAndRefreshes()
            assert.is_true(ok, err)
        end)
    end)

    for _, view in ipairs(views) do
        describe("taps, " .. view.name, function()
            local left_right_zones = {
                overlay = view.overlay,
                forward_zone = { ratio_x = 0.75, ratio_y = 0, ratio_w = 0.25, ratio_h = 1 },
                backward_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 0.25, ratio_h = 1 },
            }

            it("should go to the next and previous panel in the forward and backward zones", function()
                local viewer = newViewer(left_right_zones)
                assert.is_true(tap(viewer, 0.9, 0.5))
                assert.is_true(tap(viewer, 0.9, 0.05))
                assert.is_true(tap(viewer, 0.1, 0.95))
                assert.are.same({ next = 2, prev = 1, close = 0, closed = 0 }, calls)
            end)

            it("should do nothing elsewhere, not even show the buttons", function()
                local viewer = newViewer(left_right_zones)
                assert.are.equal("---", tapAcross(viewer, 0.5, { 0.3, 0.5, 0.7 }))
                assert.are.equal("-", tapAcross(viewer, 0.05, { 0.5 }))
                assert.is_false(viewer.buttons_visible)
            end)

            it("should go to the next panel in the middle of the screen, in the forward zone", function()
                -- the default tap zones: forward is the right 3/4 of the screen
                local viewer = newViewer{
                    overlay = view.overlay,
                    forward_zone = { ratio_x = 1/4, ratio_y = 0, ratio_w = 3/4, ratio_h = 1 },
                    backward_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1/4, ratio_h = 1 },
                }
                assert.are.equal("pnnn", tapAcross(viewer, 0.5, { 0.1, 0.3, 0.5, 0.9 }))
                assert.are.equal("n", tapAcross(viewer, 0.2, { 0.5 }))
            end)

            it("should do nothing when page turns with taps are disabled", function()
                G_reader_settings:makeTrue("page_turns_disable_tap")
                local viewer = newViewer(left_right_zones)
                assert.are.equal("---", tapAcross(viewer, 0.5, { 0.1, 0.5, 0.9 }))
            end)

            it("should do nothing without tap zones", function()
                local viewer = newViewer{ overlay = view.overlay }
                assert.are.equal("---", tapAcross(viewer, 0.5, { 0.1, 0.5, 0.9 }))
            end)
        end)
    end

    describe("holds", function()
        before_each(spyPansAndRefreshes)
        after_each(restorePansAndRefreshes)

        local function newHoldViewer(scale_factor, overlay)
            local viewer = newViewer{ overlay = overlay }
            viewer.scale_factor = scale_factor
            return viewer
        end

        -- A gesture dx, dy screen pixels away from the middle of the screen, as the gesture detector sends it
        local function gesture(viewer, ges, dx, dy)
            local pos = point(0.5, 0.5)
            return viewer:onGesture{ ges = ges, pos = Geom:new{ x = pos.x + dx, y = pos.y + dy, w = 0, h = 0 } }
        end

        -- Hold in the middle of the screen and release dx, dy screen pixels away, after a drag: the gesture
        -- detector sends hold_pan once the finger has moved past its pan threshold, far more than a few pixels
        local function hold(viewer, dx, dy, drag)
            assert.is_true(gesture(viewer, "hold", 0, 0))
            if drag then
                assert.is_true(gesture(viewer, "hold_pan", dx, dy))
            end
            return gesture(viewer, "hold_release", dx, dy)
        end

        for _, view in ipairs(views) do
            it("should close on a hold released without a drag, " .. view.name, function()
                local viewer = newHoldViewer(0, view.overlay)
                assert.is_true(hold(viewer, 0, 0))
                -- a slight move, without a drag
                local slight = viewer.pan_threshold + 10
                assert.is_true(hold(viewer, slight, -slight))
                assert.are.same({ next = 0, prev = 0, close = 2, closed = 0 }, calls)
                assert.are.equal(0, full_refreshes)
                assert.are.same({}, pans)
            end)

            it("should not close on the release of the long-press that opened it, " .. view.name, function()
                local viewer = newHoldViewer(0, view.overlay)
                -- the long-press on the page goes on in the viewer: released, or dragged and released
                assert.is_true(gesture(viewer, "hold_release", 0, 0))
                assert.is_true(gesture(viewer, "hold_pan", 100, 0))
                assert.is_true(gesture(viewer, "hold_release", 100, 0))
                assert.are.same({ next = 0, prev = 0, close = 0, closed = 0 }, calls)
                assert.are.equal(0, full_refreshes)
                assert.are.same({}, pans)
            end)

            it("should close on a hold without a drag after a hold with a drag, " .. view.name, function()
                local viewer = newHoldViewer(0, view.overlay)
                assert.is_true(hold(viewer, 100, -50, true))
                assert.are.equal(0, calls.close)
                assert.is_true(hold(viewer, 0, 0))
                assert.are.equal(1, calls.close)
            end)
        end

        it("should close on a hold released without a drag when zoomed too, without a full refresh", function()
            local viewer = newHoldViewer(2)
            assert.is_true(hold(viewer, 0, 0))
            assert.are.same({ next = 0, prev = 0, close = 1, closed = 0 }, calls)
            assert.are.equal(0, full_refreshes)
            assert.are.same({}, pans)
        end)

        for _, scale_factor in ipairs({ 0, 2 }) do
            it("should pan on a hold followed by a drag, " .. (scale_factor == 0 and "fit to the screen" or "zoomed"), function()
                local viewer = newHoldViewer(scale_factor)
                assert.is_true(hold(viewer, 100, -50, true))
                assert.are.same({ { -100, 50 } }, pans)
                assert.are.same({ next = 0, prev = 0, close = 0, closed = 0 }, calls)
                assert.are.equal(0, full_refreshes)
            end)
        end

        it("should neither pan nor refresh the screen after a drag back to where it started", function()
            local viewer = newHoldViewer(2)
            assert.is_true(gesture(viewer, "hold", 0, 0))
            assert.is_true(gesture(viewer, "hold_pan", 200, 0))
            assert.is_true(gesture(viewer, "hold_release", 1, 0))
            assert.are.same({}, pans)
            assert.are.equal(0, full_refreshes)
            assert.are.same({ next = 0, prev = 0, close = 0, closed = 0 }, calls)
        end)

        it("should do nothing on a hold followed by a drag over the page", function()
            local viewer = newHoldViewer(0, true)
            assert.is_true(hold(viewer, 100, -50, true))
            assert.are.same({}, pans)
            assert.are.same({ next = 0, prev = 0, close = 0, closed = 0 }, calls)
            assert.are.equal(0, full_refreshes)
            assert.are.equal(0.5, viewer._center_x_ratio)
        end)
    end)

    describe("swipes", function()
        for _, view in ipairs(views) do
            it("should go to the next panel west and the previous one east, " .. view.name, function()
                local viewer = newViewer{ overlay = view.overlay }
                assert.is_true(swipe(viewer, "west"))
                assert.is_true(swipe(viewer, "west"))
                assert.is_true(swipe(viewer, "east"))
                assert.are.same({ next = 2, prev = 1, close = 0, closed = 0 }, calls)
            end)

            it("should swap them with inverse_reading_order, " .. view.name, function()
                local viewer = newViewer{ overlay = view.overlay, inverse_reading_order = true }
                assert.is_true(swipe(viewer, "west"))
                assert.is_true(swipe(viewer, "east"))
                assert.is_true(swipe(viewer, "east"))
                assert.are.same({ next = 2, prev = 1, close = 0, closed = 0 }, calls)
            end)

            it("should close north and south, " .. view.name, function()
                local viewer = newViewer{ overlay = view.overlay }
                assert.is_true(swipe(viewer, "north"))
                assert.is_true(swipe(viewer, "south"))
                assert.are.same({ next = 0, prev = 0, close = 2, closed = 0 }, calls)
            end)

            it("should mirror them with a mirrored UI, " .. view.name, function()
                local viewer = newViewer{ overlay = view.overlay }
                local orig_mirrored = BD._mirrored_ui_layout
                BD._mirrored_ui_layout = true
                local ok, err = pcall(function()
                    assert.is_true(swipe(viewer, "east"))
                    assert.is_true(swipe(viewer, "east"))
                    assert.is_true(swipe(viewer, "west"))
                end)
                BD._mirrored_ui_layout = orig_mirrored
                assert.is_true(ok, err)
                assert.are.same({ next = 2, prev = 1, close = 0, closed = 0 }, calls)
            end)

            it("should not go to panels when page turns with swipes are disabled, " .. view.name, function()
                G_reader_settings:makeTrue("page_turns_disable_swipe")
                local viewer = newViewer{ overlay = view.overlay }
                assert.is_true(swipe(viewer, "west"))
                assert.is_true(swipe(viewer, "east"))
                assert.are.same({ next = 0, prev = 0, close = 0, closed = 0 }, calls)
            end)
        end

        it("should zoom north and south on the screen sides, fullscreen", function()
            local viewer = newViewer()
            viewer._image_wg:getSize() -- render it, as painting would
            local zoomed_in, zoomed_out = 0, 0
            viewer.onZoomIn = function() zoomed_in = zoomed_in + 1 return true end
            viewer.onZoomOut = function() zoomed_out = zoomed_out + 1 return true end
            assert.is_true(swipe(viewer, "north", 0.05))
            assert.is_true(swipe(viewer, "south", 0.95))
            assert.are.equal(1, zoomed_in)
            assert.are.equal(1, zoomed_out)
            assert.are.same({ next = 0, prev = 0, close = 0, closed = 0 }, calls)
        end)

        it("should close north and south on the screen sides too, over the page", function()
            local viewer = newViewer{ overlay = true }
            assert.is_true(swipe(viewer, "north", 0.05))
            assert.is_true(swipe(viewer, "south", 0.95))
            assert.are.same({ next = 0, prev = 0, close = 2, closed = 0 }, calls)
            assert.are.equal(0, viewer.scale_factor)
        end)

        it("should pan when zoomed", function()
            local viewer = newViewer()
            local swipe_pans = {}
            viewer.panBy = function(_, x, y) table.insert(swipe_pans, { x, y }) end
            viewer.scale_factor = 2
            assert.is_true(swipe(viewer, "west"))
            assert.is_true(swipe(viewer, "east"))
            assert.is_true(swipe(viewer, "south"))
            assert.are.same({ { 100, 0 }, { -100, 0 }, { 0, -100 } }, swipe_pans)
            assert.are.same({ next = 0, prev = 0, close = 0, closed = 0 }, calls)
        end)

        it("should do nothing on diagonal swipes over the page", function()
            spyPansAndRefreshes()
            local ok, err = pcall(function()
                local viewer = newViewer{ overlay = true }
                assert.is_true(swipe(viewer, "northeast"))
                assert.is_true(swipe(viewer, "southwest"))
                assert.are.same({}, pans)
                assert.are.same({ next = 0, prev = 0, close = 0, closed = 0 }, calls)
            end)
            restorePansAndRefreshes()
            assert.is_true(ok, err)
        end)
    end)

    describe("zoom and pan", function()
        local function spread(viewer)
            return viewer:onSpread(nil, { ges = "spread", direction = "horizontal", distance = 200, pos = point(0.5, 0.5) })
        end

        local function pinch(viewer)
            return viewer:onPinch(nil, { ges = "pinch", direction = "horizontal", distance = 200, pos = point(0.5, 0.5) })
        end

        it("should zoom with spread and pinch fullscreen", function()
            local viewer = newViewer()
            viewer._image_wg:getSize() -- render it, as painting would
            assert.is_true(spread(viewer))
            local zoomed_in = viewer.scale_factor
            assert.is_true(zoomed_in > 0)
            viewer._image_wg:getSize() -- the new one
            assert.is_true(pinch(viewer))
            assert.is_true(viewer.scale_factor < zoomed_in)
        end)

        it("should ignore spread, pinch and pan over the page", function()
            spyPansAndRefreshes()
            local ok, err = pcall(function()
                local viewer = newViewer{ overlay = true }
                local image_wg = viewer._image_wg
                assert.is_true(spread(viewer))
                assert.is_true(pinch(viewer))
                assert.is_true(viewer:onZoomIn(1))
                assert.is_true(viewer:onZoomOut(0.5))
                assert.is_true(viewer:onPan(nil, { ges = "pan", relative = { x = 100, y = 50 }, pos = point(0.5, 0.5) }))
                assert.is_true(viewer:onPanRelease(nil, { ges = "pan_release", pos = point(0.6, 0.6) }))
                assert.are.equal(0, viewer.scale_factor)
                assert.are.equal(image_wg, viewer._image_wg)
                assert.are.same({}, pans)
                assert.are.same({ next = 0, prev = 0, close = 0, closed = 0 }, calls)
            end)
            restorePansAndRefreshes()
            assert.is_true(ok, err)
        end)
    end)

    describe("one-handed navigation", function()
        local ReaderPanelNav
        setup(function()
            ReaderPanelNav = require("apps/reader/modules/readerpanelnav")
        end)

        -- A viewer with the tap zones ReaderPanelNav gives it for that hand, with inverted page turns
        local function newOneHandViewer(hand, overlay)
            G_reader_settings:saveSetting("panel_nav_one_hand", hand)
            local panelnav = ReaderPanelNav:new{
                ui = {},
                view = {
                    registerViewModule = function() end,
                    inverse_reading_order = true,
                },
            }
            local forward_zone, backward_zone = panelnav:getTapZones()
            return newViewer{
                overlay = overlay,
                forward_zone = forward_zone,
                backward_zone = backward_zone,
                inverse_reading_order = true,
            }
        end

        for _, view in ipairs(views) do
            it("should go back on a strip on the right with the right hand, and forward elsewhere, " .. view.name, function()
                local viewer = newOneHandViewer("right", view.overlay)
                -- the strip is as wide as the default backward tap zone, 1/4, and not mirrored
                assert.are.equal("nnnpp", tapAcross(viewer, 0.5, { 0.05, 0.5, 0.74, 0.76, 0.95 }))
                assert.are.equal("np", tapAcross(viewer, 0.02, { 0.5, 0.9 }))
                assert.are.equal("np", tapAcross(viewer, 0.98, { 0.5, 0.9 }))
            end)

            it("should go back on a strip on the left with the left hand, and forward elsewhere, " .. view.name, function()
                local viewer = newOneHandViewer("left", view.overlay)
                assert.are.equal("ppnnn", tapAcross(viewer, 0.5, { 0.05, 0.24, 0.26, 0.5, 0.95 }))
                assert.are.equal("pn", tapAcross(viewer, 0.02, { 0.1, 0.5 }))
                assert.are.equal("pn", tapAcross(viewer, 0.98, { 0.1, 0.5 }))
            end)

            it("should make the strip as wide as the backward page turn tap zone, " .. view.name, function()
                G_reader_settings:saveSetting("page_turns_tap_zones", "left_right")
                G_reader_settings:saveSetting("page_turns_tap_zone_backward_size_ratio", 0.1)
                G_reader_settings:saveSetting("page_turns_tap_zone_forward_size_ratio", 0.5)
                assert.are.equal("nnpp", tapAcross(newOneHandViewer("right", view.overlay), 0.5, { 0.5, 0.89, 0.91, 0.99 }))
                assert.are.equal("ppnn", tapAcross(newOneHandViewer("left", view.overlay), 0.5, { 0.01, 0.09, 0.11, 0.5 }))
            end)

            it("should keep the strip from 10 to 50 % of the screen width, " .. view.name, function()
                G_reader_settings:saveSetting("page_turns_tap_zones", "left_right")
                G_reader_settings:saveSetting("page_turns_tap_zone_backward_size_ratio", 0.02)
                assert.are.equal("nnpp", tapAcross(newOneHandViewer("right", view.overlay), 0.5, { 0.5, 0.89, 0.91, 0.99 }))
                G_reader_settings:saveSetting("page_turns_tap_zone_backward_size_ratio", 0.9)
                assert.are.equal("nnpp", tapAcross(newOneHandViewer("right", view.overlay), 0.5, { 0.1, 0.49, 0.51, 0.9 }))
                assert.are.equal("ppnn", tapAcross(newOneHandViewer("left", view.overlay), 0.5, { 0.1, 0.49, 0.51, 0.9 }))
            end)

            it("should still swap the swipes with inverted page turns, " .. view.name, function()
                local viewer = newOneHandViewer("right", view.overlay)
                assert.is_true(swipe(viewer, "east"))
                assert.are.same({ next = 1, prev = 0, close = 0, closed = 0 }, calls)
                assert.is_true(swipe(viewer, "west"))
                assert.are.same({ next = 1, prev = 1, close = 0, closed = 0 }, calls)
            end)
        end
    end)

    describe("rotation", function()
        after_each(function()
            G_reader_settings:delSetting("imageviewer_rotate_auto_for_best_fit")
        end)

        -- An image the other way round from the screen, that ImageViewer would rotate
        local function crosswiseImage()
            local w, h = 200, 100
            if Screen:getWidth() > Screen:getHeight() then
                w, h = h, w
            end
            return Blitbuffer.new(w, h, Blitbuffer.TYPE_BBRGB32)
        end

        it("should keep the rotation it is given, rather than ImageViewer's auto-rotation", function()
            G_reader_settings:makeTrue("imageviewer_rotate_auto_for_best_fit")
            local image = crosswiseImage()
            local viewer = newViewer{ image = image, rotated = false }
            assert.is_false(viewer.rotated)
            assert.are.equal(0, viewer._image_wg.rotation_angle)
            viewer = newViewer{ image = Blitbuffer.new(image:getHeight(), image:getWidth(), Blitbuffer.TYPE_BBRGB32), rotated = true }
            assert.is_true(viewer.rotated)
        end)

        it("should never rotate the image over the page", function()
            G_reader_settings:makeTrue("imageviewer_rotate_auto_for_best_fit")
            local viewer = newViewer{ overlay = true, image = crosswiseImage(), rotated = true }
            assert.is_false(viewer.rotated)
            assert.are.equal(0, viewer._image_wg.rotation_angle)
            viewer:setImage(crosswiseImage(), true)
            assert.is_false(viewer.rotated)
            assert.are.equal(0, viewer._image_wg.rotation_angle)
        end)
    end)

    describe("setImage", function()
        it("should replace the image, fit to the screen", function()
            local viewer = newViewer()
            viewer.scale_factor = 2
            viewer._center_x_ratio = 0.2
            local image = Blitbuffer.new(50, 300, Blitbuffer.TYPE_BBRGB32)
            viewer:setImage(image, true)
            assert.are.equal(image, viewer.image)
            assert.are.equal(image, viewer._image_wg.image)
            assert.is_true(viewer.rotated)
            assert.are.equal(0, viewer.scale_factor)
            assert.are.equal(0.5, viewer._center_x_ratio)
            viewer:setImage(Blitbuffer.new(300, 50, Blitbuffer.TYPE_BBRGB32))
            assert.is_false(viewer.rotated)
        end)

        it("should replace the image and where it is on the page, and refresh the whole screen, over the page", function()
            local viewer = newViewer{ overlay = true, panel_rect = { x = 10, y = 20, w = 30, h = 40 } }
            local refreshes = {}
            local saved_set_dirty = UIManager.setDirty
            UIManager.setDirty = function(_, widget, refreshtype, region)
                table.insert(refreshes, { widget, refreshtype, region })
            end
            local image = Blitbuffer.new(50, 300, Blitbuffer.TYPE_BBRGB32)
            local rect = { x = 50, y = 60, w = 70, h = 80 }
            local ok, err = pcall(viewer.setImage, viewer, image, false, rect)
            UIManager.setDirty = saved_set_dirty
            assert.is_true(ok, err)
            assert.are.equal(image, viewer.image)
            assert.are.equal(image, viewer._image_wg.image)
            assert.are.equal(rect, viewer.panel_rect)
            -- the page under the panel may have changed too
            assert.are.same({ { viewer, Device:hasKaleidoWfm() and "partial" or "ui" } }, refreshes)
            viewer:setImage(image, false)
            assert.is_nil(viewer.panel_rect)
        end)
    end)

    describe("image ownership", function()
        for _, view in ipairs(views) do
            it("should free the images it is given when they are replaced and when it closes, " .. view.name, function()
                local first = Blitbuffer.new(200, 100, Blitbuffer.TYPE_BBRGB32)
                local second = Blitbuffer.new(100, 200, Blitbuffer.TYPE_BBRGB32)
                local viewer = newViewer{ overlay = view.overlay, image = first }
                viewer:setImage(second, false)
                assert.are.equal(0, first:getAllocated())
                assert.are.equal(1, second:getAllocated())
                -- the same image again is kept
                viewer:setImage(second, false)
                assert.are.equal(1, second:getAllocated())
                viewer:onCloseWidget()
                assert.are.equal(0, second:getAllocated())
            end)
        end

        it("should not free them with image_disposable false", function()
            local first = Blitbuffer.new(200, 100, Blitbuffer.TYPE_BBRGB32)
            local second = Blitbuffer.new(100, 200, Blitbuffer.TYPE_BBRGB32)
            local viewer = newViewer{ image = first, image_disposable = false }
            viewer:setImage(second, false)
            viewer:onCloseWidget()
            assert.are.equal(1, first:getAllocated())
            assert.are.equal(1, second:getAllocated())
        end)
    end)

    describe("reserved bottom height", function()
        it("should lay out the image above it, and paint it with the callback", function()
            local painted
            local reserved = Screen:scaleBySize(20)
            local viewer = newViewer{
                reserved_bottom_height = reserved,
                paint_bottom_callback = function(bb, x, y) painted = { bb, x, y } end,
            }
            assert.are.equal(Screen:getHeight() - reserved, viewer.region.h)
            assert.are.equal(Screen:getHeight() - reserved, viewer.height)
            assert.is_true(viewer.covers_fullscreen)
            local bb = Blitbuffer.new(Screen:getWidth(), Screen:getHeight(), Blitbuffer.TYPE_BBRGB32)
            bb:fill(Blitbuffer.COLOR_BLACK)
            viewer:paintTo(bb, 0, 0)
            assert.are.same({ bb, 0, 0 }, painted)
            -- the reserved area is cleared
            local pixel = bb:getPixel(10, Screen:getHeight() - math.ceil(reserved / 2))
            assert.are.equal(Blitbuffer.COLOR_WHITE:getColorRGB32().r, pixel:getColorRGB32().r)
        end)

        it("should not be used over the page", function()
            local viewer = newViewer{ overlay = true, reserved_bottom_height = Screen:scaleBySize(20) }
            assert.are.equal(0, viewer.reserved_bottom_height)
        end)
    end)

    describe("over the page", function()
        local screen_w, screen_h, bottom_h, margin, frame, image_gray

        setup(function()
            screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
            bottom_h = Screen:scaleBySize(20)
            -- the margin around the card, and its border and padding
            margin = Size.margin.default * 2
            frame = Size.border.thick + Size.padding.small
            image_gray = Blitbuffer.Color8(0x40)
        end)

        after_each(function()
            G_reader_settings:delSetting("color_rendering")
        end)

        local function newImage(w, h)
            local image = Blitbuffer.new(w, h, Blitbuffer.TYPE_BBRGB32)
            image:fill(image_gray)
            return image
        end

        -- Paint an overlay viewer on a black page, and return the screen and the painting order
        local function paintOverlay(options)
            local painted = {}
            options.overlay = true
            options.overlay_bottom_height = bottom_h
            options.paint_background_callback = function(bb, x, y)
                table.insert(painted, { x, y })
                bb:fill(Blitbuffer.COLOR_BLACK)
            end
            local viewer = newViewer(options)
            local bb = Blitbuffer.new(screen_w, screen_h, Blitbuffer.TYPE_BBRGB32)
            bb:fill(Blitbuffer.COLOR_WHITE)
            viewer:paintTo(bb, 0, 0)
            return bb, painted, viewer
        end

        local function gray(bb, x, y)
            return bb:getPixel(x, y):getColorRGB32().r
        end

        -- The card: border, padding, and image, centred above the bottom height
        local function cardOf(image)
            local w, h = image:getWidth() + 2 * frame, image:getHeight() + 2 * frame
            return {
                x = math.floor((screen_w - w) / 2),
                y = math.floor((screen_h - bottom_h - h) / 2),
                w = w, h = h,
            }
        end

        it("should cover the full screen, with no reserved bottom height", function()
            local viewer = newViewer{ overlay = true, overlay_bottom_height = bottom_h }
            assert.is_true(viewer.covers_fullscreen)
            assert.are.equal(0, viewer.reserved_bottom_height)
        end)

        it("should paint the page, lighten it above the bottom height, then show the panel centred in a card", function()
            local image = newImage(100, 60)
            local bb, painted = paintOverlay{ image = image }
            assert.are.same({ { 0, 0 } }, painted)
            -- the page, lightened: black turns mid-gray, the bottom height (e.g., the footer) as it is
            local lightened = gray(bb, 2, 2)
            assert.is_true(lightened > 0x60 and lightened < 0xA0, lightened)
            assert.are.equal(lightened, gray(bb, screen_w - 3, screen_h - bottom_h - 1))
            assert.are.equal(0, gray(bb, 2, screen_h - bottom_h))
            assert.are.equal(0, gray(bb, screen_w - 3, screen_h - 1))
            -- the card: black border, white padding, the image as it is
            local card = cardOf(image)
            local mid_y = card.y + math.floor(card.h / 2)
            assert.are.equal(lightened, gray(bb, card.x - 1, mid_y))
            assert.are.equal(0, gray(bb, card.x, mid_y))
            assert.are.equal(0, gray(bb, card.x + Size.border.thick - 1, mid_y))
            assert.are.equal(0xFF, gray(bb, card.x + Size.border.thick, mid_y))
            assert.are.equal(0x40, gray(bb, card.x + frame, mid_y))
            assert.are.equal(0x40, gray(bb, card.x + card.w - frame - 1, mid_y))
            assert.are.equal(0, gray(bb, card.x + card.w - 1, mid_y))
            assert.are.equal(lightened, gray(bb, card.x + card.w, mid_y))
            local mid_x = card.x + math.floor(card.w / 2)
            assert.are.equal(0, gray(bb, mid_x, card.y))
            assert.are.equal(0x40, gray(bb, mid_x, card.y + frame))
            assert.are.equal(0x40, gray(bb, mid_x, card.y + card.h - frame - 1))
            assert.are.equal(0, gray(bb, mid_x, card.y + card.h - 1))
            -- centred
            assert.is_true(math.abs(card.x - (screen_w - card.x - card.w)) <= 1)
            assert.is_true(math.abs(card.y - (screen_h - bottom_h - card.y - card.h)) <= 1)
        end)

        it("should paint a white page without a background callback", function()
            local viewer = newViewer{ overlay = true }
            local bb = Blitbuffer.new(screen_w, screen_h, Blitbuffer.TYPE_BBRGB32)
            bb:fill(Blitbuffer.COLOR_BLACK)
            viewer:paintTo(bb, 0, 0)
            assert.are.equal(0xFF, gray(bb, 2, 2))
            assert.are.equal(0xFF, gray(bb, 2, screen_h - 1))
        end)

        it("should frame the panel on the page, black in grayscale and red in color, above the bottom height", function()
            local line_w = Size.line.thick
            -- a panel at the top left, going down below the bottom height
            local rect = Geom:new{ x = 4, y = 6, w = math.floor(screen_w / 5), h = screen_h }
            G_reader_settings:makeFalse("color_rendering")
            local bb = paintOverlay{ image = newImage(20, 20), panel_rect = rect }
            local lightened = gray(bb, 2, 2)
            local mid_y = math.floor(screen_h / 4)
            assert.are.equal(lightened, gray(bb, rect.x - 1, mid_y))
            assert.are.equal(0, gray(bb, rect.x, mid_y))
            assert.are.equal(0, gray(bb, rect.x + line_w - 1, mid_y))
            assert.are.equal(lightened, gray(bb, rect.x + line_w, mid_y))
            assert.are.equal(0, gray(bb, rect.x + rect.w - 1, mid_y))
            assert.are.equal(0, gray(bb, rect.x + 10, rect.y))
            assert.are.equal(lightened, gray(bb, rect.x + 10, rect.y + line_w))
            -- red in color, and only above the bottom height, where the page stays as it is
            G_reader_settings:makeTrue("color_rendering")
            bb = paintOverlay{ image = newImage(20, 20), panel_rect = rect }
            local function rgb(x, y)
                local pixel = bb:getPixel(x, y):getColorRGB32()
                return { pixel.r, pixel.g, pixel.b }
            end
            assert.are.same({ 0xFF, 0, 0 }, rgb(rect.x, mid_y))
            assert.are.same({ 0xFF, 0, 0 }, rgb(rect.x, screen_h - bottom_h - 1))
            assert.are.same({ 0, 0, 0 }, rgb(rect.x, screen_h - bottom_h))
            assert.are.same({ 0, 0, 0 }, rgb(rect.x + rect.w - 1, screen_h - 1))
        end)

        it("should not frame anything without a panel rectangle", function()
            G_reader_settings:makeFalse("color_rendering")
            local bb = paintOverlay{ image = newImage(20, 20) }
            local lightened = gray(bb, 2, 2)
            for x = 0, screen_w - 1, 7 do
                local y = math.floor(screen_h / 10)
                assert.are.equal(lightened, gray(bb, x, y), x)
            end
        end)

        it("should fit the largest panel within the margins, above the bottom height", function()
            local max_size = PanelViewer.getOverlayMaxSize(bottom_h)
            assert.are.same({
                w = screen_w - 2 * (margin + frame),
                h = screen_h - bottom_h - 2 * (margin + frame),
            }, max_size)
            assert.are.same({
                w = screen_w - 2 * (margin + frame),
                h = screen_h - 2 * (margin + frame),
            }, PanelViewer.getOverlayMaxSize(0))
            local image = newImage(max_size.w, max_size.h)
            local bb = paintOverlay{ image = image }
            local card = cardOf(image)
            assert.are.same({ x = margin, y = margin }, { x = card.x, y = card.y })
            assert.are.equal(screen_w - margin, card.x + card.w)
            assert.are.equal(screen_h - bottom_h - margin, card.y + card.h)
            local lightened = gray(bb, 2, 2)
            assert.are.equal(lightened, gray(bb, margin - 1, margin + 10))
            assert.are.equal(0, gray(bb, margin, margin + 10))
            assert.are.equal(0, gray(bb, screen_w - margin - 1, margin + 10))
            assert.are.equal(lightened, gray(bb, screen_w - margin, margin + 10))
            assert.are.equal(0, gray(bb, margin + 10, screen_h - bottom_h - margin - 1))
            assert.are.equal(lightened, gray(bb, margin + 10, screen_h - bottom_h - margin))
        end)

        it("should show the image as it is, without scaling it", function()
            local image = newImage(30, 500)
            local viewer = newViewer{ overlay = true, image = image }
            local size = viewer._image_wg:getSize()
            assert.are.same({ 30, 500 }, { size.w, size.h })
            assert.are.equal(image, viewer._image_wg._bb)
        end)

        it("should refresh the whole screen when shown and closed", function()
            local viewer = newViewer{ overlay = true }
            local refreshes = {}
            local saved_set_dirty = UIManager.setDirty
            UIManager.setDirty = function(_, widget, refresh)
                if type(refresh) == "function" then
                    table.insert(refreshes, { widget, refresh() })
                end
            end
            local ok, err = pcall(function()
                viewer:onShow()
                viewer:onCloseWidget()
            end)
            UIManager.setDirty = saved_set_dirty
            assert.is_true(ok, err)
            assert.are.same({ { viewer, "full", nil, true }, { nil, "flashui", nil } }, refreshes)
            assert.are.equal(1, calls.closed)
        end)
    end)

    describe("closing", function()
        for _, view in ipairs(views) do
            it("should call close_callback, " .. view.name, function()
                local viewer = newViewer{ overlay = view.overlay }
                viewer:onCloseWidget()
                assert.are.equal(1, calls.closed)
            end)

            it("should close and call rotation_callback on rotation, " .. view.name, function()
                local rotated_to
                local viewer = newViewer{ overlay = view.overlay, rotation_callback = function(mode) rotated_to = mode end }
                local mode = Screen:getRotationMode()
                assert.is_true(viewer:onSetRotationMode(mode))
                assert.is_nil(rotated_to)
                assert.are.equal(0, calls.closed)
                local new_mode = (mode + 1) % 4
                assert.is_true(viewer:onSetRotationMode(new_mode))
                assert.are.equal(new_mode, rotated_to)
                assert.are.equal(1, calls.closed)
            end)

            it("should close and call rotation_callback without a mode when the screen is resized, " .. view.name, function()
                local rotations = {}
                local viewer = newViewer{
                    overlay = view.overlay,
                    reserved_bottom_height = not view.overlay and Screen:scaleBySize(20) or nil,
                    rotation_callback = function(mode) table.insert(rotations, tostring(mode)) end,
                }
                viewer:onSetDimensions({ w = Screen:getWidth(), h = Screen:getHeight() })
                assert.are.same({}, rotations)
                assert.are.equal(0, calls.closed)
                viewer:onSetDimensions({ w = Screen:getHeight(), h = Screen:getWidth() })
                assert.are.same({ "nil" }, rotations)
                assert.are.equal(1, calls.closed)
            end)
        end
    end)
end)
