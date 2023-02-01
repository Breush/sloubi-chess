CharInfo :: struct {
    // Original glyph info, where the vertices should be
    // without special placement.
    glyphCodepoint : u32;
    glyphBlank : bool;
    glyphOffset : Chamber.vec2;
    glyphExtent : Chamber.vec2;
    glyphAdvance : float;

    effective : struct {
        glyphOffset : Chamber.vec2;
        xStart : float;
        xEnd : float;
        xEndWithAdvance : float;
        yStart : float;
        yEnd : float;
    }
}

CharInfos :: struct {
    infos : [..]CharInfo;

    dirty : bool;
    justifyMaxWidth : float;
    justifyStartingOffsetX : float;
    justifyComputedHeight : float;
}

create_text_mesh :: (existingMesh : *Magma.Mesh = null) -> *Magma.Mesh {
    mesh := existingMesh;
    if mesh == null {
        mesh = Magma.create_mesh(instance.engine.scene);
    }
    mesh.material = Magma.create_material(instance.shaders.text);
    return mesh;
}

// @todo A default anchor to Center would be more coherent with what we have elsewhere (rect-mesh),
// but it would be a breaking change, so this is not done yet.
text_mesh_update :: (mesh : *Magma.Mesh, text : string, fontId : string, color : Chamber.vec3, depth := 0.0, anchor := Chamber.Anchor.TopLeft, computeCharInfos := false) -> (width : float, charInfos : CharInfos) {
    charInfos : CharInfos;
    charInfos.dirty = true;

    mesh.disabled &= ~.Application;
    if text.count == 0 {
        mesh.indices.count = 0;
        Magma.mesh_commit_indices(mesh);
        charInfos.dirty = false;
        return 0.0, charInfos;
    }

    glyphInfos := Sill.fonts_glyph_infos(instance.engine, fontId, text);
    defer Basic.array_free(glyphInfos);
    fontInfo := Sill.fonts_info(instance.engine, fontId);

    Magma.material_set(mesh.material, "fontTexture", fontInfo.texture);
    Magma.material_set_color(mesh.material, "color", color);

    if computeCharInfos {
        Basic.array_resize(*charInfos.infos, glyphInfos.count);
    }
    infos : []CharInfo = charInfos.infos;

    totalBlanks := 0;

    for *glyphInfo, index : glyphInfos {
        if glyphInfo.blank then totalBlanks += 1;
        if computeCharInfos {
            infos[index].glyphCodepoint = glyphInfo.codepoint;
            infos[index].glyphBlank = glyphInfo.blank;
            infos[index].glyphOffset = glyphInfo.offset;
            infos[index].glyphExtent = glyphInfo.extent;
            infos[index].glyphAdvance = glyphInfo.advance;
        }
    }

    // @todo Is baking all that into one texture worth it?
    Basic.array_resize(*mesh.vertices, 4 * (glyphInfos.count - totalBlanks));
    Basic.array_resize(*mesh.indices, 6 * (glyphInfos.count - totalBlanks));

    index := 0;
    for *glyphInfo : glyphInfos {
        if glyphInfo.blank then continue;

        mesh.vertices[4 * index + 0].position.x = glyphInfo.offset.x;
        mesh.vertices[4 * index + 0].position.y = glyphInfo.offset.y;
        mesh.vertices[4 * index + 0].position.z = depth;
        mesh.vertices[4 * index + 1].position.x = glyphInfo.offset.x;
        mesh.vertices[4 * index + 1].position.y = glyphInfo.offset.y + glyphInfo.extent.height;
        mesh.vertices[4 * index + 1].position.z = depth;
        mesh.vertices[4 * index + 2].position.x = glyphInfo.offset.x + glyphInfo.extent.width;
        mesh.vertices[4 * index + 2].position.y = glyphInfo.offset.y + glyphInfo.extent.height;
        mesh.vertices[4 * index + 2].position.z = depth;
        mesh.vertices[4 * index + 3].position.x = glyphInfo.offset.x + glyphInfo.extent.width;
        mesh.vertices[4 * index + 3].position.y = glyphInfo.offset.y;
        mesh.vertices[4 * index + 3].position.z = depth;
        mesh.vertices[4 * index + 0].uv.x = glyphInfo.minUv.x;
        mesh.vertices[4 * index + 0].uv.y = glyphInfo.minUv.y;
        mesh.vertices[4 * index + 1].uv.x = glyphInfo.minUv.x;
        mesh.vertices[4 * index + 1].uv.y = glyphInfo.maxUv.y;
        mesh.vertices[4 * index + 2].uv.x = glyphInfo.maxUv.x;
        mesh.vertices[4 * index + 2].uv.y = glyphInfo.maxUv.y;
        mesh.vertices[4 * index + 3].uv.x = glyphInfo.maxUv.x;
        mesh.vertices[4 * index + 3].uv.y = glyphInfo.minUv.y;

        mesh.indices[6 * index + 0] = cast(u16) (4 * index + 0);
        mesh.indices[6 * index + 1] = cast(u16) (4 * index + 1);
        mesh.indices[6 * index + 2] = cast(u16) (4 * index + 2);
        mesh.indices[6 * index + 3] = cast(u16) (4 * index + 2);
        mesh.indices[6 * index + 4] = cast(u16) (4 * index + 3);
        mesh.indices[6 * index + 5] = cast(u16) (4 * index + 0);

        index += 1;
    }

    if computeCharInfos {
        for *charInfo : infos {
            charInfo.effective.glyphOffset.std = charInfo.glyphOffset;
            charInfo.effective.xStart = charInfo.effective.glyphOffset.x;
            charInfo.effective.xEnd = charInfo.effective.glyphOffset.x + charInfo.glyphExtent.width;
            charInfo.effective.xEndWithAdvance = charInfo.effective.glyphOffset.x + charInfo.glyphAdvance;
            charInfo.effective.yStart = 0;
            charInfo.effective.yEnd = fontInfo.font.size;
        }
    }

    textWidth := Basic.peek(glyphInfos).offset.x + Basic.peek(glyphInfos).extent.x;

    if anchor != .TopLeft {
        offset : Chamber.vec2;
        if anchor == {
            case .Center;       offset = .{-textWidth / 2, -fontInfo.font.size / 2.0};
            case .Left;         offset.y = -fontInfo.font.size / 2.0;
            case .Right;        offset = .{-textWidth, -fontInfo.font.size / 2.0};
            case .Top;          offset.x = -textWidth / 2;
            case .Bottom;       offset = .{-textWidth / 2, -fontInfo.font.size};
            case .TopRight;     offset.x = -textWidth;
            case .BottomLeft;   offset.y = -fontInfo.font.size;
            case .BottomRight;  offset = .{-textWidth, -fontInfo.font.size};
        }

        offset.x = Math.floor(offset.x + 0.5);
        offset.y = Math.floor(offset.y + 0.5);

        index := 0;
        for *glyphInfo : glyphInfos {
            if glyphInfo.blank then continue;

            mesh.vertices[4 * index + 0].position.xy.std += offset;
            mesh.vertices[4 * index + 1].position.xy.std += offset;
            mesh.vertices[4 * index + 2].position.xy.std += offset;
            mesh.vertices[4 * index + 3].position.xy.std += offset;
            index += 1;
        }
    }

    Magma.mesh_commit_vertices(mesh);
    Magma.mesh_commit_indices(mesh);

    return textWidth, charInfos;
}

