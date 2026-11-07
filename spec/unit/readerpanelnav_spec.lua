describe("ReaderPanelNav module", function()
    local ReaderPanelNav

    setup(function()
        require("commonrequire")
        ReaderPanelNav = require("apps/reader/modules/readerpanelnav")
    end)

    describe("sortPanelsByReadingDirection", function()
        local panelnav

        before_each(function()
            -- Create a minimal instance for testing sorting logic
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        describe("with LRTB direction (Left-Right, Top-Bottom)", function()
            before_each(function()
                panelnav.panel_direction = "LRTB"
            end)

            it("should sort panels top to bottom, left to right", function()
                local panels = {
                    { x = 300, y = 100, w = 200, h = 150 },  -- top right
                    { x = 50, y = 100, w = 200, h = 150 },   -- top left
                    { x = 50, y = 300, w = 200, h = 150 },   -- bottom left
                    { x = 300, y = 300, w = 200, h = 150 },  -- bottom right
                }
                local sorted = panelnav:sortPanelsByReadingDirection(panels)
                -- Expected order: top-left, top-right, bottom-left, bottom-right
                assert.are.equal(50, sorted[1].x)
                assert.are.equal(100, sorted[1].y)
                assert.are.equal(300, sorted[2].x)
                assert.are.equal(100, sorted[2].y)
                assert.are.equal(50, sorted[3].x)
                assert.are.equal(300, sorted[3].y)
                assert.are.equal(300, sorted[4].x)
                assert.are.equal(300, sorted[4].y)
            end)

            it("should handle panels with slight Y overlap as different rows", function()
                -- This is the specific case from user: panels with 8px Y overlap
                -- A: (45,65)-(534,350) and B: (45,342)-(506,499)
                -- Overlap: 342-350 = 8 pixels, which is < 30% threshold
                local panels = {
                    { x = 45, y = 342, w = 461, h = 157 },  -- B (lower)
                    { x = 45, y = 65, w = 489, h = 285 },   -- A (upper)
                }
                local sorted = panelnav:sortPanelsByReadingDirection(panels)
                -- A should come before B (A has smaller Y center)
                assert.are.equal(65, sorted[1].y)   -- A first
                assert.are.equal(342, sorted[2].y)  -- B second
            end)

            it("should treat panels with significant Y overlap as same row", function()
                -- Two panels with same Y range should be in the same row
                local panels = {
                    { x = 300, y = 100, w = 200, h = 100 },  -- right
                    { x = 50, y = 100, w = 200, h = 100 },   -- left, same Y range
                }
                local sorted = panelnav:sortPanelsByReadingDirection(panels)
                -- Same row, so sort by X: left first, then right
                assert.are.equal(50, sorted[1].x)
                assert.are.equal(300, sorted[2].x)
            end)
        end)

        describe("with RLTB direction (Right-Left, Top-Bottom)", function()
            before_each(function()
                panelnav.panel_direction = "RLTB"
            end)

            it("should sort panels top to bottom, right to left", function()
                local panels = {
                    { x = 50, y = 100, w = 200, h = 150 },   -- top left
                    { x = 300, y = 100, w = 200, h = 150 },  -- top right
                    { x = 50, y = 300, w = 200, h = 150 },   -- bottom left
                    { x = 300, y = 300, w = 200, h = 150 },  -- bottom right
                }
                local sorted = panelnav:sortPanelsByReadingDirection(panels)
                -- Expected order: top-right, top-left, bottom-right, bottom-left
                assert.are.equal(300, sorted[1].x)
                assert.are.equal(100, sorted[1].y)
                assert.are.equal(50, sorted[2].x)
                assert.are.equal(100, sorted[2].y)
                assert.are.equal(300, sorted[3].x)
                assert.are.equal(300, sorted[3].y)
                assert.are.equal(50, sorted[4].x)
                assert.are.equal(300, sorted[4].y)
            end)
        end)

        describe("with TBLR direction (Top-Bottom, Left-Right)", function()
            before_each(function()
                panelnav.panel_direction = "TBLR"
            end)

            it("should sort panels left to right, top to bottom in each column", function()
                local panels = {
                    { x = 300, y = 300, w = 200, h = 150 },  -- right bottom
                    { x = 50, y = 100, w = 200, h = 150 },   -- left top
                    { x = 300, y = 100, w = 200, h = 150 },  -- right top
                    { x = 50, y = 300, w = 200, h = 150 },   -- left bottom
                }
                local sorted = panelnav:sortPanelsByReadingDirection(panels)
                -- Expected: left-top, left-bottom, right-top, right-bottom
                assert.are.equal(50, sorted[1].x)
                assert.are.equal(100, sorted[1].y)
                assert.are.equal(50, sorted[2].x)
                assert.are.equal(300, sorted[2].y)
                assert.are.equal(300, sorted[3].x)
                assert.are.equal(100, sorted[3].y)
                assert.are.equal(300, sorted[4].x)
                assert.are.equal(300, sorted[4].y)
            end)
        end)

        describe("with TBRL direction (Top-Bottom, Right-Left)", function()
            before_each(function()
                panelnav.panel_direction = "TBRL"
            end)

            it("should sort panels right to left, top to bottom in each column", function()
                local panels = {
                    { x = 50, y = 100, w = 200, h = 150 },   -- left top
                    { x = 300, y = 100, w = 200, h = 150 },  -- right top
                    { x = 50, y = 300, w = 200, h = 150 },   -- left bottom
                    { x = 300, y = 300, w = 200, h = 150 },  -- right bottom
                }
                local sorted = panelnav:sortPanelsByReadingDirection(panels)
                -- Expected: right-top, right-bottom, left-top, left-bottom
                assert.are.equal(300, sorted[1].x)
                assert.are.equal(100, sorted[1].y)
                assert.are.equal(300, sorted[2].x)
                assert.are.equal(300, sorted[2].y)
                assert.are.equal(50, sorted[3].x)
                assert.are.equal(100, sorted[3].y)
                assert.are.equal(50, sorted[4].x)
                assert.are.equal(300, sorted[4].y)
            end)
        end)

        it("should read the pages of a double-page spread one after the other", function()
            local spread = { w = 1600, h = 1200 }
            local panels = {
                { x = 40, y = 40, w = 720, h = 540 },    -- left page
                { x = 40, y = 620, w = 720, h = 540 },
                { x = 840, y = 40, w = 720, h = 540 },   -- right page
                { x = 840, y = 620, w = 720, h = 540 },
            }
            local function xs(sorted)
                local t = {}
                for i, p in ipairs(sorted) do t[i] = p.x .. "," .. p.y end
                return t
            end
            assert.are.same({ "40,40", "40,620", "840,40", "840,620" },
                xs(panelnav:sortPanelsByReadingDirection(panels, "LRTB", spread)))
            assert.are.same({ "840,40", "840,620", "40,40", "40,620" },
                xs(panelnav:sortPanelsByReadingDirection(panels, "RLTB", spread)))
            -- a panel across both pages: rows across the spread
            table.insert(panels, { x = 400, y = 1170, w = 800, h = 20 })
            assert.are.same({ "40,40", "840,40", "40,620", "840,620", "400,1170" },
                xs(panelnav:sortPanelsByReadingDirection(panels, "LRTB", spread)))
            -- not a spread
            table.remove(panels)
            assert.are.same({ "40,40", "840,40", "40,620", "840,620" },
                xs(panelnav:sortPanelsByReadingDirection(panels, "LRTB", { w = 1600, h = 1800 })))
        end)

        it("should return nil for empty panels array", function()
            local panels = {}
            local sorted = panelnav:sortPanelsByReadingDirection(panels)
            assert.is_nil(sorted)
        end)

        it("should handle nil panels", function()
            local sorted = panelnav:sortPanelsByReadingDirection(nil)
            assert.is_nil(sorted)
        end)

        it("should handle single panel", function()
            local panels = {{ x = 100, y = 100, w = 200, h = 150 }}
            local sorted = panelnav:sortPanelsByReadingDirection(panels)
            assert.are.equal(1, #sorted)
            assert.are.equal(100, sorted[1].x)
        end)
    end)

    describe("overlap threshold for row/column detection", function()
        local panelnav

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
            panelnav.panel_direction = "LRTB"
        end)

        it("should not consider 5% Y overlap as same row", function()
            -- Panel A: height 200, Panel B: height 100
            -- Overlap: 5 pixels = 5% of smaller (100)
            local panels = {
                { x = 50, y = 100, w = 200, h = 200 },   -- A
                { x = 50, y = 295, w = 200, h = 100 },   -- B (5px overlap with A)
            }
            local sorted = panelnav:sortPanelsByReadingDirection(panels)
            -- Should be treated as different rows, sorted by Y
            assert.are.equal(100, sorted[1].y)  -- A first (smaller Y)
            assert.are.equal(295, sorted[2].y)  -- B second
        end)

        it("should consider 40% Y overlap as same row", function()
            -- Panel A and B both at y=100-200 (same Y range, 100% overlap)
            local panels = {
                { x = 300, y = 100, w = 200, h = 100 },  -- right
                { x = 50, y = 100, w = 200, h = 100 },   -- left (same Y range)
            }
            local sorted = panelnav:sortPanelsByReadingDirection(panels)
            -- Same row, sorted by X (left to right in LRTB)
            assert.are.equal(50, sorted[1].x)   -- left first
            assert.are.equal(300, sorted[2].x)  -- right second
        end)

        it("should not consider 25% Y overlap as same row", function()
            -- Panel A: height 100, Panel B: height 100
            -- Overlap: 25 pixels = 25% (below 30% threshold)
            local panels = {
                { x = 50, y = 100, w = 200, h = 100 },
                { x = 50, y = 175, w = 200, h = 100 },
            }
            local sorted = panelnav:sortPanelsByReadingDirection(panels)
            -- Different rows, sorted by Y center
            assert.are.equal(100, sorted[1].y)  -- first panel
            assert.are.equal(175, sorted[2].y)  -- second panel
        end)
    end)

    describe("clipPanelsToPage", function()
        local panelnav

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        it("should clip panel extending beyond page bounds", function()
            local panels = {
                { x = -10, y = -10, w = 200, h = 200 },  -- extends past top-left
            }
            local clipped = panelnav:clipPanelsToPage(panels, 500, 500)
            assert.are.equal(1, #clipped)
            assert.are.equal(0, clipped[1].x)
            assert.are.equal(0, clipped[1].y)
            assert.are.equal(190, clipped[1].w)
            assert.are.equal(190, clipped[1].h)
        end)

        it("should clip panel extending beyond bottom-right", function()
            local panels = {
                { x = 400, y = 400, w = 200, h = 200 },  -- extends past bottom-right
            }
            local clipped = panelnav:clipPanelsToPage(panels, 500, 500)
            assert.are.equal(1, #clipped)
            assert.are.equal(400, clipped[1].x)
            assert.are.equal(400, clipped[1].y)
            assert.are.equal(100, clipped[1].w)
            assert.are.equal(100, clipped[1].h)
        end)

        it("should remove panel completely outside page bounds", function()
            local panels = {
                { x = -200, y = -200, w = 100, h = 100 },  -- completely outside
                { x = 100, y = 100, w = 200, h = 200 },
            }
            local clipped = panelnav:clipPanelsToPage(panels, 500, 500)
            assert.are.equal(1, #clipped)
            assert.are.equal(100, clipped[1].x)
        end)

        it("should return nil when all panels are outside page bounds", function()
            local panels = {
                { x = -200, y = -200, w = 100, h = 100 },  -- completely outside
            }
            local clipped = panelnav:clipPanelsToPage(panels, 500, 500)
            assert.is_nil(clipped)
        end)

        it("should not modify panel within page bounds", function()
            local panels = {
                { x = 100, y = 100, w = 200, h = 200 },
            }
            local clipped = panelnav:clipPanelsToPage(panels, 500, 500)
            assert.are.equal(1, #clipped)
            assert.are.equal(100, clipped[1].x)
            assert.are.equal(100, clipped[1].y)
            assert.are.equal(200, clipped[1].w)
            assert.are.equal(200, clipped[1].h)
        end)

        it("should return nil for empty panels array", function()
            local clipped = panelnav:clipPanelsToPage({}, 500, 500)
            assert.is_nil(clipped)
        end)

        it("should handle nil panels", function()
            local clipped = panelnav:clipPanelsToPage(nil, 500, 500)
            assert.is_nil(clipped)
        end)
    end)

    describe("getPanelsForCurrentPage", function()
        local panelnav
        local detections

        before_each(function()
            detections = 0
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {
                        getAllPanelsFromPage = function(_, pageno)
                            detections = detections + 1
                            if pageno == 1 then
                                return {
                                    { x = 300, y = 100, w = 200, h = 150 },
                                    { x = 50, y = 100, w = 200, h = 150 },
                                    { x = 60, y = 110, w = 50, h = 50 },     -- an inset
                                    { x = 600, y = 100, w = 100, h = 100 },  -- outside the page
                                }
                            end
                        end,
                        getNativePageDimensions = function()
                            return { w = 550, h = 800 }
                        end,
                    },
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        it("should return the clipped and sorted panels, those within others too, and cache them", function()
            local panels = panelnav:getPanelsForCurrentPage()
            assert.are.equal(3, #panels)
            assert.are.equal(50, panels[1].x)
            assert.are.equal(60, panels[2].x)
            assert.are.equal(300, panels[3].x)
            assert.are.equal(panels, panelnav:getPanelsForCurrentPage())
            assert.are.equal(1, detections)
        end)

        it("should return nil for a page without panels", function()
            panelnav.ui.paging.current_page = 2
            assert.is_nil(panelnav:getPanelsForCurrentPage())
            assert.are.equal(2, panelnav.panels_page)
        end)
    end)

    describe("getDirectionDescription", function()
        local panelnav

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        it("should return description for valid direction codes", function()
            assert.is_not_nil(panelnav:getDirectionDescription("LRTB"))
            assert.is_not_nil(panelnav:getDirectionDescription("RLTB"))
            assert.is_not_nil(panelnav:getDirectionDescription("TBLR"))
            assert.is_not_nil(panelnav:getDirectionDescription("TBRL"))
            assert.is_not_nil(panelnav:getDirectionDescription("LRBT"))
            assert.is_not_nil(panelnav:getDirectionDescription("RLBT"))
            assert.is_not_nil(panelnav:getDirectionDescription("BTLR"))
            assert.is_not_nil(panelnav:getDirectionDescription("BTRL"))
        end)

        it("should return direction code for unknown direction", function()
            assert.are.equal("UNKNOWN", panelnav:getDirectionDescription("UNKNOWN"))
        end)

        it("should match the labels of the zoom direction option", function()
            local KoptOptions = require("ui/data/koptoptions")
            local zoom_direction
            for _, tab in ipairs(KoptOptions) do
                for _, option in ipairs(tab.options) do
                    if option.name == "zoom_direction" then
                        zoom_direction = option
                    end
                end
            end
            assert.is_not_nil(zoom_direction)
            assert.are.equal(8, #zoom_direction.item_icons)
            for i, icon in ipairs(zoom_direction.item_icons) do
                local code = icon:match("^direction%.(%u+)$")
                assert.are.equal(zoom_direction.labels[i], panelnav:getDirectionDescription(code))
            end
        end)
    end)

    describe("direction_settings", function()
        local panelnav

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {},
                    paging = { current_page = 1 },
                    highlight = { panel_zoom_enabled = true },
                },
                view = {
                    registerViewModule = function() end,
                },
            }
        end)

        it("should have correct settings for all 8 directions", function()
            local directions = {"LRTB", "LRBT", "RLTB", "RLBT", "TBLR", "TBRL", "BTLR", "BTRL"}
            for _, dir in ipairs(directions) do
                local settings = panelnav.direction_settings[dir]
                assert.is_not_nil(settings, "Missing settings for " .. dir)
                assert.is_not_nil(settings.primary, "Missing primary for " .. dir)
                assert.is_not_nil(settings.primary_order, "Missing primary_order for " .. dir)
                assert.is_not_nil(settings.secondary_order, "Missing secondary_order for " .. dir)
                assert.is_true(settings.primary == "h" or settings.primary == "v",
                    "Invalid primary for " .. dir)
                assert.is_true(settings.primary_order == 1 or settings.primary_order == -1,
                    "Invalid primary_order for " .. dir)
                assert.is_true(settings.secondary_order == 1 or settings.secondary_order == -1,
                    "Invalid secondary_order for " .. dir)
            end
        end)

        it("should have horizontal primary for row-based directions", function()
            assert.are.equal("h", panelnav.direction_settings.LRTB.primary)
            assert.are.equal("h", panelnav.direction_settings.LRBT.primary)
            assert.are.equal("h", panelnav.direction_settings.RLTB.primary)
            assert.are.equal("h", panelnav.direction_settings.RLBT.primary)
        end)

        it("should have vertical primary for column-based directions", function()
            assert.are.equal("v", panelnav.direction_settings.TBLR.primary)
            assert.are.equal("v", panelnav.direction_settings.TBRL.primary)
            assert.are.equal("v", panelnav.direction_settings.BTLR.primary)
            assert.are.equal("v", panelnav.direction_settings.BTRL.primary)
        end)
    end)

    describe("panel reading direction", function()
        local panelnav, detections

        before_each(function()
            detections = 0
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {
                        getAllPanelsFromPage = function()
                            detections = detections + 1
                            return {
                                { x = 300, y = 100, w = 200, h = 150 },
                                { x = 50, y = 100, w = 200, h = 150 },
                            }
                        end,
                        getNativePageDimensions = function()
                            return { w = 550, h = 800 }
                        end,
                    },
                    paging = { current_page = 1 },
                },
                view = {
                    registerViewModule = function() end,
                    inverse_reading_order = false,
                },
            }
        end)

        after_each(function()
            G_reader_settings:delSetting("panel_direction")
            G_reader_settings:delSetting("panel_rotate_wide")
            G_reader_settings:delSetting("panel_view_mode")
            G_reader_settings:delSetting("panel_overlay_zoom")
        end)

        it("should follow the page turn direction by default", function()
            assert.is_nil(panelnav.panel_direction)
            assert.are.equal("LRTB", panelnav:getPanelDirection())
            panelnav.view.inverse_reading_order = true
            assert.are.equal("RLTB", panelnav:getPanelDirection())
        end)

        it("should follow the page turn direction with a mirrored UI: right to left unless page turns are inverted", function()
            local BD = require("ui/bidi")
            local orig_mirrored = BD.mirroredUILayout
            BD.mirroredUILayout = function() return true end
            local ok, err = pcall(function()
                assert.are.equal("RLTB", panelnav:getPanelDirection())
                panelnav.view.inverse_reading_order = true
                assert.are.equal("LRTB", panelnav:getPanelDirection())
                panelnav:setPanelDirection("TBRL")
                assert.are.equal("TBRL", panelnav:getPanelDirection())
            end)
            BD.mirroredUILayout = orig_mirrored
            assert.is_true(ok, err)
        end)

        it("should use the panel_direction setting rather than the page turn direction", function()
            panelnav.view.inverse_reading_order = true
            panelnav:setPanelDirection("TBLR")
            assert.are.equal("TBLR", panelnav:getPanelDirection())
            panelnav:setPanelDirection("UNKNOWN")
            assert.are.equal("TBLR", panelnav:getPanelDirection())
            panelnav:setPanelDirection(nil)
            assert.are.equal("RLTB", panelnav:getPanelDirection())
        end)

        it("should sort the panels again when the page turn direction changes", function()
            local panels = panelnav:getPanelsForCurrentPage()
            assert.are.equal(50, panels[1].x)
            panelnav.view.inverse_reading_order = true
            panels = panelnav:getPanelsForCurrentPage()
            assert.are.equal(300, panels[1].x)
            assert.are.equal(panels, panelnav:getPanelsForCurrentPage())
            assert.are.equal(2, detections)
        end)

        it("should read the book settings, or else the defaults", function()
            local LuaSettings = require("luasettings")
            panelnav:onReadSettings(LuaSettings:wrap{})
            assert.is_nil(panelnav.panel_direction)
            assert.is_true(panelnav.panel_rotate_wide)
            assert.is_false(panelnav.highlight_current_panel)
            G_reader_settings:saveSetting("panel_direction", "TBRL")
            G_reader_settings:makeFalse("panel_rotate_wide")
            panelnav:onReadSettings(LuaSettings:wrap{})
            assert.are.equal("TBRL", panelnav.panel_direction)
            assert.is_false(panelnav.panel_rotate_wide)
            panelnav:onReadSettings(LuaSettings:wrap{ panel_direction = "BTLR", panel_rotate_wide = true })
            assert.are.equal("BTLR", panelnav.panel_direction)
            assert.is_true(panelnav.panel_rotate_wide)
            panelnav:onReadSettings(LuaSettings:wrap{ panel_direction = "UNKNOWN" })
            assert.is_nil(panelnav.panel_direction)
        end)

        it("should only save the settings that differ from the defaults", function()
            local LuaSettings = require("luasettings")
            local doc_settings = LuaSettings:wrap{
                panel_direction = "LRBT",
                panel_rotate_wide = false,
                highlight_current_panel = true,
                show_panel_boxes = true,
            }
            panelnav.ui.doc_settings = doc_settings
            -- the defaults: follow the page turn direction, rotate wide panels, no highlight, no boxes
            panelnav:onReadSettings(LuaSettings:wrap{})
            panelnav:onSaveSettings()
            assert.are.same({}, doc_settings.data)
            panelnav:setPanelDirection("RLBT")
            panelnav.panel_rotate_wide = false
            panelnav.highlight_current_panel = true
            panelnav:onSaveSettings()
            assert.are.same({
                panel_direction = "RLBT",
                panel_rotate_wide = false,
                highlight_current_panel = true,
            }, doc_settings.data)
            -- the same values as new defaults are not saved
            G_reader_settings:saveSetting("panel_direction", "RLBT")
            G_reader_settings:makeFalse("panel_rotate_wide")
            panelnav:onSaveSettings()
            assert.are.same({ highlight_current_panel = true }, doc_settings.data)
            -- following the page turn direction is never saved, whatever the default
            panelnav:setPanelDirection(nil)
            panelnav:onSaveSettings()
            assert.are.same({ highlight_current_panel = true }, doc_settings.data)
        end)

        it("should show the panels over the page at 150 % by default", function()
            assert.are.equal("overlay", panelnav.panel_view_mode)
            assert.are.equal(1.5, panelnav.panel_overlay_zoom)
            assert.are.equal("overlay", ReaderPanelNav.getDefaultViewMode())
            assert.are.equal(1.5, ReaderPanelNav.getDefaultOverlayZoom())
            local LuaSettings = require("luasettings")
            panelnav:onReadSettings(LuaSettings:wrap{})
            assert.are.equal("overlay", panelnav.panel_view_mode)
            assert.are.equal(1.5, panelnav.panel_overlay_zoom)
        end)

        it("should read the panel view settings of the book, or else the defaults", function()
            local LuaSettings = require("luasettings")
            G_reader_settings:saveSetting("panel_view_mode", "fullscreen")
            G_reader_settings:saveSetting("panel_overlay_zoom", "fit")
            panelnav:onReadSettings(LuaSettings:wrap{})
            assert.are.equal("fullscreen", panelnav.panel_view_mode)
            assert.are.equal("fit", panelnav.panel_overlay_zoom)
            panelnav:onReadSettings(LuaSettings:wrap{ panel_view_mode = "overlay", panel_overlay_zoom = 2 })
            assert.are.equal("overlay", panelnav.panel_view_mode)
            assert.are.equal(2, panelnav.panel_overlay_zoom)
            -- unknown values: the defaults
            panelnav:onReadSettings(LuaSettings:wrap{ panel_view_mode = "UNKNOWN", panel_overlay_zoom = -1 })
            assert.are.equal("fullscreen", panelnav.panel_view_mode)
            assert.are.equal("fit", panelnav.panel_overlay_zoom)
            G_reader_settings:saveSetting("panel_view_mode", "UNKNOWN")
            G_reader_settings:saveSetting("panel_overlay_zoom", "big")
            panelnav:onReadSettings(LuaSettings:wrap{ panel_overlay_zoom = 0 })
            assert.are.equal("overlay", panelnav.panel_view_mode)
            assert.are.equal(1.5, panelnav.panel_overlay_zoom)
        end)

        it("should only save the panel view settings that differ from the defaults", function()
            local LuaSettings = require("luasettings")
            local doc_settings = LuaSettings:wrap{ panel_view_mode = "fullscreen", panel_overlay_zoom = 2 }
            panelnav.ui.doc_settings = doc_settings
            panelnav:onReadSettings(LuaSettings:wrap{})
            panelnav:onSaveSettings()
            assert.are.same({}, doc_settings.data)
            panelnav.panel_view_mode = "fullscreen"
            panelnav.panel_overlay_zoom = 1.25
            panelnav:onSaveSettings()
            assert.are.same({ panel_view_mode = "fullscreen", panel_overlay_zoom = 1.25 }, doc_settings.data)
            panelnav.panel_overlay_zoom = "fit"
            panelnav:onSaveSettings()
            assert.are.same({ panel_view_mode = "fullscreen", panel_overlay_zoom = "fit" }, doc_settings.data)
            -- the same values as new defaults are not saved
            G_reader_settings:saveSetting("panel_view_mode", "fullscreen")
            G_reader_settings:saveSetting("panel_overlay_zoom", "fit")
            panelnav:onSaveSettings()
            assert.are.same({}, doc_settings.data)
            -- but the built-in ones are, when they are not the defaults
            panelnav.panel_view_mode = "overlay"
            panelnav.panel_overlay_zoom = 1.5
            panelnav:onSaveSettings()
            assert.are.same({ panel_view_mode = "overlay", panel_overlay_zoom = 1.5 }, doc_settings.data)
        end)
    end)

    describe("navigation", function()
        local Document, Event, Notification
        local panelnav, events, shown, notified, orig_notify
        -- panels by page, in native page coordinates; page 2 has none
        local pages = {
            [1] = {
                { x = 300, y = 100, w = 200, h = 150 },
                { x = 50, y = 100, w = 200, h = 150 },
            },
            [3] = {
                { x = 50, y = 100, w = 450, h = 150 },
                { x = 50, y = 300, w = 200, h = 150 },
                { x = 300, y = 300, w = 200, h = 150 },
            },
        }

        setup(function()
            Document = require("document/document")
            Event = require("ui/event")
            Notification = require("ui/widget/notification")
        end)

        before_each(function()
            events, shown, notified = {}, {}, {}
            orig_notify = Notification.notify
            Notification.notify = function(_, text) table.insert(notified, text) end
            local ui = {
                document = {
                    info = { number_of_pages = 3 },
                    getNextPage = Document.getNextPage,
                    getPrevPage = Document.getPrevPage,
                    getAllPanelsFromPage = function(_, pageno)
                        local panels = pages[pageno]
                        if panels then
                            local copy = {}
                            for i, p in ipairs(panels) do
                                copy[i] = { x = p.x, y = p.y, w = p.w, h = p.h }
                            end
                            return copy
                        end
                    end,
                    getNativePageDimensions = function()
                        return { w = 550, h = 800 }
                    end,
                },
                paging = { current_page = 1 },
            }
            -- ReaderUI: page changes, as ReaderPaging would do them
            function ui:handleEvent(event)
                table.insert(events, event.handler .. " " .. tostring(event.args[1]))
                if event.handler == "onGotoPage" then
                    self.paging.current_page = event.args[1]
                    panelnav:onPageUpdate(event.args[1])
                end
                return true
            end
            panelnav = ReaderPanelNav:new{
                ui = ui,
                view = {
                    registerViewModule = function() end,
                },
            }
            -- the viewer is open once a panel is shown
            panelnav.showPanel = function(self, panel)
                table.insert(shown, string.format("page %d panel %d %d,%d %dx%d", self.ui.paging.current_page,
                    self.current_panel_index, panel.x, panel.y, panel.w, panel.h))
                self._panel_viewer = self._panel_viewer or {}
            end
        end)

        after_each(function()
            Notification.notify = orig_notify
        end)

        local function closeViewer()
            panelnav._panel_viewer = nil
        end

        it("should show the panel again after the viewer closed for a rotation, or for a resize", function()
            local UIManager = require("ui/uimanager")
            local rotations = {}
            panelnav.view.onSetRotationMode = function(_, mode) table.insert(rotations, tostring(mode)) end
            local orig_next_tick = UIManager.nextTick
            UIManager.nextTick = function(_, action) action() end
            local ok, err = pcall(function()
                panelnav:onGotoNextPanel()
                panelnav:onGotoNextPanel()
                closeViewer()
                panelnav:rotateAndShowPanel(1)
                closeViewer()
                -- resized: the reader lays itself out for the new size, no rotation
                panelnav:rotateAndShowPanel()
            end)
            UIManager.nextTick = orig_next_tick
            assert.is_true(ok, err)
            assert.are.same({ "1" }, rotations)
            assert.are.same({
                "page 1 panel 1 50,100 200x150",
                "page 1 panel 2 300,100 200x150",
                "page 1 panel 2 300,100 200x150",
                "page 1 panel 2 300,100 200x150",
            }, shown)
        end)

        it("should start with the first panel on Next panel, and with the last one on Previous panel", function()
            assert.is_true(panelnav:onGotoNextPanel())
            closeViewer()
            assert.is_true(panelnav:onGotoPrevPanel())
            assert.are.same({
                "page 1 panel 1 50,100 200x150",
                "page 1 panel 2 300,100 200x150",
            }, shown)
            assert.are.same({}, events)
        end)

        it("should go on with the first panel of the next page, and show a page without panels whole", function()
            panelnav:onGotoNextPanel()
            panelnav:onGotoNextPanel()
            panelnav:onGotoNextPanel()
            panelnav:onGotoNextPanel()
            panelnav:onGotoNextPanel()
            assert.are.same({
                "page 1 panel 1 50,100 200x150",
                "page 1 panel 2 300,100 200x150",
                "page 2 panel 0 0,0 550x800",
                "page 3 panel 1 50,100 450x150",
                "page 3 panel 2 50,300 200x150",
            }, shown)
            assert.are.same({ "onGotoPage 2", "onGotoPage 3" }, events)
        end)

        it("should go back to the last panel of the previous page", function()
            panelnav.ui.paging.current_page = 3
            panelnav:onGotoNextPanel()
            panelnav:onGotoPrevPanel()
            panelnav:onGotoPrevPanel()
            panelnav:onGotoPrevPanel()
            assert.are.same({
                "page 3 panel 1 50,100 450x150",
                "page 2 panel 0 0,0 550x800",
                "page 1 panel 2 300,100 200x150",
                "page 1 panel 1 50,100 200x150",
            }, shown)
            assert.are.same({ "onGotoPage 2", "onGotoPage 1" }, events)
        end)

        it("should stay on the first and last panels of the document, and say so", function()
            panelnav:onGotoNextPanel()
            panelnav:onGotoPrevPanel()
            assert.are.equal(1, panelnav.ui.paging.current_page)
            assert.are.equal(1, panelnav.current_panel_index)
            closeViewer()
            panelnav.ui:handleEvent(Event:new("GotoPage", 3))
            panelnav:onGotoPrevPanel()
            panelnav:onGotoNextPanel()
            assert.are.equal(3, panelnav.ui.paging.current_page)
            assert.are.equal(3, panelnav.current_panel_index)
            assert.are.same({
                "page 1 panel 1 50,100 200x150",
                "page 3 panel 3 300,300 200x150",
            }, shown)
            assert.are.same({ "onGotoPage 3" }, events)
            assert.are.same({ "This is the first page.", "This is the last page." }, notified)
        end)

        it("should resume with the last panel shown on Enter panel navigation", function()
            panelnav:onEnterPanelNavMode()
            panelnav:onGotoNextPanel()
            closeViewer()
            panelnav:onEnterPanelNavMode()
            assert.are.same({
                "page 1 panel 1 50,100 200x150",
                "page 1 panel 2 300,100 200x150",
                "page 1 panel 2 300,100 200x150",
            }, shown)
        end)

        it("should start from the Panel zoom menu as Enter panel navigation, when panel zoom is allowed", function()
            local ReaderHighlight = require("apps/reader/modules/readerhighlight")
            panelnav.ui.panelnav = panelnav
            local highlight = { ui = panelnav.ui, panel_zoom_enabled = true }
            local item
            for _, menu_item in ipairs(ReaderHighlight.genPanelZoomMenu(highlight)) do
                if menu_item.text == "Start panel navigation" then
                    item = menu_item
                end
            end
            assert.is_not_nil(item)
            assert.is_true(item.enabled_func())
            highlight.panel_zoom_enabled = false
            assert.is_false(item.enabled_func())
            -- a plain item: TouchMenu closes the menu after its callback
            assert.is_nil(item.checked_func)
            assert.is_falsy(item.keep_menu_open)
            -- ReaderUI hands the event to the module
            local handleEvent = panelnav.ui.handleEvent
            function panelnav.ui:handleEvent(event)
                handleEvent(self, event)
                if event.handler == "onEnterPanelNavMode" then
                    return panelnav:onEnterPanelNavMode()
                end
            end
            panelnav.ui.paging.current_page = 3
            item.callback()
            assert.are.same({ "onEnterPanelNavMode nil" }, events)
            assert.are.same({ "page 3 panel 1 50,100 450x150" }, shown)
        end)

        it("should start with the panel at a long-pressed position, of the page pressed", function()
            assert.is_false(panelnav:showPanelAt({ x = 10, y = 10, page = 1 }))
            assert.is_true(panelnav:showPanelAt({ x = 400, y = 200, page = 1 }))
            closeViewer()
            assert.is_true(panelnav:showPanelAt({ x = 100, y = 350, page = 3 }))
            assert.are.same({
                "page 1 panel 2 300,100 200x150",
                "page 3 panel 2 50,300 200x150",
            }, shown)
            assert.are.same({ "onGotoPage 3" }, events)
        end)

        it("should start with the whole page on a long-press on a page without panels", function()
            panelnav.ui.paging.current_page = 2
            assert.is_true(panelnav:showPanelAt({ x = 100, y = 350, page = 2 }))
            assert.are.same({ "page 2 panel 0 0,0 550x800" }, shown)
            -- and goes on with the next page
            panelnav:onGotoNextPanel()
            assert.are.same({ "page 2 panel 0 0,0 550x800", "page 3 panel 1 50,100 450x150" }, shown)
            closeViewer()
            panelnav.ui.document.getAllPanelsFromPage = nil
            assert.is_false(panelnav:showPanelAt({ x = 100, y = 350, page = 2 }))
        end)

        it("should discard the taps made while turning the page, not to skip its first panel", function()
            local Input = require("device").input
            local delays = {}
            stub(Input, "inhibitInputUntil", function(_, delay) table.insert(delays, delay) end)
            local ok, err = pcall(function()
                panelnav:onGotoNextPanel()
                panelnav:onGotoNextPanel()
                assert.are.same({}, delays)
                -- page 2, then page 3
                panelnav:onGotoNextPanel()
                panelnav:onGotoNextPanel()
                assert.are.same({ 0.2, 0.2 }, delays)
                panelnav:onGotoPrevPanel()
                assert.are.same({ 0.2, 0.2, 0.2 }, delays)
                -- not at the end of the document
                panelnav:onGotoPrevPanel()
                panelnav:onGotoPrevPanel()
                panelnav:onGotoPrevPanel()
                assert.are.equal(1, panelnav.ui.paging.current_page)
                assert.are.equal(4, #delays)
            end)
            Input.inhibitInputUntil:revert()
            assert.is_true(ok, err)
        end)

        it("should navigate from a long-pressed panel, or else show the panel found there alone, as a copy", function()
            local Blitbuffer = require("ffi/blitbuffer")
            local ReaderHighlight = require("apps/reader/modules/readerhighlight")
            local UIManager = require("ui/uimanager")
            local tile = Blitbuffer.new(100, 150, Blitbuffer.TYPE_BBRGB32)
            panelnav.ui.panelnav = panelnav
            panelnav.ui.document.getPanelFromPage = function() return { x = 0, y = 0, w = 100, h = 150 } end
            panelnav.ui.document.drawPagePart = function() return tile, false end
            local highlight = ReaderHighlight:extend{
                ui = panelnav.ui,
                view = {
                    -- page 1 shown 1:1
                    screenToPageTransform = function(_, pos) return { x = pos.x, y = pos.y, page = 1 } end,
                },
                clear = function() end,
            }
            local viewer
            stub(UIManager, "show", function(_, widget) viewer = widget end)
            local ok, err = pcall(function()
                assert.is_true(highlight:onPanelZoom(nil, { pos = { x = 400, y = 200 } }))
                assert.are.same({ "page 1 panel 2 300,100 200x150" }, shown)
                assert.is_nil(viewer)
                closeViewer()
                -- outside the detected panels: ImageViewer, with a copy of the cache tile
                assert.is_true(highlight:onPanelZoom(nil, { pos = { x = 10, y = 10 } }))
                assert.are.equal(1, #shown)
                assert.is_not_nil(viewer)
                assert.are_not.equal(tile, viewer.image)
                assert.is_true(viewer.image_disposable)
                UIManager:close(viewer)
            end)
            UIManager.show:revert()
            tile:free()
            assert.is_true(ok, err)
        end)

        it("should forget the panels on page change and when the document closes", function()
            panelnav:onGotoNextPanel()
            assert.are.equal(1, panelnav.panels_page)
            panelnav:onPageUpdate(2)
            assert.is_nil(panelnav.current_page_panels)
            assert.are.equal(0, panelnav.current_panel_index)
            panelnav.ui.paging.current_page = 2
            panelnav:getPanelsForPage(3)
            assert.is_not_nil(panelnav.current_page_panels)
            panelnav._panel_viewer = nil
            panelnav:onCloseDocument()
            assert.is_nil(panelnav.current_page_panels)
            assert.is_nil(panelnav.panels_page)
        end)

        it("should not start without panel detection", function()
            panelnav.ui.document.getAllPanelsFromPage = nil
            assert.is_nil(panelnav:onGotoNextPanel())
            assert.is_nil(panelnav:onGotoPrevPanel())
            assert.is_nil(panelnav:onEnterPanelNavMode())
            assert.are.same({}, shown)
        end)
    end)

    describe("getTapZones", function()
        local BD
        local panelnav, backward_w
        -- top / bottom page turn tap zones
        local page_turn_forward_zone = { ratio_x = 0, ratio_y = 0.5, ratio_w = 1, ratio_h = 0.5 }
        local page_turn_backward_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 0.5 }

        setup(function()
            BD = require("ui/bidi")
            backward_w = G_defaults:readSetting("DTAP_ZONE_BACKWARD").w
        end)

        before_each(function()
            panelnav = ReaderPanelNav:new{
                ui = {},
                view = {
                    registerViewModule = function() end,
                    inverse_reading_order = true,
                    getTapZones = function()
                        return page_turn_forward_zone, page_turn_backward_zone
                    end,
                },
            }
        end)

        after_each(function()
            G_reader_settings:delSetting("panel_nav_one_hand")
            G_reader_settings:delSetting("page_turns_tap_zones")
            G_reader_settings:delSetting("page_turns_tap_zone_backward_size_ratio")
        end)

        it("should be the page turn tap zones without one-handed navigation", function()
            local forward_zone, backward_zone = panelnav:getTapZones()
            assert.are.equal(page_turn_forward_zone, forward_zone)
            assert.are.equal(page_turn_backward_zone, backward_zone)
            G_reader_settings:saveSetting("panel_nav_one_hand", "both")
            forward_zone, backward_zone = panelnav:getTapZones()
            assert.are.equal(page_turn_forward_zone, forward_zone)
            assert.are.equal(page_turn_backward_zone, backward_zone)
        end)

        it("should make the strip as wide as the backward page turn tap zone", function()
            G_reader_settings:saveSetting("panel_nav_one_hand", "right")
            G_reader_settings:saveSetting("page_turns_tap_zone_backward_size_ratio", 0.1)
            -- not with the default tap zones, which don't use it
            local _, default_backward_zone = panelnav:getTapZones()
            assert.are.same({ ratio_x = 1 - backward_w, ratio_y = 0, ratio_w = backward_w, ratio_h = 1 }, default_backward_zone)
            G_reader_settings:saveSetting("page_turns_tap_zones", "left_right")
            local forward_zone, backward_zone = panelnav:getTapZones()
            assert.are.same({ ratio_x = 0, ratio_y = 0, ratio_w = 1 - 0.1, ratio_h = 1 }, forward_zone)
            assert.are.same({ ratio_x = 1 - 0.1, ratio_y = 0, ratio_w = 0.1, ratio_h = 1 }, backward_zone)
        end)

        it("should keep the strip from 10 to 50 % of the screen width", function()
            G_reader_settings:saveSetting("panel_nav_one_hand", "right")
            G_reader_settings:saveSetting("page_turns_tap_zones", "left_right")
            for _, ratios in ipairs({ { 0, 0.1 }, { 0.05, 0.1 }, { 0.1, 0.1 }, { 0.3, 0.3 }, { 0.5, 0.5 }, { 0.7, 0.5 }, { 1, 0.5 } }) do
                G_reader_settings:saveSetting("page_turns_tap_zone_backward_size_ratio", ratios[1])
                local forward_zone, backward_zone = panelnav:getTapZones()
                assert.are.same({ ratio_x = 1 - ratios[2], ratio_y = 0, ratio_w = ratios[2], ratio_h = 1 }, backward_zone, ratios[1])
                assert.are.same({ ratio_x = 0, ratio_y = 0, ratio_w = 1 - ratios[2], ratio_h = 1 }, forward_zone, ratios[1])
            end
        end)

        it("should not mirror the strip with inverted page turns or a mirrored UI", function()
            G_reader_settings:saveSetting("panel_nav_one_hand", "left")
            local orig_mirrored = BD._mirrored_ui_layout
            BD._mirrored_ui_layout = true
            local ok, forward_zone, backward_zone = pcall(panelnav.getTapZones, panelnav)
            BD._mirrored_ui_layout = orig_mirrored
            assert.is_true(ok, forward_zone)
            assert.are.same({ ratio_x = backward_w, ratio_y = 0, ratio_w = 1 - backward_w, ratio_h = 1 }, forward_zone)
            assert.are.same({ ratio_x = 0, ratio_y = 0, ratio_w = backward_w, ratio_h = 1 }, backward_zone)
        end)
    end)

    describe("showPanel", function()
        local Blitbuffer, PanelViewer, Screen, UIManager
        local panelnav, footer, drawn

        setup(function()
            Blitbuffer = require("ffi/blitbuffer")
            PanelViewer = require("ui/widget/panelviewer")
            Screen = require("device").screen
            UIManager = require("ui/uimanager")
        end)

        before_each(function()
            drawn = {}
            footer = {
                settings = { reclaim_height = false },
                getHeight = function() return 40 end,
                paintTo = function() end,
            }
            panelnav = ReaderPanelNav:new{
                ui = {
                    document = {
                        drawPagePart = function(_, pageno, rect, rotation, rotate, max_size)
                            table.insert(drawn, { pageno, rect, rotation, rotate, max_size })
                            return Blitbuffer.new(rect.w, rect.h, Blitbuffer.TYPE_BBRGB32), rotate
                        end,
                    },
                    paging = { current_page = 2 },
                },
                view = {
                    registerViewModule = function() end,
                    footer = footer,
                    footer_visible = true,
                    inverse_reading_order = true,
                    getTapZones = function()
                        return { ratio_x = 0, ratio_y = 0, ratio_w = 0.75, ratio_h = 1 },
                               { ratio_x = 0.75, ratio_y = 0, ratio_w = 0.25, ratio_h = 1 }
                    end,
                },
                -- see "over the page" below
                panel_view_mode = "fullscreen",
            }
        end)

        after_each(function()
            if panelnav._panel_viewer then
                UIManager:close(panelnav._panel_viewer)
            end
            G_reader_settings:delSetting("panel_nav_one_hand")
        end)

        it("should open the viewer with the footer at the bottom and the page turn settings, then reuse it", function()
            panelnav:showPanel({ x = 0, y = 0, w = 100, h = 150 })
            local viewer = panelnav._panel_viewer
            assert.is_not_nil(viewer)
            assert.are.equal(40, viewer.reserved_bottom_height)
            assert.is_function(viewer.paint_bottom_callback)
            assert.are.equal(0.75, viewer.forward_zone.ratio_w)
            assert.are.equal(0.75, viewer.backward_zone.ratio_x)
            assert.is_true(viewer.inverse_reading_order)
            assert.are.equal(2, drawn[1][1])
            -- rendered at the size it is shown, above the footer
            assert.are.same({ w = Screen:getWidth(), h = Screen:getHeight() - 40 }, drawn[1][5])
            panelnav:showPanel({ x = 0, y = 0, w = 120, h = 150 })
            assert.are.equal(viewer, panelnav._panel_viewer)
            assert.are.equal(120, viewer.image:getWidth())
            assert.are.same({ w = Screen:getWidth(), h = Screen:getHeight() - 40 }, drawn[2][5])
            UIManager:close(viewer)
            assert.is_nil(panelnav._panel_viewer)
        end)

        it("should give the viewer copies of the panel tiles, which the document cache may free while shown", function()
            local tiles = {}
            panelnav.ui.document.drawPagePart = function(_, pageno, rect, rotation, rotate, max_size)
                local tile = Blitbuffer.new(rect.w, rect.h, Blitbuffer.TYPE_BBRGB32)
                tile:setPixel(0, 0, Blitbuffer.COLOR_WHITE)
                table.insert(tiles, tile)
                return tile, rotate
            end
            panelnav:showPanel({ x = 0, y = 0, w = 100, h = 150 })
            local viewer = panelnav._panel_viewer
            local image = viewer.image
            assert.are_not.equal(tiles[1], image)
            -- the cache drops the tile (e.g., on low memory): the viewer's copy stays
            tiles[1]:free()
            assert.are.equal(1, image:getAllocated())
            assert.are.equal(100, image:getWidth())
            assert.are.equal(0xFF, image:getPixel(0, 0):getColorRGB32().r)
            -- the next panel: a copy again, the viewer frees the previous one
            panelnav:showPanel({ x = 0, y = 0, w = 120, h = 150 })
            assert.are_not.equal(tiles[2], viewer.image)
            assert.are.equal(120, viewer.image:getWidth())
            assert.are.equal(0, image:getAllocated())
            assert.are.equal(1, tiles[2]:getAllocated())
            UIManager:close(viewer)
            assert.are.equal(1, tiles[2]:getAllocated())
        end)

        it("should give the viewer the page turn tap zones, or the one-handed ones", function()
            -- page turn tap zones unlike the one-handed ones: top / bottom
            local forward_zone = { ratio_x = 0, ratio_y = 0.5, ratio_w = 1, ratio_h = 0.5 }
            local backward_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 0.5 }
            panelnav.view.getTapZones = function() return forward_zone, backward_zone end
            local backward_w = G_defaults:readSetting("DTAP_ZONE_BACKWARD").w
            local expected = {
                off = { forward_zone, backward_zone },
                left = {
                    { ratio_x = backward_w, ratio_y = 0, ratio_w = 1 - backward_w, ratio_h = 1 },
                    { ratio_x = 0, ratio_y = 0, ratio_w = backward_w, ratio_h = 1 },
                },
                right = {
                    { ratio_x = 0, ratio_y = 0, ratio_w = 1 - backward_w, ratio_h = 1 },
                    { ratio_x = 1 - backward_w, ratio_y = 0, ratio_w = backward_w, ratio_h = 1 },
                },
            }
            for _, hand in ipairs({ "off", "left", "right" }) do
                if hand == "off" then
                    G_reader_settings:delSetting("panel_nav_one_hand")
                else
                    G_reader_settings:saveSetting("panel_nav_one_hand", hand)
                end
                panelnav:showPanel({ x = 0, y = 0, w = 100, h = 150 })
                local viewer = panelnav._panel_viewer
                assert.are.same(expected[hand][1], viewer.forward_zone, hand)
                assert.are.same(expected[hand][2], viewer.backward_zone, hand)
                -- swipes still follow the page turn direction
                assert.is_true(viewer.inverse_reading_order)
                UIManager:close(viewer)
            end
        end)

        it("should paint an overlapping footer over the panel", function()
            footer.settings.reclaim_height = true
            panelnav:showPanel({ x = 0, y = 0, w = 100, h = 150 })
            assert.are.equal(0, panelnav._panel_viewer.reserved_bottom_height)
            assert.is_function(panelnav._panel_viewer.paint_bottom_callback)
            assert.are.same({ w = Screen:getWidth(), h = Screen:getHeight() }, drawn[1][5])
        end)

        it("should not paint a hidden footer", function()
            panelnav.view.footer_visible = false
            panelnav:showPanel({ x = 0, y = 0, w = 100, h = 150 })
            assert.are.equal(0, panelnav._panel_viewer.reserved_bottom_height)
            assert.is_nil(panelnav._panel_viewer.paint_bottom_callback)
            assert.are.same({ w = Screen:getWidth(), h = Screen:getHeight() }, drawn[1][5])
        end)

        it("should tell wide panels from the area they are shown in", function()
            -- 3 times as wide as tall, shown in a portrait area 4 or 2 times as tall as wide
            assert.is_false(panelnav:isWidePanel({ x = 0, y = 0, w = 300, h = 100 }, { w = 100, h = 400 }))
            assert.is_true(panelnav:isWidePanel({ x = 0, y = 0, w = 300, h = 100 }, { w = 100, h = 200 }))
            -- tall panels in a landscape area
            assert.is_true(panelnav:isWidePanel({ x = 0, y = 0, w = 100, h = 300 }, { w = 200, h = 100 }))
            assert.is_false(panelnav:isWidePanel({ x = 0, y = 0, w = 100, h = 300 }, { w = 100, h = 200 }))
            -- never in a square area
            assert.is_false(panelnav:isWidePanel({ x = 0, y = 0, w = 300, h = 100 }, { w = 100, h = 100 }))
        end)

        it("should rotate wide panels only, unless disabled", function()
            panelnav.view.footer_visible = false -- shown on the whole screen
            local landscape = Screen:getWidth() > Screen:getHeight()
            local ratio = math.max(Screen:getWidth(), Screen:getHeight()) / math.min(Screen:getWidth(), Screen:getHeight())
            -- the other way round from the screen, more or less elongated than it
            local function panel(elongation)
                local long, short = math.floor(100 * elongation), 100
                if landscape then
                    return { x = 0, y = 0, w = short, h = long }
                end
                return { x = 0, y = 0, w = long, h = short }
            end
            assert.is_true(panelnav:isWidePanel(panel(ratio * 1.1)))
            assert.is_false(panelnav:isWidePanel(panel(1.1)))
            assert.is_false(panelnav:isWidePanel(landscape and { x = 0, y = 0, w = 300, h = 100 } or { x = 0, y = 0, w = 100, h = 300 }))
            panelnav:showPanel(panel(ratio * 1.1))
            panelnav:showPanel(panel(1.1))
            panelnav.panel_rotate_wide = false
            panelnav:showPanel(panel(ratio * 1.1))
            assert.is_true(drawn[1][4])
            assert.is_false(drawn[2][4])
            assert.is_false(drawn[3][4])
            assert.is_true(panelnav._panel_viewer.rotated == false)
        end)

        describe("over the page", function()
            local painted, view_zoom

            before_each(function()
                panelnav.panel_view_mode = "overlay"
                -- the page is shown at twice its native size, 10, 20 from the top left of the screen
                view_zoom = 2
                panelnav.view.state = { zoom = view_zoom }
                panelnav.view.pageToScreenTransform = function(_, page, rect)
                    return { page = page, x = 10 + rect.x * view_zoom, y = 20 + rect.y * view_zoom,
                             w = rect.w * view_zoom, h = rect.h * view_zoom }
                end
                painted = {}
                panelnav.view.paintTo = function(_, bb, x, y)
                    table.insert(painted, { bb, x, y })
                end
                -- render the panel as big as fits in max_size, as Document:drawPagePart() does
                panelnav.ui.document.drawPagePart = function(_, pageno, rect, rotation, rotate, max_size)
                    table.insert(drawn, { pageno, rect, rotation, rotate, max_size })
                    local zoom = math.min(max_size.w / rect.w, max_size.h / rect.h)
                    return Blitbuffer.new(math.ceil(rect.w * zoom - 0.001), math.ceil(rect.h * zoom - 0.001),
                        Blitbuffer.TYPE_BBRGB32), rotate
                end
            end)

            local function imageSize()
                local image = panelnav._panel_viewer.image
                return { w = image:getWidth(), h = image:getHeight() }
            end

            it("should open the viewer over the page as the reader shows it, then reuse it", function()
                panelnav:showPanel({ x = 10, y = 20, w = 100, h = 50 })
                local viewer = panelnav._panel_viewer
                assert.is_true(viewer.overlay)
                -- the footer stays as it is, painted with the page
                assert.are.equal(0, viewer.reserved_bottom_height)
                assert.is_nil(viewer.paint_bottom_callback)
                assert.are.equal(40, viewer.overlay_bottom_height)
                viewer.paint_background_callback("bb", 0, 0)
                assert.are.same({ { "bb", 0, 0 } }, painted)
                -- where the panel is on the page
                assert.are.same({ page = 2, x = 30, y = 60, w = 200, h = 100 }, viewer.panel_rect)
                -- the same tap zones and swipes as fullscreen
                assert.are.equal(0.75, viewer.forward_zone.ratio_w)
                assert.are.equal(0.75, viewer.backward_zone.ratio_x)
                assert.is_true(viewer.inverse_reading_order)
                assert.are.equal(2, drawn[1][1])
                panelnav:showPanel({ x = 200, y = 300, w = 120, h = 60 })
                assert.are.equal(viewer, panelnav._panel_viewer)
                assert.are.same({ page = 2, x = 410, y = 620, w = 240, h = 120 }, viewer.panel_rect)
                assert.are.same({ w = 360, h = 180 }, imageSize())
                UIManager:close(viewer)
                assert.is_nil(panelnav._panel_viewer)
            end)

            it("should leave the footer as it is when it overlaps the page, and use the whole screen without it", function()
                footer.settings.reclaim_height = true
                panelnav:showPanel({ x = 0, y = 0, w = 100, h = 150 })
                assert.are.equal(40, panelnav._panel_viewer.overlay_bottom_height)
                assert.are.equal(0, panelnav._panel_viewer.reserved_bottom_height)
                UIManager:close(panelnav._panel_viewer)
                panelnav.view.footer_visible = false
                panelnav:showPanel({ x = 0, y = 0, w = 100, h = 150 })
                assert.are.equal(0, panelnav._panel_viewer.overlay_bottom_height)
                assert.is_nil(panelnav._panel_viewer.paint_bottom_callback)
            end)

            it("should enlarge the panel from its size on the page, by the zoom setting", function()
                local panel = { x = 0, y = 0, w = 100, h = 50 } -- 200x100 on the page
                local sizes = {}
                for _, zoom in ipairs({ 1.5, 1.25, 2 }) do
                    panelnav.panel_overlay_zoom = zoom
                    panelnav:showPanel(panel)
                    table.insert(sizes, imageSize())
                end
                assert.are.same({ { w = 300, h = 150 }, { w = 250, h = 125 }, { w = 400, h = 200 } }, sizes)
                assert.are.same({ w = 300, h = 150 }, drawn[1][5])
            end)

            it("should show it at most as big as fits on the screen, as with Fit screen", function()
                local max_size = PanelViewer.getOverlayMaxSize(40)
                -- 1.5 times that panel on the page is too wide, but not too tall
                local panel = { x = 0, y = 0, w = math.ceil(max_size.w / 2), h = math.floor(max_size.h / 4) }
                panelnav:showPanel(panel)
                local zoom = max_size.w / panel.w
                assert.are.same({ w = max_size.w, h = math.min(max_size.h, panel.h * view_zoom * 1.5) }, drawn[1][5])
                assert.are.same({ w = max_size.w, h = math.ceil(panel.h * zoom - 0.001) }, imageSize())
                -- a small panel, to fit the screen: as big as fits, too
                panelnav.panel_overlay_zoom = "fit"
                local small = { x = 0, y = 0, w = 20, h = 10 }
                panelnav:showPanel(small)
                assert.are.same(max_size, drawn[2][5])
                assert.are.equal(max_size.w, imageSize().w)
                -- the card within the margins, above the footer
                local image = imageSize()
                assert.is_true(image.w <= max_size.w and image.h <= max_size.h)
            end)

            it("should never rotate the panel", function()
                panelnav.panel_rotate_wide = true
                local landscape = Screen:getWidth() > Screen:getHeight()
                local wide = landscape and { x = 0, y = 0, w = 10, h = 300 } or { x = 0, y = 0, w = 300, h = 10 }
                assert.is_true(panelnav:isWidePanel(wide))
                panelnav:showPanel(wide)
                assert.is_false(drawn[1][4])
                assert.is_false(panelnav._panel_viewer.rotated)
            end)

            it("should frame nothing when the panel is not on the screen", function()
                panelnav.view.pageToScreenTransform = function() return nil end
                panelnav:showPanel({ x = 0, y = 0, w = 100, h = 50 })
                assert.is_nil(panelnav._panel_viewer.panel_rect)
                -- its size on the page, from the zoom of the page
                assert.are.same({ w = 300, h = 150 }, imageSize())
            end)

            it("should stay over the page until the viewer is closed", function()
                panelnav:showPanel({ x = 0, y = 0, w = 100, h = 50 })
                local viewer = panelnav._panel_viewer
                -- (the menu is not reachable while the viewer is open)
                panelnav.panel_view_mode = "fullscreen"
                panelnav:showPanel({ x = 0, y = 0, w = 100, h = 50 })
                assert.are.equal(viewer, panelnav._panel_viewer)
                assert.is_true(viewer.overlay)
                assert.is_false(drawn[2][4])
                UIManager:close(viewer)
                panelnav:showPanel({ x = 0, y = 0, w = 100, h = 50 })
                assert.is_false(panelnav._panel_viewer.overlay)
            end)
        end)
    end)
end)
