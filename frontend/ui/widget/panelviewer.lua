--[[--
PanelViewer shows the panels of comic pages one at a time, enlarged over the page or fullscreen.

It is an @{ui.widget.imageviewer|ImageViewer} whose image is replaced in place with
@{PanelViewer:setImage|setImage()}, and whose page turn keys, taps and swipes call back its
caller to go to the next or previous panel.

Over the page (overlay): the page painted by paint_background_callback stays visible, lightened,
the panel is framed on it, and its image is shown as it is given (not scaled, nor rotated), in a
card centred above overlay_bottom_height. It can't be zoomed nor panned.
Fullscreen: the image is scaled to fit the screen, and can be zoomed and panned as in ImageViewer.

Keys: the page turn keys go to the next or previous panel, Back closes. Where the left and right
keys turn pages (as in ReaderPaging), they go to the next or previous panel too, otherwise they
pan the image like up and down (fullscreen only), except on devices with few keys, where left
closes instead.

Touch: a tap in the forward or backward zone goes to the next or previous panel, a tap elsewhere
does nothing. A long-press released without a drag closes. While the image fits the screen, a swipe
west or east goes to the next or previous panel (the other way round with inverse_reading_order),
and a swipe north or south closes, except fullscreen on the screen sides, where it zooms as in
ImageViewer. Fullscreen, swipes pan while zoomed in, a long-press followed by a drag pans, and
spread, pinch and pan work as in ImageViewer. Any multiswipe closes.

@usage
    local viewer = PanelViewer:new{
        image = bb, -- freed by the viewer, as the next ones
        rotated = false,
        next_callback = function() viewer:setImage(next_bb, false) end,
        prev_callback = function() viewer:setImage(prev_bb, false) end,
    }
    UIManager:show(viewer)
--]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageViewer = require("ui/widget/imageviewer")
local ImageWidget = require("ui/widget/imagewidget")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

-- Over the page: how much the page is lightened (0: not at all, 1: to white). As with the "dim" page
-- overlap style, black turns mid-gray: the panel stands out, and the page can still be read.
local OVERLAY_LIGHTEN_FACTOR = 0.5
-- Over the page: the margin around the card on each side, and the card border and padding
local OVERLAY_MARGIN = Size.margin.default * 2
local OVERLAY_BORDER = Size.border.thick
local OVERLAY_PADDING = Size.padding.small
-- The frame of the current panel on the page, on a color screen
local PANEL_FRAME_COLOR = Blitbuffer.ColorRGB24(0xFF, 0x00, 0x00)

local PanelViewer = ImageViewer:extend{
    fullscreen = true,
    with_title_bar = false,
    -- The images we are given are ours: freed when setImage() replaces them, and when we close (so not
    -- document cache tiles, which the cache frees when it drops them, e.g., on low memory)
    image_disposable = true,

    -- Show the panel over the page rather than fullscreen
    overlay = false,
    -- Over the page: where the panel is on the screen, in the page painted under it (nil: not shown)
    panel_rect = nil,
    -- Over the page: height at the bottom of the screen that is neither lightened nor covered by
    -- the panel (e.g., the reader footer). Fullscreen, ImageViewer's reserved_bottom_height is used.
    overlay_bottom_height = 0,

    -- Callbacks: next and previous panel, viewer closed (from onCloseWidget),
    -- function(bb, x, y) painting over reserved_bottom_height (fullscreen, e.g., the reader footer),
    -- function(bb, x, y) painting the page under the panel (over the page, on the whole screen),
    -- function(mode) rotating the screen (called after the viewer has closed itself; without a mode
    -- when the screen has been resized without a rotation event, e.g., rotated by Android)
    next_callback = nil,
    prev_callback = nil,
    close_callback = nil,
    paint_bottom_callback = nil,
    paint_background_callback = nil,
    rotation_callback = nil,

    -- Tap zones going to the next and previous panel, as ratios of the screen size,
    -- like those of ReaderView:getTapZones() (nil: no zone)
    forward_zone = nil,
    backward_zone = nil,
    -- Swipe east rather than west goes to the next panel, as ReaderView.inverse_reading_order does
    inverse_reading_order = false,
}

local function isInZone(pos, zone)
    if not zone then
        return false
    end
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    return pos.x >= zone.ratio_x * screen_w and pos.x < (zone.ratio_x + zone.ratio_w) * screen_w
       and pos.y >= zone.ratio_y * screen_h and pos.y < (zone.ratio_y + zone.ratio_h) * screen_h
end

--[[--
Get the color of the frame of the current panel on the page.

@return red on a color screen, black otherwise (where red is a dark gray, hard to tell from the
borders of the panels on a lightened page)
--]]
function PanelViewer.getPanelFrameColor()
    return Screen:isColorEnabled() and PANEL_FRAME_COLOR or Blitbuffer.COLOR_BLACK
end

--[[--
Frame a panel on the page with a thick line.

The frame of the current panel over the page, and ReaderPanelNav's "Highlight current panel" and
panel boxes.

@param bb BlitBuffer to paint to
@param rect panel on the screen {x, y, w, h}
@param[opt] color frame color (default: the current panel's, see getPanelFrameColor())
@param[opt] clip Geom part of the screen to paint in (default: all of it)
--]]
function PanelViewer.paintPanelFrame(bb, rect, color, clip)
    color = color or PanelViewer.getPanelFrameColor()
    local function paintEdge(x, y, w, h)
        if clip then
            local right, bottom = math.min(x + w, clip.x + clip.w), math.min(y + h, clip.y + clip.h)
            x, y = math.max(x, clip.x), math.max(y, clip.y)
            w, h = right - x, bottom - y
        end
        if w > 0 and h > 0 then
            bb:paintRectRGB32(x, y, w, h, color)
        end
    end
    local line_w = Size.line.thick
    paintEdge(rect.x, rect.y, rect.w, line_w)
    paintEdge(rect.x, rect.y + rect.h - line_w, rect.w, line_w)
    paintEdge(rect.x, rect.y, line_w, rect.h)
    paintEdge(rect.x + rect.w - line_w, rect.y, line_w, rect.h)
end

--[[--
Get the largest size of the image of a panel shown over the page.

It is the size of the screen, less the bottom height, the margins around the card and its border.

@int bottom_height height at the bottom of the screen not to cover, as overlay_bottom_height
@treturn table size {w, h}
--]]
function PanelViewer.getOverlayMaxSize(bottom_height)
    local frame = 2 * (OVERLAY_MARGIN + OVERLAY_BORDER + OVERLAY_PADDING)
    return {
        w = Screen:getWidth() - frame,
        h = Screen:getHeight() - (bottom_height or 0) - frame,
    }
end

function PanelViewer:init()
    if self.overlay then
        -- the image as it is given, over a page that goes down to the bottom of the screen
        self.rotated = false
        self.reserved_bottom_height = 0
    end
    -- Our caller has rendered the image for this rotation, don't let ImageViewer decide on another one
    local rotated = self.rotated
    ImageViewer.init(self)
    if self.rotated ~= rotated then
        self.rotated = rotated
        self:update()
    end
    -- We paint the whole screen, reserved_bottom_height included, see paintTo()
    self.covers_fullscreen = true
    self:registerKeyEvents()
    if Device:isTouchDevice() then
        -- to tell a long-press from a long-press and drag, as the gesture detector does, see onHoldRelease()
        self.ges_events.HoldPan = {
            GestureRange:new{
                ges = "hold_pan",
                range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
            },
        }
    end
end

-- Each physical key is in a single key_events entry: InputContainer:onKeyPress() goes through
-- them with pairs(), so a key in two of them would trigger either.
function PanelViewer:registerKeyEvents()
    if not Device:hasKeys() then
        return
    end
    -- The page turn keys go to panels, they no longer zoom
    self.key_events.ZoomIn = nil
    self.key_events.ZoomOut = nil
    self.key_events.Close = { { Device.input.group.Back } }
    self.key_events.NextPanel = { { Device.input.group.PgFwd } }
    self.key_events.PrevPanel = { { Device.input.group.PgBack } }
    -- The left and right keys turn pages as in ReaderPaging:registerKeyEvents(): on D-pad devices
    -- using it as action keys, with left_right_keys_turn_pages, otherwise unless there are few keys
    local left_right_turn_pages
    if Device:hasDPad() and Device:useDPadAsActionKeys() then
        left_right_turn_pages = G_reader_settings:isTrue("left_right_keys_turn_pages")
    else
        left_right_turn_pages = not Device:hasFewKeys()
    end
    if left_right_turn_pages then
        -- so they go to panels rather than pan
        local prev_key, next_key = "Left", "Right"
        if BD.mirroredUILayout() then
            prev_key, next_key = next_key, prev_key
        end
        table.insert(self.key_events.NextPanel, { next_key })
        table.insert(self.key_events.PrevPanel, { prev_key })
        self.key_events.PanLeft = nil
        self.key_events.PanRight = nil
    elseif Device:hasFewKeys() then
        -- no panning with the cursor keys, left closes as in other dialogs on these devices
        self.key_events.PanUp = nil
        self.key_events.PanDown = nil
        self.key_events.PanLeft = nil
        self.key_events.PanRight = nil
        table.insert(self.key_events.Close, { "Left" })
    end
end

--[[--
Replace the image shown: fullscreen, scaled to fit the screen; over the page, as it is.

@param image BlitBuffer, freed by the viewer when replaced or closed (unless image_disposable is false)
@bool rotated whether to show it rotated (fullscreen only)
@param[opt] panel_rect where the panel is on the screen, in the page under it {x, y, w, h}
(over the page only, nil: not shown)
--]]
function PanelViewer:setImage(image, rotated, panel_rect)
    local previous_image = self.image
    self.image = image
    self.rotated = rotated and not self.overlay or false
    self.panel_rect = panel_rect
    self.scale_factor = 0
    self._scale_to_fit = true
    self._center_x_ratio = 0.5
    self._center_y_ratio = 0.5
    -- they depend on the image size, see ImageViewer:_applyNewScaleFactor()
    self._min_scale_factor = nil
    self._max_scale_factor = nil
    self._panning = false
    -- frees the previous image widget
    self:update()
    if self.image_disposable and previous_image and previous_image ~= image then
        previous_image:free()
    end
    if self.reserved_bottom_height > 0 then
        -- what is painted there may have changed with the image (e.g., the page number)
        UIManager:setDirty(self, "ui", self:getReservedArea())
    end
end

function PanelViewer:update()
    if not self.overlay then
        return ImageViewer.update(self)
    end
    -- Over the page: the image in a card, centred above overlay_bottom_height
    self:_clean_image_wg()
    self._image_wg = ImageWidget:new{
        image = self.image,
        image_disposable = false,
        alpha = true, -- as ImageViewer
        width = self.image:getWidth(),
        height = self.image:getHeight(),
    }
    self[1] = CenterContainer:new{
        dimen = self:getOverlayArea(),
        FrameContainer:new{
            bordersize = OVERLAY_BORDER,
            padding = OVERLAY_PADDING,
            margin = 0,
            background = Blitbuffer.COLOR_WHITE,
            self._image_wg,
        },
    }
    -- the whole screen: the page under the panel may have changed too
    self.dithered = true
    UIManager:setDirty(self, Device:hasKaleidoWfm() and "partial" or "ui", nil, true)
end

-- The area of the screen below our widgets, of reserved_bottom_height
function PanelViewer:getReservedArea()
    return Geom:new{
        x = 0, y = Screen:getHeight() - self.reserved_bottom_height,
        w = Screen:getWidth(), h = self.reserved_bottom_height,
    }
end

-- Over the page: the area of the screen above overlay_bottom_height, lightened, where the panel is shown
function PanelViewer:getOverlayArea()
    return Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(), h = Screen:getHeight() - self.overlay_bottom_height,
    }
end

function PanelViewer:paintTo(bb, x, y)
    if self.overlay then
        -- the page, lightened above the bottom height
        if self.paint_background_callback then
            self.paint_background_callback(bb, x, y)
        else
            bb:paintRect(x, y, Screen:getWidth(), Screen:getHeight(), Blitbuffer.COLOR_WHITE)
        end
        local area = self:getOverlayArea():offsetBy(x, y)
        bb:lightenRect(area.x, area.y, area.w, area.h, OVERLAY_LIGHTEN_FACTOR)
        -- where the panel is on it
        local rect = self.panel_rect
        if rect then
            PanelViewer.paintPanelFrame(bb, { x = x + rect.x, y = y + rect.y, w = rect.w, h = rect.h }, nil, area)
        end
        -- the card
        ImageViewer.paintTo(self, bb, x, y)
        return
    end
    ImageViewer.paintTo(self, bb, x, y)
    if self.reserved_bottom_height > 0 then
        local area = self:getReservedArea()
        bb:paintRect(x + area.x, y + area.y, area.w, area.h, Blitbuffer.COLOR_WHITE)
    end
    if self.paint_bottom_callback then
        self.paint_bottom_callback(bb, x, y)
    end
end

function PanelViewer:onNextPanel()
    if self.next_callback then
        self.next_callback()
    end
    return true
end

function PanelViewer:onPrevPanel()
    if self.prev_callback then
        self.prev_callback()
    end
    return true
end

function PanelViewer:onTap(_, ges)
    -- like ReaderPaging's tap zones; no ImageViewer button bar
    if G_reader_settings:nilOrFalse("page_turns_disable_tap") then
        if isInZone(ges.pos, self.forward_zone) then
            return self:onNextPanel()
        elseif isInZone(ges.pos, self.backward_zone) then
            return self:onPrevPanel()
        end
    end
    return true
end

function PanelViewer:onHold(arg, ges)
    self._hold_dragged = false
    return ImageViewer.onHold(self, arg, ges)
end

function PanelViewer:onHoldPan()
    -- the finger moved past the gesture detector's pan threshold: not just a long-press
    -- (ImageViewer's pan_threshold, a few pixels, would take a slight roll of the finger for a drag)
    self._hold_dragged = true
    return true
end

function PanelViewer:onHoldRelease(_, ges)
    -- _panning: we got the hold (the release of the long-press that opened us comes without it)
    if not self._panning then
        return true
    end
    self._panning = false
    if not self._hold_dragged then
        -- a long-press, zoomed in or not: back to the page (on touch-only devices, the exit that
        -- always works, so no full refresh as in ImageViewer)
        return self:onClose()
    end
    -- a long-press and drag pans, as in ImageViewer (over the page, the panel doesn't move)
    local dx, dy = ges.pos.x - self._pan_relative_x, ges.pos.y - self._pan_relative_y
    if not self.overlay and (math.abs(dx) >= self.pan_threshold or math.abs(dy) >= self.pan_threshold) then
        self:panBy(-dx, -dy)
    end
    return true
end

function PanelViewer:onSwipe(arg, ges)
    if self.scale_factor ~= 0 then
        -- zoomed in or out: pan
        return ImageViewer.onSwipe(self, arg, ges)
    end
    -- like ReaderPaging:onSwipe()
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" or direction == "east" then
        if G_reader_settings:nilOrFalse("page_turns_disable_swipe") then
            local forward = direction == "west"
            if self.inverse_reading_order then
                forward = not forward
            end
            if forward then
                return self:onNextPanel()
            else
                return self:onPrevPanel()
            end
        end
    elseif direction == "north" or direction == "south" then
        -- fullscreen, ImageViewer zooms with them on the screen sides (for devices without multitouch)
        if self.overlay or (ges.pos.x >= Screen:getWidth() * 1/8 and ges.pos.x <= Screen:getWidth() * 7/8) then
            return self:onClose()
        end
    end
    if self.overlay then
        return true
    end
    return ImageViewer.onSwipe(self, arg, ges)
end

-- Over the page, the size of the panel is a setting: no zooming (spread, pinch, or anything else
-- that would zoom in or out) nor panning (pan, long-press and drag, cursor keys)
function PanelViewer:onSpread(arg, ges)
    if self.overlay then
        return true
    end
    return ImageViewer.onSpread(self, arg, ges)
end

function PanelViewer:onPinch(arg, ges)
    if self.overlay then
        return true
    end
    return ImageViewer.onPinch(self, arg, ges)
end

function PanelViewer:onZoomIn(inc)
    if self.overlay then
        return true
    end
    return ImageViewer.onZoomIn(self, inc)
end

function PanelViewer:onZoomOut(dec)
    if self.overlay then
        return true
    end
    return ImageViewer.onZoomOut(self, dec)
end

function PanelViewer:panBy(x, y)
    if not self.overlay then
        ImageViewer.panBy(self, x, y)
    end
end

function PanelViewer:onSetRotationMode(mode)
    if mode ~= nil and mode ~= Screen:getRotationMode() then
        -- we are laid out for the current screen size: close, our caller shows a new viewer
        UIManager:close(self)
        if self.rotation_callback then
            self.rotation_callback(mode)
        end
    end
    return true
end

function PanelViewer:onSetDimensions(dimen)
    -- The screen has been resized without a SetRotationMode event (e.g., Android rotates it itself,
    -- or the emulator window was resized): as on rotation, we are laid out for the previous size
    -- (self.region is the screen above reserved_bottom_height, see ImageViewer:init())
    if dimen.w ~= self.region.w or dimen.h ~= self.region.h + self.reserved_bottom_height then
        UIManager:close(self)
        if self.rotation_callback then
            self.rotation_callback()
        end
    end
end

function PanelViewer:onCloseWidget()
    ImageViewer.onCloseWidget(self)
    if self.reserved_bottom_height > 0 then
        UIManager:setDirty(nil, "flashui", self:getReservedArea())
    end
    if self.close_callback then
        self.close_callback()
    end
end

return PanelViewer
