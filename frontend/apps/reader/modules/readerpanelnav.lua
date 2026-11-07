--[[--
Panel-by-panel navigation for comics and manga in paged documents.

The panels of a page are shown one at a time in a @{ui.widget.panelviewer|PanelViewer}, in the panel
reading direction: by default, the page turn direction (right to left with RTL page turning, as for
manga). The last panel of a page is followed by the first one of the next page, and a page without
panels is shown whole.

By default, a panel is shown over the page, which stays visible around it: enlarged by the
panel_overlay_zoom setting, centred on the screen, and framed on the page. Otherwise (panel_view_mode
"fullscreen"), it is shown alone, as big as the screen allows, and wide panels can be rotated.

Navigation starts with a long-press on a panel when panel zoom is allowed, or with the "Enter panel
navigation", "Next panel" and "Previous panel" actions. It ends when the viewer is closed, on the
page of the last panel shown.

Panels are only detected for the pages shown in the viewer (or with the debug panel boxes). Pages
that are not made of panels (text, title and illustration pages, splash pages) have none: they are
shown whole, see KOPTContext:getAllPanelsFromPage().

@module readerpanelnav
--]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local PanelViewer = require("ui/widget/panelviewer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local dbg = require("dbg")
local logger = require("logger")
local optionsutil = require("ui/data/optionsutil")
local _ = require("gettext")
local N_ = _.ngettext
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template

local ReaderPanelNav = WidgetContainer:extend{
    name = "readerpanelnav",
    -- The panels of panels_page sorted in panels_direction, see getPanelsForPage()
    current_page_panels = nil,
    panels_page = nil,
    panels_direction = nil,
    current_panel_index = 0, -- of the last panel shown, in current_page_panels: 0 if none (or the whole page)
    _panel_viewer = nil, -- the PanelViewer, while navigating

    -- Settings
    panel_view_mode = "overlay", -- "overlay": over the page, "fullscreen": alone, see getDefaultViewMode()
    panel_overlay_zoom = 1.5, -- over the page: size of the panel to its size on the page, or "fit" the screen
    panel_direction = nil, -- one of the keys of direction_settings, nil to follow the page turn direction
    panel_rotate_wide = true, -- fullscreen: rotate wide panels to show them bigger, see isWidePanel()
    highlight_current_panel = false, -- frame the last panel shown, on the page
    show_panel_boxes = false, -- debug: frame all the panels detected on the page, with their number

    -- Each direction defines: primary axis (h/v), primary order (+/-), secondary order (+/-)
    -- h = horizontal first (row mode), v = vertical first (column mode)
    -- + = increasing (left-to-right or top-to-bottom), - = decreasing (right-to-left or bottom-to-top)
    direction_settings = {
        LRTB = { primary = "h", primary_order = 1,  secondary_order = 1  }, -- Left-Right, Top-Bottom
        LRBT = { primary = "h", primary_order = 1,  secondary_order = -1 }, -- Left-Right, Bottom-Top
        RLTB = { primary = "h", primary_order = -1, secondary_order = 1  }, -- Right-Left, Top-Bottom
        RLBT = { primary = "h", primary_order = -1, secondary_order = -1 }, -- Right-Left, Bottom-Top
        TBLR = { primary = "v", primary_order = 1,  secondary_order = 1  }, -- Top-Bottom, Left-Right
        TBRL = { primary = "v", primary_order = 1,  secondary_order = -1 }, -- Top-Bottom, Right-Left
        BTLR = { primary = "v", primary_order = -1, secondary_order = 1  }, -- Bottom-Top, Left-Right
        BTRL = { primary = "v", primary_order = -1, secondary_order = -1 }, -- Bottom-Top, Right-Left
    },
}

function ReaderPanelNav:onDispatcherRegisterActions()
    Dispatcher:registerAction("goto_next_panel",
        {category="none", event="GotoNextPanel", title=_("Go to next panel"), paging=true})
    Dispatcher:registerAction("goto_prev_panel",
        {category="none", event="GotoPrevPanel", title=_("Go to previous panel"), paging=true})
    Dispatcher:registerAction("enter_panel_nav_mode",
        {category="none", event="EnterPanelNavMode", title=_("Enter panel navigation mode"), paging=true})
end

function ReaderPanelNav:init()
    self:onDispatcherRegisterActions()
    -- to draw the panel boxes
    self.view:registerViewModule("panel_nav", self)
end

local function isViewMode(mode)
    return mode == "overlay" or mode == "fullscreen"
end

local function isOverlayZoom(zoom)
    return zoom == "fit" or type(zoom) == "number" and zoom > 0
end

--[[--
Get how the panels of newly opened books are shown.

@treturn string "overlay" (the default) or "fullscreen", the panel_view_mode setting
--]]
function ReaderPanelNav.getDefaultViewMode()
    local mode = G_reader_settings:readSetting("panel_view_mode")
    return isViewMode(mode) and mode or "overlay"
end

--[[--
Get the zoom of the panels shown over the page, for newly opened books.

@return the panel_overlay_zoom setting: the size of a panel to its size on the page (1.5 by
default), or "fit" to show it as big as fits on the screen
--]]
function ReaderPanelNav.getDefaultOverlayZoom()
    local zoom = G_reader_settings:readSetting("panel_overlay_zoom")
    return isOverlayZoom(zoom) and zoom or 1.5
end

function ReaderPanelNav:onReadSettings(config)
    local view_mode = config:readSetting("panel_view_mode")
    self.panel_view_mode = isViewMode(view_mode) and view_mode or self.getDefaultViewMode()
    local overlay_zoom = config:readSetting("panel_overlay_zoom")
    self.panel_overlay_zoom = isOverlayZoom(overlay_zoom) and overlay_zoom or self.getDefaultOverlayZoom()
    self.panel_direction = config:readSetting("panel_direction") or G_reader_settings:readSetting("panel_direction")
    if not self.direction_settings[self.panel_direction] then
        self.panel_direction = nil
    end
    if config:has("panel_rotate_wide") then
        self.panel_rotate_wide = config:isTrue("panel_rotate_wide")
    else
        self.panel_rotate_wide = G_reader_settings:nilOrTrue("panel_rotate_wide")
    end
    if config:has("highlight_current_panel") then
        self.highlight_current_panel = config:isTrue("highlight_current_panel")
    else
        self.highlight_current_panel = G_reader_settings:isTrue("highlight_current_panel")
    end
    if config:has("show_panel_boxes") then
        self.show_panel_boxes = config:isTrue("show_panel_boxes")
    else
        self.show_panel_boxes = G_reader_settings:isTrue("show_panel_boxes")
    end
end

-- The book only keeps the settings that differ from the defaults for newly opened books
local function saveSettingIfNotDefault(doc_settings, key, value, default)
    if value ~= nil and value ~= default then
        doc_settings:saveSetting(key, value)
    else
        doc_settings:delSetting(key)
    end
end

function ReaderPanelNav:onSaveSettings()
    local doc_settings = self.ui.doc_settings
    saveSettingIfNotDefault(doc_settings, "panel_view_mode", self.panel_view_mode, self.getDefaultViewMode())
    saveSettingIfNotDefault(doc_settings, "panel_overlay_zoom", self.panel_overlay_zoom, self.getDefaultOverlayZoom())
    -- nil, following the page turn direction, is never saved
    saveSettingIfNotDefault(doc_settings, "panel_direction", self.panel_direction,
        G_reader_settings:readSetting("panel_direction"))
    saveSettingIfNotDefault(doc_settings, "panel_rotate_wide", self.panel_rotate_wide,
        G_reader_settings:nilOrTrue("panel_rotate_wide"))
    saveSettingIfNotDefault(doc_settings, "highlight_current_panel", self.highlight_current_panel,
        G_reader_settings:isTrue("highlight_current_panel"))
    saveSettingIfNotDefault(doc_settings, "show_panel_boxes", self.show_panel_boxes,
        G_reader_settings:isTrue("show_panel_boxes"))
end

--[[--
Get the panel reading direction.

@treturn string Direction code: the panel_direction setting, or else RLTB with RTL page turning
(page turns inverted, or not inverted with a mirrored UI, as in ReaderView:getTapZones()), LRTB otherwise
--]]
function ReaderPanelNav:getPanelDirection()
    local rtl_page_turning = self.view.inverse_reading_order and true or false
    if BD.mirroredUILayout() then
        rtl_page_turning = not rtl_page_turning
    end
    return self.panel_direction or (rtl_page_turning and "RLTB" or "LRTB")
end

--[[--
Set panel reading direction.

@param direction string Direction code (LRTB, LRBT, RLTB, RLBT, TBLR, TBRL, BTLR, BTRL), or nil to follow the page turn direction
--]]
function ReaderPanelNav:setPanelDirection(direction)
    if direction == nil or self.direction_settings[direction] then
        self.panel_direction = direction
        -- the panels get sorted again when needed, see getPanelsForPage()
        if self.show_panel_boxes or self.highlight_current_panel then
            UIManager:setDirty(self.view.dialog, "ui")
        end
    end
end

--[[--
Get the label of a direction code, the same as for the zoom direction option.

@param direction string Direction code
@treturn string Label, or the code itself if unknown
--]]
function ReaderPanelNav:getDirectionDescription(direction)
    return optionsutil.zoom_direction_labels[direction] or direction
end

--[[--
Group panels into rows, in left to right, top to bottom order.

Panels are taken top to bottom, then left to right. A panel that is not left of the
previous one joins the current row if it overlaps it vertically. A panel back on the
left joins it only if it fits within its vertical extent, so that a tall panel can span
several rows of smaller ones; otherwise it starts a new row. A panel with no other panel
ending further right at some height doesn't extend the vertical extent of the row it joins.

@param panels non-empty array of panel rectangles {x, y, w, h}
@treturn table array of rows {start_y, end_y, panels}, with the panels of each row sorted left to right
--]]
function ReaderPanelNav:sortLRTB(panels)
    local POS_THRESHOLD = 5 -- positions closer than this are considered equal
    local BUCKET_SIZE = 8   -- height of the horizontal bands used to find the rightmost panels

    -- a panel is rightmost if no other panel ends further right in one of the bands it spans
    local rightmost_by_bucket = {}
    for _, panel in ipairs(panels) do
        local panel_right = panel.x + panel.w
        local start_bucket = math.floor(panel.y / BUCKET_SIZE)
        local end_bucket = math.floor((panel.y + panel.h) / BUCKET_SIZE)

        for bucket = start_bucket, end_bucket do
            if not rightmost_by_bucket[bucket] or panel_right > rightmost_by_bucket[bucket].right_edge then
                rightmost_by_bucket[bucket] = { panel = panel, right_edge = panel_right }
            end
        end
    end
    local is_rightmost = {}
    for _, info in pairs(rightmost_by_bucket) do
        is_rightmost[info.panel] = true
    end

    local sorted = {}
    for i, p in ipairs(panels) do
        sorted[i] = p
    end
    table.sort(sorted, function(a, b)
        if math.abs(a.y - b.y) > POS_THRESHOLD then
            return a.y < b.y
        else
            return a.x < b.x
        end
    end)

    local rows = {}
    local current_row = nil
    local prev_x = -math.huge

    for _, panel in ipairs(sorted) do
        local p_top = panel.y
        local p_bottom = panel.y + panel.h
        local wrapped_left = panel.x < prev_x - POS_THRESHOLD

        if current_row == nil then
            current_row = {
                start_y = p_top,
                end_y = p_bottom,
                panels = { panel },
            }
        elseif wrapped_left then
            local fits_in_current_row = p_top >= current_row.start_y - POS_THRESHOLD and
                                        p_bottom <= current_row.end_y + POS_THRESHOLD

            if fits_in_current_row then
                table.insert(current_row.panels, panel)
                if not is_rightmost[panel] then
                    current_row.start_y = math.min(current_row.start_y, p_top)
                    current_row.end_y = math.max(current_row.end_y, p_bottom)
                end
            else
                table.insert(rows, current_row)
                current_row = {
                    start_y = p_top,
                    end_y = p_bottom,
                    panels = { panel },
                }
            end
        else
            local overlap_start = math.max(p_top, current_row.start_y)
            local overlap_end = math.min(p_bottom, current_row.end_y)
            local has_overlap = overlap_end > overlap_start

            if has_overlap then
                table.insert(current_row.panels, panel)
                if not is_rightmost[panel] then
                    current_row.start_y = math.min(current_row.start_y, p_top)
                    current_row.end_y = math.max(current_row.end_y, p_bottom)
                end
            else
                table.insert(rows, current_row)
                current_row = {
                    start_y = p_top,
                    end_y = p_bottom,
                    panels = { panel },
                }
            end
        end

        prev_x = panel.x
    end
    if current_row then
        table.insert(rows, current_row)
    end

    for _, row in ipairs(rows) do
        table.sort(row.panels, function(a, b)
            if math.abs(a.x - b.x) > POS_THRESHOLD then
                return a.x < b.x
            else
                return a.y < b.y
            end
        end)
    end

    return rows
end

--[[--
Sort panels by reading direction using coordinate transformation.

Transforms all coordinates to LRTB-equivalent, sorts using sortLRTB,
then maps back to original panels with row/col assigned.

On a double-page spread (a page wider than high) with each panel on one of its halves, the panels
of one half come before those of the other: the right half first when reading from right to left.

@param panels array of panel rectangles {x, y, w, h}
@param direction string Direction code, by default the panel reading direction
@param[opt] page_size size {w, h} of the page
@treturn table sorted array of panels with row/col fields added, or nil if no panels
--]]
function ReaderPanelNav:sortPanelsByReadingDirection(panels, direction, page_size)
    if not panels or #panels == 0 then return end

    direction = direction or self:getPanelDirection()
    local primary, secondary = direction:sub(1, 2), direction:sub(3, 4)

    if page_size and page_size.w > page_size.h then
        local middle, margin = page_size.w / 2, page_size.w * 0.02
        local left, right = {}, {}
        for _, p in ipairs(panels) do
            if p.x + p.w <= middle + margin then
                table.insert(left, p)
            elseif p.x >= middle - margin then
                table.insert(right, p)
            else -- across both pages
                left = nil
                break
            end
        end
        if left and #left > 0 and #right > 0 then
            local rtl = primary == "RL" or secondary == "RL"
            local sorted = self:sortPanelsByReadingDirection(rtl and right or left, direction)
            for _, p in ipairs(self:sortPanelsByReadingDirection(rtl and left or right, direction)) do
                table.insert(sorted, p)
            end
            return sorted
        end
    end
    local is_row_first = (primary == "LR" or primary == "RL")

    -- transform the coordinates so that the panels can be sorted as LRTB
    local transformed = {}
    for i, p in ipairs(panels) do
        local tp = { x = p.x, y = p.y, w = p.w, h = p.h, ref = p }

        -- Transform X (if Right-to-Left)
        if (is_row_first and primary == "RL") or (not is_row_first and secondary == "RL") then
            tp.x = -p.x - p.w
        end
        -- Transform Y (if Bottom-to-Top)
        if (is_row_first and secondary == "BT") or (not is_row_first and primary == "BT") then
            tp.y = -p.y - p.h
        end
        -- Swap axes for column-first (TB/BT primary) to treat columns as "rows"
        if not is_row_first then
            tp.x, tp.y = tp.y, tp.x
            tp.w, tp.h = tp.h, tp.w
        end
        transformed[i] = tp
    end

    local rows = self:sortLRTB(transformed)

    -- back to the original panels, with their row and column
    local sorted = {}
    for r_idx, row in ipairs(rows) do
        for c_idx, tp in ipairs(row.panels) do
            if is_row_first then
                tp.ref.row, tp.ref.col = r_idx, c_idx
            else
                tp.ref.col, tp.ref.row = r_idx, c_idx
            end
            table.insert(sorted, tp.ref)
        end
    end

    logger.dbg("ReaderPanelNav: sorted order (direction:", direction, "):")
    for i, p in ipairs(sorted) do
        logger.dbg("  ", i, ": (", p.x, ",", p.y, ")-(", p.x + p.w, ",", p.y + p.h, ") row=", p.row, "col=", p.col)
    end

    return sorted
end

--[[--
Clip panels to ensure they are within page boundaries.
Panels that extend outside the page are clipped to the page bounds.
Panels that are completely outside the page are removed.

@param panels array of panel rectangles {x, y, w, h}
@param page_width width of the page
@param page_height height of the page
@treturn table array of clipped panels, or nil if no panels
--]]
function ReaderPanelNav:clipPanelsToPage(panels, page_width, page_height)
    if not panels or #panels == 0 then
        return nil
    end

    local clipped = {}

    for _, panel in ipairs(panels) do
        local clipped_left = math.max(0, panel.x)
        local clipped_top = math.max(0, panel.y)
        local clipped_right = math.min(page_width, panel.x + panel.w)
        local clipped_bottom = math.min(page_height, panel.y + panel.h)
        local clipped_w = clipped_right - clipped_left
        local clipped_h = clipped_bottom - clipped_top
        -- panels outside of the page are dropped
        if clipped_w > 0 and clipped_h > 0 then
            table.insert(clipped, {
                x = clipped_left,
                y = clipped_top,
                w = clipped_w,
                h = clipped_h,
            })
        end
    end

    local removed = #panels - #clipped
    if removed > 0 then
        logger.dbg("ReaderPanelNav: clipped/removed", removed, "panels outside page bounds")
    end
    if #clipped > 0 then
        return clipped
    end
end

--[[--
Get the panels of a page, sorted in the panel reading direction.

They are detected the first time they are needed, and kept until the page changes. Panels within
others (insets) are kept: the detection only gives the panels to show.

@param pageno page number
@treturn table array of panel rectangles {x, y, w, h} in native page coordinates, with their row
and col, or nil if there are none (or the document has no panel detection)
--]]
function ReaderPanelNav:getPanelsForPage(pageno)
    if not self.ui.document.getAllPanelsFromPage then
        return nil
    end
    local direction = self:getPanelDirection()
    if self.panels_page == pageno and self.panels_direction == direction then
        return self.current_page_panels
    end

    local panels = self.ui.document:getAllPanelsFromPage(pageno)
    local page_size = self.ui.document:getNativePageDimensions(pageno)
    if panels and page_size then
        panels = self:clipPanelsToPage(panels, page_size.w, page_size.h)
    end
    if panels then
        panels = self:sortPanelsByReadingDirection(panels, direction, page_size)
    end
    self.current_page_panels = panels
    self.panels_page = pageno
    self.panels_direction = direction
    -- an index in the previous panels means nothing now
    self.current_panel_index = 0
    return panels
end

--[[--
Get the panels of the current page, sorted in the panel reading direction.

@treturn table array of panel rectangles, or nil, see getPanelsForPage()
--]]
function ReaderPanelNav:getPanelsForCurrentPage()
    return self:getPanelsForPage(self.ui.paging.current_page)
end

--[[--
Check whether a panel is wide, so that it is shown bigger rotated.

It is when its orientation differs from the screen's, and its aspect ratio is at least the screen's:
then, rotated, it is as much bigger as the screen is longer than wide. (Most panels in a row of two
are only a bit wider than tall: rotated, they would be only that bit bigger.)

@param panel panel rectangle {x, y, w, h}
@param area size {w, h} the panel is shown in (default: the screen)
@treturn bool
--]]
function ReaderPanelNav:isWidePanel(panel, area)
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    if area then
        screen_w, screen_h = area.w, area.h
    end
    if (screen_w > screen_h) == (panel.w > panel.h) then
        return false
    end
    local screen_ratio = math.max(screen_w, screen_h) / math.min(screen_w, screen_h)
    local panel_ratio = math.max(panel.w, panel.h) / math.min(panel.w, panel.h)
    return screen_ratio > 1 and panel_ratio >= screen_ratio
end

--[[--
Get the tap zones going to the next and previous panel in the viewer.

They are the page turn tap zones, unless one-handed navigation is on (the panel_nav_one_hand
setting: "left" or "right"): then a full-height strip on the side of the hand holding the device,
as wide as the backward page turn tap zone (from 10 to 50 % of the screen width), goes back, and
the rest of the screen forward. They are not mirrored with the reading direction (nor with the UI):
the hand is not related to it.

@treturn table forward zone {ratio_x, ratio_y, ratio_w, ratio_h}
@treturn table backward zone
--]]
function ReaderPanelNav:getTapZones()
    local hand = G_reader_settings:readSetting("panel_nav_one_hand")
    if hand ~= "left" and hand ~= "right" then
        return self.view:getTapZones()
    end
    -- the backward tap zone size, as ReaderView:getTapZones() and the page turns menu use it
    local strip_w = G_defaults:readSetting("DTAP_ZONE_BACKWARD").w
    if G_reader_settings:readSetting("page_turns_tap_zones", "default") ~= "default" then
        strip_w = G_reader_settings:readSetting("page_turns_tap_zone_backward_size_ratio", strip_w)
    end
    -- both ways remain within reach of the thumb
    strip_w = math.max(0.1, math.min(strip_w, 0.5))
    if hand == "left" then
        return { ratio_x = strip_w, ratio_y = 0, ratio_w = 1 - strip_w, ratio_h = 1 },
               { ratio_x = 0, ratio_y = 0, ratio_w = strip_w, ratio_h = 1 }
    end
    return { ratio_x = 0, ratio_y = 0, ratio_w = 1 - strip_w, ratio_h = 1 },
           { ratio_x = 1 - strip_w, ratio_y = 0, ratio_w = strip_w, ratio_h = 1 }
end

--[[--
Show a panel of the current page in the viewer, opening it if needed.

Over the page (panel_view_mode "overlay"), the panel is rendered at panel_overlay_zoom times its
size on the page, at most as big as fits above the footer, and the viewer frames it where it is on
the page. Fullscreen, it is rendered as big as fits above the footer, rotated if it is wide and
panel_rotate_wide is on. The view stays the same until the viewer closes.

@param panel panel rectangle {x, y, w, h}, in native page coordinates
--]]
function ReaderPanelNav:showPanel(panel)
    dbg.dassert(panel, "showPanel called with nil panel")
    local viewer = self._panel_viewer
    -- (the view and the footer don't change while the viewer is open)
    local overlay
    if viewer then
        overlay = viewer.overlay
    else
        overlay = self.panel_view_mode == "overlay"
    end
    local footer = self.view.footer
    local footer_visible = self.view.footer_visible
    -- the height at the bottom of the screen left to the footer
    local bottom_height
    if viewer then
        bottom_height = overlay and viewer.overlay_bottom_height or viewer.reserved_bottom_height
    elseif overlay then
        -- over the page, the footer stays as it is, even if it overlaps the page
        bottom_height = footer_visible and footer:getHeight() or 0
    else
        -- fullscreen, it stays at the bottom of the screen, over the panel if it overlaps the page
        bottom_height = footer_visible and not footer.settings.reclaim_height and footer:getHeight() or 0
    end
    local pageno = self.ui.paging.current_page
    local image, rotated, panel_rect
    if overlay then
        -- its size on the page, enlarged, but no bigger than fits on the screen; not rotated
        local max_size = PanelViewer.getOverlayMaxSize(bottom_height)
        if self.panel_overlay_zoom ~= "fit" then
            local zoom = self.view.state.zoom * self.panel_overlay_zoom
            max_size.w = math.min(max_size.w, panel.w * zoom)
            max_size.h = math.min(max_size.h, panel.h * zoom)
        end
        image, rotated = self.ui.document:drawPagePart(pageno, panel, 0, false, max_size)
        -- to frame it on the page
        panel_rect = self.view:pageToScreenTransform(pageno, panel)
    else
        -- render the panel at the size it is shown, so that the viewer doesn't have to scale it again
        local max_size = { w = Screen:getWidth(), h = Screen:getHeight() - bottom_height }
        local rotate = self.panel_rotate_wide and self:isWidePanel(panel, max_size)
        image, rotated = self.ui.document:drawPagePart(pageno, panel, 0, rotate, max_size)
    end
    if not image then
        logger.dbg("ReaderPanelNav: drawPagePart returned nil image")
        UIManager:show(InfoMessage:new{
            text = _("Could not render panel."),
            timeout = 2,
        })
        return
    end
    -- The viewer frees the image it is given: a copy, as the tile is the document cache's, which may
    -- drop and free it while it is shown (e.g., DocCache:memoryPressureCheck() on low memory)
    image = image:copy()
    if viewer then
        viewer:setImage(image, rotated, panel_rect)
        return
    end

    local forward_zone, backward_zone = self:getTapZones()
    self._panel_viewer = PanelViewer:new{
        image = image,
        rotated = rotated,
        overlay = overlay,
        panel_rect = panel_rect,
        overlay_bottom_height = overlay and bottom_height or 0,
        paint_background_callback = overlay and function(bb, x, y)
            -- the page as the reader shows it, with its footer
            self.view:paintTo(bb, x, y)
        end or nil,
        reserved_bottom_height = not overlay and bottom_height or 0,
        paint_bottom_callback = not overlay and footer_visible and function(bb, x, y)
            -- it is up to date: ReaderFooter updates its text on page changes
            footer:paintTo(bb, x, y)
        end or nil,
        forward_zone = forward_zone,
        backward_zone = backward_zone,
        inverse_reading_order = self.view.inverse_reading_order,
        next_callback = function() self:onGotoNextPanel() end,
        prev_callback = function() self:onGotoPrevPanel() end,
        close_callback = function() self._panel_viewer = nil end,
        rotation_callback = function(mode) self:rotateAndShowPanel(mode) end,
    }
    UIManager:show(self._panel_viewer)
end

--[[--
Show a panel of the current page, or the whole page if it has no panels.

@param index index of the panel, counted from the last one if negative (-1 is the last one)
--]]
function ReaderPanelNav:showPanelIndex(index)
    local pageno = self.ui.paging.current_page
    local panels = self:getPanelsForPage(pageno)
    if panels then
        if index < 0 then
            index = #panels + 1 + index
        end
        self.current_panel_index = math.max(1, math.min(index, #panels))
        logger.dbg("ReaderPanelNav: showing panel", self.current_panel_index, "of", #panels, "on page", pageno)
        self:showPanel(panels[self.current_panel_index])
    else
        self.current_panel_index = 0
        logger.dbg("ReaderPanelNav: no panels, showing page", pageno)
        local page_size = self.ui.document:getNativePageDimensions(pageno)
        self:showPanel({ x = 0, y = 0, w = page_size.w, h = page_size.h })
    end
end

--[[--
Start panel navigation with the panel at a position, as on a long-press.

On a page without panels, navigation starts with the whole page, as it is shown when navigating.

@param pos position {x, y, page} in native page coordinates, as from ReaderView:screenToPageTransform()
@treturn bool true if a panel contains it (or the page has no panels), and it is shown
--]]
function ReaderPanelNav:showPanelAt(pos)
    if not self.ui.document.getAllPanelsFromPage then
        return false
    end
    local panels = self:getPanelsForPage(pos.page)
    local index
    if panels then
        for i, panel in ipairs(panels) do
            if pos.x >= panel.x and pos.x <= panel.x + panel.w and
               pos.y >= panel.y and pos.y <= panel.y + panel.h then
                index = i
                break
            end
        end
        if not index then
            return false
        end
    end
    if pos.page ~= self.ui.paging.current_page then
        -- in scroll mode: the panel is on the next page shown
        self.ui:handleEvent(Event:new("GotoPage", pos.page))
    end
    self:showPanelIndex(index or 1)
    return true
end

--[[--
Go to the next or previous page, and show its first or last panel.

At the end or start of the document, notify and stay on the current panel.

@param direction 1 for the next page, -1 for the previous one
--]]
function ReaderPanelNav:turnPage(direction)
    local pageno = self.ui.paging.current_page
    local new_pageno
    if direction > 0 then
        new_pageno = self.ui.document:getNextPage(pageno)
    else
        new_pageno = self.ui.document:getPrevPage(pageno)
    end
    if new_pageno == 0 then
        Notification:notify(direction > 0 and _("This is the last page.") or _("This is the first page."),
            Notification.SOURCE_ALWAYS_SHOW)
        return
    end
    -- rather than GotoViewRel, which can scroll within the page, or end the document
    self.ui:handleEvent(Event:new("GotoPage", new_pageno))
    self:showPanelIndex(direction > 0 and 1 or -1)
    -- Rendering and detecting the panels of the new page takes a while on slow devices: a tap made
    -- meanwhile (tapping again, as nothing seems to happen) would skip its first panel. Discard
    -- them, as ReaderRolling does after a re-rendering.
    Input:inhibitInputUntil(0.2)
end

--[[--
Show the next panel, of the next page after the last one.

Without the viewer, start panel navigation with the first panel of the current page.
--]]
function ReaderPanelNav:onGotoNextPanel()
    if not self._panel_viewer then
        if not self.ui.document.getAllPanelsFromPage then return end
        self:showPanelIndex(1)
        return true
    end
    local panels = self:getPanelsForCurrentPage()
    if panels and self.current_panel_index < #panels then
        self:showPanelIndex(self.current_panel_index + 1)
    else
        self:turnPage(1)
    end
    return true
end

--[[--
Show the previous panel, of the previous page before the first one.

Without the viewer, start panel navigation with the last panel of the current page.
--]]
function ReaderPanelNav:onGotoPrevPanel()
    if not self._panel_viewer then
        if not self.ui.document.getAllPanelsFromPage then return end
        self:showPanelIndex(-1)
        return true
    end
    if self.current_panel_index > 1 then
        self:showPanelIndex(self.current_panel_index - 1)
    else
        self:turnPage(-1)
    end
    return true
end

--[[--
Start panel navigation, with the last panel shown on the current page if any, or its first one.
--]]
function ReaderPanelNav:onEnterPanelNavMode()
    if not self._panel_viewer then
        if not self.ui.document.getAllPanelsFromPage then return end
        -- (detecting the panels again forgets the last one shown)
        self:getPanelsForCurrentPage()
        self:showPanelIndex(math.max(self.current_panel_index, 1))
    end
    return true
end

--[[--
Rotate the screen, as asked from the viewer, which has closed itself: show the panel again.

@param[opt] mode rotation mode, nil when the screen has already been resized (the reader gets the
SetDimensions event after the viewer)
--]]
function ReaderPanelNav:rotateAndShowPanel(mode)
    if mode then
        self.view:onSetRotationMode(mode)
    end
    UIManager:nextTick(function()
        self:showPanelIndex(math.max(self.current_panel_index, 1))
    end)
end

--[[--
Toggle panel box visualization for debugging.
--]]
function ReaderPanelNav:onToggleShowPanelBoxes()
    self.show_panel_boxes = not self.show_panel_boxes

    if self.show_panel_boxes then
        local panels = self:getPanelsForCurrentPage()
        local panel_count = panels and #panels or 0
        UIManager:show(InfoMessage:new{
            text = _("Panel boxes visible.") .. "\n" ..
                T(N_("Detected 1 panel on this page.", "Detected %1 panels on this page.", panel_count), panel_count),
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Panel boxes hidden."),
            timeout = 2,
        })
    end

    -- Redraw the page
    UIManager:setDirty(self.view.dialog, "ui")
    return true
end

--[[--
Paint panel bounding boxes on the view.

This is called by ReaderView as a registered view module.

@param bb BlitBuffer to paint to
@param x X offset
@param y Y offset
--]]
function ReaderPanelNav:paintTo(bb, x, y)
    local panels
    if self.show_panel_boxes then
        panels = self:getPanelsForCurrentPage()
    elseif self.highlight_current_panel and self.current_panel_index > 0
            and self.panels_page == self.ui.paging.current_page then
        -- not detecting the panels for that: there is a current one only once they are
        panels = self.current_page_panels
    end
    if not panels then
        return
    end

    local box_color = Blitbuffer.ColorRGB24(0x00, 0xCC, 0x00)  -- green for all the panels
    local current_box_color = PanelViewer.getPanelFrameColor()  -- red (black in grayscale) for the current one
    local number_font = Font:getFace("infofont", 14)

    for i, panel in ipairs(panels) do
        local rect = self.view:pageToScreenTransform(self.panels_page, panel)
        local is_current = i == self.current_panel_index
        -- without show_panel_boxes, only the current panel is highlighted
        if rect and (self.show_panel_boxes or is_current) then
            local color = is_current and current_box_color or box_color
            -- as the viewer frames the current panel, over the page
            PanelViewer.paintPanelFrame(bb, rect, color)

            -- debug: panel number, in white on the box color
            if self.show_panel_boxes then
                local num_text = tostring(i)
                local text_size = RenderText:sizeUtf8Text(0, Screen:getWidth(), number_font, num_text)
                local num_w = text_size.x + 8
                local num_h = number_font.size + 4
                bb:paintRectRGB32(rect.x + 4, rect.y + 4, num_w, num_h, color)
                RenderText:renderUtf8Text(bb, rect.x + 8, rect.y + 4 + number_font.size - 2, number_font, num_text, false, false, Blitbuffer.COLOR_WHITE)
            end
        end
    end
end

--[[--
Forget the panels of the previous page on page change.
--]]
function ReaderPanelNav:onPageUpdate(new_page_no)
    if self.panels_page ~= new_page_no then
        self.current_page_panels = nil
        self.panels_page = nil
        self.panels_direction = nil
        self.current_panel_index = 0
    end
end

function ReaderPanelNav:onCloseDocument()
    if self._panel_viewer then
        UIManager:close(self._panel_viewer)
    end
    self.current_page_panels = nil
    self.panels_page = nil
    self.panels_direction = nil
end

return ReaderPanelNav
