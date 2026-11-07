describe("ImageViewer widget", function()
    local Blitbuffer, ImageViewer, Screen, Size

    setup(function()
        require("commonrequire")
        Blitbuffer = require("ffi/blitbuffer")
        ImageViewer = require("ui/widget/imageviewer")
        Screen = require("device").screen
        Size = require("ui/size")
    end)

    local function newViewer(options)
        local o = {
            image = Blitbuffer.new(200, 100, Blitbuffer.TYPE_BBRGB32),
            with_title_bar = false,
        }
        for k, v in pairs(options) do
            o[k] = v
        end
        return ImageViewer:new(o)
    end

    describe("reserved_bottom_height", function()
        local reserved

        setup(function()
            reserved = Screen:scaleBySize(20)
        end)

        it("should change nothing when 0", function()
            local viewer = newViewer{ fullscreen = true }
            assert.are.equal(0, viewer.reserved_bottom_height)
            assert.are.equal(Screen:getHeight(), viewer.region.h)
            assert.are.equal(Screen:getHeight(), viewer.height)
            assert.is_true(viewer.covers_fullscreen)
            -- the frame keeps its border, off screen
            assert.are.equal(Size.border.window, viewer.main_frame.bordersize)
            local bb = Blitbuffer.new(Screen:getWidth(), Screen:getHeight(), Blitbuffer.TYPE_BBRGB32)
            viewer:paintTo(bb, 0, 0)
            assert.are.equal(-Size.border.window, viewer.main_frame.dimen.y)
            assert.are.equal(Screen:getHeight() + 2 * Size.border.window, viewer.main_frame.dimen.h)
            local framed = newViewer{ fullscreen = false }
            assert.are.equal(Screen:getHeight(), framed.region.h)
            assert.are.equal(Screen:getHeight() - Screen:scaleBySize(40), framed.height)
            assert.is_nil(framed.covers_fullscreen)
        end)

        it("should lay out the viewer and its buttons above it", function()
            local viewer = newViewer{ fullscreen = true, reserved_bottom_height = reserved, buttons_visible = true }
            assert.are.equal(Screen:getHeight() - reserved, viewer.region.h)
            assert.are.equal(Screen:getHeight() - reserved, viewer.height)
            -- it doesn't paint there, so it doesn't cover the full screen
            assert.is_nil(viewer.covers_fullscreen)
            -- the frame border would be over it
            assert.are.equal(0, viewer.main_frame.bordersize)

            local bb = Blitbuffer.new(Screen:getWidth(), Screen:getHeight(), Blitbuffer.TYPE_BBRGB32)
            viewer:paintTo(bb, 0, 0)
            local frame = viewer.main_frame.dimen
            assert.are.equal(0, frame.y)
            assert.are.equal(Screen:getHeight() - reserved, frame.y + frame.h)
            local close_button = viewer.button_table:getButtonById("close").dimen
            assert.is_true(close_button.y + close_button.h <= Screen:getHeight() - reserved)

            local framed = newViewer{ fullscreen = false, reserved_bottom_height = reserved }
            assert.are.equal(Screen:getHeight() - reserved, framed.region.h)
            assert.are.equal(Screen:getHeight() - reserved - Screen:scaleBySize(40), framed.height)
            assert.are.equal(Size.border.window, framed.main_frame.bordersize)
        end)

        it("should keep it on update", function()
            local viewer = newViewer{ fullscreen = true, reserved_bottom_height = reserved }
            viewer.buttons_visible = true
            viewer:update()
            assert.are.equal(Screen:getHeight() - reserved, viewer.height)
            assert.are.equal(Screen:getHeight() - reserved, viewer.img_container_h + viewer.button_container:getSize().h)
        end)
    end)
end)
