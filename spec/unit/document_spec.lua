describe("PDF document module", function()
    local DocumentRegistry

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
    end)

    local doc
    it("should open document", function()
        local sample_pdf = "spec/front/unit/data/tall.pdf"
        doc = DocumentRegistry:openDocument(sample_pdf)
        assert.truthy(doc)
    end)
    it("should get page dimensions", function()
        local dimen = doc:getPageDimensions(1, 1, 0)
        assert.are.same(dimen.w, 567)
        assert.are.same(dimen.h, 1418)
    end)
    it("should get cover image", function()
        local image = doc:getCoverPageImage()
        assert.truthy(image)
        assert.are.same(320, image:getWidth())
        assert.are.same(800, image:getHeight())
    end)
    local pos0 = {page = 1, x = 0, y = 20}
    local pos1 = {page = 1, x = 300, y = 120}
    local pboxes = {
        {x = 26, y = 42, w = 240, h = 22},
        {x = 48, y = 82, w = 185, h = 22},
    }
    it("should clip page rect to PNG file", function()
        doc:clipPagePNGFile(pos0, pos1, nil, nil, "/tmp/clip0.png")
        doc:clipPagePNGFile(pos0, pos1, pboxes, "lighten", "/tmp/clip1.png")
    end)
    it("should clip page rect to PNG string", function()
        local clip0 = doc:clipPagePNGString(pos0, pos1, nil, nil)
        assert.truthy(clip0)
        local clip1 = doc:clipPagePNGString(pos0, pos1, pboxes, "lighten")
        assert.truthy(clip1)
    end)
    it("should draw a page part fit to a size, rotated for best fit if asked to", function()
        local rect = { x = 0, y = 0, w = 300, h = 100 }
        -- 300x100 fit into 200x200: zoom 2/3, 200x67
        local bb, rotated = doc:drawPagePart(1, rect, 0, false, { w = 200, h = 200 })
        assert.is_false(rotated)
        assert.are.equal(200, bb:getWidth())
        assert.are.equal(67, bb:getHeight())
        -- rotated into 100x400: zoom min(100/100, 400/300) = 1, rendered unrotated, 300x100
        bb, rotated = doc:drawPagePart(1, rect, 0, true, { w = 100, h = 400 })
        assert.is_true(rotated)
        assert.are.equal(300, bb:getWidth())
        assert.are.equal(100, bb:getHeight())
        -- no need to rotate it into 400x100: zoom min(400/300, 100/100) = 1
        bb, rotated = doc:drawPagePart(1, rect, 0, true, { w = 400, h = 100 })
        assert.is_false(rotated)
        assert.are.equal(300, bb:getWidth())
        -- by default, fit to the screen
        local canvas_size = require("document/canvascontext"):getSize()
        bb = doc:drawPagePart(1, rect, 0, false)
        assert.is_true(bb:getWidth() == canvas_size.w or bb:getHeight() == canvas_size.h)
        assert.is_true(bb:getWidth() <= canvas_size.w and bb:getHeight() <= canvas_size.h)
    end)
    it("should close document", function()
        doc:close()
    end)
end)

describe("EPUB document module", function()
    local DocumentRegistry, cre

    setup(function()
        require("commonrequire")
        cre = require("libs/libkoreader-cre")
        DocumentRegistry = require("document/documentregistry")
    end)

    local doc
    it("should open document", function()
        doc = DocumentRegistry:openDocument("spec/front/unit/data/juliet.epub")
        assert.truthy(doc)
    end)
    it("should get cover image", function()
        local image = doc:getCoverPageImage()
        assert.truthy(image)
        assert.are.same(520, image:getWidth())
        assert.are.same(800, image:getHeight())
    end)
    it("should register droid sans fallback", function()
        local face_list = cre.getFontFaces()
        local has_droid_sans = false
        for i, v in ipairs(face_list) do
            if v == "Droid Sans Mono" then
                has_droid_sans = true
                break
            end
        end
        assert.is_true(has_droid_sans)
        assert.is_true(#face_list >= 10)
    end)
    it("should close document", function()
        doc:close()
    end)
end)
