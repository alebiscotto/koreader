--[[--
Panel-by-panel navigation for comics and manga in paged documents.

The panels detected on the page are visited in the panel reading direction.

@module readerpanelnav
--]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local optionsutil = require("ui/data/optionsutil")
local _ = require("gettext")
local Screen = Device.screen

local ReaderPanelNav = InputContainer:extend{
    name = "readerpanelnav",
    -- Panel navigation state
    panel_nav_enabled = false,
    current_page_panels = nil,  -- cached panels for current page
    current_panel_index = 0,    -- 0 means no panel selected (full page view)
    panels_page = nil,          -- page number for cached panels
    _panel_viewer = nil,        -- current ImageViewer widget (reused for performance)

    -- Visualization options
    highlight_current_panel = false, -- highlight only the current panel
    show_panel_boxes = false,   -- show bounding boxes around all detected panels (debug)

    panel_direction = "LRTB", -- one of the keys of direction_settings

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
    -- Register as view module to draw panel boxes
    self.view:registerViewModule("panel_nav", self)
end

function ReaderPanelNav:onReadSettings(config)
    if config:has("panel_nav_enabled") then
        self.panel_nav_enabled = config:isTrue("panel_nav_enabled")
    else
        self.panel_nav_enabled = G_reader_settings:isTrue("panel_nav_enabled")
    end
    self.panel_direction = config:readSetting("panel_direction")
        or G_reader_settings:readSetting("panel_direction")
        or "LRTB"
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

function ReaderPanelNav:onSaveSettings()
    self.ui.doc_settings:saveSetting("panel_nav_enabled", self.panel_nav_enabled)
    self.ui.doc_settings:saveSetting("panel_direction", self.panel_direction)
    self.ui.doc_settings:saveSetting("highlight_current_panel", self.highlight_current_panel)
    self.ui.doc_settings:saveSetting("show_panel_boxes", self.show_panel_boxes)
end

--[[--
Set panel reading direction.

@param direction string Direction code (LRTB, LRBT, RLTB, RLBT, TBLR, TBRL, BTLR, BTRL)
--]]
function ReaderPanelNav:setPanelDirection(direction)
    if self.direction_settings[direction] then
        self.panel_direction = direction
        -- Invalidate cached panels when direction changes
        self.current_page_panels = nil
        self.panels_page = nil
        self.current_panel_index = 0
        -- Refresh display if showing panel boxes
        if self.show_panel_boxes then
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

@param panels array of panel rectangles {x, y, w, h}
@treturn table sorted array of panels with row/col fields added, or nil if no panels
--]]
function ReaderPanelNav:sortPanelsByReadingDirection(panels)
    if not panels or #panels == 0 then return end

    local direction = self.panel_direction or "LRTB"
    local primary, secondary = direction:sub(1, 2), direction:sub(3, 4)
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
Check if panel A is completely contained within panel B.

@param a panel rectangle {x, y, w, h}
@param b panel rectangle {x, y, w, h}
@treturn bool true if A is completely inside B
--]]
function ReaderPanelNav:isPanelContainedIn(a, b)
    return a.x >= b.x and a.x + a.w <= b.x + b.w and
           a.y >= b.y and a.y + a.h <= b.y + b.h
end