// Will modify the effective positions of the charInfos to justify the text
// according to the provided maxWidth.
justify_char_infos :: (charInfos : *CharInfos, maxWidth : float, startingOffsetX : float) -> (height : float, updated : bool) {
    if !charInfos.dirty && charInfos.justifyMaxWidth == maxWidth && charInfos.justifyStartingOffsetX == startingOffsetX {
        return charInfos.justifyComputedHeight, false;
    }

    // This allows us to break on a URL.
    isSplitCharacter :: inline (charInfo : *CharInfo) -> bool {
        return charInfo.glyphBlank || charInfo.glyphCodepoint == #char "/";
    }

    charInfos.dirty = false;
    charInfos.justifyMaxWidth = maxWidth;
    charInfos.justifyStartingOffsetX = startingOffsetX;

    infos : []CharInfo = charInfos.infos;
    if infos.count == 0 then return 0.0, true;

    offset : Chamber.vec2;
    offset.x = startingOffsetX;

    lastKnownSplitCharacterIndex := -1;
    for *charInfo, index : infos {
        if isSplitCharacter(charInfo) then lastKnownSplitCharacterIndex = index;

        // There is a line break, we move the whole line down without justify.
        if charInfo.glyphCodepoint == #char "\n" {
            offset.x = startingOffsetX - charInfo.glyphOffset.x;
            offset.y += UiConstants.HeightLine;
        }

        charInfo.effective.glyphOffset.std = charInfo.glyphOffset + offset;
        charInfo.effective.yStart = offset.y;
        charInfo.effective.yEnd = offset.y + UiConstants.HeightLine;
        currentWidth := charInfo.effective.glyphOffset.x + charInfo.glyphExtent.width;

        if currentWidth > maxWidth {
            // When it does not fit and we don't have a previous blank, accept it.
            //      |      |
            //      aaaaaaaaaaa
            if lastKnownSplitCharacterIndex == -1 then continue;

            // Moving the whole word down to the next line.
            for i : lastKnownSplitCharacterIndex + 1 .. index {
                infos[i].effective.glyphOffset.y += UiConstants.HeightLine;
                infos[i].effective.yStart += UiConstants.HeightLine;
                infos[i].effective.yEnd += UiConstants.HeightLine;
            }

            // Justify the whole previous line.
            j := lastKnownSplitCharacterIndex;
            blankCount := 0;
            while j >= 0 && infos[j].glyphBlank { j -= 1; } // Ignore ending blanks.
            while j >= 0 && infos[j].effective.yStart == infos[j + 1].effective.yStart && infos[j].glyphCodepoint != #char "\n" {
                if infos[j].glyphBlank then blankCount += 1;
                j -= 1;
            }

            // Justify only when the whole previous line has more than one word.
            //      |      |
            //      aaaaa bbbb
            if blankCount > 0 {
                j = lastKnownSplitCharacterIndex;
                extraSpacePerBlank := (maxWidth - (offset.x + infos[j].glyphOffset.x + infos[j].glyphExtent.width)) / blankCount;
                while j >= 0 && infos[j].glyphBlank {
                    infos[j].effective.glyphOffset.x += blankCount * extraSpacePerBlank;
                    j -= 1;
                }
                while j >= 0 && infos[j].effective.yStart == infos[j + 1].effective.yStart && infos[j].glyphCodepoint != #char "\n" {
                    infos[j].effective.glyphOffset.x += blankCount * extraSpacePerBlank;
                    if infos[j].glyphBlank then blankCount -= 1;
                    j -= 1;
                }
            }

            // Leave the ending blank character to the line above.
            i := lastKnownSplitCharacterIndex + 1;
            if i >= infos.count then break; // Last character is a blank, just stop here.

            offset.x = -infos[i].glyphOffset.x;
            offset.y += UiConstants.HeightLine;

            preOffset := -infos[i].effective.glyphOffset.x;
            while i <= index {
                infos[i].effective.glyphOffset.x += preOffset;
                i += 1;
            }

            lastKnownSplitCharacterIndex = -1;
        }
    }

    for *charInfo : infos {
        Chamber.round(*charInfo.effective.glyphOffset);
        charInfo.effective.xStart = charInfo.effective.glyphOffset.x;
        charInfo.effective.xEnd = charInfo.effective.glyphOffset.x + charInfo.glyphExtent.width;
        charInfo.effective.xEndWithAdvance = charInfo.effective.glyphOffset.x + charInfo.glyphAdvance;
    }

    charInfos.justifyComputedHeight = offset.y + UiConstants.HeightLine;
    return charInfos.justifyComputedHeight, true;
}
