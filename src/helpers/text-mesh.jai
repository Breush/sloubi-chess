CharInfo :: struct { // @fixme Also store how many bytes it is worth.
    // Original glyph info, where the vertices should be
    // without special placement.
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

create_text_mesh :: () -> *Magma.Mesh {
    mesh := Magma.create_mesh(instance.engine.scene);
    mesh.material = Magma.create_material(instance.shaders.text);
    return mesh;
}

text_mesh_update :: (mesh : *Magma.Mesh, text : string, font : *Chamber.Font, color : Chamber.vec3, depth := 0.0) -> []CharInfo #must {
    mesh.disabled = (text.count == 0);
    if mesh.disabled then return .[];

    // @todo Have a clever way to keep the texture up-to-date.
    // And not recreate it each time...
    glyphInfos := Chamber.font_glyph_infos(font, text); // @todo Get them without the blanks characters.
    defer Basic.array_free(glyphInfos);
    fontTexture := Magma.create_texture(instance.engine.renderEngine);
    Magma.texture_load_from_memory(fontTexture, font.pixels, font.extent);

    Magma.material_set(mesh.material, "fontTexture", fontTexture);
    Magma.material_set(mesh.material, "color", color);

    charInfos : [..]CharInfo;
    Basic.array_resize(*charInfos, glyphInfos.count);

    totalBlanks := 0;

    for *glyphInfo, index : glyphInfos {
        if glyphInfo.blank then totalBlanks += 1;
        charInfos[index].glyphBlank = glyphInfo.blank;
        charInfos[index].glyphOffset = glyphInfo.offset;
        charInfos[index].glyphExtent = glyphInfo.extent;
        charInfos[index].glyphAdvance = glyphInfo.advance;
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

    for *charInfo : charInfos {
        charInfo.effective.glyphOffset.std = charInfo.glyphOffset;
        charInfo.effective.xStart = charInfo.effective.glyphOffset.x;
        charInfo.effective.xEnd = charInfo.effective.glyphOffset.x + charInfo.glyphExtent.width;
        charInfo.effective.xEndWithAdvance = charInfo.effective.glyphOffset.x + charInfo.glyphAdvance;
        charInfo.effective.yStart = 0;
        charInfo.effective.yEnd = font.size;
    }

    Magma.mesh_commit_vertices(mesh);
    Magma.mesh_commit_indices(mesh);
    Magma.mesh_commit_instance(mesh);

    return charInfos;
}


// Will modify the effective positions of the charInfos to justify the text
// according to the provided maxWidth.
justify_char_infos :: (charInfos : []CharInfo, maxWidth : float, startingOffsetX : float) -> float {
    if charInfos.count == 0 then return 0.0;

    offset : Chamber.vec2;
    offset.x = startingOffsetX;

    lastKnownBlankIndex := -1;
    for *charInfo, index : charInfos {
        if charInfo.glyphBlank then lastKnownBlankIndex = index;
        charInfo.effective.glyphOffset.std = charInfo.glyphOffset + offset;
        charInfo.effective.yStart = offset.y;
        charInfo.effective.yEnd = offset.y + UiConstants.HeightLine;
        currentWidth := charInfo.effective.glyphOffset.x + charInfo.glyphExtent.width;

        if currentWidth > maxWidth {
            // When it does not fit and we don't have a previous blank, accept it.
            //      |      |
            //      aaaaaaaaaaa
            if lastKnownBlankIndex == -1 then continue;

            // Moving the whole word down to the next line.
            for i : lastKnownBlankIndex + 1 .. index {
                charInfos[i].effective.glyphOffset.y += UiConstants.HeightLine;
                charInfos[i].effective.yStart += UiConstants.HeightLine;
                charInfos[i].effective.yEnd += UiConstants.HeightLine;
            }

            // Justify the whole previous line.
            j := lastKnownBlankIndex;
            blankCount := 0;
            while j >= 0 && charInfos[j].glyphBlank { j -= 1; } // Ignore ending blanks.
            while j >= 0 && charInfos[j].effective.yStart == charInfos[j + 1].effective.yStart {
                if charInfos[j].glyphBlank then blankCount += 1;
                j -= 1;
            }

            // Justify only when the whole previous line has more than one word.
            //      |      |
            //      aaaaa bbbb
            if blankCount > 0 {
                j = lastKnownBlankIndex;
                extraSpacePerBlank := (maxWidth - (offset.x + charInfos[j].glyphOffset.x + charInfos[j].glyphExtent.width)) / blankCount;
                while j >= 0 && charInfos[j].glyphBlank {
                    charInfos[j].effective.glyphOffset.x += Math.floor(blankCount * extraSpacePerBlank + 0.5);
                    j -= 1;
                }
                while j >= 0 && charInfos[j].effective.yStart == charInfos[j + 1].effective.yStart {
                    charInfos[j].effective.glyphOffset.x += Math.floor(blankCount * extraSpacePerBlank + 0.5);
                    if charInfos[j].glyphBlank then blankCount -= 1;
                    j -= 1;
                }
            }

            // Leave the ending blank character to the line above.
            i := lastKnownBlankIndex + 1;
            if i >= charInfos.count then break; // Last character is a blank, just stop here.

            offset.x = -charInfos[i].glyphOffset.x;
            offset.y += UiConstants.HeightLine;

            preOffset := -charInfos[i].effective.glyphOffset.x;
            while i <= index {
                charInfos[i].effective.glyphOffset.x += preOffset;
                i += 1;
            }

            lastKnownBlankIndex = -1;
        }
    }

    for *charInfo : charInfos {
        charInfo.effective.xStart = charInfo.effective.glyphOffset.x;
        charInfo.effective.xEnd = charInfo.effective.glyphOffset.x + charInfo.glyphExtent.width;
        charInfo.effective.xEndWithAdvance = charInfo.effective.glyphOffset.x + charInfo.glyphAdvance;
    }

    return offset.y + UiConstants.HeightLine;
}
