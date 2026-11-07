describe("Koptinterface module", function()
    local DocumentRegistry, Koptinterface
    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        Koptinterface = require("document/koptinterface")
    end)

    describe("should", function()

        local doc

        setup(function()
            doc = DocumentRegistry:openDocument("spec/front/unit/data/tall.pdf")
            doc.configurable.text_wrap = 0
        end)

        teardown(function()
            doc:close()
        end)

        it("should get auto bbox", function()
            local auto_bbox = Koptinterface:getAutoBBox(doc, 1)
            assert.is.near(22, auto_bbox.x0, 0.5)
            assert.is.near(38, auto_bbox.y0, 0.5)
            assert.is.near(548, auto_bbox.x1, 0.5)
            assert.is.near(1387, auto_bbox.y1, 0.5)
        end)

        it("should get semi auto bbox", function()
            local semiauto_bbox = Koptinterface:getSemiAutoBBox(doc, 1)
            local page_bbox = doc:getPageBBox(1)
            doc.bbox[1] = {
                x0 = page_bbox.x0 + 10,
                y0 = page_bbox.y0 + 10,
                x1 = page_bbox.x1 - 10,
                y1 = page_bbox.y1 - 10,
            }

            local bbox = Koptinterface:getSemiAutoBBox(doc, 1)
            assert.is_not.near(semiauto_bbox.x0, bbox.x0, 0.5)
            assert.is_not.near(semiauto_bbox.y0, bbox.y0, 0.5)
            assert.is_not.near(semiauto_bbox.x1, bbox.x1, 0.5)
            assert.is_not.near(semiauto_bbox.y1, bbox.y1, 0.5)
        end)

        it("should render optimized page to de-watermark", function()
            local page_dimen = doc:getPageDimensions(1, 1.0, 0)
            local tile = Koptinterface:renderOptimizedPage(doc, 1, nil,
            1.0, 0, 0)
            assert.truthy(tile)
            assert.are.same(page_dimen, tile.excerpt)
        end)

        it("should reflow page in foreground", function()
            doc.configurable.text_wrap = 1
            local kc = Koptinterface:getCachedContext(doc, 1)
            assert.truthy(kc)
        end)

        it("should hint reflowed page in background", function()
            doc.configurable.text_wrap = 1
            Koptinterface:hintReflowedPage(doc, 1, 1.0, 0, false)
            -- and wait for reflowing to complete
            local kc = Koptinterface:getCachedContext(doc, 1)
            assert.truthy(kc)
        end)

        it("should get native text boxes", function()
            Koptinterface:getCachedContext(doc, 1)
            local boxes = Koptinterface:getNativeTextBoxes(doc, 1)
            assert.equal(60, #boxes)
        end)

        it("should get native text boxes from scratch", function()
            Koptinterface:getCachedContext(doc, 1)
            local boxes = Koptinterface:getNativeTextBoxesFromScratch(doc, 1)
            assert.equal(60, #boxes)
        end)

        it("should get reflow text boxes", function()
            doc.configurable.text_wrap = 1
            Koptinterface:getCachedContext(doc, 1)
            local boxes = Koptinterface:getReflowedTextBoxes(doc, 1)
            local lines_in_reflowed_page = #boxes
            assert.truthy(lines_in_reflowed_page > 60)
        end)

        it("should get reflow text boxes from scratch", function()
            doc.configurable.text_wrap = 1
            Koptinterface:getCachedContext(doc, 1)
            local boxes = Koptinterface:getReflowedTextBoxesFromScratch(doc, 1)
            local lines_in_reflowed_page = #boxes
            assert.truthy(lines_in_reflowed_page > 60)
        end)

    end)

    describe("should", function()

        local complex_doc

        setup(function()
            complex_doc = DocumentRegistry:openDocument("spec/front/unit/data/sample.pdf")
            complex_doc.configurable.text_wrap = 0
        end)

        teardown(function()
            complex_doc:close()
        end)

        it("should get page block of a two-column page", function()
            for i = 0.3, 0.6, 0.3 do
                for j = 0.3, 0.6, 0.3 do
                    local block = Koptinterface:getPageBlock(complex_doc, 34, i, j)
                    assert.truthy(block.x1 - block.x0 < 0.5)
                end
            end
        end)

        it("should get word from native position", function()
            local word_boxes = Koptinterface:getWordFromPosition(complex_doc, {
                page = 19, x = 400, y = 530,
            })
            assert.is.same("previous", word_boxes.word)
        end)

        it("should get word from reflow position", function()
            complex_doc.configurable.text_wrap = 1
            Koptinterface:getCachedContext(complex_doc, 19)
            local word_boxes = Koptinterface:getWordFromPosition(complex_doc, {
                page = 19, x = 320, y = 730,
            })
            assert.is.same("time,", word_boxes.word)
        end)

    end)

    describe("should", function()

        local paper_doc

        setup(function()
            paper_doc = DocumentRegistry:openDocument("spec/front/unit/data/paper.pdf")
            paper_doc.configurable.text_wrap = 0
        end)

        teardown(function()
            paper_doc:close()
        end)

        it("should get link from native position", function()
            local link = Koptinterface:getLinkFromPosition(paper_doc, 1, {
                x = 140, y = 560,
            })
            assert.truthy(link)
            assert.is.same(20, link.page)
            require("dbg"):v("link", link)
        end)

        it("should get link from reflow position", function()
            paper_doc.configurable.text_wrap = 1
            local link = Koptinterface:getLinkFromPosition(paper_doc, 1, {
                x = 455, y = 1105,
            })
            assert.truthy(link)
            assert.is.same(20, link.page)
        end)

    end)

    describe("panel detection", function()
        local Archiver, Blitbuffer, DataStorage
        local doc
        -- two framed panels on a 1600 x 2400 px page, that MuPDF opens at 96 dpi: 1200 x 1800 native
        local panels_px = { { 80, 80, 1440, 1080 }, { 80, 1240, 1440, 1080 } }
        local scale = 0.75

        setup(function()
            Archiver = require("ffi/archiver")
            Blitbuffer = require("ffi/blitbuffer")
            DataStorage = require("datastorage")
            local page = Blitbuffer.new(1600, 2400, Blitbuffer.TYPE_BB8)
            page:fill(Blitbuffer.COLOR_WHITE)
            for _, p in ipairs(panels_px) do
                page:paintBorder(p[1], p[2], p[3], p[4], 4, Blitbuffer.COLOR_BLACK)
                for i = 1, 6 do
                    page:paintRect(p[1] + math.floor(p[3] * i / 8), p[2] + 200, 3, p[4] - 400, Blitbuffer.COLOR_BLACK)
                end
            end
            local png = DataStorage:getDataDir() .. "/panels.png"
            page:writePNG(png)
            page:free()
            local f = io.open(png, "rb")
            local content = f:read("*a")
            f:close()
            os.remove(png)
            -- a page with panels, then an empty one
            local blank = Blitbuffer.new(160, 240, Blitbuffer.TYPE_BB8)
            blank:fill(Blitbuffer.COLOR_WHITE)
            blank:writePNG(png)
            blank:free()
            f = io.open(png, "rb")
            local blank_content = f:read("*a")
            f:close()
            os.remove(png)
            local cbz = DataStorage:getDataDir() .. "/panels.cbz"
            local writer = Archiver.Writer:new{}
            assert.is_true(writer:open(cbz, "zip"))
            writer:addFileFromMemory("1.png", content)
            writer:addFileFromMemory("2.png", blank_content)
            writer:close()
            doc = DocumentRegistry:openDocument(cbz)
        end)

        teardown(function()
            doc:close()
        end)

        it("should render the page at about a million pixels", function()
            local size = doc:getNativePageDimensions(1)
            assert.are.equal(1600 * scale, size.w)
            local kc, zoom = Koptinterface:getPanelDetectionContext(doc, 1)
            assert.is_true(math.abs(kc.src.width - size.w * zoom) <= 1)
            assert.is_true(math.abs(kc.src.width * kc.src.height - 1000000) < 10000)
            kc:free()
        end)

        it("should give the panels in native page coordinates", function()
            local panels = doc:getAllPanelsFromPage(1)
            assert.are.equal(2, #panels)
            table.sort(panels, function(a, b) return a.y < b.y end)
            for i, p in ipairs(panels_px) do
                local panel = panels[i]
                assert.is_true(math.abs(panel.x - p[1] * scale) <= 6 and math.abs(panel.y - p[2] * scale) <= 6
                    and math.abs(panel.w - p[3] * scale) <= 10 and math.abs(panel.h - p[4] * scale) <= 10,
                    string.format("panel %d: %.0f,%.0f %.0fx%.0f", i, panel.x, panel.y, panel.w, panel.h))
            end
            local panel = doc:getPanelFromPage(1, { x = 800 * scale, y = 1800 * scale })
            assert.is_true(math.abs(panel.y - 1240 * scale) <= 6)
            assert.is_nil(doc:getPanelFromPage(1, { x = 800 * scale, y = 1200 * scale }))
            -- a page without panels has none
            assert.is_nil(doc:getAllPanelsFromPage(2))
        end)
    end)

end)