--[[--
Filter out panels that are completely contained within other panels.
Keeps only the outermost panels.

@param panels array of panel rectangles {x, y, w, h}
@treturn table filtered array of panels, or nil if no panels
--]]
function ReaderPanelNav:filterNestedPanels(panels)
    if not panels or #panels == 0 then
        return
    end
    if #panels == 1 then
        return panels
    end

    local filtered = {}

    for i, panel_a in ipairs(panels) do
        local is_nested = false

        for j, panel_b in ipairs(panels) do
            if i ~= j then
                -- equal panels are not nested
                if self:isPanelContainedIn(panel_a, panel_b) and
                   not self:isPanelContainedIn(panel_b, panel_a) then
                    is_nested = true
                    break
                end
            end
        end

        if not is_nested then
            table.insert(filtered, panel_a)
        end
    end

    logger.dbg("ReaderPanelNav: filtered", #panels - #filtered, "nested panels, keeping", #filtered)
    return filtered
end

--[[--
Calculate the intersection area of two panels.

@param a panel rectangle {x, y, w, h}
@param b panel rectangle {x, y, w, h}
@treturn number intersection area (0 if no overlap)
--]]
function ReaderPanelNav:getPanelIntersectionArea(a, b)
    local a_left, a_right = a.x, a.x + a.w
    local a_top, a_bottom = a.y, a.y + a.h
    local b_left, b_right = b.x, b.x + b.w
    local b_top, b_bottom = b.y, b.y + b.h

    local inter_left = math.max(a_left, b_left)
    local inter_right = math.min(a_right, b_right)
    local inter_top = math.max(a_top, b_top)
    local inter_bottom = math.min(a_bottom, b_bottom)

    local inter_width = inter_right - inter_left
    local inter_height = inter_bottom - inter_top

    if inter_width > 0 and inter_height > 0 then
        return inter_width * inter_height
    end
    return 0
end

--[[--
Merge two panels into their bounding box.

@param a panel rectangle {x, y, w, h}
@param b panel rectangle {x, y, w, h}
@treturn table merged panel rectangle {x, y, w, h}
--]]
function ReaderPanelNav:mergePanels(a, b)
    local left = math.min(a.x, b.x)
    local top = math.min(a.y, b.y)
    local right = math.max(a.x + a.w, b.x + b.w)
    local bottom = math.max(a.y + a.h, b.y + b.h)

    return {
        x = left,
        y = top,
        w = right - left,
        h = bottom - top,
    }
end

--[[--
Merge overlapping panels into single panels.
If two panels overlap significantly (> threshold of smaller panel's area),
they are merged into their bounding box.

@param panels array of panel rectangles {x, y, w, h}
@param overlap_threshold fraction of overlap required to merge (default 0.3 = 30%)
@treturn table array of merged panels, or nil if no panels
--]]
function ReaderPanelNav:mergeOverlappingPanels(panels, overlap_threshold)
    if not panels or #panels == 0 then
        return
    end
    if #panels == 1 then
        return panels
    end

    overlap_threshold = overlap_threshold or 0.3

    -- keep merging until no more merges happen
    local merged = true
    local result = {}
    for _, p in ipairs(panels) do
        table.insert(result, { x = p.x, y = p.y, w = p.w, h = p.h })
    end

    while merged do
        merged = false
        local new_result = {}
        local merged_indices = {}

        for i = 1, #result do
            if not merged_indices[i] then
                local current = result[i]

                for j = i + 1, #result do
                    if not merged_indices[j] then
                        local other = result[j]
                        local intersection = self:getPanelIntersectionArea(current, other)

                        if intersection > 0 then
                            local area_current = current.w * current.h
                            local area_other = other.w * other.h
                            local smaller_area = math.min(area_current, area_other)
                            if intersection / smaller_area >= overlap_threshold then
                                current = self:mergePanels(current, other)
                                merged_indices[j] = true
                                merged = true
                            end
                        end
                    end
                end

                table.insert(new_result, current)
            end
        end

        result = new_result
    end

    local merged_count = #panels - #result
    if merged_count > 0 then
        logger.dbg("ReaderPanelNav: merged", merged_count, "overlapping panels, now have", #result)
    end

    return result
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
Get panels for the current page, sorted by reading direction.

@treturn table array of sorted panels, or nil if no panels found
--]]
function ReaderPanelNav:getPanelsForCurrentPage()
    -- Check if document supports panel detection
    if not self.ui.document.getAllPanelsFromPage then
        return nil
    end

    local pageno = self.ui.paging.current_page

    -- Return cached panels if available for current page
    if self.current_page_panels and self.panels_page == pageno then
        return self.current_page_panels
    end

    local panels = self.ui.document:getAllPanelsFromPage(pageno)
    if panels then
        local page_size = self.ui.document:getNativePageDimensions(pageno)
        if page_size then
            panels = self:clipPanelsToPage(panels, page_size.w, page_size.h)
        end
    end
    -- merging and filtering never leave a page without panels
    if panels then
        panels = self:mergeOverlappingPanels(panels, 0.5)
        panels = self:filterNestedPanels(panels)
        panels = self:sortPanelsByReadingDirection(panels)
        self.current_panel_index = 0 -- full page view
    end
    self.current_page_panels = panels
    self.panels_page = pageno
    return panels
end

--[[--
Navigate to the next panel.

@treturn bool true if handled
--]]
function ReaderPanelNav:onGotoNextPanel()
    logger.dbg("ReaderPanelNav:onGotoNextPanel called, enabled:", self.panel_nav_enabled)

    if not self.panel_nav_enabled then
        return false
    end

    local panels = self:getPanelsForCurrentPage()
    logger.dbg("ReaderPanelNav: panels count:", panels and #panels or 0, "current index:", self.current_panel_index)

    if not panels then
        -- No panels on this page, go to next page
        logger.dbg("ReaderPanelNav: no panels, going to next page")
        self.ui:handleEvent(Event:new("GotoViewRel", 1))
        return true
    end

    if self.current_panel_index < #panels then
        -- Go to next panel
        self.current_panel_index = self.current_panel_index + 1
        logger.dbg("ReaderPanelNav: navigating to panel", self.current_panel_index)
        self:showPanel(panels[self.current_panel_index])
    else
        -- At last panel, go to next page
        logger.dbg("ReaderPanelNav: at last panel, going to next page")
        self.current_panel_index = 0
        self.current_page_panels = nil
        self.panels_page = nil
        self.ui:handleEvent(Event:new("GotoViewRel", 1))
    end

    return true
end

--[[--
Navigate to the previous panel.

@treturn bool true if handled
--]]
function ReaderPanelNav:onGotoPrevPanel()
    if not self.panel_nav_enabled then
        return false
    end

    local panels = self:getPanelsForCurrentPage()

    if self.current_panel_index > 1 then
        -- Go to previous panel
        self.current_panel_index = self.current_panel_index - 1
        self:showPanel(panels[self.current_panel_index])
    elseif self.current_panel_index == 1 then
        -- At first panel, show full page
        self.current_panel_index = 0
        self:showFullPage()
    else
        -- At full page view, go to previous page and show last panel
        self.current_page_panels = nil
        self.panels_page = nil
        self.ui:handleEvent(Event:new("GotoViewRel", -1))
        UIManager:nextTick(function()
            local new_panels = self:getPanelsForCurrentPage()
            if new_panels then
                self.current_panel_index = #new_panels
                self:showPanel(new_panels[self.current_panel_index])
            end
        end)
    end

    return true
end

--[[--
Show a specific panel in the ImageViewer.

@param panel panel rectangle {x, y, w, h}
--]]
function ReaderPanelNav:showPanel(panel)
    local dbg = require("dbg")
    dbg.dassert(panel, "showPanel called with nil panel")
    if not panel then return end

    logger.dbg("ReaderPanelNav: showPanel called with panel:", panel)

    local pageno = self.ui.paging.current_page
    logger.dbg("ReaderPanelNav: drawing panel from page", pageno)

    -- Make sure we have the drawPagePart method
    if not self.ui.document.drawPagePart then
        logger.dbg("ReaderPanelNav: document does not support drawPagePart")
        UIManager:show(InfoMessage:new{
            text = _("Panel zoom not supported for this document type."),
            timeout = 2,
        })
        return
    end

    local image, rotate = self.ui.document:drawPagePart(pageno, panel, 0)

    if image then
        -- If we already have an ImageViewer open, just update the image
        if self._panel_viewer then
            logger.dbg("ReaderPanelNav: reusing existing ImageViewer")
            -- Guard against updating while a repaint is in progress
            if self._panel_viewer._updating then
                logger.dbg("ReaderPanelNav: skipping update, already updating")
                return
            end
            self._panel_viewer._updating = true
            self._panel_viewer.image = image
            -- Immediately clean the image widget so any pending refresh uses new image
            self._panel_viewer:_clean_image_wg()
            -- Now trigger the update synchronously
            self._panel_viewer:update()
            self._panel_viewer._updating = false
            return
        end

        logger.dbg("ReaderPanelNav: creating new ImageViewer")
        local ImageViewer = require("ui/widget/imageviewer")

        -- Keep reference to self for callbacks
        local panelnav = self

        -- Calculate height to leave room for status bar (footer)
        local footer_height = 0
        if self.view.footer and self.view.footer_visible
           and not self.view.footer.settings.reclaim_height then
            footer_height = self.view.footer:getHeight()
        end
        local viewer_height = Screen:getHeight() - footer_height

        local imgviewer = ImageViewer:new{
            image = image,
            image_disposable = false, -- It's a TileCache item
            with_title_bar = false,
            fullscreen = true,
            rotated = rotate,
            height = viewer_height, -- Leave room for footer
        }

        -- Patch update() to use our custom height (leaving room for footer)
        -- This ensures buttons appear above the status bar
        local orig_update = imgviewer.update
        imgviewer.update = function(iv)
            -- Temporarily override height before update runs
            local saved_getHeight = Screen.getHeight
            Screen.getHeight = function() return viewer_height end
            orig_update(iv)
            Screen.getHeight = saved_getHeight
            -- Also ensure region is correct
            iv.region.h = viewer_height
        end

        -- Paint footer on top of ImageViewer if visible
        if footer_height > 0 then
            local orig_paintTo = imgviewer.paintTo
            local last_footer_page = pageno  -- Track which page footer was last updated for
            imgviewer.paintTo = function(self_viewer, bb, x, y)
                orig_paintTo(self_viewer, bb, x, y)
                -- Paint footer at the bottom of the screen
                if panelnav.view.footer and panelnav.view.footer_visible then
                    local current_page = panelnav.ui.paging.current_page
                    -- Only refresh footer content when page changes
                    if current_page ~= last_footer_page then
                        logger.dbg("ReaderPanelNav: page changed from", last_footer_page, "to", current_page, "- refreshing footer")
                        panelnav.view.footer:onUpdateFooter(true)
                        last_footer_page = current_page
                    end
                    panelnav.view.footer:paintTo(bb, x, y)
                end
            end
        end

        -- Only add panel navigation if enabled
        if self.panel_nav_enabled then
            local is_rtl = BD.mirroredUILayout()

            -- Panel navigation handlers
            imgviewer.onNextPanel = function(self_viewer)
                local cur_panels = panelnav:getPanelsForCurrentPage()
                if cur_panels and panelnav.current_panel_index < #cur_panels then
                    -- Same page: just update the image in place
                    panelnav.current_panel_index = panelnav.current_panel_index + 1
                    panelnav:showPanel(cur_panels[panelnav.current_panel_index])
                elseif cur_panels then
                    -- End of page: go to next page, keep viewer open
                    -- Do everything in one tick so image updates before repaint
                    panelnav.current_panel_index = 0
                    panelnav.current_page_panels = nil
                    panelnav.panels_page = nil
                    UIManager:nextTick(function()
                        panelnav.ui:handleEvent(Event:new("GotoViewRel", 1))
                        local new_panels = panelnav:getPanelsForCurrentPage()
                        if new_panels then
                            panelnav.current_panel_index = 1
                            panelnav:showPanel(new_panels[1])
                        else
                            -- No panels on new page, close viewer
                            UIManager:close(self_viewer)
                        end
                    end)
                end
                return true
            end

            imgviewer.onPrevPanel = function(self_viewer)
                local cur_panels = panelnav:getPanelsForCurrentPage()
                if panelnav.current_panel_index > 1 then
                    -- Same page: just update the image in place
                    panelnav.current_panel_index = panelnav.current_panel_index - 1
                    panelnav:showPanel(cur_panels[panelnav.current_panel_index])
                else
                    -- Start of page: go to previous page, keep viewer open
                    -- Do everything in one tick so image updates before repaint
                    panelnav.current_page_panels = nil
                    panelnav.panels_page = nil
                    UIManager:nextTick(function()
                        panelnav.ui:handleEvent(Event:new("GotoViewRel", -1))
                        local new_panels = panelnav:getPanelsForCurrentPage()
                        if new_panels then
                            panelnav.current_panel_index = #new_panels
                            panelnav:showPanel(new_panels[panelnav.current_panel_index])
                        else
                            -- No panels on new page, close viewer
                            UIManager:close(self_viewer)
                        end
                    end)
                end
                return true
            end

            -- Key bindings (replace default zoom with panel navigation)
            if Device:hasKeys() then
                imgviewer.key_events.ZoomIn = nil
                imgviewer.key_events.ZoomOut = nil
                imgviewer.key_events.NextPanel = { { { "RPgFwd", "LPgFwd", is_rtl and "Left" or "Right" } }, event = "NextPanel" }
                imgviewer.key_events.PrevPanel = { { { "RPgBack", "LPgBack", is_rtl and "Right" or "Left" } }, event = "PrevPanel" }
            end

            -- Touch zones (tap left/right edges)
            if Device:isTouchDevice() then
                imgviewer:registerTouchZones({
                    {
                        id = "panel_tap_forward",
                        ges = "tap",
                        screen_zone = is_rtl
                            and { ratio_x = 0, ratio_y = 0, ratio_w = 0.25, ratio_h = 1 }
                            or  { ratio_x = 0.75, ratio_y = 0, ratio_w = 0.25, ratio_h = 1 },
                        handler = function() return imgviewer:onNextPanel() end,
                    },
                    {
                        id = "panel_tap_backward",
                        ges = "tap",
                        screen_zone = is_rtl
                            and { ratio_x = 0.75, ratio_y = 0, ratio_w = 0.25, ratio_h = 1 }
                            or  { ratio_x = 0, ratio_y = 0, ratio_w = 0.25, ratio_h = 1 },
                        handler = function() return imgviewer:onPrevPanel() end,
                    },
                })
            end
        end

        -- Handle device rotation: apply rotation, close viewer, re-show panel
        imgviewer.onSetRotationMode = function(self_viewer, mode)
            if mode ~= nil and mode ~= Screen:getRotationMode() then
                UIManager:close(self_viewer)
                -- Apply rotation via ReaderView
                panelnav.view:onSetRotationMode(mode)
                -- Re-show panel after rotation
                UIManager:nextTick(function()
                    local rot_panels = panelnav:getPanelsForCurrentPage()
                    if rot_panels and panelnav.current_panel_index > 0 then
                        panelnav:showPanel(rot_panels[panelnav.current_panel_index])
                    end
                end)
            end
            return true
        end

        -- Clear reference when ImageViewer is closed, but call original cleanup first
        local orig_onCloseWidget = imgviewer.onCloseWidget
        imgviewer.onCloseWidget = function(self_viewer)
            panelnav._panel_viewer = nil
            -- Call original cleanup to free resources
            if orig_onCloseWidget then
                orig_onCloseWidget(self_viewer)
            end
        end

        -- Store reference for reuse
        self._panel_viewer = imgviewer
        UIManager:show(imgviewer)
        logger.dbg("ReaderPanelNav: showing panel", self.current_panel_index)
    else
        logger.dbg("ReaderPanelNav: drawPagePart returned nil image")
        UIManager:show(InfoMessage:new{
            text = _("Could not render panel."),
            timeout = 2,
        })
    end
end

--[[--
Show full page (exit panel zoom).
--]]
function ReaderPanelNav:showFullPage()
    self.current_panel_index = 0
    self.ui:handleEvent(Event:new("RedrawCurrentPage"))
end

--[[--
Toggle panel navigation enabled setting (for menu).
--]]
function ReaderPanelNav:togglePanelNavEnabled()
    self.panel_nav_enabled = not self.panel_nav_enabled

    if self.panel_nav_enabled then
        UIManager:show(InfoMessage:new{
            text = _("Panel navigation enabled."),
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Panel navigation disabled."),
            timeout = 2,
        })
        -- Reset state
        self.current_panel_index = 0
        self.current_page_panels = nil
        self.panels_page = nil
    end
end

--[[--
Enter panel navigation mode - show current panel in ImageViewer.
Navigation keys only work if panel navigation is enabled.
--]]
function ReaderPanelNav:onEnterPanelNavMode()
    if self.ui.highlight and not self.ui.highlight.panel_zoom_enabled then
        UIManager:show(InfoMessage:new{
            text = _("Panel zoom must be enabled first."),
            timeout = 2,
        })
        return true
    end

    local panels = self:getPanelsForCurrentPage()
    if panels then
        -- no current panel, or one from a previous detection: start at the first one
        if self.current_panel_index < 1 or self.current_panel_index > #panels then
            self.current_panel_index = 1
        end
        self:showPanel(panels[self.current_panel_index])
    else
        UIManager:show(InfoMessage:new{
            text = _("No panels detected on this page."),
            timeout = 2,
        })
    end

    return true
end

--[[--
Toggle panel box visualization for debugging.
--]]
function ReaderPanelNav:onToggleShowPanelBoxes()
    self.show_panel_boxes = not self.show_panel_boxes

    if self.show_panel_boxes then
        -- Force panel detection on current page
        self:getPanelsForCurrentPage()
        local panel_count = self.current_page_panels and #self.current_page_panels or 0
        UIManager:show(InfoMessage:new{
            text = _("Panel boxes visible.") .. "\n" .. string.format(_("Detected %d panels on this page."), panel_count),
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Panel boxes hidden."),
            timeout = 2,
        })
    end

    -- Redraw the page
    UIManager:setDirty(self.dialog, "ui")
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
    if not self.show_panel_boxes and not self.highlight_current_panel then
        return
    end
    if self.ui.highlight and not self.ui.highlight.panel_zoom_enabled then
        return
    end
    if not self.panel_nav_enabled then
        return
    end

    local panels = self:getPanelsForCurrentPage()
    if not panels then
        return
    end

    local box_color = Blitbuffer.ColorRGB24(0x00, 0xCC, 0x00)  -- green for all the panels
    local current_box_color = Blitbuffer.ColorRGB24(0xFF, 0x00, 0x00)  -- red for the current one
    local line_width = Size.line.thick
    local number_font = Font:getFace("infofont", 14)

    for i, panel in ipairs(panels) do
        local rect = self.view:pageToScreenTransform(self.panels_page, panel)
        local is_current = i == self.current_panel_index
        -- without show_panel_boxes, only the current panel is highlighted
        if rect and (self.show_panel_boxes or is_current) then
            local color = is_current and current_box_color or box_color
            bb:paintRectRGB32(rect.x, rect.y, rect.w, line_width, color)
            bb:paintRectRGB32(rect.x, rect.y + rect.h - line_width, rect.w, line_width, color)
            bb:paintRectRGB32(rect.x, rect.y, line_width, rect.h, color)
            bb:paintRectRGB32(rect.x + rect.w - line_width, rect.y, line_width, rect.h, color)

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

    if self.show_panel_boxes then
        logger.dbg("ReaderPanelNav: painted", #panels, "panel boxes with numbers")
    end
end

--[[--
Handle page change to reset panel state.
--]]
function ReaderPanelNav:onPageUpdate(new_page_no)
    if self.panels_page ~= new_page_no then
        self.current_page_panels = nil
        self.panels_page = nil
        self.current_panel_index = 0
    end
end

return ReaderPanelNav
